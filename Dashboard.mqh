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
  void UpdateETA(datetime targetTime, datetime currentLocal)
  {
    //--- Calculate remaining seconds until target
    int remainingSeconds = (int)(targetTime - currentLocal);

    //--- If target time has passed, calculate next day's target
    if (remainingSeconds <= 0)
    {
      //--- Add 24 hours (86400 seconds) to get next day's target
      datetime nextTarget = targetTime + 86400;
      remainingSeconds = (int)(nextTarget - currentLocal);
    }

    //--- Convert to HH:MM:SS format
    int hours = remainingSeconds / 3600;
    int minutes = (remainingSeconds % 3600) / 60;
    int seconds = remainingSeconds % 60;

    string etaText = StringFormat("Next ORB: %02dh:%02dm:%02ds", hours, minutes, seconds);

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
