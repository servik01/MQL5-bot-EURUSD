//+------------------------------------------------------------------+
//|                                                      PinBar.mqh   |
//|  Детекция пинбара, фильтр по размеру и снятие ликвидности         |
//+------------------------------------------------------------------+
#ifndef SMC_PINBAR_MQH
#define SMC_PINBAR_MQH

struct SPinBar
  {
   bool              valid;
   int               direction;      // +1 бычий, -1 медвежий
   double            open;
   double            high;
   double            low;
   double            close;
   double            range;
   double            tailRatio;
   datetime          time;
  };

//+------------------------------------------------------------------+
//| minRange - минимально допустимый диапазон свечи (0 = без фильтра) |
//+------------------------------------------------------------------+
SPinBar DetectPinBar(const string symbol, const ENUM_TIMEFRAMES tf,
                     const int shift, const double minTailRatio,
                     const double minRange)
  {
   SPinBar pb;
   pb.valid     = false;
   pb.direction = 0;
   pb.open      = 0.0;
   pb.high      = 0.0;
   pb.low       = 0.0;
   pb.close     = 0.0;
   pb.range     = 0.0;
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

   pb.open  = o;
   pb.high  = h;
   pb.low   = l;
   pb.close = c;
   pb.range = range;
   pb.time  = iTime(symbol, tf, shift);

   //--- отсекаем микросвечи до анализа геометрии
   if(minRange > 0.0 && range < minRange)
      return(pb);

   double bodyTop    = MathMax(o, c);
   double bodyBottom = MathMin(o, c);
   double upperTail  = h - bodyTop;
   double lowerTail  = bodyBottom - l;

   if(lowerTail / range >= minTailRatio && lowerTail > upperTail)
     {
      pb.valid     = true;
      pb.direction = 1;
      pb.tailRatio = lowerTail / range;
      return(pb);
     }

   if(upperTail / range >= minTailRatio && upperTail > lowerTail)
     {
      pb.valid     = true;
      pb.direction = -1;
      pb.tailRatio = upperTail / range;
      return(pb);
     }

   return(pb);
  }

//+------------------------------------------------------------------+
bool IsSweepDown(const SPinBar &pb, const double level)
  {
   if(!pb.valid || level <= 0.0)
      return(false);
   return(pb.low < level && pb.close > level);
  }

//+------------------------------------------------------------------+
bool IsSweepUp(const SPinBar &pb, const double level)
  {
   if(!pb.valid || level <= 0.0)
      return(false);
   return(pb.high > level && pb.close < level);
  }

#endif
