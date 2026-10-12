extends Node3D
## Shows unit models in a row from the game's camera angle, each playing an action,
## and saves a screenshot. Usage:
##   godot --path . res://tests/model_gallery.tscn -- codes=NO_INF,VI_INF act=A1 shot=<png> t=0.6
## "act=cycle" shows S, M, A1, A2, A3 and D side by side for every code.
var units := []
var act := "S"

func _ready() -> void:
	if Assets.load_install() != "":
		get_tree().quit(1); return
	Defs.load_from_assets()
	var codes: Array = UnitModels.SPECS.keys()
	var shot := ""
	var t := 0.8
	var yaw := 0.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("codes="): codes = Array(a.substr(6).split(","))
		elif a.begins_with("act="): act = a.substr(4)
		elif a.begins_with("shot="): shot = a.substr(5)
		elif a.begins_with("t="): t = a.substr(2).to_float()
		elif a.begins_with("yaw="): yaw = a.substr(4).to_float()
	var lib := ModelLibrary.new()
	var acts := ["S", "M", "A1", "A2", "A3", "D"] if act == "cycle" else [act]
	var row := 0
	for code in codes:
		var col := 0
		for ac in acts:
			if ac != "S" and ac != "M" and ac != "D" and not Assets.has_action(code, ac):
				continue
			var u := Unit.new()
			u.sprite_code = code
			u.utype = Defs.unit_types.get(code, {})
			u.nation_id = 1
			u.action = ac
			u.attacking = ac.begins_with("A")
			u.dir = 3
			u.set_meta("preview_color", Color(0.85, 0.15, 0.12))
			var m := lib.make(u)
			if m == null:
				print("no model for ", code)
				continue
			add_child(m)
			var gx := col if acts.size() > 1 else row % 6
			var gy := row if acts.size() > 1 else row / 6
			m.position = (Vector3(1, 0, -1) * gx + Vector3(1, 0, 1) * gy * 1.4) * 0.85
			units.append([u, m])
			col += 1
		row += 1
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.6 + 1.0 * (acts.size() if acts.size() > 1 else mini(6, codes.size()))
	add_child(cam)
	var center := Vector3.ZERO
	for p in units: center += p[1].position
	center /= maxf(1, units.size())
	center += Vector3(0.5, 0.6, 0.5)
	# the original view: screen-up is location (-1,-1), so the camera sits on the (+1,+1) side
	var back := Vector3(1, 0, 1).normalized().rotated(Vector3.UP, deg_to_rad(yaw))
	cam.position = center + back * 20.0 * cos(deg_to_rad(30)) + Vector3.UP * 20.0 * sin(deg_to_rad(30))
	cam.look_at(center, Vector3.UP)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.45, 0.52, 0.4)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	add_child(env)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(60, 60)
	ground.mesh = pm
	var gm := StandardMaterial3D.new(); gm.albedo_color = Color(0.42, 0.5, 0.36)
	ground.material_override = gm
	add_child(ground)
	if shot != "":
		await get_tree().create_timer(t).timeout
		get_viewport().get_texture().get_image().save_png(shot)
		get_tree().quit()

func _process(_d: float) -> void:
	var lib := ModelLibrary.new()
	for p in units:
		var u: Unit = p[0]
		if u.attacking:
			u.anim_frame = (u.anim_frame + 1) % maxi(1, Assets.action_len(u.sprite_code, u.action, 3))
		lib.sync(u, p[1])
