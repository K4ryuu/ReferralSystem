/* <----> Includes <----> */
#include <karyuu>
#include <discordWebhookAPI>

#undef REQUIRE_EXTENSIONS
#undef REQUIRE_PLUGIN
#include <store>
#include <shop>

/* <----> Pragma <----> */
#pragma tabsize 3;
#pragma semicolon 1;
#pragma newdecls required;

#define _DatabaseEntry "ref_system"

/* <----> Globals <----> */
Database g_database = null;

ConVar	g_hConVarCreditsStart;
ConVar	g_hConVarCreditsStep;
ConVar	g_hConVarCreditsNew;
ConVar	g_hConVarWebHook;
ConVar	g_hConVarMinTime;
ConVar	g_hConVarRewardTime;

char		g_sPlayerSteamID[MAXPLAYERS + 1][32];
char		g_sPlayerCode[MAXPLAYERS + 1][32];
char		g_sPlayerInviter[MAXPLAYERS + 1][MAX_NAME_LENGTH];
char		g_sPlayerInviterSteam[MAXPLAYERS + 1][32];

int		g_iPlayerInvited[MAXPLAYERS + 1];
int		g_iPlayerValidated[MAXPLAYERS + 1];
int		g_iPlayerTime[MAXPLAYERS + 1]			 = { 0, ... };
int		g_iStoreSupport							 = 0;

bool		g_iPlayerWriteStatus[MAXPLAYERS + 1] = { false, ... };
bool		g_bPlayerRedeemed[MAXPLAYERS + 1]	 = { false, ... };
bool		g_bPlayerRecieved[MAXPLAYERS + 1]	 = { false, ... };

/* <----> Plugin Info <----> */
public Plugin myinfo =
{
	name			= "Player Referral System",
	author		= "KitsuneLab | Karyuu",
	description = "A plugin that allows players to refer other players to the server for rewards.",
	version		= "1.0",
	url			= "https://kitsune-lab.dev/"
};

/* <----> Code <----> */
public void OnPluginStart()
{
	char sTranslationPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, STRING(sTranslationPath), "translations/karyuu_referral.phrases.txt");

	if (FileExists(sTranslationPath))
	{
		LoadTranslations("karyuu_referral.phrases");
	}
	else
		SetFailState("Missing translation file: %s", sTranslationPath);

	HookEvent("player_team", EventHook_PlayerTeam);

	if (SQL_CheckConfig(_DatabaseEntry))
	{
		Database.Connect(Database_Connect_Callback, _DatabaseEntry);
	}
	else
		SetFailState("Database entry (\"%s\") is missing from \"databases.cfg\"", _DatabaseEntry);

	g_hConVarCreditsNew	 = CreateConVar("sm_refer_credit_invited", "50", "How many credits players will receive when they enter a code.", _, true, 0.0);
	g_hConVarCreditsStep	 = CreateConVar("sm_refer_credit_inviter_step", "10", "How much credit increase in reward after an invite.", _, true, 0.0);
	g_hConVarCreditsStart = CreateConVar("sm_refer_credit_inviter_start", "100", "The base reward for the first invite. After that (start + (invited * step))", _, true, 0.0);
	g_hConVarWebHook		 = CreateConVar("sm_refer_discord_webhook", "", "Discord WebHook to send refer messages", FCVAR_PROTECTED);
	g_hConVarMinTime		 = CreateConVar("sm_refer_min_time", "10", "Minimum time to refer a code", _, true, 0.0);
	g_hConVarRewardTime	 = CreateConVar("sm_refer_reward_time", "180", "How much time player have to play to get the rewards", _, true, 0.0);

	AutoExecConfig(true, "plugin.ReferralSystem");

	Karyuu_RegMultipleCommand("sm_ref;sm_referral", Command_ReferralMenu, "Opens the referral menu");
	Karyuu_RegCommand("sm_redeem", Command_ReferCode, "Uses a referral code to claim rewards");
	Karyuu_RegCommand("sm_noredeem", Command_NoReferCode, "Set no referral and claim rewards");

	CreateTimer(60.0, Timer_AddPlayTime, _, TIMER_REPEAT);
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	MarkNativeAsOptional("Store_SetClientCredits");
	MarkNativeAsOptional("Store_GetClientCredits");
	MarkNativeAsOptional("Shop_GiveClientCredits");
	return APLRes_Success;
}

