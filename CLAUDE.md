# Ear Collector

A World of Warcraft addon for **WoW Forever only** (Interface `16001`, the
Classic-style game on the modern Retail engine). It records the enemy players
you kill in the open world as Diablo-style "ears". Battlegrounds, arenas and
other instances never count.

The game client can't run here. Correctness comes from the headless checks
below, then a human test in game.

## Checks: run before you call anything done

- `scripts/check.sh` runs every check in about 3 seconds. CI runs the same
  command. Steps:
  - `syntax`: `luac5.1 -p`
  - `toc`: TOC fields and file list, and Interface matches the pinned Forever build
  - `luacheck`
  - `names`: event and script-handler names against Blizzard's Forever docs
  - `luals`: lua-language-server with WoW API annotations
  - `xml`: XML against `UI.xsd`
  - `format`: StyLua
  - `test`: busted
- `scripts/check.sh --fix` formats first. `scripts/check.sh luals test` runs only the named steps.
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
- A caught error is stored in `EarCollectorDB.errors` (bounded) and announced
  once per session. After 3 errors the handler is switched off until `/reload`.
  `/ears errors` shows the log. With `/ears debug` on, errors also go to the
  game's error handler for BugSack during development.
- The wrapper is a safety net, not error handling. Prevent the error:
  - **Secret values.** Forever hides unit identity in instances, PvP matches and
    some maps. GUIDs, names and other values then become "secret". Comparing,
    concatenating, indexing or calling `tostring` on a secret raises an error.
    Check `Context.Readable(v)` before touching any value from the API.
  - **Nil returns.** Assume any API can return nil. Check before indexing or
    doing arithmetic.
  - **Saved data.** It can be old, hand-edited or truncated.
    `Database.Migrate` repairs it on load. Code that reads saved fields must
    still tolerate missing ones.
- Never cause taint, which leads to "action blocked" messages and the
  disable-addons prompt:
  - Don't write to Blizzard globals or frames.
  - Don't call protected functions.
  - Don't replace Blizzard functions. Use `hooksecurefunc` if a hook is ever needed.
- Never cost frame time:
  - No `OnUpdate` polling or per-frame work.
  - No high-frequency events without a reason.
  - Keep logs in saved data bounded.
- Tests: every new failure path gets a spec. `spec/errors_spec.lua` shows how
  to assert an error is contained. `wow.secret()` makes a value that errors when
  misused, so specs catch unguarded access.

## WoW Forever API facts the code relies on

- **No combat log.** The combat log is closed to addons on Forever.
  `CombatLogGetCurrentEventInfo` and `C_CombatLog.GetCurrentEventInfo` are not
  available. Kills come from the `PARTY_KILL(attackerGUID, targetGUID)` event,
  which fires for your and your group's killing blows. There is no damage,
  assist or spell data.
- `GetPlayerInfoByGUID(guid)` returns `localizedClass, englishClass,
  localizedRace, englishRace, sex, name, realmName, level`. `realmName` is ""
  for your own realm. `level` is the 8th return and may be nil. The pinned
  annotations list only 7.
- Use `C_PvP.GetZonePVPInfo()`, not the deprecated global `GetZonePVPInfo`.
- Death recap (`C_DeathRecap.GetRecapEvents`) exposes `sourceName` for what
  killed you. It's the likely source for future Rivals/Vengeance features.
  Its behaviour in PvP is unverified.
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
| `Core/Database.lua` | SavedVariables migrate/repair |
| `Core/Context.lua` | open-world decision; secret-safe reads |
| `Core/Ears.lua` | pure grading and recording logic |
| `Detectors/PartyKill.lua` | the kill detector |
| `UI/Chat.lua`, `UI/Slash.lua` | output and `/ears` |

Keep game-touching code thin and decisions in plain functions that specs call directly.

## Tests (busted) and simulating the game

`spec/support/wow.lua` is a fake Forever client:

- `wow.reset{...}` installs API stubs with the given state.
- `wow.loadAddon("EarCollector.toc", { EarCollectorDB = saved })` loads files in
  TOC order with `(addonName, ns)`, then fires `ADDON_LOADED`.
- `wow.fireEvent(...)` dispatches an event. `wow.slash("/ears recent")` runs a command.
- `wow.secret()` makes a secret value.
- `wow.replay(dofile("spec/fixtures/x.lua"))` plays an event sequence. In a
  fixture, `"<secret>"` becomes a secret value, which matches how `/ears debug`
  logs one.

Stub return values must match Blizzard's docs, in order. Prefer fixtures
captured from real play (`/ears debug`, then copy `debugLog` from
`WTF/Account/<ACCOUNT>/SavedVariables/EarCollector.lua`, anonymising names) over
long hand-written sequences.

## What the checks can't tell you

- whether and when `PARTY_KILL` fires in the live client, and whether its GUIDs
  are readable in the open world
- pet killing blows: is the attacker your GUID or your pet's?
- taint, combat lockdown, and SavedVariables surviving `/reload` and relog

Report work as "verified headlessly: ...; needs in-game check: ...", and put the
in-game steps in the PR description.

## In-game checklist (for the human)

1. Copy or symlink the checkout to `Interface/AddOns/EarCollector/` inside the
   WoW Forever client's folder (`World of Warcraft/_<flavor>_/`). The folder name must match the `.toc`. On the AddOns screen it
   must be listed and not marked out of date. `/dump select(4, GetBuildInfo())`
   should print `16001`.
2. Turn on `/console scriptErrors 1`, or use BugSack, then `/reload`. No errors
   at login, and `/ears` prints a summary.
3. Run `/ears debug`, then kill an enemy player in the open world. The chat
   shows the decision "new ear" and a "You collected ..." line.
   `/dump EarCollectorDB.ears[#EarCollectorDB.ears]` shows the right name,
   class, level and zone.
4. A groupmate's killing blow says "not your killing blow". A battleground kill
   says "instance:pvp". A pet's killing blow: note what happens.
5. Ears survive `/reload` and relog. `/ears errors` says "No errors recorded".
6. No "action blocked" or taint messages, in combat or out.
7. Optional: copy `EarCollectorDB.debugLog` for a new spec fixture.
