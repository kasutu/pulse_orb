//+------------------------------------------------------------------+
//| ORBTradeEntry.mqh - Handles ORB trade entry logic                |
//+------------------------------------------------------------------+
#ifndef __ORBTradeEntry_mqh__
#define __ORBTradeEntry_mqh__

#include <Trade\Trade.mqh>
#include "TimeEngine.mqh"

void ORBTradeEntry(int timeOffset, string eaPrefix)
{
  static double orbHigh = 0;
  static double orbLow = 0;
  static datetime orbTime = 0;
  static int lastTradeDay = -1;

  MqlDateTime nowStruct;
  TimeEngine::ToStruct(TimeEngine::GetLocal(timeOffset), nowStruct);

  // Get today's date for line names
  datetime todayBar = TimeEngine::BarOpen(_Symbol, PERIOD_M15, 0);
  string dateStr = TimeToString(TimeEngine::ApplyOffset(todayBar, timeOffset), TIME_DATE);

  string todayHighLine = eaPrefix + "High_" + dateStr;
  string todayLowLine = eaPrefix + "Low_" + dateStr;

  // Get ORB levels from today's lines
  if (ObjectFind(0, todayHighLine) >= 0 && ObjectFind(0, todayLowLine) >= 0)
  {
    orbHigh = ObjectGetDouble(0, todayHighLine, OBJPROP_PRICE, 0);
    orbLow = ObjectGetDouble(0, todayLowLine, OBJPROP_PRICE, 0);
    orbTime = (datetime)ObjectGetInteger(0, todayHighLine, OBJPROP_TIME, 0);
  }

  // Skip if already traded today
  if (lastTradeDay == nowStruct.day_of_year)
    return;

  double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

  // BUY breakout above ORB high
  if (orbHigh > 0 && price > orbHigh)
  {
    MqlTradeRequest req;
    MqlTradeResult res;
    ZeroMemory(req);

    req.action = TRADE_ACTION_DEAL;
    req.symbol = _Symbol;
    req.volume = 0.1;
    req.type = ORDER_TYPE_BUY;
    req.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    req.sl = orbLow;
    req.tp = orbHigh + (orbHigh - orbLow);
    req.deviation = 10;
    req.magic = 12345;

    if (OrderSend(req, res))
    {
      if (res.retcode == TRADE_RETCODE_DONE)
      {
        Print("ORB BUY trade placed at ", DoubleToString(req.price, _Digits));
        lastTradeDay = nowStruct.day_of_year;
      }
      else
      {
        Print("ORB BUY trade failed: ", res.retcode);
      }
    }
  }
  // SELL breakout below ORB low
  else if (orbLow > 0 && price < orbLow)
  {
    MqlTradeRequest req;
    MqlTradeResult res;
    ZeroMemory(req);

    req.action = TRADE_ACTION_DEAL;
    req.symbol = _Symbol;
    req.volume = 0.1;
    req.type = ORDER_TYPE_SELL;
    req.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    req.sl = orbHigh;
    req.tp = orbLow - (orbHigh - orbLow);
    req.deviation = 10;
    req.magic = 12345;

    if (OrderSend(req, res))
    {
      if (res.retcode == TRADE_RETCODE_DONE)
      {
        Print("ORB SELL trade placed at ", DoubleToString(req.price, _Digits));
        lastTradeDay = nowStruct.day_of_year;
      }
      else
      {
        Print("ORB SELL trade failed: ", res.retcode);
      }
    }
  }
}

#endif