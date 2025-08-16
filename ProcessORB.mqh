//+------------------------------------------------------------------+
//|                    ProcessORB.mqh                                |
//|   Extracted from pulse_orb.mq5 for modularity                   |
//+------------------------------------------------------------------+
#include "TimeEngine.mqh"
#include "LineDrawer.mqh"

void ProcessORB(datetime candleTime, int dayOfYear, int endHour, int timeOffset, CLineDrawer *drawer)
{
  static int lastProcessedDay = 0;

  //--- Get current local time for line end calculation
  datetime currentLocal = TimeEngine::GetLocal(timeOffset);
  MqlDateTime localStruct;
  TimeEngine::ToStruct(currentLocal, localStruct);

  //--- Find the closed 15-minute bar and get its data
  int barIndex = iBarShift(_Symbol, PERIOD_M15, candleTime, true);
  if (barIndex < 0)
  {
    Print("ERROR: Could not find 15-minute bar for candle time: ", TimeToString(candleTime));
    return;
  }

  datetime barTime = iTime(_Symbol, PERIOD_M15, barIndex);
  Print("ORB Stage: Target 15-min bar located at index ", barIndex, " - Next: Extract OHLC data from closed candle at ", TimeToString(barTime));

  //--- Get OHLC of the closed 15-minute bar
  double highestPrice = iHigh(_Symbol, PERIOD_M15, barIndex);
  double lowestPrice = iLow(_Symbol, PERIOD_M15, barIndex);
  double openPrice = iOpen(_Symbol, PERIOD_M15, barIndex);
  double closePrice = iClose(_Symbol, PERIOD_M15, barIndex);

  //--- Create horizontal line objects
  MqlDateTime endStruct = localStruct;
  endStruct.hour = endHour;
  endStruct.min = 0;
  endStruct.sec = 0;
  datetime endLocalTime = StructToTime(endStruct);
  datetime lineEndTime = endLocalTime - (timeOffset * 3600); // Convert local end time to GMT

  Print("ORB Stage: OHLC data extracted from CLOSED candle - Next: Create horizontal lines from ", TimeToString(barTime), " to ", TimeToString(lineEndTime),
        " | High=", DoubleToString(highestPrice, _Digits), " Low=", DoubleToString(lowestPrice, _Digits));

  //--- Check if lines already exist using line drawer
  if (drawer != NULL && drawer.LinesExist(barTime))
  {
    lastProcessedDay = dayOfYear;
    return;
  }

  //--- Use line drawer to create ORB lines
  if (drawer != NULL)
  {
    if (drawer.DrawLines(barTime, highestPrice, lowestPrice, lineEndTime))
    {
      lastProcessedDay = dayOfYear;
      Print("ORB Stage: Lines created successfully for ", TimeToString(candleTime), " - Processing complete");
    }
  }
}
//+------------------------------------------------------------------+
