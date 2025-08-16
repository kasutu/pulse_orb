//+------------------------------------------------------------------+
//|                                                        pulse.mq5 |
//|                                                       kasutufx |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "kasutufx"
#property link "https://www.mql5.com"
#property version "1.01"
#property description "Draw vertical line at 6AM NY time"

//--- Input Parameters
input int InpNYHour = 6;             // Target hour in New York time (24-hour format)
input int InpNYOffset = -4;          // NY offset from GMT (-4 for EDT, -5 for EST)
input double InpLineHeight = 1000.0; // Height of the vertical line in pips

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
  return (INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
  //--- Clean up all objects when EA is removed
  ObjectsDeleteAll(0, "VLine_");
  ChartRedraw();
}
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
  //--- Track last processed day to avoid duplicates
  static int lastProcessedDay = 0;

  //--- Get current GMT time and calculate NY time
  datetime currentGMT = TimeGMT();
  datetime currentNY = currentGMT + (InpNYOffset * 3600);

  MqlDateTime nyStruct;
  TimeToStruct(currentNY, nyStruct);

  //--- Exit if already processed today or before target hour
  if (lastProcessedDay == nyStruct.day_of_year || nyStruct.hour < InpNYHour)
    return;

  //--- Calculate target GMT time (6 AM NY converted to GMT)
  datetime targetGMT = currentGMT - (nyStruct.hour - InpNYHour) * 3600 - nyStruct.min * 60 - nyStruct.sec;

  //--- Find closest bar and get its data
  int barIndex = iBarShift(_Symbol, _Period, targetGMT, true);
  if (barIndex < 0)
    return;

  datetime barTime = iTime(_Symbol, _Period, barIndex);
  double barClose = iClose(_Symbol, _Period, barIndex);

  //--- Calculate pip value and line dimensions
  double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
  int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
  double pipValue = (digits == 3 || digits == 5) ? 10 * point : point;
  double heightInPrice = InpLineHeight * pipValue;

  //--- Create line object
  string objectName = "VLine_" + TimeToString(barTime, TIME_DATE);
  ObjectsDeleteAll(0, "VLine_"); // Remove old lines

  if (!ObjectCreate(0, objectName, OBJ_TREND, 0, barTime, barClose + heightInPrice / 2, barTime, barClose - heightInPrice / 2))
    return;

  //--- Set line properties
  ObjectSetInteger(0, objectName, OBJPROP_COLOR, clrDodgerBlue);
  ObjectSetInteger(0, objectName, OBJPROP_WIDTH, 2);
  ObjectSetInteger(0, objectName, OBJPROP_RAY_LEFT, false);
  ObjectSetInteger(0, objectName, OBJPROP_RAY_RIGHT, false);

  lastProcessedDay = nyStruct.day_of_year;
  ChartRedraw();
}
//+------------------------------------------------------------------+
