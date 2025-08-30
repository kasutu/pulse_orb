//+------------------------------------------------------------------+
//| OHRB_15min_Graded_Trading.mq5                                    |
//| Grader + adaptive spread + ATR SL buffer + Grade C/D controls    |
//+------------------------------------------------------------------+
#property strict
#include <Trade\Trade.mqh>
CTrade trade;

//---------------------- Inputs --------------------------------------
input bool AutoTrade = true;           // allow live/backtest trading
input double BaseRiskPercent = 0.25;   // LOW DEFAULT for $20 micro accounts
input double MaxRiskPercent = 1.0;     // maximum allowed per-trade risk (%)
input double RiskReward_default = 2.0; // default RR for non-A grades
input int StopBufferPoints = 10;       // buffer beyond range for SL (points) - baseline
input double SL_ATR_FACTOR = 0.20;     // SL at least ATR * this fractional amount
input int ATRPeriod = 14;              // ATR for grading & management
input double GradeA_Mult = 1.75;
input double GradeB_Mult = 1.25;
input double GradeC_Mult = 1.00;
input double GradeD_Mult = 0.50;
input double GradeF_Mult = 0.00;
input int MaxSpreadPoints = 25;            // baseline - auto-adapted for large-spread symbols
input double SpreadMultiplier = 3.0;       // tolerated multiple of typical spread when deciding
input bool AllowGradeCOutsidePrime = true; // allow Grade C outside prime sessions?
input bool AllowGradeD = false;            // allow Grade D trades (default off)
input int LondonOpen = 8;
input int LondonClose = 10;
input int NYOpen = 13;
input int NYClose = 15;
input double EquityStopLevel = 10.0; // stop trading entirely under this equity
input int Slippage = 10;
input int MagicNumber = 20250829;
input string EAComment = "OHRB_15m_Graded_Trading_v1";

//--- Range capture globals
int currentRangeHour = -1;
double rangeHigh = 0.0;
double rangeLow = 0.0;
bool recording = false;
bool rangeReady = false;
bool entryTaken = false;

// management state
long managedTicket = -1;
double entryATR = 0.0;
double maxEquity = 0.0;
bool tradingStopped = false;

//---------------------- Utility: ATR (single-value) -----------------
double GetATR(ENUM_TIMEFRAMES tf = PERIOD_M15)
{
  int handle = iATR(_Symbol, tf, ATRPeriod);
  if (handle == INVALID_HANDLE)
    return (SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10.0);
  double buf[];
  if (CopyBuffer(handle, 0, 0, 1, buf) <= 0)
  {
    IndicatorRelease(handle);
    return (SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10.0);
  }
  double v = buf[0];
  IndicatorRelease(handle);
  if (v <= 0.0)
    return (SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10.0);
  return v;
}

//---------------------- Real grader (your logic) --------------------
bool IsPrimeHour(int hour)
{
  return (hour >= LondonOpen && hour <= LondonClose) || (hour >= NYOpen && hour <= NYClose);
}

double EvaluateSetup(bool isLong, double entryPrice, double slPrice, int hour, double rangeHigh_local, double rangeLow_local)
{
  double Point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
  double Bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
  double Ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

  double atr = GetATR(PERIOD_M15);
  if (atr <= 0.0)
    atr = Point * 10.0; // fallback

  double rangeSize = MathAbs(rangeHigh_local - rangeLow_local);
  double range_vs_atr = rangeSize / atr;

  double breakoutDist = isLong ? (entryPrice - rangeHigh_local) : (rangeLow_local - entryPrice);
  double breakout_vs_atr = breakoutDist / atr;

  double spreadPoints = (Ask - Bid) / Point;

  int score = 0;
  if (range_vs_atr >= 1.0)
    score += 2;
  else if (range_vs_atr >= 0.5)
    score += 1;

  if (breakout_vs_atr >= 0.25)
    score += 2;
  else if (breakout_vs_atr >= 0.05)
    score += 1;

  if (spreadPoints <= (MaxSpreadPoints * 0.5))
    score += 1;
  else if (spreadPoints <= MaxSpreadPoints)
    score += 0;
  else
    score -= 1;

  if (IsPrimeHour(hour))
    score += 1;

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

  PrintFormat("GRADE %c: score=%d range/ATR=%.2f breakout/ATR=%.3f spreadPts=%.1f mult=%.2f",
              grade, score, range_vs_atr, breakout_vs_atr, spreadPoints, mult);

  return mult;
}
char GradeFromMult(double mult)
{
  if (mult == GradeA_Mult)
    return 'A';
  if (mult == GradeB_Mult)
    return 'B';
  if (mult == GradeC_Mult)
    return 'C';
  if (mult == GradeD_Mult)
    return 'D';
  return 'F';
}

