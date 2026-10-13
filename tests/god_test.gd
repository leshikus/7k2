extends Node
## Every Greater Being with a power casts it next to enemies; check the effect.
func _ready() -> void:
	if Assets.load_install() != "":
		get_tree().quit(1); return
	var ok := true
	for race in ["ROMAN", "GREEK", "JAPANESE", "MONGOL", "CARTH", "PERSIAN", "INDIAN"]:
		var g := Game.new()
		add_child(g)
		g.start({"seed": 3, "size": 90, "race": race, "ai_count": 1, "fryhtan_count": 0, "lairs": 0})
		var p := g.player()
		var foe := g.nation(2)
		g.declare_war(1, 2)
		var home: Town = g.towns.filter(func(t): return t.nation_id == 1)[0]
		var c := Vector2i(home.center_loc()) + Vector2i(0, 9)
		var gi: Dictionary = Defs.gods[race]
		var god := g.spawn_unit(gi["unit"], 1, c, 100.0)
		p.prayer_points = 400.0
		var gen := g.spawn_unit(Defs.unit_sprite(race, "INF"), 1, c + Vector2i(1, 0), 40.0)
		gen.rank = Defs.Rank.GENERAL
		gen.leadership = 40.0
		var enemies: Array = []
		for i in 6:
			enemies.append(g.spawn_unit(Defs.unit_sprite(foe.race, "INF"), 2, c + Vector2i(2 + i % 3, 2 + i / 3), 30.0))
		var efirm := g.spawn_firm("CAMP", 2, foe.race, g._place_near(Rect2i(c, Vector2i.ONE), 6, 6, 4), true)
		var fog_before := g.fog.count(0)
		var hp_before: float = efirm.hp if efirm else 0.0
		# an enemy spy hiding in our town, for the Japanese god to expose
		var spy := g.spawn_unit(Defs.unit_sprite(foe.race, "INF"), 2, c + Vector2i(-2, 0), 20.0)
		spy.is_spy = true
		g.spy_enter(spy, home)
		# the original's powers are aimed (go_cast_power): at the general, an
		# enemy, an enemy building, or around the god for the earthquake
		var aim := c
		match race:
			"ROMAN": aim = gen.cell()
			"MONGOL", "INDIAN": aim = enemies[0].cell()
			"PERSIAN": aim = Vector2i(efirm.center_loc()) if efirm else c
			"JAPANESE":
				aim = Vector2i(home.center_loc())
				god.loc = Vector2(g.world.nearest_walkable(aim + Vector2i(0, 4)))
		if race == "CARTH":
			god.loc = Vector2(c)          # carth_cast_quake centres the quake on the god
		var cast := god.cast_power(aim)
		if race == "CARTH":
			g._quake_next_day()
		var effect := ""
		match race:
			"ROMAN": effect = "general leadership %d -> %d" % [40, gen.leadership]; ok = ok and gen.leadership >= 70.0
			"GREEK": effect = "own units invulnerable: %s" % (gen.invulnerable_until > g.frame); ok = ok and gen.invulnerable_until > g.frame
			"JAPANESE": effect = "enemy spy exposed: %s" % (spy.dead or not g.spies.has(spy)); ok = ok and (spy.dead or not g.spies.has(spy))
			"MONGOL": effect = "enemies defected: %d" % enemies.filter(func(e): return e.nation_id == 1).size(); ok = ok and enemies.any(func(e): return e.nation_id == 1)
			"CARTH":
				var shaken := enemies.filter(func(e): return e.dead or e.hp < e.max_hp).size()
				effect = "enemy camp hp %d -> %d, enemies shaken %d" % [hp_before, efirm.hp if efirm else -1, shaken]
				ok = ok and (shaken > 0 or (efirm != null and efirm.hp < hp_before))
			"PERSIAN": effect = "enemy camp revealed: %s" % (efirm != null and efirm.revealed_to.has(1)); ok = ok and efirm != null and efirm.revealed_to.has(1)
			"INDIAN":
				var hp0 := 0.0
				for e in enemies: hp0 += e.hp
				for i in 300: g.sim_frame()
				var hp1 := 0.0
				for e in enemies: hp1 += e.hp if not e.dead else 0.0
				effect = "tornadoes %d, enemy hp %d -> %d" % [g.tornadoes.size(), hp0, hp1]
				ok = ok and hp1 < hp0
		print("%-9s cast=%s  %s  prayer left %d" % [race, cast, effect, p.prayer_points])
		ok = ok and cast
		g.queue_free()
		await get_tree().process_frame
	print("RESULT: ", "PASS" if ok else "FAIL")
	get_tree().quit()