public void OnAllPluginsLoaded()
{
	// --> Check if any stores are loaded
	if (LibraryExists("store_zephyrus"))
	{
		g_iStoreSupport = 1;
	}
	else if (LibraryExists("shop"))
	{
		g_iStoreSupport = 2;
	}
	else
		SetFailState("No supported store plugin found, please install 'Store Zephyrus' or 'Shop-Core'.");
}

public Action Timer_AddPlayTime(Handle timer, DataPack pack)
{
	char			sQuery[256];
	Transaction txn = new Transaction();

	for (int iClient = 1; iClient < MaxClients; iClient++)
	{
		if (!IsClientInGame(iClient) || IsFakeClient(iClient))
			continue;

		if (g_bPlayerRecieved[iClient])
			continue;

		g_iPlayerTime[iClient]++;
		g_database.Format(STRING(sQuery), "UPDATE `ref_data` SET `time` = (`time` + '1') WHERE `steamid` = '%s';", g_sPlayerSteamID[iClient]);
		txn.AddQuery(sQuery);

		if (!g_bPlayerRedeemed[iClient] && g_sPlayerInviter[iClient][0] == '\0')
		{
			if (g_iPlayerTime[iClient] > g_hConVarMinTime.IntValue)
			{
				FormatEx(g_sPlayerInviter[iClient], sizeof(g_sPlayerInviter[]), "None");

				g_bPlayerRedeemed[iClient] = true;

				g_database.Format(STRING(sQuery), "UPDATE `ref_data` SET `inviter` = 'None' WHERE `steamid` = '%s';", g_sPlayerSteamID[iClient]);
				txn.AddQuery(sQuery);

				continue;
			}

			char sBuffer[256];
			FormatEx(STRING(sBuffer), "%T", "CHAT_REFER_AVAILABLE_HINT", iClient, g_hConVarMinTime.IntValue - g_iPlayerTime[iClient]);

			PrintHintText(iClient, sBuffer);
			CPrintToChat(iClient, "{default}「{lightred}%T{default}」{lime}%T", "CHAT_PREFIX", iClient, "CHAT_REFER_AVAILABLE", iClient, g_hConVarMinTime.IntValue - g_iPlayerTime[iClient]);
		}
		else if (!g_bPlayerRecieved[iClient] && g_iPlayerTime[iClient] > g_hConVarRewardTime.IntValue)
		{
			GiveCredits(iClient, g_hConVarCreditsNew.IntValue);
			g_bPlayerRecieved[iClient] = true;
			CPrintToChat(iClient, "{default}「{lightred}%T{default}」{lime}%T", "CHAT_PREFIX", iClient, "CHAT_REFERED", iClient, g_sPlayerInviter[iClient], g_hConVarCreditsNew.IntValue);

			g_database.Format(STRING(sQuery), "UPDATE `ref_data` USE INDEX(`indexed_steamid`) SET `invited` = (`invited` + '1') WHERE `steamid` = '%s';", g_sPlayerInviterSteam[iClient]);
			g_database.Query(Nothing_Callback, sQuery);

			g_database.Format(STRING(sQuery), "UPDATE `ref_data` USE INDEX(`indexed_steamid`) SET `recieved` = '1' WHERE `steamid` = '%s';", g_sPlayerSteamID[iClient]);
			g_database.Query(Nothing_Callback, sQuery);

			for (int iTarget = 1; iTarget <= MaxClients; iTarget++)
			{
				if (IsClientInGame(iTarget) && !IsFakeClient(iTarget))
				{
					if (Karyuu_StrEquals(g_sPlayerSteamID[iTarget], g_sPlayerInviterSteam[iClient]))
					{
						g_iPlayerInvited[iTarget]++;
						g_iPlayerValidated[iTarget]++;

						g_database.Format(STRING(sQuery), "UPDATE `ref_data` USE INDEX(`indexed_steamid`) SET `validated` = (`validated` + '1') WHERE `steamid` = '%s';", g_sPlayerInviterSteam[iClient]);
						g_database.Query(Nothing_Callback, sQuery);

						int iCredit = g_hConVarCreditsStart.IntValue + (g_iPlayerInvited[iTarget] * g_hConVarCreditsStep.IntValue);

						GiveCredits(iTarget, iCredit);

						CPrintToChat(iTarget, "{default}「{lightred}%T{default}」{lime}%T", "CHAT_PREFIX", iTarget, "CHAT_REFERED_BY", iTarget, iCredit, iClient);
						break;
					}
				}
			}
		}
	}
	g_database.Execute(txn);
	return Plugin_Continue;
}