//---------------------- Helpers: adaptive spread & SL ----------------
double GetTypicalSpreadPoints()
{
  double Point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
  long sp = (long)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
  if (sp > 0)
    return (double)sp;
  double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
  double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
  if (Point <= 0.0)
    return 99999.0;
  return (ask - bid) / Point;
}

double EffectiveMaxSpread()
{
  double typ = GetTypicalSpreadPoints();
  double eff = MathMax((double)MaxSpreadPoints, typ * SpreadMultiplier);
  return eff;
}

double ComputeSLBufferPrice(double point, double atr)
{
  double a = atr * SL_ATR_FACTOR;      // ATR-based buffer (price units)
  double b = StopBufferPoints * point; // fixed point buffer
  return MathMax(a, b);
}

//---------------------- Position helpers ----------------------------
bool GetOurOpenPositionTicket(long &ticket_out)
{
  ticket_out = -1;
  int total = PositionsTotal();
  for (int i = 0; i < total; i++)
  {
    ulong t = PositionGetTicket(i);
    if (t == 0)
      continue;
    if (!PositionSelectByTicket(t))
      continue;
    string sym = PositionGetString(POSITION_SYMBOL);
    if (sym != _Symbol)
      continue;
    long magic = (long)PositionGetInteger(POSITION_MAGIC);
    if (magic != MagicNumber)
      continue;
    ticket_out = (long)t;
    return true;
  }
  return false;
}

void ClosePositionWithReason(ulong ticket, string reason)
{
  if (!PositionSelectByTicket(ticket))
    return;
  double profit = PositionGetDouble(POSITION_PROFIT);
  bool ok = trade.PositionClose(ticket);
  double equity = AccountInfoDouble(ACCOUNT_EQUITY);
  double drawdown = (maxEquity > 0) ? (maxEquity - equity) / maxEquity * 100.0 : 0.0;
  PrintFormat("Closed Ticket=%d Profit=%.2f Equity=%.2f Drawdown=%.2f%% Reason=%s", ticket, profit, equity, drawdown, reason);
}

//---------------------- Sizing -------------------------------------
double CalculateBaseLot(double entry, double sl)
{
  double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
  double Point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
  double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

  double stopDistance = MathAbs(entry - sl);
  double riskPerLot = 0.0;
  if (tickValue > 0.0)
    riskPerLot = (stopDistance / Point) * tickValue;
  else
  {
    double contract = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
    if (contract > 0.0)
      riskPerLot = contract * Point;
  }
  if (riskPerLot <= 0.0)
    return (SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));

  double riskAmount = accountBalance * (BaseRiskPercent / 100.0);
  double lotSize = riskAmount / riskPerLot;

  double lotMin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
  double lotMax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
  double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
  if (lotStep <= 0)
    lotStep = 0.01;

  if (lotSize < lotMin)
    lotSize = lotMin;
  if (lotSize > lotMax)
    lotSize = lotMax;

  long steps = (long)(lotSize / lotStep);
  if (steps < 1)
    steps = 1;
  double result = steps * lotStep;
  return NormalizeDouble(result, 2);
}

