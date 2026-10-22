class_name HeroRes
extends RefCounted
## The heroes of the world (oherores.cpp): the historic heroes of HERO.DBF
## and fictional ones up to ten per nationality, each appearing at most once.
## Some wander the map from the towns (think_generate_hero); half of them can
## be hired for gold, the others only come to a kingdom that has done great
## deeds (induce_hero_join_nation). Inns offer heroes too, and powerful units
## of no fame (create_powerful_unit).

const HERO_COUNT_PER_RACE := 10
const MAX_INDEPENDENT_HERO := 20
const BASIC_COMBAT_TRAIN := 20
const MAX_COMBAT_TRAIN := 100
const MAX_COMBAT_BATTLE := 200
const BASIC_SKILL_TRAIN := 20
const MAX_SKILL_TRAIN := 100


## HeroRes::init + second_init: the list of heroes, which of them are for
## hire, and none has appeared yet. The fictional heroes are always the same
## (a constant random seed, for network games).
static func init(g: Game) -> void:
	g.hero_info = []
	for h in Defs.heroes:
		g.hero_info.append({"name": h["name"], "race": h["race"], "infantry": h.get("infantry", true),
			"special": h.get("special", false), "historic": true})
	var rng4 := RandomNumberGenerator.new()
	rng4.seed = 4
	for r in Defs.races:
		var code: String = r["code"]
		var have := g.hero_info.filter(func(x): return x["race"] == code).size()
		for i in range(have, HERO_COUNT_PER_RACE):
			var inf := rng4.randi() % 2 == 0
			g.hero_info.append({"name": Defs.random_person_name(code, rng4), "race": code, "infantry": inf,
				"special": not inf, "historic": false})
	# second_init: half of them, at random, can be hired (drawn apart from the
	# game's own sequence, so the map of a seed stays the same)
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = g.rng.seed + 7919
	for i in g.hero_info.size():
		g.hero_info[i]["id"] = i + 1
		g.hero_info[i]["for_hire"] = rng2.randi() % 2 == 1
		g.hero_info[i]["appeared"] = false


static func info(g: Game, hero_id: int) -> Dictionary:
	if hero_id < 1 or hero_id > g.hero_info.size():
		return {}
	return g.hero_info[hero_id - 1]


## HeroRes::hire_cost, for inn units and heroes in the field alike.
static func hire_cost(combat: int, max_combat: int, skill: int, spy_skill: int, item_id: int) -> int:
	var c := combat + skill * 2 + 100
	if combat > MAX_COMBAT_TRAIN:
		c += combat * 2 - MAX_COMBAT_TRAIN
		c += max_combat
	if skill > 0:
		c += skill
		var i := 10
		while i < skill:
			c += i / 5
			i += 20
	if spy_skill > 0:
		c += spy_skill
		var j := 10
		while j < spy_skill:
			c += j / 5
			j += 20
	c *= 2
	c += int(Items.TABLE.get(item_id, [0, 0, 0])[Items.COST]) if item_id > 0 else 0
	return mini(c, 30000)


## HeroRes::create_powerful_unit's figures: a power of 50-100 (mostly the
## lower end) sets combat and leadership levels, their maximums, and above
## 35 an item of matching rarity.
static func powerful_stats(g: Game, sprite: String, power := 0, historic := -1) -> Dictionary:
	var rng := g.rng
	if power == 0:
		var rc := rng.randi() % 10
		if rc == 0:
			power = 50 + rng.randi() % 50
		elif rc <= 2:
			power = 50 + rng.randi() % 35
		elif rc <= 5:
			power = 50 + rng.randi() % 25
		else:
			power = 50 + rng.randi() % 10
		if historic == 1:
			power = maxi(power, 70)
	var item_id := 0
	var item_para := 0
	if power > 35:
		var rarity := Items.MAX_RARITY * power / 100
		var low := Items.MIN_RARITY + (rng.randi() % (rarity - Items.MIN_RARITY) if rarity > Items.MIN_RARITY else 0) + 1
		item_id = random_item(rng, low, rarity, sprite)
		item_para = Items.random_para(item_id, rng) if item_id > 0 else 0
	var combat := 100 + rng.randi() % 400
	var skill := 100 + (500 - combat) / 3
	combat = combat * power / 100
	skill = skill * power / 100
	combat = maxi(BASIC_COMBAT_TRAIN, combat)
	skill = maxi(BASIC_SKILL_TRAIN, skill)
	var max_combat := maxi(MAX_COMBAT_BATTLE, combat * (100 + rng.randi() % 30) / 100)
	var max_skill := maxi(MAX_SKILL_TRAIN, skill * (100 + rng.randi() % 30) / 100)
	return {"combat": combat, "max_combat": max_combat, "leadership": skill, "max_skill": max_skill,
		"item_id": item_id, "item_para": item_para}


