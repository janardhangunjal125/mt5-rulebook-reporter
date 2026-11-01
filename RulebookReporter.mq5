//+------------------------------------------------------------------+
//| RulebookReporter.mq5                                             |
//| RULEBOOK REPORTER v1 — READ-ONLY WATCHER for Rulebook v1 (NQ)    |
//|                                                                  |
//| WHAT THIS EA DOES                                                |
//|   * Watches the account it is attached to.                       |
//|   * Reports: position opened / SL or TP changed / position       |
//|     closed / every deal (entry & exit fills) / a heartbeat with   |
//|     balance, equity and open-position count.                     |
//|   * If a watcher URL is set, it POSTs each event as JSON to it.  |
//|     If no URL is set (LOCAL MODE), it writes the same events to  |
//|     a log file + the Experts journal instead.                    |
//|                                                                  |
//| WHAT THIS EA NEVER DOES                                          |
//|   * It contains NO order-sending code at all: no OrderSend, no   |
//|     CTrade, no position close/modify calls. It cannot open,      |
//|     close or change any trade. It only LOOKS and REPORTS.        |
//|   * It never sees or sends the account password.                 |
//|                                                                  |
//| SETUP                                                            |
//|   1. Copy this file into MT5: File > Open Data Folder >          |
//|      MQL5 > Experts, then compile in MetaEditor (F7).            |
//|   2. Tools > Options > Expert Advisors: tick "Allow WebRequest   |
//|      for listed URL" and add your watcher URL                    |
//|      (only needed if you run a watcher endpoint).                |
//|   3. Drag the EA onto any one chart of the account. Done.        |
//+------------------------------------------------------------------+
#property copyright   "Rulebook Reporter v1 — read-only"
#property version     "1.00"
#property strict

//------------------------- USER SETTINGS ---------------------------
input string InpWatcherURL    = "";     // Watcher URL (empty = LOCAL MODE, log only)
input string InpSharedSecret  = "";     // Shared secret token (your watcher server token; keep it private)
input int    InpPollSeconds   = 3;      // Position poll interval (seconds)
input int    InpHeartbeatSecs = 60;     // Heartbeat interval (seconds)
input bool   InpLocalAlerts   = true;   // Popup alert on position open/close
input string InpAccountTag    = "";     // Optional label, e.g. "demo" or "live"
//-------------------------------------------------------------------

string   g_fileName = "rulebook-reporter-log.txt";
long     g_lastHeartbeat = 0;

// Snapshot of one open position, for change detection
struct PosSnap
{
   ulong  ticket;
   long   posId;
   string symbol;
   long   type;        // POSITION_TYPE_BUY / SELL
   double volume;
   double priceOpen;
   double sl;
   double tp;
   double profit;
};

PosSnap g_prev[];   // positions seen on the previous poll

//------------------------- SMALL HELPERS ---------------------------
string JsonEsc(string s)
{
   StringReplace(s, "\\", "\\\\");
   StringReplace(s, "\"", "\\\"");
   return s;
}

string NowIso()
{
   return TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);
}

string BaseJson(string eventName)
{
   string j = "{";
   j += "\"event\":\"" + eventName + "\",";
   j += "\"account_login\":" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + ",";
   j += "\"account_server\":\"" + JsonEsc(AccountInfoString(ACCOUNT_SERVER)) + "\",";
   j += "\"account_tag\":\"" + JsonEsc(InpAccountTag) + "\",";
   j += "\"time_server\":\"" + NowIso() + "\",";
   j += "\"balance\":" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + ",";
   j += "\"equity\":" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2);
   return j;
}

// Send one event: to the watcher URL if set, otherwise to the log file.
void Emit(string json)
{
   Print("[RulebookReporter] ", json);

   if(InpWatcherURL == "")
   {
      int h = FileOpen(g_fileName, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI);
      if(h != INVALID_HANDLE)
      {
         FileSeek(h, 0, SEEK_END);
         FileWriteString(h, json + "\r\n");
         FileClose(h);
      }
      return;
   }

   char postData[];
   char result[];
   string resultHeaders;
   StringToCharArray(json, postData, 0, StringLen(json), CP_UTF8);
   ResetLastError();
   string headers = "Content-Type: application/json\r\n";
   if(InpSharedSecret != "")
      headers += "X-Reporter-Token: " + InpSharedSecret + "\r\n";
   int res = WebRequest("POST", InpWatcherURL, headers,
                        5000, postData, result, resultHeaders);
   if(res == -1)
      Print("[RulebookReporter] WebRequest FAILED, error ", GetLastError(),
            " — is the URL whitelisted in Tools > Options > Expert Advisors?");
}

string PositionJson(string eventName, PosSnap &p)
{
   string j = BaseJson(eventName);
   j += ",\"position_ticket\":" + IntegerToString((long)p.ticket);
   j += ",\"position_id\":" + IntegerToString(p.posId);
   j += ",\"symbol\":\"" + JsonEsc(p.symbol) + "\"";
   j += ",\"side\":\"" + (p.type == POSITION_TYPE_BUY ? "BUY" : "SELL") + "\"";
   j += ",\"volume\":" + DoubleToString(p.volume, 2);
   j += ",\"price_open\":" + DoubleToString(p.priceOpen, _Digits);
   j += ",\"sl\":" + DoubleToString(p.sl, _Digits);
   j += ",\"tp\":" + DoubleToString(p.tp, _Digits);
   j += ",\"profit\":" + DoubleToString(p.profit, 2);
   j += "}";
   return j;
}

