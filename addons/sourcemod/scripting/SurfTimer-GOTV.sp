#include <colorvariables>
#include <cstrike>
#include <sourcemod>
#include <sourcetvmanager>
#include <surftimer>
#include <unixtime_sourcemod>
#include <regex>

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION		   "0.3-Enums-And-Transactions"

/*-> Database table name to use for connection <-*/
#define DB_Name				   "wr_demos"
#define DB_Name_Expired		   "wr_demos_expired"
#define DB_Checkpoints		   "demos_checkpoints"
#define DB_Checkpoints_Expired "demos_checkpoints_expired"
/*###############################################*/

/*-> Menus <-*/
Menu menu_main;
Menu submenu_main;
Menu menu_list_demos;

/*-> Queries <-*/
char sql_deleteDemoEntries[]	  = "DELETE FROM %s WHERE DemoName = '%s';";
char sql_mapFinished[]			  = "UPDATE %s SET MapFinished = '1' WHERE DemoName = '%s';";
char sql_insertRun[]			  = "INSERT INTO %s (SteamId, RunTime, StartTick, EndTick, DemoName, Server, Bonus, Stage, Date, MapFinished, Style, IsRecord, FastDL, DownloadURL, Tickrate) VALUES ('%s', '%s', '%s', '%s', '%s', '%s', '%i', '%i', NOW(), '0', '%i', '%i', '%s', '%s', '%.1f')";
char sql_insertCheckpoint[]		  = "INSERT INTO %s (steamId, demoName, cp, demoTick, runTime, pbDiff, wrDiff, mapFinished) VALUES ('%s', '%s', %i, %s, '%s', '%s', '%s', 0)";
char sql_moveExpired[]			  = "INSERT INTO %s (SELECT * FROM %s WHERE `Date` < NOW() - INTERVAL %i DAY);";
char sql_deleteExpired[]		  = "DELETE FROM %s WHERE `Date` < NOW() - INTERVAL %i DAY;";
// Create tables
char sql_createRunsTable[]		  = "CREATE TABLE IF NOT EXISTS `%s` (`SteamId` varchar(64) NOT NULL, `RunTime` text NOT NULL, `StartTick` int NOT NULL, `EndTick` int NOT NULL, `DemoName` text NOT NULL, `Server` text NOT NULL, `Bonus` int NOT NULL, `Stage` int NOT NULL, `Date` datetime NOT NULL DEFAULT NOW(), `MapFinished` int NOT NULL, `Style` int NOT NULL, `IsRecord` int NOT NULL, `FastDL` text NOT NULL, `DownloadURL` text NOT NULL, `Tickrate` double NOT NULL, KEY `SteamId` (`SteamId`));";
char sql_createCheckpointsTable[] = "CREATE TABLE IF NOT EXISTS `%s` (`steamId` varchar(32) NOT NULL, `demoName` text NOT NULL, `cp` int NOT NULL DEFAULT '0', `demoTick` int NOT NULL, `runTime` varchar(64) NOT NULL, `pbDiff` varchar(64) NULL, `wrDiff` varchar(64) NULL, `mapFinished` int NULL DEFAULT '0', `Date` TIMESTAMP(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6), KEY `steamId` (`steamId`));";

enum struct CoreData
{
	/*-> DB <-*/
	Database	  db;

	/*-> ConVars <-*/
	ConVar		  cTvEnabled;
	ConVar		  cTickrate;
	ConVar		  cLogPath;
	ConVar		  cDemoPath;
	ConVar		  cHostname;
	ConVar		  cMapLogPath;
	ConVar		  cFastDL;
	ConVar		  cDownloadURL;
	ConVar		  cPrefix;
	ConVar		  cExpireTime;

	char		  DemoPath[PLATFORM_MAX_PATH];
	char		  FastDL[256];
	char		  DownloadURL[256];
	char		  Prefix[256];
	char		  Hostname[500];
	char		  Logfile[500];
	char		  Maplog[500];
	int			  ExpireTime;

	/*-> FORWARDS <-*/
	GlobalForward fwSelectedDemo;
}
CoreData Core;

enum struct DemoData
{
	int	  WRCount;
	int	  Number;
	char  DemoName[500];
	char  InitTime[128];
	char  Mapname[128];
	char  PlayerNameWR[MAX_NAME_LENGTH];
	char  TimeWR[128];
	float FloatWR;
	bool  IsRecordWR;
}
DemoData	  Demo;

