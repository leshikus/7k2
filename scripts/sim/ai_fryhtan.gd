class_name AIFryhtan
extends RefCounted
## A Fryhtan kingdom's lairs and special buildings thinking for themselves:
## FirmLair::process_ai (of_laira.cpp) - breeding, borrowing Fryhtans from
## other lairs, cowing linked villages into tribute, attacking camps that
## compete for them, new lairs by untamed villages, technologies and special
## structures by species (of_lara2.cpp) - and the special buildings
## (of_mtrna.cpp, of_anima.cpp, of_alcha.cpp, of_incua.cpp).

const TRIBUTE := Town.MONSTER_COLLECT_TOWN_TRIBUTE_LOYALTY
const SPECIAL_FIRMS := ["LISHORR", "WLISHORR", "BEE", "TERMITE", "ANIMAL", "ALCHEMY", "INCUBAT", "MAGIC"]

## FirmLair::think_*_buy_tech: each species' technologies and how keen it is on them
const SPECIES_TECHS := {
	"PLANT": [["LISHORR", 80], ["WLISHORR", 50], ["LISH_CAM", 50]],
	"LYW": [["FBEE", 80], ["FTERMITE", 80]],
	"HOBGLOB": [["JAGUAR", 70], ["GORILLA", 70], ["RHINOCER", 50]],
	"ROCKMAN": [["WEAPON1", 60], ["WEAPON2", 60], ["WEAPON3", 60]],
	"GREMJERM": [["MAGIC1", 90], ["MAGIC2", 30], ["MAGIC3", 50], ["MAGIC4", 30]],
	"GITH": [["FORTRESS", 50], ["FORT_CAM", 50]],
	"GIANTET": [["LIVEGOLD", 20], ["GOLDLIVE", 70], ["MINELIVE", 90], ["MINEGOLD", 60], ["ALCHEMY", 50]],
}


static func process(ai: NationAI, f: Firm, day: int) -> void:
	match f.code:
		"LAIR":
			_process_lair(ai, f, day)
		"BEE", "TERMITE":
			if day % 7 == f.obj_id % 7:
				_train_think_new(ai, f)
		"ANIMAL":
			if day % 7 == f.obj_id % 7:
				_animal_think_hire(ai, f)
		"ALCHEMY":
			_alchemy_think_conversion(ai, f)
		"INCUBAT":
			_incubator_think_production(ai, f)


# -------------------------------------------------------------- lairs ---

## FirmLair::process_ai
static func _process_lair(ai: NationAI, f: Firm, day: int) -> void:
	var id := f.obj_id
	if day % 7 == id % 7 or day == 0:
		_think_recruit(ai, f)
	if f.should_close and f.soldiers.is_empty() and f.overseer == null:
		AIFirm.del_firm(ai, f)
		return
	if day % 30 == (id + 5) % 30:
		AIFirm._think_assign_better_commander(ai, f)
	if ai.g.config.has("tutorial"):
		return
	if day % 30 == (id + 10) % 30:
		AIFirm._think_attack_nearby_enemy(ai, f)
	if day % 15 == id % 15:
		_think_attack_linked_town(ai, f)
		_think_attack_competing_camp(ai, f)
	if day % 60 == (id + 15) % 60 or day == 0:
		if not _think_repress_new_town(ai, f):
			if AIFirm.total_camp_space(ai, false) <= ai.total_unit_count():
				build_lair(ai, f, f)
	if day % 30 == (id + 20) % 30:
		_think_buy_tech(ai, f)
	if day % 45 == (id + 20) % 45:
		_think_build_special(ai, f)


## FirmLair::ai_should_close
static func should_close(ai: NationAI, f: Firm) -> bool:
	return AIFirm.total_camp_space(ai, false) >= ai.total_unit_count() + NationAI.MAX_SOLDIER \
		and f.linked_towns.is_empty() and ai.camps().size() > 1


## FirmLair::has_resisting_linked_town
static func has_resisting_town(f: Firm) -> bool:
	return f.linked_towns.any(func(t): return t.nation_id == 0 and t.resistance_to(f.nation_id) >= TRIBUTE)


