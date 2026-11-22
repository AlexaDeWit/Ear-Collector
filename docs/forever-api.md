# The WoW Forever API

The game behaviour Ear Collector depends on. Read it before you touch detection or
any call into the game. Each fact names the Blizzard file it comes from, in the
`forever` branch of [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source/tree/forever)
(the build `scripts/setup-tools.sh` pins). Facts that only play in the game can
confirm are marked, and `docs/in-game-tests.md` tests them.

## Finding things offline

- **Blizzard's generated API docs** are the authority:
  `.cache/wow-ui-source/Interface/AddOns/Blizzard_APIDocumentationGenerated/`. Look
  for `SecretArguments`, `SecretWhenUnitIdentityRestricted` and `Nilable`.
- **Ketho's LuaLS annotations** are in `.cache/wow-api/Annotations/Core`. They
  follow Retail and lag it, so `types/wow-forever.lua` declares the real globals
  they miss, each with the Blizzard file that defines it.
- **Blizzard's UI code.** `.cache/wow-ui-source` is a sparse, blob-less clone, so
  `git grep` in it fetches one file at a time and stalls. Make a worktree
  elsewhere, set a sparse pattern, and check out in one batch (about 35 MB):

  ```bash
  git -C .cache/wow-ui-source worktree add --no-checkout /tmp/ui HEAD
  git -C /tmp/ui sparse-checkout set --no-cone '/Interface/**/*.lua'
  git -C /tmp/ui checkout
  ```

- warcraft.wiki.gg blocks cloud sessions.

## The Lua environment

- Lua 5.1, without `io`, `require`, `dofile`, `loadfile`, `package` or `debug`.
- **Secret values.** Forever hides unit identity in instances, PvP matches and
  some maps. GUIDs, names and other values then arrive "secret". Comparing,
  concatenating, indexing or calling `tostring` on a secret raises an error, and
  so does using one as a table key. `issecretvalue(v)` tests for one.
- **Secret tables.** `issecrettable(t)` is true for a table the addon may not
  index unless `canaccesstable(t)` says so.
- **Restrictions.** `C_RestrictedActions.GetAddOnRestrictionState(type)` reports
  which addon restrictions are on (`Enum.AddOnRestrictionType`: `Combat`, `Map`,
  `PvPMatch` and others). Functions marked `HasRestrictions` fail while one is on.

## Kills

- **No combat log.** `CombatLogGetCurrentEventInfo` and
  `C_CombatLog.GetCurrentEventInfo` don't exist for addons, so there is no
  damage, assist or spell data.
- **`PARTY_KILL(attackerGUID, targetGUID)`** fires for a killing blow by you, your
  pet or your group. Both arguments are `SecretWhenUnitIdentityRestricted`,
  which Blizzard documents as secret "when the unit isn't player-controlled or
  in the party/raid". Community addons report them secret inside battlegrounds
  and instances. In the open world it fires for your own kills with both GUIDs
  readable, even while the `Combat` restriction is on (seen in game with an NPC
  kill). *Needs the game:* the same for an enemy player, and whether a pet's kill
  names the pet or its owner.
- **`UNIT_DIED(guid)`** fires for units that die near you. Most are creatures,
  whose GUIDs are secret.
- **Group membership:** `C_PartyInfo.IsGUIDInGroup(guid)`. The global
  `IsGUIDInGroup` is a deprecation shim. Group pets have no GUID lookup, so
  their tokens (`partypetN`, `raidpetN`) are compared one by one.
- **`GetPlayerInfoByGUID(guid)`** returns `localizedClass, englishClass,
  localizedRace, englishRace, sex, name, realmName, level`. `level`, the 8th
  return, can be nil, and the pinned annotations list only 7.
- **Surnames.** Forever characters have a first name and a surname instead of a
  realm (`RegionalUniqueNamesEnabled()` is true;
  `Blizzard_FrameXMLUtil/Camelot/NameUtil.lua`). `GetPlayerInfoByGUID` returns
  both as the name, `"Brennus Themenace"`, with the realm empty (seen in game).
  *Needs the game:* whether `UnitName` and the death recap's `sourceName` give
  the full name too. Players are keyed by GUID, never by "Name-Realm".
