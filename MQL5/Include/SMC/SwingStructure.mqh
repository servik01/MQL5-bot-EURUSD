//+------------------------------------------------------------------+
//|                                              SwingStructure.mqh   |
//|  Определение тренда по рыночной структуре (BOS / CHoCH)           |
//+------------------------------------------------------------------+
#ifndef SMC_SWINGSTRUCTURE_MQH
#define SMC_SWINGSTRUCTURE_MQH

//--- Состояние тренда
enum ENUM_SMC_TREND
  {
   SMC_TREND_NONE =  0,   // структура ещё не определена
   SMC_TREND_BULL =  1,   // бычья структура (HH/HL)
   SMC_TREND_BEAR = -1    // медвежья структура (LH/LL)
  };

//--- Событие структуры
enum ENUM_SMC_EVENT
  {
   SMC_EVENT_NONE = 0,
   SMC_BOS_BULL,          // пробой по тренду вверх
   SMC_BOS_BEAR,          // пробой по тренду вниз
   SMC_CHOCH_BULL,        // смена характера на бычий
   SMC_CHOCH_BEAR         // смена характера на медвежий
  };

//+------------------------------------------------------------------+
//| Класс отслеживания структуры на одном таймфрейме                  |
//+------------------------------------------------------------------+
class CSwingStructure
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   int               m_swingBars;      // окно фрактала (баров слева/справа)
   bool              m_breakByClose;   // true = пробой по close, false = по wick

   //--- последний подтверждённый неснятый свинг-хай
   double            m_swingHigh;
   datetime          m_swingHighTime;
   bool              m_swingHighBroken;

   //--- последний подтверждённый неснятый свинг-лоу
   double            m_swingLow;
   datetime          m_swingLowTime;
   bool              m_swingLowBroken;

   //--- защищённые уровни (инвалидация структуры)
   double            m_protectedLow;
   double            m_protectedHigh;

   ENUM_SMC_TREND    m_trend;
   ENUM_SMC_EVENT    m_lastEvent;
   datetime          m_lastEventTime;
   datetime          m_lastProcessedBar;

   bool              IsSwingHigh(const int shift);
   bool              IsSwingLow(const int shift);
   void              DetectNewSwings(void);
   void              DetectBreaks(void);

public:
                     CSwingStructure(void);
   bool              Init(const string symbol, const ENUM_TIMEFRAMES tf,
                          const int swingBars, const bool breakByClose);
   bool              Update(void);          // true, если обработан новый бар

   ENUM_SMC_TREND    Trend(void)          const { return m_trend;          }
   ENUM_SMC_EVENT    LastEvent(void)      const { return m_lastEvent;      }
   datetime          LastEventTime(void)  const { return m_lastEventTime;  }

   double            SwingHigh(void)      const { return m_swingHigh;      }
   double            SwingLow(void)       const { return m_swingLow;       }
   datetime          SwingHighTime(void)  const { return m_swingHighTime;  }
   datetime          SwingLowTime(void)   const { return m_swingLowTime;   }

   double            ProtectedLow(void)   const { return m_protectedLow;   }
   double            ProtectedHigh(void)  const { return m_protectedHigh;  }

   string            TrendToString(void)  const;
  };

//+------------------------------------------------------------------+
CSwingStructure::CSwingStructure(void) : m_symbol(NULL),
                                         m_tf(PERIOD_CURRENT),
                                         m_swingBars(2),
                                         m_breakByClose(true),
                                         m_swingHigh(0.0),
                                         m_swingHighTime(0),
                                         m_swingHighBroken(false),
                                         m_swingLow(0.0),
                                         m_swingLowTime(0),
                                         m_swingLowBroken(false),
                                         m_protectedLow(0.0),
                                         m_protectedHigh(0.0),
                                         m_trend(SMC_TREND_NONE),
                                         m_lastEvent(SMC_EVENT_NONE),
                                         m_lastEventTime(0),
                                         m_lastProcessedBar(0)
  {
  }

