class_name ModelLibrary
extends RefCounted
## Supplies low-poly 3D models to View3D in place of the original sprites
## (View3D.model_provider). Models are built by tools/blender and live in
## res://assets/models. An object without a model keeps its sprite cards.
##
## Humanoid units share one skeleton; their clips come from one animation library
## (anims/humanoid.glb) and are chosen per sprite action through UnitModels.

const MODEL_DIR := "res://assets/models/"
## Unshaded with its own fixed sun, like the original's pre-lit sprites (the 3D
## view has no lights of its own).
const TEAM_SHADER := """
shader_type spatial;
render_mode cull_back, unshaded;
uniform sampler2D palette : source_color, filter_nearest;
uniform vec4 team_color : source_color = vec4(1.0);
uniform vec4 tint : source_color = vec4(1.0);
const vec3 SUN = vec3(-0.45, 0.80, -0.40);
void fragment() {
	vec4 t = texture(palette, UV);
	// alpha 0 marks the nation-colour cells (see tools/blender/common.py)
	vec3 c = mix(t.rgb * team_color.rgb, t.rgb, step(0.5, t.a));
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float light = 0.62 + 0.55 * max(dot(n, normalize(SUN)), 0.0) + 0.08 * n.y;
	ALBEDO = c * tint.rgb * light;
}
"""

static var _scenes := {}            # path -> PackedScene (or null when missing)
static var _anim_libs := {}         # name -> AnimationLibrary
static var _shader: Shader
static var _materials := {}         # "palette path|team colour" -> ShaderMaterial


static var _requested := false


func _init() -> void:
	# load every model in the background now, so the first unit or building of a
	# kind does not stall a frame when it appears
	if _requested:
		return
	_requested = true
	for dir in ["anims", "units", "riders", "mounts", "fryhtans", "gods", "siege", "props", "projectiles", "buildings", "houses", "nature"]:
		for f in DirAccess.get_files_at(MODEL_DIR + dir):
			f = f.trim_suffix(".import")          # exported games list X.glb.import
			if f.ends_with(".glb"):
				ResourceLoader.load_threaded_request(MODEL_DIR + dir + "/" + f)


func make(obj: Object) -> Node3D:
	if obj is Unit:
		return _make_unit(obj)
	if obj is Bullet:
		return _make_bullet(obj)
	if obj is Firm:
		return _make_firm(obj)
	if obj is Town:
		return _make_town(obj)
	if obj is Plant:
		return _make_plant(obj)
	if obj is Rock:
		return _make_rock(obj)
	if obj is FirmEffect:
		return _make_firm_effect(obj)
	if obj is SpriteEffect:
		return _make_spell_effect(obj)
	if obj is Tornado:
		return _make_tornado(obj)
	return null


func sync(obj: Object, model: Node3D) -> void:
	if obj is Plant or obj is Rock:
		return
	if obj is Unit:
		_sync_unit(obj, model)
	elif obj is Bullet:
		_sync_bullet(obj, model)
	elif obj is Firm:
		_sync_firm(obj, model)
	elif obj is Town:
		_sync_town(obj, model)
	elif obj is FirmEffect or obj is SpriteEffect:
		if obj.done:
			for c in model.get_children():
				if c is CPUParticles3D:
					c.emitting = false
	elif obj is Tornado:
		model.get_child(0).rotate_y(0.25)


# --------------------------------------------------------------------- units ---

func _make_unit(u: Unit) -> Node3D:
	var spec := UnitModels.spec(u.sprite_code)
	if spec.is_empty() or (spec["model"] != "" and _scene(spec["model"]) == null):
		return null
	var root := Node3D.new()
	root.name = "Unit_%s" % u.sprite_code
	var pivot := Node3D.new()
	pivot.name = "Pivot"
	pivot.position = Vector3(0.5, spec.get("fly", 0.0), 0.5)   # View3D anchors units at the tile corner
	root.add_child(pivot)
	var st := {"spec": spec, "pivot": pivot, "parts": [], "color": _color(u), "tint": Color.WHITE,
		"action": "", "frame": -1, "weapons": {}}
	var holder: Node3D = pivot
	# carts: a static body with wheels, pulled by animated beasts; the crew stands in it
	if spec.has("cart"):
		var cart := _add_part(st, spec["cart"], pivot, "", "cart")
		if cart.is_empty():
			return null
		st["wheels"] = []
		for n in cart["inst"].find_children("Wheel*", "", true, false):
			st["wheels"].append(n)
		# moving parts of siege weapons (props.py): Arm swings, Barrel recoils, Saw spins
		for key in ["Arm", "Barrel", "Saw"]:
			var n := cart["inst"].find_child(key, true, false) as Node3D
			if n:
				st[key] = n
				st[key + "_rest"] = n.transform
		for p in spec.get("pullers", []):
			var beast := _add_part(st, p[0], pivot, "", "mount")
			if not beast.is_empty():
				beast["inst"].position = p[1]
		holder = Node3D.new()
		holder.position = spec.get("seat", Vector3(0, 0.35, 0))
		pivot.add_child(holder)
	if spec.has("mount") and not spec.has("cart"):
		var mount := _add_part(st, spec["mount"], pivot, "", "mount")
		if mount.is_empty():
			return null
		holder = _seat(mount["inst"], spec["mount"])
	if spec["model"] == "":
		root.set_meta("st", st)
		return root
	var own: bool = spec.get("own_anims", false)
	var body := _add_part(st, spec["model"], holder, "" if own else spec.get("anims", "humanoid"), "beast" if own else "body")
	if body.is_empty():
		return null
	for m in body["meshes"]:
		if m.name.begins_with("W_"):
			st["weapons"][m.name] = m
	root.set_meta("st", st)
	_show_weapons(st, "S")
	return root


