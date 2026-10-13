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
var warned := false


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
	# Bullet::warn_target: a step before landing, the units around the target see it coming
	if not warned and d.length() <= speed * 2.0:
		warned = true
		var at := Iso.to_loc(dest - Vector2(0, -8))
		for u in Game.inst.units_near(at, 2.5):
			if not u.dead and u.inside_firm == null and (shooter == null or not is_instance_valid(shooter) or u.nation_id != shooter.nation_id):
				u.warned(dir)
	if d.length() <= speed:
		done = true
		var at := Iso.to_loc(dest - Vector2(0, -8))
		if target and is_instance_valid(target) and not target.dead:
			at = target.center_loc()
			# SPAB_REFLECT_ARROW: the arrow flies back, a point weaker, now the reflecter's
			if target is Unit and target.special_ability() == "reflect" and damage > 1.0 \
					and shooter and is_instance_valid(shooter) and not shooter.dead:
				var back := Game.inst.spawn_bullet(target, shooter, sprite_code, speed, maxf(0.0, damage - 1.0))
				back.radius = radius
				if Assets.has_sprite("REFLECT"):
					Game.inst.spawn_sprite_effect("REFLECT", at, Color.WHITE)
				return
			var dmg := damage
			if target is Unit:
				dmg = (target as Unit).arrow_reduction(dmg, dir)
			if dmg > 0.0:
				target.take_damage(dmg, shooter if is_instance_valid(shooter) else null)
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
