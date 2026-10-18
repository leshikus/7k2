class_name Independents
extends RefCounted
## Independent towns thinking for themselves (otownind.cpp, otowna.cpp): they
## raise walls, their villagers go over to admired kingdoms of their race,
## a big one may proclaim a kingdom of its own, and wanderers settle new
## villages (TownArray::think_new_independent_town).

const INDEPENDENT_LINK_RESISTANCE := 50
const NEW_NATION_INTERVAL_DAYS := 365
const MIN_INTER_TOWN_DISTANCE := 16.0


static func next_day(g: Game) -> void:
	var day := g.day
	for t in g.towns.duplicate():
		if t.dead or t.nation_id != 0 or t.under_construction or t.population <= 0:
			continue
		if day % 15 == t.obj_id % 15:
			think_set_link(g, t)
		if day % 60 == t.obj_id % 60:
			think_unit_join_nation(g, t)
		if day % 90 == t.obj_id % 90:
			think_build_wall(g, t)
		if day % 365 == t.obj_id % 365:
			think_form_new_nation(g, t)
	if day % 30 == 0:
		think_new_town(g)


static func _setting(g: Game, key: String, fallback):
	return g.config.get(key, GameSetup.defaults().get(key, fallback))


## Town::think_independent_set_link: an independent town works for a foreign
## building only while its resistance to that kingdom is low (not for camps).
static func think_set_link(g: Game, t: Town) -> void:
	for f in t.linked_firms:
		if f.dead or Espionage.is_camp(f) or f.code == "LAIR":
			continue
		var on := f.nation_id <= 0 or t.resistance_to(f.nation_id) <= Game.INDEPENDENT_LINK_RESISTANCE
		if g.link_side(t, f) != on:
			g.set_link(t, f, on)


## Town::think_independent_build_wall
static func think_build_wall(g: Game, t: Town) -> void:
	if t.target_wall_level > t.wall_level or t.wall_level >= 2:
		return
	var chance: int = {GameSetup.LOW: 5, GameSetup.MODERATE: 15, GameSetup.HIGH: 30}.get(int(_setting(g, "resistance", GameSetup.LOW)), 5)
	chance += t.population / 2
	if g.rng.randi() % 200 < chance:
		t.target_wall_level = t.wall_level + 1


## Town::think_independent_unit_join_nation: once in a while a villager goes
## over to the kingdom of his race with the best reputation and standing.
static func think_unit_join_nation(g: Game, t: Town) -> void:
	if t.jobless() <= 0:
		return
	if t.join_min_rating < 0:
		t.join_min_rating = 100 + g.rng.randi() % 150     # Town::init
	t.join_min_rating -= 2
	var best_rating := t.join_min_rating
	var best: Town = null
	for o in g.towns:
		if o.dead or o.race != t.race or o.nation_id <= 0 or o.nation_id == GameObj.MONSTER_NATION:
			continue
		var n := g.nation(o.nation_id)
		if n == null or not n.alive or n.cash <= 0.0 or g.day < n.last_independent_join_day + 90:
			continue
		var r := int(n.reputation) + Goals.total_score(g, n)
		if r > best_rating:
			best_rating = r
			best = o
	if best == null:
		return
	# Town::independent_unit_join_nation: he walks out and changes sides
	var c := g.exit_cell(t.footprint(), Vector2i(t.x1 + 3, t.y1 + Defs.TOWN_SIZE))
	var u := g.spawn_unit(Defs.unit_sprite(t.race, "CIV"), best.nation_id, c, Defs.CITIZEN_COMBAT_LEVEL)
	if u == null:
		return
	u.loyalty = t.loyalty if t.nation_id > 0 else 50.0
	t.population -= 1
	t._check_empty()
	t.queue_redraw()
	var n := g.nation(best.nation_id)
	n.last_independent_join_day = g.day
	g.notify_nation(n.id, "A villager of %s has come to join your kingdom." % t.town_name, Vector2(c), true)
	t.join_min_rating = maxi(100, best_rating + 100 + g.rng.randi() % 30)


## Town::think_independent_form_new_nation
static func think_form_new_nation(g: Game, t: Town) -> void:
	if g.rng.randi() % 10 > 0 or t.population < 30:
		return
	var all_pop := 0
	for o in g.towns:
		if o.nation_id > 0 and not o.dead:
			all_pop += o.population
	if all_pop > 60 * Defs.MAX_NATION:
		return
	if not can_form_new_ai_nation(g) or t.tribute_to() > 0:
		return
	form_new_nation(g, t)