public Action EventHook_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	int iClient = GetClientOfUserId(GetEventInt(event, "userid"));

	if (!IsClientInGame(iClient) || IsFakeClient(iClient))
		return Plugin_Continue;

	int iAddRefer = g_iPlayerInvited[iClient] - g_iPlayerValidated[iClient];

	if (iAddRefer > 0)
	{
		int iGivenCredit, iCredit;
		while (g_iPlayerInvited[iClient] > g_iPlayerValidated[iClient])
		{
			iCredit = g_hConVarCreditsStart.IntValue + (g_iPlayerValidated[iClient] * g_hConVarCreditsStep.IntValue);

			iGivenCredit += iCredit;
			g_iPlayerValidated[iClient]++;
		}

		if (iGivenCredit > 0)
		{
			GiveCredits(iClient, iGivenCredit);
			CPrintToChat(iClient, "{default}「{lightred}%T{default}」{lime}%T", "CHAT_PREFIX", iClient, "CHAT_RECIEVE_OFFLINE", iClient, iGivenCredit, iAddRefer);
		}

		char sQuery[256];
		g_database.Format(STRING(sQuery), "UPDATE `ref_data` USE INDEX(`indexed_steamid`) SET `validated` = '%d' WHERE `steamid` = '%s';", g_iPlayerInvited[iClient], g_sPlayerSteamID[iClient]);
		g_database.Query(Nothing_Callback, sQuery);
	}
	return Plugin_Continue;
}

public Action Command_NoReferCode(int iClient, int iArgs)
{
	if (!IsClientConnected(iClient))
		return Plugin_Handled;

	if (g_sPlayerInviter[iClient][0] != '\0')
	{
		CPrintToChat(iClient, "{default}「{lightred}%T{default}」{lightred}%T", "CHAT_PREFIX", iClient, Karyuu_StrEquals(g_sPlayerInviter[iClient], "None") ? "CHAT_CANT_REFER" : "CHAT_ALREADY_REFERRED", iClient);
		return Plugin_Handled;
	}

	FormatEx(g_sPlayerInviter[iClient], sizeof(g_sPlayerInviter[]), "None");

	char sQuery[256];
	g_database.Format(STRING(sQuery), "UPDATE `ref_data` SET `inviter` = 'None', `recieved` = '1' WHERE `steamid` = '%s';", g_sPlayerSteamID[iClient]);
	g_database.Query(Nothing_Callback, sQuery);

	int iCredit = RoundFloat(g_hConVarCreditsNew.IntValue * 0.5);
	GiveCredits(iClient, iCredit);
	g_bPlayerRecieved[iClient] = true;

	CPrintToChat(iClient, "{default}「{lightred}%T{default}」{lightred}%T", "CHAT_PREFIX", iClient, "CHAT_REFERED", iClient, "None", iCredit);
	return Plugin_Handled;
}

public Action Command_ReferCode(int iClient, int iArgs)
{
	if (!IsClientConnected(iClient))
		return Plugin_Handled;

	if (g_sPlayerInviter[iClient][0] != '\0')
	{
		CPrintToChat(iClient, "{default}「{lightred}%T{default}」{lightred}%T", "CHAT_PREFIX", iClient, Karyuu_StrEquals(g_sPlayerInviter[iClient], "None") ? "CHAT_CANT_REFER" : "CHAT_ALREADY_REFERRED", iClient);
		return Plugin_Handled;
	}

	char sArg[256];
	GetCmdArgString(STRING(sArg));

	if (sArg[0] == '\0')
	{
		CPrintToChat(iClient, "{default}「{lightred}%T{default}」{lightred}%T", "CHAT_PREFIX", iClient, "CHAT_CMD_HELP", iClient);
		return Plugin_Handled;
	}

	if (strlen(sArg) < 3 || strlen(sArg) > 16)
	{
		CPrintToChat(iClient, "{default}「{lightred}%T{default}」{lightred}%T", "CHAT_PREFIX", iClient, "CHAT_LENGTH_ERROR", iClient);
		return Plugin_Handled;
	}

	if (Karyuu_StrEquals(sArg, g_sPlayerCode[iClient]))
	{
		CPrintToChat(iClient, "{default}「{lightred}%T{default}」{lightred}%T", "CHAT_PREFIX", iClient, "CHAT_OWN_CODE", iClient);
		return Plugin_Handled;
	}

	char sQuery[256];
	g_database.Format(STRING(sQuery), "SELECT `name`,`steamid`,`code` FROM `ref_data` USE INDEX (`indexed_code`) WHERE `code` = '%s';", sArg);
	g_database.Query(Callback_GetCodeData, sQuery, GetClientSerial(iClient));
	return Plugin_Handled;
}

