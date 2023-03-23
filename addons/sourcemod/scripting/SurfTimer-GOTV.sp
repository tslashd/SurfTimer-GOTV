#include <colorlib>
#include <cstrike>
#include <filesystem>
#include <sourcemod>
#include <sourcetvmanager>
#include <surftimer>
#include <unixtime_sourcemod>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION	"0.3"

/*-> Database table name to use for connection <-*/
#define DB_Name			"wr_demos"
#define DB_Name_Expired "wr_demos_expired"
/*###############################################*/

/*-> Menus <-*/
Menu		  menu_main;
Menu		  submenu_main;
Menu		  menu_list_demos;

/*-> DB <-*/
Database	  db = null;

/*-> FORWARDS <-*/
GlobalForward g_SelectedDemo;

/*-> ConVars <-*/
ConVar		  gc_tvEnabled;
ConVar		  gc_ServerTickrate;
ConVar		  gc_LogPath;
ConVar		  gc_DemoPath;
ConVar		  gc_HostName;
ConVar		  gc_MapLogPath;
ConVar		  gc_FastDL;
ConVar		  gc_DownloadURL;
ConVar		  gc_Prefix;

/*-> Global Variables <-*/
bool		  g_blnMapEnd			= false;
bool		  g_bIsSurfTimerEnabled = false;
bool		  g_bIsRecordWR			= false;
bool		  g_bPersonalDemos[MAXPLAYERS];
char		  g_strMapName[128];
char		  g_strDemoName[500];
char		  g_strDemoPath[PLATFORM_MAX_PATH];
char		  g_strTime[128];
char		  g_strLogFile[500];
char		  g_strMapLog[500];
char		  g_strWRLog[500];
char		  g_strHostName[500];
char		  g_strPlayerWR[MAX_NAME_LENGTH];
char		  g_strTimeWR[128];
char		  g_strFastDL[256];
char		  g_strDownloadURL[256];
char		  g_strPrefix[256];
int			  g_intDemoNumber = 0;
int			  g_intWRCount	  = 0;

EngineVersion g_EngineVersion;

public Plugin myinfo =
{
	name		= "SurfTimer | GOTV",
	author		= "tslashd",
	description = "Log runs and record demos",
	version		= PLUGIN_VERSION,
	url			= "connect clarity.surf"
};

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	// No need for the old GetGameFolderName setup.
	g_EngineVersion = GetEngineVersion();
	if (g_EngineVersion != Engine_CSGO)
	{
		SetFailState("This plugin was made for use with Counter-Strike: Global Offensive only.");
		return APLRes_Failure;
	}
	return APLRes_Success;
}

public void OnPluginStart()
{
	gc_LogPath		  = CreateConVar("sm_ck_gotv_log", "", "Path to where the log should be stored (addons/sourcemod/logs/_SurfTimer-GOTV.txt)");
	gc_MapLogPath	  = CreateConVar("sm_ck_gotv_maplogpath", "", "Path to where the log files for each map will be stored without trailing / (.demos/_maps)");
	gc_DemoPath		  = CreateConVar("sm_ck_gotv_demopath", "", "Path to where the demo files should be stored without trailing / (.demos/Private)");
	gc_DownloadURL	  = CreateConVar("sm_ck_gotv_downloadurl", "", "URL where the demos recorded from the plugin could be accessed");
	gc_Prefix		  = CreateConVar("sm_ck_gotv_prefix", "", "Prefix for the plugin");
	gc_FastDL		  = FindConVar("sv_downloadurl");
	gc_ServerTickrate = FindConVar("sv_maxupdaterate");

	// TEST
	RegAdminCmd("sm_demos_test", Command_Test, ADMFLAG_ROOT, "Test");
	RegConsoleCmd("sm_demos", Menu_Command, "List all demos available for client");
	RegConsoleCmd("sm_demos_list", Menu_Command, "List all demos available for client");
	RegConsoleCmd("sm_admin_demos", Menu_Command, "List all demos available for client");
	RegConsoleCmd("sm_wrdemos", Menu_Command, "List all demos available for client");

	CreateConVar("sm_demorecorder_version", PLUGIN_VERSION, "Standard plugin version ConVar. Please don't change me!", FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DONTRECORD);

	AutoExecConfig(true, "SurfTimer-GOTV");
	InitForwards();

	// DB stuff
	if (SQL_CheckConfig("demo_recorder")) SQL_TConnect(OnDatabaseConnect, "demo_recorder");
	else SetFailState("Can't find 'demo_recorder' entry in sourcemod/configs/databases.cfg!");
}

public void OnAllPluginsLoaded()
{
	g_bIsSurfTimerEnabled = LibraryExists("surftimer");
}

public void OnLibraryAdded(const char[] name)
{
	g_bIsSurfTimerEnabled = StrEqual(name, "surftimer") ? true : g_bIsSurfTimerEnabled;
}

public void OnLibraryRemoved(const char[] name)
{
	g_bIsSurfTimerEnabled = StrEqual(name, "surftimer") ? false : g_bIsSurfTimerEnabled;
}

