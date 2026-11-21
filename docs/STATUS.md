# Ear Collector: status and handoff

Read this first in a new session, together with `CLAUDE.md` (how to work) and
`git log`. Update it at the end of every piece of work: what changed, what's
next, and what's waiting on the user. It's the memory that survives a session
ending or a conversation being compacted.

Last updated: 2026-11-21.

## Decisions made with the user

| Topic | Decision |
|---|---|
| Game version | **WoW Forever only** (Interface `16001`), the version the user plays. No Classic or Retail TOCs. |
| What counts | Open-world kills only. Battlegrounds and other instances never count. |
| Who counts | You, your pet, anyone in your group, or a group member's pet landing the killing blow. **Assists count too**: someone outside your group lands the blow while you earn honorable-kill credit. |
| Repeat kills | Killing the same player again within 10 minutes adds to the existing ear's count. Each repeat restarts the window. |
| Grades | By level gap: Poor (grey, no honor), Common (5+ below), Uncommon (fair fight), Rare (3+ above). Outnumbered grading was dropped: Forever has no damage data. Legendary/Vengeance waits on deaths (below). |
| Skin tones | Each race's ear comes in 4 tones, picked from a hash of the victim's GUID: random, but stable per player. Accepted: real skin tone isn't available and can change anyway. |
| Ear art | Painted procedurally by `art/paint_ears.py`. The user approved the painted look, after rejecting flat vector art as "looks like nothing". |
| Icons elsewhere | Pouch slots use our ear art. Tooltips and chat use Blizzard's race icons. The minimap drawer uses `Media/Ears/human-2`. |
| Opening the pouch | `/ears`, the minimap addon drawer, a key binding, your bags (on by default; `/ears bags off`), and clicking an ear link in chat. |
| Escape | Closes the pouch without opening the game menu, via `UISpecialFrames`: the one sanctioned write to a Blizzard global, because Blizzard reads it inside `securecall`. `RegisterGameMenuEscHandler` and keyboard propagation were rejected (reasons in `CLAUDE.md`). |
| Loot toast | A pop-up for each new ear (not camped repeats), with a loot sound by grade. Up to 3 stack. Click to open the pouch on it. `/ears toast` and `/ears sound` toggle it. |
| Pouch tabs | Ears, Ledger, Rivals, with Blizzard's tab style. Ledger: Ears, Last 7 days (rolling), Players, Assists; grades; classes; top 5 zones. Rivals: per player by GUID, most kills first (repeat kills count), 10 a page, "Prey" at 3+ kills; click opens their latest ear. The pouch keeps the last tab for the session. |
| Options page | Options > AddOns > Ear Collector, built with Blizzard's Settings API for addons. Also `/ears options` (or `config`, `settings`) and right-click in the minimap drawer. Debug stays slash-only. The repeat-kill window shows minutes (0 to 60) and saves seconds. In combat it says it can't open instead of calling a restricted function. |
| Deaths and Vengeance | Deaths come from the death recap, matched by name to an enemy player in view at the moment of death (target, focus, mouseover, nameplates) to get a GUID. No match, no record. 3 deaths to a player since you last killed them make their next ear Legendary ("Vengeance"), even inside the repeat-kill window; that clears the debt. Rivals marks: Avenge (vengeance owed) > Nemesis (killed you 2+ times, more than you've killed them) > Prey (3+ kills, never killed you). The Ledger's fourth box is "Ears lost"; the player count moved to the Rivals header. |
| Error handling | Errors must never reach the player. See `CLAUDE.md`. |
| License | MIT. |
| Workflow | One branch per piece of work from `main`, a PR, and the user merges. Never push to `main` directly. |
| CI workflow files | Claude can't push `.github/workflows/` (no `workflow` permission; it can't be granted). Stage them in `ci/workflows/` for the user to move. |

## Done

- **PR #1** (merged): scaffold, kill detection (`PARTY_KILL`), group kills, assists (honorable-kill matching), surnames, error containment, the check toolchain, `CLAUDE.md`, and the in-game test sheet.
- **PR #2** (merged): the Ear Pouch window and the five ways to open it.
- **PR #3** (merged): painted ear art for 9 races × 4 tones plus a generic ear, the `art` check, and this status file.
- **PR #4** (merged): the loot toast.
- **PR #5** (merged): Escape closes the pouch.
- **PR #6** (merged): the options page; checks now skip Claude Code worktrees under `.claude/worktrees/`; README status refreshed.
- **PR #7** (open, `ledger`): the pouch's tabs, with the Ledger and the Rivals list.
- **PR #8** (open, `deaths`, builds on #7): deaths from the death recap, the Rivals "Deaths" column, Nemesis, and Legendary Vengeance ears.

## Waiting on the user

1. **Turn CI on**: move `ci/workflows/ci.yml` and `release.yml` to `.github/workflows/` on `main` in GitHub's web editor (steps in `ci/README.md`), then delete `ci/`.
2. **Merge PR #7, then PR #8** (#8 builds on #7).
3. **In-game tests** (`docs/in-game-tests.md`). Nothing has been run in the game yet. The ones that decide the most:
   - T1: does `PARTY_KILL` fire with readable IDs for your and your group's open-world kills?
   - T2: do honorable kills arrive within about 2 s of the death, so assists match?
   - T9: does saved data survive `/reload`? One addon author claims Forever doesn't reload it.
   - T10: the pouch, including opening your bags in combat without "action blocked", and the ear art loading.
   - T11: the loot toast and its sounds.
   - T12: Escape closes the pouch, in combat too, with a clean taint log.
   - T13: the options page, including the Defaults button and combat.
   - T14: the Ledger and Rivals tabs, including whether the layout fits.
   - T15: deaths, Nemesis and Vengeance (needs T4).
   - T4: does the death recap name who killed you? It gates deaths, Nemesis and Vengeance. `/ears debug` now answers it from a single death.
   - T6: is the 7th `GetPlayerInfoByGUID` value the surname?

## Next up (in order)

1. **Adversarial review** of everything before v1.0. The first run was stopped before it reported; run it again (read-only, in a worktree) once deaths are in.
2. **README install section**, then the first release once CI is on: `v1.0.0` tag, CurseForge and Wago project IDs in the TOC, their API tokens as repository secrets (the user's steps).
3. Later: export ears as text, inspect another Ear Collector user's pouch, CurseForge and Wago publishing.

Reading Forever's UI source: `.cache/wow-ui-source` is a sparse, blob-less checkout, so `git grep` there fetches one file at a time and stalls. Instead, add a worktree in the scratchpad (`git -C .cache/wow-ui-source worktree add --no-checkout <dir> HEAD`), set a sparse pattern such as `'/Interface/**/*.lua'`, and `git checkout`: it fetches in one batch (about 35 MB, a minute).

## Open questions only the game can answer

These are listed in `docs/in-game-tests.md`. The design leans on:
- `PARTY_KILL` GUIDs being readable for enemy players in the open world (Blizzard's docs say so).
- Pet killing blows reporting the pet's GUID.
- Honorable-kill credit arriving within `Assists.WINDOW` (2.5 s) of `UNIT_DIED`.
- Addon TGA textures loading on Forever.

## Where things are

- Design concept and interactive mockup (claude.ai artifact, private to the user): https://claude.ai/artifact/84T2Qhaen3EuZxcMjwkixv. To change it, read it with the Artifact tool's `read` action and publish to the same URL.
- Kill-detection research with sources: `docs/research/forever-viability.md`.
- How to run checks, the error rules, API facts and code layout: `CLAUDE.md`.
- In-game test probes: `docs/in-game-tests.md`.
