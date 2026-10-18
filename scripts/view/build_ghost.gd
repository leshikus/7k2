class_name BuildGhost
extends Node2D
## Placement preview of a building under the mouse cursor.

var build: Dictionary = {}
var pos := Vector2i.ZERO
var w := 1
var h := 1
var ok := false
var color := Color.WHITE


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
	# Link lines to the towns and buildings this site would connect to.
	var g := Game.inst
	if g:
		var c := Vector2(pos) + Vector2(w, h) * 0.5
		var sc := Vector2.ZERO
		var code: String = build.get("firm", "")
		var camp := code in ["CAMP", "FORT", "LAIR"]
		var work := code in Firm.WORK_FIRMS
		for t in g.towns:
			if not t.visible or Game._center_dist(c, t.center_loc()) > Defs.effective_distance(code, ""):
				continue
			if t.nation_id == 0 and not (work or code == "MARKET" or camp):
				continue
			if t.nation_id > 0 and t.nation_id != g.player_id and not camp:
				continue
			cv.draw_line(sc, o + Iso.to_screen(t.center_loc()), Color(1, 0.9, 0.3, 0.8), 2.0)
		for f in g.firms:
			if f.nation_id == g.player_id and Game._center_dist(c, f.center_loc()) <= Defs.effective_distance(f.code, code):
				cv.draw_line(sc, o + Iso.to_screen(f.center_loc()), Color(0.5, 0.8, 1.0, 0.8), 2.0)
	var frames: Array = build.get("frames", [])
	if frames.is_empty():
		return
	var origin := o + Iso.to_screen(Vector2(pos))
	for rec in frames[0]["bitmaps"]:
		var b := Assets.firm_bitmap(build, rec, color)
		if not b.is_empty() and b[2] != 4:
			cv.draw_texture(b[0], origin + b[1], Color(1, 1, 1, 0.55) * Color(tint.r * 0.5 + 0.5, tint.g * 0.5 + 0.5, tint.b * 0.5 + 0.5))
