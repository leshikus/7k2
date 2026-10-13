extends Node
## Behaviour checked against the original's formulas, written out here from
## the source independently of the game code: Unit::actual_damage (mean of
## many blows), BaseObj::being_attack_hit, Skill::actual_max_hit_points,
## AttackAttribute::effectiveness, the leading general and hero bonuses, a
## duel's length, and the money of caravan trade (UnitCaravan::
## market_load_goods_now, NationBase::import_goods).

var ok := true


func check(cond: bool, what: String) -> void:
	print(("ok   " if cond else "FAIL ") + what)
	if not cond:
		ok = false


## Unit::actual_damage, expected value: attack_damage + random(3) [mean 1]
## + pierce * random(1+min(combat,100)) / 100 [mean pierce*min(c,100)/200]
## + combat*2/100 for heroes above 100 + min(base*leadership, 1000)/100 when led.
func expected_damage(att: Dictionary, combat: float, leadership := 0.0) -> float:
	var base := float(att["damage"]) + 1.0
	var e := base + float(att["pierce"]) * minf(combat, 100.0) / 200.0
	if combat > 100.0:
		e += combat * 2.0 / 100.0
	if leadership > 0.0:
		e += minf((float(att["damage"]) + 1.0) * leadership, 1000.0) / 100.0
	return e


func mean_roll(u: Unit, att: Dictionary, n := 6000) -> float:
	var s := 0.0
	for i in n:
		s += u.roll_damage(att)
	return s / n


