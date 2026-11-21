# WoW Forever kill-detection viability (research, November 2026)

> Saved from the research session that shaped the detector design. Findings marked
> [verified in source] were checked against Blizzard's UI source for the Forever build
> (Gethe/wow-ui-source, `forever` branch, commit 734f065). [community] and [inferred]
> items are unconfirmed until the in-game tests in `docs/in-game-tests.md` run.
> The design it recommends is implemented; decisions since then are in `docs/STATUS.md`.


Prepared 2026-11-21 for WoW Forever live build 1.60.1.71037 (Interface 16001, game type "camelot",
`WOW_PROJECT_CAMELOT = 18`). This builds on `wow-addon-plan.md` §1.1–1.2 and does not repeat it. Nothing
in `/home/user/Ear-Collector` was modified. Race icons and the group-acceptance code change are out of
scope; the code is mentioned only where a finding affects it.

## How to read this

Each item carries a label:

- **[verified in source]**: checked in Blizzard's Forever UI source, Gethe/wow-ui-source branch `forever`
  at commit `734f065` ("1.60.1 (71037)"). `scripts/setup-tools.sh` fetches the API docs from that
  commit into `.cache/wow-ui-source/`; for other files, clone that branch. Paths below are
  relative to `Interface/AddOns/`. The generated API docs are in `Blizzard_APIDocumentationGenerated/`.
  This proves what the API surface is, not how the server behaves.
- **[community]**: from addon source on GitHub (cloned during the research) or from search-engine
  summaries. Where an addon says it measured or "verified in game", that is noted, because most of these
  addons are new, often AI-assisted, and much of their code encodes assumptions rather than observations.
- **[inferred]**: my reasoning. It needs an in-game check.

**Verdicts** are **works**, **likely**, **unknown** or **no**.

