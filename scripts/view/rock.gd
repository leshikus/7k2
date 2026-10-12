class_name Rock
extends Node2D
## A mountain or boulder. Blocks movement and building like the original's rocks.

var kind := 0          # index into Assets.rock_types
var x1 := 0
var y1 := 0
var w := 1
var h := 1
var tex: Texture2D
var ofs := Vector2.ZERO


func setup(type_index: int, at: Vector2i) -> void:
	var t: Dictionary = Assets.rock_types[type_index]
	kind = type_index
	x1 = at.x
	y1 = at.y
	w = t["w"]
	h = t["h"]
	tex = t["tex"]
	# sort by the footprint centre so units walking around are layered correctly
	position = Iso.to_screen(Vector2(x1 + w * 0.5, y1 + h * 0.5))
	ofs = Iso.to_screen(Vector2(x1, y1)) - position + t["ofs"]


func footprint() -> Rect2i:
	return Rect2i(x1, y1, w, h)


func _draw() -> void:
	if tex:
		draw_texture(tex, ofs)
