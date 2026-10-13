extends Node
## The scenario editor: place towns, buildings, units, deposits and treasure,
## set kingdoms, relations and goals, save, and play the saved scenario.
var ok := true
func check(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	ok = ok and c
func _ready() -> void:
	if Assets.load_install() != "":
		get_tree().quit(1); return
	Defs.load_from_assets()
	var g := Game.new()
	add_child(g)
	g.start({"editor": true, "seed": 3, "size": 90, "race": "NORMAN", "ai_count": 1, "fryhtan_count": 0, "indep_towns": 0, "lairs": 0, "reveal": true})
	var ed := ScenarioEditorWindow.new()
	ed.game = g
	add_child(ed)
	var frame0 := g.frame
	for i in 30:
		g._process(0.1)
	check(g.frame == frame0, "time stands still in the editor")
	var spot := Vector2i(-1, -1)
	for k in 2000:
		var c := Vector2i(g.rng.randi_range(2, g.world.w - 18), g.rng.randi_range(2, g.world.h - 18))
		if g.world.can_place(c.x, c.y, 16, 16) and not g._overlaps_site(Rect2i(c, Vector2i(16, 16))):
			spot = c
			break
	check(spot.x >= 0, "found flat open ground")
	var towns0 := g.towns.size()
	check(ed.place({"kind": "town", "race": "VIKING", "nation": 1}, spot + Vector2i(3, 3)), "place a Viking town for you")
	check(g.towns.size() == towns0 + 1 and g.towns[-1].race == "VIKING", "the town is there")
	check(ed.place({"kind": "firm", "code": "FORT", "race": "NORMAN", "nation": 1}, spot + Vector2i(11, 3)), "place a fort")
	check(ed.place({"kind": "unit", "sprite": "NO_INF", "nation": 1, "rank": Defs.Rank.GENERAL}, spot + Vector2i(3, 10)), "place a general")
	check(ed.place({"kind": "firm", "code": "LAIR", "race": "GITH", "nation": GameObj.MONSTER_NATION}, spot + Vector2i(11, 11)), "place a wild Grokken lair")
	var row: Dictionary = Assets.table("RAW")[0]
	var sites0 := g.sites.size()
	var sat := spot + Vector2i(1, 7)
	ed.place({"kind": "site", "row": row, "nation": -1}, sat)
	check(g.sites.size() == sites0 + 1, "place a deposit")
	ed.place({"kind": "item", "id": 4, "nation": -1}, spot + Vector2i(6, 12))
	check(g.treasures.any(func(t): return t.object_id == 4), "place Excalibur")
	# a kingdom, a relation and goals
	ed._fill_kingdoms()
	var n2 := g.nation(2)
	n2.relations[1] = Defs.Relation.ALLIANCE
	g.nation(1).relations[2] = Defs.Relation.ALLIANCE
	g.goals = Goals.new()
	ed._add_goal(g.goals.win, ed.GOAL_KINDS[5], 1, 250, 10)
	g.selected = [g.towns[-1]]
	ed._add_goal(g.goals.lose, ed.GOAL_KINDS[13], 1, 0, 0)
	check(g.goals.win.size() == 1 and g.goals.lose.size() == 1 and g.goals.lose[0]["target"] is Town, "goals: population 250 within 10 years; losing the Viking town loses")
	ed.name_edit.text = "Editor Test"
	ed.text_edit.text = "A test briefing."
	var path := ed._save()
	check(path != "", "saved to " + path)
	var listed := SaveGame.list_scenarios().filter(func(s): return s["name"] == "Editor Test")
	check(not listed.is_empty() and listed[0]["text"] == "A test briefing.", "listed with its briefing")
	# play it
	var g2 := Game.new()
	add_child(g2)
	g2.start({"scenario": ProjectSettings.globalize_path(path), "seed": 9})
	check(g2.day == 0 and g2.towns.any(func(t): return t.race == "VIKING" and t.nation_id == 1), "the scenario starts on day 0 with the Viking town")
	check(g2.firms.any(func(f): return f.code == "LAIR" and f.monster_code == "GITH"), "the wild lair is there")
	check(g2.nation(1).relation(2) == Defs.Relation.ALLIANCE, "the alliance holds")
	check(g2.goals != null and g2.goals.win.size() == 1 and g2.goals.win[0]["p2"] == 250 and g2.goals.lose[0]["target"] is Town, "the goals hold, with their target")
	for i in 50:
		g2.sim_frame()
	check(g2.frame == 50, "and time runs")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("RESULT: ", "PASS" if ok else "FAIL")
	get_tree().quit()
