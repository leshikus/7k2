class_name NationAI
extends RefCounted
## Computer-controlled kingdom. A compact take on the oai_*.cpp strategies:
## secure towns with camps, build the mine-factory-market chain, research,
## win independent towns over with camps and grants, and attack weaker rivals.

const RESEARCH_ORDER := ["MINING", "MANUFACT", "INFCLOSE", "FARMING", "INFDEFEN", "CATAPULT", "INFRANGE", "BALLISTA", "WAR_PROD", "FLAMETHR", "CANNON"]

var n: Nation
var g: Game
var war_target := 0
var war_start_day := 0
var attack_target: GameObj = null
var aggression := 1.0


func _init(nation: Nation, game: Game) -> void:
	n = nation
	g = game
	aggression = g.rng.randf_range(0.7, 1.4)


var _last_close := -999


func next_day(day: int) -> void:
	if not n.alive or (day + n.id * 3) % 7 != 0:
		return
	if my_towns().is_empty() and my_firms().is_empty():
		_homeless(day)
		return
	_garrisons()
	_economy(day)
	_expand(day)
	_military(day)
	_use_gods()
	_diplomacy(day)


# ---------------------------------------------------------------- helpers ---

func my_towns() -> Array:
	return g.towns.filter(func(t): return t.nation_id == n.id and not t.dead)


func my_firms(code := "") -> Array:
	return g.firms.filter(func(f): return f.nation_id == n.id and not f.dead and (code == "" or f.code == code))


func idle_units(humans_only := true) -> Array:
	return g.units.filter(func(u): return u.nation_id == n.id and not u.dead and u.inside_firm == null and u.order == Unit.Order.IDLE and u.home_town == null and (not humans_only or u.is_human()))


func _builder_near(c: Vector2) -> Unit:
	var best: Unit = null
	var best_d := INF
	for u in idle_units():
		if u.rank == Defs.Rank.KING:
			continue
		var d: float = u.center_loc().distance_to(c)
		if d < best_d:
			best_d = d
			best = u
	if best == null:
		# recruit a builder from the most loyal town
		var towns := my_towns().filter(func(t): return t.can_recruit() and t.population > 12)
		towns.sort_custom(func(a, b): return a.loyalty > b.loyalty)
		if not towns.is_empty():
			best = towns[0].recruit()
	return best


func _has_market_chain(m: Firm) -> bool:
	for f in m.linked_firms:
		if f.code == "FACTORY" and f.nation_id == n.id and not f.under_construction:
			if f.linked_firms.any(func(x): return x.code == "MARKET" and x.nation_id == n.id and not x.under_construction):
				return true
	return false


func _close_unprofitable() -> void:
	# mines (600/yr) that do not end in a market, then idle luxuries
	for m in my_firms("MINE"):
		if not m.under_construction and not _has_market_chain(m):
			m.die(null)
			return
	for f in my_firms("FACTORY"):
		if not f.linked_firms.any(func(x): return x.code == "MARKET" and x.nation_id == n.id):
			f.die(null)
			return
	# luxuries next; defences (towers, forts) are kept until the debt is crippling
	for code in ["INN", "SPY", "STABLE", "WAR"]:
		var l := my_firms(code)
		if not l.is_empty():
			l[0].die(null)
			return
	for r in my_firms("RESEARCH"):
		if r.research_tech == "":
			r.die(null)
			return
	if n.cash > -2000:
		return
	for f in my_firms():
		if Firm.TOWER_FIRMS.has(f.code):
			f.die(null)
			return
	for code in ["BASE"]:
		var l := my_firms(code)
		if not l.is_empty():
			l[0].die(null)
			return
	for r in my_firms("RESEARCH"):
		if r.research_tech == "":
			r.die(null)
			return


func _nearest_own_town(c: Vector2) -> Town:
	var best: Town = null
	for t in my_towns():
		if best == null or t.center_loc().distance_to(c) < best.center_loc().distance_to(c):
			best = t
	return best


func _under_construction() -> bool:
	for f in my_firms():
		if f.under_construction:
			return true
	return false


