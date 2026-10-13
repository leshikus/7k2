extends Node
## Wagons and new towns (ou_wagon.cpp, Town::recruit, Unit::settle_town,
## Town::process_construction), and hit points by combat level
## (Skill::actual_max_hit_points, BaseObj::being_attack_hit).

var ok := true


func check(cond: bool, what: String) -> void:
	print(("ok   " if cond else "FAIL ") + what)
	if not cond:
		ok = false


func frames(g: Game, n: int) -> void:
	for i in n:
		g.sim_frame()


func site_near(g: Game, c: Vector2i) -> Vector2i:
	for r in range(6, 30):
		for k in 24:
			var a := TAU * k / 24.0
			var p := c + Vector2i(roundi(cos(a) * r), roundi(sin(a) * r))
			if g.can_build_town(p):
				return p
	return Vector2i(-1, -1)


func _ready() -> void:
	if Assets.load_install() != "":
		get_tree().quit(1); return
	Defs.load_from_assets()
	var g := Game.new()
	add_child(g)
	g.start({"seed": 17, "size": 120, "race": "NORMAN", "ai_count": 1, "fryhtan_count": 0, "reveal": true})
	frames(g, 5)
	var p := g.player()
	p.cash = 5000.0
	var home: Town = g.towns.filter(func(t): return t.nation_id == p.id)[0]

	# ---- hit points follow combat level; armour and ATTACK_SLOW_DOWN
	var base := float(Defs.unit_types[Defs.unit_sprite("NORMAN", "INF")]["hp"])
	var weak := g.spawn_unit(Defs.unit_sprite("NORMAN", "INF"), p.id, Vector2i(5, 5), 20.0)
	var strong := g.spawn_unit(Defs.unit_sprite("NORMAN", "INF"), p.id, Vector2i(7, 5), 80.0)
	check(is_equal_approx(weak.max_hp, base * 0.2) and is_equal_approx(strong.max_hp, base * 0.8), "hit points are the table's times combat level / 100 (%d, %d)" % [weak.max_hp, strong.max_hp])
	weak.combat = 40.0
	check(is_equal_approx(weak.max_hp, base * 0.4), "and grow with training")
	var cat := g.spawn_unit("CATAPULT", p.id, Vector2i(9, 5), 30.0)
	check(is_equal_approx(cat.max_hp, float(Defs.unit_types["CATAPULT"]["hp"])), "a war machine keeps its full hit points")
	var hp0 := strong.hp
	strong.take_damage(9.0 + strong.armor(), null)
	check(is_equal_approx(hp0 - strong.hp, 3.0), "a blow loses its armour and two thirds (ATTACK_SLOW_DOWN)")
	var king := p.king
	check(king != null and is_equal_approx(king.combat, 100.0) and is_equal_approx(king.leadership, 100.0), "the king starts with combat and leadership 100")

	# ---- a wagon of settlers
	home.population = 60
	var jobless := home.jobless()
	var pop0 := home.population
	var w: Unit = home.recruit_wagon()
	check(w != null and w.is_wagon(), "a town sends out a wagon")
	check(w.wagon_pop == mini(jobless, 10) and home.population == pop0 - w.wagon_pop, "with up to ten villagers (%d)" % w.wagon_pop)

	# it founds a new town
	var site := site_near(g, Vector2i(home.center_loc()))
	check(site.x >= 0, "room for a new town")
	var cash0 := p.cash
	w.order_found_town(site)
	var town: Town = null
	for i in 3000:
		g.sim_frame()
		var made := g.towns.filter(func(t): return t.x1 == site.x and t.y1 == site.y)
		if not made.is_empty():
			town = made[0]
			break
	check(town != null and town.under_construction and town.nation_id == p.id, "the wagon builds a town")
	check(is_equal_approx(cash0 - p.cash, Game.TOWN_BUILDING_COST) or cash0 - p.cash >= Game.TOWN_BUILDING_COST, "for %d gold" % int(Game.TOWN_BUILDING_COST))
	var settlers := w.wagon_pop
	check(w.dead or not is_instance_valid(w) or not g.units.has(w), "the wagon is used up")

	# save while it is being built
	SaveGame.save(g, "test_wagon")
	var g2 := Game.new()
	add_child(g2)
	SaveGame.load_into(g2, "test_wagon")
	DirAccess.remove_absolute(SaveGame.path_for("test_wagon"))
	var t2 := g2.towns.filter(func(t): return t.x1 == site.x and t.y1 == site.y)
	check(not t2.is_empty() and t2[0].under_construction and t2[0].builder_pop == settlers, "a town being built is saved")
	g2.queue_free()
	Game.inst = g

	for i in 400:
		g.sim_frame()
		if not town.under_construction:
			break
	check(not town.under_construction and town.population == settlers, "when built, the settlers move in (%d)" % town.population)

	# a second wagon settles into the new town
	home.population = 60
	var w2: Unit = home.recruit_wagon()
	var total := func(): return g.towns.filter(func(t): return t.nation_id == p.id and not t.dead).reduce(func(a, t): return a + t.population, 0)
	var before: int = total.call()
	var carried := w2.wagon_pop
	check(w2.order_settle(), "a wagon can settle in a town of its race")
	for i in 3000:
		g.sim_frame()
		if not is_instance_valid(w2) or w2.dead or not g.units.has(w2):
			break
	check(total.call() == before + carried, "its %d settlers join the town (%d -> %d)" % [carried, before, total.call()])

	# a single soldier founds a town too
	var s := g.spawn_unit(Defs.unit_sprite("NORMAN", "INF"), p.id, g.free_unit_cell(Vector2i(home.center_loc()) + Vector2i(0, 6)), 30.0)
	var site2 := site_near(g, s.cell() + Vector2i(4, 4))
	s.order_found_town(site2)
	var t3: Town = null
	for i in 3000:
		g.sim_frame()
		var made := g.towns.filter(func(t): return t.x1 == site2.x and t.y1 == site2.y)
		if not made.is_empty():
			t3 = made[0]
			break
	check(t3 != null and t3.builder_pop == 1, "a soldier founds a town of one")
	check(not king.can_found_town(), "a king may not")
	print("RESULT: ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
