class_name AIBase
extends RefCounted
## Shared helpers of the computer kingdoms (NationAI, FryhtanAI) and the
## earlier compact strategy kept for Fryhtan kingdoms. A compact take on the oai_*.cpp strategies:
## secure towns with camps, build the mine-factory-market chain, research,
## win independent towns over with camps and grants, and attack weaker rivals.

## "SPUS"/"SPUB" stand for the special-unit techs of the kingdom's own race.
const RESEARCH_ORDER := ["MINING", "MANUFACT", "INFCLOSE", "FARMING", "SPUS", "INFDEFEN", "CATAPULT", "INFRANGE", "BALLISTA", "WAR_PROD", "AGITATE", "SPUB", "FLAMETHR", "STEALINF", "BRIBE", "COUNTERS", "CANNON", "OFF_BLD3", "EXPCART", "ASSASSIN", "STEALTEC", "F_BALLIS", "OFF_BLD1", "OFF_BLD4", "OFF_BLD2"]

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
	# Config::ai_aggressiveness (none .. very high) on top of each kingdom's temper
	aggression *= [0.5, 0.75, 1.0, 1.3, 1.6][clampi(_aggressiveness(), 0, 4)]


var _last_close := -999


func next_day(day: int) -> void:
	if not n.alive:
		return
	Espionage.ai_think(n, g, war_target, day)
	for u in g.units.duplicate():
		if u.is_caravan and u.nation_id == n.id and not u.dead:
			Caravans.process_ai(u, day)
	# FirmSpecial::process_ai, FirmSpy::process_ai, FirmFort::think_train_archer
	for f in my_firms():
		# Firm::process_common_ai: repair when it can spend
		if not f.repair and f.hp < f.max_hp and not f.under_construction and Training.ai_should_spend(n, 50 + Diplomacy._pref(n, "repair_concern") / 2):
			f.repair = true
		if f.code == "FORT" and not f.under_construction and f.target_archers == f.archers and f.archers < Firm.MAX_FORT_ARCHER:
			var importance := Diplomacy._pref(n, "military_development") / 3 + (10 if war_target > 0 else 0)
			if Training.ai_should_spend(n, importance, Firm.TRAIN_ARCHER_COST):
				f.set_target_archers(-1)
		if Training.is_train_firm(f) and not f.under_construction:
			Training.process_ai(f, self, day)
	if (day + n.id * 3) % 7 != 0:
		return
	if my_towns().is_empty() and my_firms().is_empty():
		_homeless(day)
		return
	_garrisons()
	_seek_treasure()
	_settle_spare_peasants()
	_economy(day)
	_think_split_towns(day)
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
	n.add_cash(-cost, "Construction")
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
				linked[0].draft_into(f)


## Site::ai_get_site_object: send the nearest idle unit that can take it to any
## treasure near the kingdom's towns and buildings.
func _seek_treasure() -> void:
	if g.treasures.is_empty():
		return
	var bases: Array = my_towns() + my_firms()
	for t in g.treasures:
		if g.units.any(func(u): return u.nation_id == n.id and u.order == Unit.Order.MOVE and u.goal == t.cell):
			continue
		if not bases.any(func(b): return b.center_loc().distance_to(t.center_loc()) < 30.0):
			continue
		var best: Unit = null
		var best_d := 40.0
		for u in idle_units():
			if u.rank == Defs.Rank.KING or u.is_civilian() and t.kind == Treasure.Kind.ITEM:
				continue
			if t.kind == Treasure.Kind.SCROLL and u.race != t.race():
				continue
			if t.kind == Treasure.Kind.ITEM and (u.item_id != 0 or not Items.can_pick(u)):
				continue
			var d: float = u.center_loc().distance_to(t.center_loc())
			if d < best_d:
				best_d = d
				best = u
		if best:
			best.order_move(t.cell)


## Peasants left over from building go back to a town, keeping two on hand.
func _settle_spare_peasants() -> void:
	var idle := idle_units().filter(func(u): return u.is_civilian())
	for i in range(2, idle.size()):
		idle[i].order_settle()


