class_name Minimap
extends Control
## Diamond-shaped overview map. Click or drag to move the camera.

signal jump_to(loc: Vector2)
signal order_to(loc: Vector2)

var game: Game
var camera: CameraRig
var _img: Image
var _tex: ImageTexture
var _timer := 0.0
var _base := PackedByteArray()
var _terrain := PackedByteArray()   # terrain shading only (Terrain map)

## Map modes (MapMatrix::map_mode): the Terrain map, the World Political map
## (with or without the kingdoms' zones of power), the Trade map; and the
## filters that show only the selected object's kingdom or kind.
enum Mode { TERRAIN, POWER, TRADE }
var mode := Mode.POWER
var power_mode := false
var filter_nation := -1        # show only this kingdom's objects (-1 off)
var filter_kind := ""          # "unit", "town" or a building code ("" off)
const MODE_COLOR := Color(0.33, 0.36, 0.25)

const TERRAIN_COLORS := [Color(0.25, 0.42, 0.16), Color(0.42, 0.55, 0.22), Color(0.52, 0.42, 0.28)]


func setup(g: Game, cam: CameraRig) -> void:
	game = g
	camera = cam
	var w := g.world.w
	var h := g.world.h
	_img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	_base.resize(w * h * 4)
	_terrain.resize(w * h * 4)
	for y in h:
		for x in w:
			var c: Color = TERRAIN_COLORS[g.world.corner(x, y)]
			# Terrain map: shaded where the land falls away (the shadowColor rule)
			var t := c.darkened(0.25) if x >= 2 and g.world.corner(x, y) < g.world.corner(x - 2, y) else c
			var j := (y * w + x) * 4
			_terrain[j] = int(t.r8)
			_terrain[j + 1] = int(t.g8)
			_terrain[j + 2] = int(t.b8)
			_terrain[j + 3] = 255
			if g.world.plant[y * w + x] == 1:
				c = c.darkened(0.35)
			elif g.world.occupant[y * w + x] is Rock:
				c = Color(0.25, 0.3, 0.45) if (g.world.occupant[y * w + x] as Rock).tex == null else Color(0.45, 0.38, 0.3)
			var i := (y * w + x) * 4
			_base[i] = int(c.r8)
			_base[i + 1] = int(c.g8)
			_base[i + 2] = int(c.b8)
			_base[i + 3] = 255
	_tex = ImageTexture.create_from_image(_img)
	_refresh()


func _process(delta: float) -> void:
	if game == null:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.4
		_refresh()
	queue_redraw()


func _refresh() -> void:
	var px := _base.duplicate()
	var w := game.world.w
	var filtered := filter_nation >= 0 or filter_kind != ""
	match mode:
		Mode.TERRAIN:
			if not filtered:
				for i in w * game.world.h:
					var occ = game.world.occupant[i]
					if game.world.plant[i] == 1 or occ is Rock:
						continue
					px[i * 4] = _terrain[i * 4]
					px[i * 4 + 1] = _terrain[i * 4 + 1]
					px[i * 4 + 2] = _terrain[i * 4 + 2]
				for c in game.fires:
					var k: int = (c.y * w + c.x) * 4
					px[k] = 255
					px[k + 1] = 120
					px[k + 2] = 20
		Mode.POWER:
			if power_mode and not filtered:
				var pm := game.power_map()
				for i in pm.size():
					if pm[i] > 0 and game.world.plant[i] == 0 and not (game.world.occupant[i] is Rock):
						var n := game.nation(pm[i])
						if n:
							var c := n.color.darkened(0.35)
							px[i * 4] = int(c.r8)
							px[i * 4 + 1] = int(c.g8)
							px[i * 4 + 2] = int(c.b8)
	if mode == Mode.TRADE or filtered:
		for i in w * game.world.h:
			px[i * 4] = int(MODE_COLOR.r8)
			px[i * 4 + 1] = int(MODE_COLOR.g8)
			px[i * 4 + 2] = int(MODE_COLOR.b8)
	var fog := game.fog
	if not game.reveal_all:
		for i in fog.size():
			var v := fog[i]
			if v == 0:
				px[i * 4] = 0
				px[i * 4 + 1] = 0
				px[i * 4 + 2] = 0
			elif v == 1:
				px[i * 4] = px[i * 4] / 2
				px[i * 4 + 1] = px[i * 4 + 1] / 2
				px[i * 4 + 2] = px[i * 4 + 2] / 2
	_img.set_data(game.world.w, game.world.h, false, Image.FORMAT_RGBA8, px)
	_tex.update(_img)