//---------------------- Manage open position (smart exits) ----------
void ManageOpenPosition()
{
  long t;
  if (!GetOurOpenPositionTicket(t))
  {
    managedTicket = -1;
    return;
  }
  managedTicket = t;
  if (!PositionSelectByTicket((ulong)managedTicket))
  {
    managedTicket = -1;
    return;
  }

  double Point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
  double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
  double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
  double price_open = PositionGetDouble(POSITION_PRICE_OPEN);
  double current_sl = PositionGetDouble(POSITION_SL);
  double current_tp = PositionGetDouble(POSITION_TP);
  double volume = PositionGetDouble(POSITION_VOLUME);
  long type = PositionGetInteger(POSITION_TYPE);

  double profit = PositionGetDouble(POSITION_PROFIT);
  double equity = AccountInfoDouble(ACCOUNT_EQUITY);
  double profitPoints = (type == POSITION_TYPE_BUY) ? (bid - price_open) / Point : (price_open - ask) / Point;

  // small profit (>0.2% equity) outside prime -> close
  if ((profit / equity) > 0.002)
  {
    MqlDateTime _tm;
    TimeToStruct(TimeCurrent(), _tm);
    if (!IsPrimeHour(_tm.hour))
    {
      ClosePositionWithReason((ulong)managedTicket, "SmallProfit_OutsidePrime");
      return;
    }
  }

  // spread spike exit (use effective max)
  double spreadPts = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) - SymbolInfoDouble(_Symbol, SYMBOL_BID)) / Point;
  double effMaxSpread = EffectiveMaxSpread();
  if (spreadPts > effMaxSpread)
  {
    ClosePositionWithReason((ulong)managedTicket, "SpreadSpike");
    return;
  }

  // ATR collapse exit
  double currATR = GetATR(PERIOD_M15);
  if (entryATR > 0 && currATR > 0 && currATR < entryATR * 0.7)
  {
    ClosePositionWithReason((ulong)managedTicket, "ATR_Collapse");
    return;
  }
  // else keep position running (TP/SL will close it)
}

//---------------------- Init & suggested presets --------------------
void PrintSuggestedPresets()
{
  Print("Suggested presets for $20 micro-account:");
  Print("Conservative: BaseRiskPercent=0.25, GradeA_Mult=1.5, GradeB_Mult=1.0, GradeC_Mult=0.75");
  Print("Balanced:     BaseRiskPercent=0.4,  GradeA_Mult=1.75, GradeB_Mult=1.25, GradeC_Mult=1.0");
  Print("Aggressive:   BaseRiskPercent=0.6,  GradeA_Mult=2.0,  GradeB_Mult=1.5,  GradeC_Mult=1.25 (NOT recommended for $20)");
}

int OnInit()
{
  trade.SetExpertMagicNumber(MagicNumber);
  trade.SetDeviationInPoints(Slippage);
  maxEquity = AccountInfoDouble(ACCOUNT_EQUITY);

  // Pre-flight checklist
  PrintFormat("OHRB_15m_Graded_Trading initialized. AutoTrade=%s BaseRisk%%=%.2f Equity=%.2f",
              AutoTrade ? "true" : "false", BaseRiskPercent, maxEquity);
  PrintFormat("AllowGradeCOutsidePrime=%s AllowGradeD=%s SpreadMultiplier=%.2f",
              AllowGradeCOutsidePrime ? "true" : "false", AllowGradeD ? "true" : "false", SpreadMultiplier);
  PrintSuggestedPresets();
  return (INIT_SUCCEEDED);
}

void OnDeinit(const int reason) { /* nothing */ }