public void OnMapStart()
{
	float fRecordTime;
	g_blnMapEnd	 = false;
	gc_tvEnabled = FindConVar("tv_enable");
	if (!gc_tvEnabled.BoolValue)
		SetFailState("GOTV is NOT enabled on this server.");

	surftimer_GetMapData(g_strPlayerWR, g_strTimeWR, fRecordTime);
}

public void OnConfigsExecuted()
{
	g_intDemoNumber = 0;
	g_intWRCount	= 0;

	GetConVarString(gc_Prefix, g_strPrefix, sizeof(g_strPrefix));
}

Action Timer_StartRecording(Handle timer, int client)
{
	if (SourceTV_IsRecording())
		return Plugin_Handled;

	if (!IsClientSourceTV(client) && !IsFakeClient(client) && !SourceTV_IsRecording() && IsClientInGame(client))
	{
		Start_Recording();
	}

	return Plugin_Handled;
}

public void OnClientPostAdminCheck(int client)
{
	if (!IsClientSourceTV(client) && !IsFakeClient(client) && !SourceTV_IsRecording())
		CreateTimer(2.0, Timer_StartRecording, client);
}

public void OnClientDisconnect_Post(int client)
{
	if (GetRealClientCount() <= 0 && !g_blnMapEnd && SourceTV_IsRecording())
		Stop_Recording();
}

public void OnMapEnd()
{
	g_blnMapEnd = true;
	if (SourceTV_IsRecording()) Stop_Recording();
}

public void surftimer_OnNewRecord(int client, int style, char[] time, char[] timeDif, int bonusGroup)
{
	g_intWRCount  = g_intWRCount + 1;
	g_bIsRecordWR = true;
	char playerName[MAX_NAME_LENGTH], demoMessage[256];
	GetClientName(client, playerName, sizeof(playerName));

	if (bonusGroup != -1)
	{
		Format(g_strWRLog, sizeof(g_strWRLog), "WRB %d [%s] | %s by %s --- Time %s --- Improved %s ---", bonusGroup, GetStyle(style), g_strMapName, playerName, time, timeDif);
		Format(demoMessage, sizeof(demoMessage), "WRB %d [%s] | %s by %s --- Time %s --- Improved %s ---", bonusGroup, GetStyle(style), g_strMapName, playerName, time, timeDif);
		SourceTV_PrintToDemoConsole("%s", demoMessage);
	}
	else
	{
		Format(g_strWRLog, sizeof(g_strWRLog), "WR [%s] | %s by %s --- Time %s --- Improved %s --- Previous: %s [%s]", GetStyle(style), g_strMapName, playerName, time, timeDif, g_strPlayerWR, g_strTimeWR);
		Format(demoMessage, sizeof(demoMessage), "WR [%s] | %s by %s --- Time %s --- Improved %s --- Previous: %s [%s]", GetStyle(style), g_strMapName, playerName, time, timeDif, g_strPlayerWR, g_strTimeWR);
		SourceTV_PrintToDemoConsole("%s", demoMessage);
	}
}

public void surftimer_OnNewWRCP(int client, int style, char[] time, char[] timeDif, int stage, float fRunTime)
{
	g_intWRCount		= g_intWRCount + 1;
	g_intDemoNumber		= g_intDemoNumber + 1;
	float floatTickRate = GetConVarFloat(gc_ServerTickrate);
	int	  currentTick	= SourceTV_GetRecordingTick();
	char  playerName[MAX_NAME_LENGTH], demoMessage[256], wrcpEndTick[64], wrcpStartTick[64], query[1024], playerId[64];
	GetClientName(client, playerName, sizeof(playerName));
	GetClientAuthId(client, AuthId_SteamID64, playerId, sizeof(playerId));

	Format(wrcpEndTick, sizeof(wrcpEndTick), "%d", currentTick);
	Format(wrcpStartTick, sizeof(wrcpStartTick), "%.0f", currentTick - fRunTime * floatTickRate);
	Format(g_strWRLog, sizeof(g_strWRLog), "WRCP %d [%s] | %s by %s --- Time %s --- Improved %s --- StartTick %s --- EndTick %s --- %s", stage, GetStyle(style), g_strMapName, playerName, time, timeDif, wrcpStartTick, wrcpEndTick, g_strDemoName);
	Format(demoMessage, sizeof(demoMessage), "WRCP %d [%s] | %s by %s --- Time %s --- Improved %s ---", stage, GetStyle(style), g_strMapName, playerName, time, timeDif);
	SourceTV_PrintToDemoConsole("%s", demoMessage);

	Format(query, sizeof(query), "INSERT INTO %s (SteamId, RunTime, StartTick, EndTick, DemoName, Server, Bonus, Stage, Date, MapFinished, Style, IsRecord, FastDL, DownloadURL, Tickrate) VALUES ('%s', '%s', '%s', '%s', '%s', '%s', '0', '%d', NOW(), '0', '%d', '1', '%s', '%s', '%.1f')", DB_Name, playerId, time, wrcpStartTick, wrcpEndTick, g_strDemoName, g_strHostName, stage, style, g_strFastDL, g_strDownloadURL, floatTickRate);
	db.Query(SQL_ErrorCheckCallback, query);

	populateLog(g_strWRLog);
	populateMapLog(g_strWRLog);
}

