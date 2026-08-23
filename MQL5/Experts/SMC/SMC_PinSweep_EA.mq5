//+------------------------------------------------------------------+
//|                                            SMC_PinSweep_EA.mq5    |
//|  Тренд по структуре D1 + H1 (строгое совпадение)                  |
//|  Вход: лимитка на откате в хвост H1 пинбара, снявшего ликвидность |
//|  Стоп за хвост пинбара, тейк по фиксированному R:R                |
//+------------------------------------------------------------------+
#property copyright "SMC PinSweep"
#property version   "1.10"
#property strict

#include <Trade\Trade.mqh>
#include <SMC\SwingStructure.mqh>
#include <SMC\PinBar.mqh>

//--- Структура
input group "=== Структура (тренд) ==="
input int      InpSwingBarsD1     = 2;        // D1: окно фрактала (баров с каждой стороны)
input int      InpSwingBarsH1     = 2;        // H1: окно фрактала
input bool     InpBreakByClose    = true;     // Пробой структуры считать по close (не по хвосту)

//--- Пинбар
input group "=== Пинбар ==="
input double   InpMinTailRatio    = 0.40;     // Мин. доля хвоста от диапазона свечи
input bool     InpRequireSweep    = true;     // Требовать снятие ликвидности

//--- Вход
input group "=== Вход (лимитный откат) ==="
input double   InpEntryRetrace    = 0.40;     // Откат в хвост от низа/верха тела, доля хвоста
input int      InpPendingLifeBars = 1;        // Жизнь неисполненной лимитки, баров H1

//--- Риск и сделка
input group "=== Риск ==="
input double   InpRiskRewardRatio = 2.0;      // R:R (тейк = R:R * стоп)
input double   InpRiskPercent     = 0.5;      // Риск на сделку, % от баланса (0 = фикс. лот)
input double   InpFixedLot        = 0.01;     // Фиксированный лот (если риск % = 0)
input int      InpSLBufferPoints  = 20;       // Буфер стопа за хвост, пунктов
input int      InpMaxSpreadPoints = 30;       // Макс. спред для входа, пунктов
input int      InpMaxPositions    = 1;        // Макс. позиций + лимиток по символу

//--- Служебное
input group "=== Служебное ==="
input long     InpMagic           = 20260823; // Magic number
input bool     InpDrawSignals     = true;     // Рисовать сигналы на графике
input bool     InpVerboseLog      = true;     // Подробный лог

//--- Глобальные объекты
CTrade           g_trade;
CSwingStructure  g_structD1;
CSwingStructure  g_structH1;
datetime         g_lastBarH1 = 0;
int              g_lotDigits = 2;

//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpEntryRetrace < 0.0 || InpEntryRetrace >= 1.0)
     {
      Print("InpEntryRetrace должен быть в диапазоне [0.0 .. 1.0)");
      return(INIT_PARAMETERS_INCORRECT);
     }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(20);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   if(!g_structD1.Init(_Symbol, PERIOD_D1, InpSwingBarsD1, InpBreakByClose))
      return(INIT_FAILED);
   if(!g_structH1.Init(_Symbol, PERIOD_H1, InpSwingBarsH1, InpBreakByClose))
      return(INIT_FAILED);

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

   PrintFormat("SMC_PinSweep %s: риск %.2f%%, R:R 1:%.1f, откат %.2f, лимитка %d бар(ов)",
               _Symbol, InpRiskPercent, InpRiskRewardRatio, InpEntryRetrace, InpPendingLifeBars);
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(InpDrawSignals)
      ObjectsDeleteAll(0, "SMC_");
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   datetime cur = iTime(_Symbol, PERIOD_H1, 0);
   if(cur == 0 || cur == g_lastBarH1)
      return;
   g_lastBarH1 = cur;

   //--- снимаем протухшие лимитки до анализа нового сигнала
   ExpirePendingOrders();

   g_structD1.Update();
   g_structH1.Update();

   if(InpVerboseLog)
      PrintFormat("[%s] Тренд D1=%s H1=%s | H1 swingLow=%.*f swingHigh=%.*f",
                  TimeToString(cur), g_structD1.TrendToString(), g_structH1.TrendToString(),
                  _Digits, g_structH1.SwingLow(), _Digits, g_structH1.SwingHigh());

   if(CountOwnPositions() + CountOwnPendings() >= InpMaxPositions)
      return;

   ENUM_SMC_TREND td = g_structD1.Trend();
   ENUM_SMC_TREND th = g_structH1.Trend();
   if(td == SMC_TREND_NONE || td != th)
      return;

   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpreadPoints)
      return;

   SPinBar pb = DetectPinBar(_Symbol, PERIOD_H1, 1, InpMinTailRatio);
   if(!pb.valid)
      return;

   if((td == SMC_TREND_BULL && pb.direction != 1) ||
      (td == SMC_TREND_BEAR && pb.direction != -1))
      return;

   if(InpRequireSweep)
     {
      if(td == SMC_TREND_BULL)
        {
         if(!IsSweepDown(pb, g_structH1.SwingLow()))
            return;
        }
      else
        {
         if(!IsSweepUp(pb, g_structH1.SwingHigh()))
            return;
        }
     }

   PlaceLimitOrder(td, pb);
  }

