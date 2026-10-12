"""Builds the buildings: every firm type in the four architectural styles of the
original (NE northern-European, ME Mediterranean, EA east-Asian, MA middle-eastern),
the race-specific stables and Seats of Power, town houses, and the Fryhtan lairs.

blender -b --factory-startup -P tools/blender/buildings.py -- [name ...]

A model fills its footprint (loc_w x loc_h locations, one location = one unit),
centred on the origin, entrance towards the camera (+x / -y in Blender). Static
meshes; a few named parts are animated by the game:
  Wheel*  turns slowly (mills, mine headframes)
  Flag*   team banners (nation colour)
"""
import sys, os, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from mathutils import Vector
from common import *
from common import _mesh_obj

# role names used here -> palette roles
STYLE_COLORS = {
    "NE": {"linen": "#e6dcc4", "wood": "#5e4232", "cloth": "#8a6a3e", "cloth_dark": "#6a4e2e", "stone": "#a8a49a", "stone_dark": "#7a766e", "trim": "#c03a30", "metal": "#7a8288", "plant": "#5a8a3a", "black": "#2a2420", "leather": "#9a7a4a"},
    "ME": {"linen": "#ecdcb8", "wood": "#7a5638", "cloth": "#c06038", "cloth_dark": "#9a4628", "stone": "#d8ccae", "stone_dark": "#b0a488", "trim": "#e8e2d0", "metal": "#8a8a80", "plant": "#6a8a3a", "black": "#2e2620", "leather": "#a07a4a"},
    "EA": {"linen": "#ece4d0", "wood": "#a83228", "cloth": "#46504e", "cloth_dark": "#2e3634", "stone": "#9a968c", "stone_dark": "#6e6a62", "trim": "#d8b048", "metal": "#5a5a52", "plant": "#4a7a3a", "black": "#201c1a", "leather": "#8a6a3a"},
    "MA": {"linen": "#dcc49a", "wood": "#7a5432", "cloth": "#c8a870", "cloth_dark": "#a88850", "stone": "#d0b080", "stone_dark": "#a88a60", "trim": "#3a7aa0", "metal": "#8a8070", "plant": "#5a8a3a", "black": "#2a2018", "leather": "#a07040"},
    "FRY": {"linen": "#6a5a4a", "wood": "#4a3a2e", "cloth": "#5a6a3a", "cloth_dark": "#3a4a2a", "stone": "#6a6458", "stone_dark": "#4a4640", "trim": "#a03030", "metal": "#5a5a50", "plant": "#4a6a2a", "black": "#141210", "leather": "#7a5a3a", "bone": "#e8dcc0", "flesh": "#8a4a4a", "glow": "#b0ff60", "chitin": "#8a7a2a"},
}

# race -> architectural style of its buildings (the original's FBUILD groups)
RACE_STYLE = {"NORMAN": "NE", "VIKING": "NE", "CELTIC": "NE", "ROMAN": "ME", "GREEK": "ME", "CARTH": "ME",
              "CHINESE": "EA", "JAPANESE": "EA", "MONGOL": "EA", "EGYPTIAN": "MA", "PERSIAN": "MA", "INDIAN": "MA"}

PARTS = []      # collected parts of the building being built


def P(o, role):
    PARTS.append(colored(o, role))
    return o


def blk(w, d, h, at, role="linen", z0=0.0):
    """Box standing on z0, centred on `at` (x, y)."""
    return P(box("blk", (w, d, h), at=(at[0], at[1], z0 + h / 2)), role)


def gable(w, d, h, at, z0, role="cloth", along_x=True, over=0.12):
    """Gable roof (triangular prism) on a w x d block whose walls end at z0."""
    import bmesh
    bm = bmesh.new()
    W, D = (w / 2 + over, d / 2 + over)
    if along_x:
        pts = [(-W, -D, 0), (W, -D, 0), (W, 0, h), (-W, 0, h), (-W, D, 0), (W, D, 0)]
        faces = [(0, 1, 2, 3), (3, 2, 5, 4), (0, 3, 4), (1, 5, 2), (0, 4, 5, 1)]
    else:
        pts = [(-W, -D, 0), (0, -D, h), (W, -D, 0), (-W, D, 0), (0, D, h), (W, D, 0)]
        faces = [(0, 2, 1), (3, 4, 5), (0, 1, 4, 3), (1, 2, 5, 4), (0, 3, 5, 2)]
    vs = [bm.verts.new(p) for p in pts]
    for f in faces:
        bm.faces.new([vs[i] for i in f])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = _mesh_obj("gable", bm)
    o.location = (at[0], at[1], z0)
    return P(o, role)