func _try_build(code: String, near: Rect2i, anchors: Array = []) -> Firm:
	var cost := float(Defs.firm_types.get(code, {}).get("cost", 200))
	if not n.can_afford(cost):
		return null
	var b := Assets.firm_build(code, n.race)
	var pos := g._place_near(near, b.get("loc_w", 5), b.get("loc_h", 5), 8, anchors)
	if pos.x < 0:
		return null
	var builder := _builder_near(Vector2(pos))
	if builder == null:
		return null
	var f := g.spawn_firm(code, n.id, n.race, pos, false)
	if f == null:
		return null
	n.add_cash(-cost)
	builder.order_build(f)
	return f


func _resume_construction() -> void:
	for f in my_firms():
		if f.under_construction and (f.builder == null or not is_instance_valid(f.builder) or f.builder.dead):
			var busy := g.units.any(func(u): return u.nation_id == n.id and u.order == Unit.Order.BUILD and u.order_firm == f)
			if not busy:
				var b := _builder_near(f.center_loc())
				if b:
					b.order_build(f)


# -------------------------------------------------------------- garrisons ---

func _garrisons() -> void:
	_resume_construction()
	for f in my_firms():
		if not (f.code in Firm.MILITARY_FIRMS) or f.under_construction:
			continue
		var heading := g.units.any(func(u): return u.nation_id == n.id and u.order == Unit.Order.ENTER and u.order_firm == f)
		if f.overseer == null and not heading:
			var gen := _best_idle_leader(f.center_loc())
			if gen:
				gen.order_enter(f)
				continue
		if f.soldiers.size() < f.capacity() * 2 / 3 and n.cash > 200:
			var linked: Array = f.linked_towns.filter(func(t): return t.nation_id == n.id and t.loyalty >= 50 and t.population > 25)
			if not linked.is_empty():
				var u: Unit = linked[0].recruit()
				if u:
					u.order_enter(f)


func _best_idle_leader(c: Vector2) -> Unit:
	var best: Unit = null
	for u in idle_units():
		if u.rank == Defs.Rank.GENERAL and (best == null or u.leadership > best.leadership):
			best = u
	if best == null:
		for u in idle_units():
			if u.rank == Defs.Rank.SOLDIER and (best == null or u.leadership > best.leadership):
				best = u
		if best:
			best.rank = Defs.Rank.GENERAL
			best.leadership = maxf(best.leadership, 30.0)
	return best


# --------------------------------------------------------------- economy ---