**Access limits.**
- warcraft.wiki.gg, curseforge.com, wago.io, wowinterface.com, icy-veins.com, wowhead.com and
  news.blizzard.com could not be fetched (DNS refused by the session's network policy). Anything from
  them came through WebSearch summaries and is labelled [community].
- The GitHub REST API refused issue and PR reads for third-party repositories, so PR discussions were not
  read. Commit messages were.
- GitHub code search worked, and found about 130 repositories that use `PARTY_KILL` together with
  `issecretvalue`. The relevant ones were cloned.

### Main community sources (cloned, commit, date)

| Addon | Commit | What makes it useful |
|---|---|---|
| **Killed by Savages** (Mouchoir/Killed-by-Savages) | `7644e31`, 2026-11-18 | Forever-only guild kill board. Its README says detection was "measured with a probe before it was written". The probe is `probe/KBSProbe`. **The strongest evidence found.** |
| **Spicy Kill Streaks** (zednx/spicy-kill-streaks) | `876d93e`, 2026-11-21 | Its `CLAUDE.md` has a "WoW Forever facts (verified in game)" section. |
| **Overlord** (leliondoc/overlord-forever-addon) | `4a79200`, 2026-11-18 | Forever world-PvP campaign addon. Dated in-game checks; `docs/audit-complet-2026-10-04.md` says the GUID path was "validé en jeu" (validated in game). |
| **HeadHunter** (GudaAddons/HeadHunter) | `84328ef`, 2026-11-21 | Forever and Era. Dated beta probes: death recap on 2026-09-23 (build 69913), honor lines on 2026-10-04. |
| **HonorLog** (adbergen/honor-log) | `eeb4578`, 2026-11-21 | Forever world PvP via HK deltas, honor lines and the death recap. Ships `/honorlog probe`. |
| **dG KillShot** (linman0x90/dgks) | `3b7a754`, 2026-11-20 | Now also records team kills (`PARTY_KILL` by group members) and reads killers from the death recap. |
| **HardcoreAchievements** (IAmChills) | `4bb37c3`, 2026-11-21 | Widely used. `Forever/KillTracking.lua` documents what `PARTY_KILL` and `UNIT_DIED` do on Forever. |
| **AutoBiographer** (AaronV-T) | `2544402`, 2026-11-09 | Forever kill and death tracking. Uses `C_DamageMeter` after combat. |
| Blood Feud, Olympus, InTheBinKoS, dota-raid-tools, helloforever | various | Corroborating designs. |
| Quantum-Seer `forever_secret_values.md` | `0731699` | A research note that quotes warcraft.wiki.gg's "Patch 1.60.1/API changes/notes". Second-hand. |

---

## Verdicts at a glance

| # | Question | Verdict |
|---|---|---|
| 1a | `PARTY_KILL` fires for **your** killing blow | **works** (API verified; behaviour measured by the community) |
| 1a | ... for **your pet** (attacker = the pet's GUID) | **likely** |
| 1a | ... for **party members** and their pets | **likely** |
| 1a | ... for **raid members**, including other subgroups | **likely** (exact reach and range not published) |
| 1a | ... for **guardians and totems** | **unknown** |
| 1b | Fires for enemy **players** in open-world PvP with **readable** GUIDs | **likely**, close to works; two counter-signals noted |
| 1c | Blizzard code registers the `PARTY_KILL` frame event | **no**: Blizzard only uses the closed combat-log sub-event |
| 1d | Group membership by GUID (`C_PartyInfo.IsGUIDInGroup`) | **works** for players; pets need a token scan |
| 2 | Any signal for a kill where someone outside the group landed the blow but you fought | **likely**: an HK counter step matched to a `UNIT_DIED` |
| 2 | Forever has honor and honorable kills | **works** |
| 2 | `PLAYER_PVP_KILLS_CHANGED`, `GetPVPSessionStats` and `GetPVPLifetimeStats` exist without secret flags | **works** |
| 2 | `CHAT_MSG_COMBAT_HONOR_GAIN` names the victim on Forever | **unknown**: sources conflict |
| 2 | `UNIT_DIED` fires for nearby enemy players with a readable GUID | **likely** (range unknown) |
| 3 | `C_DeathRecap.GetRecapEvents()` names your open-world PvP killer | **likely**, close to works |
| 3 | A dedicated "new recap available" event | **no**: use `PLAYER_DEAD` and retry |
| 4 | Which maps turn on `AddOnRestrictionType.Map` | **unknown** as a list; documented as "a dungeon or raid" |
| 4 | Open-world PvP is ever "unit identity restricted" | **likely no** |
| 5 | War Mode on Forever | **no**: rulesets instead; PvP is flag-based |
| 5 | World battlefields or free-for-all zones | **unknown**: no evidence either way |

---

## Q1. `PARTY_KILL` on Forever

### 1a. Who triggers it

**Verdicts:** your killing blows **works**; pets **likely**; party **likely**; raid **likely**; guardians
and totems **unknown**.

**What the source shows**

- [verified in source] `UnitDocumentation.lua:3724–3734` defines `PARTY_KILL` with payload
  `attackerGUID: WOWGUID, targetGUID: WOWGUID`, both non-nilable, and flags
  `SecretWhenUnitIdentityRestricted = true` and `SynchronousEvent = true`. The docs do not describe who
  triggers it.
- [verified in source] The flag is defined in `SecretPredicatesDocumentation.lua:130–132`:
  *"Guarded APIs and events produce secret values when the unit isn't player-controlled or in the
  party/raid. For compound tokens (eg. 'boss1target'), results are secret if any unit in the chain fails
  this."*
  - The attacker is you, a group member, or a pet, all of which are player-controlled or in the group.
  - The target is an enemy player, which is player-controlled.
  - So by this definition neither GUID should be secret in open-world PvP.

**Your own killing blows**

- [community, verified in game] Spicy Kill Streaks `CLAUDE.md`: *"`PARTY_KILL(attackerGUID, targetGUID)`
  works outside instances with readable GUIDs and names the exact killing blow. It may be secret in some
  content: check `issecretvalue` before comparing."*
- [community, measured] Overlord `docs/audit-complet-2026-10-04.md:190`: the PARTY_KILL GUID path was
  "validé en jeu (baseline HK)".

**Pets**

- [community] Several addons agree that a pet's killing blow arrives with the **pet's GUID** as the
  attacker, not the owner's:
  - Overlord `KillingBlows.lua:12`: *"A pet's blow is the pet's (the PARTY_KILL attacker is not us)."*
  - Olympus `Wanted.lua:1357`: *"a pet's GUID is not ours"*.
  - Killed by Savages role `mypet`, Blood Feud, AutoBiographer and Spicy all compare the attacker with
    `UnitGUID("pet")`.
  - HardcoreAchievements `Forever/KillTracking.lua:7`: *"a party member, including pets, was credited"*.

**Party and raid members**

- [community, measured] The Killed by Savages README: *"a killing blow by you, your pet or your group
  (`PARTY_KILL`)"*. Its detector maps the attacker to the roles `me`, `mypet`, `party`, `partypet`, `raid`
  and `raidpet` (`Core/Detect.lua:86–106`).
- [community] Its probe was written specifically to learn *"whether PARTY_KILL also covers raid members
  outside our subgroup"* (`KBSProbe.lua:504–530`). The answer is not published, but the shipped addon
  counts every raid role.
- [community] Overlord saw raid traffic at scale: *"chaque PARTY_KILL de raid (plusieurs/s en 200v200)"*
  (several raid PARTY_KILLs per second in 200-versus-200 fights) and *"Un PARTY_KILL de raid peut provenir
  d'un membre sur une autre couche"* (a raid PARTY_KILL can come from a member on another layer)
  (`Core.lua:1489, 1637–1640`).
- [community] Olympus `Wanted.lua:1379`: *"every creature a party member kills fires it too"*.
- [community] HardcoreAchievements `Forever/KillTracking.lua:6–8` adds a range limit: *"You do not need to
  target the mob or be on its threat table; observing a group kill in range is enough."*
  - [inferred] Group kills far away from you, out of client range or on another layer, may not fire, or
    may fire with an attacker you cannot resolve.

**Guardians and totems**

- **unknown.** No source tested them.
- [community] HardcoreAchievements' Classic combat-log path assumes no PARTY_KILL for
  totem, pet or mechanic kills. That is Classic, though, and contradicts the Forever pet evidence above.

**Attackers outside the group**

- [community] Two addons handle an attacker that resolves to no group unit:
  - HardcoreAchievements logs *"killer is not in the group"*.
  - Killed by Savages counts `detect.killByOther`.
- [community] HardcoreAchievements also handles a **secret attacker with a readable target**: *"The event
  itself means the party was credited. Who swung is unreadable"*.
- [inferred] These are defensive branches, not proof that either case happens. Ear Collector should log
  both, not error on them.

### 1b. Does it fire for enemy players in open-world PvP, with readable GUIDs?

**Verdict: likely**, close to works.

**For**

- [verified in source] The predicate definition in 1a means player GUIDs are not identity-restricted.
- [community, measured] Killed by Savages, Spicy, Overlord and HonorLog all rely on it in the open world.
- [community] They all report it secret in battlegrounds and instances:
  - The Killed by Savages README: *"Battlegrounds: enemies are secret inside"*.
  - HardcoreAchievements `Forever/LootKills.lua:6`: *"Inside dungeons/raids, PARTY_KILL and UNIT_DIED
    GUIDs are secret"*.
  - dgks commit `3aa7642` quotes a real error from restricted content: *"attempt to compare local
    'attackerGUID' (a secret string value, while execution tainted by 'dgks')"*.

**Counter-signals** [community, via search]

- Vendetta PvP's CurseForge page reportedly says *"killing-blow announcements are currently unavailable on
  WoW Forever (1.60.1)"*. The reason is unknown.
- A WoWInterface thread from January 2026, "Issues with PARTY_KILL in PvP", is about Retail; its author
  could not test in PvP. https://wowinterface.com/forums/showthread.php?p=345270
- Neither is a measured failure on Forever, so the verdict stays **likely**.

### 1c. Who listens to it

**Verdict:** Blizzard registers the frame event: **no**.

**Blizzard's own code** [verified in source]

- No Blizzard file registers the standalone `PARTY_KILL` frame event.
- Every Blizzard reference is to the **combat-log sub-event**:
  - `Blizzard_CombatLogProcessor/Blizzard_CombatLogProcessor.lua:823, 961`. This addon's TOC has
    `## UseSecureEnvironment: 1`, so it runs in the secure environment.
  - `Blizzard_CombatLog/Mainline/Blizzard_CombatLog.lua:115, 294, 346, 797–808` (filters).
  - `Blizzard_ChatFrame/Mainline/ChatConfigFrame.lua:717` (chat message type).
- So Blizzard's UI makes no assumption about the frame event.

**Addons that ship Forever TOCs**

| Addon | Who counts | Guards it assumes |
|---|---|---|
| Killed by Savages | you, pet, party, party pet, raid, raid pet; uses `PARTY_KILL` only to name the victim of an **HK step** | skips secret GUIDs and battlegrounds; victim must be an enemy faction |
| HonorLog | you only, and only as the "killing blow" flag on an HK step | skips secret GUIDs; target must match `^Player`; skips PvP instances |
| dgks | you = kill; group member on a non-group player = "team kill" (via `party1..4`/`raid1..40` scan) | `isSecret` check placed **outside** the `--@debug@` block |
| Spicy Kill Streaks | you and your pet | `usableString` (not secret and non-empty) on both GUIDs |
| Blood Feud | you and your pet | instances paused |
| Overlord | you; group members via a roster cache | handles a hidden attacker by falling back to the achievement KB counter |
| HardcoreAchievements | player, pet, member, member pet; "other" is ignored | treats a secret attacker as "party credited" |
| AutoBiographer | player or player pet (creature kills) | secret check on the attacker |
| Olympus, dota-raid-tools, InTheBinKoS | you (Olympus); "we or our group" (dota-raid-tools); you plus HK pairing (InTheBinKoS) | secret checks |

### 1d. Checking group membership by GUID

**Verdict: works** for players; pets need extra work.

- [verified in source] `PartyInfoDocumentation.lua:419–433` defines
  `C_PartyInfo.IsGUIDInGroup(guid, category?) -> isInGroup: bool`.
  - It is flagged `SecretArguments = "AllowedWhenUntainted"`, so addon code must not pass it a secret GUID.
  - It has **no secret-return flag**.
  - `category` is nilable: *"If not provided, the active party is used"*.
- [inferred] A pet's GUID is not a group member, so `IsGUIDInGroup` will return false for pets.
- For pets, scan the tokens: `UnitGUID("pet")`, `partypet1..4` and `raidpet1..40`.
  - [verified in source] `UnitGUID` is `SecretWhenUnitIdentityRestricted`, and group pets are
    player-controlled.
  - The scaffold-ci working tree already does this scan.
- [verified in source] An alternative: `UnitTokenFromGUID(guid)` (`UnitDocumentation.lua:3296`;
  `SecretWhenUnitIdentityRestricted`, `AllowedWhenTainted` args), then
  `UnitPlayerOrPetInParty(token)` or `UnitPlayerOrPetInRaid(token)`. Both return a `bool` with no secret
  flag.
  - [inferred] `UnitTokenFromGUID` may return a non-group token such as `target` or `nameplateN`, so the
    explicit scan is more predictable.

---

## Q2. Kills where someone outside the group lands the killing blow

### Is there any usable signal?

**Verdict: likely.**

The approach that has been measured in game [community: the Killed by Savages README and
`Core/Detect.lua`]:

1. The server grants an **honorable kill** (HK) to everyone who helped kill the enemy, killing blow or not.
2. `PLAYER_PVP_KILLS_CHANGED` fires when the lifetime counter moves.
3. About 3 seconds later, each HK is matched within ±2 seconds to:
   1. a `PARTY_KILL` by you or your group, giving the victim and "killing blow"; or else
   2. a `UNIT_DIED` of an enemy-faction player near you, giving the victim and "assist"; or else
   3. nothing, giving "HK with no victim".
4. HKs that arrive within 2 seconds of each other are matched together. If more enemies died than HKs
   arrived, **nobody is guessed**.

The rest of this section covers the parts of that approach.

### Does Forever have honor and honorable kills?

**Verdict: works.**

- [verified in source] The Camelot inspect frame shows HKs:
  `Blizzard_InspectUI/Camelot/InspectPVPFrame.lua:110–132` calls `GetInspectHonorData()` and shows
  "Honorable Kills", *Today* and *Lifetime*.
- [verified in source] There is a PvP rank system:
  - `Blizzard_UIPanels_Game/Camelot/PVPRankFrame.lua` reads `C_MajorFactions.GetMajorFactionProgressionInfo(2800)`
    for rank points.
  - It has 14 `Enum.PvPRanks`, a season countdown and a weekly cap.
  - The battleground scoreboard has an honor-gained column, and `honorLevel` is reused as the PvP rank
    (`Blizzard_PVPMatch/Camelot/PVPMatchTableOverrides.lua`).
- [verified in source] The War Mode, honor-level and prestige UI is absent:
  - `Blizzard_PVPUI.toc` has `ExcludeLoadGameType: camelot`.
  - The Camelot talent frame has *"No PvP talents in Camelot"*.
  - `UnitFramePvPIndicatorStyle.lua` says *"Camelot has no prestige art"*.
- [community] HonorLog uses honor currency 1792, rank-points currency 3468 and rank currency 3473.

### Do the HK counters exist, and are they secret?

**Verdict: works.**

- [verified in source] `PlayerScriptDocumentation.lua:708–746` defines
  `GetPVPLifetimeStats() -> lifetimeHonorableKills, lifetimeMaxPVPRank`,
  `GetPVPSessionStats() -> honorableKills, dishonorableKills` and `GetPVPYesterdayStats`.
  None carries a secret flag.
- [verified in source] `UnitDocumentation.lua:3864–3872`: `PLAYER_PVP_KILLS_CHANGED(unitTarget)` has no
  secret flag.
- [community, measured] The Killed by Savages README and `Detect.lua:362–375`: *"The counter is readable
  in a battleground but every enemy is secret"*.
- [community] Overlord prefers `GetPVPLifetimeStats` because the session count resets daily.
  InTheBinKoS polls `GetPVPSessionStats` once a second as well. Both are cheap, and polling covers a
  missed event.

### Does the honor chat line name the victim?

**Verdict: unknown.**

- [verified in source] `ChatInfoDocumentation.lua:1401–1427`: `CHAT_MSG_COMBAT_HONOR_GAIN` carries **no
  event-level secret flag**. It is one of the few chat events without `SecretInChatMessagingLockdown`.
  Its `text`, `playerName` and `guid` fields are not marked `NeverSecret` either.
- [community] The sources disagree on whether Forever's line names the victim:
  - HeadHunter `Detection/HonorKills.lua:10–11`: *"Forever 'You have been awarded N Honor.' names nobody
    (seen in game 2026-10-04)"*. That was a beta build.
  - HeadHunter's 1.0.x changelog says *"On WoW Forever, a group kill now counts through the game's
    'honorable kill' message"*.
  - HonorLog and InTheBinKoS parse named `COMBATLOG_HONORGAIN*` lines and fall back to the award line.
  - Overlord treats the line as diagnostic only, because it is *"diffusé à tous les membres éligibles
    proches"* (sent to every eligible member nearby).

### What `UNIT_DIED` does

**Verdict: likely** for nearby enemy players with a readable GUID.

- [verified in source] `UnitDocumentation.lua:4224–4233`: payload `unitGUID`, flags
  `SecretWhenUnitIdentityRestricted` and `SynchronousEvent`.
  - By the predicate, it is secret for creatures that aren't in your group in restricted content, and not
    secret for players.
- [community] An older wiki line says *"secret in the same cases cooldowns & auras are secret"*. That
  would mean it is secret in combat, and it conflicts with the generated docs. The docs are newer.
- [community, measured] What it covers:
  - Killed by Savages: *"the enemy player who died next to you at that moment (`UNIT_DIED`)"*.
  - HardcoreAchievements: *"Nearby UNIT_DIED events"*.
  - AutoBiographer resolves NPC GUIDs from it in the open world.
  - All report it secret in dungeons, raids and battlegrounds.
- **Range: unknown.**
  - [inferred] Probably the client's area of interest; `OBJECT_LEFT_AOI(guid)` exists in the same doc
    file.
- **Feign Death: unknown.**
  - [community] On Classic the combat log logged Feign Death as `UNIT_DIED` (HeadHunter HH-153).
  - HeadHunter says a Feign Death gives **no honor**, *"seen in game: honor 1 s after the death"*.
  - So an HK match filters Feign Death out. A bare `UNIT_DIED` does not.

### Can an HK step plus a player `UNIT_DIED` identify "you got credit for killing X"?

**Verdict: likely**, with known gaps.

- [community, measured] This is exactly what Killed by Savages does (see the top of this section).
- Gaps:
  - **Bursts are ambiguous.** When several enemies die within 2 seconds, Killed by Savages names
    nobody.
  - **Grey victims give no HK** [community: Classic rules via search; Overlord `KillingBlows.lua:7–11`].
    A `PARTY_KILL` on a grey player must therefore not be held back waiting for an HK.
  - [community] Overlord: *"On Forever the honorable kill of every kill around goes to everyone near"*.
    An HK means you or your group contributed, so HK-based assists are broader than "you hit them".

### Extra signals worth noting

**`C_DamageMeter` "EnemyDamageTaken" after combat:** a possible "you fought X" corroboration.

- [verified in source] `DamageMeterDocumentation.lua` and `DamageMeterConstantsDocumentation.lua` (enum
  `EnemyDamageTaken = 10`, `Deaths = 9`):
  - The getters are `SecretWhenInCombat`.
  - Source rows have `name` and `sourceGUID` marked `ConditionalSecret`, and `factionGroup`.
  - `isLocalPlayer` and `deathRecapID` are marked `NeverSecret`.
- [verified in source] Blizzard_DamageMeter loads on Camelot (TOC `AllowLoadGameType: standard, camelot`).
- [community] On Forever:
  - helloforever reads `EnemyDamageTaken` rows, with enemy names, after combat for creatures.
  - AutoBiographer reads DamageMeter sessions after combat, and notes *"WoW Forever follows each
    completed-session update with a session ID of 0"*.
- [inferred] For enemy **players**, the rows should list everyone your side damaged during the fight,
  with names readable once combat ends. That fits an "assist" check. Untested for players.

**Your lifetime killing blows**

- [community, checked in game] Overlord `CombatTracker.lua:272–278`: `GetAchievementCriteriaInfo(1487, 1)`
  quantity *"gave 2133"* on 2026-11-15. `C_AchievementInfo.GetCriteriaInfo` does not exist on Forever.
- A step in this count confirms your own killing blow even when `PARTY_KILL` is hidden.

---

## Q3. The player's own deaths (for Rivals/Vengeance)

### Does `C_DeathRecap.GetRecapEvents()` name the killer?

**Verdict: likely**, close to works.

**What the source shows** [verified in source]

- The API:
  - `DeathRecapDocumentation.lua` defines `GetRecapEvents(recapID?)`, `HasRecapEvents(recapID?)`,
    `GetRecapLink(recapID?)` and `GetRecapMaxHealth(recapID?)`.
  - All take `SecretArguments = "AllowedWhenUntainted"` and have **no secret-return flags**.
  - The `DeathRecapEventInfo` structure is documented with **no fields**, so the docs cannot say whether
    individual fields are secret.
- It loads on Forever:
  - Blizzard_DeathRecap loads with `[Family]\... [AllowLoadGameType mainline]`, and camelot is a member
    of mainline. The evidence: TOC lines such as
    `Mainline\ChatConfigFrameOverrides.lua [AllowLoadGameType mainline] [ExcludeLoadGameType camelot]`
    would be pointless otherwise.
  - Camelot uses the Mainline `DEATH` dialog, whose 4th button is *Death Recap*
    (`Blizzard_StaticPopup_Game/Mainline/GameDialogDefs.lua:183–249`). The Camelot override file only
    replaces `GetBindWarning`.
- How Blizzard's frame reads it (`Blizzard_DeathRecap/Mainline/Blizzard_DeathRecap.lua`):
  - Events come newest first; `causedDeath = i == 1`.
  - Fields used: `event`, `spellId`, `spellName`, `amount`, `overkill`, `absorbed`, `resisted`,
    `blocked`, `school`, `timestamp`, `currentHP`, `sourceName`, `hideCaster`, `environmentalType`.
  - The caster shown is `sourceName` unless `hideCaster` is set.
- Blizzard's PTR reporter reads `C_DeathRecap.GetRecapEvents()[1].sourceGUID`
  (`Blizzard_PTRFeedback/Blizzard_PTRFeedback_Events.lua:113–121`).

**What addons observed** [community]

- HeadHunter probe, 2026-09-23, build 69913 (`Detection/ForeverDeaths.lua:3–7`):
  - Entries have `sourceGUID`, `sourceName` (*"Given-Realm", no family name*), `sourceFlags`, `event`,
    `amount`, `overkill` and `timestamp` (server epoch).
  - The killing blow has `overkill >= 0`; Olympus adds that other rows have `-1`.
- Killed by Savages README (measured): *"Deaths come from the death recap, which names the killer (player
  or pet) and the spell"*. The recap is *"readable in battlegrounds too"*. For a pet killer the recap
  *"does not name a pet's owner"*.
- helloforever: *"`HasRecapEvents` returning a secret boolean now waits like any other secret"*. So guard
  `HasRecapEvents` too.
- Killed by Savages: *"The client fires PLAYER_DEAD twice at times, within the same second"*.

### Which event signals a new recap, and what is its ID?

**Verdict: no** dedicated event.

- [verified in source] The `DeathRecap` system's `Events` list is empty. Nothing in the docs signals that a
  recap is ready.
- Read it on `PLAYER_DEAD`, and retry if it is empty. Addons use 0.3, 0.5, 1, 1.5, 2, 3 and 4 seconds.
- [verified in source] The recap ID:
  - Calling with `nil` gives the most recent death, as Blizzard's death dialog does (`OpenDeathRecapUI()`
    with no ID).
  - Numbered IDs come from the closed combat-log `UNIT_DIED` sub-event
    (`Blizzard_CombatLogProcessor.lua:845–853`), out of reach for addons.
  - They also come from `C_DamageMeter` `Deaths` rows as `deathRecapID`, which is `NeverSecret`.
  - Chat links use `|Hdeath:<id>|h` (`LinkUtil.lua:21`).

