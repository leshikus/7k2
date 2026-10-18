class_name Training
extends RefCounted
## Training buildings (of_train.cpp, otrainee.cpp, of_spec*.cpp, of_spy*.cpp):
## the Training Ground of a race's special unit (FirmSpecial, here "STABLE")
## and the Espionage College (FirmSpy, "SPY"). Villagers come in from linked
## towns as trainees (up to MAX_TRAINEE), are trained one at a time each day
## (basic training) and every month further (advanced training, twice at the
## college), and stay inside until mobilized. A trainee is a record, as the
## original's Trainee; the unit is made when he walks out.

const MAX_TRAINEE := 8
const TRAIN_SKILL_COST := 30            # FirmSpy: the college needs this much cash to take a trainee
const BASIC_COMBAT_TRAIN := 20.0
const BASIC_SKILL_TRAIN := 20.0
const MAX_SKILL_TRAIN := 100.0
const MAX_COMBAT_BATTLE := 200.0

enum { CIVILIAN, INFANTRY, SPECIAL }
const TYPE_KIND := ["CIV", "INF", "SPU"]
const TYPE_NAME := ["Civilian", "Infantry", "Special unit"]
## FirmTrain::required_linked_firm: the town must also be linked to a fort to
## give an infantryman, to a training ground to give a special unit.
const REQUIRED_LINKED := ["", "FORT", "STABLE"]


static func is_train_firm(f: Firm) -> bool:
	return f.code == "STABLE" or f.code == "SPY"


## firm_res[]->same_race_worker: a training ground takes only its own race.
static func same_race(f: Firm) -> bool:
	return f.code == "STABLE"


static func unit_of(race: String, type: int) -> String:
	return Defs.unit_sprite(race, TYPE_KIND[type])


static func build_cost(sprite: String) -> float:
	return float(Defs.unit_types.get(sprite, {}).get("cost", 0))


# ------------------------------------------------------------- recruiting ---

## Firm::can_train_from_town
static func can_train_from_town(f: Firm, t: Town, type: int) -> bool:
	if t.dead or t.nation_id != f.nation_id or (same_race(f) and t.race != f.race) \
			or t.loyalty < Defs.MIN_RECRUIT_LOYALTY or t.population <= 0:
		return false
	var need: String = REQUIRED_LINKED[type]
	if need == "":
		return true
	for lf in t.linked_firms:
		if lf.code == need and lf.nation_id == t.nation_id and not lf.dead and not lf.under_construction \
				and (not same_race(lf) or lf.race == t.race):
			return true
	return false


## FirmTrain::can_recruit (and FirmSpy's: the town must qualify too)
static func can_recruit(f: Firm, t: Town, type: int) -> bool:
	var n := f.nation()
	if t == null or n == null or n.cash < 0.0 or f.trainees.size() >= MAX_TRAINEE or t.dead or t.population <= 0:
		return false
	if f.code == "SPY" and not can_train_from_town(f, t, type):
		return false
	return true


## Firm::scan_best_recruitable_town: for each race, the linked town most above
## the minimum recruiting loyalty.
static func best_towns(f: Firm, type: int) -> Array:
	var best := {}
	var value := {}
	for t in f.linked_towns:
		if not can_train_from_town(f, t, type):
			continue
		var v := int(t.loyalty) - Defs.MIN_RECRUIT_LOYALTY
		if v > int(value.get(t.race, 0)):
			best[t.race] = t
			value[t.race] = v
	return best.values()


## The types this building trains.
static func train_types(f: Firm) -> Array:
	return [CIVILIAN, INFANTRY, SPECIAL] if f.code == "SPY" else [SPECIAL]


