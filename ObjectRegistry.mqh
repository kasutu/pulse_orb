// ObjectRegistry.mqh
// Lightweight helpers for naming, tracking, and clearing chart objects
// Usage: #include "utils/ObjectRegistry.mqh"

#ifndef __OBJECT_REGISTRY_MQH__
#define __OBJECT_REGISTRY_MQH__

// Keep a simple in-memory registry of object IDs we create during this session
static string __g_obj_ids[];
static int __g_obj_counter = 0; // for ad-hoc unique keys

// --- Timeframe to string ---
string TfToString(ENUM_TIMEFRAMES tf)
{
  switch (tf)
  {
  case PERIOD_M1:
    return "M1";
  case PERIOD_M2:
    return "M2";
  case PERIOD_M3:
    return "M3";
  case PERIOD_M4:
    return "M4";
  case PERIOD_M5:
    return "M5";
  case PERIOD_M6:
    return "M6";
  case PERIOD_M10:
    return "M10";
  case PERIOD_M12:
    return "M12";
  case PERIOD_M15:
    return "M15";
  case PERIOD_M20:
    return "M20";
  case PERIOD_M30:
    return "M30";
  case PERIOD_H1:
    return "H1";
  case PERIOD_H2:
    return "H2";
  case PERIOD_H3:
    return "H3";
  case PERIOD_H4:
    return "H4";
  case PERIOD_H6:
    return "H6";
  case PERIOD_H8:
    return "H8";
  case PERIOD_H12:
    return "H12";
  case PERIOD_D1:
    return "D1";
  case PERIOD_W1:
    return "W1";
  case PERIOD_MN1:
    return "MN1";
  default:
    return IntegerToString((int)tf);
  }
}

// --- ID building helpers ---
string MakeId(string prefix, string typeTag, string symbol, ENUM_TIMEFRAMES tf, string key)
{
  // Format: prefix_type_symbol_tf_key
  return prefix + "_" + typeTag + "_" + symbol + "_" + TfToString(tf) + "_" + key;
}

string KeyFromTime(datetime t)
{
  // Use epoch seconds for simplicity
  return "t" + IntegerToString((int)t);
}

string NextCounterKey()
{
  __g_obj_counter++;
  return "n" + IntegerToString(__g_obj_counter);
}

// --- Registry ops ---
bool RegisterId(string id)
{
  for (int i = 0; i < ArraySize(__g_obj_ids); i++)
    if (__g_obj_ids[i] == id)
      return false;
  int n = ArraySize(__g_obj_ids);
  ArrayResize(__g_obj_ids, n + 1);
  __g_obj_ids[n] = id;
  return true;
}

bool UnregisterId(string id)
{
  int n = ArraySize(__g_obj_ids);
  for (int i = 0; i < n; i++)
  {
    if (__g_obj_ids[i] == id)
    {
      __g_obj_ids[i] = __g_obj_ids[n - 1];
      ArrayResize(__g_obj_ids, n - 1);
      return true;
    }
  }
  return false;
}

// --- Deletion helpers ---
bool DeleteById(long chartId, string id)
{
  if (ObjectFind(chartId, id) >= 0)
  {
    bool ok = ObjectDelete(chartId, id);
    UnregisterId(id);
    return ok;
  }
  UnregisterId(id);
  return true;
}

void ClearRegistered(long chartId)
{
  for (int i = ArraySize(__g_obj_ids) - 1; i >= 0; i--)
    ObjectDelete(chartId, __g_obj_ids[i]);
  ArrayResize(__g_obj_ids, 0);
}

void ClearByPrefix(long chartId, string prefix)
{
  // Delete anything on the chart that starts with prefix
  ObjectsDeleteAll(chartId, prefix);
  // Reset local registry (assumes we track one prefix per EA instance)
  ArrayResize(__g_obj_ids, 0);
}

void RebuildRegistryFromChart(long chartId, string prefix)
{
  ArrayResize(__g_obj_ids, 0);
  int total = ObjectsTotal(chartId, -1, -1);
  for (int i = 0; i < total; i++)
  {
    string name = ObjectName(chartId, i, -1, -1);
    if (StringFind(name, prefix) == 0)
    {
      int n = ArraySize(__g_obj_ids);
      ArrayResize(__g_obj_ids, n + 1);
      __g_obj_ids[n] = name;
    }
  }
}

#endif // __OBJECT_REGISTRY_MQH__