- **Level colours.** The game colours a level by its gap to yours
  (`GetRelativeDifficultyColor`, `Blizzard_FrameXMLUtil/Mainline/DifficultyUtil.lua`,
  which Forever loads): red at 5 or more above, orange at 3 or 4, yellow from
  4 below to 2 above, then green as far below as
  `UnitQuestTrivialLevelRange("player")` reaches, and grey beyond. A grey
  victim gives no honor.
- **Where you are:** `IsInInstance()` returns `inInstance, instanceType`
  (`"none"`, `"pvp"`, `"arena"`, `"party"`, `"raid"`, `"scenario"`).
  `C_PvP.GetZonePVPInfo()` returns `"combat"` for a zone-wide battle and
  `"arena"` for a free-for-all area. The global `GetZonePVPInfo` is deprecated.

## Honorable kills

- `GetPVPLifetimeStats()` returns the lifetime honorable-kill count, and
  `PLAYER_PVP_KILLS_CHANGED(unit)` fires when it changes. Neither is secret.
- A victim too far below your level (grey) gives no honor.
- *Needs the game:* how long after the death the honorable kill arrives.

## Deaths

- `C_DeathRecap.HasRecapEvents()` and `C_DeathRecap.GetRecapEvents()` with no ID
  read the latest recap. Events come newest first, and `Blizzard_DeathRecap` treats
  the first as the killing blow. No event announces a new recap, so read it
  after `PLAYER_DEAD`.
- The event structure is undocumented. Blizzard's recap UI reads `sourceName`,
  `spellName`, `amount`, `overkill`, `timestamp`, `hideCaster` and `currentHP`,
  and `Blizzard_PTRFeedback` reads `sourceGUID`. NPCs appear too.
- Blizzard's recap window loads only on Retail (`[AllowLoadGameType mainline]`),
  although `C_DeathRecap` is documented for every client. *Needs the game:*
  whether Forever fills the recap.
- Units you can see: `target`, `focus`, `mouseover` and the nameplates on
  screen, with `UnitExists`, `UnitIsPlayer`, `UnitCanAttack`, `UnitGUID` and
  `UnitName`. `C_NamePlate.GetNamePlates()` returns the nameplate frames, and
  each has Blizzard's `NamePlateBaseMixin:GetUnit()`, which returns its unit
  token (`Blizzard_NamePlates/Blizzard_NamePlateBase.lua`). The tokens are
  `nameplateN`, and N can pass 40.

## The damage meter

Forever has Blizzard's built-in damage meter (`DamageMeterDocumentation.lua`,
`Blizzard_DamageMeter`). The client keeps its own totals for each fight, and
addons such as Details read them instead of a combat log.

- `C_DamageMeter.GetAvailableCombatSessions()` lists the fights the meter keeps,
  each with a `sessionID`. It isn't secret.
- `C_DamageMeter.GetCombatSessionFromType(sessionType, type)` and
  `GetCombatSessionFromID(sessionID, type)` return a fight's totals.
  `Enum.DamageMeterSessionType.Current` is the fight in progress or just ended.
  Both are `SecretWhenInCombat`, so read them once combat ends.
- With `Enum.DamageMeterType.EnemyDamageTaken` (10), `combatSources` lists the
  enemies that took damage, each with `sourceGUID` and `name` (both
  `ConditionalSecret`), `totalAmount`, `sourceDisplayType` and `factionGroup`.
- `deathRecapID` and `deathTimeSeconds` are filled in for deaths on the `Deaths`
  view only, so they don't say whether an enemy died.
- `C_DamageMeter.IsDamageMeterAvailable()` returns whether the player can use
  the meter. Blizzard's meter window shows only while the `damageMeterEnabled`
  setting is on.
- `PLAYER_REGEN_DISABLED` and `PLAYER_REGEN_ENABLED` fire as you enter and leave
  combat. `UnitAffectingCombat("player")` reports it too.

