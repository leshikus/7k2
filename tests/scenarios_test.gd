extends Node
## The scenarios shipped in res://scenario/*.json (made by tools/make_scenarios):
## each loads with its kingdoms and goals, is listed on the start screen, and
## plays two months without error or an early end.
var fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


func _ready() -> void:
	Assets.load_install()
	Defs.load_from_assets()
	var listed := ScenarioFile.list_premade().filter(func(s): return s["source"] == "new")
	_check(listed.size() >= 6, "the new scenarios are listed (%d)" % listed.size())
	for info in listed:
		var g := Game.new()
		add_child(g)
		g.start({"scenario": info["path"], "seed": 1})
		var p := g.player()
		var name: String = info["name"]
		_check(p != null and g.goals != null and not g.goals.win.is_empty(), "%s: loads with the player's kingdom and goals" % name)
		_check(info["text"] != "", "%s: has a briefing" % name)
		match info["path"].get_file():
			"SiegeOfCarthage.json":
				var ct = g.towns.filter(func(t): return t.town_name == "Carthago")
				_check(ct.size() == 1 and ct[0].wall_level == 2 and g.goals.win[0]["target"] == ct[0], "%s: Carthago stands walled, the goal names it" % name)
			"TheRelic.json":
				var h = g.units.filter(func(u): return u.unit_name == "Theron the Keeper")
				_check(h.size() == 1 and g.goals.lose.any(func(c): return c["target"] == h[0]), "%s: losing Theron loses the game" % name)
			"ShadowWar.json":
				var col = g.firms.filter(func(f): return f.code == "SPY" and f.nation_id == p.id)
				_check(col.size() == 1 and col[0].trainees.size() == 3, "%s: three agents wait at the college" % name)
			"LordOfTheLair.json":
				_check(p.is_fryhtan, "%s: the player leads Fryhtans" % name)
		for d in 60:
			for f in Defs.FRAMES_PER_DAY:
				g.sim_frame()
		_check(not g.over, "%s: two months played, the game goes on" % name)
		g.queue_free()
		await get_tree().process_frame
	print("RESULT: ", "PASS" if fails == 0 else "FAIL")
	get_tree().quit(0 if fails == 0 else 2)