### Alternatives

- **The killer's full name:**
  - [community] The recap name lacks the surname. Take `sourceGUID` and call
    `GetPlayerInfoByGUID(sourceGUID)`.
- **When the recap is hidden or empty** [community: dgks, HeadHunter]:
  - Remember enemy players whose target was you (compare `UnitGUID(unit.."target")` with your own GUID).
  - Do not use `UnitIsUnit` on compound tokens; per dgks commit `82a9198` it always returns a secret.
- **The owner of a killing pet:**
  - [inferred] Call `UnitOwnerGUID(token)` on a nameplate or target token of the pet. The argument type is
    `UnitTokenPvPRestrictedForAddOns`, so it may return nil.
- **Damage taken by source:**
  - [community] AutoBiographer reads the `DamageTaken` breakdown after combat:
    `combatSpells[].combatSpellDetails.unitName`.

---

## Q4. Restrictions

### What turns on the Map restriction, and which maps?

**Verdict: unknown** as a list.

- [verified in source] `RestrictedActionsConstantsDocumentation.lua` describes `Map` as *"The player is on
  a map that applies addon restrictions."*
- [verified in source] The predicates name the maps only by example:
  - `SecretOnRestrictedMaps`: *"…when the player is on an addon-restricted map such as a dungeon or raid."*
  - `SecretInChatMessagingLockdown`: *"…a communication-restricted map such as a dungeon or raid."*
  - `SecretWhenUnitComparisonRestricted`: *"…only applies when the player is on an addon-restricted
    map."*
