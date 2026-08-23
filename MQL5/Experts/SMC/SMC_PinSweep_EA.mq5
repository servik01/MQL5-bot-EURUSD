//+------------------------------------------------------------------+
//|                                            SMC_PinSweep_EA.mq5    |
//|  Тренд D1+H1 по структуре, вход лимиткой от пинбара со снятием    |
//|  ликвидности в зоне дискаунта. R:R фиксированный.                 |
//+------------------------------------------------------------------+
#property copyright "SMC PinSweep"
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>
#include <SMC\SwingStructure.mqh>
#include <SMC\PinBar.mqh>
#include <SMC\NewsFilter.mqh>
#include <SMC\TradeLogger.mqh>

input group "=== Структура (тренд) ==="
input int      InpSwingBarsD1      = 2;        // D1: окно фрактала
input int      InpSwingBarsH1      = 2;        // H1: окно фрактала
input bool     InpBreakByClose     = true;     // Пробой структуры по close
input int      InpHistoryBarsH1    = 120;      // Глубина истории свингов H1, баров (неделя)
input int      InpHistoryBarsD1    = 40;       // Глубина истории свингов D1, баров

input group "=== Пинбар ==="
input double   InpMinTailRatio     = 0.40;     // Мин. доля хвоста от диапазона
input double   InpMinRangeATR      = 0.50;     // Мин. диапазон свечи в долях ATR(14) H1
input int      InpATRPeriod        = 14;       // Период ATR

input group "=== Премиум / дискаунт ==="
input bool     InpUsePremiumFilter = true;     // Требовать откат от экстремума
input double   InpMinRetracement   = 0.40;     // Мин. откат от хая/лоу диапазона

input group "=== Вход ==="
input double   InpEntryRetrace     = 0.40;     // Откат в хвост от края тела
input int      InpPendingLifeBars  = 1;        // Жизнь лимитки, баров H1

input group "=== Риск ==="
input double   InpRiskRewardRatio  = 2.0;      // R:R
input double   InpRiskPercent      = 0.5;      // Риск на сделку, %
input double   InpFixedLot         = 0.01;     // Фикс. лот (если риск % = 0)
input int      InpSLBufferPoints   = 20;       // Буфер стопа, пунктов
input int      InpMaxSpreadPoints  = 30;       // Макс. спред, пунктов
input int      InpMaxPositions     = 1;        // Макс. позиций + лимиток

input group "=== Новости ==="
input bool     InpUseNewsFilter    = true;     // Фильтр новостей
input int      InpNewsMinsBefore   = 30;       // Пауза до новости, минут
input int      InpNewsMinsAfter    = 30;       // Пауза после новости, минут

input group "=== Выходные ==="
input bool     InpCloseBeforeWeekend = true;   // Закрывать всё перед выходными
input int      InpFridayNoNewHour   = 18;      // Пятница: не открывать после, час сервера
input int      InpFridayCloseHour   = 20;      // Пятница: закрыть всё в, час сервера

input group "=== Служебное ==="
input long     InpMagic            = 20260823; // Magic number
input bool     InpWriteCsvLog      = true;     // Писать CSV-лог
input bool     InpDrawSignals      = true;     // Рисовать сигналы
input bool     InpVerboseLog       = true;     // Подробный лог в терминал

CTrade           g_trade;
CSwingStructure  g_structD1;
CSwingStructure  g_structH1;
CNewsFilter      g_news;
CTradeLogger     g_log;

