class_name LightningBolt
extends Node2D
## A short-lived jagged lightning bolt striking a point on the map.

var points := PackedVector2Array()
var life := 0.35


func setup(world_pos: Vector2) -> void:
	position = world_pos
	z_index = 40
	var p := Vector2(randf_range(-60, 60), -700)
	points.append(p)
	while p.y < 0:
		p += Vector2(randf_range(-55, 55), randf_range(25, 60))
		points.append(Vector2(p.x, minf(p.y, 0.0)))
	points[points.size() - 1] = Vector2.ZERO


func _process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var a := clampf(life / 0.35, 0.0, 1.0)
	draw_polyline(points, Color(0.7, 0.8, 1.0, a * 0.5), 6.0)
	draw_polyline(points, Color(1, 1, 1, a), 2.0)
