#!/usr/bin/env bash
# Install the headless toolchain that scripts/check.sh uses. Idempotent: every
# step is skipped when its pinned version is already present.
#
#   scripts/setup-tools.sh              # tools + WoW API data (Ubuntu/Debian; root or sudo)
#   scripts/setup-tools.sh --data-only  # only the WoW API data into .cache/ (any OS with git+curl)
#
# Used by the SessionStart hook (cloud sessions), CI, and humans on Ubuntu.
# Network: Ubuntu apt mirrors, github.com release downloads and git fetches.
# It deliberately avoids luarocks.org, which Claude Code's default cloud
# network allowlist does not include.
set -euo pipefail

# Pinned versions. Bump deliberately, in one commit, and let CI confirm.
LUALS_VERSION="3.19.2"
STYLUA_VERSION="2.6.0"
# Ketho/vscode-wow-api: LuaLS annotations for the WoW API (Retail/Mainline engine).
WOW_API_COMMIT="d0b5b51fac4c52c493371b9b18e66ce604ea4326"
# Gethe/wow-ui-source, `forever` branch (WoW Forever 1.60.1.71037): Blizzard's own
# generated API docs (the authoritative event list) and UI.xsd.
WOW_UI_SOURCE_COMMIT="734f065329cff4992835b01a84f210a297db91b6"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE="$ROOT/.cache"
PREFIX="${TOOLS_PREFIX:-/usr/local}"
SUDO=""
[ "$(id -u)" -eq 0 ] || SUDO="sudo"

log() { printf '[setup-tools] %s\n' "$*" >&2; }

install_apt() {
	local need=()
	command -v lua5.1 >/dev/null || need+=(lua5.1)
	command -v luacheck >/dev/null || need+=(lua-check)
	command -v busted >/dev/null || need+=(lua-busted)
	command -v xmllint >/dev/null || need+=(libxml2-utils)
	command -v unzip >/dev/null || need+=(unzip)
	command -v jq >/dev/null || need+=(jq)
	[ ${#need[@]} -eq 0 ] && return 0
	log "apt-get install ${need[*]}"
	$SUDO apt-get update -qq
	$SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends "${need[@]}" >/dev/null
}

install_luals() {
	local dir="$PREFIX/lib/lua-language-server-$LUALS_VERSION" wrapper="$PREFIX/bin/lua-language-server"
	if [ ! -x "$dir/bin/lua-language-server" ]; then
		log "lua-language-server $LUALS_VERSION"
		local tmp
		tmp="$(mktemp -d)"
		curl -fsSL --retry 3 -o "$tmp/luals.tgz" \
			"https://github.com/LuaLS/lua-language-server/releases/download/$LUALS_VERSION/lua-language-server-$LUALS_VERSION-linux-x64.tar.gz"
		$SUDO mkdir -p "$dir"
		$SUDO tar -xzf "$tmp/luals.tgz" -C "$dir"
		rm -rf "$tmp"
	fi
	if ! grep -qs "$dir" "$wrapper"; then
		$SUDO mkdir -p "$PREFIX/bin"
		printf '#!/bin/sh\nexec "%s/bin/lua-language-server" "$@"\n' "$dir" | $SUDO tee "$wrapper" >/dev/null
		$SUDO chmod 0755 "$wrapper"
	fi
}

install_stylua() {
	if stylua --version 2>/dev/null | grep -qx "stylua $STYLUA_VERSION"; then return 0; fi
	log "stylua $STYLUA_VERSION"
	local tmp
	tmp="$(mktemp -d)"
	curl -fsSL --retry 3 -o "$tmp/stylua.zip" \
		"https://github.com/JohnnyMorganz/StyLua/releases/download/v$STYLUA_VERSION/stylua-linux-x86_64.zip"
	unzip -q -o "$tmp/stylua.zip" -d "$tmp"
	$SUDO mkdir -p "$PREFIX/bin"
	$SUDO install -m 0755 "$tmp/stylua" "$PREFIX/bin/stylua"
	rm -rf "$tmp"
}

# git fetch of one pinned commit. Works where GitHub archive/API downloads are
# refused (cloud sessions only allow git and release assets for unattached repos).
fetch_commit() { # fetch_commit <dir> <repo url> <commit> [sparse paths...]
	local dir="$1" url="$2" commit="$3"
	shift 3
	[ "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" = "$commit" ] && return 0
	log "$(basename "$url" .git) @ ${commit:0:7}"
	rm -rf "$dir"
	mkdir -p "$dir"
	git -C "$dir" init -q
	if [ $# -gt 0 ]; then
		git -C "$dir" sparse-checkout set --no-cone "$@"
		git -C "$dir" fetch -q --depth 1 --filter=blob:none "$url" "$commit"
	else
		git -C "$dir" fetch -q --depth 1 "$url" "$commit"
	fi
	git -C "$dir" -c advice.detachedHead=false checkout -q FETCH_HEAD
}

if [ "${1:-}" != "--data-only" ]; then
	install_apt
	install_luals
	install_stylua
fi
fetch_commit "$CACHE/wow-api" https://github.com/Ketho/vscode-wow-api.git "$WOW_API_COMMIT"
fetch_commit "$CACHE/wow-ui-source" https://github.com/Gethe/wow-ui-source.git "$WOW_UI_SOURCE_COMMIT" \
	'/version.txt' \
	'/Interface/AddOns/Blizzard_APIDocumentationGenerated/' \
	'/Interface/AddOns/Blizzard_SharedXML/UI.xsd'
