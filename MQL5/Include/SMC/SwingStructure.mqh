//+------------------------------------------------------------------+
//|                                              SwingStructure.mqh   |
//|  Структура рынка: свинги с историей, BOS/CHoCH, тренд             |
//+------------------------------------------------------------------+
#ifndef SMC_SWINGSTRUCTURE_MQH
#define SMC_SWINGSTRUCTURE_MQH

enum ENUM_SMC_TREND
  {
   SMC_TREND_NONE =  0,
   SMC_TREND_BULL =  1,
   SMC_TREND_BEAR = -1
  };

enum ENUM_SMC_EVENT
  {
   SMC_EVENT_NONE = 0,
   SMC_BOS_BULL,
   SMC_BOS_BEAR,
   SMC_CHOCH_BULL,
   SMC_CHOCH_BEAR
  };

//--- Точка структуры. swept выставляется, когда ликвидность уровня уже
//--- была снята — повторно такой уровень для входа не используется.
struct SSwingPoint
  {
   datetime          time;
   double            price;
   bool              swept;
   bool              broken;
  };

//+------------------------------------------------------------------+
class CSwingStructure
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   int               m_swingBars;
   bool              m_breakByClose;
   int               m_historyBars;      // глубина хранения свингов, баров

   SSwingPoint       m_highs[];
   SSwingPoint       m_lows[];

   ENUM_SMC_TREND    m_trend;
   ENUM_SMC_EVENT    m_lastEvent;
   datetime          m_lastEventTime;
   datetime          m_lastProcessedBar;

   bool              IsSwingHigh(const int shift);
   bool              IsSwingLow(const int shift);
   void              DetectNewSwings(void);
   void              DetectBreaks(void);
   void              PruneHistory(void);

public:
                     CSwingStructure(void);
   bool              Init(const string symbol, const ENUM_TIMEFRAMES tf,
                          const int swingBars, const bool breakByClose,
                          const int historyBars);
   bool              Update(void);

   ENUM_SMC_TREND    Trend(void)         const { return m_trend;         }
   ENUM_SMC_EVENT    LastEvent(void)     const { return m_lastEvent;     }
   string            TrendToString(void) const;

   //--- ближайший неснятый и непробитый уровень ликвидности
   bool              LastUnsweptLow(double &price, int &index);
   bool              LastUnsweptHigh(double &price, int &index);
   void              MarkLowSwept(const int index);
   void              MarkHighSwept(const int index);

   //--- границы текущего диапазона для премиум/дискаунт
   bool              RangeBounds(double &low, double &high);

   int               HighsCount(void) const { return ArraySize(m_highs); }
   int               LowsCount(void)  const { return ArraySize(m_lows);  }
  };

//+------------------------------------------------------------------+
CSwingStructure::CSwingStructure(void) : m_symbol(NULL),
                                         m_tf(PERIOD_CURRENT),
                                         m_swingBars(2),
                                         m_breakByClose(true),
                                         m_historyBars(120),
                                         m_trend(SMC_TREND_NONE),
                                         m_lastEvent(SMC_EVENT_NONE),
                                         m_lastEventTime(0),
                                         m_lastProcessedBar(0)
  {
   ArrayResize(m_highs, 0);
   ArrayResize(m_lows, 0);
  }

