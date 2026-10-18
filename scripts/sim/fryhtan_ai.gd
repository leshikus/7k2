class_name FryhtanAI
extends NationAI
## A computer-run Fryhtan kingdom (on_mons.cpp, NationMonster): the kingdom
## AI of the humans' (NationAI) plus raids for life points when they run low,
## attacks on hostile kingdoms, and buying independent lairs. Its lairs think
## for themselves (AIFryhtan: of_laira.cpp, of_lara2.cpp) and so do its special
## buildings (of_mtrna, of_anima, of_alcha, of_incua).

const LAIR_COST := 300.0
const LAIR_LIVE := 200.0

var last_lishorr_power := 0     # Nation::ai_last_build_lishorr_net_power


## NationMonster::process_ai_main
func _main(id: int) -> void:
	if g.day % 15 == n.id % 15 and think_acquire_live_points():
		return
	if g.config.has("tutorial"):
		return
	super._main(id)
	match id:
		11:
			think_attack_hostile_nation()
		12:
			think_buy_independent_lair()


func lairs() -> Array:
	return my_firms("LAIR").filter(func(f): return not f.under_construction)


## NationMonster::think_acquire_live_points: short of life points, raid the
## best town - an enemy's, a neutral one after a while, a friend's if not
## honest, or a village no longer paying tribute.
func think_acquire_live_points() -> bool:
	if n.live_points >= 1000 * (30 + pref("live_points_reserve")) / 100:
		return false
	if g.config.has("tutorial"):
		n.live_points = 1000.0 * (30 + pref("live_points_reserve")) / 100.0
		return false
	var ls := lairs()
	if ls.is_empty():
		return false
	var c := Vector2.ZERO
	for f in ls:
		c += f.center_loc()
	c /= ls.size()
	var best: Town = null
	var best_r := -10000
	var best_def := 0
	var delay: int = [1000, 720, 365, 180, 90][clampi(_aggressiveness(), 0, 4)]
	for t in g.towns:
		if t.dead or t.population <= (100 - pref("monster_aggressiveness")) / 20:
			continue
		var ok := false
		if t.nation_id > 0:
			if t.nation_id == n.id:
				continue
			var st := relation(t.nation_id)
			if st == Defs.Relation.WAR:
				ok = true
			elif g.day < delay:
				continue
			elif st == Defs.Relation.NEUTRAL:
				ok = true
			else:
				ok = pref("honesty") < 50
		elif t.resistance_to(n.id) < Town.MONSTER_COLLECT_TOWN_TRIBUTE_LOYALTY:
			ok = true
		if not ok:
			continue
		var def := AIFirm.possible_defender_combat_level(t, 0)
		var r := 200 - def / 10 + distance_rating(c, t.center_loc())
		if t.nation_id > 0:
			r -= Diplomacy.ai_rel(n, t.nation_id) * 2
			var tn := g.nation(t.nation_id)
			if tn and tn.is_fryhtan:
				r -= 50
			if tn and not tn.is_ai:
				r += (_aggressiveness() - 1) * 30
		elif AIFirm.pays_tribute(t):
			r -= 50
		if r > best_r:
			best_r = r
			best = t
			best_def = def
	if best == null:
		return false
	AIAttack.attack_target(self, best, best_def, n.live_points < 200)
	return true


## NationMonster::think_attack_hostile_nation: a building or a town of a
## kingdom at war with us, picked at random.
func think_attack_hostile_nation() -> void:
	var target: GameObj = null
	var pool: Array = g.firms.duplicate() if g.rng.randi() % 2 == 0 else g.towns.duplicate()
	if pool.is_empty():
		return
	var start := g.rng.randi() % pool.size()
	for i in pool.size():
		var o = pool[(start + i + 1) % pool.size()]
		if o.dead or o.nation_id <= 0 or o.nation_id == n.id:
			continue
		if o is Town and o.population == 0:
			continue
		var on := g.nation(o.nation_id)
		if on and on.relation(n.id) == Defs.Relation.WAR:
			target = o
			break
	if target:
		AIAttack.attack_target(self, target, AIFirm.obj_power(target))


## NationMonster::think_buy_independent_lair: a wild lair of a species we do
## not have - bought if one of our lairs is beside it, else a lair is built
## next to it first.
func think_buy_independent_lair() -> void:
	if lairs().is_empty():
		return
	for loop in [1, 2]:
		for t in g.firms:
			if t.dead or t.code != "LAIR" or t.nation_id != GameObj.MONSTER_NATION:
				continue
			if n.cash < SpecialFirms.take_lair_cost(t):
				continue
			if g.units.any(func(u): return u.nation_id == n.id and not u.dead and u.sprite_code == t.monster_code):
				continue
			if loop == 1:
				if SpecialFirms.can_take_lair(t, n.id):
					SpecialFirms.take_lair(t, n.id)
					return
			else:
				var best: Firm = null
				var best_r := 0
				for f in lairs():
					var r := distance_rating(t.center_loc(), f.center_loc())
					if r > best_r:
						best_r = r
						best = f
				if best:
					if not should_spend(20 + pref("peacefulness") / 2, SpecialFirms.take_lair_cost(t)):
						break
					AIFryhtan.build_lair(self, best, t)
					return


func accepts_peace(from: int) -> bool:
	return Diplomacy.consider_cease_war(g, n, g.nation(from)) > 0