func _best_idle_leader(c: Vector2) -> Unit:
	var best: Unit = null
	for u in idle_units():
		if u.rank == Defs.Rank.GENERAL and (best == null or u.leadership > best.leadership):
			best = u
	if best == null:
		for u in idle_units():
			if u.rank == Defs.Rank.SOLDIER and not u.is_civilian() and (best == null or u.leadership > best.leadership):
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
	# keep every Tower of Science busy
	for r in my_firms("RESEARCH"):
		if r.research_tech == "" and not r.under_construction:
			for c in RESEARCH_ORDER:
				var code: String = c
				if code == "SPUS":
					code = Defs.spu_structure_tech(n.race)
				elif code == "SPUB":
					code = Defs.spu_berserk_tech(n.race)
				var t := Defs.tech_def(code)
				if Defs.can_research(n, t):
					r.start_research(code)
					break
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
							n.add_cash(-float(Defs.firm_types["MINE"]["cost"]), "Construction")
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
	if day > 400 and my_firms("INN").is_empty() and n.cash > 1500:
		if _try_build("INN", towns[0].footprint()):
			return
	for inn in my_firms("INN"):
		if not inn.heroes.is_empty() and n.cash > 2500:
			inn.hire_hero(0)
	# spies: guard home, then infiltrate the camps and towns of the kingdom we fight
	if day > 600 and my_firms("SPY").is_empty() and n.cash > 2000:
		if _try_build("SPY", towns[0].footprint(), [towns[0].center_loc()]):
			return
	# caravans between our markets and those of friendly kingdoms
	# (FirmMarket::ai_create_new_trade: a caravan with the other market as its second stop)
	for mk in my_firms("MARKET"):
		if mk.under_construction or g.caravans_of(mk) >= 1 or Caravans.can_hire(mk) <= 0 or not Training.ai_should_spend(n, 30):
			continue
		var partner := g.find_trade_partner(mk, n.id)
		if partner:
			var c: Unit = mk.hire_caravan()
			if c:
				c.set_caravan_stop(1, partner)
			break
	if day > 500 and my_firms("STABLE").is_empty() and n.cash > 1200 and n.tech_level(Defs.spu_structure_tech(n.race)) > 0:
		if _try_build("STABLE", towns[0].footprint(), [towns[0].center_loc()]):
			return
	if day > 700 and my_firms("WAR").is_empty() and n.cash > 2000 and n.tech_level("CATAPULT") > 0:
		if _try_build("WAR", towns[0].footprint()):
			return
	for wf in my_firms("WAR"):
		if wf.weapon == "" and n.cash > 1500:
			for wcode in Defs.MEGA_WEAPONS + ["CANNON", "F_BALLIS", "FLAMETHR", "BALLISTA", "EXPCART", "CATAPULT"]:
				if n.tech_level(wcode) > 0:
					wf.queue_weapon(wcode)
					break
	# an offensive building beside a fort, once researched (FirmMagic::process_ai casts by itself)
	if day > 900 and n.cash > 3500:
		var have := my_firms().filter(func(f): return f.code in Defs.OFFENSIVE_FIRMS).size()
		var forts := my_firms("FORT") + my_firms("CAMP")
		if have < 2 and not forts.is_empty():
			for code in Defs.OFFENSIVE_FIRMS:
				if Defs.knows_firm(n, code) and my_firms(code).is_empty():
					var anchor: Firm = forts[(day / 7) % forts.size()]
					if _try_build(code, anchor.footprint()):
						return
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
	var army := idle_units(false).filter(func(u): return u.can_attack() and u.rank != Defs.Rank.KING and not u.is_civilian())
	var mine := g.military_strength(n.id)
	# pick a war
	if war_target == 0 and day > int(700 / aggression):
		var weakest := 0
		var weakest_s := INF
		for o in g.nations:
			if o.id == n.id or not o.alive or n.relation(o.id) >= Defs.Relation.PEACE:
				continue
			if Diplomacy.has_trade(n, o.id) and Diplomacy.ai_rel(n, o.id) >= 60:
				continue      # a valued trading partner (think_declare_war wants a poor relation)
			var s := g.military_strength(o.id)
			# more aggressive towards human players (oai_attk.cpp: +100/+300/+500 to the rating)
			if o.is_player and _aggressiveness() >= GameSetup.MODERATE:
				s *= [1.0, 1.0, 0.8, 0.6, 0.4][_aggressiveness()]
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
	army = idle_units(false).filter(func(u): return u.can_attack() and u.rank != Defs.Rank.KING and not u.is_civilian())
	# against a human, more troops (maxTargetCombatLevel grows by a third a level)
	var needed := 6
	var wt := g.nation(war_target) if war_target > 0 else null
	if wt and wt.is_player and _aggressiveness() >= GameSetup.MODERATE:
		needed += needed * (_aggressiveness() - GameSetup.MODERATE + 1) / 3
	if attack_target and army.size() >= needed:
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


