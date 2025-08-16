//+------------------------------------------------------------------+
//|                    ProcessORB.mqh                                |
//|   Refactored for TimeEngine integration and historical handling  |
//+------------------------------------------------------------------+
#include "TimeEngine.mqh"
#include "LineDrawer.mqh"

class ProcessORB
{
private:
  static int lastProcessedDay;

public:
  // Process single ORB (current or historical)
  static void Process(datetime candleTime, int dayOfYear, int endHour, int timeOffset, CLineDrawer *drawer)
  {
    // Find bar and validate
    int barIndex = iBarShift(_Symbol, PERIOD_M15, candleTime, true);
    if (barIndex < 0)
    {
      Print("ERROR: Could not find 15-minute bar for: ", TimeToString(candleTime));
      return;
    }

    datetime barTime = TimeEngine::BarOpen(_Symbol, PERIOD_M15, barIndex);
    Print("ORB: Processing bar at index ", barIndex, " time ", TimeToString(barTime));

    // Extract OHLC
    double high = iHigh(_Symbol, PERIOD_M15, barIndex);
    double low = iLow(_Symbol, PERIOD_M15, barIndex);

    // Calculate line end time using TimeEngine
    datetime lineEndTime = CalculateEndTime(candleTime, endHour, timeOffset);

    Print("ORB: Lines from ", TimeToString(barTime), " to ", TimeToString(lineEndTime),
          " | H=", DoubleToString(high, _Digits), " L=", DoubleToString(low, _Digits));

    // Check existing and draw
    if (drawer != NULL && !drawer.LinesExist(barTime))
    {
      if (drawer.DrawLines(barTime, high, low, lineEndTime))
      {
        lastProcessedDay = dayOfYear;
        Print("ORB: Lines created successfully");
      }
    }
  }

  // Process historical ORBs in range
  static void ProcessHistorical(int lookbackBars, int startHour, int endHour, int timeOffset, CLineDrawer *drawer)
  {
    for (int i = lookbackBars; i >= 1; i--)
    {
      if (TimeEngine::IsTargetHour(_Symbol, PERIOD_M15, i, startHour, timeOffset))
      {
        datetime barTime = TimeEngine::BarOpen(_Symbol, PERIOD_M15, i);
        MqlDateTime localStruct;
        TimeEngine::BarTimeStruct(_Symbol, PERIOD_M15, i, timeOffset, localStruct);

        Process(barTime, localStruct.day_of_year, endHour, timeOffset, drawer);
      }
    }
  }

  // Check if should process new ORB
  static bool ShouldProcess(datetime candleTime, int timeOffset, int startHour)
  {
    MqlDateTime localStruct;
    datetime localTime = TimeEngine::ApplyOffset(candleTime, timeOffset);
    TimeEngine::ToStruct(localTime, localStruct);

    bool isTargetTime = (localStruct.hour == startHour && localStruct.min == 0);
    bool notProcessedToday = (lastProcessedDay != localStruct.day_of_year);

    return isTargetTime && notProcessedToday;
  }

private:
  // Calculate line end time
  static datetime CalculateEndTime(datetime candleTime, int endHour, int timeOffset)
  {
    // Get candle's local date
    datetime localCandleTime = TimeEngine::ApplyOffset(candleTime, timeOffset);
    MqlDateTime endStruct;
    TimeEngine::ToStruct(localCandleTime, endStruct);

    // Set end hour in local time
    endStruct.hour = endHour;
    endStruct.min = 0;
    endStruct.sec = 0;

    return StructToTime(endStruct);
  }
};

int ProcessORB::lastProcessedDay = 0;