//---------------------- Main tick -----------------------------------
void OnTick()
{
  // update peak equity
  double equity = AccountInfoDouble(ACCOUNT_EQUITY);
  if (equity > maxEquity)
    maxEquity = equity;
  if (equity < EquityStopLevel)
  {
    if (!tradingStopped)
    {
      tradingStopped = true;
      PrintFormat("Equity %.2f < EquityStopLevel %.2f -> trading halted", equity, EquityStopLevel);
    }
    return;
  }

  // manage existing position first
  ManageOpenPosition();
  if (managedTicket > 0)
    return; // one position at a time

  // range capture
  MqlDateTime tm;
  TimeToStruct(TimeCurrent(), tm);
  int h = tm.hour;
  int m = tm.min;
  double Bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
  double Ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
  double Point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

  if (h != currentRangeHour)
  {
    currentRangeHour = h;
    recording = true;
    rangeReady = false;
    entryTaken = false;
    rangeHigh = Bid;
    rangeLow = Bid;
    PrintFormat("New hour %d: start 15-min range recording (min=%d)", h, m);
  }
  if (recording && m < 15)
  {
    if (Bid > rangeHigh)
      rangeHigh = Bid;
    if (Bid < rangeLow)
      rangeLow = Bid;
    return;
  }
  if (recording && m >= 15)
  {
    recording = false;
    rangeReady = true;
    double rangePoints = (rangeHigh - rangeLow) / Point;
    PrintFormat("Range ready H%d High=%.5f Low=%.5f Size=%.0fp", h, rangeHigh, rangeLow, rangePoints);
  }

  // entry logic
  if (rangeReady && !entryTaken)
  {
    double typSpread = GetTypicalSpreadPoints();
    double effMaxSpread = EffectiveMaxSpread();
    PrintFormat("TypicalSpread=%.1f pts EffMaxSpread=%.1f pts (configured MaxSpread=%d, multiplier=%.2f)",
                typSpread, effMaxSpread, MaxSpreadPoints, SpreadMultiplier);

    // LONG breakout
    if (Ask > rangeHigh)
    {
      double atr = GetATR(PERIOD_M15);
      double slBufferPrice = ComputeSLBufferPrice(Point, atr); // price units
      double sl = rangeLow - slBufferPrice;
      double risk = Ask - sl;
      if (risk <= Point * 10)
      {
        Print("Risk too small for long");
        entryTaken = true;
        return;
      }

      double mult = EvaluateSetup(true, Ask, sl, h, rangeHigh, rangeLow);
      char grade = GradeFromMult(mult);
      if (grade == 'F')
      {
        PrintFormat("Skipped long grade=%c", grade);
        entryTaken = true;
        return;
      }
      if (grade == 'D' && !AllowGradeD)
      {
        PrintFormat("Skipped long grade=D (low quality)");
        entryTaken = true;
        return;
      }

      // session rule: allow A anytime; B only in prime; C optionally outside prime
      if (grade == 'B' && !IsPrimeHour(h))
      {
        Print("Grade B outside prime -> skip");
        entryTaken = true;
        return;
      }
      if (grade == 'C' && !IsPrimeHour(h) && !AllowGradeCOutsidePrime)
      {
        Print("Grade C outside prime and AllowGradeCOutsidePrime=false -> skip");
        entryTaken = true;
        return;
      }

      // spread check
      double spreadPts = (Ask - Bid) / Point;
      if (spreadPts > effMaxSpread)
      {
        PrintFormat("Skipping: spread %.1f pts > effectiveMax %.1f pts", spreadPts, effMaxSpread);
        entryTaken = true;
        return;
      }

      double rr = (grade == 'A') ? 6.0 : 2.0;

      double baseLot = CalculateBaseLot(Ask, sl);

      // grade multiplier and A-grade scaled risk option
      double finalLot = baseLot * mult;
      if (grade == 'A' && MaxRiskPercent > BaseRiskPercent)
      {
        double riskScale = MaxRiskPercent / BaseRiskPercent;
        finalLot = finalLot * MathMin(riskScale, 2.0);
      }

      double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      if (lotStep <= 0)
        lotStep = 0.01;
      long steps = (long)(finalLot / lotStep);
      if (steps < 1)
        steps = 1;
      finalLot = steps * lotStep;
      finalLot = MathMax(finalLot, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));
      finalLot = MathMin(finalLot, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX));

      double tp = Ask + (Ask - sl) * rr;

      PrintFormat("[CANDIDATE] LONG Grade=%c mult=%.2f baseLot=%.2f finalLot=%.2f SL=%.5f TP=%.5f RR=%.2f ATR=%.5f spread=%.1f effMaxSpread=%.1f",
                  grade, mult, baseLot, finalLot, sl, tp, rr, GetATR(PERIOD_M15), (Ask - Bid) / Point, effMaxSpread);

      if (AutoTrade)
      {
        bool ok = trade.Buy(finalLot, NULL, 0.0, sl, tp, EAComment);
        if (ok)
        {
          PrintFormat("LONG ENTER Grade=%c mult=%.2f lot=%.2f sl=%.5f tp=%.5f rr=%.2f", grade, mult, finalLot, sl, tp, rr);
          entryATR = GetATR(PERIOD_M15);
          entryTaken = true;
          long t;
          if (GetOurOpenPositionTicket(t))
            managedTicket = t;
        }
        else
          PrintFormat("LONG order failed err=%d", GetLastError());
      }
      entryTaken = true;
      return;
    }

    // SHORT breakout
    if (Bid < rangeLow)
    {
      double atr = GetATR(PERIOD_M15);
      double slBufferPrice = ComputeSLBufferPrice(Point, atr);
      double sl = rangeHigh + slBufferPrice;
      double risk = sl - Bid;
      if (risk <= Point * 10)
      {
        Print("Risk too small for short");
        entryTaken = true;
        return;
      }

      double mult = EvaluateSetup(false, Bid, sl, h, rangeHigh, rangeLow);
      char grade = GradeFromMult(mult);
      if (grade == 'F')
      {
        PrintFormat("Skipped short grade=%c", grade);
        entryTaken = true;
        return;
      }
      if (grade == 'D' && !AllowGradeD)
      {
        PrintFormat("Skipped short grade=D (low quality)");
        entryTaken = true;
        return;
      }

      if (grade == 'B' && !IsPrimeHour(h))
      {
        Print("Grade B outside prime -> skip");
        entryTaken = true;
        return;
      }
      if (grade == 'C' && !IsPrimeHour(h) && !AllowGradeCOutsidePrime)
      {
        Print("Grade C outside prime and AllowGradeCOutsidePrime=false -> skip");
        entryTaken = true;
        return;
      }

      double spreadPts = (Ask - Bid) / Point;
      double effMaxSpread2 = EffectiveMaxSpread();
      if (spreadPts > effMaxSpread2)
      {
        PrintFormat("Skipping: spread %.1f pts > effectiveMax %.1f pts", spreadPts, effMaxSpread2);
        entryTaken = true;
        return;
      }

      double rr = (grade == 'A') ? 6.0 : 2.0;
      double baseLot = CalculateBaseLot(Bid, sl);

      double finalLot = baseLot * mult;
      if (grade == 'A' && MaxRiskPercent > BaseRiskPercent)
      {
        double riskScale = MaxRiskPercent / BaseRiskPercent;
        finalLot = finalLot * MathMin(riskScale, 2.0);
      }

      double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
      if (lotStep <= 0)
        lotStep = 0.01;
      long steps = (long)(finalLot / lotStep);
      if (steps < 1)
        steps = 1;
      finalLot = steps * lotStep;
      finalLot = MathMax(finalLot, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));
      finalLot = MathMin(finalLot, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX));

      double tp = Bid - (sl - Bid) * rr;

      PrintFormat("[CANDIDATE] SHORT Grade=%c mult=%.2f baseLot=%.2f finalLot=%.2f SL=%.5f TP=%.5f RR=%.2f ATR=%.5f spread=%.1f effMaxSpread=%.1f",
                  grade, mult, baseLot, finalLot, sl, tp, rr, GetATR(PERIOD_M15), (Ask - Bid) / Point, effMaxSpread2);

      if (AutoTrade)
      {
        bool ok = trade.Sell(finalLot, NULL, 0.0, sl, tp, EAComment);
        if (ok)
        {
          PrintFormat("SHORT ENTER Grade=%c mult=%.2f lot=%.2f sl=%.5f tp=%.5f rr=%.2f", grade, mult, finalLot, sl, tp, rr);
          entryATR = GetATR(PERIOD_M15);
          entryTaken = true;
          long t;
          if (GetOurOpenPositionTicket(t))
            managedTicket = t;
        }
        else
          PrintFormat("SHORT order failed err=%d", GetLastError());
      }
      entryTaken = true;
      return;
    }
  }
}
//+------------------------------------------------------------------+
