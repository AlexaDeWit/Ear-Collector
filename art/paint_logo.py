"""Paint the Ear Collector logo: a painted ear on a dark medallion with a gold rim.

It reuses the ear painter, so the logo matches the ears in the pouch.

Usage: python3 art/paint_logo.py <out.png>
Needs numpy and Pillow.
"""
import sys

import numpy as np
from PIL import Image

import paint_ears as pe

S = pe.S  # 512: the painter's working size, and the logo's
EAR = ("human", 1)  # the human ear the addon uses as its icon (Media/Ears/human-2)
EAR_SIZE = 0.80  # of the canvas


def background():
    """Dark red leather in a gold ring, in linear RGB."""
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    d = np.sqrt((xx - S / 2) ** 2 + (yy - S * 0.45) ** 2) / (S / 2)
    centre, edge = pe.srgb_to_linear("#5a1a14"), pe.srgb_to_linear("#140807")
    t = np.clip(d, 0, 1)[..., None] ** 1.4
    leather = centre * (1 - t) + edge * t
    grain = 0.88 + 0.24 * pe.value_noise(96, 0.6)
    rgb = leather * grain[..., None]
    ring = pe.torus(S / 2, S / 2, S * 0.455, S * 0.022, "#c79a3c")
    a = ring.alpha[..., None]
    return ring.rgb * a + rgb * (1 - a)


def main():
    out = sys.argv[1]
    race, tone = EAR
    image = Image.fromarray((pe.linear_to_srgb(background()) * 255 + 0.5).astype(np.uint8), "RGB").convert("RGBA")
    ear = pe.render(race, pe.TONES[race][tone])
    size = int(S * EAR_SIZE)
    ear = ear.resize((size, size), Image.LANCZOS)
    image.alpha_composite(ear, ((S - size) // 2, (S - size) // 2))
    image.convert("RGB").save(out)
    print(out)


if __name__ == "__main__":
    main()