## Instantiates one model of a unit (the body, or the mount it rides).
func _add_part(st: Dictionary, rel: String, parent: Node3D, lib: String, role: String) -> Dictionary:
	var scene := _scene(rel)
	if scene == null:
		return {}
	var inst := scene.instantiate()
	if role == "mount":
		inst.scale = Vector3.ONE * float(_mount_info(rel).get("scale", 1.0))
	elif role == "beast":
		inst.scale = Vector3.ONE * float(_creature_info(rel).get("scale", 1.0))
	parent.add_child(inst)
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(inst, meshes)
	var part := {"inst": inst, "meshes": meshes, "role": role, "own_mat": false}
	part["mat"] = _team_material(meshes, st["color"])
	for m in meshes:
		m.material_override = part["mat"]
	if lib != "":
		part["ap"] = _anim_player(inst, lib)
	else:
		var ap := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap:
			for n in ap.get_animation_list():
				if UnitModels.LOOPING.has(n):
					ap.get_animation(n).loop_mode = Animation.LOOP_LINEAR
		part["ap"] = ap
	st["parts"].append(part)
	return part


## A node that follows the mount's saddle. tools/blender/mounts.py writes each
## mount's seat point to mounts/mounts.json, in skeleton space.
static var _saddles := {}

## Seat point, seat bone and scale of a mount (written by mounts.py).
static func _mount_info(rel: String) -> Dictionary:
	if _saddles.is_empty():
		var f := FileAccess.open(MODEL_DIR + "mounts/mounts.json", FileAccess.READ)
		if f:
			_saddles = JSON.parse_string(f.get_as_text())
	return _saddles.get(rel.get_file().get_basename(), {})


static var _creatures := {}

## Scale of a creature model with its own clips (written by fryhtans.py).
static func _creature_info(rel: String) -> Dictionary:
	if _creatures.is_empty():
		var f := FileAccess.open(MODEL_DIR + "fryhtans/creatures.json", FileAccess.READ)
		if f:
			_creatures = JSON.parse_string(f.get_as_text())
	return _creatures.get(rel.get_file().get_basename(), {})


static func _seat(mount: Node3D, rel: String) -> Node3D:
	var info := _mount_info(rel)
	var skel := mount.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null or not info.has("point"):
		return mount as Node3D
	var bone := skel.find_bone(info.get("bone", "Body"))
	var att := BoneAttachment3D.new()
	att.bone_idx = bone
	skel.add_child(att)
	var pt: Array = info["point"]
	var rest := skel.get_bone_global_rest(bone)
	var seat := Node3D.new()
	seat.name = "Seat"
	# upright at rest, and undo the mount's import scale so the rider keeps its size
	var k := 1.0 / (mount.scale.x * (skel.get_parent() as Node3D).scale.x)
	seat.transform = Transform3D(rest.basis.inverse().orthonormalized().scaled(Vector3(k, k, k)),
		rest.affine_inverse() * Vector3(pt[0], pt[1], pt[2]))
	att.add_child(seat)
	return seat


