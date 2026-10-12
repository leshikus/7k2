class_name View3D
extends Node3D
## 3D presentation of the running game. The simulation's objects are still 2D nodes
## (kept hidden) whose render(cv) is replayed here. While the original's bitmaps
## stand in for models, every bitmap becomes a camera-facing card (Sprite3D)
## standing on its object's ground position, ground art (foundations, deposits,
## lakes, rubble) becomes flat decals, and lines, bars and labels go to a screen
## overlay. Cards ignore the depth buffer and are sorted by their ground anchor,
## which reproduces the original's draw order at its own view angle.

const PX := 1.0 / CameraRig.PX_PER_UNIT

const TERRAIN_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D tex_g : filter_linear, repeat_enable;
uniform sampler2D tex_f : filter_linear, repeat_enable;
uniform sampler2D tex_d : filter_linear, repeat_enable;
uniform sampler2D weights : filter_linear;
uniform sampler2D noise : filter_linear, repeat_enable;
uniform vec2 map_size;
varying vec2 loc;

void vertex() {
	loc = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	// the 2D terrain shader (TerrainView), evaluated on the ground plane
	vec2 tuv = loc * 32.0 / 512.0;
	vec3 w = texture(weights, (loc + 0.5) / (map_size + 1.0)).rgb;
	float n = texture(noise, loc / 23.0).r - 0.5;
	w += vec3(n, -n, n * 1.4) * 0.6;
	w = max(w, vec3(0.0));
	w = pow(w, vec3(4.0));
	w /= max(w.r + w.g + w.b, 0.0001);
	vec3 c = texture(tex_g, tuv).rgb * w.r + texture(tex_f, tuv).rgb * w.g + texture(tex_d, tuv).rgb * w.b;
	float dx = texture(weights, (loc + vec2(1.0, 0.5)) / (map_size + 1.0)).b - texture(weights, (loc + vec2(0.0, 0.5)) / (map_size + 1.0)).b;
	float dy = texture(weights, (loc + vec2(0.5, 1.0)) / (map_size + 1.0)).b - texture(weights, (loc + vec2(0.5, 0.0)) / (map_size + 1.0)).b;
	c *= 1.0 - (dx + dy) * 0.18;
	ALBEDO = clamp(c, 0.0, 1.0);    // matches the 2D colours as is (checked against screenshots)
}
"""

const FOG_SHADER := """
shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, blend_mix;
uniform sampler2D fog : filter_linear;
uniform vec2 map_size;
uniform vec2 loc_origin;
uniform vec2 loc_dx;
uniform vec2 loc_dy;

void vertex() {
	POSITION = vec4(VERTEX.xy, 0.5, 1.0);
}

