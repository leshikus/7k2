"""Builds the Fryhtans and wild animals.

blender -b --factory-startup -P tools/blender/fryhtans.py -- [CODE ...]

The humanoid Fryhtans (and the gorilla) are the KayKit humanoid rig with new
"skins": recoloured KayKit body parts plus procedural horns, tails, claws, plates
and growths, so they play the shared humanoid clips. The insects use Quaternius'
cute-monster rigs (bee, crab), the jaguar the cat rig with extra clips keyed here.
"""
import sys, os, math, random
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from mathutils import Vector, Matrix, Euler, Quaternion
from common import *
import humans

# ------------------------------------------------------------------ palettes ---

PAL = {
    "PLANT":    {"plant": "#3f8a52", "plant_dark": "#24583a", "skin": "#4f9a5e", "cloth": "#2e6a40", "cloth_dark": "#24583a", "bone": "#c8d8a0", "eyes": "#e03020", "metal": "#3f8a52", "leather": "#2e6a40", "leather_dark": "#24583a", "leather_light": "#5aa868", "hair": "#2e6a40", "linen": "#7ab070"},
    "LYW":      {"flesh": "#e07060", "skin": "#d86858", "plant": "#b04040", "bone": "#f0a090", "eyes": "#ffe060", "cloth": "#a03838", "cloth_dark": "#702828", "leather": "#a03838", "leather_dark": "#702828", "metal": "#d86858", "hair": "#a03838"},
    "HOBGLOB":  {"skin": "#c08070", "flesh": "#a85848", "horn": "#e8e0cc", "bone": "#e8dcc0", "cloth": "#9a3030", "cloth_dark": "#6a2020", "leather": "#7a3a2a", "leather_dark": "#5a2a20", "metal": "#b0a090", "hair": "#4a2a20", "eyes": "#ffd040"},
    "GIANTET":  {"skin": "#c8c098", "flesh": "#a8a070", "horn": "#efe8d8", "cloth": "#5a6a3a", "cloth_dark": "#3a4a2a", "leather": "#6a5a3a", "leather_dark": "#4a3e2a", "fur": "#8a7a58", "metal": "#9a9aa0", "hair": "#6a5a40", "eyes": "#d03020"},
    "GITH":     {"stone": "#8a7058", "stone_dark": "#5a4636", "skin": "#9a7a5e", "flesh": "#c03030", "cloth": "#6a5440", "cloth_dark": "#4a3a2c", "leather": "#6a5440", "leather_dark": "#4a3a2c", "fur": "#7a6048", "metal": "#8a7058", "hair": "#5a4636", "eyes": "#ff4020", "linen": "#9a7a5e"},
    "ROCKMAN":  {"chitin": "#d8b040", "gold": "#e8c050", "metal": "#d8b040", "metal_dark": "#9a7a28", "skin": "#c8a038", "cloth": "#a07a20", "cloth_dark": "#6a5018", "leather": "#8a6a20", "leather_dark": "#5a4418", "flesh": "#c03030", "eyes": "#e02020", "bone": "#f0e0b0", "hair": "#8a6a20", "linen": "#e0c060"},
    "GREMJERM": {"skin": "#d8d4cc", "bone": "#f0ece4", "flesh": "#c04040", "cloth": "#a8a49c", "cloth_dark": "#7a7670", "leather": "#a8a49c", "leather_dark": "#7a7670", "metal": "#c8c4bc", "hair": "#b0aca4", "eyes": "#e02020", "chitin": "#9aa8c0"},
    "GORILLA":  {"fur": "#2a2a30", "skin": "#3a3a42", "cloth": "#2a2a30", "cloth_dark": "#1e1e24", "leather": "#2a2a30", "leather_dark": "#1e1e24", "metal": "#2a2a30", "hair": "#1e1e24", "flesh": "#4a4a54", "eyes": "#d0a040", "linen": "#3a3a42", "leather_light": "#3a3a42"},
}

# ------------------------------------------------------- procedural features ---

def at_bone(rig, bone, offset=(0, 0, 0)):
    return rig.bone_head(bone) + Vector(offset)


