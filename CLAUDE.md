# Ear Collector

A World of Warcraft addon for **WoW Forever only** (Interface `16001`, the
Classic-style game on the modern Retail engine). It records the enemy players
you or your group kill in the open world as Diablo-style "ears", plus assists
(someone outside your group lands the blow while you earn honorable-kill credit).
Battlegrounds and other instances never count: kills there would be noise.

The game client can't run here. Correctness comes from the headless checks
below, then a human test in game.

**Start here:** `docs/STATUS.md` has the decisions made with the user, what's
done, what's waiting on the user, and the ordered backlog. Update it at the end
of every piece of work. It's the project's memory across sessions.

## Checks: run before you call anything done

- `scripts/check.sh` runs every check in about 3 seconds. CI runs the same
  command. Steps:
  - `syntax`: `luac5.1 -p`
  - `toc`: TOC fields and file list, and Interface matches the pinned Forever build
  - `luacheck`
  - `names`: event and script-handler names against Blizzard's Forever docs
  - `luals`: lua-language-server with WoW API annotations
  - `xml`: XML against `UI.xsd`
  - `art`: ear textures exist, are valid 32-bit TGAs, and match the painter that made them
  - `format`: StyLua
  - `test`: busted
- `scripts/check.sh --fix` formats first. `scripts/check.sh luals test` runs only the named steps.
- `scripts/build-zip.sh` builds an install zip of the current commit for testing
  in game (what the release packager would publish, version `dev-<commit>`).
- "missing tool" means run `scripts/setup-tools.sh`. In cloud sessions the
  SessionStart hook runs it already. Its first lines pin every tool version and
  the WoW Forever build the checks use.
- Fix the cause of a finding. Don't silence it with `---@diagnostic disable`,
  `-- luacheck: ignore` or new `diagnostics.globals` entries unless the user agrees.

## Errors must never reach the player

An error that escapes an addon goes to the game's error handler. Players see
popups, repeated errors lag the client, and WoW may suggest disabling every
addon. Treat an escaped error as a serious bug.

- Every entry point runs through `Errors.Call` / `Errors.Wrap` (`Core/Errors.lua`):
  - Event handlers registered with `ns.On` are wrapped automatically.
  - Slash commands use `Errors.Wrap`.
  - New entry points must be wrapped too: `C_Timer` callbacks, `OnUpdate` and
    `OnClick` scripts, and hooks.
- Keep error names narrow, because 3 errors switch a name off:
  - Detection never shares a name with UI work. `ns.Collect` and
    `ns.RecordDeath` run the chat line, pouch refresh and toast in their own
    `Errors.Call`, so a UI bug can't switch off kill detection.
  - Each `/ears` subcommand has its own name (`/ears pouch`, `/ears stats`...).
    `/ears errors` and `/ears help` are never switched off.
  - The pouch window is built all or nothing: if `build` fails, the pouch stays
    closed until `/reload` instead of throwing on every refresh.
- A caught error is stored in `EarCollectorDB.errors` (bounded) and announced
  once per session. After 3 errors the handler is switched off until `/reload`.
  `/ears errors` shows the log. With `/ears debug` on, errors also go to the
  game's error handler for BugSack during development.
- The wrapper is a safety net, not error handling. Prevent the error:
  - **Secret values.** Forever hides unit identity in instances, PvP matches and
    some maps. GUIDs, names and other values then become "secret". Comparing,
    concatenating, indexing or calling `tostring` on a secret raises an error,
    and so does using one as a table key. Tables can be secret too
    (`issecrettable`; indexing one without `canaccesstable` is an error).
    Check `Context.Readable(v)`, which covers both, before touching any value
    from the API.
  - **Nil returns.** Assume any API can return nil. Check before indexing or
    doing arithmetic.
  - **Saved data.** It can be old, hand-edited or truncated.
    `Database.MigrateAccount` / `MigrateCharacter` repair it on load. Code that
    reads saved fields must still tolerate missing ones.
  - **Where saved data lives.** `EarCollectorDB` (account-wide): `settings`,
    `ui`, `errors`, `debugLog`. `EarCollectorCharDB` (per character,
    `SavedVariablesPerCharacter`): `ears`, `deaths`, `stats`. `ns.db` is a view
    whose fields are those saved tables (`Database.View`): change them in place
    (`Database.Clear` empties a list); reassigning a field would stop it being
    saved. Data an older version saved account-wide moves to the first character
    that loads (`Database.MoveShared`), and is never dropped.