//+------------------------------------------------------------------+
bool CSwingStructure::Init(const string symbol, const ENUM_TIMEFRAMES tf,
                           const int swingBars, const bool breakByClose)
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

   //--- прогреваем историю
   int need = m_swingBars * 2 + 10;
   if(Bars(m_symbol, m_tf) < need)
     {
      PrintFormat("CSwingStructure::Init - недостаточно истории %s %s (нужно %d)",
                  m_symbol, EnumToString(m_tf), need);
      return(false);
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| Бар shift является свинг-хаем?                                    |
//+------------------------------------------------------------------+
bool CSwingStructure::IsSwingHigh(const int shift)
  {
   double pivot = iHigh(m_symbol, m_tf, shift);
   if(pivot <= 0.0)
      return(false);

   for(int k = 1; k <= m_swingBars; k++)
     {
      //--- слева допускаем равенство, справа требуем строгое превышение
      if(pivot < iHigh(m_symbol, m_tf, shift + k))
         return(false);
      if(pivot <= iHigh(m_symbol, m_tf, shift - k))
         return(false);
     }
   return(true);
  }

//+------------------------------------------------------------------+
//| Бар shift является свинг-лоу?                                     |
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
//| Поиск новых подтверждённых свингов                                |
//+------------------------------------------------------------------+
void CSwingStructure::DetectNewSwings(void)
  {
   //--- кандидат подтверждается только когда справа от него закрылось
   //--- m_swingBars баров, т.е. индекс кандидата = m_swingBars + 1
   int cand = m_swingBars + 1;

   if(Bars(m_symbol, m_tf) < cand + m_swingBars + 2)
      return;

   if(IsSwingHigh(cand))
     {
      datetime t = iTime(m_symbol, m_tf, cand);
      if(t > m_swingHighTime)
        {
         m_swingHigh       = iHigh(m_symbol, m_tf, cand);
         m_swingHighTime   = t;
         m_swingHighBroken = false;
        }
     }

   if(IsSwingLow(cand))
     {
      datetime t = iTime(m_symbol, m_tf, cand);
      if(t > m_swingLowTime)
        {
         m_swingLow       = iLow(m_symbol, m_tf, cand);
         m_swingLowTime   = t;
         m_swingLowBroken = false;
        }
     }
  }

//+------------------------------------------------------------------+
//| Проверка пробоя структуры последним закрытым баром                |
//+------------------------------------------------------------------+
void CSwingStructure::DetectBreaks(void)
  {
   double upProbe   = m_breakByClose ? iClose(m_symbol, m_tf, 1) : iHigh(m_symbol, m_tf, 1);
   double downProbe = m_breakByClose ? iClose(m_symbol, m_tf, 1) : iLow(m_symbol, m_tf, 1);

   //--- пробой вверх
   if(!m_swingHighBroken && m_swingHighTime > 0 && upProbe > m_swingHigh)
     {
      m_swingHighBroken = true;
      m_lastEvent       = (m_trend == SMC_TREND_BEAR) ? SMC_CHOCH_BULL : SMC_BOS_BULL;
      m_lastEventTime   = iTime(m_symbol, m_tf, 1);
      m_trend           = SMC_TREND_BULL;

      //--- защищённый минимум = минимум движения от пробитого хая до текущего бара
      int idx = iBarShift(m_symbol, m_tf, m_swingHighTime);
      if(idx > 1)
        {
         int li = iLowest(m_symbol, m_tf, MODE_LOW, idx, 1);
         if(li >= 0)
            m_protectedLow = iLow(m_symbol, m_tf, li);
        }
      return;      // за один бар обрабатываем только одно событие
     }

   //--- пробой вниз
   if(!m_swingLowBroken && m_swingLowTime > 0 && downProbe < m_swingLow)
     {
      m_swingLowBroken = true;
      m_lastEvent      = (m_trend == SMC_TREND_BULL) ? SMC_CHOCH_BEAR : SMC_BOS_BEAR;
      m_lastEventTime  = iTime(m_symbol, m_tf, 1);
      m_trend          = SMC_TREND_BEAR;

      int idx = iBarShift(m_symbol, m_tf, m_swingLowTime);
      if(idx > 1)
        {
         int hi = iHighest(m_symbol, m_tf, MODE_HIGH, idx, 1);
         if(hi >= 0)
            m_protectedHigh = iHigh(m_symbol, m_tf, hi);
        }
     }
  }

//+------------------------------------------------------------------+
//| Обновление состояния (вызывать на каждом тике; отработает один    |
//| раз на новом баре своего таймфрейма)                              |
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

   return(true);
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

#endif // SMC_SWINGSTRUCTURE_MQH
//+------------------------------------------------------------------+
