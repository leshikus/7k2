"""Shared helpers for the Blender build scripts (Blender 4.2, run headless).

Characters are assembled from KayKit body parts on KayKit's shared 41-bone humanoid
rig. Every part keeps its UV islands but is moved onto a small *role palette*: one
column per material role (skin, hair, metal, cloth, team ...), each a vertical
light-to-dark gradient like the KayKit cells. A race's look is then just the colours
of its palette. The `team` column has alpha 0: the game's shader paints it in the
owning nation's colour.
"""
import bpy, bmesh, os, sys, math
from mathutils import Vector, Matrix

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sources

REPO = sources.REPO
OUT = os.path.join(REPO, "assets", "models")

# ------------------------------------------------------------------ palette ---

ROLES = [
    "skin", "hair", "eyes", "metal", "metal_dark", "leather_light", "leather", "leather_dark",
    "cloth", "cloth2", "cloth_dark", "team", "trim", "linen", "wood", "bone",
    "glow", "fur", "plant", "plant_dark", "stone", "stone_dark", "flesh", "chitin",
    "horn", "gold", "black", "white", "team_dark", "fire", "spare2", "spare3",
]
ROLE = {r: i for i, r in enumerate(ROLES)}
PAL_W, PAL_H = 32 * 16, 128          # 16 px per column

# KayKit texture cell ("A0".."D7": row A is the top quarter) -> role.
_COMMON = {"A0": "skin", "A1": "hair", "A2": "eyes", "A3": "metal", "A4": "metal_dark",
           "A5": "leather_light", "A6": "leather", "A7": "leather_dark"}
CELL_ROLES = {
    "knight_texture": {**_COMMON, "A7": "metal", "B0": "team", "B1": "linen", "B2": "metal",
                       "B3": "metal", "B4": "trim", "B5": "wood", "B6": "leather_dark",
                       "B7": "cloth_dark", "C2": "team"},
    "barbarian_texture": {**_COMMON, "B0": "cloth", "B1": "cloth", "B2": "linen", "B3": "metal",
                          "B4": "fur", "B5": "wood", "B6": "leather_dark", "B7": "fur",
                          "C0": "linen", "C2": "metal_dark", "C3": "cloth_dark", "C7": "fur",
                          "D1": "linen"},
    "mage_texture": {**_COMMON, "A4": "metal", "A5": "leather_light", "B0": "cloth", "B1": "cloth",
                     "B2": "team", "B3": "metal", "B5": "wood", "B7": "cloth_dark", "C0": "linen",
                     "C1": "team", "C2": "trim", "C3": "leather", "C6": "glow", "C7": "skin"},
    "rogue_texture": {**_COMMON, "B0": "cloth", "B1": "cloth2", "B2": "metal", "B3": "metal",
                      "B5": "leather_light", "B6": "leather", "C0": "linen", "C3": "cloth_dark",
                      "C5": "leather", "C6": "leather_dark"},
    "skeleton": {**_COMMON, "B1": "bone", "B7": "team", "C0": "linen", "C1": "cloth",
                 "C2": "team", "C3": "leather_light", "C5": "leather", "C6": "leather_dark",
                 "D7": "glow"},
}

# Base colours (the middle of each gradient); a race palette overrides some of them.
DEFAULT_COLORS = {
    "skin": "#e8b48e", "hair": "#5a3a22", "eyes": "#141a1c", "metal": "#9aa5aa",
    "metal_dark": "#4d5357", "leather_light": "#b27052", "leather": "#8a5a3e",
    "leather_dark": "#5e4c40", "cloth": "#7a6a55", "cloth2": "#a08a6a", "cloth_dark": "#4a4038",
    "team": "#ffffff", "trim": "#e0b84e", "linen": "#d8d4c8", "wood": "#8a5e3c",
    "bone": "#e6dcc6", "glow": "#9fffb0", "fur": "#8e8378", "plant": "#4f8a3a",
    "plant_dark": "#2e5a2a", "stone": "#9a958c", "stone_dark": "#5e5a54", "flesh": "#b0705a",
    "chitin": "#c9a23a", "horn": "#d8ccb0", "gold": "#e8c050", "black": "#1a1a1e",
    "white": "#f0f0f0", "team_dark": "#ffffff", "fire": "#ff8a20", "spare2": "#ff00ff",
    "spare3": "#ff00ff",
}


def hex_rgb(h):
    h = h.lstrip("#")
    return [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]


