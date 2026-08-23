//+------------------------------------------------------------------+
//|                                            SMC_PinSweep_EA.mq5    |
//|  Тренд по структуре D1 + H1 (строгое совпадение)                  |
//|  Вход: H1 пинбар, снявший ликвидность предыдущего свинга          |
//|  Стоп за хвост пинбара, тейк по фиксированному R:R                |
//+------------------------------------------------------------------+
#property copyright "SMC PinSweep"
#property version   "1.00"
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

//--- Риск и сделка
input group "=== Риск ==="
input double   InpRiskRewardRatio = 2.0;      // R:R (тейк = R:R * стоп)
input double   InpRiskPercent     = 0.5;      // Риск на сделку, % от баланса (0 = фикс. лот)
input double   InpFixedLot        = 0.01;     // Фиксированный лот (если риск % = 0)
input int      InpSLBufferPoints  = 20;       // Буфер стопа за хвост, пунктов
input int      InpMaxSpreadPoints = 30;       // Макс. спред для входа, пунктов
input int      InpMaxPositions    = 1;        // Макс. одновременных позиций по символу

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
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(20);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   if(!g_structD1.Init(_Symbol, PERIOD_D1, InpSwingBarsD1, InpBreakByClose))
      return(INIT_FAILED);
   if(!g_structH1.Init(_Symbol, PERIOD_H1, InpSwingBarsH1, InpBreakByClose))
      return(INIT_FAILED);

   //--- разрядность лота
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

   PrintFormat("SMC_PinSweep инициализирован: %s, риск %.2f%%, R:R 1:%.1f",
               _Symbol, InpRiskPercent, InpRiskRewardRatio);
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
   //--- работаем только на открытии нового H1 бара
   datetime cur = iTime(_Symbol, PERIOD_H1, 0);
   if(cur == 0 || cur == g_lastBarH1)
      return;
   g_lastBarH1 = cur;

   //--- обновляем структуру на обоих таймфреймах
   g_structD1.Update();
   g_structH1.Update();

   if(InpVerboseLog)
      PrintFormat("[%s] Тренд D1=%s H1=%s | H1 swingLow=%.*f swingHigh=%.*f",
                  TimeToString(cur), g_structD1.TrendToString(), g_structH1.TrendToString(),
                  _Digits, g_structH1.SwingLow(), _Digits, g_structH1.SwingHigh());

   if(CountOwnPositions() >= InpMaxPositions)
      return;

   //--- строгое совпадение трендов
   ENUM_SMC_TREND td = g_structD1.Trend();
   ENUM_SMC_TREND th = g_structH1.Trend();
   if(td == SMC_TREND_NONE || td != th)
      return;

   //--- фильтр спреда
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpreadPoints)
     {
      if(InpVerboseLog)
         PrintFormat("Пропуск: спред %d > %d", (int)spread, InpMaxSpreadPoints);
      return;
     }

   //--- пинбар на последнем закрытом H1 баре
   SPinBar pb = DetectPinBar(_Symbol, PERIOD_H1, 1, InpMinTailRatio);
   if(!pb.valid)
      return;

   //--- направление пинбара должно совпадать с трендом
   if((td == SMC_TREND_BULL && pb.direction != 1) ||
      (td == SMC_TREND_BEAR && pb.direction != -1))
      return;

   //--- снятие ликвидности
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

   OpenTrade(td, pb);
  }

//+------------------------------------------------------------------+
//| Открытие позиции по сигналу                                       |
//+------------------------------------------------------------------+
void OpenTrade(const ENUM_SMC_TREND trend, const SPinBar &pb)
  {
   double point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double buffer = InpSLBufferPoints * point;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(ask <= 0.0 || bid <= 0.0)
      return;

   double entry, sl, tp;

   if(trend == SMC_TREND_BULL)
     {
      entry = ask;
      sl    = pb.low - buffer;
      if(entry - sl <= 0.0)
         return;
      tp = entry + (entry - sl) * InpRiskRewardRatio;
     }
   else
     {
      entry = bid;
      sl    = pb.high + buffer;
      if(sl - entry <= 0.0)
         return;
      tp = entry - (sl - entry) * InpRiskRewardRatio;
     }

   sl = NormalizeDouble(sl, _Digits);
   tp = NormalizeDouble(tp, _Digits);

   //--- проверка минимальной дистанции стопов брокера
   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDist  = stopsLevel * point;
   if(MathAbs(entry - sl) < minDist || MathAbs(tp - entry) < minDist)
     {
      PrintFormat("Пропуск: стоп/тейк ближе минимальной дистанции брокера (%d пунктов)",
                  (int)stopsLevel);
      return;
     }

   double lot = CalcLot(MathAbs(entry - sl));
   if(lot <= 0.0)
     {
      Print("Пропуск: расчётный лот равен нулю");
      return;
     }

   bool ok = false;
   string comment = (trend == SMC_TREND_BULL) ? "SMC pin sweep buy" : "SMC pin sweep sell";

   if(trend == SMC_TREND_BULL)
      ok = g_trade.Buy(lot, _Symbol, 0.0, sl, tp, comment);
   else
      ok = g_trade.Sell(lot, _Symbol, 0.0, sl, tp, comment);

   if(!ok)
     {
      PrintFormat("Ошибка открытия: retcode=%d %s",
                  g_trade.ResultRetcode(), g_trade.ResultRetcodeDescription());
      return;
     }

   PrintFormat("ВХОД %s lot=%.*f entry=%.*f sl=%.*f tp=%.*f tail=%.2f",
               (trend == SMC_TREND_BULL ? "BUY" : "SELL"),
               g_lotDigits, lot, _Digits, entry, _Digits, sl, _Digits, tp, pb.tailRatio);

   if(InpDrawSignals)
      DrawSignal(trend, pb);
  }

//+------------------------------------------------------------------+
//| Расчёт лота от риска                                              |
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
//| Приведение лота к требованиям символа                             |
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
      lot = 0.0;                 // не хватает средств под минимальный риск
   if(lot > maxLot)
      lot = maxLot;

   return(NormalizeDouble(lot, g_lotDigits));
  }

//+------------------------------------------------------------------+
//| Количество своих открытых позиций по символу                      |
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
//| Отрисовка сигнала на графике                                      |
//+------------------------------------------------------------------+
void DrawSignal(const ENUM_SMC_TREND trend, const SPinBar &pb)
  {
   string name = StringFormat("SMC_sig_%d", (int)pb.time);
   double anchor = (trend == SMC_TREND_BULL) ? pb.low : pb.high;

   if(!ObjectCreate(0, name, OBJ_ARROW, 0, pb.time, anchor))
      return;

   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, (trend == SMC_TREND_BULL) ? 233 : 234);
   ObjectSetInteger(0, name, OBJPROP_COLOR,
                    (trend == SMC_TREND_BULL) ? clrDeepSkyBlue : clrOrangeRed);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR,
                    (trend == SMC_TREND_BULL) ? ANCHOR_TOP : ANCHOR_BOTTOM);
  }
//+------------------------------------------------------------------+
