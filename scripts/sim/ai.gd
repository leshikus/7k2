class_name NationAI
extends AIBase
## A computer-run human kingdom, as the original runs one (oai_*.cpp): a
## personality; a main thought cycle at the pace set by the aggressiveness
## setting (build mines, capture towns, expand the army, secret attacks,
## diplomacy, grand plans, cutting costs); a queue of actions that units
## carry out (build, assign a commander or soldiers, settle, scout); and the
## towns, buildings and units that think for themselves (AITown, AIFirm, AIUnit).

enum { BUILD_FIRM = 1, ASSIGN_OVERSEER, ASSIGN_SOLDIER, ASSIGN_SPY, SCOUT, BUILD_TOWN, SETTLE_TOWN }
const STD_ACTION_RETRY_COUNT := 4
const MAX_SUITABLE_ATTACK_CAMP := 30
const MAX_AI_ATTACK_TARGET := 10
const MAX_SOLDIER := 15
const IDEAL_INTER_PLACE_SPACE := 3

var actions: Array = []             # ActionNode: {id, mode, para, para2, x, y, rx, ry, unit, retry, instance, processing, processed, add_day, next_retry}
var last_action_id := 0
var capture_town: Town = null       # ai_capture_enemy_town_recno
var capture_plan_day := 0
var capture_start_day := 0
var capture_use_all := false
var attack_camps: Array = []        # AttackCamp: {firm, combat, distance, patrol_day}
var attack_targets: Array = []      # ai_attack_target_x/y_loc
var attack_target_nation := -1
var lead_attack_camp: Firm = null
var last_defend_day := -1000
var secret_attack := {}             # nation id -> true (NationRelation::ai_secret_attack)


func _init(nation: Nation, game: Game) -> void:
	super(nation, game)
	# the personality is drawn on first use, so creating the kingdoms does not
	# disturb the random numbers the map is generated with
	# Nation::init: the computer grants gold before its people rebel
	for t in g.towns:
		if t.nation_id == n.id:
			t.auto_grant_loyalty = Defs.REBEL_LOYALTY + 1


# ---------------------------------------------------------------- saving ---

static func _oid(o) -> int:
	return o.obj_id if o != null and is_instance_valid(o) and not o.dead else 0


func to_dict() -> Dictionary:
	return {
		"actions": actions.map(func(a):
			var c: Dictionary = a.duplicate()
			c["unit"] = _oid(a["unit"])
			return c),
		"last_action_id": last_action_id,
		"capture": [_oid(capture_town), capture_plan_day, capture_start_day, capture_use_all],
		"attack_camps": attack_camps.map(func(a): return [_oid(a["firm"]), a["combat"], a["distance"], a["patrol_day"]]),
		"attack_targets": attack_targets.map(func(o): return _oid(o)),
		"attack_nation": attack_target_nation, "lead_camp": _oid(lead_attack_camp),
		"last_defend_day": last_defend_day, "secret_attack": secret_attack.keys(),
	}


func from_dict(d: Dictionary, by_id: Dictionary) -> void:
	actions.clear()
	for a in d.get("actions", []):
		var c: Dictionary = a.duplicate()
		for k in ["id", "mode", "x", "y", "rx", "ry", "retry", "instance", "processing", "processed", "add_day", "next_retry"]:
			c[k] = int(c.get(k, 0))
		if c["mode"] == SETTLE_TOWN or c["mode"] == SCOUT:
			c["para"] = int(c["para"])
		var u = by_id.get(int(a.get("unit", 0)))
		c["unit"] = u if u is Unit else null
		actions.append(c)
	last_action_id = int(d.get("last_action_id", 0))
	var cap: Array = d.get("capture", [0, 0, 0, false])
	var ct = by_id.get(int(cap[0]))
	capture_town = ct if ct is Town else null
	capture_plan_day = int(cap[1])
	capture_start_day = int(cap[2])
	capture_use_all = bool(cap[3])
	attack_camps.clear()
	for a in d.get("attack_camps", []):
		var f = by_id.get(int(a[0]))
		if f is Firm:
			attack_camps.append({"firm": f, "combat": int(a[1]), "distance": int(a[2]), "patrol_day": int(a[3])})
	attack_targets.clear()
	for i in d.get("attack_targets", []):
		var o = by_id.get(int(i))
		if o != null:
			attack_targets.append(o)
	attack_target_nation = int(d.get("attack_nation", -1))
	var lc = by_id.get(int(d.get("lead_camp", 0)))
	lead_attack_camp = lc if lc is Firm else null
	last_defend_day = int(d.get("last_defend_day", -1000))
	secret_attack.clear()
	for k in d.get("secret_attack", []):
		secret_attack[int(k)] = true


## Nation::init_personalty
const PREFS := ["force_projection", "military_development", "inc_pop_by_capture", "peacefulness", "military_courage",
	"territorial_cohesiveness", "trading_tendency", "allying_tendency", "honesty", "town_defense", "loyalty_concern",
	"forgiveness", "collect_tax", "hire_unit", "use_weapon", "keep_general", "keep_skilled_unit", "diplomacy_retry",
	"attack_monster", "spy", "counter_spy", "cash_reserve", "food_reserve", "use_marine", "repair_concern", "scout",
	"research", "seat_of_power", "monster_aggressiveness", "monster_special", "live_points_reserve", "surrender"]