public Action Command_ReferralMenu(int iClient, int iArgs)
{
	if (!IsClientConnected(iClient))
		return Plugin_Handled;

	if (g_sPlayerInviter[iClient][0] == '\0')
	{
		CPrintToChat(iClient, "{default}「{lightred}%T{default}」{lightred}%T", "CHAT_PREFIX", iClient, "CHAT_WAIT", iClient, g_hConVarMinTime.IntValue - g_iPlayerTime[iClient]);
		return Plugin_Handled;
	}

	bool	bCustomAccess = Karyuu_ClientHasFlag(iClient, ADMFLAG_CUSTOM3) || Karyuu_ClientHasFlag(iClient, ADMFLAG_CUSTOM4) || Karyuu_ClientHasFlag(iClient, ADMFLAG_CUSTOM6);

	Panel hPanel		  = new Panel();

	Karyuu_Panel_SetTitle(hPanel, "☰ %T\n ", "MENU_TITLE", iClient);

	Karyuu_Panel_AddText(hPanel, "   • %T: %s", "MENU_INVITED_BY", iClient, g_sPlayerInviter[iClient]);
	Karyuu_Panel_AddText(hPanel, "   • %T: %s", "MENU_CODE", iClient, g_sPlayerCode[iClient]);
	Karyuu_Panel_AddText(hPanel, "   • %T: %d\n ", "MENU_YOU_INVITED", iClient, g_iPlayerInvited[iClient]);
	Karyuu_Panel_AddItem(hPanel, bCustomAccess ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED, " ▸ %T", "MENU_SET_CUSTOM", iClient);
	Karyuu_Panel_AddText(hPanel, " ");
	Karyuu_Panel_AddItem(hPanel, _, "%T", "MENU_EXIT", iClient);
	Karyuu_Panel_Send(hPanel, MenuSystem_MainMenu_Handler, iClient);

	return Plugin_Handled;
}

public int MenuSystem_MainMenu_Handler(Menu menu, MenuAction action, int iClient, int iParam)
{
	Karyuu_HandlePanelJunk(menu, action);

	if (action == MenuAction_Select)
	{
		switch (iParam)
		{
			case 1:
			{
				g_iPlayerWriteStatus[iClient] = true;
				CPrintToChat(iClient, "{default}「{lightred}%T{default}」{lightred}%T", "CHAT_PREFIX", iClient, "CHAT_ENTER_NEW_CODE", iClient);
			}
			default:
				delete menu;
		}
	}
	return 0;
}

public void Database_Connect_Callback(Database database, const char[] error, any data)
{
	if (database == null)
	{
		SetFailState("Database connection has failed | Error: %s", error);
		return;
	}

	g_database = database;

	char sQuery[512];
	g_database.Format(STRING(sQuery), "CREATE TABLE IF NOT EXISTS `ref_data` ( `name` VARCHAR(64) NOT NULL, `steamid` VARCHAR(32) NOT NULL, `inviter` VARCHAR(32) NULL, `inviter_steam` VARCHAR(32) NULL, `code` VARCHAR(32) NOT NULL COLLATE 'utf8mb4_general_ci', `recieved` MEDIUMINT UNSIGNED NULL DEFAULT '0', `invited` MEDIUMINT UNSIGNED NULL DEFAULT '0', `validated` MEDIUMINT UNSIGNED NULL DEFAULT '0', `time` MEDIUMINT UNSIGNED NULL DEFAULT '0', PRIMARY KEY (`steamid`) USING BTREE, UNIQUE INDEX `indexed_steamid` (`steamid`) USING BTREE, UNIQUE INDEX `indexed_code` (`code`) USING BTREE ) COLLATE='utf8mb4_general_ci' ENGINE=InnoDB;");
	g_database.Query(Supressed_Callback, sQuery);

	for (int iClient = 1; iClient < MAXPLAYERS; iClient++)
	{
		if (!IsClientInGame(iClient) || IsFakeClient(iClient))
			continue;

		OnClientPostAdminCheck(iClient);
	}
}

