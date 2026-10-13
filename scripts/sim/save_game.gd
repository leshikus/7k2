class_name SaveGame
## Saves and restores a running game as JSON in user://saves/.
## Objects reference each other by obj_id; references are resolved after
## every object has been recreated. Transient state (paths, current attack
## targets, projectiles) is not saved: units come back idle.

const VERSION := 1
const DIR := "user://saves"


static func path_for(slot: String) -> String:
	return "%s/%s.json" % [DIR, slot]


static func exists(slot: String) -> bool:
	return FileAccess.file_exists(path_for(slot))


static func describe(slot: String) -> String:
	var d := _read(path_for(slot))
	if d.is_empty():
		return ""
	return "%s — %s" % [d.get("kingdom", "?"), d.get("date", "?")]


# ------------------------------------------------------------------- save ---

static func save(g: Game, slot: String) -> bool:
	DirAccess.make_dir_recursive_absolute(DIR)
	return save_path(g, path_for(slot))


## Scenarios made in the editor (ScenarioEditorWindow), saved like games.
const SCENARIO_DIR := "user://scenarios"


static func save_scenario(g: Game, name: String, text: String) -> String:
	DirAccess.make_dir_recursive_absolute(SCENARIO_DIR)
	var safe := ""
	for ch in name.strip_edges():
		safe += ch if ch.is_valid_identifier() or ch.is_valid_int() or ch in [" ", "-"] else "_"
	if safe.strip_edges() == "":
		safe = "My scenario"
	var path := "%s/%s.json" % [SCENARIO_DIR, safe.strip_edges()]
	return path if save_path(g, path, {"scenario_name": name, "scenario_text": text}) else ""


static func list_scenarios() -> Array:
	var out: Array = []
	var dir := DirAccess.open(SCENARIO_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.get_extension() != "json":
			continue
		var path := SCENARIO_DIR.path_join(f)
		var d := _read(path)
		out.append({"path": ProjectSettings.globalize_path(path), "name": d.get("scenario_name", f.get_basename()),
			"text": d.get("scenario_text", ""), "difficulty": 0, "source": "yours"})
	return out


static func save_path(g: Game, path: String, extra := {}) -> bool:
	var d := {
		"version": VERSION,
		"kingdom": g.player().name,
		"date": g.date_string(),
		"config": g.config,
		"rng_seed": str(g.rng.seed),
		"rng_state": str(g.rng.state),
		"frame": g.frame,
		"day": g.day,
		"player_id": g.player_id,
		"reveal_all": g.reveal_all,
		"next_id": GameObj._next_id,
		"world": {
			"w": g.world.w, "h": g.world.h,
			"corners": Marshalls.raw_to_base64(g.world.corners),
		},
		"fog": Marshalls.raw_to_base64(g.fog),
		"trees": _trees(g),
		"rocks": g.rocks.map(func(r): return [r.kind, r.x1, r.y1]),
		"weather": g.weather.to_dict(),
		"start_points": g.start_points.map(func(p): return [p.x, p.y]),
		"used_town_names": g._used_town_names.keys(),
		"sites": g.sites.map(func(s): return _site(g, s)),
		"nations": g.nations.map(func(n): return _nation(n)),
		"towns": g.towns.filter(func(t): return not t.dead).map(func(t): return _town(t)),
		"firms": g.firms.filter(func(f): return not f.dead).map(func(f): return _firm(g, f)),
		"units": g.units.filter(func(u): return not u.dead).map(func(u): return _unit(u)),
		"goals": g.goals.to_dict(_id) if g.goals else null,
		"treasures": g.treasures.map(func(t): return [t.kind, t.object_id, t.para, t.cell.x, t.cell.y, t.recno]),
		"taken_sites": g.taken_sites,
		"year0": g.year0,
		"tech_available": g.tech_available,
		"campaign_battle": g.campaign_battle.to_dict(_id) if g.campaign_battle else null,
	}
	d.merge(extra)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(d, "", false, true))   # full float precision
	return true


static func _trees(g: Game) -> Array:
	var out := []
	for c in g._plants:
		out.append([c.x, c.y, g._plants[c].variant])
	return out


static func _id(o: Object) -> int:
	if o == null or not is_instance_valid(o):
		return 0
	return (o as GameObj).obj_id


