//+------------------------------------------------------------------+
//| TimeEngine.mqh - Centralized time handling for EA               |
//+------------------------------------------------------------------+
#ifndef __TIMEENGINE_MQH__
#define __TIMEENGINE_MQH__

class TimeEngine
{
public:
    // Get current GMT time
    static datetime GetGMT()
    {
        return TimeGMT();
    }

    // Get current local time (using offset)
    static datetime GetLocal(int offset)
    {
        return TimeGMT() + (offset * 3600);
    }

    // Convert GMT datetime to local
    static datetime GMTToLocal(datetime gmt, int offset)
    {
        return gmt + (offset * 3600);
    }

    // Convert local datetime to GMT
    static datetime LocalToGMT(datetime local, int offset)
    {
        return local - (offset * 3600);
    }

    // Get MqlDateTime struct for any datetime
    static void ToStruct(datetime t, MqlDateTime &s)
    {
        TimeToStruct(t, s);
    }

    // Get open time of a bar in a given timeframe and index
    static datetime BarOpen(string symbol, ENUM_TIMEFRAMES tf, int index)
    {
        return iTime(symbol, tf, index);
    }

    // Get close time of a bar in a given timeframe and index
    static datetime BarClose(string symbol, ENUM_TIMEFRAMES tf, int index)
    {
        return iTime(symbol, tf, index) + PeriodSeconds(tf);
    }

    // Get hour/minute in GMT or local for a bar
    static void BarTimeStruct(string symbol, ENUM_TIMEFRAMES tf, int index, int offset, MqlDateTime &gmtStruct, MqlDateTime &localStruct)
    {
        datetime gmt = iTime(symbol, tf, index);
        TimeToStruct(gmt, gmtStruct);
        TimeToStruct(GMTToLocal(gmt, offset), localStruct);
    }
};

#endif // __TIMEENGINE_MQH__
//+------------------------------------------------------------------+