/*-> Global Variables <-*/
bool		  g_blnMapEnd			= false;
bool		  g_bIsSurfTimerEnabled = false;
bool		  g_bPersonalDemos[MAXPLAYERS];

char		  g_strWRLog[500];	  // This should be made as a logMsg var in each function

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
	Core.cLogPath	  = CreateConVar("sm_ck_gotv_log", "", "Path to where the log should be stored (addons/sourcemod/logs/_SurfTimer-GOTV.txt)");
	Core.cMapLogPath  = CreateConVar("sm_ck_gotv_maplogpath", "", "Path to where the log files for each map will be stored without trailing / (.demos/_maps)");
	Core.cDemoPath	  = CreateConVar("sm_ck_gotv_demopath", "", "Path to where the demo files should be stored without trailing / (.demos/Private)");
	Core.cDownloadURL = CreateConVar("sm_ck_gotv_downloadurl", "", "URL where the demos recorded from the plugin could be accessed");
	Core.cPrefix	  = CreateConVar("sm_ck_gotv_prefix", "", "Prefix for the plugin");
	Core.cExpireTime  = CreateConVar("sm_ck_gotv_expire", "7", "Days until db entries are moved to expired and not shown in menu");
	Core.cFastDL	  = FindConVar("sv_downloadurl");
	Core.cTickrate	  = FindConVar("sv_maxupdaterate");

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
	g_blnMapEnd		= false;
	Core.cTvEnabled = FindConVar("tv_enable");
	if (!Core.cTvEnabled.BoolValue)
		SetFailState("GOTV is NOT enabled on this server.");

	surftimer_GetMapData(Demo.PlayerNameWR, Demo.TimeWR, Demo.FloatWR);
}

public void OnConfigsExecuted()
{
	Demo.Number	 = 0;
	Demo.WRCount = 0;

	GetConVarString(Core.cPrefix, Core.Prefix, sizeof(Core.Prefix));
	Core.ExpireTime = GetConVarInt(Core.cExpireTime);
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
	Demo.WRCount	= Demo.WRCount + 1;
	Demo.IsRecordWR = true;
	char playerName[MAX_NAME_LENGTH], demoMessage[256];
	GetClientName(client, playerName, sizeof(playerName));

	if (bonusGroup != -1)
	{
		FormatEx(g_strWRLog, sizeof(g_strWRLog), "WRB %d [%s] | %s by %s --- Time %s --- Improved %s ---", bonusGroup, GetStyle(style), Demo.Mapname, playerName, time, timeDif);
		FormatEx(demoMessage, sizeof(demoMessage), "WRB %d [%s] | %s by %s --- Time %s --- Improved %s ---", bonusGroup, GetStyle(style), Demo.Mapname, playerName, time, timeDif);
		SourceTV_PrintToDemoConsole("%s", demoMessage);
	}
	else
	{
		FormatEx(g_strWRLog, sizeof(g_strWRLog), "WR [%s] | %s by %s --- Time %s --- Improved %s --- Previous: %s [%s]", GetStyle(style), Demo.Mapname, playerName, time, timeDif, Demo.PlayerNameWR, Demo.TimeWR);
		FormatEx(demoMessage, sizeof(demoMessage), "WR [%s] | %s by %s --- Time %s --- Improved %s --- Previous: %s [%s]", GetStyle(style), Demo.Mapname, playerName, time, timeDif, Demo.PlayerNameWR, Demo.TimeWR);
		SourceTV_PrintToDemoConsole("%s", demoMessage);
	}
}

