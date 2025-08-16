//+------------------------------------------------------------------+
//| VolumeConfirmationEngine.mqh                                     |
//| Checks if volume confirms a signal based on SMA20 * factor       |
//+------------------------------------------------------------------+
#ifndef __VOLUME_CONFIRMATION_ENGINE_MQH__
#define __VOLUME_CONFIRMATION_ENGINE_MQH__

class VolumeConfirmationEngine
{
private:
  double m_factor;
  ENUM_TIMEFRAMES m_timeframe;

public:
  // Constructor with default factor and timeframe
  VolumeConfirmationEngine(double factor = 1.5, ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT)
  {
    m_factor = factor;
    m_timeframe = timeframe;
  }

  // Set the factor
  void SetFactor(double factor)
  {
    m_factor = factor;
  }

  // Set the timeframe
  void SetTimeframe(ENUM_TIMEFRAMES timeframe)
  {
    m_timeframe = timeframe;
  }

  // Get the factor
  double GetFactor() const
  {
    return m_factor;
  }

  // Get the timeframe
  ENUM_TIMEFRAMES GetTimeframe() const
  {
    return m_timeframe;
  }

  // Check if volume confirms (current bar)
  bool IsConfirmed(int volume_shift = 0)
  {
    double sma = iMA(NULL, m_timeframe, 20, 0, MODE_SMA, MODE_VOLUME, volume_shift);
    long vol = iVolume(NULL, m_timeframe, volume_shift);
    return (vol >= sma * m_factor);
  }

  // Returns the volume comparison as a string, e.g., "actual >= expected"
  string GetVolumeComparisonString(int volume_shift = 0)
  {
    double sma = iMA(NULL, m_timeframe, 20, 0, MODE_SMA, MODE_VOLUME, volume_shift);
    long vol = iVolume(NULL, m_timeframe, volume_shift);
    double expected = sma * m_factor;
    return DoubleToString(vol) + " >= " + DoubleToString(expected);
  }
};

#endif // __VOLUME_CONFIRMATION_ENGINE_MQH__
