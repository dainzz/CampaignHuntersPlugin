[Setting name="Show Window"]
bool S_ShowWindow = true;

[Setting name="Only send new or improved times"]
bool S_FilterOldTimes = true;

[Setting min=0 max=60000 name="Sync Interval"]
int S_SyncInterval = 1000;

[Setting name="API Host"]
string S_Host = "http://dainzz-001-site1.htempurl.com";

[Setting name="Username"]
string S_Username = "";

[Setting password name="Password"]
string S_Password = "";

#if DEPENDENCY_MLFEEDRACEDATA
[Setting category="PB List" name="Disable Live Updates via MLFeed?" description="Disable this to skip checking current race data for better times."]
#endif
bool S_SkipMLFeedCheck = false;