public void surftimer_OnNewWRCP(int client, int style, char[] time, char[] timeDif, int stage, float fRunTime)
{
	Demo.WRCount		= Demo.WRCount + 1;
	Demo.Number			= Demo.Number + 1;
	float floatTickRate = GetConVarFloat(Core.cTickrate);
	int	  currentTick	= SourceTV_GetRecordingTick();
	char  playerName[MAX_NAME_LENGTH], demoMessage[256], wrcpEndTick[64], wrcpStartTick[64], query[1024], playerId[64];
	GetClientName(client, playerName, sizeof(playerName));
	GetClientAuthId(client, AuthId_SteamID64, playerId, sizeof(playerId));

	FormatEx(wrcpEndTick, sizeof(wrcpEndTick), "%d", currentTick);
	FormatEx(wrcpStartTick, sizeof(wrcpStartTick), "%.0f", currentTick - fRunTime * floatTickRate);
	FormatEx(g_strWRLog, sizeof(g_strWRLog), "WRCP %d [%s] | %s by %s --- Time %s --- Improved %s --- StartTick %s --- EndTick %s --- %s", stage, GetStyle(style), Demo.Mapname, playerName, time, timeDif, wrcpStartTick, wrcpEndTick, Demo.DemoName);
	FormatEx(demoMessage, sizeof(demoMessage), "WRCP %d [%s] | %s by %s --- Time %s --- Improved %s ---", stage, GetStyle(style), Demo.Mapname, playerName, time, timeDif);
	SourceTV_PrintToDemoConsole("%s", demoMessage);

	// FormatEx(query, sizeof(query), "INSERT INTO %s (SteamId, RunTime, StartTick, EndTick, DemoName, Server, Bonus, Stage, Date, MapFinished, Style, IsRecord, FastDL, DownloadURL, Tickrate) VALUES ('%s', '%s', '%s', '%s', '%s', '%s', '0', '%d', NOW(), '0', '%d', '1', '%s', '%s', '%.1f')", DB_Name, playerId, time, wrcpStartTick, wrcpEndTick, Demo.DemoName, Core.Hostname, stage, style, Core.FastDL, Core.DownloadURL, floatTickRate);
	// Core.db.Query(SQL_ErrorCheckCallback, query);

	FormatEx(query, sizeof(query), sql_insertRun, DB_Name, playerId, time, wrcpStartTick, wrcpEndTick, Demo.DemoName, Core.Hostname, 0, stage, style, 1, Core.FastDL, Core.DownloadURL, floatTickRate);
	Core.db.Query(SQL_ErrorCheckCallback, query);

	populateLog(g_strWRLog);
	populateMapLog(g_strWRLog);
}

public void surftimer_OnStageFinished(int client, int style, char[] time, char[] timeDif, int stage, float fRunTime, float fClientRunTime)
{
	Demo.WRCount		= Demo.WRCount + 1;
	Demo.Number			= Demo.Number + 1;
	float floatTickRate = GetConVarFloat(Core.cTickrate);
	int	  currentTick	= SourceTV_GetRecordingTick();
	char  playerName[MAX_NAME_LENGTH], demoMessage[256], wrcpEndTick[64], wrcpStartTick[64], query[1024], playerId[64];
	GetClientName(client, playerName, sizeof(playerName));
	GetClientAuthId(client, AuthId_SteamID64, playerId, sizeof(playerId));

	FormatEx(wrcpEndTick, sizeof(wrcpEndTick), "%d", currentTick);
	FormatEx(wrcpStartTick, sizeof(wrcpStartTick), "%.0f", currentTick - fClientRunTime * floatTickRate);
	FormatEx(g_strWRLog, sizeof(g_strWRLog), "Stage %d [%s] | %s by %s --- Time %s --- Difference %s --- StartTick %s --- EndTick %s --- %s", stage, GetStyle(style), Demo.Mapname, playerName, time, timeDif, wrcpStartTick, wrcpEndTick, Demo.DemoName);
	FormatEx(demoMessage, sizeof(demoMessage), "Stage %d [%s] | %s by %s --- Time %s --- Difference %s ---", stage, GetStyle(style), Demo.Mapname, playerName, time, timeDif);
	SourceTV_PrintToDemoConsole("%s", demoMessage);

	// Old query
	// FormatEx(query, sizeof(query), "INSERT INTO %s (SteamId, RunTime, StartTick, EndTick, DemoName, Server, Bonus, Stage, Date, MapFinished, Style, IsRecord, FastDL, DownloadURL, Tickrate) VALUES ('%s', '%s', '%s', '%s', '%s', '%s', '0', '%d', NOW(), '0', '%d', '0', '%s', '%s', '%.1f')", DB_Name, playerId, time, wrcpStartTick, wrcpEndTick, Demo.DemoName, Core.Hostname, stage, style, Core.FastDL, Core.DownloadURL, floatTickRate);
	FormatEx(query, sizeof(query), sql_insertRun, DB_Name, playerId, time, wrcpStartTick, wrcpEndTick, Demo.DemoName, Core.Hostname, 0, stage, style, 0, Core.FastDL, Core.DownloadURL, floatTickRate);
	Core.db.Query(SQL_ErrorCheckCallback, query);

	populateLog(g_strWRLog);
	populateMapLog(g_strWRLog);
}