static func _site(g: Game, s: Site) -> Dictionary:
	return {"raw": s.raw, "row": Assets.table("RAW").find(s.row), "x1": s.x1, "y1": s.y1, "w": s.w, "h": s.h, "reserve": s.reserve}


static func _nation(n: Nation) -> Dictionary:
	var d := {
		"id": n.id, "name": n.name, "race": n.race, "color": n.color.to_html(false), "is_ai": n.is_ai,
		"is_player": n.is_player, "alive": n.alive, "cash": n.cash, "food": n.food, "reputation": n.reputation,
		"king": _id(n.king), "tech": n.tech, "research_progress": n.research_progress,
		"relations": _int_keys_to_str(n.relations), "prayer_points": n.prayer_points,
		"income_year": n.income_year, "expense_year": n.expense_year,
		"last_income_year": n.last_income_year, "last_expense_year": n.last_expense_year,
		"income_by": n.income_by, "expense_by": n.expense_by, "last_income_by": n.last_income_by, "last_expense_by": n.last_expense_by, "kill_monster_score": n.kill_monster_score,
		"is_fryhtan": n.is_fryhtan, "monster_code": n.monster_code, "live_points": n.live_points, "had_base": n.had_base, "homeless_days": n.homeless_days,
		"known_gods": n.known_gods.keys(), "items_acquired": n.items_acquired.keys(),
	}
	if n.ai:
		d["ai"] = {"war_target": n.ai.war_target, "war_start_day": n.ai.war_start_day, "aggression": n.ai.aggression}
	return d


static func _town(t: Town) -> Dictionary:
	return {
		"id": t.obj_id, "name": t.town_name, "race": t.race, "nation": t.nation_id, "x1": t.x1, "y1": t.y1,
		"population": t.population, "loyalty": t.loyalty, "target_loyalty": t.target_loyalty,
		"resistance": _int_keys_to_str(t.resistance), "target_resistance": _int_keys_to_str(t.target_resistance),
		"qol": t.quality_of_life, "bonus_loyalty": t.bonus_loyalty, "growth": t.population_growth,
		"tax_penalty": t.tax_penalty, "auto_tax": t.auto_tax_loyalty, "auto_grant": t.auto_grant_loyalty, "recruit_penalty": t.recruit_penalty, "grant_penalty": t.grant_penalty,
		"last_rebel_day": t.last_rebel_day,
		"wall_level": t.wall_level, "target_wall_level": t.target_wall_level, "wall_progress": t.wall_progress, "wall_hp": t.wall_hp,
	}


static func _firm(g: Game, f: Firm) -> Dictionary:
	return {
		"id": f.obj_id, "code": f.code, "nation": f.nation_id, "race": f.race, "x1": f.x1, "y1": f.y1, "build_row": f.build_row,
		"under_construction": f.under_construction, "progress": f.progress, "hp": f.hp,
		"builder": _id(f.builder), "overseer": _id(f.overseer), "soldiers": f.soldiers.map(func(u): return u.obj_id),
		"site": g.sites.find(f.site), "raw": f.raw, "reserve": f.reserve, "stock": f.stock, "raw_stock": f.raw_stock,
		"goods": f.goods, "market_sales": f.market_sales, "research_tech": f.research_tech,
		"research_points": f.research_points, "weapon": f.weapon, "weapon_progress": f.weapon_progress,
		"weapon_queue": f.weapon_queue, "heroes": f.heroes, "monster": f.monster_code, "raid_timer": f.raid_timer,
		"max_hp": f.max_hp, "charge": f.cast_charge, "extra": f.extra_units.map(func(u): return u.obj_id),
		"animals": f.animals, "alchemy": f.alchemy_mode, "propagate": f.propagate, "rally": [f.rally.x, f.rally.y],
	}


static func _unit(u: Unit) -> Dictionary:
	return {
		"id": u.obj_id, "sprite": u.sprite_code, "nation": u.nation_id, "x": u.loc.x, "y": u.loc.y,
		"rank": u.rank, "combat": u.combat, "leadership": u.leadership, "hp": u.hp, "max_hp": u.max_hp,
		"name": u.unit_name, "hero": u.is_hero, "life": u.life_frames, "dir": u.dir, "ver": u.weapon_version,
		"home_town": _id(u.home_town), "home_firm": _id(u.home_firm), "inside": _id(u.inside_firm),
		"spy": u.is_spy, "spy_skill": u.spy_skill, "spy_place": _id(u.spy_place), "spy_action": u.spy_action, "hidden": u.has_meta("hidden"),
		"cloak": u.cloak_id, "camo": [u.camouflage_days, u.camouflage_power], "sleeper": u.sleeper_for, "loyalty": u.loyalty,
		"item": [u.item_id, u.item_para],
		"caravan_home": _id(u.caravan_home), "caravan_dest": _id(u.caravan_dest), "caravan_leg": u.caravan_leg, "cargo": u.cargo,
	}


