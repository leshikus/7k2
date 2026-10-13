extends Node
## The Seat of Power's Special Blessing: every wish of the original's table,
## the prayer points it uses, and the button only with full points.

var ok := true


func check(cond: bool, what: String) -> void:
	print(("ok   " if cond else "FAIL ") + what)
	if not cond:
		ok = false


func open_spot(g: Game, near: Vector2i, w: int, h: int) -> Vector2i:
	for r in range(4, 40):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var at := near + Vector2i(dx, dy)
				if g.world.can_place(at.x - 1, at.y - 1, w + 2, h + 2) and not g._overlaps_site(Rect2i(at, Vector2i(w, h))):
					return at
	return Vector2i(-1, -1)


func _ready() -> void:
	if Assets.load_install() != "":
		get_tree().quit(1); return
	Defs.load_from_assets()
	var g := Game.new()
	add_child(g)
	g.start({"seed": 5, "size": 120, "race": "NORMAN", "ai_count": 2, "reveal": true})
	var p := g.player()
	var town: Town = g.towns.filter(func(t): return t.nation_id == p.id)[0]
	var base := g.spawn_firm("BASE", p.id, "NORMAN", open_spot(g, Vector2i(town.center_loc()), 4, 4), true)
	check(base != null, "a Seat of Power")
	check(not Wishes.can_wish(base), "no blessing without full prayer points")
	p.prayer_points = Wishes.FULL - 1
	check(not Wishes.can_wish(base), "nor one point short")

	# an enemy spy in our town and a wounded garrison, so those wishes have work
	var enemy: Nation = g.nations.filter(func(n): return n.id != p.id)[0]
	g.declare_war(p.id, enemy.id)
	var camp: Firm = g.firms.filter(func(f): return f.nation_id == p.id and Espionage.is_camp(f))[0]
	for s in Espionage.occupants(camp):
		s.hp = s.max_hp * 0.3
	var counts := {}
	for w in Wishes.TABLE:
		var id: String = w[0]
		if id.contains("SPY_"):
			var spy := g.spawn_unit(Defs.unit_sprite(enemy.race, "INF"), enemy.id, Vector2i(town.center_loc()) + Vector2i(3, 3), 20.0)
			spy.is_spy = true
			spy.spy_skill = 10.0
			g.spy_enter(spy, town)
		var spies_before := g.spies.size()
		var units_before := g.units.size()
		var cash_before := p.cash
		p.prayer_points = Wishes.FULL
		check(Wishes.can_wish(base), "%s: blessing available with full points" % id)
		var txt := Wishes.invoke(base, id)
		print("     ", txt)
		check(txt != "", "%s: reports its result" % id)
		check(p.prayer_points == (0.0 if txt != "No effect!" else Wishes.FULL / 2.0), "%s: prayer points used" % id)
		match id:
			"NEW_HUMAN", "NEW_SPY", "NEW_MONSTER", "NEW_HERO":
				check(g.units.size() == units_before + 1, "%s: a unit joins" % id)
			"CASH":
				check(p.cash >= cash_before + 2000.0, "CASH: 2000-7000 gold")
			"CLEAR_SPY_NATION", "KILL_SPY_NATION", "KILL_SPY_BUILDING":
				check(g.spies.size() <= spies_before, "%s: spies caught" % id)
			"HEAL_BUILDING":
				check(Espionage.occupants(camp).all(func(s): return s.hp >= s.max_hp - 0.01), "HEAL_BUILDING: the wounded camp is healed")
			"RAW":
				check(g.firms.any(func(f): return f.code == "MINE" and f.nation_id == p.id and not f.under_construction), "RAW: a finished mine")
	# random draws: through the network command, every kind seen in time
	for i in 300:
		p.prayer_points = Wishes.FULL
		Net.cmd(base, "bless", [])
		var t: String = base.get_meta("wish_text", "")
		counts[t.left(30)] = true
	check(counts.size() > 8, "random blessings vary (%d kinds)" % counts.size())
	print("RESULT: ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