## NationArray::can_form_new_ai_nation
static func can_form_new_ai_nation(g: Game) -> bool:
	if not _setting(g, "nation_emerge", false):
		return false
	var ai_alive := g.nations.filter(func(n): return n.alive and n.is_ai).size()
	var configured := int(g.config.get("ai_count", 0)) + int(g.config.get("fryhtan_count", 0))
	var alive := g.nations.filter(func(n): return n.alive).size()
	return ai_alive < configured and alive < Defs.MAX_NATION \
		and g.day > g.last_del_nation_day + NEW_NATION_INTERVAL_DAYS and g.day > g.last_new_nation_day + NEW_NATION_INTERVAL_DAYS


## Town::form_new_nation: a king of combat 70-100 and leadership 50-100; the
## town's loyalty 70-90; no surrender for two years; perhaps some extra cash,
## food or leaders.
static func form_new_nation(g: Game, t: Town) -> int:
	var c := g.exit_cell(t.footprint(), Vector2i(t.x1 + 3, t.y1 + Defs.TOWN_SIZE))
	var n := g.add_nation(t.race)
	var king := g.spawn_unit(Defs.unit_sprite(t.race, "INF"), n.id, c, float(70 + g.rng.randi() % 31))
	if king == null:
		return 0
	king.rank = Defs.Rank.KING
	king.leadership = float(50 + g.rng.randi() % 51)
	king.loyalty = 100.0
	n.king = king
	t.population -= 1
	t.surrender(n.id)
	t.loyalty = float(70 + g.rng.randi() % 20)
	for o in g.nations:
		if o != n:
			n.never_until["REQUEST_SURRENDER:%d" % o.id] = g.day + 365 * 2
	match g.rng.randi() % 10:
		2: n.cash += float(g.rng.randi() % 5000)
		3: n.food += float(g.rng.randi() % 5000)
		4:
			for i in g.rng.randi() % 5 + 1:
				if t.jobless() <= 0:
					break
				var u := g.spawn_unit(Defs.unit_sprite(t.race, "CIV"), n.id, c + Vector2i(i + 1, 0), float(50 + g.rng.randi() % 50))
				if u == null:
					break
				u.leadership = float(50 + g.rng.randi() % 50)
				t.population -= 1
	g.last_new_nation_day = g.day
	g.notify("A new kingdom, the %s, has been founded in %s." % [n.name, t.town_name], t.center_loc())
	return n.id


## TownArray::think_new_independent_town: wanderers of every race gather a few
## a month; ten of a race found a village of 20-30 somewhere free, while there
## are fewer than ten independent towns and fewer than a thousand people.
static func think_new_town(g: Game) -> void:
	if not _setting(g, "town_emerge", true) or g.rng.randi() % 3 != 0:
		return
	var indep := 0
	var all_pop := 0
	for t in g.towns:
		if t.dead:
			continue
		all_pop += t.population
		if t.nation_id == 0:
			indep += 1
	if indep >= 10 or all_pop > 1000:
		return
	for r in Defs.races:
		g.race_wanderers[r["code"]] = int(g.race_wanderers.get(r["code"], 0)) + 2 + g.rng.randi() % 5
	var start := g.rng.randi() % Defs.races.size()
	var race := ""
	for i in Defs.races.size():
		var code: String = Defs.races[(start + i + 1) % Defs.races.size()]["code"]
		if int(g.race_wanderers.get(code, 0)) >= 10:
			race = code
			break
	if race == "":
		return
	var p := _town_loc(g, g.world.w * g.world.h / 4)
	if p.x < 0:
		return
	var pop := mini(20 + g.rng.randi() % 10, int(g.race_wanderers[race]))
	var t := g.spawn_town(race, 0, p, pop)
	var res := GameSetup.town_resistance(g.config if g.config.has("resistance") else GameSetup.defaults(), g.rng)
	t.base_resistance = float(res)
	for n in g.nations:
		t.resistance[n.id] = float(res)
	g.race_wanderers[race] = int(g.race_wanderers[race]) - pop
	g.update_links()


## TownArray::think_town_loc: free ground at least 16 away from every town.
static func _town_loc(g: Game, tries: int) -> Vector2i:
	for i in mini(tries, 2000):
		var x := g.rng.randi() % maxi(1, g.world.w - 20)
		var y := 2 + g.rng.randi() % maxi(1, g.world.h - 18)
		if not g.world.can_place(x, y, Defs.TOWN_SIZE + 4, Defs.TOWN_SIZE + 4) or g._overlaps_site(Rect2i(x, y, Defs.TOWN_SIZE + 4, Defs.TOWN_SIZE + 4)):
			continue
		var c := Vector2(x + 2 + Defs.TOWN_SIZE / 2.0, y + 2 + Defs.TOWN_SIZE / 2.0)
		if g.towns.any(func(t): return not t.dead and t.center_loc().distance_to(c) < MIN_INTER_TOWN_DISTANCE):
			continue
		if g.firms.any(func(f): return not f.dead and f.center_loc().distance_to(c) < 8.0):
			continue
		return Vector2i(x + 2, y + 2)
	return Vector2i(-1, -1)
