class_name UnitModels
## Which model and which animation clips each unit sprite uses. Clip names are
## those of the shared humanoid library (anims/humanoid.glb, from KayKit's rig).
## "weapons" lists the W_* meshes shown during an action (others are hidden).

## Clips that loop (stand and move).
const LOOPING := ["Idle", "Idle_B", "Idle_Combat", "2H_Melee_Idle", "Unarmed_Idle", "Walking_A",
	"Walking_B", "Walking_C", "Walking_D_Skeletons", "Running_A", "Running_B", "Running_C",
	"Spellcasting", "Lie_Idle", "Sit_Floor_Idle", "Ride_Idle", "Ride_Gallop"]

const DEFAULT_CLIPS := {"S": "Idle", "M": "Walking_A", "A1": "1H_Melee_Attack_Chop",
	"A2": "1H_Melee_Attack_Slice_Diagonal", "A3": "1H_Melee_Attack_Stab", "D": "Death_A"}

static var SPECS := {
	# civilians: work tools
	"NO_CIV": _civ("NO_CIV"), "VI_CIV": _civ("VI_CIV"), "CE_CIV": _civ("CE_CIV"), "RO_CIV": _civ("RO_CIV"),
	"GR_CIV": _civ("GR_CIV"), "CT_CIV": _civ("CT_CIV"), "CH_CIV": _civ("CH_CIV"), "JA_CIV": _civ("JA_CIV"),
	"MO_CIV": _civ("MO_CIV"), "EG_CIV": _civ("EG_CIV"), "PE_CIV": _civ("PE_CIV"), "IN_CIV": _civ("IN_CIV"),
	# infantry
	"NO_INF": _u("NO_INF", {"A2": BOW_CLIP}, {"*": ["W_Sword", "W_Shield"], "A2": ["W_Bow"]}),
	"VI_INF": _u("VI_INF", {"A2": "2H_Melee_Attack_Chop"}, {"*": ["W_Axe", "W_Shield"], "A2": ["W_Axe2"]}),
	"CE_INF": _u("CE_INF", {"A1": "1H_Melee_Attack_Slice_Diagonal", "A2": "1H_Melee_Attack_Stab"}, {"*": ["W_Sword", "W_Shield"]}),
	"RO_INF": _u("RO_INF", {"A1": "1H_Melee_Attack_Stab"}, {"*": ["W_Sword", "W_Shield"]}),
	"GR_INF": _u("GR_INF", {"A1": "1H_Melee_Attack_Stab"}, {"*": ["W_Spear", "W_Shield"]}),
	"CT_INF": _u("CT_INF", {"A2": BOW_CLIP}, {"*": ["W_Sword", "W_Shield"], "A2": ["W_Bow"]}),
	"CH_INF": _u("CH_INF", {"A1": "1H_Melee_Attack_Slice_Diagonal", "A2": BOW_CLIP}, {"*": ["W_Sword"], "A2": ["W_Bow"]}),
	"JA_INF": _u("JA_INF", {"A1": "1H_Melee_Attack_Slice_Horizontal", "A2": "2H_Melee_Attack_Stab"}, {"*": ["W_Sword"], "A2": ["W_Spear"]}),
	"MO_INF": _u("MO_INF", {"A1": "1H_Melee_Attack_Slice_Diagonal", "A2": "1H_Melee_Attack_Chop"}, {"*": ["W_Sword"], "A2": ["W_Sword2"]}),
	"EG_INF": _u("EG_INF", {"A2": BOW_CLIP}, {"*": ["W_Sword", "W_Shield"], "A2": ["W_Bow"]}),
	"PE_INF": _u("PE_INF", {"A1": "1H_Melee_Attack_Stab", "A2": BOW_CLIP, "A3": BOW_CLIP}, {"*": ["W_Spear", "W_Shield"], "A2": ["W_Bow"], "A3": ["W_Bow"]}),
	"IN_INF": _u("IN_INF", {"A1": "1H_Melee_Attack_Slice_Diagonal", "A2": BOW_CLIP}, {"*": ["W_Sword", "W_Shield"], "A2": ["W_Bow"]}),
	# special units on foot
	"VI_SPU": _u("VI_SPU", {"A2": "2H_Melee_Attack_Spin", "A3": "Throw"}, {"*": ["W_Axe"], "A2": ["W_Axe2"], "A3": ["W_Throw"]}),
	"CE_SPU": _u("CE_SPU", {"A1": "2H_Melee_Attack_Chop", "A2": "2H_Melee_Attack_Stab", "A3": "Spellcast_Shoot"}, {"*": ["W_Staff"]}),
	"CH_SPU": _u("CH_SPU", {"S": "Unarmed_Idle", "A1": "Unarmed_Melee_Attack_Kick", "A2": "Unarmed_Melee_Attack_Punch_A"}, {"*": []}),
	# mounted special units
	"NO_SPU": _ride("NO_SPU", "horse_bay", {}, {"*": ["W_Sword", "W_Shield"]}),
	"RO_SPU": _ride("RO_SPU", "horse_chestnut", {"A2": "Ride_1H_Melee_Attack_Stab"}, {"*": ["W_Sword"], "A2": ["W_Spear"], "A3": ["W_Throw"]}),
	"GR_SPU": _ride("GR_SPU", "horse_grey", {"A1": "Ride_1H_Melee_Attack_Stab", "A2": "Ride_2H_Melee_Attack_Stab"}, {"*": ["W_Spear", "W_Shield"]}),
	"MO_SPU": _ride("MO_SPU", "horse_white", {"A2": "Ride_2H_Ranged_Shoot"}, {"*": ["W_Sword"], "A2": ["W_Bow"], "A3": ["W_Throw"]}),
	"PE_SPU": _ride("PE_SPU", "horse_black", {"A2": "Ride_1H_Melee_Attack_Stab"}, {"*": ["W_Sword"], "A3": ["W_Throw"]}),
	"CT_SPU": _ride("CT_SPU", "elephant", {"A1": "Ride_2H_Melee_Attack_Stab", "A2": "Ride_2H_Melee_Attack_Stab"}, {"*": ["W_Spear"]}, 2.0),
	"IN_SPU": _ride("IN_SPU", "elephant_white", {"A1": "Ride_2H_Melee_Attack_Stab", "A2": "Ride_Throw"}, {"*": ["W_Spear"], "A2": ["W_Throw"], "A3": ["W_Throw"]}, 2.0),
	"EG_SPU": {"model": "riders/EG_SPU.glb", "cart": "props/chariot.glb", "seat": Vector3(0, 0.36, -0.1),
		"pullers": [["mounts/horse_bay.glb", Vector3(-0.32, 0, 1.75)], ["mounts/horse_chestnut.glb", Vector3(0.32, 0, 1.75)]],
		"clips": {"M": "Idle", "A1": "1H_Melee_Attack_Stab", "A2": "Throw", "A3": "Throw"},
		"weapons": {"*": ["W_Spear"], "A2": ["W_Throw"], "A3": ["W_Throw"]}, "mount_stride": 2.4},
	"CARAVAN": {"model": "", "cart": "props/caravan.glb", "pullers": [["mounts/horse_grey.glb", Vector3(0, 0, 1.55)]], "mount_move": "Walk", "mount_stride": 1.4},
	"WAGON": {"model": "", "cart": "props/wagon.glb", "pullers": [["mounts/horse_bay.glb", Vector3(0, 0, 1.55)]], "mount_move": "Walk", "mount_stride": 1.4},
	# Fryhtans: new skins on the humanoid rig
	"PLANT": _f("PLANT", {"S": "Idle_Combat", "A1": "Unarmed_Melee_Attack_Punch_A", "A2": "2H_Melee_Attack_Spin"}, {}, 1.0),
	"LYW": _f("LYW", {"S": "Unarmed_Idle", "M": "Walking_D_Skeletons", "A1": "Unarmed_Melee_Attack_Punch_B", "A2": "Unarmed_Melee_Attack_Kick", "D": "Death_C_Skeletons"}, {}, 0.8),
	"HOBGLOB": _f("HOBGLOB", {"A1": "Unarmed_Melee_Attack_Punch_A", "A2": BOW_CLIP, "A3": "Unarmed_Melee_Attack_Kick"}, {"*": [], "A2": ["W_Bow"]}, 1.0),
	"GIANTET": _f("GIANTET", {"S": "2H_Melee_Idle", "A1": "2H_Melee_Attack_Chop", "A2": "2H_Melee_Attack_Slice"}, {"*": ["W_Axe"]}, 1.2),
	"GITH": _f("GITH", {"S": "Unarmed_Idle", "M": "Walking_C", "A1": "Unarmed_Melee_Attack_Punch_B", "A2": "Throw", "A3": "Throw"}, {"*": [], "A2": ["W_Throw"], "A3": ["W_Throw"]}, 1.3),
	"ROCKMAN": _f("ROCKMAN", {"A1": "1H_Melee_Attack_Slice_Diagonal", "A2": "Block_Attack"}, {"*": ["W_Sword", "W_Shield"]}, 1.1),
	"GREMJERM": _f("GREMJERM", {"M": "Running_B", "A1": "Unarmed_Melee_Attack_Punch_A", "A2": "Unarmed_Melee_Attack_Kick", "A3": "Spellcast_Shoot"}, {}, 1.4),
	"GORILLA": _f("GORILLA", {"S": "Unarmed_Idle", "M": "Walking_C", "A1": "Unarmed_Melee_Attack_Punch_A", "A2": "Unarmed_Melee_Attack_Punch_B"}, {}, 1.0),
	# animals and insects with their own rigs
	"BEE": {"model": "fryhtans/BEE.glb", "own_anims": true, "beast_clips": {"S": "Flying", "M": "Flying", "D": "Death"}, "mount_stride": 1.0, "fly": 0.9},
	"TERMITE": {"model": "fryhtans/TERMITE.glb", "own_anims": true, "beast_clips": {"M": "Walk"}, "mount_stride": 0.5},
	"JAGUAR": {"model": "fryhtans/JAGUAR.glb", "own_anims": true, "beast_clips": {"M": "Walk"}, "mount_stride": 0.9},
	"RHINOCER": {"model": "", "mount": "mounts/rhino.glb", "mount_move": "Walk", "mount_stride": 1.2},
	# siege weapons (rigid; parts animated in code)
	"CATAPULT": _siege("CATAPULT"), "BALLISTA": _siege("BALLISTA"), "FLAMETHR": _siege("FLAMETHR"),
	"CANNON": _siege("CANNON"), "EXPCART": _siege("EXPCART"), "F_BALLIS": _siege("F_BALLIS"),
	"M_CANNON": _siege("M_CANNON"), "M_F_BALL": _siege("M_F_BALL"), "M_SAW": _siege("M_SAW"),
	"F_CANNON": _siege("F_CANNON"), "F__BALLI": _siege("F__BALLI"), "F_CATAPU": _siege("F_CATAPU"),
	# Greater Beings: large and hovering
	"NO_GOD": _god("NO_GOD", {"A1": "1H_Melee_Attack_Slice_Diagonal"}, {"*": ["W_Sword"]}),
	"VI_GOD": _god("VI_GOD", {"A1": "Spellcast_Shoot"}, {"*": ["W_Hammer"]}),
	"CE_GOD": _god("CE_GOD", {"A1": "Spellcast_Long"}, {"*": ["W_Staff"]}),
	"RO_GOD": _god("RO_GOD", {"A1": "1H_Melee_Attack_Stab"}, {"*": ["W_Spear", "W_Shield"]}),
	"GR_GOD": _god("GR_GOD", {"A1": "1H_Melee_Attack_Stab"}, {"*": ["W_Spear", "W_Shield"]}),
	"CA_GOD": _god("CA_GOD", {"A1": "Spellcast_Summon"}, {"*": ["W_Staff"]}),
	"CH_GOD": {"model": "", "mount": "mounts/qilin.glb", "fly": 0.5, "mount_move": "Run", "mount_stride": 3.0},
	"JA_GOD": _god("JA_GOD", {"A1": "Spellcast_Shoot"}, {}),
	"MO_GOD": _god("MO_GOD", {"A1": BOW_CLIP}, {"*": ["W_Bow"]}),
	"EG_GOD": _god("EG_GOD", {"A1": "Spellcast_Raise"}, {}),
	"PE_GOD": _god("PE_GOD", {"A1": "1H_Melee_Attack_Slice_Horizontal"}, {"*": ["W_Sword"]}),
	"IN_GOD": _god("IN_GOD", {"A1": "2H_Melee_Attack_Chop"}, {"*": ["W_Club"]}),
	"JA_SPU": _u("JA_SPU", {"A1": "1H_Melee_Attack_Slice_Horizontal", "A2": "Dualwield_Melee_Attack_Stab", "A3": "Throw"}, {"*": ["W_Sword"], "A2": ["W_Sword", "W_Knife"], "A3": ["W_Throw"]}),
}

