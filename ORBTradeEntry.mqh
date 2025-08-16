//+------------------------------------------------------------------+
//| ORBTradeEntry.mqh - Handles ORB trade entry logic                |
//+------------------------------------------------------------------+
#ifndef __ORBTradeEntry_mqh__
#define __ORBTradeEntry_mqh__

#include <Trade\Trade.mqh>
#include "TimeEngine.mqh"

// Centralized ORB settings
struct ORBSettings
{
  double lotSize;        // trade volume
  double slippage;       // max price deviation
  int magicNumber;       // EA magic number
  double rrRatio;        // Risk:Reward multiplier (1 = 1:1, 2 = 1:2, etc.)
  ENUM_TIMEFRAMES orbTf; // timeframe to read ORB levels from
};

void ORBTradeEntry(int timeOffset, string eaPrefix, ORBSettings &cfg)
{
  static double orbHigh = 0;
  static double orbLow = 0;
  static datetime orbTime = 0;
  static int lastTradeDay = -1;

  MqlDateTime nowStruct;
  TimeEngine::ToStruct(TimeEngine::GetLocal(timeOffset), nowStruct);

  // Get today's date for line names
  datetime todayBar = TimeEngine::BarOpen(_Symbol, cfg.orbTf, 0);
  string dateStr = TimeToString(TimeEngine::ApplyOffset(todayBar, timeOffset), TIME_DATE);

  string todayHighLine = eaPrefix + "High_" + dateStr;
  string todayLowLine = eaPrefix + "Low_" + dateStr;

  // Get ORB levels from objects
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

  // BUY breakout
  if (orbHigh > 0 && price > orbHigh)
  {
    MqlTradeRequest req;
    MqlTradeResult res;
    ZeroMemory(req);

    double risk = orbHigh - orbLow;

    req.action = TRADE_ACTION_DEAL;
    req.symbol = _Symbol;
    req.volume = cfg.lotSize;
    req.type = ORDER_TYPE_BUY;
    req.price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    req.sl = orbLow;
    req.tp = orbHigh + (risk * cfg.rrRatio);
    req.deviation = (int)cfg.slippage;
    req.magic = cfg.magicNumber;

    if (OrderSend(req, res) && res.retcode == TRADE_RETCODE_DONE)
    {
      Print("ORB BUY trade placed at ", DoubleToString(req.price, _Digits));
      lastTradeDay = nowStruct.day_of_year;
    }
    else
      Print("ORB BUY trade failed: ", res.retcode);
  }
  // SELL breakout
  else if (orbLow > 0 && price < orbLow)
  {
    MqlTradeRequest req;
    MqlTradeResult res;
    ZeroMemory(req);

    double risk = orbHigh - orbLow;

    req.action = TRADE_ACTION_DEAL;
    req.symbol = _Symbol;
    req.volume = cfg.lotSize;
    req.type = ORDER_TYPE_SELL;
    req.price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    req.sl = orbHigh;
    req.tp = orbLow - (risk * cfg.rrRatio);
    req.deviation = (int)cfg.slippage;
    req.magic = cfg.magicNumber;

    if (OrderSend(req, res) && res.retcode == TRADE_RETCODE_DONE)
    {
      Print("ORB SELL trade placed at ", DoubleToString(req.price, _Digits));
      lastTradeDay = nowStruct.day_of_year;
    }
    else
      Print("ORB SELL trade failed: ", res.retcode);
  }
}

#endif
