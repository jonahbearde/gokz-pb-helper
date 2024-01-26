#include <sourcemod>
#include "colors"
#include "globalpb"
#include "gokz"
#include "gokz/core"
#include "gokz/localdb"
#include "smjansson"

#define SP_VERSION "0.1"

char g_Prefix[32] = "{green}KZ {grey}| ";
bool g_UsesGokz   = false;

public Plugin myinfo =
{
	name        = "gokz-pb-helper",
	author      = "Reeed",
	description = "show pb when players join Axe KZ servers",
	version     = "0.1",
	url         = "https://axekz.com/#/"

}

public void
	OnPluginStart()
{
	HookEvent("player_spawn", OnPlayerSpawn, EventHookMode_Post);
}

public void OnAllPluginsLoaded()
{
	g_UsesGokz = LibraryExists("gokz-core");

	ConVar cvPrefix = FindConVar("gokz_chat_prefix");
	if (cvPrefix != null)
	{
		cvPrefix.GetString(g_Prefix, sizeof(g_Prefix));
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (StrEqual(name, "gokz-core"))
	{
		g_UsesGokz = false;
	}
}

public void OnLibraryAdded(const char[] name)
{
	if (StrEqual(name, "gokz-core"))
	{
		g_UsesGokz = true;
	}
}

static bool hasSpawned[MAXPLAYERS + 1];

public void OnClientPutInServer(int client)
{
	OnClientPutInServer_FirstSpawn(client);
}

void OnClientPutInServer_FirstSpawn(int client)
{
	hasSpawned[client] = false;
}

public void GOKZ_OnOptionChanged(int client, const char[] option, any newValue)
{
	if (StrEqual(option, gC_CoreOptionNames[Option_Mode]))
	{
		int mode = GOKZ_GetCoreOption(client, Option_Mode);
		RequestRecords(client, mode);
	}
}

public void OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast)  // player_spawn post hook
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (IsValidClient(client))
	{
		int team = GetClientTeam(client);
		if (!hasSpawned[client] && (team == CS_TEAM_CT || team == CS_TEAM_T))
		{
			hasSpawned[client] = true;

			int mode           = 2;  // Default to KZTimer
			if (g_UsesGokz)
			{
				mode = GOKZ_GetCoreOption(client, Option_Mode);
			}

			if (mode >= sizeof(gC_APIModes))
			{
				return;
			}
			RequestRecords(client, mode);
		}
	}
}

void RequestRecords(int client, int mode)
{
	char map[256];
	GetCurrentMap(map, sizeof(map));
	GetMapDisplayName(map, map, sizeof(map));
	int userid       = GetClientUserId(client);
	int targetUserid = GetClientUserId(client);

	DataPack data1 = CreateDataPack();

	data1.WriteCell(userid);
	data1.WriteCell(targetUserid);
	data1.WriteCell(mode);
	// course
	data1.WriteCell(0);
	// tp
	data1.WriteCell(1);
	data1.WriteString(map);
	// 1.get wr?    2.pro/tp?
	RequestGlobalPB(true, client, map, 0, mode, true, HTTPRequestCompleted_Stage1, data1);
}

void HTTPRequestCompleted_Stage1(Handle request, bool failure, bool requestSuccess, EHTTPStatusCode status, DataPack data1)
{
	if (failure || !requestSuccess || status != k_EHTTPStatusCode200OK)
	{
		delete request;
		delete data1;
		return;
	}

	float wrTime      = -1.0;
	int   wrTeleports = -1;
	int   wrPoints    = -1;
	if (!GetRequestRecordInfo(request, wrTime, wrTeleports, wrPoints))
	{
		delete request;
		delete data1;
		return;
	}

	data1.Reset();
	int userid       = data1.ReadCell();
	int targetUserid = data1.ReadCell();
	int mode         = data1.ReadCell();
	int course       = data1.ReadCell();
	int hasTeleports = data1.ReadCell();

	char map[256];
	data1.ReadString(map, sizeof(map));

	int client = GetClientOfUserId(userid);
	int target = GetClientOfUserId(targetUserid);
	if (client == 0 || target == 0)
	{
		delete request;
		delete data1;
		return;
	}

	DataPack data2 = new DataPack();
	data2.WriteFloat(wrTime);
	data2.WriteCell(wrTeleports);
	data2.WriteCell(wrPoints);

	RequestGlobalPB(false, target, map, course, mode, hasTeleports > 0 ? true : false, HTTPRequestCompleted_Stage2, data1, data2);

	delete request;
}

