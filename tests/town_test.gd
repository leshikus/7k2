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
	var cells := {}
	for u in out3:
		cells[u.cell()] = true
	_check(cells.size() == out3.size(), "the men come out on separate cells (%d men, %d cells)" % [out3.size(), cells.size()])

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
	vt.return_fire(raider)                # Town::return_fire: the villagers mark their attacker
	var bystander: Town = g.towns.filter(func(x): return x != vt and not x.dead)[0]
	_check(not bystander.fire_targets.has(raider), "another village does not throw at a raider who never attacked it")
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

	# --- loyalty as the original keeps it
	# a soldier in the field without a general drifts down a point a month
	var lone := g.spawn_unit(Defs.unit_sprite(p.race, "INF"), p.id, g.free_unit_cell(Vector2i(home.center_loc()) + Vector2i(-9, 6)), 30.0)
	lone.loyalty = 60.0
	Espionage.update_unit_loyalty(lone)
	_check(lone.loyalty == 59.0, "a soldier with no general loses a point a month (%.0f)" % lone.loyalty)
	# a general who has done much and been rewarded little is less loyal
	var vet := g.spawn_unit(Defs.unit_sprite(p.race, "INF"), p.id, g.free_unit_cell(Vector2i(home.center_loc()) + Vector2i(-9, 8)), 60.0)
	vet.rank = Defs.Rank.GENERAL
	vet.nation_contribution = 120
	_check(Espionage.contribution_penalty(vet) == 50.0, "an unrewarded veteran general loses up to 50 of his target loyalty")
	vet.reward(p.id)
	vet.reward(p.id)
	_check(Espionage.contribution_penalty(vet) == 0.0, "rewards make up for it (%d gold for %d deeds)" % [vet.total_reward, vet.nation_contribution])
	# a camp's men change loyalty once a month, not daily
	var lc := g.spawn_firm("CAMP", p.id, p.race, g._place_near(home.footprint(), 6, 6, 20), true)
	var lg := g.spawn_unit(Defs.unit_sprite(p.race, "INF"), p.id, g.free_unit_cell(lc.door()), 40.0)
	lg.rank = Defs.Rank.GENERAL
	lg.leadership = 10.0
	lc.accept_unit(lg)
	var ls := g.spawn_unit(Defs.unit_sprite(p.race, "INF"), p.id, g.free_unit_cell(lc.door()), 90.0)
	ls.leadership = 60.0
	lc.accept_unit(ls)
	ls.loyalty = 70.0
	for d in 29:
		lc.next_day(g.day + 1 + d)
	_check(ls.loyalty >= 69.0, "camp loyalty moves once a month, not daily (%.0f after 29 days)" % ls.loyalty)
	# below 30 a soldier in the field may go over to another kingdom
	var foe2: Nation = g.nations.filter(func(n): return n.id != p.id and not n.is_fryhtan)[0]
	p.contact[foe2.id] = true
	foe2.reputation = 80.0
	var turn := g.spawn_unit(Defs.unit_sprite(p.race, "INF"), p.id, g.free_unit_cell(Vector2i(home.center_loc()) + Vector2i(-11, 6)), 30.0)
	turn.loyalty = 0.0
	Espionage.think_betray(g, turn)
	_check(turn.nation_id == foe2.id and turn.loyalty >= 40.0, "a soldier with no loyalty left goes over to a respected kingdom (loyalty now %.0f)" % turn.loyalty)

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
	# --- a general's influence on a linked town (Town::update_target_loyalty):
	# leadership / 3, +8 for his race and +8 for the kingdom's being the
	# town's; a fort counts fully, a camp 80%
	home = g.spawn_town(p.race, p.id, g._random_free_rect(Defs.TOWN_SIZE + 16, Defs.TOWN_SIZE + 16, 2, [], 0.0) + Vector2i(8, 8), 30)
	home.loyalty = 60.0
	var fb := Assets.firm_build("FORT", p.race)
	var lfort := g.spawn_firm("FORT", p.id, p.race, g._place_near(home.footprint(), fb.get("loc_w", 4), fb.get("loc_h", 4), 6, [home.center_loc()]), true)
	g.update_links()
	_check(home.linked_firms.has(lfort), "the new fort is linked to the town")
	var lgen := g.spawn_unit(Defs.unit_sprite(p.race, "INF"), p.id, lfort.door(), 40.0)
	lgen.rank = Defs.Rank.GENERAL
	lgen.leadership = 60.0
	lfort.accept_unit(lgen)
	var gen_part := func() -> int:
		for pt in home.target_loyalty_parts():
			if str(pt[0]).contains(lgen.display_name()):
				return int(pt[1])
		return -999
	_check(gen_part.call() == 60 / 3 + 8 + 8, "a general of leadership 60 adds 36 to his town's target loyalty (%d)" % gen_part.call())
	lfort.code = "CAMP"
	_check(gen_part.call() == 36 * 80 / 100, "in a camp, 80%% of it (%d)" % gen_part.call())
	lfort.code = "FORT"
	var parts := home.target_loyalty_parts()
	var total := 0
	for pt in parts.slice(0, -1):
		total += int(pt[1])
	home.update_target_loyalty()
	_check(int(home.target_loyalty) == clampi(total, 0, 100) or total > 100, "the target is the sum of its terms (%d)" % int(home.target_loyalty))

	# --- promotion and demotion (Unit::set_rank)
	lfort.release_unit(lgen)
	lgen.loyalty = 70.0
	lgen.demote()
	_check(lgen.rank == Defs.Rank.SOLDIER and lgen.loyalty == 30.0, "a demoted general loses 40 loyalty (%.0f)" % lgen.loyalty)
	lgen.promote()
	_check(lgen.rank == Defs.Rank.GENERAL and lgen.loyalty == 50.0, "a promoted soldier gains 20 (%.0f)" % lgen.loyalty)

	# --- who builds what (FirmInfo::can_build) and the free band around buildings
	var civ := g.spawn_unit(Defs.unit_sprite(p.race, "CIV"), p.id, g.free_unit_cell(lfort.door()), 10.0)
	_check(civ != null and civ.is_civilian(), "a villager")
	_check(Defs.unit_can_build(lgen, "CAMP") and not Defs.unit_can_build(lgen, "MARKET") and Defs.unit_can_build(lgen, "WAR") and Defs.unit_can_build(lgen, "OFF_BLD1"),
		"a soldier builds military buildings only")
	_check(Defs.unit_can_build(civ, "MARKET") and Defs.unit_can_build(civ, "CAMP") and not Defs.unit_can_build(civ, "OFF_BLD1"),
		"a villager builds the rest, and camps, but no offensive structure")
	var fp := lfort.footprint()
	_check(not g.can_build_firm("MARKET", Vector2i(fp.end.x + 1, fp.position.y), 3, 3), "no building one cell from another")
	var far := Vector2i(fp.end.x + Game.INTER_PLACE_SPACE, fp.position.y)
	_check(g.can_build_firm("MARKET", far, 3, 3) or not g.world.can_place(far.x, far.y, 3, 3), "two cells apart is allowed")

	# --- settling a group into a town of their race
	var settlers: Array = []
	for i in 2:
		settlers.append(g.spawn_unit(Defs.unit_sprite(p.race, "INF"), p.id, g.free_unit_cell(Vector2i(home.center_loc()) + Vector2i(6, 0)), 20.0))
	home.population = 20
	for su in settlers:
		su.order_settle_into(home)
	_days(g, 20)
	_check(home.population == 22, "soldiers ordered into their town join it (%d)" % home.population)
	# --- the king dies: the throne stays empty until a successor is chosen
	var old_king := p.king
	old_king.leadership = 90.0
	var heir := g.spawn_unit(Defs.unit_sprite(p.race, "INF"), p.id, g.free_unit_cell(Vector2i(home.center_loc()) + Vector2i(-6, 0)), 40.0)
	heir.leadership = 30.0
	var witness := g.spawn_unit(Defs.unit_sprite(p.race, "INF"), p.id, g.free_unit_cell(Vector2i(home.center_loc()) + Vector2i(-6, 2)), 40.0)
	witness.loyalty = 80.0
	old_king.die(null)
	_check(p.king == null and heir.rank == Defs.Rank.SOLDIER, "nobody is crowned by himself")
	_check(heir.can_succeed_king() and not civ.can_succeed_king() and g.has_king_successor_candidate(p), "a soldier can succeed him, a villager not")
	var hl := home.loyalty
	_days(g, 9)
	_check(witness.loyalty <= 77.0 and home.loyalty < hl, "with the throne empty, loyalty falls a point every 3 days (%.0f)" % witness.loyalty)
	witness.loyalty = 80.0
	home.loyalty = 60.0
	g.cmd_succeed_king(p.id, heir)
	# 40 leadership taken as at least 20... 30 < 90: (30 - 90) / 3 = -20, and -20 more for a soldier
	_check(p.king == heir and heir.rank == Defs.Rank.KING, "the chosen soldier is king")
	_check(witness.loyalty == 40.0 and home.loyalty == 20.0, "loyalty falls by a third of the lost leadership and 20 for a soldier (%.0f, town %.0f)" % [witness.loyalty, home.loyalty])
	_check(not heir.can_succeed_king() and not witness.can_succeed_king(), "no one else can succeed while there is a king")
	# no king and no candidate: the kingdom is lost
	heir.die(null)
	for m in g.units.duplicate():
		if m.nation_id == p.id and not m.dead and m.can_succeed_king():
			m.die(null)
	_check(not g.has_king_successor_candidate(p), "nobody left to succeed")
	print("RESULT: ", "PASS" if fails == 0 else "FAIL")
	get_tree().quit(0 if fails == 0 else 2)
