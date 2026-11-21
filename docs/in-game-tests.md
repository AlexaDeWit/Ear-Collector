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

## T2: honorable kills (how assists are detected)

```
/run local f=CreateFrame("Frame")f:RegisterEvent("PLAYER_PVP_KILLS_CHANGED")f:RegisterEvent("CHAT_MSG_COMBAT_HONOR_GAIN")f:SetScript("OnEvent",function(_,e,m)print(format("%.1f",GetTime()),e,S(GetPVPSessionStats()),S(GetPVPLifetimeStats()),S(m))end)
```

Repeat T1 cases 1, 3 and 6, and kill a grey-level enemy. Case 6 should give an
ear marked "Assist" (check with `/ears debug` on). For each, note:
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

## T10: the Ear Pouch

1. `/ears` opens the pouch, and the close button and `/ears` close it.
2. The minimap addon drawer lists "Ear Collector" with an ear icon. Hovering
   shows your totals, and clicking toggles the pouch.
3. Key Bindings > AddOns has "Ear Collector: Toggle Ear Pouch". Bind a key and
   try it.
4. Press B: the pouch opens with your bags and closes with them. Open it with
   `/ears` first and it stays open when the bags close. `/ears bags off` stops
   it opening with your bags.
5. Do step 4 in combat. There should be no "action blocked" or "interface action
   failed" message.
6. Click an ear's name in a "You collected ..." chat line. The pouch opens on
   that ear's page, highlights it and shows its tooltip.
7. Drag the pouch, `/reload`, and open it again. It should be where you left it.
8. Ear art: each slot shows the victim's race ear (orc, troll, tauren, undead,
   Skyborne, and so on) in one of four skin tones. The same player always gets
   the same tone. Poor ears are greyed out. Tooltips show Blizzard's
   race icon on the race line. If a slot is a green square, the texture failed
   to load: note which race.

## T11: the loot toast

1. Collect an ear. A toast appears near the top of the screen, with the ear art,
   the name in its grade colour, level, race and class (and the groupmate who
   landed the blow, or "Assist"), plus a loot sound. A Rare or better ear plays
   the epic loot sound.
2. It fades after about 4 seconds. Hovering keeps it up and shows the ear's
   tooltip.
3. Left-click opens the pouch on that ear. Right-click dismisses it.
4. Several ears at once stack up to three.
5. `/ears sound off` mutes it, and `/ears toast off` stops it.

## T12: Escape closes the pouch, without taint

The pouch adds its name to Blizzard's `UISpecialFrames` list, which Escape
reads inside `securecall`. This test checks that nothing else gets tainted.

1. Turn on the taint log, then `/reload`:
   ```
   /console taintLog 1
   ```
2. Open the pouch with `/ears` and press Escape. The pouch closes, and the game
   menu does not open. Press Escape again: now the game menu opens.
3. Open your bags with B (the pouch opens with them) and press Escape. Both
   close, and the game menu does not open.
4. Target something, make sure the pouch is closed, and press Escape: the
   target clears, as it does without the addon. This is the step taint would
   break: Escape still reads the pouch's entry when the pouch is closed.
5. Do steps 2 to 4 in combat (a training dummy will do). Cast a spell with a
   cast time, open the pouch, and press Escape mid-cast: the first press stops
   the cast, the second closes the pouch. There should be no "action blocked"
   or "interface action failed" message.
6. Log out (the taint log is written then) and open `Logs/taint.log` in the
   game folder. Search it for `EarCollector`. Lines that only say the addon
   wrote `UISpecialFrames` are expected. A line that blames `EarCollector` for a
   blocked action (`ADDON_ACTION_BLOCKED`, `ClearTarget`, `SpellStopCasting`,
   `ToggleGameMenu`) is a bug: paste it back.
7. Turn the log off again with `/console taintLog 0`.

## Reporting back

Paste the printed lines, or copy `EarCollectorDB.debugLog` from
`WTF/Account/<ACCOUNT>/SavedVariables/EarCollector.lua`. Anonymise player names
if you like. Those lines become test fixtures in `spec/fixtures/`.
