void Main() {
    if (!PermissionsOkay) {
        NotifyMissingPermissions();
        return;
    }
    trace("MLFeed detected: " + tostring(g_mlfeedDetected));
    //startnew(MainLoop);
	
	g_APIToken = getToken();
	print("Token is " + g_APIToken);
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


dictionary g_addedTimes;
string g_APIToken;

uint lastPbUpdate = 0;
 
#if DEPENDENCY_MLFEEDRACEDATA
bool g_mlfeedDetected = true;
#else
bool g_mlfeedDetected = false;
#endif

 
bool get_PlaygroundNotNullAndEditorNull() {
    return GetApp().CurrentPlayground !is null && GetApp().Editor is null;
}
 
// returns true if should exit because we're in solo mode
bool SoloModeExitCheck() {
    return GetApp().PlaygroundScript !is null;
}
 
 
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

	// Parse the server response
	auto js = Json::Parse(req.String());
	
	return js["token"];
	
}

 
void Update(float dt) {
    if (g_mlfeedDetected) {
        if (PlaygroundNotNullAndEditorNull) {
             if (autoUpdate && lastPbUpdate + S_SyncInterval < Time::Now && !g_CurrentyUpdating) { 
                 startnew(UpdateRecords);
                 lastPbUpdate = Time::Now; 
                 }
        }
                    else{
                g_addedTimes.DeleteAll();
                timeLeft = -1;
                //print("Map Change, resetting data.");
            }
        }
    if(!g_mlfeedDetected)
        print("no MLFeed");
}
 
uint g_PlayersInServerLast = 0;
bool g_CurrentlyLoadingRecords = false;
 
 

 int timeLeft = -1;
 
 void Test() {
 print("---------------------------------");
     CTrackMania@ app = cast<CTrackMania>(GetApp());
	 CSmPlayer@ smPlayer = cast<CSmPlayer>(app.CurrentPlayground.GameTerminals[0].GUIPlayer);
        CSmScriptPlayer@ smScript = cast<CSmScriptPlayer>(smPlayer.ScriptAPI);
	 
	 

 CGamePlaygroundClientScriptAPI@ ret = GetPlaygroundClientScriptAPISync(app);
        while (ret is null) {
            print("PlaygroundScript is null");
        yield();
        @ret = GetPlaygroundClientScriptAPISync(app);
    }
        print("Playground Info: Loading Screen: " + ret.IsLoadingScreen + ", GameTime: " + (ret.GameTime - smScript.StartTime));   
return;
 
 
 auto cp = cast<CTrackMania>(GetApp()).CurrentPlayground;
    if (cp is null) return;    
    auto raceData = MLFeed::GetRaceData_V4();
    auto elapsed = raceData.Rules_GameTime - raceData.Rules_StartTime;
    print(elapsed);
	print(Time::Now);
	 print("---------------------------------");
}
 
 CGamePlaygroundClientScriptAPI@ GetPlaygroundClientScriptAPISync(CGameCtnApp@ app) {
    try {
        return cast<CTrackMania>(app).Network.PlaygroundClientScriptAPI;
    } catch {}
    return null;
}

 
void UpdateRecords() {
  	g_CurrentyUpdating = true;    
    CTrackMania@ app = cast<CTrackMania>(GetApp());
    if(app.RootMap is null){
        print("MAP NULL");
        g_CurrentyUpdating = false;
        return;
    }
    //string mapUid = app.RootMap.MapInfo.MapUid;
	string mapName = app.RootMap.MapName;
 
	auto raceData = MLFeed::GetRaceData_V4();  
	auto total = raceData.Rules_EndTime - raceData.Rules_StartTime;
    auto elapsed = raceData.Rules_GameTime - raceData.Rules_StartTime;
	string mapUid = raceData.lastMap;

    if(timeLeft == -1){
        CGamePlaygroundClientScriptAPI@ ret = GetPlaygroundClientScriptAPISync(app);
		
        while (ret is null) {
            print("PlaygroundScript is null");
            yield();
            @ret = GetPlaygroundClientScriptAPISync(app);
        }
        CSmPlayer@ smPlayer = cast<CSmPlayer>(app.CurrentPlayground.GameTerminals[0].GUIPlayer);
        while (smPlayer is null) {
            print("smPlayer is null");
            yield();
            @smPlayer = cast<CSmPlayer>(app.CurrentPlayground.GameTerminals[0].GUIPlayer);
        }
        
        CSmScriptPlayer@ smScript = cast<CSmScriptPlayer>(smPlayer.ScriptAPI);
		string time = Time::Format(ret.GameTime - smScript.StartTime);
        print("Playground Info: StartTime: " + smScript.StartTime + ", CurrentTime: " + time);   

    timeLeft = raceData.Rules_EndTime - raceData.Rules_GameTime;
	while (timeLeft < 0) {
            print("time < 0, round probably didnt start yet");
            yield();
			sleep(200);
			timeLeft = raceData.Rules_EndTime - raceData.Rules_GameTime;
        }	
        print("Synchronizing timer, time left: " + Time::Format(timeLeft));
						
						auto req = Net::HttpRequest();
	req.Method = Net::HttpMethod::Get;
	req.Url = S_Host + "/api/time/" + timeLeft;
	req.Headers["Authorization"] = "Bearer " + g_APIToken;
	req.Start();
					while (!req.Finished()) {
					yield();
					sleep(50);
		}	
		
    }

	Json::Value jsonData = Json::Array();

    for (uint i = 0; i < raceData.SortedPlayers_TimeAttack.Length; i++){
        auto player = cast<MLFeed::PlayerCpInfo_V4>(raceData.SortedPlayers_TimeAttack[i]);
        
        if (player.bestTime < 1)
                continue;
		
        if (g_addedTimes.Exists(player.WebServicesUserId)){            
            auto existingTime = int(g_addedTimes[player.WebServicesUserId]); 
            if(!(player.BestTime < existingTime)){
                if(S_FilterOldTimes)continue;  
            }
            else{
                print("Found improved record for " + player.name + ": " + existingTime + " => " + player.bestTime);
            }
        }		
        else{
            print("Found new record for " + player.name + ": "  + player.bestTime);
        }
        
		Json::Value playerObj = Json::Object();
 
		playerObj["Name"] = player.name;
		playerObj["PlayerId"] = player.WebServicesUserId;
        
        Json::Value map = Json::Object();

		map["MapId"] = mapUid;
		map["Name"] = mapName;	
 
		Json::Value record = Json::Object();	
 
		record["Time"] = player.BestTime;
		record["Map"] = map;
		record["Player"] = playerObj;
		record["TimeLeft"] = Time::Stamp;
        
        jsonData.Add(record);
        
 		g_addedTimes[player.WebServicesUserId] = player.bestTime;
  }	 

if(jsonData.Length > 0){
    print("Sending records to API.");
    string data = Json::Write(jsonData);


		auto req = Net::HttpRequest();
	req.Method = Net::HttpMethod::Post;
	req.Url = S_Host + "/api/records";
	req.Headers["Content-Type"] = "application/json";
	req.Headers["Authorization"] = "Bearer " + g_APIToken;
		req.Body = data;
	req.Start();
       

        while (!req.Finished()) {
            yield();
            sleep(50);
            } 
			if (req.ResponseCode() != 200) {
		error("API Error, http error " + req.ResponseCode());}

}



  g_CurrentyUpdating = false;
}


 
/* GET INFO FROM GAME */
 