def horns(rig, role="horn", size=1.0, up=0.6, spread=1.0):
    c, r = humans._head_frame(rig)
    out = []
    for s in (-1, 1):
        prev = c + Vector((s * r * 0.75, 0, r * 0.55))
        for i in range(3):
            d = Vector((s * (0.55 - 0.2 * i) * spread, -0.1 * i, up + 0.25 * i)).normalized()
            seg = 0.17 * size * (1.0 - 0.15 * i)
            mid = prev + d * seg * 0.5
            o = cone("horn", 0.07 * size * (1 - 0.3 * i), 0.07 * size * (0.7 - 0.3 * i) + 0.005, seg, 6, at=mid)
            o.rotation_mode = "QUATERNION"
            o.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d)
            out.append(colored(o, role))
            prev = prev + d * seg
    return [(o, "head") for o in out]


def tail(rig, role="skin", length=0.9, thick=0.12, segs=4, droop=0.35):
    p = at_bone(rig, "hips", (0, 0.12, 0.02))
    out = []
    d = Vector((0, 1, -droop)).normalized()
    for i in range(segs):
        seg = length / segs
        r1 = thick * (1 - i / segs) + 0.01
        r2 = thick * (1 - (i + 1) / segs) + 0.005
        o = cone("tail", r1, r2, seg, 6, at=p + d * seg * 0.5)
        o.rotation_mode = "QUATERNION"
        o.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d)
        out.append((colored(o, role), "hips"))
        p = p + d * seg
        d = (d + Vector((0, 0.1, 0.25))).normalized()
    return out


def spikes(rig, bone="chest", role="horn", n=4, size=0.18, spread=0.18, back=0.2, up=0.15):
    out = []
    base = at_bone(rig, bone, (0, back, up))
    for i in range(n):
        x = (i - (n - 1) / 2) * spread
        o = cone("spike", size * 0.35, 0.01, size, 5, at=base + Vector((x, 0.05, 0.05 * (1 - abs(x)))),
                 rot=(math.radians(-60), 0, x * 1.2))
        out.append((colored(o, role), bone))
    return out


def claws(rig, role="horn", size=0.16):
    out = []
    for side in ("l", "r"):
        h = at_bone(rig, "hand." + side)
        sx = 1 if side == "l" else -1
        for i in range(3):
            o = cone("claw", 0.035, 0.005, size, 4, at=h + Vector((sx * (0.12 + 0.06 * i), -0.06 * (i - 1), -0.05)),
                     rot=(0, sx * math.radians(90), 0))
            out.append((colored(o, role), "hand." + side))
    return out


def lumps(rig, bones, role="stone", n=3, size=0.14, seed=1):
    rnd = random.Random(seed)
    out = []
    for b in bones:
        for i in range(n):
            off = Vector((rnd.uniform(-0.18, 0.18), rnd.uniform(-0.05, 0.22), rnd.uniform(0.0, 0.25)))
            o = sphere("lump", size * rnd.uniform(0.7, 1.2), 6, 4, at=at_bone(rig, b) + off, scale=(1, 1, 0.8))
            out.append((colored(o, rnd.choice([role, role, role + "_dark" if role + "_dark" in ROLE else role])), b))
    return out


def fronds(rig, role="plant", n=5):
    out = []
    base = at_bone(rig, "chest", (0, 0.15, 0.3))
    for i in range(n):
        a = (i / (n - 1) - 0.5) * 2.2
        d = Vector((math.sin(a) * 0.8, 0.5, 0.9)).normalized()
        o = sphere("frond", 0.3, 6, 4, at=base + d * 0.28, scale=(0.35, 0.12, 1.0))
        o.rotation_mode = "QUATERNION"
        o.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d)
        out.append((colored(o, role if i % 2 else "plant_dark"), "chest"))
    return out


def snout(rig, role="flesh", length=0.28, width=0.3, z=-0.05):
    c, r = humans._head_frame(rig)
    o = box("snout", (width, length, width * 0.75), at=c + Vector((0, -r - length * 0.35, z)))
    nose = sphere("nostrils", width * 0.35, 6, 4, at=c + Vector((0, -r - length * 0.8, z)), scale=(1.2, 0.6, 0.8))
    return [(colored(o, role), "head"), (colored(nose, "black"), "head")]


def mandibles(rig, role="chitin"):
    c, r = humans._head_frame(rig)
    out = []
    for s in (-1, 1):
        o = cone("mandible", 0.05, 0.005, 0.32, 5, at=c + Vector((s * r * 0.45, -r * 1.05, -r * 0.45)),
                 rot=(math.radians(-100), 0, s * math.radians(-25)))
        out.append((colored(o, role), "head"))
    return out