func _economy(day: int) -> void:
	var towns := my_towns()
	if towns.is_empty():
		return
	# in debt: close a building that earns nothing, at most one a month
	if n.cash < -100 and day - _last_close >= 30:
		_last_close = day
		_close_unprofitable()
	# taxes when short of money
	if n.cash < 300:
		for t in towns:
			if t.loyalty > 65:
				t.collect_tax()
	# walls for towns at war, once the economy can afford them
	if war_target > 0 and n.cash > 2000:
		for t in towns:
			if t.target_wall_level < 2 and t.population > 25:
				t.build_wall()
				break
	# grants to keep towns loyal
	for t in towns:
		if t.loyalty < 40 and n.cash > t.grant_cost() * 4:
			t.grant(n.id)
	if _under_construction():
		return
	# every town needs a camp
	for t in towns:
		if not t.linked_firms.any(func(f): return f.nation_id == n.id and f.code in Firm.MILITARY_FIRMS):
			if _try_build("CAMP", t.footprint()):
				return
	# Keep at least a third of the people farming (Town::process_food): only add
	# workplaces while their staff would fit within 60% of the population.
	var pop := 0
	for t in towns:
		pop += t.population
	var work_slots := my_firms().filter(func(f): return f.is_work_firm()).size() * Defs.MAX_WORKER
	var can_employ := n.cash > 0 and work_slots < pop * 2
	if n.food < 0:
		for r in my_firms("RESEARCH"):
			if n.tech_level("FARMING") < Defs.tech_def("FARMING")["max"]:
				r.start_research("FARMING")
	if not can_employ:
		return
	# mines on deposits near our towns
	for s in g.sites:
		if s.mine != null or s.reserve < 1000:
			continue
		for t in towns:
			if Game._center_dist(s.center_loc(), t.center_loc()) <= Defs.EFFECTIVE_FIRM_TOWN_DISTANCE:
				# only start a mine when the whole mine-factory-market chain is affordable
				if n.cash > 1300 and my_firms("MINE").filter(func(m): return not m.linked_firms.any(func(f): return f.code == "FACTORY")).is_empty():
					var b := _builder_near(s.center_loc())
					if b:
						var f := g.spawn_firm("MINE", n.id, n.race, Vector2i(s.x1, s.y1), false)
						if f:
							n.add_cash(-float(Defs.firm_types["MINE"]["cost"]))
							b.order_build(f)
							return
				break
	# factories must reach both a mine and a town (for workers); markets a factory and a town
	for m in my_firms("MINE"):
		if not m.linked_firms.any(func(f): return f.code == "FACTORY" and f.nation_id == n.id):
			var t := _nearest_own_town(m.center_loc())
			if t and _try_build("FACTORY", t.footprint(), [m.center_loc(), t.center_loc()]):
				return
	for fa in my_firms("FACTORY"):
		if not fa.linked_firms.any(func(f): return f.code == "MARKET" and f.nation_id == n.id):
			var t := _nearest_own_town(fa.center_loc())
			if t and _try_build("MARKET", t.footprint(), [fa.center_loc(), t.center_loc()]):
				return
	if day > 200 and my_firms("RESEARCH").is_empty() and n.cash > 1200:
		if _try_build("RESEARCH", towns[0].footprint()):
			return
	for r in my_firms("RESEARCH"):
		if r.research_tech == "" and not r.under_construction:
			for code in RESEARCH_ORDER:
				var t := Defs.tech_def(code)
				var ok: bool = n.tech_level(code) < t["max"]
				if t.has("req") and n.tech_level(t["req"]) < t["req_lvl"]:
					ok = false
				if ok:
					r.start_research(code)
					break
	if day > 400 and my_firms("INN").is_empty() and n.cash > 1500:
		if _try_build("INN", towns[0].footprint()):
			return
	for inn in my_firms("INN"):
		if not inn.heroes.is_empty() and n.cash > 2500:
			inn.hire_hero(0)
	# spies: agitate the towns of the kingdom we are at war with
	if day > 800 and my_firms("SPY").is_empty() and n.cash > 2500 and war_target > 0:
		if _try_build("SPY", towns[0].footprint(), [towns[0].center_loc()]):
			return
	for sc in my_firms("SPY"):
		if sc.weapon_queue == 0 and n.cash > 1500 and g.units.filter(func(u): return u.is_spy and u.nation_id == n.id).size() < 3:
			sc.weapon_queue = 1
	for sp in g.units:
		if sp.is_spy and sp.nation_id == n.id and not sp.dead and sp.order == Unit.Order.IDLE and not sp.has_meta("hidden") and war_target > 0:
			var tt: Array = g.towns.filter(func(t): return t.nation_id == war_target and not t.dead)
			if not tt.is_empty():
				sp.order_infiltrate(tt[g.rng.randi() % tt.size()])
	# caravans between our markets and those of friendly kingdoms
	if n.cash > 900:
		for mk in my_firms("MARKET"):
			if not mk.under_construction and g.caravans_of(mk) < 1 and g.find_trade_partner(mk, n.id) != null:
				mk.hire_caravan()
				break
	if day > 500 and my_firms("STABLE").is_empty() and n.cash > 1200:
		if _try_build("STABLE", towns[0].footprint(), [towns[0].center_loc()]):
			return
	for st in my_firms("STABLE"):
		if st.weapon == "" and n.cash > 700 and (war_target > 0 or n.cash > 2500):
			st.queue_weapon(st.special_unit())
	if day > 700 and my_firms("WAR").is_empty() and n.cash > 2000 and n.tech_level("CATAPULT") > 0:
		if _try_build("WAR", towns[0].footprint()):
			return
	for wf in my_firms("WAR"):
		if wf.weapon == "" and n.cash > 1500:
			for wcode in ["CANNON", "FLAMETHR", "BALLISTA", "CATAPULT"]:
				if n.tech_level(wcode) > 0:
					wf.queue_weapon(wcode)
					break
	if day > 900 and my_firms("BASE").is_empty() and n.cash > 3500:
		var same_race := towns.filter(func(t): return t.race == n.race)
		if not same_race.is_empty() and _try_build("BASE", same_race[0].footprint()):
			return
	for b in my_firms("BASE"):
		if n.prayer_points >= b.god_cost() and war_target > 0:
			var god: Unit = b.invoke_god()
			if god and attack_target and is_instance_valid(attack_target) and not attack_target.dead:
				god.order_attack(attack_target)