public Action surftimer_OnMapFinished(int client, float fRunTime, char sRunTime[54], float PBDiff, float WRDiff, int rank, int total, int style)
{
	Demo.Number			= Demo.Number + 1;
	float floatTickRate = GetConVarFloat(Core.cTickrate);
	int	  currentTick	= SourceTV_GetRecordingTick();
	char  strStartTick[64], strEndTick[64], strRunTime[64], playerName[MAX_NAME_LENGTH], query[1024], playerId[64];
	GetClientName(client, playerName, sizeof(playerName));
	GetClientAuthId(client, AuthId_SteamID64, playerId, sizeof(playerId));

	// Assign runtime, start tick, end tick - Map finished
	FormatEx(strEndTick, sizeof(strEndTick), "%d", currentTick);
	FormatEx(strStartTick, sizeof(strStartTick), "%.0f", currentTick - fRunTime * floatTickRate);
	FormatEx(strRunTime, sizeof(strRunTime), "%.0f", fRunTime);

	// Is this a WR?
	if (Demo.IsRecordWR)
	{
		// Old query
		// FormatEx(query, sizeof(query), "INSERT INTO %s (SteamId, RunTime, StartTick, EndTick, DemoName, Server, Bonus, Stage, Date, MapFinished, Style, IsRecord, FastDL, DownloadURL, Tickrate) VALUES ('%s', '%s', '%s', '%s', '%s', '%s', '0', '0', NOW(), '0', '%d', '1', '%s', '%s', '%.1f')", DB_Name, playerId, sRunTime, strStartTick, strEndTick, Demo.DemoName, Core.Hostname, style, Core.FastDL, Core.DownloadURL, floatTickRate);
		Demo.IsRecordWR = false;
		Format(g_strWRLog, sizeof(g_strWRLog), "%s StartTick %s --- EndTick %s --- %s", g_strWRLog, strStartTick, strEndTick, Demo.DemoName);
		FormatEx(query, sizeof(query), sql_insertRun, DB_Name, playerId, sRunTime, strStartTick, strEndTick, Demo.DemoName, Core.Hostname, 0, 0, style, 1, Core.FastDL, Core.DownloadURL, floatTickRate);
	}
	else
	{
		// Old query
		// FormatEx(query, sizeof(query), "INSERT INTO %s (SteamId, RunTime, StartTick, EndTick, DemoName, Server, Bonus, Stage, Date, MapFinished, Style, IsRecord, FastDL, DownloadURL, Tickrate) VALUES ('%s', '%s', '%s', '%s', '%s', '%s', '0', '0', NOW(), '0', '%d', '0', '%s', '%s', '%.1f')", DB_Name, playerId, sRunTime, strStartTick, strEndTick, Demo.DemoName, Core.Hostname, style, Core.FastDL, Core.DownloadURL, floatTickRate);
		FormatEx(g_strWRLog, sizeof(g_strWRLog), "%s by %s --- Time %s (%d/%d) --- StartTick %s --- EndTick %s --- %s", Demo.Mapname, playerName, sRunTime, rank, total, strStartTick, strEndTick, Demo.DemoName);
		FormatEx(query, sizeof(query), sql_insertRun, DB_Name, playerId, sRunTime, strStartTick, strEndTick, Demo.DemoName, Core.Hostname, 0, 0, style, 0, Core.FastDL, Core.DownloadURL, floatTickRate);
	}
	Core.db.Query(SQL_ErrorCheckCallback, query);

	populateLog(g_strWRLog);
	return Plugin_Handled;
}

