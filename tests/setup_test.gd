extends Node
## The start screen's game settings (Config, obattle.cpp): presets, treasure,
## the start-up kingdom, independent towns and lairs, resources, explored map
## and fog of war, spying methods, the difficulty rating, goals, and the
## independent towns' own doings (walls, villagers joining, new kingdoms, new
## villages).
var fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


func _days(g: Game, n: int) -> void:
	for d in n:
		for f in Defs.FRAMES_PER_DAY:
			g.sim_frame()


func _game(s: Dictionary, seed := 5) -> Game:
	var g := Game.new()
	add_child(g)
	g.start(GameSetup.to_config(s, {"seed": seed, "size": 140, "race": "NORMAN"}))
	return g


func _ready() -> void:
	Assets.load_install()
	Defs.load_from_assets()
	# --- presets and rating
	var s := GameSetup.defaults()
	_check(s["difficulty"] == 1 and s["treasure"] == GameSetup.VERY_HIGH and s["indep_towns"] == 30, "the default is the original's 'very easy'")
	# very easy (Config::change_difficulty(1)): 2+1 rivals (+18), explored, no fog,
	# 7 sites, huge treasure, small computer treasure, no aggressiveness (-10),
	# low resistance, no new kingdoms, no events, a mine near by, spy methods known
	var expect := 10 + 3 * 6 - 10
	_check(GameSetup.rating(s) == expect, "difficulty rating %d (expected %d)" % [GameSetup.rating(s), expect])
	var hard := GameSetup.defaults()
	GameSetup.apply_difficulty(hard, 7)
	_check(hard["fog"] and not hard["explore"] and hard["raw_sites"] == 3 and hard["ai_treasure"] == GameSetup.VERY_HIGH, "the hardest preset")
	_check(GameSetup.matches_level(hard, 7) and not GameSetup.matches_level(hard, 6), "a preset is recognised")

	# --- a very easy game
	s["ai_humans"] = 2
	s["ai_fryhtans"] = 1
	var g := _game(s)
	var p := g.player()
	_check(int(p.cash) == 20000 and int(p.food) == 5000, "huge treasure: 20000 gold, 5000 food (%d, %d)" % [int(p.cash), int(p.food)])
	var ai_h: Nation = g.nations.filter(func(n): return n.is_ai and not n.is_fryhtan)[0]
	var ai_f: Nation = g.nations.filter(func(n): return n.is_fryhtan)[0]
	_check(int(ai_h.cash) == 4000, "small computer treasure: 4000 (%d)" % int(ai_h.cash))
	_check(int(ai_f.cash) == 2000 and int(ai_f.live_points) == 4000, "a Fryhtan kingdom: half the gold, life points by your treasure (%d, %d)" % [int(ai_f.cash), int(ai_f.live_points)])
	var home: Town = g.towns.filter(func(t): return t.nation_id == p.id)[0]
	_check(home.population == 60 and int(home.loyalty) == 100, "the start-up town: 60 people of loyalty 100")
	var outside := g.units.filter(func(u): return u.nation_id == p.id and u.inside_firm == null and not u.dead)
	_check(outside.is_empty(), "no men outside the fort without a random start (%d)" % outside.size())
	var fort: Firm = g.firms.filter(func(f): return f.nation_id == p.id and f.code == "FORT")[0]
	_check(fort.soldiers.size() == 7 and fort.overseer and fort.overseer.rank == Defs.Rank.KING, "the king and seven soldiers in the fort")
	var indep := g.towns.filter(func(t): return t.nation_id == 0)
	print("independent towns ", indep.size())
	_check(indep.size() >= 15, "many independent towns (%d of 30 fit)" % indep.size())
	_check(indep.all(func(t): return t.resistance_to(p.id) >= 50 and t.resistance_to(p.id) < 80 and t.base_resistance == t.resistance_to(p.id)),
		"low resistance: 50-79, alike for every kingdom")
	var races := {}
	for t in indep:
		races[t.race] = true
	_check(races.size() <= 7, "at most seven races among them (%d)" % races.size())
	_check(g.firms.filter(func(f): return f.code == "LAIR" and f.nation_id == GameObj.MONSTER_NATION).size() == 7, "seven independent Fryhtan lairs")
	_check(g.sites.size() == 8, "seven resource sites and one by your town (%d)" % g.sites.size())
	_check(g.sites.any(func(st): return Vector2(st.x1, st.y1).distance_to(home.center_loc()) < 20.0), "a deposit near your town")
	_check(not g.fog_of_war and g.fog.count(0) == 0 and g.is_loc_visible(Vector2i(g.world.w - 3, g.world.h - 3)), "explored map without fog: everything is in view")
	_check(p.tech_level("STEALINF") == 1 and p.tech_level("BRIBE") == 1, "the spying methods are known")
	_check(p.contact.has(ai_h.id), "with the map explored, every kingdom has met the others")
	_check(g.goals == null, "no goals: the plain rule")
	# FirmFort: five archers on the walls shoot back
	_check(fort.archers == 5, "five archers on the fort's walls")
	var foe := g.spawn_unit(Defs.unit_sprite(ai_h.race, "INF"), ai_h.id, fort.door() + Vector2i(2, 0), 30.0)
	var b0 := g.bullets.size()
	fort.take_damage(10.0, foe)
	_check(g.bullets.size() == b0 + 1, "an archer shoots back at the attacker")
	fort.take_damage(10.0, foe)
	fort.take_damage(10.0, foe)
	_check(g.bullets.size() <= b0 + 2, "no more than two archers fire in a frame")
	g.remove_unit(foe)
	fort.archers = 0
	fort.target_archers = 0
	fort.set_target_archers(-1)
	var c0 := p.cash
	_days(g, 62)
	_check(fort.archers == 1 and p.cash < c0 - 100.0, "an archer is trained in 60 days for 120 gold (%d archers, %d spent)" % [fort.archers, int(c0 - p.cash)])
	g.queue_free()

	# --- the hardest game
	hard["ai_humans"] = 1
	hard["ai_fryhtans"] = 0
	hard["goal_population_flag"] = true
	hard["goal_population"] = 70
	g = _game(hard, 6)
	p = g.player()
	_check(int(p.cash) == 4000, "small treasure: 4000 (%d)" % int(p.cash))
	_check(g.fog_of_war and g.fog.count(0) > 0, "unexplored with fog of war")
	_check(p.tech_level("STEALINF") == 0, "spying needs research")
	indep = g.towns.filter(func(t): return t.nation_id == 0)
	_check(indep.size() <= 7 and indep.all(func(t): return t.resistance_to(p.id) >= 90 and t.wall_level >= 1), "few towns of high resistance, all walled")
	_check(g.sites.size() == 3, "three resource sites (%d)" % g.sites.size())
	home = g.towns.filter(func(t): return t.nation_id == p.id)[0]
	_check(g.goals != null and g.goals.win.size() == 3, "goals: defeat all, or the population")
	home.population = 75
	_days(g, 2)
	_check(g.over, "reaching the population goal wins the game")
	g.queue_free()

	# --- independent towns at work
	var ns := GameSetup.defaults()
	ns["ai_humans"] = 2
	ns["ai_fryhtans"] = 0
	ns["nation_emerge"] = true
	g = _game(ns, 7)
	var t: Town = g.towns.filter(func(x): return x.nation_id == 0)[0]
	t.wall_level = 0
	t.target_wall_level = 0
	t.population = 60
	var walled := false
	for k in 200:
		Independents.think_build_wall(g, t)
		if t.target_wall_level > 0:
			walled = true
			break
	_check(walled, "an independent town decides to raise a wall")
	# a villager joins the kingdom of his race with the best standing
	var same: Town = null
	for x in g.towns:
		if x.nation_id == 0 and g.towns.any(func(o): return o.nation_id > 0 and o.race == x.race):
			same = x
	if same:
		same.join_min_rating = 1
		var pop0 := same.population
		Independents.think_unit_join_nation(g, same)
		_check(same.population == pop0 - 1, "a villager of %s leaves to join a kingdom" % same.town_name)
	# a fallen rival makes room for a new kingdom
	var rival: Nation = g.nations.filter(func(n): return n.is_ai)[0]
	rival.alive = false
	g.last_del_nation_day = -1000
	_check(Independents.can_form_new_ai_nation(g), "with a rival gone a new kingdom may form")
	var n0 := g.nations.size()
	t.population = 40
	var nid := Independents.form_new_nation(g, t)
	_check(nid > 0 and g.nations.size() == n0 + 1 and t.nation_id == nid and g.nation(nid).king != null, "%s proclaims a kingdom" % t.town_name)
	_check(not Independents.can_form_new_ai_nation(g), "and no other for a year")
	# wanderers settle a new village
	for x in g.towns.duplicate():
		if x.nation_id == 0 and x != t:
			x.population = 0
			x._check_empty()
	var towns0 := g.towns.filter(func(x): return not x.dead).size()
	for k in 30:
		g.day = 30 * (k + 1)
		Independents.think_new_town(g)
	_check(g.towns.filter(func(x): return not x.dead).size() > towns0, "wanderers found a new village")
	# saved and loaded
	SaveGame.save(g, "test_setup")
	var g2 := Game.new()
	add_child(g2)
	_check(SaveGame.load_into(g2, "test_setup") == "" and g2.fog_of_war == g.fog_of_war and g2.last_new_nation_day == g.last_new_nation_day,
		"a saved game keeps the settings' state")
	DirAccess.remove_absolute(SaveGame.path_for("test_setup"))
	print("RESULT: ", "PASS" if fails == 0 else "FAIL")
	get_tree().quit(0 if fails == 0 else 2)