- [verified in source] No API lists the restricted maps, and no Blizzard UI code checks
  `AddOnRestrictionType.Map`. The only consumer is GamepadSmartNavigation, which checks `Combat`.
- [community] Addons report restrictions only in dungeons, raids and battlegrounds, never on an
  open-world map.

### Is open-world PvP ever "unit identity restricted"?

**Verdict: likely no.**

- [verified in source] By definition the identity predicate exempts player-controlled units.
- [verified in source] `SecretWhenUnitNameIdentityRestricted` even says *"except in PvP when the queried
  unit is a player"*.
- [verified in source] Forever has no War Mode UI (see Q5).
- [community] Every Forever PvP addon above works in the open world.
- Edge cases, **unknown**:
  - raid members on another layer [community: Overlord];
  - a possible future world PvP event using the `PvPMatch` restriction outside an instance [inferred].

### Predicates an addon can check

All [verified in source]:

| API | Meaning or use |
|---|---|
| `issecretvalue(v)`, `issecrettable(t)`, `canaccessvalue(v)`, `canaccesstable(t)`, `hasanysecretvalues(...)`, `scrubsecretvalues(...)` | `FrameScriptDocumentation.lua`. **These are the ones that matter: test each payload value before using it.** |
| `C_Secrets.ShouldUnitIdentityBeSecret(unit)` | Needs a **unit token**, so it is useless for a GUID from an event payload. |
| `C_Secrets.ShouldUnitComparisonBeSecret(u1, u2)`, `C_Secrets.CanCompareUnitTokens(u1, u2)` | Token comparisons. |
| `C_Secrets.HasSecretRestrictions()` | *"If false, all APIs that are tagged as potentially returning secrets will never do so."* |
| `C_RestrictedActions.IsAddOnRestrictionActive(type)`, `GetAddOnRestrictionState(type)`; event `ADDON_RESTRICTION_STATE_CHANGED(type, state)` | `IsAddOnRestrictionActive` *"will always return false during dispatch of ADDON_RESTRICTION_STATE_CHANGED"*. Use the state argument there. |
| `C_ChatInfo.InChatMessagingLockdown()` | Chat-messaging lockdown. |
| `C_CombatLog.IsCombatLogRestricted()` | Whether the combat log is closed. |
| `IsInInstance()`, `GetInstanceInfo()` | No secret flags (`InstanceDocumentation.lua:103–178`), so the scaffold's secret check on `instanceType` is harmless but not needed. |