## FirmTrain::recruit_trainee / FirmSpy::recruit_trainee
static func recruit(f: Firm, t: Town, type: int) -> bool:
	if not can_recruit(f, t, type) or (same_race(f) and t.race != f.race):
		return false
	var g := Game.inst
	var n := f.nation()
	if f.code == "SPY" and n and n.cash < TRAIN_SKILL_COST:
		return false
	var sprite := unit_of(t.race, type)
	if not Defs.unit_types.has(sprite):
		return false
	var rec := _new_trainee(t, type, sprite)
	# a spy living in the town may be the one who volunteers
	var in_town := Espionage.spies_in(t)
	if f.code != "SPY" and not in_town.is_empty() and g.rng.randi() % (t.population + in_town.size()) < in_town.size():
		var s: Unit = in_town[g.rng.randi() % in_town.size()]
		rec["spy"] = {"nation": s.nation_id, "skill": s.spy_skill, "name": s.unit_name}
		g.spies.erase(s)
		g.remove_unit(s)
	else:
		t.population -= 1
		t._check_empty()
		t.queue_redraw()
	if f.code == "SPY":
		if type != CIVILIAN:
			if rec["pot_combat"] >= 20:
				rec["pot_combat"] -= 20
			rec["pot_spy"] = 40 + g.rng.randi() % 20
		else:
			rec["pot_spy"] = 70 + g.rng.randi() % 30
	f.trainees.append(rec)
	if n:
		n.add_cash(-build_cost(sprite), "Training")
	return true


## Trainee::init
static func _new_trainee(t: Town, type: int, sprite: String) -> Dictionary:
	var rng := Game.inst.rng
	var rec := {"race": t.race, "unit": sprite, "type": type, "loyalty": t.loyalty, "src": t.obj_id,
		"combat": 0.0, "skill": 0.0, "spy_skill": 0.0, "pot_combat": 0, "pot_skill": 0, "pot_spy": 0,
		"training": true, "potential": 0, "spy": null}
	if type != CIVILIAN:
		rec["pot_combat"] = 70 + rng.randi() % 30
		rec["pot_skill"] = 10 + rng.randi() % 10
	# Skill::init: the man's own talent
	match rng.randi() % 15:
		0: rec["potential"] = 50 + rng.randi() % 51
		1: rec["potential"] = 25 + rng.randi() % 26
		2: rec["potential"] = 10 + rng.randi() % 15
	return rec


# --------------------------------------------------------------- training ---

static func next_day(f: Firm, day: int) -> void:
	var g := Game.inst
	if g.tutorial_ai_idle(f.nation_id):
		return
	_validate(f)
	for i in (10 if g.fast_build and f.nation_id == g.player_id else 1):
		_basic_train(f)
	if day % 30 == f.obj_id % 30:
		for k in (2 if f.code == "SPY" else 1):     # FirmSpy::advanced_train: twice as fast
			for rec in f.trainees:
				if not rec["training"]:
					_advanced(f, rec)


## FirmTrain::validate_trainee: forget a source town that is gone or changed.
static func _validate(f: Firm) -> void:
	for rec in f.trainees:
		var t := _town(int(rec["src"]))
		if t == null or t.race != rec["race"] or t.nation_id != f.nation_id:
			rec["src"] = -1


static func _town(id: int) -> Town:
	if id < 0:
		return null
	for t in Game.inst.towns:
		if t.obj_id == id and not t.dead:
			return t
	return null


## FirmTrain::basic_train: the first man still in basic training.
static func _basic_train(f: Firm) -> void:
	for i in f.trainees.size():
		var rec: Dictionary = f.trainees[i]
		if rec["training"]:
			_trainee_basic(f, rec)
			if f.rally.x >= 0 and not rec["training"]:
				var u := mobilize(f, i)
				if u:
					f.send_to_rally(u)
			return


## Trainee::basic_train
static func _trainee_basic(f: Firm, rec: Dictionary) -> void:
	var trained := false
	if rec["pot_spy"] > 0 and rec["spy_skill"] < BASIC_SKILL_TRAIN:
		rec["spy_skill"] = minf(MAX_SKILL_TRAIN, rec["spy_skill"] + 1.0)
		trained = true
	if rec["type"] == CIVILIAN:
		if rec["combat"] < Defs.CITIZEN_COMBAT_LEVEL:
			rec["combat"] += 1.0
			trained = true
	else:
		var basic := BASIC_COMBAT_TRAIN
		if Game.inst.god_worshipped(f.nation_id, "ROMAN"):
			basic += BASIC_COMBAT_TRAIN / 2.0
		if rec["pot_combat"] > 0 and rec["combat"] < basic:
			var days := maxf(1.0, float(Defs.unit_types.get(rec["unit"], {}).get("build_days", 10)))
			rec["combat"] = minf(MAX_COMBAT_BATTLE, rec["combat"] + basic / days)
			trained = true
	if rec["pot_skill"] > 0 and rec["skill"] < BASIC_SKILL_TRAIN:
		rec["skill"] = minf(100.0, rec["skill"] + 1.0)
		trained = true
	if not trained:
		rec["training"] = false