static func _int_keys_to_str(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[str(k)] = d[k]
	return out


static func _str_keys_to_int(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[int(k)] = d[k]
	return out


# ------------------------------------------------------------------- load ---

static func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var txt := FileAccess.get_file_as_string(path)
	var v = JSON.parse_string(txt)
	return v if v is Dictionary else {}


## Rebuilds the saved game into `g` (a fresh Game already in the scene tree).
## Returns "" on success or an error message.
static func load_into(g: Game, slot: String) -> String:
	return load_path(g, path_for(slot))


static func load_path(g: Game, path: String) -> String:
	var d := _read(path)
	if d.is_empty():
		return "Save file not found or unreadable."
	if int(d.get("version", 0)) != VERSION:
		return "Save file is from an incompatible version."
	Defs.load_from_assets()
	g.config = d.get("config", {})
	var wd: Dictionary = d["world"]
	g.world = WorldMap.new(int(wd["w"]), int(wd["h"]))
	g.world.corners = Marshalls.base64_to_raw(wd["corners"])
	g.setup_layers()
	g.frame = int(d["frame"])
	g.day = int(d["day"])
	g.player_id = int(d["player_id"])
	g.reveal_all = d.get("reveal_all", false)
	g.start_points = d.get("start_points", []).map(func(p): return Vector2(p[0], p[1]))
	for n in d.get("used_town_names", []):
		g._used_town_names[n] = true

	# kingdoms
	for nd in d["nations"]:
		var n := Nation.new(int(nd["id"]), nd["race"], Color.html(nd["color"]), nd["is_ai"])
		n.name = nd["name"]
		n.is_player = nd["is_player"]
		n.alive = nd["alive"]
		n.cash = float(nd["cash"])
		n.food = float(nd["food"])
		n.reputation = float(nd["reputation"])
		for k in nd["tech"]:
			n.tech[k] = int(nd["tech"][k])
		n.research_progress = nd["research_progress"]
		for k in nd["relations"]:
			n.relations[int(k)] = int(nd["relations"][k])
		n.prayer_points = float(nd["prayer_points"])
		n.income_year = float(nd["income_year"])
		n.expense_year = float(nd["expense_year"])
		n.last_income_year = float(nd.get("last_income_year", 0.0))
		n.income_by = nd.get("income_by", {})
		n.expense_by = nd.get("expense_by", {})
		n.last_income_by = nd.get("last_income_by", {})
		n.last_expense_by = nd.get("last_expense_by", {})
		n.last_expense_year = float(nd.get("last_expense_year", 0.0))
		n.kill_monster_score = float(nd.get("kill_monster_score", 0.0))
		if nd.has("known_gods"):
			n.known_gods.clear()
			for r in nd["known_gods"]:
				n.known_gods[r] = true
		for i in nd.get("items_acquired", []):
			n.items_acquired[int(i)] = true
		n.is_fryhtan = nd.get("is_fryhtan", false)
		n.monster_code = nd.get("monster_code", "")
		n.live_points = float(nd.get("live_points", 0.0))
		n.had_base = bool(nd.get("had_base", true))
		n.homeless_days = int(nd.get("homeless_days", 0))
		if n.is_ai:
			n.ai = FryhtanAI.new(n, g) if n.is_fryhtan else NationAI.new(n, g)
			var ad: Dictionary = nd.get("ai", {})
			n.ai.war_target = int(ad.get("war_target", 0))
			n.ai.war_start_day = int(ad.get("war_start_day", 0))
			n.ai.aggression = float(ad.get("aggression", 1.0))
		n.set_meta("king_id", int(nd["king"]))
		g.nations.append(n)

	# raw sites
	var raw_rows := Assets.table("RAW")
	for sd in d["sites"]:
		var s := Site.new()
		s.raw = sd["raw"]
		var ri := int(sd["row"])
		s.row = raw_rows[ri] if ri >= 0 and ri < raw_rows.size() else {}
		s.x1 = int(sd["x1"])
		s.y1 = int(sd["y1"])
		s.w = int(sd["w"])
		s.h = int(sd["h"])
		s.reserve = float(sd["reserve"])
		g.sites.append(s)

	var by_id := {}
	# towns
	for td in d["towns"]:
		var t := g.spawn_town(td["race"], int(td["nation"]), Vector2i(int(td["x1"]), int(td["y1"])), int(td["population"]), td["name"])
		t.obj_id = int(td["id"])
		t.loyalty = float(td["loyalty"])
		t.target_loyalty = float(td["target_loyalty"])
		t.resistance = _str_keys_to_int(td["resistance"])
		t.target_resistance = _str_keys_to_int(td["target_resistance"])
		t.quality_of_life = int(td["qol"])
		t.bonus_loyalty = float(td["bonus_loyalty"])
		t.population_growth = float(td["growth"])
		t.tax_penalty = int(td["tax_penalty"])
		t.auto_tax_loyalty = int(td.get("auto_tax", 0))
		t.auto_grant_loyalty = int(td.get("auto_grant", 0))
		t.recruit_penalty = int(td["recruit_penalty"])
		t.grant_penalty = int(td["grant_penalty"])
		t.last_rebel_day = int(td["last_rebel_day"])
		t.wall_level = int(td.get("wall_level", 0))
		t.target_wall_level = int(td.get("target_wall_level", 0))
		t.wall_progress = float(td.get("wall_progress", 0.0))
		t.wall_hp = float(td.get("wall_hp", 0.0))
		by_id[t.obj_id] = t

	# firms
	for fd in d["firms"]:
		var f := g.spawn_firm(fd["code"], int(fd["nation"]), fd["race"], Vector2i(int(fd["x1"]), int(fd["y1"])), not fd["under_construction"], int(fd.get("build_row", 0)))
		if f == null:
			continue
		f.obj_id = int(fd["id"])
		f.progress = float(fd["progress"])
		f.hp = float(fd["hp"])
		f.raw = fd["raw"]
		f.reserve = float(fd["reserve"])
		f.stock = float(fd["stock"])
		f.raw_stock = float(fd["raw_stock"])
		f.goods = fd["goods"]
		f.market_sales = float(fd["market_sales"])
		f.research_tech = fd["research_tech"]
		f.research_points = float(fd["research_points"])
		f.weapon = fd["weapon"]
		f.weapon_progress = float(fd["weapon_progress"])
		f.weapon_queue = int(fd["weapon_queue"])
		f.heroes = fd["heroes"]
		f.monster_code = fd["monster"]
		f.raid_timer = int(fd["raid_timer"])
		f.max_hp = float(fd.get("max_hp", f.max_hp))
		f.cast_charge = int(fd.get("charge", Defs.MAX_CAST_DELAY))
		f.animals = fd.get("animals", [])
		f.alchemy_mode = str(fd.get("alchemy", ""))
		if f.alchemy_mode != "" and not f.alchemy_mode in SpecialFirms.ALCHEMY_MODES:
			f.alchemy_mode = ""
		f.propagate = int(fd.get("propagate", 1))
		var ra: Array = fd.get("rally", [-1, -1])
		f.rally = Vector2i(int(ra[0]), int(ra[1]))
		f.set_meta("save", fd)
		by_id[f.obj_id] = f

	# units
	for ud in d["units"]:
		var u := g.spawn_unit(ud["sprite"], int(ud["nation"]), Vector2i(roundi(ud["x"]), roundi(ud["y"])), float(ud["combat"]))
		if u == null:
			continue
		u.obj_id = int(ud["id"])
		u.loc = Vector2(float(ud["x"]), float(ud["y"]))
		u.position = Iso.to_screen(u.loc)
		u.rank = int(ud["rank"])
		u.leadership = float(ud["leadership"])
		u.max_hp = float(ud["max_hp"])
		u.hp = float(ud["hp"])
		u.unit_name = ud["name"]
		u.is_hero = ud["hero"]
		u.weapon_version = int(ud.get("ver", u.weapon_version))
		u.life_frames = int(ud["life"])
		u.dir = int(ud["dir"])
		u.set_meta("save", ud)
		by_id[u.obj_id] = u

	# resolve references
	for u in g.units:
		if not u.has_meta("save"):
			continue
		var ud: Dictionary = u.get_meta("save")
		u.remove_meta("save")
		u.is_spy = ud.get("spy", false)
		u.spy_skill = float(ud.get("spy_skill", 0.0))
		var it: Array = ud.get("item", [0, 0])
		u.item_id = int(it[0])
		u.item_para = int(it[1])
		u.spy_action = ud.get("spy_action", "dissent")
		if not u.spy_action in ["idle", "dissent"]:
			u.spy_action = "dissent"
		u.cloak_id = int(ud.get("cloak", 0))
		var camo: Array = ud.get("camo", [0, 0])
		u.camouflage_days = int(camo[0])
		u.camouflage_power = int(camo[1])
		u.sleeper_for = int(ud.get("sleeper", 0))
		u.loyalty = float(ud.get("loyalty", 70.0))
		var sp = by_id.get(int(ud.get("spy_place", 0)))
		if sp is GameObj and ud.get("hidden", false):
			g.spy_enter(u, sp)
		var ch = by_id.get(int(ud.get("caravan_home", 0)))
		if ch is Firm:
			u.caravan_home = ch
		var cd = by_id.get(int(ud.get("caravan_dest", 0)))
		if cd is Firm:
			u.caravan_dest = cd
		u.caravan_leg = int(ud.get("caravan_leg", 0))
		u.cargo = ud.get("cargo", {})
		var hf = by_id.get(int(ud.get("home_firm", 0)))
		if hf is Firm:
			u.home_firm = hf
		var ht = by_id.get(int(ud["home_town"]))
		if ht is Town:
			u.home_town = ht
			ht.defenders.append(u)
	for f in g.firms:
		if not f.has_meta("save"):
			continue
		var fd: Dictionary = f.get_meta("save")
		f.remove_meta("save")
		var ov = by_id.get(int(fd["overseer"]))
		if ov is Unit:
			f.overseer = ov
			_put_inside(ov, f)
		for sid in fd["soldiers"]:
			var su = by_id.get(int(sid))
			if su is Unit:
				f.soldiers.append(su)
				_put_inside(su, f)
		var bu = by_id.get(int(fd["builder"]))
		if bu is Unit:
			f.builder = bu
			_put_inside(bu, f)
		for eid in fd.get("extra", []):
			var eu = by_id.get(int(eid))
			if eu is Unit:
				f.extra_units.append(eu)
				_put_inside(eu, f)
	for td in d.get("treasures", []):
		g.spawn_treasure(int(td[0]), int(td[1]), int(td[2]), Vector2i(int(td[3]), int(td[4])), int(td[5]))
	for k in d.get("taken_sites", {}):
		g.taken_sites[int(k)] = int(d["taken_sites"][k])
	if d.get("goals") is Dictionary:
		g.goals = Goals.from_dict(d["goals"], by_id)
	g.year0 = int(d.get("year0", Game.START_YEAR))
	g.tech_available = d.get("tech_available")
	if d.get("campaign_battle") is Dictionary:
		var camp := Campaign.load_saved()
		if camp:
			g.campaign_battle = CampaignBattle.restore(camp, d["campaign_battle"], g, by_id)
	for n in g.nations:
		var k = by_id.get(int(n.get_meta("king_id", 0)))
		n.king = k if k is Unit else null
		n.remove_meta("king_id")

	Assets.load_rocks()
	for r in d.get("rocks", []):
		g.add_rock(int(r[0]), Vector2i(int(r[1]), int(r[2])))

	# trees after buildings, which clear the ground they stand on
	for c in g._plants.keys():
		g._plants[c].queue_free()
		g.world.set_plant(c, false)
	g._plants.clear()
	for t in d.get("trees", []):
		var c := Vector2i(int(t[0]), int(t[1]))
		if g.world.object_at(c) == null:
			g.place_tree(c, int(t[2]))

	g.weather.from_dict(d.get("weather", {}))
	g.fog = Marshalls.base64_to_raw(d["fog"])
	GameObj._next_id = maxi(GameObj._next_id, int(d["next_id"]))
	g.rng.seed = int(d["rng_seed"])
	g.rng.state = int(d["rng_state"])
	g.update_links()
	g._update_fog()
	g._ground_dirty = true
	return ""


static func _put_inside(u: Unit, f: Firm) -> void:
	u.inside_firm = f
	u.visible = false
	u.stop()
