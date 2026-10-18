class_name AIAttack
extends RefCounted
## Attack missions (oai_attk.cpp): camps that can be spared - not linked to
## towns, or more than their towns need - are picked, enough of them to beat
## the target with the projection the kingdom prefers; the furthest set out
## first so all arrive together; the neighbouring places of the same kingdom
## are the next targets. Secret attack plans against kingdoms we may betray.

const MAX_SUITABLE_TOWN_CAMP := 10


## Nation::ai_attack_target. Returns whether troops were sent (the original
## returns the combat level sent).
static func attack_target(ai: NationAI, target: GameObj, level: int, defense := false, lead: Firm = null,
		use_all := false, just_move := false, min_attacker_level := 0, retain := false) -> bool:
	return _attack(ai, target, target.center_loc() if target else Vector2.ZERO, level, defense, just_move, min_attacker_level, lead, use_all, retain) > 0


## ai_attack_target given a place rather than an object (just move there).
static func attack_at(ai: NationAI, at: Vector2, level: int, just_move := true) -> bool:
	var obj: GameObj = ai.g.world.object_at(Vector2i(at)) as GameObj
	if obj == null:
		for u in ai.g.units_near(at, 3.0):
			if not u.dead and u.nation_id != ai.n.id:
				obj = u
				break
	if obj == null:
		return false
	return _attack(ai, obj, at, level, false, just_move, 0, null, false, false) > 0


static func _attack(ai: NationAI, target: GameObj, at: Vector2, level: int, defense: bool, just_move: bool,
		min_attacker_level: int, lead: Firm, use_all: bool, retain: bool) -> int:
	var g := ai.g
	if target == null or not is_instance_valid(target) or target.dead:
		return 0
	# campaign battles at low difficulty hold back their first attacks
	if not defense and g.campaign_battle != null:
		var diff := int(g.config.get("campaign_difficulty", 3))
		var months := g.day / 30
		if (diff == 1 and months < 12) or (diff == 2 and months < 6) or (diff == 3 and months < 3):
			return 0
	var tnid := target.nation_id
	if tnid > 0 and g.day < int(ai.n.never_until.get("DECLARE_WAR:%d" % tnid, -1)):
		return 0
	if defense:
		use_all = true
		var original := level
		level = _order_nearby_mobile(ai, target, level)
		if level < 0:
			return original - level
	var max_level := level * (150 + ai.pref("force_projection") / 2) / 100
	var tn := g.nation(tnid) if tnid > 0 else null
	if tn and not tn.is_ai and ai._aggressiveness() >= GameSetup.MODERATE:
		max_level += max_level * (ai._aggressiveness() - GameSetup.MODERATE + 1) / 3
	var min_level := level
	if not retain:
		min_level = level * (100 - ai.pref("military_courage") / 2) / 100 if defense else level * (125 + ai.pref("force_projection") / 4) / 100
	if not ai.attack_camps.is_empty():
		return 0
	_set_targets(ai, target, defense)
	ai.attack_camps.clear()
	ai.lead_attack_camp = lead
	if lead:
		ai.attack_camps.append({"firm": lead, "combat": AIFirm.total_combat_level(lead), "distance": 0, "patrol_day": 0})
	# the king stays home with few camps, when hurt, or without a full troop
	var king_firm: Firm = null
	var king := ai.n.king
	if king and is_instance_valid(king) and not king.dead and king.inside_firm and king.inside_firm.overseer == king:
		var kf: Firm = king.inside_firm
		var keep := false
		if ai.camps().size() > 3 + (100 - ai.pref("military_courage")) / 20:
			keep = true
		elif king.hp < 230 - ai.pref("military_courage"):
			keep = true
		elif kf.soldiers.size() < NationAI.MAX_SOLDIER:
			keep = true
		if keep:
			king_firm = kf
			if king.hp >= 150 - ai.pref("military_courage") / 4 and kf.soldiers.size() == NationAI.MAX_SOLDIER:
				if _dist(kf.center_loc(), at) <= Defs.effective_distance(kf.code, ""):
					king_firm = null
	var camps := ai.camps()
	for c in camps:
		if c.overseer == null or c.soldiers.is_empty() or not c.patrol_units.is_empty() or c.ai_capture_town or c.is_attack_camp:
			continue
		if c == king_firm and camps.size() > 1 and not use_all:
			continue
		var o: Unit = c.overseer
		if o.hp < o.max_hp and o.hp < 100 - ai.pref("military_courage") / 2:
			continue
		if min_attacker_level > 0 and _average_combat(c) < min_attacker_level:
			continue
		if use_all or c.code == "LAIR" or c.linked_towns.is_empty():
			_add_camp(ai, c)
	# camps more than their towns need
	if not use_all:
		for t in ai.my_towns():
			var need := AITown.protection_needed(t)
			var town_camps: Array = []
			var total := 0
			for f in t.linked_firms:
				if f.nation_id != ai.n.id or f == king_firm:
					continue
				if Espionage.is_camp(f):
					if f.overseer == null and f.soldiers.is_empty():
						continue
					if not f.patrol_units.is_empty() or f.ai_capture_town or f.is_attack_camp:
						continue
					var lvl := AIFirm.total_combat_level(f)
					total += lvl
					if town_camps.size() < MAX_SUITABLE_TOWN_CAMP:
						town_camps.append({"firm": f, "combat": lvl, "distance": 0, "patrol_day": 0})
				elif f.code == "MARKET":
					need += AIFirm.stock_value_index(f)
				elif f.is_work_firm():
					need += int(f.productivity())
			if total > need:
				for tc in town_camps:
					if total - tc["combat"] > need and ai.attack_camps.size() < NationAI.MAX_SUITABLE_ATTACK_CAMP:
						if not ai.attack_camps.any(func(a): return a["firm"] == tc["firm"]):
							ai.attack_camps.append(tc)
							total -= tc["combat"]
	if ai.attack_camps.is_empty():
		return 0
	var total := 0
	for a in ai.attack_camps:
		total += a["combat"]
	if total < min_level:
		ai.attack_camps.clear()
		return 0
	for a in ai.attack_camps:
		a["distance"] = int(_dist(a["firm"].center_loc(), at))
	ai.attack_camps.sort_custom(func(a, b): return a["combat"] - a["distance"] > b["combat"] - b["distance"])
	for i in range(ai.attack_camps.size() - 1, -1, -1):
		if total - ai.attack_camps[i]["combat"] > max_level:
			total -= ai.attack_camps[i]["combat"]
			ai.attack_camps.remove_at(i)
	_sync(ai)
	execute(ai, not just_move)
	return total


