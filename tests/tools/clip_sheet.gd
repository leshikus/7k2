extends Node3D
## Contact sheet of animation clips: one row per clip, `n` poses from start to end,
## seen from the side, to read off where each strike lands. Usage:
##   godot --path . res://tests/tools/clip_sheet.tscn -- clips=A,B model=units/NO_INF.glb n=8 shot=<png>

func _ready() -> void:
	if Assets.load_install() != "":
		get_tree().quit(1); return
	var clips: Array = ["1H_Melee_Attack_Chop"]
	var model := "units/NO_INF.glb"
	var n := 8
	var shot := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("clips="): clips = Array(a.substr(6).split(","))
		elif a.begins_with("model="): model = a.substr(6)
		elif a.begins_with("n="): n = a.substr(2).to_int()
		elif a.begins_with("shot="): shot = a.substr(5)
	var scene := ModelLibrary._scene(model)
	for r in clips.size():
		for i in n:
			var inst: Node3D = scene.instantiate()
			add_child(inst)
			inst.position = Vector3(i * 1.3, -r * 1.9, 0)
			inst.rotation.y = -PI / 2      # face screen-left: strikes go sideways
			var ap := ModelLibrary._anim_player(inst, "humanoid")
			if ap == null or not ap.has_animation(clips[r]):
				continue
			ap.play(clips[r])
			ap.seek(ap.get_animation(clips[r]).length * i / float(n - 1), true)
			ap.pause()
		var lbl := Label3D.new()
		lbl.text = "%s" % clips[r]
		lbl.font_size = 48
		lbl.position = Vector3(-1.6, -r * 1.9 + 1.0, 0)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		add_child(lbl)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = maxf(clips.size() * 1.9 + 0.4, 3.0)
	cam.position = Vector3((n - 1) * 0.65 - 1.0, -(clips.size() - 1) * 0.95 + 0.6, 20)
	add_child(cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, -20, 0)
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.82, 0.82, 0.78)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	add_child(env)
	get_window().size = Vector2i(1600, mini(1000, 200 + clips.size() * 160))
	if shot != "":
		await get_tree().create_timer(0.5).timeout
		get_viewport().get_texture().get_image().save_png(shot)
		get_tree().quit()
