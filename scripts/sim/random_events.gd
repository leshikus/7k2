class_name RandomEvents
extends RefCounted
## Random events (oevent.cpp, RandomEvent): every 200 to 1000 days, by the
## game's "random events" setting (none, low, moderate, high), one of
## thirteen things happens to some kingdom: a research breakthrough, a lost
## scroll of technology, rats in the granaries, a general or soldier dying of
## plague, sickness in a fort, a stranger or a wagon of settlers joining, a cache
## of artifacts, a plague in a town, or an accident wrecking a factory, mine
## or inn. Only the player hears about the ones that touch his kingdom.

const EVENTS := ["FINISH_TECH", "NEW_TECH", "FOOD_DESTROYED", "GENERAL_DIE", "UNIT_DIE", "SOLDIER_DIE",
	"UNIT_JOIN", "WAGON_JOIN", "ITEM_DISCOVER", "TOWN_PEOPLE_KILLED", "FACTORY_DESTROYED", "MINE_DESTROYED", "INN_DESTROYED"]
const WAGON_POP := 10       # MAX_WAGON_POPULATION

const NAMES := ["None", "Low", "Moderate", "High"]


static func frequency(g: Game) -> int:
	return clampi(int(g.config.get("random_events", 0)), 0, 3)


## RandomEvent::next_day
static func next_day(g: Game) -> void:
	var freq := frequency(g)
	if freq == 0:
		return
	if g.event_days < 0:
		g.event_days = 1000 - 200 * freq - g.rng.randi() % 200
	g.event_days -= 1
	if g.event_days > 0:
		return
	if execute(g, EVENTS[g.rng.randi() % EVENTS.size()]) != "":
		g.event_days = 1000 - 200 * freq - g.rng.randi() % 100
	else:
		g.event_days = 10 + g.rng.randi() % 10


static func _rotated(a: Array, rng: RandomNumberGenerator) -> Array:
	if a.is_empty():
		return []
	var k := rng.randi() % a.size()
	return a.slice(k) + a.slice(0, k)


## A unit a scenario goal is about may not die of an event (game.is_unit_in_condition).
static func _in_goal(g: Game, u: Unit) -> bool:
	if g.goals == null:
		return false
	for c in g.goals.win + g.goals.lose:
		if c.get("target") == u:
			return true
	return false


static func _tell(g: Game, nid: int, text: String, at: Vector2) -> void:
	if nid == g.player_id:
		g.notify(text, at)