## Trainee::advanced_train
static func _advanced(f: Firm, rec: Dictionary) -> void:
	var g := Game.inst
	var nid := f.nation_id
	if rec["pot_spy"] > 0 and rec["spy_skill"] < MAX_SKILL_TRAIN:
		var inc := maxi(20, (100 - int(rec["spy_skill"])) * int(rec["pot_spy"]) / 100)
		rec["spy_skill"] = minf(MAX_SKILL_TRAIN, rec["spy_skill"] + inc / 100.0)
	if rec["pot_combat"] > 0 and rec["combat"] < Defs.MAX_COMBAT_TRAIN:
		var inc := maxi(20, (Defs.MAX_COMBAT_TRAIN - int(rec["combat"])) * int(rec["pot_combat"]) / 100)
		if nid > 0 and g.god_worshipped(nid, "CELTIC"):
			inc += inc / 2 if rec["race"] == "CELTIC" else inc / 5
		if rec["race"] == "EGYPTIAN" and nid > 0 and g.god_worshipped(nid, "EGYPTIAN"):
			var pc := g.god_worshippers(nid, "EGYPTIAN")
			inc = inc * (Defs.MAX_WORKER * 2) / (Defs.MAX_WORKER * 2 + pc)
		rec["combat"] = minf(MAX_COMBAT_BATTLE, rec["combat"] + inc / 100.0)
	if rec["pot_skill"] > 0 and rec["skill"] < MAX_SKILL_TRAIN:
		var inc := (100 - int(rec["skill"])) * int(rec["pot_skill"]) / 100
		rec["skill"] = minf(100.0, rec["skill"] + inc / 100.0)


# ------------------------------------------------------------ mobilizing ---

## FirmTrain::mobilize_trainee: the man walks out. One still in training
## leaves as a civilian.
static func mobilize(f: Firm, i: int) -> Unit:
	if i < 0 or i >= f.trainees.size():
		return null
	var rec: Dictionary = f.trainees[i].duplicate()
	if rec["training"]:
		rec["combat"] = Defs.CITIZEN_COMBAT_LEVEL
		rec["spy_skill"] = 0.0
		rec["unit"] = unit_of(rec["race"], CIVILIAN)
	var u := _create_unit(f, rec)
	if u == null:
		return null
	f.trainees.remove_at(i)
	return u


## Every trained man walks out (the "mobilize all" button).
static func mobilize_all(f: Firm) -> Array:
	var out: Array = []
	for i in range(f.trainees.size() - 1, -1, -1):
		if not f.trainees[i]["training"]:
			var u := mobilize(f, i)
			if u:
				out.append(u)
	return out


## FirmTrain::create_trainee_unit
static func _create_unit(f: Firm, rec: Dictionary) -> Unit:
	var g := Game.inst
	var c := g.world.adjacent_to_rect(f.footprint(), f.door())
	var spy = rec.get("spy")
	var nid: int = f.nation_id if spy == null else int(spy["nation"])
	var u := g.spawn_unit(rec["unit"], nid, c, maxf(1.0, rec["combat"]))
	if u == null:
		return null
	u.leadership = rec["skill"]
	u.potential = int(rec["potential"])
	u.loyalty = rec["loyalty"]
	u.rank = Defs.Rank.SOLDIER
	u.hp = u.max_hp
	if spy != null:
		# a spy from the town: he keeps serving his own kingdom in our colours
		u.is_spy = true
		u.spy_skill = float(spy["skill"])
		u.unit_name = spy["name"]
		u.cloak_id = f.nation_id if f.nation_id != nid else 0
	elif rec["spy_skill"] > 0.0:
		u.is_spy = true
		u.spy_skill = rec["spy_skill"]
	u.queue_redraw()
	return u


