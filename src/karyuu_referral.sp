/* <----> Includes <----> */
#include <karyuu>
#include <discordWebhookAPI>

/* <----> Pragma <----> */
#pragma tabsize 3;
#pragma semicolon 1;
#pragma newdecls required;

#define _DatabaseEntry "referral_system"

/* <----> Globals <----> */
Database g_database = null;

ConVar	g_hConVarCreditsStart;
ConVar	g_hConVarCreditsStep;
ConVar	g_hConVarCreditsNew;
ConVar	g_hConVarWebHook;
ConVar	g_hConVarMinTime;

char		g_sPlayerSteamID[MAXPLAYERS + 1][32];
char		g_sPlayerCode[MAXPLAYERS + 1][32];
char		g_sPlayerInviter[MAXPLAYERS + 1][MAX_NAME_LENGTH];

int		g_iPlayerInvited[MAXPLAYERS + 1];
int		g_iPlayerValidated[MAXPLAYERS + 1];
int		g_iPlayerWriteStatus[MAXPLAYERS + 1] = { 0, ... };
int		g_iPlayerTime[MAXPLAYERS + 1]			 = { 0, ... };

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

	g_hConVarCreditsNew	 = CreateConVar("sm_refer_credit_invited", "25.0", "How many credits players will receive when they enter a code.", _, true, 0.0);
	g_hConVarCreditsStep	 = CreateConVar("sm_refer_credit_inviter_step", "5.0", "How much credit increase in reward after an invite.", _, true, 0.0);
	g_hConVarCreditsStart = CreateConVar("sm_refer_credit_inviter_start", "10.0", "The base reward for the first invite. After that (start + (invited * step))", _, true, 0.0);
	g_hConVarWebHook		 = CreateConVar("sm_refer_discord_webhook", "", "Discord WebHook to send refer messages", FCVAR_PROTECTED);
	g_hConVarMinTime		 = CreateConVar("sm_refer_min_time", "10", "Minimum minutes to refer to the inviter", _, true, 0.0);

	Karyuu_RegCommand("sm_ref;sm_referral", Command_ReferralMenu, "Opens the referral menu");

	CreateTimer(60.0, Timer_AddPlayTime, _, TIMER_REPEAT);
}

public Action Timer_AddPlayTime(Handle timer, DataPack pack)
{
	for (int iClient = 1; iClient < MaxClients; iClient++)
	{
		if (!IsClientInGame(iClient) || IsFakeClient(iClient))
			continue;

		if (g_sPlayerInviter[iClient][0] != '\0' && g_iPlayerTime[iClient] < g_hConVarMinTime.IntValue)
			continue;

		g_iPlayerTime[iClient]++;
	}
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
		float iGivenCredit, iCredit;
		while (g_iPlayerInvited[iClient] > g_iPlayerValidated[iClient])
		{
			iCredit = g_hConVarCreditsStart.FloatValue + (g_iPlayerValidated[iClient] * g_hConVarCreditsStep.FloatValue);

			if (Karyuu_ClientHasFlag(iClient, ADMFLAG_CUSTOM3))
			{
				iCredit *= 3.0;
			}
			else if (Karyuu_ClientHasFlag(iClient, ADMFLAG_CUSTOM4))
			{
				iCredit *= 2.0;
			}
			else if (Karyuu_ClientHasFlag(iClient, ADMFLAG_CUSTOM6))
			{
				iCredit = iCredit * 1.5;
			}

			iGivenCredit += iCredit;
			g_iPlayerValidated[iClient]++;
		}

		if (iGivenCredit > 0)
		{
			GiveCredits(iClient, iGivenCredit);
			CPrintToChat(iClient, "{default}「{lightred}%T{default}」{lime}%T", "CHAT_PREFIX", iClient, "CHAT_RECIEVE_OFFLINE", iClient, iGivenCredit, g_hConVarCreditsNew.FloatValue);
		}

		char sQuery[256];
		g_database.Format(STRING(sQuery), "UPDATE `ref_data` USE INDEX(`indexed_steamid`) SET `validated` = '%d' WHERE `steamid` = '%s';", g_iPlayerInvited[iClient], g_sPlayerSteamID[iClient]);
		g_database.Query(Nothing_Callback, sQuery);
	}
	return Plugin_Continue;
}

