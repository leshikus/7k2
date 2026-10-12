extends Node
## Espionage: training, infiltration and dissent, disguise, counter-spies, bribery
## and capturing a fort, assassination, stealing technology, incidents, sleepers
## who walk out, the secret report, save/load and the computer's spies.
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
	g.start({"seed": 8, "size": 100, "race": "NORMAN", "ai_count": 2, "fryhtan_count": 0, "lairs": 0, "reveal": true})
	var me := g.player()
	var foe := g.nation(2)
	var third := g.nation(3)
	for n in g.nations:
		n.cash = 50000.0
		if n.ai:
			n.ai = null          # keep the computer from interfering until the AI part
	g.declare_war(1, 2)

	# --- training ---
	var home: Town = g.towns.filter(func(t): return t.nation_id == 1)[0]
	home.loyalty = 80.0
	var college := g.spawn_firm("SPY", 1, "NORMAN", g._place_near(home.footprint(), 5, 5, 8, [home.center_loc()]), true)
	g.update_links()
	college.weapon_queue = 1
	_days(g, 30)
	var spy: Unit = null
	for u in g.units:
		if u.is_spy: spy = u
	_check(spy != null, "a spy is trained at the Espionage College")
	if spy == null:
		_finish(); return

	# --- independent town: dissent lowers resistance ---
	var indep: Array = g.towns.filter(func(t): return t.nation_id == 0)
	indep.sort_custom(func(a, b): return a.center_loc().distance_to(home.center_loc()) < b.center_loc().distance_to(home.center_loc()))
	var t: Town = indep[0]
	t.resistance[1] = 90.0
	spy.spy_skill = 80.0
	_check(spy.order_infiltrate(t), "a spy may walk into an independent town")
	_days(g, 120)
	_check(spy.has_meta("hidden") and spy.spy_place == t, "the spy is inside %s" % t.town_name)
	_check(t.resistance_to(1) < 90.0, "sowing dissent lowers its resistance to us (90 -> %.1f)" % t.resistance_to(1))
	g.spy_leave(spy)

	# --- disguise ---
	var foe_town: Town = g.towns.filter(func(x): return x.nation_id == 2)[0]
	var fort := g.spawn_firm("FORT", 2, foe.race, g._place_near(foe_town.footprint(), 4, 4, 8), true)
	g.update_links()
	var gen := g.spawn_unit(Defs.unit_sprite(foe.race, "INF"), 2, fort.door(), 40.0)
	gen.rank = Defs.Rank.GENERAL
	gen.leadership = 30.0
	fort.accept_unit(gen)
	for i in 3:
		var s := g.spawn_unit(Defs.unit_sprite(foe.race, "INF"), 2, fort.door(), 20.0)
		fort.accept_unit(s)
	_check(fort.overseer == gen and fort.soldiers.size() == 3, "the enemy fort has a general and 3 soldiers")
	# out in the open, away from both kingdoms
	var open_cell := g.world.nearest_walkable(Vector2i(g.world.w / 2, g.world.h / 2))
	for u in g.units:
		if not u.inside_firm and not u.has_meta("hidden") and u != spy and u.center_loc().distance_to(Vector2(open_cell)) < 8.0:
			u.loc += Vector2(20, 20)
	spy.loc = Vector2(open_cell)
	spy.position = Iso.to_screen(spy.loc)
	var guard := g.spawn_unit(Defs.unit_sprite(foe.race, "INF"), 2, open_cell + Vector2i(1, 0), 30.0)
	g.sim_frame()
	_check(not Espionage.can_change_cloak(spy, 2), "no disguise change with an enemy beside the spy")
	_check(g.is_hostile(guard, spy), "an undisguised spy is an enemy")
	guard.loc = spy.loc + Vector2(30, 30)
	guard.position = Iso.to_screen(guard.loc)
	g.sim_frame()
	_check(Espionage.set_cloak(spy, 2), "with nobody near, the spy puts on the enemy's colours")
	_check(not g.is_hostile(guard, spy) and not g.is_hostile(spy, guard), "the enemy takes a disguised spy for one of its own")
	_check(spy.nation_color() == foe.color, "a disguised spy wears the enemy's colour")
	Espionage.set_cloak(spy, 1)
	_check(spy.cloak_id == 0, "back in his own colours")
	# infiltrating an enemy fort puts the disguise on automatically
	_check(spy.order_infiltrate(fort) and spy.cloak_id == 2, "ordered into the enemy fort, the spy disguises himself")
	for i in 60:
		_days(g, 1)
		if spy.has_meta("hidden"):
			break
	_check(spy.spy_place == fort and spy.has_meta("hidden"), "the spy is inside the enemy fort")

	# --- loyalty ---
	_days(g, 20)
	var tl := Espionage.soldier_target_loyalty(fort, fort.soldiers[0])
	_check(absf(fort.soldiers[0].loyalty - tl) < 70.0, "soldiers' loyalty moves toward its target (%d -> %d)" % [int(fort.soldiers[0].loyalty), int(tl)])

	# --- the secret report ---
	_check(not Espionage.can_view_secret(spy), "the secret report needs Information Theft")
	me.tech["STEALINF"] = 1
	_check(Espionage.can_view_secret(spy) and Espionage.secret_report(g, 2).contains("Treasury"), "with Information Theft the spy reads their treasury")

	# --- bribery and capture ---
	var s0: Unit = fort.soldiers[0]
	s0.loyalty = 20.0
	var ch := Espionage.bribe_chance(spy, fort, s0, 4000)
	_check(ch >= 100, "bribing a disloyal soldier with 4000 gold is sure (%d%%)" % ch)
	var cash0 := me.cash
	_check(Espionage.bribe(spy, fort, s0, 4000) and s0.sleeper_for == 1, "the soldier takes the bribe and secretly serves us")
	_check(is_equal_approx(me.cash, cash0 - 4000.0), "the bribe costs 4000 gold")
	_check(not Espionage.can_bribe(fort, g.nation(2).king, 1) if g.nation(2).king else true, "a king cannot be bribed")
	_check(Espionage.bribe_chance(spy, fort, s0, 4000) == 0, "a man who is already a spy cannot be bribed again")
	gen.loyalty = 10.0
	_check(Espionage.bribe(spy, fort, gen, 4000) and gen.sleeper_for == 1, "the general takes the bribe")
	_check(Espionage.can_capture(fort, 1), "with the general bought, the fort can be captured")
	_check(Espionage.capture(fort, 1) and fort.nation_id == 1 and gen.nation_id == 1 and gen.sleeper_for == 0, "the fort is ours and its general serves us openly")
	_check(fort.soldiers.all(func(x): return x.nation_id == 1), "soldiers who stayed serve us; %d walked out" % (3 - fort.soldiers.size()))

	# a failed bribe costs the spy
	var fort2 := g.spawn_firm("FORT", 2, foe.race, g._place_near(foe_town.footprint(), 4, 4, 12), true)
	g.update_links()
	var gen2 := g.spawn_unit(Defs.unit_sprite(foe.race, "INF"), 2, fort2.door(), 40.0)
	gen2.rank = Defs.Rank.GENERAL
	gen2.leadership = 60.0
	fort2.accept_unit(gen2)
	gen2.loyalty = 100.0
	var spy2 := g.spawn_unit(Defs.unit_sprite("NORMAN", "CIV"), 1, Vector2i(1, 1), 10.0)
	spy2.is_spy = true
	spy2.spy_skill = 40.0
	g.spy_enter(spy2, fort2)
	_check(Espionage.bribe_chance(spy2, fort2, gen2, 500) <= 0, "a fully loyal general cannot be bought")
	Espionage.bribe(spy2, fort2, gen2, 500)
	_check(spy2.dead and not g.spies.has(spy2), "the spy whose bribe is refused is executed")

	# --- a sleeper let out of his fort reports to us ---
	var fort3 := g.spawn_firm("FORT", 2, foe.race, g._place_near(foe_town.footprint(), 4, 4, 16), true)
	g.update_links()
	var sl := g.spawn_unit(Defs.unit_sprite(foe.race, "INF"), 2, fort3.door(), 20.0)
	fort3.accept_unit(sl)
	sl.sleeper_for = 1
	fort3.release_unit(sl)
	_check(sl.nation_id == 1 and sl.is_spy and sl.cloak_id == 2, "a bribed soldier let out becomes our spy in enemy colours")

	# --- assassination ---
	var spy3 := g.spawn_unit(Defs.unit_sprite("NORMAN", "CIV"), 1, Vector2i(1, 1), 10.0)
	spy3.is_spy = true
	spy3.spy_skill = 40.0
	var gen3 := g.spawn_unit(Defs.unit_sprite(foe.race, "INF"), 2, fort3.door(), 40.0)
	gen3.rank = Defs.Rank.GENERAL
	fort3.accept_unit(gen3)
	g.spy_enter(spy3, fort3)
	_check(not Espionage.can_assassinate(spy3, fort3), "assassination needs spying skill %d" % Espionage.MIN_ASSASSIN_SKILL)
	spy3.spy_skill = 60.0
	var c0 := Espionage.assassinate_chance(spy3, fort3)
	me.tech["ASSASSIN"] = 1
	var c1 := Espionage.assassinate_chance(spy3, fort3)
	_check(c1 > c0, "Advanced Assassination raises the chance (%d%% -> %d%%)" % [c0, c1])
	spy3.spy_skill = 100.0
	var tries := 0
	while fort3.overseer == gen3 and not spy3.dead and tries < 1:
		Espionage.assassinate(spy3, fort3)
		tries += 1
	_check(gen3.dead or spy3.dead, "an assassination attempt kills the general or the spy (general dead: %s)" % gen3.dead)
	if gen3.dead:
		_check(fort3.overseer == null, "the fort has lost its commander")

	# --- stealing technology ---
	foe.tech["MINING"] = 2
	var spy4 := g.spawn_unit(Defs.unit_sprite("NORMAN", "CIV"), 1, Vector2i(1, 1), 10.0)
	spy4.is_spy = true
	spy4.spy_skill = 100.0
	g.spy_enter(spy4, fort2)
	_check(not Espionage.can_steal_tech(spy4, fort2), "stealing technology needs Technology Theft")
	me.tech["STEALTEC"] = 1
	var r = Espionage.steal_tech(spy4, fort2)
	_check((r == "MINING" and me.tech_level("MINING") == 2) or (r == null and spy4.dead), "the spy steals Advanced Mining or dies trying (%s)" % str(r))

	# --- incidents ---
	var spy5 := g.spawn_unit(Defs.unit_sprite("NORMAN", "CIV"), 1, Vector2i(1, 1), 10.0)
	spy5.is_spy = true
	spy5.spy_skill = 100.0
	g.spy_enter(spy5, fort2)
	me.tech["INCIDENT"] = 1
	g.make_peace(2, 3)
	var ok_inc := Espionage.create_incident(spy5, fort2, 3)
	_check((ok_inc and foe.relation(3) == Defs.Relation.WAR) or (not ok_inc and spy5.dead), "an incident sets the %s against the %s, or costs the spy" % [foe.name, third.name])

	# --- counter-espionage ---
	var intruder := g.spawn_unit(Defs.unit_sprite(foe.race, "CIV"), 2, Vector2i(1, 1), 10.0)
	intruder.is_spy = true
	intruder.spy_skill = 10.0
	g.spy_enter(intruder, home)
	var guards := []
	for i in 4:
		var cs := g.spawn_unit(Defs.unit_sprite("NORMAN", "CIV"), 1, Vector2i(1, 1), 10.0)
		cs.is_spy = true
		cs.spy_skill = 100.0
		g.spy_enter(cs, home)
		guards.append(cs)
	me.tech["COUNTERS"] = 1
	var caught := false
	for i in 20:
		Espionage.catch_spy(g, home)
		if intruder.dead:
			caught = true
			break
	_check(caught, "four skilled counter-spies catch an enemy spy in our town")
	_check(guards.all(func(x): return not x.dead), "our own spies are never caught at home")
	var sleeper_spy := g.spawn_unit(Defs.unit_sprite(foe.race, "CIV"), 2, Vector2i(1, 1), 10.0)
	sleeper_spy.is_spy = true
	sleeper_spy.spy_action = "idle"
	g.spy_enter(sleeper_spy, home)
	for i in 50:
		Espionage.catch_spy(g, home)
	_check(not sleeper_spy.dead, "a sleeping spy is not caught")

	# --- save and load ---
	var cloaked := sl
	SaveGame.save(g, "test_spies")
	var g2 := Game.new()
	add_child(g2)
	_check(SaveGame.load_into(g2, "test_spies") == "", "the game saves and loads")
	var c2: Unit = g2.units.filter(func(u): return u.obj_id == cloaked.obj_id)[0] if g2.units.any(func(u): return u.obj_id == cloaked.obj_id) else null
	_check(c2 != null and c2.cloak_id == 2 and c2.is_spy, "a disguised spy keeps his disguise after loading")
	_check(g2.spies.size() == g.spies.size(), "infiltrated spies are back in place (%d)" % g2.spies.size())
	g2.queue_free()
	Game.inst = g

	# --- the computer's spies ---
	for n in g.nations:
		if n.id != 1:
			n.ai = NationAI.new(n, g)
	foe.tech["BRIBE"] = 1
	var ai_spy := g.spawn_unit(Defs.unit_sprite(foe.race, "CIV"), 2, Vector2i(foe_town.center_loc()) + Vector2i(0, 4), 10.0)
	ai_spy.is_spy = true
	ai_spy.spy_skill = 60.0
	_days(g, 60)
	_check(ai_spy.dead or ai_spy.has_meta("hidden") or ai_spy.order != Unit.Order.IDLE, "a computer spy goes to work")
	# a computer spy inside one of our forts buys its general and takes it
	var myfort := g.spawn_firm("FORT", 1, "NORMAN", g._place_near(home.footprint(), 4, 4, 14), true)
	g.update_links()
	var mygen := g.spawn_unit(Defs.unit_sprite(foe.race, "INF"), 1, myfort.door(), 30.0)
	mygen.rank = Defs.Rank.GENERAL
	mygen.leadership = 20.0
	myfort.accept_unit(mygen)
	mygen.loyalty = 25.0
	var mole := g.spawn_unit(Defs.unit_sprite(foe.race, "CIV"), 2, Vector2i(1, 1), 10.0)
	mole.is_spy = true
	mole.spy_skill = 60.0
	g.spy_enter(mole, myfort)
	foe.cash = 20000.0
	for i in 31:
		Espionage.ai_think(foe, g, 1, i)
		if myfort.nation_id == 2 or mole.dead:
			break
	_check(myfort.nation_id == 2 or mole.dead or mygen.dead, "the computer's spy bribes our disloyal general and takes the fort (owner %d)" % myfort.nation_id)
	_finish()


func _finish() -> void:
	print("RESULT: ", "PASS" if fails == 0 else "FAIL")
	get_tree().quit(0 if fails == 0 else 2)