def make_palette(name, colors):
    """Palette image: one 16 px column per role, light at the top, dark at the bottom.
    Team columns get alpha 0 (the shader's nation-colour mask) and a white-to-grey ramp."""
    cols = dict(DEFAULT_COLORS)
    cols.update(colors)
    px = [0.0] * (PAL_W * PAL_H * 4)
    for ri, role in enumerate(ROLES):
        base = hex_rgb(cols[role])
        team = role in ("team", "team_dark")
        for y in range(PAL_H):           # y = 0 is the bottom row in Blender images
            t = y / (PAL_H - 1)           # 0 bottom (dark) .. 1 top (light)
            f = 0.62 + 0.55 * t
            if role == "team_dark":
                f *= 0.6
            c = [min(1.0, v * f) for v in base]
            a = 0.0 if team else 1.0
            for x in range(ri * 16, ri * 16 + 16):
                i = (y * PAL_W + x) * 4
                px[i:i + 4] = [c[0], c[1], c[2], a]
    img = bpy.data.images.get(name) or bpy.data.images.new(name, PAL_W, PAL_H, alpha=True)
    img.pixels = px
    img.filepath_raw = os.path.join(bpy.app.tempdir, name + ".png")
    img.file_format = "PNG"
    img.alpha_mode = "STRAIGHT"
    img.save()
    img.pack()
    return img


def palette_material(img):
    name = "M_" + img.name
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = "Closest"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.85
    m.blend_method = "OPAQUE"
    return m


def role_uv(role, v):
    """UV in the palette for a role; v (0 dark .. 1 light) picks the shade."""
    return ((ROLE[role] + 0.5) / len(ROLES), 0.03 + 0.94 * max(0.0, min(1.0, v)))


def remap_to_palette(obj, mat, override=None):
    """Moves every face of a KayKit mesh onto the role palette.
    `override` maps role -> role (e.g. {"cloth": "team"}) for this part."""
    override = override or {}
    me = obj.data
    src = None
    for s in me.materials:
        if s and s.use_nodes:
            for n in s.node_tree.nodes:
                if n.type == "TEX_IMAGE" and n.image:
                    src = os.path.splitext(n.image.name)[0]
    table = CELL_ROLES.get(src, {})
    uv = me.uv_layers.active.data
    for p in me.polygons:
        li = list(p.loop_indices)
        u = sum(uv[i].uv.x for i in li) / len(li)
        v = sum(uv[i].uv.y for i in li) / len(li)
        row = min(3, max(0, int((1.0 - v) * 4)))
        col = min(7, max(0, int(u * 8)))
        role = table.get("ABCD"[row] + str(col), "cloth")
        role = override.get(role, role)
        for i in li:
            # shade from the position inside the 256-px KayKit cell (top = light)
            cell_v = (uv[i].uv.y * 4) % 1.0
            uv[i].uv = role_uv(role, cell_v)
    me.materials.clear()
    me.materials.append(mat)


def set_faces_role(obj, role, shade=None):
    """Puts all faces of a procedural mesh on one role; shade from local height."""
    me = obj.data
    if not me.uv_layers:
        me.uv_layers.new()
    uv = me.uv_layers.active.data
    zs = [v.co.z for v in me.vertices] or [0]
    z0, z1 = min(zs), max(zs)
    for p in me.polygons:
        for li in p.loop_indices:
            z = me.vertices[me.loops[li].vertex_index].co.z
            s = shade if shade is not None else (0.35 + 0.6 * ((z - z0) / (z1 - z0) if z1 > z0 else 0.5))
            uv[li].uv = role_uv(role, s)


# ------------------------------------------------------------------- scene ---

def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)


def import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in before]


KAYKIT_CHARS = {
    "Knight": ("kaykit_adventurers", "Characters/gltf/Knight.glb"),
    "Barbarian": ("kaykit_adventurers", "Characters/gltf/Barbarian.glb"),
    "Mage": ("kaykit_adventurers", "Characters/gltf/Mage.glb"),
    "Rogue": ("kaykit_adventurers", "Characters/gltf/Rogue.glb"),
    "Rogue_Hooded": ("kaykit_adventurers", "Characters/gltf/Rogue_Hooded.glb"),
    "Skeleton_Warrior": ("kaykit_skeletons", "Characters/gltf/Skeleton_Warrior.glb"),
    "Skeleton_Minion": ("kaykit_skeletons", "Characters/gltf/Skeleton_Minion.glb"),
    "Skeleton_Mage": ("kaykit_skeletons", "Characters/gltf/Skeleton_Mage.glb"),
    "Skeleton_Rogue": ("kaykit_skeletons", "Characters/gltf/Skeleton_Rogue.glb"),
}


