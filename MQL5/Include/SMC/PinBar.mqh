//+------------------------------------------------------------------+
//|                                                      PinBar.mqh   |
//|  Детекция пинбара и снятия ликвидности (liquidity sweep)          |
//+------------------------------------------------------------------+
#ifndef SMC_PINBAR_MQH
#define SMC_PINBAR_MQH

//+------------------------------------------------------------------+
//| Описание найденного пинбара                                       |
//+------------------------------------------------------------------+
struct SPinBar
  {
   bool              valid;
   int               direction;      // +1 бычий (нижний хвост), -1 медвежий
   double            open;
   double            high;
   double            low;
   double            close;
   double            tailRatio;      // доля доминирующего хвоста в диапазоне
   datetime          time;
  };

//+------------------------------------------------------------------+
//| Разбор свечи shift на предмет пинбара                             |
//|  minTailRatio - минимальная доля хвоста от диапазона (напр. 0.4)  |
//+------------------------------------------------------------------+
SPinBar DetectPinBar(const string symbol, const ENUM_TIMEFRAMES tf,
                     const int shift, const double minTailRatio)
  {
   SPinBar pb;
   pb.valid     = false;
   pb.direction = 0;
   pb.open      = 0.0;
   pb.high      = 0.0;
   pb.low       = 0.0;
   pb.close     = 0.0;
   pb.tailRatio = 0.0;
   pb.time      = 0;

   double o = iOpen(symbol,  tf, shift);
   double h = iHigh(symbol,  tf, shift);
   double l = iLow(symbol,   tf, shift);
   double c = iClose(symbol, tf, shift);

   if(o <= 0.0 || h <= 0.0 || l <= 0.0 || c <= 0.0)
      return(pb);

   double range = h - l;
   if(range <= 0.0)
      return(pb);

   double bodyTop    = MathMax(o, c);
   double bodyBottom = MathMin(o, c);

   double upperTail = h - bodyTop;
   double lowerTail = bodyBottom - l;

   double upperRatio = upperTail / range;
   double lowerRatio = lowerTail / range;

   pb.open  = o;
   pb.high  = h;
   pb.low   = l;
   pb.close = c;
   pb.time  = iTime(symbol, tf, shift);

   //--- бычий пинбар: длинный нижний хвост, доминирующий над верхним
   if(lowerRatio >= minTailRatio && lowerTail > upperTail)
     {
      pb.valid     = true;
      pb.direction = 1;
      pb.tailRatio = lowerRatio;
      return(pb);
     }

   //--- медвежий пинбар: длинный верхний хвост
   if(upperRatio >= minTailRatio && upperTail > lowerTail)
     {
      pb.valid     = true;
      pb.direction = -1;
      pb.tailRatio = upperRatio;
      return(pb);
     }

   return(pb);
  }

//+------------------------------------------------------------------+
//| Снятие ликвидности вниз:                                          |
//|  хвост ушёл ниже уровня, а закрытие вернулось выше него           |
//+------------------------------------------------------------------+
bool IsSweepDown(const SPinBar &pb, const double level)
  {
   if(!pb.valid || level <= 0.0)
      return(false);
   return(pb.low < level && pb.close > level);
  }

//+------------------------------------------------------------------+
//| Снятие ликвидности вверх                                          |
//+------------------------------------------------------------------+
bool IsSweepUp(const SPinBar &pb, const double level)
  {
   if(!pb.valid || level <= 0.0)
      return(false);
   return(pb.high > level && pb.close < level);
  }

#endif // SMC_PINBAR_MQH
//+------------------------------------------------------------------+