def crest(rig, role="chitin", n=4):
    c, r = humans._head_frame(rig)
    return [(colored(cone("crest", 0.07, 0.005, 0.32 - 0.04 * i, 4, at=c + Vector((0, r * (0.2 + 0.3 * i), r * (1.1 - 0.2 * i))),
                          rot=(math.radians(30 + 15 * i), 0, 0)), role), "head") for i in range(n)]


def eyes_glow(rig, role="eyes"):
    c, r = humans._head_frame(rig)
    return [(colored(sphere("eye", r * 0.13, 6, 4, at=c + Vector((s * r * 0.35, -r * 0.92, r * 0.1))), role), "head") for s in (-1, 1)]


def brain(rig, role="flesh"):
    """The Bregma: a lumpy brain-blob in place of head and torso."""
    c = at_bone(rig, "chest", (0, 0, 0.15))
    out = [(colored(sphere("blob", 0.42, 10, 7, at=c, scale=(1.1, 1.0, 0.9)), role), "chest")]
    rnd = random.Random(3)
    for i in range(7):
        off = Vector((rnd.uniform(-0.35, 0.35), rnd.uniform(-0.3, 0.3), rnd.uniform(0.1, 0.4)))
        out.append((colored(sphere("lobe", rnd.uniform(0.16, 0.24), 6, 4, at=c + off), "skin"), "chest"))
    out += [(colored(sphere("eye", 0.06, 6, 4, at=c + Vector((s * 0.15, -0.4, 0.05))), "eyes"), "chest") for s in (-1, 1)]
    return out


def tentacles(rig, role="plant"):
    out = []
    for bone in ("upperleg.l", "upperleg.r", "lowerleg.l", "lowerleg.r", "lowerarm.l", "lowerarm.r", "spine"):
        base = at_bone(rig, bone)
        for k in range(2 if "leg" in bone else 3):
            a = k * 2.1 + len(bone)
            d = Vector((math.cos(a) * 0.5, math.sin(a) * 0.5, -1)).normalized()
            o = cone("tentacle", 0.06, 0.01, 0.45, 5, at=base + d * 0.22)
            o.rotation_mode = "QUATERNION"
            o.rotation_quaternion = Vector((0, 0, -1)).rotation_difference(d) @ Quaternion((1, 0, 0), math.pi)
            out.append((colored(o, role), bone))
    return out


def rock(name="rock", role="stone", r=0.28):
    o = sphere(name, r, 7, 5, scale=(1.0, 0.9, 0.85))
    return colored(o, role)


# ------------------------------------------------------------------ species ---
# body parts: (character, part names), like humans.BODIES; extras: feature builders.

