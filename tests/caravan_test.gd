extends Node
## Caravans (ou_cara.cpp): two stops, pick-ups per stop, buying abroad and
## bringing goods home, mines and factories as stops, the hiring limit, clones,
## save/load; and the goods chain they feed (Economy).
var fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


func _days(g: Game, n: int) -> void:
	for d in n:
		for f in Defs.FRAMES_PER_DAY:
			g.sim_frame()


func _ready() -> void:
	Assets.load_install()
	var g := Game.new()
	add_child(g)
	g.start({"seed": 8, "size": 100, "race": "NORMAN", "ai_count": 1, "fryhtan_count": 0, "lairs": 0, "reveal": true})
	for n in g.nations:
		n.ai = null
	g.make_peace(1, 2)
	var p := g.player()
	var foe := g.nation(2)
	p.cash = 20000.0
	foe.cash = 5000.0
	var home: Town = g.towns.filter(func(t): return t.nation_id == 1)[0]
	home.population = 60
	var foe_town: Town = g.towns.filter(func(t): return t.nation_id == 2)[0]
	var m1 := g.spawn_firm("MARKET", 1, "NORMAN", g._place_near(home.footprint(), 5, 5, 8), true)
	var m2 := g.spawn_firm("MARKET", 2, foe.race, g._place_near(foe_town.footprint(), 5, 5, 8), true)
	g.update_links()
	var raw: String = Economy.raw_types()[0]

	# --- hiring: free, one for every ten people, the market as its first stop
	var cash0 := p.cash
	var c := m1.hire_caravan()
	_check(c != null and is_equal_approx(p.cash, cash0) and c.stops.size() == 1 and c.stops[0]["firm"] == m1 and c.stops[0]["pick"] == "auto",
		"a caravan is hired free with the market as its first stop, picking up automatically")
	_check(Caravans.can_hire(m1) == maxi(1, home.population / 10) - 1, "the kingdom may keep one for every ten people (%d more)" % Caravans.can_hire(m1))

	# --- a foreign market needs a trade treaty
	_check(not c.set_caravan_stop(1, m2), "no stop at a foreign market without a trade treaty")
	Diplomacy.set_trade(g, 1, 2, true)
	_check(c.set_caravan_stop(1, m2), "with a treaty the foreign market becomes its second stop")

	# --- it buys abroad and brings the goods home; unloading abroad does not happen
	m2.goods[raw] = 400.0
	m1.goods.clear()
	var foe_cash := foe.cash
	var home_got := false
	# a caravan moves two pixels a frame: a long way takes months
	for d in 600:
		_days(g, 1)
		if float(m1.goods.get(raw, 0.0)) > 0.0:
			home_got = true
			break
	_check(home_got, "goods bought at the foreign market are unloaded at home (%d)" % int(m1.goods.get(raw, 0.0)))
	_check(float(m2.goods.get(raw, 0.0)) <= 200.0 + 0.01, "it took up to 200, a caravan's load, of what was above 100 there (%d left)" % int(m2.goods.get(raw, 0.0)))
	_check(foe.cash > foe_cash and float(p.import_year.get(2, 0.0)) > 0.0, "the purchase is paid to the seller and counted as imports")

	# --- pick-ups: none, then a chosen kind
	c.set_caravan_pick_up(1, "none")
	_check(c.stops[1]["pick"] == "none", "pick up nothing at a stop")
	c.set_caravan_pick_up(1, "P:" + raw)
	_check(c.stops[1]["pick"] == "sel" and ("P:" + raw) in c.stops[1]["picks"] and not c.market_auto, "or the chosen goods (the caravan's markets turn to manual)")

	# --- a mine and a factory of its own as stops
	var site: Site = g.sites[0]
	var mine := g.spawn_firm("MINE", 1, "NORMAN", Vector2i(site.x1, site.y1), true)
	mine.site = site
	mine.raw = site.raw
	site.mine = mine
	mine.stock = 300.0
	var fac := g.spawn_firm("FACTORY", 1, "NORMAN", g._place_near(mine.footprint(), 5, 5, 8), true)
	g.update_links()
	var c2 := m1.hire_caravan()
	_check(c2 != null and c2.set_caravan_stop(0, mine) and c2.set_caravan_stop(1, fac), "stops at its own mine and factory")
	_check(c2.stops[0]["pick"] == "sel" and c2.stops[0]["picks"] == ["R:" + mine.raw], "at a mine it picks up the raw material")
	var fac_raw0 := fac.raw_stock
	for d in 120:
		_days(g, 1)
		if fac.raw_stock > fac_raw0 + 1.0 and fac.raw == mine.raw:
			break
	_check(fac.raw == mine.raw and fac.raw_stock > fac_raw0, "the caravan carries %s to the factory, which takes it up (%d)" % [mine.raw, int(fac.raw_stock)])

	# --- clone
	var c3 := c2.duplicate_caravan()
	_check(c3 != null and c3.stops.size() == 2 and c3.stops[0]["firm"] == mine and c3.stops[1]["firm"] == fac, "a clone has the same stops")

	# --- saved and loaded
	SaveGame.save(g, "test_caravan")
	var g2 := Game.new()
	add_child(g2)
	_check(SaveGame.load_into(g2, "test_caravan") == "", "the game loads")
	DirAccess.remove_absolute(SaveGame.path_for("test_caravan"))
	var cs := g2.units.filter(func(u): return u.is_caravan and u.stops.size() == 2)
	_check(cs.size() >= 2 and cs.all(func(u): return u.stops.all(func(st): return st["firm"] is Firm)), "caravans keep their stops in a saved game")

	# --- a caravan dies with the building it is in
	var inside := g.units.filter(func(u): return u.is_caravan and u.journey == "inside" and not u.dead)
	if not inside.is_empty():
		var cu: Unit = inside[0]
		var where: Firm = cu.stops[cu.dest_stop]["firm"]
		where.die(null)
		for f in 3:
			g.sim_frame()
		_check(cu.dead, "a caravan inside a building that falls dies with it")
	print("RESULT: ", "PASS" if fails == 0 else "FAIL")
	get_tree().quit(0 if fails == 0 else 2)