func _sync_unit(u: Unit, model: Node3D) -> void:
	var st: Dictionary = model.get_meta("st")
	model.visible = model.visible and u.inside_firm == null
	var pivot: Node3D = st["pivot"]
	var g := Game.inst
	var spd := g.speed if g else 1.0
	pivot.rotation.y = lerp_angle(pivot.rotation.y, dir_yaw(u.dir), 0.35)
	var col := _color(u)
	if col != st["color"]:          # defection, surrender
		st["color"] = col
		for part in st["parts"]:
			part["own_mat"] = false
			part["mat"] = _team_material(part["meshes"], col)
			for m in part["meshes"]:
				m.material_override = part["mat"]
		st["tint"] = Color.WHITE
	_apply_tint(st, u, g)
	var act := u.action
	if u.dead:
		act = "D"
	var spec: Dictionary = st["spec"]
	var restart: bool = act != st["action"] or (act.begins_with("A") and u.anim_frame < st["frame"])
	st["frame"] = u.anim_frame
	if restart:
		st["action"] = act
		_show_weapons(st, act)
	var n_attack := maxi(1, Assets.action_len(u.sprite_code, act, u.dir)) if act.begins_with("A") else 1
	var ground := (u.speed_loc() if g else 0.12) * Defs.SIM_FPS * spd       # locations per second
	for part in st["parts"]:
		var ap: AnimationPlayer = part["ap"]
		if ap == null:
			continue
		var is_mount: bool = part["role"] == "mount" or part["role"] == "beast"
		var clip := UnitModels.mount_clip_for(spec, act) if is_mount else UnitModels.clip_for(spec, act, u.obj_id)
		if not ap.has_animation(clip):
			continue
		if restart or ap.assigned_animation != clip:
			ap.play(clip, 0.05 if act.begins_with("A") else 0.12)
			if restart:
				ap.seek(0.0, true)
		var length := ap.get_animation(clip).length
		if act.begins_with("A"):
			# the whole clip spans the sprite action; the hit lands on its last frame
			ap.speed_scale = length / (float(n_attack) / (Defs.SIM_FPS * spd))
		elif act == "M":
			var stride: float = spec.get("mount_stride" if is_mount else "stride", 1.1)
			ap.speed_scale = ground * length / stride
		elif act == "D":
			ap.speed_scale = spd * 1.4
		else:
			ap.speed_scale = spd
	_animate_rigid(st, act, u)
	if spec.get("fly", 0.0) > 0.0 and act != "D":
		# hover: a slow bob, out of step between units
		pivot.position.y = spec["fly"] + 0.08 * sin(Time.get_ticks_msec() * 0.002 + u.obj_id)
	if act == "M" and st.has("wheels"):
		for w in st["wheels"]:
			w.rotate_object_local(Vector3.RIGHT, ground / 0.3 * model.get_process_delta_time())
	if act == "D":
		# sink into the ground at the end instead of fading out
		var n := Assets.action_len(u.sprite_code, "D", 0)
		var t := float(u.death_frames - maxi(n * 2, 1) - 20) / 40.0
		pivot.position.y = spec.get("fly", 0.0) * (1.0 - clampf(float(u.death_frames) / 12.0, 0.0, 1.0)) - clampf(t, 0.0, 1.0) * 0.6


## Code-driven motion of rigid siege parts over an attack (p: 0..1 to the hit).
func _animate_rigid(st: Dictionary, act: String, u: Unit) -> void:
	var p := 0.0
	if act.begins_with("A"):
		p = float(u.anim_frame) / float(maxi(1, Assets.action_len(u.sprite_code, act, u.dir)))
	if st.has("Arm"):
		var arm: Node3D = st["Arm"]
		var swing := -1.9 * smoothstep(0.55, 0.95, p) if p > 0.0 else 0.0
		arm.transform = st["Arm_rest"] * Transform3D(Basis(Vector3.RIGHT, swing), Vector3.ZERO)
	if st.has("Barrel"):
		var b: Node3D = st["Barrel"]
		var recoil := 0.18 * (1.0 - smoothstep(0.85, 1.0, p)) * (1.0 if p >= 0.8 else 0.0)
		b.transform = st["Barrel_rest"] * Transform3D(Basis(), Vector3(0, 0, -recoil))
	if st.has("Saw") and act.begins_with("A"):
		(st["Saw"] as Node3D).rotate_object_local(Vector3.RIGHT, 0.6)
	if act == "D" and st.has("wheels"):
		# wrecked: tip over
		var pivot: Node3D = st["pivot"]
		pivot.rotation.z = lerp(pivot.rotation.z, 0.5, 0.05)


# ------------------------------------------------------------------- bullets ---

