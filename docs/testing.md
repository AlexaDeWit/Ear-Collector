# Testing

The game client can't run in CI, so correctness comes in two layers: headless
checks on every change, then a person playing the game
([`in-game-tests.md`](in-game-tests.md)). A PR says which parts were verified
headlessly and which need the game.

## Headless checks

`scripts/check.sh` runs every step in a few seconds, and CI runs the same
command. `scripts/check.sh --fix` formats first, and `scripts/check.sh luals test`
runs only the named steps. A "missing tool" message means you need
`scripts/setup-tools.sh`, which pins every tool version and the Forever build
the checks read.

| Step | What it checks |
|---|---|
| `syntax` | Every Lua file parses (`luac5.1 -p`) |
| `toc` | TOC fields and file list, and that `Interface` matches the pinned Forever build |
| `luacheck` | Lint, with every WoW global declared in `.luacheckrc` |
| `names` | Event and script-handler names exist in Blizzard's Forever docs |
| `luals` | Types, with lua-language-server and WoW API annotations |
| `xml` | `Bindings.xml` against Blizzard's `UI.xsd` |
| `art` | Ear textures exist, are valid 32-bit TGAs, and match the painter ([art.md](art.md)) |
| `format` | StyLua |
| `test` | The busted specs |

Fix the cause of a finding. A suppression (`---@diagnostic disable`,
`-- luacheck: ignore`, a new `diagnostics.globals` entry) needs the maintainer's
agreement.

## Specs

Specs live in `spec/`, one file per area (`spec/pouch_spec.lua` tests
`UI/Pouch.lua`). Every failure path gets a spec. `spec/errors_spec.lua` shows how
to assert an error stays contained.

## The fake client

`spec/support/wow.lua` stands in for the Forever client. Its stubs return values
in the order Blizzard's docs give.

**Loading and events**

- `wow.reset{...}` installs the stubs with the given state.
- `wow.loadAddon("EarCollector.toc", { EarCollectorDB = ..., EarCollectorCharDB = ... })`
  loads the files in TOC order with `(addonName, ns)`, then fires `ADDON_LOADED`.
- `wow.fireEvent(event, ...)` dispatches an event, and `wow.slash("/ears recent")`
  runs a command.
- `wow.advance(seconds)` moves both clocks and runs due `C_Timer` callbacks.
- `wow.honorableKill(n)` raises the honorable-kill count and fires
  `PLAYER_PVP_KILLS_CHANGED`.

**Secrets**

- `wow.secret()` is a value that raises an error when misused, so a spec catches
  any unguarded access.
- `wow.secretTable()` is a table the addon may not index. Lua 5.1 reports `#t`
  as 0 for it, so stubs that count check for it explicitly.

**Widgets**

- `CreateFrame` returns a small widget model. The methods specs inspect are real
  (`Show`, `Hide`, `IsShown`, `SetText`, `SetAtlas`, points, scripts), and other
  capitalised methods do nothing. lua-language-server catches misspelled ones.
- `widget:Click()`, `:Enter()`, `:Leave()`, `:Drag()` and `:Wheel(delta)` act like
  the player. Hiding a hovered widget fires `OnLeave`. That's assumed client
  behaviour, so the code is safe either way.
- `GameTooltip.lines` records tooltip text, and `wow.state().sounds` records
  `PlaySound` calls.
- `CreateAnimationGroup()` returns a group with `Play`, `Stop` and `IsPlaying`.
  `wow.finishAnimations()` completes playing groups and fires `OnFinished`.
- `CreateFrame(..., "PanelTabButtonTemplate")` adds the tab to its parent's
  `Tabs`. Read it with `rawget`, because unknown capitalised fields are no-op
  methods in the fake.

**The player and the world**

- `wow.state().units[token] = guid` makes a unit exist (`target`, `focus`,
  `mouseover`, `nameplateN`). You can attack any player who isn't you or in
  `wow.state().group`.
- `wow.state().recap` is the death recap, newest first. Fire `PLAYER_DEAD`, then
  `wow.advance(ns.DeathWatch.RECAP_DELAY)`.
- `wow.state().inCombat = true` puts the client in combat. Functions with
  restrictions then raise, and so does `Settings.OpenToCategory`.
- `wow.clickLink(link)` clicks a chat link, `wow.pressBinding("EARCOLLECTOR_TOGGLE")`
  runs a key binding, and `wow.pressEscape()` follows Forever's Escape chain.
- `wow.settingsCategory(name)` returns a registered options page with its
  `layout.initializers` and `settings`. Call `setting:SetValue(v)` as a control
  would. Proxy getters and setters run in a `securecall` stand-in, where an error
  lands in `wow.state().gameErrors`, which specs expect to stay empty.

A new WoW global needs an entry in `read_globals` in `.luacheckrc`, a stub here,
and, if the annotations lack it, a declaration in `types/wow-forever.lua`.

## Fixtures from the game

`wow.replay(dofile("spec/fixtures/<name>.lua"))` plays an event sequence. In a
fixture, `"<secret>"` becomes a secret value, the way `/ears debug` logs one.

Recorded fixtures beat hand-written ones. To make one from a play session:

1. Take `debugLog` from `WTF/Account/<ACCOUNT>/SavedVariables/EarCollector.lua`.
2. Take the victims' details from the character's own `EarCollector.lua`
   (`ears` and `deaths`, by GUID) for the fixture's `setup.players`.
3. Turn the differences in `t` into `wow.advance` steps.
4. Replace player names before committing.

## What headless checks can't tell you

- Whether `PARTY_KILL` fires in the live client, and with readable GUIDs.
- Whether a pet's killing blow names the pet or its owner.
- Taint, combat restrictions, layout, textures and sounds.

[`in-game-tests.md`](in-game-tests.md) covers these.
