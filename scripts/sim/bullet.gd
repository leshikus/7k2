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
var radius := 0         # BUL_RADIUS: hurts everything this close (in 1/32 of a cell)
var fire := 0           # FL_RADIUS: sets the ground alight


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
		var at := Iso.to_loc(dest - Vector2(0, -8))
		if target and is_instance_valid(target) and not target.dead:
			at = target.center_loc()
			target.take_damage(damage, shooter if is_instance_valid(shooter) else null)
		_splash(at)
		if fire > 0:
			Game.inst.set_fire(Vector2i(at.floor()), fire)
		return
	position += d.normalized() * speed
	frame += 1
	queue_redraw()


## Bullet::check_hit / attenuated_damage: others near the impact take
## damage falling from full to half at the edge of the radius; the
## shooter's own men are spared.
func _splash(at: Vector2) -> void:
	if radius <= 32:
		return
	var r := radius / 32.0
	var nid: int = shooter.nation_id if shooter and is_instance_valid(shooter) else -1
	for u in Game.inst.units_near(at, r + 0.5):
		if u == target or u.dead or u.inside_firm != null or u.nation_id == nid:
			continue
		if nid >= 0 and shooter and is_instance_valid(shooter) and not Game.inst.is_hostile(shooter, u):
			continue
		var d: float = u.center_loc().distance_to(at) * 32.0
		if d > radius:
			continue
		u.take_damage(damage - damage * d / (2.0 * radius) if d > 1.0 else damage, shooter if is_instance_valid(shooter) else null)


func _draw() -> void:
	render(self)


func render(cv) -> void:
	var fr := Assets.sprite_frame(sprite_code, "M", dir, frame, color)
	if not fr.is_empty():
		cv.draw_texture(fr[0], fr[1] - Vector2(0, -16))
	else:
		cv.draw_circle(Vector2.ZERO, 2, Color.BLACK)
