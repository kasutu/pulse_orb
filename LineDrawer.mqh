//+------------------------------------------------------------------+
//|                                                   LineDrawer.mqh |
//|                                                       kasutufx |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "kasutufx"
#property link "https://www.mql5.com"

//--- Include ObjectRegistry for object management
#include "ObjectRegistry.mqh"

//+------------------------------------------------------------------+
//| Line Drawing Class                                               |
//+------------------------------------------------------------------+
class CLineDrawer
{
private:
  string m_prefix; // Prefix for line objects

public:
  //--- Constructor
  CLineDrawer(string prefix);

  //--- Destructor
  ~CLineDrawer();

  //--- Main line drawing method
  bool DrawLines(datetime barTime, double highPrice, double lowPrice, datetime endTime);

  //--- Individual line creation methods
  bool CreateHorizontalLine(string lineName, datetime startTime, datetime endTime,
                            double price, color lineColor, int lineWidth = 2);

  //--- Line property setting
  void SetLineProperties(string lineName, color lineColor, int lineWidth,
                         ENUM_LINE_STYLE lineStyle = STYLE_SOLID);

  //--- Check if  lines already exist for a given date
  bool LinesExist(datetime barTime);

  //--- Generate line names
  string GenerateHighLineName(datetime barTime);
  string GenerateLowLineName(datetime barTime);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CLineDrawer::CLineDrawer(string prefix)
{
  m_prefix = prefix;
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CLineDrawer::~CLineDrawer()
{
  // Nothing to clean up here, registry is managed externally
}

//+------------------------------------------------------------------+
//| Main  line drawing method                                     |
//+------------------------------------------------------------------+
bool CLineDrawer::DrawLines(datetime barTime, double highPrice, double lowPrice, datetime endTime)
{
  //--- Generate line names
  string highLineName = GenerateHighLineName(barTime);
  string lowLineName = GenerateLowLineName(barTime);

  //--- Check if lines already exist
  if (LinesExist(barTime))
  {
    Print("lines already exist for date: ", TimeToString(barTime, TIME_DATE));
    return false;
  }

  //--- Debug: Print price information
  Print("Line Debug - High: ", DoubleToString(highPrice, _Digits),
        " Low: ", DoubleToString(lowPrice, _Digits),
        " Range: ", DoubleToString(highPrice - lowPrice, _Digits));
  Print("Line Debug - Start time: ", TimeToString(barTime),
        " End time: ", TimeToString(endTime));

  //--- Create high line
  if (!CreateHorizontalLine(highLineName, barTime, endTime, highPrice, clrBlue))
  {
    Print("ERROR: Failed to create high line: ", highLineName);
    return false;
  }

  //--- Create low line
  if (!CreateHorizontalLine(lowLineName, barTime, endTime, lowPrice, clrRed))
  {
    Print("ERROR: Failed to create low line: ", lowLineName);
    return false;
  }

  //--- Register objects in the global registry
  RegisterId(highLineName);
  RegisterId(lowLineName);

  Print("SUCCESS: Created lines - High: ", DoubleToString(highPrice, _Digits),
        " Low: ", DoubleToString(lowPrice, _Digits));

  return true;
}

//+------------------------------------------------------------------+
//| Create horizontal line                                           |
//+------------------------------------------------------------------+
bool CLineDrawer::CreateHorizontalLine(string lineName, datetime startTime, datetime endTime,
                                       double price, color lineColor, int lineWidth = 2)
{
  //--- Create the line object
  if (!ObjectCreate(0, lineName, OBJ_TREND, 0, startTime, price, endTime, price))
  {
    Print("ERROR: Failed to create line: ", lineName, " Error: ", GetLastError());
    return false;
  }

  //--- Set line properties
  SetLineProperties(lineName, lineColor, lineWidth);

  Print("SUCCESS: Created line: ", lineName, " at price: ", DoubleToString(price, _Digits));
  return true;
}

//+------------------------------------------------------------------+
//| Set line properties                                              |
//+------------------------------------------------------------------+
void CLineDrawer::SetLineProperties(string lineName, color lineColor, int lineWidth,
                                    ENUM_LINE_STYLE lineStyle = STYLE_SOLID)
{
  ObjectSetInteger(0, lineName, OBJPROP_COLOR, lineColor);
  ObjectSetInteger(0, lineName, OBJPROP_WIDTH, lineWidth);
  ObjectSetInteger(0, lineName, OBJPROP_RAY_LEFT, false);
  ObjectSetInteger(0, lineName, OBJPROP_RAY_RIGHT, false);
  ObjectSetInteger(0, lineName, OBJPROP_STYLE, lineStyle);
}

//+------------------------------------------------------------------+
//| Check if  lines already exist for a given date               |
//+------------------------------------------------------------------+
bool CLineDrawer::LinesExist(datetime barTime)
{
  string highLineName = GenerateHighLineName(barTime);
  string lowLineName = GenerateLowLineName(barTime);

  // Check if objects exist on chart
  return ObjectFind(0, highLineName) >= 0 || ObjectFind(0, lowLineName) >= 0;
}

//+------------------------------------------------------------------+
//| Generate high line name                                          |
//+------------------------------------------------------------------+
string CLineDrawer::GenerateHighLineName(datetime barTime)
{
  return m_prefix + "High_" + TimeToString(barTime, TIME_DATE);
}

//+------------------------------------------------------------------+
//| Generate low line name                                           |
//+------------------------------------------------------------------+
string CLineDrawer::GenerateLowLineName(datetime barTime)
{
  return m_prefix + "Low_" + TimeToString(barTime, TIME_DATE);
}
