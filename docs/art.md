# Ear art

Every ear in the pouch is a painted texture, one per race and skin tone. A
script paints them, so the art is code you can review and rebuild.

## How the painter works

`art/paint_ears.py` paints each ear procedurally with numpy and Pillow. It uses
a fixed seed, so a rebuild is byte-identical.

1. Anatomy is a set of control points: outline, helix rim, antihelix, concha,
   canal, tragus, antitragus and lobe. The shapes become a height map.
2. The height map is lit from the top left: normals, diffuse and specular light,
   ambient occlusion, and translucency at thin edges.
3. Skin mottling and pores go on top, then an outline for legibility and blood
   along the severed edge.
4. Race features are separately lit layers: rings, the gnome's gear, undead
   stitches, the Skyborne feather, the dwarf braid, tauren fur and beads.

Each race comes in four skin tones (`TONES`: fur colours for tauren, and dwarf
hair varies too), plus a generic ear.

## Building

```bash
scripts/build-art.sh
```

It writes `Media/Ears/<race>-<tone>.tga` and `generic.tga` (128x128, uncompressed
32-bit) and `Media/Ears/manifest.txt` (size, painter hash, texture list). Commit
the textures and the manifest with the painter change. The `art` check fails on
a stale, missing or malformed texture.

To look at full-size renders while you work:

```bash
python3 art/paint_ears.py /tmp/ears 128 --preview /tmp/ears/png
```

## In the addon

- `UI/Art.lua` maps race tokens to files (`Scourge` is `undead`).
- The game doesn't expose skin tone, so `Art.Tone(guid)` picks one from a hash of
  the victim's GUID. Tones look random across players and stay the same for each
  player. `Art.TONES` must match the painter, and a spec checks it.
- Pouch slots show the ear art. Tooltips and chat lines use Blizzard's race
  icons. The minimap drawer icon is `Media/Ears/human-2`.