- Grading reads a fight's `DamageTaken`, `DamageDone`, `HealingDone`,
  `Absorbs`, `Interrupts`, `Dispels`, `Deaths` and `EnemyDamageTaken` views.
  Each source's `isLocalPlayer` is `NeverSecret` and marks your own row; its
  `totalAmount` is your amount (a count for interrupts, dispels and deaths).
- `UnitHealth` and `UnitHealthPercent` return secrets to addons, so your health
  during a fight can't be read. `UnitHealthMax` can for you; for an enemy it
  takes a `UnitTokenPvPRestrictedForAddOns` unit, and a value of 100 or less is
  taken as a percentage and ignored.

*Needs the game:*
- whether enemy players appear in open-world PvP with readable GUIDs and names
- whether the meter counts only your group's damage, which Ear Collector assumes
- whether it tracks fights while its window is turned off
- whether the other views fill in for open-world PvP, and what `Deaths` counts
- whether `UnitHealthMax` gives an enemy player's real health in the open world

## Races and icons

- Race tokens: `Human`, `Dwarf`, `Gnome`, `NightElf`, `Scourge`, `Orc`, `Troll`,
  `Tauren`, `Skyborne`.
- Race icons are the atlases `raceicon-<race>-<male|female>` (`GetRaceAtlas` in
  `Blizzard_SharedXML`), with `Scourge` as `undead`. An icon for Skyborne isn't
  confirmed, so check `C_Texture.GetAtlasInfo` before using one.
- Addon textures load by path without the extension:
  `Interface\AddOns\EarCollector\Media\Ears\orc-2`.

## Interface hooks

- **Minimap addon drawer.** The TOC fields `AddonCompartmentFunc`,
  `AddonCompartmentFuncOnEnter` and `AddonCompartmentFuncOnLeave` name globals
  the client calls as `(addonName, mouseButton)`
  (`Blizzard_Minimap/Mainline/AddonCompartment.lua`).
- **Key bindings.** The client loads `Bindings.xml` itself (not through the TOC).
  `category="ADDONS"` files a binding under Key Bindings > AddOns, and the
  strings `BINDING_HEADER_*` and `BINDING_NAME_*` are globals set in Lua.
- **Bags.** `ToggleAllBags`, `OpenAllBags`, `CloseAllBags`, `ToggleBackpack`,
  `OpenBackpack`, `CloseBackpack`, `ToggleBag`, `OpenBag` and `CloseBag` open and
  close bags, and `IsAnyBagOpen()` reports the result. A bag's own close button
  calls `CloseBag`. Merchants, banks, mailboxes and trade windows call
  `OpenAllBags(frame)`. Losing control of your character (except on a flight
  path) runs `CloseAllWindows_WithExceptions`, and Blizzard also closes all
  windows when the interface comes back after Alt+Z.
- **Chat links.** `|Haddon:<addon>:<data>|h<text>|h` is an addon link. Clicking
  one fires the `EventRegistry` callback `"SetItemRef"` with
  `(owner, link, text, button, frame)`. Hovering any link fires
  `"ChatFrame.OnHyperlinkEnter"` with `(owner, chatFrame, link, text, ...)`, and
  leaving it `"ChatFrame.OnHyperlinkLeave"` with `(owner, chatFrame)`
  (`ChatFrameMixin`, `Blizzard_ChatFrameBase/Shared/ChatFrame.lua`).
- **Escape.** The Escape binding runs `ToggleGameMenu` (`Blizzard_GameMenuEsc`),
  which offers the key to handlers in `GameMenuEscPriority` order: dialogs,
  menus, casting (`SpellStopCasting`), the game menu and settings, Blizzard's
  panels, `CloseAllWindows`, then the world (`ClearTarget`). It opens the game
  menu only when no handler takes the key. `CloseAllWindows` closes the bags,
  then calls `securecall("CloseSpecialWindows")`, which hides every shown frame
  named in the global list `UISpecialFrames`
  (`Blizzard_UIParentPanelManager/Shared/UIParentPanelManager.lua`).
  `RegisterGameMenuEscHandler` is Blizzard's own registration: an addon that
  calls it re-sorts the handler list while tainted, so every Escape runs tainted
  and `SpellStopCasting` and `ClearTarget` get blocked.
