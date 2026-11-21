# In-game tests (WoW Forever)

These settle what headless checks and source research can't. Each line is a
chat command, under WoW's 255-character limit. Paste it into chat as is.

Start with Lua errors visible: `/console scriptErrors 1`.

Most tests print values through a helper `S`, which shows `<S>` for a secret
(hidden) value instead of touching it. Define it once per session (T0). `/etrace`
is fine for seeing *when* events fire, but it may print hidden values in clear,
so judge readability from these `/run` lines instead.

Ear Collector's own `/ears debug` covers T1, T2 and T4 for the cases the addon
handles. It prints and saves each kill, honorable kill and death, the decision,
and the active addon restrictions. The `/run` probes below are for when it shows
nothing at all.

## Procedure

1. Install the zip: delete the old `Interface/AddOns/EarCollector` folder first.
2. `/console scriptErrors 1`, then `/reload`.
3. `/ears debug`. It's saved, so it stays on across `/reload` and logout.
   Smoke test: kill any mob. Chat shows `PARTY_KILL ... not a player`, which
   proves the event fires. Only the first few NPC kills (and kills in a
   dungeon) are logged each session, so questing between fights can't push your
   PvP lines out of the log.
4. T9 (saved data survives a reload), because every other result depends on it.
5. Play world PvP as you normally would. Kills give you T1, assists give you T2,
   and dying to an enemy player who's your target or has a nameplate showing
   gives you T4. Note anything that looks wrong as it happens.
6. The window tests (T10 to T14) can be done any time, and T12 and T13 need the
   taint log on.
7. When you're done, `/reload` or log out: the game writes the saved files only
   then. Send the files listed under "Reporting back".
8. `/ears debug` again to turn it off.

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

This is needed for the Rivals "Deaths" column, Nemesis and Vengeance. The quick way: turn on `/ears debug`, have an enemy player kill you in the open world while they're your target or their nameplate is showing, and read the chat line that starts `PLAYER_DEAD`:

- `death recorded (...)`: it works.
- `no death recap`: Forever doesn't fill the recap. Deaths can't be tracked this way.
- `recap names no killer`: the recap is there but the killing blow has no name.
- `killer isn't an enemy player you could see (in view: ...)`: the name didn't match. The line shows the recap's name next to `PLAYER_DEAD` and the names it could have matched. Note the killer's name on screen too (with or without a surname?).

For the details, right after the death run these, then again 2 seconds later:

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

Ears are saved per character, so check that file too:

```
/run EarCollectorCharDB.persistProbe=time()
```

Then `/reload`, then:

```
/dump EarCollectorCharDB.persistProbe
```

Finally, log in on another character: `/dump EarCollectorCharDB.persistProbe`
prints nil (its own data), and `/dump EarCollectorDB.persistProbe` prints the
number (shared).

## T10: the Ear Pouch

1. `/ears` opens the pouch, and the close button and `/ears` close it.
2. The minimap addon drawer lists "Ear Collector" with an ear icon. Hovering
   shows your totals, and clicking toggles the pouch.
3. Key Bindings > AddOns has "Ear Collector: Toggle Ear Pouch". Bind a key and
   try it.
4. Press B: the pouch opens with your bags and closes with them, including when
   you close the last bag with its own X. Open it with `/ears` first and it
   stays open when the bags close. At a merchant, bank or mailbox your bags open
   but the pouch doesn't. `/ears bags off` stops it opening with your bags.
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

## T13: the options page

1. Open Options > AddOns. "Ear Collector" is listed, with three sections: "When
   you collect an ear", "Ear Pouch" and "What counts". Each control shows a
   tooltip on hover.
2. `/ears options` opens the same page, and so does right-clicking Ear Collector
   in the minimap addon drawer. Left-clicking it still opens the pouch.
3. Untick "Show a toast" and collect an ear: no toast, but the ear is collected.
   Tick it again.
4. `/ears bags off`, then reopen the page: "Open with your bags" is unticked.
5. Set "Repeat kill window" to 0, `/reload`, and reopen the page: it still says
   0 min. Kill the same player twice: two ears. Set it back to 10.
6. Click the page's "Defaults" button: everything returns to its default (the
   window to 10 min).
7. Enter combat and run `/ears options`: chat says it can't open during combat,
   with no "action blocked" message. After combat it opens.
8. With `/console taintLog 1` on, change a few options, log out, and search
   `Logs/taint.log` for `EarCollector`: nothing should be blamed on it.

## T14: the Ledger and Rivals tabs

1. Open the pouch: three tabs sit under it (Ears, Ledger, Rivals), in
   Blizzard's tab style. Clicking one plays the tab sound and switches panels.
2. Ledger: four boxes (Ears, Last 7 days, Assists, Ears lost), a bar split by
   grade with a coloured legend, your top classes with bars in class colours,
   and your top zones. Long zone names are cut off, not wrapped.
3. Rivals: one row per player, most kills first, with the date you last killed
   them. Three or more kills shows "Prey". Hover a row for a tooltip; click it
   to jump to their latest ear on the Ears tab.
4. With more than ten rivals, the page buttons page the list, and the mouse
   wheel does too. The Ledger hides the page buttons.
5. Collect an ear with the Ledger open: the numbers update.
6. Note anything that overlaps or runs off the window: the layout was made
   without seeing it.

## T15: deaths, Rivals and Vengeance

Needs T4 to pass.

1. Die to an enemy player in the open world: chat says "<name> killed you."
   They appear on the Rivals tab with 1 under Deaths.
2. Die to the same player three times without killing them: chat says
   "Vengeance owed", and their Rivals row shows "Avenge" in orange.
3. Kill them: the ear is Legendary, the toast says "Vengeance!" and plays the
   legendary sound, and the ear's tooltip says how many deaths it avenged.
   Their row loses the "Avenge" mark.
4. A player who has killed you more often than you've killed them (at least
   twice) shows "Nemesis" in red.
5. The Ledger's "Ears lost" box counts your deaths.
6. Die in a battleground or dungeon: nothing is recorded.

## Reporting back

After a `/reload` or logout, attach these to the chat (or paste them):

1. `WTF/Account/<ACCOUNT>/SavedVariables/EarCollector.lua`: the debug log, the
   error log and your settings. The debug log keeps the newest 300 lines, which
   holds a long session. Send it after each session if you test over several.
2. `WTF/Account/<ACCOUNT>/<Realm>/<Character>/SavedVariables/EarCollector.lua`
   for the character you played: your ears and deaths, with the details of the
   players in the debug log.
3. Your notes, and screenshots of anything on screen that looks wrong.
4. `Logs/taint.log`, only if you ran T12 or T13 and it mentions `EarCollector`.

What each part answers:

- A `PARTY_KILL` line per kill: whether it fires for you, your pet, your group
  and players outside it, and whether the GUIDs are readable or `<secret>` (T1).
- `HONOR` and `UNIT_DIED` lines, each timed to the millisecond (`t`): whether
  assists match within the 2.5-second window (T2).
- `PLAYER_DEAD` lines: whether the death recap names your killer, and how the
  name compares with the names in view (T4).
- The restrictions on each line explain hidden values (T5).

No need to anonymise anything. Player names are changed when the log becomes
test fixtures in `spec/fixtures/`. Output from the `/run` probes goes to chat
only and isn't saved, so screenshot it if you use them.