//+------------------------------------------------------------------+
//| Выставление лимитного ордера на откате в хвост пинбара            |
//+------------------------------------------------------------------+
void PlaceLimitOrder(const ENUM_SMC_TREND trend, const SPinBar &pb)
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
         return;
      //--- откат отмеряется от низа тела вниз, вглубь хвоста
      entry = bodyBottom - InpEntryRetrace * lowerTail;
      sl    = pb.low - buffer;
      if(entry - sl <= 0.0)
         return;
      tp = entry + (entry - sl) * InpRiskRewardRatio;
     }
   else
     {
      double upperTail = pb.high - bodyTop;
      if(upperTail <= 0.0)
         return;
      entry = bodyTop + InpEntryRetrace * upperTail;
      sl    = pb.high + buffer;
      if(sl - entry <= 0.0)
         return;
      tp = entry - (sl - entry) * InpRiskRewardRatio;
     }

   entry = NormalizeDouble(entry, _Digits);
   sl    = NormalizeDouble(sl,    _Digits);
   tp    = NormalizeDouble(tp,    _Digits);

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0)
      return;

   long   stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist    = stopsLevel * point;

   //--- лимитка должна лежать по нужную сторону от рынка
   if(trend == SMC_TREND_BULL && ask <= entry + minDist)
     {
      if(InpVerboseLog)
         Print("Пропуск: цена уже ниже уровня buy limit");
      return;
     }
   if(trend == SMC_TREND_BEAR && bid >= entry - minDist)
     {
      if(InpVerboseLog)
         Print("Пропуск: цена уже выше уровня sell limit");
      return;
     }

   if(MathAbs(entry - sl) < minDist || MathAbs(tp - entry) < minDist)
     {
      PrintFormat("Пропуск: стоп/тейк ближе минимальной дистанции (%d пунктов)", (int)stopsLevel);
      return;
     }

   double lot = CalcLot(MathAbs(entry - sl));
   if(lot <= 0.0)
     {
      Print("Пропуск: расчётный лот равен нулю");
      return;
     }

   //--- ордер ставится GTC, снятие по возрасту делает ExpirePendingOrders()
   bool ok = false;
   if(trend == SMC_TREND_BULL)
      ok = g_trade.BuyLimit(lot, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "SMC pin limit buy");
   else
      ok = g_trade.SellLimit(lot, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "SMC pin limit sell");

   if(!ok)
     {
      PrintFormat("Ошибка выставления лимитки: retcode=%d %s",
                  g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
      return;
     }

   PrintFormat("ЛИМИТКА %s lot=%.*f entry=%.*f sl=%.*f tp=%.*f risk=%.*f tail=%.2f жизнь=%d бар(ов)",
               (trend == SMC_TREND_BULL ? "BUY LIMIT" : "SELL LIMIT"),
               g_lotDigits, lot, _Digits, entry, _Digits, sl, _Digits, tp,
               _Digits, MathAbs(entry - sl), pb.tailRatio, MathMax(1, InpPendingLifeBars));

   if(InpDrawSignals)
      DrawSignal(trend, pb, entry);
  }

//+------------------------------------------------------------------+
//| Удаление лимиток, проживших дольше InpPendingLifeBars баров       |
//+------------------------------------------------------------------+
void ExpirePendingOrders(void)
  {
   int life = MathMax(1, InpPendingLifeBars);

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if(OrderGetInteger(ORDER_MAGIC) != InpMagic)
         continue;

      //--- возраст считаем в барах: iBarShift даёт индекс бара, на котором
      //--- ордер был выставлен. Разница времён в секундах здесь неверна,
      //--- т.к. ордер ставится на первом тике бара, а не ровно в его открытие.
      datetime setup     = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
      int      setupBar  = iBarShift(_Symbol, PERIOD_H1, setup);
      if(setupBar < 0)
         continue;
      int      barsAlive = setupBar;

      if(barsAlive >= life)
        {
         if(g_trade.OrderDelete(ticket))
            PrintFormat("Лимитка #%I64u снята: не исполнилась за %d бар(ов)", ticket, life);
         else
            PrintFormat("Не удалось снять лимитку #%I64u: retcode=%d",
                        ticket, g_trade.ResultRetcode());
        }
     }
  }

//+------------------------------------------------------------------+
double CalcLot(const double slDistance)
  {
   if(InpRiskPercent <= 0.0)
      return(NormalizeLotValue(InpFixedLot));

   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * InpRiskPercent / 100.0;

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
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      count++;
     }
   return(count);
  }

//+------------------------------------------------------------------+
int CountOwnPendings(void)
  {
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol)
         continue;
      if(OrderGetInteger(ORDER_MAGIC) != InpMagic)
         continue;
      count++;
     }
   return(count);
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

   //--- уровень лимитного входа
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
