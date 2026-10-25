extends Node
## Heroes and the inn (oherores.cpp, of_inn.cpp), the inn's recruiting
## policies, behaviour modes, the Bheema's sting, squads, auto retreat and
## reward, disbanding, spies' cover, links and taxes.

var fails := 0


func _check(cond: bool, what: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + what)
	if not cond:
		fails += 1


func _days(g: Game, n: int) -> void:
	for d in n:
		for f in Defs.FRAMES_PER_DAY:
			g.sim_frame()


func _ready() -> void:
	Assets.load_install()
	var g := Game.new()
	add_child(g)
	g.start({"seed": 21, "size": 100, "race": "NORMAN", "ai_count": 1, "fryhtan_count": 0, "lairs": 0, "reveal": true})
	for n in g.nations:
		n.ai = null
	var p := g.player()
	p.cash = 50000.0
	var home: Town = g.towns.filter(func(x): return x.nation_id == p.id)[0]

	# --- heroes: ten a nationality, half for hire, none seen yet
	_check(g.hero_info.size() == Defs.races.size() * HeroRes.HERO_COUNT_PER_RACE, "ten heroes a nationality (%d)" % g.hero_info.size())
	_check(g.hero_info.all(func(h): return not h["appeared"]), "none has appeared")
	var hire_n := g.hero_info.filter(func(h): return h["for_hire"]).size()
	_check(hire_n > g.hero_info.size() / 4 and hire_n < g.hero_info.size() * 3 / 4, "about half can be hired (%d)" % hire_n)
	_check(HeroRes.hire_cost(50, 0, 50, 0, 0) == (50 + 100 + 100 + 50 + 2 + 6) * 2, "HeroRes::hire_cost (%d)" % HeroRes.hire_cost(50, 0, 50, 0, 0))
	var hu := HeroRes.generate_hero(g)
	_check(hu != null and hu.nation_id == 0 and hu.hero_id > 0 and HeroRes.info(g, hu.hero_id)["appeared"], "a hero comes out of a town")
	_check(hu.combat >= 20 and hu.leadership >= 20, "with the powers of a hero (combat %d, leadership %d)" % [hu.combat, hu.leadership])
	_check(not g.is_hostile(hu, home) and not g.is_hostile(g.units.filter(func(u): return u.nation_id == p.id)[0], hu), "a wandering hero is nobody's enemy")
	HeroRes.info(g, hu.hero_id)["for_hire"] = true
	var cost := HeroRes.unit_hire_cost(hu)
	var c0 := p.cash
	_check(HeroRes.hire(g, hu, p.id) and hu.nation_id == p.id and hu.rank == Defs.Rank.GENERAL and is_equal_approx(c0 - p.cash, float(cost)),
		"hired for %d, he joins as a general" % cost)

	# --- the inn
	var inn := g.spawn_firm("INN", p.id, p.race, g._place_near(home.footprint(), 4, 4, 10), true)
	g.update_links()
	_check(inn.linked_towns.is_empty(), "an inn links to no town")
	for i in 8:
		Inn.add_inn_unit(inn, Defs.races[i % Defs.races.size()]["code"])
	_check(inn.heroes.size() >= 6, "guests come by (%d)" % inn.heroes.size())
	_check(inn.heroes.any(func(h): return int(h["spy_skill"]) > 0) and inn.heroes.any(func(h): return int(h["spy_skill"]) == 0), "soldiers and spies")
	_check(inn.heroes.all(func(h): return int(h["stay"]) >= 10 and int(h["stay"]) <= 14), "each stays 10-14 updates")
	var si := -1
	for i in inn.heroes.size():
		if int(inn.heroes[i]["spy_skill"]) == 0:
			si = i
			break
	var s_cost := int(inn.heroes[si]["cost"])
	c0 = p.cash
	var su := Inn.hire(inn, si)
	_check(su != null and su.rank == Defs.Rank.SOLDIER and su.nation_id == p.id and is_equal_approx(c0 - p.cash, float(s_cost)), "a soldier is hired for %d, as a soldier" % s_cost)
	_check(su.loyalty >= 40.0, "at a loyalty of at least 40 (%.0f)" % su.loyalty)
	var spi := -1
	for i in inn.heroes.size():
		if int(inn.heroes[i]["spy_skill"]) > 0:
			spi = i
			break
	var spu := Inn.hire(inn, spi)
	_check(spu != null and spu.is_spy and spu.spy_skill >= 30, "a spy for hire becomes our spy (skill %d)" % int(spu.spy_skill))

	# --- recruiting policy: soldiers go to the nearest fort with room
	var fort: Firm = g.firms.filter(func(f): return f.nation_id == p.id and f.code == "FORT")[0]
	while fort.soldiers.size() > 2:
		fort.release_unit(fort.soldiers[-1])
	inn.heroes.clear()
	inn.heroes.append({"sprite": Defs.unit_sprite(p.race, "SPU"), "race": p.race, "name": "Test Brute", "combat": 80, "max_combat": 0,
		"leadership": 10, "spy_skill": 0, "hp": -1, "item_id": 0, "item_para": 0, "hero_id": 0, "spy_of": 0, "spy_loyalty": 0, "stay": 12, "cost": 300})
	inn.heroes.append({"sprite": Defs.unit_sprite(p.race, "INF"), "race": p.race, "name": "Test Thinker", "combat": 30, "max_combat": 0,
		"leadership": 60, "spy_skill": 0, "hp": -1, "item_id": 0, "item_para": 0, "hero_id": 0, "spy_of": 0, "spy_loyalty": 0, "stay": 12, "cost": 300})
	inn.inn_policy = Inn.Policy.SOLDIERS
	Inn.run_policy(inn)
	var brute: Array = g.units.filter(func(u): return u.unit_name == "Test Brute")
	_check(brute.size() == 1 and brute[0].order_firm == fort and brute[0].order == Unit.Order.ENTER, "the soldiers policy hires a fighter and sends him to the fort")
	_check(inn.heroes.size() == 1 and inn.heroes[0]["name"] == "Test Thinker", "and leaves the thinker")
	inn.inn_policy = Inn.Policy.GENERALS
	var camp := g.spawn_firm("CAMP", p.id, p.race, g._place_near(home.footprint(), 4, 4, 12, [home.center_loc()]), true)
	Inn.run_policy(inn)
	var thinker: Array = g.units.filter(func(u): return u.unit_name == "Test Thinker")
	_check(thinker.size() == 1 and thinker[0].rank == Defs.Rank.GENERAL and thinker[0].order_firm == camp, "the generals policy sends a leader to command the empty camp")
	p.cash = Inn.POLICY_RESERVE + 100.0
	inn.heroes.append({"sprite": Defs.unit_sprite(p.race, "SPU"), "race": p.race, "name": "Test Dear", "combat": 80, "max_combat": 0,
		"leadership": 10, "spy_skill": 0, "hp": -1, "item_id": 0, "item_para": 0, "hero_id": 0, "spy_of": 0, "spy_loyalty": 0, "stay": 12, "cost": 300})
	inn.inn_policy = Inn.Policy.BOTH
	Inn.run_policy(inn)
	_check(inn.heroes.size() == 1, "the reserve is kept: nobody hired below %d gold" % int(Inn.POLICY_RESERVE))
	p.cash = 50000.0
	# the price limit (right-click: 600, 800, 1000) and never a spy
	inn.heroes.clear()
	inn.heroes.append({"sprite": Defs.unit_sprite(p.race, "SPU"), "race": p.race, "name": "Test Costly", "combat": 90, "max_combat": 0,
		"leadership": 10, "spy_skill": 0, "hp": -1, "item_id": 0, "item_para": 0, "hero_id": 0, "spy_of": 0, "spy_loyalty": 0, "stay": 12, "cost": 700})
	inn.heroes.append({"sprite": Defs.unit_sprite(p.race, "SPU"), "race": p.race, "name": "Test Sneak", "combat": 80, "max_combat": 0,
		"leadership": 10, "spy_skill": 60, "hp": -1, "item_id": 0, "item_para": 0, "hero_id": 0, "spy_of": 0, "spy_loyalty": 0, "stay": 12, "cost": 300})
	inn.inn_policy = Inn.Policy.SOLDIERS
	inn.inn_max_price = 600
	_check(Inn.next_price_cap(600) == 800 and Inn.next_price_cap(800) == 1000 and Inn.next_price_cap(1000) == 600, "the price limit cycles 600, 800, 1000")
	Inn.run_policy(inn)
	_check(inn.heroes.size() == 2, "nobody dearer than the limit is hired (%d left)" % inn.heroes.size())
	inn.inn_max_price = 800
	Inn.run_policy(inn)
	_check(inn.heroes.size() == 1 and inn.heroes[0]["name"] == "Test Sneak", "under 800 the fighter of %d is hired, the spy never" % Inn.price(inn, 0, p.id) if inn.heroes.size() > 0 else "")
	inn.heroes.clear()
	inn.inn_policy = Inn.Policy.OFF

	# --- a spy passing for an independent slips in among the guests
	_check(Espionage.cloak_choices(spu).has(0), "a spy can pass for an independent")
	spu.cloak_id = Espionage.INDEPENDENT_CLOAK
	_check(spu.seen_nation() == 0, "and is then seen as one")
	if spu.is_civilian():
		spu.combat = 30.0
	var sneaked := Inn.can_accept(inn, spu) and Inn.assign_unit(inn, spu)
	_check(sneaked or spu.is_civilian(), "a military spy disguised as an independent joins the guests")

	# --- behaviour modes and the Bheema
	var foe: Nation = g.nations.filter(func(n): return n.id != p.id)[0]
	var a := g.spawn_unit(Defs.unit_sprite(p.race, "INF"), p.id, g.free_unit_cell(Vector2i(home.center_loc()) + Vector2i(14, 0)), 40.0)
	var e := g.spawn_unit(Defs.unit_sprite("GREEK", "INF"), foe.id, g.free_unit_cell(Vector2i(home.center_loc()) + Vector2i(26, 0)), 40.0)
	g.declare_war(p.id, foe.id)
	_check(a.behavior_mode == Unit.Behavior.AGGRESSIVE and a.will_engage(e), "aggressive by default: takes on an enemy in sight")
	a.behavior_mode = Unit.Behavior.DEFENSIVE
	_check(not a.will_engage(e), "defensive: not one out of reach (%d cells, reach %d)" % [int(a.distance_to(e)), a.max_attack_range()])
	a.behavior_mode = Unit.Behavior.STAND_GROUND
	a.order = Unit.Order.MOVE
	a.on_attacked(e)
	_check(a.target != e, "standing ground, a moving unit does not turn on an attacker out of reach")
	a.behavior_mode = Unit.Behavior.AGGRESSIVE
	if Defs.unit_types.has("BEE") and Assets.has_sprite("BEE"):
		var bee := g.spawn_unit("BEE", p.id, g.free_unit_cell(Vector2i(home.center_loc()) + Vector2i(-14, 0)), 40.0)
		_check(bee.is_die_after_attack() and bee.behavior_mode == Unit.Behavior.DEFENSIVE, "a Bheema starts defensive")

	# --- squads: the general learns from his men's blows
	var gen := g.spawn_unit(Defs.unit_sprite(p.race, "INF"), p.id, g.free_unit_cell(a.cell()), 40.0)
	gen.rank = Defs.Rank.GENERAL
	gen.leadership = 50.0
	a.leader = gen
	var l0 := gen.leadership
	var c1 := a.combat
	a.gain_experience()
	_check(gen.leadership > l0 and a.combat > c1, "a blow raises the man's combat and his general's leadership (%.2f -> %.2f)" % [l0, gen.leadership])
	_check(a.leading_general() == gen, "a man near his general is led by him")

	# --- auto reward and auto retreat
	a.loyalty = 35.0
	a.auto_reward = 50
	c0 = p.cash
	a.auto_orders()
	_check(a.loyalty == 45.0 and is_equal_approx(c0 - p.cash, Unit.REWARD_COST), "below the level, the unit is rewarded (%.0f)" % a.loyalty)
	a.home_firm = fort
	a.auto_retreat = 30
	a.hp = a.max_hp * 0.2
	a.order = Unit.Order.IDLE
	a.auto_orders()
	_check(a.order == Unit.Order.ENTER and a.order_firm == fort, "below 30% of its hit points, the unit goes home")

	# --- disbanding and dropping a spy's identity
	var w0 := int(g.race_wanderers.get(p.race, 0))
	var dis := g.spawn_unit(Defs.unit_sprite(p.race, "INF"), p.id, g.free_unit_cell(Vector2i(home.center_loc()) + Vector2i(0, 12)), 30.0)
	dis.resign()
	_check(not g.units.has(dis) and int(g.race_wanderers.get(p.race, 0)) == w0 + 2, "a disbanded man adds two wanderers")
	var spy2 := g.spawn_unit(Defs.unit_sprite(p.race, "INF"), p.id, g.free_unit_cell(Vector2i(home.center_loc()) + Vector2i(2, 12)), 30.0)
	spy2.is_spy = true
	spy2.spy_skill = 40.0
	spy2.cloak_id = foe.id
	_check(not g.is_hostile(a, spy2), "our units leave our disguised spy alone")
	spy2.spy_notify = true
	_check(g.is_hostile(a, spy2), "unless he keeps up his cover")
	spy2.drop_spy_identity()
	_check(not spy2.is_spy and spy2.nation_id == foe.id, "dropping his identity, he is one of those he passed for")

	# --- links follow FirmInfo::is_linkable_to_firm
	var mine_site := g.sites.filter(func(s): return s.mine == null)
	var fac := g.spawn_firm("FACTORY", p.id, p.race, g._place_near(home.footprint(), 5, 5, 10, [home.center_loc()]), true)
	var mk := g.spawn_firm("MARKET", p.id, p.race, g._place_near(fac.footprint(), 4, 4, 6), true)
	g.update_links()
	_check(fac.linked_firms.has(mk) and not fac.linked_firms.has(fort) and not fort.linked_firms.has(camp), "a factory links to a market, not to forts; forts not to camps")

	# --- a factory's goods of another product still reach the market
	fac.raw = "Copper"
	fac.backup["Iron"] = [0.0, 50.0]
	var iron0 := float(mk.goods.get("Iron", 0.0))
	Economy._input_stored_products(mk, fac)
	_check(float(mk.goods.get("Iron", 0.0)) - iron0 > 0.0 and float(fac.backup["Iron"][1]) < 50.0, "goods stored before a switch go to the market too")

	# --- tax: the player waits for the penalty to wear off
	home.population = 40
	home.loyalty = 80.0
	if fort.overseer == null:
		fort.accept_unit(gen)
	g.update_links()
	home.tax_penalty = 0
	home.collect_tax_cmd()
	var l1 := home.loyalty
	home.collect_tax_cmd()
	_check(l1 == 70.0 and home.loyalty == l1, "a collection takes 10, and the next must wait (%.0f, %.0f)" % [l1, home.loyalty])
	_days(g, 11)
	home.loyalty = 80.0
	home.collect_tax_cmd()
	_check(home.loyalty == 70.0, "after the wait, 10 again")

	# --- a mega weapon is researchable only once its plans are found
	var mt := Defs.tech_def("M_CANNON")
	_check(not Defs.can_research(p, mt), "no mega weapon research without its plans")
	var row := -1
	var techs := Assets.table("TECH")
	for i in techs.size():
		if techs[i]["TECH"] == "M_CANNON":
			row = i + 1
	if row > 0:
		var tu := g.spawn_unit(Defs.unit_sprite(p.race, "INF"), p.id, g.free_unit_cell(Vector2i(home.center_loc()) + Vector2i(0, 14)), 30.0)
		var tr := g.spawn_treasure(Treasure.Kind.BLUEPRINT, row, 0, tu.cell())
		g._take(tr, tu)
		_check(p.mega_plans.has("M_CANNON") and p.tech_level("M_CANNON") == 0 and Defs.can_research(p, mt), "its plans found, it can be researched (not given)")

	# --- Fryhtans have loyalty (UnitClassInfo::has_loyalty); insects do not
	if Defs.unit_types.has("GITH") and Defs.unit_types.has("BEE"):
		var gk := g.spawn_unit("GITH", p.id, g.free_unit_cell(Vector2i(home.center_loc()) + Vector2i(-12, 0)), 30.0)
		var bz := g.spawn_unit("BEE", p.id, g.free_unit_cell(Vector2i(home.center_loc()) + Vector2i(-12, 2)), 30.0)
		_check(gk.has_loyalty() and not bz.has_loyalty(), "a Fryhtan has loyalty, a Bheema not")
		_check(gk.can_garrison(), "a Fryhtan can man a fort")

	# --- a spy's loyalty (Spy::update_loyalty, think_betray)
	var sp3 := g.spawn_unit(Defs.unit_sprite(p.race, "INF"), p.id, g.free_unit_cell(Vector2i(home.center_loc()) + Vector2i(4, 14)), 30.0)
	sp3.is_spy = true
	sp3.spy_skill = 40.0
	sp3.loyalty = 40.0
	Espionage.update_spy_loyalty(g, sp3)
	_check(sp3.loyalty == 41.0, "a spy's loyalty moves a point towards its target (%.0f)" % sp3.loyalty)
	sp3.cloak_id = foe.id
	sp3.loyalty = 10.0
	foe.reputation = 50.0
	_check(Espionage.spy_think_betray(g, sp3) and not sp3.is_spy and sp3.nation_id == foe.id, "a spy losing faith goes over to those he passes for")

	# --- a caravan's route (an addition): it passes the points between its stops
	var car := Caravans.hire(mk) if Caravans.can_hire(mk) > 0 else null
	if car:
		car.set_caravan_stop(0, mk)
		var other_mk := g.spawn_firm("MARKET", p.id, p.race, g._place_near(home.footprint(), 5, 5, 14, [home.center_loc()]), true)
		if other_mk and car.set_caravan_stop(1, other_mk):
			var rp := Vector2i(car.cell()) + Vector2i(3, 3)
			car.add_route_point(rp)
			car.dest_stop = 1
			Caravans._go(car, other_mk)
			_check(car.goal == rp or (not car.waypoints.is_empty() and car.path.size() > 0), "a caravan heads for its route point first (goal %s, point %s)" % [car.goal, rp])
			_check(not car.waypoints.is_empty(), "and then on to its stop")

	# --- a town being built can be cancelled; its settlers come out again
	var settler := g.spawn_unit(Defs.unit_sprite(p.race, "CIV"), p.id, g.free_unit_cell(Vector2i(home.center_loc()) + Vector2i(-16, 10)), 10.0)
	var tsite := Vector2i(-1, -1)
	for y in range(4, g.world.h - 10, 3):
		for x in range(4, g.world.w - 10, 3):
			if tsite.x < 0 and g.can_build_town(Vector2i(x, y)):
				tsite = Vector2i(x, y)
	if tsite.x >= 0:
		var nt := g.found_town(settler, tsite)
		if nt:
			var cash3 := p.cash
			var nu := g.units.size()
			nt.cancel_construction()
			_check(nt.dead and g.units.size() == nu + 1 and is_equal_approx(p.cash - cash3, Game.TOWN_BUILDING_COST / 2.0), "a town under construction is cancelled: its settler is back, half the cost refunded")

	# --- no building site on top of another place
	var fp2 := fort.footprint()
	_check(g.spawn_firm("MARKET", p.id, p.race, fp2.position + Vector2i(1, 1), false) == null, "a new site cannot go on top of a fort")

	# --- saves listed newest first
	SaveGame.save(g, "test_a")
	OS.delay_msec(1100)
	SaveGame.save(g, "test_b")
	var saves := SaveGame.list_saves()
	_check(saves.size() >= 2 and saves[0]["slot"] == "test_b", "saved games are listed newest first")
	DirAccess.remove_absolute(SaveGame.path_for("test_a"))
	DirAccess.remove_absolute(SaveGame.path_for("test_b"))

	# --- a building is paid for when its builder arrives (Unit::execute_build_firm)
	var civ := g.spawn_unit(Defs.unit_sprite(p.race, "CIV"), p.id, g.free_unit_cell(Vector2i(home.center_loc()) + Vector2i(0, -10)), 10.0)
	var mb := Assets.firm_build("MARKET", p.race)
	var site := Vector2i(-1, -1)
	for r in range(6, 40):
		for k in 64:
			var cand := Vector2i(civ.cell()) + Vector2i(int(cos(k * 0.1) * r), int(sin(k * 0.1) * r))
			if g.can_build_firm("MARKET", cand, mb.get("loc_w", 4), mb.get("loc_h", 4)):
				site = cand
				break
		if site.x >= 0:
			break
	var c2 := p.cash
	var nf := g.firms.size()
	g.cmd_place_building(p.id, "MARKET", p.race, site, civ, 100.0, 0.0, "")
	_check(is_equal_approx(p.cash, c2) and g.firms.size() == nf and not civ.build_plan.is_empty(), "nothing is paid or laid out while the builder walks")
	var paid0 := p.cash
	for k in 60:
		var before := p.cash
		_days(g, 1)
		if g.firms.size() > nf:
			paid0 = before
			break
	_check(g.firms.size() == nf + 1 and float(p.expense_by.get("Construction", 0.0)) >= 100.0, "on his arrival the site is laid out and paid for (%d gold)" % int(p.expense_by.get("Construction", 0.0)))
	_check(not g.can_build_town(Vector2i(home.x1 + Defs.TOWN_SIZE + 1, home.y1)), "no town hard by another (the free band)")

	# --- a computer kingdom gathers a small lone town into a bigger one, by wagon
	var ai := NationAI.new(p, g)
	var lone_at := Vector2i(-1, -1)
	for k in 400:
		var cand := Vector2i(g.rng.randi_range(5, g.world.w - 15), g.rng.randi_range(5, g.world.h - 15))
		if g.can_build_town(cand) and cand.distance_to(Vector2i(home.center_loc())) > 30.0:
			lone_at = cand
			break
	var lone := g.spawn_town(p.race, p.id, lone_at, 8)
	lone.setup_day = g.day - 200
	home.population = maxi(home.population, 30)
	_check(not lone.linked_towns().any(func(o): return o.nation_id == p.id) and AITown.think_merge_small_town(ai, lone), "a lone town of 8, with no mine, packs up for a bigger town")
	_check(ai.find_action(Vector2i(home.x1, home.y1), Vector2i(lone.x1, lone.y1), NationAI.SETTLE_TOWN, 0) != null, "the settle action is on the list")
	lone.population = 25
	_check(not AITown.think_merge_small_town(ai, lone), "a town of 20 or more stays")

	# --- desertion: below 30 a unit in the field may leave; at 0 it surely goes
	var des := g.spawn_unit(Defs.unit_sprite(p.race, "INF"), p.id, g.free_unit_cell(Vector2i(home.center_loc()) + Vector2i(6, 6)), 30.0)
	des.loyalty = 0.0
	Espionage.think_betray(g, des)
	_check(des.dead or des.nation_id != p.id or not g.units.has(des), "a unit at loyalty 0 leaves (or goes over)")
	var leftn := 0
	var contact_saved: Dictionary = p.contact.duplicate()
	p.contact.clear()       # nobody to go over to: only desertion
	for k in 40:
		var d2 := g.spawn_unit(Defs.unit_sprite(p.race, "INF"), p.id, g.free_unit_cell(Vector2i(home.center_loc()) + Vector2i(6, 6)), 30.0)
		d2.loyalty = 20.0
		Espionage.think_betray(g, d2)
		if not g.units.has(d2) or d2.nation_id != p.id:
			leftn += 1
		elif not d2.dead:
			g.remove_unit(d2)
	_check(leftn > 3 and leftn < 30, "at 20 about a third desert in a check (%d of 40)" % leftn)
	p.contact = contact_saved

	# --- migration between linked towns (Town::draw_detect_link_line, move_pop)
	var nb_at := Vector2i(-1, -1)
	for k in 2000:
		var cand := Vector2i(home.x1 + g.rng.randi_range(-12, 12), home.y1 + g.rng.randi_range(-12, 12))
		var cc := Vector2(cand) + Vector2(Defs.TOWN_SIZE, Defs.TOWN_SIZE) * 0.5
		if g.world.can_place(cand.x, cand.y, Defs.TOWN_SIZE, Defs.TOWN_SIZE) and Game._center_dist(cc, home.center_loc()) <= Defs.effective_distance("", ""):
			nb_at = cand
			break
	_check(nb_at.x >= 0, "a place for a neighbouring town")
	if nb_at.x >= 0:
		var nb := g.spawn_town(p.race, p.id, nb_at, 5)
		home.population = 40
		g.select_only(home)
		_check(nb in home.linked_towns() and nb.migrate_source() == home, "the selected town's neighbour shows the migrate icon")
		_check(home.migrate_source() == null, "the selected town itself shows none")
		var h0 := home.population
		home.cmd_migrate(nb, 1)
		_check(home.population == h0 - 1 and nb.population == 6, "a click moves one villager (%d -> %d)" % [h0, home.population])
		home.cmd_migrate(nb, Defs.MAX_WAGON_POPULATION)
		_check(nb.population == 16 and home.population == h0 - 11, "a right click moves a wagonload of ten (%d)" % nb.population)
		# with nobody jobless a worker moves home and keeps his job when in reach
		var wf: Firm = null
		for f in home.linked_firms:
			if f.is_work_firm() and Game._center_dist(f.center_loc(), nb.center_loc()) <= Defs.effective_distance(f.code, ""):
				wf = f
				break
		if wf != null:
			home.population = home.employed if home.employed > 0 else home.population
			if home.employed == 0:
				wf.worker_towns.append(home)
				home.employed = 1
				home.population = 1
			var wk0 := wf.workers()
			var e0 := nb.employed
			home.migrate_to(nb)
			_check(wf.workers() == wk0 and nb.employed == e0 + 1, "an employed man moves and keeps his job")
		g.deselect(home)
		_check(nb.migrate_source() == null, "no icon once the town is deselected")

	# --- the terrain type and the player's colour (Config::terrain_set, player_nation_color)
	var plants1 := Assets.plant_bitmaps.size()
	var g2 := Game.new()
	add_child(g2)
	g2.start({"seed": 3, "size": 80, "race": "NORMAN", "ai_count": 2, "fryhtan_count": 0, "lairs": 0, "terrain_set": 2, "color": 3})
	_check(Assets.terrain_set == 2 and not Assets.plant_bitmaps.is_empty() and not Assets.load_rocks().is_empty(), "badlands: their own plants (%d, fertile %d) and rocks" % [Assets.plant_bitmaps.size(), plants1])
	_check(g2.weather.avg_temp == 26 and g2.weather.temp_amp == 5, "and a hotter climate at latitude 20 (%d, swing %d)" % [g2.weather.avg_temp, g2.weather.temp_amp])
	_check(g2.player().color == Defs.NATION_COLORS[3], "the player's chosen colour")
	var cols2 := {}
	for n2 in g2.nations:
		cols2[n2.color.to_html()] = true
	_check(cols2.size() == g2.nations.size(), "every kingdom a colour of its own")
	g2.queue_free()
	var g3 := Game.new()
	add_child(g3)
	g3.start({"seed": 3, "size": 60, "race": "NORMAN", "ai_count": 1, "fryhtan_count": 0, "lairs": 0})
	_check(Assets.terrain_set == 1 and g3.weather.avg_temp == 15, "a new game is fertile again, at latitude 45 (%d)" % g3.weather.avg_temp)
	g3.queue_free()
	Game.inst = g

	print("RESULT: ", "PASS" if fails == 0 else "FAIL")
	get_tree().quit()
