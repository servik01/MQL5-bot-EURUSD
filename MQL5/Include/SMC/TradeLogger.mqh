//+------------------------------------------------------------------+
//|                                                 TradeLogger.mqh   |
//|  CSV-лог сигналов и сделок для последующего разбора               |
//+------------------------------------------------------------------+
#ifndef SMC_TRADELOGGER_MQH
#define SMC_TRADELOGGER_MQH

class CTradeLogger
  {
private:
   string            m_file;
   bool              m_enabled;

public:
                     CTradeLogger(void);
   bool              Init(const string symbol, const long magic, const bool enabled);
   void              Write(const string event, const string details);
   void              Signal(const string dir, const double entry, const double sl,
                            const double tp, const double lot, const double tailRatio,
                            const double retracePct);
   void              Rejected(const string dir, const string reason);
   string            FileName(void) const { return m_file; }
  };

//+------------------------------------------------------------------+
CTradeLogger::CTradeLogger(void) : m_file(""), m_enabled(false)
  {
  }

//+------------------------------------------------------------------+
bool CTradeLogger::Init(const string symbol, const long magic, const bool enabled)
  {
   m_enabled = enabled;
   if(!m_enabled)
      return(true);

   m_file = StringFormat("SMC_%s_%I64d.csv", symbol, magic);

   //--- создаём заголовок один раз
   if(!FileIsExist(m_file, FILE_COMMON))
     {
      int h = FileOpen(m_file, FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ';');
      if(h == INVALID_HANDLE)
        {
         PrintFormat("Не удалось создать лог %s, ошибка %d", m_file, GetLastError());
         m_enabled = false;
         return(false);
        }
      FileWrite(h, "time", "event", "details");
      FileClose(h);
     }

   PrintFormat("CSV-лог: %s (каталог Common\\Files)", m_file);
   return(true);
  }

//+------------------------------------------------------------------+
void CTradeLogger::Write(const string event, const string details)
  {
   if(!m_enabled)
      return;

   int h = FileOpen(m_file, FILE_READ | FILE_WRITE | FILE_CSV | FILE_ANSI | FILE_COMMON, ';');
   if(h == INVALID_HANDLE)
      return;

   FileSeek(h, 0, SEEK_END);
   FileWrite(h, TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES | TIME_SECONDS),
             event, details);
   FileClose(h);
  }

//+------------------------------------------------------------------+
void CTradeLogger::Signal(const string dir, const double entry, const double sl,
                          const double tp, const double lot, const double tailRatio,
                          const double retracePct)
  {
   Write("PENDING_PLACED",
         StringFormat("dir=%s entry=%.5f sl=%.5f tp=%.5f lot=%.2f tail=%.2f retrace=%.1f%%",
                      dir, entry, sl, tp, lot, tailRatio, retracePct));
  }

//+------------------------------------------------------------------+
void CTradeLogger::Rejected(const string dir, const string reason)
  {
   Write("SIGNAL_REJECTED", StringFormat("dir=%s reason=%s", dir, reason));
  }

#endif
