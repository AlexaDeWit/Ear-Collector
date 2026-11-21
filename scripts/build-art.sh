#!/usr/bin/env bash
# Repaint the ear textures in Media/Ears/ from art/paint_ears.py, the source of
# the art. Run after changing it, and commit both. The `art` step of
# scripts/check.sh fails if the painter changed without a rebuild.
#
# Needs python3 with numpy and Pillow. The output is deterministic (fixed seed).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

SIZE=128 # twice Blizzard's 64x64 icons, so detail survives at the pouch's slot size

rm -f Media/Ears/*.tga
python3 art/paint_ears.py Media/Ears "$SIZE"
{
	echo "size $SIZE"
	echo "source $(sha256sum art/paint_ears.py | cut -d' ' -f1) art/paint_ears.py"
	for tga in Media/Ears/*.tga; do
		echo "texture $(basename "$tga" .tga)"
	done
} >Media/Ears/manifest.txt
rm -f Media/Ears/sources.sha256
echo "Wrote Media/Ears/*.tga and Media/Ears/manifest.txt"