public void Nothing_Callback(Database database, DBResultSet result, char[] error, any data)
{
	if (database == null || result == null)
		LogError("Query failure | A | Error: %s", error);
}

public void Supressed_Callback(Database database, DBResultSet result, char[] error, any data) {}

public void OnClientPostAdminCheck(int iClient)
{
	if (!IsClientConnected(iClient) || IsFakeClient(iClient))
		return;

	if (!GetClientAuthId(iClient, AuthId_SteamID64, g_sPlayerSteamID[iClient], sizeof(g_sPlayerSteamID[])))
		LogError("Failed to get SteamID64 of client | %L", iClient);

	g_iPlayerWriteStatus[iClient]	 = false;
	g_iPlayerInvited[iClient]		 = 0;
	g_bPlayerRedeemed[iClient]		 = false;
	g_iPlayerValidated[iClient]	 = 0;
	g_iPlayerTime[iClient]			 = 0;
	g_sPlayerInviter[iClient][0]	 = '\0';
	g_sPlayerInviterSteam[iClient] = NULL_STRING;

	char sQuery[256];
	g_database.Format(STRING(sQuery), "SELECT `code`, `invited`, `validated`, `inviter`, `time`, `inviter_steam`, `recieved` FROM `ref_data` USE INDEX (`indexed_steamid`) WHERE `steamid` = '%s';", g_sPlayerSteamID[iClient]);
	g_database.Query(Callback_ClientLoad, sQuery, GetClientSerial(iClient));
}

static void Callback_ClientLoad(Database database, DBResultSet result, char[] error, any data)
{
	if (database == null || result == null)
	{
		LogError("Query failure | B | Error: %s", error);
		return;
	}

	int iClient = GetClientFromSerial(data);
	if (Karyuu_IsValidPlayer(iClient))
	{
		char sQuery[256];

		if (result.RowCount > 0)
		{
			while (result.FetchRow())
			{
				g_database.Format(STRING(sQuery), "UPDATE `ref_data` USE INDEX(`indexed_steamid`) SET `name` = '%N' WHERE `steamid` = '%s';", iClient, g_sPlayerSteamID[iClient]);
				g_database.Query(Nothing_Callback, sQuery);

				result.FetchString(0, g_sPlayerCode[iClient], sizeof(g_sPlayerCode[]));
				g_iPlayerInvited[iClient]	 = result.FetchInt(1);
				g_iPlayerValidated[iClient] = result.FetchInt(2);
				g_iPlayerTime[iClient]		 = result.FetchInt(4);
				result.FetchString(5, g_sPlayerInviterSteam[iClient], sizeof(g_sPlayerInviterSteam[]));
				g_bPlayerRecieved[iClient] = view_as<bool>(result.FetchInt(6));

				if (strlen(g_sPlayerInviterSteam[iClient]) > 2 || Karyuu_StrEquals(g_sPlayerCode[iClient], "None"))
					g_bPlayerRedeemed[iClient] = true;

				char sInviter[16];
				result.FetchString(3, STRING(sInviter));

				if (sInviter[0] != '\0')
				{
					g_database.Format(STRING(sQuery), "SELECT `name` FROM `ref_data` USE INDEX (`indexed_code`) WHERE `code` = '%s';", sInviter);
					g_database.Query(Callback_GetInviter, sQuery, GetClientSerial(iClient));
				}
			}
		}
		else
		{
			g_database.Format(STRING(sQuery), "INSERT INTO `ref_data` (`name`, `steamid`, `code`) VALUES ('%N', '%s', SUBSTRING(MD5(RAND()) FROM 1 FOR 6));", iClient, g_sPlayerSteamID[iClient]);
			g_database.Query(Nothing_Callback, sQuery);

			g_database.Format(STRING(sQuery), "SELECT `code`, `invited`, `validated`, `inviter`, `time`, `inviter_steam`, `recieved` FROM `ref_data` USE INDEX (`indexed_steamid`) WHERE `steamid` = '%s';", g_sPlayerSteamID[iClient]);
			g_database.Query(Callback_ClientLoad, sQuery, GetClientSerial(iClient));
		}
	}
}

