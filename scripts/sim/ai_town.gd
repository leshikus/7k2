class_name AITown
extends RefCounted
## A computer kingdom's town thinking for itself (otownai.cpp, Town::process_ai):
## whether it is a base town, rewards and taxes, migration of an outlying
## village, a fort for protection, and - in base towns - scouting, walls,
## splitting when crowded, attacking enemies close by, capturing enemy towns,
## and the buildings it wants: market, tower of science, espionage college,
## training ground, war factory, Seat of Power, inn.

const MAX_TOWN_POPULATION := Defs.MAX_TOWN_POPULATION


static func process(ai: NationAI, t: Town, day: int) -> void:
	if t.dead or t.population == 0 or t.under_construction:
		return
	var id := t.obj_id
	if day % 30 == id % 30:
		update_base_town_status(ai, t)
	if day % 3 == id % 3:
		think_reward(ai, t)
	if should_migrate(ai, t):
		if day % 30 == id % 30:
			think_migrate(ai, t)
		return
	if day % 30 == id % 30 and not t.no_neighbor_space and t.population > 1:
		if think_build_fort(ai, t):
			return
	if not t.is_base_town:
		return
	if day % 30 == (id + 15) % 30:
		think_collect_tax(ai, t)
	if day % 30 == (id + 20) % 30:
		think_scout(ai, t)
	if day % 30 == (id + 25) % 30:
		think_build_wall(ai, t)
	if day % 30 == id % 30:
		think_split_town(ai, t)
		think_move_between_town(ai, t)
		if think_attack_nearby_enemy(ai, t):
			return
		if think_attack_linked_enemy(ai, t):
			return
	if day % 120 == id % 120:
		think_capture_enemy_town(ai, t)
	if day % 30 == (id + 2) % 30 and not t.no_neighbor_space and t.population >= 5:
		if think_build_market(ai, t):
			return
		if g_untapped(ai) and ai.my_firms("MINE").is_empty() and ai.true_profit() < 0.0:
			return
		if think_build_research(ai, t):
			return
		if think_build_spy(ai, t):
			return
		if ai.has_enough_food():
			if think_build_special(ai, t):
				return
			if think_build_war_factory(ai, t):
				return
			if think_build_base(ai, t):
				return
		think_build_inn(ai, t)


static func g_untapped(ai: NationAI) -> bool:
	return ai.g.sites.any(func(s): return s.mine == null and s.reserve > 0.0)


## Town::new_base_town_status
static func update_base_town_status(ai: NationAI, t: Town) -> void:
	t.is_base_town = _new_base_status(ai, t)


static func _new_base_status(ai: NationAI, t: Town) -> bool:
	var towns := ai.my_towns()
	if t.population > 20 + ai.pref("territorial_cohesiveness") / 10 or towns.size() == 1:
		return true
	if t.jobless() != t.population:
		return true
	for o in t.linked_towns():
		if o.nation_id == t.nation_id and o.is_base_town:
			return true
	if towns.filter(func(o): return o.is_base_town).size() <= 1:
		return not towns.any(func(o): return o.population > t.population)
	return false


## Town::think_reward
static func think_reward(ai: NationAI, t: Town) -> void:
	if not t.has_linked_camp(t.nation_id) or t.grant_penalty > 0:
		return
	if t.loyalty < Defs.REBEL_LOYALTY + 5 + ai.pref("loyalty_concern") / 10:
		var imp := 40 + t.population if t.loyalty < Defs.REBEL_LOYALTY + 5 else t.population
		if ai.should_spend(imp):
			t.grant(t.nation_id)


## Town::think_collect_tax
static func think_collect_tax(ai: NationAI, t: Town) -> void:
	if not t.has_linked_camp(t.nation_id) or should_migrate(ai, t) or t.tax_penalty > 0:
		return
	var profit := int(ai.true_profit())
	var min_loyalty := 55 + 30 * ai.pref("loyalty_concern") / 100
	if profit < 0:
		min_loyalty -= -profit / 100
	min_loyalty = maxi(55, min_loyalty)
	min_loyalty = maxi(min_loyalty, int(t.target_loyalty) - 10)
	if t.loyalty >= min_loyalty:
		t.collect_tax_cmd()