def hip(w, d, h, at, z0, role="cloth", over=0.15, top=0.0, flare=0.0):
    """Hipped / pyramid roof; `top` > 0 leaves a ridge, `flare` lifts the eaves (pagoda)."""
    import bmesh
    bm = bmesh.new()
    W, D = w / 2 + over, d / 2 + over
    t = top
    base = [bm.verts.new((sx * W, sy * D, flare if (sx and sy) else 0)) for sx, sy in [(-1, -1), (1, -1), (1, 1), (-1, 1)]]
    if t > 0:
        r = [bm.verts.new((-t, 0, h)), bm.verts.new((t, 0, h))]
        faces = [(base[0], base[1], r[1], r[0]), (base[2], base[3], r[0], r[1]), (base[1], base[2], r[1]), (base[3], base[0], r[0])]
    else:
        apex = bm.verts.new((0, 0, h))
        faces = [(base[i], base[(i + 1) % 4], apex) for i in range(4)]
    for f in faces:
        bm.faces.new(f)
    bm.faces.new(list(reversed(base)))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    o = _mesh_obj("hip", bm)
    o.location = (at[0], at[1], z0)
    return P(o, role)


def pagoda(w, d, h, at, z0, role="cloth", tiers=1):
    for i in range(tiers):
        k = 1.0 - i * 0.28
        hip(w * k, d * k, h * 0.6, at, z0 + i * h * 0.75, role, over=0.35 * k, top=0.15 * w * k, flare=0.12)
        if i < tiers - 1:
            blk(w * k * 0.62, d * k * 0.62, h * 0.4, at, "wood", z0 + i * h * 0.75 + h * 0.3)


def tower(r, h, at, role="stone", roof="cone", roof_role="trim", segs=8, z0=0.0):
    P(cone("tower", r, r, h, segs, at=(at[0], at[1], z0 + h / 2)), role)
    if roof == "cone":
        P(cone("spire", r * 1.25, 0.02, r * 2.2, segs, at=(at[0], at[1], z0 + h + r * 1.1)), roof_role)
    elif roof == "dome":
        P(sphere("dome", r * 1.05, segs, 5, at=(at[0], at[1], z0 + h), cut=0.0), roof_role)
    elif roof == "crenel":
        merlons(r, at, z0 + h, role, segs)
    elif roof == "pagoda":
        hip(r * 2, r * 2, r * 1.2, at, z0 + h, roof_role, over=r * 0.5, flare=0.1)


def merlons(r, at, z, role="stone", n=8):
    for i in range(n):
        a = 2 * math.pi * i / n
        P(box("merlon", (0.16, 0.16, 0.2), at=(at[0] + math.cos(a) * r * 0.95, at[1] + math.sin(a) * r * 0.95, z + 0.1)), role)


def crenel_wall(x0, y0, x1, y1, h, role="stone", t=0.3, z0=0.0):
    L = math.hypot(x1 - x0, y1 - y0)
    ang = math.atan2(y1 - y0, x1 - x0)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    P(box("wall", (L, t, h), at=(cx, cy, z0 + h / 2), rot=(0, 0, ang)), role)
    n = max(2, int(L / 0.35))
    for i in range(n):
        if i % 2 == 0:
            f = (i + 0.5) / n
            P(box("merlon", (L / n, t, 0.16), at=(x0 + (x1 - x0) * f, y0 + (y1 - y0) * f, z0 + h + 0.08), rot=(0, 0, ang)), role)


def palisade(x0, y0, x1, y1, h=0.7, role="wood"):
    L = math.hypot(x1 - x0, y1 - y0)
    n = max(2, int(L / 0.16))
    for i in range(n + 1):
        f = i / n
        x, y = x0 + (x1 - x0) * f, y0 + (y1 - y0) * f
        P(cone("stake", 0.07, 0.07, h, 5, at=(x, y, h / 2)), role)
        P(cone("tip", 0.07, 0.0, 0.14, 5, at=(x, y, h + 0.07)), role)


