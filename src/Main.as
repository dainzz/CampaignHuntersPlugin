const string PageUID = "CHRaceStats";

PlayerFinishedHook@ playerFinishedHook = PlayerFinishedHook();
MapChangeHook@ mapChangeHook = MapChangeHook();
CSVHook@ csvHook = CSVHook();
void Main() {    
    if (!PermissionsOkay) {
        NotifyMissingPermissions();
        return;
    }   

	g_APIToken = getToken();
    
    startnew(InitCoro);
}

void InitCoro() {   
	Log("Starting InitCoro");
    MLHook::RegisterMLHook(playerFinishedHook, PageUID + "_NewRecord");
    MLHook::RegisterMLHook(mapChangeHook, PageUID + "_MapChange");
	MLHook::RegisterMLHook(csvHook, PageUID + "_CSVRecords");
	
    sleep(50);
    yield();
    IO::FileSource refreshCode("CHRaceStatsFeed.Script.txt");
    string manialinkScript = refreshCode.ReadToEnd();   
    MLHook::InjectManialinkToPlayground(PageUID, manialinkScript, true);
    yield();
    yield();
	
	while(get_cp() == null)
	{
		Log("Waiting for playground...");
		sleep(1000);
		yield();	
	}	
		
	while(getEndTime() == 4294967295)
	{
			Log("Waiting for round to start...");
			sleep(1000);
			yield();
	}
	roundStarted = true;	
	
	Log("Starting MainCoro");
    startnew(CoroutineFunc(playerFinishedHook.MainCoro));
}

void OnDestroyed() { _Unload(); }
void OnDisabled() { _Unload(); }
void _Unload() {
    trace('_Unload, unloading all hooks and removing all injected ML');
    MLHook::UnregisterMLHooksAndRemoveInjectedML();
        MLHook::RemoveInjectedMLFromPlayground(PageUID);
} 

int getEndTime(){
	auto pg = get_cp();   
	if(pg == null) return 4294967295;
	return pg.Arena.Rules.RulesStateEndTime;
}

string get_CurrentMap() {
    auto map = GetApp().RootMap;
    if (map is null) return "";
    return map.MapInfo.MapUid;
}

int get_CurrentRaceTime() {
    if (GUIPlayer_ScriptAPI !is null) return GUIPlayer_ScriptAPI.CurrentRaceTime;
     if (ControlledPlayer_ScriptAPI is null) return 0;
     return ControlledPlayer_ScriptAPI.CurrentRaceTime;
 }

bool roundStarted = false;

class MapChangeHook : MLHook::HookMLEventsByType {
    MapChangeHook() {
        super(PageUID);
    }
   
    void OnEvent(MLHook::PendingEvent@ event) override {
        if(!enabled) return;
        Log("Received Mapchange Event.");
        roundStarted = false;
        startnew(CoroutineFunc(this.SyncOnRoundStart));
    }

    void SyncOnRoundStart(){
        auto pg = get_cp();   
        Log("Waiting til round starts...");
        while(pg.Arena.Rules.RulesStateEndTime  == 4294967295 ){
                    yield();                    
        }

        roundStarted = true;
        

        auto timeleft = pg.Arena.Rules.RulesStateEndTime - pg.Arena.Rules.RulesStateStartTime;
        
        Log("Round started, synchronizing timer. Time left: " + timeleft);

        auto req = Net::HttpRequest();
        req.Method = Net::HttpMethod::Get;
        req.Url = S_Host + "/api/time/" + timeleft;
        req.Headers["Authorization"] = "Bearer " + g_APIToken;
        req.Start();
        while (!req.Finished()) {
            yield();
            sleep(50);
            }
    }
}

   void getCSV(){
        MLHook::Queue_MessageManialinkPlayground(PageUID, {"SendCSV"});
    }


class CSVHook : MLHook::HookMLEventsByType {
    CSVHook() {
        super(PageUID);
    }
   
    void OnEvent(MLHook::PendingEvent@ event) override {        
        Log("Received CSV Event.");
		IO::SetClipboard(event.data[0]);
    }

    void WriteToFile(){
        
    }
}


class PlayerFinishedHook : MLHook::HookMLEventsByType {
    PlayerFinishedHook() {
        super(PageUID);
    }

    MLHook::PendingEvent@[] pendingEvents;

    void OnEvent(MLHook::PendingEvent@ event) override {
        if(!enabled) return;
        if(!roundStarted){
            string name = event.data[0];
            string id = event.data[1];
            string timestamp = event.data[2];
            uint time = Text::ParseUInt(event.data[3]);            
            string mapUid = event.data[4];
            Log("Ignoring incoming record, round didnt start yet. ("+ name + ", " + Time::Format(time) + ", " + mapUid + ")");

            return;
        } 
        pendingEvents.InsertLast(event);
    }