## FirmTrain::cancel_train_trainee: a man still in basic training goes home
## (or to another linked town of his race) and the cost is refunded.
static func cancel(f: Firm, i: int) -> void:
	if i < 0 or i >= f.trainees.size() or not f.trainees[i]["training"]:
		return
	var rec: Dictionary = f.trainees[i]
	var home := _town(int(rec["src"]))
	if home and not (home.race == rec["race"] and home.nation_id == f.nation_id and home.population < Defs.MAX_TOWN_POPULATION):
		home = null
	if home == null:
		for t in f.linked_towns:
			if t.race == rec["race"] and t.nation_id == f.nation_id and t.population < Defs.MAX_TOWN_POPULATION and not t.dead:
				home = t
				break
	if home:
		var spy = rec.get("spy")
		if spy != null:
			_return_spy(home, spy)
		else:
			home.population += 1         # Town::inc_pop: his loyalty joins the town's
			home.loyalty = (home.loyalty * (home.population - 1) + rec["loyalty"]) / home.population
			home.queue_redraw()
		f.trainees.remove_at(i)
	elif mobilize(f, i) == null:
		kill(f, i)
	var n := f.nation()
	if n:
		n.refund_expense(build_cost(rec["unit"]), "Training")


static func _return_spy(t: Town, spy: Dictionary) -> void:
	var g := Game.inst
	var u := g.spawn_unit(Defs.unit_sprite(t.race, "CIV"), int(spy["nation"]), Vector2i(t.x1, t.y1), Defs.CITIZEN_COMBAT_LEVEL)
	if u == null:
		return
	u.is_spy = true
	u.spy_skill = float(spy["skill"])
	u.unit_name = spy["name"]
	g.spy_enter(u, t)


## FirmTrain::kill_trainee
static func kill(f: Firm, i: int) -> void:
	if i >= 0 and i < f.trainees.size():
		f.trainees.remove_at(i)


## FirmTrain::free_all_people: the building is gone; the trained walk out,
## the rest go home.
static func free_all(f: Firm) -> void:
	for i in range(f.trainees.size() - 1, -1, -1):
		if not f.trainees[i]["training"]:
			if mobilize(f, i) == null:
				kill(f, i)
		else:
			cancel(f, i)
	f.trainees.clear()


## Player command: train a man of `type`, from the best town of `race`
## (or the only one).
static func order_train(f: Firm, type: int, race := "") -> bool:
	for t in best_towns(f, type):
		if race == "" or t.race == race:
			return recruit(f, t, type)
	return false


## Player command: the selected trainee leaves, or quits training.
static func order_mobilize(f: Firm, i: int) -> void:
	if i < 0 or i >= f.trainees.size():
		return
	if f.trainees[i]["training"]:
		cancel(f, i)
	else:
		var u := mobilize(f, i)
		if u and f.nation_id == Game.inst.player_id:
			Game.inst.select_only(u)


static func order_mobilize_all(f: Firm) -> void:
	var out := mobilize_all(f)
	if not out.is_empty() and f.nation_id == Game.inst.player_id:
		Game.inst.select_only(out[-1])


# -------------------------------------------------------------------- AI ---

static func process_ai(f: Firm, ai, day: int) -> void:
	var n := f.nation()
	if n == null:
		return
	if f.code == "STABLE":
		if day % 15 == f.obj_id % 15:
			_think_train_special(f, n)
		if day % 15 == (f.obj_id + 5) % 15:
			_think_transfer(f, n, ai)
	else:
		if day % 30 == f.obj_id % 30:
			_think_train_spy(f, n, ai)
		if day % 30 == (f.obj_id + 15) % 30:
			_think_spy_action(f, n)
	if day % 30 == f.obj_id % 30 and f.linked_towns.is_empty():
		f.die(null)        # think_del: no town to draw from


## Nation::ai_should_spend
static func ai_should_spend(n: Nation, importance: int, amount := 0.0) -> bool:
	if n.cash < amount:
		return false
	var fixed := maxf(1.0, n.fixed_expense_365())
	var std := maxf(fixed, 2000.0) * (150 + Diplomacy._pref(n, "cash_reserve")) / 100.0
	if n.is_fryhtan:
		std /= 2.0                  # the standard cash level of a Fryhtan kingdom is lower
	var profit := n.true_profit_365()
	if profit < 0.0:
		var r1 := int(100.0 * -profit / fixed)
		var r2 := int(200.0 * -profit / maxf(1.0, n.cash))
		if mini(r1, r2) > importance:
			return false
	var level := 100.0 * (n.cash - amount) / (std * 2.0)
	return importance >= 100.0 - level