def tent(r, h, at, role="linen", stripe="team"):
    P(cone("tent", r, 0.04, h, 10, at=(at[0], at[1], h / 2)), role)
    P(torus("band", r * 0.55, 0.03, 10, 3, at=(at[0], at[1], h * 0.45)), stripe)
    P(cone("pole", 0.025, 0.025, 0.25, 4, at=(at[0], at[1], h + 0.12)), "wood")


def flag(at, z, h=1.0, name="Flag"):
    P(cone("flagpole", 0.03, 0.03, h, 5, at=(at[0], at[1], z + h / 2)), "wood")
    f = box(name, (0.38, 0.02, 0.26), at=(at[0] + 0.2, at[1], z + h - 0.15))
    P(f, "team")


def door(at, z0=0.0, w=0.35, h=0.55, facing="y"):
    if facing == "y":
        P(box("door", (w, 0.04, h), at=(at[0], at[1], z0 + h / 2)), "black")
    else:
        P(box("door", (0.04, w, h), at=(at[0], at[1], z0 + h / 2)), "black")


def windows(x0, x1, y, z, n, role="black", facing="y"):
    for i in range(n):
        x = x0 + (x1 - x0) * (i + 0.5) / n
        if facing == "y":
            P(box("win", (0.14, 0.04, 0.18), at=(x, y, z)), role)
        else:
            P(box("win", (0.04, 0.14, 0.18), at=(y, x, z)), role)


def beams(w, d, h, at, z0=0.0, role="wood"):
    """Timber framing on a NE house: corner posts and a mid rail."""
    for sx in (-1, 1):
        for sy in (-1, 1):
            P(box("post", (0.07, 0.07, h), at=(at[0] + sx * w / 2, at[1] + sy * d / 2, z0 + h / 2)), role)
    P(box("rail", (w + 0.05, 0.05, 0.06), at=(at[0], at[1] - d / 2, z0 + h * 0.55)), role)
    P(box("rail", (0.05, d + 0.05, 0.06), at=(at[0] + w / 2, at[1], z0 + h * 0.55)), role)


def house(style, w, d, h, at, z0=0.0, door_on=True):
    """A building block with the roof of its style."""
    wall = {"NE": "linen", "ME": "linen", "EA": "linen", "MA": "stone"}[style]
    blk(w, d, h, at, wall, z0)
    if style == "NE":
        beams(w, d, h, at, z0)
        gable(w, d, h * 0.8, at, z0 + h, "cloth", along_x=w >= d)
    elif style == "ME":
        gable(w, d, h * 0.38, at, z0 + h, "cloth", along_x=w >= d, over=0.1)
    elif style == "EA":
        for sx in (-1, 1):
            for sy in (-1, 1):
                P(box("pillar", (0.08, 0.08, h), at=(at[0] + sx * w / 2, at[1] + sy * d / 2, z0 + h / 2)), "wood")
        pagoda(w, d, h * 0.9, at, z0 + h, "cloth")
    else:  # MA: flat roof with a parapet, sometimes a dome
        blk(w + 0.06, d + 0.06, 0.1, at, "stone_dark", z0 + h)
        if w * d > 1.5:
            P(sphere("dome", min(w, d) * 0.3, 10, 5, at=(at[0], at[1], z0 + h + 0.08), cut=0.0), "cloth")
    if door_on:
        door((at[0] + w * 0.15, at[1] - d / 2 - 0.01), z0)
        windows(at[0] - w / 2 + 0.1, at[1] + 0.0, at[1] - d / 2 - 0.01, z0 + h * 0.6, 1)


def ground(w, d, role="stone_dark", h=0.05):
    """No plate: the game draws the original's ground picture under each building."""
    return None


def scatter(objs_fn, n, w, d, seed, margin=0.4):
    rnd = random.Random(seed)
    for i in range(n):
        objs_fn((rnd.uniform(-w / 2 + margin, w / 2 - margin), rnd.uniform(-d / 2 + margin, d / 2 - margin)), rnd)


def barrel(at, rnd=None):
    P(cone("barrel", 0.13, 0.13, 0.3, 8, at=(at[0], at[1], 0.15)), "wood")


def crate(at, rnd=None):
    P(box("crate", (0.26, 0.26, 0.26), at=(at[0], at[1], 0.13), rot=(0, 0, (rnd.random() if rnd else 0) * 1.5)), "leather")


