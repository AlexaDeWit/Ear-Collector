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
| Error handling | Errors must never reach the player. See `CLAUDE.md`. |
| License | MIT. |
| Workflow | One branch per piece of work from `main`, a PR, and the user merges. Never push to `main` directly. |
| CI workflow files | Claude can't push `.github/workflows/` (no `workflow` permission; it can't be granted). Stage them in `ci/workflows/` for the user to move. |

## Done

- **PR #1** (merged): scaffold, kill detection (`PARTY_KILL`), group kills, assists (honorable-kill matching), surnames, error containment, the check toolchain, `CLAUDE.md`, and the in-game test sheet.
- **PR #2** (merged): the Ear Pouch window and the five ways to open it.
- **PR #3** (open, `ear-art`): painted ear art for 9 races × 4 tones plus a generic ear, the `art` check, and this status file.

## Waiting on the user

1. **Turn CI on**: move `ci/workflows/ci.yml` and `release.yml` to `.github/workflows/` on `main` in GitHub's web editor (steps in `ci/README.md`), then delete `ci/`.
2. **Merge PR #3.**
3. **In-game tests** (`docs/in-game-tests.md`). Nothing has been run in the game yet. The ones that decide the most:
   - T1: does `PARTY_KILL` fire with readable IDs for your and your group's open-world kills?
   - T2: do honorable kills arrive within about 2 s of the death, so assists match?
   - T9: does saved data survive `/reload`? One addon author claims Forever doesn't reload it.
   - T10: the pouch, including opening your bags in combat without "action blocked", and the ear art loading.
   - T4: does the death recap name who killed you? It gates Rivals and Vengeance.
   - T6: is the 7th `GetPlayerInfoByGUID` value the surname?

## Next up (in order)

1. **Loot toast**: a small pop-up when you collect an ear, with the ear art, the victim's name in its grade color and a short sound. Clicking it opens the pouch on that ear. All handlers go through `Errors.Wrap`.
2. **Escape closes the pouch**: needs a taint-safe approach; `UISpecialFrames` writes a Blizzard global.
3. **Options panel**: the settings that exist so far (announce, open with bags, include battlefields and free-for-all areas, camping window) in Blizzard's Settings UI.
4. **Ledger and Rivals tabs**, as in the concept mockup: totals, grades, classes and zones; who you've taken ears from.
5. **Deaths, Rivals and Vengeance**: record who killed you from the death recap (if T4 passes), then Legendary "Vengeance" ears.
6. Later: export ears as text, inspect another Ear Collector user's pouch, CurseForge and Wago publishing.

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
