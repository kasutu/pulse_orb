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
#include "VolumeConfirmationEngine.mqh"
#include "ORBTradeEntry.mqh"

//--- entry settings
ORBSettings orbCfg = {0.1, 10, 12345, 6.0, PERIOD_M15};

//--- Input Parameters
input int InpStartHour = 5;      // Start hour in local time (24-hour format)
input int InpTimeOffset = 0;     // Time offset from local time (-4 for EDT, -5 for EST)
input int InpEndHour = 3;        // End hour for horizontal lines (24-hour format)
input int InpLookbackBars = 400; // Number of bars to look back for historical ORB ranges

//--- Object registry
string objectRegistry[];
int objectCount = 0;
const string EA_PREFIX = "ORB_"; // Prefix for all EA objects

//--- Dashboard instance
CDashboard *dashboard;

//--- Line drawer instance
CLineDrawer *lineDrawer;

VolumeConfirmationEngine *volumeConfirmationEngine;

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
  volumeConfirmationEngine = new VolumeConfirmationEngine();

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

  //--- Display timezone info on initialization
  if (dashboard != NULL)
  {
    dashboard.UpdateTimeZoneInfo(InpTimeOffset);

    string tzObjectName = EA_PREFIX + "TZ_Display"; // Use EA_PREFIX instead of m_prefix
    if (!ObjectExistsInRegistry(tzObjectName))
      RegisterObject(tzObjectName);
  }

  //--- Process historical ORB ranges
  ProcessORB::ProcessHistorical(InpLookbackBars, InpStartHour, InpEndHour, InpTimeOffset, lineDrawer);

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
  //--- Track 15-minute candle closes
  static datetime lastM15CandleTime = 0;

  //--- Get current local time
  datetime currentLocal = TimeEngine::GetLocal(InpTimeOffset);
  MqlDateTime localStruct;
  TimeEngine::ToStruct(currentLocal, localStruct);
  ORBTradeEntry(InpTimeOffset, EA_PREFIX, orbCfg);

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
    dashboard.UpdateTimeZoneInfo(InpTimeOffset);
    dashboard.UpdateVolumeConfirmation(volumeConfirmationEngine.GetVolumeComparisonString());

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

    Print("ORB Stage: 15-min candle closed at ", TimeToString(closedCandleTime));

    //--- Check if this should be processed
    if (ProcessORB::ShouldProcess(closedCandleTime, InpTimeOffset, InpStartHour))
    {
      Print("ORB Stage: Target candle detected - Processing ORB for ", TimeToString(closedCandleTime));

      // Get day of year for local time
      MqlDateTime localStruct;
      datetime localTime = TimeEngine::ApplyOffset(closedCandleTime, InpTimeOffset);
      TimeEngine::ToStruct(localTime, localStruct);

      ProcessORB::Process(closedCandleTime, localStruct.day_of_year, InpEndHour, InpTimeOffset, lineDrawer);
    }
  }

  ChartRedraw();
}