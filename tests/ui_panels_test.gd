extends Node
## The interface in a long autoplay game, through the real main scene: every
## kind of object's panel (units of each type and rank, buildings, towns -
## ours and others') and every report tab; the runner reports any script
## error. (Caught a crash on a panel of non-fighters and caravans keeping
## destroyed buildings as stops, which only the full scene frees.)
var main: Node
var game: Game

func _ready() -> void:
	get_window().size = Vector2i(1280, 800)
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	main._start({"seed": 7, "size": 140, "race": "JAPANESE", "ai_count": 4, "fryhtan_count": 3,
		"cash": 3000, "no_tips": true, "start_paused": false, "autoplay": true, "treasure": 3, "random_events": 2})
	game = main.game
	var seen := {}
	var panels := 0
	for step in 60:
		for f in 60:
			game.sim_frame()
		await get_tree().process_frame
		var objs: Array = []
		for u in game.units:
			if not u.dead and u.inside_firm == null:
				var k := "U:%s:%d:%s" % [u.sprite_code, u.rank, u.nation_id == game.player_id]
				if not seen.has(k) or step % 20 == 0:
					seen[k] = 1
					objs.append(u)
		for f in game.firms:
			if not f.dead:
				var k := "F:%s:%s:%s" % [f.code, f.nation_id == game.player_id, f.under_construction]
				if not seen.has(k) or step % 20 == 0:
					seen[k] = 1
					objs.append(f)
		for t in game.towns:
			if not t.dead:
				var k := "T:%s:%d" % [t.nation_id == game.player_id, mini(t.nation_id, 1)]
				if not seen.has(k) or step % 20 == 0:
					seen[k] = 1
					objs.append(t)
		for o in objs:
			game.select_only(o)
			main.hud.refresh_selection(true)
			panels += 1
		if step % 30 == 0:
			for tab in ReportsWindow.TABS:
				main.hud.reports.show_tab(tab)
				await get_tree().process_frame
			main.hud.reports.visible = false
	print("panels built %d, kinds %d, day %d" % [panels, seen.size(), game.day])
	print("RESULT: ", "PASS" if panels > 200 and seen.size() > 40 else "FAIL")
	get_tree().quit()