- **Keyboard input.** `SetPropagateKeyboardInput` has restrictions in combat.
- **Window templates.** `BasicFrameTemplateWithInset` provides `.TitleText` and
  `.CloseButton`. `PanelTabButtonTemplate` adds each tab to its parent's `Tabs`
  array, and `PanelTemplates_SetNumTabs` and `PanelTemplates_SetTab` drive them
  (`Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.lua`).
- **Bag art.** The bags' new-item glow is the atlas `bags-glow-white`, and an
  item button's frame is `Interface\Common\WhiteIconFrame`
  (`Blizzard_ItemButton`).
- **Sounds.** `PlaySound(SOUNDKIT.<NAME>, "SFX")`, with names from Forever's
  `SoundKitConstants`, such as `UI_RAID_LOOT_TOAST_LESSER_ITEM_WON`,
  `UI_EPICLOOT_TOAST`, `UI_LEGENDARY_LOOT_TOAST`, `IG_CHARACTER_INFO_TAB`,
  `IG_BACKPACK_OPEN`, `IG_BACKPACK_CLOSE` and `IG_ABILITY_PAGE_TURN`. The code
  plays a sound only if its name is in `SOUNDKIT`. *Needs the game:* whether
  Forever has `IG_MAINMENU_OPTION_CHECKBOX_ON` and `_OFF`, the grade buttons'
  clicks.

## The Settings screen

`Blizzard_Settings_Shared` is the addon options API.

- `Settings.RegisterVerticalLayoutCategory(name)` makes a page, and
  `Settings.RegisterAddOnCategory(category)` lists it under Options > AddOns.
- `Settings.RegisterAddOnSetting(category, variable, key, table, type, name, default)`
  binds a control to `table[key]`. Blizzard reads and writes the table inside
  `securecall`, and keeps a reference to it.
- `Settings.RegisterProxySetting(..., getValue, setValue)` calls the getter and
  setter inside `securecall`, so an error in either goes to the game's error
  handler.
- Registration passes through Blizzard's secure attribute delegate
  (`Blizzard_SettingsInbound.lua`), which wraps function arguments to keep their
  taint.
- `Settings.CreateDropdown(category, setting, options, tooltip)` takes a function
  returning `Settings.CreateControlTextContainer()`'s data, and
  `CreateSettingsButtonInitializer(name, buttonText, onClick, tooltip, addSearchTags)`
  makes a row with a button, added with `layout:AddInitializer`.
- `Settings.OpenToCategory(id)` calls `C_SettingsUtil.OpenSettingsPanel`, which
  has restrictions. `InCombatLockdown()` and the `Combat` addon restriction tell
  you when it would fail.

## Saved data

- `## SavedVariables` globals are saved for the account, and
  `## SavedVariablesPerCharacter` globals for each character. The game writes
  them at logout and `/reload`, and loads them before `ADDON_LOADED`.
  Confirmed in game on Forever.

## Who else uses these signals

These open-source Forever addons rely on the same events, and several
measured them in game:

| Addon | What it shows |
|---|---|
| [Killed by Savages](https://github.com/Mouchoir/Killed-by-Savages) | `PARTY_KILL` detection, measured with a probe addon (`probe/KBSProbe`) |
| [HardcoreAchievements](https://github.com/IAmChills/HardcoreAchievements) | What `PARTY_KILL` and `UNIT_DIED` do on Forever (`Forever/KillTracking.lua`) |
| [HeadHunter](https://github.com/GudaAddons/HeadHunter) | Death recap and honor probes on the Forever beta |
| [HonorLog](https://github.com/adbergen/honor-log) | Honorable-kill steps, honor messages and the death recap |
| [dG KillShot](https://github.com/linman0x90/dgks) | Group `PARTY_KILL`s and killers from the death recap |
| [Overlord](https://github.com/leliondoc/overlord-forever-addon) | GUID-based kill tracking in world PvP |
