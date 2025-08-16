//+------------------------------------------------------------------+
//|                                                        pulse.mq5 |
//|                                                       kasutufx |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "kasutufx"
#property link "https://www.mql5.com"
#property version "1.01"
#property description "Pulse Based EA using ORB + volume, news confirmation"

//--- Include the standard library for trading functions and constants
#include <Trade/Trade.mqh>
//--- Utils: object ID registry helpers
#include "ObjectRegistry.mqh"

//--- Input Parameters
// This allows you to change the lookback period from the EA's settings window.
input int InpLookback = 10; // Number of bars to look back from the current bar.

//--- Global Constants
const string OBJECT_PREFIX = "PulseLine_"; // A unique prefix for objects created by this EA.
const double PIPS_HEIGHT = 100.0;          // The desired height of the line in pips.

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
  //--- Initialization is straightforward, no special setup needed.
  // Rebuild local registry in case objects with our prefix already exist
  RebuildRegistryFromChart(0, OBJECT_PREFIX);
  return (INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
  //--- Clean up all objects created by this EA when it's removed from the chart.
  ClearByPrefix(0, OBJECT_PREFIX);
  ChartRedraw();
}
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
  //--- Use a static variable to ensure the drawing logic runs only once per bar.
  static datetime lastBarTime = 0;

  //--- Check if a new bar has formed. If not, exit the function to save resources.
  datetime currentBarTime = iTime(_Symbol, _Period, 0);
  if (lastBarTime == currentBarTime)
  {
    return; // Not a new bar, so we do nothing.
  }
  //--- A new bar has formed, so we update our tracker.
  lastBarTime = currentBarTime;

  //--- Make sure there are enough bars on the chart to satisfy the lookback period.
  if (Bars(_Symbol, _Period) < InpLookback + 1)
  {
    Print("Not enough bars on the chart for the specified lookback of ", InpLookback);
    return;
  }

  //--- Calculate the actual monetary value of one pip for the current symbol.
  //    This handles both 3/5 and 2/4 digit brokers automatically.
  double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
  int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
  double pipValue = (digits == 3 || digits == 5) ? 10 * point : point;

  //--- Identify the target bar's index, time, and closing price.
  int targetBarIndex = InpLookback;
  datetime targetTime = iTime(_Symbol, _Period, targetBarIndex);
  double targetClose = iClose(_Symbol, _Period, targetBarIndex);

  //--- Calculate the top and bottom price points for the vertical line.
  //    It will be centered around the target bar's closing price.
  double priceTop = targetClose + (PIPS_HEIGHT / 2.0) * pipValue;
  double priceBottom = targetClose - (PIPS_HEIGHT / 2.0) * pipValue;

  //--- Create a unique name for our line object (KISS: prefix + time).
  string objectName = OBJECT_PREFIX + (string)targetTime;

  //--- To ensure only one line is on the chart, delete any old lines first.
  ClearByPrefix(0, OBJECT_PREFIX);

  //--- Create a finite vertical line using OBJ_TREND with start and end points.
  if (!ObjectCreate(0, objectName, OBJ_TREND, 0, targetTime, priceTop, targetTime, priceBottom))
  {
    Print("Error creating vertical line object: ", GetLastError());
    return;
  }

  //--- Customize the appearance of the line.
  ObjectSetInteger(0, objectName, OBJPROP_COLOR, clrDodgerBlue);   // Set line color.
  ObjectSetInteger(0, objectName, OBJPROP_WIDTH, 2);               // Set line thickness.
  ObjectSetInteger(0, objectName, OBJPROP_STYLE, STYLE_SOLID);     // Set line style.
  ObjectSetInteger(0, objectName, OBJPROP_RAY_LEFT, false);        // Disable ray extending to the left.
  ObjectSetInteger(0, objectName, OBJPROP_RAY_RIGHT, false);       // Disable ray extending to the right.
  ObjectSetString(0, objectName, OBJPROP_TOOLTIP, "Lookback Bar"); // Add a tooltip on hover.
                                                                   //--- Track in registry
  RegisterId(objectName);

  //--- Redraw the chart to make the new line visible immediately.
  ChartRedraw();
}
//+------------------------------------------------------------------+
