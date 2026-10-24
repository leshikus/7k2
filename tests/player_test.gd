extends Node
## Scripted player actions through the same calls the UI uses.
func _ready() -> void:
	if Assets.load_install() != "":
		get_tree().quit(1); return
	var g := Game.new()
	add_child(g)
	g.start({"seed": 11, "size": 100, "race": "NORMAN", "ai_count": 1, "fryhtan_count": 0, "reveal": true, "lairs": 0})   # no Fryhtan raids: this is about the economy
	g.make_peace(1, 2)
	var p := g.player()
	var ok := true
	g.message.connect(func(t, _l): print("  msg: ", t))
	# --- the player's general builds a camp next to the nearest independent town
	var home: Town = g.towns.filter(func(t): return t.nation_id == p.id)[0]
	var indep: Array = g.towns.filter(func(t): return t.nation_id == 0)
	indep.sort_custom(func(a, b): return a.center_loc().distance_to(home.center_loc()) < b.center_loc().distance_to(home.center_loc()))
	var target: Town = indep[0]
	var gen: Unit = g.units.filter(func(u): return u.nation_id == p.id and u.rank == Defs.Rank.GENERAL)[0]
	gen.leadership = 80
	var b := Assets.firm_build("CAMP", p.race)
	var pos := g._place_near(target.footprint(), b["loc_w"], b["loc_h"], 6)
	var camp := g.spawn_firm("CAMP", p.id, p.race, pos, false)
	p.add_cash(-60)
	gen.order_build(camp)
	print("target town ", target.town_name, " race=", target.race, " resistance=", int(target.resistance_to(p.id)), " dist=", target.center_loc().distance_to(home.center_loc()))
	# --- a soldier builds a mine on the deposit near home, then factory and market
	var site: Site = null
	for s in g.sites:
		if Game._center_dist(s.center_loc(), home.center_loc()) <= Defs.EFFECTIVE_FIRM_TOWN_DISTANCE:
			site = s
	var soldiers: Array = g.units.filter(func(u): return u.nation_id == p.id and u.rank == Defs.Rank.SOLDIER and u.inside_firm == null)
	var mine := g.spawn_firm("MINE", p.id, p.race, Vector2i(site.x1, site.y1), false) if site else null
	if mine: soldiers[0].order_build(mine)
	for d in 120: _day(g)
	print("day 120: camp built=", not camp.under_construction, " overseer=", camp.overseer != null, " mine built=", mine and not mine.under_construction, " mine workers=", mine.workers() if mine else -1)
	# by the town or by the mine (the town may lie near the map's edge)
	var fat := g._place_near(home.footprint(), 5, 5, 14, [mine.center_loc(), home.center_loc()])
	if fat.x < 0:
		fat = g._place_near(mine.footprint(), 5, 5, 14, [mine.center_loc(), home.center_loc()])
	var fac := g.spawn_firm("FACTORY", p.id, p.race, fat, false)
	soldiers[0].order_build(fac)
	var mat := g._place_near(home.footprint(), 5, 5, 14, [fac.center_loc(), home.center_loc()])
	if mat.x < 0:
		mat = g._place_near(fac.footprint(), 5, 5, 14, [fac.center_loc(), home.center_loc()])
	var mkt := g.spawn_firm("MARKET", p.id, p.race, mat, false)
	soldiers[1].order_build(mkt)
	var cash0 := p.cash
	for d in 900:
		_day(g)
		# cross-race towns need grants as well as a camp, as in the original
		if d % 20 == 0 and target.nation_id == 0 and target.has_linked_camp(p.id): target.grant(p.id)
		if target.nation_id == p.id: break
	print("town ", target.town_name, " owner=", target.nation_id, " resistance=", int(target.resistance_to(p.id)), " target=", target.target_resistance)
	if target.nation_id != p.id:
		print("FAIL: independent town did not join"); ok = false
	for d in 300: _day(g)
	print("factory raw=", fac.raw, " raw_stock=", int(fac.raw_stock), " stock=", int(fac.stock), " workers=", fac.workers(), " | market goods=", mkt.goods, " sales=", int(mkt.market_sales), " linked towns=", mkt.linked_towns.size())
	if mkt.market_sales <= 0: print("FAIL: market sold nothing"); ok = false
	# --- special unit training centre
	var st := g.spawn_firm("STABLE", p.id, p.race, g._place_near(home.footprint(), 6, 6, 8, [home.center_loc()]), true)
	g.update_links()
	var spu := st.special_unit()
	var before_spu := g.units.filter(func(u): return u.sprite_code == spu and u.nation_id == p.id).size()
	home.loyalty = 80.0
	# FirmTrain: volunteers train inside and walk out to the rally point when done
	st.set_rally(st.door() + Vector2i(3, 3))
	Training.order_train(st, Training.SPECIAL)
	Training.order_train(st, Training.SPECIAL)
	print("trainees ", st.trainees.size())
	for d in 200: _day(g)
	var after_spu := g.units.filter(func(u): return u.sprite_code == spu and u.nation_id == p.id).size()
	print("training centre '", st.display_name(), "' trained ", after_spu - before_spu, " x ", Defs.unit_types[spu]["name"])
	if after_spu - before_spu < 2: print("FAIL: special units not trained"); ok = false

	# --- army attacks a lair placed for the test
	var lair: Firm = g.spawn_firm("LAIR", GameObj.MONSTER_NATION, "LYW", g._place_near(home.footprint(), 6, 6, 8), true)
	lair.monster_code = "LYW"
	for i in 4:
		lair.accept_unit(g.spawn_unit("LYW", GameObj.MONSTER_NATION, Vector2i(lair.x1, lair.y1 + 6), 30.0))
	for f in g.firms:
		pass
	var army: Array = []
	for i in 12:
		var u := g.spawn_unit(Defs.unit_sprite(p.race, "INF"), p.id, Vector2i(home.center_loc()) + Vector2i(0, 5), 60.0)
		army.append(u)
	for u in army: u.order_attack(lair)
	for d in 400:
		_day(g)
		if d % 10 == 0:
			var mons := g.units.filter(func(u): return u.is_monster() and not u.dead and u.center_loc().distance_to(lair.center_loc()) < 20)
			var alive := army.filter(func(u): return not u.dead)
			var orders := {}
			for u in alive: orders[u.order] = orders.get(u.order, 0) + 1
			print("  d", d, " lair hp=", int(lair.hp), " inside=", lair.soldiers.size(), " monsters out=", mons.size(), " ", mons.map(func(m): return "%s:%d" % [m.sprite_code, int(m.hp)]), " army=", alive.size(), " hp=", alive.map(func(u): return int(u.hp)), " orders=", orders, " targets=", alive.map(func(u): return "U" if u.target is Unit else ("F" if u.target else "-")))
		if lair.dead or army.all(func(u): return u.dead): break
	if not lair.dead: print("FAIL: lair survived"); ok = false
	print("lair destroyed=", lair.dead, " army left=", army.filter(func(u): return not u.dead).size(), " cash=", int(p.cash))
	print("RESULT: ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 2)

func _day(g: Game) -> void:
	for f in Defs.FRAMES_PER_DAY: g.sim_frame()
