extends Node
## The Options menu (ooptmenu.cpp) and the map (oworld_m.cpp): unit paths on the
## main view and the world map, attackers' paths under the Japanese Greater
## Being, map modes, filters and zones of power, Hide Buildings, major news,
## and the help file's screen-area texts.

var ok := true


func check(cond: bool, what: String) -> void:
	print(("ok   " if cond else "FAIL ") + what)
	if not cond:
		ok = false


func _ready() -> void:
	if Assets.load_install() != "":
		get_tree().quit(1); return
	Defs.load_from_assets()
	GameOptions.reset()
	var g := Game.new()
	add_child(g)
	g.start({"seed": 8, "size": 100, "race": "NORMAN", "ai_count": 1, "fryhtan_count": 0, "reveal": true})
	for i in 5:
		g.sim_frame()
	var p := g.player()

	# ---- unit paths
	var u := g.spawn_unit(Defs.unit_sprite("NORMAN", "INF"), p.id, g.world.nearest_walkable(Vector2i(20, 20)), 30.0)
	g.sim_frame()
	u.order_move_free(g.world.nearest_walkable(Vector2i(40, 30)))
	g.selected = [u]
	g.sim_frame()
	check(g.unit_paths(1).is_empty() and g.unit_paths(2).is_empty(), "no paths shown by default (Show Unit Paths: No)")
	GameOptions.set_opt("show_unit_path", 1)
	var paths := g.unit_paths(1)
	check(paths.size() == 1 and paths[0][0].size() >= 2 and not paths[0][1], "Main map: the selected unit's path (%d points)" % (paths[0][0].size() if paths.size() > 0 else 0))
	check(g.unit_paths(2).is_empty(), "but not on the world map")
	GameOptions.set_opt("show_unit_path", 3)
	check(g.unit_paths(2).size() == 1, "Both: on the world map too")
	g.selected = []
	check(g.unit_paths(1).is_empty(), "only selected units")
	GameOptions.set_opt("show_unit_path", 0)

	# attackers marching on us are shown when our Japanese Greater Being has worshippers
	var foe: Nation = g.nations.filter(func(n): return n.id != p.id)[0]
	g.declare_war(p.id, foe.id)
	var home: Town = g.towns.filter(func(t): return t.nation_id == p.id)[0]
	var raider := g.spawn_unit(Defs.unit_sprite(foe.race, "INF"), foe.id, g.world.nearest_walkable(Vector2i(home.center_loc()) + Vector2i(25, 25)), 30.0)
	g.sim_frame()
	raider.order_attack(home)
	g.sim_frame()
	check(g.unit_paths(1).is_empty(), "attackers' paths are hidden without the Japanese blessing")
	var base := g.spawn_firm("BASE", p.id, "JAPANESE", g._place_near(home.footprint(), 4, 4, 12), true)
	base.worker_from[home] = 5            # worshippers
	var red := g.unit_paths(1).filter(func(x): return x[1])
	check(red.size() == 1 and red[0][0].size() >= 2, "with worshippers at a Japanese Seat of Power, an attacker's path shows in red")
	check(g.unit_paths(2).any(func(x): return x[1]), "on the world map too")

	# ---- map modes and filters
	var mm := Minimap.new()
	add_child(mm)
	mm.size = Vector2(200, 100)
	var cam := CameraRig.new()
	add_child(cam)
	mm.setup(g, cam)
	check(mm.mode == Minimap.Mode.POWER and not mm.power_mode, "the map starts as the political map without zones")
	mm.set_mode(Minimap.Mode.POWER)
	check(mm.power_mode, "pressing it again shows the kingdoms' zones")
	var pm := g.power_map()
	var hc := Vector2i(home.center_loc())
	check(pm[hc.y * g.world.w + hc.x] == p.id, "a town's land belongs to its kingdom")
	mm.set_mode(Minimap.Mode.TRADE)
	var market := g.spawn_firm("MARKET", p.id, "NORMAN", g._place_near(home.footprint(), 5, 5, 14), true)
	var fort: Firm = g.firms.filter(func(f): return f.code == "FORT" and f.nation_id == p.id)[0]
	g.selected = []
	check(mm._shown(market) and not mm._shown(fort) and mm._shown(home), "the trade map shows markets and towns, not forts")
	mm.set_mode(Minimap.Mode.TERRAIN)
	check(mm._shown(fort), "the terrain map shows everything")
	g.selected = [fort]
	mm.toggle_filter_kind()
	g.selected = []
	check(mm.filter_kind == "FORT" and not mm._shown(market) and mm._shown(fort), "the object filter keeps the selected kind")
	mm.toggle_filter_kind()
	g.selected = [raider]
	mm.toggle_filter_nation()
	g.selected = []
	check(not mm._shown(fort) and mm._shown(raider), "the nation filter keeps the selected kingdom")
	mm.toggle_filter_nation()
	check(mm.filter_nation == -1 and mm._shown(fort), "and lets go again")

	# ---- Hide Buildings draws squares with names
	var rec := DrawRecorder.new()
	fort.render(rec)
	var with_tex := rec.textures.size()
	g.hide_buildings = true
	rec.clear()
	fort.render(rec)
	check(rec.textures.is_empty() and with_tex > 0 and rec.vectors.any(func(v): return v[0] == "draw_string"), "Hide Buildings: a square and a name instead of the picture")
	g.hide_buildings = false

	# ---- news and help
	var shown_msgs: Array = []
	g.message.connect(func(t, _l): if not g.last_message_minor: shown_msgs.append(t))
	g.notify("A building was lost.", Vector2(-1, -1), true)
	g.notify("The king has died.", Vector2(-1, -1))
	check(shown_msgs == ["The king has died."], "major news are told apart from minor ones")
	check(HelpText.area_text("Food") != "" and HelpText.area_text("Kingdoms Report").contains("F1"), "the help file's screen-area texts are read")
	check(HelpText.for_label("Build a town").begins_with("Build a Town"), "Build a town has the original help")
	# ---- formations: a general's troop forms up and keeps its shape on the march
	var at := g.world.nearest_walkable(Vector2i(60, 70))
	var gen := g.spawn_unit(Defs.unit_sprite("NORMAN", "INF"), p.id, at, 50.0)
	gen.rank = Defs.Rank.GENERAL
	var troop: Array = [gen]
	for i in 8:
		troop.append(g.spawn_unit(Defs.unit_sprite("NORMAN", "INF"), p.id, g.free_unit_cell(at + Vector2i(i % 3, 2 + i / 3)), 30.0))
	g.sim_frame()
	g.form_troop(troop, 2, Vector2(0, 1))
	var goals: Array = troop.map(func(u): return u.path[-1] if not u.path.is_empty() else u.cell())
	var distinct := {}
	for c in goals:
		distinct[c] = true
	check(gen.formation == 2 and distinct.size() == troop.size(), "Line: every man gets his own place")
	var front := troop.slice(1).filter(func(u): return (u.path[-1] if not u.path.is_empty() else u.cell()).y > gen.cell().y)
	check(front.size() >= 6, "in a rank in front of the general (%d of 8)" % front.size())
	for i in 300:
		g.sim_frame()
	var dest := g.world.nearest_walkable(at + Vector2i(-25, -5))
	check(g.move_troop(troop, dest), "a move keeps the formation")
	var spread := {}
	for m in troop:
		spread[m.path[-1] if not m.path.is_empty() else m.cell()] = true
	check(spread.size() == troop.size(), "the men take their places at the destination")
	gen.formation = 0
	check(not g.move_troop(troop, dest), "without a formation the group moves as before")
	check(Formations.slots(6, 12).size() == 12 and Formations.slots(3, 5).size() == 5, "every formation has a place for each man")

	# ---- player profiles: each keeps its own saved games
	var before := Profiles.current()
	check(Profiles.login("Test Player") and Profiles.current() == "Test Player", "a player registers")
	check(SaveGame.dir().contains("profiles/Test Player"), "his games go to his own folder (%s)" % SaveGame.dir())
	check(SaveGame.save(g, "profile_slot") and SaveGame.exists("profile_slot"), "and are saved there")
	check(Campaign.save_file().begins_with(SaveGame.dir()), "with his campaign")
	Profiles.remove("Test Player")
	check(not SaveGame.exists("profile_slot") and not Profiles.list().has("Test Player"), "deleting the player removes his games")
	if before != "":
		Profiles.login(before)
	else:
		Profiles.set_current("")
	check(not Profiles.login(""), "an empty name is refused")
	print("RESULT: ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
