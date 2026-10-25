extends Node
## FirmTrain (of_train.cpp, otrainee.cpp): trainees in the Espionage College and
## the Training Ground - who may enrol, basic and advanced training, one man at
## a time, mobilizing, cancelling with a refund, the rally point, enemy spies
## among the volunteers, a destroyed building, save/load and the computer.
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
	g.start({"seed": 11, "size": 100, "race": "NORMAN", "ai_count": 1, "fryhtan_count": 0, "lairs": 0, "reveal": true})
	var me := g.player()
	me.cash = 20000.0
	for n in g.nations:
		if n.ai and n.id != me.id:
			n.ai = null
	var home: Town = g.towns.filter(func(t): return t.nation_id == me.id)[0]
	home.loyalty = 80.0
	home.population = 40

	# --- the college: civilian spies need only a loyal linked town
	var col := g.spawn_firm("SPY", me.id, me.race, g._place_near(home.footprint(), 5, 5, 8, [home.center_loc()]), true)
	g.update_links()
	var forts := home.linked_firms.filter(func(f): return f.code == "FORT" and f.nation_id == me.id)
	for f in forts:
		f.die(null)              # no fort linked: no infantry spies
	g.update_links()
	_check(Training.best_towns(col, Training.CIVILIAN).size() == 1, "a civilian spy can come from the linked town")
	_check(Training.best_towns(col, Training.INFANTRY).is_empty(), "an infantry spy needs the town to be linked to a fort")
	var cash0 := me.cash
	var pop0 := home.population
	_check(Training.order_train(col, Training.CIVILIAN), "a villager enrols")
	var civ_cost := Training.build_cost(Training.unit_of(me.race, Training.CIVILIAN))
	_check(home.population == pop0 - 1 and is_equal_approx(me.cash, cash0 - civ_cost),
		"he leaves the town (%d -> %d) and his cost is paid (%d)" % [pop0, home.population, int(cash0 - me.cash)])
	Training.order_train(col, Training.CIVILIAN)
	_days(g, 5)
	var a: Dictionary = col.trainees[0]
	var b: Dictionary = col.trainees[1]
	_check(a["spy_skill"] >= 4.0 and b["spy_skill"] == 0.0, "basic training: one man at a time (%d, %d)" % [int(a["spy_skill"]), int(b["spy_skill"])])
	# cancel the second: back home and refunded
	var cash1 := me.cash
	var pop1 := home.population
	Training.order_mobilize(col, 1)
	_check(col.trainees.size() == 1 and home.population == pop1 + 1 and is_equal_approx(me.cash, cash1 + civ_cost),
		"cancelling sends him home and refunds the cost")
	_days(g, 20)
	_check(not col.trainees[0]["training"] and col.trainees[0]["spy_skill"] == 20.0 and col.trainees[0]["combat"] == 10.0,
		"after basic training: spying 20, combat 10 (%s)" % Training.describe(col.trainees[0]))
	var before: float = col.trainees[0]["spy_skill"]
	_days(g, 31)
	_check(col.trainees[0]["spy_skill"] > before, "advanced training raises his spying (%.2f -> %.2f)" % [before, col.trainees[0]["spy_skill"]])
	# save and load keep the trainees
	SaveGame.save(g, "test_training")
	var n_tr := col.trainees.size()
	var skill: float = col.trainees[0]["spy_skill"]
	var g2 := Game.new()
	add_child(g2)
	g.queue_free()
	_check(SaveGame.load_into(g2, "test_training") == "", "the game loads")
	DirAccess.remove_absolute(SaveGame.path_for("test_training"))
	g = g2
	col = g.firms.filter(func(f): return f.code == "SPY")[0]
	_check(col.trainees.size() == n_tr and is_equal_approx(col.trainees[0]["spy_skill"], skill), "a saved game keeps the trainees")
	me = g.player()
	home = g.towns.filter(func(t): return t.nation_id == me.id)[0]
	var spy := Training.mobilize(col, 0)
	_check(spy != null and spy.is_spy and spy.nation_id == me.id and spy.spy_skill >= 20.0 and col.trainees.is_empty(),
		"mobilized, he walks out as our spy")

	# --- the training ground: only its race, one at a time, rally point
	var st := g.spawn_firm("STABLE", me.id, me.race, g._place_near(home.footprint(), 6, 6, 8, [home.center_loc()]), true)
	g.update_links()
	st.set_rally(st.door() + Vector2i(4, 4))
	home.loyalty = 80.0
	_check(Training.order_train(st, Training.SPECIAL) and Training.order_train(st, Training.SPECIAL), "two volunteers for the special unit")
	var spu := st.special_unit()
	var days := int(Defs.unit_types[spu]["build_days"])
	var n0 := g.units.filter(func(u): return u.sprite_code == spu and u.nation_id == me.id).size()
	_days(g, days + 2)
	var out := g.units.filter(func(u): return u.sprite_code == spu and u.nation_id == me.id)
	_check(out.size() == n0 + 1 and st.trainees.size() == 1, "after %d days the first walks out to the rally point, the second waits" % days)
	if out.size() > n0:
		var u: Unit = out[-1]
		_check(u.combat >= 19.0 and u.combat <= 31.0, "he has had basic training (combat %d)" % int(u.combat))
	# a spy living in the town may be the volunteer
	var foe := g.nation(2)
	for k in 30:
		var s := g.spawn_unit(Defs.unit_sprite(home.race, "CIV"), foe.id, Vector2i(home.x1, home.y1), 10.0)
		s.is_spy = true
		s.spy_skill = 30.0
		g.spy_enter(s, home)
	home.population = 1
	home.loyalty = 80.0
	var spies0 := Espionage.spies_in(home).size()
	st.clear_rally()
	var got := false
	for k in 6:
		if Training.order_train(st, Training.SPECIAL) and st.trainees[-1]["spy"] != null:
			got = true
			break
		if home.population <= 0:
			home.population = 1
	_check(got and Espionage.spies_in(home).size() == spies0 - 1, "an enemy spy in the town can enrol as a trainee")
	# the building is destroyed: the trained walk out, the others go home
	_days(g, days + 2)
	var units0 := g.units.size()
	var trained := st.trainees.filter(func(r): return not r["training"]).size()
	var pending := st.trainees.size() - trained
	var hp := home.population
	st.die(null)
	_check(st.trainees.is_empty() and g.units.size() >= units0 + trained, "when it falls the %d trained walk out" % trained)
	print("home population ", hp, " -> ", home.population, " (", pending, " were in training)")

	# --- the computer trains spies and special units by itself
	var ai_n := g.nation(2)
	ai_n.cash = 45000.0
	ai_n.add_cash(5000.0, "Taxes")      # a kingdom in profit (Nation::ai_should_spend spends nothing at a loss)
	var ai_home: Town = g.towns.filter(func(t): return t.nation_id == ai_n.id)[0]
	ai_home.population = 60
	ai_home.loyalty = 90.0
	var ai_col := g.spawn_firm("SPY", ai_n.id, ai_n.race, g._place_near(ai_home.footprint(), 5, 5, 8, [ai_home.center_loc()]), true)
	g.update_links()
	for s in g.spies.duplicate():
		if s.nation_id == ai_n.id:
			g.kill_spy(s)          # the planted ones would be over its spy quota
	var spies_before := g.units.filter(func(u): return u.is_spy and u.nation_id == ai_n.id).size()
	ai_n.ai = NationAI.new(ai_n, g)
	_days(g, 70)
	var ai_spies := g.units.filter(func(u): return u.is_spy and u.nation_id == ai_n.id).size()
	print("computer: trainees ", ai_col.trainees.size(), ", spies ", ai_spies)
	_check(ai_spies > spies_before or not ai_col.trainees.is_empty(), "the computer trains spies at its college (%d -> %d)" % [spies_before, ai_spies])
	print("RESULT: ", "PASS" if fails == 0 else "FAIL")
	get_tree().quit(0 if fails == 0 else 2)