void fragment() {
	// the ground under an orthographic view is an affine function of the screen
	vec2 loc = loc_origin + SCREEN_UV.x * loc_dx + SCREEN_UV.y * loc_dy;
	float v = texture(fog, loc / map_size).r;
	ALBEDO = vec3(0.0);
	ALPHA = 1.0 - v;
}
"""

var game: Game
var rig: CameraRig
var _fog_quad: MeshInstance3D
var overlay: View3DOverlay
var extra_nodes: Array = []       # nodes outside the game's object layers (build ghost)
## Optional source of 3D models replacing the sprite cards. Duck-typed:
##   make(obj) -> Node3D or null   called once per object; null keeps the cards
##   sync(obj, model)              called every frame the object is on screen
## The model is placed at the object's ground anchor before sync(); lines, bars
## and labels still come from the object's render() via the overlay.
##   make_site(site) -> Node3D or null   optional: a raw-material deposit, placed at the
##                                       centre of its footprint; replaces its ground art
var model_provider: Object = null
var _models := {}                 # Node2D -> Node3D (or null: provider has none)
var _site_models := {}            # Site -> Node3D (or null)

var _terrain: MeshInstance3D
var _rec := DrawRecorder.new()
var _cards := {}                  # Node2D -> Array[Sprite3D]
var _static := {}                 # Node2D -> true once its cards are built (plants, rocks)
var _decals: Array = []           # MeshInstance3D
var _decal_sig := ""
var _frame := 0


func setup(g: Game, r: CameraRig, ov: View3DOverlay) -> void:
	game = g
	rig = r
	overlay = ov
	_build_terrain()


func _build_terrain() -> void:
	var w := game.world.w
	var h := game.world.h
	var pm := PlaneMesh.new()
	pm.size = Vector2(w, h)
	_terrain = MeshInstance3D.new()
	_terrain.mesh = pm
	_terrain.position = Vector3(w * 0.5, 0.0, h * 0.5)
	var sh := Shader.new()
	sh.code = TERRAIN_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var src := game.terrain_view.material as ShaderMaterial
	for p in ["tex_g", "tex_f", "tex_d", "weights", "noise", "map_size"]:
		mat.set_shader_parameter(p, src.get_shader_parameter(p))
	_terrain.material_override = mat
	add_child(_terrain)
	_build_fog()


## Fog of war as a last full-screen pass: every pixel is darkened by the fog of the
## ground under it, as the 2D view's fog layer covered everything drawn below it.
func _build_fog() -> void:
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	var mi := MeshInstance3D.new()
	mi.mesh = q
	mi.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	var sh := Shader.new()
	sh.code = FOG_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.render_priority = Material.RENDER_PRIORITY_MAX
	mat.set_shader_parameter("fog", game.fog_view.texture)
	mat.set_shader_parameter("map_size", Vector2(game.world.w, game.world.h))
	mi.material_override = mat
	rig.cam.add_child(mi)
	_fog_quad = mi


var _vectors := {}       # node -> [anchor, overlay vectors] from its last refresh
var usec := 0            # time spent in the last update, for --bench
var models_shown := 0


func _process(_delta: float) -> void:
	if game == null or not is_instance_valid(game) or game.world == null:
		return
	var t0 := Time.get_ticks_usec()
	models_shown = 0
	_frame += 1
	rig.apply()
	Iso.dir_map = rig.direction_map()
	var vp := get_viewport().get_visible_rect()
	var l0 := rig.screen_to_loc(Vector2.ZERO)
	var fm := _fog_quad.material_override as ShaderMaterial
	fm.set_shader_parameter("loc_origin", l0)
	fm.set_shader_parameter("loc_dx", rig.screen_to_loc(Vector2(vp.size.x, 0)) - l0)
	fm.set_shader_parameter("loc_dy", rig.screen_to_loc(Vector2(0, vp.size.y)) - l0)
	var margin := 260.0 * rig.zoom.x
	var view := vp.grow(margin)
	var groups: Array = []
	var seen := {}
	for layer in [game.objects, game.effects]:
		for node in layer.get_children():
			_sync(node, view, groups, seen)
	for node in extra_nodes:
		if is_instance_valid(node):
			_sync(node, view, groups, seen)
	# forget nodes that are gone
	for node in _cards.keys():
		if not seen.has(node):
			for s in _cards[node]:
				s.queue_free()
			_cards.erase(node)
			_static.erase(node)
	for node in _models.keys():
		if not seen.has(node):
			if _models[node] != null:
				_models[node].queue_free()
			_models.erase(node)
			_vectors.erase(node)
	if _frame % 20 == 1:
		_sync_decals()
	overlay.groups = groups
	overlay.queue_redraw()
	usec = Time.get_ticks_usec() - t0


func _sync(node: Node, view: Rect2, groups: Array, seen: Dictionary) -> void:
	if not is_instance_valid(node) or not node.has_method("render"):
		return
	seen[node] = true
	# Most objects need no work most frames. Trees and rocks are built once and culled
	# by the engine: refresh their fog every 15 frames. Buildings keep their place:
	# refresh them every 8 frames and reuse their health bars and labels in between.
	# Off-screen units are looked at every fourth frame; the view margin hides the lag.
	var is_static := node is Plant or node is Rock
	var m = _models.get(node)
	if is_static:
		if _frame % 15 != 0 and (_static.has(node) or m != null):
			return
	elif m != null:
		var fixed := node is Firm or node is Town
		if (_frame + node.get_instance_id()) % (8 if fixed else 4) != 0:
			if fixed:
				if m.visible:
					_reuse_vectors(node, groups)
				return
			if not m.visible:
				return
	var n2 := node as Node2D
	var loc := Iso.to_loc(n2.position)
	var anchor := Vector3(loc.x, 0.0, loc.y)
	var fog := _fog_at(loc)
	var shown := n2.visible
	if model_provider != null and _use_model(node, anchor, shown, view, groups, fog):
		return
	if is_static:
		# built once; the engine culls them, only fog is refreshed now and then
		if not _static.has(node):
			_rec.clear()
			node.render(_rec)
			_apply_cards(node, anchor, _rec.textures)
			_static[node] = true
		if _frame % 15 == 0 or _frame < 3:
			_set_shown(node, shown)
		return
	var sp := rig.cam.unproject_position(anchor)
	if not shown or not view.has_point(sp):
		_hide(node)
		return
	_rec.clear()
	node.render(_rec)
	_apply_cards(node, anchor, _rec.textures)
	if not _rec.vectors.is_empty() and fog > 0:
		groups.append([sp, rig.zoom.x, _rec.vectors.duplicate()])


## Shows the provider's model instead of cards; false when there is no model.
func _use_model(node: Node, anchor: Vector3, shown: bool, view: Rect2, groups: Array, fog: int) -> bool:
	if not _models.has(node):
		var m = model_provider.make(node)
		_models[node] = m
		if m != null:
			add_child(m)
			_hide(node)
	var model: Node3D = _models[node]
	if model == null:
		return false
	model.position = anchor
	if node is Plant or node is Rock:
		# static: the engine culls it; only fog and visibility change
		model.visible = shown
		model.process_mode = Node.PROCESS_MODE_DISABLED
		model_provider.sync(node, model)
		return true
	var sp := rig.cam.unproject_position(anchor)
	var vis := shown and view.has_point(sp)
	if vis != model.visible or _frame < 3:
		model.visible = vis
		# hidden models stop animating: skeletons off screen cost as much as on it
		model.process_mode = Node.PROCESS_MODE_INHERIT if vis else Node.PROCESS_MODE_DISABLED
	if not vis:
		return true
	models_shown += 1
	model_provider.sync(node, model)
	_rec.clear()
	node.render(_rec)
	if not _rec.vectors.is_empty() and fog > 0:
		var vec := _rec.vectors.duplicate()
		groups.append([sp, rig.zoom.x, vec])
		_vectors[node] = [anchor, vec]
	else:
		_vectors.erase(node)
	return true


## Last frame's health bars and labels of a building, at the current view.
func _reuse_vectors(node: Node, groups: Array) -> void:
	var v = _vectors.get(node)
	if v != null:
		groups.append([rig.cam.unproject_position(v[0]), rig.zoom.x, v[1]])


func _apply_cards(node: Node, anchor: Vector3, textures: Array) -> void:
	var cards: Array = _cards.get(node, [])
	while cards.size() < textures.size():
		var s := Sprite3D.new()
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		s.shaded = false
		s.double_sided = true
		s.no_depth_test = true
		s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
		s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		s.pixel_size = PX
		s.centered = false
		s.sorting_use_aabb_center = false
		add_child(s)
		cards.append(s)
	for i in cards.size():
		var s: Sprite3D = cards[i]
		if i >= textures.size():
			s.visible = false
			s.remove_meta("used")
			continue
		var t: Array = textures[i]
		var tex: Texture2D = t[0]
		s.texture = tex
		s.position = anchor
		# 2D draws from the top-left, y down; a card's offset is its bottom-left, y up
		s.offset = Vector2(t[1].x, -t[1].y - tex.get_height())
		s.modulate = t[2]
		s.set_meta("used", true)
		s.sorting_offset = i * 0.001
		s.visible = true
	_cards[node] = cards


func _set_shown(node: Node, shown: bool) -> void:
	for s in _cards.get(node, []):
		s.visible = shown and s.has_meta("used")


func _hide(node: Node) -> void:
	for s in _cards.get(node, []):
		s.visible = false


func _fog_at(loc: Vector2) -> int:
	var c := Vector2i(clampi(floori(loc.x), 0, game.world.w - 1), clampi(floori(loc.y), 0, game.world.h - 1))
	return game.fog[c.y * game.world.w + c.x]


## Ground bitmaps as flat decals, rebuilt when they change.
func _sync_decals() -> void:
	_sync_sites()
	_rec.clear()
	game.ground_layer.render(_rec)
	var sig := ""
	for t in _rec.textures:
		sig += "%d:%d,%d;" % [t[0].get_rid().get_id(), int(t[1].x), int(t[1].y)]
	if sig == _decal_sig:
		return
	_decal_sig = sig
	for d in _decals:
		d.queue_free()
	_decals.clear()
	for t in _rec.textures:
		_decals.append(_decal(t[0], t[1]))


## Deposit models from the provider; a site with one is left out of the ground art.
func _sync_sites() -> void:
	if model_provider == null or not model_provider.has_method("make_site"):
		return
	var live := {}
	for s in game.sites:
		live[s] = true
		if not _site_models.has(s):
			var m = model_provider.make_site(s)
			_site_models[s] = m
			if m != null:
				var c: Vector2 = s.center_loc()
				m.position = Vector3(c.x, 0.0, c.y)
				add_child(m)
				s.set_meta("model3d", true)
		var model: Node3D = _site_models[s]
		if model != null:
			model.visible = s.mine == null and game.is_explored_rect(s.footprint())
	for s in _site_models.keys():
		if not live.has(s):
			if _site_models[s] != null:
				_site_models[s].queue_free()
			_site_models.erase(s)


func _decal(tex: Texture2D, pos: Vector2) -> MeshInstance3D:
	var sz := tex.get_size()
	var corners := [pos, pos + Vector2(sz.x, 0), pos + sz, pos + Vector2(0, sz.y)]
	var uvs := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in [0, 1, 2, 0, 2, 3]:
		var l := Iso.to_loc(corners[i])
		st.set_uv(uvs[i])
		st.add_vertex(Vector3(l.x, 0.01, l.y))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.albedo_texture = tex
	mat.render_priority = -1
	mi.material_override = mat
	add_child(mi)
	return mi
