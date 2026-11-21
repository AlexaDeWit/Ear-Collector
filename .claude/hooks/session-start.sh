#!/usr/bin/env bash
# SessionStart hook: make the check toolchain available in Claude Code cloud
# sessions. Local sessions are left alone (install tools yourself; see CLAUDE.md).
# Always exits 0 so a network hiccup never blocks the session; stdout is added
# to Claude's context, so it says plainly whether the tools are ready.
set -uo pipefail
[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

if out="$(scripts/setup-tools.sh 2>&1)"; then
	echo "WoW addon check tools are installed. Run scripts/check.sh before calling work done."
else
	echo "WARNING: scripts/setup-tools.sh failed, so some scripts/check.sh steps will report missing tools."
	echo "Last output:"
	printf '%s\n' "$out" | tail -n 15
fi
exit 0
