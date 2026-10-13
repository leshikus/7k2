extends Node
## Random events (oevent.cpp): each of the thirteen, and their schedule by the
## "random events" setting.

var ok := true


func check(cond: bool, what: String) -> void:
	print(("ok   " if cond else "FAIL ") + what)
	if not cond:
		ok = false


func days(g: Game, n: int) -> void:
	for d in n:
		for f in Defs.FRAMES_PER_DAY:
			g.sim_frame()


func _ready() -> void:
	if Assets.load_install() != "":
		get_tree().quit(1); return
	Defs.load_from_assets()
	var g := Game.new()
	add_child(g)
	g.start({"seed": 9, "size": 120, "race": "NORMAN", "ai_count": 2, "fryhtan_count": 1, "reveal": true})
	days(g, 30)
	var p := g.player()
	var town: Town = g.towns.filter(func(t): return t.nation_id == p.id)[0]
	# give the events something to work on in every kingdom
	for n in g.nations:
		n.food = 3000.0
	town.population = 40
	var res := g.spawn_firm("RESEARCH", p.id, "NORMAN", g._place_near(town.footprint(), 3, 3, 10), true)
	res.start_research("MINING")
	var lvl := p.tech_level("MINING")
	var r := RandomEvents.execute(g, "FINISH_TECH")
	check(r == "FINISH_TECH" and g.nations.any(func(n): return n.tech_level("MINING") > 0 or n.tech.size() > 0), "a research breakthrough")
	check(RandomEvents.execute(g, "NEW_TECH") == "NEW_TECH", "a lost scroll of technology")
	var food := {}
	for n in g.nations:
		food[n.id] = n.food
	check(RandomEvents.execute(g, "FOOD_DESTROYED") == "FOOD_DESTROYED" and g.nations.any(func(n): return n.food < food[n.id]), "rats eat a kingdom's food")
	var units0 := g.units.filter(func(u): return not u.dead).size()
	check(RandomEvents.execute(g, "UNIT_DIE") == "UNIT_DIE", "a soldier dies of plague")
	var generals := g.units.filter(func(u): return not u.dead and u.rank == Defs.Rank.GENERAL and u.nation_id > 0)
	check(RandomEvents.execute(g, "GENERAL_DIE") == ("GENERAL_DIE" if not generals.is_empty() else ""), "a general dies of plague (%d generals)" % generals.size())
	for f in g.firms:
		if Espionage.is_camp(f):
			for s in f.soldiers:
				s.hp = 1.0
	check(RandomEvents.execute(g, "SOLDIER_DIE") == "SOLDIER_DIE", "sickness in a fort")
	var before := g.units.size()
	check(RandomEvents.execute(g, "UNIT_JOIN") == "UNIT_JOIN" and g.units.size() == before + 1, "a stranger joins a kingdom")
	before = g.units.size()
	check(RandomEvents.execute(g, "WAGON_JOIN") == "WAGON_JOIN" and g.units.size() >= before + 8, "a wagon of 8-10 settlers joins")
	var joined: Unit = g.units[-1]
	check(joined.nation_id > 0 and (joined.cell().x <= 3 or joined.cell().y <= 3 or joined.cell().x >= g.world.w - 4 or joined.cell().y >= g.world.h - 4), "they arrive at the edge of the map")
	var tr := g.treasures.size()
	check(RandomEvents.execute(g, "ITEM_DISCOVER") == "ITEM_DISCOVER" and g.treasures.size() >= tr + 3, "a cache of artifacts near a town")
	var pop := {}
	for t in g.towns:
		pop[t] = t.population
	check(RandomEvents.execute(g, "TOWN_PEOPLE_KILLED") == "TOWN_PEOPLE_KILLED" and g.towns.any(func(t): return t.population <= pop[t] - 10), "a plague in a town kills 10 to 20")
	var inn := g.spawn_firm("INN", p.id, "NORMAN", g._place_near(town.footprint(), 3, 3, 12), true)
	check(RandomEvents.execute(g, "INN_DESTROYED") == "INN_DESTROYED" and g.firms.filter(func(f): return f.code in ["INN", "ANIMAL"] and not f.dead).size() < 1 + g.firms.filter(func(f): return f.code == "ANIMAL").size(), "an inn burns down")
	# the schedule: none never, high often
	var g2 := Game.new()
	add_child(g2)
	g2.start({"seed": 9, "size": 90, "race": "NORMAN", "ai_count": 2, "random_events": 0})
	for d in 1500:
		RandomEvents.next_day(g2)
	check(g2.event_days == -1, "no random events when they are off")
	g2.config["random_events"] = 3
	var fired := 0
	var last := -1
	for d in 2000:
		RandomEvents.next_day(g2)
		if g2.event_days > last + 1 and last >= 0:
			fired += 1
		last = g2.event_days
	check(fired >= 3, "high frequency: an event every few hundred days (%d in 2000 days)" % fired)
	print("RESULT: ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
