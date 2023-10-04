[Setting name="Records Sync Interval"]
int S_SyncInterval = 1000;

[Setting name="Show Window"]
bool S_ShowWindow = true;

#if DEPENDENCY_MLFEEDRACEDATA
[Setting category="PB List" name="Disable Live Updates via MLFeed?" description="Disable this to skip checking current race data for better times."]
#endif
bool S_SkipMLFeedCheck = false;

