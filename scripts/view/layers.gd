class_name GroundLayer
extends Node2D
## Draws the flat ground bitmaps of raw sites, firms and towns below all objects.

var game: Game


func _draw() -> void:
	render(self)


func render(cv) -> void:
	if game == null:
		return
	for l in game.lakes:
		var t: Dictionary = Assets.rock_types[l[0]]
		if game.is_explored_rect(Rect2i(l[1], l[2], t["w"], t["h"])):
			cv.draw_texture(t["tex"], Iso.to_screen(Vector2(l[1], l[2])) + t["ofs"])
	for s in game.sites:
		if game.is_explored_rect(s.footprint()):
			s.draw_ground(cv)
	for t in game.towns:
		if is_instance_valid(t) and not t.dead and game.is_explored_rect(t.footprint()):
			t.draw_ground(cv)
	for f in game.firms:
		if is_instance_valid(f) and not f.dead and game.is_explored_rect(f.footprint()):
			f.draw_ground(cv)
	for r in game.rubble:
		cv.draw_texture(r[0], r[1])