## Town::should_ai_migrate: a village of only jobless people while base towns exist.
static func should_migrate(ai: NationAI, t: Town) -> bool:
	if t.is_base_town or not ai.my_towns().any(func(o): return o.is_base_town):
		return false
	return t.population - t.jobless() <= 0


## Town::think_ai_migrate
static func think_migrate(ai: NationAI, t: Town) -> void:
	if ai.g.day < t.setup_day + 90:
		return
	var min_loyalty := 35 + 5 + ai.pref("loyalty_concern") / 10
	if t.loyalty < min_loyalty:
		if t.grant_penalty == 0 and t.target_loyalty < min_loyalty + 5 and ai.should_spend(20 + ai.pref("territorial_cohesiveness") / 2):
			t.grant(t.nation_id)
		if t.loyalty < min_loyalty:
			return
	var best: Town = null
	var best_r := 0
	for o in ai.my_towns():
		if o == t or not o.is_base_town or o.under_construction or o.race != t.race:
			continue
		if t.population > MAX_TOWN_POPULATION - o.population:
			continue
		var r := 1000 + ai.distance_rating(t.center_loc(), o.center_loc())
		if r > best_r:
			best_r = r
			best = o
	if best == null or ai.find_action(Vector2i(best.x1, best.y1), Vector2i(-1, -1), NationAI.SETTLE_TOWN, 0) != null:
		return
	var count := mini((int(t.loyalty) - Defs.MIN_RECRUIT_LOYALTY) / 5, t.jobless())
	if count > 0:
		ai.add_action(Vector2i(best.x1, best.y1), Vector2i(t.x1, t.y1), NationAI.SETTLE_TOWN, 0, count)


## Town::protection_needed / protection_available
static func protection_needed(t: Town) -> int:
	var p := t.population * 10
	for f in t.linked_firms:
		if f.nation_id != t.nation_id:
			continue
		if f.code == "MARKET":
			p += AIFirm.stock_value_index(f) * 2
		elif f.is_work_firm():
			p += int(f.productivity()) * 2
			if f.code == "MINE":
				p += 200
	return p


static func protection_available(t: Town) -> int:
	var p := 0
	for f in t.linked_firms:
		if f.nation_id == t.nation_id and Espionage.is_camp(f):
			p += 10 + AIFirm.total_combat_level(f)
	return p


## Town::think_build_fort
static func think_build_fort(ai: NationAI, t: Town) -> bool:
	var forts := 0
	for f in t.linked_firms:
		if f.code != "FORT" or f.nation_id != t.nation_id:
			continue
		if f.under_construction or f.ai_recruiting or f.soldiers.size() < NationAI.MAX_SOLDIER:
			return false
		forts += 1
	var build := forts == 0 and t.is_base_town and ai.my_towns().filter(func(o): return o.is_base_town).size() <= 2
	if not build:
		if not ai.should_spend(70 + ai.pref("military_development") / 4):
			return false
		var need := protection_needed(t)
		var have := protection_available(t)
		if have >= need:
			return false
		if not (need > 0 and have == 0):
			var urgency := 100 * (need - have) / need
			if ai.total_jobless() - Defs.MAX_WORKER < (100 - urgency) * (200 - ai.pref("military_development")) / 200:
				return false
		var jl := ai.total_jobless()
		if jl >= 30 or (jl >= 15 and t.is_base_town) or ai.camps().any(func(c): return c.should_close):
			build = true
		if not build:
			return false
	# a camp linked to the town is upgraded instead (Firm::start_upgrade)
	for f in t.linked_firms:
		if f.code == "CAMP" and f.nation_id == t.nation_id and not f.under_construction:
			return f.start_upgrade_to_fort()
	return build_neighbor_firm(ai, t, "FORT")