## Projectile model of each bullet sprite (projectiles/*.glb from props.py).
const BULLETS := {
	"CATSTONE": "stone", "F_CATSON": "stone", "RK_ARROW": "stone", "RK_ARRO2": "stone",
	"CATFIRE": "fireball", "FL_ARROW": "fireball", "CANBALL": "cannonball", "M_CANBL1": "cannonball",
	"M_CANBL2": "cannonball", "F_CANBAL": "spit", "SK_ARROW": "spit", "TC_ARR00": "bolt", "TC_ARR02": "bolt",
	"FB_ARROW": "bolt", "M_DARROW": "bolt", "F_TC_ARR": "bolt", "VI_ARROW": "axe", "JA_ARROW": "shuriken",
	"CE_ARROW": "spark", "LIGHTING": "spark", "GC_ARROW": "spark",
}


static func bullet_model(code: String) -> String:
	if BULLETS.has(code):
		return BULLETS[code]
	if code.ends_with("JAVEL") or code.ends_with("JAVE2"):
		return "javelin"
	return "arrow"


func _make_bullet(b: Bullet) -> Node3D:
	var scene := _scene("projectiles/%s.glb" % bullet_model(b.sprite_code))
	if scene == null:
		return null
	var root := Node3D.new()
	var inst: Node3D = scene.instantiate()
	root.add_child(inst)
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(inst, meshes)
	var mat := _team_material(meshes, Color.WHITE)
	for m in meshes:
		m.material_override = mat
	var heavy := ["stone", "cannonball", "fireball", "spit"].has(bullet_model(b.sprite_code))
	root.set_meta("st", {"inst": inst, "start": Iso.to_loc(b.position), "spin": bullet_model(b.sprite_code) in ["axe", "shuriken"],
		"arc": 0.35 if heavy else 0.15})
	return root


func _sync_bullet(b: Bullet, model: Node3D) -> void:
	var st: Dictionary = model.get_meta("st")
	var inst: Node3D = st["inst"]
	var start: Vector2 = st["start"]
	var here := Iso.to_loc(b.position)
	var dest := Iso.to_loc(b.dest)
	var total := maxf(0.01, start.distance_to(dest))
	var p := clampf(1.0 - here.distance_to(dest) / total, 0.0, 1.0)
	var arc: float = st["arc"] * total
	inst.position = Vector3(0.5, 0.75 + arc * sin(PI * p), 0.5)
	var flat := dest - start
	var climb := arc * PI * cos(PI * p) / total        # d(height)/d(ground)
	var fwd := Vector3(flat.x, climb * flat.length(), flat.y).normalized()
	if fwd.length() > 0.01:
		inst.basis = Basis.looking_at(-fwd, Vector3.UP)
	if st["spin"]:
		inst.rotate_object_local(Vector3.RIGHT, p * 25.0)


# --------------------------------------------------------- firms and towns ---

## Architectural style of each race's buildings (tools/blender/buildings.py).
const RACE_STYLE := {"NORMAN": "NE", "VIKING": "NE", "CELTIC": "NE", "ROMAN": "ME", "GREEK": "ME",
	"CARTH": "ME", "CHINESE": "EA", "JAPANESE": "EA", "MONGOL": "EA", "EGYPTIAN": "MA", "PERSIAN": "MA",
	"INDIAN": "MA"}
const STYLED_FIRMS := ["FORT", "CAMP", "MINE", "FACTORY", "MARKET", "INN", "RESEARCH", "WAR", "SPY"]


static func firm_model(f: Firm) -> String:
	if f.code in STYLED_FIRMS:
		return "buildings/%s_%s.glb" % [f.code, RACE_STYLE.get(f.race, "NE")]
	if f.code == "STABLE" or f.code == "BASE":
		return "buildings/%s_%s.glb" % [f.code, f.race if RACE_STYLE.has(f.race) else "NORMAN"]
	return "buildings/%s.glb" % f.code


## A static building model in the owner's colour; returns {inst, meshes, mat}.
func _building(rel: String, col: Color) -> Dictionary:
	var scene := _scene(rel)
	if scene == null:
		return {}
	var inst: Node3D = scene.instantiate()
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(inst, meshes)
	var mat := _team_material(meshes, col)
	for m in meshes:
		m.material_override = mat
	return {"inst": inst, "meshes": meshes, "mat": mat}


func _make_firm(f: Firm) -> Node3D:
	var b := _building(firm_model(f), _color(f))
	if b.is_empty():
		return null
	var root := Node3D.new()
	root.name = "Firm_%s" % f.code
	var holder := Node3D.new()
	root.add_child(holder)
	holder.add_child(b["inst"])
	# models are designed for a footprint (buildings/footprints.json); fit loc_w x loc_h
	var fp: Array = _footprint(firm_model(f))
	holder.scale = Vector3(f.w / float(fp[0]), 1.0, f.h / float(fp[1]))
	holder.scale.y = (holder.scale.x + holder.scale.z) * 0.5
	b["holder"] = holder
	b["color"] = _color(f)
	b["wheels"] = b["inst"].find_children("Wheel*", "", true, false)
	b["shown_hp"] = -1.0
	root.set_meta("st", b)
	return root


