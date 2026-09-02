//+------------------------------------------------------------------+
//|                                            SMC_PinSweep_EA.mq5    |
//|  Тренд по структуре на старшем ТФ + ТФ входа, вход лимиткой от    |
//|  ликвидности в зоне дискаунта. R:R фиксированный.                 |
//+------------------------------------------------------------------+
#property copyright "SMC PinSweep"
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>
#include <SMC\SwingStructure.mqh>
#include <SMC\PinBar.mqh>
#include <SMC\Engulfing.mqh>
#include <SMC\NewsFilter.mqh>
#include <SMC\TradeLogger.mqh>

input group "=== Структура (тренд) ==="
input ENUM_TIMEFRAMES InpTrendTF   = PERIOD_H4; // Старший ТФ тренда (был D1)
input ENUM_TIMEFRAMES InpEntryTF   = PERIOD_H1; // ТФ входа/сигнала
input int      InpSwingBarsD1      = 2;        // Старший ТФ: окно фрактала
input int      InpSwingBarsH1      = 2;        // ТФ входа: окно фрактала
input bool     InpBreakByClose     = true;     // Пробой структуры по close
input int      InpHistoryBarsH1    = 120;      // Глубина истории свингов на ТФ входа, баров
input int      InpHistoryBarsD1    = 40;       // Глубина истории свингов на старшем ТФ, баров

input group "=== Пинбар ==="
input double   InpMinTailRatio     = 0.40;     // Мин. доля хвоста от диапазона
input double   InpMinRangeATR      = 0.50;     // Мин. диапазон свечи в долях ATR(14) на ТФ входа
input int      InpATRPeriod        = 14;       // Период ATR

input group "=== Поглощение ==="
input bool     InpUseEngulfing       = true;     // Альтернативный вход по поглощению
input double   InpMinEngulfBodyRatio = 1.0;      // Мин. отношение тела к предыдущему
input double   InpMaxEngulfBodyRatio = 2.0;      // Макс. отношение тела к предыдущему (0 = без потолка)
input double   InpEngulfEntryRetrace = 0.50;     // Откат в тело поглощающей свечи
input double   InpMaxEngulfRetracement = 0.70;   // Макс. откат premium/discount для поглощения (0 = без потолка)

input group "=== Премиум / дискаунт ==="
input bool     InpUsePremiumFilter    = true;  // Требовать откат от экстремума
input double   InpMinRetracement      = 0.40;  // Мин. откат от хая/лоу диапазона
input double   InpPinbarDeadZoneLow   = 0.65;  // Пинбар: начало мёртвой зоны отката (0 = без выреза)
input double   InpPinbarDeadZoneHigh  = 0.90;  // Пинбар: конец мёртвой зоны отката

input group "=== Вход ==="
input double   InpEntryRetrace     = 0.40;     // Откат в хвост от края тела
input int      InpPendingLifeBars  = 1;        // Жизнь лимитки, баров ТФ входа

input group "=== Риск ==="
input double   InpRiskRewardRatio  = 4.0;      // R:R
input double   InpRiskPercent      = 0.5;      // Риск на сделку, %
input double   InpFixedLot         = 0.01;     // Фикс. лот (если риск % = 0)
input int      InpSLBufferPoints   = 20;       // Буфер стопа, пунктов
input int      InpMaxSpreadPoints  = 30;       // Макс. спред, пунктов
input int      InpMaxPositions     = 1;        // Макс. позиций + лимиток

input group "=== Управление сделкой ==="
input bool     InpUseBreakeven          = true;  // Перенос в безубыток
input double   InpBreakevenTriggerR     = 2.0;   // При каком R (от изначального риска) переносить
input int      InpBreakevenBufferPoints = 0;     // Буфер сверх входа при переносе, пунктов
input bool     InpUseTrailingStop       = false; // Трейлинг-стоп
input double   InpTrailingStartR        = 1.5;   // При каком R начинать трейлинг
input int      InpTrailingDistancePoints = 200;  // Дистанция трейлинга от цены, пунктов

input group "=== Новости ==="
input bool     InpUseNewsFilter    = true;     // Фильтр новостей
input int      InpNewsHourServer   = 14;       // Час новости, время сервера (сейчас UTC+2)
input int      InpNewsMinuteServer = 30;       // Минута новости, время сервера
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