def char_path(name):
    pack, rel = KAYKIT_CHARS[name]
    return sources.path(pack, *rel.split("/"))


def _strip(name):
    return name.split(".")[0]


class Rig:
    """A KayKit rig with the body parts chosen from any KayKit character."""

    def __init__(self, base="Knight"):
        objs = import_glb(char_path(base))
        self.arm = next(o for o in objs if o.type == "ARMATURE")
        self.arm.name = "Rig"
        self.arm.animation_data_clear()
        self.arm.data.pose_position = "REST"
        self.parts = {}
        self._take(objs)

    def _take(self, objs):
        for o in objs:
            if o.type == "MESH" and _strip(o.name) == "Icosphere":
                bpy.data.objects.remove(o)
            elif o.type == "MESH":
                self.parts[_strip(o.name)] = o

    def borrow(self, char, names):
        """Copies parts (by name) from another KayKit character onto this rig."""
        objs = import_glb(char_path(char))
        other = next(o for o in objs if o.type == "ARMATURE")
        got = []
        for o in objs:
            if o.type != "MESH":
                continue
            n = _strip(o.name)
            if n in names:
                mw = o.matrix_world.copy()
                if o.parent_type == "BONE":
                    bone = o.parent_bone
                    o.parent = self.arm
                    o.parent_type = "BONE"
                    o.parent_bone = bone
                    o.matrix_world = mw
                else:
                    o.parent = self.arm
                    o.matrix_world = mw
                    for m in o.modifiers:
                        if m.type == "ARMATURE":
                            m.object = self.arm
                self.parts[n] = o
                got.append(n)
            else:
                bpy.data.objects.remove(o)
        bpy.data.objects.remove(other)
        missing = set(names) - set(got)
        if missing:
            raise RuntimeError("%s has no %s" % (char, missing))

    def drop(self, *names):
        for n in names:
            o = self.parts.pop(n, None)
            if o:
                bpy.data.objects.remove(o)

    def keep_only(self, names):
        for n in list(self.parts):
            if n not in names:
                self.drop(n)

    def bone_head(self, bone):
        return self.arm.matrix_world @ self.arm.data.bones[bone].head_local

    def bone_matrix(self, bone):
        """World matrix of a bone in rest pose (origin at the head)."""
        return self.arm.matrix_world @ self.arm.data.bones[bone].matrix_local

    def scale_head(self, f):
        """Shrinks the head (KayKit heads are chibi-sized) and everything worn on it."""
        pivot = self.bone_head("head")
        for n, o in self.parts.items():
            if o.parent_type == "BONE" and o.parent_bone == "head":
                mw = o.matrix_world
                o.matrix_world = Matrix.Translation(pivot) @ Matrix.Scale(f, 4) @ Matrix.Translation(-pivot) @ mw
            elif o.vertex_groups and "head" in o.vertex_groups:
                gi = o.vertex_groups["head"].index
                inv = o.matrix_world.inverted()
                for v in o.data.vertices:
                    w = next((g.weight for g in v.groups if g.group == gi), 0.0)
                    if w > 0.5:
                        wco = o.matrix_world @ v.co
                        v.co = inv @ (pivot + (wco - pivot) * f)

    def attach(self, obj, bone, name=None):
        """Parents a procedural mesh (built in world space at rest pose) to a bone."""
        bpy.context.view_layer.update()
        mw = obj.matrix_world.copy()
        obj.parent = self.arm
        obj.parent_type = "BONE"
        obj.parent_bone = bone
        obj.matrix_world = mw
        self.parts[name or obj.name] = obj
        return obj

    def to_palette(self, mat, override=None, part_overrides=None):
        part_overrides = part_overrides or {}
        for n, o in self.parts.items():
            if o.get("procedural"):
                o.data.materials.clear()
                o.data.materials.append(mat)
                continue
            ov = dict(override or {})
            ov.update(part_overrides.get(n, {}))
            remap_to_palette(o, mat, ov)

    def bake_rigid(self, keep_separate=()):
        """Turns bone-parented parts into skinned meshes (one bone, weight 1) so the
        whole body can be joined into one mesh; `keep_separate` parts stay objects
        (weapons the game shows or hides per action)."""
        for n, o in self.parts.items():
            if o.parent_type != "BONE":
                continue
            bone = o.parent_bone
            mw = o.matrix_world.copy()
            o.parent = self.arm
            o.parent_type = "OBJECT"
            o.matrix_world = mw
            bpy.context.view_layer.objects.active = o
            o.select_set(True)
            bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
            o.select_set(False)
            o.matrix_parent_inverse = self.arm.matrix_world.inverted()
            vg = o.vertex_groups.new(name=bone)
            vg.add([v.index for v in o.data.vertices], 1.0, "REPLACE")
            mod = o.modifiers.new("Armature", "ARMATURE")
            mod.object = self.arm

    def join_body(self, keep_separate=()):
        body = [o for n, o in self.parts.items() if n not in keep_separate]
        for o in body:
            bpy.context.view_layer.objects.active = o
            o.select_set(True)
            bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
            o.select_set(False)
        bpy.ops.object.select_all(action="DESELECT")
        for o in body:
            o.select_set(True)
        bpy.context.view_layer.objects.active = body[0]
        bpy.ops.object.join()
        j = bpy.context.view_layer.objects.active
        j.name = "Body"
        self.parts = {n: o for n, o in self.parts.items() if n in keep_separate}
        self.parts["Body"] = j
        return j

    def height(self):
        top = 0.0
        for o in self.parts.values():
            for c in o.bound_box:
                top = max(top, (o.matrix_world @ Vector(c)).z)
        return top


