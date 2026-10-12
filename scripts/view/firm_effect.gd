class_name FirmEffect
extends Node2D
## Building destruction explosion and fires, animated from FIRM_DIE.FRM.

var recs: Array = []
var frame_i := 0
var ticks := 0
var ticks_per_frame := 2
var loops := 0
var done := false


## part: 1 explosion, 2 small fire, 3 large fire. `at` is the location the
## bitmap is anchored to (the firm's top-left, or a random spot for fires).
func setup(part: int, at: Vector2, loop_count := 0) -> void:
	recs = Assets.die_part(part)
	loops = loop_count
	position = Iso.to_screen(at)
	z_index = 5
	done = recs.is_empty()


func sim_frame() -> void:
	if done:
		return
	ticks += 1
	if ticks >= ticks_per_frame:
		ticks = 0
		frame_i += 1
		if frame_i >= recs.size():
			if loops > 0:
				loops -= 1
				frame_i = 0
			else:
				done = true
				return
		queue_redraw()


func _draw() -> void:
	render(self)


func render(cv) -> void:
	if done or recs.is_empty():
		return
	var b := Assets.die_bitmap(recs[frame_i])
	if not b.is_empty():
		cv.draw_texture(b[0], b[1])
