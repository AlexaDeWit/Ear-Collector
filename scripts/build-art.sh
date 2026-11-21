#!/usr/bin/env bash
# Rebuild the ear textures in Media/Ears/ from the SVG sources in art/ears/.
# Run after changing any SVG, and commit both. The `art` step of
# scripts/check.sh fails if a source changed without a rebuild.
#
# Needs node with Playwright (preinstalled in Claude Code cloud sessions) and
# python3 with Pillow.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

SIZE=64      # Blizzard's own icons are 64x64
RENDER=256   # render larger, then downscale for clean edges
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

node scripts/render-ears.js art/ears "$tmp" "$RENDER"
python3 scripts/png-to-tga.py "$tmp" Media/Ears "$SIZE"
(cd art/ears && sha256sum -- *.svg) >Media/Ears/sources.sha256
echo "Wrote Media/Ears/*.tga and Media/Ears/sources.sha256"
