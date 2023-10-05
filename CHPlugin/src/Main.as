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

 bool ValidState(){
    CTrackMania@ app = cast<CTrackMania>(GetApp());
    if(app.PlaygroundScript !is null) return false; //Solomode
    if(app.Editor !is null) return false; //Editor
    if(app.RootMap is null) return false; //Main Menu
    return true;
 }
 bool RoundStarted(){
   	auto raceData = MLFeed::GetRaceData_V4(); 
    //timeLeft = raceData.Rules_EndTime - raceData.Rules_GameTime;
    //int totalTime = raceData.Rules_EndTime - raceData.Rules_StartTime; might be < 0 before round starts
    //if(timeLeft > 0 )
    //    return true;
    if(raceData.Rules_StartTime > 0 && raceData.Rules_EndTime > 0)
        return true;
    return false;
 }

string g_PreviousMap = "";

 bool NewMap(){
    CTrackMania@ app = cast<CTrackMania>(GetApp());
    if(app.RootMap is null){
       return false;}
    if(g_PreviousMap != app.RootMap.IdName)
    {
        g_PreviousMap = app.RootMap.IdName;
        return true;
    }
    return false;
 }

void Update(float dt) {
    if (g_mlfeedDetected) {
        if (PlaygroundNotNullAndEditorNull) {
             if (autoUpdate && lastPbUpdate + S_SyncInterval < Time::Now && !g_CurrentyUpdating) {
                if(!ValidState()) return; 
                if(!RoundStarted()) return;
                if(NewMap()){
                    g_TimerSynced = false;  
                    g_addedTimes.DeleteAll();              
                }                
                 startnew(UpdateRecords);
                 lastPbUpdate = Time::Now; 
                 }
        }
                
        }
   
}


bool g_CurrentyUpdating = false;
bool autoUpdate = false;
bool g_TimerSynced = false;
 
 
 void Test() {
 print("---------------------------------");
     auto mapg = cast<CTrackMania>(GetApp()).Network.ClientManiaAppPlayground;
            if (mapg is null) {print("MAP IS NULL");return;}
            auto scoreMgr = mapg.ScoreMgr;
            auto userMgr = mapg.UserMgr;
            if (scoreMgr is null || userMgr is null)
            {
                print("Score or User is null");
            };
	auto raceData = MLFeed::GetRaceData_V4(); 
        print(raceData.SortedPlayers_TimeAttack.Length);
return;
    for(int i = 0; i < raceData.SortedPlayers_TimeAttack.Length;i++){
        auto player = cast<MLFeed::PlayerCpInfo_V4>(raceData.SortedPlayers_TimeAttack[i]);
        if(player.bestTime > 0)
            print(player.name + ": " + Time::Format(player.bestTime));
    }

}

 
void UpdateRecords() {
  	g_CurrentyUpdating = true;    
    CTrackMania@ app = cast<CTrackMania>(GetApp());
    if(app.RootMap is null){
        print("MAP NULL");
        g_CurrentyUpdating = false;
        return;
    }
	string mapName = app.RootMap.MapName;
 
	auto raceData = MLFeed::GetRaceData_V4(); 

	string mapUid = raceData.lastMap;

    if(!g_TimerSynced){  
        auto timeLeft = raceData.Rules_EndTime - raceData.Rules_GameTime;
        if (timeLeft > 0) {
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
           g_TimerSynced = true;
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
    print("Sending " + jsonData.Length + " records to API.");
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
                error("API Error, HTTP Error " + req.ResponseCode());
                }

}

 g_CurrentyUpdating = false;
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
    if (!S_ShowWindow) return;  
 
    int uiFlags = UI::WindowFlags::NoCollapse;
 
    UI::SetNextWindowSize(100, 100, UI::Cond::FirstUseEver);
    if (UI::Begin("Campaign Hunters", S_ShowWindow, uiFlags)) {
   
 
            // put everything in a child so buttons work when interface is hidden
            if (UI::BeginChild("##pbs-full-ui", UI::GetContentRegionAvail())) {
           
                    UI::AlignTextToFramePadding();
                    auto curPos1 = UI::GetCursorPos();
                    autoUpdate = (UI::Checkbox("Autoupdate", autoUpdate));

                    if (g_CurrentyUpdating) {
                        UI::Text("Updating...");
                    } else {
                        if (UI::Button("Copy to clipboard##local-plrs-pbs")) {
                            startnew(CopyToClipboard);
                        } 
                        if (UI::Button("Print RaceData Length##local-plrs-pbs")) {
                            startnew(Test);
                        }
                        UI::Text("Added Records: " + g_addedTimes.GetKeys().Length);
                        
                      
                    }
 
 
               
 
 
 
            }
            UI::EndChild();
        
    }
    UI::End();
}