//--- состояние открытых позиций для б/у и трейлинга: изначальный риск
//--- фиксируется на момент филла и не пересчитывается, даже если стоп
//--- потом подвинулся - иначе R-мультипл потерял бы смысл.
ulong            g_posTicket[];
double           g_posInitialRisk[];
bool             g_posBreakevenDone[];

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
   if(InpEngulfEntryRetrace < 0.0 || InpEngulfEntryRetrace >= 1.0)
     {
      Print("InpEngulfEntryRetrace должен быть в [0.0 .. 1.0)");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpMaxEngulfRetracement > 0.0 && InpMaxEngulfRetracement <= InpMinRetracement)
     {
      Print("InpMaxEngulfRetracement должен быть больше InpMinRetracement (или 0, чтобы отключить)");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpPinbarDeadZoneHigh > InpPinbarDeadZoneLow &&
      (InpPinbarDeadZoneLow < 0.0 || InpPinbarDeadZoneHigh >= 1.0))
     {
      Print("InpPinbarDeadZoneLow/High должны быть в [0.0 .. 1.0)");
      return(INIT_PARAMETERS_INCORRECT);
     }
   //--- CSwingStructure::Update() смотрит только на shift=1 относительно своего
   //--- последнего обработанного бара; если InpEntryTF грубее InpTrendTF, внешний
   //--- гейт OnTick (по InpEntryTF) будет звать g_structD1.Update() реже её
   //--- собственных баров, и она молча пропустит промежуточные свинги/пробои.
   if(PeriodSeconds(InpEntryTF) > PeriodSeconds(InpTrendTF))
     {
      Print("InpEntryTF должен быть не грубее InpTrendTF (иначе тихо теряются бары структуры)");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpUseBreakeven && InpBreakevenTriggerR < 0.0)
     {
      Print("InpBreakevenTriggerR должен быть >= 0");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpUseTrailingStop && (InpTrailingStartR < 0.0 || InpTrailingDistancePoints <= 0))
     {
      Print("InpTrailingStartR должен быть >= 0, InpTrailingDistancePoints > 0");
      return(INIT_PARAMETERS_INCORRECT);
     }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(20);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   if(!g_structD1.Init(_Symbol, InpTrendTF, InpSwingBarsD1, InpBreakByClose, InpHistoryBarsD1))
      return(INIT_FAILED);
   if(!g_structH1.Init(_Symbol, InpEntryTF, InpSwingBarsH1, InpBreakByClose, InpHistoryBarsH1))
      return(INIT_FAILED);

   g_atrHandle = iATR(_Symbol, InpEntryTF, InpATRPeriod);
   if(g_atrHandle == INVALID_HANDLE)
     {
      Print("Не удалось создать хэндл ATR");
      return(INIT_FAILED);
     }

   if(InpUseNewsFilter)
      g_news.Init(InpNewsHourServer, InpNewsMinuteServer, InpNewsMinsBefore, InpNewsMinsAfter);

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

   //--- б/у и трейлинг реагируют на каждый тик, не дожидаясь закрытия бара
   ManageOpenPositions();

   datetime cur = iTime(_Symbol, InpEntryTF, 0);
   if(cur == 0 || cur == g_lastBarH1)
      return;
   g_lastBarH1 = cur;

   ExpirePendingOrders();

   g_structD1.Update();
   g_structH1.Update();

   if(InpVerboseLog)
      PrintFormat("[%s] %s=%s %s=%s", TimeToString(cur),
                  EnumToString(InpTrendTF), g_structD1.TrendToString(),
                  EnumToString(InpEntryTF), g_structH1.TrendToString());

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

   //--- фильтр размера свечи по ATR - общий для пинбара и поглощения
   double minRange = 0.0;
   double atrValue = 0.0;
   if(InpMinRangeATR > 0.0)
     {
      double atr[];
      if(CopyBuffer(g_atrHandle, 0, 1, 1, atr) != 1)
         return;
      atrValue = atr[0];
      minRange = atrValue * InpMinRangeATR;
     }

   //--- оба сетапа ищут вход независимо друг от друга (не ИЛИ, а параллельно) -
   //--- если совпадут на одном баре и есть место по InpMaxPositions, встанут оба
   TryPinBarEntry(td, dirName, minRange, atrValue);

   if(InpUseEngulfing && CountOwnPositions() + CountOwnPendings() < InpMaxPositions)
      TryEngulfingEntry(td, dirName, minRange, atrValue);
  }