func init_personality() -> void:
	if n.prefs.has("_set"):
		return
	for k in PREFS:
		n.prefs[k] = g.rng.randi() % 101
	n.prefs["economic_development"] = 100 - int(n.prefs["military_development"])
	n.prefs["inc_pop_by_growth"] = 100 - int(n.prefs["inc_pop_by_capture"])
	n.prefs["spy"] = mini(60, int(n.prefs["spy"]))
	n.prefs["counter_spy"] = mini(60, int(n.prefs["counter_spy"]))
	n.prefs["unit_chase_distance"] = 15 + g.rng.randi() % 15
	n.prefs["_set"] = 1


func pref(k: String) -> int:
	if not n.prefs.has("_set"):
		init_personality()
	return int(n.prefs.get(k, 50))


# -------------------------------------------------------------- figures ---

## Nation::ai_camp_array: forts and camps, and a Fryhtan kingdom's lairs.
func camps() -> Array:
	return my_firms().filter(func(f): return (Espionage.is_camp(f) or f.code == "LAIR") and not f.under_construction)


func total_population() -> int:
	var p := 0
	for t in my_towns():
		p += t.population
	return p


func total_jobless() -> int:
	var p := 0
	for t in my_towns():
		p += t.jobless()
	return p


## Nation::total_unit_count: the kingdom's fighting men (Fryhtans too) and war machines.
func total_unit_count() -> int:
	return g.units.filter(func(u): return u.nation_id == n.id and not u.dead and not u.is_civilian() and not u.is_caravan and not u.is_god and not u.is_wagon()).size()


## NationBase::true_profit_365days
func true_profit() -> float:
	return n.true_profit_365()


func military_rank() -> int:
	return Diplomacy.military_rank(g, n)


func overall_rank() -> int:
	return Diplomacy.overall_rank(g, n)


## NationBase::yearly_food_change: farming less eating.
func yearly_food_change() -> float:
	return Diplomacy.yearly_food_change(g, n)


## Nation::ai_has_enough_food
func has_enough_food() -> bool:
	var yc := yearly_food_change()
	if yc < 0.0 and n.food > 0.0 and 100.0 * -yc / n.food > 50 - pref("food_reserve") / 3:
		return false
	return n.food > 2000 + 2000 * pref("food_reserve") / 100 or yc > 0.0


func should_spend(importance: int, amount := 0.0) -> bool:
	return Training.ai_should_spend(n, importance, amount)


## Nation::ai_should_spend_war
func should_spend_war(enemy_military: int, cease := false) -> bool:
	var imp := 30 + pref("military_development") / 5 + military_rank() - enemy_military * 2
	if cease:
		imp += 20
	return should_spend(imp)


func can_ai_build(code: String) -> bool:
	if n.is_fryhtan and n.live_points < SpecialFirms.setup_live(code):
		return false
	return n.cash >= float(Defs.firm_types.get(code, {}).get("cost", 0)) and Defs.knows_firm(n, code)


func relation(nid: int) -> int:
	return n.relation(nid) if nid > 0 else Defs.Relation.NEUTRAL


func distance_rating(a: Vector2, b: Vector2) -> int:
	return 100 - 100 * int(maxf(absf(a.x - b.x), absf(a.y - b.y))) / g.world.w


# ------------------------------------------------------------ main loop ---

## Nation::process_ai
func next_day(day: int) -> void:
	if not n.alive:
		return
	if n.king == null or not is_instance_valid(n.king) or n.king.dead:
		if think_succeed_king():
			return
		AIGrand.think_surrender(self)
		return
	if n.research_tech == "":
		think_new_research()
	var interval: int = [300, 90, 30, 15, 15][clampi(_aggressiveness(), 0, 4)]
	if g.config.has("tutorial"):
		interval = 120
	_main(posmod(day - n.id * 4, interval))
	if not n.alive:
		return
	if posmod(day - n.id, 3) == 0:
		process_actions()
	_on_going()
	# the original keeps its computer kingdoms afloat
	if _aggressiveness() == GameSetup.NONE and not g.config.has("tutorial") and n.cash > 1000:
		n.add_cheat(ceilf(-n.cash / 500.0))
	if n.cash < 100:
		n.add_cheat(float(200 + g.rng.randi() % 500))
	if n.food < 100:
		n.food += 1000.0
	if day % 360 == n.id % 360:
		_improve_relation()
	# the towns, buildings and units of the kingdom think for themselves
	for t in my_towns():
		AITown.process(self, t, day)
	for f in my_firms():
		if not f.dead and not f.under_construction:
			AIFirm.process(self, f, day)
	for u in g.units.duplicate():
		if u.nation_id == n.id and not u.dead and u.inside_firm == null:
			if u.is_caravan:
				Caravans.process_ai(u, day)          # UnitCaravan::process_ai
			else:
				AIUnit.process(self, u, day)
	AISpy.process_all(self, day)          # Spy::process_ai
	_use_gods()