static func _dist(a: Vector2, b: Vector2) -> float:
	return maxf(absf(a.x - b.x), absf(a.y - b.y))


static func _average_combat(c: Firm) -> int:
	var n := c.soldiers.size() + (1 if c.overseer else 0)
	return AIFirm.total_combat_level(c) / n if n > 0 else 0


static func _add_camp(ai: NationAI, c: Firm) -> void:
	if ai.attack_camps.any(func(a): return a["firm"] == c):
		return
	if ai.attack_camps.size() < NationAI.MAX_SUITABLE_ATTACK_CAMP:
		ai.attack_camps.append({"firm": c, "combat": AIFirm.total_combat_level(c), "distance": 0, "patrol_day": 0})


## Nation::set_ai_attack_target: the target and, unless defending, the places
## of the same kingdom within 15 around it, nearest first.
static func _set_targets(ai: NationAI, target: GameObj, defense: bool) -> void:
	ai.attack_targets = [target]
	ai.attack_target_nation = target.nation_id
	if defense:
		return
	var c := target.center_loc()
	var scan := 15.0
	var found: Array = []
	for o in ai.g.firms + ai.g.towns:
		if o == target or o.dead or o.nation_id != target.nation_id:
			continue
		var d := _dist(o.center_loc(), c)
		if d <= scan:
			found.append([d, o])
	for u in ai.g.units_near(c, scan):
		if u != target and not u.dead and u.inside_firm == null and u.nation_id == target.nation_id and _dist(u.center_loc(), c) <= scan:
			found.append([_dist(u.center_loc(), c), u])
	found.sort_custom(func(a, b): return a[0] < b[0])
	for f in found:
		if ai.attack_targets.size() >= NationAI.MAX_AI_ATTACK_TARGET:
			break
		ai.attack_targets.append(f[1])


## Nation::ai_attack_order_nearby_mobile: our idle soldiers around join in;
## returns the defence they leave for the camps.
static func _order_nearby_mobile(ai: NationAI, target: GameObj, level: int) -> int:
	var scan := 15 + ai.pref("military_development") / 20
	var c := target.center_loc()
	var near: Array = []
	for u in ai.g.units_near(c, float(scan)):
		if u.dead or u.nation_id != ai.n.id or u.is_civilian() or u.inside_firm != null or not u.can_attack():
			continue
		if _dist(u.center_loc(), c) > scan or _dist(u.center_loc(), c) < 1.0:
			continue
		near.append(u)
	near.sort_custom(func(a, b): return _dist(a.center_loc(), c) < _dist(b.center_loc(), c))
	for u in near:
		if u.hp < u.max_hp * (150 - ai.pref("military_courage") / 2) / 200.0:
			continue
		if u.ai_action_id > 0:
			continue
		if u.order == Unit.Order.IDLE or u.order == Unit.Order.ENTER:
			u.order_attack(target)
			level -= int(u.hp)
			if level <= 0:
				break
	return level


