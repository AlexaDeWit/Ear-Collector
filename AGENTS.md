# Agent instructions

The constitution for agents working on Ear Collector. These are requirements, not
suggestions.

## Start here

- **Read [`README.md`](README.md) first**: what the addon does and how players use it.
- **Escalate, don't guess.** Stop on an ambiguous, missing, or contradictory
  requirement instead of inventing a way through it.
- **The tracker is the plan.** Open issues hold the backlog, the decisions
  waiting on the maintainer, and the in-game results so far.
- **The game can't run here.** Headless checks are the floor. Whatever only the
  game can show goes to the maintainer as steps from
  [`docs/in-game-tests.md`](docs/in-game-tests.md), and their results come back
  as `/ears debug` logs.

| Work | Read next |
|---|---|
| Change detection, grading or saved data | [`docs/architecture.md`](docs/architecture.md), then [`docs/forever-api.md`](docs/forever-api.md) |
| Change what's saved, or how it loads | [`docs/architecture.md`](docs/architecture.md#changing-whats-saved), then [`docs/testing.md`](docs/testing.md#saved-files-from-past-releases) |
| Call a game API or hook the interface | [`docs/forever-api.md`](docs/forever-api.md) |
| Add or change specs, or turn a debug log into a fixture | [`docs/testing.md`](docs/testing.md) |
| Change the ear art | [`docs/art.md`](docs/art.md) |
| Ask the maintainer to test something in game | [`docs/in-game-tests.md`](docs/in-game-tests.md) |
| Commit or open a PR | [`CONTRIBUTING.md`](CONTRIBUTING.md) and the PR template |

## Invariants

- **The rules in [`CONTRIBUTING.md`](CONTRIBUTING.md#rules-for-the-code) are
  binding**: no error reaches the player, no taint, no frame-time cost, nothing
  leaves the player's screen. So are
  [Keeping the code small](CONTRIBUTING.md#keeping-the-code-small) and
  [Tests](CONTRIBUTING.md#tests).
- **Leave it smaller than you found it.** Before calling work done, reread
  your diff for comments that restate code or docs, helpers copied between
  files, and files that grew a second concern.
- **Local verification**: `scripts/check.sh` passes before you call work done.
  A "missing tool" message means `scripts/setup-tools.sh`, which the
  SessionStart hook runs in cloud sessions.
- **Fix the cause of a finding.** Suppressions need the maintainer's agreement.
- **Report what you verified.** Say what passed headlessly and what needs the
  game, with the in-game steps.

## Documentation

- Write for a player or maintainer with a concrete task. Docs state how things
  are, not how they came to be.
- Keep plans and task status in the tracker. Keep review and verification
  records in commit messages or PR discussion.
- Do not commit session transcripts, handoff notes, temporary review artifacts,
  or prose that only justifies the agent's work.
- Keep each explanation in one home and link to it.
- When behaviour changes, update or remove the documentation it makes stale, in
  the same PR.
- Write prose, comments, commits and PRs in Canadian English (`behaviour`,
  `colour`, `licence` as a noun). Plain words, active voice, no em-dashes or
  en-dashes. Identifiers, Blizzard's API names and the game's own terms
  ("honor", "honorable kill") keep their spelling.
- Instructions for the maintainer are concrete steps a player can follow: what
  to type, what they should see, what to send back. No implementation terms.

## Cloud sessions

- GitHub refuses changes under `.github/workflows/` from a cloud session, which
  lacks the `workflow` permission. Put the new file in `ci/workflows/`, say in
  the PR where it goes, and ask the maintainer to move it.
- The maintainer takes test builds from CI. Don't send zips.
- A cloud session can't GPG-sign commits or sign off for the maintainer. Its
  commits carry the `Assisted-by:` trailer. When the maintainer squash-merges,
  GitHub adds a `Co-authored-by:` line for the session's git identity, and
  that's expected.

## Commit and PR

Per [`CONTRIBUTING.md`](CONTRIBUTING.md): Conventional Commits, and non-trivial
AI help disclosed with an `Assisted-by:` trailer. Agents never merge or push to
`main`. One branch and one PR per piece of work, and the maintainer
squash-merges it, so the PR title becomes the commit subject on `main`: write it
as a Conventional Commit.