**Recommendation** [inferred]:
- Do not gate on predicates. They are per unit and need tokens.
- Gate on the payload values themselves (`issecretvalue`) and on `IsInInstance()`.
- Read `IsAddOnRestrictionActive(Map / PvPMatch)` only to label hidden kills in the debug log.

---

## Q5. Forever's PvP context

**Realms**

- [community, via search; the Blizzard article "Choose Your Ruleset in World of Warcraft: Forever",
  news.blizzard.com/article/24302070] Realms are replaced by **rulesets**: Normal, PvP, Roleplay, and
  Hardcore (post-launch). They are "mega realms", region-wide.
- [community] HeadHunter keeps PvP, Normal, Roleplay and Hardcore data apart, and its online count is
  *"everyone in your region, both factions"*.
- [community] Layering exists: Overlord has `LayerJumper.lua`, and HeadHunter has `Detection/Layer.lua`.

**War Mode: no**

- [community] No War Mode.
- [verified in source] There is no War Mode button in the Camelot talent frame, and Blizzard_PVPUI is
  excluded on camelot.
- `C_PvP.IsWarModeFeatureEnabled()` exists in the shared docs; test it in game.

**Flagging**

- [community, Icy Veins via search] On the PvP ruleset you are auto-flagged in contested and enemy zones
  (*"any zone above Level 15 is considered a Contested Zone"*). On Normal and RP you flag manually.
