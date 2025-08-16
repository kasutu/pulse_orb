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
  string m_tzObjectName;
  string m_volumeObjectName;

public:
  //--- Constructor
  CDashboard(string prefix = "ORB_")
  {
    m_prefix = prefix;
    m_etaObjectName = m_prefix + "ETA_Display";
    m_tzObjectName = m_prefix + "TZ_Display";
    m_volumeObjectName = m_prefix + "Volume_Display";
  }
  //--- Update Timezone/Chart Time display
  void UpdateTimeZoneInfo(int offset)
  {
    datetime localTime = TimeLocal();
    datetime offsetTime = localTime + (offset * 3600);

    MqlDateTime localStruct, offsetStruct;
    TimeToStruct(localTime, localStruct);
    TimeToStruct(offsetTime, offsetStruct);

    string tzText = StringFormat(
        "Local: %04d-%02d-%02d %02d:%02d | Offset: %04d-%02d-%02d %02d:%02d (UTC%+d)",
        localStruct.year, localStruct.mon, localStruct.day, localStruct.hour, localStruct.min,
        offsetStruct.year, offsetStruct.mon, offsetStruct.day, offsetStruct.hour, offsetStruct.min,
        offset);

    if (!ObjectCreate(0, m_tzObjectName, OBJ_LABEL, 0, 0, 0))
    {
      ObjectSetString(0, m_tzObjectName, OBJPROP_TEXT, tzText);
    }
    else
    {
      ObjectSetString(0, m_tzObjectName, OBJPROP_TEXT, tzText);
      ObjectSetInteger(0, m_tzObjectName, OBJPROP_CORNER, CORNER_LEFT_LOWER);
      ObjectSetInteger(0, m_tzObjectName, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, m_tzObjectName, OBJPROP_YDISTANCE, 20);
      ObjectSetInteger(0, m_tzObjectName, OBJPROP_COLOR, clrAqua);
      ObjectSetInteger(0, m_tzObjectName, OBJPROP_FONTSIZE, 12);
    }
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
      ObjectSetInteger(0, m_etaObjectName, OBJPROP_YDISTANCE, 35);
      ObjectSetInteger(0, m_etaObjectName, OBJPROP_COLOR, clrYellow);
      ObjectSetInteger(0, m_etaObjectName, OBJPROP_FONTSIZE, 12);
    }
  }

  void UpdateVolumeConfirmation(string volumeText)
  {
    string volumeLabel = "Volume: " + volumeText;

    if (!ObjectCreate(0, m_volumeObjectName, OBJ_LABEL, 0, 0, 0))
    {
      ObjectSetString(0, m_volumeObjectName, OBJPROP_TEXT, volumeLabel);
    }
    else
    {
      ObjectSetString(0, m_volumeObjectName, OBJPROP_TEXT, volumeLabel);
      ObjectSetInteger(0, m_volumeObjectName, OBJPROP_CORNER, CORNER_LEFT_LOWER);
      ObjectSetInteger(0, m_volumeObjectName, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, m_volumeObjectName, OBJPROP_YDISTANCE, 50);
      ObjectSetInteger(0, m_volumeObjectName, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(0, m_volumeObjectName, OBJPROP_FONTSIZE, 12);
    }
  }

  //--- Remove ETA and TZ display
  void RemoveETA()
  {
    ObjectDelete(0, m_etaObjectName);
    ObjectDelete(0, m_tzObjectName);
  }

  //--- Get ETA object name for registry
  string GetETAObjectName()
  {
    return m_etaObjectName;
  }
};