public Action surftimer_OnCheckpoint(int client, float fRunTime, char sRunTime[54], float fPbCp, char sPbDiff[16], float fSrCp, char sSrDiff[16], int iCheckpoint)
{
	char demoMessage[256], playerName[MAX_NAME_LENGTH], currentTick[32], playerId[64], query[1024];

	FormatEx(currentTick, sizeof(currentTick), "%d", SourceTV_GetRecordingTick());
	GetClientName(client, playerName, sizeof(playerName));
	GetClientAuthId(client, AuthId_SteamID64, playerId, sizeof(playerId));

	// CPrintToChat(client, "iCheckpoint = %i | fRunTime %.1f", iCheckpoint, fRunTime);
	FormatEx(demoMessage, sizeof(demoMessage), "CP %i | %s | tick: %s | PB: %s | WR: %s", iCheckpoint, playerName, currentTick, sPbDiff, sSrDiff);

	// Old query
	// FormatEx(query, sizeof(query), "INSERT INTO %s (steamId, demoName, cp, demoTick, runTime, pbDiff, wrDiff, mapFinished) VALUES ('%s', '%s', %i, %s, '%s', '%s', '%s', 0)", DB_Checkpoints, playerId, Demo.DemoName, iCheckpoint, currentTick, sRunTime, sPbDiff, sSrDiff);
	FormatEx(query, sizeof(query), sql_insertCheckpoint, DB_Checkpoints, playerId, Demo.DemoName, iCheckpoint, currentTick, sRunTime, sPbDiff, sSrDiff);
	Core.db.Query(SQL_ErrorCheckCallback, query);

	SourceTV_PrintToDemoConsole("%s", demoMessage);
	return Plugin_Handled;
}

public Action surftimer_OnBonusFinished(int client, float fRunTime, char sRunTime[54], float fPBDiff, float fSRDiff, int rank, int total, int bonusid, int style)
{
	Demo.Number			= Demo.Number + 1;
	int	  currentTick	= SourceTV_GetRecordingTick();
	float floatTickRate = GetConVarFloat(Core.cTickrate);
	char  strStartTick[64], strEndTick[64], strRunTime[64], playerName[MAX_NAME_LENGTH], query[1024], playerId[64];

	GetClientName(client, playerName, sizeof(playerName));
	GetClientAuthId(client, AuthId_SteamID64, playerId, sizeof(playerId));

	// Assign runtime, start tick, end tick - Bonus Finished
	FormatEx(strEndTick, sizeof(strEndTick), "%d", currentTick);
	FormatEx(strStartTick, sizeof(strStartTick), "%.0f", currentTick - fRunTime * floatTickRate);
	FormatEx(strRunTime, sizeof(strRunTime), "%.0f", fRunTime);

	// Is this a WRB?
	if (Demo.IsRecordWR)
	{
		// Old query
		// FormatEx(query, sizeof(query), "INSERT INTO %s (SteamId, RunTime, StartTick, EndTick, DemoName, Server, Bonus, Stage, Date, MapFinished, Style, IsRecord, FastDL, DownloadURL, Tickrate) VALUES ('%s', '%s', '%s', '%s', '%s', '%s', '%d', '0', NOW(), '0', '%d', '1', '%s', '%s', '%.1f')", DB_Name, playerId, sRunTime, strStartTick, strEndTick, Demo.DemoName, Core.Hostname, bonusid, style, Core.FastDL, Core.DownloadURL, floatTickRate);
		Demo.IsRecordWR = false;
		Format(g_strWRLog, sizeof(g_strWRLog), "%s StartTick %s --- EndTick %s --- %s", g_strWRLog, strStartTick, strEndTick, Demo.DemoName);
		FormatEx(query, sizeof(query), sql_insertRun, DB_Name, playerId, sRunTime, strStartTick, strEndTick, Demo.DemoName, Core.Hostname, bonusid, 0, style, 1, Core.FastDL, Core.DownloadURL, floatTickRate);
	}
	else
	{
		// Old query
		// FormatEx(query, sizeof(query), "INSERT INTO %s (SteamId, RunTime, StartTick, EndTick, DemoName, Server, Bonus, Stage, Date, MapFinished, Style, IsRecord, FastDL, DownloadURL, Tickrate) VALUES ('%s', '%s', '%s', '%s', '%s', '%s', '%d', '0', NOW(), '0', '%d', '0', '%s', '%s', '%.1f')", DB_Name, playerId, sRunTime, strStartTick, strEndTick, Demo.DemoName, Core.Hostname, bonusid, style, Core.FastDL, Core.DownloadURL, floatTickRate);
		FormatEx(g_strWRLog, sizeof(g_strWRLog), "%s [Bonus %d] FINISHED by %s --- Time %s (%d/%d) --- StartTick %s --- EndTick %s --- %s", Demo.Mapname, bonusid, playerName, sRunTime, rank, total, strStartTick, strEndTick, Demo.DemoName);
		FormatEx(query, sizeof(query), sql_insertRun, DB_Name, playerId, sRunTime, strStartTick, strEndTick, Demo.DemoName, Core.Hostname, bonusid, 0, style, 0, Core.FastDL, Core.DownloadURL, floatTickRate);
	}
	Core.db.Query(SQL_ErrorCheckCallback, query);

	populateLog(g_strWRLog);
	return Plugin_Handled;
}

