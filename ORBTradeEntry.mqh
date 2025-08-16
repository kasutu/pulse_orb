//+------------------------------------------------------------------+
//| ORBTradeEntry.mqh - ORB entry with buffer + EMA confirmation     |
//+------------------------------------------------------------------+
#ifndef __ORBTradeEntry_mqh__
#define __ORBTradeEntry_mqh__

#include <Trade\Trade.mqh>
#include "TimeEngine.mqh"

// Centralized ORB + EMA settings
struct ORBSettings
{
  double lotSize;        // trade volume
  double slippage;       // max price deviation (points)
  int magicNumber;       // EA magic number
  double rrRatio;        // TP = risk * rrRatio
  ENUM_TIMEFRAMES orbTf; // timeframe for ORB objects
  double entryBuffer;    // acceptance zone = risk * entryBuffer
  int emaPeriod;         // EMA length (50 EMA)
  ENUM_TIMEFRAMES emaTf; // EMA timeframe
};

void ORBTradeEntry(int timeOffset, string eaPrefix, ORBSettings &cfg)
{
  static double orbHigh = 0.0;
  static double orbLow = 0.0;
  static int lastTradeDay = -1;
  static bool bullishCrossOccurred = false;
  static bool bearishCrossOccurred = false;

  // EMA handle cache (50 and 200 EMA)
  static int ema50Handle = INVALID_HANDLE;
  static int ema200Handle = INVALID_HANDLE;
  static int cachedPeriod = -1;
  static ENUM_TIMEFRAMES cachedTf = (ENUM_TIMEFRAMES)-1;
  static string cachedSymbol = "";

  // Build/rebuild EMA handles if needed
  if (ema50Handle == INVALID_HANDLE ||
      cachedPeriod != cfg.emaPeriod ||
      cachedTf != cfg.emaTf ||
      cachedSymbol != _Symbol)
  {
    if (ema50Handle != INVALID_HANDLE)
      IndicatorRelease(ema50Handle);
    ema50Handle = iMA(_Symbol, cfg.emaTf, cfg.emaPeriod, 0, MODE_EMA, PRICE_CLOSE); // 50 EMA
    cachedPeriod = cfg.emaPeriod;
    cachedTf = cfg.emaTf;
    cachedSymbol = _Symbol;
  }
  if (ema200Handle == INVALID_HANDLE || cachedTf != cfg.emaTf || cachedSymbol != _Symbol)
  {
    if (ema200Handle != INVALID_HANDLE)
      IndicatorRelease(ema200Handle);
    ema200Handle = iMA(_Symbol, cfg.emaTf, 200, 0, MODE_EMA, PRICE_CLOSE); // 200 EMA
  }

  // If EMA handles not ready, abort this tick
  if (ema50Handle == INVALID_HANDLE || ema200Handle == INVALID_HANDLE)
    return;

  // Pull latest EMA values (50 and 200)
  double ema50Buf[2];
  double ema200Buf[2];
  if (CopyBuffer(ema50Handle, 0, 0, 2, ema50Buf) <= 0 || CopyBuffer(ema200Handle, 0, 0, 2, ema200Buf) <= 0)
    return;
  const double ema50 = ema50Buf[0];
  const double ema50Prev = ema50Buf[1];
  const double ema200 = ema200Buf[0];
  const double ema200Prev = ema200Buf[1];

  // Volume confirmation
  // Use global pointer defined in .mq5
  bool volumeConfirmed = false;
  if (volumeConfirmationEngine != NULL)
    volumeConfirmed = volumeConfirmationEngine.IsConfirmed();

  // Current day
  MqlDateTime nowStruct;
  TimeEngine::ToStruct(TimeEngine::GetLocal(timeOffset), nowStruct);

  // Reset cross flags at new day
  if (lastTradeDay != nowStruct.day_of_year)
  {
    bullishCrossOccurred = false;
    bearishCrossOccurred = false;
    lastTradeDay = nowStruct.day_of_year;
  }

  // Track cross occurrence
  bool goldenCross = (ema50Prev <= ema200Prev && ema50 > ema200);
  bool deathCross = (ema50Prev >= ema200Prev && ema50 < ema200);
  if (goldenCross)
    bullishCrossOccurred = true;
  if (deathCross)
    bearishCrossOccurred = true;

  // Resolve today's ORB object names
  datetime todayBar = TimeEngine::BarOpen(_Symbol, cfg.orbTf, 0);
  string dateStr = TimeToString(TimeEngine::ApplyOffset(todayBar, timeOffset), TIME_DATE);
  string todayHighLine = eaPrefix + "High_" + dateStr;
  string todayLowLine = eaPrefix + "Low_" + dateStr;

  // Read ORB levels from chart objects (must exist)
  if (ObjectFind(0, todayHighLine) >= 0 && ObjectFind(0, todayLowLine) >= 0)
  {
    orbHigh = ObjectGetDouble(0, todayHighLine, OBJPROP_PRICE, 0);
    orbLow = ObjectGetDouble(0, todayLowLine, OBJPROP_PRICE, 0);
  }
  else
  {
    // No ORB lines -> nothing to do
    return;
  }

  // Sanity
  const double risk = orbHigh - orbLow;
  if (!(risk > 0.0))
    return;

  const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
  const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

  // BUY breakout: price above ORB high, bullish cross occurred, price above both EMAs, volume confirmed
  bool priceAboveEMAs = (bid > ema50 && bid > ema200);
  if (bid > orbHigh && bullishCrossOccurred && priceAboveEMAs && volumeConfirmed)
  {
    MqlTradeRequest req;
    MqlTradeResult res;
    ZeroMemory(req);
    ZeroMemory(res);

    req.action = TRADE_ACTION_DEAL;
    req.symbol = _Symbol;
    req.volume = cfg.lotSize;
    req.type = ORDER_TYPE_BUY;
    req.price = ask;
    req.sl = orbLow;
    req.tp = orbHigh + (risk * cfg.rrRatio);
    req.deviation = (int)cfg.slippage;
    req.magic = cfg.magicNumber;

    if (OrderSend(req, res) && res.retcode == TRADE_RETCODE_DONE)
    {
      Print("ORB BUY @ ", DoubleToString(req.price, _Digits),
            " | EMA50=", DoubleToString(ema50, _Digits),
            " | EMA200=", DoubleToString(ema200, _Digits),
            " | risk=", DoubleToString(risk, _Digits));
    }
    else
    {
      Print("ORB BUY failed: retcode=", res.retcode);
    }
  }
  // SELL breakout: price below ORB low, bearish cross occurred, price below both EMAs, volume confirmed
  bool priceBelowEMAs = (bid < ema50 && bid < ema200);
  if (bid < orbLow && bearishCrossOccurred && priceBelowEMAs && volumeConfirmed)
  {
    MqlTradeRequest req;
    MqlTradeResult res;
    ZeroMemory(req);
    ZeroMemory(res);

    req.action = TRADE_ACTION_DEAL;
    req.symbol = _Symbol;
    req.volume = cfg.lotSize;
    req.type = ORDER_TYPE_SELL;
    req.price = bid;
    req.sl = orbHigh;
    req.tp = orbLow - (risk * cfg.rrRatio);
    req.deviation = (int)cfg.slippage;
    req.magic = cfg.magicNumber;

    if (OrderSend(req, res) && res.retcode == TRADE_RETCODE_DONE)
    {
      Print("ORB SELL @ ", DoubleToString(req.price, _Digits),
            " | EMA50=", DoubleToString(ema50, _Digits),
            " | EMA200=", DoubleToString(ema200, _Digits),
            " | risk=", DoubleToString(risk, _Digits));
    }
    else
    {
      Print("ORB SELL failed: retcode=", res.retcode);
    }
  }
}

#endif