//+------------------------------------------------------------------+
bool CSwingStructure::Init(const string symbol, const ENUM_TIMEFRAMES tf,
                           const int swingBars, const bool breakByClose,
                           const int historyBars)
  {
   if(swingBars < 1)
     {
      Print("CSwingStructure::Init - swingBars должен быть >= 1");
      return(false);
     }

   m_symbol       = symbol;
   m_tf           = tf;
   m_swingBars    = swingBars;
   m_breakByClose = breakByClose;
   m_historyBars  = MathMax(historyBars, swingBars * 4 + 10);

   int need = m_historyBars + m_swingBars * 2 + 10;
   if(Bars(m_symbol, m_tf) < need)
     {
      PrintFormat("CSwingStructure::Init - мало истории %s %s: есть %d, нужно %d",
                  m_symbol, EnumToString(m_tf), Bars(m_symbol, m_tf), need);
      return(false);
     }

   //--- Прогрев: строим структуру по истории, чтобы тренд был известен
   //--- сразу после запуска, а не через N баров ожидания.
   for(int shift = m_historyBars; shift >= m_swingBars + 1; shift--)
     {
      if(IsSwingHigh(shift))
        {
         SSwingPoint p;
         p.time   = iTime(m_symbol, m_tf, shift);
         p.price  = iHigh(m_symbol, m_tf, shift);
         p.swept  = false;
         p.broken = false;
         int n = ArraySize(m_highs);
         ArrayResize(m_highs, n + 1);
         m_highs[n] = p;
        }
      if(IsSwingLow(shift))
        {
         SSwingPoint p;
         p.time   = iTime(m_symbol, m_tf, shift);
         p.price  = iLow(m_symbol, m_tf, shift);
         p.swept  = false;
         p.broken = false;
         int n = ArraySize(m_lows);
         ArrayResize(m_lows, n + 1);
         m_lows[n] = p;
        }
     }

   //--- прогоняем пробои по тем же историческим барам
   for(int shift = m_historyBars; shift >= 1; shift--)
     {
      double up   = m_breakByClose ? iClose(m_symbol, m_tf, shift) : iHigh(m_symbol, m_tf, shift);
      double down = m_breakByClose ? iClose(m_symbol, m_tf, shift) : iLow(m_symbol, m_tf, shift);
      datetime bt = iTime(m_symbol, m_tf, shift);

      for(int i = ArraySize(m_highs) - 1; i >= 0; i--)
        {
         if(!m_highs[i].broken && m_highs[i].time < bt && up > m_highs[i].price)
           {
            m_highs[i].broken = true;
            m_trend = SMC_TREND_BULL;
           }
        }
      for(int i = ArraySize(m_lows) - 1; i >= 0; i--)
        {
         if(!m_lows[i].broken && m_lows[i].time < bt && down < m_lows[i].price)
           {
            m_lows[i].broken = true;
            m_trend = SMC_TREND_BEAR;
           }
        }
     }

   m_lastProcessedBar = iTime(m_symbol, m_tf, 0);

   PrintFormat("Структура %s %s прогрета: тренд=%s, свингов %d/%d",
               m_symbol, EnumToString(m_tf), TrendToString(),
               ArraySize(m_highs), ArraySize(m_lows));
   return(true);
  }

//+------------------------------------------------------------------+
bool CSwingStructure::IsSwingHigh(const int shift)
  {
   double pivot = iHigh(m_symbol, m_tf, shift);
   if(pivot <= 0.0)
      return(false);

   for(int k = 1; k <= m_swingBars; k++)
     {
      if(pivot < iHigh(m_symbol, m_tf, shift + k))
         return(false);
      if(pivot <= iHigh(m_symbol, m_tf, shift - k))
         return(false);
     }
   return(true);
  }

//+------------------------------------------------------------------+
bool CSwingStructure::IsSwingLow(const int shift)
  {
   double pivot = iLow(m_symbol, m_tf, shift);
   if(pivot <= 0.0)
      return(false);

   for(int k = 1; k <= m_swingBars; k++)
     {
      if(pivot > iLow(m_symbol, m_tf, shift + k))
         return(false);
      if(pivot >= iLow(m_symbol, m_tf, shift - k))
         return(false);
     }
   return(true);
  }

//+------------------------------------------------------------------+
void CSwingStructure::DetectNewSwings(void)
  {
   int cand = m_swingBars + 1;
   if(Bars(m_symbol, m_tf) < cand + m_swingBars + 2)
      return;

   datetime t = iTime(m_symbol, m_tf, cand);

   if(IsSwingHigh(cand))
     {
      int n = ArraySize(m_highs);
      if(n == 0 || m_highs[n - 1].time < t)
        {
         SSwingPoint p;
         p.time   = t;
         p.price  = iHigh(m_symbol, m_tf, cand);
         p.swept  = false;
         p.broken = false;
         ArrayResize(m_highs, n + 1);
         m_highs[n] = p;
        }
     }

   if(IsSwingLow(cand))
     {
      int n = ArraySize(m_lows);
      if(n == 0 || m_lows[n - 1].time < t)
        {
         SSwingPoint p;
         p.time   = t;
         p.price  = iLow(m_symbol, m_tf, cand);
         p.swept  = false;
         p.broken = false;
         ArrayResize(m_lows, n + 1);
         m_lows[n] = p;
        }
     }
  }

