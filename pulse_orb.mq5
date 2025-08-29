//+------------------------------------------------------------------+
//| OHRB_15min_Simple.mq5                                           |
//| Back to basics: Original profitable logic + dynamic lots only   |
//| Removed all filters that destroyed the edge                     |
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>

input double RiskPercent = 1.0;         // Risk percentage per trade
input double RiskReward = 2.0;          // Simple fixed RR (what worked before)
input int StopBufferPoints = 10;        // Buffer beyond range for SL
input int Slippage = 10;                // Deviation in points
input bool AutoTrade = true;            // Allow trading
input int MagicNumber = 20250829;       // Magic number for EA trades
input string EAComment = "OHRB_Simple"; // Order comment

//--- Minimal risk controls only
input double MinLotSize = 0.01; // Minimum position size
input double MaxLotSize = 1.0;  // Maximum position size

//--- Global state (exactly like original)
datetime currentRangeHour = -1;
double rangeHigh = 0.0;
double rangeLow = 0.0;
bool recording = false;
bool rangeReady = false;
bool entryTaken = false;

CTrade trade;

// --------------------- Setup grading ---------------------
// Grade multipliers (tune these via backtest)
input double GradeA_Mult = 1.75; // strongest setups
input double GradeB_Mult = 1.25;
input double GradeC_Mult = 1.00; // baseline
input double GradeD_Mult = 0.50; // small size
input double GradeF_Mult = 0.00; // skip

input int ATRPeriod = 14;       // ATR used for grading
input int MaxSpreadPoints = 25; // used by grading
input int LondonOpen = 8;       // prime hour example
input int LondonClose = 10;
input int NYOpen = 13;
input int NYClose = 15;

// compute ATR (single-value read)
double GetATR(ENUM_TIMEFRAMES tf = PERIOD_M15)
{
  int handle = iATR(_Symbol, tf, ATRPeriod);
  if (handle == INVALID_HANDLE)
    return 0.0;
  double buf[];
  if (CopyBuffer(handle, 0, 0, 1, buf) <= 0)
  {
    IndicatorRelease(handle);
    return 0.0;
  }
  double v = buf[0];
  IndicatorRelease(handle);
  return v;
}

// is prime hour helper (reuse if present)
bool IsPrimeHour(int hour)
{
  return (hour >= LondonOpen && hour <= LondonClose) || (hour >= NYOpen && hour <= NYClose);
}

// Evaluate the breakout setup and return multiplier (and print grade info)
double EvaluateSetup(bool isLong, double entryPrice, double slPrice, int hour, double rangeHigh_local, double rangeLow_local)
{
  double Point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
  double Bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
  double Ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

  double atr = GetATR(PERIOD_M15);
  if (atr <= 0.0)
    atr = Point * 10.0; // safe fallback

  // metrics (in price units)
  double rangeSize = MathAbs(rangeHigh_local - rangeLow_local);
  double range_vs_atr = rangeSize / atr; // e.g. 1.0 means range == 1 ATR

  // breakout strength measured from the range edge into price beyond edge
  double breakoutDist = isLong ? (entryPrice - rangeHigh_local) : (rangeLow_local - entryPrice);
  double breakout_vs_atr = breakoutDist / atr; // small positive preferred

  // spread in points
  double spreadPoints = (Ask - Bid) / Point;

  // basic scoring (each block adds points)
  int score = 0;
  // range quality
  if (range_vs_atr >= 1.0)
    score += 2; // >=1 ATR is strong
  else if (range_vs_atr >= 0.5)
    score += 1; // medium

  // breakout momentum
  if (breakout_vs_atr >= 0.25)
    score += 2; // good momentum
  else if (breakout_vs_atr >= 0.05)
    score += 1;

  // spread quality
  if (spreadPoints <= (MaxSpreadPoints * 0.5))
    score += 1;
  else if (spreadPoints <= MaxSpreadPoints)
    score += 0;
  else
    score -= 1; // too wide, penalize

  // time bonus
  if (IsPrimeHour(hour))
    score += 1;

  // convert score to grade
  char grade = 'F';
  if (score >= 6)
    grade = 'A';
  else if (score >= 4)
    grade = 'B';
  else if (score >= 2)
    grade = 'C';
  else if (score >= 1)
    grade = 'D';
  else
    grade = 'F';

  double mult = GradeF_Mult;
  if (grade == 'A')
    mult = GradeA_Mult;
  else if (grade == 'B')
    mult = GradeB_Mult;
  else if (grade == 'C')
    mult = GradeC_Mult;
  else if (grade == 'D')
    mult = GradeD_Mult;
  else
    mult = GradeF_Mult;

  // Log a single-line summary so you can debug/backtest easily
  PrintFormat("GRADE %c: score=%d range/ATR=%.2f breakout/ATR=%.3f spreadPts=%.1f mult=%.2f",
              grade, score, range_vs_atr, breakout_vs_atr, spreadPoints, mult);

  return (mult);
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
  trade.SetExpertMagicNumber(MagicNumber);
  trade.SetDeviationInPoints(Slippage);
  Print("OHRB_Simple initialized. Risk=", DoubleToString(RiskPercent, 1), "% RR=", DoubleToString(RiskReward, 1));
  return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
  // Clean exit
}

