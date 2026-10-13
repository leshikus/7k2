extends Node
## Towns under attack and their walls (otown.cpp, otowndef.cpp, otownwal.cpp,
## otownpop.cpp): defenders, resistance worn down by attacks, people killed,
## surrender, Fryhtan tribute, wall building and repairs, and building repairs.
var fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


func _days(g: Game, n: int) -> void:
	for d in n:
		for f in Defs.FRAMES_PER_DAY:
			g.sim_frame()


func _ready() -> void:
	Assets.load_install()
	var g := Game.new()
	add_child(g)
	g.start({"seed": 31, "size": 100, "race": "NORMAN", "ai_count": 1, "fryhtan_count": 1, "lairs": 0, "reveal": true, "resistance": GameSetup.MODERATE})
	for n in g.nations:
		n.ai = null
	var p := g.player()
	p.cash = 20000.0
	var t: Town = g.towns.filter(func(x): return x.nation_id == 0)[0]
	t.population = 40
	t.set_wall_level(0)
	_check(t.town_combat_level == 30, "a moderate setting gives independent defenders combat 30")
	for n in g.nations:
		t.resistance[n.id] = 70.0
	var att := g.spawn_unit(Defs.unit_sprite(p.race, "INF"), p.id, g.free_unit_cell(Vector2i(t.center_loc()) + Vector2i(4, 0)), 40.0)

	# --- defenders come out while the walls are down, taking resistance with them
	var r0 := t.resistance_to(p.id)
	t.take_damage(10.0, att)
	var out := t.defenders.size()
	_check(out > 0, "villagers come out to defend (%d)" % out)
	_check(t.defenders.all(func(d): return d.combat >= 20.0 and d.combat <= 40.0), "at the town's combat level, give or take 10")
	_check(t.resistance_to(p.id) < r0, "each defender takes resistance with him (%.1f -> %.1f)" % [r0, t.resistance_to(p.id)])
	_check(out <= int(r0 / 5.0) + 1, "no more defenders than resistance allows")
	# one comes home victorious
	var d0: Unit = t.defenders[0]
	var before := t.resistance_to(p.id)
	t.defender_returned(d0)
	_check(t.resistance_to(p.id) > before + 2.0, "a defender coming home gives it back, and 2 more (%.1f -> %.1f)" % [before, t.resistance_to(p.id)])
	for d in t.defenders.duplicate():
		d.die(null)
	t.defenders.clear()

	# --- with no defenders the attack wears resistance down and kills people
	t.resistance[p.id] = 40.0
	var pop0 := t.population
	for i in 60:
		t.take_damage(20.0, att)
		t.defenders.clear()
	_check(t.resistance_to(p.id) < 40.0, "blows wear the resistance down (%.1f)" % t.resistance_to(p.id))
	_check(t.population < pop0, "every 200 points of blows kill a villager (%d -> %d)" % [pop0, t.population])

	# --- a wall takes a fifth of the blow
	t.set_wall_level(1)
	var hp0 := t.wall_hp
	t.take_damage(30.0, att)
	_check(is_equal_approx(hp0 - t.wall_hp, 30.0 / Defs.ATTACK_SLOW_DOWN / 5.0), "the wall takes a fifth of the slowed blow")
	t.wall_hp = 50.0
	t.last_attacked_frame = -1000
	t.repair_wall = false
	t._process_wall()
	_check(t.wall_hp == 50.0, "without orders the wall is not repaired")
	t.repair_wall = true
	t._process_wall()
	_check(t.wall_hp == 51.0, "ordered, a villager mends it a point a day")

	# --- Fryhtan tribute only once resistance is gone
	var fry: Nation = g.nations.filter(func(n): return n.is_fryhtan)[0]
	var lair := g.spawn_firm("LAIR", fry.id, fry.monster_code, g._place_near(t.footprint(), 6, 6, 8), true)
	lair.accept_unit(g.spawn_unit(fry.monster_code, fry.id, lair.door(), 60.0))
	lair.overseer = lair.soldiers[0] if lair.overseer == null and not lair.soldiers.is_empty() else lair.overseer
	g.update_links()
	t.resistance[fry.id] = 20.0
	_check(t.tribute_to() == 0, "a village resisting at 20 pays no tribute")
	t.resistance[fry.id] = 0.0
	_check(t.tribute_to() == fry.id, "at 0 it pays the Fryhtans")
	var cash0 := fry.cash
	t._pay_tribute()
	_check(fry.cash > cash0, "5 a villager by the commander's leadership (%d)" % int(fry.cash - cash0))

	# --- building repairs only when ordered
	var fort: Firm = g.firms.filter(func(f): return f.nation_id == p.id and f.code == "FORT")[0]
	fort.hp = fort.max_hp - 10.0
	fort.last_attacked_frame = -1000
	fort.repair = false
	_days(g, 3)
	_check(fort.hp == fort.max_hp - 10.0, "a damaged building is not mended unless told")
	fort.set_repair(true)
	var c1 := p.cash
	_days(g, 3)
	_check(fort.hp > fort.max_hp - 10.0 and p.cash < c1, "ordered, it is mended a point a day at its cost")
	print("RESULT: ", "PASS" if fails == 0 else "FAIL")
	get_tree().quit(0 if fails == 0 else 2)
