//+------------------------------------------------------------------+
//|                                                  Engulfing.mqh    |
//|  Детекция поглощающей свечи по тренду - альтернатива пинбару,     |
//|  без требования снятия ликвидности.                               |
//+------------------------------------------------------------------+
#ifndef SMC_ENGULFING_MQH
#define SMC_ENGULFING_MQH

enum ENUM_SMC_ENGULF_REJECT
  {
   SMC_ENGULF_OK = 0,
   SMC_ENGULF_NO_DATA,
   SMC_ENGULF_RANGE_TOO_SMALL,
   SMC_ENGULF_NOT_ENGULFING,
   SMC_ENGULF_BODY_TOO_BIG
  };

struct SEngulfing
  {
   bool                    valid;
   int                     direction;   // +1 бычье, -1 медвежье
   double                  open;
   double                  high;
   double                  low;
   double                  close;
   double                  bodyRatio;   // тело текущей свечи / тело предыдущей
   datetime                time;
   ENUM_SMC_ENGULF_REJECT  reject;
  };

//+------------------------------------------------------------------+
string EngulfRejectToString(const ENUM_SMC_ENGULF_REJECT reason)
  {
   switch(reason)
     {
      case SMC_ENGULF_OK:               return("ok");
      case SMC_ENGULF_NO_DATA:          return("no_data");
      case SMC_ENGULF_RANGE_TOO_SMALL:  return("range");
      case SMC_ENGULF_NOT_ENGULFING:    return("not_engulfing");
      case SMC_ENGULF_BODY_TOO_BIG:     return("body_too_big");
      default:                          return("unknown");
     }
  }

//+------------------------------------------------------------------+
//| minRange     - минимальный диапазон свечи, как у пинбара (0 = без)|
//| minBodyRatio - во сколько раз тело текущей свечи должно быть      |
//|                больше тела предыдущей (1.0 = просто поглощение)   |
//| maxBodyRatio - верхняя граница того же отношения (0 = без потолка)|
//|                огромные поглощения чаще похожи на истощение,      |
//|                чем на продолжение движения - см. OPEN_QUESTIONS.md|
//+------------------------------------------------------------------+
SEngulfing DetectEngulfing(const string symbol, const ENUM_TIMEFRAMES tf,
                           const int shift, const double minRange,
                           const double minBodyRatio, const double maxBodyRatio)
  {
   SEngulfing e;
   e.valid     = false;
   e.direction = 0;
   e.open      = 0.0;
   e.high      = 0.0;
   e.low       = 0.0;
   e.close     = 0.0;
   e.bodyRatio = 0.0;
   e.time      = 0;
   e.reject    = SMC_ENGULF_NO_DATA;

   double o  = iOpen(symbol,  tf, shift);
   double h  = iHigh(symbol,  tf, shift);
   double l  = iLow(symbol,   tf, shift);
   double c  = iClose(symbol, tf, shift);
   double po = iOpen(symbol,  tf, shift + 1);
   double pc = iClose(symbol, tf, shift + 1);

   if(o <= 0.0 || h <= 0.0 || l <= 0.0 || c <= 0.0 || po <= 0.0 || pc <= 0.0)
      return(e);

   double range = h - l;
   if(range <= 0.0)
      return(e);

   e.open  = o;
   e.high  = h;
   e.low   = l;
   e.close = c;
   e.time  = iTime(symbol, tf, shift);

   //--- отсекаем микросвечи, как у пинбара
   if(minRange > 0.0 && range < minRange)
     {
      e.reject = SMC_ENGULF_RANGE_TOO_SMALL;
      return(e);
     }

   double body     = MathAbs(c - o);
   double prevBody = MathAbs(pc - po);
   e.bodyRatio = (prevBody > 0.0) ? body / prevBody : 0.0;

   //--- тело текущей свечи полностью перекрывает тело предыдущей
   bool bullish = (c > o) && (pc < po) && (o <= pc) && (c >= po);
   bool bearish = (c < o) && (pc > po) && (o >= pc) && (c <= po);

   if(bullish && e.bodyRatio >= minBodyRatio)
     {
      if(maxBodyRatio > 0.0 && e.bodyRatio > maxBodyRatio)
        {
         e.reject = SMC_ENGULF_BODY_TOO_BIG;
         return(e);
        }
      e.valid     = true;
      e.direction = 1;
      e.reject    = SMC_ENGULF_OK;
      return(e);
     }
   if(bearish && e.bodyRatio >= minBodyRatio)
     {
      if(maxBodyRatio > 0.0 && e.bodyRatio > maxBodyRatio)
        {
         e.reject = SMC_ENGULF_BODY_TOO_BIG;
         return(e);
        }
      e.valid     = true;
      e.direction = -1;
      e.reject    = SMC_ENGULF_OK;
      return(e);
     }

   e.reject = SMC_ENGULF_NOT_ENGULFING;
   return(e);
  }

#endif