## FirmLair::ai_combat_level_needed: the villages it holds, by how hostile
## the other kingdoms' buildings beside them are.
static func combat_level_needed(ai: NationAI, f: Firm) -> int:
	var need := 0
	for t in f.linked_towns:
		if t.nation_id != 0:
			continue
		for o in t.linked_firms:
			if o.nation_id > 0 and o.nation_id != GameObj.MONSTER_NATION and o.nation_id != f.nation_id:
				var st := ai.relation(o.nation_id)
				if st == Defs.Relation.WAR:
					need += t.population * 10
				elif st <= Defs.Relation.NEUTRAL:
					need += t.population * 5
	if f.overseer and f.overseer.rank == Defs.Rank.KING:
		need = maxi(400, need)
	return need


## FirmLair::think_recruit: Fryhtans from lairs with more, then breeding.
static func _think_recruit(ai: NationAI, f: Firm) -> void:
	if f.soldiers.size() + f.patrol_units.size() >= NationAI.MAX_SOLDIER:
		return
	var diff := combat_level_needed(ai, f) - AIFirm.total_combat_level(f)
	while diff > 0:
		var p := _get_soldier_from_other_lair(ai, f)
		if p <= 0:
			break
		diff -= p
	var n := ai.n
	var ut: Dictionary = Defs.unit_types.get(f.monster_code, {})
	var cost := float(ut.get("cost", 100))
	if f.soldiers.size() >= f.capacity() or n.cash < cost or n.live_points < float(ut.get("live_cost", 50)):
		return
	if f.soldiers.filter(func(s): return s.basic_days > 0).size() >= 3:
		return
	var imp := 70 * (NationAI.MAX_SOLDIER - f.soldiers.size()) / NationAI.MAX_SOLDIER + maxi(diff, 0) / 5
	for code in SPECIAL_FIRMS:
		if Defs.knows_firm(n, code) and ai.my_firms(code).is_empty():
			imp -= 40 + ai.pref("monster_special") / 4
			break
	if f.overseer:
		var add := int(f.overseer.lead_skill()) * 2 / 3
		if f.overseer.rank == Defs.Rank.KING:
			add += add / 2
		imp += add
	if ai.should_spend(imp, cost):
		f.breed()


## FirmLair::ai_get_soldier_from_other_lair: from a lair being closed, or
## one with more Fryhtans and no village to subdue. Returns its power.
static func _get_soldier_from_other_lair(ai: NationAI, f: Firm) -> int:
	var best: Firm = null
	var best_r := 0
	for o in ai.my_firms("LAIR"):
		if o == f or o.under_construction or has_resisting_town(o):
			continue
		if o.should_close:
			best = o
			break
		if o.soldiers.size() <= f.soldiers.size() + f.patrol_units.size():
			continue
		var r: int = (o.soldiers.size() - f.soldiers.size() - f.patrol_units.size()) * 10 + ai.distance_rating(f.center_loc(), o.center_loc())
		if r > best_r:
			best_r = r
			best = o
	if best == null:
		return 0
	var u: Unit = null
	if best.should_close and best.overseer and ai.g.rng.randi() % 3 == 0:
		u = best.overseer
		best.release_unit(u)
	if u == null:
		var ready: Array = best.soldiers.filter(func(s): return s.basic_days <= 0)
		if not ready.is_empty():
			u = ready[ai.g.rng.randi() % ready.size()]
			best.release_unit(u)
	if u == null:
		return 0
	u.order_enter(f)
	return int(u.obj_power())


## FirmLair::think_attack_linked_town: force a linked village to pay tribute.
static func _think_attack_linked_town(ai: NationAI, f: Firm) -> void:
	if f.overseer == null and not f.soldiers.any(func(s): return s.basic_days <= 0):
		return
	for t in f.linked_towns:
		if t.nation_id == 0 and t.resistance_to(f.nation_id) >= TRIBUTE:
			if AIAttack.attack_target(ai, t, AIFirm.possible_defender_combat_level(t, f.nation_id), false, f, true):
				return


