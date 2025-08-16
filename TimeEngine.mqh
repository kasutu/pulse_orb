//+------------------------------------------------------------------+
//| TimeEngine.mqh - Local time-based centralized time handling     |
//+------------------------------------------------------------------+
#ifndef __TIMEENGINE_MQH__
#define __TIMEENGINE_MQH__

class TimeEngine
{
public:
  // Get current local time with offset
  static datetime GetLocal(int offsetHours = 0)
  {
    return TimeLocal() + (offsetHours * 3600);
  }

  // Apply offset to any datetime
  static datetime ApplyOffset(datetime time, int offsetHours)
  {
    return time + (offsetHours * 3600);
  }

  // Get MqlDateTime struct for any datetime
  static void ToStruct(datetime t, MqlDateTime &s)
  {
    TimeToStruct(t, s);
  }

  // Get open time of a bar (uses raw GMT bar time)
  static datetime BarOpen(string symbol, ENUM_TIMEFRAMES tf, int index)
  {
    return iTime(symbol, tf, index);
  }

  // Get close time of a bar (uses raw GMT bar time)
  static datetime BarClose(string symbol, ENUM_TIMEFRAMES tf, int index)
  {
    return iTime(symbol, tf, index) + PeriodSeconds(tf);
  }

  // Get time struct for a bar with offset applied
  static void BarTimeStruct(string symbol, ENUM_TIMEFRAMES tf, int index, int offsetHours, MqlDateTime &localStruct)
  {
    datetime barTime = BarOpen(symbol, tf, index);
    datetime localTime = ApplyOffset(barTime, offsetHours);
    TimeToStruct(localTime, localStruct);
  }

  // Historical view methods
  static bool IsTargetHour(string symbol, ENUM_TIMEFRAMES tf, int index, int targetHour, int offsetHours)
  {
    MqlDateTime localStruct;
    BarTimeStruct(symbol, tf, index, offsetHours, localStruct);
    return (localStruct.hour == targetHour && localStruct.min == 0);
  }

  static datetime GetHistoricalBar(string symbol, ENUM_TIMEFRAMES tf, int lookbackBars, int targetHour, int offsetHours)
  {
    for (int i = lookbackBars; i >= 1; i--)
    {
      if (IsTargetHour(symbol, tf, i, targetHour, offsetHours))
        return BarOpen(symbol, tf, i);
    }
    return 0;
  }
};

#endif // __TIMEENGINE_MQH__