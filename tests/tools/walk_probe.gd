extends Node
## Walk a peasant toward several targets and log when its facing changes.
##   godot --headless --path . res://tests/tools/walk_probe.tscn
func _ready() -> void:
	if Assets.load_install() != "":
		get_tree().quit(1); return
	var g := Game.new()
	add_child(g)
	g.start({"seed": 11, "size": 100, "race": "NORMAN", "ai_count": 1, "reveal": true, "lairs": 0})
	var p := g.player()
	var c := g.world.nearest_walkable(Vector2i(50, 50))
	var u := g.spawn_unit("NO_CIV", p.id, c, 0)
	for off in [Vector2i(-8, 4), Vector2i(8, -4), Vector2i(-4, 8), Vector2i(4, -8), Vector2i(-9, 3), Vector2i(9, -3)]:
		u.order_move(u.cell() + off)
		var line := ""
		var last := -9
		for i in 300:
			g.sim_frame()
			line += "%.1f " % u.position.x
			if u.dir != last:
				line += "[%d]@%d " % [u.dir, i]
				last = u.dir
			if u.order == Unit.Order.IDLE: break
		print(off, " ", line)
	get_tree().quit()
