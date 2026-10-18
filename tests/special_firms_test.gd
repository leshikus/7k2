extends Node
## Fryhtan special buildings, offensive buildings, lair technology, Porcupine,
## berserk gating and their save/load.

var ok := true


func check(cond: bool, what: String) -> void:
	print(("ok   " if cond else "FAIL ") + what)
	if not cond:
		ok = false


func days(g: Game, n: int) -> void:
	for d in n:
		for f in Defs.FRAMES_PER_DAY * 3:
			g.sim_frame()


func open_spot(g: Game, near: Vector2i, w: int, h: int) -> Vector2i:
	for r in range(4, 30):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var at := near + Vector2i(dx, dy)
				if g.world.can_place(at.x - 1, at.y - 1, w + 2, h + 2) and not g._overlaps_site(Rect2i(at, Vector2i(w, h))):
					var busy := g.units.any(func(u): return not u.dead and u.inside_firm == null and Rect2i(at - Vector2i(1, 1), Vector2i(w + 2, h + 2)).has_point(u.cell()))
					if not busy:
						return at
	return Vector2i(-1, -1)


func _ready() -> void:
	if Assets.load_install() != "":
		get_tree().quit(1); return
	Defs.load_from_assets()
	var g := Game.new()
	add_child(g)
	g.start({"seed": 11, "size": 120, "race": "GITH", "ai_count": 1, "fryhtan_count": 1, "reveal": true})
	var p := g.player()
	p.cash = 20000.0
	p.live_points = 20000.0
	var human: Nation = g.nations.filter(func(n): return not n.is_fryhtan)[0]
	g.declare_war(p.id, human.id)
	var lair: Firm = g.firms.filter(func(f): return f.nation_id == p.id and f.code == "LAIR")[0]
	var home := lair.center_loc()
	print("player ", p.name, " species ", SpecialFirms.lair_species(lair))

	# ---- lair technology
	check(SpecialFirms.buy_tech(lair, "FORTRESS") and p.tech_level("FORTRESS") == 1, "buy Fortress at a Grokken lair")
	check(not SpecialFirms.buy_tech(lair, "LISHORR"), "cannot buy another species' tech")
	check(not SpecialFirms.buy_tech(lair, "WEAPON1"), "cannot buy Ezpinez tech")
	var life0 := p.live_points
	check(SpecialFirms.buy_tech(lair, "FORT_CAM") and life0 - p.live_points == Defs.fryhtan_tech_live_cost(Defs.tech_def("FORT_CAM")), "Camouflaged Fortress costs life points")

	# ---- Fortress from four Grokkens
	var spot := open_spot(g, Vector2i(home) + Vector2i(10, 0), 4, 4)
	var grok: Array = []
	for o in [Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2), Vector2i(2, 2)]:
		grok.append(g.spawn_unit("GITH", p.id, spot + o, 40.0))
	check(SpecialFirms.fortress_spot(grok.slice(0, 3)).x < 0, "three Grokkens are not enough")
	var fort := SpecialFirms.transform_to_fortress(grok)
	check(fort != null and fort.code == "FORTRESS" and not fort.under_construction, "four Grokkens become a Fortress")
	if fort:
		check(fort.extra_units.size() == 4 and grok.all(func(u): return u.inside_firm == fort), "the Grokkens are inside it")
		check(is_equal_approx(fort.max_hp, float(Defs.firm_types["FORTRESS"]["hp"]) * 1.0), "level-1 hit points")
		check(fort.hidden_from(human.id) and not fort.hidden_from(p.id), "camouflaged from others, not from its owner")
		var archer := g.spawn_unit("GITH", p.id, Vector2i(fort.x1 + fort.w + 1, fort.y1), 30.0)
		check(fort.accept_unit(archer), "a Grokken is posted inside")
		var human_u := g.spawn_unit("NO_INF", p.id, Vector2i(fort.x1 + fort.w + 1, fort.y1 + 1), 30.0)
		check(human_u == null or not fort.accept_unit(human_u), "only Fryhtans man a Fortress")
		var foe := g.spawn_unit(Defs.unit_sprite(human.race, "INF"), human.id, Vector2i(fort.x1 + fort.w + 5, fort.y1 + 1), 10.0)
		foe.frozen_until = g.frame + 100000
		var hp0 := foe.hp
		days(g, 5)
		check(foe.hp < hp0 or foe.dead, "the Fortress shoots at an enemy (%d -> %d)" % [hp0, foe.hp])
		check(g.frame < fort.shown_until or foe.dead, "firing reveals it for a while")

	# ---- breeding grounds and the Vapngart
	p.tech["FBEE"] = 1
	var bee_at := open_spot(g, Vector2i(home) + Vector2i(-14, 0), 5, 5)
	var hive := g.spawn_firm("BEE", p.id, "", bee_at, true)
	check(SpecialFirms.buildable_units(hive) == ["BEE"], "the Bheema Hyfe breeds Bheema")
	var cash0 := p.cash
	hive.queue_weapon("BEE")
	days(g, 25)
	var bees := g.units.filter(func(u): return u.sprite_code == "BEE" and u.nation_id == p.id and not u.dead)
	check(bees.size() == 1 and cash0 - p.cash >= 70.0, "a Bheema is bred for gold and life")
	p.tech["WEAPON3"] = 2
	var inc_at := open_spot(g, Vector2i(home) + Vector2i(0, 14), 6, 6)
	var inc := g.spawn_firm("INCUBAT", p.id, "", inc_at, true)
	check(SpecialFirms.buildable_units(inc) == ["F_CANNON"], "the Vapngart grows Nemezez once learnt")
	inc.queue_weapon("F_CANNON")
	days(g, 140)
	var nem: Array = g.units.filter(func(u): return u.sprite_code == "F_CANNON" and u.nation_id == p.id and not u.dead)
	check(nem.size() == 1, "a Nemezez is grown")
	if not nem.is_empty():
		check(nem[0].weapon_version == 2 and nem[0].attack_list().size() == 1 and nem[0].attack_list()[0]["range"] == 7, "version 2 uses its level-2 attack")

	# ---- Keraal
	p.tech["JAGUAR"] = 1
	var ker_at := open_spot(g, Vector2i(home) + Vector2i(14, 14), 6, 6)
	var ker := g.spawn_firm("ANIMAL", p.id, "", ker_at, true)
	for i in 3:
		SpecialFirms._update_animals(ker)
	check(not ker.animals.is_empty() and ker.animals.all(func(a): return a["unit"] == "JAGUAR"), "tamed Jaguara come to the Keraal")
	var jag := SpecialFirms.hire_animal(ker, 0)
	check(jag != null and jag.sprite_code == "JAGUAR" and jag.nation_id == p.id, "hire a Jaguara")

	# ---- Alchemist Tor
	p.tech["GOLDLIVE"] = 1
	var alc_at := open_spot(g, Vector2i(home) + Vector2i(-14, 14), 6, 6)
	var alc := g.spawn_firm("ALCHEMY", p.id, "", alc_at, true)
	check(not SpecialFirms.can_convert(alc, "LIVEGOLD"), "an unlearnt conversion is refused")
	alc.alchemy_mode = "GOLDLIVE"
	cash0 = p.cash
	life0 = p.live_points
	SpecialFirms._alchemy(alc)
	check(is_equal_approx(cash0 - p.cash, 30.0) and is_equal_approx(p.live_points - life0, 15.0), "30 gold become 15 life points (before Advanced Alchemy)")
	p.tech["ALCHEMY"] = 2
	cash0 = p.cash
	SpecialFirms._alchemy(alc)
	check(is_equal_approx(cash0 - p.cash, 60.0), "Advanced Alchemy doubles the rate")

	# ---- Mage Tor
	p.tech["MAGIC2"] = 1
	p.tech["MAGIC4"] = 1
	var mag_at := open_spot(g, Vector2i(home) + Vector2i(0, -14), 5, 5)
	var mag := g.spawn_firm("MAGIC", p.id, "", mag_at, true)
	check(not SpecialFirms.can_cast(mag, "WOUND"), "Wound Units needs its tech")
	var foes: Array = []
	for k in 3:
		foes.append(g.spawn_unit(Defs.unit_sprite(human.race, "INF"), human.id, Vector2i(mag.x1 + mag.w + 6 + k, mag.y1 + 2), 10.0))
	life0 = p.live_points
	var at: Vector2 = foes[1].center_loc()
	check(SpecialFirms.cast(mag, "FREEZE", at), "cast Freeze Units")
	check(foes.all(func(u): return u.frozen_until > g.frame + Defs.FRAMES_PER_DAY * 10), "enemies around the target are frozen for 12 days")
	check(p.live_points < life0 and mag.cast_charge == Defs.MAX_CAST_DELAY - 30, "the spell costs life points and charge")
	check(not SpecialFirms.can_cast(mag, "TELEPORT"), "no second spell until recharged")
	days(g, 31)
	check(SpecialFirms.can_cast(mag, "TELEPORT"), "recharged after 30 days")
	var alive: Array = (bees + [jag]).filter(func(u): return u != null and not u.dead and u.inside_firm == null)
	var tp_unit: Unit = alive[0] if not alive.is_empty() else g.spawn_unit("BEE", p.id, g.free_unit_cell(Vector2i(mag.x1, mag.y1 + mag.h + 2)), 20.0)
	var dest := g.world.nearest_walkable(Vector2i(home) + Vector2i(25, 25))
	check(SpecialFirms.cast(mag, "TELEPORT", Vector2(dest), tp_unit) and tp_unit.cell().distance_to(dest) < 4.0, "teleport a unit")

	# ---- Lishorr damage
	var lish := g.spawn_firm("LISHORR", p.id, "", open_spot(g, Vector2i(home) + Vector2i(20, -10), 2, 2), true)
	p.tech["LISHORR"] = 1
	var dmg := SpecialFirms.lishorr_damage(lish)
	check(dmg == 24.0 or dmg == 30.0, "Lishorr damage by weather and tech (%d)" % dmg)
	check(not SpecialFirms.hidden_from(lish, human.id), "a Lishorr is seen without Camouflage Ability")
	p.tech["LISH_CAM"] = 1
	check(SpecialFirms.hidden_from(lish, human.id), "with it, a Lishorr is hidden while it has not fired")

	# ---- independent lair taken over
	var wild: Array = g.firms.filter(func(f): return f.code == "LAIR" and f.is_monster())
	if not wild.is_empty():
		var wl: Firm = wild[0]
		var near := open_spot(g, Vector2i(wl.center_loc()) + Vector2i(8, 0), 6, 6)
		var mine_lair := g.spawn_firm("LAIR", p.id, p.race, near, true)
		mine_lair.monster_code = p.monster_code
		var cmd := g.spawn_unit(p.monster_code, p.id, near + Vector2i(0, 7), 60.0)
		cmd.rank = Defs.Rank.GENERAL
		mine_lair.accept_unit(cmd)
		check(SpecialFirms.can_take_lair(wl, p.id), "an independent lair next to ours can be bought")
		check(SpecialFirms.take_lair(wl, p.id) and wl.nation_id == p.id, "take over the independent lair")

	# ---- human side: offensive building, Porcupine, berserk
	human.cash = 10000.0
	human.is_ai = true
	var hf: Firm = g.firms.filter(func(f): return f.nation_id == human.id)[0]
	var arch_at := open_spot(g, Vector2i(hf.center_loc()) + Vector2i(12, 0), 5, 5)
	var arch := g.spawn_firm("OFF_BLD4", human.id, human.race, arch_at, true)
	var victims: Array = []
	# FirmMagic::think_cast_to_top: it fires when enough enemies are attacking it
	for k in 20:
		var v := g.spawn_unit("GITH", p.id, g.free_unit_cell(Vector2i(arch.x1 + arch.w + 1 + k % 3, arch.y1 + k / 3)), 20.0)
		v.frozen_until = g.frame + 100000
		v.order = Unit.Order.ATTACK
		v.target = arch
		victims.append(v)
	cash0 = human.cash
	SpecialFirms.next_day(arch, g.day)
	check(arch.cast_charge < Defs.MAX_CAST_DELAY and is_equal_approx(cash0 - human.cash, 70.0), "the computer's Archimedetron fires by itself for 70 gold")
	check(victims.all(func(v): return v.dead or v.hp < v.max_hp), "the death ray burns the Fryhtans around it")
	human.tech["EXPCART"] = 1
	var cart := g.spawn_unit("EXPCART", human.id, Vector2i(arch.x1 + arch.w + 6, arch.y1 + 6), 10.0)
	var tgt := g.spawn_unit("GITH", p.id, Vector2i(arch.x1 + arch.w + 8, arch.y1 + 6), 20.0)
	tgt.frozen_until = g.frame + 100000
	var thp := tgt.hp
	cart.order_attack(tgt)
	for f in 200:
		g.sim_frame()
	# EXPLODE_DAMAGE is 50 * ATTACK_SLOW_DOWN through being_attack_hit: about 50 less armour
	check(cart.dead and (tgt.dead or tgt.hp < thp - 40.0), "the Porcupine runs up and explodes (%d -> %d)" % [thp, tgt.hp])
	var spu := g.spawn_unit(Defs.unit_sprite(human.race, "SPU"), human.id, Vector2i(arch.x1 - 3, arch.y1), 100.0)
	var power: Array = spu.utype["attacks"].filter(func(a): return a.get("consume", 0) >= 20)
	if not power.is_empty():
		check(not spu.current_attack() in power, "berserk attack locked without the Berserker tech")
		human.tech[Defs.spu_berserk_tech(human.race)] = 1
		check(spu.current_attack() in power, "berserk attack with the tech")
	else:
		print("note: %s has no power attack" % spu.sprite_code)
	check(not Defs.can_research(human, Defs.tech_def(Defs.spu_structure_tech("INDIAN" if human.race != "INDIAN" else "NORMAN"))), "another race's training centre cannot be researched")

	# ---- save and load
	var fort_charge := mag.cast_charge
	SaveGame.save(g, "special_test")
	var g2 := Game.new()
	add_child(g2)
	SaveGame.load_into(g2, "special_test")
	Game.inst = g2
	var f2: Array = g2.firms.filter(func(f): return f.code == "FORTRESS")
	check(not f2.is_empty() and f2[0].extra_units.size() == 4 and f2[0].soldiers.size() >= 0, "the Fortress keeps its Grokkens after loading")
	var m2: Array = g2.firms.filter(func(f): return f.code == "MAGIC" and f.nation_id == p.id)
	check(not m2.is_empty() and m2[0].cast_charge == fort_charge, "the Mage Tor keeps its charge")
	var a2: Array = g2.firms.filter(func(f): return f.code == "ALCHEMY" and f.nation_id == p.id)
	check(not a2.is_empty() and a2[0].alchemy_mode == "GOLDLIVE", "the Alchemist Tor keeps its conversion")
	var n2: Array = g2.units.filter(func(u): return u.sprite_code == "F_CANNON" and not u.dead)
	check(not n2.is_empty() and n2[0].weapon_version == 2, "units keep their version")
	var ai_specials := g.firms.filter(func(f): return f.nation_id != p.id and (f.code in Defs.FRYHTAN_FIRMS or f.code == "FORTRESS")).map(func(f): return f.code)
	print("computer Fryhtan buildings: ", ai_specials)
	print("RESULT: ", "PASS" if ok else "FAIL")
	get_tree().quit()
