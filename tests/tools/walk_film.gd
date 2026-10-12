extends Node
## Film a peasant walking left then right in the real renderer, one PNG strip each.
##   godot --path . res://tests/tools/walk_film.tscn -- out=<dir>
func _ready() -> void:
	if Assets.load_install() != "":
		get_tree().quit(1); return
	var out := "."
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4)
	get_window().size = Vector2i(160, 160)
	var g := Game.new()
	add_child(g)
	g.start({"seed": 11, "size": 100, "race": "NORMAN", "ai_count": 1, "reveal": true, "lairs": 0})
	var u := g.spawn_unit("NO_CIV", g.player().id, g.world.nearest_walkable(Vector2i(50, 50)), 0)
	var cam := Camera2D.new()
	cam.zoom = Vector2(2, 2)
	add_child(cam)
	cam.make_current()
	for leg in [["left", Vector2i(-5, 5)], ["right", Vector2i(5, -5)]]:
		u.order_move(u.cell() + leg[1])
		var strip := Image.create(80 * 24, 80, false, Image.FORMAT_RGBA8)
		for i in 24:
			g.sim_frame()
			cam.position = Iso.to_screen(Vector2(50, 50)) + Vector2(0, -10)
			cam.position.x = u.position.x       # follow at the unit's x so drift shows
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			strip.blit_rect(img, Rect2i(40, 40, 80, 80), Vector2i(i * 80, 0))
		strip.save_png(out.path_join("film_%s.png" % leg[0]))
	get_tree().quit()