## Nation::ai_attack_target_sync: the further camps start first.
static func _sync(ai: NationAI) -> void:
	var max_d := 0
	for a in ai.attack_camps:
		max_d = maxi(max_d, a["distance"])
	# SpriteInfo::travel_days: of the kingdom's basic soldier, plus 10%
	var code := Defs.unit_sprite(ai.n.race, "INF") if not ai.n.is_fryhtan else ai.n.monster_code
	var spd := maxf(1.0, float(Assets.sprites.get(code, {}).get("speed", 4)))
	var max_days := int(Defs.LOC * max_d / spd) / Defs.FRAMES_PER_DAY * 110 / 100
	for a in ai.attack_camps:
		var travel: int = max_days * int(a["distance"]) / maxi(1, max_d)
		a["patrol_day"] = ai.g.day + (max_days - travel)
		a["firm"].is_attack_camp = true


## Nation::ai_attack_target_execute: camps whose day has come send their men.
static func execute(ai: NationAI, direct: bool) -> void:
	while not ai.attack_targets.is_empty():
		var t = ai.attack_targets[0]
		if t != null and is_instance_valid(t) and not t.dead and t.nation_id == ai.attack_target_nation:
			break
		ai.attack_targets.remove_at(0)
	if ai.attack_targets.is_empty():
		reset(ai)
		return
	var target: GameObj = ai.attack_targets[0]
	for i in range(ai.attack_camps.size() - 1, -1, -1):
		var a: Dictionary = ai.attack_camps[i]
		if ai.g.day < a["patrol_day"]:
			continue
		var c: Firm = a["firm"]
		if is_instance_valid(c) and not c.dead and (c.overseer or not c.soldiers.is_empty()):
			var out: Array
			if c == ai.lead_attack_camp and c.overseer and c.overseer.is_human():
				out = c.patrol(Firm.PATROL_NO_GENERAL)      # the leading camp's commander stays to win the town over
			else:
				out = c.patrol(Firm.PATROL_ALL)
			c.patrol_units = out.duplicate()
			if not out.is_empty():
				if ai.attack_target_nation > 0:
					Diplomacy._ai_send(ai.g, ai.n, ai.attack_target_nation, "DECLARE_WAR")
				if not direct:
					ai.g.move_troop(out, Vector2i(target.center_loc()))
				else:
					if target.nation_id > 0 and ai.relation(target.nation_id) != Defs.Relation.WAR:
						ai.g.declare_war(ai.n.id, target.nation_id)
					for u in out:
						u.order_attack(target)
						u.in_attack_mission = true
		if is_instance_valid(c):
			c.is_attack_camp = false
		ai.attack_camps.remove_at(i)


## Nation::reset_ai_attack_target
static func reset(ai: NationAI) -> void:
	for a in ai.attack_camps:
		if is_instance_valid(a["firm"]):
			a["firm"].is_attack_camp = false
	ai.attack_camps.clear()


## Nation::think_secret_attack: pick a kingdom to turn on - weaker, little
## trade, little goodwill - more readily the human player.
static func think_secret_attack(ai: NationAI) -> bool:
	if ai.pref("peacefulness") >= 80:
		return false
	var enemy := Diplomacy._enemy_military(ai.g, ai.n)
	if enemy > 20 + ai.pref("military_courage") - ai.pref("peacefulness"):
		return false
	var best := 0
	var best_r := 0
	var ours := ai.military_rank()
	for o in ai.g.nations:
		if not o.alive or o == ai.n:
			continue
		var trade := Diplomacy.trade_rating(ai.g, ai.n, o) / 2 + Diplomacy.trade_with_rating(ai.g, ai.n, o) / 2
		var on: bool = ai.secret_attack.has(o.id)
		if not on:
			var st := ai.relation(o.id)
			if st == Defs.Relation.PEACE:
				if enemy > 0:
					continue
			elif st == Defs.Relation.ALLIANCE:
				continue
			if trade > 50 - ai.pref("trading_tendency") / 2:
				continue
		var r := (ours - Diplomacy.military_rank(ai.g, o)) * 2 + (ai.overall_rank() - 50) - trade * 2 \
			- Diplomacy.ai_rel(ai.n, o.id) / 2 - ai.pref("peacefulness") / 2
		if not o.is_ai:
			match ai._aggressiveness():
				GameSetup.MODERATE:
					r += 100
				GameSetup.HIGH:
					r += 300
				GameSetup.VERY_HIGH:
					r += 500
		if on and r < 0:
			ai.secret_attack.erase(o.id)
			continue
		if r > best_r:
			best_r = r
			best = o.id
	if best > 0:
		ai.secret_attack[best] = true
		return true
	return false