## Where in each attack clip (0..1) the blow lands or the missile leaves the hand,
## read off contact sheets (tests/tools/clip_sheet.tscn) and the right hand's peak
## speed (tests/tools/attack_audit.tscn -- hits). The view times the clip so this
## moment falls on the sprite action's last frame, when the simulation deals the hit.
const HIT_TIME := {
	"1H_Melee_Attack_Chop": 0.58, "1H_Melee_Attack_Slice_Diagonal": 0.45,
	"1H_Melee_Attack_Slice_Horizontal": 0.3, "1H_Melee_Attack_Stab": 0.3,
	"2H_Melee_Attack_Chop": 0.5, "2H_Melee_Attack_Slice": 0.38, "2H_Melee_Attack_Spin": 0.5,
	"2H_Melee_Attack_Stab": 0.3, "2H_Ranged_Shoot": 0.5, "Block_Attack": 0.5,
	"Dualwield_Melee_Attack_Stab": 0.3, "Ride_1H_Melee_Attack_Chop": 0.6,
	"Ride_1H_Melee_Attack_Slice_Diagonal": 0.45, "Ride_1H_Melee_Attack_Stab": 0.3,
	"Ride_2H_Melee_Attack_Stab": 0.3, "Ride_2H_Ranged_Shoot": 0.5, "Ride_Throw": 0.55,
	"Spellcast_Long": 0.65, "Spellcast_Raise": 0.5, "Spellcast_Shoot": 0.4,
	"Spellcast_Summon": 0.68, "Throw": 0.55, "Unarmed_Melee_Attack_Kick": 0.38,
	"Unarmed_Melee_Attack_Punch_A": 0.32, "Unarmed_Melee_Attack_Punch_B": 0.32,
}

