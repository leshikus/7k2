extends Node2D
## Draws every frame of a sprite action in all 8 directions, anchored on a cross,
## to check frame-to-frame alignment. Usage:
##   godot --path . res://tests/tools/walk_strip.tscn -- code=NO_CIV act=M shot=<png>
func _ready() -> void:
	if Assets.load_install() != "":
		get_tree().quit(1); return
	var code := "NO_CIV"
	var act := "M"
	var shot := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("code="): code = a.substr(5)
		elif a.begins_with("act="): act = a.substr(4)
		elif a.begins_with("shot="): shot = a.substr(5)
	get_window().size = Vector2i(1400, 900)
	for d in 8:
		var n := Assets.action_len(code, act, d)
		for f in n:
			var fr := Assets.sprite_frame(code, act, d, f, Color(0.8, 0.1, 0.1))
			if fr.is_empty():
				continue
			var at := Vector2(60 + f * 110, 70 + d * 105)
			var s := Sprite2D.new()
			s.texture = fr[0]
			s.centered = false
			s.position = at + fr[1]
			add_child(s)
			var l := Line2D.new()
			l.points = [at - Vector2(40, 0), at + Vector2(40, 0)]
			l.width = 1
			add_child(l)
			var l2 := Line2D.new()
			l2.points = [at - Vector2(0, 60), at + Vector2(0, 15)]
			l2.width = 1
			add_child(l2)
	RenderingServer.set_default_clear_color(Color(0.35, 0.45, 0.3))
	if shot != "":
		await get_tree().create_timer(0.3).timeout
		get_viewport().get_texture().get_image().save_png(shot)
		get_tree().quit()