# ------------------------------------------------------------------- firms ---

def fort(s, w, d):
    ground(w, d, "stone_dark")
    m = 0.45
    x0, x1, y0, y1 = -w / 2 + m, w / 2 - m, -d / 2 + m, d / 2 - m
    wall = "stone"
    hgt = 0.9
    for a, b in [((x0, y0), (x1, y0)), ((x1, y0), (x1, y1)), ((x1, y1), (x0, y1)), ((x0, y1), (x0, y0))]:
        crenel_wall(a[0], a[1], b[0], b[1], hgt, wall)
    roof = {"NE": "cone", "ME": "crenel", "EA": "pagoda", "MA": "dome"}[s]
    rr = {"NE": "trim", "ME": "stone", "EA": "cloth", "MA": "cloth"}[s]
    for cx, cy in [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]:
        tower(0.38, 1.4, (cx, cy), "stone", roof, rr)
    # keep
    if s == "EA":
        blk(1.8, 1.8, 0.8, (0.1, 0.3), "stone")
        pagoda(1.8, 1.8, 0.9, (0.1, 0.3), 0.8, "cloth", tiers=3)
    elif s == "MA":
        blk(1.8, 1.8, 1.4, (0.1, 0.3), "stone")
        P(sphere("dome", 0.75, 12, 6, at=(0.1, 0.3, 1.4), cut=0.0), "cloth")
    else:
        blk(1.6, 1.6, 1.9, (0.1, 0.3), "stone")
        merlons(1.0, (0.1, 0.3), 1.9, "stone", 12) if s == "ME" else gable(1.6, 1.6, 0.8, (0.1, 0.3), 1.9, "cloth")
    door((0.6, y0 - 0.16), 0, 0.5, 0.7)
    flag((0.1, 0.3), 2.4 if s != "EA" else 3.0, 1.0)


def camp(s, w, d):
    ground(w, d, "cloth_dark" if s != "MA" else "stone_dark")
    m = 0.35
    x0, x1, y0, y1 = -w / 2 + m, w / 2 - m, -d / 2 + m, d / 2 - m
    palisade(x0, y1, x1, y1); palisade(x0, y0, x0, y1); palisade(x1, y0 + 1.2, x1, y1)
    palisade(x0, y0, x1 - 1.5, y0)
    tent(0.75, 1.2, (-0.4, 0.5), "linen", "team")
    for p in [(1.2, 1.1), (-1.3, -0.6), (0.9, -0.8), (-1.4, 1.5)]:
        tent(0.45, 0.75, p, "linen" if s != "EA" else "cloth", "team")
    P(box("rack", (0.6, 0.1, 0.4), at=(0.2, -1.3, 0.2)), "wood")
    flag((-0.4, 0.5), 1.2, 1.0)
    scatter(barrel, 3, w, d, 3)


def mine(s, w, d):
    ground(w, d, "stone_dark")
    P(sphere("heap", 1.2, 10, 5, at=(-1.2, 1.2, 0), scale=(1.2, 1.0, 0.6), cut=0.0), "stone")
    house(s, 1.6, 1.2, 0.8, (1.0, 1.0))
    # headframe over the shaft
    for sx in (-1, 1):
        P(box("leg", (0.1, 0.1, 2.0), at=(sx * 0.45, -0.5, 1.0), rot=(0, sx * -0.2, 0)), "wood")
    P(box("crossbar", (1.0, 0.12, 0.12), at=(0, -0.5, 1.9)), "wood")
    P(box("shaft", (1.0, 1.0, 0.3), at=(0, -0.5, 0.15)), "black")
    w1 = wheel_part("Wheel_head", 0.38, (0, -0.5, 2.05))
    P(box("cart", (0.4, 0.6, 0.3), at=(1.4, -1.3, 0.25)), "metal")
    flag((1.0, 1.0), 1.4, 0.8)


def factory(s, w, d):
    ground(w, d, "stone_dark")
    house(s, 2.6, 2.0, 1.1, (-0.3, 0.4))
    P(cone("chimney", 0.25, 0.2, 2.2, 6, at=(0.8, 1.0, 1.1)), "stone")
    wheel_part("Wheel_water", 0.6, (1.35, -0.2, 0.6))
    P(box("race", (0.3, 2.0, 0.15), at=(1.75, -0.2, 0.08)), "trim" if s == "MA" else "metal")
    scatter(crate, 4, w, d, 5)
    flag((-0.3, 0.4), 2.0, 0.8)