public Action Command_ReferralMenu(int iClient, int iArgs)
{
	if (!IsClientConnected(iClient))
		return Plugin_Handled;

	bool	bCustomAccess = Karyuu_ClientHasFlag(iClient, ADMFLAG_CUSTOM3) || Karyuu_ClientHasFlag(iClient, ADMFLAG_CUSTOM4) || Karyuu_ClientHasFlag(iClient, ADMFLAG_CUSTOM6);

	Panel hPanel		  = new Panel();

	Karyuu_Panel_SetTitle(hPanel, "☰ %T\n ", "MENU_TITLE", iClient);

	Karyuu_Panel_AddText(hPanel, "   • %T: %s", "MENU_INVITED_BY", iClient, g_sPlayerInviter[iClient]);
	Karyuu_Panel_AddText(hPanel, "   • %T: %s", "MENU_CODE", iClient, g_sPlayerCode[iClient]);
	Karyuu_Panel_AddText(hPanel, "   • %T: %d\n ", "MENU_YOU_INVITED", iClient, g_iPlayerInvited[iClient]);
	Karyuu_Panel_AddItem(hPanel, bCustomAccess ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED, " ▸ %T", "MENU_SET_CUSTOM", iClient);
	Karyuu_Panel_AddItem(hPanel, g_sPlayerInviter[iClient][0] == '\0' ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED, " ▸ %T", "MENU_REFER", iClient);
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
				if (g_iPlayerTime[iClient] < g_hConVarMinTime.IntValue)
				{
					CPrintToChat(iClient, "{default}「{lightred}%T{default}」{lightred}%T", "CHAT_PREFIX", iClient, "CHAT_WAIT", iClient, g_hConVarMinTime.IntValue - g_iPlayerTime[iClient]);
					return 0;
				}

				g_iPlayerWriteStatus[iClient] = 1;
				CPrintToChat(iClient, "{default}「{lightred}%T{default}」{lightred}%T", "CHAT_PREFIX", iClient, "CHAT_ENTER_CODE", iClient);
			}
			case 2:
			{
				g_iPlayerWriteStatus[iClient] = 2;
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
	g_database.Format(STRING(sQuery), "CREATE TABLE `ref_data` ( `name` VARCHAR(64) NOT NULL, `steamid` VARCHAR(32) UNSIGNED NOT NULL, `inviter` VARCHAR(32) NULL, `code` VARCHAR(32) NOT NULL COLLATE 'utf8mb4_general_ci', `invited` MEDIUMINT(7) UNSIGNED NULL DEFAULT '0', `validated` MEDIUMINT(7) UNSIGNED NULL DEFAULT '0', PRIMARY KEY (`steamid`) USING BTREE, UNIQUE INDEX `indexed_steamid` (`steamid`) USING BTREE, UNIQUE INDEX `indexed_code` (`code`) USING BTREE ) COLLATE='utf8mb4_general_ci' ENGINE=InnoDB;");
	g_database.Query(Nothing_Callback, sQuery);

	for (int iClient = 1; iClient < MAXPLAYERS + 1; iClient++)
	{
		if (!IsClientInGame(iClient) || IsFakeClient(iClient))
			continue;

		OnClientPostAdminCheck(iClient);
	}
}

public void Nothing_Callback(Database database, DBResultSet result, char[] error, any data)
{
	if (database == null || result == null)
		LogError("Query failure | Error: %s", error);
}

public void OnClientPostAdminCheck(int iClient)
{
	if (!IsClientConnected(iClient) || IsFakeClient(iClient))
		return;

	if (GetClientAuthId(iClient, AuthId_SteamID64, g_sPlayerSteamID[iClient], sizeof(g_sPlayerSteamID[])))
		LogError("Failed to get SteamID64 of client | %L", iClient);

	g_iPlayerWriteStatus[iClient] = 0;
	g_iPlayerInvited[iClient]		= 0;
	g_iPlayerValidated[iClient]	= 0;
	g_iPlayerTime[iClient]			= 0;
	FormatEx(g_sPlayerCode[iClient], sizeof(g_sPlayerCode[]), "None");

	char sQuery[256];
	g_database.Format(STRING(sQuery), "SELECT `code`, `invited`, `validated`, `inviter` FROM `ref_data` USE INDEX (`indexed_steamid`) WHERE `steamid` = '%s';", g_sPlayerSteamID[iClient]);
	g_database.Query(Callback_ClientLoad, sQuery, GetClientSerial(iClient));
}