- [verified in source] The Camelot player frame has a PvP flag timer and the FFA PvP icon art
  (`Blizzard_UnitFrame/Camelot/PlayerFrame.lua`, `UnitFramePvPIndicatorStyle.lua`).

**Faction rules**

- Two factions [community]. Killed by Savages filters victims to the enemy faction, because a same-faction
  death *"where everyone fights everyone"* could otherwise be misattributed.
- [verified in source] `GetZonePVPInfo` still reports `sanctuary`, `arena` (free-for-all), `friendly`,
  `hostile`, `contested` and `combat` (`Blizzard_FrameXML/Mainline/ZoneText.lua`).

**Battlegrounds and world PvP**

- [community] Warsong Gulch, Arathi Basin, Alterac Valley and the new **Darkspear Islands**, all instanced.
  Queues mix the Normal, PvP and RP rulesets. **No arenas.**
- **No source found** for world battlefields, the Silithus or Eastern Plaguelands objectives, or
  Gurubashi-style free-for-all on Forever. The verdict is **unknown**; the in-game test is below.
- Overlord's "fronts", keeps and outposts are the addon's own construct, not a Blizzard system [community].

**Honor**

- [community] Two currencies: Honor (for gear, with a 25,000 cap per HonorLog) and Rank Points (14 ranks,
  weekly cap, seasons; no realm-ladder ranking).
- [community] HKs go to everyone who helped, including your group nearby. Grey victims give no
  honor [community: Classic rules].

**Names and GUIDs**

- [verified in source] Characters have **a first name and a surname**:
  - `RegionalUniqueNamesEnabled()` exists.
  - `UnitName` returns `name, surname` on Camelot (`Blizzard_FrameXMLUtil/Camelot/NameUtil.lua`).
  - The separator is `Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR`.
- [community] dgks commit `4f6da89`: `GetPlayerInfoByGUID` and `UnitNameFromGUID` *"return the surname
  where other clients return the realm"*.
- [community, wiki via the Quantum-Seer note] Since beta build 70425, creature, pet, vehicle and
  game-object GUIDs have obfuscated server and spawn parts. **Player GUIDs are not in that list.**

---

## Recommended detection design: "you or your group", open world

The design keeps one primary signal, adds one confirming signal, and treats everything else as optional.
It fits the existing `Detectors/PartyKill.lua` and `Core/Context.lua` on scaffold-ci, which already apply
the secret guards, use `IsGUIDInGroup`, scan pets and exclude instances.

### Signal A (primary): `PARTY_KILL` by you, your pet, a group member or a group pet

Steps, in order:

1. If either GUID is secret, increment `hiddenKills` and stop. This guard must stay **outside** any
   `--@debug@` block (the dgks lesson).
2. The target must match `^Player%-`.
3. `Context.Current()` must say the kill counts: not in an instance, and battlefield and free-for-all
   zones per the settings.
4. Classify the attacker:
   - `player` or `pet` gives `by = "you"`. Optionally split `"pet"` out.
   - `IsGUIDInGroup` true gives `by = "group"`.
   - A `partypet` or `raidpet` match gives `by = "group"`.
   - Anything else gives "other". **Keep it in a 5-second ring** for signal B; do not drop it silently.
5. **Add a victim-faction check** [inferred, as Killed by Savages does]:
   - Take the race from `GetPlayerInfoByGUID`, map it to a faction, and require the enemy faction.
   - This guards against free-for-all zones and same-faction edge cases.
   - Race mapping is the separate race research, so reuse its table.
6. **Do not require an HK.** Grey victims give none.
7. Deduplicate by victim GUID within about 5 seconds across all signals. `Ears.Record` already treats
   repeats as "camped".

### Signal B (confirming, and the source of assists): an HK counter step

1. On `PLAYER_PVP_KILLS_CHANGED`, plus a 1-second poll as a backstop, read `GetPVPLifetimeStats()`.
   Skip it if the value is secret.
2. Steps inside an instance are ignored, or counted only.
3. After about 3 seconds, match each step within ±2 seconds:
   - to a signal-A record (mark it `confirmed = true`); else
   - to an "other" `PARTY_KILL`; else
   - to a `UNIT_DIED` of an enemy-faction player.
4. Group steps within 2 seconds together. When there are more deaths than HKs, name nobody (the Killed by
   Savages rule).