//------------------------- POSITION POLLING ------------------------
int SnapshotPositions(PosSnap &out[])
{
   int total = PositionsTotal();
   ArrayResize(out, total);
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      out[i].ticket    = ticket;
      out[i].posId     = PositionGetInteger(POSITION_IDENTIFIER);
      out[i].symbol    = PositionGetString(POSITION_SYMBOL);
      out[i].type      = PositionGetInteger(POSITION_TYPE);
      out[i].volume    = PositionGetDouble(POSITION_VOLUME);
      out[i].priceOpen = PositionGetDouble(POSITION_PRICE_OPEN);
      out[i].sl        = PositionGetDouble(POSITION_SL);
      out[i].tp        = PositionGetDouble(POSITION_TP);
      out[i].profit    = PositionGetDouble(POSITION_PROFIT);
   }
   return total;
}

int FindPrev(ulong ticket)
{
   for(int i = 0; i < ArraySize(g_prev); i++)
      if(g_prev[i].ticket == ticket) return i;
   return -1;
}

void PollPositions()
{
   PosSnap now[];
   int n = SnapshotPositions(now);

   // New positions + SL/TP changes
   for(int i = 0; i < n; i++)
   {
      int k = FindPrev(now[i].ticket);
      if(k < 0)
      {
         Emit(PositionJson("POSITION_OPEN", now[i]));
         if(InpLocalAlerts)
            Alert("Rulebook Reporter: NEW POSITION ", now[i].symbol, " ",
                  (now[i].type == POSITION_TYPE_BUY ? "BUY" : "SELL"), " ",
                  DoubleToString(now[i].volume, 2), " @ ",
                  DoubleToString(now[i].priceOpen, _Digits));
      }
      else if(MathAbs(g_prev[k].sl - now[i].sl) > 0.0000001 ||
              MathAbs(g_prev[k].tp - now[i].tp) > 0.0000001)
      {
         Emit(PositionJson("POSITION_SLTP_CHANGE", now[i]));
      }
   }

   // Closed positions (were in prev, gone now)
   for(int i = 0; i < ArraySize(g_prev); i++)
   {
      bool stillThere = false;
      for(int j = 0; j < n; j++)
         if(now[j].ticket == g_prev[i].ticket) { stillThere = true; break; }
      if(!stillThere)
      {
         Emit(PositionJson("POSITION_CLOSE", g_prev[i]));
         if(InpLocalAlerts)
            Alert("Rulebook Reporter: POSITION CLOSED ", g_prev[i].symbol);
      }
   }

   ArrayResize(g_prev, n);
   for(int i = 0; i < n; i++) g_prev[i] = now[i];
}

//------------------------- TRADE EVENTS ----------------------------
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(trans.deal == 0) return;
   if(!HistoryDealSelect(trans.deal)) return;

   long entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   string entryName = (entry == DEAL_ENTRY_IN)  ? "IN"  :
                      (entry == DEAL_ENTRY_OUT) ? "OUT" : "INOUT";

   string j = BaseJson("DEAL");
   j += ",\"deal_ticket\":" + IntegerToString((long)trans.deal);
   j += ",\"position_id\":" + IntegerToString(HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID));
   j += ",\"symbol\":\"" + JsonEsc(HistoryDealGetString(trans.deal, DEAL_SYMBOL)) + "\"";
   j += ",\"deal_type\":" + IntegerToString(HistoryDealGetInteger(trans.deal, DEAL_TYPE));
   j += ",\"entry\":\"" + entryName + "\"";
   j += ",\"price\":" + DoubleToString(HistoryDealGetDouble(trans.deal, DEAL_PRICE), _Digits);
   j += ",\"volume\":" + DoubleToString(HistoryDealGetDouble(trans.deal, DEAL_VOLUME), 2);
   j += ",\"profit\":" + DoubleToString(HistoryDealGetDouble(trans.deal, DEAL_PROFIT), 2);
   j += "}";
   Emit(j);
}

//------------------------- LIFECYCLE -------------------------------
int OnInit()
{
   EventSetTimer(MathMax(1, InpPollSeconds));
   SnapshotPositions(g_prev);

   string mode = (InpWatcherURL == "") ? "LOCAL MODE (log file only)" : "POSTING to watcher URL";
   Print("[RulebookReporter] STARTED — ", mode,
         " | account ", AccountInfoInteger(ACCOUNT_LOGIN),
         " on ", AccountInfoString(ACCOUNT_SERVER),
         " | open positions at start: ", ArraySize(g_prev));
   Emit(BaseJson("REPORTER_START") + ",\"mode\":\"" +
        (InpWatcherURL == "" ? "local" : "watcher") + "\"}");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   Emit(BaseJson("REPORTER_STOP") + "}");
   Print("[RulebookReporter] STOPPED, reason ", reason);
}

void OnTimer()
{
   PollPositions();
   long now = (long)TimeCurrent();
   if(now - g_lastHeartbeat >= InpHeartbeatSecs)
   {
      g_lastHeartbeat = now;
      Emit(BaseJson("HEARTBEAT") + ",\"open_positions\":" +
           IntegerToString(PositionsTotal()) + "}");
   }
}
//+------------------------------------------------------------------+
