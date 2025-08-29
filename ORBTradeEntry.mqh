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
  // Grading: scale volume by grade tiers based on volumeRatio
  // gradeFactors[0] = multiplier for grade 0 (weak), gradeFactors[1] = grade1, etc.
  double gradeFactors[5];
  // volumeRatio thresholds mapping to grades (e.g. 1.0,1.5,2.0)
  double gradeThresholds[4];
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
  bool volumeConfirmed = false;
  if (volumeConfirmationEngine != NULL)
    volumeConfirmed = volumeConfirmationEngine.IsConfirmed();

  // Current day
  MqlDateTime nowStruct;
  TimeEngine::ToStruct(TimeEngine::GetLocal(timeOffset), nowStruct);

  // Trade limit per session
  static int tradeCount = 0;
  static int lastSessionDay = -1;
  static int lastSessionHour = -1;
  int currentHour = nowStruct.hour;
  int currentDay = nowStruct.day_of_year;
  int sessionEndHour = 24; // Default, can be parameterized
  if (lastSessionDay != currentDay || (lastSessionHour < sessionEndHour && currentHour >= sessionEndHour))
  {
    tradeCount = 0;
    lastSessionDay = currentDay;
    lastSessionHour = currentHour;
  }

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

  // Calculate Fibonacci levels for TP
  double fib1 = orbHigh + (risk * 1.0);    // 100% extension above high
  double fib2 = orbHigh + (risk * 2.0);    // 200% extension above high
  double fib1Sell = orbLow - (risk * 1.0); // 100% extension below low
  double fib2Sell = orbLow - (risk * 2.0); // 200% extension below low

  // ORB breakout BUY with volume confirmation and trade limit
  if (bid > orbHigh && volumeConfirmed && tradeCount < 10)
  {
    MqlTradeRequest req;
    MqlTradeResult res;
    ZeroMemory(req);
    ZeroMemory(res);

    req.action = TRADE_ACTION_DEAL;
    req.symbol = _Symbol;
    // Determine grading multiplier based on volume ratio
    double volRatio = 1.0;
    if (volumeConfirmationEngine != NULL)
      volRatio = volumeConfirmationEngine.GetVolumeRatio(0);

    // Map volRatio to grade index
    int grade = 0;
    for (int gi = 0; gi < ArraySize(cfg.gradeThresholds); gi++)
    {
      if (cfg.gradeThresholds[gi] > 0 && volRatio >= cfg.gradeThresholds[gi])
        grade = gi + 1; // grade 1..N
    }

    double gradeFactor = cfg.gradeFactors[0];
    if (grade >= 1 && grade < ArraySize(cfg.gradeFactors))
      gradeFactor = cfg.gradeFactors[grade];

    double desiredVolume = cfg.lotSize * gradeFactor;
    // Normalize to broker step
    double volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    if (volStep <= 0) volStep = 0.01;
    desiredVolume = MathMax(desiredVolume, volStep);
    desiredVolume = MathRound(desiredVolume / volStep) * volStep;
    req.volume = NormalizeDouble(desiredVolume, 2);
    req.type = ORDER_TYPE_BUY;
    req.price = ask;
    req.sl = orbLow;
    req.tp = fib1;
    req.deviation = (int)cfg.slippage;
    req.magic = cfg.magicNumber;

  if (OrderSend(req, res) && res.retcode == TRADE_RETCODE_DONE)
    {
      tradeCount++;
      Print("ORB Breakout BUY @ ", DoubleToString(req.price, _Digits),
            " | risk=", DoubleToString(risk, _Digits),
            " | volume=", DoubleToString(req.volume, 2));
      // Set trailing stop to orbHigh (breakout level), then trail to fib1 as price moves up, and to fib2 if price exceeds fib1
      double trailLevel = orbHigh;
      if (bid > fib1)
        trailLevel = fib1;
      if (bid > fib2)
        trailLevel = fib2;
      // Modify order to trail stop
      ulong ticket = res.order;
      if (ticket > 0)
      {
        MqlTradeRequest modReq;
        MqlTradeResult modRes;
        ZeroMemory(modReq);
        ZeroMemory(modRes);
        modReq.action = TRADE_ACTION_SLTP;
        modReq.order = ticket;
        modReq.sl = trailLevel;
        if (OrderSend(modReq, modRes))
          Print("Trailing stop for BUY set to ", DoubleToString(trailLevel, _Digits));
      }
    }
    else
    {
      Print("ORB Breakout BUY failed: retcode=", res.retcode);
    }
  }
  // ORB breakout SELL with volume confirmation and trade limit
  if (bid < orbLow && volumeConfirmed && tradeCount < 10)
  {
    MqlTradeRequest req;
    MqlTradeResult res;
    ZeroMemory(req);
    ZeroMemory(res);

    req.action = TRADE_ACTION_DEAL;
    req.symbol = _Symbol;
    // Determine grading multiplier based on volume ratio
    double volRatio = 1.0;
    if (volumeConfirmationEngine != NULL)
      volRatio = volumeConfirmationEngine.GetVolumeRatio(0);

    int grade = 0;
    for (int gi = 0; gi < ArraySize(cfg.gradeThresholds); gi++)
    {
      if (cfg.gradeThresholds[gi] > 0 && volRatio >= cfg.gradeThresholds[gi])
        grade = gi + 1;
    }

    double gradeFactor = cfg.gradeFactors[0];
    if (grade >= 1 && grade < ArraySize(cfg.gradeFactors))
      gradeFactor = cfg.gradeFactors[grade];

    double desiredVolume = cfg.lotSize * gradeFactor;
    double volStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
    if (volStep <= 0) volStep = 0.01;
    desiredVolume = MathMax(desiredVolume, volStep);
    desiredVolume = MathRound(desiredVolume / volStep) * volStep;
    req.volume = NormalizeDouble(desiredVolume, 2);
    req.type = ORDER_TYPE_SELL;
    req.price = bid;
    req.sl = orbHigh;
    req.tp = fib1Sell;
    req.deviation = (int)cfg.slippage;
    req.magic = cfg.magicNumber;

    if (OrderSend(req, res) && res.retcode == TRADE_RETCODE_DONE)
    {
      tradeCount++;
      Print("ORB Breakout SELL @ ", DoubleToString(req.price, _Digits),
            " | risk=", DoubleToString(risk, _Digits),
            " | volume=", DoubleToString(req.volume, 2));
      // Set trailing stop to orbLow (breakout level), then trail to fib1Sell as price moves down, and to fib2Sell if price exceeds fib1Sell
      double trailLevel = orbLow;
      if (bid < fib1Sell)
        trailLevel = fib1Sell;
      if (bid < fib2Sell)
        trailLevel = fib2Sell;
      // Modify order to trail stop
      ulong ticket = res.order;
      if (ticket > 0)
      {
        MqlTradeRequest modReq;
        MqlTradeResult modRes;
        ZeroMemory(modReq);
        ZeroMemory(modRes);
        modReq.action = TRADE_ACTION_SLTP;
        modReq.order = ticket;
        modReq.sl = trailLevel;
        if (OrderSend(modReq, modRes))
          Print("Trailing stop for SELL set to ", DoubleToString(trailLevel, _Digits));
      }
    }
    else
    {
      Print("ORB Breakout SELL failed: retcode=", res.retcode);
    }
  }
}

#endif
