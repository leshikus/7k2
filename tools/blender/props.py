"""Builds rigid (unskinned) models: carts, siege weapons, projectiles.

blender -b --factory-startup -P tools/blender/props.py -- [name ...]

Moving parts are separate objects with fixed names the game animates by code:
  Wheel*   spins about its local x axis while the unit moves
  Arm      throwing arm (catapult): swings about local x on attack
  Barrel   recoils along local z on attack
  Saw      spins about local z while attacking
Models face +z in Godot (-y in Blender), like the characters.
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from mathutils import Vector, Matrix
from common import *

PROP_COLORS = {"wood": "#8a5e3c", "leather": "#7a4e32", "metal": "#8a9094", "metal_dark": "#4a4e52",
               "linen": "#e0d8c4", "trim": "#d8b048", "stone": "#9a958c", "black": "#202024",
               "cloth2": "#c8b080", "flesh": "#b07858", "chitin": "#7a8a3a", "plant": "#5a8a3a"}


def mat_props(name="props", extra=None):
    cols = dict(PROP_COLORS)
    cols.update(extra or {})
    return palette_material(make_palette("pal_" + name, cols))


def wheel(name, r=0.3, w=0.08, at=(0, 0, 0), spokes=6, role="wood"):
    """A wheel turning about x (its axle)."""
    rim = colored(torus(name + "_rim", r, w * 0.6, 12, 4, rot=(0, math.radians(90), 0)), role)
    hub = colored(cone(name + "_hub", w, w, w * 2.2, 6, rot=(0, math.radians(90), 0)), "metal_dark")
    parts = [rim, hub]
    for i in range(spokes):
        a = math.pi * i / spokes
        parts.append(colored(box(name + "_sp", (0.03, 0.03, r * 2), rot=(a, 0, 0)), role))
    o = join(name, parts)
    o.location = at
    return o


def finish(name, objs, sub="props"):
    path = os.path.join(OUT, sub, name + ".glb")
    mat = bpy.data.materials.get("M_pal_props") or mat_props()
    for o in objs:
        if not o.data.materials:
            o.data.materials.append(mat)
    export_glb(path, objs)
    print("BUILT", name, path)


def build_chariot():
    reset()
    mat = mat_props()
    floor = colored(box("Floor", (0.75, 0.6, 0.06), at=(0, 0.1, 0.32)), "wood")
    front = colored(box("Front", (0.75, 0.05, 0.42), at=(0, -0.2, 0.55)), "team")
    sides = [colored(box("Side", (0.05, 0.5, 0.32), at=(s * 0.38, 0.05, 0.5)), "team") for s in (-1, 1)]
    rail = colored(torus("Rail", 0.38, 0.025, 10, 4, at=(0, -0.0, 0.78), arc=0.5, rot=(0, 0, math.radians(180))), "trim")
    pole = colored(box("Pole", (0.06, 1.7, 0.06), at=(0, -1.05, 0.38)), "wood")
    yoke = colored(box("Yoke", (1.1, 0.06, 0.06), at=(0, -1.8, 0.7)), "wood")
    body = join("Chariot", [floor, front, rail, pole, yoke] + sides)
    w1 = wheel("Wheel_L", 0.34, at=(-0.46, 0.15, 0.34))
    w2 = wheel("Wheel_R", 0.34, at=(0.46, 0.15, 0.34))
    for o in (body, w1, w2):
        o.data.materials.clear()
        o.data.materials.append(mat)
    finish("chariot", [body, w1, w2])


def build_wagon(name="wagon", cover="team"):
    reset()
    mat = mat_props()
    bed = colored(box("Bed", (0.9, 1.6, 0.12), at=(0, 0.2, 0.42)), "wood")
    sides = [colored(box("Side", (0.05, 1.6, 0.25), at=(s * 0.45, 0.2, 0.58)), "wood") for s in (-1, 1)]
    hoops = []
    for i in range(4):
        y = -0.45 + i * 0.43
        hoops.append(colored(torus("Hoop", 0.45, 0.02, 10, 4, at=(0, y, 0.68), rot=(math.radians(90), 0, 0), arc=0.5), "wood"))
    canvas = colored(sphere("Cover", 0.5, 10, 6, at=(0, 0.2, 0.66), scale=(0.95, 1.75, 1.15), cut=0.0), cover)
    crates = [colored(box("Crate", (0.3, 0.3, 0.3), at=(0.15, 1.05, 0.62)), "wood")]
    pole = colored(box("Pole", (0.06, 1.0, 0.06), at=(0, -0.95, 0.38)), "wood")
    body = join("Wagon", [bed, canvas, pole] + sides + hoops + crates)
    wheels = [wheel("Wheel_%d" % i, 0.27, at=(sx * 0.52, sy, 0.27)) for i, (sx, sy) in enumerate([(-1, -0.35), (1, -0.35), (-1, 0.75), (1, 0.75)])]
    for o in [body] + wheels:
        o.data.materials.clear()
        o.data.materials.append(mat)
    finish(name, [body] + wheels)


# ------------------------------------------------------------ siege weapons ---

def _frame(w=0.9, l=1.4, h=0.35, role="wood"):
    """A wheeled chassis: two side beams and cross beams; returns (parts, wheels)."""
    parts = [colored(box("Beam", (0.1, l, 0.12), at=(s * w / 2, 0, h)), role) for s in (-1, 1)]
    parts += [colored(box("Cross", (w, 0.1, 0.1), at=(0, y, h)), role) for y in (-l / 2 + 0.1, 0, l / 2 - 0.1)]
    wheels = [wheel("Wheel_%d" % i, 0.25, at=(sx * (w / 2 + 0.08), sy * (l / 2 - 0.2), 0.25))
              for i, (sx, sy) in enumerate([(-1, -1), (1, -1), (-1, 1), (1, 1)])]
    return parts, wheels


def _export(name, body_parts, moving, extra=None):
    mat = mat_props(name, extra)
    body = join("Body", body_parts)
    objs = [body] + moving
    for o in objs:
        o.data.materials.clear()
        o.data.materials.append(mat)
    finish(name, objs, "siege")


BIO_COLORS = {"chitin": "#7a8a3a", "flesh": "#b05050"}


def build_catapult(name="CATAPULT", bio=False):
    reset()
    role, metal = ("chitin", "flesh") if bio else ("wood", "metal_dark")
    parts, wheels = _frame(0.9, 1.5, 0.4, role)
    parts += [colored(box("Upright", (0.1, 0.1, 0.7), at=(s * 0.35, 0.2, 0.75)), role) for s in (-1, 1)]
    parts += [colored(box("Stop", (0.8, 0.1, 0.1), at=(0, 0.2, 1.1)), role)]
    arm = join("Arm", [colored(box("ArmBeam", (0.1, 1.3, 0.1), at=(0, -0.55, 0)), role),
                       colored(sphere("Cup", 0.16, 8, 4, at=(0, -1.2, 0.08), cut=0.0), metal),
                       colored(box("Weight", (0.35, 0.3, 0.35), at=(0, 0.2, -0.1)), "stone")])
    arm.location = (0, 0.15, 0.55)
    if bio:
        parts += [colored(sphere("Shell", 0.6, 8, 5, at=(0, 0.3, 0.55), scale=(1.0, 1.3, 0.5), cut=0.0), "chitin")]
    _export(name, parts, [arm] + wheels, BIO_COLORS if bio else None)


def build_ballista(name="BALLISTA", bio=False, unicorn=False):
    reset()
    role = "chitin" if bio else "wood"
    parts, wheels = _frame(0.8, 1.3, 0.35, role)
    parts += [colored(box("Stock", (0.14, 1.4, 0.12), at=(0, -0.1, 0.62)), role),
              colored(box("Post", (0.12, 0.12, 0.3), at=(0, 0.2, 0.45)), role)]
    bow = colored(torus("Bow", 0.75, 0.04, 10, 4, at=(0, 0.35, 0.62), rot=(0, 0, math.radians(-90 - 50)), arc=0.28),
                  "flesh" if bio else "metal_dark")
    bolt = colored(box("Bolt", (0.04, 1.1, 0.04), at=(0, -0.3, 0.7)), "metal")
    parts += [bow, bolt]
    if unicorn:
        parts += [colored(cone("Horn", 0.1, 0.0, 0.8, 6, at=(0, -1.15, 0.65), rot=(math.radians(90), 0, 0)), "trim"),
                  colored(sphere("Head", 0.25, 8, 5, at=(0, -0.8, 0.65), scale=(0.9, 1.3, 0.9)), "linen")]
    if bio:
        parts += [colored(sphere("Shell", 0.55, 8, 5, at=(0, 0.25, 0.5), scale=(1.0, 1.2, 0.6), cut=0.0), "chitin")]
    _export(name, parts, wheels, {"chitin": "#6a7a8a", "flesh": "#a05060"} if bio else None)


def build_cannon(name="CANNON", big=False, bio=False):
    reset()
    k = 1.5 if big else 1.0
    role = "chitin" if bio else "wood"
    tube = "flesh" if bio else "metal_dark"
    trail = colored(box("Trail", (0.3, 1.2 * k, 0.12), at=(0, 0.45 * k, 0.25)), role)
    cheeks = [colored(box("Cheek", (0.08, 0.5 * k, 0.35 * k), at=(s * 0.22 * k, -0.05, 0.42 * k)), role) for s in (-1, 1)]
    wheels = [wheel("Wheel_%d" % i, 0.35 * k, at=(s * 0.38 * k, -0.05, 0.35 * k)) for i, s in enumerate((-1, 1))]
    barrel = join("Barrel", [colored(cone("Tube", 0.16 * k, 0.12 * k, 1.2 * k, 10, at=(0, -0.4 * k, 0), rot=(math.radians(-90), 0, 0)), tube),
                             colored(torus("Muzzle", 0.13 * k, 0.04 * k, 10, 4, at=(0, -1.0 * k, 0), rot=(math.radians(90), 0, 0)), "metal" if not bio else "flesh"),
                             colored(sphere("Breech", 0.17 * k, 8, 5, at=(0, 0.2 * k, 0)), tube)])
    barrel.location = (0, 0, 0.6 * k)
    _export(name, [trail] + cheeks, [barrel] + wheels, {"chitin": "#5a4a6a", "flesh": "#8a5070"} if bio else None)


def build_spitfire():
    reset()
    parts, wheels = _frame(0.9, 1.4, 0.35)
    tank = colored(cone("Tank", 0.35, 0.35, 0.8, 10, at=(0, 0.25, 0.65), rot=(math.radians(-90), 0, 0)), "metal_dark")
    head = join("Barrel", [colored(cone("Neck", 0.12, 0.1, 0.8, 8, at=(0, -0.4, 0), rot=(math.radians(-90), 0, 0)), "metal"),
                           colored(sphere("Dragon", 0.22, 8, 5, at=(0, -0.85, 0.05), scale=(0.9, 1.4, 0.9)), "trim"),
                           colored(cone("Jaw", 0.1, 0.02, 0.3, 6, at=(0, -1.1, -0.05), rot=(math.radians(-90), 0, 0)), "trim")])
    head.location = (0, 0, 0.75)
    _export("FLAMETHR", parts + [tank], [head] + wheels)


def build_porcupine():
    reset()
    parts, wheels = _frame(0.9, 1.3, 0.35)
    keg = colored(cone("Keg", 0.42, 0.42, 0.9, 10, at=(0, 0, 0.75), rot=(math.radians(-90), 0, 0)), "wood")
    spikes = []
    for i in range(14):
        a = i * 2 * math.pi / 7
        y = -0.3 if i < 7 else 0.3
        d = Vector((math.cos(a), 0, math.sin(a)))
        o = cone("Spike", 0.05, 0.0, 0.4, 4, at=Vector((0, y, 0.75)) + d * 0.55)
        o.rotation_mode = "QUATERNION"
        o.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d)
        spikes.append(colored(o, "metal"))
    _export("EXPCART", parts + [keg] + spikes, wheels)


def build_megasaw():
    reset()
    parts, wheels = _frame(1.2, 1.8, 0.45)
    parts += [colored(box("Housing", (0.9, 0.9, 0.6), at=(0, 0.3, 0.85)), "metal_dark"),
              colored(box("Boom", (0.15, 0.9, 0.15), at=(0, -0.55, 0.9)), "wood")]
    teeth = []
    for i in range(16):
        a = i * math.pi / 8
        teeth.append(colored(cone("Tooth", 0.06, 0.0, 0.14, 3, at=(0, math.cos(a) * 0.62, math.sin(a) * 0.62),
                                  rot=(a - math.pi / 2, 0, 0)), "metal"))
    blade = join("Saw", [colored(cone("Blade", 0.6, 0.6, 0.04, 16, rot=(0, math.radians(90), 0)), "metal")] + teeth)
    blade.location = (0, -1.0, 0.9)
    _export("M_SAW", parts, [blade] + wheels)


# --------------------------------------------------------------- projectiles ---

def _arrow():
    return join("arrow", [colored(box("shaft", (0.025, 0.7, 0.025)), "wood"),
                          colored(cone("tip", 0.04, 0.0, 0.1, 4, at=(0, -0.4, 0), rot=(math.radians(90), 0, 0)), "metal"),
                          colored(box("fletch", (0.1, 0.12, 0.01), at=(0, 0.32, 0)), "linen")])


def _javelin(length=1.2, r=0.035):
    return join("javelin", [colored(box("shaft", (r, length, r)), "wood"),
                            colored(cone("tip", r * 1.5, 0.0, 0.18, 4, at=(0, -length / 2 - 0.08, 0), rot=(math.radians(90), 0, 0)), "metal")])


PROJECTILES = {   # they point along +z in Godot (-y here)
    "arrow": _arrow,
    "javelin": _javelin,
    "bolt": lambda: _javelin(1.1, 0.05),
    "axe": lambda: join("axe", [colored(box("haft", (0.04, 0.5, 0.04)), "wood"),
                                colored(box("head", (0.04, 0.12, 0.2), at=(0, -0.2, 0.08)), "metal")]),
    "stone": lambda: colored(sphere("stone", 0.2, 7, 5, scale=(1, 0.9, 0.85)), "stone"),
    "cannonball": lambda: colored(sphere("cannonball", 0.12, 8, 5), "black"),
    "fireball": lambda: colored(sphere("fireball", 0.18, 8, 5), "fire"),
    "spit": lambda: colored(sphere("spit", 0.12, 6, 4, scale=(1, 1.6, 1)), "plant"),
    "shuriken": lambda: join("shuriken", [colored(box("a", (0.2, 0.2, 0.02), rot=(0, 0, math.radians(45))), "metal"),
                                          colored(box("b", (0.2, 0.2, 0.02)), "metal")]),
    "spark": lambda: colored(sphere("spark", 0.15, 6, 4), "glow"),
}


def build_projectiles():
    for n, f in PROJECTILES.items():
        reset()
        mat = mat_props("projectiles", {"fire": "#ff8a20", "glow": "#9fe8ff"})
        o = f()
        o.data.materials.clear()
        o.data.materials.append(mat)
        finish(n, [o], "projectiles")


BUILDS = {"chariot": build_chariot, "wagon": build_wagon,
          "caravan": lambda: build_wagon("caravan", "linen"),
          "CATAPULT": build_catapult, "BALLISTA": build_ballista, "FLAMETHR": build_spitfire,
          "CANNON": build_cannon, "EXPCART": build_porcupine, "M_SAW": build_megasaw,
          "F_BALLIS": lambda: build_ballista("F_BALLIS", unicorn=True),
          "M_CANNON": lambda: build_cannon("M_CANNON", big=True),
          "M_F_BALL": lambda: build_ballista("M_F_BALL", unicorn=True),
          "F_CANNON": lambda: build_cannon("F_CANNON", bio=True),
          "F__BALLI": lambda: build_ballista("F__BALLI", bio=True),
          "F_CATAPU": lambda: build_catapult("F_CATAPU", bio=True),
          "projectiles": build_projectiles}

if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for n, f in BUILDS.items():
        if not args or n in args:
            f()