KK = humans.BODIES
SPECIES = {
    "PLANT": dict(body=("Skeleton_Warrior", ["Skeleton_Warrior_Body", "Skeleton_Warrior_ArmLeft", "Skeleton_Warrior_ArmRight", "Skeleton_Warrior_LegLeft", "Skeleton_Warrior_LegRight", "Skeleton_Warrior_Head", "Skeleton_Warrior_Jaw"]),
                  roles={"bone": "plant", "metal": "plant_dark", "leather": "plant_dark", "leather_dark": "plant_dark", "team": "plant", "glow": "eyes", "cloth": "plant"},
                  extras=lambda g: fronds(g) + claws(g, "bone", 0.22) + spikes(g, "upperarm.l", "plant_dark", 2, 0.2, 0.12, 0.0, 0.1) + spikes(g, "upperarm.r", "plant_dark", 2, 0.2, 0.12, 0.0, 0.1) + eyes_glow(g),
                  height=1.45, head=0.75, w={"Claw": None}),
    "LYW": dict(body=("Skeleton_Minion", ["Skeleton_Minion_LegLeft", "Skeleton_Minion_LegRight", "Skeleton_Minion_ArmLeft", "Skeleton_Minion_ArmRight"]),
                roles={"bone": "flesh", "leather": "flesh", "leather_dark": "skin", "metal": "flesh", "team": "flesh", "glow": "eyes"},
                extras=lambda g: brain(g) + tentacles(g, "plant"), height=1.0, head=1.0, w={}),
    "HOBGLOB": dict(body=("Barbarian", ["Barbarian_Body", "Barbarian_ArmLeft", "Barbarian_ArmRight", "Barbarian_LegLeft", "Barbarian_LegRight", "Barbarian_Head"]),
                    roles={"cloth": "skin", "fur": "flesh", "hair": "flesh", "linen": "skin", "cloth_dark": "cloth_dark"},
                    extras=lambda g: horns(g, "horn", 1.6, 0.9, 1.2) + spikes(g, "lowerarm.l", "horn", 1, 0.2, 0.1, 0.1, 0.0) + spikes(g, "lowerarm.r", "horn", 1, 0.2, 0.1, 0.1, 0.0) + claws(g) + eyes_glow(g),
                    height=1.45, head=0.7, w={"Bow": "bow"}),
    "GIANTET": dict(body=("Barbarian", ["Barbarian_Body", "Barbarian_ArmLeft", "Barbarian_ArmRight", "Barbarian_LegLeft", "Barbarian_LegRight", "Barbarian_Head"]),
                    roles={"cloth": "skin", "hair": "fur", "fur": "fur", "linen": "skin"},
                    extras=lambda g: horns(g, "horn", 1.8, 0.25, 1.6) + snout(g, "flesh") + tail(g, "skin", 0.8, 0.07) + eyes_glow(g),
                    height=1.75, head=0.72, bulk=1.15, w={"Axe": "greataxe"}),
    "GITH": dict(body=("Barbarian", ["Barbarian_Body", "Barbarian_ArmLeft", "Barbarian_ArmRight", "Barbarian_LegLeft", "Barbarian_LegRight", "Barbarian_Head"]),
                 roles={"cloth": "stone", "skin": "stone", "hair": "stone_dark", "fur": "stone_dark", "linen": "stone", "cloth_dark": "stone_dark", "metal": "stone_dark", "leather": "stone_dark", "leather_dark": "stone_dark"},
                 extras=lambda g: lumps(g, ["chest", "spine", "upperarm.l", "upperarm.r", "lowerarm.l", "lowerarm.r", "head"], "stone", 3, 0.16) + eyes_glow(g) + [(colored(sphere("gem", 0.12, 6, 4, at=at_bone(g, "chest", (0, -0.42, 0.2)), scale=(1, 0.6, 1.2)), "flesh"), "chest")],
                 height=2.0, head=0.6, bulk=1.45, w={"Throw": "rock"}),
    "ROCKMAN": dict(body=("Knight", ["Knight_Body", "Knight_ArmLeft", "Knight_ArmRight", "Knight_LegLeft", "Knight_LegRight", "Knight_Head"]),
                    roles={"metal": "chitin", "skin": "chitin", "hair": "metal_dark", "team": "flesh", "linen": "gold", "leather": "metal_dark", "leather_dark": "metal_dark", "cloth_dark": "metal_dark"},
                    extras=lambda g: mandibles(g) + crest(g) + tail(g, "chitin", 1.0, 0.13, 5, 0.6) + spikes(g, "chest", "gold", 3, 0.22, 0.2, 0.2, 0.25) + eyes_glow(g),
                    height=1.7, head=0.7, w={"Sword": "khopesh", "Shield": "sh_round"}),
    "GREMJERM": dict(body=("Skeleton_Rogue", ["Skeleton_Rogue_Body", "Skeleton_Rogue_ArmLeft", "Skeleton_Rogue_ArmRight", "Skeleton_Rogue_LegLeft", "Skeleton_Rogue_LegRight", "Skeleton_Rogue_Head", "Skeleton_Rogue_Jaw"]),
                     roles={"bone": "skin", "metal": "bone", "leather": "cloth", "leather_dark": "cloth_dark", "team": "chitin", "glow": "eyes", "cloth": "skin"},
                     extras=lambda g: snout(g, "bone", 0.36, 0.22, 0.0) + crest(g, "chitin", 3) + tail(g, "skin", 1.0, 0.11, 5, 0.2) + claws(g, "flesh") + eyes_glow(g),
                     height=1.35, head=0.8, w={}),
    "GORILLA": dict(body=("Barbarian", ["Barbarian_Body", "Barbarian_ArmLeft", "Barbarian_ArmRight", "Barbarian_LegLeft", "Barbarian_LegRight", "Barbarian_Head"]),
                    roles={"cloth": "fur", "skin": "flesh", "hair": "fur", "linen": "fur", "cloth_dark": "fur", "metal": "fur", "leather": "fur", "leather_dark": "fur", "leather_light": "fur"},
                    extras=lambda g: lumps(g, ["upperarm.l", "upperarm.r", "chest"], "fur", 2, 0.18, 7) + eyes_glow(g),
                    height=1.5, head=0.6, bulk=1.35, w={}),
}
WEAPONS_EXTRA = {"rock": ("proc", lambda: rock())}


