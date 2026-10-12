class_name DirDebug
extends Node2D
## Debug: line from each unit to its destination.

var pairs: Array = []


func _ready() -> void:
	z_index = 70


func _process(_d: float) -> void:
	queue_redraw()


func _draw() -> void:
	for p in pairs:
		var u: Unit = p[0]
		if is_instance_valid(u):
			draw_line(u.position, Iso.to_screen(p[1]), Color(1, 1, 0, 0.8), 2.0)