func _sync_firm(f: Firm, model: Node3D) -> void:
	var st: Dictionary = model.get_meta("st")
	var holder: Node3D = st["holder"]
	var col := _color(f)
	if col != st["color"]:
		st["color"] = col
		st["mat"] = _team_material(st["meshes"], col)
		for m in st["meshes"]:
			m.material_override = st["mat"]
	# under construction: the building rises from the ground (Firm::draw_full_size
	# darkens it instead; here the height tells the progress)
	var k := 1.0
	if f.under_construction:
		k = lerpf(0.12, 1.0, clampf(f.progress / 100.0, 0.0, 1.0))
	var sy: float = (holder.scale.x + holder.scale.z) * 0.5 * k
	if absf(holder.scale.y - sy) > 0.001:
		holder.scale.y = sy
	if not f.under_construction and f.overseer != null or f.code in ["MINE", "FACTORY"]:
		var dt := model.get_process_delta_time() * (Game.inst.speed if Game.inst else 1.0)
		for w in st["wheels"]:
			(w as Node3D).rotate_object_local(Vector3.RIGHT, dt * 0.8)


func _make_town(t: Town) -> Node3D:
	var root := Node3D.new()
	root.name = "Town_%s" % t.town_name
	var st := {"layout": "", "pop": -1, "color": _color(t), "houses": [], "race": t.race}
	root.set_meta("st", st)
	_build_town(t, root, st)
	_sync_town_wall(t, root, st)
	return root


func _build_town(t: Town, root: Node3D, st: Dictionary) -> void:
	for n in st["houses"]:
		n.queue_free()
	st["houses"] = []
	st["layout"] = str(t.layout.get("code", ""))
	st["race"] = t.race
	var style: String = RACE_STYLE.get(t.race, "NE")
	var center := t.center_loc()
	var i := 0
	for s in t.layout.get("slots", []):
		var at := Vector2(t.x1 + s["x"] / 32.0, t.y1 + s["y"] / 32.0) - center
		var items: Array = []           # [model, offset from the slot, yaw]
		match s["type"]:
			"HOUSE":
				# a house slot is one multi-house picture in the original; fill its
				# footprint (TOWNBULD loc size) with a small cluster of houses
				var hb := Assets.town_house(t.race, int(s["code"]))
				var size: Vector2 = hb[2] if hb.size() > 2 else Vector2(2, 2)
				var nx := maxi(1, int(round(size.x / 1.5)))
				var ny := maxi(1, int(round(size.y / 1.5)))
				for gx in nx:
					for gy in ny:
						var hv := hash(Vector3i(t.obj_id, i, gx * 7 + gy))
						var off := Vector2((gx + 0.5) / nx - 0.5, (gy + 0.5) / ny - 0.5) * size
						var big := 3 if nx * ny == 1 and size.x >= 2 else 1 + hv % 2
						items.append(["houses/house_%s_%d%s.glb" % [style, big, "ab"[hv % 2]], off, PI * 0.5 * (hv % 2)])
			"FLAG":
				items.append(["houses/flag.glb", Vector2.ZERO, 0.0])
			"PLANT":
				items.append(["nature/bush_%d.glb" % ((t.obj_id + int(s["x"])) % 3), Vector2.ZERO, 0.0])
		i += 1
		for it in items:
			var b := _building(it[0], st["color"])
			if b.is_empty():
				continue
			var n: Node3D = b["inst"]
			var pos: Vector2 = at + it[1]
			n.position = Vector3(pos.x, 0.0, pos.y)
			n.rotation.y = it[2]
			root.add_child(n)
			st["houses"].append(n)


func _sync_town(t: Town, model: Node3D) -> void:
	var st: Dictionary = model.get_meta("st")
	var col := _color(t)
	if str(t.layout.get("code", "")) != st["layout"] or t.race != st["race"] or col != st["color"]:
		st["color"] = col
		_build_town(t, model, st)
		st["wall"] = -1
	_sync_town_wall(t, model, st)