## Nation::process_ai_main
func _main(id: int) -> void:
	match id:
		0: think_build_firm()
		1: AICapture.think_capture(self)
		2: pass                       # think_explore: nothing in the original
		3: think_military()
		4: AIAttack.think_secret_attack(self)
		5: AIDiplomacy.think(self)
		6: AIGrand.think_grand_plan(self)
		7: think_reduce_expense()


## Nation::process_on_going_action
func _on_going() -> void:
	if capture_town and g.day % 5 == n.id % 5:
		AICapture.think_capturing_enemy_town(self)
	if not attack_camps.is_empty():
		AIAttack.execute(self, true)


func _improve_relation() -> void:
	for o in g.nations:
		if o == n or not o.alive or n.relation(o.id) == Defs.Relation.WAR:
			continue
		Diplomacy.change_ai_rel(n, o.id, Diplomacy.trade_rating(g, n, o) / 10)
		if int(n.war_count.get(o.id, 0)) > 0 and g.rng.randi() % maxi(1, 5 - pref("forgiveness") / 20) > 0:
			n.war_count[o.id] = int(n.war_count[o.id]) - 1


## Nation::think_succeed_king
func think_succeed_king() -> bool:
	var best: Unit = null
	var best_r := 0
	for u in g.units:
		if u.nation_id != n.id or u.dead or u.is_civilian() or u.is_spy:
			continue
		if not (u.is_human() or (n.is_fryhtan and SpecialFirms.is_fryhtan_unit(u))):
			continue
		if u.inside_firm != null and u.inside_firm.overseer != u and not (u in u.inside_firm.soldiers):
			continue
		var r := int(u.lead_skill()) + int(u.combat) / 4
		if u.race == n.race:
			r += 50
		if u.rank == Defs.Rank.GENERAL:
			r += 30
		if r > best_r:
			best_r = r
			best = u
	if best == null:
		return false
	if best.inside_firm:
		best.inside_firm.release_unit(best)
	g.succeed_king(n, best)
	return true


## Nation::think_new_research
func think_new_research() -> void:
	if my_firms("RESEARCH").filter(func(f): return not f.under_construction).is_empty():
		return
	var best := ""
	var cls := ""
	var farming := Defs.tech_def("FARMING")
	if Defs.can_research(n, farming) and (not has_enough_food() or g.rng.randi() % maxi(1, 100 - pref("food_reserve")) < 10):
		best = "FARMING"
	if best == "" and pref("use_weapon") > 50:
		var tw := 0
		for w in Defs.WEAPONS:
			tw += n.tech_level(w)
		if g.rng.randi() % maxi(1, 100 - pref("use_weapon") + tw * 3) < 25:
			cls = "WEAPON"
	if best == "" and cls == "" and pref("spy") > 50:
		var ts := 0
		for t in Defs.TECHS:
			if t.get("spy", false):
				ts += n.tech_level(t["code"])
		if g.rng.randi() % maxi(1, 100 - pref("spy") + ts * 3) < 25:
			cls = "SPYING"
	var race_pop := {}
	for t in my_towns():
		race_pop[t.race] = int(race_pop.get(t.race, 0)) + t.jobless()
	if best == "" and cls == "":
		var max_pop := 0
		for r in race_pop:
			var code := Defs.spu_structure_tech(r)
			if Defs.can_research(n, Defs.tech_def(code)) and race_pop[r] > max_pop:
				max_pop = race_pop[r]
				best = code
	var all := Defs.research_techs()
	if best == "":
		var pool: Array = all.filter(func(t): return _tech_class(t) == cls) if cls != "" else []
		if pool.is_empty():
			var classes := ["PRODUCT", "SPYING", "MILITARY", "SPU_STRU", "SPU_POW", "WEAPON", "OFF_BLD"]
			var c2: String = classes[g.rng.randi() % classes.size()]
			pool = all.filter(func(t): return _tech_class(t) == c2)
		best = _random_researchable(pool, race_pop)
	if best == "":
		best = _random_researchable(all, race_pop)
	if best == "":
		best = _random_researchable(all, {})
	if best != "":
		n.start_research(best)


func _tech_class(t: Dictionary) -> String:
	var c: String = t["code"]
	if t.get("spy", false):
		return "SPYING"
	if c in ["MINING", "MANUFACT", "FARMING", "WAR_PROD"]:
		return "PRODUCT"
	if c in ["INFCLOSE", "INFRANGE", "INFDEFEN"]:
		return "MILITARY"
	if c.begins_with("SPUS"):
		return "SPU_STRU"
	if c.begins_with("SPUB"):
		return "SPU_POW"
	if c.begins_with("OFF_BLD"):
		return "OFF_BLD"
	return "WEAPON"


func _random_researchable(pool: Array, race_pop: Dictionary) -> String:
	if pool.is_empty():
		return ""
	var start := g.rng.randi() % pool.size()
	for i in pool.size():
		var t: Dictionary = pool[(start + i + 1) % pool.size()]
		if not Defs.can_research(n, t):
			continue
		if not race_pop.is_empty() and t.has("race") and int(race_pop.get(t["race"], 0)) <= 0:
			continue
		return t["code"]
	return ""


# ------------------------------------------------------------- actions ---

