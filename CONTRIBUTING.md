# Contributing

How we work on Ear Collector: the contribution process, the repository's
requirements, and the rules the code follows. How the addon works is in
[`docs/architecture.md`](docs/architecture.md).

## Working language

Write issues and discussion in **English**, so the next person with the same
problem can find them. Rough English is welcome, and so is your own language
run through a translator. If English is a real barrier, I also read **French**
and **Swedish**. Source code, identifiers, comments, and commit messages stay
in English.

## Development

The tools install on Ubuntu or another Debian-based Linux:

```bash
scripts/setup-tools.sh   # the pinned toolchain and Blizzard's Forever API data
scripts/check.sh         # every check: lint, types, art, format, tests
```

`scripts/check.sh` must pass before you push, and CI runs the same command.
[`docs/testing.md`](docs/testing.md) explains each step and the fake game client
the specs run against.

To run your working copy in the game, link the checkout into the client's
AddOns folder under the name `EarCollector`:

```bash
ln -s "$PWD" "/path/to/WoW Forever/Interface/AddOns/EarCollector"
```

Each CI run also attaches an installable zip to its summary page.
`scripts/build-zip.sh` builds the same zip locally, and
`scripts/build-art.sh` repaints the ear textures ([`docs/art.md`](docs/art.md)).

What the headless checks can't see, a person checks in the game with
[`docs/in-game-tests.md`](docs/in-game-tests.md).

## Rules for the code

These bind everyone, human or agent. The mechanisms behind them are in
[`docs/architecture.md`](docs/architecture.md).

- **No error reaches the player.** Run every entry point (event handler, slash
  command, timer, script, hook) through `Errors.Call` or `Errors.Wrap`, under a
  name narrow enough that switching it off breaks nothing else. Then prevent the
  error anyway: check `Context.Readable` before touching any value from the
  game, check every API return for nil, and expect saved data to be damaged.
  Every new failure path gets a spec.
- **No taint.** Don't write to Blizzard globals or frames, don't call protected
  functions, and don't replace Blizzard functions (use `hooksecurefunc`). The
  one sanctioned write is the pouch's entry in `UISpecialFrames`.
- **No frame-time cost.** No `OnUpdate` polling, no high-frequency event without
  a reason, and a bound on every saved log.
- **Nothing leaves the player's screen.** Ear Collector never sends chat,
  emotes, whispers or addon messages. Any sharing feature needs the
  maintainer's agreement and must be opt-in.
- **Saved data changes in place.** `ns.db`'s fields are the saved tables, so
  modify them rather than reassign them.
