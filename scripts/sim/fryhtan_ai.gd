class_name FryhtanAI
extends NationAI
## Computer-controlled Fryhtan kingdom (after on_mons.cpp / of_laira.cpp):
## breeds Fryhtans in its lairs with gold and life points, builds new lairs
## beside independent villages, terrorises them until they pay tribute, and
## raids human kingdoms for life points.

const LAIR_COST := 300.0
const LAIR_LIVE := 200.0


func next_day(day: int) -> void:
	if not n.alive or (day + n.id * 3) % 7 != 0:
		return
	var lairs: Array = my_firms("LAIR")
	_resume_construction()
	_alchemy()
	_leaders(lairs)
	_breed(lairs)
	_expand_lairs(day, lairs)
	_attack(day, lairs)
	_diplomacy(day)


## Surplus gold is turned into life points, as an Alchemist Tor does once
## its conversion is researched (FirmMonsterAlchemy: 2 gold per life point).
## This port has no Alchemist Tor building, so the AI converts directly.
const ALCHEMY_RESERVE := 1500.0
const ALCHEMY_WEEKLY := 1400.0


func _alchemy() -> void:
	if n.live_points >= 800.0 or n.cash <= ALCHEMY_RESERVE:
		return
	var gold := minf(n.cash - ALCHEMY_RESERVE, ALCHEMY_WEEKLY)
	n.add_cash(-gold)
	n.live_points += gold * 0.5


## Resume abandoned lair sites, pulling a Fryhtan out of a lair if none is idle.
func _resume_construction() -> void:
	for f in my_firms("LAIR"):
		if not f.under_construction:
			continue
		if f.builder != null and is_instance_valid(f.builder) and not f.builder.dead:
			continue
		if g.units.any(func(u): return u.nation_id == n.id and u.order == Unit.Order.BUILD and u.order_firm == f):
			continue
		var b := _builder_near(f.center_loc())
		if b == null:
			for home in my_firms("LAIR"):
				if not home.under_construction and home.soldiers.size() > 1:
					b = home.soldiers[0]
					home.release_unit(b)
					break
		if b:
			b.order_build(f)


## Fryhtans build their own lairs: the nearest idle one does it.
func _builder_near(c: Vector2) -> Unit:
	var best: Unit = null
	for u in _monsters_idle():
		if u.rank == Defs.Rank.KING:
			continue
		if best == null or u.center_loc().distance_to(c) < best.center_loc().distance_to(c):
			best = u
	return best


func _monsters_idle() -> Array:
	return g.units.filter(func(u): return u.nation_id == n.id and not u.dead and u.inside_firm == null and u.order == Unit.Order.IDLE)


## Every lair needs a commander: its presence lets the lair cow nearby villages.
func _leaders(lairs: Array) -> void:
	for f in lairs:
		if f.under_construction or f.overseer != null:
			continue
		var heading := g.units.any(func(u): return u.nation_id == n.id and u.order == Unit.Order.ENTER and u.order_firm == f and u.rank >= Defs.Rank.GENERAL)
		if heading:
			continue
		var best: Unit = null
		for u in _monsters_idle():
			if u.rank != Defs.Rank.KING and (best == null or u.combat > best.combat):
				best = u
		if best == null and not f.soldiers.is_empty():
			# promote the strongest Fryhtan already inside
			var s: Unit = f.soldiers[0]
			for x in f.soldiers:
				if x.combat > s.combat:
					s = x
			f.soldiers.erase(s)
			s.rank = Defs.Rank.GENERAL
			s.leadership = maxf(s.leadership, 40.0 + s.combat * 0.3)
			f.overseer = s
			continue
		if best:
			best.rank = Defs.Rank.GENERAL
			best.leadership = maxf(best.leadership, 40.0 + best.combat * 0.3)
			best.order_enter(f)


func _brood_of(f: Firm) -> int:
	var c: int = f.soldiers.size()
	for u in g.units:
		if u.home_firm == f and not u.dead and u.inside_firm == null:
			c += 1
	return c


func _breed(lairs: Array) -> void:
	for f in lairs:
		if f.under_construction:
			continue
		# keep a reserve for upkeep and the next lair
		if n.cash < 250.0:
			return
		if _brood_of(f) < f.capacity():
			f.breed()