def market(s, w, d):
    ground(w, d, "stone")
    for i, (x, y) in enumerate([(-1.2, -1.2), (1.2, -1.2), (-1.2, 1.2), (1.2, 1.2)]):
        for sx in (-1, 1):
            for sy in (-1, 1):
                P(box("post", (0.06, 0.06, 0.8), at=(x + sx * 0.45, y + sy * 0.35, 0.4)), "wood")
        P(box("awning", (1.1, 0.9, 0.06), at=(x, y, 0.85), rot=(0.15, 0, 0)), "team" if i % 2 == 0 else "linen")
        P(box("counter", (0.9, 0.3, 0.35), at=(x, y - 0.25, 0.18)), "wood")
    P(cone("well", 0.35, 0.35, 0.35, 10, at=(0, 0, 0.18)), "stone")
    P(cone("wellroof", 0.5, 0.02, 0.4, 4, at=(0, 0, 1.0)), "cloth")
    scatter(barrel, 4, w, d, 7)
    scatter(crate, 3, w, d, 8)


def inn(s, w, d):
    ground(w, d, "stone_dark")
    house(s, 2.6, 1.8, 1.0, (0, 0.3))
    blk(2.2, 1.5, 0.7, (0, 0.3), "linen", 1.0) if s != "MA" else None
    if s == "NE":
        gable(2.2, 1.5, 0.8, (0, 0.3), 1.7, "cloth")
    P(box("sign", (0.4, 0.04, 0.3), at=(0.8, -0.75, 0.9)), "team")
    for i in range(3):
        P(box("table", (0.4, 0.4, 0.3), at=(-1.0 + i * 0.9, -1.4, 0.15)), "wood")


def research(s, w, d):
    ground(w, d, "stone")
    house(s, 2.0, 1.6, 0.8, (-0.5, 0.6))
    roof = {"NE": "cone", "ME": "dome", "EA": "pagoda", "MA": "dome"}[s]
    tower(0.6, 2.6, (0.9, -0.4), "stone", roof, "trim" if s != "MA" else "cloth", 10)
    P(cone("telescope", 0.08, 0.05, 0.7, 6, at=(1.2, -0.6, 3.2), rot=(0.6, 0.4, 0)), "metal")
    flag((-0.5, 0.6), 1.5 if s != "NE" else 1.9, 0.8)


def war(s, w, d):
    ground(w, d, "stone_dark")
    house(s, 3.2, 2.2, 1.3, (-0.4, 0.6))
    # crane
    P(box("mast", (0.15, 0.15, 2.4), at=(1.6, -1.2, 1.2)), "wood")
    P(box("jib", (0.12, 1.6, 0.12), at=(1.6, -0.6, 2.35), rot=(0.3, 0, 0)), "wood")
    P(box("load", (0.3, 0.3, 0.3), at=(1.6, 0.1, 1.5)), "stone")
    wheel_part("Wheel_parts", 0.35, (0.4, -1.6, 0.35))
    P(box("beam", (1.6, 0.15, 0.15), at=(-0.6, -1.5, 0.1)), "wood")
    flag((-0.4, 0.6), 2.4 if s == "NE" else 1.8, 0.8)


def spy(s, w, d):
    ground(w, d, "stone_dark")
    house(s, 2.0, 1.6, 0.9, (-0.4, 0.4))
    tower(0.45, 1.8, (1.0, -0.6), "stone", {"NE": "cone", "ME": "crenel", "EA": "pagoda", "MA": "dome"}[s], "cloth")
    P(sphere("hedge", 0.5, 8, 4, at=(-1.4, -1.3, 0), scale=(1.3, 0.6, 0.8), cut=0.0), "plant")


