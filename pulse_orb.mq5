//+------------------------------------------------------------------+
//|                                                        pulse.mq5 |
//|                                                       kasutufx |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "kasutufx"
#property link "https://www.mql5.com"
#property version "1.01"
#property description "Draw horizontal ORB lines based on 15-minute OHLC bar"

//--- Include dashboard
#include "Dashboard.mqh"
//--- Include line drawer
#include "LineDrawer.mqh"

//--- Input Parameters
input int InpStartHour = 6;   // Start hour in local time (24-hour format)
input int InpTimeOffset = -4; // Time offset from GMT (-4 for EDT, -5 for EST)
input int InpEndHour = 17;    // End hour for horizontal lines (24-hour format)

//--- Object registry
string objectRegistry[];
int objectCount = 0;
const string EA_PREFIX = "ORB_"; // Prefix for all EA objects

//--- Dashboard instance
CDashboard *dashboard;

//--- Line drawer instance
CLineDrawer *lineDrawer;

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

  //--- Initialize line drawer
  lineDrawer = new CLineDrawer(EA_PREFIX);

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

  //--- Clean up line drawer
  if (lineDrawer != NULL)
  {
    delete lineDrawer;
    lineDrawer = NULL;
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
    dashboard.UpdateETA(todayTarget, currentLocal);

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

  Print("ORB Debug - Current GMT: ", TimeToString(currentGMT),
        " Current Local: ", TimeToString(currentLocal),
        " Target GMT: ", TimeToString(targetGMT));

  //--- Find closest bar and get its data
  int barIndex = iBarShift(_Symbol, _Period, targetGMT, true);
  if (barIndex < 0)
  {
    Print("ERROR: Could not find bar for target time: ", TimeToString(targetGMT));
    return;
  }

  datetime barTime = iTime(_Symbol, _Period, barIndex);
  Print("ORB Debug - Found bar at index ", barIndex, " with time: ", TimeToString(barTime));

  //--- Get OHLC of the 15-minute bar
  double highestPrice = iHigh(_Symbol, _Period, barIndex);
  double lowestPrice = iLow(_Symbol, _Period, barIndex);
  double openPrice = iOpen(_Symbol, _Period, barIndex);
  double closePrice = iClose(_Symbol, _Period, barIndex);

  Print("ORB Debug - 15min OHLC: Open=", DoubleToString(openPrice, _Digits),
        " High=", DoubleToString(highestPrice, _Digits),
        " Low=", DoubleToString(lowestPrice, _Digits),
        " Close=", DoubleToString(closePrice, _Digits));

  //--- Create horizontal line objects
  MqlDateTime endStruct = localStruct;
  endStruct.hour = InpEndHour;
  endStruct.min = 0;
  endStruct.sec = 0;
  datetime endLocalTime = StructToTime(endStruct);
  datetime lineEndTime = endLocalTime - (InpTimeOffset * 3600); // Convert local end time to GMT

  //--- Check if lines already exist using line drawer
  if (lineDrawer != NULL && lineDrawer.LinesExist(barTime))
  {
    lastProcessedDay = localStruct.day_of_year;
    return;
  }

  //--- Use line drawer to create ORB lines
  if (lineDrawer != NULL)
  {
    if (lineDrawer.DrawLines(barTime, highestPrice, lowestPrice, lineEndTime))
    {
      lastProcessedDay = localStruct.day_of_year;
    }
  }

  ChartRedraw();
}
//+------------------------------------------------------------------+
