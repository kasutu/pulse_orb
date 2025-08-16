//+------------------------------------------------------------------+
//|                                                    Dashboard.mqh |
//|                                                       kasutufx |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Dashboard class for ORB EA                                       |
//+------------------------------------------------------------------+
class CDashboard
{
private:
  string m_prefix;
  string m_etaObjectName;

public:
  //--- Constructor
  CDashboard(string prefix = "ORB_")
  {
    m_prefix = prefix;
    m_etaObjectName = m_prefix + "ETA_Display";
  }

  //--- Destructor
  ~CDashboard()
  {
    RemoveETA();
  }

  //--- Update ETA display
  void UpdateETA(int startHour, int endHour, datetime currentLocal, datetime todayTarget)
  {
    //--- Get current local time structure
    MqlDateTime currentStruct;
    TimeToStruct(currentLocal, currentStruct);

    //--- Calculate end time for today's session
    MqlDateTime endStruct = currentStruct;
    endStruct.hour = endHour;
    endStruct.min = 0;
    endStruct.sec = 0;
    datetime todayEnd = StructToTime(endStruct);

    string prefix;
    int etaSeconds;

    if (currentStruct.hour >= startHour && currentStruct.hour < endHour)
    {
      //--- During session - countdown to end
      etaSeconds = (int)(todayEnd - currentLocal);
      prefix = "Pulse T+"; // T for Time countdown
    }
    else
    {
      //--- Before session start - countdown to start
      etaSeconds = (int)(todayTarget - currentLocal);
      prefix = "Pulse T-";
    }

    //--- Ensure positive values for display
    if (etaSeconds < 0)
      etaSeconds = -etaSeconds;

    int etaHours = etaSeconds / 3600;
    int etaMinutes = (etaSeconds % 3600) / 60;
    etaSeconds = etaSeconds % 60;

    string etaText = StringFormat("%s%02d:%02d:%02d", prefix, etaHours, etaMinutes, etaSeconds);

    //--- Create or update ETA display
    if (!ObjectCreate(0, m_etaObjectName, OBJ_LABEL, 0, 0, 0))
    {
      ObjectSetString(0, m_etaObjectName, OBJPROP_TEXT, etaText);
    }
    else
    {
      ObjectSetString(0, m_etaObjectName, OBJPROP_TEXT, etaText);
      ObjectSetInteger(0, m_etaObjectName, OBJPROP_CORNER, CORNER_LEFT_LOWER);
      ObjectSetInteger(0, m_etaObjectName, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, m_etaObjectName, OBJPROP_YDISTANCE, 30);
      ObjectSetInteger(0, m_etaObjectName, OBJPROP_COLOR, clrYellow);
      ObjectSetInteger(0, m_etaObjectName, OBJPROP_FONTSIZE, 12);
    }
  }

  //--- Remove ETA display
  void RemoveETA()
  {
    ObjectDelete(0, m_etaObjectName);
  }

  //--- Get ETA object name for registry
  string GetETAObjectName()
  {
    return m_etaObjectName;
  }
};
