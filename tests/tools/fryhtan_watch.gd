extends Node
## A computer-only game with Fryhtan kingdoms, to watch their special buildings
## and the human kingdoms' new research:
##   godot --headless --path . res://tests/tools/fryhtan_watch.tscn -- days=2000 seed=3
func _ready() -> void:
	if Assets.load_install() != "":
		get_tree().quit(1); return
	var days := 2000
	var seed := 3
	for a in OS.get_cmdline_user_args():
		if a.begins_with("days="): days = a.substr(5).to_int()
		elif a.begins_with("seed="): seed = a.substr(5).to_int()
	var g := Game.new()
	add_child(g)
	g.start({"seed": seed, "size": 160, "race": "NORMAN", "ai_count": 3, "fryhtan_count": 2, "autoplay": true, "reveal": true})
	var t0 := Time.get_ticks_msec()
	for d in days:
		for f in Defs.FRAMES_PER_DAY:
			g.sim_frame()
		if d % 500 == 499:
			print("day %d (%ds)" % [g.day, (Time.get_ticks_msec() - t0) / 1000])
			for n in g.nations:
				var kinds := {}
				for f in g.firms:
					if f.nation_id == n.id:
						kinds[f.code] = kinds.get(f.code, 0) + 1
				var units := {}
				for u in g.units:
					if u.nation_id == n.id and not u.dead:
						units[u.sprite_code] = units.get(u.sprite_code, 0) + 1
				var techs := n.tech.keys().filter(func(k): return not Defs.tech_def(k).is_empty())
				for f in g.firms:
					if f.nation_id == n.id and f.code == "RESEARCH":
						print("    research %s workers %d pts %d links %d" % [f.research_tech, f.workers(), int(f.research_points), f.linked_towns.filter(func(t): return t.nation_id == n.id).size()])
				print("  %s alive=%s cash=%d life=%d\n    firms %s\n    units %s\n    tech %s" % [n.name, n.alive, int(n.cash), int(n.live_points), kinds, units, techs])
	get_tree().quit()
