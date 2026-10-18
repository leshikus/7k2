class_name AICapture
extends RefCounted
## Taking towns (oai_capt.cpp, oai_cap2.cpp): independent villages whose
## resistance a good commander can bring low get a camp beside them; enemy
## towns have their defending camps and troops attacked first, then a camp
## is built to win the people over.

const MAX_CAPTURE_TOWN := 40
const MIN_CAPTURE_RESISTANCE_DEC := 20


## Nation::think_capture
static func think_capture(ai: NationAI) -> bool:
	if ai.camps().is_empty():
		return false
	if ai.my_firms("MINE").is_empty() and ai.total_population() < 25:
		return false
	if think_capture_independent(ai, false):
		return true
	return think_capture_independent(ai, true)


## Nation::think_capture_independent: villages in order of the resistance we
## can expect to bring them to, if below 30-50.
static func think_capture_independent(ai: NationAI, hire: bool) -> bool:
	var choices: Array = []
	for t in ai.g.towns:
		if t.dead or t.nation_id != 0 or t.no_neighbor_space or t.under_construction:
			continue
		if _rebel_town(ai, t):
			continue
		if not ai.my_towns().any(func(o): return o.is_base_town):
			continue
		var skip := false
		for f in t.linked_firms:
			if not Espionage.is_camp(f):
				continue
			if f.nation_id == ai.n.id:
				skip = true
				break
			if f.overseer and f.nation_id > 0 and f.overseer.lead_skill() >= 70.0 and f.overseer.race == t.race:
				skip = true
				break
		if skip:
			continue
		var ref := Vector2i(t.x1, t.y1)
		if ai.find_action(Vector2i(-1, -1), ref, NationAI.BUILD_FIRM, "CAMP") != null or ai.find_action(Vector2i(-1, -1), ref, NationAI.BUILD_FIRM, "FORT") != null:
			continue
		var r := capture_expected_resistance(ai, t, hire)
		if r < 50 - ai.pref("peacefulness") / 5 and choices.size() < MAX_CAPTURE_TOWN:
			choices.append([t, r])
	choices.sort_custom(func(a, b): return a[1] < b[1])
	for ch in choices:
		var t: Town = ch[0]
		if not ai.g.config.get("explore", true):
			var near := false
			for o in ai.my_towns():
				var d := int(maxf(absf(t.center_loc().x - o.center_loc().x), absf(t.center_loc().y - o.center_loc().y)))
				if ai.g.day > d * (5 - ai._aggressiveness()) / 5:
					near = true
					break
			if not near:
				continue
		if start_capture(ai, t, 0 if hire else 1):
			return true
	return false


static func _rebel_town(ai: NationAI, t: Town) -> bool:
	return ai.g.rebels.any(func(r): return r.get("town") == t)


## Nation::should_use_cash_to_capture
static func should_use_cash_to_capture(ai: NationAI) -> bool:
	if ai.n.cash >= 20000 * (200 + ai.pref("cash_reserve") - ai.pref("loyalty_concern")) / 200:
		return true
	return ai.military_rank() < 50 + ai.pref("peacefulness") / 5 and ai.should_spend(ai.pref("loyalty_concern") / 4)


## Nation::capture_expected_resistance
static func capture_expected_resistance(ai: NationAI, t: Town, hire: bool) -> int:
	if should_use_cash_to_capture(ai):
		return 0
	if hire:
		return hire_best_capturer(ai, t, false)
	return find_best_capturer(ai, t)[1]


## Nation::start_capture: 0 - hire a capturer, 1 - use one we have, 2 - try
## ours first. A fort (a quarter of the time, or when we can afford it) or a
## camp is built beside the town with him as its commander.
static func start_capture(ai: NationAI, t: Town, mode: int) -> bool:
	var u: Unit = null
	match mode:
		0:
			u = hire_best_capturer(ai, t, true)
		1:
			u = find_best_capturer(ai, t)[0]
		2:
			u = find_best_capturer(ai, t)[0]
			if u == null:
				u = hire_best_capturer(ai, t, true)
	if u == null:
		if should_use_cash_to_capture(ai):
			u = ai.get_unit(false, t.race, Vector2i(t.center_loc()))
		if u == null:
			return false
	var code := "FORT" if ai.g.rng.randi() % 4 == 0 or ai.should_spend(30 + ai.pref("military_development") / 3) else "CAMP"
	var at := ai.find_best_place(code, t)
	if at.x < 0:
		t.no_neighbor_space = true
		return false
	if not mobilize_capturer(ai, u):
		return false
	ai.add_action(at, Vector2i(t.x1, t.y1), NationAI.BUILD_FIRM, code, 1, u)
	return true


