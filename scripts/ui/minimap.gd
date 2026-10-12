class_name Minimap
extends Control
## Diamond-shaped overview map. Click or drag to move the camera.

signal jump_to(loc: Vector2)
signal order_to(loc: Vector2)

var game: Game
var camera: Camera2D
var _img: Image
var _tex: ImageTexture
var _timer := 0.0
var _base := PackedByteArray()

const TERRAIN_COLORS := [Color(0.25, 0.42, 0.16), Color(0.42, 0.55, 0.22), Color(0.52, 0.42, 0.28)]


func setup(g: Game, cam: Camera2D) -> void:
	game = g
	camera = cam
	var w := g.world.w
	var h := g.world.h
	_img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	_base.resize(w * h * 4)
	for y in h:
		for x in w:
			var c: Color = TERRAIN_COLORS[g.world.corner(x, y)]
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


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.05, 0.07))
	if game == null:
		return
	var xf := _xf()
	draw_set_transform_matrix(xf)
	draw_texture(_tex, Vector2.ZERO)
	for t in game.towns:
		if t.visible:
			draw_rect(Rect2(Vector2(t.x1, t.y1), Vector2(6, 6)), t.nation_color())
	for f in game.firms:
		if f.visible:
			draw_rect(Rect2(Vector2(f.x1, f.y1), Vector2(f.w, f.h)), f.nation_color().darkened(0.2))
	for u in game.units:
		if u.visible and not u.dead and u.inside_firm == null:
			draw_rect(Rect2(u.loc, Vector2(1.5, 1.5)), u.nation_color().lightened(0.3))
	draw_set_transform_matrix(Transform2D.IDENTITY)
	if camera:
		var vp := get_viewport_rect().size / camera.zoom
		var corners := [camera.position + Vector2(-vp.x, -vp.y) * 0.5, camera.position + Vector2(vp.x, -vp.y) * 0.5,
			camera.position + Vector2(vp.x, vp.y) * 0.5, camera.position + Vector2(-vp.x, vp.y) * 0.5]
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
