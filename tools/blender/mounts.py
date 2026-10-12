"""Builds the quadruped mounts and beasts on Quaternius' farm-animal rig (CC0):
horses in several coats, the war elephant (reshaped cow) and the rhinoceros.

blender -b --factory-startup -P tools/blender/mounts.py -- [name ...]

Each model keeps its own clips (Idle, Walk, Run, Attack, Death). Mounts get an empty
named "Saddle" on the Body bone; the game seats a rider model there
(scripts/models/model_library.gd). Riders come from humans.py (RIDERS).
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, bmesh
from mathutils import Vector, Matrix
from common import *
import humans

FARM = ("lowpoly-animated-farm-animal-pack", "Farm Animals by @Quaternius", "FBX")


def import_farm(name):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=sources.path(FARM[0], FARM[1], FARM[2], name + ".fbx"))
    objs = [o for o in bpy.data.objects if o not in before]
    arm = next(o for o in objs if o.type == "ARMATURE")
    mesh = next(o for o in objs if o.type == "MESH")
    for a in bpy.data.actions:
        a.name = a.name.split("|")[-1]
    arm.animation_data_clear()
    arm.data.pose_position = "REST"
    return arm, mesh


def mat_roles(mesh, table, mat):
    """Puts each face on the palette role of its original material."""
    me = mesh.data
    if not me.uv_layers:
        me.uv_layers.new()
    uv = me.uv_layers.active.data
    names = [m.name if m else "" for m in me.materials]
    zs = [v.co.z for v in me.vertices]
    z0, z1 = min(zs), max(zs)
    for p in me.polygons:
        role = table.get(names[p.material_index], "fur")
        for li in p.loop_indices:
            z = me.vertices[me.loops[li].vertex_index].co.z
            uv[li].uv = role_uv(role, 0.3 + 0.65 * (z - z0) / (z1 - z0))
    me.materials.clear()
    me.materials.append(mat)


def bone_world(arm, bone, tail=False):
    b = arm.data.bones[bone]
    return arm.matrix_world @ (b.tail_local if tail else b.head_local)


def skin_to(arm, obj, bone):
    """Makes a procedural mesh follow one bone (weight 1)."""
    bpy.context.view_layer.update()
    mw = obj.matrix_world.copy()
    obj.parent = arm
    obj.matrix_parent_inverse = arm.matrix_world.inverted()
    obj.matrix_world = mw
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    vg = obj.vertex_groups.new(name=bone)
    vg.add([v.index for v in obj.data.vertices], 1.0, "REPLACE")
    m = obj.modifiers.new("Armature", "ARMATURE")
    m.object = arm
    return obj


def radial_scale(mesh, arm, groups, k, kz=None):
    """Thickens (k > 1) the parts of a mesh weighted to `groups`, about each bone's axis."""
    for g in groups:
        if g not in mesh.vertex_groups:
            continue
        gi = mesh.vertex_groups[g].index
        b = arm.data.bones[g]
        h, t = b.head_local, b.tail_local
        axis = (t - h).normalized()
        for v in mesh.data.vertices:
            w = next((x.weight for x in v.groups if x.group == gi), 0.0)
            if w <= 0.3:
                continue
            p = v.co - h
            along = axis * p.dot(axis)
            perp = p - along
            f = 1.0 + (k - 1.0) * w
            perp = Vector((perp.x * f, perp.y * f, perp.z * (1.0 + ((kz or k) - 1.0) * w)))
            v.co = h + along + perp


def scale_group(mesh, arm, group, k, about="head", offset=Vector()):
    gi = mesh.vertex_groups[group].index
    b = arm.data.bones[group]
    c = (b.head_local if about == "head" else b.tail_local) + offset
    for v in mesh.data.vertices:
        w = next((x.weight for x in v.groups if x.group == gi), 0.0)
        if w > 0.5:
            v.co = c + (v.co - c) * k


SADDLES = {}


def add_saddle(arm, at_world):
    """Records the seat point (armature space, converted to glTF's y-up axes)."""
    p = arm.matrix_world.inverted() @ at_world
    SADDLES.setdefault("current", {}).update({"bone": "Body", "point": [p.x, p.z, -p.y]})


def write_saddles(name):
    import json
    path = os.path.join(OUT, "mounts", "mounts.json")
    data = json.load(open(path)) if os.path.exists(path) else {}
    if "current" in SADDLES:
        data[name] = SADDLES.pop("current")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    json.dump(data, open(path, "w"), indent=1, sort_keys=True)