## Nation::find_best_capturer: our general of the town's race, idle and not
## busy winning another village, who would bring its resistance lowest.
## Returns [unit, expected resistance].
static func find_best_capturer(ai: NationAI, t: Town) -> Array:
	var best_r := 0
	if t.nation_id == 0:
		best_r = maxi(int(t.resistance_to(ai.n.id)) - MIN_CAPTURE_RESISTANCE_DEC, Defs.SURRENDER_RESISTANCE)
	else:
		best_r = maxi(int(t.loyalty) - MIN_CAPTURE_RESISTANCE_DEC, Defs.SURRENDER_LOYALTY)
	var best: Unit = null
	for u in ai.g.units:
		if u.dead or u.nation_id != ai.n.id or not u.is_human() or u.rank < Defs.Rank.GENERAL or u.race != t.race:
			continue
		if u.home_firm != null:
			continue
		if u.rank == Defs.Rank.KING and t.nation_id > 0:
			continue
		if u.inside_firm != null:
			if u.inside_firm.overseer != u:
				continue
			var busy := false
			for lt in u.inside_firm.linked_towns:
				if lt.nation_id == 0 and float(lt.target_resistance.get(ai.n.id, 100)) < lt.resistance_to(ai.n.id):
					busy = true
					break
			if busy:
				continue
		elif u.order != Unit.Order.IDLE:
			continue
		var r := 100 - t.commander_influence(u, ai.n)
		if r < best_r:
			best_r = r
			best = u
	return [best, best_r]


## Nation::mobilize_capturer: a commander leaves his camp.
static func mobilize_capturer(ai: NationAI, u: Unit) -> bool:
	if u.inside_firm != null and u.inside_firm.overseer == u:
		u.inside_firm.release_unit(u)
	return true


## Nation::hire_best_capturer: the inn hero of the town's race with the most
## leadership. hire_now: the hero, else the resistance we could expect.
static func hire_best_capturer(ai: NationAI, t: Town, hire_now: bool):
	if not ai.should_hire_unit(30):
		return null if hire_now else 0
	var best_inn: Firm = null
	var best_i := -1
	var best_r := 0
	for inn in ai.my_firms("INN"):
		for i in inn.heroes.size():
			var h: Dictionary = inn.heroes[i]
			if h["race"] != t.race or int(h.get("spy_skill", 0)) > 0 or ai.n.cash < float(h["cost"]):
				continue
			var r := int(h["leadership"])
			if r > Defs.CITIZEN_COMBAT_LEVEL and r > best_r:
				best_r = r
				best_inn = inn
				best_i = i
	if best_inn == null:
		return null if hire_now else 0
	if hire_now:
		var u := best_inn.hire_hero(best_i)
		if u:
			u.rank = Defs.Rank.GENERAL
		return u
	var h2: Dictionary = best_inn.heroes[best_i]
	var inf := int(minf(100.0, float(h2["leadership"]))) / 2
	inf = inf + inf / 3
	inf = clampi(inf + int(ai.n.reputation / 2.0), 0, 100)
	return 100 - inf


# -------------------------------------------------------- enemy towns ---

## Nation::think_capture_new_enemy_town
static func think_capture_new_enemy_town(ai: NationAI, from: Town, use_all := false) -> bool:
	if ai.camps().is_empty() or ai.capture_town:
		return false
	if ai.n.cash < 1000 + 2000 * ai.pref("cash_reserve") / 100:
		return false
	var t := _think_capture_enemy_town_target(ai, from)
	if t == null:
		return false
	var rc := attack_enemy_town_defense(ai, t, use_all)
	if rc == 1:
		ai.capture_town = t
		ai.capture_plan_day = ai.g.day
		ai.capture_start_day = 0
		ai.capture_use_all = use_all
		return true
	if rc == -1:
		return start_capture(ai, t, 2)
	return false


## Nation::think_capturing_enemy_town: watch the attack, send reinforcements,
## and build the camp once the defenders are gone.
static func think_capturing_enemy_town(ai: NationAI) -> void:
	var t: Town = ai.capture_town
	if t == null:
		return
	if not is_instance_valid(t) or t.dead or t.nation_id == ai.n.id:
		ai.capture_town = null
		return
	var m := mobile_defense_combat_level(ai, t.center_loc(), t.nation_id, false)
	var has_war: int = m[1]
	if ai.capture_start_day == 0:
		if has_war == 2:
			ai.capture_start_day = ai.g.day
		if ai.g.day > ai.capture_plan_day + 90:
			ai.capture_town = null
		return
	if ai.g.day - ai.capture_start_day >= 15 and m[0] > 0 and has_war == 2:
		AIAttack.attack_at(ai, t.center_loc(), m[0], true)
		return
	if has_war != 2:
		var rc := attack_enemy_town_defense(ai, t, ai.capture_use_all)
		if rc == 1:
			ai.capture_start_day = 0
			return
		ai.capture_town = null
		ai.capture_start_day = 0
		if rc == -1:
			start_capture(ai, t, 2)


