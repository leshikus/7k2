class_name ScenarioLoader
extends RefCounted
## Builds a Game from an original premade scenario (see ScenarioFile): the map
## regenerated from its seed, then the kingdoms, towns, buildings, garrisons,
## units, deposits, rocks and plants it contains.

## RELATION_HOSTILE, TENSE, NEUTRAL, FRIENDLY, ALLIANCE -> Defs.Relation
const RELATION_MAP := [Defs.Relation.WAR, Defs.Relation.NEUTRAL, Defs.Relation.NEUTRAL, Defs.Relation.PEACE, Defs.Relation.ALLIANCE]
const UNIT_MODE_OVERSEE := 1
const UNIT_MODE_CONSTRUCT_FIRM := 4

var g: Game
var s: ScenarioFile
var cfg: Dictionary
var nation_map := {}      # scenario nation recno -> Nation id
var firm_map := {}        # scenario firm recno -> Firm
var town_map := {}        # scenario town recno -> Town
var unit_map := {}        # scenario unit recno -> Unit
var unit_rows: Array = []
var firm_codes: Array = []
var skipped := {}         # what could not be placed, for the log


static func race_code(race_id: int) -> String:
	if race_id > 0 and race_id <= Defs.races.size():
		return Defs.races[race_id - 1]["code"]
	if race_id < 0 and -race_id <= Defs.monsters.size():
		return Defs.monsters[-race_id - 1]["unit"]
	return ""


func build(game: Game, file: ScenarioFile, config: Dictionary) -> void:
	g = game
	s = file
	cfg = config
	unit_rows = Assets.table("UNIT")
	for f in Assets.table("FIRM"):
		firm_codes.append(f["CODE"])
	g.world = WorldMap.new(s.w, s.h)
	g.world.corners = s.terrain_corners()
	g.setup_layers()
	g.reveal_all = cfg.get("reveal", false)
	_nations()
	_sites()
	_towns()
	_firms()
	_units()
	_rocks()
	_plants()
	_explored()
	if not s.goals.is_empty():
		g.goals = Goals.from_scenario(s.goals, _goal_target)
	for n in g.nations:
		if n.king == null or not is_instance_valid(n.king):
			n.king = g._best_heir(n) if not n.is_fryhtan else _strongest(n.id)
			if n.king:
				n.king.rank = Defs.Rank.KING
	g.update_links()
	g._update_fog()
	g._ground_dirty = true
	if not skipped.is_empty():
		print("scenario: not placed ", skipped)


## What a goal's first parameter names, in this game's terms.
func _goal_target(c: Dictionary):
	var p1: int = c["p1"]
	match c["id"]:
		Goals.DEFEAT_KINGDOM, Goals.FORM_ALLY_WITH_KINGDOM:
			return nation_map.get(p1)
		Goals.KILL_UNIT, Goals.KEEP_UNIT_ALIVE, Goals.MEET_UNIT:
			return unit_map.get(p1)
		Goals.CONQUER_TOWN:
			return town_map.get(p1)
		Goals.DESTROY_FIRM, Goals.CONQUER_FIRM:
			return firm_map.get(p1)
		Goals.REACH_UNIT_COUNT:
			return _sprite_of(p1)
		Goals.GET_SCROLL, Goals.ACQUIRE_ITEM:
			return p1
		Goals.ACQUIRE_TECH:
			var techs := Assets.table("TECH")
			return techs[p1 - 1]["TECH"] if p1 >= 1 and p1 <= techs.size() else null
	return null


func _strongest(nid: int) -> Unit:
	var best: Unit = null
	for u in g.units:
		if u.nation_id == nid and not u.dead and (best == null or u.rank * 1000 + u.combat > best.rank * 1000 + best.combat):
			best = u
	return best


func _skip(what: String) -> void:
	skipped[what] = skipped.get(what, 0) + 1


