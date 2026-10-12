class_name SelectBox
extends Control
## Rubber-band rectangle for drag selection.

var rect := Rect2()
var active := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func show_rect(a: Vector2, b: Vector2) -> void:
	rect = Rect2(a, b - a).abs()
	active = true
	queue_redraw()


func hide_rect() -> void:
	active = false
	queue_redraw()


func _draw() -> void:
	if active:
		draw_rect(rect, Color(0.4, 1.0, 0.4, 0.12))
		draw_rect(rect, Color(0.5, 1.0, 0.5, 0.9), false, 1.0)