//+------------------------------------------------------------------+
void CSwingStructure::DetectBreaks(void)
  {
   double up   = m_breakByClose ? iClose(m_symbol, m_tf, 1) : iHigh(m_symbol, m_tf, 1);
   double down = m_breakByClose ? iClose(m_symbol, m_tf, 1) : iLow(m_symbol, m_tf, 1);
   datetime bt = iTime(m_symbol, m_tf, 1);

   //--- пробой вверх: ломаются все неснятые хаи ниже цены
   bool brokeUp = false;
   for(int i = ArraySize(m_highs) - 1; i >= 0; i--)
     {
      if(!m_highs[i].broken && m_highs[i].time < bt && up > m_highs[i].price)
        {
         m_highs[i].broken = true;
         brokeUp = true;
        }
     }
   if(brokeUp)
     {
      m_lastEvent     = (m_trend == SMC_TREND_BEAR) ? SMC_CHOCH_BULL : SMC_BOS_BULL;
      m_lastEventTime = bt;
      m_trend         = SMC_TREND_BULL;
      return;
     }

   bool brokeDown = false;
   for(int i = ArraySize(m_lows) - 1; i >= 0; i--)
     {
      if(!m_lows[i].broken && m_lows[i].time < bt && down < m_lows[i].price)
        {
         m_lows[i].broken = true;
         brokeDown = true;
        }
     }
   if(brokeDown)
     {
      m_lastEvent     = (m_trend == SMC_TREND_BULL) ? SMC_CHOCH_BEAR : SMC_BOS_BEAR;
      m_lastEventTime = bt;
      m_trend         = SMC_TREND_BEAR;
     }
  }

//+------------------------------------------------------------------+
void CSwingStructure::PruneHistory(void)
  {
   datetime cutoff = iTime(m_symbol, m_tf, 0) - (datetime)(PeriodSeconds(m_tf) * m_historyBars);

   int keep = 0;
   int n    = ArraySize(m_highs);
   for(int i = 0; i < n; i++)
      if(m_highs[i].time >= cutoff)
        {
         if(keep != i)
            m_highs[keep] = m_highs[i];
         keep++;
        }
   ArrayResize(m_highs, keep);

   keep = 0;
   n    = ArraySize(m_lows);
   for(int i = 0; i < n; i++)
      if(m_lows[i].time >= cutoff)
        {
         if(keep != i)
            m_lows[keep] = m_lows[i];
         keep++;
        }
   ArrayResize(m_lows, keep);
  }

//+------------------------------------------------------------------+
bool CSwingStructure::Update(void)
  {
   datetime cur = iTime(m_symbol, m_tf, 0);
   if(cur == 0 || cur == m_lastProcessedBar)
      return(false);

   m_lastProcessedBar = cur;
   m_lastEvent        = SMC_EVENT_NONE;

   DetectNewSwings();
   DetectBreaks();
   PruneHistory();

   return(true);
  }

//+------------------------------------------------------------------+
//| Ближайший по времени неснятый и непробитый минимум                |
//+------------------------------------------------------------------+
bool CSwingStructure::LastUnsweptLow(double &price, int &index)
  {
   for(int i = ArraySize(m_lows) - 1; i >= 0; i--)
     {
      if(!m_lows[i].swept && !m_lows[i].broken)
        {
         price = m_lows[i].price;
         index = i;
         return(true);
        }
     }
   return(false);
  }

//+------------------------------------------------------------------+
bool CSwingStructure::LastUnsweptHigh(double &price, int &index)
  {
   for(int i = ArraySize(m_highs) - 1; i >= 0; i--)
     {
      if(!m_highs[i].swept && !m_highs[i].broken)
        {
         price = m_highs[i].price;
         index = i;
         return(true);
        }
     }
   return(false);
  }

//+------------------------------------------------------------------+
void CSwingStructure::MarkLowSwept(const int index)
  {
   if(index >= 0 && index < ArraySize(m_lows))
      m_lows[index].swept = true;
  }

//+------------------------------------------------------------------+
void CSwingStructure::MarkHighSwept(const int index)
  {
   if(index >= 0 && index < ArraySize(m_highs))
      m_highs[index].swept = true;
  }

//+------------------------------------------------------------------+
//| Границы диапазона: последний свинг-хай и свинг-лоу в истории      |
//+------------------------------------------------------------------+
bool CSwingStructure::RangeBounds(double &low, double &high)
  {
   int nh = ArraySize(m_highs);
   int nl = ArraySize(m_lows);
   if(nh == 0 || nl == 0)
      return(false);

   high = m_highs[nh - 1].price;
   low  = m_lows[nl - 1].price;

   return(high > low);
  }

//+------------------------------------------------------------------+
string CSwingStructure::TrendToString(void) const
  {
   switch(m_trend)
     {
      case SMC_TREND_BULL: return("BULL");
      case SMC_TREND_BEAR: return("BEAR");
      default:             return("NONE");
     }
  }

#endif
