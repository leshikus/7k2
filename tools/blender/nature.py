"""Builds trees (the original's 15 species), bushes, rocks, mountains, raw-material
deposits and the town flag. All procedural: trunks plus jittered low-poly crowns.

blender -b --factory-startup -P tools/blender/nature.py -- [name ...]
"""
import sys, os, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, bmesh
from mathutils import Vector
from common import *
from common import _mesh_obj

NATURE_COLORS = {"wood": "#6a4a32", "leather_dark": "#4a3424", "plant": "#4f8a3a", "plant_dark": "#2e5a2a",
                 "stone": "#9a958c", "stone_dark": "#6e6a62", "cloth": "#8a3a8a", "cloth2": "#d87a2a",
                 "cloth_dark": "#b84a2a", "linen": "#a8c860", "trim": "#d8c040", "leather": "#c88a5a",
                 "metal": "#b87a4a", "metal_dark": "#5a5c62", "flesh": "#c86040", "fur": "#7a9a4a",
                 "skin": "#3a6a3a", "hair": "#8ab84a", "bone": "#c8b890", "black": "#2a2420"}
PARTS = []


def P(o, role, shade=None):
    PARTS.append(colored(o, role, shade))
    return o


def blob(r, at, role, seed, scale=(1, 1, 1), segs=7, rings=5):
    """A jittered sphere: one clump of foliage or one rock."""
    rnd = random.Random(seed)
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=r)
    for v in bm.verts:
        v.co *= 1.0 + rnd.uniform(-0.18, 0.18)
        v.co = Vector((v.co.x * scale[0], v.co.y * scale[1], v.co.z * scale[2]))
    o = _mesh_obj("blob", bm)
    o.location = at
    return P(o, role)


def trunk(h, r, at=(0, 0, 0), lean=(0, 0), role="wood"):
    o = cone("trunk", r, r * 0.6, h, 6, at=(at[0] + lean[0] * h / 2, at[1] + lean[1] * h / 2, h / 2), rot=(-lean[1], lean[0], 0))
    return P(o, role)


def crown(n, r, h, spread, roles, seed, squash=0.85, top=0.0):
    rnd = random.Random(seed)
    for i in range(n):
        a = rnd.uniform(0, 2 * math.pi)
        d = rnd.uniform(0, spread)
        z = h + rnd.uniform(-r * 0.4, r * 0.5) + top * i / max(1, n - 1)
        blob(r * rnd.uniform(0.75, 1.1), (math.cos(a) * d, math.sin(a) * d, z), rnd.choice(roles), seed + i, (1, 1, squash))


def tree_A(s):   # purple flowering bush
    crown(5, 0.45, 0.45, 0.3, ["cloth", "cloth"], s, 0.9)


def tree_B(s):   # bamboo clump
    rnd = random.Random(s)
    for i in range(7):
        x, y = rnd.uniform(-0.3, 0.3), rnd.uniform(-0.3, 0.3)
        h = rnd.uniform(1.4, 2.0)
        P(cone("cane", 0.035, 0.03, h, 5, at=(x, y, h / 2)), "linen")
        blob(0.16, (x, y, h), "plant", s + i, (1.4, 1.4, 0.5))


def tree_C(s):   # orange-flowered tree
    trunk(1.0, 0.1); crown(6, 0.42, 1.25, 0.45, ["plant", "plant_dark", "cloth2"], s)


def tree_D(s):   # red-orange autumn tree
    trunk(1.1, 0.09); crown(5, 0.4, 1.35, 0.35, ["cloth_dark", "cloth2", "plant_dark"], s, 1.1, 0.4)


def tree_E(s):   # yellow-green layered tree
    trunk(0.9, 0.1); crown(6, 0.42, 1.15, 0.45, ["trim", "linen", "plant"], s)


def tree_F(s):   # dark round tree
    trunk(0.8, 0.1); crown(5, 0.5, 1.15, 0.3, ["plant_dark", "skin"], s)


def tree_G(s):   # oak
    trunk(1.0, 0.14); crown(8, 0.48, 1.35, 0.6, ["plant", "plant_dark", "fur"], s, 0.8)


def tree_H(s):   # broad flat-crowned tree
    trunk(1.2, 0.12, lean=(0.1, 0)); crown(7, 0.42, 1.45, 0.75, ["plant_dark", "plant"], s, 0.6)


def tree_I(s):   # willow: drooping fronds
    trunk(1.3, 0.13)
    rnd = random.Random(s)
    for i in range(9):
        a = i * 2 * math.pi / 9
        P(cone("frond", 0.32, 0.12, 1.3, 5, at=(math.cos(a) * 0.45, math.sin(a) * 0.45, 1.15)), rnd.choice(["fur", "plant"]))
    blob(0.6, (0, 0, 1.85), "fur", s, (1, 1, 0.6))


def tree_K(s):   # sparse small tree
    trunk(1.0, 0.07, lean=(0.08, 0.05)); crown(4, 0.22, 1.1, 0.45, ["plant", "linen"], s)