## Town::ai_build_neighbor_firm
static func build_neighbor_firm(ai: NationAI, t: Town, code: String, race := "") -> bool:
	var at := ai.find_best_place(code, t)
	if at.x < 0:
		t.no_neighbor_space = true
		return false
	return not ai.add_action(at, Vector2i(t.x1, t.y1), NationAI.BUILD_FIRM, code, 1, null, race).is_empty()


static func _has_own(t: Town, code: String) -> bool:
	return t.linked_firms.any(func(f): return f.code == code and f.nation_id == t.nation_id and not f.dead)


## Town::think_build_market
static func think_build_market(ai: NationAI, t: Town) -> bool:
	if ai.g.day < t.setup_day + 90:
		return false
	if t.population < 10 + (100 - ai.pref("trading_tendency")) / 20 or t.no_neighbor_space or should_migrate(ai, t):
		return false
	if not ai.can_ai_build("MARKET") or ai.build_action_near("MARKET", t.center_loc()) or _has_own(t, "MARKET"):
		return false
	return build_neighbor_firm(ai, t, "MARKET")


## Town::think_build_research
static func think_build_research(ai: NationAI, t: Town) -> bool:
	var n := ai.n
	if not ai.can_ai_build("RESEARCH"):
		return false
	if not ai.has_enough_food() and n.tech_level("FARMING") >= int(Defs.tech_def("FARMING")["max"]):
		return false
	var towers := ai.my_firms("RESEARCH")
	var pct := 50 + ai.pref("inc_pop_by_growth")
	if towers.is_empty():
		pct = mini(pct, 100)
	if t.jobless() < Defs.MAX_WORKER * pct / 200 or ai.total_jobless() < Defs.MAX_WORKER * 2 * pct / 200:
		return false
	var pop := maxi(1, ai.total_population())
	var workers := 0
	for f in towers:
		workers += f.workers()
	if 100 * workers / pop > 10 + ai.pref("research") / 3:
		return false
	var imp := 50 + ai.pref("research") / 2 - towers.size() * 10
	if towers.is_empty() and ai.pref("spy") > 0:
		imp += 50
	if not ai.should_spend(imp):
		return false
	if not Defs.research_techs().any(func(x): return Defs.can_research(n, x)):
		return false
	var max_r := mini(ai.my_towns().size(), 2 * (50 + ai.pref("use_weapon")) / 50)
	if towers.size() >= max_r:
		return false
	for f in towers:
		if f.workers() < Defs.MAX_WORKER:
			return false
	return build_neighbor_firm(ai, t, "RESEARCH")


## Town::think_build_spy
static func think_build_spy(ai: NationAI, t: Town) -> bool:
	if not ai.can_ai_build("SPY"):
		return false
	var spy_techs := 0
	for x in Defs.TECHS:
		if x.get("spy", false):
			spy_techs += ai.n.tech_level(x["code"])
	if spy_techs == 0:
		return false
	var p := 150 - ai.pref("spy")
	if t.jobless() < Defs.MAX_WORKER * p / 200 or ai.total_jobless() < Defs.MAX_WORKER * 2 * p / 200:
		return false
	if t.linked_firms.any(func(f): return f.code == "SPY"):
		return false
	if not ai.should_spend(20 + ai.pref("spy") / 2):
		return false
	return build_neighbor_firm(ai, t, "SPY", t.race)


## Town::think_build_special
static func think_build_special(ai: NationAI, t: Town) -> bool:
	if ai.n.tech_level(Defs.spu_structure_tech(t.race)) <= 0 or not ai.can_ai_build("STABLE"):
		return false
	var p := 150 - ai.pref("military_development")
	if t.jobless() < Defs.MAX_WORKER * p / 200 or ai.total_jobless() < Defs.MAX_WORKER * 2 * p / 200:
		return false
	if t.linked_firms.any(func(f): return f.code == "STABLE"):
		return false
	if not ai.should_spend(50 + ai.pref("military_development") / 2):
		return false
	return build_neighbor_firm(ai, t, "STABLE", t.race)


