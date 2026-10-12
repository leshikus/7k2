extends Node
## Espionage: train, infiltrate a town (resistance falls), sabotage, steal tech.
func _ready() -> void:
	Assets.load_install()
	var g := Game.new()
	add_child(g)
	g.start({"seed": 8, "size": 100, "race": "NORMAN", "ai_count": 1, "fryhtan_count": 0, "lairs": 0, "reveal": true})
	var ok := true
	var home: Town = g.towns.filter(func(t): return t.nation_id == 1)[0]
	home.loyalty = 80.0
	var college := g.spawn_firm("SPY", 1, "NORMAN", g._place_near(home.footprint(), 5, 5, 8, [home.center_loc()]), true)
	g.update_links()
	college.weapon_queue = 1
	for d in 30:
		for f in Defs.FRAMES_PER_DAY: g.sim_frame()
	var spy: Unit = null
	for u in g.units:
		if u.is_spy: spy = u
	print("spy trained: ", spy != null, " skill ", int(spy.spy_skill) if spy else -1, " college '", college.display_name(), "'")
	ok = ok and spy != null
	if spy:
		var indep: Array = g.towns.filter(func(t): return t.nation_id == 0)
		indep.sort_custom(func(a, b): return a.center_loc().distance_to(home.center_loc()) < b.center_loc().distance_to(home.center_loc()))
		var t: Town = indep[0]
		var r0 := t.resistance_to(1)
		spy.order_infiltrate(t)
		for d in 200:
			for f in Defs.FRAMES_PER_DAY: g.sim_frame()
		print("infiltrated ", t.town_name, ": hidden=", spy.has_meta("hidden"), " resistance %d -> %d" % [r0, t.resistance_to(1)])
		ok = ok and spy.has_meta("hidden") and t.resistance_to(1) < r0
		# enemy research tower: sabotage then steal
		g.spy_leave(spy)
		var foe := g.nation(2)
		foe.tech["MINING"] = 2
		var foe_town: Town = g.towns.filter(func(x): return x.nation_id == 2)[0]
		var tower := g.spawn_firm("RESEARCH", 2, foe.race, g._place_near(foe_town.footprint(), 5, 5, 8), true)
		spy.spy_skill = 90.0
		g.spy_enter(spy, tower)
		spy.spy_action = "sabotage"
		var hp0 := tower.hp
		for d in 12:
			for f in Defs.FRAMES_PER_DAY: g.sim_frame()
		spy.spy_action = "steal"
		for d in 12:
			for f in Defs.FRAMES_PER_DAY: g.sim_frame()
		print("sabotage hp %d -> %d, stolen MINING level %d, spy alive %s" % [hp0, tower.hp, g.player().tech_level("MINING"), not spy.dead])
		ok = ok and tower.hp < hp0 and (g.player().tech_level("MINING") > 0 or spy.dead)
	print("RESULT: ", "PASS" if ok else "FAIL")
	get_tree().quit()