static void Callback_GetInviter(Database database, DBResultSet result, char[] error, any data)
{
	if (database == null || result == null)
	{
		LogError("Query failure | D | Error: %s", error);
		return;
	}

	int iClient = GetClientFromSerial(data);
	if (IsClientInGame(iClient) && !IsFakeClient(iClient))
	{
		if (result.RowCount > 0)
		{
			while (result.FetchRow())
				result.FetchString(0, g_sPlayerInviter[iClient], sizeof(g_sPlayerInviter[]));
		}
		else
			FormatEx(g_sPlayerInviter[iClient], sizeof(g_sPlayerInviter[]), "None");
	}
}

public Action OnClientSayCommand(int iClient, const char[] command, const char[] message)
{
	if (iClient < 1 || iClient > MaxClients || !IsClientInGame(iClient) || IsChatTrigger() || !g_iPlayerWriteStatus[iClient])
		return Plugin_Continue;

	char trimmedMessage[255], sQuery[256];
	strcopy(STRING(trimmedMessage), message);
	TrimString(trimmedMessage);

	if (Karyuu_StrEquals(trimmedMessage, "cancel"))
	{
		g_iPlayerWriteStatus[iClient] = false;
		return Plugin_Handled;
	}

	if (strlen(trimmedMessage) < 3 || strlen(trimmedMessage) > 16)
	{
		CPrintToChat(iClient, "{default}「{lightred}%T{default}」{lightred}%T", "CHAT_PREFIX", iClient, "CHAT_LENGTH_ERROR", iClient);
		return Plugin_Handled;
	}

	if (Karyuu_StrEquals(trimmedMessage, "None"))
	{
		CPrintToChat(iClient, "{default}「{lightred}%T{default}」{lightred}%T", "CHAT_PREFIX", iClient, "CHAT_CODE_EXISTS", iClient);
		return Plugin_Handled;
	}

	DataPack pack = new DataPack();
	pack.WriteCell(GetClientSerial(iClient));
	pack.WriteString(trimmedMessage);
	pack.Reset();

	g_database.Format(STRING(sQuery), "SELECT `name` FROM `ref_data` USE INDEX (`indexed_code`) WHERE `code` = '%s';", trimmedMessage);
	g_database.Query(Callback_CheckCodeExistance, sQuery, pack);

	g_iPlayerWriteStatus[iClient] = false;
	return Plugin_Handled;
}

static void Callback_CheckCodeExistance(Database database, DBResultSet result, char[] error, any data)
{
	if (database == null || result == null)
	{
		LogError("Query failure | E | Error: %s", error);
		return;
	}

	int iClient = GetClientFromSerial(view_as<DataPack>(data).ReadCell());
	if (IsClientInGame(iClient) && !IsFakeClient(iClient))
	{
		if (result.RowCount <= 0)
		{
			char sQuery[256], sCode[32];
			view_as<DataPack>(data).ReadString(STRING(sCode));

			g_database.Format(STRING(sQuery), "UPDATE `ref_data` USE INDEX(`indexed_code`) SET `code` = '%s' WHERE `code` = '%s';", sCode, g_sPlayerCode[iClient]);
			g_database.Query(Nothing_Callback, sQuery);

			g_database.Format(STRING(sQuery), "UPDATE `ref_data` SET `inviter` = '%s' WHERE `inviter` = '%s';", sCode, g_sPlayerCode[iClient]);
			g_database.Query(Nothing_Callback, sQuery);

			FormatEx(g_sPlayerCode[iClient], sizeof(g_sPlayerCode[]), sCode);

			CPrintToChat(iClient, "{default}「{lightred}%T{default}」{lightred}%T", "CHAT_PREFIX", iClient, "CHAT_CODE_CHANGED", iClient, sCode);
		}
		else
			CPrintToChat(iClient, "{default}「{lightred}%T{default}」{lightred}%T", "CHAT_PREFIX", iClient, "CHAT_CODE_EXISTS", iClient);
	}
}

