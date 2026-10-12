class_name Bullet
extends Node2D
## A projectile (arrow, javelin, boulder) flying toward its target.

var shooter: GameObj = null
var target: GameObj = null
var sprite_code := ""
var speed := 16.0
var damage := 0.0
var dir := 0
var frame := 0
var dest := Vector2.ZERO
var color := Color.WHITE
var done := false


func setup(from: Unit, to: GameObj, sprite: String, spd: float, dmg: float) -> void:
	shooter = from
	target = to
	sprite_code = sprite
	speed = spd
	damage = dmg
	color = from.nation_color()
	position = from.position + Vector2(0, -12)
	dest = Iso.to_screen(to.center_loc()) + Vector2(0, -8)
	dir = maxi(0, Iso.dir_of(to.center_loc() - from.center_loc()))
	z_index = 2
	if Assets.is_blend_sprite(sprite):
		material = Assets.blend_material()


func sim_frame() -> void:
	if done:
		return
	if target and is_instance_valid(target) and not target.dead:
		dest = Iso.to_screen(target.center_loc()) + Vector2(0, -8)
	var d := dest - position
	if d.length() <= speed:
		done = true
		if target and is_instance_valid(target) and not target.dead:
			target.take_damage(damage, shooter if is_instance_valid(shooter) else null)
		return
	position += d.normalized() * speed
	frame += 1
	queue_redraw()


func _draw() -> void:
	render(self)


func render(cv) -> void:
	var fr := Assets.sprite_frame(sprite_code, "M", dir, frame, color)
	if not fr.is_empty():
		cv.draw_texture(fr[0], fr[1] - Vector2(0, -16))
	else:
		cv.draw_circle(Vector2.ZERO, 2, Color.BLACK)
