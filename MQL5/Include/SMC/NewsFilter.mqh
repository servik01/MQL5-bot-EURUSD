//+------------------------------------------------------------------+
//|                                                  NewsFilter.mqh   |
//|  Блокировка торговли вокруг фиксированного дневного окна новости  |
//+------------------------------------------------------------------+
#ifndef SMC_NEWSFILTER_MQH
#define SMC_NEWSFILTER_MQH

//--- Экономический календарь в тестере стратегий не всегда отдаёт данные
//--- (см. OPEN_QUESTIONS.md), поэтому вместо CalendarValueHistory() -
//--- фиксированное дневное окно по серверному времени (TimeCurrent()).
//--- TimeGMT() для этого не годится: в тестере стратегий она равна
//--- TimeTradeServer() (серверному времени), а не настоящему UTC - поведение
//--- разъехалось бы между тестером и live. Час/минута задаются как серверное
//--- время; если сервер брокера идёт по UTC+2, это и есть искомое UTC+2.
class CNewsFilter
  {
private:
   int               m_targetMinutesServer; // время новости, минут от полуночи по серверу
   int               m_minsBefore;
   int               m_minsAfter;

public:
                     CNewsFilter(void);
   void              Init(const int hourServer, const int minuteServer,
                          const int minsBefore, const int minsAfter);
   bool              IsBlocked(string &reason);
  };

//+------------------------------------------------------------------+
CNewsFilter::CNewsFilter(void) : m_targetMinutesServer(0),
                                 m_minsBefore(30),
                                 m_minsAfter(30)
  {
  }

//+------------------------------------------------------------------+
void CNewsFilter::Init(const int hourServer, const int minuteServer,
                       const int minsBefore, const int minsAfter)
  {
   m_targetMinutesServer = hourServer * 60 + minuteServer;
   m_minsBefore          = minsBefore;
   m_minsAfter           = minsAfter;

   PrintFormat("Новостной фильтр: окно %02d:%02d (время сервера) -%d/+%d мин",
               hourServer, minuteServer, m_minsBefore, m_minsAfter);
  }

//+------------------------------------------------------------------+
//| Попадает ли текущий момент в запретное окно вокруг времени новости? |
//+------------------------------------------------------------------+
bool CNewsFilter::IsBlocked(string &reason)
  {
   reason = "";

   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int nowMinutes = dt.hour * 60 + dt.min;

   //--- разница now-target, свёрнутая в [-720, 720) на случай окна у полуночи
   int diff = nowMinutes - m_targetMinutesServer;
   while(diff >= 720)
      diff -= 1440;
   while(diff < -720)
      diff += 1440;

   if(diff < -m_minsBefore || diff > m_minsAfter)
      return(false);

   reason = StringFormat("окно новости %02d:%02d (сейчас %02d:%02d, время сервера)",
                         m_targetMinutesServer / 60, m_targetMinutesServer % 60,
                         dt.hour, dt.min);
   return(true);
  }

#endif