def finish(arm, height, name, extra=()):
    """Scales to `height`, renames clips, exports with animations."""
    bpy.context.view_layer.update()
    top = 0.0
    for o in [o for o in bpy.data.objects if o.type == "MESH"]:
        for c in o.bound_box:
            top = max(top, (o.matrix_world @ Vector(c)).z)
    s = height / top
    # Exported with clips, the armature node's own transform is keyed too, so an
    # object scale would be undone; the game scales the scene root instead.
    SADDLES.setdefault("current", {})["scale"] = s
    keep = {"Idle": "Idle", "Walk": "Walk", "Run": "Run", "Death": "Death", "Jump": "Attack"}
    for a in list(bpy.data.actions):
        if a.name in keep:
            a.name = keep[a.name]
            a.use_fake_user = True
            a.id_root = "OBJECT"     # the glTF exporter skips actions without it
        else:
            bpy.data.actions.remove(a)
    arm.animation_data_create()
    arm.animation_data.action = bpy.data.actions["Idle"]
    write_saddles(name)
    objs = [arm] + [o for o in bpy.data.objects if o.parent == arm] + list(extra)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    path = os.path.join(OUT, "mounts", name + ".glb")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
        export_animations=True, export_animation_mode="ACTIONS", export_skins=True,
        export_force_sampling=True, export_optimize_animation_size=True,
        export_anim_single_armature=True, export_materials="EXPORT")
    print("BUILT", name, path, "scale", s)


# -------------------------------------------------------------------- horses ---

HORSE_COATS = {
    "horse_bay": {"fur": "#7a4a30", "hair": "#2a2020"},
    "horse_black": {"fur": "#2e2a2a", "hair": "#141212"},
    "horse_white": {"fur": "#e4e0d8", "hair": "#b8b0a4"},
    "horse_grey": {"fur": "#8e8a86", "hair": "#3a3836"},
    "horse_chestnut": {"fur": "#9a5a32", "hair": "#c8a070"},
}


def build_horse(name, barding=None):
    reset()
    arm, mesh = import_farm("Horse")
    pal = make_palette("pal_" + name, HORSE_COATS[name.split("+")[0]])
    mat = palette_material(pal)
    mat_roles(mesh, {"Material.003": "fur", "Material.006": "hair"}, mat)
    # saddle cloth in the nation colour, over the back
    back = (bone_world(arm, "Shoulders") + bone_world(arm, "Hips")) * 0.5
    cloth = colored(box("saddlecloth", (2.75, 2.6, 0.25), at=back + Vector((0, 0.2, 0.55))), "team")
    seat = colored(box("saddle", (1.6, 1.6, 0.35), at=back + Vector((0, 0.15, 0.85))), "leather")
    for o in (cloth, seat):
        o.data.materials.append(mat)
        skin_to(arm, o, "Body")
    add_saddle(arm, back + Vector((0, 0.15, 1.0)))
    finish(arm, 1.55, name)


# ----------------------------------------------------------------- elephants ---

def build_elephant(name, skin="#8a8a8e", howdah=False):
    reset()
    arm, mesh = import_farm("Cow")
    pal = make_palette("pal_" + name, {"fur": skin, "horn": "#f0ead8", "flesh": "#c89090"})
    mat = palette_material(pal)
    mat_roles(mesh, {"White": "fur", "Black": "fur", "Pink": "flesh"}, mat)
    legs = [g.name for g in mesh.vertex_groups if "Leg" in g.name or "Foot" in g.name]
    radial_scale(mesh, arm, legs, 1.9)
    radial_scale(mesh, arm, ["Body", "Torso", "Back", "Hips", "Shoulders"], 1.25, 1.15)
    # trunk, ears and tusks follow the head
    head = bone_world(arm, "Head")
    tip = bone_world(arm, "Head", tail=True)
    fwd = Vector((0, -1, 0))
    parts = []
    trunk = [colored(cone("trunk%d" % i, 0.42 - i * 0.08, 0.36 - i * 0.08, 0.9, 8,
                          at=tip + fwd * (0.4 + 0.15 * i) + Vector((0, 0, -0.5 - 0.8 * i)),
                          rot=(math.radians(-15 * i), 0, 0)), "fur") for i in range(3)]
    parts += trunk
    for s in (-1, 1):
        ear = colored(sphere("ear", 1.0, 8, 4, at=head + Vector((s * 1.15, -0.2, 0.0)), scale=(0.15, 0.9, 1.1)), "fur")
        tusk = colored(cone("tusk", 0.12, 0.02, 1.3, 6, at=tip + fwd * 0.5 + Vector((s * 0.4, 0, -0.6)), rot=(math.radians(-60), 0, 0)), "horn")
        parts += [ear, tusk]
    for o in parts:
        o.data.materials.append(mat)
        skin_to(arm, o, "Head")
    back = (bone_world(arm, "Shoulders") + bone_world(arm, "Hips")) * 0.5
    cloth = colored(box("caparison", (3.6, 3.6, 2.0), at=back + Vector((0, 0.1, 0.3))), "team")
    cloth.data.materials.append(mat)
    skin_to(arm, cloth, "Body")
    seat_h = 1.4
    if howdah:
        hb = colored(box("howdah", (2.0, 2.0, 1.0), at=back + Vector((0, 0.2, 1.6))), "trim")
        roof = colored(cone("roof", 1.6, 0.1, 1.2, 4, at=back + Vector((0, 0.2, 3.4)), rot=(0, 0, math.radians(45))), "team")
        posts = [colored(box("post", (0.12, 0.12, 1.4), at=back + Vector((sx * 0.9, 0.2 + sy * 0.9, 2.6))), "wood") for sx in (-1, 1) for sy in (-1, 1)]
        for o in [hb, roof] + posts:
            o.data.materials.append(mat)
            skin_to(arm, o, "Body")
        seat_h = 2.1
    add_saddle(arm, back + Vector((0, 0.2, seat_h)))
    finish(arm, 2.3, name)