## Town::think_build_war_factory
static func think_build_war_factory(ai: NationAI, t: Town) -> bool:
	var n := ai.n
	if not ai.can_ai_build("WAR"):
		return false
	var p := 200 - ai.pref("use_weapon")
	if t.jobless() < Defs.MAX_WORKER * p / 200 or ai.total_jobless() < Defs.MAX_WORKER * 2 * p / 200:
		return false
	var wl := 0
	for w in Defs.WEAPONS:
		wl += n.tech_level(w)
	if wl == 0:
		return false
	var wars := ai.my_firms("WAR")
	if n.cash < 20000 * (100 + ai.pref("cash_reserve")) / 200:
		if ai.true_profit() < 0.0 and not wars.is_empty():
			return false
		if not ai.should_spend(30 + ai.pref("use_weapon") / 2):
			return false
	var max_w := mini(ai.my_towns().size(), (1 + wl) * ai.pref("use_weapon") / 100)
	if wars.size() >= max_w:
		return false
	for f in wars:
		if f.weapon == "":
			return false
	return build_neighbor_firm(ai, t, "WAR")


## Town::think_build_base: a Seat of Power of a Greater Being whose scroll we hold.
static func think_build_base(ai: NationAI, t: Town) -> bool:
	var n := ai.n
	if ai.my_firms("RESEARCH").is_empty() or ai.my_firms("MARKET").is_empty():
		return false
	if not ai.should_spend(40 + ai.pref("seat_of_power") / 2) or not ai.can_ai_build("BASE"):
		return false
	var p := 200 - ai.pref("seat_of_power")
	if t.jobless() < Defs.MAX_WORKER * p / 200 or ai.total_jobless() < Defs.MAX_WORKER * 2 * p / 200:
		return false
	var built := ai.my_firms("BASE").map(func(f): return f.race)
	for r in n.known_gods.keys():
		if r in built or not ai.g.nation_has_race_town(n.id, r):
			continue
		var town := t
		if t.race != r:
			var same := ai.my_towns().filter(func(o): return o.race == r)
			if same.is_empty():
				continue
			town = same[0]
		return build_neighbor_firm(ai, town, "BASE", r)
	return false


## Town::think_build_inn
static func think_build_inn(ai: NationAI, t: Town) -> bool:
	if ai.my_firms("INN").size() < supported_inn_count(ai) and ai.can_ai_build("INN"):
		if t.linked_firms.filter(func(f): return f.code == "INN" and f.nation_id == t.nation_id).size() >= 1:
			return false
		return build_neighbor_firm(ai, t, "INN")
	return false


## Nation::ai_supported_inn_count
static func supported_inn_count(ai: NationAI) -> int:
	var fixed := maxf(1.0, ai.n.last_expense_year if ai.n.last_expense_year > 0.0 else ai.n.expense_year)
	var supported := int(ai.n.cash / maxf(1000.0, fixed / 2.0))
	return clampi(supported, 0, 1 + ai.pref("hire_unit") / 50)


## Town::think_split_town
static func think_split_town(ai: NationAI, t: Town) -> void:
	if t.jobless() == 0 or t.population < (MAX_TOWN_POPULATION - 15) + ai.pref("territorial_cohesiveness") / 10:
		return
	for o in t.linked_towns():
		if o.nation_id == t.nation_id and o.population < 20 and o.race == t.race:
			return
	var at := ai.g._random_free_rect(Defs.TOWN_SIZE, Defs.TOWN_SIZE, 2, [], 0.0, 200)
	var near := ai.find_best_place("", t)
	if near.x >= 0:
		at = near
	if at.x < 0 or maxf(absf(at.x - t.center_loc().x), absf(at.y - t.center_loc().y)) > Defs.effective_distance("", ""):
		return
	var u := t.recruit()
	if u:
		u.order_found_town(at)


## Town::think_move_between_town: people move to a linked town of the same race
## that is smaller by more than 10.
static func think_move_between_town(ai: NationAI, t: Town) -> void:
	for o in t.linked_towns():
		if o.nation_id != t.nation_id or o.race != t.race:
			continue
		var guard := 0
		while t.population - o.population > 10 and guard < 50:
			guard += 1
			if not t.migrate_to(o):
				break