5. An HK matched to "other" or to `UNIT_DIED` is an **assist**: `by = "assist"`.
6. An unmatched HK only increments a "hidden HK" counter.

### Signal C: `UNIT_DIED` ring buffer

- Register `UNIT_DIED`. Keep readable `Player-` GUIDs that are not yours for 90 seconds, with what
  `GetPlayerInfoByGUID` returns.
- Use it **only** through signal B, because Feign Death and fights you only watched also produce it.

### Signal D (optional corroboration, after combat): `C_DamageMeter`

- On `DAMAGE_METER_COMBAT_SESSION_UPDATED` with a session ID above 0, once out of combat, read
  `EnemyDamageTaken` for that session.
- An assist victim found there was damaged by your side: show it as "fought".
- It is not needed for counting; keep it out of v1 unless the in-game test shows player rows.

### What becomes an ear (decisions for the user)

| `by` | Source | Counts as an ear? |
|---|---|---|
| `you`, `pet`, `group` | signal A | **Yes.** This is the decision already made. |
| `assist` | signal B with C, or B with an "other" `PARTY_KILL` | **Your call.** Recommendation: record it, but show it apart ("assists"), or put it behind a setting that is off by default. It is broader than "you hit them" (Overlord: HKs go to everyone nearby). |
| hidden HK | signal B alone | Never an ear; a counter for the stats panel. |

### Code notes for scaffold-ci (no changes made)

- **`realm`** from `GetPlayerInfoByGUID` may hold the **surname** on Forever [community: dgks].
  - Verify with test T6 below.
  - Key ears by **player GUID**, or by name plus surname. Do not build "Name-Realm" from the 7th return.
- **The "not you or your group" branch** (`Detectors/PartyKill.lua`) should feed the signal-B ring rather
  than only tracing.
- **`hiddenKills`** is useful. Also record `C_RestrictedActions.GetAddOnRestrictionState` for `Map` and
  `PvPMatch` in the debug entry, so hidden kills can be explained.
- **Own deaths (Rivals):**
  1. On `PLAYER_DEAD` (deduplicate within 3 seconds), read `HasRecapEvents` and `GetRecapEvents` with
     retries, each guarded with `issecretvalue` and `issecrettable`.
  2. Use the first row with `overkill >= 0`, or row 1.
  3. Skip the row when `hideCaster` is true.
  4. Resolve the full name via `GetPlayerInfoByGUID(sourceGUID)`.
  5. Count it only when `sourceFlags` mark a hostile player (`0x400` and `0x40`) and you are not in an
     instance.
- **A separate risk** [community, contested]:
  - HeadHunter's README says *"The Forever client does not load saved data back (a known client issue)"*,
    and its code detects it at runtime (`Core/Database.lua:270`).
  - Other Forever addons (Killed by Savages, HonorLog, AutoBiographer) rely on SavedVariables without
    comment.
  - Trophies depend on persistence, so add the reload test T10 below.

---

## In-game tests that would settle what remains unknown

Turn on Lua errors with `/console scriptErrors 1`. Define the helper once per session; it never compares
a secret. `/run` code runs tainted, so it behaves like addon code. `/etrace` is Blizzard's own (secure)
code [inferred: it may print secret values as plain text], so use it only to see **whether and when**
events fire.

| # | What it settles | Do this |
|---|---|---|
| T0 | The helper used by every test | `/run S=function(v)if v==nil then return"nil"end return issecretvalue(v)and"<S>"or tostring(v)end` |
| T1 | Q1a and Q1b: does `PARTY_KILL` fire for you, your pet, party and raid (including another subgroup), and is each GUID readable? Also when `UNIT_DIED` fires. | `/run local f=CreateFrame("Frame")f:RegisterEvent("PARTY_KILL")f:RegisterEvent("UNIT_DIED")f:SetScript("OnEvent",function(_,e,a,b)print(format("%.1f",GetTime()),e,S(a),S(b),"pet:",S(UnitGUID("pet")))end)`. Then, on the PvP ruleset, in a contested zone: (a) land a solo killing blow on an enemy player; (b) let your pet finish one; (c) let a party member finish one near you; (d) a raid member in another subgroup; (e) one at 100+ yards; (f) an enemy killed by a non-grouped ally while you fought; (g) a hunter feigning death. Ear Collector's `/ears debug` prints the same plus its decision. |
| T2 | Q2: the HK counters, and the honor line's text (named or not) | `/run local f=CreateFrame("Frame")f:RegisterEvent("PLAYER_PVP_KILLS_CHANGED")f:RegisterEvent("CHAT_MSG_COMBAT_HONOR_GAIN")f:SetScript("OnEvent",function(_,e,m)print(format("%.1f",GetTime()),e,S(GetPVPSessionStats()),S(GetPVPLifetimeStats()),S(m))end)`. Repeat T1 (a), (c) and (f), and also kill a grey-level enemy. Note whether an HK and a named line arrive, and the time gap to `PARTY_KILL` and `UNIT_DIED`. |
| T3 | Event ordering, by eye | `/etrace`, type `PARTY_KILL` in the search box (then `UNIT_DIED`, `PLAYER_PVP_KILLS_CHANGED`, `CHAT_MSG_COMBAT_HONOR_GAIN`), and mark moments with `/etrace mark solo kill`. |
| T4 | Q3: the recap after you die to an enemy player, and to their pet | `/run print(S(C_DeathRecap.HasRecapEvents()))` and then `/run local t=C_DeathRecap.GetRecapEvents()if issecrettable(t)then return print("<S>")end for i=1,3 do local e=t[i]if e and not issecrettable(e)then print(i,S(e.event),S(e.sourceName),S(e.sourceGUID),S(e.overkill),S(e.hideCaster))end end`. Run it right on death and again 2 s later. |
| T5 | Q4 and Q5: restrictions, zone type, War Mode | `/run for k,v in pairs(Enum.AddOnRestrictionType)do print(k,C_RestrictedActions.GetAddOnRestrictionState(v))end print(IsInInstance())print(C_PvP.GetZonePVPInfo())print(S(C_PvP.IsWarModeFeatureEnabled()),S(C_PvP.IsWarModeDesired()))`. Run it in a capital, a contested zone in combat, Gurubashi Arena (does it report `arena`?), and a dungeon. |
| T6 | Victim identity and secrecy on an enemy player in combat; realm vs surname | Target the player, then `/run local g=UnitGUID("target")print(S(g),S(C_Secrets.ShouldUnitIdentityBeSecret("target")))if not issecretvalue(g)then print(GetPlayerInfoByGUID(g))print(UnitName("target"))print(RegionalUniqueNamesEnabled())end` |
| T7 | Q1d: the group check for players and pets | In a party with a hunter or warlock: `/run for i=1,4 do local g=UnitGUID("party"..i)local p=UnitGUID("partypet"..i)if g then print(i,S(C_PartyInfo.IsGUIDInGroup(g)),S(p and UnitTokenFromGUID(p)),S(p and C_PartyInfo.IsGUIDInGroup(p)))end end` |
| T8 | Signal D: do enemy players appear in DamageMeter after combat, and is a death's recap ID readable? | Out of combat after a fight: `/run local a=C_DamageMeter.GetAvailableCombatSessions()ID=a[#a]and a[#a].sessionID print("session",ID)`, then `/run for _,c in ipairs(C_DamageMeter.GetCombatSessionFromID(ID,Enum.DamageMeterType.EnemyDamageTaken).combatSources)do print(S(c.name),S(c.sourceGUID),S(c.factionGroup))end` and `/run for _,c in ipairs(C_DamageMeter.GetCombatSessionFromID(ID,Enum.DamageMeterType.Deaths).combatSources)do print(S(c.name),S(c.isLocalPlayer),S(c.deathRecapID))end` |
| T9 | Your own killing-blow counter as a fallback | `/run print(S(select(4,GetAchievementCriteriaInfo(1487,1))),S(GetPVPLifetimeStats()))`, before and after a killing blow. |
| T10 | Whether SavedVariables persist on Forever | `/run EarCollectorDB.persistProbe=time()`, `/reload`, then `/dump EarCollectorDB.persistProbe`. Repeat across a full logout. |

