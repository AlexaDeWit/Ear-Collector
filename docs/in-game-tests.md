# In-game tests (WoW Forever)

These settle what headless checks and source research can't. Each line is a
chat command, under WoW's 255-character limit. Paste it into chat as is.

Start with Lua errors visible: `/console scriptErrors 1`.

Most tests print values through a helper `S`, which shows `<S>` for a secret
(hidden) value instead of touching it. Define it once per session (T0). `/etrace`
is fine for seeing *when* events fire, but it may print hidden values in clear,
so judge readability from these `/run` lines instead.

Ear Collector's own `/ears debug` covers T1 for the cases the addon handles. It
prints each `PARTY_KILL`, the decision, and the active addon restrictions.

## T0: helper (once per session)

```
/run S=function(v)if v==nil then return"nil"end return issecretvalue(v)and"<S>"or tostring(v)end
```

## T1: does PARTY_KILL fire, and for whom? Are the GUIDs readable?

This is the main viability question.

```
/run local f=CreateFrame("Frame")f:RegisterEvent("PARTY_KILL")f:RegisterEvent("UNIT_DIED")f:SetScript("OnEvent",function(_,e,a,b)print(format("%.1f",GetTime()),e,S(a),S(b),"pet:",S(UnitGUID("pet")))end)
```

Then, on the PvP ruleset in a contested zone, note what prints for each case:

1. You land a solo killing blow on an enemy player.
2. Your pet finishes one.
3. A party member finishes one near you.
4. A raid member in another subgroup finishes one.
5. One dies 100+ yards away.
6. An ally outside your group finishes an enemy you were fighting.
7. A hunter feigns death.

## T2: honorable kills (for a possible "assist" tier)

```
/run local f=CreateFrame("Frame")f:RegisterEvent("PLAYER_PVP_KILLS_CHANGED")f:RegisterEvent("CHAT_MSG_COMBAT_HONOR_GAIN")f:SetScript("OnEvent",function(_,e,m)print(format("%.1f",GetTime()),e,S(GetPVPSessionStats()),S(GetPVPLifetimeStats()),S(m))end)
```

Repeat T1 cases 1, 3 and 6, and kill a grey-level enemy. For each, note:
- whether an honorable kill (HK) arrives
- whether the honor message names the victim
- the time gap to PARTY_KILL and UNIT_DIED

## T3: event order, by eye

Type `/etrace` and filter for `PARTY_KILL`, then `UNIT_DIED`, `PLAYER_PVP_KILLS_CHANGED` and `CHAT_MSG_COMBAT_HONOR_GAIN`. Mark moments with `/etrace mark solo kill`.

## T4: does the death recap name who killed you?

This is needed for Rivals and Vengeance. Right after an enemy player (or their pet) kills you, run these, then again 2 seconds later:

```
/run print(S(C_DeathRecap.HasRecapEvents()))
```

```
/run local t=C_DeathRecap.GetRecapEvents()if issecrettable(t)then return print("<S>")end for i=1,3 do local e=t[i]if e and not issecrettable(e)then print(i,S(e.event),S(e.sourceName),S(e.sourceGUID),S(e.overkill),S(e.hideCaster))end end
```

## T5: restrictions and zone type

Run this in a capital, a contested zone during combat, a free-for-all area if Forever has one, and a dungeon:

```
/run for k,v in pairs(Enum.AddOnRestrictionType)do print(k,C_RestrictedActions.GetAddOnRestrictionState(v))end print(IsInInstance())print(C_PvP.GetZonePVPInfo())print(S(C_PvP.IsWarModeFeatureEnabled()),S(C_PvP.IsWarModeDesired()))
```

## T6: victim identity in combat, and surname vs realm

Target an enemy player, then:

```
/run local g=UnitGUID("target")print(S(g),S(C_Secrets.ShouldUnitIdentityBeSecret("target")))if not issecretvalue(g)then print(GetPlayerInfoByGUID(g))print(UnitName("target"))print(RegionalUniqueNamesEnabled())end
```

The 7th value from `GetPlayerInfoByGUID` should be the surname. The addon stores it as one.

## T7: group check for players and pets

In a party with a hunter or warlock:

```
/run for i=1,4 do local g=UnitGUID("party"..i)local p=UnitGUID("partypet"..i)if g then print(i,S(C_PartyInfo.IsGUIDInGroup(g)),S(p and UnitTokenFromGUID(p)),S(p and C_PartyInfo.IsGUIDInGroup(p)))end end
```

## T8: does the damage meter list enemy players after a fight?

Out of combat after a fight, run these three in order:

```
/run local a=C_DamageMeter.GetAvailableCombatSessions()ID=a[#a]and a[#a].sessionID print("session",ID)
```

```
/run for _,c in ipairs(C_DamageMeter.GetCombatSessionFromID(ID,Enum.DamageMeterType.EnemyDamageTaken).combatSources)do print(S(c.name),S(c.sourceGUID),S(c.factionGroup))end
```

```
/run for _,c in ipairs(C_DamageMeter.GetCombatSessionFromID(ID,Enum.DamageMeterType.Deaths).combatSources)do print(S(c.name),S(c.isLocalPlayer),S(c.deathRecapID))end
```

## T9: does saved data survive a reload?

One addon author claims Forever doesn't load saved data back. Others rely on it working.

```
/run EarCollectorDB.persistProbe=time()
```

Then `/reload`, then:

```
/dump EarCollectorDB.persistProbe
```

It should print the same number. Repeat across a full logout.

## Reporting back

Paste the printed lines, or copy `EarCollectorDB.debugLog` from
`WTF/Account/<ACCOUNT>/SavedVariables/EarCollector.lua`. Anonymise player names
if you like. Those lines become test fixtures in `spec/fixtures/`.