## FirmLair::think_attack_competing_camp: camps and lairs set up after ours
## beside a village we are subduing.
static func _think_attack_competing_camp(ai: NationAI, f: Firm) -> bool:
	var best: Firm = null
	var min_r := 0xFFFF
	for t in f.linked_towns:
		if t.nation_id != 0 or t.resistance_to(f.nation_id) < TRIBUTE:
			continue
		for o in t.linked_firms:
			if o.nation_id == f.nation_id or o.nation_id <= 0 or o.nation_id == GameObj.MONSTER_NATION or o.obj_id < f.obj_id:
				continue
			var st := ai.relation(o.nation_id)
			var on := ai.g.nation(o.nation_id)
			if ai.pref("monster_aggressiveness") > 50 or st == Defs.Relation.WAR or (st <= Defs.Relation.NEUTRAL and on and not on.is_fryhtan):
				var r := Diplomacy.level(st) * 150 + AIFirm.total_combat_level(o)
				if r < min_r:
					min_r = r
					best = o
	if best:
		return AIAttack.attack_target(ai, best, AIFirm.total_combat_level(best), false, f, false, false, 0, true)
	return false


## FirmLair::think_repress_new_town: a new lair beside the nearest village no
## lair holds yet, unless enough of our lairs are still busy subduing theirs.
static func _think_repress_new_town(ai: NationAI, f: Firm) -> bool:
	if f.overseer == null or f.soldiers.size() < 1 + (0 if f.should_close else ai.pref("force_projection") / 30):
		return false
	var max_out := 2 if ai.camps().size() >= 7 - ai.pref("military_development") / 30 else 1
	var outstanding := 0
	for o in ai.my_firms("LAIR"):
		if o.under_construction or has_resisting_town(o):
			outstanding += 1
			if outstanding == max_out:
				return false
	var best: Town = null
	var best_r := -1000
	for t in ai.g.towns:
		if t.dead or t.nation_id != 0:
			continue
		if t.linked_firms.any(func(o): return o.code == "LAIR" and o.nation_id > 0):
			continue
		var r := ai.distance_rating(f.center_loc(), t.center_loc())
		r -= t.linked_firms.filter(func(o): return Espionage.is_camp(o) or o.code == "LAIR").size() * 50
		if r > best_r and ai.find_action(Vector2i(-1, -1), Vector2i(t.x1, t.y1), NationAI.BUILD_FIRM, "LAIR") == null:
			best_r = r
			best = t
	if best:
		build_lair(ai, f, best)
		return true
	return false


## FirmLair::ai_build_lair: the strongest Fryhtan is made a general and sent
## to build a lair beside the place.
static func build_lair(ai: NationAI, f: Firm, place: GameObj) -> void:
	var best: Unit = null
	for s in f.soldiers:
		if s.basic_days > 0:
			continue
		if best == null or s.hp > best.hp:
			best = s
	if best == null:
		return
	var ref := Vector2i(place.x1, place.y1)
	if ai.find_action(Vector2i(-1, -1), ref, NationAI.BUILD_FIRM, "LAIR") != null:
		return
	f.release_unit(best)
	best.rank = Defs.Rank.GENERAL
	var at := ai.find_best_place("LAIR", place)
	if at.x < 0:
		place.no_neighbor_space = true
		return
	ai.add_action(at, ref, NationAI.BUILD_FIRM, "LAIR", 1, best)


# --------------------------------------------------- technologies ---

## NationArray::update_military_rating: hit points and 20 a unit (90 more for
## a war machine), over 50.
static func military_rating(ai: NationAI) -> int:
	var pts := 0.0
	for u in ai.g.units:
		if u.nation_id == ai.n.id and not u.dead:
			pts += u.hp + (90.0 if u.is_weapon else 0.0) + 20.0
	return int(pts / 50.0)


