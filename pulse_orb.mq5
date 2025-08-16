//+------------------------------------------------------------------+
//|                                                        pulse.mq5 |
//|                                                       kasutufx |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "kasutufx"
#property link "https://www.mql5.com"
#property version "1.01"
#property description "Draw horizontal ORB lines based on configurable time range"

//--- Include dashboard
#include "Dashboard.mqh"

//--- Input Parameters
input int InpStartHour = 6;     // Start hour in local time (24-hour format)
input int InpTimeOffset = -4;   // Time offset from GMT (-4 for EDT, -5 for EST)
input int InpRangeMinutes = 15; // Minutes to calculate price range
input int InpEndHour = 17;      // End hour for horizontal lines (24-hour format)

//--- Object registry
string objectRegistry[];
int objectCount = 0;
const string EA_PREFIX = "ORB_"; // Prefix for all EA objects

//--- Dashboard instance
CDashboard *dashboard;

//+------------------------------------------------------------------+
//| Add object to registry                                           |
//+------------------------------------------------------------------+
void RegisterObject(string objectName)
{
  ArrayResize(objectRegistry, objectCount + 1);
  objectRegistry[objectCount] = objectName;
  objectCount++;
}

//+------------------------------------------------------------------+
//| Check if object exists in registry                               |
//+------------------------------------------------------------------+
bool ObjectExistsInRegistry(string objectName)
{
  for (int i = 0; i < objectCount; i++)
  {
    if (objectRegistry[i] == objectName)
      return true;
  }
  return false;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
  //--- Initialize dashboard
  dashboard = new CDashboard(EA_PREFIX);

  //--- Rebuild registry from existing objects on chart
  objectCount = 0;
  ArrayResize(objectRegistry, 0);

  int totalObjects = ObjectsTotal(0);
  for (int i = 0; i < totalObjects; i++)
  {
    string objName = ObjectName(0, i);
    if (StringFind(objName, EA_PREFIX) == 0)
    {
      RegisterObject(objName);
    }
  }

  return (INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
  //--- Clean up dashboard
  if (dashboard != NULL)
  {
    delete dashboard;
    dashboard = NULL;
  }

  //--- Clean up all registered objects when EA is removed
  for (int i = 0; i < objectCount; i++)
  {
    ObjectDelete(0, objectRegistry[i]);
  }
  ChartRedraw();
}
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
  //--- Track last processed day to avoid duplicates
  static int lastProcessedDay = 0;

  //--- Get current GMT time and calculate local time
  datetime currentGMT = TimeGMT();
  datetime currentLocal = currentGMT + (InpTimeOffset * 3600);

  MqlDateTime localStruct;
  TimeToStruct(currentLocal, localStruct);

  //--- Calculate next target time (today's or tomorrow's start hour)
  MqlDateTime todayTargetStruct = localStruct;
  todayTargetStruct.hour = InpStartHour;
  todayTargetStruct.min = 0;
  todayTargetStruct.sec = 0;
  datetime todayTarget = StructToTime(todayTargetStruct);

  //--- Update dashboard with ETA
  if (dashboard != NULL)
  {
    dashboard.UpdateETA(InpStartHour, InpEndHour, currentLocal, todayTarget);

    //--- Register ETA display if not already registered
    string etaObjectName = dashboard.GetETAObjectName();
    if (!ObjectExistsInRegistry(etaObjectName))
      RegisterObject(etaObjectName);
  }

  //--- Exit if already processed today or before target hour
  if (lastProcessedDay == localStruct.day_of_year || localStruct.hour < InpStartHour)
  {
    ChartRedraw();
    return;
  }

  //--- Calculate target GMT time (start hour converted to GMT)
  datetime targetGMT = currentGMT - (localStruct.hour - InpStartHour) * 3600 - localStruct.min * 60 - localStruct.sec;

  //--- Find closest bar and get its data
  int barIndex = iBarShift(_Symbol, _Period, targetGMT, true);
  if (barIndex < 0)
    return;

  datetime barTime = iTime(_Symbol, _Period, barIndex);

  //--- Calculate price range for the first X minutes from target time
  datetime rangeEndTime = barTime + (InpRangeMinutes * 60);
  double highestPrice = 0;
  double lowestPrice = 0;
  bool firstBar = true;

  //--- Find all bars within the time range and get high/low
  for (int i = barIndex; i >= 0; i--)
  {
    datetime currentBarTime = iTime(_Symbol, _Period, i);
    if (currentBarTime < barTime)
      break; // Stop if we go before target time
    if (currentBarTime > rangeEndTime)
      continue; // Skip if after range

    double high = iHigh(_Symbol, _Period, i);
    double low = iLow(_Symbol, _Period, i);

    if (firstBar)
    {
      highestPrice = high;
      lowestPrice = low;
      firstBar = false;
    }
    else
    {
      if (high > highestPrice)
        highestPrice = high;
      if (low < lowestPrice)
        lowestPrice = low;
    }
  }

  //--- Create horizontal line objects
  MqlDateTime endStruct = localStruct;
  endStruct.hour = InpEndHour;
  endStruct.min = 0;
  endStruct.sec = 0;
  datetime endLocalTime = StructToTime(endStruct);
  datetime lineEndTime = endLocalTime - (InpTimeOffset * 3600); // Convert local end time to GMT

  string highLineName = EA_PREFIX + "High_" + TimeToString(barTime, TIME_DATE);
  string lowLineName = EA_PREFIX + "Low_" + TimeToString(barTime, TIME_DATE);

  //--- Check if these lines already exist in registry
  if (ObjectExistsInRegistry(highLineName) || ObjectExistsInRegistry(lowLineName))
  {
    lastProcessedDay = localStruct.day_of_year;
    return;
  }

  //--- Create high horizontal line
  if (!ObjectCreate(0, highLineName, OBJ_TREND, 0, barTime, highestPrice, lineEndTime, highestPrice))
    return;

  //--- Set high line properties
  ObjectSetInteger(0, highLineName, OBJPROP_COLOR, clrBlue);
  ObjectSetInteger(0, highLineName, OBJPROP_WIDTH, 2);
  ObjectSetInteger(0, highLineName, OBJPROP_RAY_LEFT, false);
  ObjectSetInteger(0, highLineName, OBJPROP_RAY_RIGHT, false);
  ObjectSetInteger(0, highLineName, OBJPROP_STYLE, STYLE_SOLID);

  //--- Create low horizontal line
  if (!ObjectCreate(0, lowLineName, OBJ_TREND, 0, barTime, lowestPrice, lineEndTime, lowestPrice))
    return;

  //--- Set low line properties
  ObjectSetInteger(0, lowLineName, OBJPROP_COLOR, clrRed);
  ObjectSetInteger(0, lowLineName, OBJPROP_WIDTH, 2);
  ObjectSetInteger(0, lowLineName, OBJPROP_RAY_LEFT, false);
  ObjectSetInteger(0, lowLineName, OBJPROP_RAY_RIGHT, false);
  ObjectSetInteger(0, lowLineName, OBJPROP_STYLE, STYLE_SOLID);

  //--- Add to registry
  RegisterObject(highLineName);
  RegisterObject(lowLineName);

  lastProcessedDay = localStruct.day_of_year;
  ChartRedraw();
}
//+------------------------------------------------------------------+
