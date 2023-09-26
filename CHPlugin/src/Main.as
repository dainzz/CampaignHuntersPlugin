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

#if DEPENDENCY_MLFEEDRACEDATA
bool g_mlfeedDetected = true;
#else
bool g_mlfeedDetected = false;
#endif


uint lastPbUpdate = 0;

void MainLoop() {
    // when current playground becomes not-null, get records
    // when player count changes, get records
    // when playground goes null, reset
    while (PermissionsOkay) {
        yield();
        if (PlaygroundNotNullAndEditorNull && S_ShowWindow) {
            //startnew(UpdateRecords);
            lastPbUpdate = Time::Now; // set this here to avoid triggering immediately
            while (PlaygroundNotNullAndEditorNull && S_ShowWindow) {
                yield();
                if (g_PlayersInServerLast != GetPlayersInServerCount() || lastPbUpdate + 60000 < Time::Now) {
                    g_PlayersInServerLast = GetPlayersInServerCount();
                    //startnew(UpdateRecords);
                    lastPbUpdate = Time::Now; // bc we start it in a coro; don't want to run twice
                }
            }
            g_Records.RemoveRange(0, g_Records.Length);
        }
        // wait while playground is null or we aren't showing the window
        while (!PlaygroundNotNullAndEditorNull || !S_ShowWindow) yield();
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
    if (g_mlfeedDetected && !S_SkipMLFeedCheck && S_ShowWindow) {
        // checking this every frame has minimal overhead; <0.1ms
        CheckMLFeedForBetterTimes();
    }
}

uint g_PlayersInServerLast = 0;
array<PBTime@> g_Records;
bool g_CurrentlyLoadingRecords = false;

void UpdateRecords() {
	
	 CTrackMania@ app = cast<CTrackMania>(GetApp());
    string mapUid = app.RootMap.MapInfo.MapUid;
	string mapName = app.RootMap.MapName;
	
	
	auto mapg = cast<CTrackMania>(GetApp()).Network.ClientManiaAppPlayground;
    if (mapg is null) return;
    auto scoreMgr = mapg.ScoreMgr;
    auto userMgr = mapg.UserMgr;
    if (scoreMgr is null || userMgr is null) return ;
    auto players = GetPlayersInServer();
    if (players.Length == 0) return;

	auto raceData = MLFeed::GetRaceData_V4();	

	
	auto timeLeft = raceData.Rules_EndTime - raceData.Rules_GameTime;
	
	
			         Net::HttpRequest@ reqTime = Net::HttpGet("http://dainzz-001-site1.htempurl.com/api/time/" + timeLeft);
        while (!reqTime.Finished()) {
            yield();
            sleep(50);
			}
	
	
	Json::Value jsonData = Json::Array();
	
		for (uint i = 0; i < raceData.SortedPlayers_TimeAttack.Length; i++){
		
		auto player = cast<MLFeed::PlayerCpInfo_V4>(raceData.SortedPlayers_TimeAttack[i]);
		if(player.bestTime < 1)
			continue;
		
		string guid = player.WebServicesUserId;
		
		Json::Value playerObj = Json::Object();
		
		playerObj["Name"] = player.name;
		playerObj["PlayerId"] = guid;
		
		
		Json::Value map = Json::Object();
				
		map["MapId"] = mapUid;
		map["Name"] = mapName;	
		
		Json::Value record = Json::Object();
		
			record["Time"] = player.BestTime;
			record["Map"] = map;
			record["Player"] = playerObj;
			
		 
		 string data = Json::Write(record);
		 
		  //IO::SetClipboard(data);
			 
			 //string url = "http://192.168.178.75:7236/api/record";
			 string url = "http://dainzz-001-site1.htempurl.com/api/record";
			 
			 
			 
			 
			         Net::HttpRequest@ req = Net::HttpPost(url, data, "application/json");
        while (!req.Finished()) {
            yield();
            sleep(50);
        } 
			 
			 
	
  }	 			

			 
			 
	
}

// fast enough to call once per frame
uint lastLPR_Rank;
uint lastLPR_Time;
uint get_LocalPlayersRank() {
    // once per frame
    if (lastLPR_Time + 5 > Time::Now) return lastLPR_Rank;
    // otherwise update
    lastLPR_Time = Time::Now;
    lastLPR_Rank = g_Records.Length;
    for (uint i = 0; i < g_Records.Length; i++) {
        if (g_Records[i].isLocalPlayer) {
            lastLPR_Rank = i + 1;
            break;
        }
    }
    return lastLPR_Rank;
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
array<PBTime@> GetPlayersPBs() {
    auto mapg = cast<CTrackMania>(GetApp()).Network.ClientManiaAppPlayground;
    if (mapg is null) return {};
    auto scoreMgr = mapg.ScoreMgr;
    auto userMgr = mapg.UserMgr;
    if (scoreMgr is null || userMgr is null) return {};
    auto players = GetPlayersInServer();
    if (players.Length == 0) return {};
    auto playerWSIDs = MwFastBuffer<wstring>();
    dictionary wsidToPlayer;
    for (uint i = 0; i < players.Length; i++) {
        playerWSIDs.Add(players[i].User.WebServicesUserId);
        @wsidToPlayer[players[i].User.WebServicesUserId] = players[i];
    }

    g_CurrentlyLoadingRecords = true;
    auto rl = scoreMgr.Map_GetPlayerListRecordList(userMgr.Users[0].Id, playerWSIDs, GetApp().RootMap.MapInfo.MapUid, "PersonalBest", "", "", "");
    while (rl.IsProcessing) yield();
    g_CurrentlyLoadingRecords = false;

    if (rl.HasFailed || !rl.HasSucceeded) {
        warn("Requesting records failed. Type,Code,Desc: " + rl.ErrorType + ", " + rl.ErrorCode + ", " + rl.ErrorDescription);
        return {};
    }

    /* note:
        - usually we expect `rl.MapRecordList.Length != players.Length`
        - `players[i].User.WebServicesUserId != rl.MapRecordList[i].WebServicesUserId`
       so we use a dictionary to look up the players (wsidToPlayer we set up earlier)
    */

    string localWSID = GetLocalPlayerWSID();

    array<PBTime@> ret;
    for (uint i = 0; i < rl.MapRecordList.Length; i++) {
        auto rec = rl.MapRecordList[i];
        auto _p = cast<CSmPlayer>(wsidToPlayer[rec.WebServicesUserId]);
        if (_p is null) {
            warn("Failed to lookup player from temp dict");
            continue;
        }
        ret.InsertLast(PBTime(_p, rec, rec.WebServicesUserId == localWSID));
        // remove the player so we can quickly get all players in server that don't have records
        wsidToPlayer.Delete(rec.WebServicesUserId);
    }
    // get pbs for players without pbs
    auto playersWOutRecs = wsidToPlayer.GetKeys();
    for (uint i = 0; i < playersWOutRecs.Length; i++) {
        auto wsid = playersWOutRecs[i];
        auto player = cast<CSmPlayer>(wsidToPlayer[wsid]);
        try {
            // sometimes we get a null pointer exception here on player.User.WebServicesUserId
            ret.InsertLast(PBTime(player, null));
        } catch {
            warn("Got exception updating records. Will retry in 500ms. Exception: " + getExceptionInfo());
            //startnew(RetryRecordsSoon);
        }
    }
    ret.SortAsc();
    return ret;
}


class ServerPB{
string name;
uint time;

int opCmp(ServerPB@ other) const {
        if (time == 0) {
            return (other.time == 0 ? 0 : 1); // one or both PB unset
        }
        if (other.time == 0 || time < other.time) return -1;
        if (time == other.time) return 0;
        return 1;
    }
}

class PBTime {
    string name;
    string club;
    string wsid;
    uint time;
    string timeStr;
    string replayUrl;
    uint recordTs;
    string recordDate;
    bool isLocalPlayer;

    PBTime(CSmPlayer@ _player, CMapRecord@ _rec, bool _isLocalPlayer = false) {
        wsid = _player.User.WebServicesUserId; // rare null pointer exception here? `[        Platform] [11:24:26] [players-pbs-dev]  Invalid address for member ID 03002000. This is likely a Nadeo bug! Setting it to null!`
        name = _player.User.Name;
        club = _player.User.ClubTag;
        isLocalPlayer = _isLocalPlayer;
        if (_rec !is null) {
            time = _rec.Time;
            replayUrl = _rec.ReplayUrl;
            recordTs = _rec.Timestamp;
        } else {
            time = 0;
            replayUrl = "";
            recordTs = 0;
        }
        UpdateCachedStrings();
    }

    void UpdateCachedStrings() {
        timeStr = time == 0 ? "???" : Time::Format(time);
        recordDate = recordTs == 0 ? "??-??-?? ??:??" : Time::FormatString("%y-%m-%d %H:%M", recordTs);
    }

    int opCmp(PBTime@ other) const {
        if (time == 0) {
            return (other.time == 0 ? 0 : 1); // one or both PB unset
        }
        if (other.time == 0 || time < other.time) return -1;
        if (time == other.time) return 0;
        return 1;
    }
}

#if DEPENDENCY_MLFEEDRACEDATA
void CheckMLFeedForBetterTimes() {
    auto raceData = MLFeed::GetRaceData();
    bool foundBetter = false;
    for (uint i = 0; i < g_Records.Length; i++) {
        auto pbTime = g_Records[i];
        auto player = raceData.GetPlayer(pbTime.name);
        if (player is null) continue;
        if (player.bestTime < 1) continue;
        if (player.bestTime < int(pbTime.time) || pbTime.time < 1) {
            pbTime.time = player.bestTime;
            pbTime.recordTs = Time::Stamp;
            pbTime.replayUrl = "";
            pbTime.UpdateCachedStrings();
            foundBetter = true;
        }
    }

    // found a better time, so update PBs order
    if (foundBetter) {
        g_Records.SortAsc();
    }
}
#else
void CheckMLFeedForBetterTimes() {}
#endif





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
                    if (g_CurrentlyLoadingRecords) {
                        UI::Text("Updating...");
                    } else {
                        if (UI::Button("Refresh##local-plrs-pbs")) {
                            startnew(UpdateRecords);
                        }
                    }
                               
     
                }


               
            }
            UI::EndChild();
        }
    }
    UI::End();
}
