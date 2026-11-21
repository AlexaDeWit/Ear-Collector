# Ear Collector: status and handoff

Read this first in a new session, together with `CLAUDE.md` (how to work) and
`git log`. Update it at the end of every piece of work: what changed, what's
next, and what's waiting on the user. It's the memory that survives a session
ending or a conversation being compacted.

Last updated: 2026-11-21 (after merging PRs #10 and #11; debug log made ready for in-game tests in PR #12).

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
| Per-character data | Each character has its own collection: ears, deaths and kill stats are in `EarCollectorCharDB` (`SavedVariablesPerCharacter`). Settings, the pouch's position and the error and debug logs are account-wide in `EarCollectorDB`. Chosen by the user over a shared collection tagged by character. |
| Nothing public | The user plays on an RP-PvP realm. Everything the addon shows is local: chat lines print only to the player's own chat window, toasts and sounds play only on their client. It never sends chat, emotes, whispers or addon messages that other players could see, so it can't break anyone's immersion. Sharing ears with other players was never built. |
| Error handling | Errors must never reach the player. See `CLAUDE.md`. |
| License | MIT. |
| Workflow | One branch per piece of work from `main`, a PR, and the user merges. Never push to `main` directly. |
| Branch and tag rules | GitHub rulesets copied from the user's Saerskriven repo. `main`: PRs only, no force-push or deletion, signed commits, 1 approving review, and both CI jobs passing on an up-to-date branch. The user merges by admin bypass. Tags: only admins create them, and they must be signed. No one can move or delete a tag, so a bad release gets a new version. |
| CI workflow files | Cloud sessions can't push `.github/workflows/`: they lack the `workflow` permission, and it can't be granted. A cloud session stages the file in `ci/workflows/` for the user to move. A local session pushes over SSH and can change it directly. |

## Done

- **PR #1** (merged): scaffold, kill detection (`PARTY_KILL`), group kills, assists (honorable-kill matching), surnames, error containment, the check toolchain, `CLAUDE.md`, and the in-game test sheet.
- **PR #2** (merged): the Ear Pouch window and the five ways to open it.
- **PR #3** (merged): painted ear art for 9 races × 4 tones plus a generic ear, the `art` check, and this status file.
- **PR #4** (merged): the loot toast.
- **PR #5** (merged): Escape closes the pouch.
- **PR #6** (merged): the options page; checks now skip Claude Code worktrees under `.claude/worktrees/`; README status refreshed.
- **PR #7** (merged): the pouch's tabs, with the Ledger and the Rivals list.
- **PR #8** (merged): deaths from the death recap, the Rivals "Deaths" column, Nemesis, and Legendary Vengeance ears.
- **PR #9** (merged): per-character data, fixes from an adversarial review of everything, README install section.
- **PR #10** (merged): `scripts/build-zip.sh` for test builds, and this file brought up to date.
- **PR #11** (merged): CI turned on. The workflows moved from `ci/workflows/` to `.github/workflows/`.
- **PR #12** (open, `debug-log`): the debug log made ready for in-game tests (millisecond times, honor steps, names in view at a death, NPC and dungeon lines capped, 300 entries); a dungeon's hidden mob kills no longer count as hidden kills; the chat option renamed "Note it in your chat"; the test procedure in `docs/in-game-tests.md`.

Every planned v1.0 feature is built and on `main`. What's left is in-game verification and the release. The user tests with a zip of PR #12's branch; `scripts/build-zip.sh` makes another.

## Waiting on the user

1. **Decide the Poor grade**: Poor is "10+ levels below you", but the game's grey (no-honor) range at 60 is about 13 below, so levels 48 to 50 grade Poor yet give honor. Follow the game's grey formula instead? Asked, not yet answered.
2. **In-game tests** (`docs/in-game-tests.md`). Nothing has been run in the game yet. The ones that decide the most:
   - T1: does `PARTY_KILL` fire with readable IDs for your and your group's open-world kills?
   - T2: do honorable kills arrive within about 2 s of the death, so assists match?
   - T9: does saved data survive `/reload`, for both the account file and the per-character file? One addon author claims Forever doesn't reload it.
   - T10: the pouch, including opening your bags in combat without "action blocked", and the ear art loading.
   - T11: the loot toast and its sounds.
   - T12: Escape closes the pouch, in combat too, with a clean taint log.
   - T13: the options page, including the Defaults button and combat.
   - T14: the Ledger and Rivals tabs, including whether the layout fits.
   - T15: deaths, Nemesis and Vengeance (needs T4).
   - T4: does the death recap name who killed you? It gates deaths, Nemesis and Vengeance. `/ears debug` now answers it from a single death.
   - T6: is the 7th `GetPlayerInfoByGUID` value the surname?

3. **Release**, once the in-game tests pass: push a signed tag (`git tag -s v1.0.0`, or `v1.0.0-beta1` for a test build) and the release workflow publishes the zip as a GitHub Release. CurseForge and Wago are optional: each needs a project the user creates, its ID in the TOC (`## X-Curse-Project-ID`, `## X-Wago-ID`), and an API token as a repository secret (`CF_API_TOKEN`, `WAGO_API_TOKEN`).

The user's procedure is the "Procedure" and "Reporting back" sections of `docs/in-game-tests.md`: `/ears debug` on, play, `/reload`, then send the account file (debug log) and the character file (victim details).

When in-game results come back: turn `/ears debug` logs into fixtures (`spec/fixtures/`, replayed with `wow.replay`; `t` gives the gaps for `wow.advance`, the character file's ears give `setup.players`), anonymise names, fix what fails, and keep the in-game sheet in step.

## Next up (in order)

1. **Deferred from the review** (each small; none blocks v1.0):
   - The Poor grade's level gap (waiting on the user's decision, above).
   - A group kill that gave no honor (a grey victim) still uses up a nearby credit, which can cost an ally's kill its assist.
   - Nameplates are scanned as `nameplate1..40`; `C_NamePlate.GetNamePlates()` exists, but the frame's unit-token field isn't documented.
   - Opening with bags does nothing with bag-replacement addons (`IsAnyBagOpen` stays false).
   - The fake's `UnitCanAttack` is true for same-faction players.
2. Later: export ears as text; inspect another Ear Collector user's pouch (addon messages, which Forever may restrict: the `Chat` addon restriction and `SecretInChatMessagingLockdown`).

Making a test build: `scripts/build-zip.sh` writes `.release/EarCollector-dev-<commit>.zip` (committed files only, minus what `.pkgmeta` ignores), then send it with SendUserFile.

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