- **Every release loads every earlier save, and leaves a newer one intact.**
  Add saved fields; never rename, retype or reuse one. A change of shape is a
  numbered migration step with a saved-file fixture. The rules are in
  [`docs/architecture.md`](docs/architecture.md#changing-whats-saved).
- **WoW Forever only.** Interface `16001`, no Classic or Retail TOCs. The API
  facts the code relies on are in [`docs/forever-api.md`](docs/forever-api.md).
- **WoW's Lua is 5.1** without `io`, `require`, `dofile`, `loadfile`, `package`
  or `debug`. Specs and scripts may use them, addon code may not.
- Write `---@type Frame` above `CreateFrame` results, and pass event names as
  string literals (`ns.On("PARTY_KILL", fn)`) so the `names` check sees them.

## Keeping the code small

Someone should be able to fork this and find their way in an afternoon.

- **One concern per file.** A file nearing 300 lines usually holds two things:
  split it. A new pouch tab is its own file and registers with `Pouch.AddTab`,
  like the others. Nothing gets special-cased into the window.
- **Decisions in `Core/`, the game in `Detectors/` and `UI/`.** A rule that
  decides something is a plain function a spec can call. The code that reads
  the game or draws a frame stays thin around it.
- **Short comments that say why.** A file opens with a few lines on what it is
  and anything a reader must not miss. Comment the reason behind non-obvious
  code, never what the next line does, and never the history of how it got
  there.
- **One home for each fact.** Design rationale lives in
  [`docs/architecture.md`](docs/architecture.md), and game behaviour in
  [`docs/forever-api.md`](docs/forever-api.md), naming the Blizzard file it
  comes from. Code links there instead of restating it.
- **Game facts are checked, not assumed.** Confirm an API's arguments, returns
  and restrictions in Blizzard's Forever source before relying on them, and mark
  what only play can confirm as *Needs the game* until it has been seen.
- **One event, one result.** The game often reports one thing twice (a death
  fires `UNIT_DIED` and `PARTY_KILL`). Decide which signal owns it, and give the
  spec both signals.
- **Every decision is traced.** A choice that makes or withholds an ear or a
  death record goes through `ns.Trace` (or `ns.TraceRoutine` for things that
  never count), so `/ears debug` explains it in play.

## Tests

[`docs/testing.md`](docs/testing.md) has the details.

- **A rule's spec fails without the rule.** After adding one, break it on
  purpose (flip a comparison, drop a guard) and check a spec goes red. If none
  does, the spec isn't testing the rule.
- **Assert only what the rule promises.** Compare sets when order isn't part of
  it, and check every effect: a duplicate can hide in a repeat count while the
  number of ears looks right.
- **Shared helpers live in `spec/support/`.** If a second spec file needs the
  same helper, move it there instead of copying it.
- **The fake client follows the game.** A stub returns what Blizzard's docs
  say, in their order. When play shows the fake was wrong, fix the fake first,
  then the code.

## AI-assisted contributions

AI-assisted work is welcome, but the bar does not change. **You are the
author. You must understand and be able to explain every line. The
contribution must be worth more than the time it takes to review.** We close
low-effort, unreviewed AI output ("slop").

- **Disclose non-trivial AI use**. Editor autocomplete needs no disclosure.
  AI-generated or substantially AI-shaped code, prose, or commits do. Add an
  `Assisted-by:` git trailer that names the tool, for example
  `Assisted-by: <Agent Name> (<Vendor>)`, and mention it in the PR. The
  trailer records a tool that helped. You remain the sole author, so it is
  **not** `Co-authored-by:`. The exception is a commit an agent made under its
  own git identity: the squash merge credits it with a `Co-authored-by:` line,
  which stays.
- **Verify before you file**. Never open an issue that an AI produced and you
  have not reproduced yourself.

## Developer Certificate of Origin (DCO)

We accept contributions under the **[Developer Certificate of Origin](DCO)**
(DCO, v1.1): a per-commit affirmation that you have the right to submit your
work under the project's [MIT licence](LICENSE). It asks you only to certify
provenance, and grants the project no power to relicense or close the code.

**Sign off every commit**. `git commit -s` appends a `Signed-off-by` trailer
from your git identity:

```
Signed-off-by: Your Name <you@example.com>
```

- **Every commit in a PR** needs a `Signed-off-by` that matches its author.
- It is **separate from the GPG signature**. `-S` proves who committed. `-s`
  certifies your right to contribute. Use both: `git commit -S -s`.
- **Forgot one?** `git commit --amend -s --no-edit` fixes the last commit.
  `git rebase --signoff main` signs off a whole branch.

## Pull requests

Pull requests are squash-merged. The title becomes the commit subject on
`main`, so write it as a Conventional Commit, and the commit messages become its
body, so keep them worth reading. Open as a draft while work or review is
moving, and mark it ready when it is not. The body is three headings, **What** (the goal), **Why** (the
motivation), and **Consequences** (player-visible changes, trade-offs, one
sentence each, and the section goes when there are none), plus a one-line
AI-assistance disclosure. The template has them.

A reviewer reads the body before the diff, so write it so someone who has not
opened the diff understands the change on its own. Lead with what a player or
reviewer gains. The mechanism comes second, and only as far as the diff does
not already show it. No play-by-play of files, and no checklists: CI enforces
its own. When a change needs testing in the game, say which steps of
[`docs/in-game-tests.md`](docs/in-game-tests.md) apply. End with `Closes #NNN`
where an issue completes.

## Repository requirements

- **Use [Conventional Commits](https://www.conventionalcommits.org/)**.
  Subjects are `type(scope): summary`, where `type` is one of `feat`, `fix`,
  `docs`, `chore`, `ci`, `refactor`, `test`, `build`, `perf`. The scope is
  optional. Keep the summary short and imperative.
- **Commits are GPG-signed, DCO signed off, and AI-disclosed** (see above).
- **`main` takes changes through pull requests only**, squash-merged, with both
  CI jobs passing on an up-to-date branch.
- **Pin every GitHub Action to a full commit SHA**, with the version in a
  trailing comment.
- **Keep workflows injection-free**. Never interpolate untrusted
  `${{ github.event.* }}` or `${{ github.head_ref }}` into `run:` blocks. Pass
  them through `env:`.
- **Keep secrets in the `release` environment**, never at the repository level.
  Pass a secret only to the step that needs it, never to a whole job or a
  called workflow. Never use `pull_request_target`.

## Releases

Releases are maintainer territory. A signed tag publishes one:

```bash
git tag -s v1.0.0 -m "Ear Collector 1.0.0"
git push origin v1.0.0
```

The release workflow runs every check. Then the
[BigWigs packager](https://github.com/BigWigsMods/packager) builds
`EarCollector-<tag>-forever.zip`, uploads it to CurseForge, and attaches it to a
GitHub Release. Tags can't be moved or deleted, so a bad release gets a new
version. A tag containing `alpha` or `beta` (`v1.0.0-beta1`) makes a GitHub
pre-release and a CurseForge file of that type.

The CurseForge upload goes first. If it fails, the packager stops before the
GitHub Release. Re-run the failed job, because the tag is still good.

CurseForge finds the project from `## X-Curse-Project-ID` in the TOC. The API
token is `CURSE_PUBLICATION_SECRET` in the `release` environment, which only
`v*` tags can deploy to. Wago would need `## X-Wago-ID` in the TOC and a
`WAGO_API_TOKEN` secret in the same environment, passed to the packager step.
