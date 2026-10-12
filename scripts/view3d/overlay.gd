class_name View3DOverlay
extends Control
## Screen layer over the 3D world for lines, health bars, flags and labels recorded
## from objects. Each group is drawn around its object's projected ground anchor,
## scaled by the camera zoom, as the 2D view drew them.

var groups: Array = []        # [screen anchor, scale, vectors]


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _draw() -> void:
	for g in groups:
		draw_set_transform(g[0], 0.0, Vector2(g[1], g[1]))
		for v in g[2]:
			callv(v[0], v[1])
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
