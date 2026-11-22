"""Paint the Ear Collector ear icons: one per WoW Forever race, plus a generic ear.

This program is the source of the art. scripts/build-art.sh runs it and writes
Media/Ears/*.tga (128x128, 32-bit) plus a manifest the `art` check uses.

How an ear is painted, at 512x512 before downscaling:
  1. Anatomy as shapes: the outline, the rolled rim (helix), the Y-shaped inner
     ridge (antihelix), the bowl (concha), the canal, the flaps in front of and
     below it (tragus, antitragus) and the lobe.
  2. The shapes become a height map: raised ridges, sunken bowl, soft blurs.
  3. Lighting from the top left: surface normals from the height map, diffuse
     and specular light, ambient occlusion in the folds, and redder skin where
     the ear is thin (translucency).
  4. Skin detail: mottling and pores, an outline for legibility, and blood
     along the severed edge (these are trophies).
  5. Race features as separately lit layers: metal rings, a gear stud, an
     undead seam with stitches, a feather, a braid, tauren fur.

Each race comes in a few tones (TONES): Media/Ears/<race>-<n>.tga.

Usage: python3 art/paint_ears.py <out dir> <size> [--preview <png dir>]
Needs numpy and Pillow.
"""
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

S = 512  # working size
SS = 2  # supersampling for masks
RNG = np.random.default_rng(20261121)  # fixed seed: rebuilds are identical

# ---------------------------------------------------------------- helpers


def srgb_to_linear(hex_color):
    c = np.array([int(hex_color[i : i + 2], 16) / 255 for i in (1, 3, 5)], dtype=np.float32)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def scale_hex(hex_color, factor):
    """A lighter (>1) or darker (<1) version of an sRGB hex colour."""
    rgb = [min(255, int(int(hex_color[i : i + 2], 16) * factor)) for i in (1, 3, 5)]
    return "#%02x%02x%02x" % tuple(rgb)


def linear_to_srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055)


def catmull(points, closed=True, steps=20):
    """Smooth curve through control points. A repeated point makes a sharp tip."""
    pts = [np.array(p, dtype=np.float64) for p in points]
    n = len(pts)
    out = []
    segments = range(n) if closed else range(n - 1)
    for i in segments:
        p0 = pts[(i - 1) % n] if closed else pts[max(i - 1, 0)]
        p1 = pts[i]
        p2 = pts[(i + 1) % n] if closed else pts[i + 1]
        p3 = pts[(i + 2) % n] if closed else pts[min(i + 2, n - 1)]
        for t in np.linspace(0, 1, steps, endpoint=False):
            t2, t3 = t * t, t * t * t
            out.append(
                0.5
                * (
                    2 * p1
                    + (-p0 + p2) * t
                    + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                    + (-p0 + 3 * p1 - 3 * p2 + p3) * t3
                )
            )
    if not closed:
        out.append(pts[-1])
    return [tuple(p) for p in out]


def _canvas():
    return Image.new("L", (S * SS, S * SS), 0)


def _finish(img):
    return np.asarray(img.resize((S, S), Image.LANCZOS), dtype=np.float32) / 255.0


def poly(points, smooth=True):
    img = _canvas()
    pts = catmull(points) if smooth else points
    ImageDraw.Draw(img).polygon([(x * SS, y * SS) for x, y in pts], fill=255)
    return _finish(img)


def ellipse(cx, cy, rx, ry, angle=0.0):
    a = math.radians(angle)
    pts = []
    for t in np.linspace(0, 2 * math.pi, 96, endpoint=False):
        x, y = rx * math.cos(t), ry * math.sin(t)
        pts.append((cx + x * math.cos(a) - y * math.sin(a), cy + x * math.sin(a) + y * math.cos(a)))
    return poly(pts, smooth=False)


def stroke(points, w0, w1=None, closed=False, profile=None):
    """A smooth stroke whose width tapers from w0 to w1, or follows profile(t) * w0."""
    w1 = w0 if w1 is None else w1
    pts = catmull(points, closed=closed, steps=40)
    img = _canvas()
    d = ImageDraw.Draw(img)
    for i, (x, y) in enumerate(pts):
        t = i / max(len(pts) - 1, 1)
        width = w0 * profile(t) if profile else w0 + (w1 - w0) * t
        r = width * SS / 2
        d.ellipse([x * SS - r, y * SS - r, x * SS + r, y * SS + r], fill=255)
    return _finish(img)