static void Callback_ClientLoad(Database database, DBResultSet result, char[] error, any data)
{
	if (database == null || result == null)
	{
		LogError("Query failure | Error: %s", error);
		return;
	}

	int iClient = GetClientFromSerial(data);
	if (IsClientInGame(iClient) && !IsFakeClient(iClient))
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

				char sInviter[16];
				result.FetchString(3, STRING(sInviter));

				if (sInviter[0] != '\0')
				{
					g_database.Format(STRING(sQuery), "SELECT `name` FROM `ref_data` USE INDEX (`indexed_code`) WHERE `code` = '%s';", sInviter);
					g_database.Query(Callback_GetInviter, sQuery, GetClientSerial(iClient));
				}
				else
					FormatEx(g_sPlayerInviter[iClient], sizeof(g_sPlayerInviter[]), "None");
			}
		}
		else
		{
			FormatEx(g_sPlayerCode[iClient], sizeof(g_sPlayerCode[]), "None");
			g_iPlayerInvited[iClient]	 = 0;
			g_iPlayerValidated[iClient] = 0;

			g_database.Format(STRING(sQuery), "INSERT INTO `ref_data` (`name`, `steamid`, `code`) VALUES ('%N', '%s', SUBSTRING(MD5(RAND()) FROM 1 FOR 6);", iClient, g_sPlayerSteamID[iClient]);
			g_database.Query(Nothing_Callback, sQuery);
		}
	}
}

static void Callback_GetInviter(Database database, DBResultSet result, char[] error, any data)
{
	if (database == null || result == null)
	{
		LogError("Query failure | Error: %s", error);
		return;
	}

	int iClient = GetClientFromSerial(data);
	if (IsClientInGame(iClient) && !IsFakeClient(iClient))
	{
		if (result.RowCount > 0)
		{
			while (result.FetchRow())
			{
				result.FetchString(0, g_sPlayerInviter[iClient], sizeof(g_sPlayerInviter[]));
			}
		}
		else
			FormatEx(g_sPlayerInviter[iClient], sizeof(g_sPlayerInviter[]), "None");
	}
}

public Action OnClientSayCommand(int iClient, const char[] command, const char[] message)
{
	if (iClient < 1 || iClient > MaxClients || !IsClientInGame(iClient) || IsChatTrigger() || g_iPlayerWriteStatus[iClient] == 0)
		return Plugin_Continue;

	char trimmedMessage[255];
	strcopy(STRING(trimmedMessage), message);
	TrimString(trimmedMessage);

	if (Karyuu_StrContains(trimmedMessage, "cancel"))
	{
		g_iPlayerWriteStatus[iClient] = 0;
		return Plugin_Handled;
	}

	char sQuery[256];

	switch (g_iPlayerWriteStatus[iClient])
	{
		case 1:
		{
			if (Karyuu_StrEquals(trimmedMessage, g_sPlayerCode[iClient]))
			{
				CPrintToChat(iClient, "{default}「{lightred}%T{default}」{lightred}%T", "CHAT_PREFIX", iClient, "CHAT_OWN_CODE", iClient);
				return Plugin_Handled;
			}

			g_database.Format(STRING(sQuery), "SELECT `name`,`steamid`,`code` FROM `ref_data` USE INDEX (`indexed_code`) WHERE `code` = '%s';", trimmedMessage);
			g_database.Query(Callback_GetCodeData, sQuery, GetClientSerial(iClient));
		}
		case 2:
		{
			if (strlen(trimmedMessage) < 3 || strlen(trimmedMessage) > 16)
			{
				CPrintToChat(iClient, "{default}「{lightred}%T{default}」{lightred}%T", "CHAT_PREFIX", iClient, "CHAT_LENGTH_ERROR", iClient);
				return Plugin_Handled;
			}

			DataPack pack = new DataPack();
			pack.WriteCell(GetClientSerial(iClient));
			pack.WriteString(trimmedMessage);
			pack.Reset();

			g_database.Format(STRING(sQuery), "SELECT `name` FROM `ref_data` USE INDEX (`indexed_code`) WHERE `code` = '%s';", trimmedMessage);
			g_database.Query(Callback_CheckCodeExistance, sQuery, pack);
		}
	}
	g_iPlayerWriteStatus[iClient] = 0;
	return Plugin_Handled;
}

