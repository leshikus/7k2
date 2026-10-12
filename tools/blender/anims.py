"""Exports the shared humanoid animation library: the KayKit rig with every clip.
Unit models carry no animations; the game plays these clips on any humanoid."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy
from common import *

reset()
objs = import_glb(char_path("Skeleton_Minion"))
arm = next(o for o in objs if o.type == "ARMATURE")
arm.name = "Rig"
# Godot only builds a Skeleton3D for skinned glTF nodes, so keep one tiny skinned part.
for o in objs:
    if o.type == "MESH" and not o.name.startswith("Skeleton_Minion_Eyes"):
        bpy.data.objects.remove(o)
eyes = next(o for o in bpy.data.objects if o.type == "MESH")
eyes.name = "Anchor"
for a in bpy.data.actions:
    a.use_fake_user = True
    if a.name.endswith("_Rig"):
        a.name = a.name[:-4]
# --- riding clips: seated legs (from Sit_Chair_Pose) + the upper body of a clip ---
from mathutils import Quaternion
LOWER = ("root", "hips", "upperleg", "lowerleg", "foot", "toes", "IK", "kneeIK", "heelIK", "control")
RIDE = ["Idle", "1H_Melee_Attack_Chop", "1H_Melee_Attack_Slice_Diagonal", "1H_Melee_Attack_Stab",
        "1H_Melee_Attack_Slice_Horizontal", "2H_Melee_Attack_Stab", "2H_Melee_Attack_Chop",
        "2H_Ranged_Shoot", "Throw", "Spellcast_Shoot", "Hit_A"]
SPREAD = 0.55   # radians each thigh turns outward to straddle the mount


def _bone(dp):
    return dp.split('"')[1] if dp.startswith("pose.bones") else ""


def _lower(b):
    return any(b == k or b.startswith(k + ".") or b.startswith(k + "-") or b.startswith(k) for k in LOWER)


sit = bpy.data.actions["Sit_Chair_Pose"]
f0 = sit.frame_range[0]
for name in RIDE:
    src = bpy.data.actions[name]
    a = src.copy()
    a.name = "Ride_" + name
    a.use_fake_user = True
    for fc in list(a.fcurves):
        if _lower(_bone(fc.data_path)):
            a.fcurves.remove(fc)
    r0, r1 = src.frame_range
    vals = {}
    for fc in sit.fcurves:
        b = _bone(fc.data_path)
        if _lower(b):
            vals[(fc.data_path, fc.array_index)] = fc.evaluate(f0)
    for side, sgn in (("l", 1), ("r", -1)):
        dp = 'pose.bones["upperleg.%s"].rotation_quaternion' % side
        q = Quaternion([vals.get((dp, i), (1, 0, 0, 0)[i]) for i in range(4)])
        q = q @ Quaternion((0, 0, 1), sgn * SPREAD)
        for i in range(4):
            vals[(dp, i)] = q[i]
    # hips at the rig origin, so the model's root can sit on the saddle point
    hp = 'pose.bones["hips"].location'
    vals[(hp, 0)] = 0.0
    vals[(hp, 1)] = -arm.data.bones["hips"].head_local.z
    vals[(hp, 2)] = 0.0
    for (dp, i), v in vals.items():
        fc = a.fcurves.new(dp, index=i, action_group=_bone(dp))
        fc.keyframe_points.insert(r0, v)
        fc.keyframe_points.insert(r1, v)

print("ACTIONS", sorted(a.name for a in bpy.data.actions))
bpy.ops.object.select_all(action="DESELECT")
arm.select_set(True); eyes.select_set(True)
os.makedirs(os.path.join(OUT, "anims"), exist_ok=True)
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "anims", "humanoid.glb"), export_format="GLB",
    use_selection=True, export_animations=True, export_animation_mode="ACTIONS",
    export_skins=True, export_force_sampling=True, export_optimize_animation_size=True,
    export_anim_single_armature=True, export_def_bones=False, export_materials="NONE")