## Nation::add_action: not when the same is queued already.
func add_action(at: Vector2i, ref: Vector2i, mode: int, para = 0, instance := 1, unit: Unit = null, para2 = "") -> Dictionary:
	if find_action(at, ref, mode, para, unit) != null:
		return {}
	last_action_id += 1
	var a := {"id": last_action_id, "mode": mode, "para": para, "para2": para2, "x": at.x, "y": at.y, "rx": ref.x, "ry": ref.y,
		"unit": unit, "retry": STD_ACTION_RETRY_COUNT, "instance": instance, "processing": 0, "processed": 0,
		"add_day": g.day, "next_retry": 0}
	actions.append(a)
	if unit:
		a["retry"] = 1
		_process_one(a)          # the unit may change, carry it out now
	return a


## Nation::is_action_exist: at the location, or (at.x < 0) by the reference location.
func find_action(at: Vector2i, ref: Vector2i, mode: int, para, unit: Unit = null) -> Variant:
	for a in actions:
		if a["mode"] != mode or str(a["para"]) != str(para):
			continue
		if unit and a["unit"] != unit:
			continue
		if at.x >= 0:
			if a["x"] == at.x and a["y"] == at.y:
				return a
		elif a["rx"] == ref.x and a["ry"] == ref.y:
			return a
	return null


func action_exists(mode: int, para) -> bool:
	return actions.any(func(a): return a["mode"] == mode and str(a["para"]) == str(para))


## Nation::is_build_action_exist: a building of the kind planned near.
func build_action_near(code: String, at: Vector2) -> bool:
	var d := Defs.effective_distance(code, "")
	return actions.any(func(a): return a["mode"] == BUILD_FIRM and a["para"] == code and maxf(absf(a["x"] - at.x), absf(a["y"] - at.y)) <= d)


## Nation::process_action (every 3 days): a share of the queue is carried out;
## a failed action is tried again a week later, up to four times.
func process_actions() -> void:
	_count_done()
	var alive_nations := g.nations.filter(func(x): return x.alive).size()
	var max_count := 70 / maxi(1, alive_nations) / maxi(1 - _aggressiveness(), 1)
	var done := 0
	for a in actions.duplicate():
		if done >= max_count:
			break
		if a["processing"] >= a["instance"]:
			if g.day > a["add_day"] + 30 * 6:
				actions.erase(a)
			continue
		if g.day < a["next_retry"] or a["retry"] <= 0:
			continue
		if a["unit"] != null and (not is_instance_valid(a["unit"]) or a["unit"].dead):
			actions.erase(a)
			continue
		_process_one(a)
		done += 1


func _process_one(a: Dictionary) -> void:
	var rc := 0
	match a["mode"]:
		BUILD_FIRM: rc = _do_build_firm(a)
		ASSIGN_OVERSEER: rc = _do_assign_overseer(a)
		ASSIGN_SOLDIER: rc = _do_assign_soldier(a)
		ASSIGN_SPY: rc = _do_assign_spy(a)
		SCOUT: rc = _do_scout(a)
		BUILD_TOWN: rc = _do_build_town(a)
		SETTLE_TOWN: rc = _do_settle_town(a)
	var del := false
	if rc == 1:
		a["processing"] += 1
	elif rc == 0:
		if a["unit"] != null:
			del = true
		else:
			a["next_retry"] = g.day + 7
			a["retry"] -= 1
			if a["retry"] <= 0:
				del = true
	else:
		a["retry"] = 0
		del = true
	if del and a["processing"] <= a["processed"]:
		actions.erase(a)


## Nation::action_finished: units that carried an action out (or failed to)
## are counted; a fully done action is removed.
func _count_done() -> void:
	var busy := {}
	for u in g.units:
		if u.nation_id == n.id and not u.dead and u.ai_action_id > 0:
			if u.order == Unit.Order.IDLE or u.inside_firm != null:
				u.ai_action_id = 0
			else:
				busy[u.ai_action_id] = int(busy.get(u.ai_action_id, 0)) + 1
	for a in actions.duplicate():
		a["processed"] = a["processing"] - int(busy.get(a["id"], 0))
		if a["processing"] > 0 and (a["processed"] >= a["instance"] or (a["retry"] <= 0 and a["processed"] >= a["processing"])):
			actions.erase(a)


## Nation::check_firm_ready: the building is still there, ours, and of the
## type the action was queued for (a fort's request filed as a camp's is
## dropped, as in the original).
func _firm_ready(f: Firm, code: String) -> bool:
	if f == null or f.dead or f.nation_id != n.id:
		return false
	return code == "" or code == "0" or f.code == code


func _firm_at(x: int, y: int) -> Firm:
	for f in g.firms:
		if not f.dead and f.footprint().has_point(Vector2i(x, y)):
			return f
	return null


func _town_at(x: int, y: int) -> Town:
	for t in g.towns:
		if not t.dead and t.footprint().has_point(Vector2i(x, y)):
			return t
	return null