datetime         g_lastBarH1 = 0;
int              g_atrHandle = INVALID_HANDLE;
int              g_lotDigits = 2;

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpEntryRetrace < 0.0 || InpEntryRetrace >= 1.0)
     {
      Print("InpEntryRetrace должен быть в [0.0 .. 1.0)");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpMinRetracement < 0.0 || InpMinRetracement >= 1.0)
     {
      Print("InpMinRetracement должен быть в [0.0 .. 1.0)");
      return(INIT_PARAMETERS_INCORRECT);
     }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(20);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   if(!g_structD1.Init(_Symbol, PERIOD_D1, InpSwingBarsD1, InpBreakByClose, InpHistoryBarsD1))
      return(INIT_FAILED);
   if(!g_structH1.Init(_Symbol, PERIOD_H1, InpSwingBarsH1, InpBreakByClose, InpHistoryBarsH1))
      return(INIT_FAILED);

   g_atrHandle = iATR(_Symbol, PERIOD_H1, InpATRPeriod);
   if(g_atrHandle == INVALID_HANDLE)
     {
      Print("Не удалось создать хэндл ATR");
      return(INIT_FAILED);
     }

   if(InpUseNewsFilter)
      g_news.Init(_Symbol, InpNewsMinsBefore, InpNewsMinsAfter);

   g_log.Init(_Symbol, InpMagic, InpWriteCsvLog);

   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      step = 0.01;
   g_lotDigits = 0;
   double s = step;
   while(s < 1.0 - 1e-9 && g_lotDigits < 8)
     {
      s *= 10.0;
      g_lotDigits++;
     }

   g_log.Write("EA_INIT", StringFormat("symbol=%s risk=%.2f%% rr=1:%.1f", _Symbol,
                                       InpRiskPercent, InpRiskRewardRatio));
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
   if(InpDrawSignals)
      ObjectsDeleteAll(0, "SMC_");
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   //--- закрытие перед выходными проверяем на каждом тике, не только на баре
   if(InpCloseBeforeWeekend && IsFridayCloseTime())
     {
      CloseEverything("выходные");
      return;
     }

   datetime cur = iTime(_Symbol, PERIOD_H1, 0);
   if(cur == 0 || cur == g_lastBarH1)
      return;
   g_lastBarH1 = cur;

   ExpirePendingOrders();

   g_structD1.Update();
   g_structH1.Update();

   if(InpVerboseLog)
      PrintFormat("[%s] D1=%s H1=%s", TimeToString(cur),
                  g_structD1.TrendToString(), g_structH1.TrendToString());

   if(CountOwnPositions() + CountOwnPendings() >= InpMaxPositions)
      return;

   if(InpCloseBeforeWeekend && IsFridayNoNewTime())
      return;

   ENUM_SMC_TREND td = g_structD1.Trend();
   ENUM_SMC_TREND th = g_structH1.Trend();
   if(td == SMC_TREND_NONE || td != th)
      return;

   string dirName = (td == SMC_TREND_BULL) ? "BUY" : "SELL";

   if(SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) > InpMaxSpreadPoints)
      return;

   //--- фильтр размера свечи по ATR
   double minRange = 0.0;
   if(InpMinRangeATR > 0.0)
     {
      double atr[];
      if(CopyBuffer(g_atrHandle, 0, 1, 1, atr) != 1)
         return;
      minRange = atr[0] * InpMinRangeATR;
     }

   SPinBar pb = DetectPinBar(_Symbol, PERIOD_H1, 1, InpMinTailRatio, minRange);
   if(!pb.valid)
      return;

   if((td == SMC_TREND_BULL && pb.direction != 1) ||
      (td == SMC_TREND_BEAR && pb.direction != -1))
      return;

   //--- новости
   if(InpUseNewsFilter)
     {
      string reason;
      if(g_news.IsBlocked(TimeCurrent(), reason))
        {
         g_log.Rejected(dirName, "news: " + reason);
         if(InpVerboseLog)
            Print("Пропуск по новостям: ", reason);
         return;
        }
     }

   //--- снятие ликвидности неснятого ранее уровня
   double level = 0.0;
   int    levelIdx = -1;

   if(td == SMC_TREND_BULL)
     {
      if(!g_structH1.LastUnsweptLow(level, levelIdx))
        {
         g_log.Rejected(dirName, "нет неснятого свинг-лоу");
         return;
        }
      if(!IsSweepDown(pb, level))
         return;
     }
   else
     {
      if(!g_structH1.LastUnsweptHigh(level, levelIdx))
        {
         g_log.Rejected(dirName, "нет неснятого свинг-хая");
         return;
        }
      if(!IsSweepUp(pb, level))
         return;
     }

   //--- премиум / дискаунт
   double retracePct = 0.0;
   if(InpUsePremiumFilter)
     {
      double rLow, rHigh;
      if(!g_structH1.RangeBounds(rLow, rHigh))
        {
         g_log.Rejected(dirName, "диапазон не определён");
         return;
        }

      double span = rHigh - rLow;
      if(span <= 0.0)
         return;

      if(td == SMC_TREND_BULL)
         retracePct = (rHigh - pb.close) / span;      // насколько откатили от хая
      else
         retracePct = (pb.close - rLow) / span;       // насколько откатили от лоу

      if(retracePct < InpMinRetracement)
        {
         g_log.Rejected(dirName, StringFormat("откат %.1f%% < %.1f%%",
                                              retracePct * 100.0, InpMinRetracement * 100.0));
         if(InpVerboseLog)
            PrintFormat("Пропуск: откат только %.1f%%", retracePct * 100.0);
         return;
        }
     }

   if(PlaceLimitOrder(td, pb, retracePct))
     {
      //--- уровень израсходован, повторно не используется
      if(td == SMC_TREND_BULL)
         g_structH1.MarkLowSwept(levelIdx);
      else
         g_structH1.MarkHighSwept(levelIdx);
     }
  }