static void Callback_GetCodeData(Database database, DBResultSet result, char[] error, any data)
{
	if (database == null || result == null)
	{
		LogError("Query failure | F | Error: %s", error);
		return;
	}

	int iClient = GetClientFromSerial(data);
	if (IsClientInGame(iClient) && !IsFakeClient(iClient))
	{
		if (result.RowCount > 0)
		{
			while (result.FetchRow())
			{
				char sQuery[256], sInviterCode[32];
				result.FetchString(0, g_sPlayerInviter[iClient], sizeof(g_sPlayerInviter[]));
				result.FetchString(1, g_sPlayerInviterSteam[iClient], sizeof(g_sPlayerInviterSteam[]));
				result.FetchString(2, STRING(sInviterCode));

				g_bPlayerRedeemed[iClient] = true;

				g_database.Format(STRING(sQuery), "UPDATE `ref_data` USE INDEX(`indexed_steamid`) SET `inviter` = '%s', `inviter_steam` = '%s' WHERE `steamid` = '%s';", sInviterCode, g_sPlayerInviterSteam[iClient], g_sPlayerSteamID[iClient]);
				g_database.Query(Nothing_Callback, sQuery);

				CPrintToChat(iClient, "{default}「{lightred}%T{default}」{lime}%T", "CHAT_PREFIX", iClient, "CHAT_REFERRED", iClient, g_hConVarRewardTime.IntValue);

				static char sWebHook[512];
				if (sWebHook[0] == '\0')
					g_hConVarWebHook.GetString(STRING(sWebHook));

				if (sWebHook[0] != '\0')
				{
					char	  sBuffer[256];

					Webhook hWebhook = new Webhook();
					hWebhook.SetUsername("KitsuneLab");
					hWebhook.SetAvatarURL("https://kitsune-lab.dev/storage/images/kl-logo.webp");

					Embed hEmbed = new Embed("⌜Player Referral⌟", "");
					hEmbed.SetTimeStampNow();
					hEmbed.SetColor(15844367);

					char sServerName[256];
					FindConVar("hostname").GetString(STRING(sServerName));

					EmbedFooter hFooter = new EmbedFooter(sServerName);
					hFooter.SetIconURL("https://img.icons8.com/cotton/64/000000/server.png");
					hEmbed.SetFooter(hFooter);
					delete hFooter;

					FormatEx(STRING(sBuffer), "▹ [%N](http://www.steamcommunity.com/profiles/%s)", iClient, g_sPlayerSteamID[iClient]);

					EmbedField hFieldA = new EmbedField("◉ PLAYER", sBuffer, true);
					hEmbed.AddField(hFieldA);

					FormatEx(STRING(sBuffer), "▹ [%s](http://www.steamcommunity.com/profiles/%s)", g_sPlayerInviter[iClient], g_sPlayerInviterSteam[iClient]);

					EmbedField hFieldB = new EmbedField("◉ INVITER", sBuffer, true);
					hEmbed.AddField(hFieldB);

					FormatEx(STRING(sBuffer), "▹ %s", sInviterCode);

					EmbedField hFieldC = new EmbedField("◉ CODE", sBuffer, true);
					hEmbed.AddField(hFieldC);

					hWebhook.AddEmbed(hEmbed);

					hWebhook.Execute(sWebHook, OnWebHookExecuted, _);
					delete hWebhook;
				}
			}
		}
		else
			CPrintToChat(iClient, "{default}「{lightred}%T{default}」{lightred}%T", "CHAT_PREFIX", iClient, "CHAT_CODE_NOT_FOUND", iClient);
	}
}

public void OnWebHookExecuted(HTTPResponse response, any id)
{
	if (response.Status != HTTPStatus_OK)
		LogError("An error has occured while sending a discord webhook. | Status: %d", response.Status);
}

stock void GiveCredits(int iClient, int iCredit)
{
	switch (g_iStoreSupport)
	{
		case 1:
		{
			Store_SetClientCredits(iClient, (Store_GetClientCredits(iClient) + iCredit));
		}
		case 2:
		{
			Shop_GiveClientCredits(iClient, iCredit);
		}
	}
}