## Nation::ai_build_firm
func _do_build_firm(a: Dictionary) -> int:
	var code: String = a["para"]
	var race: String = a["para2"] if str(a["para2"]) != "" else n.race
	var b: Unit = a["unit"] if a["unit"] != null else get_unit(true, race if code in ["BASE", "STABLE", "SPY"] else "", Vector2i(a["x"], a["y"]))
	if b == null and code in ["CAMP", "FORT"]:
		b = get_unit(false, "", Vector2i(a["x"], a["y"]))
	if b == null or not can_ai_build(code):
		return 0
	var at := Vector2i(a["x"], a["y"])
	if code == "MINE":
		at = Vector2i(a["rx"], a["ry"])
	var f := g.spawn_firm(code, n.id, race, at, false)
	if f == null:
		return -1
	n.add_cash(-float(Defs.firm_types.get(code, {}).get("cost", 0)), "Construction")
	if n.is_fryhtan:
		n.live_points -= SpecialFirms.setup_live(code)
	if code == "LAIR":
		f.monster_code = n.monster_code
	f.setup_day = g.day
	b.order_build(f)
	b.ai_action_id = a["id"]
	a["unit"] = b
	return 1


## Nation::ai_build_town
func _do_build_town(a: Dictionary) -> int:
	if g.config.has("tutorial"):
		return 0
	var b: Unit = a["unit"] if a["unit"] != null else get_unit(true, str(a["para"]), Vector2i(a["x"], a["y"]))
	if b == null or not b.can_found_town():
		return 0
	b.order_found_town(Vector2i(a["x"], a["y"]))
	b.ai_action_id = a["id"]
	a["unit"] = b
	return 1


## Nation::ai_assign_overseer
func _do_assign_overseer(a: Dictionary) -> int:
	var f := _firm_at(a["x"], a["y"])
	if not _firm_ready(f, str(a["para"])) or not (Espionage.is_camp(f) or f.code == "LAIR"):
		return -1
	var u: Unit = a["unit"] if a["unit"] != null else get_unit(false, AIFirm.majority_race(f), Vector2i(a["x"], a["y"]))
	if u == null:
		return 0
	if u.rank == Defs.Rank.SOLDIER:
		u.rank = Defs.Rank.GENERAL
	if f.overseer and f.overseer != u:
		var old := f.overseer
		f.release_unit(old)
	u.order_enter(f)
	u.ai_action_id = a["id"]
	a["unit"] = u
	return 1


## Nation::ai_assign_soldier
func _do_assign_soldier(a: Dictionary) -> int:
	var f := _firm_at(a["x"], a["y"])
	if not _firm_ready(f, str(a["para"])) or not (Espionage.is_camp(f) or f.code == "LAIR"):
		return -1
	if f.soldiers.size() >= MAX_SOLDIER:
		return -1
	if MAX_SOLDIER - f.soldiers.size() < a["instance"]:
		a["instance"] = maxi(a["processing"] + 1, MAX_SOLDIER - f.soldiers.size())
	var u: Unit = a["unit"]
	if u == null:
		u = recruit_in_firm_soldier(f, str(a["para2"]))
	if u == null:
		return 0
	u.order_enter(f)
	u.ai_action_id = a["id"]
	return 1


## Nation::ai_settle_town: villagers (a wagon for several) move to another town.
func _do_settle_town(a: Dictionary) -> int:
	if g.config.has("tutorial"):
		return 0
	var dest := _town_at(a["x"], a["y"])
	var src := _town_at(a["rx"], a["ry"])
	if dest == null or src == null or dest.nation_id != n.id or src.nation_id != n.id:
		return -1
	if not src.can_recruit():
		if not src.has_linked_camp(n.id):
			return 0
		if n.cash > 0.0:
			src.grant(n.id)
		return 0
	var count: int = a["instance"] - a["processing"]
	var u: Unit = src.recruit_wagon() if count > 1 else src.recruit()
	if u == null:
		return 0
	u.order_settle_into(dest)
	u.ai_action_id = a["id"]
	if count > 1:
		a["instance"] = maxi(a["processing"] + 1, a["instance"] - u.settlers() + 1)
	return 1


## Nation::ai_scout
func _do_scout(a: Dictionary) -> int:
	var src := _town_at(a["rx"], a["ry"])
	if src == null or src.nation_id != n.id:
		return -1
	if not src.can_recruit():
		return 0
	var u := src.recruit()
	if u == null:
		return 0
	u.order_move(Vector2i(a["x"], a["y"]))
	u.ai_action_id = a["id"]
	return 1


## Nation::ai_assign_spy (the action): the spy puts on the target's colours and goes in.
func _do_assign_spy(a: Dictionary) -> int:
	var u: Unit = a["unit"]
	if u == null or u.dead or not u.is_spy or u.nation_id != n.id:
		return -1
	var target: GameObj = _town_at(a["x"], a["y"])
	if target == null:
		target = _firm_at(a["x"], a["y"])
	if target == null:
		return -1
	if not u.order_infiltrate(target):
		u.order_move(u.cell() + Vector2i(g.rng.randi() % 20 - 10, g.rng.randi() % 20 - 10))
		a["retry"] += 1
		return 0
	if Espionage.can_camouflage(u) and g.rng.randi() % 100 < int(u.spy_skill):
		Espionage.start_camouflage(u)
	return -1


# --------------------------------------------------------- unit supply ---

