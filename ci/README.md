# Workflows waiting to be enabled

GitHub only lets a token with the `workflow` permission create files in
`.github/workflows/`, and the Claude Code session that wrote this scaffold
doesn't have it. These two files belong there:

| File here | Move to |
|---|---|
| `ci/workflows/ci.yml` | `.github/workflows/ci.yml` |
| `ci/workflows/release.yml` | `.github/workflows/release.yml` |

On GitHub: open each file, click the pencil (Edit), and change the file name
box to `.github/workflows/ci.yml` (backspace at the start of the box to move up
a folder). Or, from a local clone:

```bash
git mv ci/workflows .github/workflows && git rm ci/README.md && git commit -m "Enable CI workflows" && git push
```

Then delete this `ci/` folder.