- Never cause taint, which leads to "action blocked" messages and the
  disable-addons prompt:
  - Don't write to Blizzard globals or frames. The one exception is appending
    the pouch's name to `UISpecialFrames`, a list Blizzard keeps for addons and
    reads inside `securecall` (see "Escape" below).
  - Don't call protected functions.
  - Don't replace Blizzard functions. Use `hooksecurefunc` if a hook is ever needed.
- Never cost frame time:
  - No `OnUpdate` polling or per-frame work.
  - No high-frequency events without a reason.
  - Keep logs in saved data bounded.
- Tests: every new failure path gets a spec. `spec/errors_spec.lua` shows how
  to assert an error is contained. `wow.secret()` makes a value that errors when
  misused, so specs catch unguarded access.

## Ear art

- `art/paint_ears.py` is the source of the art: it paints each race's ear
  procedurally (numpy + Pillow, fixed seed, so rebuilds are byte-identical).
  - Anatomy is control points: outline, helix rim, antihelix, concha, canal,
    tragus, antitragus and lobe. The shapes become a height map.
  - The height map is lit from the top left: normals, diffuse and specular
    light, ambient occlusion, and translucency at thin edges.
  - Then skin mottling and pores, an outline for legibility, and blood along
    the severed edge.
  - Race features are separately lit layers: rings, the gnome's gear, undead
    stitches, the Skyborne feather, the dwarf braid, tauren fur and beads.
  - Each race comes in 4 skin tones (`TONES`; tauren: fur colours; dwarf hair
    varies too), written as `Media/Ears/<race>-<tone>.tga`, plus `generic.tga`.
- `scripts/build-art.sh` writes `Media/Ears/<name>.tga` (128x128, uncompressed
  32-bit) and `Media/Ears/manifest.txt` (size, painter hash, texture list). Run
  it after changing the painter and commit both. The `art` check fails on a
  stale, missing or malformed texture.
- To look at the full-size renders while iterating:
  `python3 art/paint_ears.py /tmp/ears 128 --preview /tmp/ears/png`.
- `UI/Art.lua` maps race tokens to files (`Scourge` -> `undead`). The game
  doesn't expose skin tone, so `Art.Tone(guid)` picks one from a hash of the
  victim's GUID: random across players, stable for each player.
  `Art.TONES` must match the painter (a spec checks). WoW loads addon
  textures by path without the extension:
  `Interface\AddOns\EarCollector\Media\Ears\orc-2`.
- Pouch slots show the ear art. Tooltips and chat lines use Blizzard's race
  icons. The minimap drawer icon is `Media/Ears/human-2`.

## GitHub workflow files: the human moves them

Claude sessions can't push changes under `.github/workflows/`. GitHub refuses
them because Claude's GitHub connection lacks the `workflow` permission, and
the user can't grant it. To add or change a workflow, put the file in
`ci/workflows/`, explain the move in `ci/README.md` and the PR description, and
ask the user to move it in GitHub's web editor. Everything else pushes normally.

## WoW Forever API facts the code relies on

- **No combat log.** The combat log is closed to addons on Forever.
  `CombatLogGetCurrentEventInfo` and `C_CombatLog.GetCurrentEventInfo` are not
  available. Kills come from the `PARTY_KILL(attackerGUID, targetGUID)` event,
  which fires for your and your group's killing blows. There is no damage,
  assist or spell data.
- `GetPlayerInfoByGUID(guid)` returns `localizedClass, englishClass,
  localizedRace, englishRace, sex, name, realmName, level`. `level` is the 8th
  return and may be nil. The pinned annotations list only 7.