def export_glb(path, objects, animations=False):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objects:
        o.select_set(True)
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_apply=False,
        export_animations=animations, export_skins=True, export_morph=False,
        export_yup=True, export_texcoords=True, export_normals=True,
        export_materials="EXPORT", export_image_format="AUTO",
        export_anim_single_armature=True, export_force_sampling=True,
        export_optimize_animation_size=True, export_def_bones=False,
    )


# ------------------------------------------------------- procedural shapes ---

def _mesh_obj(name, bm):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(o)
    o["procedural"] = True
    for p in me.polygons:
        p.use_smooth = False
    return o


def cone(name, r1, r2, depth, segs=8, at=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=r1, radius2=r2, depth=depth)
    o = _mesh_obj(name, bm)
    o.location, o.rotation_euler, o.scale = at, rot, scale
    return o


def sphere(name, r, segs=8, rings=5, at=(0, 0, 0), scale=(1, 1, 1), cut=None):
    """UV sphere; `cut` (-1..1) removes everything below that fraction of the radius."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=r)
    if cut is not None:
        geom = [v for v in bm.verts if v.co.z < cut * r - 1e-4]
        bmesh.ops.delete(bm, geom=geom, context="VERTS")
    o = _mesh_obj(name, bm)
    o.location, o.scale = at, scale
    return o


def box(name, size, at=(0, 0, 0), rot=(0, 0, 0)):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
    o = _mesh_obj(name, bm)
    o.location, o.rotation_euler = at, rot
    return o


def torus(name, R, r, segs=10, ring=5, at=(0, 0, 0), rot=(0, 0, 0), arc=1.0):
    """Torus (or an arc of one, `arc` = fraction of a full turn) around z."""
    bm = bmesh.new()
    rings = []
    n = segs if arc >= 1.0 else segs + 1
    for i in range(n):
        a = 2 * math.pi * arc * i / segs
        c = Vector((math.cos(a) * R, math.sin(a) * R, 0))
        rad = Vector((math.cos(a), math.sin(a), 0))
        rings.append([bm.verts.new(c + rad * (math.cos(2 * math.pi * j / ring) * r) + Vector((0, 0, math.sin(2 * math.pi * j / ring) * r))) for j in range(ring)])
    for i in range(segs if arc >= 1.0 else segs):
        a, b = rings[i], rings[(i + 1) % n]
        for j in range(ring):
            bm.faces.new((a[j], a[(j + 1) % ring], b[(j + 1) % ring], b[j]))
    o = _mesh_obj(name, bm)
    o.location, o.rotation_euler = at, rot
    return o


def join(name, objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    j = bpy.context.view_layer.objects.active
    j.name = name
    j["procedural"] = True
    return j


def colored(obj, role, shade=None):
    set_faces_role(obj, role, shade)
    return obj
