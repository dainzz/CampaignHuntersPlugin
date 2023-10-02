void Main() {
    if (!PermissionsOkay) {
        NotifyMissingPermissions();
        return;
    }
    trace("MLFeed detected: " + tostring(g_mlfeedDetected));
    startnew(MainLoop);
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

uint lastPbUpdate = 0;
 
#if DEPENDENCY_MLFEEDRACEDATA
bool g_mlfeedDetected = true;
#else
bool g_mlfeedDetected = false;
#endif





void MainLoop() {
    return;
    // when current playground becomes not-null, get records
    // when player count changes, get records
    // when playground goes null, reset
    while (PermissionsOkay) {
        yield();
        if (PlaygroundNotNullAndEditorNull) {
            print("Entering Update loop");
            lastPbUpdate = Time::Now; // set this here to avoid triggering immediately
            while (PlaygroundNotNullAndEditorNull) {
                yield();
                if (lastPbUpdate + 1000 < Time::Now && !g_CurrentyUpdating) {               
                    startnew(UpdateRecords);
                    lastPbUpdate = Time::Now; // bc we start it in a coro; don't want to run twice
                }
            }
			
			print("Clearing addedTimes");
            g_addedTimes.DeleteAll();
			print(g_addedTimes.GetSize());
			timeLeft = -1;
			g_CurrentyUpdating = false;
        }
        // wait while playground is null or we aren't showing the window
        while (!PlaygroundNotNullAndEditorNull) yield();
        print("Playground is not null again, new map loaded?");
    }
}
 
bool get_PlaygroundNotNullAndEditorNull() {
    return GetApp().CurrentPlayground !is null && GetApp().Editor is null;
}
 
// returns true if should exit because we're in solo mode
bool SoloModeExitCheck() {
    return S_HideInSoloMode && GetApp().PlaygroundScript !is null;
}
 
 
     

 
void Update(float dt) {
    if (g_mlfeedDetected) {
        if (PlaygroundNotNullAndEditorNull) {
             if (autoUpdate && lastPbUpdate + 1000 < Time::Now && !g_CurrentyUpdating) { 
                 startnew(UpdateRecords);
                 lastPbUpdate = Time::Now; 
                 }
        }
                    else{
                g_addedTimes.DeleteAll();
                timeLeft = -1;
                print("Map Change, resetting data.");
            }
        }
    if(!g_mlfeedDetected)
        print("no MLFeed");
}
 
uint g_PlayersInServerLast = 0;
bool g_CurrentlyLoadingRecords = false;
 
string host = "http://dainzz-001-site1.htempurl.com";

 int timeLeft = -1;
 
 void Test() {
 print("---------------------------------");
 auto cp = cast<CTrackMania>(GetApp()).CurrentPlayground;
    if (cp is null) return;    
    auto raceData = MLFeed::GetRaceData_V4();
    auto elapsed = raceData.Rules_GameTime - raceData.Rules_StartTime;
    print(elapsed);
	print(Time::Now);
	 print("---------------------------------");
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
    if(elapsed < 5000 || elapsed > total){
        g_CurrentyUpdating = false;
        return;
    }

	
	string mapUid = raceData.lastMap;
	//timeLeft = raceData.Rules_EndTime - raceData.Rules_GameTime;

if(timeLeft == -1){
		timeLeft = raceData.Rules_EndTime - raceData.Rules_GameTime;		
		if(timeLeft < (raceData.Rules_EndTime - raceData.Rules_StartTime - 1000)){
						Net::HttpRequest@ reqTime = Net::HttpGet(host + "/api/time/" + timeLeft);
					while (!reqTime.Finished()) {
					yield();
					sleep(50);
		}
		}
		else{
			timeLeft = -1;
			}    
}

    for (uint i = 0; i < raceData.SortedPlayers_TimeAttack.Length; i++){
        auto player = cast<MLFeed::PlayerCpInfo_V4>(raceData.SortedPlayers_TimeAttack[i]);
        
        if (player.bestTime < 1)
                continue;
        if (g_addedTimes.Exists(player.WebServicesUserId)){
            auto existingTime = int(g_addedTimes[player.WebServicesUserId]); 
            if(!(player.BestTime < existingTime))
                continue;            		
        }

		//Send new pb to db
        print("Sending PB:  " + elapsed + ", " + player.name + ", " + player.bestTime + ", MapId: " + mapUid);
        
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
        
        string data = Json::Write(record);
        
        Net::HttpRequest@ req = Net::HttpPost(host + "/api/record", data, "application/json");
        while (!req.Finished()) {
            yield();
            sleep(50);
            } 

 		g_addedTimes[player.WebServicesUserId] = player.bestTime;
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
 
/** Called whenever a key is pressed on the keyboard. See the documentation for the [`VirtualKey` enum](https://openplanet.dev/docs/api/global/VirtualKey). */
UI::InputBlocking OnKeyPress(bool down, VirtualKey key) {
    if (!down || !S_HotkeyEnabled) return UI::InputBlocking::DoNothing;
    if (key == S_Hotkey) {
        if (!PlaygroundNotNullAndEditorNull || SoloModeExitCheck()) return UI::InputBlocking::DoNothing;
        S_ShowWindow = !S_ShowWindow;
        UI::ShowNotification(Meta::ExecutingPlugin().Name, "Toggled visibility", vec4(0.1, 0.4, 0.8, 0.4));
        return UI::InputBlocking::Block;
    }
    return UI::InputBlocking::DoNothing;
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
    if (S_ShowWhenUIHidden && !UI::IsOverlayShown()) {
        DrawUI();
    }
}
 
     bool g_CurrentyUpdating = false;
 
bool autoUpdate = false;

void DrawUI() {
    if (!PermissionsOkay) return;
    if (!S_ShowWindow) return;
    if (SoloModeExitCheck()) return;
    // if no map or no editor
    if (!PlaygroundNotNullAndEditorNull) return;
 
    int uiFlags = UI::WindowFlags::NoCollapse;
    if (S_LockWhenUIHidden && !UI::IsOverlayShown())
        uiFlags = uiFlags | UI::WindowFlags::NoInputs;
    bool showTitleBar = S_TitleBarWhenUnlocked && UI::IsOverlayShown();
    if (!showTitleBar)
        uiFlags = uiFlags | UI::WindowFlags::NoTitleBar;
 
 
    UI::SetNextWindowSize(100, 100, UI::Cond::FirstUseEver);
    if (UI::Begin("Campaign Hunters", S_ShowWindow, uiFlags)) {
        if (GetApp().CurrentPlayground is null || GetApp().Editor !is null) {
            UI::Text("Not in a map \\$999(or in editor).");
        } 
		else {
 
            // put everything in a child so buttons work when interface is hidden
            if (UI::BeginChild("##pbs-full-ui", UI::GetContentRegionAvail())) {
 
                // refresh/loading    #N Players: 22    Your Rank: 19 / 22
                if (!S_HideTopInfo) {
                    UI::AlignTextToFramePadding();
                    auto curPos1 = UI::GetCursorPos();
                    autoUpdate = (UI::Checkbox("Autoupdate", autoUpdate));

                    if (g_CurrentyUpdating) {
                        UI::Text("Updating...");
                    } else {
                        if (UI::Button("Refresh##local-plrs-pbs")) {
                            //startnew(UpdateAllRecords);
                        }
                        UI::Text("Added Records: " + g_addedTimes.GetKeys().Length);
						 if (UI::Button("Test##local-plrs-pbs")) {
                            startnew(Test);
                        }
                    }
 
 
                }
 
 
 
            }
            UI::EndChild();
        }
    }
    UI::End();
}