def bulk_up(rig, k):
    """Thickens torso and arms (Grokken, Minotauros, gorilla) about each bone axis."""
    for o in rig.parts.values():
        if not o.vertex_groups:
            continue
        for g in ("chest", "spine", "upperarm.l", "upperarm.r", "lowerarm.l", "lowerarm.r", "hips"):
            if g not in o.vertex_groups:
                continue
            gi = o.vertex_groups[g].index
            b = rig.arm.data.bones[g]
            h, t = b.head_local, b.tail_local
            axis = (t - h).normalized()
            for v in o.data.vertices:
                w = next((x.weight for x in v.groups if x.group == gi), 0.0)
                if w < 0.3:
                    continue
                p = v.co - h
                along = axis * p.dot(axis)
                v.co = h + along + (p - along) * (1 + (k - 1) * w)


def build_species(code):
    sp = SPECIES[code]
    reset()
    char, parts = sp["body"]
    rig = Rig(char)
    rig.keep_only(parts)
    rig.scale_head(sp.get("head", 0.7))
    if sp.get("bulk"):
        bulk_up(rig, sp["bulk"])
    pal = make_palette("pal_" + code, PAL[code])
    mat = palette_material(pal)
    rig.to_palette(mat, sp.get("roles", {}))
    bpy.context.view_layer.update()
    for o, bone in sp["extras"](rig):
        o.data.materials.clear()
        o.data.materials.append(mat)
        rig.attach(o, bone, "x%d" % len(rig.parts))
    weapons = []
    humans.WEAPONS.update(WEAPONS_EXTRA)
    for slot, w in sp.get("w", {}).items():
        if w:
            weapons.append(humans._weapon(rig, slot, w, mat).name)
    rig.bake_rigid()
    rig.join_body(keep_separate=tuple(weapons))
    s = sp["height"] / rig.height()
    rig.arm.scale = (s, s, s)
    humans.export_unit(code, rig, "fryhtans")


# ------------------------------------------------------- insects and the cat ---

CUTE = ("textured-cute-monster-pack",)


def _cute_path(name):
    import glob
    return glob.glob(os.path.join(sources.path(CUTE[0]), "**", name + ".fbx"), recursive=True)[0]


def _anim_path(pack, name):
    import glob
    return glob.glob(os.path.join(sources.path(pack), "**", name + ".fbx"), recursive=True)[0]


def export_creature(name, arm, height, keep, palette, roles, extra_scale=1.0):
    """Recolours an FBX creature, scales it, keeps clips `keep` (old -> new name)."""
    import mounts
    for a in list(bpy.data.actions):
        a.name = a.name.split("|")[-1]
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    if palette:
        mat = palette_material(make_palette("pal_" + name, palette))
        for m in meshes:
            mounts.mat_roles(m, roles, mat)
    bpy.context.view_layer.update()
    top = max((m.matrix_world @ Vector(c)).z for m in meshes for c in m.bound_box)
    s = height / top
    for a in list(bpy.data.actions):
        if a.name in keep:
            a.name = keep[a.name]
            a.use_fake_user = True
            a.id_root = "OBJECT"
        else:
            bpy.data.actions.remove(a)
    arm.animation_data_create()
    arm.animation_data.action = bpy.data.actions[list(keep.values())[0]]
    import json
    path = os.path.join(OUT, "fryhtans", "creatures.json")
    data = json.load(open(path)) if os.path.exists(path) else {}
    data[name] = {"scale": s * extra_scale}
    os.makedirs(os.path.dirname(path), exist_ok=True)
    json.dump(data, open(path, "w"), indent=1, sort_keys=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in [arm] + meshes:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "fryhtans", name + ".glb"), export_format="GLB",
        use_selection=True, export_animations=True, export_animation_mode="ACTIONS", export_skins=True,
        export_force_sampling=True, export_anim_single_armature=True, export_materials="EXPORT")
    print("BUILT", name)