def build_rhino(name="rhino"):
    reset()
    arm, mesh = import_farm("Cow")
    pal = make_palette("pal_" + name, {"fur": "#6e665e", "horn": "#d8ccb0", "flesh": "#8a7a70"})
    mat = palette_material(pal)
    mat_roles(mesh, {"White": "fur", "Black": "fur", "Pink": "flesh"}, mat)
    legs = [g.name for g in mesh.vertex_groups if "Leg" in g.name or "Foot" in g.name]
    radial_scale(mesh, arm, legs, 1.6)
    radial_scale(mesh, arm, ["Body", "Torso", "Back", "Hips", "Shoulders"], 1.2, 1.05)
    tip = bone_world(arm, "Head", tail=True)
    horn = colored(cone("horn", 0.32, 0.02, 1.2, 6, at=tip + Vector((0, -0.55, 0.0)), rot=(math.radians(-25), 0, 0)), "horn")
    horn2 = colored(cone("horn2", 0.2, 0.02, 0.6, 6, at=tip + Vector((0, -0.1, 0.25)), rot=(math.radians(-15), 0, 0)), "horn")
    for o in (horn, horn2):
        o.data.materials.append(mat)
        skin_to(arm, o, "Head")
    finish(arm, 1.4, name)


def build_qilin():
    """Chi Lin, the Chinese Greater Being: a golden horned horse."""
    reset()
    arm, mesh = import_farm("Horse")
    pal = make_palette("pal_qilin", {"fur": "#e0b040", "hair": "#c83020", "horn": "#f4ead0"})
    mat = palette_material(pal)
    mat_roles(mesh, {"Material.003": "fur", "Material.006": "hair"}, mat)
    tip = bone_world(arm, "Head", tail=True)
    head = bone_world(arm, "Head")
    parts = [colored(cone("horn", 0.15, 0.01, 1.0, 6, at=(head + tip) * 0.5 + Vector((s * 0.25, 0.3, 0.6)), rot=(math.radians(30), s * 0.3, 0)), "horn") for s in (-1, 1)]
    parts += [colored(cone("flame", 0.25, 0.01, 0.8, 5, at=bone_world(arm, "Back") + Vector((0, 0.4 * i, 0.5)), rot=(math.radians(-30), 0, 0)), "hair") for i in range(3)]
    for o in parts:
        o.data.materials.append(mat)
        skin_to(arm, o, "Head" if o.name.startswith("horn") else "Body")
    finish(arm, 2.2, "qilin")


BUILDS = {
    "qilin": build_qilin,
    **{n: (lambda n=n: build_horse(n)) for n in HORSE_COATS},
    "elephant": lambda: build_elephant("elephant"),
    "elephant_white": lambda: build_elephant("elephant_white", "#dcd6cc", howdah=True),
    "rhino": build_rhino,
}


def build_riders(codes=()):
    for code, u in humans.RIDERS.items():
        if codes and code not in codes:
            continue
        rig = humans.build_character(code, u, "RIDER")
        humans.export_unit(code, rig, "riders")


if __name__ == "__main__":
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for n, f in BUILDS.items():
        if not args or n in args:
            f()
    if not args or "riders" in args:
        build_riders()
