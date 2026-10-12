extends Node
## The player leads a Fryhtan kingdom: lair start, breeding, a new lair, survival.
func _ready() -> void:
	if Assets.load_install() != "":
		get_tree().quit(1); return
	Defs.load_from_assets()
	var species: Dictionary = Defs.monsters[0]
	var g := Game.new()
	add_child(g)
	g.start({"seed": 9, "size": 100, "race": species["unit"], "ai_count": 2, "fryhtan_count": 1, "reveal": true})
	var p := g.player()
	var ok := true
	print("player ", p.name, " fryhtan=", p.is_fryhtan, " monster=", p.monster_code, " life=", p.live_points, " cash=", p.cash)
	var lairs: Array = g.firms.filter(func(f): return f.nation_id == p.id and f.code == "LAIR")
	print("lairs ", lairs.size(), " brood inside ", lairs[0].soldiers.size() if lairs else -1, " king ", p.king != null)
	if not p.is_fryhtan or lairs.is_empty() or p.king == null:
		print("FAIL: no Fryhtan start"); ok = false
	for n in g.nations:
		if n != p:
			print("  ", n.name, " fryhtan=", n.is_fryhtan, " relation=", p.relation(n.id))
	var lair: Firm = lairs[0]
	var before := lair.soldiers.size()
	var bred := lair.breed()
	print("bred ", bred != null, " brood ", before, "->", lair.soldiers.size(), " life ", p.live_points)
	if bred == null: print("FAIL: breed"); ok = false
	# build a second lair with an outside Fryhtan, as the UI does
	var builder: Unit = g.units.filter(func(u): return u.nation_id == p.id and u.inside_firm == null and not u.dead)[0]
	var b := Assets.firm_build("LAIR", p.race)
	var pos := g._place_near(lair.footprint(), b.get("loc_w", 6), b.get("loc_h", 6), 8)
	var nl := g.spawn_firm("LAIR", p.id, p.race, pos, false)
	nl.monster_code = p.monster_code
	builder.order_build(nl)
	for d in 150:
		for f in 30: g.sim_frame()
	print("day 150: new lair built=", not nl.under_construction, " alive=", p.alive, " lairs=", g.firms.filter(func(f): return f.nation_id == p.id).size(), " units=", g.units.filter(func(u): return u.nation_id == p.id and not u.dead).size(), " life=", int(p.live_points))
	if nl.under_construction: print("FAIL: lair not built"); ok = false
	if not p.alive: print("FAIL: player Fryhtans died"); ok = false
	print("RESULT: ", "PASS" if ok else "FAIL")
	get_tree().quit()
