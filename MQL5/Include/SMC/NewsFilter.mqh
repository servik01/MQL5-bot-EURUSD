//+------------------------------------------------------------------+
//|                                                  NewsFilter.mqh   |
//|  Блокировка торговли вокруг новостей высокой важности             |
//+------------------------------------------------------------------+
#ifndef SMC_NEWSFILTER_MQH
#define SMC_NEWSFILTER_MQH

class CNewsFilter
  {
private:
   string            m_curr1;
   string            m_curr2;
   int               m_minsBefore;
   int               m_minsAfter;
   bool              m_available;      // календарь вообще отдаёт данные?

   bool              CurrencyMatches(const string eventCurrency);

public:
                     CNewsFilter(void);
   void              Init(const string symbol, const int minsBefore, const int minsAfter);
   bool              IsBlocked(const datetime now, string &reason);
   bool              Available(void) const { return m_available; }
  };

//+------------------------------------------------------------------+
CNewsFilter::CNewsFilter(void) : m_curr1(""), m_curr2(""),
                                 m_minsBefore(30), m_minsAfter(30),
                                 m_available(false)
  {
  }

//+------------------------------------------------------------------+
void CNewsFilter::Init(const string symbol, const int minsBefore, const int minsAfter)
  {
   m_curr1      = SymbolInfoString(symbol, SYMBOL_CURRENCY_BASE);
   m_curr2      = SymbolInfoString(symbol, SYMBOL_CURRENCY_PROFIT);
   m_minsBefore = minsBefore;
   m_minsAfter  = minsAfter;

   //--- Пробный запрос: в ряде сборок календарь недоступен в тестере.
   //--- Берём широкое окно, чтобы отличить "нет данных" от "нет событий".
   MqlCalendarValue probe[];
   datetime now = TimeCurrent();
   int n = CalendarValueHistory(probe, now - 30 * 86400, now + 7 * 86400);
   m_available = (n > 0);

   if(m_available)
      PrintFormat("Новостной фильтр активен: %s/%s, окно -%d/+%d мин, событий в пробе: %d",
                  m_curr1, m_curr2, m_minsBefore, m_minsAfter, n);
   else
      Print("ВНИМАНИЕ: экономический календарь недоступен — новостной фильтр НЕ работает. "
            "Результаты теста будут завышены относительно реальной торговли.");
  }

//+------------------------------------------------------------------+
bool CNewsFilter::CurrencyMatches(const string eventCurrency)
  {
   return(eventCurrency == m_curr1 || eventCurrency == m_curr2);
  }

//+------------------------------------------------------------------+
//| Попадает ли момент now в запретное окно вокруг важной новости?    |
//+------------------------------------------------------------------+
bool CNewsFilter::IsBlocked(const datetime now, string &reason)
  {
   reason = "";
   if(!m_available)
      return(false);

   datetime from = now - (datetime)(m_minsAfter  * 60);
   datetime to   = now + (datetime)(m_minsBefore * 60);

   MqlCalendarValue values[];
   int n = CalendarValueHistory(values, from, to);
   if(n <= 0)
      return(false);

   for(int i = 0; i < n; i++)
     {
      MqlCalendarEvent ev;
      if(!CalendarEventById(values[i].event_id, ev))
         continue;
      if(ev.importance != CALENDAR_IMPORTANCE_HIGH)
         continue;

      //--- валюта события живёт в стране события, не в самом событии
      MqlCalendarCountry country;
      if(!CalendarCountryById(ev.country_id, country))
         continue;
      if(!CurrencyMatches(country.currency))
         continue;

      reason = StringFormat("%s %s (%s)", country.currency, ev.name,
                            TimeToString(values[i].time, TIME_MINUTES));
      return(true);
     }

   return(false);
  }

#endif
