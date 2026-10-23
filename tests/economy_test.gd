extends Node
## The economy (of_work.cpp, of_mine.cpp, of_fact.cpp, of_mark.cpp, otown.cpp,
## ofirmlnk.cpp, oun_proc.cpp): links and their switches, workers hired and
## paid, the goods chain from mine to market, the towns' demand and sales,
## and the upkeep of men in the field.
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
	g.start({"seed": 21, "size": 100, "race": "NORMAN", "ai_count": 1, "fryhtan_count": 0, "lairs": 0, "reveal": true})
	for n in g.nations:
		n.ai = null
	var p := g.player()
	p.cash = 20000.0
	p.food = 5000.0
	var home: Town = g.towns.filter(func(t): return t.nation_id == p.id)[0]
	home.population = 60
	home.loyalty = 80.0
	# a mine on the nearest deposit, a factory and a market beside it
	var site: Site = null
	for s in g.sites:
		if site == null or Vector2(s.x1, s.y1).distance_to(home.center_loc()) < Vector2(site.x1, site.y1).distance_to(home.center_loc()):
			site = s
	var mine := g.spawn_firm("MINE", p.id, "NORMAN", Vector2i(site.x1, site.y1), true)
	mine.site = site
	mine.raw = site.raw
	mine.reserve = site.reserve
	site.mine = mine
	var fac := g.spawn_firm("FACTORY", p.id, "NORMAN", g._place_near(mine.footprint(), 5, 5, 8, [home.center_loc()]), true)
	var mkt := g.spawn_firm("MARKET", p.id, "NORMAN", g._place_near(fac.footprint(), 5, 5, 6, [home.center_loc()]), true)
	g.update_links()

	# --- links: mine-factory and factory-market on, mine-market off
	_check(g.link_on(mine, fac) and g.link_on(fac, mkt), "mines feed factories and factories markets by default")
	_check(not mkt in mine.linked_firms or not g.link_on(mine, mkt), "a mine does not feed a market unless told to")
	_check(g.link_on(mine, home) and g.link_on(mkt, home), "an own town is linked both ways")

	# --- workers: one every 5 days up to the wanted ten, paid 5 a year each
	_check(mine.needed_workers == 10 and mine.workers() == 0, "a mine wants ten workers, and starts with none")
	_days(g, 26)
	_check(mine.workers() >= 4 and mine.workers() <= 6, "after 26 days it has hired about five (%d)" % mine.workers())
	_check(home.employed == mine.workers() + fac.workers(), "the town counts its workers (%d)" % home.employed)
	_days(g, 40)
	_check(mine.workers() == 10, "then its ten (%d)" % mine.workers())
	mine.set_needed_workers(3)
	_check(mine.workers() == 3, "wanting fewer sends the others home")
	mine.set_needed_workers(10)
	var wages := float(p.expense_by.get("Workers", 0.0))
	_check(wages > 0.0, "workers are paid (%.1f so far)" % wages)

	# --- the goods chain
	_days(g, 60)
	print("mine stock %d, factory raw %d goods %d made %d, market goods %s demand %s" % [int(mine.stock), int(fac.raw_stock), int(fac.stock), int(fac.last_month_output + fac.month_output), mkt.goods, mkt.demand])
	_check(fac.raw == mine.raw, "the factory takes up the mine's material (%s)" % fac.raw)
	_check(float(mkt.goods.get(mine.raw, 0.0)) > 0.0 or mkt.market_sales > 0.0, "goods reach the market")
	_check(float(mkt.demand.get(mine.raw, 0.0)) > 0.0, "the town wants them (monthly demand %d)" % int(mkt.demand.get(mine.raw, 0.0)))
	_check(mkt.market_sales > 0.0, "and buys them (%d gold)" % int(mkt.market_sales))
	var expect := home.jobless() * Economy.PEASANT_GOODS_MONTH_DEMAND + home.employed * Economy.WORKER_GOODS_MONTH_DEMAND
	Economy.distribute_demand(g)
	var supply := float(mkt.goods.get(mine.raw, 0.0))
	var dm := float(mkt.demand.get(mine.raw, 0.0))
	_check(is_equal_approx(dm, maxf(expect, supply) if supply < expect else expect),
		"demand: half a unit a month a peasant, one a worker (%.1f, formula %.1f)" % [dm, expect])

	# --- factory products and their stocks
	var prod := fac.raw
	var rs := fac.raw_stock
	Economy.change_production(fac)
	_check(fac.raw != prod and fac.raw_stock == 0.0, "changing the product starts the other from nothing")
	Economy.set_production(fac, prod)
	_check(fac.raw == prod and is_equal_approx(fac.raw_stock, rs), "and switching back finds the old stocks")

	# --- a shrinking town takes workers back
	var emp := home.employed
	home.population = maxi(1, emp - 4)
	g._update_workers()
	_check(home.employed <= home.population, "when the town shrinks its workers come home (%d employed of %d)" % [home.employed, home.population])
	home.population = 60

	# --- links across kingdoms need both ends
	var foe := g.nation(2)
	var ftown: Town = g.towns.filter(func(t): return t.nation_id == foe.id)[0]
	var fm := g.spawn_firm("MARKET", foe.id, foe.race, g._place_near(mine.footprint(), 5, 5, 10), true)
	g.update_links()
	if fm in mine.linked_firms:
		_check(not g.link_on(mine, fm), "a link to another kingdom's building starts off")
		g.set_link(mine, fm, true)
		_check(g.link_side(mine, fm) and not g.link_on(mine, fm), "switched on at one end only, it stays off")
		g.set_link(fm, mine, true)
		_check(g.link_on(mine, fm), "and works once both agree")

	# --- independent towns work for a kingdom whose resistance is low
	var indep: Town = null
	for t in g.towns:
		if t.nation_id == 0 and mine in t.linked_firms:
			indep = t
	if indep:
		indep.resistance[p.id] = 90.0
		g.link_state.erase(g._link_key(mine, indep)[0])
		_check(not g.link_on(mine, indep), "an independent town of high resistance will not work there")
		indep.resistance[p.id] = 40.0
		Independents.think_set_link(g, indep)
		_check(g.link_on(mine, indep), "with resistance at or below 50 its people may")

	# --- upkeep: men in the field are paid and fed
	var gen := g.spawn_unit(Defs.unit_sprite(p.race, "INF"), p.id, home.footprint().position + Vector2i(0, 8), 40.0)
	gen.rank = Defs.Rank.GENERAL
	var gpay := float(p.expense_by.get("Generals", 0.0))
	_days(g, 10)
	_check(float(p.expense_by.get("Generals", 0.0)) - gpay >= 50.0 * 10.0 / 365.0 - 0.01, "a general in the field earns 50 a year")
	p.food = -1000.0
	gen.loyalty = 80.0
	_days(g, 10)
	_check(gen.loyalty < 80.0, "with no food, loyalty falls (%d)" % int(gen.loyalty))
	print("RESULT: ", "PASS" if fails == 0 else "FAIL")
	get_tree().quit(0 if fails == 0 else 2)