## RandomEvent::execute_event: what happened, or "" when nothing could.
static func execute(g: Game, id: String) -> String:
	var rng := g.rng
	var alive: Array = g.nations.filter(func(n): return n.alive)
	match id:
		"FINISH_TECH":
			for f in _rotated(g.firms, rng):
				if f.code == "RESEARCH" and not f.dead and f.nation_id > 0 and f.research_tech != "":
					var n := g.nation(f.nation_id)
					var code: String = f.research_tech
					n.tech[code] = n.tech_level(code) + 1
					n.research_progress.erase(code)
					f.research_points = 0.0
					if n.tech[code] >= Defs.tech_def(code).get("max", 0):
						f.research_tech = ""
					_tell(g, n.id, "A research breakthrough has been achieved and your current project has been completed!", f.center_loc())
					return id
		"NEW_TECH":
			if alive.is_empty():
				return ""
			var n: Nation = alive[rng.randi() % alive.size()]
			var valid := Defs.research_techs().filter(func(t):
				return Defs.can_research(n, t) and not g.firms.any(func(f): return f.nation_id == n.id and f.research_tech == t["code"]))
			if not valid.is_empty():
				var t: Dictionary = valid[rng.randi() % valid.size()]
				n.tech[t["code"]] = n.tech_level(t["code"]) + 1
				_tell(g, n.id, "A lost scroll has been found giving details of %s technology!" % t["name"], Vector2(-1, -1))
				return id
		"FOOD_DESTROYED":
			if alive.is_empty():
				return ""
			var n: Nation = alive[rng.randi() % alive.size()]
			if n.food > 500.0:
				var lost := 2000 + rng.randi() % 2000 if n.food >= 10000.0 else 100 + rng.randi() % maxi(1, int(n.food) / 4)
				n.food -= float(lost)
				_tell(g, n.id, "A plague of rats has infested your granaries! You have lost %d bushels of your food stores!" % lost, Vector2(-1, -1))
				return id
		"GENERAL_DIE", "UNIT_DIE":
			var rank := Defs.Rank.GENERAL if id == "GENERAL_DIE" else Defs.Rank.SOLDIER
			for u in _rotated(g.units, rng):
				if u.dead or u.nation_id <= 0 or u.rank != rank or _in_goal(g, u):
					continue
				if u.is_caravan or u.is_god or u.is_weapon or u.is_civilian():
					continue
				if u.is_monster() and rng.randi() % 2 == 0:
					continue       # a Fryhtan has half a chance to survive
				if u.inside_firm == null:
					_tell(g, u.nation_id, "Your %s, %s, has succumbed to the plague." % ["General" if rank == Defs.Rank.GENERAL else "soldier", u.display_name()], u.center_loc())
					u.die(null)
					return id
				if u.inside_firm.overseer == u and Espionage.is_camp(u.inside_firm):
					_tell(g, u.nation_id, "Your General, %s, has succumbed to the plague." % u.display_name(), u.inside_firm.center_loc())
					g.kill_inside(u.inside_firm, u)
					return id
		"SOLDIER_DIE":
			for f in _rotated(g.firms, rng):
				if f.dead or f.nation_id <= 0 or f.under_construction or not Espionage.is_camp(f):
					continue
				var killed := 0
				for s in f.soldiers.duplicate():
					if _in_goal(g, s):
						continue
					var dies: bool = rng.randi() % maxi(1, int(s.max_hp * 2)) > int(s.hp) if not s.is_monster() \
						else rng.randi() % maxi(1, int(s.max_hp * 3)) > int(s.hp * 2)
					if dies:
						g.kill_inside(f, s)
						killed += 1
				if killed > 0:
					_tell(g, f.nation_id, "%d soldier%s in your %s %s died of a sickness." % [killed, "" if killed == 1 else "s", f.display_name(), "has" if killed == 1 else "have"], f.center_loc())
					return id
		"UNIT_JOIN":
			if alive.is_empty():
				return ""
			var n: Nation = alive[rng.randi() % alive.size()]
			var pick := rng.randi() % (Defs.races.size() + Defs.monsters.size())
			var sprite := ""
			var skill := float(rng.randi_range(10, 50))
			if pick < Defs.races.size():
				var race: String = Defs.races[pick]["code"]
				sprite = Defs.unit_sprite(race, ["CIV", "INF", "SPU"][rng.randi() % 3])
			else:
				sprite = Defs.monsters[pick - Defs.races.size()]["unit"]
			var u := _edge_unit(g, sprite, n.id, skill)
			if u:
				u.loyalty = 60.0
				_tell(g, n.id, "A %s has arrived and offered to serve you." % u.type_name(), u.center_loc())
				return id
		"WAGON_JOIN":
			if alive.is_empty():
				return ""
			var n: Nation = alive[rng.randi() % alive.size()]
			var race: String = Defs.races[rng.randi() % Defs.races.size()]["code"]
			var pop := WAGON_POP - rng.randi() % 3
			var first := _edge_unit(g, "WAGON", n.id, 100.0)
			if first:
				first.wagon_pop = pop
				first.wagon_race = race
				_tell(g, n.id, "A wagon of %d %s settlers has arrived to join your kingdom." % [pop, Defs.race_adj(race)], first.center_loc())
				return id
		"ITEM_DISCOVER":
			for t in _rotated(g.towns, rng):
				if t.dead or t.nation_id <= 0:
					continue
				var made := 0
				for i in range(3 + rng.randi() % 2, 0, -1):
					var item := Items.random_id(rng, Items.MIN_RARITY, Items.MIN_RARITY + rng.randi() % (Items.MAX_RARITY - Items.MIN_RARITY + 1))
					var c := g._free_treasure_cell(Vector2i(t.x1 + Defs.TOWN_SIZE - i, t.y1 + Defs.TOWN_SIZE + 1))
					if item != 0 and c.x >= 0:
						g.spawn_treasure(Treasure.Kind.ITEM, item, Items.random_para(item, rng), c)
						made += 1
				if made > 0:
					_tell(g, t.nation_id, "A cache of artifacts has been dug up near your town of %s!" % t.display_name(), t.center_loc())
					return id
		"TOWN_PEOPLE_KILLED":
			for t in _rotated(g.towns, rng):
				if t.dead or t.nation_id <= 0 or t.population <= 10:
					continue
				var k := mini(10 + rng.randi() % 11, t.population - 1)
				t.population -= k
				_tell(g, t.nation_id, "A plague has killed %d people in your town of %s." % [k, t.display_name()], t.center_loc())
				return id
		"FACTORY_DESTROYED", "MINE_DESTROYED", "INN_DESTROYED":
			var codes: Array = {"FACTORY_DESTROYED": ["FACTORY", "WAR", "INCUBAT", "MAGIC", "ALCHEMY"],
				"MINE_DESTROYED": ["MINE"], "INN_DESTROYED": ["INN", "ANIMAL"]}[id]
			for f in _rotated(g.firms, rng):
				if f.dead or f.nation_id <= 0 or f.under_construction or not f.code in codes:
					continue
				var workers: int = f.workers()
				# FirmWork::kill_all_worker: the workers came from linked towns
				var left := workers
				for t in f.worker_from:
					if left <= 0:
						break
					if is_instance_valid(t) and not t.dead:
						var k := mini(int(f.worker_from[t]), mini(left, t.population - 1))
						t.population -= maxi(0, k)
						left -= maxi(0, k)
				var where: Vector2 = f.center_loc()
				var nid: int = f.nation_id
				var what: String = f.display_name()
				f.die(null)
				match id:
					"FACTORY_DESTROYED":
						_tell(g, nid, "A %s has been destroyed in an accident%s." % [what, (", killing %d workers" % workers) if workers > 0 else ""], where)
					"MINE_DESTROYED":
						_tell(g, nid, "There has been an explosion in your mine, collapsing it%s." % ((" and causing the death of %d workers" % workers) if workers > 0 else ""), where)
					_:
						_tell(g, nid, "Your %s has burnt down." % what, where)
				return id
	return ""


## RandomEvent::create_boundary_unit: a newcomer at the edge of the map.
static func _edge_unit(g: Game, sprite: String, nid: int, skill: float, near := Vector2i(-1, -1)) -> Unit:
	if not Assets.has_sprite(sprite):
		return null
	var w := g.world.w
	var h := g.world.h
	for t in 16:
		var c := near
		if c.x < 0:
			var p := g.rng.randi() % (2 * (w - 2) + 2 * (h - 2))
			if p < w - 2:
				c = Vector2i(p + 1, 1)
			elif p < w - 2 + h - 2:
				c = Vector2i(w - 2, p - (w - 2) + 1)
			elif p < 2 * (w - 2) + h - 2:
				c = Vector2i(p - (w - 2) - (h - 2) + 1, h - 2)
			else:
				c = Vector2i(1, p - 2 * (w - 2) - (h - 2) + 1)
		c = g.free_unit_cell(c)
		if g.world.is_walkable(c):
			return g.spawn_unit(sprite, nid, c, skill)
		near = Vector2i(-1, -1)
	return null
