extends Node
## Every report page renders, money is booked by kind, and the Hall of Fame keeps scores.
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
	g.start({"seed": 5, "size": 100, "race": "NORMAN", "ai_count": 2, "cash": 3000})
	for d in 400:
		for f in Defs.FRAMES_PER_DAY:
			g.sim_frame()
	var r := ReportsWindow.new()
	r.game = g
	add_child(r)
	r.add_news(g.date_string(), "Something happened.")
	for i in ReportsWindow.TABS.size():
		r.tabs.current_tab = i
		r.refresh()
		var txt: String = r.pages[ReportsWindow.TABS[i]].text
		check(txt.length() > 10, "%s page: %s" % [ReportsWindow.TABS[i], txt.substr(0, 60).replace("\n", " ")])
	var p := g.player()
	check(p.last_expense_by.has("Buildings") or p.expense_by.has("Buildings"), "building upkeep is booked as Buildings: %s" % [p.last_expense_by])
	var kinds := {}
	for n in g.nations:
		for k in n.last_income_by.keys() + n.income_by.keys():
			kinds[k] = true
	print("income kinds seen: ", kinds.keys())
	check(not kinds.is_empty(), "income is booked by kind")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(HallOfFame.PATH))
	var place := HallOfFame.add(g, 500, 100)
	var place2 := HallOfFame.add(g, 900, 120)
	var place3 := HallOfFame.add(g, 100, 80)
	check(place == 1 and place2 == 1 and place3 == 3, "Hall of Fame orders scores (%d, %d, %d)" % [place, place2, place3])
	check(HallOfFame.describe().contains("900"), "Hall of Fame lists the best game")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(HallOfFame.PATH))
	print("RESULT: ", "PASS" if ok else "FAIL")
	get_tree().quit()
