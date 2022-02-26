#include dhooks
#include sdkhooks
#include vip_core

public Plugin myinfo =
{
	name = "[VIP] Healthshot Pro",
	author = "xstage",
	version = "1.1.1",
	url = "https://hlmod.ru/members/xstage.99505/"
};

enum
{
	USE_ALL = 0,
	BLOCK_USE,
	ALLOW_USE_VIP,
}

enum struct Healthshot
{
	int iHealth;
	int iCount;
}

static const char g_sFeature[] = "Healthshot_Pro";

int				g_iType, g_iMaxHealth;
float			g_fHealthshotEffect;
Healthshot		esHealthshot[MAXPLAYERS+1];

public void OnPluginStart()
{
	if(GetEngineVersion() != Engine_CSGO)
	{
		SetFailState("Плагин работает только в CS:GO");
		return;
	}

	ConVar hCvar;
	
	(hCvar = CreateConVar("sm_healthshot_maxhp", "100", "Предел восстановления здоровья", _, true, 100.0)).AddChangeHook(ChangeConVar_CallBack);
	g_iMaxHealth = hCvar.IntValue;
	
	(hCvar = CreateConVar("sm_healthshot_blockuse", "1", "0 - Могут подбирать все / 1 - Запретить подбирать шприц другим игрокам / 2 - Запретить подбирать другим игрокам, кроме VIP-игроков", _, true, 0.0, true, 2.0)).AddChangeHook(ChangeConVar_CallBack);
	g_iType = hCvar.IntValue;
	
	(hCvar = CreateConVar("sm_healthshot_effect", "1.3", "Длительность эффекта <Healthshot> / 0 - выключить", _, true, 0.0)).AddChangeHook(ChangeConVar_CallBack);
	g_fHealthshotEffect = hCvar.FloatValue;
	
	AutoExecConfig(true, "VIP_HealthshotPro", "vip");
	
	Handle hGameData = LoadGameConfigFile("vip_healthshot.games");
	
	if (!hGameData)
	{
		SetFailState("Не найден файл - vip_healthshot.games.txt");
		return;
	}
	
	Handle hHealthshotUse = DHookCreateDetour(Address_Null, CallConv_THISCALL, ReturnType_Void, ThisPointer_Ignore);
	DHookSetFromConf(hHealthshotUse, hGameData, SDKConf_Signature, "CItem_Healthshot::CompleteUse");
	DHookAddParam(hHealthshotUse, HookParamType_CBaseEntity, _, DHookPass_ByRef);
	DHookEnableDetour(hHealthshotUse, false, HealthshotCompleteUse);
	
	delete hGameData;
	
	for(int i = 1; i <= MaxClients; i++) if(IsClientInGame(i)) OnClientPutInServer(i);
	
	if(VIP_IsVIPLoaded())
		VIP_OnVIPLoaded();
}

public void ChangeConVar_CallBack(ConVar convar, const char[] oldValue, const char[] newValue)
{
	char sNameCvar[64];
	convar.GetName(sNameCvar, sizeof(sNameCvar));
	
	if(sNameCvar[14] == 'm')
	{
		g_iMaxHealth = convar.IntValue;
	}
	else if(sNameCvar[14] == 'b')
	{
		g_iType = convar.IntValue;
	}
	else if(sNameCvar[14] == 'e')
	{
		g_fHealthshotEffect = convar.FloatValue;
	}
}

public void OnMapStart()
{
	PrecacheSound("items/healthshot_success_01.wav");
}

public void OnClientPutInServer(int iClient)
{
	SDKHook(iClient, SDKHook_WeaponCanUse, OnWeaponCanUse);
}

public void VIP_OnVIPLoaded()
{
	VIP_RegisterFeature(g_sFeature, STRING);
	
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && VIP_IsClientVIP(i))
			VIP_OnVIPClientLoaded(i);
	}
}

public void VIP_OnVIPClientLoaded(int iClient)
{
	char sBuffer[2][8], sValue[32];
	
	VIP_GetClientFeatureString(iClient, g_sFeature, sValue, sizeof(sValue));
	ExplodeString(sValue, ";", sBuffer, sizeof(sBuffer), sizeof(sBuffer[]));
	
	esHealthshot[iClient].iCount = StringToInt(sBuffer[0]);
	esHealthshot[iClient].iHealth = StringToInt(sBuffer[1]);
}

public void VIP_OnPlayerSpawn(int iClient, int iTeam, bool bVIP)
{	
	if(VIP_IsClientFeatureUse(iClient, g_sFeature))
	{
		int iAmmo = GetEntProp(iClient, Prop_Data, "m_iAmmo", _, 21);
	
		for(int i = 0; i < esHealthshot[iClient].iCount - iAmmo; i++)
		{
			GivePlayerItem(iClient, "weapon_healthshot");
		}
	}
}

public Action OnWeaponCanUse(int iClient, int iEntity)
{
	if(!IsValidEntity(iEntity))
		return Plugin_Continue;
		
	char sWeaponName[64];
	GetEntityClassname(iEntity, sWeaponName, sizeof(sWeaponName));
	
	if(!strcmp(sWeaponName, "weapon_healthshot"))
	{
		switch(g_iType)
		{
			case USE_ALL:
			{
				return Plugin_Continue;
			}
			
			case BLOCK_USE:
			{
				if(VIP_GetClientFeatureStatus(iClient, g_sFeature) == NO_ACCESS)
					return Plugin_Handled;
			}
			
			case ALLOW_USE_VIP:
			{
				if(!VIP_IsClientVIP(iClient))
					return Plugin_Handled;
			}
		}
	}
	
	return Plugin_Continue;
}

public MRESReturn HealthshotCompleteUse(Handle hParams)
{
	float fPos[3];
	int iClient = DHookGetParam(hParams, 1);
	
	if(IsClientInGame(iClient) && VIP_GetClientFeatureStatus(iClient, g_sFeature) != NO_ACCESS)
	{
		int iHealth = GetClientHealth(iClient);
		int iGetHealth = esHealthshot[iClient].iHealth;
		
		if((iHealth + iGetHealth) < g_iMaxHealth)
			SetEntityHealth(iClient, GetClientHealth(iClient) + iGetHealth);
		else
			SetEntityHealth(iClient, g_iMaxHealth);
		
		GetClientAbsOrigin(iClient, fPos);
		EmitAmbientSound("items/healthshot_success_01.wav", fPos);
		
		if(g_fHealthshotEffect != 0.0)
			SetEntPropFloat(iClient, Prop_Send, "m_flHealthShotBoostExpirationTime", GetGameTime() + g_fHealthshotEffect);

		return MRES_Supercede;
	}
	
	return MRES_Ignored;
}

public void OnPluginEnd() 
{
	if(CanTestFeatures() && GetFeatureStatus(FeatureType_Native, "VIP_UnregisterFeature") == FeatureStatus_Available)
	{
		VIP_UnregisterFeature(g_sFeature);
	}
}