## FirmLair::think_buy_tech / think_tech_to_buy: the species' techs, starting
## at a random one, bought when strong enough or with life points to spare.
static func _think_buy_tech(ai: NationAI, f: Firm) -> String:
	var list: Array = SPECIES_TECHS.get(SpecialFirms.lair_species(f), [])
	if list.is_empty():
		return ""
	var total := 0
	for e in list:
		total += ai.n.tech_level(e[0])
	var seq := ai.g.rng.randi() % list.size()
	var mil := military_rating(ai)
	for i in list.size():
		seq = (seq + 1) % list.size()
		var code: String = list[seq][0]
		var keen: int = list[seq][1]
		var t := Defs.tech_def(code)
		if t.is_empty():
			continue
		var excess := 1000 + total * 100 - keen * 4
		var spare := ai.n.live_points > Defs.fryhtan_tech_live_cost(t) + excess * (75 + ai.pref("live_points_reserve") / 2) / 100.0
		if mil + ai.pref("monster_special") / 10 + keen / 5 > 40 + total * 10 or spare:
			if SpecialFirms.can_buy_tech(f, t):
				SpecialFirms.buy_tech(f, code)
				return code
	return ""


# ----------------------------------------------- special structures ---

## FirmLair::should_build_special
static func _should_build_special(ai: NationAI, code: String) -> bool:
	if not Defs.knows_firm(ai.n, code) or not ai.can_ai_build(code):
		return false
	var count := ai.my_firms(code).size()
	if count == 0:
		return true
	return ai.should_spend(40 + ai.pref("monster_special") / 5 - count * 10, float(Defs.firm_types.get(code, {}).get("cost", 0)))


## FirmLair::think_build_special: one queued at a time, by species.
static func _think_build_special(ai: NationAI, f: Firm) -> void:
	if ai.actions.any(func(a): return a["mode"] == NationAI.BUILD_FIRM and str(a["para"]) in SPECIAL_FIRMS):
		return
	var fai := ai as FryhtanAI
	match SpecialFirms.lair_species(f):
		"PLANT":
			if not _should_build_special(ai, "LISHORR"):
				return
			for o in ai.my_firms():
				if o.code == "LISHORR":
					continue
				var net: int = AICapture.net_attacker_power_in_area(ai.g, o.center_loc(), ai.n.id, 0, false, 8)[0]
				if net < fai.last_lishorr_power:
					if AIFirm.build_neighbor_firm(ai, o, "LISHORR"):
						fai.last_lishorr_power = net
						return
			fai.last_lishorr_power += 100
		"LYW":
			var code := "BEE" if ai.g.rng.randi() % 2 == 0 else "TERMITE"
			if not _should_build_special(ai, code):
				return
			# a hive or mound still idle is used before another is built
			if ai.my_firms(code).any(func(o): return o.weapon == ""):
				return
			AIFirm.build_neighbor_firm(ai, f, code)
		"HOBGLOB":
			if not _should_build_special(ai, "ANIMAL"):
				return
			if ai.my_firms("ANIMAL").any(func(o): return o.animals.size() >= 2):
				return
			AIFirm.build_neighbor_firm(ai, f, "ANIMAL")
		"GIANTET":
			# on a raw material site first (the original's tech check always passes)
			var s := ai._seek_mine()
			if s and not ai.action_exists(NationAI.BUILD_FIRM, "ALCHEMY"):
				ai.add_action(Vector2i(s.x1, s.y1), Vector2i(s.x1, s.y1), NationAI.BUILD_FIRM, "ALCHEMY")
				return
			if not _should_build_special(ai, "ALCHEMY"):
				return
			if ai.my_firms("ALCHEMY").any(func(o): return o.last_month_output + o.month_output < 10.0):
				return
			AIFirm.build_neighbor_firm(ai, f, "ALCHEMY")
		"ROCKMAN":
			if not _should_build_special(ai, "INCUBAT"):
				return
			if ai.my_firms("INCUBAT").any(func(o): return o.weapon == ""):
				return
			AIFirm.build_neighbor_firm(ai, f, "INCUBAT")
		"GREMJERM":
			if not _should_build_special(ai, "MAGIC"):
				return
			if ai.my_firms("MAGIC").any(func(o): return o.cast_charge >= Defs.MAX_CAST_DELAY):
				return
			AIFirm.build_neighbor_firm(ai, f, "MAGIC")
		# "GITH": think_build_grokken_special builds nothing


