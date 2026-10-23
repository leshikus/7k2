class_name BuildGhost
extends Node2D
## Placement preview of a building under the mouse cursor.

var build: Dictionary = {}
var pos := Vector2i.ZERO
var w := 1
var h := 1
var ok := false
var color := Color.WHITE
var _town: Town = null           # the town shown when a new town is placed


## A new town's place (Unit::settle_town): the town itself, transparent.
func set_town(race: String, p: Vector2i, valid: bool, col: Color) -> void:
	build = {"loc_w": Defs.TOWN_SIZE, "loc_h": Defs.TOWN_SIZE, "town": race}
	pos = p
	w = Defs.TOWN_SIZE
	h = Defs.TOWN_SIZE
	ok = valid
	color = col
	position = Iso.to_screen(Vector2(pos) + Vector2(w, h) * 0.5)
	if _town == null or _town.race != race:
		_town = Town.new()
		_town.setup("", race, Game.inst.player_id if Game.inst else 0, p, 20)
	_town.x1 = p.x
	_town.y1 = p.y
	_town.position = position
	queue_redraw()


func _ready() -> void:
	z_index = 60


func set_state(b: Dictionary, p: Vector2i, valid: bool, col: Color) -> void:
	build = b
	pos = p
	w = b.get("loc_w", 3)
	h = b.get("loc_h", 3)
	ok = valid
	color = col
	# anchored at its centre like a building, so the 3D view places its card there
	position = Iso.to_screen(Vector2(pos) + Vector2(w, h) * 0.5)
	queue_redraw()


func _draw() -> void:
	render(self)


func render(cv) -> void:
	if build.is_empty():
		return
	var tint := Color(0.4, 1.0, 0.4, 0.55) if ok else Color(1.0, 0.3, 0.3, 0.55)
	var o := -position
	var pts := PackedVector2Array([
		o + Iso.to_screen(Vector2(pos.x, pos.y)), o + Iso.to_screen(Vector2(pos.x + w, pos.y)),
		o + Iso.to_screen(Vector2(pos.x + w, pos.y + h)), o + Iso.to_screen(Vector2(pos.x, pos.y + h))])
	cv.draw_colored_polygon(pts, Color(tint.r, tint.g, tint.b, 0.25))
	pts.append(pts[0])
	cv.draw_polyline(pts, tint, 2.0)
	# the free band kept around every building and town (World::can_build_firm,
	# INTER_PLACE_SPACE): nothing may stand there; it ends at the map's edge
	var sp := Game.INTER_PLACE_SPACE
	var mw: int = Game.inst.world.w if Game.inst and Game.inst.world else 1 << 20
	var mh: int = Game.inst.world.h if Game.inst and Game.inst.world else 1 << 20
	var bx1 := maxi(0, pos.x - sp)
	var by1 := maxi(0, pos.y - sp)
	var bx2 := mini(mw, pos.x + w + sp)
	var by2 := mini(mh, pos.y + h + sp)
	var band := PackedVector2Array([
		o + Iso.to_screen(Vector2(bx1, by1)), o + Iso.to_screen(Vector2(bx2, by1)),
		o + Iso.to_screen(Vector2(bx2, by2)), o + Iso.to_screen(Vector2(bx1, by2))])
	band.append(band[0])
	for i in 4:
		Game.draw_dashes(cv, band[i], band[i + 1], Color(tint.r, tint.g, tint.b, 0.8), 1.5, 5.0)
	# a new town: the town itself, and lines to the buildings it would link to
	if build.has("town"):
		var gt := Game.inst
		if gt:
			var tc := Vector2(pos) + Vector2(w, h) * 0.5
			for f in gt.firms:
				if f.nation_id == gt.player_id and not f.dead and Defs.firm_links_town(f.code, f.race, str(build["town"])) \
						and Game._center_dist(tc, f.center_loc()) <= Defs.effective_distance(f.code, ""):
					cv.draw_line(Vector2.ZERO, o + Iso.to_screen(f.center_loc()), Color(1, 0.9, 0.3, 0.8), 2.0)
		if _town:
			_town.position = position
			_town.render(cv)
		return
	# Link lines to the towns and buildings this site would connect to.
	var g := Game.inst
	if g:
		var c := Vector2(pos) + Vector2(w, h) * 0.5
		var sc := Vector2.ZERO
		var code: String = build.get("firm", "")
		var camp := code in ["CAMP", "FORT", "LAIR"]
		var work := code in Firm.WORK_FIRMS
		var race: String = Game.inst.player().race if Game.inst.player() else ""
		for t in g.towns:
			if not t.visible or Game._center_dist(c, t.center_loc()) > Defs.effective_distance(code, ""):
				continue
			if not Defs.firm_links_town(code, race, t.race):
				continue
			if t.nation_id == 0 and not (work or code == "MARKET" or camp):
				continue
			if t.nation_id > 0 and t.nation_id != g.player_id and not camp:
				continue
			cv.draw_line(sc, o + Iso.to_screen(t.center_loc()), Color(1, 0.9, 0.3, 0.8), 2.0)
		for f in g.firms:
			if code != "INN" and f.nation_id == g.player_id and Defs.firms_linkable(code, f.code) and Game._center_dist(c, f.center_loc()) <= Defs.effective_distance(f.code, code):
				cv.draw_line(sc, o + Iso.to_screen(f.center_loc()), Color(0.5, 0.8, 1.0, 0.8), 2.0)
	var frames: Array = build.get("frames", [])
	if frames.is_empty():
		return
	var origin := o + Iso.to_screen(Vector2(pos))
	for rec in frames[0]["bitmaps"]:
		var b := Assets.firm_bitmap(build, rec, color)
		if not b.is_empty() and b[2] != 4:
			cv.draw_texture(b[0], origin + b[1], Color(1, 1, 1, 0.55) * Color(tint.r * 0.5 + 0.5, tint.g * 0.5 + 0.5, tint.b * 0.5 + 0.5))