func _nations() -> void:
	var spectate: bool = cfg.get("autoplay", false)
	var player_recno := 0
	for nd in s.nations:
		if nd["type"] == 1:
			player_recno = nd["recno"]
	if player_recno == 0 and not s.nations.is_empty():
		player_recno = s.nations[0]["recno"]
	# the player's kingdom first so that it gets id 1
	var order: Array = s.nations.duplicate()
	order.sort_custom(func(a, b): return (a["recno"] == player_recno) and b["recno"] != player_recno)
	for nd in order:
		var code := race_code(nd["race"])
		if code == "":
			continue
		var id := g.nations.size() + 1
		var col: Color = Defs.NATION_COLORS[clampi(nd["color"] - 1, 0, Defs.NATION_COLORS.size() - 1)]
		var is_player: bool = nd["recno"] == player_recno
		var n := Nation.new(id, code, col, not is_player or spectate)
		n.is_player = is_player
		n.cash = maxf(0.0, nd["cash"])
		n.food = maxf(0.0, nd["food"])
		n.reputation = clampf(nd["reputation"], -100.0, 100.0)
		if nd["race"] < 0:
			n.is_fryhtan = true
			n.monster_code = code
			n.live_points = maxf(300.0, nd["live_points"])
			n.name = "%s Fryhtans" % Defs.monsters[-nd["race"] - 1]["name"]
		if nd["name"] != "":
			n.name = nd["name"]
		g.nations.append(n)
		nation_map[nd["recno"]] = id
	g.player_id = 1
	for nd in s.nations:
		if not nation_map.has(nd["recno"]):
			continue
		var a := g.nation(nation_map[nd["recno"]])
		for k in nd["relations"].size():
			var other: int = k + 1
			if other == nd["recno"] or not nation_map.has(other):
				continue
			a.relations[nation_map[other]] = RELATION_MAP[clampi(nd["relations"][k], 0, 4)]
	for n in g.nations:
		if n.is_ai:
			n.ai = FryhtanAI.new(n, g) if n.is_fryhtan else NationAI.new(n, g)


func _nid(recno: int, race_id := 0) -> int:
	if recno <= 0:
		return GameObj.MONSTER_NATION if race_id < 0 else 0
	return nation_map.get(recno, 0)


func _sites() -> void:
	var raws: Array = Assets.table("RAW")
	for sd in s.sites:
		if sd["type"] >= Treasure.Kind.SCROLL and sd["type"] <= Treasure.Kind.BLUEPRINT:
			# scrolls, gold, items and weapon plans lying on the map
			g.spawn_treasure(sd["type"], sd["object_id"], sd["qty"], Vector2i(sd["x"], sd["y"]), sd["recno"])
			continue
		if sd["type"] != 1 or sd["object_id"] < 1 or sd["object_id"] > mini(3, raws.size()):
			_skip("site type %d" % sd["type"])
			continue
		var row: Dictionary = raws[sd["object_id"] - 1]
		var site := Site.new()
		site.raw = row["NAME"]
		site.row = row
		site.x1 = sd["x"]
		site.y1 = sd["y"]
		site.w = row["LOC_WIDTH"].to_int()
		site.h = row["LOC_HEIGHT"].to_int()
		site.reserve = float(sd["qty"])
		g.sites.append(site)


func _towns() -> void:
	var names: Array = Assets.table("TOWNNAME")
	for td in s.towns:
		var race := race_code(td["race"])
		if race == "" or td["race"] < 0:
			_skip("town")
			continue
		var name := ""
		var nid: int = td["name_id"]
		if nid >= 1 and nid <= names.size() and not String(names[nid - 1]["NAME"]).begins_with("@"):
			name = names[nid - 1]["NAME"]
		var t := g.spawn_town(race, _nid(td["nation"]), Vector2i(td["x"], td["y"]), maxi(1, td["population"]), name)
		town_map[td["recno"]] = t
		t.loyalty = clampf(td["loyalty"], 0.0, 100.0)
		t.target_loyalty = t.loyalty
		for k in td["resistance"].size():
			if nation_map.has(k + 1):
				t.resistance[nation_map[k + 1]] = clampf(td["resistance"][k], 0.0, 100.0)
		t.wall_level = clampi(td["wall"], 0, 2)
		t.target_wall_level = clampi(maxi(td["wall"], td["target_wall"]), 0, 2)
		if t.wall_level > 0:
			t.wall_hp = t.wall_max_hp()
		t._pick_layout()


func _firms() -> void:
	for fd in s.firms:
		var fid: int = fd["firm_id"]
		if fid < 1 or fid > firm_codes.size():
			_skip("firm id %d" % fid)
			continue
		var code: String = firm_codes[fid - 1]
		var race := race_code(fd["race"])
		var nid := _nid(fd["nation"], fd["race"])
		var f := g.spawn_firm(code, nid, race, Vector2i(fd["x"], fd["y"]), not fd["under_construction"], fd["build_id"])
		if f == null:
			_skip(code)
			continue
		if code == "LAIR":
			f.monster_code = race
		if fd["max_hp"] > 0.0:
			f.hp = f.max_hp * clampf(fd["hp"] / fd["max_hp"], 0.05, 1.0)
			if f.under_construction:
				f.progress = clampf(fd["hp"] / fd["max_hp"] * 100.0, 0.0, 99.0)
		firm_map[fd["recno"]] = f
		for sd in fd["soldiers"]:
			var u := _spawn(sd["unit_id"], nid, Vector2i(f.x1, f.y1 + f.h), sd["combat"], sd["skill"], sd["rank"], sd["race"])
			if u == null:
				continue
			if not f.accept_unit(u):
				u.loc = Vector2(g.world.adjacent_to_rect(f.footprint(), f.door()))
				u.position = Iso.to_screen(u.loc)