func _ready() -> void:
	if Assets.load_install() != "":
		get_tree().quit(1); return
	Defs.load_from_assets()
	var g := Game.new()
	add_child(g)
	g.start({"seed": 2, "size": 90, "race": "NORMAN", "ai_count": 1, "fryhtan_count": 0, "reveal": true})
	var p := g.player()
	var foe: Nation = g.nations.filter(func(n): return n.id != p.id)[0]
	p.tech.clear()
	var inf := Defs.unit_sprite("NORMAN", "INF")
	var spot := g.world.nearest_walkable(Vector2i(40, 40))

	# ---- hit points and blows
	var t := float(Defs.unit_types[inf]["hp"])
	for c in [10.0, 20.0, 55.0, 100.0]:
		var u := g.spawn_unit(inf, p.id, spot, c)
		check(is_equal_approx(u.max_hp, t * c / 100.0), "max hit points = %d x %d / 100 = %.1f" % [t, c, u.max_hp])
		u.die(null)
	var target := g.spawn_unit(inf, foe.id, spot + Vector2i(1, 0), 60.0)
	target.stop()
	for blow in [2.0, 9.0, 30.0]:
		var before := target.hp
		target.take_damage(blow, null)
		var a: float = target.armor()
		var d: float = blow - a
		var expect: float = (-1.0 / d if d <= -1.0 else (1.0 if d < 1.0 else d))
		expect = minf(expect, blow) / 3.0
		check(is_equal_approx(before - target.hp, expect), "a blow of %d against armour %d takes %.2f (being_attack_hit)" % [blow, a, before - target.hp])
	target.hp = target.max_hp

	# ---- damage by combat level, against the formula's mean
	var attacker := g.spawn_unit(inf, p.id, spot + Vector2i(-1, 0), 40.0)
	attacker.stop()
	attacker.target = null
	var att: Dictionary = attacker.utype["attacks"][0]
	for c in [20.0, 60.0, 100.0]:
		attacker.combat = c
		var m := mean_roll(attacker, att)
		var e := expected_damage(att, c)
		check(absf(m - e) / e < 0.03, "mean blow at combat %d: %.2f, formula %.2f" % [c, m, e])
	# a hero above the trained maximum: one more for every 50 combat
	attacker.combat = 250.0
	var mh := mean_roll(attacker, att)
	var eh := expected_damage(att, 250.0)
	check(absf(mh - eh) / eh < 0.03, "mean blow of a combat-250 hero: %.2f, formula %.2f" % [mh, eh])
	attacker.combat = 40.0
	# led by a general within ten cells
	var gen := g.spawn_unit(inf, p.id, spot + Vector2i(-3, 0), 60.0)
	gen.rank = Defs.Rank.GENERAL
	gen.leadership = 70.0
	gen.stop()
	attacker.leader = gen
	var ml := mean_roll(attacker, att)
	var el := expected_damage(att, 40.0, 70.0)
	check(absf(ml - el) / el < 0.03, "led by a general of leadership 70: %.2f, formula %.2f" % [ml, el])
	gen.loc = Vector2(spot) + Vector2(-30, 0)
	check(attacker.leading_general() == null, "a general too far away does not lead")
	attacker.leader = null

	# ---- effectiveness: a cannon on a fort, a catapult on a man
	var fort: Firm = g.firms.filter(func(f): return f.code == "FORT")[0]
	for w in ["CANNON", "CATAPULT"]:
		if not Defs.unit_types.has(w) or not Assets.has_sprite(w):
			continue
		var wa: Dictionary = Defs.unit_types[w]["attacks"][0]
		var a: Array = wa["att"]
		for tgt in [fort, target]:
			var dfn: Array = tgt.defense()
			var expect: float = ((a[0] + a[1]) / 2 * dfn[0] + (100 - dfn[0]) * a[2] + a[3] * dfn[1]) / 10000.0 + 1.0
			check(is_equal_approx(Defs.effectiveness(a, dfn), expect) and expect >= 1.0,
				"%s on %s: effectiveness %.2f" % [w, tgt.display_name(), expect])

	# ---- a duel lasts as the formulas say
	var hits := 0
	var trials := 40
	for i in trials:
		var a1 := g.spawn_unit(inf, p.id, spot + Vector2i(-1, 3), 50.0)
		var b1 := g.spawn_unit(inf, foe.id, spot + Vector2i(0, 3), 50.0)
		a1.target = b1
		a1.dir = 2
		b1.dir = 6                      # face to face: no flank bonus
		var n := 0
		while not b1.dead and n < 1000:
			b1.take_damage(a1.roll_damage(a1.utype["attacks"][0]), a1)
			n += 1
		hits += n
		a1.die(null)
	# the formula's mean hit, blow by blow: actual_damage, then being_attack_hit
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var arm: float = target.armor()
	var sum := 0.0
	for k in 20000:
		var x := float(att["damage"]) + rng.randi_range(0, 2) + float(att["pierce"]) * rng.randi_range(0, 50) / 100.0
		var dd := x - arm
		var hit: float = (-1.0 / dd if dd <= -1.0 else (1.0 if dd < 1.0 else dd))
		sum += minf(hit, x) / 3.0
	var per_hit := sum / 20000.0
	var expect_hits := float(Defs.unit_types[inf]["hp"]) * 0.5 / per_hit
	check(absf(float(hits) / trials - expect_hits) <= maxf(1.5, expect_hits * 0.15),
		"a combat-50 infantryman falls to another in %.1f blows (formula %.1f)" % [float(hits) / trials, expect_hits])

	# ---- shields and special abilities (Bullet::hit_target, oun_spab.cpp)
	var guard := g.spawn_unit(inf, foe.id, spot + Vector2i(4, 4), 50.0)
	guard.stop()
	guard.dir = 2
	check(guard.can_guard(false), "a combat-50 Norman infantryman can raise his shield (guard level %d)" % Defs.unit_types[inf]["guard_level"])
	guard.warned(6)
	check(guard.is_guarding() and guard.dir == 2, "an arrow from the front: he raises it")
	check(is_equal_approx(guard.arrow_reduction(15.0, 6), 5.0), "and the arrow loses 10")
	check(is_equal_approx(guard.arrow_reduction(15.0, 2), 15.0), "but not one from behind")
	var shooter := g.spawn_unit(inf, p.id, spot + Vector2i(4, 0), 50.0)
	shooter.stop()
	guard.spab = "reflect"
	guard.spab_day = g.day
	guard.guard_frames = 0
	var nb := g.bullets.size()
	var refl := g.spawn_bullet(shooter, guard, "ARROW" if Assets.has_sprite("ARROW") else shooter.utype["attacks"][0]["bullet"], 8.0, 6.0)
	var hp_g := guard.hp
	for k in 200:
		if refl.done:
			break
		refl.sim_frame()
	var back := g.bullets.filter(func(b): return b.target == shooter and not b.done)
	check(is_equal_approx(guard.hp, hp_g) and back.size() == 1 and is_equal_approx(back[0].damage, 5.0), "Reflect Arrow: it flies back to the archer, a point weaker")
	guard.spab = ""
	var freezer := g.spawn_unit(Defs.unit_sprite("VIKING", "INF"), p.id, spot + Vector2i(8, 8), 250.0)
	var victims: Array = []
	for k in 6:
		victims.append(g.spawn_unit(inf, foe.id, g.free_unit_cell(spot + Vector2i(10, 8)), 10.0))
	g.sim_frame()
	freezer.spab = "freeze"
	freezer.spab_day = g.day
	freezer._freeze_around(victims[0])
	check(victims.slice(1).any(func(v): return v.frozen_until > g.frame), "Freeze: a blow freezes enemies near the target")
	check(Defs.SPECIAL_ABILITY["NO_INF"] == "mirage" and Defs.SPECIAL_ABILITY["RO_SPU"] == "reflect" and Defs.SPECIAL_ABILITY["VI_INF"] == "freeze", "each unit has the original's ability")

	# ---- training in a fort (FirmCamp::basic_train, advanced_train)
	var tfort: Firm = g.firms.filter(func(f): return f.code == "FORT" and f.nation_id == p.id)[0]
	var tt: Town = g.towns.filter(func(x): return x.nation_id == p.id)[0]
	tt.loyalty = 90.0
	while tfort.soldiers.size() >= tfort.capacity():
		tfort.release_unit(tfort.soldiers[-1])
	var rec := tt.draft_into(tfort)
	check(rec != null and rec.basic_days == int(rec.utype["build_days"]), "a recruit starts basic training")
	if rec:
		for d in rec.basic_days + 1:
			g.day += 1
			tfort._train()
		check(absf(rec.combat - 20.0) < 0.5 and rec.basic_days == 0, "and finishes it at combat 20 (%.2f)" % rec.combat)
		var o: Unit = tfort.overseer
		rec.potential = 0
		rec.hp = rec.max_hp
		var c0 := rec.combat
		var lead := int(o.lead_skill())
		g.day = (g.day / 30 + 1) * 30 + tfort.obj_id % 30
		tfort._train()
		var expect := c0 + maxf(20.0, lead - c0) * 1.0 * 100.0 / 100.0 / 100.0
		check(lead <= c0 or is_equal_approx(rec.combat, minf(expect, lead)), "a month under a general of leadership %d: combat %.2f -> %.2f (formula %.2f)" % [lead, c0, rec.combat, expect])

	# ---- trade: loading at a foreign market is a purchase, unloading is free
	Diplomacy.set_trade(g, p.id, foe.id, true)
	var home: Town = g.towns.filter(func(x): return x.nation_id == p.id)[0]
	var ftown: Town = g.towns.filter(func(x): return x.nation_id == foe.id)[0]
	var m1 := g.spawn_firm("MARKET", p.id, "NORMAN", g._place_near(home.footprint(), 5, 5, 8), true)
	var m2 := g.spawn_firm("MARKET", foe.id, foe.race, g._place_near(ftown.footprint(), 5, 5, 8), true)
	p.cash = 5000.0
	foe.cash = 5000.0
	m2.goods["Iron"] = 200.0
	m1.goods.clear()
	var car := g.spawn_unit("CARAVAN", p.id, g.free_unit_cell(Vector2i(m2.x1, m2.y1 + m2.h + 1)), 10.0)
	car.set_caravan_stop(0, m1)
	car.set_caravan_stop(1, m2)
	# UnitCaravan::market_auto_load_goods at the foreign market: what is above 100
	Caravans._market_auto_load(car, m2)
	var bought: float = car.cargo.get("P:Iron", 0.0)
	check(is_equal_approx(bought, 100.0), "the caravan loads what is above 100 abroad (%d)" % bought)
	check(is_equal_approx(5000.0 - p.cash, bought * Defs.PRODUCT_PRICE) and is_equal_approx(foe.cash - 5000.0, bought * Defs.PRODUCT_PRICE),
		"paying %d x %.1f, which the seller earns (import_goods)" % [bought, Defs.PRODUCT_PRICE])
	check(is_equal_approx(float(p.import_year.get(foe.id, 0.0)), bought * Defs.PRODUCT_PRICE), "the purchase counts as imports from them")
	var cash_before := p.cash
	var foe_before := foe.cash
	Caravans._market_unload(car, m1)
	check(is_equal_approx(p.cash, cash_before) and is_equal_approx(foe.cash, foe_before) and m1.goods.get("Iron", 0.0) >= bought - 0.01,
		"unloading at home costs and earns nothing")
	car.cargo["P:Iron"] = 50.0
	Caravans._market_unload(car, m2)
	check(is_equal_approx(car.cargo.get("P:Iron", 0.0), 50.0), "nothing is unloaded at another kingdom's market")
	p.cash = 10.0
	m2.goods["Iron"] = 300.0
	car.cargo.clear()
	Caravans._market_auto_load(car, m2)
	check(car.cargo.get("P:Iron", 0.0) <= 10.0 / Defs.PRODUCT_PRICE + 0.01, "a kingdom buys only what its treasury pays for")
	print("RESULT: ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
