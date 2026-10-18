class_name Rebels
extends RefCounted
## Rebellions (Town::think_rebel, orebel.cpp): when a town's loyalty sinks to
## the rebel level, a third to two thirds of its people walk out under a
## leader as independent rebels hostile to their old kingdom. The town stays
## (its loyalty rises as the malcontents leave). A rebel band attacks a town
## or building of that kingdom, or goes to settle in a town of its own race;
## if its leader falls, the rest surrender to the kingdom with the best
## reputation.

## g.rebels: [{id, leader: Unit, units: Array[Unit], hostile: [nation ids],
##             action: "idle"|"attack_town"|"attack_firm"|"settle_to", target}]


static func group(g: Game, id: int) -> Dictionary:
	for r in g.rebels:
		if r["id"] == id:
			return r
	return {}


static func is_hostile_to(g: Game, u: Unit, nid: int) -> bool:
	var r := group(g, u.rebel_id)
	return not r.is_empty() and nid in r["hostile"]


## Town::think_rebel and Town::create_rebel_unit
static func town_rebels(g: Game, t: Town) -> int:
	var old := t.nation_id
	var spies := g.spies.filter(func(s): return s.spy_place == t).size()
	if spies >= t.population:
		return 0
	var pop0 := t.population
	var leader := _rebel_unit(g, t, true)
	if leader == null:
		return 0
	var r := {"id": g.next_rebel_id, "leader": leader, "units": [leader], "hostile": [old], "action": "attack_town", "target": t}
	g.next_rebel_id += 1
	g.rebels.append(r)
	leader.rebel_id = r["id"]
	var count := 0
	if pop0 > 1:
		var others := (pop0 - spies) * (30 + g.rng.randi() % 30) / 100
		for i in others:
			var u := _rebel_unit(g, t, false)
			if u == null:
				break
			u.rebel_id = r["id"]
			r["units"].append(u)
			count += 1
		t.loyalty = minf(100.0, t.loyalty + 50.0 * count / maxf(1.0, t.population))
	g.notify_nation(old, "%d of the people of %s have rebelled against you!" % [count + 1, t.town_name], t.center_loc())
	return count + 1


static func _rebel_unit(g: Game, t: Town, leader: bool) -> Unit:
	if t.jobless() <= 0 and not leader:
		return null
	var c := g.exit_cell(t.footprint(), Vector2i(t.center_loc()) + Vector2i(0, 4))
	var u := g.spawn_unit(Defs.unit_sprite(t.race, "CIV"), 0, c, 10.0)
	if u == null:
		return null
	t.population -= 1
	if leader:
		u.combat = minf(100.0, 10.0 + t.population * 2 + g.rng.randi() % 10)
		u.leadership = minf(100.0, 10.0 + t.population + g.rng.randi() % 10)
		u.rank = Defs.Rank.GENERAL
	u.queue_redraw()
	return u


## RebelArray::next_day
static func next_day(g: Game) -> void:
	for r in g.rebels.duplicate():
		r["units"] = r["units"].filter(func(u): return is_instance_valid(u) and not u.dead and u.rebel_id == r["id"])
		if r["units"].is_empty():
			g.rebels.erase(r)
			continue
		if not is_instance_valid(r["leader"]) or r["leader"].dead or r["leader"].rebel_id != r["id"]:
			_leader_quit(g, r)
			if not g.rebels.has(r):
				continue
		if r["units"].all(func(u): return u.order == Unit.Order.IDLE):
			r["action"] = "idle"
		if r["action"] == "idle":
			_think_new_action(g, r)


## Rebel::process_leader_quit
static func _leader_quit(g: Game, r: Dictionary) -> void:
	var new_leader: Unit = r["units"][0]
	new_leader.rank = Defs.Rank.GENERAL
	r["leader"] = new_leader
	if r["units"].size() > 1:
		var best: Nation = null
		for n in g.nations:
			if n.alive and n.reputation > 0 and not n.is_fryhtan and (best == null or n.reputation > best.reputation):
				best = n
		if best == null:
			return
		for u in r["units"]:
			u.rebel_id = 0
			u.rank = Defs.Rank.SOLDIER
			u.nation_id = best.id
			u.stop()
			u.queue_redraw()
		g.rebels.erase(r)
		g.notify_nation(best.id, "Leaderless rebels have surrendered to you.", new_leader.center_loc())


## Rebel::think_new_action: settle in a town of their race, attack a town of
## the hostile kingdom, or attack one of its buildings.
static func _think_new_action(g: Game, r: Dictionary) -> void:
	var leader: Unit = r["leader"]
	var at := leader.center_loc()
	match g.rng.randi() % 3:
		0:
			var towns := g.towns.filter(func(t): return not t.dead and t.race == leader.race and not t.nation_id in r["hostile"] \
				and (t.nation_id == 0 or not g.nation(t.nation_id).is_fryhtan))
			if towns.is_empty():
				return
			var t: Town = towns[g.rng.randi() % towns.size()]
			r["action"] = "settle_to"
			r["target"] = t
			for u in r["units"]:
				u.stop()
				u.nation_id = t.nation_id        # they join whoever owns the town
				u.rebel_id = 0
				u.rank = Defs.Rank.SOLDIER
				u.home_town = t
				u.order = Unit.Order.RETURN
			g.rebels.erase(r)
		1:
			var best: Town = null
			for t in g.towns:
				if not t.dead and t.nation_id in r["hostile"] and t.race == leader.race \
						and (best == null or t.center_loc().distance_to(at) < best.center_loc().distance_to(at)):
					best = t
			if best:
				r["action"] = "attack_town"
				r["target"] = best
				for u in r["units"]:
					u.order_attack(best)
		2:
			var best: Firm = null
			for f in g.firms:
				if not f.dead and f.nation_id in r["hostile"] and not f.is_monster() \
						and (best == null or f.center_loc().distance_to(at) < best.center_loc().distance_to(at)):
					best = f
			if best:
				r["action"] = "attack_firm"
				r["target"] = best
				for u in r["units"]:
					u.order_attack(best)


static func to_save(g: Game) -> Array:
	return g.rebels.map(func(r): return {"id": r["id"], "leader": r["leader"].obj_id if is_instance_valid(r["leader"]) else 0,
		"units": r["units"].filter(func(u): return is_instance_valid(u)).map(func(u): return u.obj_id),
		"hostile": r["hostile"], "action": r["action"]})


static func from_save(g: Game, a: Array, by_id: Dictionary) -> void:
	g.rebels.clear()
	for d in a:
		var units: Array = []
		for i in d["units"]:
			if by_id.has(int(i)):
				units.append(by_id[int(i)])
				by_id[int(i)].rebel_id = int(d["id"])
		if units.is_empty():
			continue
		var leader = by_id.get(int(d["leader"]), units[0])
		g.rebels.append({"id": int(d["id"]), "leader": leader, "units": units,
			"hostile": d["hostile"].map(func(x): return int(x)), "action": "idle", "target": null})
		g.next_rebel_id = maxi(g.next_rebel_id, int(d["id"]) + 1)