//+------------------------------------------------------------------+
//| Пинбар со снятием ликвидности. true, если лимитка выставлена.     |
//+------------------------------------------------------------------+
bool TryPinBarEntry(const ENUM_SMC_TREND td, const string dirName,
                    const double minRange, const double atrValue)
  {
   SPinBar pb = DetectPinBar(_Symbol, InpEntryTF, 1, InpMinTailRatio, minRange);
   if(!pb.valid)
     {
      //--- причина и числа в лог - материал для калибровки InpMinRangeATR/InpMinTailRatio
      if(pb.reject == SMC_PINBAR_RANGE_TOO_SMALL || pb.reject == SMC_PINBAR_TAIL_TOO_SMALL)
         g_log.Rejected(dirName, StringFormat("pinbar_%s range=%.5f atr=%.5f minRange=%.5f tail=%.2f",
                                              PinBarRejectToString(pb.reject), pb.range, atrValue,
                                              minRange, pb.tailRatio));
      return(false);
     }

   if((td == SMC_TREND_BULL && pb.direction != 1) ||
      (td == SMC_TREND_BEAR && pb.direction != -1))
      return(false);

   if(!CheckNewsFilter(dirName))
      return(false);

   //--- снятие ликвидности неснятого ранее уровня - требуется только у пинбара
   double level = 0.0;
   int    levelIdx = -1;

   if(td == SMC_TREND_BULL)
     {
      if(!g_structH1.LastUnsweptLow(level, levelIdx))
        {
         g_log.Rejected(dirName, "нет неснятого свинг-лоу");
         return(false);
        }
      if(!IsSweepDown(pb, level))
         return(false);
     }
   else
     {
      if(!g_structH1.LastUnsweptHigh(level, levelIdx))
        {
         g_log.Rejected(dirName, "нет неснятого свинг-хая");
         return(false);
        }
      if(!IsSweepUp(pb, level))
         return(false);
     }

   double retracePct = 0.0;
   if(!CheckPremiumDiscount(td, dirName, pb.close, 0.0,
                            InpPinbarDeadZoneLow, InpPinbarDeadZoneHigh, retracePct))
      return(false);

   if(!PlaceLimitOrder(td, pb, retracePct))
      return(false);

   //--- уровень израсходован, повторно не используется
   if(td == SMC_TREND_BULL)
      g_structH1.MarkLowSwept(levelIdx);
   else
      g_structH1.MarkHighSwept(levelIdx);

   return(true);
  }

//+------------------------------------------------------------------+
//| Поглощение по тренду. Снятие ликвидности не требуется.            |
//+------------------------------------------------------------------+
bool TryEngulfingEntry(const ENUM_SMC_TREND td, const string dirName,
                       const double minRange, const double atrValue)
  {
   SEngulfing eg = DetectEngulfing(_Symbol, InpEntryTF, 1, minRange,
                                   InpMinEngulfBodyRatio, InpMaxEngulfBodyRatio);
   if(!eg.valid)
     {
      if(eg.reject == SMC_ENGULF_RANGE_TOO_SMALL || eg.reject == SMC_ENGULF_NOT_ENGULFING ||
         eg.reject == SMC_ENGULF_BODY_TOO_BIG)
         g_log.Rejected(dirName, StringFormat("engulf_%s range=%.5f atr=%.5f minRange=%.5f ratio=%.2f",
                                              EngulfRejectToString(eg.reject), eg.high - eg.low,
                                              atrValue, minRange, eg.bodyRatio));
      return(false);
     }

   if((td == SMC_TREND_BULL && eg.direction != 1) ||
      (td == SMC_TREND_BEAR && eg.direction != -1))
      return(false);

   if(!CheckNewsFilter(dirName))
      return(false);

   double retracePct = 0.0;
   if(!CheckPremiumDiscount(td, dirName, eg.close, InpMaxEngulfRetracement,
                            0.0, 0.0, retracePct))
      return(false);

   return(PlaceEngulfLimitOrder(td, eg, retracePct));
  }