public Action Command_Test(int client, int args)
{
	if (args)
	{
		char cmdInput[256];
		GetCmdArg(1, cmdInput, sizeof(cmdInput));
		PrintToServer(GetMapname(cmdInput));
	}
	else
	{
		PrintToServer(GetMapname("22_04_23-14_03_13-surf_piano-0 "));
	}

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
	PrintToServer("[SurfTV] Successfully connected to database!");

	// Create Tables in DB if not exist
	Core.db					 = view_as<Database>(hndl);	   // Set global DB Handle
	Transaction createTables = SQL_CreateTransaction();
	char		query[1024];

	// Runs
	FormatEx(query, sizeof(query), sql_createRunsTable, DB_Name);
	SQL_AddQuery(createTables, query);
	FormatEx(query, sizeof(query), sql_createRunsTable, DB_Name_Expired);
	SQL_AddQuery(createTables, query);

	// Checkpoints
	FormatEx(query, sizeof(query), sql_createCheckpointsTable, DB_Checkpoints);
	SQL_AddQuery(createTables, query);
	FormatEx(query, sizeof(query), sql_createCheckpointsTable, DB_Checkpoints_Expired);
	SQL_AddQuery(createTables, query);

	SQL_ExecuteTransaction(Core.db, createTables, SQLTrx_OnSuccess, SQLTrx_OnFailed, 2);

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
		CPrintToChat(client, "%s Query failed, please try again later.", Core.Prefix);
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
		FormatEx(itemInfo, sizeof(itemInfo), "%i | %i | %s | %i | %i | %i | %s | %s | %.1f | %s | %s | %s", StartTick, EndTick, DemoName, Bonus, Stage, IsRecord, FastDL, DownloadURL, Tickrate, SteamId, temp, RunTime);
		if (Bonus > 0)
		{
			FormatEx(buff, sizeof(buff), "[%s] Bonus: %i (%s)", GetStyle(Style), Bonus, RunTime);
			FormatEx(itemName, sizeof(itemName), "surf_%s\n%s", temp, buff);
		}
		else if (Stage > 0)
		{
			FormatEx(buff, sizeof(buff), "[%s] Stage: %i (%s)", GetStyle(Style), Stage, RunTime);
			FormatEx(itemName, sizeof(itemName), "surf_%s\n%s", temp, buff);
		}
		else if (Bonus == 0 && Stage == 0)
		{
			FormatEx(buff, sizeof(buff), "[%s] %s (%s)", GetStyle(Style), RunTime, szDate);
			FormatEx(itemName, sizeof(itemName), "surf_%s\n%s", temp, buff);
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
					Format(query, sizeof(query), "%s AND Bonus = 0 AND Stage = 0 AND MapFinished = 1 ORDER BY Date DESC;", query);
				case 1:
					Format(query, sizeof(query), "%s AND Bonus = 0 AND Stage > 0 AND MapFinished = 1 ORDER BY Date DESC;", query);
				case 2:
					Format(query, sizeof(query), "%s AND Bonus > 0 AND Stage = 0 AND MapFinished = 1 ORDER BY Date DESC;", query);
			}

			// CPrintToChat(client, "{blue}[Sub-Menu]{default} Query: {yellow}%s", query);
			Core.db.Query(SQL_ListSteamids, query, GetClientUserId(client), DBPrio_Normal);
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
			// PrintToServer(info);

			// CPrintToChat(client, "%s{default} Link for selected demo ({gold}%s{default}):", Prefix, splitArray[11][0]);
			// CPrintToChat(client, "%s {blue}%s/%s.dem", Prefix, splitArray[7][0], splitArray[2][0]);
			// CPrintToChat(client, "%s{default} Start: {yellow}%s{default} | End: {yellow}%s{default} | Player: {yellow}%s", Prefix, splitArray[0][0], splitArray[1][0], splitArray[9][0]);

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
	Core.cHostname = FindConVar("hostname");

	GetConVarString(Core.cMapLogPath, Core.Maplog, sizeof(Core.Maplog));
	GetConVarString(Core.cDemoPath, Core.DemoPath, sizeof(Core.DemoPath));
	GetConVarString(Core.cLogPath, Core.Logfile, sizeof(Core.Logfile));
	GetConVarString(Core.cHostname, Core.Hostname, sizeof(Core.Hostname));
	GetConVarString(Core.cFastDL, Core.FastDL, sizeof(Core.FastDL));
	GetConVarString(Core.cDownloadURL, Core.DownloadURL, sizeof(Core.DownloadURL));
	GetCurrentMap(Demo.Mapname, sizeof(Demo.Mapname));

	// createFolders(Core.DemoPath, Core.Maplog, g_strDownloadFolder);

	if (!SourceTV_IsRecording())
	{
		char logMsg[1000];
		FormatTime(Demo.InitTime, sizeof(Demo.InitTime), "%d_%m_%y-%H_%M_%S", GetTime());
		FormatEx(Demo.DemoName, sizeof(Demo.DemoName), "%s-%s-%d", Demo.InitTime, Demo.Mapname, Demo.Number);
		FormatEx(logMsg, sizeof(logMsg), "================================= %s.dem ================================= %s =================================", Demo.DemoName, Core.Hostname);

		ServerCommand("tv_record %s/%s", Core.DemoPath, Demo.DemoName);
		FixRecord();

		populateLog(logMsg);
		PrintToServer("Started recording - %s", Demo.DemoName);
	}
}

