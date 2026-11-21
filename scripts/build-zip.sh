#!/usr/bin/env bash
# Build an install zip the way the release packager does, for testing in game
# before CI publishes releases.
#
#   scripts/build-zip.sh        # writes .release/EarCollector-dev-<commit>.zip
#
# It packages the committed files only (git ls-files), leaving out what
# .pkgmeta ignores (spec, scripts, types, art, ci, docs, CLAUDE.md, README.md)
# and every dotfile, and stamps the TOC version with the commit. Unzip it into
# World of Warcraft/_<flavor>_/Interface/AddOns/.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing tool: $1"; exit 1; }; }
need git
need zip

sha=$(git rev-parse --short HEAD)
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
	echo "note: uncommitted changes are not included (the zip has commit $sha)"
fi

out=.release
stage="$out/stage"
rm -rf "$stage"
mkdir -p "$stage/EarCollector"
git archive HEAD | tar -x -C "$stage/EarCollector"
(
	cd "$stage/EarCollector"
	rm -rf spec scripts types art ci docs CLAUDE.md README.md
	find . -name '.*' -not -name '.' -prune -exec rm -rf {} +
	sed -i "s/@project-version@/dev-$sha/" EarCollector.toc
	# Every file the TOC lists must be in the zip.
	grep -vE '^\s*(#|$)' EarCollector.toc | tr -d '\r' | while read -r f; do
		[ -f "${f//\\//}" ] || { echo "missing from zip: $f"; exit 1; }
	done
)
zipfile="$out/EarCollector-dev-$sha.zip"
rm -f "$zipfile"
(cd "$stage" && zip -qr "../$(basename "$zipfile")" EarCollector)
rm -rf "$stage"
echo "$zipfile"