## Nation::ai_get_unit / ai_find_unit: an idle unit of the kind near by, else
## one hired at an inn (military) or recruited from a town (civilian), else a
## soldier taken out of a camp.
func get_unit(civilian: bool, race: String, dest: Vector2i) -> Unit:
	var best: Unit = null
	var best_d := INF
	for u in g.units:
		if u.nation_id != n.id or u.dead or not u.is_human() or u.is_spy or u.is_caravan or u.rank == Defs.Rank.KING:
			continue
		if race != "" and u.race != race:
			continue
		if u.is_civilian() != civilian or u.home_town != null:
			continue
		if u.inside_firm != null:
			if u.inside_firm.overseer == u and Espionage.is_camp(u.inside_firm) and u.inside_firm.should_close:
				u.inside_firm.release_unit(u)
				return u
			continue
		if u.order != Unit.Order.IDLE or u.ai_action_id > 0 or u.attacking or u.home_firm != null:
			continue
		var d := u.center_loc().distance_to(Vector2(dest))
		if d < best_d:
			best_d = d
			best = u
	if best:
		return best
	if not civilian:
		var h := hire_unit(race, false, dest)
		if h:
			return h
		if race != "":
			return find_unit_from_camp(race, dest)
		return null
	return recruit_peasant(race, dest)


func should_hire_unit(importance: int) -> bool:
	if my_firms("INN").is_empty():
		return false
	return should_spend(importance + pref("hire_unit") / 5 - 10)


## Nation::hire_unit: the best hero of the race the treasury can pay.
func hire_unit(race: String, spy: bool, dest: Vector2i) -> Unit:
	if not should_hire_unit(20):
		return null
	var best: Firm = null
	var best_i := -1
	var best_r := 0
	for inn in my_firms("INN"):
		for i in inn.heroes.size():
			var h: Dictionary = inn.heroes[i]
			if race != "" and h["race"] != race:
				continue
			if spy and int(h.get("spy_skill", 0)) == 0:
				continue
			if n.cash < float(h["cost"]):
				continue
			var r := int(h["leadership"]) - (100 - 100 * int(inn.center_loc().distance_to(Vector2(dest))) / g.world.w)
			if h["race"] == n.race:
				r += 50
			if r > best_r:
				best_r = r
				best = inn
				best_i = i
	return best.hire_hero(best_i) if best else null


func find_unit_from_camp(race: String, dest: Vector2i) -> Unit:
	var best: Firm = null
	var best_r := 0
	for c in camps():
		if c.soldiers.any(func(s): return s.race == race and s.basic_days <= 0):
			var r := distance_rating(Vector2(dest), c.center_loc())
			if r > best_r:
				best_r = r
				best = c
	if best == null:
		return null
	for s in best.soldiers:
		if s.race == race and s.basic_days <= 0:
			best.release_unit(s)
			return s
	return null


## Nation::recruit_peasant: from the nearest own town that can spare one.
func recruit_peasant(race: String, dest: Vector2i) -> Unit:
	var best: Town = null
	var best_r := 0
	for t in my_towns():
		if t.jobless() <= 0 or (race != "" and t.race != race):
			continue
		var r := distance_rating(t.center_loc(), Vector2(dest))
		if r > best_r:
			best_r = r
			best = t
	if best == null:
		return null
	if not best.can_recruit():
		if n.cash > 0.0:
			best.grant(n.id)
		if not best.can_recruit():
			return null
	return best.recruit()


## Nation::recruit_in_firm_soldier: a soldier from the camp with men to spare.
func recruit_in_firm_soldier(dest: Firm, race: String) -> Unit:
	if race == "":
		race = AIFirm.majority_race(dest)
		if race == "":
			return null
	var best: Firm = null
	var best_r := 0
	for c in camps():
		if c == dest:
			continue
		var r := (AIFirm.total_combat_level(c) - AIFirm.combat_level_needed(self, c)) / 3 + distance_rating(c.center_loc(), dest.center_loc())
		for s in c.soldiers:
			if s.basic_days <= 0 and s.race == race:
				r += 50
		if r > best_r:
			best_r = r
			best = c
	if best == null:
		return null
	var pick: Unit = null
	var pr := 0
	for s in best.soldiers:
		if s.basic_days > 0:
			continue
		var r := 50 if s.race == race else (20 if not s.is_human() else 10)
		if r > pr:
			pr = r
			pick = s
	if pick:
		best.release_unit(pick)
	return pick


# ------------------------------------------------------------ placement ---