uint GetPlayersInServerCount() {
    auto cp = cast<CTrackMania>(GetApp()).CurrentPlayground;
    if (cp is null) return 0;
    return cp.Players.Length;
}
 
string GetLocalPlayerWSID() {
    try {
        return GetApp().Network.ClientManiaAppPlayground.LocalUser.WebServicesUserId;
    } catch {
        return "";
    }
}
 
// array<CGamePlayer@>@ GetPlayersInServer() {
array<CSmPlayer@>@ GetPlayersInServer() {
    auto cp = cast<CTrackMania>(GetApp()).CurrentPlayground;
    if (cp is null) return {};
    array<CSmPlayer@> ret;
    for (uint i = 0; i < cp.Players.Length; i++) {
        auto player = cast<CSmPlayer>(cp.Players[i]);
        if (player !is null) ret.InsertLast(player);
    }
    return ret;
}
 
// Returns a sorted list of player PB time objects. This is assumed to be called only from UpdateRecords().

 
 
/* hotkey */
 

 
 
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
 
     bool g_CurrentyUpdating = false;
 
bool autoUpdate = false;


 void CopyToClipboard() {
     
     auto cp = cast<CTrackMania>(GetApp()).CurrentPlayground;     
    if (cp is null) return;    

     CTrackMania@ app = cast<CTrackMania>(GetApp());
    if(app.RootMap is null){
        print("MAP NULL");
        return;
    }
    auto raceData = MLFeed::GetRaceData_V4();
	string mapName = app.RootMap.MapName; 	
	string mapUid = raceData.lastMap;

    string data = "RaceData: \n\n";
    for (uint i = 0; i < raceData.SortedPlayers_TimeAttack.Length; i++){
        auto player = cast<MLFeed::PlayerCpInfo_V4>(raceData.SortedPlayers_TimeAttack[i]);

		string pData = player.name + ";";
		pData += player.WebServicesUserId  + ";";
        
        pData += mapUid + ";";
		 pData += mapName + ";";	
         pData += Time::Format(player.BestTime) + ";";		
		pData += Time::Stamp + ";";

        data += pData + "\n";
    }

auto keys = g_addedTimes.GetKeys();

string DictData = "\nDictData: \n\n";
for(int i = 0; i < keys.Length; i++){
    int time = int(g_addedTimes[keys[i]]);
    DictData += keys[i] + ";" + time + ";\n";
}

data += DictData;
    IO::SetClipboard(data);
	 print("Copied current RaceData to Clipboard");
}


void DrawUI() {
    if (!PermissionsOkay) return;
    if (!S_ShowWindow) return;
    if (SoloModeExitCheck()) return;
    // if no map or no editor
    if (!PlaygroundNotNullAndEditorNull) return;
 
    int uiFlags = UI::WindowFlags::NoCollapse;
    
 
 
    UI::SetNextWindowSize(100, 100, UI::Cond::FirstUseEver);
    if (UI::Begin("Campaign Hunters", S_ShowWindow, uiFlags)) {
        if (GetApp().CurrentPlayground is null || GetApp().Editor !is null) {
            UI::Text("Not in a map \\$999(or in editor).");
        } 
		else {
 
            // put everything in a child so buttons work when interface is hidden
            if (UI::BeginChild("##pbs-full-ui", UI::GetContentRegionAvail())) {
 
                // refresh/loading    #N Players: 22    Your Rank: 19 / 22
          
                    UI::AlignTextToFramePadding();
                    auto curPos1 = UI::GetCursorPos();
                    autoUpdate = (UI::Checkbox("Autoupdate", autoUpdate));

                    if (g_CurrentyUpdating) {
                        UI::Text("Updating...");
                    } else {
                        if (UI::Button("Copy to clipboard##local-plrs-pbs")) {
                            startnew(CopyToClipboard);
                        }
                        UI::Text("Added Records: " + g_addedTimes.GetKeys().Length);
                        
                      
                    }
 
 
               
 
 
 
            }
            UI::EndChild();
        }
    }
    UI::End();
}