//+------------------------------------------------------------------+
bool PlaceLimitOrder(const ENUM_SMC_TREND trend, const SPinBar &pb, const double retracePct)
  {
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double buffer = InpSLBufferPoints * point;

   double bodyTop    = MathMax(pb.open, pb.close);
   double bodyBottom = MathMin(pb.open, pb.close);

   double entry, sl, tp;

   if(trend == SMC_TREND_BULL)
     {
      double lowerTail = bodyBottom - pb.low;
      if(lowerTail <= 0.0)
         return(false);
      entry = bodyBottom - InpEntryRetrace * lowerTail;
      sl    = pb.low - buffer;
      if(entry - sl <= 0.0)
         return(false);
      tp = entry + (entry - sl) * InpRiskRewardRatio;
     }
   else
     {
      double upperTail = pb.high - bodyTop;
      if(upperTail <= 0.0)
         return(false);
      entry = bodyTop + InpEntryRetrace * upperTail;
      sl    = pb.high + buffer;
      if(sl - entry <= 0.0)
         return(false);
      tp = entry - (sl - entry) * InpRiskRewardRatio;
     }

   entry = NormalizeDouble(entry, _Digits);
   sl    = NormalizeDouble(sl,    _Digits);
   tp    = NormalizeDouble(tp,    _Digits);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0)
      return(false);

   double minDist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;
   string dirName = (trend == SMC_TREND_BULL) ? "BUY" : "SELL";

   if(trend == SMC_TREND_BULL && ask <= entry + minDist)
     {
      g_log.Rejected(dirName, "цена ниже уровня лимитки");
      return(false);
     }
   if(trend == SMC_TREND_BEAR && bid >= entry - minDist)
     {
      g_log.Rejected(dirName, "цена выше уровня лимитки");
      return(false);
     }

   if(MathAbs(entry - sl) < minDist || MathAbs(tp - entry) < minDist)
     {
      g_log.Rejected(dirName, "стоп/тейк ближе STOPS_LEVEL");
      return(false);
     }

   double lot = CalcLot(MathAbs(entry - sl));
   if(lot <= 0.0)
     {
      g_log.Rejected(dirName, "лот = 0");
      return(false);
     }

   bool ok = (trend == SMC_TREND_BULL)
             ? g_trade.BuyLimit(lot, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "SMC pin limit")
             : g_trade.SellLimit(lot, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "SMC pin limit");

   if(!ok)
     {
      g_log.Rejected(dirName, StringFormat("retcode=%d", g_trade.ResultRetcode()));
      PrintFormat("Ошибка выставления: %d %s", g_trade.ResultRetcode(),
                  g_trade.ResultRetcodeDescription());
      return(false);
     }

   g_log.Signal(dirName, entry, sl, tp, lot, pb.tailRatio, retracePct * 100.0);
   PrintFormat("ЛИМИТКА %s entry=%.*f sl=%.*f tp=%.*f lot=%.*f tail=%.2f откат=%.1f%%",
               dirName, _Digits, entry, _Digits, sl, _Digits, tp,
               g_lotDigits, lot, pb.tailRatio, retracePct * 100.0);

   if(InpDrawSignals)
      DrawSignal(trend, pb, entry);

   return(true);
  }

//+------------------------------------------------------------------+
//| Снятие протухших лимиток. Возраст в барах, с учётом freeze level. |
//+------------------------------------------------------------------+
void ExpirePendingOrders(void)
  {
   int    life   = MathMax(1, InpPendingLifeBars);
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double freeze = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL) * point;
   double ask    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid    = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if(OrderGetInteger(ORDER_MAGIC) != InpMagic)
         continue;

      datetime setup    = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
      int      setupBar = iBarShift(_Symbol, PERIOD_H1, setup);
      if(setupBar < 0 || setupBar < life)
         continue;

      //--- freeze level: вблизи рынка брокер не даст тронуть ордер
      if(freeze > 0.0)
        {
         double price = OrderGetDouble(ORDER_PRICE_OPEN);
         long   type  = OrderGetInteger(ORDER_TYPE);
         double dist  = (type == ORDER_TYPE_BUY_LIMIT) ? (ask - price) : (price - bid);
         if(dist < freeze)
           {
            if(InpVerboseLog)
               PrintFormat("Лимитка #%I64u в зоне freeze, снятие отложено", ticket);
            continue;
           }
        }

      if(g_trade.OrderDelete(ticket))
         g_log.Write("PENDING_EXPIRED", StringFormat("ticket=%I64u bars=%d", ticket, setupBar));
      else
         PrintFormat("Не удалось снять #%I64u: retcode=%d", ticket, g_trade.ResultRetcode());
     }
  }

//+------------------------------------------------------------------+
//| Пятница: время закрывать всё                                      |
//+------------------------------------------------------------------+
bool IsFridayCloseTime(void)
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return(dt.day_of_week == FRIDAY && dt.hour >= InpFridayCloseHour);
  }

//+------------------------------------------------------------------+
bool IsFridayNoNewTime(void)
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return(dt.day_of_week == FRIDAY && dt.hour >= InpFridayNoNewHour);
  }