const BOW_CLIP := "2H_Ranged_Shoot"
const RIDE_CLIPS := {"S": "Ride_Idle", "M": "Ride_Idle", "A1": "Ride_1H_Melee_Attack_Chop",
	"A2": "Ride_1H_Melee_Attack_Slice_Diagonal", "A3": "Ride_Throw", "D": "Death_B"}


## A rider (riders/<code>.glb) on a mount (mounts/<mount>.glb).
static func _ride(code: String, mount: String, clips: Dictionary, weapons: Dictionary, stride := 2.4) -> Dictionary:
	var c := RIDE_CLIPS.duplicate()
	c.merge(clips, true)
	return {"model": "riders/%s.glb" % code, "mount": "mounts/%s.glb" % mount, "clips": c,
		"weapons": weapons, "mount_stride": stride}


static func _u(code: String, clips: Dictionary, weapons: Dictionary) -> Dictionary:
	return {"model": "units/%s.glb" % code, "clips": clips, "weapons": weapons}


static func _f(code: String, clips: Dictionary, weapons: Dictionary, stride: float) -> Dictionary:
	return {"model": "fryhtans/%s.glb" % code, "clips": clips, "weapons": weapons, "stride": stride}


static func _god(code: String, clips: Dictionary, weapons: Dictionary) -> Dictionary:
	var c := {"S": "Spellcasting", "M": "Idle"}
	c.merge(clips, true)
	return {"model": "gods/%s.glb" % code, "clips": c, "weapons": weapons, "fly": 0.6, "hover": true}


