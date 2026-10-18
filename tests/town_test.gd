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
	# --- the sortie: all, no leader, no injured; recruits in training stay
	var camp: Firm = fort
	camp.eject_all()
	var gen := g.spawn_unit(Defs.unit_sprite(p.race, "INF"), p.id, camp.door(), 60.0)
	gen.rank = Defs.Rank.GENERAL
	camp.accept_unit(gen)
	var men: Array = []
	for i in 4:
		var s := g.spawn_unit(Defs.unit_sprite(p.race, "INF"), p.id, g.free_unit_cell(camp.door()), 40.0)
		camp.accept_unit(s)
		s.basic_days = 0
		men.append(s)
	men[3].basic_days = 5
	men[2].hp = men[2].max_hp - 30.0
	var out1 := camp.patrol(Firm.PATROL_NO_GENERAL)
	_check(camp.overseer == gen and out1.size() == 3 and not (men[3] in out1), "no leader: the trained soldiers go, the commander and the recruit stay")
	for u in out1:
		camp.accept_unit(u)
		u.basic_days = 0
	var out2 := camp.patrol(Firm.PATROL_NO_INJURED)
	_check(gen in out2 and not (men[2] in out2) and out2.size() == 3, "no injured: the wounded man stays (%d out)" % out2.size())
	_check(out2.all(func(u): return u == gen or u.leader == gen), "the commander leads his sortie")
	for u in out2:
		camp.accept_unit(u)
	var out3 := camp.patrol(Firm.PATROL_ALL)
	_check(gen in out3 and men[2] in out3 and not (men[3] in out3), "all: everyone trained goes out with the commander")

	# --- one commander: a general entering takes over and the old one comes out
	for u in out3:
		if u != gen:
			camp.accept_unit(u)
	var king := p.king
	if king.inside_firm:
		king.inside_firm.release_unit(king)
	camp.accept_unit(king)
	_check(camp.overseer == king and gen.inside_firm == null, "the king takes command of the fort")
	camp.accept_unit(gen)
	_check(camp.overseer == gen and king.inside_firm == null and not (king in camp.soldiers), "a general entering takes command; the king comes out")
	_check(not camp.soldiers.any(func(s): return s.rank >= Defs.Rank.GENERAL), "no general or king is kept among the soldiers")
	var sol: Unit = camp.soldiers.filter(func(s): return s.basic_days <= 0)[0]
	camp.make_overseer(sol)
	_check(sol in camp.soldiers, "no promotion while there is a commander")
	camp.release_unit(gen)
	camp.make_overseer(sol)
	_check(camp.overseer == sol and sol.rank == Defs.Rank.GENERAL, "with none, a soldier is promoted to general and commander")

	# --- villagers throw stones and bricks (Town::bullet_id)
	var foe: Nation = g.nations.filter(func(n): return n.id != p.id and not n.is_fryhtan)[0]
	var vt: Town = g.towns.filter(func(x): return x.nation_id == 0)[0]
	vt.population = 30
	vt.resistance[foe.id] = 80.0
	var raider := g.spawn_unit(Defs.unit_sprite(foe.race, "INF"), foe.id, g.free_unit_cell(Vector2i(vt.center_loc()) + Vector2i(5, 0)), 30.0)
	vt.aggressors[foe.id] = g.frame       # it has attacked the village
	g.unit_grid.clear()
	g.sim_frame()
	var nb := g.bullets.size()
	for i in 40:
		vt.archer_energy = 100
		vt.town_shoot()
	var thrown: Array = g.bullets.slice(nb)
	_check(not thrown.is_empty() and thrown.all(func(b): return b.sprite_code in ["ROCK", "BRICK"]), "villagers throw rocks and bricks (%d thrown)" % thrown.size())
	raider.die(null)

	# --- a wagon takes the jobless first, then workers; one alone walks
	var home: Town = g.towns.filter(func(x): return x.nation_id == p.id)[0]
	var mine := g.spawn_firm("FACTORY", p.id, p.race, g._place_near(home.footprint(), 5, 5, 14), true)
	g.update_links()
	home.population = 12
	home.loyalty = 80.0
	home.recruit_penalty = 0
	mine.worker_towns.clear()
	for i in 12:
		mine.worker_towns.append(home)
	g._update_workers()
	_check(home.jobless() == 0 and home.wagon_count() == 10, "a town with nobody idle can still send a wagon of 10")
	var w := home.recruit_wagon()
	g._update_workers()
	_check(w != null and w.is_wagon() and w.wagon_pop == 10 and home.population == 2, "ten leave in the wagon (%d left)" % home.population)
	_check(mine.workers() == 2, "the workers who left quit the mine (%d stay)" % mine.workers())
	_check(home.loyalty < 80.0, "the town's loyalty drops (%.1f)" % home.loyalty)
	home.population = 1
	mine.worker_towns.clear()
	g._update_workers()
	var one := home.recruit_wagon()
	_check(one != null and not one.is_wagon() and home.population == 0, "a lone villager walks instead")
	# --- a camp is upgraded to a fort in place, troops and all (Firm::start_upgrade)
	var cmp := g.spawn_firm("CAMP", p.id, p.race, g._place_near(home.footprint(), 6, 6, 16), true)
	var cg := g.spawn_unit(Defs.unit_sprite(p.race, "INF"), p.id, g.free_unit_cell(cmp.door()), 50.0)
	cg.rank = Defs.Rank.GENERAL
	cmp.accept_unit(cg)
	var cs := g.spawn_unit(Defs.unit_sprite(p.race, "INF"), p.id, g.free_unit_cell(cmp.door()), 30.0)
	cmp.accept_unit(cs)
	p.cash = 5000.0
	var cash1 := p.cash
	_check(cmp.start_upgrade("FORT") and is_equal_approx(cash1 - p.cash, float(Defs.firm_types["FORT"]["cost"])), "the upgrade costs a fort's setup cost")
	_check(not cmp.start_upgrade("FORT"), "it cannot be started twice")
	for i in 260:
		cmp.sim_frame()
		g.frame += 1
	_check(cmp.code == "FORT" and cmp.upgrading == "" and cmp.overseer == cg and cs in cmp.soldiers, "after 200 frames the camp is a fort with its commander and soldiers inside")

	# --- rewards: 30 gold for 10 loyalty (Unit::reward, FirmCamp::reward)
	cs.loyalty = 40.0
	cg.loyalty = 70.0
	var cash2 := p.cash
	cmp.reward_least_loyal()
	_check(cs.loyalty == 50.0 and cg.loyalty == 70.0 and is_equal_approx(cash2 - p.cash, 30.0), "the camp's least loyal man is rewarded")
	var ru := g.spawn_unit(Defs.unit_sprite(p.race, "INF"), p.id, g.free_unit_cell(Vector2i(home.center_loc()) + Vector2i(9, -6)), 30.0)
	ru.loyalty = 95.0
	ru.reward(p.id)
	_check(ru.loyalty == 100.0, "a reward lifts loyalty, up to 100")
	p.king.loyalty = 50.0
	p.king.reward(p.id)
	_check(p.king.loyalty == 50.0, "the king is not rewarded")

	# --- cancelling a building site: half the cost back, the builder walks out
	var site_at := g._place_near(home.footprint(), 5, 5, 18)
	var uc := g.spawn_firm("INN", p.id, p.race, site_at, false)
	var bld := g.spawn_unit(Defs.unit_sprite(p.race, "CIV"), p.id, g.free_unit_cell(site_at), 20.0)
	uc.set_builder(bld)
	var cash3 := p.cash
	uc.cancel_construction()
	_check(uc.dead and is_equal_approx(p.cash - cash3, float(Defs.firm_types["INN"]["cost"]) / 2.0), "a cancelled site refunds half its cost")
	_check(not bld.dead and bld.inside_firm == null and bld.visible, "and its builder comes out")

	# --- Fryhtans are not people: they cannot found towns
	var fu := g.spawn_unit(fry.monster_code, p.id, g.free_unit_cell(Vector2i(home.center_loc()) + Vector2i(8, 8)), 30.0)
	_check(fu != null and not fu.is_human() and not fu.can_found_town(), "a Fryhtan cannot build a town")
	fu.die(null)

	# --- selling: half the cost by hit points, only above 80%
	var c0 := p.cash
	mine.hp = mine.max_hp * 0.7
	_check(not mine.can_sell(), "a building below 80% of its hit points cannot be sold")
	mine.hp = mine.max_hp
	mine.sell_firm()
	_check(mine.dead and is_equal_approx(p.cash - c0, float(Defs.firm_types["FACTORY"]["cost"]) / 2.0), "sold for half its cost (%d)" % int(p.cash - c0))
	_check(ScenarioFile.fix_caps("FRY IN BOOTS") == "Fry in Boots" and ScenarioFile.fix_caps("GAUL: SECOND TIME LUCKY") == "Gaul: Second Time Lucky"
		and ScenarioFile.fix_caps("ALEXANDER THE NOT SO GREAT (by Nick)") == "Alexander the Not So Great (by Nick)" and ScenarioFile.fix_caps("I Spy: DarkManX") == "I Spy: DarkManX",
		"scenario names in capitals are shown in title case")
	print("RESULT: ", "PASS" if fails == 0 else "FAIL")
	get_tree().quit(0 if fails == 0 else 2)