func _expand_lairs(day: int, lairs: Array) -> void:
	var homeless := lairs.is_empty()
	if not homeless and (lairs.size() >= 1 + (day + 200) / 400 or n.cash < LAIR_COST + 200.0 or n.live_points < LAIR_LIVE):
		return
	if lairs.any(func(f): return f.under_construction):
		return
	var home: Vector2 = lairs[0].center_loc() if not lairs.is_empty() else Vector2(g.world.w / 2.0, g.world.h / 2.0)
	# nearest independent village not yet cowed by one of our lairs
	var best: Town = null
	var best_d := 45.0
	for t in g.towns:
		if t.dead or t.nation_id != 0:
			continue
		if t.linked_firms.any(func(f): return f.nation_id == n.id):
			continue
		var d := t.center_loc().distance_to(home)
		if d < best_d:
			best_d = d
			best = t
	if best == null and not homeless:
		return
	var near: Rect2i = best.footprint() if best else Rect2i(Vector2i(home), Vector2i.ONE)
	var anchors: Array = [best.center_loc()] if best else []
	var b := Assets.firm_build("LAIR", n.monster_code)
	if homeless and not _monsters_idle().is_empty():
		home = _monsters_idle()[0].center_loc()
		if best == null:
			near = Rect2i(Vector2i(home), Vector2i.ONE)
	var pos := g._place_near(near, b.get("loc_w", 6), b.get("loc_h", 6), 6, anchors)
	if pos.x < 0:
		return
	var builders := _monsters_idle()
	if builders.is_empty():
		# send one out of the fullest lair
		for f in lairs:
			if f.soldiers.size() > 2:
				var u: Unit = f.soldiers[0]
				f.release_unit(u)
				builders = [u]
				break
	if builders.is_empty():
		return
	var lair := g.spawn_firm("LAIR", n.id, n.monster_code, pos, false)
	if lair == null:
		return
	lair.monster_code = n.monster_code
	if not homeless:
		n.add_cash(-LAIR_COST)
		n.live_points -= LAIR_LIVE
	builders[0].order_build(lair)


## Terrorise linked villages until they pay tribute; raid human kingdoms when strong.
func _attack(day: int, lairs: Array) -> void:
	var army := _monsters_idle().filter(func(u): return u.rank != Defs.Rank.KING)
	var garrisons := 0
	for f in lairs:
		garrisons += f.soldiers.size()
	# a village linked to our lair that still resists: send a few to break its will
	for f in lairs:
		if f.under_construction or f.overseer == null:
			continue
		for t in f.linked_towns:
			if t.nation_id == 0 and not t.dead and t.resistance_to(n.id) >= Defs.SURRENDER_RESISTANCE and t.population > 8:
				# a party big enough for the village militia (about one defender per five villagers)
				var need := clampi(t.population / 8 + 2, 3, 6)
				if f.soldiers.size() < need:
					break
				var busy := g.units.any(func(u): return u.home_firm == f and u.order == Unit.Order.ATTACK and u.target == t)
				if busy:
					break
				for i in f.soldiers.size() - 1:
					f.release_unit(f.soldiers[0], t)
				break
	# think_acquire_live_points: when starved of life, hunt the nearest humans
	var hungry := n.live_points < 100.0 and day > 400
	if day < int(500 / aggression) and not hungry:
		return
	if army.size() + garrisons < (5 if hungry else 10):
		return
	if attack_target == null or not is_instance_valid(attack_target) or attack_target.dead or attack_target.nation_id == 0 or not n.is_hostile_to(attack_target.nation_id):
		attack_target = _human_target(lairs)
	if attack_target == null:
		return
	for f in lairs:
		while f.soldiers.size() > 3:
			f.release_unit(f.soldiers[0], attack_target)
	for u in army:
		u.order_attack(attack_target)


func _human_target(lairs: Array) -> GameObj:
	if lairs.is_empty():
		return null
	var c: Vector2 = lairs[0].center_loc()
	var best: GameObj = null
	var best_d := INF
	for t in g.towns:
		if t.dead or t.nation_id <= 0 or not n.is_hostile_to(t.nation_id):
			continue
		var d := c.distance_to(t.center_loc())
		if d < best_d:
			best_d = d
			best = t
	for f in g.firms:
		if f.dead or f.nation_id <= 0 or f.nation_id == GameObj.MONSTER_NATION or not n.is_hostile_to(f.nation_id):
			continue
		var d := c.distance_to(f.center_loc()) * 1.2
		if d < best_d:
			best_d = d
			best = f
	return best


func _diplomacy(_day: int) -> void:
	pass


func accepts_peace(from: int) -> bool:
	# Fryhtans make peace only when clearly outmatched
	return g.military_strength(n.id) < g.military_strength(from) * 0.5
