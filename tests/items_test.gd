extends Node
## Items and scrolls on the map: scenarios place them, a unit stepping on one takes
## it, items change combat, timed and manual items work, a fallen king drops a
## Scroll of Power, and all of it survives a save.
var fails := 0

func _ready() -> void:
	if Assets.load_install() != "":
		get_tree().quit(1); return
	Defs.load_from_assets()
	var paths := {}
	for info in ScenarioFile.list_premade():
		paths[info["path"].get_file().get_basename().to_lower()] = info["path"]

	# a random map has a few ordinary items
	var g := _game({"seed": 5, "size": 100, "race": "NORMAN", "ai_count": 1, "reveal": true})
	_check(g.treasures.size() >= 3 and g.treasures.all(func(t): return t.kind == Treasure.Kind.ITEM), "random map: %d items lying about" % g.treasures.size())
	var p := g.player()
	var u: Unit = g.spawn_unit("NO_INF", p.id, Vector2i(50, 50), 40.0)
	var t := g.spawn_treasure(Treasure.Kind.ITEM, 1, 0, u.cell())      # Berserker Sword
	g.sim_frame()
	for i in 10:
		g.sim_frame()
	_check(u.item_id == 1 and not t in g.treasures, "stepping on it picks up the %s" % Items.item_name(1))
	var att := u.current_attack()
	var base := 0.0
	var with_item := 0.0
	for i in 200:
		with_item += u.roll_damage(att)
	u.item_id = 0
	for i in 200:
		base += u.roll_damage(att)
	_check(with_item / 200.0 > base / 200.0 + 4.0, "the sword adds about 5 damage (%.1f vs %.1f)" % [with_item / 200.0, base / 200.0])
	# Aegis Field takes the blows while its uses last
	u.item_id = 9
	u.item_para = 2
	var hp := u.hp
	u.take_damage(30.0, null)
	u.take_damage(30.0, null)
	_check(u.hp == hp and u.item_id == 0, "the Aegis Field absorbs two hits and is spent")
	u.take_damage(30.0, null)
	_check(u.hp < hp, "then blows land again")
	# a civilian cannot pick items up
	var pc: Unit = g.spawn_unit("NO_CIV", p.id, Vector2i(56, 50), 10.0)
	g.spawn_treasure(Treasure.Kind.ITEM, 3, 0, pc.cell())
	for i in 11:
		g.sim_frame()
	_check(pc.item_id == 0, "peasants leave items where they lie")
	# Judas Ring wins over an enemy soldier nearby
	var enemy: Unit = g.spawn_unit("NO_INF", g.nations[1].id, u.cell() + Vector2i(3, 0), 30.0)
	u.item_id = 25
	u.item_para = 1
	_check(u.use_manual_item(enemy) == "" and enemy.nation_id == p.id and u.item_id == 0, "the Judas Ring converts an enemy soldier")
	# timed: Staff of Invincibility
	u.item_id = 10
	u.item_para = 3
	hp = u.hp
	u.take_damage(20.0, null)
	_check(u.hp < hp, "the staff does nothing until activated")
	_check(u.turn_on_item() and u.item_para < 0, "activating the staff")
	hp = u.hp
	u.take_damage(20.0, null)
	_check(u.hp == hp, "an active staff makes the unit invincible")
	for d in 4:
		g.next_day()
	_check(u.item_id == 0, "the staff runs out after its days")
	# a fallen king drops his Scroll of Power
	var king := p.king
	_check(p.known_gods.has("NORMAN"), "a kingdom knows its own Greater Being")
	var before := g.treasures.size()
	king.take_damage(1e6, null)
	_check(not p.known_gods.has("NORMAN") and g.treasures.size() == before + 1 and g.treasures.back().kind == Treasure.Kind.SCROLL, "the king's death drops the Norman Scroll of Power")
	# and a Norman picking it up gets it back; a Viking cannot
	var scroll: Treasure = g.treasures.back()
	var vik: Unit = g.spawn_unit("VI_INF", p.id, scroll.cell, 30.0)
	for i in 11:
		g.sim_frame()
	_check(scroll in g.treasures, "a Viking cannot take a Norman scroll")
	vik.loc = Vector2(vik.cell() + Vector2i(3, 3))
	var nor: Unit = g.spawn_unit("NO_INF", p.id, scroll.cell, 30.0)
	for i in 11:
		g.sim_frame()
	_check(not scroll in g.treasures and p.known_gods.has("NORMAN"), "a Norman takes it back")
	# save and load keep carried items and treasures
	nor.item_id = 8
	nor.item_para = 0
	_check(SaveGame.save(g, "test_items"), "saved")
	var g2 := Game.new()
	add_child(g2)
	_check(SaveGame.load_into(g2, "test_items") == "", "loaded")
	_check(g2.treasures.size() == g.treasures.size() and g2.units.any(func(x): return x.item_id == 8), "items and treasures survive a save")
	DirAccess.remove_absolute(SaveGame.path_for("test_items"))
	g2.queue_free()
	g.queue_free()

	# scenarios: the Aegis Field goal in Mongolswarm, the scroll goal in MongolStruggle
	for sc in ["mongolswarm", "mongolstruggle"]:
		if not paths.has(sc):
			continue
		g = _game({"scenario": paths[sc]})
		var goal: Array = g.goals.win.filter(func(c): return c["id"] in [Goals.ACQUIRE_ITEM, Goals.GET_SCROLL])
		_check(not goal.is_empty() and goal[0]["supported"], "%s: %s" % [sc, goal[0]["text"] if not goal.is_empty() else "no goal"])
		var want := g.treasures.filter(func(x): return (goal[0]["id"] == Goals.ACQUIRE_ITEM and x.kind == Treasure.Kind.ITEM and x.object_id == goal[0]["p1"]) \
			or (goal[0]["id"] == Goals.GET_SCROLL and x.recno == goal[0]["p1"]))
		_check(want.size() == 1, "%s: the goal's %s lies on the map" % [sc, want[0].title() if want.size() == 1 else "treasure"])
		if want.size() == 1:
			var pl := g.player()
			var taker: Unit = null
			for x in g.units:
				if x.nation_id == pl.id and not x.dead and x.inside_firm == null and x.is_human() and not x.is_civilian() \
						and (want[0].kind != Treasure.Kind.SCROLL or x.race == want[0].race()):
					taker = x
					break
			if taker:
				taker.loc = Vector2(want[0].cell)
				for i in 11:
					g.sim_frame()
				var res := []
				g.game_over.connect(func(v, txt): res.append([v, txt]))
				g.next_day()
				_check(goal[0]["met"] or (not res.is_empty() and res[0][0]), "%s: taking it meets the goal %s" % [sc, res])
		g.queue_free()
	print("RESULT: ", "PASS" if fails == 0 else "FAIL")
	get_tree().quit(0 if fails == 0 else 2)


func _game(cfg: Dictionary) -> Game:
	var g := Game.new()
	add_child(g)
	g.start(cfg)
	return g


func _check(c: bool, what: String) -> void:
	print(("  ok   " if c else "  FAIL ") + what)
	if not c:
		fails += 1