def tree_L(s):   # light green round tree
    trunk(0.8, 0.11); crown(6, 0.48, 1.15, 0.38, ["hair", "linen", "plant"], s)


def tree_M(s):   # tall thin tree
    trunk(2.0, 0.08); crown(4, 0.28, 1.6, 0.25, ["plant", "linen"], s, 1.0, 0.7)


def tree_N(s):   # cypress / conifer
    trunk(0.4, 0.1)
    for i in range(3):
        P(cone("needles", 0.42 - i * 0.1, 0.06, 0.9, 7, at=(0, 0, 0.75 + i * 0.55)), "plant_dark" if i % 2 == 0 else "skin")


def tree_O(s):   # orange autumn tree
    trunk(1.0, 0.1); crown(6, 0.42, 1.3, 0.42, ["cloth2", "cloth2", "cloth_dark"], s)


def tree_T(s):   # small palm / fern
    trunk(0.9, 0.06, lean=(0.12, 0))
    for i in range(7):
        a = i * 2 * math.pi / 7
        o = box("leaf", (0.6, 0.14, 0.03), at=(0.1 + math.cos(a) * 0.3, math.sin(a) * 0.3, 0.9), rot=(0, 0.45, a))
        P(o, "plant")


SPECIES = {"TREE-A": tree_A, "TREE-B": tree_B, "TREE-C": tree_C, "TREE-D": tree_D, "TREE-E": tree_E,
           "TREE-F": tree_F, "TREE-G": tree_G, "TREE-H": tree_H, "TREE-I": tree_I, "TREE-K": tree_K,
           "TREE-L": tree_L, "TREE-M": tree_M, "TREE-N": tree_N, "TREE-O": tree_O, "TREE-T": tree_T}


def export(name):
    mat = palette_material(make_palette("pal_nature", NATURE_COLORS))
    for o in PARTS:
        o.data.materials.clear()
        o.data.materials.append(mat)
    body = join(name, list(PARTS))
    export_glb(os.path.join(OUT, "nature", name + ".glb"), [body])
    PARTS.clear()
    print("BUILT", name)


def build_rock(name, seed, n=3, size=0.5, roles=("stone", "stone_dark")):
    rnd = random.Random(seed)
    for i in range(n):
        blob(size * rnd.uniform(0.6, 1.0), (rnd.uniform(-0.3, 0.3), rnd.uniform(-0.3, 0.3), size * 0.25), rnd.choice(roles), seed + i, (1, 1, 0.65))


def build_mountain(seed):
    """A rocky peak filling a unit footprint (the game scales it to the rock's size)."""
    rnd = random.Random(seed)
    for i in range(6):
        a = rnd.uniform(0, 2 * math.pi)
        d = rnd.uniform(0, 0.25)
        blob(rnd.uniform(0.3, 0.45), (math.cos(a) * d, math.sin(a) * d, rnd.uniform(0.1, 0.35)), rnd.choice(["stone", "stone_dark"]), seed + i, (1, 1, 1.4))


def build_deposit(kind):
    roles = {"clay": ("leather", "flesh"), "copper": ("metal", "trim"), "iron": ("metal_dark", "stone_dark")}[kind]
    rnd = random.Random(len(kind))
    for i in range(9):
        blob(rnd.uniform(0.15, 0.3), (rnd.uniform(-0.8, 0.8), rnd.uniform(-0.8, 0.8), 0.08), rnd.choice(roles + ("stone",)), i, (1, 1, 0.6))


def build_flag():
    P(cone("pole", 0.04, 0.03, 1.8, 5, at=(0, 0, 0.9)), "wood")
    P(box("flag", (0.55, 0.03, 0.36), at=(0.28, 0, 1.6)), "team")


def main(args):
    for code, f in SPECIES.items():
        n = "tree_" + code[-1]
        if not args or n in args:
            reset(); f(ord(code[-1])); export(n)
    for i in range(3):
        if not args or "bush" in args:
            reset(); crown(3, 0.28, 0.25, 0.2, ["plant", "plant_dark", "fur"], 50 + i); export("bush_%d" % i)
    for i in range(4):
        if not args or "rock" in args:
            reset(); build_rock("rock_%d" % i, 70 + i); export("rock_%d" % i)
    for i in range(3):
        if not args or "mountain" in args:
            reset(); build_mountain(90 + i); export("mountain_%d" % i)
    for k in ("clay", "copper", "iron"):
        if not args or "deposit" in args:
            reset(); build_deposit(k); export("deposit_" + k)
    if not args or "flag" in args:
        reset(); build_flag()
        mat = palette_material(make_palette("pal_nature", NATURE_COLORS))
        for o in PARTS:
            o.data.materials.clear(); o.data.materials.append(mat)
        body = join("flag", list(PARTS)); PARTS.clear()
        export_glb(os.path.join(OUT, "houses", "flag.glb"), [body]); print("BUILT flag")


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
