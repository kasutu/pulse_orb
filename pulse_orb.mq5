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
input int InpNYHour = 6;        // Target hour in New York time (24-hour format)
input int InpNYOffset = -4;     // NY offset from GMT (-4 for EDT, -5 for EST)
input int InpRangeMinutes = 15; // Minutes to calculate price range for line height

//--- Object registry
string objectRegistry[];
int objectCount = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
  //--- Rebuild registry from existing objects on chart
  objectCount = 0;
  ArrayResize(objectRegistry, 0);

  int totalObjects = ObjectsTotal(0);
  for (int i = 0; i < totalObjects; i++)
  {
    string objName = ObjectName(0, i);
    if (StringFind(objName, "VLine_") == 0)
    {
      ArrayResize(objectRegistry, objectCount + 1);
      objectRegistry[objectCount] = objName;
      objectCount++;
    }
  }

  return (INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
  //--- Clean up all registered objects when EA is removed
  for (int i = 0; i < objectCount; i++)
  {
    ObjectDelete(0, objectRegistry[i]);
  }
  //--- Remove ETA display
  ObjectDelete(0, "ETA_Display");
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

  //--- Calculate next target time (today's or tomorrow's 6 AM NY)
  datetime nextTargetNY = currentNY;
  MqlDateTime targetStruct = nyStruct;
  targetStruct.hour = InpNYHour;
  targetStruct.min = 0;
  targetStruct.sec = 0;

  if (nyStruct.hour >= InpNYHour) // If past today's target, use tomorrow
  {
    nextTargetNY += 24 * 3600; // Add 24 hours
    TimeToStruct(nextTargetNY, targetStruct);
    targetStruct.hour = InpNYHour;
    targetStruct.min = 0;
    targetStruct.sec = 0;
  }

  nextTargetNY = StructToTime(targetStruct);

  //--- Calculate and display ETA
  int etaSeconds = (int)(nextTargetNY - currentNY);
  int etaHours = etaSeconds / 3600;
  int etaMinutes = (etaSeconds % 3600) / 60;
  etaSeconds = etaSeconds % 60;

  string etaText = StringFormat("ETA to %dAM NY: %02d:%02d:%02d", InpNYHour, etaHours, etaMinutes, etaSeconds);

  //--- Create or update ETA display
  if (!ObjectCreate(0, "ETA_Display", OBJ_LABEL, 0, 0, 0))
  {
    ObjectSetString(0, "ETA_Display", OBJPROP_TEXT, etaText);
  }
  else
  {
    ObjectSetString(0, "ETA_Display", OBJPROP_TEXT, etaText);
    ObjectSetInteger(0, "ETA_Display", OBJPROP_CORNER, CORNER_LEFT_LOWER);
    ObjectSetInteger(0, "ETA_Display", OBJPROP_XDISTANCE, 10);
    ObjectSetInteger(0, "ETA_Display", OBJPROP_YDISTANCE, 30);
    ObjectSetInteger(0, "ETA_Display", OBJPROP_COLOR, clrYellow);
    ObjectSetInteger(0, "ETA_Display", OBJPROP_FONTSIZE, 12);
  }

  //--- Exit if already processed today or before target hour
  if (lastProcessedDay == nyStruct.day_of_year || nyStruct.hour < InpNYHour)
  {
    ChartRedraw();
    return;
  }

  //--- Calculate target GMT time (6 AM NY converted to GMT)
  datetime targetGMT = currentGMT - (nyStruct.hour - InpNYHour) * 3600 - nyStruct.min * 60 - nyStruct.sec;

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

  //--- Create line object
  string objectName = "VLine_" + TimeToString(barTime, TIME_DATE);

  //--- Check if this line already exists
  bool lineExists = false;
  for (int i = 0; i < objectCount; i++)
  {
    if (objectRegistry[i] == objectName)
    {
      lineExists = true;
      break;
    }
  }

  if (lineExists)
  {
    lastProcessedDay = nyStruct.day_of_year;
    return;
  }

  if (!ObjectCreate(0, objectName, OBJ_TREND, 0, barTime, highestPrice, barTime, lowestPrice))
    return;

  //--- Set line properties
  ObjectSetInteger(0, objectName, OBJPROP_COLOR, clrDodgerBlue);
  ObjectSetInteger(0, objectName, OBJPROP_WIDTH, 2);
  ObjectSetInteger(0, objectName, OBJPROP_RAY_LEFT, false);
  ObjectSetInteger(0, objectName, OBJPROP_RAY_RIGHT, false);

  //--- Add to registry
  ArrayResize(objectRegistry, objectCount + 1);
  objectRegistry[objectCount] = objectName;
  objectCount++;

  lastProcessedDay = nyStruct.day_of_year;
  ChartRedraw();
}
//+------------------------------------------------------------------+