# ------------------------------------------------ special buildings ---

## FirmMonsterTrain::think_train_new: its first kind of unit, while there is money.
static func _train_think_new(ai: NationAI, f: Firm) -> void:
	var kinds := SpecialFirms.buildable_units(f)
	if kinds.is_empty() or f.weapon_queue >= 3:
		return
	var unit: String = kinds[0]
	var price := SpecialFirms.unit_price(unit)
	var total := maxi(1, ai.total_unit_count())
	var have := ai.g.units.filter(func(u): return u.nation_id == ai.n.id and not u.dead and u.sprite_code == unit).size()
	var pct := 100 * have / total if have > 0 else 0
	if not ai.should_spend(80 - pct, price[0]) or ai.n.cash <= 0.0:
		return
	if f.weapon != "" and f.weapon != unit:
		return
	f.queue_weapon(unit)


## FirmAnimal::think_hire_new
static func _animal_think_hire(ai: NationAI, f: Firm) -> void:
	if AIFirm.total_camp_space(ai, true) < 5 - 4 * ai.pref("military_development") / 100:
		return
	if not ai.should_spend(60 + ai.pref("monster_special") / 3):
		return
	var imp := 40 + ai.pref("monster_special") / 4
	for i in f.animals.size():
		if not SpecialFirms.can_hire_animal(f, i):
			continue
		if ai.should_spend(imp, float(f.animals[i]["cost"])):
			SpecialFirms.hire_animal(f, i)
			return


## FirmMonsterAlchemy::think_change_conversion (the life-to-gold branch sets
## gold-to-life, as in the original)
static func _alchemy_think_conversion(ai: NationAI, f: Firm) -> void:
	var n := ai.n
	var mode := f.alchemy_mode
	if f.site != null and f.reserve > 0.0:
		if n.tech_level("MINELIVE") > 0 and n.cash > n.live_points + 500 + ai.pref("cash_reserve") * 2:
			mode = "MINELIVE"
		if n.tech_level("MINEGOLD") > 0 and n.live_points > n.cash + 500 + ai.pref("live_points_reserve") * 2:
			mode = "MINEGOLD"
	elif n.live_points < ai.pref("live_points_reserve") * 5 and n.cash > 1500 + ai.pref("cash_reserve") * 10:
		if n.tech_level("GOLDLIVE") > 0:
			mode = "GOLDLIVE"
	elif n.cash < ai.pref("cash_reserve") * 5 and n.live_points > 2500 + ai.pref("live_points_reserve") * 10:
		if n.tech_level("LIVEGOLD") > 0:
			mode = "GOLDLIVE"
	else:
		mode = ""
	if mode == "" or SpecialFirms.can_convert(f, mode):
		f.alchemy_mode = mode


## FirmIncubator::think_new_production: the machine we have fewest of, newer first.
static func _incubator_think_production(ai: NationAI, f: Firm) -> void:
	if f.weapon_queue >= 3:
		return
	if AIFirm.total_camp_space(ai, true) < 5 - 4 * ai.pref("military_development") / 100:
		return
	if not ai.should_spend(65 + ai.pref("use_weapon") / 4):
		return
	var kinds := SpecialFirms.buildable_units(f)
	if kinds.is_empty():
		return
	var count := {}
	var total := 0
	for k in kinds:
		count[k] = ai.g.units.filter(func(u): return u.nation_id == ai.n.id and not u.dead and u.sprite_code == k).size()
		total += count[k]
	var avg: int = total / kinds.size()
	var best := ""
	var best_r := 0
	for k in kinds:
		var r: int = avg - int(count[k]) + ai.n.tech_level(Defs.unit_tech(k)) * 3
		if r > best_r:
			best_r = r
			best = k
	if best != "" and (f.weapon == "" or f.weapon == best):
		f.queue_weapon(best)