public void surftimer_OnStageFinished(int client, int style, char[] time, char[] timeDif, int stage, float fRunTime, float fClientRunTime)
{
	g_intWRCount		= g_intWRCount + 1;
	g_intDemoNumber		= g_intDemoNumber + 1;
	float floatTickRate = GetConVarFloat(gc_ServerTickrate);
	int	  currentTick	= SourceTV_GetRecordingTick();
	char  playerName[MAX_NAME_LENGTH], demoMessage[256], wrcpEndTick[64], wrcpStartTick[64], query[1024], playerId[64];
	GetClientName(client, playerName, sizeof(playerName));
	GetClientAuthId(client, AuthId_SteamID64, playerId, sizeof(playerId));

	Format(wrcpEndTick, sizeof(wrcpEndTick), "%d", currentTick);
	Format(wrcpStartTick, sizeof(wrcpStartTick), "%.0f", currentTick - fClientRunTime * floatTickRate);
	Format(g_strWRLog, sizeof(g_strWRLog), "Stage %d [%s] | %s by %s --- Time %s --- Difference %s --- StartTick %s --- EndTick %s --- %s", stage, GetStyle(style), g_strMapName, playerName, time, timeDif, wrcpStartTick, wrcpEndTick, g_strDemoName);
	Format(demoMessage, sizeof(demoMessage), "Stage %d [%s] | %s by %s --- Time %s --- Difference %s ---", stage, GetStyle(style), g_strMapName, playerName, time, timeDif);
	SourceTV_PrintToDemoConsole("%s", demoMessage);

	Format(query, sizeof(query), "INSERT INTO %s (SteamId, RunTime, StartTick, EndTick, DemoName, Server, Bonus, Stage, Date, MapFinished, Style, IsRecord, FastDL, DownloadURL, Tickrate) VALUES ('%s', '%s', '%s', '%s', '%s', '%s', '0', '%d', NOW(), '0', '%d', '0', '%s', '%s', '%.1f')", DB_Name, playerId, time, wrcpStartTick, wrcpEndTick, g_strDemoName, g_strHostName, stage, style, g_strFastDL, g_strDownloadURL, floatTickRate);
	db.Query(SQL_ErrorCheckCallback, query);

	populateLog(g_strWRLog);
	populateMapLog(g_strWRLog);
}

public Action surftimer_OnMapFinished(int client, float fRunTime, char sRunTime[54], float PBDiff, float WRDiff, int rank, int total, int style)
{
	g_intDemoNumber		= g_intDemoNumber + 1;
	float floatTickRate = GetConVarFloat(gc_ServerTickrate);
	int	  currentTick	= SourceTV_GetRecordingTick();
	char  strStartTick[64], strEndTick[64], strRunTime[64], playerName[MAX_NAME_LENGTH], query[1024], playerId[64];
	GetClientName(client, playerName, sizeof(playerName));
	GetClientAuthId(client, AuthId_SteamID64, playerId, sizeof(playerId));

	// Assign runtime, start tick, end tick - Map finished
	Format(strEndTick, sizeof(strEndTick), "%d", currentTick);
	Format(strStartTick, sizeof(strStartTick), "%.0f", currentTick - fRunTime * floatTickRate);
	Format(strRunTime, sizeof(strRunTime), "%.0f", fRunTime);

	// Is this a WR?
	if (g_bIsRecordWR)
	{
		g_bIsRecordWR = false;
		Format(g_strWRLog, sizeof(g_strWRLog), "%s StartTick %s --- EndTick %s --- %s", g_strWRLog, strStartTick, strEndTick, g_strDemoName);
		populateMapLog(g_strWRLog);
		Format(query, sizeof(query), "INSERT INTO %s (SteamId, RunTime, StartTick, EndTick, DemoName, Server, Bonus, Stage, Date, MapFinished, Style, IsRecord, FastDL, DownloadURL, Tickrate) VALUES ('%s', '%s', '%s', '%s', '%s', '%s', '0', '0', NOW(), '0', '%d', '1', '%s', '%s', '%.1f')", DB_Name, playerId, sRunTime, strStartTick, strEndTick, g_strDemoName, g_strHostName, style, g_strFastDL, g_strDownloadURL, floatTickRate);
		db.Query(SQL_ErrorCheckCallback, query);
	}
	else
	{
		Format(g_strWRLog, sizeof(g_strWRLog), "%s by %s --- Time %s (%d/%d) --- StartTick %s --- EndTick %s --- %s", g_strMapName, playerName, sRunTime, rank, total, strStartTick, strEndTick, g_strDemoName);
		Format(query, sizeof(query), "INSERT INTO %s (SteamId, RunTime, StartTick, EndTick, DemoName, Server, Bonus, Stage, Date, MapFinished, Style, IsRecord, FastDL, DownloadURL, Tickrate) VALUES ('%s', '%s', '%s', '%s', '%s', '%s', '0', '0', NOW(), '0', '%d', '0', '%s', '%s', '%.1f')", DB_Name, playerId, sRunTime, strStartTick, strEndTick, g_strDemoName, g_strHostName, style, g_strFastDL, g_strDownloadURL, floatTickRate);
		db.Query(SQL_ErrorCheckCallback, query);
	}

	populateLog(g_strWRLog);
	return Plugin_Handled;
}