void Stop_Recording()
{
	char logMsg[256];
	FormatEx(logMsg, sizeof(logMsg), "Total replays for %s : %d", Demo.Mapname, Demo.Number);

	ServerCommand("tv_stoprecord");
	populateLog(logMsg);

	// Update all entries from current map in DB as MapFinished = 1
	updateEntries();

	if (Demo.Number <= 0)
		deleteDemo(Core.DemoPath, Demo.DemoName, Core.Logfile);
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
	if (strlen(Core.Logfile) > 0)
		LogToFileEx(Core.Logfile, "%s", message);
}

stock void populateMapLog(char[] message)
{
	if (strlen(Core.Maplog) > 0)
	{
		if (StrEqual(Core.Hostname, ""))
			GetConVarString(Core.cHostname, Core.Hostname, sizeof(Core.Hostname));

		char szPath[500];
		FormatEx(szPath, sizeof(szPath), "%s/%s.txt", Core.Maplog, Demo.Mapname);
		LogToFileEx(szPath, "%s --- %s", message, Core.Hostname);
	}
}

stock void deleteDemo(char[] path, char[] name, char[] log)
{
	char logMsg[1000];
	if (DirExists(path))
	{
		char szPath[500];
		FormatEx(szPath, sizeof(szPath), "%s/%s.dem", path, name);

		if (FileExists(szPath))
		{
			DeleteFile(szPath);
			FormatEx(logMsg, sizeof(logMsg), "Demo deleted - %s", szPath);
			populateLog(logMsg);
		}
		else
		{
			FormatEx(logMsg, sizeof(logMsg), "Demo does NOT exist - %s", szPath);
			populateLog(logMsg);
		}
	}
	else
	{
		FormatEx(logMsg, sizeof(logMsg), "Dir does NOT exist - %s", path);
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
	Transaction updateTrx = SQL_CreateTransaction();
	char		query[1024];

	if (Demo.Number <= 0)
	{
		// Delete runs
		FormatEx(query, sizeof(query), sql_deleteDemoEntries, DB_Name, Demo.DemoName);
		SQL_AddQuery(updateTrx, query);

		// Delete checkpoints
		FormatEx(query, sizeof(query), sql_deleteDemoEntries, DB_Checkpoints, Demo.DemoName);
		SQL_AddQuery(updateTrx, query);
	}
	else
	{
		// Update runs
		FormatEx(query, sizeof(query), sql_mapFinished, DB_Name, Demo.DemoName);
		SQL_AddQuery(updateTrx, query);

		// Update checkpoints
		FormatEx(query, sizeof(query), sql_mapFinished, DB_Checkpoints, Demo.DemoName);
		SQL_AddQuery(updateTrx, query);
	}

	SQL_ExecuteTransaction(Core.db, updateTrx, SQLTrx_OnSuccess, SQLTrx_OnFailed, 1);
}

void moveExpired()
{
	Transaction expired = SQL_CreateTransaction();
	char		query[1024];

	// Old queries
	// FormatEx(query_MoveExpired, sizeof(query_MoveExpired), "INSERT INTO %s (SELECT * FROM %s WHERE `Date` < NOW() - INTERVAL %i DAY);", DB_Name_Expired, DB_Name, Core.ExpireTime);
	// FormatEx(query_DeleteExpired, sizeof(query_DeleteExpired), "DELETE FROM %s WHERE `Date` < NOW() - INTERVAL %i DAY;", DB_Name, Core.ExpireTime);

	// Copy all expired runs to expired table
	FormatEx(query, sizeof(query), sql_moveExpired, DB_Name_Expired, DB_Name, Core.ExpireTime);
	SQL_AddQuery(expired, query);
	// Delete all expired runs from main table
	FormatEx(query, sizeof(query), sql_deleteExpired, DB_Name, Core.ExpireTime);
	SQL_AddQuery(expired, query);

	// Old queries
	// FormatEx(query_MoveExpired, sizeof(query_MoveExpired), "INSERT INTO %s (SELECT * FROM %s WHERE `timestamp` < NOW() - INTERVAL %i DAY);", DB_Checkpoints_Expired, DB_Checkpoints, Core.ExpireTime);
	// FormatEx(query_DeleteExpired, sizeof(query_DeleteExpired), "DELETE FROM %s WHERE `timestamp` < NOW() - INTERVAL %i DAY;", DB_Checkpoints, Core.ExpireTime);

	// Copy checkpoints to expired
	FormatEx(query, sizeof(query), sql_moveExpired, DB_Checkpoints_Expired, DB_Checkpoints, Core.ExpireTime);
	SQL_AddQuery(expired, query);
	// Delete checkpoints from main
	FormatEx(query, sizeof(query), sql_deleteExpired, DB_Checkpoints, Core.ExpireTime);
	SQL_AddQuery(expired, query);

	SQL_ExecuteTransaction(Core.db, expired, SQLTrx_OnSuccess, SQLTrx_OnFailed, 0);
}

public void SQLTrx_OnSuccess(Handle db, any data, int numQueries, Handle[] results, any[] queryData)
{
	switch (data)
	{
		case 0: PrintToServer("[SurfTV] Successfully moved expired entries! (%i days)", Core.ExpireTime);
		case 1: PrintToServer("[SurfTV] Successfully updated entries!");
		case 2: PrintToServer("[SurfTV] Successfully created tables!");
	}
}

public void SQLTrx_OnFailed(Handle db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	switch (data)
	{
		case 0: LogError("[SurfTV] Failed moving expired entries! (%i days)", Core.ExpireTime);
		case 1: LogError("[SurfTV] Failed updating entries!");
		case 2: LogError("[SurfTV] Failed to create tables!");
	}

	SetFailState("[SurfTV] Transaction failed! Queries: %i (Case: %i)", numQueries, data);
}

char[] GetMapname(char[] demoName)
{
	char  regex_expression[] = "\\d{2}_\\d{2}_\\d{2}-\\d{2}_\\d{2}_\\d{2}-(surf_[a-zA-Z0-9_]+)-\\d";
	char  regex_match[512];

	Regex rr = CompileRegex(regex_expression);
	if (MatchRegex(rr, demoName) != -1)
	{
		GetRegexSubString(rr, 1, regex_match, sizeof regex_match);
		// PrintToServer("Matched string: %s", regex_match);
	}
	else
	{
		PrintToServer("No match found.");
	}

	delete rr;
	return regex_match;
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
	Core.fwSelectedDemo = new GlobalForward("SurfTV_SelectedDemo", ET_Event, Param_Cell, Param_String, Param_Cell, Param_Cell, Param_String, Param_String, Param_String, Param_String);
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
	Call_StartForward(Core.fwSelectedDemo);

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