//+------------------------------------------------------------------+
//|                                                WeeklySweep.mqh    |
//|  Снятие ликвидности прошлой недели (PWL/PWH): вход по CHoCH на    |
//|  InpEntryTF после того, как хвост снял прошлонедельный хай/лоу    |
//|  и закрылся обратно внутри диапазона.                             |
//+------------------------------------------------------------------+
#ifndef SMC_WEEKLYSWEEP_MQH
#define SMC_WEEKLYSWEEP_MQH

//+------------------------------------------------------------------+
class CWeeklySweep
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;          // InpEntryTF - на нём же ищем свечу снятия
   double            m_pwHigh;
   double            m_pwLow;
   datetime          m_weekAnchor;  // время начала текущей недели (W1 бар 0)

   //--- одноразовые на неделю: PWH/PWL снимается не больше раза за неделю
   bool              m_highSwept;
   bool              m_lowSwept;
   //--- ждём первый CHoCH в нужную сторону после снятия; срабатывает раз
   bool              m_highPending;
   bool              m_lowPending;

   void              RefreshWeekLevels(void);

public:
                     CWeeklySweep(void);
   bool              Init(const string symbol, const ENUM_TIMEFRAMES tf);
   void              Update(void);

   bool              ConsumeLowPending(void);
   bool              ConsumeHighPending(void);

   double            PWHigh(void) const { return m_pwHigh; }
   double            PWLow(void)  const { return m_pwLow;  }
  };

//+------------------------------------------------------------------+
CWeeklySweep::CWeeklySweep(void) : m_symbol(NULL),
                                   m_tf(PERIOD_CURRENT),
                                   m_pwHigh(0.0),
                                   m_pwLow(0.0),
                                   m_weekAnchor(0),
                                   m_highSwept(false),
                                   m_lowSwept(false),
                                   m_highPending(false),
                                   m_lowPending(false)
  {
  }

//+------------------------------------------------------------------+
bool CWeeklySweep::Init(const string symbol, const ENUM_TIMEFRAMES tf)
  {
   m_symbol = symbol;
   m_tf     = tf;

   if(Bars(m_symbol, PERIOD_W1) < 3)
     {
      PrintFormat("CWeeklySweep::Init - мало недельной истории %s: есть %d, нужно >= 3",
                  m_symbol, Bars(m_symbol, PERIOD_W1));
      return(false);
     }

   RefreshWeekLevels();
   return(true);
  }

//+------------------------------------------------------------------+
//| При смене недели пересчитывает PWH/PWL и сбрасывает флаги -       |
//| снятие прошлой недели не переносится на следующую.                |
//+------------------------------------------------------------------+
void CWeeklySweep::RefreshWeekLevels(void)
  {
   datetime weekStart = iTime(m_symbol, PERIOD_W1, 0);
   if(weekStart == m_weekAnchor)
      return;

   m_weekAnchor  = weekStart;
   m_pwHigh      = iHigh(m_symbol, PERIOD_W1, 1);
   m_pwLow       = iLow(m_symbol, PERIOD_W1, 1);
   m_highSwept   = false;
   m_lowSwept    = false;
   m_highPending = false;
   m_lowPending  = false;
  }

//+------------------------------------------------------------------+
//| Вызывать раз на новый закрытый бар InpEntryTF.                    |
//+------------------------------------------------------------------+
void CWeeklySweep::Update(void)
  {
   RefreshWeekLevels();

   double high1  = iHigh(m_symbol, m_tf, 1);
   double low1   = iLow(m_symbol, m_tf, 1);
   double close1 = iClose(m_symbol, m_tf, 1);

   //--- снятие PWH: хвост выше уровня, закрытие обратно ниже (отбой)
   if(!m_highSwept && high1 > m_pwHigh && close1 < m_pwHigh)
     {
      m_highSwept   = true;
      m_highPending = true;
     }

   //--- снятие PWL: хвост ниже уровня, закрытие обратно выше (отбой)
   if(!m_lowSwept && low1 < m_pwLow && close1 > m_pwLow)
     {
      m_lowSwept   = true;
      m_lowPending = true;
     }
  }

//+------------------------------------------------------------------+
bool CWeeklySweep::ConsumeLowPending(void)
  {
   if(!m_lowPending)
      return(false);
   m_lowPending = false;
   return(true);
  }

//+------------------------------------------------------------------+
bool CWeeklySweep::ConsumeHighPending(void)
  {
   if(!m_highPending)
      return(false);
   m_highPending = false;
   return(true);
  }

#endif
