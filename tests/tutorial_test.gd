extends Node
## The learning campaigns: every lesson's map and texts load, and the first
## lesson moves on objective by objective as the player does what it asks.
var ok := true
func check(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	ok = ok and c
func _ready() -> void:
	if Assets.load_install() != "":
		get_tree().quit(1); return
	Defs.load_from_assets()
	for l in Tutorial.LESSONS:
		var path := Tutorial.map_path(l)
		var g := Game.new()
		add_child(g)
		g.start({"scenario": path, "seed": 1, "tutorial": l["id"]})
		var t := Tutorial.new()
		t.setup(g, l["id"])
		check(path != "" and g.player() != null and not t.blocks.is_empty(), "%s: map (%s) and %d text blocks, %d objectives, first: %s" % [l["name"], g.player().name if g.player() else "?", t.blocks.size(), t.last_objective(), t.pages()[0]["text"].substr(0, 50).replace("\n", " ") if not t.pages().is_empty() else "-"])
		if l["id"] == 1:
			_lesson1(g, t)
		g.queue_free()
		await get_tree().process_frame
	print("RESULT: ", "PASS" if ok else "FAIL")
	get_tree().quit()

func _sel(g: Game, o) -> void:
	g.selected = [o] if o else []

func _lesson1(g: Game, t: Tutorial) -> void:
	var p := g.player()
	var fort: Firm = g.goals.win[2]["target"]
	check(fort is Firm and fort.nation_id == p.id, "lesson 1 knows its fort (goal 2): %s" % fort)
	check(not t.check(), "step 1 waits")
	_sel(g, fort)
	t.continue_pressed = true
	check(t.check() and t.current == 2, "selecting the fort and Continue: step 2")
	t.press("Fill from towns")
	check(t.check() and t.current == 3, "Fill from towns: step 3")
	t.continue_pressed = true
	t.check()
	t.continue_pressed = true
	check(t.check() and t.current == 5, "two Continues: step 5")
	_sel(g, fort)
	t.continue_pressed = true
	var had := fort.soldiers.size() > 0
	check(t.check() == had, "step 5 needs soldiers in the fort (%d)" % fort.soldiers.size())
	if had:
		t.press("Send out soldiers")
		check(t.check() and t.current == 7, "Send out soldiers: step 7")