def build_bee():
    reset()
    bpy.ops.import_scene.fbx(filepath=_cute_path("Bee"))
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    names = {m.name for o in bpy.data.objects if o.type == "MESH" for m in o.data.materials if m}
    print("BEE MATS", names)
    roles = {n: ("black" if "lack" in n or "Eye" in n else "chitin" if "ellow" in n or "Main" in n else "linen" if "ing" in n else "chitin") for n in names}
    # keeps its own painted texture (the FBX does not link it)
    import glob
    png = glob.glob(os.path.join(sources.path(CUTE[0]), "**", "Bee_Texture.png"), recursive=True)[0]
    img = bpy.data.images.load(png)
    img.pack()
    for o in bpy.data.objects:
        if o.type == "MESH":
            for m in o.data.materials:
                m.use_nodes = True
                nt = m.node_tree
                tex = nt.nodes.new("ShaderNodeTexImage")
                tex.image = img
                nt.links.new(tex.outputs["Color"], nt.nodes["Principled BSDF"].inputs["Base Color"])
    export_creature("BEE", arm, 0.9, {"Flying": "Flying", "Bite_Front": "Attack", "Death": "Death"}, None, roles)


def build_termite():
    reset()
    bpy.ops.import_scene.fbx(filepath=_cute_path("Crab"))
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    names = {m.name for o in bpy.data.objects if o.type == "MESH" for m in o.data.materials if m}
    print("CRAB MATS", names)
    roles = {n: ("black" if "Eye" in n or "lack" in n else "chitin") for n in names}
    export_creature("TERMITE", arm, 0.55, {"Idle": "Idle", "Walk": "Walk", "Bite_Front": "Attack", "Death": "Death"},
                    {"chitin": "#c87a3a", "black": "#2a1e18"}, roles)


def _key_root(arm, name, frames):
    """Keys whole-body motion on the cat's root bone: [(frame, loc, rot_euler)]."""
    a = bpy.data.actions.new(name)
    a.id_root = "OBJECT"
    arm.animation_data_create()
    arm.animation_data.action = a
    root = arm.pose.bones[0]
    root.rotation_mode = "QUATERNION"
    for f, loc, rot in frames:
        root.location = loc
        root.rotation_quaternion = Euler(rot).to_quaternion()
        root.keyframe_insert("location", frame=f)
        root.keyframe_insert("rotation_quaternion", frame=f)
    a.use_fake_user = True
    return a


def build_jaguar():
    reset()
    bpy.ops.import_scene.fbx(filepath=_anim_path("animated-animales-low-poly", "Cat"))
    arm = next(o for o in bpy.data.objects if o.type == "ARMATURE")
    for a in list(bpy.data.actions):
        a.name = a.name.split("|")[-1]
    # pounce: crouch, leap forward and up, land; death: roll onto the side
    _key_root(arm, "Pounce", [(1, (0, 0, 0), (0, 0, 0)), (6, (0, 0, -0.3), (0.15, 0, 0)), (12, (0, 0.6, 0.5), (-0.35, 0, 0)), (18, (0, 0.2, 0), (0, 0, 0)), (24, (0, 0, 0), (0, 0, 0))])
    _key_root(arm, "Dying", [(1, (0, 0, 0), (0, 0, 0)), (10, (0, 0, -0.2), (0, 0.6, 0)), (20, (0, 0, -0.5), (0, 1.5, 0)), (30, (0, 0, -0.5), (0, 1.57, 0))])
    names = {m.name for o in bpy.data.objects if o.type == "MESH" for m in o.data.materials if m}
    roles = {n: ("fur" if n == "Grey" else "linen" if n == "White" else "flesh") for n in names}
    export_creature("JAGUAR", arm, 0.95, {"Idle": "Idle", "Walking": "Walk", "Pounce": "Attack", "Dying": "Death"},
                    {"fur": "#d8a038", "linen": "#efe0b8", "flesh": "#c07060"}, roles)


ANIMALS = {"BEE": build_bee, "TERMITE": build_termite, "JAGUAR": build_jaguar}

if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for code in SPECIES:
        if not args or code in args:
            build_species(code)
    for code, f in ANIMALS.items():
        if not args or code in args:
            f()
