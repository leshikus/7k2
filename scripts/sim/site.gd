class_name Site
extends RefCounted
## A raw-material deposit (clay, copper or iron) that a mine can be built on.

var raw := ""
var row: Dictionary = {}
var x1 := 0
var y1 := 0
var w := 6
var h := 6
var reserve := 0.0
var mine: Firm = null


func footprint() -> Rect2i:
	return Rect2i(x1, y1, w, h)


func center_loc() -> Vector2:
	return Vector2(x1 + w * 0.5, y1 + h * 0.5)


func draw_ground(ci: CanvasItem) -> void:
	if mine != null or row.is_empty():
		return
	var ic := Assets.raw_icon(row["MAP_PTR"])
	if not ic.is_empty():
		var ofs := Vector2(row["OFFSET_X"].to_int(), row["OFFSET_Y"].to_int()) + Iso.bitmap_adjust(w, h)
		ci.draw_texture(ic[0], Iso.to_screen(Vector2(x1, y1)) + ofs)