## Nation::find_best_place_loc: weigh every spot around the reference place -
## nearer is better; near the kingdom's towns (and friendly or willing
## independent ones); factories and markets near mines, markets and
## factories; and never hard against another building or town.
func find_best_place(code: String, ref: GameObj, distance := IDEAL_INTER_PLACE_SPACE) -> Vector2i:
	var c := ref.center_loc()
	var eff := Defs.effective_distance(code, ref.code if ref is Firm else "")
	var pw := Defs.TOWN_SIZE
	var ph := Defs.TOWN_SIZE
	if code != "":
		var bd := Assets.firm_build(code, n.race)
		pw = bd.get("loc_w", 3)
		ph = bd.get("loc_h", 3)
	var rx1 := maxi(0, int(c.x) - eff - pw / 2)
	var ry1 := maxi(0, int(c.y) - eff - ph / 2)
	var rx2 := mini(g.world.w - 1, int(c.x) + eff)
	var ry2 := mini(g.world.h - 1, int(c.y) + eff)
	var rw := rx2 - rx1 + 1
	var rh := ry2 - ry1 + 1
	var m := PackedInt32Array()
	m.resize(rw * rh)
	for y in rh:
		for x in rw:
			m[y * rw + x] = 10 - maxi(absi(rx1 + x - int(c.x)), absi(ry1 + y - int(c.y)))
	var add := func(r: Rect2i, v: int) -> void:
		for y in range(maxi(ry1, r.position.y), mini(ry2, r.end.y - 1) + 1):
			for x in range(maxi(rx1, r.position.x), mini(rx2, r.end.x - 1) + 1):
				m[(y - ry1) * rw + (x - rx1)] += v
	var area := Rect2i(rx1 - 20, ry1 - 20, rw + 40, rh + 40)
	for f in g.firms:
		if f.dead or not area.intersects(f.footprint()):
			continue
		if (code == "MARKET" and f.code in ["MINE", "FACTORY"] or code == "FACTORY" and f.code in ["MINE", "MARKET"]) and f.nation_id == n.id:
			var e := Defs.effective_distance(f.code, code)
			add.call(Rect2i(Vector2i(f.center_loc()) - Vector2i.ONE * e, Vector2i.ONE * (e * 2 + 1)), 40)
		add.call(f.footprint().grow(distance), -20)
	for t in g.towns:
		if t.dead or not area.intersects(t.footprint()):
			continue
		var e := Defs.effective_distance("", code)
		var wa := t.population * 2
		if t.nation_id != n.id:
			if t.nation_id == 0:
				wa = wa * (100 - int(t.resistance_to(n.id))) / 100
			else:
				wa = wa * (relation(t.nation_id) + 1) / 4
		add.call(Rect2i(Vector2i(t.center_loc()) - Vector2i.ONE * e, Vector2i.ONE * (e * 2 + 1)), wa)
		add.call(t.footprint().grow(distance), -100)
	var best := Vector2i(-1, -1)
	var best_w := 0
	for y in range(ry1, ry2 - ph + 2):
		for x in range(rx1, rx2 - pw + 2):
			if code != "" and not g.can_build_firm(code, Vector2i(x, y), pw, ph):
				continue
			if code == "" and (not g.world.can_place(x, y, pw, ph) or g._overlaps_site(Rect2i(x, y, pw, ph))):
				continue
			var tot := 0
			for yy in ph:
				for xx in pw:
					tot += m[(y - ry1 + yy) * rw + (x - rx1 + xx)]
			var wv := tot / (pw * ph)
			if wv > best_w:
				best_w = wv
				best = Vector2i(x, y)
	return best


# ------------------------------------------------------------ economy ---

## Nation::think_build_firm (mines)
func think_build_firm() -> void:
	if not _should_build_mine():
		return
	_think_attack_units_standing_on_mine()
	if _think_build_mine():
		return
	_think_destroy_raw_site_guard()


## Nation::think_attack_units_standing_on_mine: idle units of a kingdom no
## better than neutral blocking a deposit are attacked with every camp.
func _think_attack_units_standing_on_mine() -> bool:
	for s in g.sites:
		if s.mine != null or g.world.can_place(s.x1, s.y1, s.w, s.h):
			continue
		for u in g.units:
			if u.dead or u.inside_firm != null or u.attacking or u.order != Unit.Order.IDLE or u.nation_id == n.id:
				continue
			if not s.footprint().has_point(u.cell()):
				continue
			if u.nation_id > 0 and relation(u.nation_id) <= Defs.Relation.NEUTRAL:
				AIAttack.attack_target(self, u, int(u.obj_power()), false, null, true)
				return true
	return false


## Nation::think_destroy_raw_site_guard: an idle unit of an unfriendly
## kingdom guarding a free deposit where we have a base is driven off.
func _think_destroy_raw_site_guard() -> bool:
	if not n.is_fryhtan and not my_towns().any(func(t): return t.is_base_town):
		return false
	for s in g.sites:
		if s.mine != null:
			continue
		for u in g.units:
			if u.dead or u.inside_firm != null or u.order != Unit.Order.IDLE or u.attacking or u.nation_id == n.id or u.nation_id <= 0:
				continue
			if not s.footprint().has_point(u.cell()) or relation(u.nation_id) >= Defs.Relation.PEACE:
				continue
			var m := AICapture.mobile_defense_combat_level(self, s.center_loc(), u.nation_id, true)
			if m[1] == -1:
				continue
			if AIAttack.attack_target(self, u, m[0], false, null, true):
				return true
	return false


## Nation::think_build_mine
func _think_build_mine() -> bool:
	var s := _seek_mine()
	if s == null:
		return false
	var mined := my_firms("MINE").filter(func(f): return f.raw == s.raw).size()
	if mined > 0 and not should_spend(20):
		return false
	if not g.config.get("explore", true) and g.config.get("setup", false):
		var ok := false
		for t in my_towns():
			if g.day > int(Vector2(s.x1, s.y1).distance_to(t.center_loc())) * (5 - _aggressiveness()) / 5:
				ok = true
				break
		if not ok:
			return false
	return not add_action(Vector2i(s.x1, s.y1), Vector2i(s.x1, s.y1), BUILD_FIRM, "MINE").is_empty()