# ------------------------------------------------------------- expansion ---

func _expand(_day: int) -> void:
	var towns := my_towns()
	if towns.is_empty():
		return
	var best: Town = null
	var best_d := 34.0
	for t in g.towns:
		if t.nation_id != 0 or t.dead:
			continue
		for mt in towns:
			var d := t.center_loc().distance_to(mt.center_loc())
			if d < best_d:
				best_d = d
				best = t
	if best == null:
		return
	if best.has_linked_camp(n.id):
		if n.cash > best.grant_cost() * 3 and best.resistance_to(n.id) < 60 and best.resistance_to(n.id) > Defs.SURRENDER_RESISTANCE:
			best.grant(n.id)
		return
	var pending := best.linked_firms.any(func(f): return f.nation_id == n.id and f.code in Firm.MILITARY_FIRMS)
	if not pending and not _under_construction():
		_try_build("CAMP", best.footprint())


# -------------------------------------------------------------- military ---

func _military(day: int) -> void:
	var army := idle_units(false).filter(func(u): return u.can_attack() and u.rank != Defs.Rank.KING)
	var mine := g.military_strength(n.id)
	# pick a war
	if war_target == 0 and day > int(700 / aggression):
		var weakest := 0
		var weakest_s := INF
		for o in g.nations:
			if o.id == n.id or not o.alive or n.relation(o.id) >= Defs.Relation.PEACE:
				continue
			var s := g.military_strength(o.id)
			if s < weakest_s:
				weakest_s = s
				weakest = o.id
		if weakest > 0 and mine > weakest_s * (1.6 / aggression) and g.rng.randf() < 0.2:
			war_target = weakest
			war_start_day = day
			g.declare_war(n.id, weakest)
	if war_target > 0:
		var wn := g.nation(war_target)
		if wn == null or not wn.alive or n.relation(war_target) != Defs.Relation.WAR:
			war_target = 0
			attack_target = null
	# also respond to anyone at war with us; the standing war with Fryhtan
	# kingdoms only becomes an offensive once the kingdom is established
	if war_target == 0:
		for o in g.nations:
			if o.alive and o.id != n.id and n.relation(o.id) == Defs.Relation.WAR:
				if o.is_fryhtan and (day < 700 or mine < g.military_strength(o.id) * 1.2):
					continue
				war_target = o.id
				war_start_day = day
				break
	if attack_target == null or not is_instance_valid(attack_target) or attack_target.dead or attack_target.nation_id != war_target:
		attack_target = _pick_target()
	# pull soldiers out of camps to form an army
	if war_target > 0 and army.size() < 8:
		for f in my_firms():
			if f.code in Firm.MILITARY_FIRMS and f.soldiers.size() > 3:
				for i in f.soldiers.size() - 2:
					f.release_unit(f.soldiers[0])
	army = idle_units(false).filter(func(u): return u.can_attack() and u.rank != Defs.Rank.KING)
	if attack_target and army.size() >= 6:
		for u in army:
			u.order_attack(attack_target)
		return
	# clear nearby Fryhtan lairs when strong enough
	if army.size() >= 8:
		var lair := _nearest_lair()
		if lair:
			for u in army:
				u.order_attack(lair)
			return
	# otherwise park extra soldiers in camps
	if war_target == 0:
		for u in army:
			if u.rank == Defs.Rank.GENERAL and not u.is_hero:
				continue
			for f in my_firms():
				if f.code in Firm.MILITARY_FIRMS and not f.under_construction and f.soldiers.size() < f.capacity():
					u.order_enter(f)
					break