static func _siege(code: String) -> Dictionary:
	return {"model": "", "cart": "siege/%s.glb" % code}


static func _civ(code: String) -> Dictionary:
	return _u(code, {"A1": "1H_Melee_Attack_Chop"}, {"*": ["W_Tool"]})


static func hit_time(clip: String) -> float:
	return HIT_TIME.get(clip, 0.5)


static func spec(code: String) -> Dictionary:
	return SPECS.get(code, {})


static func clip_for(s: Dictionary, act: String, variant := 0) -> String:
	var clips: Dictionary = s.get("clips", {})
	if act == "D" and not clips.has("D"):
		return "Death_A" if variant % 2 == 0 else "Death_B"
	if clips.has(act):
		return clips[act]
	return DEFAULT_CLIPS.get(act, "Idle")


## Mount clips (mounts.py): Idle, Walk, Run, Attack (rearing), Death.
static func mount_clip_for(s: Dictionary, act: String) -> String:
	var own: Dictionary = s.get("beast_clips", {})
	if own.has(act):
		return own[act]
	if act == "S":
		return "Idle"
	if act == "M":
		return s.get("mount_move", "Run")
	if act == "D":
		return "Death"
	return "Attack"


static func weapons_for(s: Dictionary, act: String) -> Array:
	var w: Dictionary = s.get("weapons", {})
	return w.get(act, w.get("*", []))