void HTTPRequestCompleted_Stage2(Handle request, bool failure, bool requestSuccess, EHTTPStatusCode status, DataPack data1, DataPack data2)
{
	data1.Reset();
	int userid       = data1.ReadCell();
	int targetUserid = data1.ReadCell();
	int mode         = data1.ReadCell();
	int course       = data1.ReadCell();
	int hasTeleports = data1.ReadCell();

	char map[256];
	data1.ReadString(map, sizeof(map));

	delete data1;

	DataPack data1 = CreateDataPack();
	data1.WriteCell(userid);
	data1.WriteCell(targetUserid);
	data1.WriteCell(mode);
	data1.WriteCell(course);
	// get pro
	data1.WriteCell(0);
	data1.WriteString(map);

	data2.Reset();
	float wrTime = data2.ReadFloat();
	delete data2;

	float pbTime      = -1.0;
	int   pbTeleports = -1;
	int   pbPoints    = -1;
	if (!GetRequestRecordInfo(request, pbTime, pbTeleports, pbPoints))
	{
		delete request;
		return;
	}

	delete request;

	int client = GetClientOfUserId(userid);
	int target = GetClientOfUserId(targetUserid);
	if (client == 0 || target == 0)
	{
		return;
	}

	PrintRecordsOnSpawn(client, mode, hasTeleports, wrTime, pbTime, pbTeleports, pbPoints);

	if (hasTeleports > 0)
	{
		// get pro records
		RequestGlobalPB(true, client, map, course, mode, false, HTTPRequestCompleted_Stage1, data1);
	}
}

void PrintRecordsOnSpawn(int client, int mode, int hasTeleports, float wrTime, float pbTime, int pbTeleports, int pbPoints)
{
	char fmtWrTime[32], fmtPbTime[32], wrPhrase[32], pbPhrase[128];
	if (wrTime > 0)
	{
		FormatDuration(fmtWrTime, sizeof(fmtWrTime), wrTime);
		FormatEx(wrPhrase, sizeof(wrPhrase), "{green}%s", fmtWrTime);
	}
	else
	{
		FormatEx(wrPhrase, sizeof(wrPhrase), "{grey}暂无");
	}

	if (pbTime > 0)
	{
		FormatDuration(fmtPbTime, sizeof(fmtPbTime), pbTime);
		FormatEx(pbPhrase, sizeof(pbPhrase), "{green}%s {default}| {yellow}%d{default}分 | {yellow}%d{default}TP", fmtPbTime, pbPoints, pbTeleports);
	}
	else
	{
		FormatEx(pbPhrase, sizeof(pbPhrase), "{grey}暂无");
	}

	FormatDuration(fmtPbTime, sizeof(fmtPbTime), pbTime);
	if (hasTeleports > 0)
	{
		CPrintToChat(client, "{darkblue}%s {default}- {lightblue}存点记录 {default}- {darkred}WR{default} [ %s{default} ] - {lime}PB {default}[ %s ]", gC_ModeShort[mode], wrPhrase, pbPhrase);
	}
	else
	{
		CPrintToChat(client, "{darkblue}%s {default}- {blue}裸跳记录 {default}- {darkred}WR{default} [ %s{default} ] - {lime}PB {default}[ %s ]", gC_ModeShort[mode], wrPhrase, pbPhrase);
	}
}