## An army without a home (a scenario's invaders, or the remains of a beaten
## kingdom): win a base by wearing down the nearest independent town until it
## surrenders, otherwise make war on the nearest kingdom it is not at peace with.
func _homeless(day: int) -> void:
	var army := g.units.filter(func(u): return u.nation_id == n.id and not u.dead and u.inside_firm == null and u.can_attack())
	if army.is_empty():
		return
	var c := Vector2.ZERO
	for u in army:
		c += u.center_loc()
	c /= army.size()
	if attack_target != null and is_instance_valid(attack_target) and not attack_target.dead and attack_target.nation_id != n.id:
		for u in army:
			if u.order == Unit.Order.IDLE and u.rank != Defs.Rank.KING:
				u.order_attack(attack_target)
		return
	var best: GameObj = null
	var best_d := INF
	for t in g.towns:
		if t.nation_id == 0 and not t.dead:
			var d := c.distance_to(t.center_loc())
			if d < best_d:
				best_d = d
				best = t
	if best == null or best_d > 60.0:
		# no village to take nearby: attack the closest rival not at peace with us
		for o in g.nations:
			if o.id == n.id or not o.alive or n.relation(o.id) >= Defs.Relation.PEACE:
				continue
			for obj in g.firms + g.towns:
				if obj.nation_id == o.id and not obj.dead:
					var d := c.distance_to(obj.center_loc())
					if d < best_d:
						best_d = d
						best = obj
		if best != null and best.nation_id > 0 and n.relation(best.nation_id) != Defs.Relation.WAR:
			g.declare_war(n.id, best.nation_id)
			war_target = best.nation_id
			war_start_day = day
	attack_target = best
	if best == null:
		return
	for u in army:
		if u.rank != Defs.Rank.KING or army.size() == 1:
			u.order_attack(best)


func _pick_target() -> GameObj:
	if war_target == 0:
		return null
	var home := my_towns()
	var c: Vector2 = home[0].center_loc() if not home.is_empty() else Vector2(g.world.w / 2.0, g.world.h / 2.0)
	var best: GameObj = null
	var best_d := INF
	for f in g.firms:
		if f.nation_id == war_target and not f.dead:
			var d := c.distance_to(f.center_loc()) * (0.7 if f.code in Firm.MILITARY_FIRMS else 1.0)
			if d < best_d:
				best_d = d
				best = f
	if best == null:
		for t in g.towns:
			if t.nation_id == war_target and not t.dead:
				var d := c.distance_to(t.center_loc())
				if d < best_d:
					best_d = d
					best = t
	return best


func _nearest_lair() -> Firm:
	var home := my_towns()
	if home.is_empty():
		return null
	var c: Vector2 = home[0].center_loc()
	var best: Firm = null
	var best_d := 40.0
	for f in g.firms:
		if f.code == "LAIR" and not f.dead:
			var d := c.distance_to(f.center_loc())
			if d < best_d:
				best_d = d
				best = f
	return best


# ------------------------------------------------------------- diplomacy ---

func _use_gods() -> void:
	for u in g.units:
		if u.is_god and u.nation_id == n.id and not u.dead and u.can_cast_power():
			if g.find_enemy_near(u, float(u.god_info().get("cast_range", 6))):
				u.cast_power()


func _diplomacy(day: int) -> void:
	# make peace with stronger enemies after a long war
	for o in g.nations:
		if o.id == n.id or not o.alive or n.relation(o.id) != Defs.Relation.WAR or o.is_player:
			continue
		if day - war_start_day > 900 and g.rng.randf() < 0.05:
			g.make_peace(n.id, o.id)
			if war_target == o.id:
				war_target = 0


func accepts_peace(from: int) -> bool:
	var rel := n.relation(from)
	var mine := g.military_strength(n.id)
	var theirs := g.military_strength(from)
	var other := g.nation(from)
	var rep: float = other.reputation if other else 0.0
	if rel == Defs.Relation.WAR:
		return mine < theirs * 0.8 or (g.day - war_start_day > 500 and rep > 0 and g.rng.randf() < 0.5)
	return rep > -20.0 and (war_target != from)