## FirmSpecial::think_train_new
static func _think_train_special(f: Firm, n: Nation) -> void:
	if not ai_should_spend(n, 50) or n.cash <= 0.0:
		return
	var best: Town = null
	for t in f.linked_towns:
		if t.nation_id == f.nation_id and t.race == f.race and t.jobless() > (best.jobless() if best else 0):
			best = t
	if best:
		recruit(f, best, SPECIAL)


## FirmSpecial::think_transfer_unit: trained men go to the nearest camp with room.
static func _think_transfer(f: Firm, n: Nation, ai) -> void:
	if f.trainees.is_empty() or f.trainees[0]["training"]:
		return
	var best: Firm = null
	var best_d := INF
	for c in Game.inst.firms:
		if c.dead or c.nation_id != f.nation_id or not Espionage.is_camp(c) or c.under_construction or c.soldiers.size() >= c.capacity():
			continue
		var d := c.center_loc().distance_to(f.center_loc())
		if d < best_d:
			best_d = d
			best = c
	if best == null:
		return
	var room := best.capacity() - best.soldiers.size()
	var i := 0
	while i < f.trainees.size() and room > 0:
		if f.trainees[i]["training"]:
			i += 1
			continue
		var u := mobilize(f, i)
		if u == null:
			break
		u.order_enter(best)
		room -= 1


## FirmSpy::think_train_new
static func _think_train_spy(f: Firm, n: Nation, ai) -> void:
	var g := Game.inst
	var pref := Diplomacy._pref(n, "spy")
	var pop := 0
	for t in g.towns:
		if t.nation_id == n.id and not t.dead:
			pop += t.population
	if pop < 30 - pref / 10:
		return
	var spies := g.units.filter(func(u): return u.is_spy and u.nation_id == n.id and not u.dead).size()
	if spies > pop * (10 + pref / 5) / 100:
		return
	if not ai_should_spend(n, 25 + pref / 2):
		return
	if f.linked_towns.is_empty():
		return
	var start := g.rng.randi() % f.linked_towns.size()
	for k in f.linked_towns.size():
		var t: Town = f.linked_towns[(start + k + 1) % f.linked_towns.size()]
		var civ := g.rng.randi() % 2 == 0
		var type := CIVILIAN if civ else (INFANTRY if g.rng.randi() % 2 == 0 else SPECIAL)
		if f.trainees.any(func(rec): return rec["race"] == t.race and (rec["type"] == CIVILIAN) == civ):
			continue                 # has_spy: one of this kind in training already
		if can_train_from_town(f, t, type) and recruit(f, t, type):
			return


## FirmSpy::think_spy_action: trained spies go out on missions (Espionage.ai_think
## picks their targets), less often with a bad reputation.
static func _think_spy_action(f: Firm, n: Nation) -> void:
	var g := Game.inst
	if n.reputation < 0 and g.rng.randi() % maxi(1, int(-n.reputation / 5)) != 0:
		return
	for i in range(f.trainees.size() - 1, -1, -1):
		if not f.trainees[i]["training"]:
			mobilize(f, i)
			return


# ------------------------------------------------------------------- info ---

## What the panel's buttons depend on.
static func signature(f: Firm) -> String:
	var s := ""
	for rec in f.trainees:
		s += "T" if rec["training"] else "R"
	for type in train_types(f):
		s += "|" + ",".join(best_towns(f, type).map(func(t): return str(t.obj_id)))
	return s

static func describe(rec: Dictionary) -> String:
	var ut: Dictionary = Defs.unit_types.get(rec["unit"], {})
	var s: String = ut.get("name", rec["unit"])         # the unit's name already says its race
	s += "  combat %d" % int(rec["combat"])
	if rec["skill"] > 0.0:
		s += ", leadership %d" % int(rec["skill"])
	if rec["spy_skill"] > 0.0 and (rec.get("spy") == null):
		s += ", spying %d" % int(rec["spy_skill"])
	if rec["training"]:
		s += "  (in training)"
	return s