public Action surftimer_OnCheckpoint(int client, float fRunTime, char sRunTime[54], float fPbCp, char sPbDiff[16], float fSrCp, char sSrDiff[16], int iCheckpoint)
{
	char demoMessage[256], playerName[MAX_NAME_LENGTH], currentTick[32];

	Format(currentTick, sizeof(currentTick), "%d", SourceTV_GetRecordingTick());
	GetClientName(client, playerName, sizeof(playerName));
	Format(demoMessage, sizeof(demoMessage), "CP %i | %s | tick: %s | PB: %s | WR: %s", iCheckpoint, playerName, currentTick, sPbDiff, sSrDiff);

	SourceTV_PrintToDemoConsole("%s", demoMessage);
	return Plugin_Handled;
}

public Action surftimer_OnBonusFinished(int client, float fRunTime, char sRunTime[54], float fPBDiff, float fSRDiff, int rank, int total, int bonusid, int style)
{
	g_intDemoNumber		= g_intDemoNumber + 1;
	int	  currentTick	= SourceTV_GetRecordingTick();
	float floatTickRate = GetConVarFloat(gc_ServerTickrate);
	char  strStartTick[64], strEndTick[64], strRunTime[64], playerName[MAX_NAME_LENGTH], query[1024], playerId[64];

	GetClientName(client, playerName, sizeof(playerName));
	GetClientAuthId(client, AuthId_SteamID64, playerId, sizeof(playerId));

	// Assign runtime, start tick, end tick - Bonus Finished
	Format(strEndTick, sizeof(strEndTick), "%d", currentTick);
	Format(strStartTick, sizeof(strStartTick), "%.0f", currentTick - fRunTime * floatTickRate);
	Format(strRunTime, sizeof(strRunTime), "%.0f", fRunTime);

	// Is this a WRB?
	if (g_bIsRecordWR)
	{
		g_bIsRecordWR = false;
		Format(g_strWRLog, sizeof(g_strWRLog), "%s StartTick %s --- EndTick %s --- %s", g_strWRLog, strStartTick, strEndTick, g_strDemoName);
		populateMapLog(g_strWRLog);
		Format(query, sizeof(query), "INSERT INTO %s (SteamId, RunTime, StartTick, EndTick, DemoName, Server, Bonus, Stage, Date, MapFinished, Style, IsRecord, FastDL, DownloadURL, Tickrate) VALUES ('%s', '%s', '%s', '%s', '%s', '%s', '%d', '0', NOW(), '0', '%d', '1', '%s', '%s', '%.1f')", DB_Name, playerId, sRunTime, strStartTick, strEndTick, g_strDemoName, g_strHostName, bonusid, style, g_strFastDL, g_strDownloadURL, floatTickRate);
		db.Query(SQL_ErrorCheckCallback, query);
	}
	else
	{
		Format(g_strWRLog, sizeof(g_strWRLog), "%s [Bonus %d] FINISHED by %s --- Time %s (%d/%d) --- StartTick %s --- EndTick %s --- %s", g_strMapName, bonusid, playerName, sRunTime, rank, total, strStartTick, strEndTick, g_strDemoName);
		Format(query, sizeof(query), "INSERT INTO %s (SteamId, RunTime, StartTick, EndTick, DemoName, Server, Bonus, Stage, Date, MapFinished, Style, IsRecord, FastDL, DownloadURL, Tickrate) VALUES ('%s', '%s', '%s', '%s', '%s', '%s', '%d', '0', NOW(), '0', '%d', '0', '%s', '%s', '%.1f')", DB_Name, playerId, sRunTime, strStartTick, strEndTick, g_strDemoName, g_strHostName, bonusid, style, g_strFastDL, g_strDownloadURL, floatTickRate);
		db.Query(SQL_ErrorCheckCallback, query);
	}

	populateLog(g_strWRLog);
	return Plugin_Handled;
}

public Action Command_Test(int client, int args)
{
	return Plugin_Handled;
}