## Town::think_attack_nearby_enemy
static func think_attack_nearby_enemy(ai: NationAI, t: Town) -> bool:
	var r := t.footprint().grow(6)
	var level := 0
	var target: GameObj = null
	for u in ai.g.units:
		if u.dead or u.nation_id <= 0 or u.inside_firm or not r.has_point(u.cell()):
			continue
		if u.order == Unit.Order.IDLE and ai.relation(u.nation_id) == Defs.Relation.WAR:
			level += int(u.hp)
			if target == null or ai.g.rng.randi() % 5 == 0:
				target = u
	for f in ai.g.firms:
		if f.dead or f.nation_id <= 0 or not r.intersects(f.footprint()):
			continue
		if ai.relation(f.nation_id) == Defs.Relation.WAR:
			level += maxi(50, AIFirm.total_combat_level(f))
			if target == null or ai.g.rng.randi() % 5 == 0:
				target = f
	if level > 0 and target:
		AIAttack.attack_target(ai, target, level)
		return true
	return false


## Town::think_attack_linked_enemy
static func think_attack_linked_enemy(ai: NationAI, t: Town) -> bool:
	var n := ai.n
	for f in t.linked_firms:
		if f.nation_id == t.nation_id or f.nation_id <= 0 or f.should_close:
			continue
		var fn := f.nation()
		if fn and fn.is_ai and ai.relation(f.nation_id) != Defs.Relation.WAR:
			continue
		var lvl := 50
		if Espionage.is_camp(f):
			var st := ai.relation(f.nation_id)
			if st >= Defs.Relation.PEACE:
				if not AIGrand.should_attack_friendly(ai, f.nation_id, 100):
					continue
				AIGrand.end_treaty(ai, f.nation_id)
			elif st == Defs.Relation.NEUTRAL:
				if fn and Diplomacy.military_rank(ai.g, fn) > ai.military_rank():
					continue
			var tr := Diplomacy.trade_rating(ai.g, n, fn) if fn else 0
			if tr > 50 or (fn and tr + Diplomacy.trade_with_rating(ai.g, n, fn) > 100):
				continue
			lvl = AIFirm.total_combat_level(f)
		elif ai.relation(f.nation_id) != Defs.Relation.WAR:
			continue
		AIAttack.attack_target(ai, f, lvl)
		return true
	return false


## Town::think_capture_enemy_town
static func think_capture_enemy_town(ai: NationAI, t: Town) -> bool:
	if ai.capture_town:
		return false
	if protection_available(t) - protection_needed(t) < 300 - ai.pref("military_courage") * 2:
		return false
	return AICapture.think_capture_new_enemy_town(ai, t)


## Town::think_scout
static func think_scout(ai: NationAI, t: Town) -> void:
	if ai.g.config.get("explore", true) or not ai.g.config.get("setup", false):
		return
	if ai.g.day > 50 + ai.pref("scout") or ai.my_towns().size() > 1:
		return
	var c := t.center_loc()
	var dx := 50 + ai.g.rng.randi() % 50
	var dy := 50 + ai.g.rng.randi() % 50
	var dest := Vector2i(int(c.x) + (dx if ai.g.rng.randi() % 2 == 0 else -dx), int(c.y) + (dy if ai.g.rng.randi() % 2 == 0 else -dy))
	dest = Vector2i(clampi(dest.x, 0, ai.g.world.w - 1), clampi(dest.y, 0, ai.g.world.h - 1))
	ai.add_action(dest, Vector2i(t.x1, t.y1), NationAI.SCOUT, 0)


## Town::think_build_wall
static func think_build_wall(ai: NationAI, t: Town) -> void:
	if t.target_wall_level > t.wall_level or t.wall_level >= 2:
		return
	var imp := ai.pref("town_defense") / 3 + t.population / 2 + t.linked_firms.size() * 4
	var cost: float = Town.WALL_COST[t.wall_level + 1]
	if ai.should_spend(imp, cost):
		t.target_wall_level = t.wall_level + 1