## Nation::attack_enemy_town_defense: 1 - troops sent, 0 - not strong enough,
## -1 - nothing defends the town.
static func attack_enemy_town_defense(ai: NationAI, t: Town, use_all := false) -> int:
	if t.nation_id == 0:
		return -1
	var best: Firm = null
	var max_lvl := -1
	for f in t.linked_firms:
		if f.nation_id == t.nation_id and Espionage.is_camp(f):
			var lvl := AIFirm.total_combat_level(f)
			if lvl > max_lvl:
				max_lvl = lvl
				best = f
	var mob: int = mobile_defense_combat_level(ai, t.center_loc(), t.nation_id, false)[0]
	var total := max_lvl + mob
	if best:
		var tn := ai.g.nation(best.nation_id)
		if tn and ai.g.nations.any(func(o): return o != tn and o.alive and tn.relation(o.id) == Defs.Relation.WAR):
			use_all = true
		return 1 if AIAttack.attack_target(ai, best, total, false, null, use_all) else 0
	if mob > 0:
		return 1 if AIAttack.attack_at(ai, t.center_loc(), total, true) else 0
	return -1


## Nation::think_capture_enemy_town_target: hostile (or much disliked) towns
## not yet beside one of our camps, weighed by distance, defence, loyalty,
## size, relative strength, the player first at higher aggressiveness, and
## mines of materials we lack.
static func _think_capture_enemy_town_target(ai: NationAI, from: Town) -> Town:
	var ours := ai.military_rank()
	var best: Town = null
	var best_r := -1000
	var biggest := _max_overall_nation(ai)
	var mined := {}
	for m in ai.my_firms("MINE"):
		mined[m.raw] = true
	for t in ai.g.towns:
		if t.dead or t.nation_id == 0 or t.nation_id == ai.n.id:
			continue
		if t.has_linked_camp(ai.n.id) or _has_any_camp(t, ai.n.id):
			continue
		var st := ai.relation(t.nation_id)
		var lvl := Diplomacy.ai_rel(ai.n, t.nation_id)
		var ok := st == Defs.Relation.WAR or lvl < 10 or (st <= Defs.Relation.NEUTRAL and t.nation_id == biggest and lvl < 30)
		if not ok:
			continue
		if _has_any_camp(t, t.nation_id):
			return t
		var tn := ai.g.nation(t.nation_id)
		var theirs := Diplomacy.military_rank(ai.g, tn)
		if theirs > ours * (80 + ai.pref("military_courage") / 2) / 100:
			continue
		if not ai.should_spend_war(theirs):
			continue
		var lvl_t := enemy_town_combat_level(ai, t, true)
		if lvl_t == -1:
			continue
		var r := ai.distance_rating(from.center_loc(), t.center_loc())
		r -= lvl_t / 10
		r -= int(t.loyalty)
		r += t.population
		r += 2 * (ours - theirs)
		if tn and not tn.is_ai:
			if ai.g.config.has("tutorial"):
				continue
			match ai._aggressiveness():
				GameSetup.MODERATE:
					r += 100
				GameSetup.HIGH:
					r += 300
				GameSetup.VERY_HIGH:
					r += 500
		for f in t.linked_firms:
			if f.nation_id == t.nation_id and f.code == "MINE" and not mined.has(f.raw):
				r += int(150.0 * f.reserve / Defs.MAX_RAW_RESERVE_QTY)
		r += t.linked_firms.size() * 5
		if r > best_r:
			best_r = r
			best = t
	return best


static func _has_any_camp(t: Town, nid: int) -> bool:
	return t.linked_firms.any(func(f): return f.nation_id == nid and Espionage.is_camp(f))


static func _max_overall_nation(ai: NationAI) -> int:
	var best := 0
	var best_r := -1
	for o in ai.g.nations:
		if not o.alive:
			continue
		var r := Diplomacy.overall_rank(ai.g, o)
		if r > best_r:
			best_r = r
			best = o.id
	return best


## Nation::enemy_town_combat_level: troops around it plus its camps; -1 if a battle is on.
static func enemy_town_combat_level(ai: NationAI, t: Town, return_if_war: bool) -> int:
	var m := mobile_defense_combat_level(ai, t.center_loc(), t.nation_id, return_if_war)
	if m[0] < 0 and return_if_war and m[1] < 0:
		return -1
	var lvl: int = m[0]
	for f in t.linked_firms:
		if f.nation_id == t.nation_id and Espionage.is_camp(f):
			lvl += AIFirm.total_combat_level(f)
	return lvl