All snippets are under the 255-character chat limit. They are maintained in
`docs/in-game-tests.md`.

---

## Source index

**Blizzard**
- https://github.com/Gethe/wow-ui-source/tree/forever (commit `734f065`). Key files:
  - `Blizzard_APIDocumentationGenerated/`: `UnitDocumentation.lua`, `SecretPredicatesDocumentation.lua`,
    `SecretPredicateAPIDocumentation.lua`, `PartyInfoDocumentation.lua`, `PlayerScriptDocumentation.lua`,
    `ChatInfoDocumentation.lua`, `DeathRecapDocumentation.lua`, `DamageMeterDocumentation.lua`,
    `RestrictedActionsConstantsDocumentation.lua`, `RestrictedActionsDocumentation.lua`,
    `FrameScriptDocumentation.lua`, `InstanceDocumentation.lua`, `PvpInfoDocumentation.lua`
  - `Blizzard_DeathRecap/`
  - `Blizzard_StaticPopup_Game/Mainline/GameDialogDefs.lua`
  - `Blizzard_CombatLogProcessor/`
  - `Blizzard_InspectUI/Camelot/InspectPVPFrame.lua`
  - `Blizzard_UIPanels_Game/Camelot/PVPRankFrame.lua`
  - `Blizzard_PlayerSpells/Camelot/ClassTalents/Blizzard_ClassTalentsFrame.lua`
  - `Blizzard_PVPUI/Blizzard_PVPUI.toc`
  - `Blizzard_FrameXMLUtil/Camelot/NameUtil.lua`
  - `Blizzard_DamageMeter/`
  - `Blizzard_EventTrace/Blizzard_EventTrace.lua`

**Addons**
- https://github.com/Mouchoir/Killed-by-Savages (`README.md`, `addon/KilledBySavages/Core/Detect.lua`,
  `probe/KBSProbe/KBSProbe.lua`)
- https://github.com/zednx/spicy-kill-streaks (`CLAUDE.md`, `SpicyKillStreaks/SpicyKillStreaks.lua`)
- https://github.com/leliondoc/overlord-forever-addon (`CombatTracker.lua`, `KillingBlows.lua`, `Core.lua`,
  `docs/audit-complet-2026-10-04.md`)
- https://github.com/GudaAddons/HeadHunter (`Detection/ForeverDeaths.lua`, `Detection/HonorKills.lua`,
  `Sync/Justice.lua`, `Core/Database.lua`, `README.md`)
- https://github.com/adbergen/honor-log (`Core.lua`, `Modules/Probe.lua`)
- https://github.com/linman0x90/dgks (`dgks.lua`; commits `3aa7642`, `82a9198`, `4f6da89`, `b3f7875`)
- https://github.com/IAmChills/HardcoreAchievements (`Forever/KillTracking.lua`, `Forever/LootKills.lua`)
- https://github.com/AaronV-T/AutoBiographer (`Main.lua`, `Api.lua`)
- https://github.com/alwaysfilip/bloodfeud, https://github.com/dnl-gentile/olympus-addon,
  https://github.com/Decessuss/InTheBinKoS, https://github.com/saboya/dota-raid-tools,
  https://github.com/fol2/helloforever, https://github.com/thevariableK/Quantum-Seer

**Search summaries only (pages not reachable)**
- Blizzard ruleset article: https://news.blizzard.com/en-us/article/24302070/
- Icy Veins PvP overview: https://www.icy-veins.com/wow-forever/pvp-overview
- Wowhead news: https://www.wowhead.com/news=383292/how-pvp-progression-in-world-of-warcraft-forever
- Darkspear Islands: https://worldofwarcraft.blizzard.com/news/24307308
- Vendetta PvP: https://www.curseforge.com/wow/addons/vendetta-pvp
- WoWInterface thread: https://wowinterface.com/forums/showthread.php?p=345270
- warcraft.wiki.gg (`PARTY_KILL`, `UNIT_DIED`, Patch 1.60.1 notes)
