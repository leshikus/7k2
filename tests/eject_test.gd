extends Node
## Eject the king from his fort, walk him away and check he faces where he goes.
func _ready() -> void:
	if Assets.load_install() != "":
		get_tree().quit(1); return
	var g := Game.new()
	add_child(g)
	g.start({"seed": 11, "size": 100, "race": "NORMAN", "ai_count": 1, "reveal": true, "lairs": 0})
	var p := g.player()
	var king: Unit = g.units.filter(func(u): return u.nation_id == p.id and u.rank == Defs.Rank.KING)[0]
	print("king inside=", king.inside_firm, " loc=", king.loc)
	var f: Firm = king.inside_firm
	if f == null:
		f = g.firms.filter(func(x): return x.nation_id == p.id and x.code == "FORT")[0] if g.firms.any(func(x): return x.nation_id == p.id and x.code == "FORT") else null
	if f and king.inside_firm == null:
		f.accept_unit(king)
	print("firm ", f.code if f else "none")
	f.release_unit(king)
	print("after release loc=", king.loc, " dir=", king.dir)
	var bad := 0
	var dests := [king.cell() + Vector2i(8, 0), king.cell() + Vector2i(0, 8), king.cell() + Vector2i(-6, -6), king.cell() + Vector2i(6, 6)]
	for dest in dests:
		king.order_move(dest)
		for i in 400:
			var before := king.loc
			g.sim_frame()
			var dl := king.loc - before
			if dl.length() > 0.001:
				var want := Iso.dir_of(dl)
				if want != king.dir:
					bad += 1
					if bad < 10: print("frame ", i, " moving ", dl, " want dir ", want, " has ", king.dir, " action ", king.action)
			if king.order == Unit.Order.IDLE: break
		print("dest ", dest, " reached ", king.cell(), " dir ", king.dir)
	print("mismatches ", bad)
	# every unit of a busy computer-only game, ejections and sallies included
	g.config["autoplay"] = true
	var prev := {}
	var wrong := 0
	var moves := 0
	for fr in 6000:
		for u in g.units:
			if prev.has(u) and not u.dead and u.inside_firm == null and not u.attacking:
				var dl: Vector2 = u.loc - prev[u]
				if dl.length() > 0.001 and dl.length() < 1.5:
					moves += 1
					if Iso.dir_of(dl) != u.dir:
						wrong += 1
						if wrong < 8: print("unit ", u.display_name(), " order ", u.order, " moving ", dl, " faces ", u.dir, " want ", Iso.dir_of(dl))
		prev.clear()
		for u in g.units:
			prev[u] = u.loc
		g.sim_frame()
	print("all units: moves ", moves, " facing wrong ", wrong)
	var ok := true
	# units leave by the door side (right-down face, x = x1 + w)
	var fort: Firm = g.firms.filter(func(x): return x.nation_id == p.id and x.code == "FORT")[0]
	var u2: Unit = g.units.filter(func(u): return u.nation_id == p.id and u.inside_firm == fort)[0]
	fort.release_unit(u2)
	print("exit cell ", u2.cell(), " fort x ", fort.x1, "..", fort.x1 + fort.w - 1, " y ", fort.y1, "..", fort.y1 + fort.h - 1)
	if u2.cell().x != fort.x1 + fort.w:
		print("FAIL: did not leave by the door side"); ok = false
	# fill from towns: instant, no loyalty loss
	var town: Town = fort.linked_towns.filter(func(t): return t.nation_id == p.id)[0]
	town.loyalty = 80.0
	var loy := town.loyalty
	var pop := town.population
	var n0 := fort.soldiers.size()
	var d := town.draft_into(fort)
	print("drafted ", d != null, " soldiers ", n0, "->", fort.soldiers.size(), " pop ", pop, "->", town.population, " loyalty ", loy, "->", town.loyalty)
	if d == null or fort.soldiers.size() != n0 + 1 or town.loyalty != loy or d.inside_firm != fort:
		print("FAIL: draft"); ok = false
	# commander swap
	var gen := g.spawn_unit(Defs.unit_sprite(p.race, "INF"), p.id, Vector2i(fort.x1 + fort.w, fort.y1), 50.0)
	gen.rank = Defs.Rank.GENERAL
	if fort.soldiers.size() >= fort.capacity(): fort.release_unit(fort.soldiers[0])
	fort.soldiers.append(gen); fort._hide_unit(gen)
	var old := fort.overseer
	fort.make_overseer(gen)
	print("commander swapped ", fort.overseer == gen, " old in soldiers ", old == null or old in fort.soldiers)
	if fort.overseer != gen: ok = false
	# auto tax
	town.auto_tax_loyalty = 60
	town.loyalty = 90.0
	var cash := p.cash
	town.next_day(g.day + 1)
	print("auto tax: cash ", int(cash), "->", int(p.cash), " loyalty ", town.loyalty)
	if p.cash <= cash and town.has_linked_camp(p.id): print("FAIL: auto tax"); ok = false
	print("RESULT: ", "PASS" if ok else "FAIL")
	get_tree().quit()