## Nation::ai_should_build_mine
func _should_build_mine() -> bool:
	var jl := total_jobless()
	if jl < (100 - pref("economic_development")) / 2 or jl < 16:
		return false
	if not g.sites.any(func(s): return s.mine == null and s.reserve > 0.0):
		return false
	if not can_ai_build("MINE"):
		return false
	var mines := my_firms("MINE")
	if not mines.is_empty() and (true_profit() < 0.0 or total_population() < 40 + pref("economic_development") / 5):
		return false
	if action_exists(BUILD_FIRM, "MINE"):
		return false
	if jl < 30:
		for m in mines:
			if m.workers() < Defs.MAX_WORKER:
				return false
	return true


## Nation::seek_mine: a deposit of a kind we do not mine yet, nearest a town
## of ours; else of the kind we mine least.
func _seek_mine() -> Site:
	var mined := {}
	for m in my_firms("MINE"):
		mined[m.raw] = int(mined.get(m.raw, 0)) + 1
	var near := {}
	var near_d := {}
	for s in g.sites:
		if s.mine != null or s.reserve <= 0.0 or not g.world.can_place(s.x1, s.y1, s.w, s.h):
			continue
		if find_action(Vector2i(-1, -1), Vector2i(s.x1, s.y1), BUILD_FIRM, "MINE") != null:
			continue
		for t in my_towns():
			var d := maxf(absf(s.x1 - t.center_loc().x), absf(s.y1 - t.center_loc().y))
			if d < float(near_d.get(s.raw, INF)):
				near_d[s.raw] = d
				near[s.raw] = s
	var best: Site = null
	var best_d := INF
	for r in near:
		if not mined.has(r) and near_d[r] < best_d:
			best_d = near_d[r]
			best = near[r]
	if best == null:
		var least := 1 << 30
		for r in near:
			if int(mined.get(r, 0)) < least:
				least = int(mined.get(r, 0))
				best = near[r]
	return best


## Nation::think_reduce_expense: close the least productive war factory or tower.
func think_reduce_expense() -> void:
	if true_profit() > 0.0 or n.cash > 5000 * pref("cash_reserve") / 100:
		return
	var best: Firm = null
	var best_r := 0
	for f in my_firms():
		if f.code in ["WAR", "RESEARCH"]:
			var r := 100 - int(f.productivity())
			if r > best_r:
				best_r = r
				best = f
	if best:
		AIFirm.del_firm(self, best)


# ------------------------------------------------------------ military ---

## Nation::think_military: a new fort by the biggest base town when the army
## needs room, or close one down when food runs short.
func think_military() -> void:
	if yearly_food_change() < 0.0:
		return             # think_close_camp: does nothing in the original
	if not _should_expand_military() and not _troop_needs_camp():
		return
	var best: Town = null
	var best_r := 0
	for t in my_towns():
		if not t.is_base_town or t.no_neighbor_space:
			continue
		if t.population > best_r:
			best_r = t.population
			best = t
	if best == null:
		return
	var at := find_best_place("FORT", best)
	if at.x < 0:
		best.no_neighbor_space = true
		return
	add_action(at, Vector2i(best.x1, best.y1), BUILD_FIRM, "FORT")


func _should_expand_military() -> bool:
	if true_profit() < 0.0 or not should_spend(pref("military_development") / 2):
		return false
	var cs := camps()
	if cs.size() * 9 > total_jobless() * (50 + pref("military_development")) / 150:
		return false
	var free := 0
	for c in cs:
		if c.should_close:
			continue
		free += 9 - (int(c.overseer != null) + c.soldiers.size() + c.patrol_units.size())
		if c.ai_recruiting:
			return false
	return free < 9


func has_too_many_camps() -> bool:
	return camps().size() * 9 > total_jobless() * (150 + pref("military_development")) / 150


func _troop_needs_camp() -> bool:
	if has_too_many_camps() or not should_spend(50 + pref("military_development") / 2):
		return false
	var units := g.units.filter(func(u): return u.nation_id == n.id and not u.dead and not u.is_civilian() and (u.is_human() or u.is_weapon))
	var gens := units.filter(func(u): return u.rank == Defs.Rank.GENERAL).size()
	var cs := camps().size()
	return units.size() - cs * MAX_SOLDIER >= 9 + 20 * (100 - pref("military_development")) / 200 \
		and gens - cs >= 2 + 4 * (100 - pref("military_development")) / 200


## Nation::ai_defend: answer an attack on a town, building or leader.
func ai_defend(attacker: GameObj) -> void:
	if attacker == null or not is_instance_valid(attacker) or attacker.dead or g.day < last_defend_day + 7:
		return
	last_defend_day = g.day
	# the enemy's strength there less ours; ai_request_military_aid is disabled in the original
	var lvl: int = AICapture.mobile_defense_combat_level(self, attacker.center_loc(), attacker.nation_id, false)[0]
	AIAttack.attack_target(self, attacker, lvl, true)


func accepts_peace(from: int) -> bool:
	return Diplomacy.consider_cease_war(g, n, g.nation(from)) > 0
