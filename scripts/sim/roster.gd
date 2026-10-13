class_name Roster
extends RefCounted
## The heroes and items a player profile keeps between games (PlayerProfile::
## hero_array, item_array, ProfileHero). The original keeps these records -
## up to MAX_PROFILE_HERO heroes and MAX_PROFILE_ITEM items, with each hero's
## unit, rank, name, skill, loyalty, item and spy details and an on-duty mark -
## and the functions to fill them from a unit (update_unit) and to create the
## unit again (create_unit), but no menu of its own uses them. Here they work
## as those functions describe: a won game puts the player's surviving heroes
## and the items his men carry on the roster; a new game can bring them along;
## heroes on duty come back with what they learnt, or are struck off if they fell.

const MAX_HERO := 20      # PlayerProfile::MAX_PROFILE_HERO
const MAX_ITEM := 40      # PlayerProfile::MAX_PROFILE_ITEM


static func _path() -> String:
	var n := Profiles._safe(Profiles.current())
	return "" if n == "" else "%s/%s/roster.json" % [Profiles.ROOT, n]


static func load_roster() -> Dictionary:
	var p := _path()
	if p == "" or not FileAccess.file_exists(p):
		return {"heroes": [], "items": []}
	var d = JSON.parse_string(FileAccess.get_file_as_string(p))
	return d if d is Dictionary else {"heroes": [], "items": []}


static func save_roster(r: Dictionary) -> void:
	var p := _path()
	if p == "":
		return
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(r))


## ProfileHero::update_unit
static func record(u: Unit) -> Dictionary:
	return {"sprite": u.sprite_code, "rank": u.rank, "race": u.race, "name": u.unit_name,
		"combat": u.combat, "leadership": u.leadership, "loyalty": u.loyalty,
		"item": [u.item_id, u.item_para], "is_spy": u.is_spy, "spy_skill": u.spy_skill, "on_duty": false}


## ProfileHero::create_unit: the hero joins the kingdom at `at`.
static func create(g: Game, h: Dictionary, nid: int, at: Vector2i) -> Unit:
	var u := g.spawn_unit(str(h["sprite"]), nid, g.free_unit_cell(at), float(h["combat"]))
	if u == null:
		return null
	u.is_hero = true
	u.rank = Defs.Rank.GENERAL if int(h["rank"]) >= Defs.Rank.GENERAL else Defs.Rank.SOLDIER
	u.unit_name = str(h["name"])
	u.leadership = float(h["leadership"])
	u.loyalty = float(h["loyalty"])
	u.item_id = int(h["item"][0])
	u.item_para = int(h["item"][1])
	u.refresh_max_hp()
	u.hp = u.max_hp
	u.is_spy = bool(h.get("is_spy", false))
	u.spy_skill = float(h.get("spy_skill", 0.0))
	u.set_meta("roster", str(h["name"]))
	return u


## At the start of a game: the heroes not on duty join the player beside his
## king, and the stored items lie at his feet. Returns how many heroes came.
static func bring(g: Game) -> int:
	var r := load_roster()
	var p := g.player()
	if p == null or (r["heroes"].is_empty() and r["items"].is_empty()):
		return 0
	var at: Vector2i = p.king.cell() if p.king and is_instance_valid(p.king) else Vector2i(g.start_points[0]) if not g.start_points.is_empty() else Vector2i(10, 10)
	if p.king and p.king.inside_firm:
		at = g.world.adjacent_to_rect(p.king.inside_firm.footprint(), at)
	var n := 0
	for h in r["heroes"]:
		if h.get("on_duty", false):
			continue
		if create(g, h, p.id, at + Vector2i(n % 3, 2 + n / 3)):
			h["on_duty"] = true
			n += 1
	for it in r["items"]:
		var c := g._free_treasure_cell(at + Vector2i(-2, 0))
		if c.x >= 0:
			g.spawn_treasure(Treasure.Kind.ITEM, int(it[0]), int(it[1]), c)
	r["items"] = []
	save_roster(r)
	return n


## At the end of a game: heroes on duty come back (with what they learnt) or
## are struck off; after a victory the player's other heroes and his men's
## items join the roster, as far as it has room.
static func settle(g: Game, won: bool) -> void:
	if _path() == "":
		return
	var r := load_roster()
	var p := g.player()
	var alive := {}
	if p:
		for u in g.units:
			if not u.dead and u.nation_id == p.id and u.is_hero:
				alive[u.unit_name] = u
	var kept: Array = []
	for h in r["heroes"]:
		if not h.get("on_duty", false):
			kept.append(h)
		elif alive.has(h["name"]):
			kept.append(record(alive[h["name"]]))
			alive.erase(h["name"])
	if won:
		for nm in alive:
			if kept.size() >= MAX_HERO:
				break
			if not kept.any(func(h): return h["name"] == nm):
				kept.append(record(alive[nm]))
		if p:
			for u in g.units:
				if r["items"].size() >= MAX_ITEM:
					break
				if not u.dead and u.nation_id == p.id and not u.is_hero and u.item_id > 0:
					r["items"].append([u.item_id, u.item_para])
	r["heroes"] = kept
	save_roster(r)