func _sprite_of(unit_id: int) -> String:
	if unit_id < 1 or unit_id > unit_rows.size():
		return ""
	return unit_rows[unit_id - 1]["SPRITE"]


func _spawn(unit_id: int, nid: int, at: Vector2i, combat: float, skill: float, rank: int, race_id: int) -> Unit:
	var spr := _sprite_of(unit_id)
	if spr == "":
		_skip("unit id %d" % unit_id)
		return null
	var u := g.spawn_unit(spr, nid, at, clampf(combat, 5.0, 100.0))
	if u == null:
		_skip(spr)
		return null
	u.rank = clampi(rank, 0, 2)
	u.leadership = clampf(skill, 0.0, 100.0)
	return u


func _units() -> void:
	var kings := {}
	for nd in s.nations:
		if nd["king"] > 0 and nation_map.has(nd["recno"]):
			kings[nd["king"]] = nation_map[nd["recno"]]
	var heroes: Array = Assets.table("HERO")
	for ud in s.units:
		if ud["spy"] > 0:
			_skip("spy")        # spies are cloaked as another kingdom; their true side is in the spy array
			continue
		var nid := _nid(ud["nation"], ud["race"])
		var on_map: bool = ud["x"] >= 0 and ud["y"] >= 0
		var host: Firm = firm_map.get(ud["mode_para"]) if ud["mode"] in [UNIT_MODE_OVERSEE, UNIT_MODE_CONSTRUCT_FIRM] else null
		var at := Vector2i(ud["x"] >> 5, ud["y"] >> 5) if on_map else (Vector2i(host.x1, host.y1 + host.h) if host else Vector2i(-1, -1))
		if at.x < 0:
			_skip("unit off map")
			continue
		var u := _spawn(ud["unit_id"], nid, at, ud["combat"], ud["skill"], ud["rank"], ud["race"])
		if u == null:
			continue
		unit_map[ud["recno"]] = u
		if ud["hero_id"] > 0 and ud["hero_id"] <= heroes.size():
			u.is_hero = true
			u.unit_name = heroes[ud["hero_id"] - 1]["NAME"]
		if kings.has(ud["recno"]) and kings[ud["recno"]] == nid:
			u.rank = Defs.Rank.KING
			u.max_hp *= 2.0
			u.hp = u.max_hp
			g.nation(nid).king = u
		if host and not on_map:
			if ud["mode"] == UNIT_MODE_OVERSEE:
				if host.overseer == null and host.is_military():
					host.overseer = u
					host._hide_unit(u)
				elif not host.accept_unit(u):
					pass
			elif ud["mode"] == UNIT_MODE_CONSTRUCT_FIRM:
				host.set_builder(u)


func _rocks() -> void:
	var types := Assets.load_rocks()
	var by_row := {}
	for i in types.size():
		by_row[types[i]["row"]] = i
	for rd in s.rocks:
		if by_row.has(rd["recno"]):
			_place_rock(by_row[rd["recno"]], Vector2i(rd["x"], rd["y"]))
		else:
			_skip("rock")
	for rd in s.dirts:
		# dirt patches are flat decorations; only ponds block the way
		if by_row.has(rd["recno"]) and types[by_row[rd["recno"]]]["type"] == "P":
			_place_rock(by_row[rd["recno"]], Vector2i(rd["x"], rd["y"]))


func _place_rock(ti: int, at: Vector2i) -> void:
	var t: Dictionary = Assets.rock_types[ti]
	if at.x < 0 or at.y < 0 or at.x + t["w"] > g.world.w or at.y + t["h"] > g.world.h:
		_skip("rock outside")
		return
	for y in range(at.y, at.y + t["h"]):
		for x in range(at.x, at.x + t["w"]):
			var o = g.world.occupant[y * g.world.w + x]
			if o != null and not (o is Rock):
				_skip("rock overlap")
				return
	g.add_rock(ti, at)


func _plants() -> void:
	if Assets.plant_bitmaps.is_empty():
		return
	var extra: PackedByteArray = s.planes["extra"]
	for y in s.h:
		for x in s.w:
			if s.loc_flag(x, y) & ScenarioFile.LOCATE_BLOCK_MASK != ScenarioFile.LOCATE_IS_PLANT:
				continue
			var c := Vector2i(x, y)
			if not g.world.is_free(c):
				continue
			g.place_tree(c, Assets.plant_variant_of_row.get(extra[y * s.w + x], 0))


## Locations the player had explored when the scenario was saved.
func _explored() -> void:
	var visit: PackedByteArray = s.planes["visit"]
	for i in mini(visit.size(), g.fog.size()):
		if visit[i] > 0 and g.fog[i] == 0:
			g.fog[i] = 1