- **Surnames.** Forever characters have a first name and a surname instead of
  realms (`RegionalUniqueNamesEnabled()` is true; see Blizzard's
  `Blizzard_FrameXMLUtil/Camelot/NameUtil.lua`). The 7th return then holds the
  surname; it's stored as `surname`. Key players by GUID, never by "Name-Realm".
- **Identity secrecy.** `PARTY_KILL` is `SecretWhenUnitIdentityRestricted`.
  Blizzard documents that rule as secret "when the unit isn't player-controlled
  or in the party/raid", so enemy players should be readable in the open world.
  Community addons report the GUIDs secret inside battlegrounds and instances.
  The debug log records active addon restrictions (`C_RestrictedActions`) to
  explain hidden kills.
- Who counts: the killer may be you, your pet, a group member
  (`C_PartyInfo.IsGUIDInGroup`; the global `IsGUIDInGroup` is only a
  deprecation shim on Forever) or a group member's pet (`partypetN`/`raidpetN`).
  See `ns.ClassifyKiller`.
- **Assists** (`Core/Assists.lua`, `Detectors/HonorKill.lua`). There's no damage
  data, so the evidence is timing:
  - An honorable-kill (HK) step in `GetPVPLifetimeStats()`, signalled by
    `PLAYER_PVP_KILLS_CHANGED`, is matched to an enemy player's `UNIT_DIED` (or
    an outside-group `PARTY_KILL`) within `Assists.WINDOW` seconds.
  - A credit next to a group kill is used up by it.
  - More deaths than credits means nobody is named, and the credit counts in
    `stats.unnamedHonorKills`.
  - Matching runs `WINDOW + 0.5` seconds later via `C_Timer.After`, because the
    events can arrive in any order.
  - Credits and the deaths within `WINDOW` of them form connected groups, each
    resolved as a whole once nothing in it is newer than `WINDOW`. Matching one
    credit at a time lost both assists when two enemies died a second apart.
  - Grey-level kills give no honor, so they never become assists.
- Use `C_PvP.GetZonePVPInfo()`, not the deprecated global `GetZonePVPInfo`.
- Race icons are atlases `raceicon-<race>-<male|female>` (Blizzard's
  `GetRaceAtlas` in `Blizzard_SharedXML`). `Scourge` maps to `undead`. Forever's
  race tokens are Human, Dwarf, Gnome, NightElf, Scourge, Orc, Troll, Tauren and
  Skyborne. Check `C_Texture.GetAtlasInfo` before using an atlas: an icon for
  Skyborne isn't confirmed.