//+------------------------------------------------------------------+
//| Calculate position size - ONLY dynamic element                  |
//+------------------------------------------------------------------+
double CalculatePositionSize(double entry, double sl)
{
  double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
  double Point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
  double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

  double stopDistance = MathAbs(entry - sl);
  double riskPerLot = (stopDistance / Point) * tickValue;

  if (riskPerLot <= 0)
    return MinLotSize;

  double riskAmount = accountBalance * (RiskPercent / 100.0);
  double lotSize = riskAmount / riskPerLot;

  // Apply basic limits
  lotSize = MathMax(MinLotSize, lotSize);
  lotSize = MathMin(MaxLotSize, lotSize);

  // Normalize to broker requirements
  double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
  if (lotStep <= 0)
    lotStep = 0.01;

  lotSize = NormalizeDouble(MathRound(lotSize / lotStep) * lotStep, 2);

  return MathMax(MinLotSize, lotSize);
}

//+------------------------------------------------------------------+
//| Check whether we already have a position opened by this EA       |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
  for (int i = 0; i < PositionsTotal(); i++)
  {
    if (PositionGetSymbol(i) == _Symbol)
    {
      if (PositionSelect(_Symbol))
      {
        long magic = (long)PositionGetInteger(POSITION_MAGIC);
        if (magic == MagicNumber)
          return true;
      }
    }
  }
  return false;
}

//+------------------------------------------------------------------+
//| Main tick handler - ORIGINAL LOGIC RESTORED                     |
//+------------------------------------------------------------------+
void OnTick()
{
  datetime now = TimeCurrent();
  MqlDateTime dt;
  TimeToStruct(now, dt);
  int h = dt.hour;
  int m = dt.min;

  double Bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
  double Ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
  double Point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

  // New hour: reset and start recording (ORIGINAL LOGIC)
  if ((datetime)h != currentRangeHour)
  {
    currentRangeHour = h;
    recording = true;
    rangeReady = false;
    entryTaken = false;
    rangeHigh = Bid;
    rangeLow = Bid;
    PrintFormat("New hour %d: Start 15-min range recording", h);
  }

  // While in first 15 minutes, update high/low (ORIGINAL LOGIC)
  if (recording && m < 15)
  {
    if (Bid > rangeHigh)
      rangeHigh = Bid;
    if (Bid < rangeLow)
      rangeLow = Bid;
    return;
  }

  // At minute 15+, finalize range (ORIGINAL LOGIC - NO FILTERS)
  if (recording && m >= 15)
  {
    recording = false;
    rangeReady = true;
    double rangePoints = (rangeHigh - rangeLow) / Point;
    PrintFormat("Range ready H%d: High=%.5f Low=%.5f Size=%.0fp",
                h, rangeHigh, rangeLow, rangePoints);
  }

  // Watch for breakouts (ORIGINAL SIMPLE LOGIC)
  if (rangeReady && !entryTaken)
  {
    // Skip if we already have a position
    if (HasOpenPosition())
    {
      entryTaken = true;
      return;
    }

    // LONG breakout - exactly like original
    if (Ask > rangeHigh)
    {
      if (AutoTrade)
      {
        double sl = rangeLow - StopBufferPoints * Point;
        double risk = Ask - sl;

        // Only check for reasonable risk (original had Point * 10)
        if (risk > Point * 10)
        {
          double lotSize = CalculatePositionSize(Ask, sl);
          double tp = Ask + risk * RiskReward;

          bool ok = trade.Buy(lotSize, NULL, 0, sl, tp, EAComment);
          PrintFormat("LONG H%d: Lots=%.2f Entry=%.5f SL=%.5f TP=%.5f Status=%s",
                      h, lotSize, Ask, sl, tp, ok ? "SUCCESS" : "FAILED");
          if (!ok)
            PrintFormat("Trade error: %d", GetLastError());
        }
        else
          PrintFormat("Risk too small: %.5f (min %.5f)", risk, Point * 10);
      }
      entryTaken = true;
      return;
    }

    // SHORT breakout - exactly like original
    if (Bid < rangeLow)
    {
      if (AutoTrade)
      {
        double sl = rangeHigh + StopBufferPoints * Point;
        double risk = sl - Bid;

        // Only check for reasonable risk (original had Point * 10)
        if (risk > Point * 10)
        {
          double lotSize = CalculatePositionSize(Bid, sl);
          double tp = Bid - risk * RiskReward;

          bool ok = trade.Sell(lotSize, NULL, 0, sl, tp, EAComment);
          PrintFormat("SHORT H%d: Lots=%.2f Entry=%.5f SL=%.5f TP=%.5f Status=%s",
                      h, lotSize, Bid, sl, tp, ok ? "SUCCESS" : "FAILED");
          if (!ok)
            PrintFormat("Trade error: %d", GetLastError());
        }
        else
          PrintFormat("Risk too small: %.5f (min %.5f)", risk, Point * 10);
      }
      entryTaken = true;
      return;
    }
  }
}

//+------------------------------------------------------------------+