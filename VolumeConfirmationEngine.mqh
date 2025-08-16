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

  // Calculate SMA of volume
  double VolumeSMA(int period, int shift = 0) const
  {
    long volumes[];
    int copied = CopyTickVolume(_Symbol, m_timeframe, shift, period, volumes);
    if (copied <= 0)
      return 0;

    double sum = 0;
    for (int i = 0; i < copied; i++)
      sum += (double)volumes[i];

    return (copied > 0) ? sum / copied : 0;
  }

public:
  // Constructor with default factor and timeframe
  VolumeConfirmationEngine(double factor = 1.5, ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT)
  {
    m_factor = factor;
    m_timeframe = timeframe;
  }

  // Setters
  void SetFactor(double factor) { m_factor = factor; }
  void SetTimeframe(ENUM_TIMEFRAMES timeframe) { m_timeframe = timeframe; }

  // Getters
  double GetFactor() const { return m_factor; }
  ENUM_TIMEFRAMES GetTimeframe() const { return m_timeframe; }

  // Check if volume confirms (current bar or shifted bar)
  bool IsConfirmed(int volume_shift = 0)
  {
    double sma = VolumeSMA(20, volume_shift);
    long vol = iVolume(_Symbol, m_timeframe, volume_shift);
    return (sma > 0 && vol >= sma * m_factor);
  }

  // Returns the volume comparison as a string
  string GetVolumeComparisonString(int volume_shift = 0)
  {
    double sma = VolumeSMA(20, volume_shift);
    long vol = iVolume(_Symbol, m_timeframe, volume_shift);
    double expected = sma * m_factor;

    return IntegerToString(vol) + " >= " + DoubleToString(expected, 2);
  }
};

#endif // __VOLUME_CONFIRMATION_ENGINE_MQH__