## Item::init_random for a unit: of the rarities given, one it can use (a
## bow only for a unit with a ranged attack - judged, as in the original,
## against its leadership level, which is 0 when the item is chosen).
static func random_item(rng: RandomNumberGenerator, low: int, high: int, sprite: String) -> int:
	var pick := 0
	var n := 0
	for id in Items.TABLE:
		var r: int = Items.TABLE[id][Items.RARE]
		if r < low or r > high or not can_equip(id, sprite, 0):
			continue
		n += 1
		if rng.randi() % n == 0:
			pick = id
	return pick


## ItemRes::can_equip
static func can_equip(id: int, sprite: String, skill: int) -> bool:
	var t: Array = Items.TABLE.get(id, [])
	if t.is_empty():
		return false
	if t[Items.ABILITY] == Items.Ability.ARROW_DAMAGE:
		var ranged := false
		for a in Defs.unit_types.get(sprite, {}).get("attacks", []):
			if int(a["range"]) > 1 and skill >= int(a["combat_lvl"]):
				ranged = true
		return ranged
	return true


## HeroRes::create_powerful_unit: the unit, with loyalty 50-89 unless given.
static func create_powerful_unit(g: Game, at: Vector2i, nid: int, sprite: String, power := 0, loyalty := 0, historic := -1) -> Unit:
	if loyalty == 0:
		loyalty = 50 + g.rng.randi() % 40
	var st := powerful_stats(g, sprite, power, historic)
	var u := g.spawn_unit(sprite, nid, at, float(st["combat"]))
	if u == null:
		return null
	apply_stats(u, st)
	u.loyalty = float(loyalty)
	u.rank = Defs.Rank.SOLDIER
	return u


static func apply_stats(u: Unit, st: Dictionary) -> void:
	u.combat = float(st["combat"])
	u.max_combat = int(st["max_combat"])
	u.leadership = float(st["leadership"])
	if int(st.get("item_id", 0)) > 0:
		u.item_id = int(st["item_id"])
		u.item_para = int(st["item_para"])
	u.refresh_max_hp()
	u.hp = u.max_hp


## HeroRes::create_hero's choice: a hero not yet seen, of the race (if
## given) and for hire or not (if given).
static func pick_hero(g: Game, race := "", for_hire := -1, historic := -1) -> Dictionary:
	var pool: Array = []
	for h in g.hero_info:
		if h["appeared"] or (race != "" and h["race"] != race):
			continue
		if (for_hire != -1 and int(h["for_hire"]) != for_hire) or (historic != -1 and int(h["historic"]) != historic):
			continue
		pool.append(h)
	if pool.is_empty():
		return {}
	return pool[g.rng.randi() % pool.size()]


static func hero_sprite(g: Game, h: Dictionary) -> String:
	var kind := "INF"
	if h["infantry"] and h["special"]:
		kind = "INF" if g.rng.randi() % 2 == 0 else "SPU"
	elif h["special"]:
		kind = "SPU"
	return Defs.unit_sprite(h["race"], kind)


## HeroRes::create_hero: a hero of the list, who has now appeared.
static func create_hero(g: Game, at: Vector2i, nid: int, race := "", power := 0, loyalty := 0, for_hire := -1) -> Unit:
	var h := pick_hero(g, race, for_hire)
	if h.is_empty():
		return null
	var u := create_powerful_unit(g, at, nid, hero_sprite(g, h), power, loyalty, 1 if h["historic"] else 0)
	if u == null:
		return null
	u.hero_id = int(h["id"])
	u.is_hero = true
	u.unit_name = h["name"]
	h["appeared"] = true
	return u