## The town's fence or wall (Town.wall_level 0..2) and, while a better wall is
## being built, the new one rising inside it.
func _sync_town_wall(t: Town, model: Node3D, st: Dictionary) -> void:
	var style: String = RACE_STYLE.get(t.race, "NE")
	var building := t.target_wall_level > t.wall_level
	if st.get("wall", -1) != t.wall_level or st.get("wall_building", false) != building:
		for k in ["wall_node", "wall_next"]:
			if st.has(k) and is_instance_valid(st[k]):
				st[k].queue_free()
			st.erase(k)
		st["wall"] = t.wall_level
		st["wall_building"] = building
		var b := _building("houses/wall_%s_%d.glb" % [style, t.wall_level], st["color"])
		if not b.is_empty():
			model.add_child(b["inst"])
			st["wall_node"] = b["inst"]
		if building:
			var nb := _building("houses/wall_%s_%d.glb" % [style, t.target_wall_level], st["color"])
			if not nb.is_empty():
				model.add_child(nb["inst"])
				st["wall_next"] = nb["inst"]
	if st.has("wall_next"):
		var f := clampf(t.wall_progress / float(Town.MAX_WALL_PROGRESS), 0.02, 1.0)
		(st["wall_next"] as Node3D).scale = Vector3(0.97, f, 0.97)


# ------------------------------------------------------------ trees, rocks ---

## A raw-material deposit (View3D places it at the footprint centre). The pile model
## is about 2 x 2; it is spread over the site's footprint.
func make_site(site: Site) -> Node3D:
	var kind := site.raw.to_lower()
	if not kind in ["clay", "copper", "iron"]:
		return null
	var b := _building("nature/deposit_%s.glb" % kind, Color.WHITE)
	if b.is_empty():
		return null
	var root := Node3D.new()
	var inst: Node3D = b["inst"]
	root.add_child(inst)
	inst.scale = Vector3(site.w * 0.4, 1.0, site.h * 0.4)
	inst.rotation.y = float(hash(Vector2i(site.x1, site.y1)) % 4) * PI * 0.5
	return root

## A tree of the original's species (TREE-A .. TREE-T) at its growth stage.
func _make_plant(p: Plant) -> Node3D:
	var info: Dictionary = Assets.plant_bitmaps[p.variant % Assets.plant_bitmaps.size()] if not Assets.plant_bitmaps.is_empty() else {}
	var species: String = str(info.get("plant", "TREE-G"))
	var b := _building("nature/tree_%s.glb" % species.right(1), Color.WHITE)
	if b.is_empty():
		return null
	var root := Node3D.new()
	var inst: Node3D = b["inst"]
	root.add_child(inst)
	var cell: Vector2i = p.get_meta("cell", Vector2i.ZERO)
	var h := hash(cell)
	inst.position = Vector3(0.5, 0.0, 0.5)              # View3D anchors plants at the tile corner
	inst.rotation.y = float(h % 628) / 100.0
	var k: float = [0.6, 0.8, 1.0][p.variant % 3] * (0.9 + float(h % 21) / 100.0)
	inst.scale = Vector3(k, k, k)
	return root


## Mountains and boulders, stretched over the rock's footprint.
func _make_rock(r: Rock) -> Node3D:
	var big := r.w * r.h >= 4
	var h := hash(Vector2i(r.x1, r.y1))
	var rel := "nature/mountain_%d.glb" % (h % 3) if big else "nature/rock_%d.glb" % (h % 4)
	var b := _building(rel, Color.WHITE)
	if b.is_empty():
		return null
	var root := Node3D.new()
	var inst: Node3D = b["inst"]
	root.add_child(inst)
	var size := float(mini(r.w, r.h))
	inst.scale = Vector3(r.w * 1.1, size * (1.6 if big else 0.9), r.h * 1.1)
	inst.rotation.y = float(h % 4) * PI * 0.5
	return root


# ------------------------------------------------------------------ effects ---
# Particle effects in place of the original's effect sprites (FIRM_DIE.FRM
# explosions and fires, spell flashes, the tornado).

static var _fx_mats := {}

static func _fx_material(col: Color, additive: bool) -> StandardMaterial3D:
	var key := "%s|%s" % [col.to_html(), additive]
	if _fx_mats.has(key):
		return _fx_mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	# the per-particle ramp colour comes through dark in the Compatibility renderer
	# for blended particles, so smoke takes its colour from the material alone
	m.vertex_color_use_as_albedo = additive
	m.albedo_color = col
	m.albedo_texture = _soft_dot()
	_fx_mats[key] = m
	return m


static var _dot: GradientTexture2D

## A round, soft-edged particle sprite (white, alpha falling off from the centre).
static func _soft_dot() -> GradientTexture2D:
	if _dot == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.6), Color(1, 1, 1, 0)])
		_dot = GradientTexture2D.new()
		_dot.gradient = g
		_dot.fill = GradientTexture2D.FILL_RADIAL
		_dot.fill_from = Vector2(0.5, 0.5)
		_dot.fill_to = Vector2(1.0, 0.5)
		_dot.width = 64
		_dot.height = 64
	return _dot