- **Opening the pouch** (`UI/Access.lua`); each way verified in Forever's UI source:
  - Minimap addon drawer: TOC `AddonCompartmentFunc*` name globals that the
    client calls as `(addonName, mouseButton | button)`.
  - Key binding: `Bindings.xml` (loaded by the client, not the TOC) with
    `category="ADDONS"`; the strings `BINDING_HEADER_*` / `BINDING_NAME_*`
    are set in Lua.
  - Bags: `hooksecurefunc` post-hooks on `ToggleAllBags`, `OpenAllBags`,
    `CloseAllBags`, `ToggleBackpack`, `OpenBackpack`, `CloseBackpack`,
    `ToggleBag`, `OpenBag` and `CloseBag` (what a bag's own close button calls),
    then `IsAnyBagOpen()`. The pouch closes with the bags only if the bags opened
    it. Merchants, banks, mailboxes and trade windows call `OpenAllBags(self)`;
    with a frame argument the pouch doesn't open.
  - Chat links: `|Haddon:EarCollector:ear:<guid>:<time>|h`. Blizzard's "addon"
    link handler fires `EventRegistry` "SetItemRef" `(owner, link, text, button, frame)`.
  - The window uses `BasicFrameTemplateWithInset` (`.TitleText`, `.CloseButton`).
  - Tabs use Blizzard's `PanelTabButtonTemplate`, which adds each tab to its
    parent's `Tabs` array, with `PanelTemplates_SetNumTabs` / `PanelTemplates_SetTab`
    (`Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.lua`). A tab registers
    with `Pouch.AddTab{ title, build, refresh, pages?, setPage? }` while the addon
    loads. Each tab's build and refresh run in their own `Errors.Call`, so a
    failing tab is skipped and the rest of the pouch works. The page buttons
    page whichever tab is showing.
- **Escape** (`closeOnEscape` in `UI/Pouch.lua`). On Forever the Escape binding
  runs `ToggleGameMenu` (`Blizzard_GameMenuEsc`). It offers the key to handlers
  registered with `RegisterGameMenuEscHandler`, in `GameMenuEscPriority` order:
  dialogs, menus, casting (`SpellStopCasting`), the game menu and settings,
  Blizzard's own panels, then `CloseAllWindows`, then the world (`ClearTarget`).
  It opens the game menu only if no handler took the key.
  - `CloseAllWindows` closes the bags, then runs `securecall("CloseSpecialWindows")`,
    which hides every shown frame named in `UISpecialFrames`
    (`Blizzard_UIParentPanelManager/Shared/UIParentPanelManager.lua`). The pouch
    appends its name there once, when it's built. The `securecall` keeps the
    tainted entry from tainting the rest of Escape.
  - Never call `RegisterGameMenuEscHandler`. Only Blizzard's code does.
    Calling it from an addon would insert into and re-sort Blizzard's handler
    list while tainted, so every Escape would run tainted and its protected calls
    (`SpellStopCasting`, `ClearTarget`) would be blocked.
  - Don't use `OnKeyDown` with `SetPropagateKeyboardInput`. That method is
    restricted in combat (`HasRestrictions`), so the pouch would either swallow
    every key or let Escape through to the game menu.
  - The pouch also closes when Blizzard closes all windows for other reasons:
    losing control of your character (not on a flight path), and the interface
    being shown again after Alt+Z.
- **Loot toast** (`UI/Toast.lua`): our own frames on `UIParent`, not Blizzard's
  alert system, which would risk taint. Fading uses animation groups, not
  `OnUpdate`. Sounds are `SOUNDKIT` names from Forever's `SoundKitConstants`
  (`UI_RAID_LOOT_TOAST_LESSER_ITEM_WON`, `UI_EPICLOOT_TOAST`,
  `UI_LEGENDARY_LOOT_TOAST`), played with `PlaySound(id, "SFX")`. Only new ears
  get a toast; camped repeats don't.
- **Options page** (`UI/Options.lua`): Blizzard's Settings API for addons
  (`Blizzard_Settings_Shared`), registered on `ADDON_LOADED` after the database
  is migrated.
  - Registration goes through Blizzard's secure attribute delegate
    (`Blizzard_SettingsInbound.lua`), which wraps function arguments to keep
    their taint.
  - Checkboxes are `Settings.RegisterAddOnSetting` on `db.settings`; Blizzard
    reads and writes the table itself, inside `securecall`. Never replace
    `db.settings` after load: the settings hold a reference to it.
  - The repeat-kill slider is `Settings.RegisterProxySetting`: minutes on screen,
    seconds saved. Blizzard calls the getter and setter inside `securecall`,
    where an error goes to the game's error handler, so they run in
    `Errors.Call` and fall back to a valid value. A slider label formatter must
    not error either.
  - The rest of the addon reads `db.settings` when it needs a value, so no
    change callback is needed. Keep it that way: don't cache settings.
  - `Settings.OpenToCategory` calls `C_SettingsUtil.OpenSettingsPanel`, which
    has restrictions (`HasRestrictions`): check `InCombatLockdown()` first and
    tell the player instead of calling it in combat.
  - The minimap drawer passes the mouse button name on click
    (`Blizzard_Minimap/Mainline/AddonCompartment.lua`); right-click opens options.
- **Deaths** (`Detectors/Death.lua`, `Core/Deaths.lua`). The death recap is the
  only record of who killed you.
  - `C_DeathRecap.HasRecapEvents()` / `GetRecapEvents()` with no ID read the
    latest recap. Events come newest first, and Blizzard_DeathRecap marks the
    first as the one that caused the death.
  - Event fields Blizzard's UI reads: `sourceName` (no GUID), `spellName`,
    `amount`, `overkill`, `timestamp`, `hideCaster`, `currentHP`. The structure
    is undocumented, and NPCs appear too.
  - Blizzard's recap window loads only on Retail
    (`[AllowLoadGameType mainline]` in its TOC), though `C_DeathRecap` is
    documented for every client. Whether Forever fills it is test T4.
  - Blizzard's PTR feedback code reads `deathEvents[1].sourceGUID`. A readable
    player GUID there identifies the killer outright (not you, not your group).
  - Otherwise, on `PLAYER_DEAD` the addon notes the enemy players in view
    (target, focus, mouseover, `nameplate1..40`; `UnitIsPlayer` and
    `UnitCanAttack`). After `DeathWatch.RECAP_DELAY` it matches the recap's name
    exactly against each player's name, its first word, and name plus surname
    (UnitName's second return) with a space or a hyphen. "Grimbash Stonefist"
    can't match "Grimbash Ironhide". No match, or a form two players share,
    records nothing. `DeathWatch` (the detector) reads the game; `Deaths` stays
    pure.
  - Vengeance: `Deaths.VENGEANCE` (3) deaths to one player since you last killed
    them make their next ear Legendary (quality 5, `ear.vengeance`), even inside
    the repeat-kill window. `ns.Collect` sets `kill.vengeance` from
    `Deaths.Debt`; taking the ear clears the debt.
  - `/ears debug` logs every death's decision, which turns T4 into fixtures.
- **API references, offline.** warcraft.wiki.gg is blocked from cloud sessions.
  - Blizzard's own docs for the pinned Forever build:
    `.cache/wow-ui-source/Interface/AddOns/Blizzard_APIDocumentationGenerated/`.
    They're authoritative. Look for `SecretArguments`,
    `SecretWhenUnitIdentityRestricted` and `Nilable`.
  - Ketho's LuaLS annotations: `.cache/wow-api/Annotations/Core`. They follow
    Retail and lag it. A missing real global is declared in
    `types/wow-forever.lua`, with where it's defined.
- Every new WoW global needs an entry in `read_globals` in `.luacheckrc` and a
  stub in `spec/support/wow.lua`.
- Write `---@type Frame` above `CreateFrame` results. Pass event names as string
  literals (`ns.On("PARTY_KILL", fn)`) so the `names` check sees them.
- WoW's Lua is 5.1 without `io`, `require`, `dofile`, `loadfile`, `package`
  or `debug`. Addon code must not use them. Specs and scripts may.

## Code layout

| File | Role |
|---|---|
| `Core/Init.lua` | namespace, version, quality colors |
| `Core/Errors.lua` | error containment (see above) |
| `Core/Events.lua` | `ns.On(event, fn)` dispatcher |
| `Core/Database.lua` | SavedVariables: account and per-character repair, the `ns.db` view |
| `Core/Context.lua` | open-world decision; secret-safe reads |
| `Core/Ears.lua` | pure grading and recording logic |
| `Core/Assists.lua` | pure assist matching (honor credit to deaths) |
| `Core/Ledger.lua` | pure totals for the Ledger tab |
| `Core/Rivals.lua` | pure per-player rows for the Rivals tab |
| `Core/Deaths.lua` | pure death recording, recap reading, killer matching, vengeance debt |
| `Detectors/Shared.lua` | victim details, debug trace, `ns.Collect` |
| `Detectors/PartyKill.lua` | kills by you, your pet, your group |
| `Detectors/HonorKill.lua` | assists: `UNIT_DIED` + honorable-kill steps |
| `Detectors/Death.lua` | your deaths: the death recap matched to an enemy in view |
| `UI/Chat.lua` | chat output, ear links, race icons |
| `UI/Art.lua` | race to ear-texture mapping |
| `UI/Pouch.lua` | the Ear Pouch window (built on first open), its tabs and the Ears grid |
| `UI/LedgerTab.lua` | the Ledger tab: totals, grades, classes, top zones |
| `UI/RivalsTab.lua` | the Rivals tab: players you've taken ears from |
| `UI/Toast.lua` | the loot toast when you collect an ear |
| `UI/Options.lua` | the options page in Blizzard's Settings screen |
| `UI/Access.lua` | ways to open it: drawer, key binding, bags, chat links |
| `UI/Slash.lua` | `/ears` commands |
| `Bindings.xml` | the "Toggle Ear Pouch" key binding |
| `art/paint_ears.py` -> `Media/Ears/*.tga` | the ear painter and the textures it makes |

Keep game-touching code thin and decisions in plain functions that specs call directly.

## Tests (busted) and simulating the game

`spec/support/wow.lua` is a fake Forever client:

- `wow.reset{...}` installs API stubs with the given state.
- `wow.loadAddon("EarCollector.toc", { EarCollectorDB = saved, EarCollectorCharDB = char })` loads files in
  TOC order with `(addonName, ns)`, then fires `ADDON_LOADED`.
- `wow.fireEvent(...)` dispatches an event. `wow.slash("/ears recent")` runs a command.
- `wow.advance(seconds)` moves both clocks and runs due `C_Timer` callbacks.
  `wow.honorableKill(n)` bumps the HK count and fires `PLAYER_PVP_KILLS_CHANGED`.
- `wow.secret()` makes a secret value.
- Widgets: `CreateFrame` returns a small widget model. Methods whose state specs
  inspect are real (`Show`/`Hide`/`IsShown`, `SetText`, `SetAtlas`, points,
  scripts...), and other capitalized methods are no-ops; lua-language-server
  catches misspelled ones. `widget:Click()`, `:Enter()`, `:Leave()`, `:Drag()`
  and `:Wheel(delta)` act like the player. `GameTooltip.lines` records tooltip
  text. `wow.clickLink(link)` clicks a chat link, and
  `wow.pressBinding("EARCOLLECTOR_TOGGLE")` runs a `Bindings.xml` body.
  `CreateAnimationGroup()` returns a group with `Play`/`Stop`/`IsPlaying`, and
  `wow.finishAnimations()` completes playing groups and fires `OnFinished`.
  `PlaySound` calls are recorded in `wow.state().sounds`.
- `CreateFrame(..., "PanelTabButtonTemplate")` adds the tab to its parent's
  `Tabs` (read it with `rawget` in the fake: unknown capitalised fields are
  no-op methods there). `PanelTemplates_SetTab` errors if a tab is missing.
- Units: `wow.state().units[token] = guid` makes a unit exist (target, focus,
  mouseover, `nameplateN`). Players are `Player-` GUIDs; you can attack anyone
  not you or in `state.group`. `wow.state().recap` is the death recap's events,
  newest first; fire `PLAYER_DEAD`, then `wow.advance(ns.Deaths.RECAP_DELAY)`.
- `wow.pressEscape()` follows Forever's Escape chain: it closes the game menu if
  it's open, otherwise closes the bags and hides shown `UISpecialFrames`, and
  opens the game menu (`state.gameMenuShown`) only if nothing closed.
- `wow.secretTable()` is a table the addon may not index (`issecrettable` true,
  `canaccesstable` false). `#t` is 0 in Lua 5.1, so stubs that report a count
  check for it explicitly.
- `widget:Enter()` marks a widget hovered; hiding a hovered widget fires
  `OnLeave` (assumed client behaviour; code must be safe either way).
- `wow.state().inCombat = true` puts the client in combat. Frame methods Forever
  restricts in combat (`SetPropagateKeyboardInput` and the like) then raise, and
  so does `Settings.OpenToCategory`.
- The Settings screen follows `Blizzard_Settings_Shared`: `wow.settingsCategory(name)`
  returns a registered category with its `layout.initializers` (section headers
  and controls, in order) and `settings`. Call `setting:SetValue(v)` as the
  control would. Proxy getters and setters run in a `securecall` stand-in:
  an error there lands in `wow.state().gameErrors`, which specs expect to stay
  empty.
- `wow.replay(dofile("spec/fixtures/x.lua"))` plays an event sequence. In a
  fixture, `"<secret>"` becomes a secret value, which matches how `/ears debug`
  logs one.

Stub return values must match Blizzard's docs, in order. Prefer fixtures
captured from real play (`/ears debug`, then copy `debugLog` from
`WTF/Account/<ACCOUNT>/SavedVariables/EarCollector.lua`, anonymising names) over
long hand-written sequences.

The debug log (`ns.Trace`, `Detectors/Shared.lua`) is built for that:
- Each entry has `at` (server time) and `t` (`GetTime()` to the millisecond,
  for the gaps between events), the event, attacker and target (`<secret>` when
  hidden), the decision and the active restrictions.
- It keeps the newest `Database.DEBUG_LOG_SIZE` (300) entries. Decisions about
  things that never count (NPC kills, kills in dungeons, honor in battlegrounds)
  go through `ns.TraceRoutine`: `ns.ROUTINE_TRACES` (3) of each kind per
  session, so they can't push PvP lines out.
- Honor steps are logged as they arrive, and a death whose recap name matches
  nobody lists the names in view (`DeathWatch.NamesInView`).
- Victim details aren't in the log: take them from the character file's `ears`
  and `deaths`, by GUID.

## What the checks can't tell you

- whether and when `PARTY_KILL` fires in the live client, and whether its GUIDs
  are readable in the open world
- pet killing blows: is the attacker your GUID or your pet's?
- taint, combat lockdown, and SavedVariables surviving `/reload` and relog

Report work as "verified headlessly: ...; needs in-game check: ...", and put the
in-game steps in the PR description.

## In-game checklist (for the human)

`docs/in-game-tests.md` has copy-paste `/run` probes for each open question:
whether `PARTY_KILL` fires and for whom, honorable kills, the death recap,
restrictions, surnames, the group check, and whether SavedVariables persist.
The basic checklist:

1. Copy or symlink the checkout to `Interface/AddOns/EarCollector/` inside the
   WoW Forever client's folder (`World of Warcraft/_<flavor>_/`). The folder name must match the `.toc`. On the AddOns screen it
   must be listed and not marked out of date. `/dump select(4, GetBuildInfo())`
   should print `16001`.
2. Turn on `/console scriptErrors 1`, or use BugSack, then `/reload`. No errors
   at login, and `/ears stats` prints a summary.
3. Run `/ears debug`, then kill an enemy player in the open world. The chat
   shows the decision "new ear (you)" and a "You collected ..." line with the
   victim's race icon.
   `/dump EarCollectorCharDB.ears[#EarCollectorCharDB.ears]` shows the right name,
   class, level and zone.
4. A groupmate's killing blow in the open world says "new ear (group)". A
   battleground kill says "instance:pvp". For a pet's killing blow (yours or a
   groupmate's), note whether the attacker GUID is the pet or its owner. For a
   kill where someone outside your group lands the blow, note whether
   PARTY_KILL fires at all.
5. Ears survive `/reload` and relog. Another character has its own (empty)
   pouch but the same settings. `/ears errors` says "No errors recorded".
6. No "action blocked" or taint messages, in combat or out. Open and close
   your bags in combat too.
7. The pouch: `/ears` opens it. It also opens from the minimap addon drawer
   (with an ear icon), from Key Bindings > AddOns > Ear Collector, from your bags
   (B), and by clicking an ear name in chat. It keeps its position after a drag
   and `/reload`. Escape closes it without opening the game menu, in combat
   too, and the taint log stays clean (T12 in `docs/in-game-tests.md`).
   `/ears options` and right-clicking in the minimap drawer open Options >
   AddOns > Ear Collector (T13). The Ledger and Rivals tabs fill in (T14).
8. Optional: copy `EarCollectorDB.debugLog` for a new spec fixture.
