# Ear Collector

A World of Warcraft addon for **WoW Forever** that collects an ear from every
enemy player you kill in the open world, like the ears that PvP kills dropped in
Diablo II.

Kills in battlegrounds, arenas and other instances don't count, so your
collection stays a record of real world PvP.

## Status

Early development. The first version records your open-world killing blows on
enemy players and reports them in chat. It has not yet been tested in game.

## Commands

| Command | What it does |
|---|---|
| `/ears` | Totals and your latest ear |
| `/ears recent [n]` | Your newest ears (default 5) |
| `/ears debug` | Print every killing blow the addon sees, and why it did or didn't count |
| `/ears errors` | Errors the addon caught. It keeps running; include these in bug reports |

## Installing a development copy

Copy or symlink this folder into the WoW Forever client's `Interface/AddOns/`
folder, inside the game's install directory (`World of Warcraft/_<flavor>_/`). The
folder must be named `EarCollector`.

## Development

Requires Ubuntu (or another Debian-based Linux) for the setup script.

```bash
scripts/setup-tools.sh   # install the pinned toolchain
scripts/check.sh         # run every check: lint, types, format, tests
```

See [CLAUDE.md](CLAUDE.md) for how the checks work, the error-handling rules,
and the in-game test checklist.

Releases: push a tag like `v0.1.0`. CI runs the checks, then publishes the zip
as a GitHub Release.

## License

[MIT](LICENSE)