static func _particles(amount: int, life: float, size: float, col: Color, ramp: Array, additive := true,
		velocity := Vector2(0.5, 1.5), spread := 25.0, gravity := 0.5, one_shot := false, box := Vector3(0.3, 0.1, 0.3)) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.one_shot = one_shot
	p.explosiveness = 0.9 if one_shot else 0.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = box
	p.direction = Vector3.UP
	p.spread = spread
	p.initial_velocity_min = velocity.x
	p.initial_velocity_max = velocity.y
	p.gravity = Vector3(0, gravity, 0)
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.material = _fx_material(col, additive)
	p.mesh = q
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray(ramp)
	p.color_ramp = g
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1, 0.2))
	p.scale_amount_curve = curve
	return p


const FIRE := [Color(1.0, 0.9, 0.4, 0.9), Color(1.0, 0.45, 0.1, 0.8), Color(0.3, 0.1, 0.05, 0.0)]
const SMOKE := [Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.55), Color(1, 1, 1, 0.0)]
const SMOKE_COLOR := Color(0.42, 0.4, 0.37, 0.35)    # material colour; the ramp only fades


func _make_firm_effect(e: FirmEffect) -> Node3D:
	var root := Node3D.new()
	var kind := 1
	if e.recs == Assets.die_part(2):
		kind = 2
	elif e.recs == Assets.die_part(3):
		kind = 3
	if kind == 1:
		# explosion at the building's corner: a fireball, smoke and debris
		var at := Vector3(2.5, 0.4, 2.5)
		var boom := _particles(60, 0.9, 0.9, Color.WHITE, FIRE, true, Vector2(2.0, 5.0), 70.0, -2.0, true, Vector3(1.2, 0.3, 1.2))
		var smoke := _particles(40, 2.2, 1.4, SMOKE_COLOR, SMOKE, false, Vector2(0.5, 1.5), 50.0, 0.4, true, Vector3(1.4, 0.4, 1.4))
		var debris := _particles(30, 1.2, 0.18, Color(0.35, 0.28, 0.2), [Color(0.4, 0.3, 0.2, 1), Color(0.3, 0.25, 0.2, 1), Color(0.2, 0.2, 0.2, 0)], false, Vector2(3.0, 6.0), 60.0, -9.8, true, Vector3(1.0, 0.3, 1.0))
		for p in [boom, smoke, debris]:
			p.position = at
			root.add_child(p)
			p.emitting = true
	else:
		var big := kind == 3
		var fire := _particles(24 if big else 12, 0.8, 0.5 if big else 0.32, Color.WHITE, FIRE, true, Vector2(0.6, 1.4), 15.0, 0.8)
		var smoke := _particles(16 if big else 8, 2.5, 0.8 if big else 0.5, SMOKE_COLOR, SMOKE, false, Vector2(0.5, 1.0), 12.0, 0.3)
		smoke.position.y = 0.6
		for p in [fire, smoke]:
			p.position += Vector3(0.5, 0.3, 0.5)
			root.add_child(p)
			p.emitting = true
	return root


func _make_spell_effect(e: SpriteEffect) -> Node3D:
	var root := Node3D.new()
	var col := e.color.lightened(0.4)
	var ramp := [Color(1, 1, 1, 0.9), Color(col.r, col.g, col.b, 0.7), Color(col.r, col.g, col.b, 0.0)]
	var burst := _particles(50, 1.2, 0.35, Color.WHITE, ramp, true, Vector2(1.0, 3.0), 180.0, 0.5, true, Vector3(0.6, 0.6, 0.6))
	burst.position = Vector3(0.5, 0.8, 0.5)
	root.add_child(burst)
	burst.emitting = true
	return root


func _make_tornado(t: Tornado) -> Node3D:
	var root := Node3D.new()
	var spin := Node3D.new()
	root.add_child(spin)
	var funnel := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.4
	cyl.bottom_radius = 0.25
	cyl.height = 4.0
	cyl.radial_segments = 10
	funnel.mesh = cyl
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.75, 0.72, 0.65, 0.35)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	funnel.material_override = m
	funnel.position.y = 2.0
	spin.add_child(funnel)
	var dust := _particles(60, 1.6, 0.6, SMOKE_COLOR, SMOKE, false, Vector2(1.5, 3.0), 30.0, 1.0, false, Vector3(0.6, 0.2, 0.6))
	spin.add_child(dust)
	dust.emitting = true
	spin.position = Vector3(0.5, 0, 0.5)
	return root


static var _footprints := {}

