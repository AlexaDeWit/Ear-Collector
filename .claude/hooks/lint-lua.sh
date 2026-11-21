#!/usr/bin/env bash
# PostToolUse hook (Edit|Write): run luacheck on the .lua file Claude just
# changed. Exit 2 shows the findings to Claude right away; the full suite is
# still scripts/check.sh.
command -v jq >/dev/null && command -v luacheck >/dev/null || exit 0
file="$(jq -r '.tool_input.file_path // empty')"
case "$file" in *.lua) ;; *) exit 0 ;; esac
[ -f "$file" ] || exit 0
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0
if ! out="$(luacheck --formatter plain --codes --no-color "$file" 2>&1)"; then
	printf 'luacheck found problems in the file you just edited:\n%s\n' "$out" >&2
	exit 2
fi
exit 0
