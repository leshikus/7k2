extends Node3D
## Steps unit models through attacks at the simulation's frame rate and checks that
## each clip reaches its impact moment (UnitModels.HIT_TIME) on the frame the hit
## lands, then plays its follow-through before returning to standing.
var fails := 0

func _ready() -> void:
	if Assets.load_install() != "":
		get_tree().quit(1); return
	Defs.load_from_assets()
	var lib := ModelLibrary.new()
	var dt := 1.0 / Defs.SIM_FPS
	for code in ["NO_INF", "VI_INF", "GR_INF", "NO_SPU", "MO_SPU", "VI_SPU", "GITH", "CE_SPU"]:
		for att in Defs.unit_types[code]["attacks"]:
			var act: String = att["action"]
			if not Assets.has_action(code, act):
				continue
			var u := Unit.new()
			u.sprite_code = code
			u.utype = Defs.unit_types[code]
			u.nation_id = 1
			u.dir = 3
			var m := lib.make(u)
			add_child(m)
			var ap := _body_ap(m)
			var clip := UnitModels.clip_for(UnitModels.spec(code), act)
			var n := Assets.action_len(code, act, 3)
			u.action = act
			u.attacking = true
			for f in n:
				u.anim_frame = f
				lib.sync(u, m)
				ap.advance(dt)
			# the simulation deals the hit now
			var at := ap.current_animation_position / ap.current_animation_length
			var want := UnitModels.hit_time(clip)
			var ok := ap.current_animation == clip and absf(at - want) < 0.06
			# back to standing: the swing should keep playing, then idle
			u.action = "S"
			u.attacking = false
			u.anim_frame = 0
			lib.sync(u, m)
			ap.advance(dt)
			var follows := ap.current_animation == clip
			for i in 80:
				lib.sync(u, m)
				ap.advance(dt)
			var idles := ap.current_animation == UnitModels.clip_for(UnitModels.spec(code), "S")
			_check(ok and follows and idles, "%s %s %s: impact at %.2f (want %.2f), follow-through %s, then idle %s" % [code, act, clip, at, want, follows, idles])
			m.queue_free()
	print("RESULT: ", "PASS" if fails == 0 else "FAIL")
	get_tree().quit(0 if fails == 0 else 2)


func _body_ap(m: Node3D) -> AnimationPlayer:
	for part in m.get_meta("st")["parts"]:
		if part["role"] == "body" and part["ap"]:
			return part["ap"]
	return null


func _check(c: bool, what: String) -> void:
	print(("  ok   " if c else "  FAIL ") + what)
	if not c:
		fails += 1
