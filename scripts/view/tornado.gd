class_name Tornado
extends Node2D
## Hanuman's tornado (otornado.cpp): wanders for a while, battering enemy units
## and buildings in its path.

var owner_nation := 0
var loc := Vector2.ZERO
var heading := Vector2.RIGHT
var life := 600
var frame_i := 0
var done := false


func setup(nation_id: int, at: Vector2) -> void:
	owner_nation = nation_id
	loc = at
	heading = Vector2.from_angle(Game.inst.rng.randf() * TAU)
	position = Iso.to_screen(loc)
	z_index = 6
	if Assets.is_blend_sprite("TORNADO"):
		material = Assets.blend_material()


func sim_frame() -> void:
	var g := Game.inst
	life -= 1
	if life <= 0:
		done = true
		return
	if life % 20 == 0:
		heading = heading.rotated(g.rng.randf_range(-0.8, 0.8))
	var next := loc + heading * 0.08
	if next.x < 1 or next.y < 1 or next.x > g.world.w - 2 or next.y > g.world.h - 2:
		heading = -heading
	else:
		loc = next
	position = Iso.to_screen(loc)
	frame_i += 1
	if life % 5 == 0:
		var owner := g.nation(owner_nation)
		for u in g.units:
			if u.dead or u.inside_firm or u.nation_id == owner_nation or u.is_god:
				continue
			if owner and u.nation_id > 0 and u.nation_id != GameObj.MONSTER_NATION and not owner.is_hostile_to(u.nation_id):
				continue
			if u.center_loc().distance_to(loc) < 1.6:
				u.take_damage(6.0, null)
		for f in g.firms:
			if f.nation_id != owner_nation and not f.dead and f.footprint().has_point(Vector2i(loc)):
				if owner and f.nation_id > 0 and f.nation_id != GameObj.MONSTER_NATION and not owner.is_hostile_to(f.nation_id):
					continue
				f.take_damage(20.0, null)
	queue_redraw()


func _draw() -> void:
	render(self)


func render(cv) -> void:
	var fr := Assets.sprite_frame("TORNADO", "M", 0, frame_i / 2, Color.WHITE)
	if not fr.is_empty():
		cv.draw_texture(fr[0], fr[1])