static void Callback_CheckCodeExistance(Database database, DBResultSet result, char[] error, any data)
{
	if (database == null || result == null)
	{
		LogError("Query failure | Error: %s", error);
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
		LogError("Query failure | Error: %s", error);
		return;
	}

	int iClient = GetClientFromSerial(data);
	if (IsClientInGame(iClient) && !IsFakeClient(iClient))
	{
		if (result.RowCount > 0)
		{
			while (result.FetchRow())
			{
				char sQuery[256], sInviterSteamID[32], sInviterCode[32];
				result.FetchString(0, g_sPlayerInviter[iClient], sizeof(g_sPlayerInviter[]));
				result.FetchString(1, STRING(sInviterSteamID));
				result.FetchString(2, STRING(sInviterCode));

				g_database.Format(STRING(sQuery), "UPDATE `ref_data` USE INDEX(`indexed_steamid`) SET `invited` = (`invited` + '1') WHERE `steamid` = '%s';", sInviterSteamID);
				g_database.Query(Nothing_Callback, sQuery);

				g_database.Format(STRING(sQuery), "UPDATE `ref_data` USE INDEX(`indexed_steamid`) SET `inviter` = '%s' WHERE `steamid` = '%s';", iClient, sInviterCode, g_sPlayerSteamID[iClient]);
				g_database.Query(Nothing_Callback, sQuery);

				GiveCredits(iClient, g_hConVarCreditsNew.FloatValue);

				for (int iTarget = 1; iTarget <= MaxClients; iTarget++)
				{
					if (IsClientInGame(iTarget) && !IsFakeClient(iTarget))
					{
						if (Karyuu_StrEquals(g_sPlayerSteamID[iTarget], sInviterSteamID))
						{
							g_iPlayerInvited[iTarget]++;
							g_iPlayerValidated[iTarget]++;

							g_database.Format(STRING(sQuery), "UPDATE `ref_data` USE INDEX(`indexed_steamid`) SET `validated` = (`validated` + '1') WHERE `steamid` = '%s';", sInviterSteamID);
							g_database.Query(Nothing_Callback, sQuery);

							float iCredit = g_hConVarCreditsStart.FloatValue + (g_iPlayerInvited[iTarget] * g_hConVarCreditsStep.FloatValue);

							if (Karyuu_ClientHasFlag(iClient, ADMFLAG_CUSTOM3))
							{
								iCredit *= 3.0;
							}
							else if (Karyuu_ClientHasFlag(iClient, ADMFLAG_CUSTOM4))
							{
								iCredit *= 2.0;
							}
							else if (Karyuu_ClientHasFlag(iClient, ADMFLAG_CUSTOM6))
							{
								iCredit = iCredit * 1.5;
							}

							GiveCredits(iClient, iCredit);

							CPrintToChat(iTarget, "{default}「{lightred}%T{default}」{lime}%T", "CHAT_PREFIX", iTarget, "CHAT_REFERED_BY", iTarget, iCredit, iClient);
							break;
						}
					}
				}

				static char sWebHook[512];
				if (sWebHook[0] == '\0')
					g_hConVarWebHook.GetString(STRING(sWebHook));

				if (sWebHook[0] != '\0')
				{
					char	  sBuffer[256];

					Webhook hWebhook = new Webhook();
					hWebhook.SetUsername("KitsuneLab");
					hWebhook.SetAvatarURL("https://kitsune-lab.dev/storage/images/kl-logo.webp");

					Embed hEmbed = new Embed("⌜Player Referral⌟ ", "");
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

					FormatEx(STRING(sBuffer), "▹ [%N](http://www.steamcommunity.com/profiles/%s)", iClient, sInviterSteamID);

					EmbedField hFieldB = new EmbedField("◉ INVITER", sBuffer, true);
					hEmbed.AddField(hFieldB);

					FormatEx(STRING(sBuffer), "▹ %s", sInviterCode);

					EmbedField hFieldC = new EmbedField("◉ CODE", sBuffer, true);
					hEmbed.AddField(hFieldC);

					hWebhook.AddEmbed(hEmbed);

					hWebhook.Execute(sWebHook, OnWebHookExecuted, _);
					delete hWebhook;
				}

				CPrintToChat(iClient, "{default}「{lightred}%T{default}」{lime}%T", "CHAT_PREFIX", iClient, "CHAT_REFERED", iClient, g_sPlayerInviter[iClient], g_hConVarCreditsNew.FloatValue);
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

stock void GiveCredits(int iClient, float iCredit)
{
	// TODO: Alex, ide tedd a credit addolást!
}