//+------------------------------------------------------------------+
//| Общий фильтр новостей - для пинбара и поглощения одинаков.        |
//+------------------------------------------------------------------+
bool CheckNewsFilter(const string dirName)
  {
   if(!InpUseNewsFilter)
      return(true);

   string reason;
   if(g_news.IsBlocked(reason))
     {
      g_log.Rejected(dirName, "news: " + reason);
      if(InpVerboseLog)
         Print("Пропуск по новостям: ", reason);
      return(false);
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| Общий фильтр премиум/дискаунт - нижняя граница одна на оба сетапа, |
//| верхняя (maxRetrace) и мёртвая зона (deadZoneLow/High) опциональны |
//| и свои у вызывающей стороны: у пинбара глубокий откат работает    |
//| лучше, у поглощения - хуже, а у пинбара ещё и провал в середине.  |
//+------------------------------------------------------------------+
bool CheckPremiumDiscount(const ENUM_SMC_TREND td, const string dirName,
                          const double closePrice, const double maxRetrace,
                          const double deadZoneLow, const double deadZoneHigh,
                          double &retracePct)
  {
   retracePct = 0.0;
   if(!InpUsePremiumFilter)
      return(true);

   double rLow, rHigh;
   if(!g_structH1.RangeBounds(rLow, rHigh))
     {
      g_log.Rejected(dirName, "диапазон не определён");
      return(false);
     }

   double span = rHigh - rLow;
   if(span <= 0.0)
      return(false);

   if(td == SMC_TREND_BULL)
      retracePct = (rHigh - closePrice) / span;      // насколько откатили от хая
   else
      retracePct = (closePrice - rLow) / span;        // насколько откатили от лоу

   if(retracePct < InpMinRetracement)
     {
      g_log.Rejected(dirName, StringFormat("откат %.1f%% < %.1f%%",
                                           retracePct * 100.0, InpMinRetracement * 100.0));
      if(InpVerboseLog)
         PrintFormat("Пропуск: откат только %.1f%%", retracePct * 100.0);
      return(false);
     }

   if(maxRetrace > 0.0 && retracePct > maxRetrace)
     {
      g_log.Rejected(dirName, StringFormat("откат %.1f%% > %.1f%%",
                                           retracePct * 100.0, maxRetrace * 100.0));
      if(InpVerboseLog)
         PrintFormat("Пропуск: откат слишком глубокий %.1f%%", retracePct * 100.0);
      return(false);
     }

   if(deadZoneHigh > deadZoneLow && retracePct >= deadZoneLow && retracePct < deadZoneHigh)
     {
      g_log.Rejected(dirName, StringFormat("откат %.1f%% в мёртвой зоне [%.1f%%..%.1f%%)",
                                           retracePct * 100.0, deadZoneLow * 100.0, deadZoneHigh * 100.0));
      if(InpVerboseLog)
         PrintFormat("Пропуск: откат %.1f%% в мёртвой зоне", retracePct * 100.0);
      return(false);
     }

   return(true);
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

   return(SubmitLimitOrder(trend, entry, sl, tp, "pinbar", pb.tailRatio, retracePct,
                           pb.time, pb.low, pb.high));
  }

//+------------------------------------------------------------------+
//| Геометрия входа по поглощающей свече: откат в тело от close.      |
//+------------------------------------------------------------------+
bool PlaceEngulfLimitOrder(const ENUM_SMC_TREND trend, const SEngulfing &eg, const double retracePct)
  {
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double buffer = InpSLBufferPoints * point;

   double entry, sl, tp;

   if(trend == SMC_TREND_BULL)
     {
      entry = eg.close - InpEngulfEntryRetrace * (eg.close - eg.open);
      sl    = eg.low - buffer;
      if(entry - sl <= 0.0)
         return(false);
      tp = entry + (entry - sl) * InpRiskRewardRatio;
     }
   else
     {
      entry = eg.close + InpEngulfEntryRetrace * (eg.open - eg.close);
      sl    = eg.high + buffer;
      if(sl - entry <= 0.0)
         return(false);
      tp = entry - (sl - entry) * InpRiskRewardRatio;
     }

   return(SubmitLimitOrder(trend, entry, sl, tp, "engulf", eg.bodyRatio, retracePct,
                           eg.time, eg.low, eg.high));
  }

//+------------------------------------------------------------------+
//| Общая часть выставления лимитки: проверки STOPS_LEVEL, лот, лог,  |
//| отправка ордера. Используется и пинбаром, и поглощением.          |
//+------------------------------------------------------------------+
bool SubmitLimitOrder(const ENUM_SMC_TREND trend, double entry, double sl, double tp,
                      const string setup, const double ratio, const double retracePct,
                      const datetime barTime, const double barLow, const double barHigh)
  {
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

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
      g_log.Rejected(dirName, setup + ": цена ниже уровня лимитки");
      return(false);
     }
   if(trend == SMC_TREND_BEAR && bid >= entry - minDist)
     {
      g_log.Rejected(dirName, setup + ": цена выше уровня лимитки");
      return(false);
     }

   if(MathAbs(entry - sl) < minDist || MathAbs(tp - entry) < minDist)
     {
      g_log.Rejected(dirName, setup + ": стоп/тейк ближе STOPS_LEVEL");
      return(false);
     }

   double lot = CalcLot(MathAbs(entry - sl));
   if(lot <= 0.0)
     {
      g_log.Rejected(dirName, setup + ": лот = 0");
      return(false);
     }

   string comment = "SMC " + setup + " limit";
   bool ok = (trend == SMC_TREND_BULL)
             ? g_trade.BuyLimit(lot, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, comment)
             : g_trade.SellLimit(lot, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, comment);

   if(!ok)
     {
      g_log.Rejected(dirName, StringFormat("%s: retcode=%d", setup, g_trade.ResultRetcode()));
      PrintFormat("Ошибка выставления (%s): %d %s", setup, g_trade.ResultRetcode(),
                  g_trade.ResultRetcodeDescription());
      return(false);
     }

   g_log.Signal(setup, dirName, entry, sl, tp, lot, ratio, retracePct * 100.0);
   PrintFormat("ЛИМИТКА(%s) %s entry=%.*f sl=%.*f tp=%.*f lot=%.*f ratio=%.2f откат=%.1f%%",
               setup, dirName, _Digits, entry, _Digits, sl, _Digits, tp,
               g_lotDigits, lot, ratio, retracePct * 100.0);

   if(InpDrawSignals)
      DrawSignal(trend, barTime, barLow, barHigh, entry);

   return(true);
  }

//+------------------------------------------------------------------+
//| Перенос в безубыток и трейлинг открытых позиций. Стоп двигается   |
//| только вперёд (в сторону прибыли), никогда назад. R считается от  |
//| изначального риска на момент филла, не от текущего стопа.         |
//+------------------------------------------------------------------+
void ManageOpenPositions(void)
  {
   if(!InpUseBreakeven && !InpUseTrailingStop)
      return;

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol || PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;

      int idx = FindPositionState(ticket);
      if(idx < 0)
         continue;

      double initialRisk = g_posInitialRisk[idx];
      if(initialRisk <= 0.0)
         continue;

      long   type = PositionGetInteger(POSITION_TYPE);
      double open = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl   = PositionGetDouble(POSITION_SL);
      double tp   = PositionGetDouble(POSITION_TP);
      double curPrice = (type == POSITION_TYPE_BUY)
                        ? SymbolInfoDouble(_Symbol, SYMBOL_BID)
                        : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      double profitDist = (type == POSITION_TYPE_BUY) ? (curPrice - open) : (open - curPrice);
      double rMultiple  = profitDist / initialRisk;

      double newSl = sl;

      if(InpUseBreakeven && !g_posBreakevenDone[idx] && rMultiple >= InpBreakevenTriggerR)
        {
         double beSl = (type == POSITION_TYPE_BUY)
                      ? open + InpBreakevenBufferPoints * point
                      : open - InpBreakevenBufferPoints * point;
         bool   better = (type == POSITION_TYPE_BUY) ? (beSl > newSl) : (beSl < newSl);
         if(better)
           {
            newSl = beSl;
            g_posBreakevenDone[idx] = true;
           }
        }

      if(InpUseTrailingStop && rMultiple >= InpTrailingStartR)
        {
         double trailSl = (type == POSITION_TYPE_BUY)
                         ? curPrice - InpTrailingDistancePoints * point
                         : curPrice + InpTrailingDistancePoints * point;
         bool   better = (type == POSITION_TYPE_BUY) ? (trailSl > newSl) : (trailSl < newSl);
         if(better)
            newSl = trailSl;
        }

      if(newSl == sl)
         continue;

      newSl = NormalizeDouble(newSl, _Digits);
      if(newSl == sl)
         continue;

      if(g_trade.PositionModify(ticket, newSl, tp))
         g_log.Write("SL_MODIFIED", StringFormat("ticket=%I64u sl=%.5f r=%.2f", ticket, newSl, rMultiple));
      else
         PrintFormat("Не удалось подвинуть стоп #%I64u: retcode=%d", ticket, g_trade.ResultRetcode());
     }
  }

