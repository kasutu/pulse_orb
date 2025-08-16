//+------------------------------------------------------------------+
//|                                                        pulse.mq5 |
//|                                                       kasutufx |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "kasutufx"
#property link "https://www.mql5.com"
#property version "1.01"
#property description "Draw horizontal ORB lines based on 15-minute OHLC bar"

#include "Dashboard.mqh"
#include "LineDrawer.mqh"
#include "TimeEngine.mqh"
#include "ProcessORB.mqh"

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

  //--- Track 15-minute candle closes
  static datetime lastM15CandleTime = 0;

  //--- Get current GMT and local time using TimeEngine
  datetime currentGMT = TimeEngine::GetGMT();
  datetime currentLocal = TimeEngine::GetLocal(InpTimeOffset);
  MqlDateTime gmtStruct, localStruct;
  TimeEngine::ToStruct(currentGMT, gmtStruct);
  TimeEngine::ToStruct(currentLocal, localStruct);

  //--- Reset lastProcessedDay when InpEndHour is reached
  if (localStruct.hour >= InpEndHour && localStruct.hour < InpStartHour)
  {
    lastProcessedDay = 0;
  }

  //--- Calculate next target time (today's or tomorrow's start hour)
  MqlDateTime todayTargetStruct = localStruct;
  todayTargetStruct.hour = InpStartHour;
  todayTargetStruct.min = 0;
  todayTargetStruct.sec = 0;
  datetime todayTarget = StructToTime(todayTargetStruct);

  //--- Update dashboard with ETA
  if (dashboard != NULL)
  {
    dashboard.UpdateETA(todayTarget, currentGMT);
    dashboard.UpdateTimeZoneInfo(InpTimeOffset);

    //--- Register ETA display if not already registered
    string etaObjectName = dashboard.GetETAObjectName();
    if (!ObjectExistsInRegistry(etaObjectName))
      RegisterObject(etaObjectName);
  }

  //--- Check for new 15-minute candle close
  datetime currentM15CandleTime = TimeEngine::BarOpen(_Symbol, PERIOD_M15, 0);
  bool newM15Candle = (currentM15CandleTime != lastM15CandleTime);

  if (newM15Candle)
  {
    lastM15CandleTime = currentM15CandleTime;

    //--- Get the time of the just-closed candle (bar index 1)
    datetime closedCandleTime = TimeEngine::BarOpen(_Symbol, PERIOD_M15, 1);
    MqlDateTime closedCandleStruct;
    TimeEngine::ToStruct(closedCandleTime, closedCandleStruct); // Use GMT/UTC

    Print("ORB Stage: 15-min candle closed at ", TimeToString(closedCandleTime), " GMT - Hour: ", closedCandleStruct.hour,
          " Min: ", closedCandleStruct.min);

    //--- Check if this is the target candle (starts at InpStartHour:00 UTC)
    if (closedCandleStruct.hour == InpStartHour && closedCandleStruct.min == 0 &&
        lastProcessedDay != closedCandleStruct.day_of_year)
    {
      Print("ORB Stage: Target candle detected at UTC - Processing ORB for ", TimeToString(closedCandleTime));
  ProcessORB(closedCandleTime, closedCandleStruct.day_of_year, InpEndHour, InpTimeOffset, lineDrawer);
    }
  }

  ChartRedraw();
}