func _aggressiveness() -> int:
	return int(g.config.get("aggressiveness", GameSetup.MODERATE))


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

## Town::think_split_town / ai_settle_new: a town close to its population
## limit sends a villager to found a new town beside it, unless a small town
## of its race is already nearby.
func _think_split_towns(day: int) -> void:
	if not n.can_afford(Game.TOWN_BUILDING_COST + 300.0):
		return
	for t in my_towns():
		if (day / 7 + t.obj_id) % 4 != 0 or t.under_construction:
			continue
		if t.population < Defs.MAX_TOWN_POPULATION - 15 + int(Diplomacy._pref(n, "cohesive")) / 10:
			continue
		if g.towns.any(func(o): return o != t and o.nation_id == n.id and o.race == t.race and o.population < 20 				and o.center_loc().distance_to(t.center_loc()) < 16.0):
			continue
		var c := Vector2i(t.center_loc())
		var site := Vector2i(-1, -1)
		for r in range(Defs.TOWN_SIZE + 2, 13):
			for k in 16:
				var a := TAU * k / 16.0
				var p := c + Vector2i(roundi(cos(a) * r), roundi(sin(a) * r)) - Vector2i.ONE * (Defs.TOWN_SIZE / 2)
				if g.can_build_town(p):
					site = p
					break
			if site.x >= 0:
				break
		if site.x < 0:
			continue
		var u: Unit = t.recruit()
		if u:
			u.order_found_town(site)
			return


## UnitGod::think_*_god: where a computer kingdom's Greater Being casts.
func _use_gods() -> void:
	for u in g.units:
		if not u.is_god or u.nation_id != n.id or u.dead or not u.can_cast_power() or u.cast_target.x >= 0:
			continue
		var at := _god_target(u)
		if at.x >= 0:
			u.order_cast_power(at)


func _god_target(god: Unit) -> Vector2i:
	var c := god.center_loc()
	match god.god_info().get("race", ""):
		"ROMAN":
			# think_roman_god: the commander most in need of leadership
			var best: Firm = null
			var best_r := 0.0
			for f in my_firms():
				if Espionage.is_camp(f) and f.overseer and f.overseer.is_human() and f.overseer.leadership <= 70.0:
					var r := 5000.0 + (5000.0 if f.overseer.rank == Defs.Rank.KING else 0.0) - absf(f.overseer.leadership - 40.0) * 70.0
					for s in f.soldiers:
						r += f.overseer.combat - s.combat
					if r > best_r:
						best_r = r
						best = f
			return Vector2i(best.center_loc()) if best else Vector2i(-1, -1)
		"GREEK", "MONGOL", "INDIAN", "CARTH":
			# fighting near by: the god goes where the enemy is
			var e = g.find_enemy_near(god, 12.0)
			if e and (god.god_info()["race"] != "CARTH" or not (e is Unit)):
				return Vector2i(e.center_loc())
			if e and god.god_info()["race"] == "CARTH":
				return Vector2i(-1, -1)
			return Vector2i(-1, -1)
		"PERSIAN":
			for f in g.firms:
				if not f.dead and f.nation_id != n.id and f.nation_id > 0 and not f.revealed_to.has(n.id) and f.center_loc().distance_to(c) < 20.0:
					return Vector2i(f.center_loc())
		"EGYPTIAN":
			var small: Town = null
			for t in my_towns():
				if t.population < Defs.MAX_TOWN_POPULATION - 10 and (small == null or t.population < small.population):
					small = t
			return Vector2i(small.center_loc()) if small else Vector2i(-1, -1)
		"JAPANESE":
			for s in g.spies:
				if s.nation_id != n.id and is_instance_valid(s.spy_place) and s.spy_place.nation_id == n.id:
					return Vector2i(s.spy_place.center_loc())
	return Vector2i(-1, -1)


## Nation::think_diplomacy about once a month: cease-fires, treaties, food
## purchases and technology exchanges (Diplomacy.ai_think).
func _diplomacy(day: int) -> void:
	if (day / 7 + n.id) % 4 == 0:
		Diplomacy.ai_think(g, n)


func accepts_peace(from: int) -> bool:
	var rel := n.relation(from)
	var mine := g.military_strength(n.id)
	var theirs := g.military_strength(from)
	var other := g.nation(from)
	var rep: float = other.reputation if other else 0.0
	if rel == Defs.Relation.WAR:
		return mine < theirs * 0.8 or (g.day - war_start_day > 500 and rep > 0 and g.rng.randf() < 0.5)
	return rep > -20.0 and (war_target != from)