func _xf() -> Transform2D:
	# location (x, y) -> minimap pixel, as a diamond filling the control
	var s := minf(size.x, size.y * 2.0) / float(game.world.w + game.world.h)
	var origin := Vector2(size.x * 0.5, (size.y - (game.world.w + game.world.h) * s * 0.5) * 0.5)
	return Transform2D(Vector2(s, s * 0.5), Vector2(-s, s * 0.5), origin)


var _phase := 0


## What the mode and filters let through (FirmArray / TownArray / UnitArray::draw_dot).
func _shown(o: GameObj) -> bool:
	if o in game.selected:
		return true          # the selected object ignores every filter
	if filter_nation >= 0 and o.nation_id != filter_nation:
		return false
	if filter_kind != "":
		if filter_kind == "unit" and not (o is Unit):
			return false
		if filter_kind == "town" and not (o is Town):
			return false
		if o is Firm:
			var group := ["FORT", "CAMP"]
			if filter_kind in group:
				if not (o.code in group):
					return false
			elif o.code != filter_kind:
				return false
		elif filter_kind != "unit" and filter_kind != "town":
			return false
	if mode == Mode.TRADE:
		if o is Firm:
			return o.code in ["MINE", "FACTORY", "MARKET"]
		if o is Unit:
			return o.is_caravan
	return true


func set_mode(m: int) -> void:
	if m == Mode.POWER and mode == Mode.POWER:
		power_mode = not power_mode       # the political map's button toggles the zones
	mode = m
	_refresh()


## The nation and object filter buttons: lock onto the selected object.
func toggle_filter_nation() -> void:
	if filter_nation >= 0 or game.selected.is_empty():
		filter_nation = -1
	else:
		filter_nation = game.selected[0].nation_id
	_refresh()


func toggle_filter_kind() -> void:
	if filter_kind != "" or game.selected.is_empty():
		filter_kind = ""
	else:
		var o = game.selected[0]
		filter_kind = "unit" if o is Unit else ("town" if o is Town else o.code)
	_refresh()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.05, 0.07))
	if game == null:
		return
	var xf := _xf()
	draw_set_transform_matrix(xf)
	draw_texture(_tex, Vector2.ZERO)
	for t in game.towns:
		if t.visible and _shown(t):
			draw_rect(Rect2(Vector2(t.x1, t.y1), Vector2(6, 6)), t.nation_color())
	for f in game.firms:
		if f.visible and _shown(f):
			draw_rect(Rect2(Vector2(f.x1, f.y1), Vector2(f.w, f.h)), f.nation_color().darkened(0.2))
	for u in game.units:
		if u.visible and not u.dead and u.inside_firm == null and _shown(u):
			draw_rect(Rect2(u.loc, Vector2(1.5, 1.5)), u.nation_color().lightened(0.3))
	# Show Unit Paths on the world map: black, red for attackers (ounadraw.cpp)
	for pl in game.unit_paths(2):
		var pts := PackedVector2Array(pl[0])
		if pts.size() >= 2:
			draw_polyline(pts, Color(0.85, 0.1, 0.1) if pl[1] else Color(0, 0, 0), 1.0)
	# WarPointArray::draw_dot: a flashing cross over each zone under attack
	_phase = (_phase + 1) % 16
	if _phase % 2 == 0 and not game.war_points.is_empty():
		var col: Color = [Color(1, 0.2, 0.1), Color(1, 0.5, 0.1), Color(1, 0.8, 0.2), Color(0, 0, 0, 0)][(_phase / 2) % 4]
		for z in game.war_points:
			var o := Vector2(z) * Game.WAR_ZONE
			var e := float(Game.WAR_ZONE)
			draw_line(o, o + Vector2(e, e), col, 1.5)
			draw_line(o + Vector2(e, 0), o + Vector2(0, e), col, 1.5)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	if camera:
		var vp := get_viewport_rect().size / camera.zoom
		var corners := [camera.iso_pos + Vector2(-vp.x, -vp.y) * 0.5, camera.iso_pos + Vector2(vp.x, -vp.y) * 0.5,
			camera.iso_pos + Vector2(vp.x, vp.y) * 0.5, camera.iso_pos + Vector2(-vp.x, vp.y) * 0.5]
		var pts := PackedVector2Array()
		for c in corners:
			pts.append(xf * Iso.to_loc(c))
		pts.append(pts[0])
		draw_polyline(pts, Color(1, 1, 1, 0.8), 1.0)


func _gui_input(event: InputEvent) -> void:
	if game == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		order_to.emit(_xf().affine_inverse() * (event as InputEventMouse).position)
		accept_event()
		return
	var pressed := false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		pressed = true
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		pressed = true
	if pressed:
		var loc: Vector2 = _xf().affine_inverse() * (event as InputEventMouse).position
		jump_to.emit(loc)
		accept_event()
