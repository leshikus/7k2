extends Node
## Waypoints, rally points and the tips from the install.
var ok := true
func check(c: bool, what: String) -> void:
	print(("ok   " if c else "FAIL ") + what)
	ok = ok and c
func _ready() -> void:
	if Assets.load_install() != "":
		get_tree().quit(1); return
	Defs.load_from_assets()
	var tips := TipsBox.load_tips("HUMAN")
	check(tips.size() > 10 and TipsBox.load_tips("FRYHTAN").size() > 3, "tips: %d for humans, first: %s" % [tips.size(), tips[0].substr(0, 50) if tips.size() > 0 else ""])
	var g := Game.new()
	add_child(g)
	g.start({"seed": 5, "size": 100, "race": "NORMAN", "ai_count": 1, "cash": 20000})
	var p := g.player()
	var u: Unit = g.units.filter(func(x): return x.nation_id == p.id and x.inside_firm == null)[0]
	var a := g.world.nearest_walkable(u.cell() + Vector2i(6, 0))
	var b := g.world.nearest_walkable(u.cell() + Vector2i(6, 6))
	u.add_waypoint(a)
	u.add_waypoint(b)
	check(u.order == Unit.Order.MOVE and u.waypoints.size() == 1, "a move and a waypoint queued")
	for i in 600:
		g.sim_frame()
	check(u.cell().distance_to(b) < 2.0 and u.waypoints.is_empty(), "the unit went on to the waypoint (%s, wanted %s)" % [u.cell(), b])
	# rally point at a war factory
	p.tech["CATAPULT"] = 1
	var t: Town = g.towns.filter(func(x): return x.nation_id == p.id)[0]
	var pos := g._place_near(t.footprint(), 4, 4, 8, [t.center_loc()])
	var wf := g.spawn_firm("WAR", p.id, p.race, pos, true)
	g.update_links()
	var rp := g.world.nearest_walkable(wf.door() + Vector2i(8, 2))
	wf.set_rally(rp)
	wf.queue_weapon("CATAPULT")
	g.fast_build = true
	# 60 days of a full factory; fewer workers take longer
	for i in Defs.FRAMES_PER_DAY * 90:
		g.sim_frame()
		if g.units.any(func(x): return x.sprite_code == "CATAPULT" and x.nation_id == p.id) and i % Defs.FRAMES_PER_DAY == 0:
			for k in Defs.FRAMES_PER_DAY * 5:      # a few days to reach the rally point
				g.sim_frame()
			break
	var cats := g.units.filter(func(x): return x.sprite_code == "CATAPULT" and x.nation_id == p.id)
	check(not cats.is_empty(), "a catapult was built")
	if not cats.is_empty():
		check(cats[0].cell().distance_to(rp) < 3.0 or cats[0].order == Unit.Order.MOVE, "it went to the rally point (%s, rally %s)" % [cats[0].cell(), rp])
	print("RESULT: ", "PASS" if ok else "FAIL")
	get_tree().quit()
