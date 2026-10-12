extends Node
## Checks every unit model's attack animations against the original's attacks:
## the clip exists, its kind (melee, shot, throw, spell) fits the attack's range and
## projectile, and the weapons it shows exist on the model. Also prints each clip's
## impact time (from the right hand's peak speed), used by UnitModels.HIT_TIME.
##   godot --headless --path . res://tests/tools/attack_audit.tscn [-- hits]

func _ready() -> void:
	if Assets.load_install() != "":
		get_tree().quit(1); return
	Defs.load_from_assets()
	var lib := ModelLibrary.new()
	var problems := 0
	var anims := ModelLibrary.anim_library("humanoid")
	for code in UnitModels.SPECS.keys():
		var spec: Dictionary = UnitModels.SPECS[code]
		var ut: Dictionary = Defs.unit_types.get(code, {})
		if ut.is_empty() or not Assets.has_sprite(code):
			continue
		var u := Unit.new()
		u.sprite_code = code
		u.utype = ut
		u.nation_id = 1
		var m := lib.make(u)
		var weapons: Dictionary = m.get_meta("st")["weapons"] if m else {}
		var line := "%-9s" % code
		for att in ut.get("attacks", []):
			var act: String = att["action"]
			if not Assets.has_action(code, act):
				line += "  %s:(no sprite)" % act
				continue
			var ranged: bool = att["range"] > 1 or att["bullet"] != ""
			var own: bool = spec.get("own_anims", false) or spec.get("model", "") == ""
			var clip := UnitModels.mount_clip_for(spec, act) if own else UnitModels.clip_for(spec, act)
			var kind := _kind(clip)
			var note := ""
			if not own and anims and not anims.has_animation(clip):
				note += " MISSING-CLIP"
			if not own:
				if ranged and kind == "melee":
					note += " MELEE-CLIP-FOR-RANGED"
				elif not ranged and kind != "melee":
					note += " %s-CLIP-FOR-MELEE" % kind.to_upper()
				for w in UnitModels.weapons_for(spec, act):
					if not weapons.has(w):
						note += " NO-" + w
				var shown: Array = UnitModels.weapons_for(spec, act)
				if kind == "shot" and not shown.any(func(w): return w.contains("Bow")):
					note += " SHOOTS-WITHOUT-BOW"
				if kind == "melee" and shown.is_empty() and not clip.begins_with("Unarmed") and not clip.contains("Block"):
					note += " ARMED-CLIP-NO-WEAPON"
			if note != "":
				problems += 1
			line += "  %s[r%d %s]=%s%s" % [act, att["range"], att["bullet"], clip, note]
		print(line)
		if m:
			m.free()
	print("problems: ", problems)
	if "hits" in OS.get_cmdline_user_args():
		_hit_times()
	get_tree().quit(0)


static func _kind(clip: String) -> String:
	if clip.contains("Ranged") or clip.contains("Shoot") and not clip.begins_with("Spell"):
		return "shot"
	if clip.contains("Throw"):
		return "throw"
	if clip.begins_with("Spell") or clip.contains("Spellcast"):
		return "spell"
	return "melee"


## Impact time of each attack clip: the moment the right hand moves fastest.
func _hit_times() -> void:
	var scene := ModelLibrary._scene("units/NO_INF.glb")
	var inst: Node3D = scene.instantiate()
	add_child(inst)
	var ap := ModelLibrary._anim_player(inst, "humanoid")
	var sk: Skeleton3D = inst.find_children("*", "Skeleton3D", true, false)[0]
	var hand := sk.find_bone("hand.r")
	if hand < 0:
		hand = sk.find_bone("handslot.r")
	var clips := {}
	for s in UnitModels.SPECS.values():
		for c in s.get("clips", {}).values():
			clips[c] = true
	for c in UnitModels.DEFAULT_CLIPS.values() + UnitModels.RIDE_CLIPS.values():
		clips[c] = true
	var names := clips.keys()
	names.sort()
	for clip in names:
		if not ap.has_animation(clip) or clip in UnitModels.LOOPING or clip.begins_with("Death"):
			continue
		var length := ap.get_animation(clip).length
		ap.play(clip)
		var prev := Vector3.ZERO
		var best := 0.0
		var best_t := 0.0
		var steps := int(length * 60.0)
		for i in steps + 1:
			var t := float(i) / 60.0
			ap.seek(t, true)
			sk.force_update_all_bone_transforms() if sk.has_method("force_update_all_bone_transforms") else null
			var p := sk.get_bone_global_pose(hand).origin
			if i > 0:
				var v := (p - prev).length()
				if v > best:
					best = v
					best_t = t
			prev = p
		print("HIT %-36s len %.2f  peak %.2f  (%.2f)" % [clip, length, best_t, best_t / length])
