class_name Plant
extends Node2D
## A tree from the original plant bitmaps.

var tex: Texture2D
var ofs := Vector2.ZERO
var variant := 0


func _draw() -> void:
	render(self)


func render(cv) -> void:
	if tex:
		cv.draw_texture(tex, ofs)
