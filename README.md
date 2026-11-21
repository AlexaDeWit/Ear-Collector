# Ear Collector

A World of Warcraft addon for **WoW Forever** that collects an ear from every
enemy player you or your group kill in the open world, like the ears that PvP
kills dropped in Diablo II. Assists count too: when someone outside your group
lands the killing blow and you earn honorable-kill credit, you still get the ear.

Kills in battlegrounds, arenas and other instances don't count, so your
collection stays a record of real world PvP.

## Status

In development, and not yet tested in game. It records open-world kills of
enemy players by you, your pet or your group, plus assists. Each ear has painted
art for the victim's race and a grade by level gap. You get a chat line and a
loot toast when you collect one, and your ears go in an Ear Pouch window, with
a Ledger of totals and a list of Rivals. When an enemy player kills you three
times, their next ear is a Legendary Vengeance ear. Its options are in
Options > AddOns > Ear Collector.

## Installing

1. Download `EarCollector-<version>.zip` from this repository's Releases page.
   (CurseForge and Wago listings are planned.)
2. Unzip it into `World of Warcraft/_<flavor>_/Interface/AddOns/`, so that you
   have `Interface/AddOns/EarCollector/EarCollector.toc`.
3. Start the game, or `/reload` if it's running. On the AddOns screen, Ear
   Collector should be listed and enabled.

To update, delete the old `EarCollector` folder and unzip the new one. Your
data is saved outside the addon folder, so it survives updates. Each character
has its own collection (`WTF/Account/<account>/<realm>/<character>/SavedVariables/EarCollector.lua`);
settings are shared by all your characters (`WTF/Account/<account>/SavedVariables/EarCollector.lua`).

## Grades

| Grade | When |
|---|---|
| Poor (grey) | The victim was 10 or more levels below you. No honor, no assists. |
| Common (white) | 5 to 9 levels below you |
| Uncommon (green) | A fair fight |
| Rare (blue) | 3 or more levels above you |
| Legendary (orange) | Vengeance: they had killed you 3 or more times since you last killed them |

Killing the same player again within 10 minutes adds to that ear's count
instead of dropping a new one (the window is in the options).

## Rivals

The Rivals tab lists everyone you've taken an ear from or died to. Marks:
**Avenge** (vengeance owed: their next ear is Legendary), **Nemesis** (they've
killed you more often than you've killed them) and **Prey** (you've killed them
three or more times, and they've never killed you).

## Commands

| Command | What it does |
|---|---|
| `/ears` | Open or close your Ear Pouch |
| `/ears options` | Open the options (also in Options > AddOns, or right-click Ear Collector in the minimap addon drawer) |
| `/ears stats` | Totals and your latest ear |
| `/ears recent [n]` | Your newest ears (default 5) |
| `/ears bags on\|off` | Open the pouch with your bags (on by default) |
| `/ears toast on\|off` | The pop-up when you collect an ear |
| `/ears sound on\|off` | The pop-up's loot sound |
| `/ears debug` | Print every killing blow the addon sees, and why it did or didn't count |
| `/ears errors` | Errors the addon caught. It keeps running; include these in bug reports |

The pouch also opens from the minimap addon drawer, a key binding (Key
Bindings > AddOns > Ear Collector), your bags, and by clicking an ear's name in
chat. Escape closes it.

Found a bug? `/ears errors` lists what the addon caught; please include it in
the report.

## Installing a development copy

Copy or symlink this folder into the WoW Forever client's `Interface/AddOns/`
folder, inside the game's install directory (`World of Warcraft/_<flavor>_/`). The
folder must be named `EarCollector`.

## Development

Requires Ubuntu (or another Debian-based Linux) for the setup script.

```bash
scripts/setup-tools.sh   # install the pinned toolchain
scripts/check.sh         # run every check: lint, types, art, format, tests
scripts/build-art.sh     # repaint Media/Ears/*.tga after editing art/paint_ears.py
```

See [CLAUDE.md](CLAUDE.md) for how the checks work, the error-handling rules,
and the in-game test checklist.

Releases: push a tag like `v0.1.0`. CI runs the checks, then publishes the zip
as a GitHub Release.

## License

[MIT](LICENSE)
