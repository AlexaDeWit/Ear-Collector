<img src="docs/logo.png" alt="Ear Collector logo: a severed ear in a gold ring" width="128" align="right">

# Ear Collector

A World of Warcraft addon for **WoW Forever** that collects an ear from every
enemy player you or your group kill in the open world, like the ears PvP kills
dropped in Diablo II.

- Kills by you, your pet, your group and their pets count. So do assists: kills
  someone outside your group finished after you damaged the victim or earned
  honor for them.
- Battlegrounds, arenas and dungeons never count.
- Each ear shows the victim's race and a grade set by the level gap. Ears go in
  an Ear Pouch, with a Ledger of totals and a list of Rivals.
- Everything stays on your screen. Ear Collector never posts to chat or sends
  anything other players can see.

Ear Collector is heavily AI-authored. See [How it's made](#how-its-made).

## Install

1. Download `EarCollector-<version>.zip` from the
   [releases page](https://github.com/AlexaDeWit/Ear-Collector/releases).
2. Unzip it into the `Interface/AddOns/` folder of your WoW Forever
   installation, so that you have `Interface/AddOns/EarCollector/EarCollector.toc`.
3. Start the game, or type `/reload`.

To update, delete the `EarCollector` folder and unzip the new one. Your ears are
saved outside it. Each character keeps its own collection, and the settings are
shared by all your characters.

## Use

Open the pouch with `/ears`, your bags, the minimap addon drawer, a key binding
(Key Bindings > AddOns), or by clicking an ear's name in chat. Escape closes it.
The options are in Options > AddOns > Ear Collector.

| Command | What it does |
|---|---|
| `/ears` | Open or close the pouch |
| `/ears options` | Open the options |
| `/ears stats` | Your totals and latest ear |
| `/ears recent [n]` | Your newest ears (5 unless you give a number) |
| `/ears bags on\|off` | Open the pouch with your bags |
| `/ears popup on\|off` | The pop-up when you collect an ear |
| `/ears popup move` | Drag pop-ups where you want them |
| `/ears sound on\|off` | The pop-up's sound |
| `/ears debug` | Print and save what the addon sees, for testing and bug reports |
| `/ears errors` | Errors the addon caught (it keeps running) |

### Grades

An ear's grade follows the colour the game shows for the victim's level.

| Grade | Their level showed | Which means |
|---|---|---|
| Poor | Grey | Far enough below you to give no honor |
| Common | Green | Below you, but still worth honor |
| Uncommon | Yellow | From 4 levels below you to 2 above |
| Rare | Orange | 3 or 4 levels above you |
| Epic | Red | 5 or more levels above you |
| Legendary | | Owed vengeance: they had killed you 3 times since you last killed them |

Killing the same player again within 10 minutes adds to that ear instead of
dropping a new one. The options set the window.

### Rivals

The Rivals tab lists everyone you've taken an ear from or died to. **Avenge**
means their next ear is Legendary, **Nemesis** means they've killed you more
often than you've killed them, and **Prey** means you've killed them three times
or more and they've never killed you.

### What it can't see

WoW Forever doesn't give addons the combat log, so Ear Collector works from the
game's kill and honor reports and its damage meter.

- An assist counts only when the enemy player dies near you.
- Who killed you comes from the death recap, matched against the enemy players
  you could see or had hit. If none of them matches, the death isn't recorded.

## How it's made

Ear Collector is heavily AI-authored. Claude Code, Anthropic's coding agent,
wrote most of the code, the tests, the documentation, and the scripts that paint
the ears and the logo. The maintainer decides what it does and how it looks,
merges every change, and tests it in the game. Every AI-assisted commit carries
an `Assisted-by:` trailer, and [`CONTRIBUTING.md`](CONTRIBUTING.md) has the
rules AI-assisted contributions follow.

## Reporting a bug

Open an [issue](https://github.com/AlexaDeWit/Ear-Collector/issues) and include
what `/ears errors` lists.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Licence

[MIT](LICENSE)