public void OnDatabaseConnect(Handle owner, Handle hndl, const char[] error, any data)
{
	if (hndl == null || strlen(error) > 0)
	{
		PrintToServer("[SurfTV] Unable to connect to database (%s)", error);
		LogError("[SurfTV] Unable to connect to database (%s)", error);
		return;
	}
	db = view_as<Database>(hndl);	 // Set global DB Handle

	// Create Tables in DB if not exist
	char query_CreateMainTable[1024], query_CreateExpiredTable[1024];

	FormatEx(query_CreateMainTable, sizeof(query_CreateMainTable), "CREATE TABLE IF NOT EXISTS `%s` (`SteamId` varchar(64) NOT NULL, `RunTime` text NOT NULL, `StartTick` int NOT NULL, `EndTick` int NOT NULL, `DemoName` text NOT NULL, `Server` text NOT NULL, `Bonus` int NOT NULL, `Stage` int NOT NULL, `Date` datetime NOT NULL, `MapFinished` int NOT NULL, `Style` int NOT NULL, `IsRecord` int NOT NULL, `FastDL` text NOT NULL, `DownloadURL` text NOT NULL, `Tickrate` double NOT NULL, KEY `SteamId` (`SteamId`));", DB_Name);
	db.Query(SQL_ErrorCheckCallback, query_CreateMainTable, DBPrio_High);

	FormatEx(query_CreateExpiredTable, sizeof(query_CreateExpiredTable), "CREATE TABLE IF NOT EXISTS `%s` (`SteamId` varchar(64) NOT NULL, `RunTime` text NOT NULL, `StartTick` int NOT NULL, `EndTick` int NOT NULL, `DemoName` text NOT NULL, `Server` text NOT NULL, `Bonus` int NOT NULL, `Stage` int NOT NULL, `Date` datetime NOT NULL, `MapFinished` int NOT NULL, `Style` int NOT NULL, `IsRecord` int NOT NULL, `FastDL` text NOT NULL, `DownloadURL` text NOT NULL, `Tickrate` double NOT NULL, KEY `SteamId` (`SteamId`));", DB_Name_Expired);
	db.Query(SQL_ErrorCheckCallback, query_CreateExpiredTable, DBPrio_High);

	// Success Print
	PrintToServer("[SurfTV] Successfully connected to database!");

	moveExpired();
}

// Function to catch errors during queries
public void SQL_ErrorCheckCallback(Handle owner, DBResultSet results, const char[] error, any data)
{
	if (results == null || strlen(error) > 0)
	{
		LogError("[SurfTV] Query failed! %s", error);
	}
}