static func _footprint(rel: String) -> Array:
	if _footprints.is_empty():
		var f := FileAccess.open(MODEL_DIR + "buildings/footprints.json", FileAccess.READ)
		if f:
			_footprints = JSON.parse_string(f.get_as_text())
	return _footprints.get(rel.get_file().get_basename(), [6, 6])


static func _aabb(n: Node) -> AABB:
	var box := AABB()
	var first := true
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(n, meshes)
	for m in meshes:
		var a: AABB = m.get_aabb()
		var tr: Transform3D = m.transform
		var p: Node = m.get_parent()
		while p != null and p != n.get_parent() and p is Node3D:
			tr = (p as Node3D).transform * tr
			p = p.get_parent()
		a = tr * a
		box = a if first else box.merge(a)
		first = false
	return box


static func _color(o: Object) -> Color:
	return o.get_meta("preview_color") if o.has_meta("preview_color") else o.nation_color()


func _apply_tint(st: Dictionary, u: Unit, g: Game) -> void:
	var tint := Color.WHITE
	if g and u.frozen_until > g.frame:
		tint = Color(0.6, 0.8, 1.3)
	elif g and u.invulnerable_until > g.frame:
		tint = Color(1.25, 1.2, 0.8)
	if st["tint"] == tint:
		return
	st["tint"] = tint
	for part in st["parts"]:
		# per-unit tint: give this unit its own copy of the shared material
		if not part["own_mat"]:
			part["mat"] = part["mat"].duplicate()
			part["own_mat"] = true
			for m in part["meshes"]:
				m.material_override = part["mat"]
		part["mat"].set_shader_parameter("tint", tint)


func _show_weapons(st: Dictionary, act: String) -> void:
	var weapons: Dictionary = st["weapons"]
	if weapons.is_empty():
		return
	var shown: Array = UnitModels.weapons_for(st["spec"], act)
	for n in weapons:
		weapons[n].visible = shown.has(n)


## Yaw of a model (facing +z) for the original's 8 directions. Direction 0 is
## screen-north at camera yaw 0, i.e. location direction (-1, -1); east is (1, -1).
static func dir_yaw(d: int) -> float:
	var a := d * PI / 4.0
	var v := Vector2(-1, -1).normalized() * cos(a) + Vector2(1, -1).normalized() * sin(a)
	return atan2(v.x, v.y)


# ------------------------------------------------------------------- helpers ---

static func _scene(rel: String) -> PackedScene:
	var path := MODEL_DIR + rel
	if not _scenes.has(path):
		if not ResourceLoader.exists(path):
			_scenes[path] = null
		elif ResourceLoader.load_threaded_get_status(path) != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_scenes[path] = ResourceLoader.load_threaded_get(path)      # waits if still loading
		else:
			_scenes[path] = load(path)
	return _scenes[path]


static func _collect_meshes(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect_meshes(c, out)


static func _team_material(meshes: Array[MeshInstance3D], col: Color) -> ShaderMaterial:
	var tex: Texture2D = null
	for m in meshes:
		var src := m.get_active_material(0)
		if src is BaseMaterial3D and src.albedo_texture:
			tex = src.albedo_texture
			break
	var key := "%s|%s" % [tex.resource_path if tex else "", col.to_html()]
	if _materials.has(key):
		return _materials[key]
	if _shader == null:
		_shader = Shader.new()
		_shader.code = TEAM_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("palette", tex)
	mat.set_shader_parameter("team_color", col)
	_materials[key] = mat
	return mat


## Finds or adds the AnimationPlayer of a model and gives it the shared library.
static func _anim_player(inst: Node, lib_name: String) -> AnimationPlayer:
	var lib := anim_library(lib_name)
	if lib == null:
		return null
	var ap := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap == null:
		ap = AnimationPlayer.new()
		ap.name = "AnimationPlayer"
		inst.add_child(ap)
	ap.root_node = ap.get_path_to(inst)
	if not ap.has_animation_library(""):
		ap.add_animation_library("", lib)
	return ap


static func anim_library(lib_name: String) -> AnimationLibrary:
	if _anim_libs.has(lib_name):
		return _anim_libs[lib_name]
	var scene := _scene("anims/%s.glb" % lib_name)
	var lib: AnimationLibrary = null
	if scene:
		var tmp := scene.instantiate()
		var ap := tmp.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if ap:
			lib = AnimationLibrary.new()
			for n in ap.get_animation_list():
				var a: Animation = ap.get_animation(n).duplicate()
				if UnitModels.LOOPING.has(n):
					a.loop_mode = Animation.LOOP_LINEAR
				lib.add_animation(n, a)
		tmp.free()
	_anim_libs[lib_name] = lib
	return lib
