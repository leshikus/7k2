class_name Plant
extends Node2D
## A tree from the original plant bitmaps.

var tex: Texture2D
var ofs := Vector2.ZERO
var variant := 0


func _draw() -> void:
	if tex:
		draw_texture(tex, ofs)