def blur(a, sigma):
    """Gaussian blur (separable, via FFT; no scipy needed)."""
    if sigma <= 0:
        return a
    pad = int(3 * sigma) + 1
    p = np.pad(a, pad, mode="edge")
    x = np.arange(-pad, pad + 1)
    k = np.exp(-(x**2) / (2 * sigma**2))
    k /= k.sum()
    for axis in (0, 1):
        n, m = p.shape[axis], len(k)
        length = n + m - 1
        shape = [1, 1]
        shape[axis] = -1
        r = np.fft.irfft(np.fft.rfft(p, length, axis=axis) * np.fft.rfft(k, length).reshape(shape), length, axis=axis)
        p = np.take(r, range((m - 1) // 2, (m - 1) // 2 + n), axis=axis)
    return p[pad:-pad, pad:-pad]


def value_noise(cells, sigma=0.0):
    grid = RNG.random((cells, cells)).astype(np.float32)
    img = Image.fromarray((grid * 255).astype(np.uint8)).resize((S, S), Image.BICUBIC)
    n = np.asarray(img, dtype=np.float32) / 255.0
    return blur(n, sigma) if sigma else n


def shift(a, dx, dy):
    return np.roll(np.roll(a, dy, axis=0), dx, axis=1)


def normalize(v):
    return v / np.maximum(np.linalg.norm(v, axis=-1, keepdims=True), 1e-6)


LIGHT = normalize(np.array([-0.55, -0.7, 0.85]))
HALF = normalize(LIGHT + np.array([0.0, 0.0, 1.0]))


def light(height, albedo, strength=95.0, ao=None, spec=0.25, shine=24.0, metal=False, ambient=0.30, diffuse=0.95):
    """Shade a height map. albedo is HxWx3 linear RGB. Returns linear RGB."""
    gy, gx = np.gradient(height)
    n = normalize(np.dstack([-gx * strength, -gy * strength, np.ones_like(height)]))
    ndl = np.clip(n @ LIGHT, 0, 1)
    ndh = np.clip(n @ HALF, 0, 1)
    occlusion = np.ones_like(height) if ao is None else ao
    color = albedo * (ambient * occlusion + diffuse * ndl * np.sqrt(occlusion))[..., None]
    highlight = (ndh**shine * spec * occlusion)[..., None]
    if metal:
        color = color + highlight * albedo * 2.2 + highlight * 0.35
    else:
        color = color + highlight * np.array([1.0, 0.96, 0.92])
    # A cool fill light from the bottom right keeps shadows from going flat.
    fill = np.clip(n @ normalize(np.array([0.6, 0.6, 0.5])), 0, 1)
    return color + albedo * (0.10 * fill)[..., None]


class Layer:
    def __init__(self, rgb, alpha):
        self.rgb, self.alpha = rgb, np.clip(alpha, 0, 1)


def over(layers):
    rgb = np.zeros((S, S, 3), dtype=np.float32)
    alpha = np.zeros((S, S), dtype=np.float32)
    for layer in layers:
        a = layer.alpha[..., None]
        rgb = layer.rgb * a + rgb * (1 - a)
        alpha = layer.alpha + alpha * (1 - layer.alpha)
    return rgb, alpha


# ---------------------------------------------------------------- anatomy


class Ear:
    """Control points for one ear (a right ear seen from the side; face on the left)."""

    def __init__(self, outline, helix, antihelix, concha, fossa, tragus, antitragus, canal, lobe, cut):
        self.outline, self.helix, self.antihelix = outline, helix, antihelix
        self.concha, self.fossa = concha, fossa
        self.tragus, self.antitragus, self.canal, self.lobe = tragus, antitragus, canal, lobe
        self.cut = cut

    def transformed(self, fn):
        def tp(points):
            return [fn(x, y) for x, y in points]

        def te(e):
            cx, cy = fn(e[0], e[1])
            scale = abs(fn(e[0] + 1, e[1])[0] - cx)
            return (cx, cy, e[2] * scale, e[3] * scale) + tuple(e[4:])

        return Ear(
            tp(self.outline),
            [(tp(p), w0, w1) for p, w0, w1 in self.helix],
            [(tp(p), w0, w1) for p, w0, w1 in self.antihelix],
            tp(self.concha),
            tp(self.fossa),
            te(self.tragus),
            te(self.antitragus),
            te(self.canal),
            te(self.lobe),
            tp(self.cut),
        )


FRONT = [(198, 225), (192, 270), (190, 315), (200, 350), (222, 380), (232, 418)]  # attachment to the face

HUMAN = Ear(
    outline=[(205, 175), (212, 120), (245, 78), (298, 60), (350, 80), (382, 130), (392, 195), (384, 262), (362, 322),
             (340, 372), (332, 420), (312, 460), (278, 472), (247, 455)] + FRONT[::-1][:1] + [(222, 380), (200, 350),
             (190, 315), (192, 270), (198, 225)],
    helix=[([(252, 238), (226, 205), (222, 150), (250, 106), (298, 86), (345, 103), (370, 145), (376, 200), (368, 262),
             (348, 318), (326, 364)], 30, 22)],
    antihelix=[([(292, 366), (318, 322), (334, 264), (332, 204)], 30, 24),
               ([(332, 206), (322, 158), (302, 120)], 22, 12),
               ([(332, 210), (296, 194), (252, 186)], 20, 12)],
    concha=[(252, 238), (300, 220), (322, 252), (318, 305), (292, 342), (252, 348), (224, 324), (220, 282), (232, 252)],
    fossa=[(304, 128), (322, 172), (300, 188), (266, 184), (284, 152)],
    tragus=(206, 302, 19, 31, -8),
    antitragus=(284, 356, 25, 15, -24),
    canal=(234, 296, 15, 21, 0),
    lobe=(286, 432, 42, 34, 0),
    cut=[(205, 178)] + FRONT + [(240, 445)],
)

ELF = Ear(
    outline=[(205, 185), (212, 140), (240, 108), (286, 92), (340, 72), (404, 40), (468, 12), (468, 12), (448, 50),
             (420, 96), (398, 150), (388, 210), (378, 270), (358, 325), (338, 372), (330, 420), (310, 458), (278, 470),
             (247, 455), (232, 420), (222, 382), (200, 352), (190, 316), (192, 272), (198, 228)],
    helix=[([(252, 238), (226, 206), (226, 160), (250, 126), (296, 108), (350, 88), (408, 58), (458, 24)], 30, 6),
           ([(452, 40), (426, 88), (402, 146), (390, 208), (380, 268), (360, 322), (336, 366)], 10, 22)],
    antihelix=[([(292, 366), (318, 322), (334, 264), (336, 206)], 30, 24),
               ([(336, 208), (348, 164), (380, 108), (420, 70)], 22, 8),
               ([(336, 212), (300, 196), (254, 188)], 20, 12)],
    concha=[(252, 238), (300, 222), (324, 254), (320, 306), (292, 344), (252, 350), (224, 326), (220, 284), (232, 254)],
    fossa=[(352, 150), (392, 102), (362, 160), (330, 190), (290, 190), (310, 172)],
    tragus=(206, 304, 19, 31, -8),
    antitragus=(284, 358, 25, 15, -24),
    canal=(234, 298, 15, 21, 0),
    lobe=(286, 432, 40, 32, 0),
    cut=[(205, 188)] + FRONT + [(240, 445)],
)

TROLL = Ear(
    outline=[(205, 185), (212, 140), (240, 112), (290, 102), (360, 106), (430, 118), (500, 140), (500, 140), (442, 176),
             (402, 216), (386, 268), (362, 325), (340, 372), (332, 420), (312, 458), (278, 470), (247, 455), (232, 420),
             (222, 382), (200, 352), (190, 316), (192, 272), (198, 228)],
    helix=[([(252, 238), (226, 206), (228, 162), (256, 130), (302, 120), (370, 124), (440, 136), (488, 144)], 30, 6),
           ([(480, 152), (440, 178), (404, 218), (388, 270), (364, 324), (338, 366)], 8, 22)],
    antihelix=[([(292, 366), (318, 322), (332, 264), (338, 212)], 30, 24),
               ([(338, 212), (382, 176), (440, 158)], 22, 8),
               ([(338, 216), (300, 200), (256, 192)], 20, 12)],
    concha=[(252, 240), (300, 224), (324, 256), (320, 306), (292, 344), (252, 350), (224, 326), (220, 284), (232, 256)],
    fossa=[(350, 190), (420, 160), (380, 190), (330, 200), (300, 198)],
    tragus=(206, 304, 19, 31, -8),
    antitragus=(284, 358, 25, 15, -24),
    canal=(234, 298, 15, 21, 0),
    lobe=(286, 432, 40, 32, 0),
    cut=[(205, 188)] + FRONT + [(240, 445)],
)

ORC = Ear(
    outline=[(205, 175), (212, 120), (245, 82), (298, 64), (360, 50), (422, 34), (422, 34), (400, 92), (390, 150),
             (388, 205), (380, 265), (360, 322), (340, 372), (332, 420), (312, 460), (278, 472), (247, 455), (232, 418),
             (222, 380), (200, 350), (190, 315), (192, 270), (198, 225)],
    helix=[([(252, 238), (226, 205), (222, 150), (250, 108), (300, 88), (362, 70), (412, 46)], 30, 8),
           ([(408, 58), (392, 104), (378, 152), (376, 205), (368, 262), (348, 318), (326, 364)], 10, 22)],
    antihelix=HUMAN.antihelix,
    concha=HUMAN.concha,
    fossa=HUMAN.fossa,
    tragus=HUMAN.tragus,
    antitragus=HUMAN.antitragus,
    canal=HUMAN.canal,
    lobe=HUMAN.lobe,
    cut=HUMAN.cut,
)

GNOME_BASE = Ear(
    outline=[(205, 175), (212, 120), (245, 80), (300, 60), (362, 58), (404, 52), (404, 52), (396, 112), (394, 190),
             (384, 262), (362, 322), (340, 372), (332, 420), (312, 460), (278, 472), (247, 455), (232, 418), (222, 380),
             (200, 350), (190, 315), (192, 270), (198, 225)],
    helix=[([(252, 238), (226, 205), (222, 150), (250, 106), (300, 84), (360, 76), (396, 64)], 30, 12),
           ([(392, 76), (384, 122), (378, 196), (368, 262), (348, 318), (326, 364)], 14, 22)],
    antihelix=HUMAN.antihelix,
    concha=HUMAN.concha,
    fossa=HUMAN.fossa,
    tragus=HUMAN.tragus,
    antitragus=HUMAN.antitragus,
    canal=HUMAN.canal,
    lobe=HUMAN.lobe,
    cut=HUMAN.cut,
)
GNOME = GNOME_BASE.transformed(lambda x, y: (290 + (x - 290) * 1.08, 262 + (y - 262) * 1.04))

# ---------------------------------------------------------------- painting


def ear_height(ear, notches=None):
    outline = poly(ear.outline)
    if notches:
        for tri in notches:
            outline = outline * (1 - poly(tri, smooth=False))
    h = 0.42 * outline
    for points, w0, w1 in ear.helix:
        h += 0.30 * blur(stroke(points, w0, w1), 5)
    for points, w0, w1 in ear.antihelix:
        h += 0.26 * blur(stroke(points, w0, w1), 6)
    h -= 0.16 * blur(poly(ear.fossa), 9)
    h -= 0.34 * blur(poly(ear.concha), 11)
    h -= 0.30 * blur(ellipse(*ear.canal), 5)
    h += 0.30 * blur(ellipse(*ear.tragus), 6)
    h += 0.22 * blur(ellipse(*ear.antitragus), 6)
    h += 0.12 * blur(ellipse(*ear.lobe), 14)
    h += 0.006 * blur(RNG.standard_normal((S, S)).astype(np.float32), 0.8)  # pores
    edge = np.clip(blur(outline, 7) * 1.7, 0, 1)  # round off the outline
    return np.clip(h, 0, 1) * edge, outline


def skin(ear, palette, notches=None, blood=True, extra_height=None, albedo_fn=None):
    h, alpha = ear_height(ear, notches)
    if extra_height is not None:
        h = h + extra_height * alpha
    base = srgb_to_linear(palette["skin"])
    mottle = value_noise(10, 3) - 0.5
    fine = value_noise(48, 0.6) - 0.5
    albedo = base[None, None, :] * (1 + mottle[..., None] * palette.get("mottle", 0.16) + fine[..., None] * 0.06)
    # Thin places (rim, lobe edge) let light through: redder, brighter.
    thin = np.clip(1.25 - blur(alpha, 16) * 1.35, 0, 1) * alpha
    sss = srgb_to_linear(palette["sss"])
    albedo = albedo * (1 - thin[..., None] * 0.55) + sss[None, None, :] * (thin[..., None] * 0.55)
    # The bowl and canal are darker and redder inside.
    deep = blur(poly(ear.concha), 10) * 0.35 + blur(ellipse(*ear.canal), 6) * 0.65
    albedo = albedo * (1 - deep[..., None] * 0.45) + srgb_to_linear(palette["inner"])[None, None, :] * (deep[..., None] * 0.45)
    if albedo_fn:
        albedo = albedo_fn(albedo, alpha)
    ao = np.clip(1 - 2.4 * np.clip(blur(h, 16) - h, 0, 1), 0.35, 1)
    spec, shine = palette.get("spec", 0.22), palette.get("shine", 22)
    if blood:
        ragged = np.clip((blur(stroke(ear.cut, 46, 30), 3) + (value_noise(40, 1.2) - 0.5) * 0.9 - 0.45) * 3, 0, 1)
        b = ragged * alpha
        cx, cy = ear.cut[-2]
        drip = np.maximum(stroke([(cx + 2, cy - 10), (cx + 4, cy + 26), (cx + 3, cy + 48)], 12, 7),
                          ellipse(cx + 3, cy + 54, 9, 11))
        alpha = np.clip(alpha + drip, 0, 1)
        b = np.clip(b + drip, 0, 1)
        clot = value_noise(60, 0.8)
        blood_rgb = srgb_to_linear("#6e0707")[None, None, :] * (0.65 + 0.6 * clot[..., None])
        albedo = albedo * (1 - b[..., None] * 0.95) + blood_rgb * (b[..., None] * 0.95)
        h = h + blur(b, 2) * 0.04 + blur(drip, 3) * 0.1
        spec_map = spec + b * 0.9
        shine = np.where(b > 0.3, 70.0, shine)
    else:
        spec_map = spec
    rgb = light(h, albedo, ao=ao, spec=spec_map, shine=shine)
    # Dark outline so the shape reads at 36 px.
    inner = np.clip((blur(alpha, 2.5) - 0.72) * 5, 0, 1)
    band = np.clip(alpha - inner, 0, 1)
    rgb = rgb * (1 - band[..., None] * 0.6)
    return Layer(rgb, alpha)


def torus(cx, cy, radius, tube, color, cover=None, cover_above=None):
    """A metal ring seen face on. `cover` hides the part above `cover_above`, as if through a piercing."""
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    dx, dy = xx - cx, yy - cy
    d = np.sqrt(dx**2 + dy**2)
    t = (d - radius) / tube
    inside = np.clip(1 - np.abs(t), 0, 1)
    alpha = np.clip((1 - np.abs(t)) * tube / 1.2, 0, 1)
    nz = np.sqrt(np.clip(1 - t**2, 0, 1))
    with np.errstate(invalid="ignore", divide="ignore"):
        nx, ny = np.nan_to_num(t * dx / d), np.nan_to_num(t * dy / d)
    n = normalize(np.dstack([nx, ny, nz + 1e-3]))
    albedo = srgb_to_linear(color)[None, None, :] * np.ones((S, S, 1), dtype=np.float32)
    ndl = np.clip(n @ LIGHT, 0, 1)
    ndh = np.clip(n @ HALF, 0, 1)
    rgb = albedo * (0.25 + 0.9 * ndl)[..., None] + albedo * (ndh**40 * 2.5)[..., None] + (ndh**80 * 0.6)[..., None]
    if cover is not None:
        alpha = alpha * (1 - cover * (yy < cover_above))
    return Layer(rgb, alpha * (inside > 0))


def metal_band(points, width, color):
    mask = stroke(points, width)
    h = blur(mask, width / 3)
    albedo = srgb_to_linear(color)[None, None, :] * np.ones((S, S, 1), dtype=np.float32)
    rgb = light(h, albedo, strength=60, spec=1.4, shine=36, metal=True, ambient=0.25)
    return Layer(rgb, mask)


def gear(cx, cy, radius, teeth=8, color="#c79a3c"):
    pts = []
    for i in range(teeth * 4):
        a = 2 * math.pi * i / (teeth * 4)
        r = radius if (i % 4) in (1, 2) else radius * 0.74
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    mask = poly(pts, smooth=False)
    hole = ellipse(cx, cy, radius * 0.28, radius * 0.28)
    h = blur(mask, 2.5) - 0.6 * blur(hole, 1.5)
    albedo = srgb_to_linear(color)[None, None, :] * np.ones((S, S, 1), dtype=np.float32)
    rgb = light(h, albedo, strength=40, spec=1.2, shine=30, metal=True, ambient=0.25)
    return Layer(rgb, np.clip(mask - hole * 0.9, 0, 1))


def stitches(seam, crosses):
    seam_mask = blur(stroke(seam, 6), 1.5)
    rgb = np.ones((S, S, 3), dtype=np.float32) * srgb_to_linear("#2b1d22")[None, None, :]
    layers = [Layer(rgb * 0.7, seam_mask * 0.85)]
    thread = np.zeros((S, S), dtype=np.float32)
    for (x0, y0), (x1, y1) in crosses:
        thread = np.maximum(thread, stroke([(x0, y0), (x1, y1)], 7))
    h = blur(thread, 2)
    albedo = srgb_to_linear("#1a1416")[None, None, :] * np.ones((S, S, 1), dtype=np.float32)
    layers.append(Layer(light(h, albedo, strength=50, spec=0.6, shine=18), thread))
    return layers


def feather(rachis):
    vane = stroke(rachis, 92, profile=lambda t: 0.25 + 0.75 * math.sin(math.pi * min(1.0, t * 1.15)) ** 0.7)
    shaft = stroke(rachis, 6, 2)
    pts = catmull(rachis, closed=False, steps=60)
    barbs = np.zeros((S, S), dtype=np.float32)
    img = _canvas()
    d = ImageDraw.Draw(img)
    for i in range(2, len(pts) - 2, 2):
        (x0, y0), (x1, y1) = pts[i - 1], pts[i + 1]
        tx, ty = x1 - x0, y1 - y0
        length = math.hypot(tx, ty) or 1
        nx, ny = -ty / length, tx / length
        reach = 34 * (1 - i / len(pts)) + 6
        for side in (-1, 1):
            ex = pts[i][0] + side * nx * reach + tx / length * 14
            ey = pts[i][1] + side * ny * reach + ty / length * 14
            d.line([(pts[i][0] * SS, pts[i][1] * SS), (ex * SS, ey * SS)], fill=255, width=SS)
    barbs = _finish(img) * vane
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    (bx, by), (ex, ey) = rachis[0], rachis[-1]
    along = ((xx - bx) * (ex - bx) + (yy - by) * (ey - by)) / ((ex - bx) ** 2 + (ey - by) ** 2)
    tip = np.clip((along - 0.68) / 0.32, 0, 1) ** 1.3  # white, turning blue in the last stretch
    white, blue = srgb_to_linear("#f4f6fb"), srgb_to_linear("#5f8fd8")
    albedo = white[None, None, :] * (1 - tip[..., None]) + blue[None, None, :] * tip[..., None]
    albedo = albedo * (1 - barbs[..., None] * 0.30)  # the barbs show as fine darker lines
    splits = np.zeros((S, S), dtype=np.float32)
    for frac, side in ((0.38, 1), (0.55, -1), (0.72, 1)):
        i = int(frac * (len(pts) - 1))
        (x0, y0), (x1, y1) = pts[i - 1], pts[i + 1]
        tx, ty = x1 - x0, y1 - y0
        length = math.hypot(tx, ty) or 1
        nx, ny = -ty / length * side, tx / length * side
        sx, sy = pts[i][0] + nx * 10, pts[i][1] + ny * 10
        splits = np.maximum(splits, stroke([(sx, sy), (sx + nx * 40 + tx / length * 18, sy + ny * 40 + ty / length * 18)], 5, 2))
    vane = vane * (1 - splits)
    h = blur(vane, 10) * 0.5 + barbs * 0.05 + shaft * 0.3
    rgb = light(h, albedo, strength=70, spec=0.3, shine=16, ambient=0.45)
    edge = np.clip((blur(vane, 2) - 0.2) * 1.6, 0, 1)  # soft, slightly ragged edge
    return Layer(rgb, np.clip(edge * (0.82 + 0.18 * barbs) + shaft, 0, 1))


def braid(path, color="#b5592a", bead="#d7a640"):
    pts = catmull(path, closed=False, steps=14)
    mask = np.zeros((S, S), dtype=np.float32)
    h = np.zeros((S, S), dtype=np.float32)
    strands = np.zeros((S, S), dtype=np.float32)
    for i in range(0, len(pts) - 1, 2):
        x, y = pts[i]
        side = -1 if (i // 2) % 2 else 1
        plait = ellipse(x + side * 10, y, 30, 15, side * 34)
        mask = np.maximum(mask, plait)
        h = np.maximum(h, blur(plait, 4) * 0.9 + i * 0.0001)
    region = mask > 0.5
    rgb_fur, fur = fur_layer(region.astype(np.float32), 90, scale_hex(color, 0.45), scale_hex(color, 1.45),
                             count=2600, length=12)
    strands = fur
    albedo = srgb_to_linear(color)[None, None, :] * (0.55 + 0.25 * strands[..., None]) + rgb_fur * 0.35
    rgb = light(h + strands * 0.03, albedo, strength=85, spec=0.4, shine=18)
    end = pts[-1]
    cap = metal_band([(end[0], end[1] - 30), (end[0], end[1] - 8)], 30, bead)
    return [Layer(rgb, mask), cap]


def fur_layer(region, direction_deg, color_dark, color_light, count=2200, length=16):
    """Short hair strokes over a region. direction_deg is degrees, or fn(x, y) -> (degrees, length scale)."""
    img = _canvas()
    d = ImageDraw.Draw(img)
    ys, xs = np.nonzero(region > 0.5)
    pick = RNG.choice(len(xs), size=min(count, len(xs)), replace=False)
    for k in pick:
        x, y = xs[k], ys[k]
        if callable(direction_deg):
            deg, scale = direction_deg(x, y)
        else:
            deg, scale = direction_deg, 1.0
        jitter = math.radians(deg) + RNG.normal(0, 0.35)
        ln = length * scale * (0.6 + RNG.random() * 0.8)
        d.line([(x * SS, y * SS), ((x + math.cos(jitter) * ln) * SS, (y + math.sin(jitter) * ln) * SS)],
               fill=int(120 + RNG.random() * 135), width=SS)
    strands = _finish(img)
    dark, lightc = srgb_to_linear(color_dark), srgb_to_linear(color_light)
    return dark[None, None, :] * (1 - strands[..., None]) + lightc[None, None, :] * strands[..., None], strands


# ---------------------------------------------------------------- races
# Each race comes in a few skin tones (tauren: fur colours). The game doesn't tell
# addons a player's skin tone, so UI/Art.lua picks one per victim from a hash of
# their GUID: random across players, stable for each one.

TONES = {
    "human": [
        dict(skin="#f1cbb3", sss="#ea827a", inner="#a85a4c"),
        dict(skin="#e0a984", sss="#dc6c5a", inner="#924c3a"),
        dict(skin="#b07752", sss="#bd5c45", inner="#6e392a"),
        dict(skin="#6f4631", sss="#8e4030", inner="#3a1e16"),
    ],
    "dwarf": [
        dict(skin="#e6a185", sss="#d9524a", inner="#8e3a2e", mottle=0.22, hair="#b5592a"),
        dict(skin="#f0c4ad", sss="#e2706a", inner="#9e5244", mottle=0.22, hair="#6b4228"),
        dict(skin="#c88b66", sss="#c85c48", inner="#7a3c2c", mottle=0.22, hair="#2e2622"),
        dict(skin="#8c5a3e", sss="#9c4834", inner="#4e2a1e", mottle=0.22, hair="#d9b46a"),
    ],
    "gnome": [
        dict(skin="#f2cdb6", sss="#ec8378", inner="#a65a4c"),
        dict(skin="#ecb99c", sss="#e2746a", inner="#9a5040"),
        dict(skin="#d49c7a", sss="#d06a56", inner="#844634"),
        dict(skin="#a8735a", sss="#b05a46", inner="#5e3426"),
    ],
    "nightelf": [
        dict(skin="#9c88d2", sss="#a675e6", inner="#4c3a7c", mottle=0.10),
        dict(skin="#7f8bd0", sss="#8a7ef0", inner="#3a3f78", mottle=0.10),
        dict(skin="#6b56a6", sss="#8a5ad8", inner="#33245e", mottle=0.10),
        dict(skin="#b9a8da", sss="#c08ef0", inner="#5e4a8a", mottle=0.10),
    ],
    "skyborne": [
        dict(skin="#f3ddcc", sss="#ef9a90", inner="#b06a5e", mottle=0.10),
        dict(skin="#f2cbb8", sss="#ee8c84", inner="#a85e52", mottle=0.10),
        dict(skin="#e4bc92", sss="#dc8a6a", inner="#9a5e44", mottle=0.10),
        dict(skin="#c89a74", sss="#c4785a", inner="#7c4a34", mottle=0.10),
    ],
    "orc": [
        dict(skin="#7d9f55", sss="#a9b94a", inner="#3e5528", mottle=0.20),
        dict(skin="#8f9a52", sss="#b8b24a", inner="#4a5226", mottle=0.20),
        dict(skin="#587c3e", sss="#86a83c", inner="#2c421e", mottle=0.20),
        dict(skin="#7e6e44", sss="#a88e4a", inner="#45391e", mottle=0.20),
    ],
    "troll": [
        dict(skin="#6c9eb0", sss="#6cc2d6", inner="#2f5562", mottle=0.18),
        dict(skin="#68a898", sss="#6ccab4", inner="#2c5a4e", mottle=0.18),
        dict(skin="#7f86b8", sss="#8a8ee0", inner="#3c3f68", mottle=0.18),
        dict(skin="#7aa66a", sss="#8ccc6c", inner="#3a5a30", mottle=0.18),
    ],
    "undead": [
        dict(skin="#a8a7a3", sss="#9aa58f", inner="#3c3240", mottle=0.30, spec=0.12, shine=12),
        dict(skin="#9ca591", sss="#9aaf88", inner="#363c30", mottle=0.30, spec=0.12, shine=12),
        dict(skin="#9ba3b2", sss="#94a4bc", inner="#323848", mottle=0.30, spec=0.12, shine=12),
        dict(skin="#aa9eae", sss="#ac98b4", inner="#3e3044", mottle=0.30, spec=0.12, shine=12),
    ],
    "tauren": [
        dict(fur_dark="#3a2010", fur_light="#b07e52", inner="#c99a8c"),
        dict(fur_dark="#161210", fur_light="#4e443c", inner="#b48a80"),
        dict(fur_dark="#9c8a70", fur_light="#f2e8d6", inner="#d8aaa0"),
        dict(fur_dark="#4e1c0c", fur_light="#b8653a", inner="#c8988a"),
    ],
    "generic": [dict(skin="#c9b2a2", sss="#c98a80", inner="#7b5a4e")],
}


def paint_human(p):
    return [skin(HUMAN, p)]


def paint_dwarf(p):
    ear = skin(HUMAN, p)
    layers = braid([(380, 40), (412, 150), (424, 270), (418, 390), (410, 470)], color=p["hair"])
    lobe = ellipse(*HUMAN.lobe)
    ring = torus(290, 470, 20, 5.5, "#d9a93e", cover=lobe, cover_above=452)
    return layers + [ear, ring]


def paint_gnome(p):
    ear = skin(GNOME, p)
    lx, ly = GNOME.lobe[0], GNOME.lobe[1] + 6
    return [ear, gear(lx + 2, ly + 2, 34, teeth=9)]


def paint_nightelf(p):
    ear = skin(ELF, p)
    cuff = metal_band([(404, 52), (424, 86)], 22, "#c9cdd8")
    return [ear, cuff]


def paint_skyborne(p):
    back = feather([(300, 300), (240, 196), (170, 120), (78, 70)])
    ear = skin(ELF, p)
    cuff = metal_band([(366, 74), (384, 108)], 16, "#e2bd5a")
    return [back, ear, cuff]


def paint_orc(p):
    ear = skin(ORC, p)
    lobe = ellipse(*ORC.lobe)
    hoop = torus(292, 474, 22, 6, "#d6a43c", cover=lobe, cover_above=455)
    small = torus(398, 104, 12, 4, "#d6a43c")
    return [ear, hoop, small]


def paint_troll(p):
    ear = skin(TROLL, p)
    bone = torus(452, 158, 17, 6, "#e8dcc0")
    return [ear, bone]


def undead_albedo(albedo, alpha):
    bruise = np.clip((value_noise(6, 4) - 0.55) * 3, 0, 1) * alpha
    rot = srgb_to_linear("#5c4a66")
    return albedo * (1 - bruise[..., None] * 0.5) + rot[None, None, :] * (bruise[..., None] * 0.5)


def paint_undead(p):
    notches = [[(392, 192), (360, 214), (390, 234)], [(368, 92), (346, 122), (382, 118)]]
    ear = skin(HUMAN, p, notches=notches, albedo_fn=undead_albedo)
    seam = [(286, 64), (296, 120), (314, 190), (318, 240)]
    crosses = [((278, 86), (306, 100)), ((286, 126), (314, 136)), ((296, 168), (326, 176)), ((304, 210), (332, 214))]
    return [ear] + stitches(seam, crosses)


def paint_tauren(p):
    # A cow's ear seen from the open side: a scoop with rolled edges, a dark hollow
    # at the base, and pale hair fanning out of it; brown fur on the rolled rim.
    outline_pts = [(78, 226), (118, 196), (190, 166), (280, 156), (366, 174), (432, 218), (476, 272), (498, 330),
                   (498, 330), (444, 328), (370, 314), (286, 302), (196, 294), (124, 284), (84, 270)]
    cup_pts = [(120, 232), (190, 196), (280, 186), (360, 202), (420, 240), (462, 302), (420, 308), (350, 298),
               (270, 288), (190, 282), (126, 268)]
    hollow = (150, 250)
    outline = poly(outline_pts)
    cup = poly(cup_pts)
    canal = ellipse(hollow[0], hollow[1], 38, 21, -6)
    h = 0.40 * outline + 0.18 * blur(np.clip(outline - cup, 0, 1), 6) - 0.22 * blur(cup, 12) - 0.35 * blur(canal, 9)
    h = np.clip(h, 0, 1) * np.clip(blur(outline, 8) * 1.7, 0, 1)
    rim = np.clip(outline - blur(cup, 4) * 1.15, 0, 1)
    fur_rgb, fur = fur_layer(rim, 12, p["fur_dark"], p["fur_light"], count=2600, length=16)
    skin_in = srgb_to_linear(p["inner"])
    dark = blur(canal, 16)
    inside = skin_in[None, None, :] * (1 - np.clip(dark * 1.6, 0, 0.92)[..., None]) * (
        0.85 + 0.3 * value_noise(30, 1)[..., None]
    )
    albedo = fur_rgb * rim[..., None] + inside * (1 - rim[..., None])

    def fan(x, y):
        dx, dy = x - hollow[0], y - hollow[1]
        dist = math.hypot(dx, dy)
        return math.degrees(math.atan2(dy, dx)), 1.6 - min(dist / 260, 1.0)

    hair_region = np.clip(cup - blur(canal, 3) * 0.8, 0, 1) * (1 - rim)
    hair_rgb, hair = fur_layer(hair_region, fan, "#bfa48a", "#fff7ea", count=3000, length=22)
    albedo = albedo * (1 - hair[..., None] * 0.8) + hair_rgb * (hair[..., None] * 0.8)
    b = np.clip((blur(stroke([(82, 228), (90, 250), (86, 270)], 40, 30), 3) + (value_noise(40, 1.2) - 0.5) * 0.9
                 - 0.45) * 3, 0, 1) * outline
    albedo = albedo * (1 - b[..., None] * 0.9) + srgb_to_linear("#6e0707")[None, None, :] * (b[..., None] * 0.9)
    ao = np.clip(1 - 2.4 * np.clip(blur(h, 16) - h, 0, 1), 0.35, 1)
    rgb = light(h + fur * 0.02 + hair * 0.015, albedo, ao=ao, spec=0.10 + b * 0.8, shine=np.where(b > 0.3, 70.0, 14.0))
    inner_band = np.clip((blur(outline, 2.5) - 0.72) * 5, 0, 1)
    rgb = rgb * (1 - np.clip(outline - inner_band, 0, 1)[..., None] * 0.5)
    ear = Layer(rgb, outline)
    # A leather thong with two beads through the lower edge.
    thong = metal_band([(318, 300), (322, 340), (326, 378)], 6, "#4a2f1c")
    bead_layers = []
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    for bx, by, r, col in [(322, 352, 15, "#8a5a2c"), (326, 386, 13, "#d9c49c")]:
        m = ellipse(bx, by, r, r)
        hb = np.sqrt(np.clip(1 - ((xx - bx) ** 2 + (yy - by) ** 2) / r**2, 0, 1))
        alb = srgb_to_linear(col)[None, None, :] * np.ones((S, S, 1), dtype=np.float32)
        bead_layers.append(Layer(light(hb * 0.25, alb, strength=60, spec=0.5, shine=30), m))
    return [ear, thong] + bead_layers


def paint_generic(p):
    return [skin(HUMAN, p, blood=False)]


RACES = {
    "human": paint_human,
    "dwarf": paint_dwarf,
    "gnome": paint_gnome,
    "nightelf": paint_nightelf,
    "skyborne": paint_skyborne,
    "orc": paint_orc,
    "troll": paint_troll,
    "undead": paint_undead,
    "tauren": paint_tauren,
    "generic": paint_generic,
}


TILT = {  # degrees clockwise, applied before the ear is fitted to the canvas
    "human": 16,
    "dwarf": 10,
    "gnome": 14,
    "undead": 16,
    "generic": 16,
    "orc": 10,
    "nightelf": 0,
    "skyborne": 0,
    "troll": -6,
    "tauren": 10,
}
MARGIN = 0.06  # of the canvas, left clear around the fitted ear for the shadow


def fit(rgb, alpha):
    """Scale and move the ear so its bounding box fills the canvas, centred."""
    ys, xs = np.nonzero(alpha > 0.05)
    left, right, top, bottom = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    room = S * (1 - 2 * MARGIN)
    scale = min(room / (right - left), room / (bottom - top))
    # Output (x, y) samples input (x / scale + c, y / scale + f), putting the box centre at the canvas centre.
    c = (left + right) / 2 - (S / 2) / scale
    f = (top + bottom) / 2 - (S / 2) / scale
    rgba = np.dstack([rgb * alpha[..., None], alpha]).astype(np.float32)
    coeffs = (1 / scale, 0, c, 0, 1 / scale, f)
    channels = []
    for i in range(4):
        ch = Image.fromarray(rgba[..., i], mode="F")
        channels.append(np.asarray(ch.transform((S, S), Image.AFFINE, coeffs, resample=Image.BICUBIC)))
    out = np.dstack(channels)
    alpha2 = np.clip(out[..., 3], 0, 1)
    rgb2 = out[..., :3] / np.maximum(alpha2[..., None], 1e-6)
    return np.clip(rgb2, 0, None), alpha2


def frame(rgb, alpha, angle, scale, dx, dy):
    """Rotate/scale/move premultiplied RGBA about the canvas centre."""
    if angle == 0 and scale == 1 and dx == 0 and dy == 0:
        return rgb, alpha
    rgba = np.dstack([rgb * alpha[..., None], alpha]).astype(np.float32)
    channels = []
    a = math.radians(-angle)
    cos, sin = math.cos(a) / scale, math.sin(a) / scale
    cx = cy = S / 2
    # Inverse affine map for PIL: output (x, y) samples input (ax + by + c, dx + ey + f).
    coeffs = (cos, sin, cx - cos * (cx + dx) - sin * (cy + dy), -sin, cos, cy + sin * (cx + dx) - cos * (cy + dy))
    for i in range(4):
        ch = Image.fromarray(rgba[..., i], mode="F")
        channels.append(np.asarray(ch.transform((S, S), Image.AFFINE, coeffs, resample=Image.BICUBIC)))
    out = np.dstack(channels)
    alpha2 = np.clip(out[..., 3], 0, 1)
    rgb2 = out[..., :3] / np.maximum(alpha2[..., None], 1e-6)
    return np.clip(rgb2, 0, None), alpha2


def render(name, palette):
    rgb, alpha = over(RACES[name](palette))
    rgb, alpha = frame(rgb, alpha, TILT[name], 1, 0, 0)
    rgb, alpha = fit(rgb, alpha)
    shadow = blur(shift(alpha, 3, 4), 3) * 0.6
    out_alpha = alpha + shadow * (1 - alpha)
    out_rgb = rgb * alpha[..., None] / np.maximum(out_alpha[..., None], 1e-6)
    srgb = linear_to_srgb(out_rgb)
    rgba = np.dstack([srgb, out_alpha])
    return Image.fromarray((np.clip(rgba, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")


def texture_names():
    """(file name, race, palette) for every texture: <race>-<tone>, or just <race> with one tone."""
    for name, tones in TONES.items():
        for i, palette in enumerate(tones, 1):
            yield (name if len(tones) == 1 else f"{name}-{i}"), name, palette


def main():
    out, size = Path(sys.argv[1]), int(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    preview_dir = Path(sys.argv[sys.argv.index("--preview") + 1]) if "--preview" in sys.argv else None
    for file_name, race, palette in texture_names():
        image = render(race, palette)
        image.resize((size, size), Image.LANCZOS).save(out / f"{file_name}.tga", compression=None)
        if preview_dir:
            preview_dir.mkdir(parents=True, exist_ok=True)
            image.save(preview_dir / f"{file_name}.png")
        print(f"{file_name}.tga")


if __name__ == "__main__":
    main()
