class_name AIBase
extends RefCounted
## Shared helpers of the computer kingdoms (NationAI, FryhtanAI): their towns
## and buildings, the aggressiveness setting, the Greater Beings' powers
## (FirmBase/UnitGod AI) and the answer to a peace offer.

var n: Nation
var g: Game
var war_target := 0
var war_start_day := 0
var aggression := 1.0


func _init(nation: Nation, game: Game) -> void:
	n = nation
	g = game
	aggression = g.rng.randf_range(0.7, 1.4)
	# Config::ai_aggressiveness (none .. very high) on top of each kingdom's temper
	aggression *= [0.5, 0.75, 1.0, 1.3, 1.6][clampi(_aggressiveness(), 0, 4)]


## Each computer kingdom thinks once a day (NationAI and FryhtanAI).
func next_day(_day: int) -> void:
	pass


func my_towns() -> Array:
	return g.towns.filter(func(t): return t.nation_id == n.id and not t.dead)


func my_firms(code := "") -> Array:
	return g.firms.filter(func(f): return f.nation_id == n.id and not f.dead and (code == "" or f.code == code))


func idle_units(humans_only := true) -> Array:
	return g.units.filter(func(u): return u.nation_id == n.id and not u.dead and u.inside_firm == null and u.order == Unit.Order.IDLE and u.home_town == null and (not humans_only or u.is_human()))


func _aggressiveness() -> int:
	return int(g.config.get("aggressiveness", GameSetup.MODERATE))


func _use_gods() -> void:
	for u in g.units.duplicate():
		if not u.is_god or u.nation_id != n.id or u.dead:
			continue
		if u.god_info().get("race", "") in ATTACK_GODS:
			if g.day % 7 == u.obj_id % 7 and u.order == Unit.Order.IDLE and not u.attacking:
				_think_attack_god(u)
			continue
		if not u.can_cast_power() or u.cast_target.x >= 0:
			continue
		var at := _god_target(u)
		if at.x >= 0:
			u.order_cast_power(at)


## UnitGod::think_norman/viking/celt/chinese_god: these Greater Beings fight.
const ATTACK_GODS := ["NORMAN", "VIKING", "CELTIC", "CHINESE"]


## UnitGod::think_*_god for a fighting god: join the weightiest attack of the
## kingdom's units - or, long at peace and hurt, go (resign).
func _think_attack_god(god: Unit) -> void:
	var target := _god_attack_target(god)
	if target != null:
		god.order_attack(target)
	elif int(god.hp) / 2 < int(god.max_hp) and n.peaceful_days() > 100 \
			and g.rng.randi() % maxi(1, int(god.max_hp)) > 2 * int(god.hp):
		god.die(null)
		g.remove_unit(god)


## UnitGod::think_god_attack_target: among the kingdom's units on the attack,
## the target weighing most - an enemy troop by its men's hit points, a
## building by its own (a camp twice), a town by its wall and defenders - less
## distance/8, a general's target 10% and a king's 20% heavier; 50 at least.
func _god_attack_target(god: Unit) -> GameObj:
	var best: GameObj = null
	var best_w := 0
	for u in g.units:
		if u.nation_id != n.id or u.dead or u.inside_firm != null or u == god:
			continue
		if u.order != Unit.Order.ATTACK or u.target == null or not is_instance_valid(u.target) or u.target.dead:
			continue
		var t: GameObj = u.target
		var w := 0
		if t is Unit:
			var tu := t as Unit
			var lead: Unit = tu if tu.rank >= Defs.Rank.GENERAL else tu.leader
			if lead != null and is_instance_valid(lead) and not lead.dead:
				for m in g.units:
					if not m.dead and (m == lead or m.leader == lead):
						w += int(m.hp)
			else:
				w -= int(tu.hp)
		elif t is Firm:
			w = int(t.hp)
			if Espionage.is_camp(t):
				w += int(t.hp)
		elif t is Town:
			var tt := t as Town
			w += int(tt.wall_hp) + (tt.jobless() + tt.defenders.size()) * 2
		w -= int(god.distance_to(t)) / 8
		if u.rank == Defs.Rank.GENERAL:
			w += w / 10
		elif u.rank == Defs.Rank.KING:
			w += w / 5
		if w > best_w:
			best_w = w
			best = t
	return best if best_w >= 50 else null


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


func accepts_peace(from: int) -> bool:
	var rel := n.relation(from)
	var mine := g.military_strength(n.id)
	var theirs := g.military_strength(from)
	var other := g.nation(from)
	var rep: float = other.reputation if other else 0.0
	if rel == Defs.Relation.WAR:
		return mine < theirs * 0.8 or (g.day - war_start_day > 500 and rep > 0 and g.rng.randf() < 0.5)
	return rep > -20.0 and (war_target != from)
