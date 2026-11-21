#!/usr/bin/env bash
# Every headless check for the addon. Contributors and CI both run this.
#
#   scripts/check.sh                  # all steps; non-zero exit if any fails
#   scripts/check.sh --fix            # format with StyLua first, then check
#   scripts/check.sh luacheck test    # only the named steps
#
# Steps: syntax toc luacheck names luals xml art format test
# Missing tools or data? Run scripts/setup-tools.sh.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

CACHE=.cache
ANNOTATIONS="$CACHE/wow-api/Annotations/Core"
BLIZZARD_DOCS="$CACHE/wow-ui-source/Interface/AddOns/Blizzard_APIDocumentationGenerated"
UI_XSD="$CACHE/wow-ui-source/Interface/AddOns/Blizzard_SharedXML/UI.xsd"
LUA="$(command -v lua5.1 || command -v lua || true)"
FIX=0
STEPS=()
for a in "$@"; do
	case "$a" in
	--fix) FIX=1 ;;
	-h | --help)
		sed -n '2,9p' "$0"
		exit 0
		;;
	*) STEPS+=("$a") ;;
	esac
done
[ ${#STEPS[@]} -eq 0 ] && STEPS=(syntax toc luacheck names luals xml art format test)

# Plain output (no colour codes) unless stdout is a terminal.
if [ -t 1 ]; then decolor() { cat; }; else decolor() { sed 's/\x1b\[[0-9;]*m//g'; }; fi

# Files: tracked plus new untracked ones, minus ignored (.cache etc).
list() { # list <extension>
	if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
		git ls-files --cached --others --exclude-standard -- "*.$1" | while read -r f; do [ -f "$f" ] && echo "$f"; done
	else
		find . \( -path ./.cache -o -path ./.git \) -prune -o -type f -name "*.$1" -print | sed 's|^\./||'
	fi
}
LUA_FILES=$(list lua)
ADDON_LUA=$(printf '%s\n' "$LUA_FILES" | grep -vE '^(spec|scripts|types|\.github|\.claude)/|^\.' || true)
XML_FILES=$(list xml | grep -vE '^(spec|scripts|\.github)/' || true)

need() {
	for t in "$@"; do
		if ! command -v "$t" >/dev/null 2>&1; then
			echo "missing tool: $t (run scripts/setup-tools.sh)"
			return 1
		fi
	done
}
need_data() {
	for d in "$@"; do
		if [ ! -e "$d" ]; then
			echo "missing $d (run scripts/setup-tools.sh, or scripts/setup-tools.sh --data-only)"
			return 1
		fi
	done
}

step_syntax() {
	need luac5.1 || return 1
	[ -z "$LUA_FILES" ] && return 0
	# shellcheck disable=SC2086
	luac5.1 -p $LUA_FILES
}
step_toc() { need lua5.1 && "$LUA" scripts/check_toc.lua .; }
step_luacheck() { need luacheck && luacheck --formatter plain --codes --no-color .; }
step_names() {
	need lua5.1 && need_data "$ANNOTATIONS" "$BLIZZARD_DOCS" || return 1
	[ -z "$ADDON_LUA" ] && return 0
	# shellcheck disable=SC2086
	"$LUA" scripts/check_wow_names.lua "$ANNOTATIONS" "$BLIZZARD_DOCS" $ADDON_LUA
}
step_luals() {
	need lua-language-server && need_data "$ANNOTATIONS" || return 1
	local logdir out rc
	logdir="$(mktemp -d)"
	out="$(lua-language-server --check="$PWD" --configpath="$PWD/.luarc.json" \
		--checklevel=Warning --logpath="$logdir" 2>&1)"
	rc=$?
	rm -rf "$logdir"
	# Drop the progress bar; keep diagnostics and the summary line.
	printf '%s\n' "$out" | tr '\r' '\n' | grep -vE '^(Initializing|>+ )|^[[:space:]]*$' | decolor
	return $rc
}
step_xml() {
	[ -z "$XML_FILES" ] && return 0
	need xmllint || return 1
	# Bindings.xml has its own format (no schema ships with the UI source):
	# check that it is well-formed. Everything else must validate against UI.xsd.
	local ui_xml rc=0
	ui_xml=$(printf '%s\n' "$XML_FILES" | grep -v '^Bindings\.xml$' || true)
	if printf '%s\n' "$XML_FILES" | grep -qx 'Bindings.xml'; then
		xmllint --noout Bindings.xml || rc=1
	fi
	if [ -n "$ui_xml" ]; then
		need_data "$UI_XSD" || return 1
		# shellcheck disable=SC2086
		xmllint --noout --schema "$UI_XSD" $ui_xml 2>&1 | grep -v ' validates$'
		[ "${PIPESTATUS[0]}" -eq 0 ] || rc=1
	fi
	return $rc
}
step_art() { need lua5.1 sha256sum && "$LUA" scripts/check_art.lua; }
step_format() {
	need stylua || return 1
	if [ "$FIX" = 1 ]; then stylua . && return 0; fi
	stylua --check . || {
		echo "(run scripts/check.sh --fix to apply)"
		return 1
	}
}
step_test() {
	need busted || return 1
	if [ -t 1 ]; then
		busted
	else
		busted -o plainTerminal | decolor
		return "${PIPESTATUS[0]}"
	fi
}

FAILED=()
for s in "${STEPS[@]}"; do
	if ! declare -F "step_$s" >/dev/null; then
		echo "unknown step: $s"
		exit 2
	fi
	echo "==> $s"
	if "step_$s"; then echo "    ok: $s"; else
		FAILED+=("$s")
		echo "    FAILED: $s"
	fi
done

echo
if [ ${#FAILED[@]} -eq 0 ]; then
	echo "All checks passed (${STEPS[*]})."
	echo "Not covered: anything that needs the game client. See docs/in-game-tests.md."
else
	echo "Failed: ${FAILED[*]}"
	exit 1
fi