//+------------------------------------------------------------------+
void CloseEverything(const string reason)
  {
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol || OrderGetInteger(ORDER_MAGIC) != InpMagic)
         continue;
      if(g_trade.OrderDelete(ticket))
         g_log.Write("PENDING_CANCELLED", reason);
     }

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
         PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      if(g_trade.PositionClose(ticket))
         g_log.Write("POSITION_CLOSED", reason);
     }
  }

//+------------------------------------------------------------------+
//| Фиксация исполнений и отклонений                                  |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &request,
                        const MqlTradeResult      &result)
  {
   if(trans.symbol != _Symbol)
      return;

   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
     {
      if(!HistoryDealSelect(trans.deal))
         return;
      if(HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagic)
         return;

      long   entryType = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
      double price     = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
      double profit    = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
      long   dealReason = HistoryDealGetInteger(trans.deal, DEAL_REASON);

      if(entryType == DEAL_ENTRY_IN)
         g_log.Write("FILLED", StringFormat("deal=%I64u price=%.5f", trans.deal, price));
      else
         if(entryType == DEAL_ENTRY_OUT)
           {
            string how = "manual";
            if(dealReason == DEAL_REASON_SL)
               how = "SL";
            else
               if(dealReason == DEAL_REASON_TP)
                  how = "TP";
            g_log.Write("CLOSED", StringFormat("deal=%I64u price=%.5f pnl=%.2f by=%s",
                                               trans.deal, price, profit, how));
           }
     }

   if(trans.type == TRADE_TRANSACTION_REQUEST && result.retcode != TRADE_RETCODE_DONE &&
      result.retcode != TRADE_RETCODE_PLACED && result.retcode != 0)
      g_log.Write("REQUEST_FAILED", StringFormat("retcode=%d", result.retcode));
  }

//+------------------------------------------------------------------+
double CalcLot(const double slDistance)
  {
   if(InpRiskPercent <= 0.0)
      return(NormalizeLotValue(InpFixedLot));

   double riskMoney = AccountInfoDouble(ACCOUNT_BALANCE) * InpRiskPercent / 100.0;
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickSize <= 0.0 || tickValue <= 0.0 || slDistance <= 0.0)
      return(0.0);

   double lossPerLot = (slDistance / tickSize) * tickValue;
   if(lossPerLot <= 0.0)
      return(0.0);

   return(NormalizeLotValue(riskMoney / lossPerLot));
  }

//+------------------------------------------------------------------+
double NormalizeLotValue(const double rawLot)
  {
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(step <= 0.0)
      step = 0.01;

   double lot = MathFloor(rawLot / step) * step;
   if(lot < minLot)
      lot = 0.0;
   if(lot > maxLot)
      lot = maxLot;

   return(NormalizeDouble(lot, g_lotDigits));
  }

//+------------------------------------------------------------------+
int CountOwnPositions(void)
  {
   int c = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetTicket(i) == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         PositionGetInteger(POSITION_MAGIC) == InpMagic)
         c++;
     }
   return(c);
  }

//+------------------------------------------------------------------+
int CountOwnPendings(void)
  {
   int c = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(OrderGetTicket(i) == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) == _Symbol &&
         OrderGetInteger(ORDER_MAGIC) == InpMagic)
         c++;
     }
   return(c);
  }

//+------------------------------------------------------------------+
void DrawSignal(const ENUM_SMC_TREND trend, const SPinBar &pb, const double entry)
  {
   string arrowName = StringFormat("SMC_sig_%d", (int)pb.time);
   double anchor    = (trend == SMC_TREND_BULL) ? pb.low : pb.high;

   if(ObjectCreate(0, arrowName, OBJ_ARROW, 0, pb.time, anchor))
     {
      ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, (trend == SMC_TREND_BULL) ? 233 : 234);
      ObjectSetInteger(0, arrowName, OBJPROP_COLOR,
                       (trend == SMC_TREND_BULL) ? clrDeepSkyBlue : clrOrangeRed);
      ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, arrowName, OBJPROP_ANCHOR,
                       (trend == SMC_TREND_BULL) ? ANCHOR_TOP : ANCHOR_BOTTOM);
     }

   string lineName = StringFormat("SMC_entry_%d", (int)pb.time);
   datetime tEnd   = pb.time + PeriodSeconds(PERIOD_H1) * (MathMax(1, InpPendingLifeBars) + 1);
   if(ObjectCreate(0, lineName, OBJ_TREND, 0, pb.time, entry, tEnd, entry))
     {
      ObjectSetInteger(0, lineName, OBJPROP_COLOR, clrGoldenrod);
      ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, lineName, OBJPROP_RAY_RIGHT, false);
     }
  }
//+------------------------------------------------------------------+