//+------------------------------------------------------------------+
int FindPositionState(const ulong ticket)
  {
   for(int i = ArraySize(g_posTicket) - 1; i >= 0; i--)
      if(g_posTicket[i] == ticket)
         return(i);
   return(-1);
  }

//+------------------------------------------------------------------+
void AddPositionState(const ulong ticket, const double initialRisk)
  {
   if(FindPositionState(ticket) >= 0)
      return;

   int n = ArraySize(g_posTicket);
   ArrayResize(g_posTicket, n + 1);
   ArrayResize(g_posInitialRisk, n + 1);
   ArrayResize(g_posBreakevenDone, n + 1);
   g_posTicket[n]        = ticket;
   g_posInitialRisk[n]   = initialRisk;
   g_posBreakevenDone[n] = false;
  }

//+------------------------------------------------------------------+
void RemovePositionState(const ulong ticket)
  {
   int idx = FindPositionState(ticket);
   if(idx < 0)
      return;

   int last = ArraySize(g_posTicket) - 1;
   g_posTicket[idx]        = g_posTicket[last];
   g_posInitialRisk[idx]   = g_posInitialRisk[last];
   g_posBreakevenDone[idx] = g_posBreakevenDone[last];
   ArrayResize(g_posTicket, last);
   ArrayResize(g_posInitialRisk, last);
   ArrayResize(g_posBreakevenDone, last);
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
      int      setupBar = iBarShift(_Symbol, InpEntryTF, setup);
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

      ulong positionId = HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);

      if(entryType == DEAL_ENTRY_IN)
        {
         g_log.Write("FILLED", StringFormat("deal=%I64u price=%.5f", trans.deal, price));

         //--- изначальный риск фиксируем сразу после филла, для б/у и трейлинга
         if(PositionSelectByTicket(positionId))
           {
            double posOpen = PositionGetDouble(POSITION_PRICE_OPEN);
            double posSl   = PositionGetDouble(POSITION_SL);
            if(posSl > 0.0)
               AddPositionState(positionId, MathAbs(posOpen - posSl));
           }
        }
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
            RemovePositionState(positionId);
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
void DrawSignal(const ENUM_SMC_TREND trend, const datetime barTime, const double barLow,
                const double barHigh, const double entry)
  {
   string arrowName = StringFormat("SMC_sig_%d", (int)barTime);
   double anchor    = (trend == SMC_TREND_BULL) ? barLow : barHigh;

   if(ObjectCreate(0, arrowName, OBJ_ARROW, 0, barTime, anchor))
     {
      ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, (trend == SMC_TREND_BULL) ? 233 : 234);
      ObjectSetInteger(0, arrowName, OBJPROP_COLOR,
                       (trend == SMC_TREND_BULL) ? clrDeepSkyBlue : clrOrangeRed);
      ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, 2);
      ObjectSetInteger(0, arrowName, OBJPROP_ANCHOR,
                       (trend == SMC_TREND_BULL) ? ANCHOR_TOP : ANCHOR_BOTTOM);
     }

   string lineName = StringFormat("SMC_entry_%d", (int)barTime);
   datetime tEnd   = barTime + PeriodSeconds(InpEntryTF) * (MathMax(1, InpPendingLifeBars) + 1);
   if(ObjectCreate(0, lineName, OBJ_TREND, 0, barTime, entry, tEnd, entry))
     {
      ObjectSetInteger(0, lineName, OBJPROP_COLOR, clrGoldenrod);
      ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, lineName, OBJPROP_RAY_RIGHT, false);
     }
  }
//+------------------------------------------------------------------+