def stable(s, w, d):
    ground(w, d, "cloth_dark")
    house(s, 3.2, 1.4, 0.9, (-0.2, 1.0))
    x0, x1, y0, y1 = -2.4, 2.4, -2.4, 0.1
    for a, b in [((x0, y0), (x1, y0)), ((x0, y0), (x0, y1)), ((x1, y0), (x1, y1))]:
        L = math.hypot(b[0] - a[0], b[1] - a[1])
        n = int(L / 0.6)
        for i in range(n + 1):
            f = i / n
            P(box("fpost", (0.07, 0.07, 0.5), at=(a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, 0.25)), "wood")
        P(box("frail", (abs(b[0] - a[0]) + 0.05, abs(b[1] - a[1]) + 0.05, 0.05), at=((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, 0.4)), "wood")
    P(sphere("hay", 0.35, 8, 4, at=(1.6, 1.2, 0), scale=(1.0, 1.0, 0.8), cut=0.0), "leather")
    P(box("trough", (0.8, 0.25, 0.2), at=(0.5, -1.0, 0.1)), "wood")
    flag((-0.2, 1.0), 1.6, 0.8)


def temple(s, w, d, race=""):
    ground(w, d, "stone")
    if s == "NE":       # cathedral with spires
        blk(1.6, 3.6, 1.6, (0, 0.4), "stone")
        gable(1.6, 3.6, 1.0, (0, 0.4), 1.6, "cloth", along_x=False)
        tower(0.45, 2.6, (-0.55, -1.5), "stone", "cone", "cloth")
        tower(0.45, 2.6, (0.55, -1.5), "stone", "cone", "cloth")
        P(cone("spire", 0.3, 0.02, 1.4, 8, at=(0, 1.2, 3.1)), "cloth")
    elif s == "ME":     # classical temple
        blk(3.6, 2.6, 0.3, (0, 0.2), "stone")
        blk(2.6, 1.8, 1.4, (0, 0.3), "linen", 0.3)
        for i in range(6):
            for y in (-1.0, 1.4):
                P(cone("column", 0.12, 0.12, 1.4, 8, at=(-1.5 + i * 0.6, y - 0.1, 1.0)), "trim")
        gable(3.4, 2.6, 0.7, (0, 0.2), 1.7, "cloth", along_x=True)
        if race == "CARTH":
            P(cone("obelisk", 0.2, 0.05, 1.6, 4, at=(-2.0, -2.0, 0.8)), "stone")
    elif s == "EA":     # pagoda
        blk(2.0, 2.0, 0.9, (0, 0.2), "linen")
        pagoda(2.4, 2.4, 1.1, (0, 0.2), 0.9, "cloth", tiers=4)
        P(cone("finial", 0.06, 0.02, 0.8, 6, at=(0, 0.2, 4.1)), "trim")
    else:               # MA: domed temple, or a stepped pyramid for Egypt
        if race == "EGYPTIAN":
            for i in range(5):
                k = 4.4 - i * 0.8
                blk(k, k, 0.5, (0, 0), "stone" if i % 2 == 0 else "stone_dark", i * 0.5)
            P(cone("cap", 0.6, 0.0, 0.6, 4, at=(0, 0, 2.8), rot=(0, 0, math.radians(45))), "trim")
        else:
            blk(3.0, 3.0, 1.4, (0, 0.2), "stone")
            P(sphere("dome", 1.3, 14, 7, at=(0, 0.2, 1.4), cut=0.0), "cloth")
            for sx in (-1, 1):
                for sy in (-1, 1):
                    tower(0.22, 2.4, (sx * 1.6, 0.2 + sy * 1.6), "stone", "dome", "cloth")
    flag((1.8, -1.8), 0.0, 1.6)


def wheel_part(name, r, at):
    import props
    o = props.wheel(name, r, at=at)
    o.rotation_euler = (0, 0, math.radians(90))
    PARTS.append(o)
    return o


# ---------------------------------------------------------------- Fryhtans ---

def lair(w, d, kind="LAIR", seed=1):
    """Fryhtan lairs: lumpy mounds with spikes, a cave mouth and bones."""
    rnd = random.Random(seed)
    ground(w, d, "cloth_dark")
    body = {"LAIR": "stone", "BEE": "chitin", "TERMITE": "leather"}.get(kind, "stone")
    if kind == "BEE":
        for i in range(4):
            P(sphere("hive", 1.3 - i * 0.25, 10, 6, at=(0, 0.2, 0.6 + i * 0.6), scale=(1, 1, 0.55)), body)
        P(sphere("hole", 0.25, 8, 4, at=(0.9, -0.5, 0.9), scale=(1, 0.3, 1)), "black")
    elif kind == "TERMITE":
        P(cone("mound", 1.6, 0.25, 3.2, 10, at=(0, 0.2, 1.6)), body)
        for i in range(5):
            a = i * 1.3
            P(cone("spire", 0.35, 0.05, 1.4 + rnd.random(), 6, at=(math.cos(a) * 1.0, 0.2 + math.sin(a) * 1.0, 0.8)), body)
    else:
        for i in range(7):
            a = i * 0.9
            r = rnd.uniform(0.8, 1.4)
            P(sphere("mound", r, 8, 5, at=(math.cos(a) * 0.9, math.sin(a) * 0.9 + 0.3, 0), scale=(1, 1, 0.9), cut=0.0), rnd.choice(["stone", "stone_dark", "cloth"]))
        P(sphere("cave", 0.55, 8, 5, at=(0.6, -1.0, 0.1), scale=(1.0, 0.4, 1.0), cut=0.0), "black")
        for i in range(9):
            a = i * 0.7
            P(cone("spike", 0.12, 0.0, 1.0 + rnd.random(), 5, at=(math.cos(a) * 1.7, 0.3 + math.sin(a) * 1.7, 0.6), rot=(rnd.uniform(-0.3, 0.3), rnd.uniform(-0.3, 0.3), 0)), "bone")
        P(sphere("glow", 0.25, 8, 4, at=(0, 0.3, 1.6)), "glow")
    for i in range(4):
        P(box("bone", (0.4, 0.06, 0.06), at=(rnd.uniform(-2, 2), rnd.uniform(-2, -1), 0.04), rot=(0, 0, rnd.random() * 3)), "bone")
    flag((-1.8, -1.8), 0.0, 1.2)


def fry_building(w, d, kind, seed=2):
    """The other Fryhtan buildings: organic towers and pods in the lair style."""
    rnd = random.Random(seed)
    ground(w, d, "cloth_dark")
    n = max(1, int(w * d / 6))
    for i in range(n):
        x, y = rnd.uniform(-w / 3, w / 3), rnd.uniform(-d / 3, d / 3)
        h = rnd.uniform(1.0, 2.6) * min(1.0, w / 4)
        P(cone("pod", 0.6 * min(1, w / 4), 0.15, h, 8, at=(x, y, h / 2)), rnd.choice(["stone", "chitin", "cloth"]))
        P(sphere("bulb", 0.35 * min(1, w / 4), 8, 4, at=(x, y, h)), rnd.choice(["glow", "flesh", "trim"]))
    flag((-w / 2 + 0.4, -d / 2 + 0.4), 0.0, 1.0)


# --------------------------------------------------------------- town houses ---

def town_house(s, size, seed):
    """Houses for town slots: size 1 hut .. 3 large."""
    rnd = random.Random(seed)
    w, d, h = [(0.9, 0.8, 0.6), (1.2, 1.0, 0.75), (1.5, 1.2, 0.9)][size - 1]
    if rnd.random() < 0.5:
        w, d = d, w
    house(s, w, d, h, (0, 0))
    if size == 3 and s in ("NE", "ME"):
        P(box("chimney", 0.18, 0.18, 0.5) if False else box("chimney", (0.18, 0.18, 0.5), at=(w * 0.25, 0, h + 0.5)), "stone")


# --------------------------------------------------------------- town walls ---

def town_wall(s, level, size=6.0):
    """Ring around a town (6 x 6 locations) with a gate towards the camera.
    level 0: fence, 1: wall, 2: fortified wall with towers."""
    h = size / 2 - 0.15
    sides = [((-h, -h), (h, -h)), ((h, -h), (h, h)), ((h, h), (-h, h)), ((-h, h), (-h, -h))]
    gate = 1.0                      # gap in the front (-y) side
    for i, (a, b) in enumerate(sides):
        segs = [(a, b)]
        if i == 0:
            segs = [(a, (-gate / 2, a[1])), ((gate / 2, a[1]), b)]
        for p0, p1 in segs:
            if level == 0:
                L = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
                n = max(1, int(L / 0.5))
                for k in range(n + 1):
                    f = k / n
                    P(box("picket", (0.06, 0.06, 0.45), at=(p0[0] + (p1[0] - p0[0]) * f, p0[1] + (p1[1] - p0[1]) * f, 0.22)), "wood")
                ang = math.atan2(p1[1] - p0[1], p1[0] - p0[0])
                P(box("rail", (L, 0.04, 0.05), at=((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2, 0.32), rot=(0, 0, ang)), "wood")
            else:
                crenel_wall(p0[0], p0[1], p1[0], p1[1], 0.6 if level == 1 else 0.85, "stone" if s != "MA" else "linen", 0.22)
    if level == 2:
        roof = {"NE": "cone", "ME": "crenel", "EA": "pagoda", "MA": "dome"}[s]
        for cx, cy in [(-h, -h), (h, -h), (h, h), (-h, h), (-gate / 2 - 0.2, -h), (gate / 2 + 0.2, -h)]:
            tower(0.28, 1.15, (cx, cy), "stone" if s != "MA" else "linen", roof, "cloth" if s != "NE" else "trim")


# ----------------------------------------------------------------- export ---

FOOTPRINTS = {}


def save_footprints():
    import json
    path = os.path.join(OUT, "buildings", "footprints.json")
    data = json.load(open(path)) if os.path.exists(path) else {}
    data.update(FOOTPRINTS)
    json.dump(data, open(path, "w"), indent=0, sort_keys=True)


def export(name, style, sub="buildings", size=None):
    if size:
        FOOTPRINTS[name] = list(size)
    mat = palette_material(make_palette("pal_bld_" + style, STYLE_COLORS[style]))
    moving = [o for o in PARTS if o.name.startswith("Wheel") or o.name.startswith("Flag")]
    static = [o for o in PARTS if o not in moving]
    for o in PARTS:
        o.data.materials.clear()
        o.data.materials.append(mat)
    body = join("Body", static)
    objs = [body] + moving
    path = os.path.join(OUT, sub, name + ".glb")
    export_glb(path, objs)
    print("BUILT", name)
    PARTS.clear()


FIRMS = {"FORT": (6, 6, fort), "CAMP": (6, 6, camp), "MINE": (6, 6, mine), "FACTORY": (6, 6, factory),
         "MARKET": (5, 5, market), "INN": (5, 5, inn), "RESEARCH": (5, 5, research), "WAR": (6, 6, war),
         "SPY": (5, 5, spy)}


def build_all(only=()):
    for code, (w, d, f) in FIRMS.items():
        for s in ("NE", "ME", "EA", "MA"):
            name = "%s_%s" % (code, s)
            if only and name not in only and code not in only:
                continue
            reset(); f(s, w, d); export(name, s, size=(w, d))
    for race, s in RACE_STYLE.items():
        for code, fn in (("STABLE", stable), ("BASE", temple)):
            name = "%s_%s" % (code, race)
            if only and name not in only and code not in only:
                continue
            reset()
            fn(s, 6, 6) if code == "STABLE" else fn(s, 6, 6, race)
            export(name, s, size=(6, 6))
    for s in ("NE", "ME", "EA", "MA"):
        for size in (1, 2, 3):
            for v in range(2):
                name = "house_%s_%d%s" % (s, size, "ab"[v])
                if only and name not in only and "houses" not in only:
                    continue
                reset(); town_house(s, size, size * 7 + v); export(name, s, "houses")
    for st in ("NE", "ME", "EA", "MA"):
        for level in (0, 1, 2):
            name = "wall_%s_%d" % (st, level)
            if only and name not in only and "walls" not in only:
                continue
            reset(); town_wall(st, level); export(name, st, "houses")
    fry = {"LAIR": (6, 6), "BEE": (5, 5), "TERMITE": (5, 5)}
    for code, (w, d) in fry.items():
        if only and code not in only:
            continue
        reset(); lair(w, d, code); export(code, "FRY", size=(w, d))
    others = {"LISHORR": (2, 2), "WLISHORR": (2, 2), "ALCHEMY": (6, 6), "INCUBAT": (6, 6), "ANIMAL": (6, 6),
              "FORTRESS": (4, 4), "MAGIC": (5, 5), "OFF_BLD1": (6, 6), "OFF_BLD2": (6, 6), "OFF_BLD3": (6, 6), "OFF_BLD4": (5, 5)}
    for i, (code, (w, d)) in enumerate(others.items()):
        if only and code not in only:
            continue
        reset(); fry_building(w, d, code, i + 3); export(code, "FRY", size=(w, d))


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    build_all(args)
    save_footprints()
