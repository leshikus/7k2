class_name SpriteEffect
extends Node2D
## One pass through an effect sprite's frames (spell flashes such as RO_EFF1).

var code := ""
var action := ""
var frames := 1
var frame_i := 0
var color := Color.WHITE
var done := false


func setup(sprite: String, at: Vector2, col: Color) -> void:
	code = sprite
	color = col
	var acts: Dictionary = Assets.sprites.get(sprite, {}).get("actions", {})
	action = acts.keys()[0] if not acts.is_empty() else "M"
	frames = maxi(1, Assets.action_len(sprite, action, 0))
	position = Iso.to_screen(at)
	z_index = 6
	if Assets.is_blend_sprite(sprite):
		material = Assets.blend_material()


func sim_frame() -> void:
	frame_i += 1
	if frame_i >= frames * 3:
		done = true
	queue_redraw()


func _draw() -> void:
	var fr := Assets.sprite_frame(code, action, 0, frame_i / 3, color)
	if not fr.is_empty():
		draw_texture(fr[0], fr[1])
