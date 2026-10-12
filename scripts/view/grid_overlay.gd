class_name GridOverlay
extends Node2D
## Debug: location grid lines over a rectangle of the map.

var rect := Rect2i()


func _ready() -> void:
	z_index = 70


func _draw() -> void:
	for x in range(rect.position.x, rect.end.x + 1):
		draw_line(Iso.to_screen(Vector2(x, rect.position.y)), Iso.to_screen(Vector2(x, rect.end.y)), Color(1, 1, 1, 0.25))
	for y in range(rect.position.y, rect.end.y + 1):
		draw_line(Iso.to_screen(Vector2(rect.position.x, y)), Iso.to_screen(Vector2(rect.end.x, y)), Color(1, 1, 1, 0.25))
