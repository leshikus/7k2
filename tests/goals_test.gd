extends Node
## Scenario goals: every scenario's goals are read and their targets found, a goal
## met wins, a lose condition loses, the deadline ends the game, and goals survive
## a save and load.
var fails := 0

func _ready() -> void:
	if Assets.load_install() != "":
		get_tree().quit(1); return
	Defs.load_from_assets()
	var paths := {}
	var with_goals := 0
	for info in ScenarioFile.list_premade():
		paths[info["path"].get_file().get_basename().to_lower()] = info["path"]
		var sf := ScenarioFile.new()
		if not sf.load_file(info["path"]):
			continue
		if sf.goals.is_empty():
			_check(false, "%s: goals read" % info["path"].get_file())
			continue
		var extra: Array = sf.goals["win"].filter(func(c): return c["id"] != Goals.DEFEAT_ALL_OTHER_KINGDOMS) \
			+ sf.goals["lose"].filter(func(c): return c["id"] != Goals.DEFEAT_OWN_KINGDOM)
		if not extra.is_empty():
			with_goals += 1
	_check(with_goals >= 20, "%d scenarios have goals beyond conquest" % with_goals)

	# gallic: kill King Vercingetorix
	var g := _start(paths["gallic"])
	var kill: Array = g.goals.win.filter(func(c): return c["id"] == Goals.KILL_UNIT)
	_check(kill.size() == 1 and kill[0]["supported"] and kill[0]["target"] is Unit, "gallic: the king to kill is found (%s)" % (kill[0]["target"].unit_name if kill.size() == 1 and kill[0]["target"] else "none"))
	var result := []
	g.game_over.connect(func(v, t): result.append([v, t]))
	g.next_day()
	_check(result.is_empty(), "gallic: no result while he lives")
	(kill[0]["target"] as Unit).take_damage(1e6, null)
	g.next_day()
	_check(result.size() == 1 and result[0][0] == true, "gallic: killing him wins (%s)" % [result])
	g.queue_free()

	# Rome: population of 1,000 in 10 years; save and load keep the goals
	g = _start(paths["rome"])
	var pop: Array = g.goals.win.filter(func(c): return c["id"] == Goals.REACH_POPULATION)
	_check(pop.size() == 1 and pop[0]["p2"] == 1000, "Rome: population goal read")
	print("  Rome population score now ", Goals.progress(g, g.player(), pop[0]))
	_check(SaveGame.save(g, "test_goals"), "Rome: saved")
	var g2 := Game.new()
	add_child(g2)
	_check(SaveGame.load_into(g2, "test_goals") == "" and g2.goals != null and g2.goals.win.size() == g.goals.win.size(), "Rome: goals survive save and load")
	DirAccess.remove_absolute(SaveGame.path_for("test_goals"))
	g2.queue_free()
	# the deadline: ten years on, the game is lost
	result = []
	g.game_over.connect(func(v, t): result.append([v, t]))
	g.day = 10 * 365 - 1
	g.next_day()
	_check(result.size() == 1 and result[0][0] == false, "Rome: the deadline loses (%s)" % [result])
	g.queue_free()

	# HeIsMyHero: Soghul must not die
	if paths.has("heismyhero"):
		g = _start(paths["heismyhero"])
		var keep: Array = g.goals.lose.filter(func(c): return c["id"] == Goals.KILL_UNIT)
		_check(keep.size() == 1 and keep[0]["target"] is Unit, "HeIsMyHero: Soghul found")
		result = []
		g.game_over.connect(func(v, t): result.append([v, t]))
		(keep[0]["target"] as Unit).take_damage(1e6, null)
		g.next_day()
		_check(result.size() == 1 and result[0][0] == false, "HeIsMyHero: losing Soghul loses (%s)" % [result])
		g.queue_free()

	print("RESULT: ", "PASS" if fails == 0 else "FAIL")
	get_tree().quit(0 if fails == 0 else 2)


func _start(path: String) -> Game:
	var g := Game.new()
	add_child(g)
	g.start({"scenario": path})
	return g


func _check(c: bool, what: String) -> void:
	print(("  ok   " if c else "  FAIL ") + what)
	if not c:
		fails += 1
