import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy, math
from common import *
reset()
r = Rig("Knight")
r.keep_only(["Knight_Body", "Knight_ArmLeft", "Knight_ArmRight", "Knight_LegLeft", "Knight_LegRight", "Knight_Head", "Knight_Helmet", "Knight_Cape", "1H_Sword", "Badge_Shield"])
r.scale_head(0.65)
pal = make_palette("pal_NORMAN", {"cloth_dark": "#5a4a3a"})
mat = palette_material(pal)
r.to_palette(mat)
r.bake_rigid()
r.join_body(keep_separate=("1H_Sword", "Badge_Shield"))
h = r.height()
print("HEIGHT", h)
s = 1.2 / h
r.arm.scale = (s, s, s)
export_glb(os.path.join(OUT, "test", "proto.glb"), [r.arm] + list(r.parts.values()))