## HeroRes::think_generate_hero: every 20 days, more likely with more human
## kingdoms and as the years pass, a hero comes out of a town while fewer
## than 20 wander the land.
static func think_generate_hero(g: Game) -> void:
	if not g.hero_appear or g.day % 20 != 0:
		return
	# the original counts the kingdoms but the last one (n < nation_array.size())
	var humans := 0
	for i in g.nations.size() - 1:
		var n: Nation = g.nations[i]
		if n.alive and not n.is_fryhtan:
			humans += 1
	var years := g.day / 365
	if (humans > 0 and g.rng.randi() % (90 + years * 2) >= humans) or (humans <= 0 and g.rng.randi() % (120 + years * 2) != 0):
		return
	var count := g.units.filter(func(u): return u.hero_id > 0 and u.nation_id == 0 and not u.dead).size()
	if count + g.rng.randi() % 5 >= MAX_INDEPENDENT_HERO:
		return
	generate_hero(g)


## HeroRes::generate_hero: from an independent town if there is one, else any.
static func generate_hero(g: Game) -> Unit:
	var towns: Array = g.towns.filter(func(t): return not t.dead)
	if towns.is_empty():
		return null
	var start := g.rng.randi() % towns.size()
	var town: Town = null
	for k in towns.size():
		var t: Town = towns[(start + k + 1) % towns.size()]
		if t.nation_id == 0:
			town = t
			break
	if town == null:
		town = towns[(start + 1) % towns.size()]
	var at := g.exit_cell(town.footprint(), Vector2i(town.x1, town.y1))
	return create_hero(g, at, 0, town.race)


## Unit::is_hero_for_hire / hero_hire_cost / can_hire_hero
static func is_for_hire(g: Game, u: Unit) -> bool:
	return u.nation_id == 0 and u.hero_id > 0 and bool(info(g, u.hero_id).get("for_hire", false)) and not u.dead


static func unit_hire_cost(u: Unit) -> int:
	return hire_cost(int(u.combat), u.max_combat, int(u.lead_skill()), 0, u.item_id)


static func can_hire(g: Game, u: Unit, nid: int) -> bool:
	var n := g.nation(nid)
	return is_for_hire(g, u) and n != null and not n.is_fryhtan and n.cash >= unit_hire_cost(u)


## Unit::hire_hero: paid, he joins and is made a general.
static func hire(g: Game, u: Unit, nid: int) -> bool:
	if not can_hire(g, u, nid):
		return false
	g.nation(nid).add_cash(-float(unit_hire_cost(u)), "Hiring")
	Espionage.betray(g, u, nid)
	u.order = Unit.Order.IDLE
	u.path.clear()
	u.rank = Defs.Rank.GENERAL
	return true


## HeroRes::induce_hero_join_nation: a great deed (a Fryhtan All-high
## slain) may bring a wandering hero over, judged by his power against the
## kingdom's reputation, its record against the Fryhtans and his race.
static func induce_hero_join_nation(g: Game, nid: int, induce: int) -> Unit:
	var n := g.nation(nid)
	if n == null or n.is_fryhtan:
		return null
	for i in range(g.units.size() - 1, -1, -1):
		var u: Unit = g.units[i]
		if u.dead or u.hero_id == 0 or u.nation_id != 0:
			continue
		var power := (int(u.lead_skill()) + int(u.combat) / 2) / 3
		if u.item_id > 0:
			power += (int(Items.TABLE.get(u.item_id, [0, 0])[Items.RARE]) + 1) * 10
		if u.obj_id % 2 == 0:
			power -= int(n.kill_monster_score) / 10
		if n.reputation > 0:
			power -= int(n.reputation) / 3
		else:
			power -= int(n.reputation)
		if u.race == n.race:
			power -= 10
		if induce >= power:
			Espionage.betray(g, u, nid)
			# Unit::ai_move_to_nearby_town
			var best: Town = null
			var bd := INF
			for t in g.towns:
				if t.nation_id == nid and not t.dead and t.center_loc().distance_to(u.center_loc()) < bd:
					bd = t.center_loc().distance_to(u.center_loc())
					best = t
			if best:
				u.order_move(g.exit_cell(best.footprint(), Vector2i(u.cell())))
			g.notify_nation(nid, "The hero %s has come to serve you." % u.unit_name, u.center_loc())
			return u
	return null


static func to_save(g: Game) -> Array:
	return g.hero_info


static func from_save(g: Game, a: Array) -> void:
	if a.is_empty():
		init(g)
		return
	g.hero_info = a
	for h in g.hero_info:
		h["id"] = int(h["id"])
