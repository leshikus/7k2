extends Node
## Caravans move goods between markets; foreign deliveries earn both sides money.
func _ready() -> void:
	Assets.load_install()
	var g := Game.new()
	add_child(g)
	g.start({"seed": 8, "size": 100, "race": "NORMAN", "ai_count": 1, "fryhtan_count": 0, "lairs": 0, "reveal": true})
	g.make_peace(1, 2)
	var ok := true
	var hm := g.towns.filter(func(t): return t.nation_id == 1)[0] as Town
	var m0 := g.spawn_firm("MARKET", 2, g.nation(2).race, g._place_near(g.towns.filter(func(t): return t.nation_id == 2)[0].footprint(), 5, 5, 8), true)
	var mm := g.spawn_firm("MARKET", 1, "NORMAN", g._place_near(hm.footprint(), 5, 5, 8), true)
	g.update_links()
	var none := g.find_trade_partner(mm, 1)
	print("without a trade treaty, partner: ", none.display_name() if none else "none")
	ok = ok and none == null
	mm.die(null)
	m0.die(null)
	Diplomacy.set_trade(g, 1, 2, true)
	var p := g.player()
	var home: Town = g.towns.filter(func(t): return t.nation_id == 1)[0]
	var foe_town: Town = g.towns.filter(func(t): return t.nation_id == 2)[0]
	var m1 := g.spawn_firm("MARKET", 1, "NORMAN", g._place_near(home.footprint(), 5, 5, 8), true)
	var m2 := g.spawn_firm("MARKET", 2, g.nation(2).race, g._place_near(foe_town.footprint(), 5, 5, 8), true)
	m1.goods["Iron"] = 400.0
	g.update_links()
	var partner := g.find_trade_partner(m1, 1)
	print("partner: ", partner.display_name() if partner else "none", " of nation ", partner.nation_id if partner else -1, " distance ", m1.center_loc().distance_to(m2.center_loc()))
	var cash1 := p.cash
	var cash2 := g.nation(2).cash
	var c := m1.hire_caravan()
	ok = ok and c != null
	var delivered := false
	for d in 400:
		for f in Defs.FRAMES_PER_DAY: g.sim_frame()
		if m2.goods.get("Iron", 0.0) > 0.0 and not delivered:
			delivered = true
			print("day ", d, ": caravan delivered ", int(m2.goods["Iron"]), " Iron goods to the foreign market")
	print("cargo now ", c.cargo, " leg ", c.caravan_leg)
	print("player cash change (incl. upkeep) ", int(p.cash - cash1), "; partner trade income visible: ", g.nation(2).income_year > 0)
	ok = ok and delivered
	# the player's choices: destination, goods, a clone on the same route
	p.cash = 5000.0
	var m3 := g.spawn_firm("MARKET", 1, "NORMAN", g._place_near(home.footprint(), 5, 5, 14), true)
	g.update_links()
	var set_ok := c.set_caravan_dest(m3) if m3 else false
	print("own second market as destination: ", set_ok)
	ok = ok and set_ok and c.caravan_dest == m3
	Diplomacy.set_trade(g, 1, 2, false)
	var refused := not c.set_caravan_dest(m2)
	print("foreign market refused without a treaty: ", refused)
	ok = ok and refused
	c.toggle_pick_up("Iron")
	var c2 := c.duplicate_caravan()
	var cloned := c2 != null and c2.caravan_dest == m3 and c2.pick_up == ["Iron"] and c2.caravan_home == m1
	print("clone on the same route with the same goods: ", cloned)
	ok = ok and cloned
	c.toggle_pick_up("Iron")
	ok = ok and c.pick_up.is_empty()
	print("RESULT: ", "PASS" if ok else "FAIL")
	get_tree().quit()