    void MainCoro() {              
        MLHook::Queue_MessageManialinkPlayground(PageUID, {"SendAllPlayerStates"});
        while (true) {
              yield();
            if(enabled && lastPbUpdate + S_SyncInterval < Time::Now ){
                 yield();
            SendToAPI();   
            lastPbUpdate = Time::Now; 
            }                  
        }
    }


 

void SendToAPI() {
    
    uint toProcess = pendingEvents.Length;
    if(toProcess == 0) return;
    Json::Value jsonData = Json::Array();    

    Log("Processing " + toProcess + " pending events:");
    
    for (uint i = 0; i < toProcess; i++) {
            auto event = pendingEvents[i];
            string name = event.data[0];
            string id = event.data[1];
            string timestamp = event.data[2];
            uint time = Text::ParseUInt(event.data[3]);            
            string mapUid = event.data[4];
            
            Json::Value playerObj = Json::Object();
 
		playerObj["Name"] = name;
		playerObj["PlayerId"] = id;
        
        Json::Value map = Json::Object();

		map["MapId"] = mapUid;
		map["Name"] = "-";	
 
		Json::Value record = Json::Object();	
 
		record["Time"] = time;
		record["Map"] = map;
		record["Player"] = playerObj;
		record["TimeLeft"] = timestamp; 

        Log("Adding record to json: " + name + ", " + id + ", " + Time::Format(time) + ", " + Time::FormatString("%H:%M:%S", Text::ParseInt64(timestamp)));
        jsonData.Add(record);              
    }
	
	bool succ = false;
	while(succ == false){
	 string data = Json::Write(jsonData);
                auto req = Net::HttpRequest();
                req.Method = Net::HttpMethod::Post;
                req.Url = S_Host + "/api/records";
                req.Headers["Content-Type"] = "application/json";
                req.Headers["Authorization"] = "Bearer " + g_APIToken;
                req.Body = data;
                req.Start();
    
        Log("Sending " + toProcess + " records to API.");
        while (!req.Finished()) {
            yield();
            sleep(50);
            } 
			
			if (req.ResponseCode() != 200) {
                error("API Error, failed to upload records. HTTP Error " + req.ResponseCode());  
				sleep(5000);
                }
            else{
                Log("Sync with server successful.");
				succ = true;
            }
	}     
		
			
            pendingEvents.RemoveRange(0, toProcess); //TODO: keep entries that returned api error

            }
}

  void AskForAllPlayerStates() {
            MLHook::Queue_MessageManialinkPlayground(PageUID, {"SendAllPlayerStates"});
        }

bool get_PermissionsOkay() {
    return Permissions::ViewRecords()
        // && Permissions::PlayRecords() // don't think this is required, just viewing
        ;
}
 
void NotifyMissingPermissions() {
    UI::ShowNotification(Meta::ExecutingPlugin().Name,
        "Missing permissions! D:\nYou probably don't have permission to view records/PBs.\nThis plugin won't do anything.",
        vec4(1, .4, .1, .3),
        10000
        );
    warn("Missing permissions! D:\nYou probably don't have permission to view records/PBs.\nThis plugin won't do anything.");
}

string g_APIToken;
uint lastPbUpdate = 0;
bool enabled = true;

 
string getToken(){

		Json::Value login = Json::Object();
		login["username"] = S_Username;
		login["password"] = S_Password;

    string data = Json::Write(login);

        Net::HttpRequest@ req = Net::HttpPost(S_Host + "/api/login", data, "application/json");
									

        while (!req.Finished()) {
            yield();
            sleep(50);
            } 
		if (req.ResponseCode() != 200) {
		error("Unable to authenticate, http error " + req.ResponseCode());
		return "";
	}

    Log("Login successful, retrieved API token.");

	// Parse the server response
	auto js = Json::Parse(req.String());
	
	return js["token"];
	
}

void Log(string _text){
    if(S_Logging) print(_text);
}

 
/* DRAW UI */
 
/** Render function called every frame intended only for menu items in `UI`.
*/
void RenderMenu() {
    if (!PermissionsOkay) return;
 
    if (UI::MenuItem("\\$0f4" + Icons::ListAlt + "\\$z " + Meta::ExecutingPlugin().Name, "", S_ShowWindow)) {
        S_ShowWindow = !S_ShowWindow;
    }
}
 
void RenderInterface() {
    DrawUI();
}
 
void Render() {
    if (!UI::IsOverlayShown()) {
        DrawUI();
    }
}

void DrawUI() {
    if (!S_ShowWindow) return;  
 
    int uiFlags = UI::WindowFlags::NoCollapse;
 
    UI::SetNextWindowSize(100, 100, UI::Cond::FirstUseEver);
    if (UI::Begin("Campaign Hunters", S_ShowWindow, uiFlags)) {
            if (UI::BeginChild("##pbs-full-ui", UI::GetContentRegionAvail())) {
           
                    UI::AlignTextToFramePadding();
                    enabled = (UI::Checkbox("Enabled", enabled));

                     if (UI::Button("Copy to clipboard")) {
                            //startnew(AskForAllPlayerStates);
							startnew(getCSV);
                        }
					UI::Text("Round started: " + roundStarted);
                  
            }
            UI::EndChild();
        
    }
    UI::End();
}


CSmArenaClient@ get_cp() {
    return cast<CSmArenaClient>(GetApp().CurrentPlayground);
}

CSmArena@ get_CP_Arena() {
    if (cp is null) return null;
    return cast<CSmArena>(cp.Arena);
}

CGameTerminal@ get_GameTerminal() {
    if (cp is null) return null;
    if (cp.GameTerminals.Length < 1) return null;
    return cp.GameTerminals[0];
}

CSmPlayer@ get_GUIPlayer() {
    if (GameTerminal is null) return null;
    return cast<CSmPlayer>(GameTerminal.GUIPlayer);
}
CSmPlayer@ get_ControlledPlayer() {
    if (GameTerminal is null) return null;
    return cast<CSmPlayer>(GameTerminal.ControlledPlayer);
}

CSmScriptPlayer@ get_GUIPlayer_ScriptAPI() {
    if (GUIPlayer is null) return null;
    return cast<CSmScriptPlayer>(GUIPlayer.ScriptAPI);
}
CSmScriptPlayer@ get_ControlledPlayer_ScriptAPI() {
    if (ControlledPlayer is null) return null;
    return cast<CSmScriptPlayer>(ControlledPlayer.ScriptAPI);
}