public Action Menu_Command(int client, int args)
{
	if (IsFakeClient(client))
		return Plugin_Handled;

	menu_main = new Menu(Main_Menu_Callback);
	menu_main.SetTitle("Select Demo Type:");

	menu_main.AddItem("item_personal_runs", "PR", ITEMDRAW_CONTROL);
	if (CheckCommandAccess(client, "", ADMFLAG_CUSTOM4))
		menu_main.AddItem("item_wrs", "WR", ITEMDRAW_CONTROL);
	else
		menu_main.AddItem("item_wrs", "WR", ITEMDRAW_DISABLED);

	menu_main.ExitButton = true;
	menu_main.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

/* Used to get and add each retrieved demo from DB to the in-game Menu */
public void SQL_ListSteamids(Handle owner, DBResultSet results, const char[] error, any userid)
{
	int client = GetClientOfUserId(userid);
	if (IsFakeClient(client)) return;	 // Stop if not valid!

	if (results == null || strlen(error) > 0)
	{
		LogError("[SurfTV] Query failed! %s", error);
		CPrintToChat(client, "%s Query failed, please try again later.", g_strPrefix);
		return;
	}

	// Everything is fine let's start
	PrintToConsole(client, "########## Available Demos ##########");
	char  SteamId[64], RunTime[32], DemoName[128], Server[128], szDate[32], buff[512], itemName[1024], itemInfo[2048], temp[32], splitArray[256][10], FastDL[256], DownloadURL[256];
	int	  Bonus, Stage, Style, IsRecord, StartTick, EndTick;
	float Tickrate;

	menu_list_demos = new Menu(Menu_Callback);
	menu_list_demos.SetTitle("Select Demo:\n ");
	menu_list_demos.ExitBackButton = true;

	/* Fetch all rows */
	while (results.FetchRow())
	{
		results.FetchString(0, SteamId, sizeof(SteamId));
		results.FetchString(1, RunTime, sizeof(RunTime));
		StartTick = results.FetchInt(2);
		EndTick	  = results.FetchInt(3);
		results.FetchString(4, DemoName, sizeof(DemoName));
		results.FetchString(5, Server, sizeof(Server));
		Bonus = results.FetchInt(6);
		Stage = results.FetchInt(7);
		results.FetchString(8, szDate, sizeof(szDate));
		Style	 = results.FetchInt(10);
		IsRecord = results.FetchInt(11);
		results.FetchString(12, FastDL, sizeof(FastDL));
		results.FetchString(13, DownloadURL, sizeof(DownloadURL));
		Tickrate = results.FetchFloat(14);

		PrintToConsole(client, "%s - %s - %s - %s [%s] - %i - %i - %s", SteamId, szDate, DemoName, RunTime, GetStyle(Style), StartTick, EndTick, Server);

		// Get mapname from query
		ExplodeString(DemoName, "surf_", splitArray, sizeof(splitArray), sizeof(splitArray));

		Format(temp, strlen(splitArray[1][0]), "%s", splitArray[1][0]);
		Format(temp, strlen(temp), "%s", temp);	   // wtf?? :D - is printed if this is not here

		// Really need a new way of doing this
		// Don't fix if it ain't broken ig lul
		Format(itemInfo, sizeof(itemInfo), "%i | %i | %s | %i | %i | %i | %s | %s | %.1f | %s | %s | %s", StartTick, EndTick, DemoName, Bonus, Stage, IsRecord, FastDL, DownloadURL, Tickrate, SteamId, temp, RunTime);
		if (Bonus > 0)
		{
			Format(buff, sizeof(buff), "[%s] Bonus: %i (%s)", GetStyle(Style), Bonus, RunTime);
			Format(itemName, sizeof(itemName), "surf_%s\n%s", temp, buff);
		}
		else if (Stage > 0)
		{
			Format(buff, sizeof(buff), "[%s] Stage: %i (%s)", GetStyle(Style), Stage, RunTime);
			Format(itemName, sizeof(itemName), "surf_%s\n%s", temp, buff);
		}
		else if (Bonus == 0 && Stage == 0)
		{
			Format(buff, sizeof(buff), "[%s] %s (%s)", GetStyle(Style), RunTime, szDate);
			Format(itemName, sizeof(itemName), "surf_%s\n%s", temp, buff);
		}
		menu_list_demos.AddItem(itemInfo, itemName, ITEMDRAW_CONTROL);
	}
	menu_list_demos.Display(client, MENU_TIME_FOREVER);
	PrintToConsole(client, "##########################################");
}

/* Main menu, select PR or WR */
public int Main_Menu_Callback(Menu menu, MenuAction action, int client, int param2)
{
	switch (action)
	{
		case MenuAction_DisplayItem:
		{
			char info[32];
			menu.GetItem(param2, info, sizeof(info));

			return RedrawMenuItem(info);
		}
		case MenuAction_Select:
		{
			char info[32], playerId[64];
			// int  flags = ReadFlagString("z");
			menu.GetItem(param2, info, sizeof(info));

			// CPrintToChat(client, "{red}[Main-Menu]{default} Param1 (client) - {yellow}%d{default} | Param2 - {yellow}%d{default}", client, param2);
			// CPrintToChat(client, "{red}[Main-Menu]{default} Info: {yellow}%s", info);
			GetClientAuthId(client, AuthId_SteamID64, playerId, sizeof(playerId));

			switch (param2)
			{
				case 0:
					g_bPersonalDemos[client] = false;
				case 1:
					g_bPersonalDemos[client] = true;
			}

			submenu_main = new Menu(Sub_Menu_Callback);
			if (g_bPersonalDemos[client])
			{
				submenu_main.SetTitle("Select Run Type:\n• WR");
			}
			else
			{
				submenu_main.SetTitle("Select Run Type:\n• PR");
			}
			submenu_main.AddItem("maps", "Map Demos", ITEMDRAW_CONTROL);
			submenu_main.AddItem("stages", "Stage Demos", ITEMDRAW_CONTROL);
			submenu_main.AddItem("bonuses", "Bonus Demos", ITEMDRAW_CONTROL);
			submenu_main.ExitBackButton = true;
			submenu_main.Display(client, MENU_TIME_FOREVER);
		}
		case MenuAction_End:
		{
			// CPrintToChat(client, "{red}[Main-Menu]{default} CLOSED");
			delete menu;
		}
	}

	return client;
}

/* Submenu to select Stage, Bonus or Map demo */
public int Sub_Menu_Callback(Menu menu, MenuAction action, int client, int param2)
{
	switch (action)
	{
		case MenuAction_DisplayItem:
		{
			char info[32];
			menu.GetItem(param2, info, sizeof(info));

			return RedrawMenuItem(info);
		}
		case MenuAction_Select:
		{
			char info[32], query[256], playerId[64];
			// int  flags = ReadFlagString("z");
			menu.GetItem(param2, info, sizeof(info));
			GetClientAuthId(client, AuthId_SteamID64, playerId, sizeof(playerId));

			if (g_bPersonalDemos[client])
				FormatEx(query, sizeof(query), "SELECT * FROM %s WHERE IsRecord = 1", DB_Name);
			else
				FormatEx(query, sizeof(query), "SELECT * FROM %s WHERE SteamId = '%s'", DB_Name, playerId);

			// CPrintToChat(client, "{blue}[Sub-Menu]{default} Info: {yellow}%s", info);
			// CPrintToChat(client, "{blue}[Sub-Menu]{default} Param1 (client) - {yellow}%d{default} | Param2 - {yellow}%d{default}", client, param2);

			switch (param2)
			{
				case 0:
					FormatEx(query, sizeof(query), "%s AND Bonus = 0 AND Stage = 0 AND MapFinished = 1 ORDER BY Date DESC;", query);
				case 1:
					FormatEx(query, sizeof(query), "%s AND Bonus = 0 AND Stage > 0 AND MapFinished = 1 ORDER BY Date DESC;", query);
				case 2:
					FormatEx(query, sizeof(query), "%s AND Bonus > 0 AND Stage = 0 AND MapFinished = 1 ORDER BY Date DESC;", query);
			}

			// CPrintToChat(client, "{blue}[Sub-Menu]{default} Query: {yellow}%s", query);
			db.Query(SQL_ListSteamids, query, GetClientUserId(client), DBPrio_Normal);
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
			{
				Menu_Command(client, 0);
			}
			else if (param2 == MenuCancel_ExitBack)
			{
				delete menu;
			}
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}

	return client;
}

/* Menu for the listed demos */
public int Menu_Callback(Menu menu, MenuAction action, int client, int param2)
{
	char splitArray[256][256];
	// int  flagRender = ReadFlagString("s");
	// int  flagDownload = ReadFlagString("a");

	switch (action)
	{
		case MenuAction_DisplayItem:
		{
			char info[256];
			menu.GetItem(param2, info, sizeof(info));

			// CPrintToChat(client, "{red}[Menu]{default} Info: {yellow}%s", info);

			return RedrawMenuItem(info);
		}
		case MenuAction_Select:
		{
			char info[1024];
			menu.GetItem(param2, info, sizeof(info));
			// CPrintToChat(client, "{red}[Menu]{default} Param1 (client) - {yellow}%d{default} | Param2 - {yellow}%d{default}", client, param2);
			// CPrintToChat(client, "{red}[Menu]{default} Full Item Info: {yellow}%s", info);

			// Really need a new way of doing this thing
			// Don't fix if it ain't broken ig lul
			/*
				StartTick = splitArray[0][0]
				EndTick = splitArray[1][0]
				DemoName = splitArray[2][0]
				Bonus = splitArray[3][0]
				Stage = splitArray[4][0]
				IsRecord = splitArray[5][0]
				FastDL = splitArray[6][0]
				DownloadURL = splitArray[7][0]
				Tickrate = splitArray[8][0]
				SteamId = splitArray[9][0]
				Mapname = splitArray[10][0]
				demoRunTime = splitArray[11][0]
			*/
			ExplodeString(info, " | ", splitArray, sizeof(splitArray), sizeof(splitArray));

			// CPrintToChat(client, "%s{default} Link for selected demo ({gold}%s{default}):", g_strPrefix, splitArray[11][0]);
			// CPrintToChat(client, "%s {blue}%s/%s.dem", g_strPrefix, splitArray[7][0], splitArray[2][0]);
			// CPrintToChat(client, "%s{default} Start: {yellow}%s{default} | End: {yellow}%s{default} | Player: {yellow}%s", g_strPrefix, splitArray[0][0], splitArray[1][0], splitArray[9][0]);

			SendSelectedDemoForward(client, splitArray[11][0], StringToInt(splitArray[0][0]), StringToInt(splitArray[1][0]), splitArray[2][0], splitArray[7][0], splitArray[9][0], splitArray[6][0]);
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
			{
				Menu_Command(client, 0);
			}
			else if (param2 == MenuCancel_ExitBack)
			{
				delete menu;
			}
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}

	return client;
}

/* Funcs */
void Start_Recording()
{
	gc_HostName = FindConVar("hostname");

	GetConVarString(gc_MapLogPath, g_strMapLog, sizeof(g_strMapLog));
	GetConVarString(gc_DemoPath, g_strDemoPath, sizeof(g_strDemoPath));
	GetConVarString(gc_LogPath, g_strLogFile, sizeof(g_strLogFile));
	GetConVarString(gc_HostName, g_strHostName, sizeof(g_strHostName));
	GetConVarString(gc_FastDL, g_strFastDL, sizeof(g_strFastDL));
	GetConVarString(gc_DownloadURL, g_strDownloadURL, sizeof(g_strDownloadURL));
	GetCurrentMap(g_strMapName, sizeof(g_strMapName));

	// createFolders(g_strDemoPath, g_strMapLog, g_strDownloadFolder);

	if (!SourceTV_IsRecording())
	{
		char logMsg[1000];
		FormatTime(g_strTime, sizeof(g_strTime), "%d_%m_%y-%H_%M_%S", GetTime());
		Format(g_strDemoName, sizeof(g_strDemoName), "%s-%s-%d", g_strTime, g_strMapName, g_intDemoNumber);
		Format(logMsg, sizeof(logMsg), "================================= %s.dem ================================= %s =================================", g_strDemoName, g_strHostName);

		ServerCommand("tv_record %s/%s", g_strDemoPath, g_strDemoName);
		FixRecord();

		populateLog(logMsg);
		PrintToServer("Started recording - %s", g_strDemoName);
	}
}

void Stop_Recording()
{
	char logMsg[256];
	Format(logMsg, sizeof(logMsg), "Total replays for %s : %d", g_strMapName, g_intDemoNumber);

	ServerCommand("tv_stoprecord");
	populateLog(logMsg);

	// Update all entries from current map in DB as MapFinished = 1
	updateEntries();

	if (g_intDemoNumber <= 0)
		deleteDemo(g_strDemoPath, g_strDemoName, g_strLogFile);
}

int GetRealClientCount()
{
	int iClients = 0;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
		{
			iClients++;
		}
	}

	return iClients;
}

stock void populateLog(char[] message)
{
	if (strlen(g_strLogFile) > 0)
		LogToFileEx(g_strLogFile, "%s", message);
}

stock void populateMapLog(char[] message)
{
	if (strlen(g_strMapLog) > 0)
	{
		if (StrEqual(g_strHostName, ""))
			GetConVarString(gc_HostName, g_strHostName, sizeof(g_strHostName));

		char szPath[500];
		Format(szPath, sizeof(szPath), "%s/%s.txt", g_strMapLog, g_strMapName);
		LogToFileEx(szPath, "%s --- %s", message, g_strHostName);
	}
}

stock void deleteDemo(char[] path, char[] name, char[] log)
{
	char logMsg[1000];
	if (DirExists(path))
	{
		char szPath[500];
		Format(szPath, sizeof(szPath), "%s/%s.dem", path, name);

		if (FileExists(szPath))
		{
			DeleteFile(szPath);
			Format(logMsg, sizeof(logMsg), "Demo deleted - %s", szPath);
			populateLog(logMsg);
		}
		else
		{
			Format(logMsg, sizeof(logMsg), "Demo does NOT exist - %s", szPath);
			populateLog(logMsg);
		}
	}
	else
	{
		Format(logMsg, sizeof(logMsg), "Dir does NOT exist - %s", path);
		populateLog(logMsg);
	}
}

stock void createFolders(char[] path1, char[] path2, char[] path3)	  // needs rework i think
{
	// *.dem path
	if (!DirExists(path1))
	{
		if (!CreateDirectory(path1, 511))
			PrintToServer("[SurfTV] Failed to create Demo directory: %s", path1);
	}
	else
	{
		PrintToServer("[SurfTV] Directory already exists: %s", path1);
	}

	// MapLog path
	if (!DirExists(path2))
	{
		if (!CreateDirectory(path2, 511))
			PrintToServer("[SurfTV] Failed to create MapLog directory: %s", path2);
	}
	else
	{
		PrintToServer("[SurfTV] Directory already exists: %s", path2);
	}

	// Public DL path
	if (!DirExists(path3))
	{
		if (!CreateDirectory(path3, 511))
			PrintToServer("[SurfTV] Failed to create Public DL directory: %s", path3);
	}
	else
	{
		PrintToServer("[SurfTV] Directory already exists: %s", path3);
	}
}

void updateEntries()
{
	char query[256];
	Format(query, sizeof(query), "UPDATE %s SET MapFinished = '1' WHERE DemoName = '%s';", DB_Name, g_strDemoName);
	db.Query(SQL_ErrorCheckCallback, query, DBPrio_Normal);
}

void moveExpired()
{
	char query_MoveExpired[512], query_DeleteExpired[512];

	// Copy all expired entries to expired table
	FormatEx(query_MoveExpired, sizeof(query_MoveExpired), "INSERT INTO %s (SELECT * FROM %s WHERE `Date` < NOW() - INTERVAL 7 DAY)", DB_Name_Expired, DB_Name);
	db.Query(SQL_ErrorCheckCallback, query_MoveExpired, _, DBPrio_Normal);

	// Delete all expired entries from main table
	FormatEx(query_DeleteExpired, sizeof(query_DeleteExpired), "DELETE FROM %s WHERE `Date` < NOW() - INTERVAL 7 DAY;", DB_Name);
	db.Query(SQL_ErrorCheckCallback, query_DeleteExpired, _, DBPrio_Normal);

	PrintToServer("[SurfTV] Successfully moved expired entries!");
}

char[] GetStyle(int style)
{
	char strStyle[5];
	switch (style)
	{
		case 0: strcopy(strStyle, sizeof strStyle, "N");
		case 1: strcopy(strStyle, sizeof strStyle, "SW");
		case 2: strcopy(strStyle, sizeof strStyle, "HSW");
		case 3: strcopy(strStyle, sizeof strStyle, "BW");
		case 4: strcopy(strStyle, sizeof strStyle, "LG");
		case 5: strcopy(strStyle, sizeof strStyle, "SM");
		case 6: strcopy(strStyle, sizeof strStyle, "FF");
		case 7: strcopy(strStyle, sizeof strStyle, "FS");
	}
	return strStyle;
}

void FixRecord()
{
	// For some reasons, demo playback speed is absolute trash without a round_start event.
	// So whenever the server starts recording a demo, we create the event and fire it.
	Event e			= CreateEvent("round_start", true);
	int	  timelimit = FindConVar("mp_timelimit").IntValue;
	e.SetInt("timelimit", timelimit);
	e.SetInt("fraglimit", 0);
	e.SetString("objective", "demofix");

	e.Fire(false);
}

/* Forwards */
void InitForwards()
{
	g_SelectedDemo = new GlobalForward("SurfTV_SelectedDemo", ET_Event, Param_Cell, Param_String, Param_Cell, Param_Cell, Param_String, Param_String, Param_String, Param_String);
}

/*
 * Sends a forward upon selecting an item from the listed demos menu
 *
 * @param client           	Index of the client who selected the demo
 * @param demoRunTime		Time format string of the selected run
 * @param demoStart            	Start tick of the selected demo
 * @param demoEnd				End tick of the selected demo
 * @param demoName			Name of the demo selected
 * @param dlUrl				Url to download the demo
 * @param demoPlayer		Id of the player on the demo
 * @param demoFdl			FastDL for the map of the selected demo
 */
void SendSelectedDemoForward(int client, const char[] demoRunTime, int demoStart, int demoEnd, const char[] demoName, const char[] dlUrl, const char[] demoPlayer, const char[] demoFdl)
{
	/* Start function call */
	Call_StartForward(g_SelectedDemo);

	/* Push parameters one at a time */
	Call_PushCell(client);
	Call_PushString(demoRunTime);
	Call_PushCell(demoStart);
	Call_PushCell(demoEnd);
	Call_PushString(demoName);
	Call_PushString(dlUrl);
	Call_PushString(demoPlayer);
	Call_PushString(demoFdl);

	/* Finish the call, get the result */
	Call_Finish();
}