## Nation::enemy_firm_combat_level: troops around it plus the camps of the towns it serves.
static func enemy_firm_combat_level(ai: NationAI, f: Firm, return_if_war: bool) -> int:
	var m := mobile_defense_combat_level(ai, f.center_loc(), f.nation_id, return_if_war)
	if return_if_war and m[1] < 0:
		return -1
	var lvl: int = m[0]
	for t in f.linked_towns:
		if t.nation_id != f.nation_id:
			continue
		for c in t.linked_firms:
			if c.nation_id == f.nation_id and Espionage.is_camp(c):
				lvl += AIFirm.total_combat_level(c)
	return lvl


## Nation::mobile_defense_combat_level: [the defenders' net power around the
## place within 5 + 2 x aggressiveness, has_war]; has_war is -1 when
## return_if_war and a battle is going on there, 1 for a battle, 2 for one
## we are in.
static func mobile_defense_combat_level(ai: NationAI, c: Vector2, target_nation: int, return_if_war: bool) -> Array:
	var r := net_attacker_power_in_area(ai.g, c, ai.n.id, target_nation, return_if_war, 5 + ai._aggressiveness() * 2)
	if r[1] == -1:
		return [-1, -1]
	return [-r[0], r[1]]


## World::net_attacker_power_in_area: [our power less the defender's, has_war].
static func net_attacker_power_in_area(g: Game, c: Vector2, attacker: int, defender: int, return_if_war: bool, scan: int) -> Array:
	var area := Rect2(c - Vector2(scan, scan), Vector2(scan * 2 + 1, scan * 2 + 1))
	var net := 0.0
	var has_war := 0
	for u in g.units_near(c, float(scan) + 1.0):
		if u.dead or u.inside_firm != null or not area.has_point(u.center_loc()):
			continue
		if u.attacking:
			if return_if_war:
				return [0, -1]
			has_war = 2 if u.nation_id == attacker else maxi(has_war, 1)
		if u.order != Unit.Order.MOVE and u.order != Unit.Order.ATTACK:
			continue
		if u.nation_id == attacker:
			net += u.obj_power()
		elif u.nation_id == defender:
			net -= u.obj_power()
	# places that shoot of their own accord: towers, and forts with archers
	for f in g.firms:
		if f.dead or f.under_construction or not area.has_point(f.center_loc()):
			continue
		if not (Firm.TOWER_FIRMS.has(f.code) or (f.code == "FORT" and f.archers > 0)):
			continue
		if f.nation_id == attacker:
			net += AIFirm.obj_power(f)
		elif f.nation_id == defender:
			net -= AIFirm.obj_power(f)
	return [int(net), has_war]


# ------------------------------------------------------------- spies ---

## Nation::ai_assign_spy_to_town / ai_assign_spy: a spy of the town's race
## goes in. (The original's ai_find_spy never matches an existing spy, so a
## spy is hired at an inn or, failing that, trained at a college - which
## takes time, so nothing is assigned yet.)
static func assign_spy_to_town(ai: NationAI, t: Town, race: String) -> bool:
	if t.population >= Defs.MAX_TOWN_POPULATION:
		return false
	if race == "":
		race = t.race
	var at := Vector2i(t.x1, t.y1)
	var u := ai.hire_unit(race, true, at)
	if u == null:
		train_spy(ai, race, true, t.center_loc())
		return false
	u.is_spy = true
	return not ai.add_action(at, Vector2i(-1, -1), NationAI.ASSIGN_SPY, t.nation_id, 1, u).is_empty()


## Nation::train_spy: at the college nearest the target, from its best town.
static func train_spy(ai: NationAI, race: String, civilian: bool, dest: Vector2) -> bool:
	var cols := ai.my_firms("SPY").filter(func(f): return not f.under_construction)
	if cols.is_empty():
		return false
	var best := ai.g.rng.randi() % cols.size()
	var best_r := 0
	for i in cols.size():
		var r := ai.distance_rating(dest, cols[i].center_loc())
		if r > best_r:
			best_r = r
			best = i
	var type := Training.CIVILIAN if civilian else Training.INFANTRY
	for k in cols.size():
		best = (best + 1) % cols.size()
		var col: Firm = cols[best]
		for t in Training.best_towns(col, type):
			if t.race == race and Training.can_recruit(col, t, type):
				return Training.recruit(col, t, type)
	return false
