class_name AIFirm
extends RefCounted
## A computer kingdom's buildings thinking for themselves (ofirmai.cpp and the
## of_*a.cpp files): closing and repairing (Firm::process_common_ai); camps
## recruiting, capturing towns, fending off invaders and choosing their
## commander (of_campa.cpp); work places keeping their workforce (of_worka.cpp);
## mines and factories building the next link of the chain; markets importing
## goods by caravan; towers, war factories, inns and Seats of Power.

const MIN_NATION_DEFEND_LOYALTY := 30
const MIN_INDEPENDENT_DEFEND_LOYALTY := 30
const MIN_FACTORY_IMPORT_STOCK_QTY := 20.0
const MAX_STOCK := Economy.MAX_STOCK
const CAPTURE_INTERVAL := [250, 60, 30, 20, 10]


static func process(ai: NationAI, f: Firm, day: int) -> void:
	_process_common(ai, f, day)
	if f.dead:
		return
	if f.code in ["LAIR", "BEE", "TERMITE", "ANIMAL", "ALCHEMY", "INCUBAT"]:
		AIFryhtan.process(ai, f, day)        # of_laira.cpp and the Fryhtan buildings
		return
	if ai.g.config.has("tutorial"):
		return
	match f.code:
		"FORT":
			_think_train_archer(ai, f)       # FirmFort::process_ai
			_process_camp(ai, f, day)
		"CAMP":
			_process_camp(ai, f, day)
		"MINE":
			_process_mine(ai, f, day)
		"FACTORY":
			_process_factory(ai, f, day)
		"MARKET":
			_process_market(ai, f, day)
		"RESEARCH":
			if day % 30 == f.obj_id % 30 and _research_think_del(ai, f):
				return
			_process_work(ai, f, day)
		"WAR":
			if f.weapon == "":
				_war_think_new_production(ai, f)
			if day % 30 == f.obj_id % 30 and _work_think_del(f):
				return
			_process_work(ai, f, day)
		"INN":
			if day % 30 == f.obj_id % 30:
				if _inn_think_del(ai, f):
					return
				_inn_think_hire_spy(ai, f)
				_inn_think_hire_general(ai, f)
		"STABLE", "SPY":
			Training.process_ai(f, ai, day)        # FirmTrain/FirmSpy::process_ai (training.gd)
		"BASE":
			# FirmBase::think_invoke_god: as soon as the prayers are full
			if ai.n.prayer_points >= Wishes.FULL and f.god_cost() <= ai.n.prayer_points:
				f.invoke_god()
			_process_work(ai, f, day)


# ------------------------------------------------------------ common ---

## Firm::process_common_ai
static func _process_common(ai: NationAI, f: Firm, day: int) -> void:
	if not f.should_close and day % 15 == f.obj_id % 15 and _should_close(ai, f):
		f.should_close = true
	if f.hp < f.max_hp and not f.should_close and not f.repair and ai.should_spend(50 + ai.pref("repair_concern") / 2):
		f.set_repair(true)


static func _should_close(ai: NationAI, f: Firm) -> bool:
	if f.code == "LAIR":
		return AIFryhtan.should_close(ai, f)
	if Espionage.is_camp(f):
		# FirmCamp::ai_should_close
		return f.linked_towns.is_empty() and f.linked_firms.is_empty() \
			and total_camp_space(ai, false) >= ai.total_unit_count() + NationAI.MAX_SOLDIER
	return false


## Firm::ai_del_firm: cancel, sell or pull it down.
static func del_firm(ai: NationAI, f: Firm) -> void:
	if f.dead:
		return
	if f.under_construction:
		f.cancel_construction()
	elif f.can_sell():
		f.sell_firm()
	else:
		f.die(null)


## Nation::total_camp_unit_space
static func total_camp_space(ai: NationAI, free_only: bool) -> int:
	var space := 0
	for c in ai.camps():
		space += (NationAI.MAX_SOLDIER - c.soldiers.size()) if free_only else NationAI.MAX_SOLDIER
	return space


## Firm::ai_build_neighbor_firm
static func build_neighbor_firm(ai: NationAI, f: Firm, code: String) -> bool:
	var at := ai.find_best_place(code, f)
	if at.x < 0:
		f.no_neighbor_space = true
		return false
	return not ai.add_action(at, Vector2i(f.x1, f.y1), NationAI.BUILD_FIRM, code).is_empty()


# ------------------------------------------------------- measurements ---

## FirmCamp::total_combat_level: soldiers' hit points (war machines add their
## power), lifted by the commander's leadership, plus his own.
static func total_combat_level(f: Firm) -> int:
	if not Espionage.is_camp(f) and f.code != "LAIR":
		if f.code.ends_with("LISHORR") or f.code == "OFFENSIV":
			return int(f.hp) * 2
		return 0
	var total := 0
	for s in f.soldiers:
		if s.basic_days > 0:
			continue
		total += int(s.hp)
		if s.is_weapon:
			total += (int(s.utype.get("weapon_power", 0)) + maxi(0, s.weapon_version - 1)) * 30
	if f.overseer:
		total += total * int(f.overseer.lead_skill()) / 150
		total += int(f.overseer.hp)
	return total


## Place::obj_power
static func obj_power(o: GameObj) -> int:
	if o is Unit:
		return int((o as Unit).obj_power())
	if o is Town:
		return possible_defender_combat_level(o, 0)
	if o is Firm:
		return total_combat_level(o)
	return 0


## FirmCamp::ai_combat_level_needed: 10 a villager of its own towns, double for base towns; 400 with the king.
static func combat_level_needed(ai: NationAI, f: Firm) -> int:
	var need := 0
	for t in f.linked_towns:
		if t.nation_id != f.nation_id or AITown.should_migrate(ai, t):
			continue
		need += t.population * 10
		if t.is_base_town:
			need += t.population * 10
	if f.overseer and f.overseer.rank == Defs.Rank.KING:
		need = maxi(400, need)
	return need


## Town::possible_defender_combat_level
static func possible_defender_combat_level(t: Town, attacker: int) -> int:
	var diff := 0.0
	if t.nation_id > 0:
		diff = t.loyalty - MIN_NATION_DEFEND_LOYALTY
	elif attacker > 0:
		diff = t.resistance_to(attacker) - MIN_INDEPENDENT_DEFEND_LOYALTY
	var total := 0
	if diff >= 0.0:
		var defenders := int(diff / 3.0) + 1
		total += t.town_combat_level * 2 * defenders
		total += int(t.wall_hp) * 4
	if t.nation_id > 0:
		for f in t.linked_firms:
			if f.nation_id == t.nation_id and Espionage.is_camp(f):
				total += total_combat_level(f)
	return total


## FirmCamp::majority_race: the commander's race, else the race most of its men are.
static func majority_race(f: Firm) -> String:
	if f.overseer:
		return f.overseer.race
	var count := {}
	for s in f.soldiers:
		count[s.race] = int(count.get(s.race, 0)) + 1
	var best := ""
	var best_c := 0
	for r in count:
		if count[r] > best_c:
			best_c = count[r]
			best = r
	if best == "":
		var n := f.nation()
		best = n.race if n and not n.is_fryhtan else ""
	return best


## FirmMarket::stock_value_index: how full the market is, 0..100.
static func stock_value_index(f: Firm) -> int:
	var total := 0.0
	var slots := 0
	for k in f.goods:
		total += float(f.goods[k])
		slots += 1
	for k in f.raws:
		total += float(f.raws[k])
		slots += 1
	if slots == 0:
		return 0
	return int(100.0 * total / (MAX_STOCK * slots))


## Town::closest_own_camp
static func closest_own_camp(t: Town) -> Firm:
	var best: Firm = null
	var best_d := 1000.0
	for f in t.linked_firms:
		if f.nation_id != t.nation_id or not Espionage.is_camp(f):
			continue
		var d := maxf(absf(t.center_loc().x - f.center_loc().x), absf(t.center_loc().y - f.center_loc().y))
		if d < best_d:
			best_d = d
			best = f
	return best


## Town::is_pay_tribute_to_monster
static func pays_tribute(t: Town) -> bool:
	var to := t.tribute_to()
	var n := Game.inst.nation(to) if to > 0 else null
	return n != null and n.is_fryhtan


## Town::can_grant_to_non_own_town
static func can_grant_foreign(t: Town, nid: int) -> bool:
	if t.nation_id == nid:
		return false
	var n := Game.inst.nation(nid)
	if n == null or n.is_fryhtan:
		return false
	if t.nation_id == 0:
		return _has_led_camp(t, nid)
	return not t.has_linked_camp(t.nation_id) and _has_led_camp(t, nid)


static func _has_led_camp(t: Town, nid: int) -> bool:
	return t.linked_firms.any(func(f): return f.nation_id == nid and Espionage.is_camp(f) and f.overseer != null and not f.under_construction)


# -------------------------------------------------------------- camps ---

## FirmCamp::process_ai
static func _process_camp(ai: NationAI, f: Firm, day: int) -> void:
	var id := f.obj_id
	_prune_patrol(f)
	if day % 30 == (id + 5) % 30:
		_think_employ_to_capture(ai, f)
	if day % 15 == (id + 10) % 15:
		_think_use_cash_to_capture(ai, f)
	if day % 15 == id % 15:
		_think_recruit(ai, f)
	if f.ai_capture_town:
		f.should_close = false
		if ai.attack_camps.is_empty() and f.patrol_units.is_empty():
			f.ai_capture_town = null
			return
		_process_capturing(ai, f)
		return
	if f.should_close:
		if f.soldiers.is_empty():
			del_firm(ai, f)
			return
	if day % 30 == id % 30:
		_think_assign_better_commander(ai, f)
		_think_change_town_link(ai, f)
	var interval := 13 - ai.pref("military_development") / 10
	if day % interval == id % interval:
		_think_attack_invader(ai, f)
	if day % 30 == id % 30:
		_think_attack_nearby_enemy(ai, f)
	var cap_interval: int = CAPTURE_INTERVAL[clampi(ai._aggressiveness(), 0, 4)]
	if day % cap_interval == id % cap_interval:
		_think_capture(ai, f)
	if day % cap_interval == (id + 5) % cap_interval:
		_think_attack_enslaving_monster(ai, f)


static func _prune_patrol(f: Firm) -> void:
	f.patrol_units = f.patrol_units.filter(func(u): return is_instance_valid(u) and not u.dead and u.inside_firm == null and u.nation_id == f.nation_id)


## FirmCamp::patrol for the computer: everyone out, remembered as the patrol.
static func patrol(f: Firm) -> Array:
	var out := f.patrol(Firm.PATROL_ALL)
	f.patrol_units = out.duplicate()
	return out


## FirmCamp::process_ai_capturing
static func _process_capturing(ai: NationAI, f: Firm) -> void:
	var t: Town = f.ai_capture_town
	if t == null or not is_instance_valid(t) or t.dead or t.nation_id == f.nation_id:
		# think_capture_return
		for u in f.patrol_units:
			u.order_enter(f)
		f.ai_capture_town = null
		return
	if f.patrol_units.is_empty():
		return
	var live_defenders: Array = t.defenders.filter(func(d): return is_instance_valid(d) and not d.dead)
	if not live_defenders.is_empty():
		for u in f.patrol_units:
			if u.order == Unit.Order.IDLE or (u.order == Unit.Order.ATTACK and u.target == t):
				u.order_attack(live_defenders[ai.g.rng.randi() % live_defenders.size()])
	else:
		var u: Unit = f.patrol_units[ai.g.rng.randi() % f.patrol_units.size()]
		u.order_attack(t)


## FirmCamp::think_recruit
static func _think_recruit(ai: NationAI, f: Firm) -> void:
	if not f.patrol_units.is_empty():
		return
	f.ai_recruiting = true
	if not f.coming_units.is_empty():
		for u in f.coming_units:
			if is_instance_valid(u) and not u.dead and u.nation_id == f.nation_id and u.order == Unit.Order.ENTER:
				return
		f.coming_units.clear()
	# an empty camp takes over the troop of a camp the kingdom is closing
	if f.overseer == null and f.soldiers.is_empty():
		var best: Firm = null
		var best_r := 0
		for c in ai.camps():
			if c != f and c.should_close and (c.overseer or not c.soldiers.is_empty()):
				var r := 100 - int(maxf(absf(f.center_loc().x - c.center_loc().x), absf(f.center_loc().y - c.center_loc().y)))
				if r > best_r:
					best_r = r
					best = c
		if best:
			var out := best.patrol(Firm.PATROL_ALL)
			if out.is_empty():
				return
			f.coming_units = out.duplicate()
			for u in out:
				u.order_enter(f)
			del_firm(ai, best)
			return
	if f.overseer == null:
		ai.add_action(Vector2i(f.x1, f.y1), Vector2i(-1, -1), NationAI.ASSIGN_OVERSEER, "FORT")
	var recruit := (combat_level_needed(ai, f) - total_combat_level(f)) / 50
	var extra := 0
	if ai.has_enough_food():
		extra += ai.total_jobless() - (20 + (100 - ai.pref("military_development")) / 3)
		if f.overseer:
			extra += int(f.overseer.lead_skill()) / 10
	if f.overseer and f.overseer == ai.n.king:
		extra = maxi(0, extra + 10)
	extra = maxi(extra, -NationAI.MAX_SOLDIER)
	recruit += extra if extra > 0 else extra / 2
	if recruit > 0:
		ai_recruit(ai, f, recruit)
	elif f.overseer:
		f.ai_recruiting = false


## FirmFort::think_train_archer
static func _think_train_archer(ai: NationAI, f: Firm) -> bool:
	if f.target_archers > f.archers:
		return false
	var imp := ai.pref("military_development") / 3 + (combat_level_needed(ai, f) - total_combat_level(f)) / 10
	if not ai.should_spend(imp, Firm.TRAIN_ARCHER_COST):
		return false
	if f.target_archers == f.archers and f.target_archers < Firm.MAX_FORT_ARCHER:
		f.set_target_archers(-1)
		return true
	return false


## Nation::not_enough_food_index: 0..100, how serious the lack of food is.
static func not_enough_food_index(ai: NationAI) -> int:
	if ai.has_enough_food():
		return 0
	return mini(100, int(100.0 * -ai.yearly_food_change() / maxf(1.0, ai.n.food)))


## FirmFort::ai_recruit: two at a time from the linked towns (its own race
## first, rewarding a disloyal town first), the rest from elsewhere.
static func _fort_recruit(ai: NationAI, f: Firm, count: int) -> bool:
	if f.soldiers.size() + f.patrol_units.size() >= NationAI.MAX_SOLDIER or count == 0:
		return false
	if f.soldiers.filter(func(s): return s.basic_days > 0).size() >= 2:
		return false
	if not ai.has_enough_food():
		count = count * (100 - not_enough_food_index(ai)) / 100
		if count < 1:
			return false
	count = mini(mini(count, NationAI.MAX_SOLDIER - f.soldiers.size() - f.patrol_units.size()), 2)
	if ai.n.cash > 0.0:
		for loop in [1, 2]:
			for t in f.linked_towns:
				if t.nation_id != f.nation_id or (loop == 1 and t.race != f.race) or t.jobless() == 0:
					continue
				if t.loyalty < 40:
					if t.grant_penalty > 30:
						break
					t.grant(t.nation_id)
				while t.can_recruit():
					if t.draft_into(f) == null:
						break
					count -= 1
					if count == 0:
						return true
	if count > 0:
		ai.add_action(Vector2i(f.x1, f.y1), Vector2i(-1, -1), NationAI.ASSIGN_SOLDIER, "CAMP", count)
	return true


## FirmCamp::ai_recruit
static func ai_recruit(ai: NationAI, f: Firm, count: int) -> bool:
	if f.code == "FORT":
		return _fort_recruit(ai, f, count)
	if f.soldiers.size() + f.patrol_units.size() >= NationAI.MAX_SOLDIER or count == 0:
		return false
	count = mini(count, NationAI.MAX_SOLDIER - f.soldiers.size() - f.patrol_units.size())
	if count > 0:
		ai.add_action(Vector2i(f.x1, f.y1), Vector2i(-1, -1), NationAI.ASSIGN_SOLDIER, f.code, count)
	return true


## FirmCamp::think_capture
static func _think_capture(ai: NationAI, f: Firm) -> void:
	if f.is_attack_camp:
		return
	var t := _think_capture_target_town(ai, f)
	if t == null:
		return
	if t.nation_id > 0 and AICapture.attack_enemy_town_defense(ai, t) != -1:
		return
	var resistance_diff := (t.loyalty - MIN_NATION_DEFEND_LOYALTY) if t.nation_id > 0 else (t.resistance_to(f.nation_id) - MIN_INDEPENDENT_DEFEND_LOYALTY)
	var defense := 0
	if t.population >= 5:
		defense += possible_defender_combat_level(t, f.nation_id)
	if defense > 0:
		if t.nation_id == 0:
			if _think_assign_better_overseer(ai, f, t):
				return
			if _think_capture_use_spy(ai, f, t):
				return
			if defense > 100 + ai.pref("military_courage") and resistance_diff > (100 - ai.pref("peacefulness")) / 5:
				return
		else:
			var tn := ai.g.nation(t.nation_id)
			if tn and Diplomacy.military_rank(ai.g, tn) > ai.military_rank():
				return
	var ok := _capture_enemy_town(ai, f, t, defense) if t.nation_id > 0 else _capture_independent_town(ai, f, t, defense)
	if ok:
		f.ai_capture_town = t
		if f.overseer == null and t.nation_id > 0 and not f.patrol_units.is_empty():
			f.patrol_units[0].order_enter(f)


## FirmCamp::think_capture_target_town: the linked town with the lowest
## resistance (or loyalty, for a hostile kingdom's) that is not still falling.
static func _think_capture_target_town(ai: NationAI, f: Firm) -> Town:
	if f.linked_towns.is_empty() or f.overseer == null:
		return null
	if ai.find_action(Vector2i(f.x1, f.y1), Vector2i(-1, -1), NationAI.ASSIGN_SOLDIER, f.code) != null:
		return null
	var best: Town = null
	var min_r := 100
	for t in f.linked_towns:
		if t.nation_id == f.nation_id:
			continue
		var cur := 0
		if t.nation_id == 0:
			if pays_tribute(t):
				continue
			cur = int(t.resistance_to(f.nation_id))
			var target := int(t.target_resistance.get(f.nation_id, cur))
			if cur - target > 0 and cur > 25 - 25 * ai.pref("peacefulness") / 100 and t.population >= 5:
				continue
		else:
			if ai.relation(t.nation_id) != Defs.Relation.WAR:
				continue
			cur = int(t.loyalty)
		if cur < min_r:
			min_r = cur
			best = t
	return best


## FirmCamp::think_attack_enslaving_monster: break the lairs that make our target villages pay tribute.
static func _think_attack_enslaving_monster(ai: NationAI, f: Firm) -> bool:
	if f.linked_towns.is_empty() or f.overseer == null:
		return false
	if ai.find_action(Vector2i(f.x1, f.y1), Vector2i(-1, -1), NationAI.ASSIGN_SOLDIER, f.code) != null:
		return false
	for t in f.linked_towns:
		if t.nation_id != 0 or not pays_tribute(t):
			continue
		for l in t.linked_firms:
			if l.code == "LAIR" and l.nation_id > 0 and t.resistance_to(l.nation_id) < Town.MONSTER_COLLECT_TOWN_TRIBUTE_LOYALTY:
				if AIAttack.attack_target(ai, l, obj_power(l), false, f, true):
					return true
	return false


## FirmCamp::ai_capture_independent_town
static func _capture_independent_town(ai: NationAI, f: Firm, t: Town, defense: int) -> bool:
	var cur := total_combat_level(f)
	var diff := defense * (150 + ai.pref("force_projection") / 2) / 100 - cur
	if diff > 0 and ai_recruit(ai, f, diff):
		return false
	return AIAttack.attack_target(ai, t, defense, false, f)


## FirmCamp::ai_capture_enemy_town: every camp joins in when we are much stronger.
static func _capture_enemy_town(ai: NationAI, f: Firm, t: Town, defense: int) -> bool:
	var tn := ai.g.nation(t.nation_id)
	var ours := ai.military_rank()
	var theirs := Diplomacy.military_rank(ai.g, tn) if tn else 0
	var use_all := false
	if ours - theirs > 30 and ai.should_spend(ai.pref("military_courage") / 2):
		use_all = true
	elif ai._aggressiveness() >= GameSetup.MODERATE and tn and not tn.is_ai and ours > theirs:
		if ai._aggressiveness() >= GameSetup.HIGH or ai.pref("peacefulness") < 50:
			use_all = true
	return AIAttack.attack_target(ai, t, defense, false, f, use_all)


## FirmCamp::think_assign_better_overseer
static func _think_assign_better_overseer(ai: NationAI, f: Firm, t: Town) -> bool:
	if ai.find_action(Vector2i(f.x1, f.y1), Vector2i(-1, -1), NationAI.ASSIGN_OVERSEER, f.code) != null:
		return true
	var res := t.resistance_to(f.nation_id)
	if res <= float(t.target_resistance.get(f.nation_id, res)) + 1.0 and res > 30.0:
		return _think_assign_better_overseer2(ai, f, t)
	return false


static func _think_assign_better_overseer2(ai: NationAI, f: Firm, t: Town) -> bool:
	var found := AICapture.find_best_capturer(ai, t)
	var best: Unit = found[0]
	if best == null or best == f.overseer:
		return false
	if f.overseer and best.lead_skill() < f.overseer.lead_skill() + 15.0:
		return false
	if not AICapture.mobilize_capturer(ai, best):
		return false
	var a := ai.add_action(Vector2i(f.x1, f.y1), Vector2i(-1, -1), NationAI.ASSIGN_OVERSEER, f.code, 1, best)
	return not a.is_empty() or true


## FirmCamp::think_capture_use_spy(2)
static func _think_capture_use_spy(ai: NationAI, f: Firm, t: Town) -> bool:
	var level := 0
	for s in Espionage.spies_in(t):
		if s.nation_id == f.nation_id:
			level += int(s.spy_skill)
	var cur := int(t.loyalty) if t.nation_id > 0 else int(t.resistance_to(f.nation_id))
	var target := int(t.target_loyalty) if t.nation_id > 0 else int(t.target_resistance.get(f.nation_id, cur))
	var min_r := mini(cur, target)
	if min_r < (MIN_NATION_DEFEND_LOYALTY if t.nation_id > 0 else MIN_INDEPENDENT_DEFEND_LOYALTY):
		return false
	if min_r * (50 + ai.pref("spy")) / 50 > level:
		return AICapture.assign_spy_to_town(ai, t, t.race)
	return false


## FirmCamp::think_employ_to_capture: a tower of science by an independent
## village whose resistance is low enough for its people to work there.
static func _think_employ_to_capture(ai: NationAI, f: Firm) -> bool:
	if ai.pref("peacefulness") > 50:
		if ai.n.cash < 1000 * ai.pref("cash_reserve") / 100:
			return false
	else:
		var towers := ai.my_firms("RESEARCH").size()
		var imp := 50 + ai.pref("research") / 2 - towers * 10
		if towers == 0:
			imp += 50
		if not ai.should_spend(imp):
			return false
	for t in f.linked_towns:
		if t.nation_id != 0 or t.resistance_to(f.nation_id) > Game.INDEPENDENT_LINK_RESISTANCE:
			continue
		if t.linked_firms.any(func(x): return x.code == "RESEARCH" and x.nation_id == f.nation_id):
			continue
		if ai.find_action(Vector2i(-1, -1), Vector2i(t.x1, t.y1), NationAI.BUILD_FIRM, "RESEARCH") != null:
			continue
		var at := ai.find_best_place("RESEARCH", t)
		if at.x >= 0:
			ai.add_action(at, Vector2i(t.x1, t.y1), NationAI.BUILD_FIRM, "RESEARCH", 1, null, ai.n.race)
			return true
	return false


## FirmCamp::think_use_cash_to_capture
static func _think_use_cash_to_capture(ai: NationAI, f: Firm) -> bool:
	if not AICapture.should_use_cash_to_capture(ai):
		return false
	for t in f.linked_towns:
		if t.nation_id == f.nation_id or t.grant_penalty > 0 or pays_tribute(t):
			continue
		if can_grant_foreign(t, f.nation_id):
			t.grant(f.nation_id)
	return true


## FirmCamp::think_attack_invader: hostile units attacking near the camp are met by its men.
static func _think_attack_invader(ai: NationAI, f: Firm) -> bool:
	var r := 6 + ai.pref("military_courage") / 20
	var area := f.footprint().grow(r)
	var level := 0
	var target: Unit = null
	for u in ai.g.units:
		if u.dead or u.nation_id <= 0 or u.inside_firm != null or not area.has_point(u.cell()):
			continue
		if u.attacking and ai.relation(u.nation_id) == Defs.Relation.WAR:
			level += int(u.hp)
			if target == null or ai.g.rng.randi() % 5 == 0:
				target = u
	if level == 0 or f.soldiers.is_empty():
		return false
	var out := f.patrol(Firm.PATROL_NO_GENERAL)
	f.patrol_units = out.duplicate()
	for u in out:
		u.order_attack(target)
	return not out.is_empty()


## FirmCamp::think_attack_nearby_enemy: hostile buildings and towns close by.
static func _think_attack_nearby_enemy(ai: NationAI, f: Firm) -> bool:
	var r := 6 + ai.pref("military_courage") / 20
	var area := f.footprint().grow(r)
	for o in ai.g.firms + ai.g.towns:
		if o.dead or o.nation_id <= 0 or not area.intersects(o.footprint()):
			continue
		if ai.relation(o.nation_id) == Defs.Relation.WAR:
			if AIAttack.attack_target(ai, o, obj_power(o), false, f):
				return true
	return false


## FirmCamp::think_change_town_link: links to independent and hostile towns on, to friendly ones off.
static func _think_change_town_link(ai: NationAI, f: Firm) -> void:
	for t in f.linked_towns:
		if t.nation_id == f.nation_id:
			continue
		var on := t.nation_id == 0 or ai.relation(t.nation_id) == Defs.Relation.WAR
		ai.g.set_link(f, t, on)


## FirmCamp::best_commander_race
static func best_commander_race(ai: NationAI, f: Firm) -> String:
	for t in f.linked_towns:
		if closest_own_camp(t) == f:
			return t.race
	var target := _think_capture_target_town(ai, f)
	if target and target.nation_id == 0:
		return target.race
	return majority_race(f)


static func cur_commander_leadership(ai: NationAI, f: Firm, best_race := "") -> int:
	if f.overseer == null:
		return 0
	if best_race == "":
		best_race = best_commander_race(ai, f)
	var l := int(f.overseer.lead_skill())
	return l if f.overseer.race == best_race else l / 2


static func new_commander_leadership(ai: NationAI, f: Firm, race: String, skill: int) -> int:
	if f.overseer == null:
		return 0
	return skill if race == best_commander_race(ai, f) else skill / 2


## FirmCamp::think_assign_better_commander: a soldier of another camp, a hero
## at an inn, or an independent hero with more leadership takes command.
static func _think_assign_better_commander(ai: NationAI, f: Firm) -> bool:
	var at := Vector2i(f.x1, f.y1)
	var existing = ai.find_action(at, Vector2i(-1, -1), NationAI.ASSIGN_OVERSEER, f.code)
	if existing != null and existing["processing"] > 0:
		return false
	var best_race := best_commander_race(ai, f)
	var cur := 0
	var best_l := 0
	if f.overseer:
		cur = cur_commander_leadership(ai, f, best_race)
		best_l = cur + 10 + ai.pref("loyalty_concern") / 10
	var best_camp: Firm = null
	var best_s: Unit = null
	for c in ai.camps():
		for s in c.soldiers:
			if not (s.is_human() or c.code == "LAIR") or s.basic_days > 0:
				continue
			var l := int(s.lead_skill())
			if s.race != best_race:
				l /= 2
			if l > best_l:
				best_l = l
				best_camp = c
				best_s = s
	var u: Unit = null
	if best_camp:
		best_camp.release_unit(best_s)
		u = best_s
	if u == null:
		for inn in ai.my_firms("INN"):
			for i in inn.heroes.size():
				var h: Dictionary = inn.heroes[i]
				if h["race"] == majority_race(f) and int(h["leadership"]) > best_l:
					var imp := 30 + (int(h["leadership"]) - cur) * (150 + ai.pref("hire_unit")) / 100
					if ai.should_spend(imp, float(h["cost"])):
						u = inn.hire_hero(i)
						break
			if u:
				break
	if u == null:
		return false
	u.rank = Defs.Rank.GENERAL
	if existing != null:
		ai.actions.erase(existing)
	return not ai.add_action(at, Vector2i(-1, -1), NationAI.ASSIGN_OVERSEER, f.code, 1, u).is_empty()


# ------------------------------------------------------- work places ---

## FirmWork::process_ai
static func _process_work(ai: NationAI, f: Firm, day: int) -> void:
	if day % 30 == f.obj_id % 30:
		_think_adjust_workforce(ai, f)
		_think_inc_worker_supply(ai, f)


static func _think_adjust_workforce(ai: NationAI, f: Firm) -> void:
	var nw := f.needed_workers
	match f.code:
		"MINE", "FACTORY":
			var opt := 3 + Defs.MAX_WORKER - Defs.MAX_WORKER * int(f.stock) / int(MAX_STOCK)
			if nw > opt:
				f.set_needed_workers(nw - maxi(1, (nw - opt) / 3))
				return
			if f.stock > MAX_STOCK * 0.1 and f.last_month_output + f.month_output > 30.0:
				return
			if f.code == "MINE" and f.reserve < Defs.MAX_RAW_RESERVE_QTY / 10.0:
				return
			if nw < Defs.MAX_WORKER:
				f.set_needed_workers(nw + (1 if f.stock > MAX_STOCK * 0.05 else 2))
		"RESEARCH":
			var workers := 0
			for x in ai.my_firms("RESEARCH"):
				workers += x.workers()
			var dec := 100 * workers / maxi(1, ai.total_population()) > 10 + ai.pref("research") / 3 or not ai.has_enough_food()
			if not dec and nw < Defs.MAX_WORKER:
				f.set_needed_workers(nw + 1)
			elif dec and nw > Defs.MAX_WORKER / 2:
				f.set_needed_workers(nw - 1)
		"WAR":
			var preferred := ai.pref("economic_development") / 20
			var avail := 0
			for t in f.linked_towns:
				if t.nation_id == f.nation_id:
					avail += t.jobless()
			if nw < 10:
				preferred = maxi(0, preferred - (10 - nw))
			if avail > preferred and f.weapon != "":
				f.set_needed_workers(nw + 1)
			elif avail < preferred and f.weapon == "" and nw > 5:
				f.set_needed_workers(nw - 1)
		"BASE":
			if ai.has_enough_food():
				if nw < Defs.MAX_WORKER:
					f.set_needed_workers(nw + 1)
			elif nw > Defs.MAX_WORKER / 2:
				f.set_needed_workers(nw - 1)


## FirmWork::think_inc_worker_supply: build a town by it, or move people to a linked one.
static func _think_inc_worker_supply(ai: NationAI, f: Firm) -> void:
	if f.needed_workers - f.workers() < 5:
		return
	var avail := 0
	var linked := 0
	for t in f.linked_towns:
		if not ai.g.work_link_on(f, t):
			continue
		linked += 1
		avail += t.jobless()
	if linked == 0:
		build_neighbor_town(ai, f)
		return
	if avail >= f.needed_workers - f.workers():
		return
	var best_to: Town = null
	var best_r := 0
	for t in f.linked_towns:
		if t.nation_id != f.nation_id:
			continue
		var r := _race_jobless(ai, t.race, t)
		if r > best_r:
			best_r = r
			best_to = t
	if best_to == null:
		return
	var from: Town = null
	var most := 0
	for t in ai.my_towns():
		if t.race == best_to.race and t != best_to and t.jobless() > most:
			most = t.jobless()
			from = t
	if from:
		ai.add_action(Vector2i(best_to.x1, best_to.y1), Vector2i(from.x1, from.y1), NationAI.SETTLE_TOWN, 0, f.needed_workers - f.workers())


static func _race_jobless(ai: NationAI, race: String, excluded: Town) -> int:
	var p := 0
	for t in ai.my_towns():
		if t.race == race and t != excluded:
			p += t.jobless()
	return p


## FirmWork::ai_build_neighbor_town
static func build_neighbor_town(ai: NationAI, f: Firm, builder: Unit = null) -> bool:
	var at := ai.find_best_place("", f)
	if at.x < 0:
		f.no_neighbor_space = true
		return false
	var count := {}
	for t in ai.my_towns():
		count[t.race] = int(count.get(t.race, 0)) + t.jobless()
	var race := ""
	var most := 0
	for r in count:
		if count[r] > most:
			most = count[r]
			race = r
	if race == "":
		return false
	if ai.find_action(Vector2i(-1, -1), Vector2i(f.x1, f.y1), NationAI.BUILD_TOWN, race) != null:
		return false
	ai.add_action(at, Vector2i(f.x1, f.y1), NationAI.BUILD_TOWN, race, 1, builder)
	return true


# ------------------------------------------------- mines and factories ---

## FirmMine::process_ai
static func _process_mine(ai: NationAI, f: Firm, day: int) -> void:
	if f.raw == "" or f.reserve <= 0.0:
		del_firm(ai, f)
		return
	if f.productivity() > 0.0:
		var now := day % 30 == f.obj_id % 30
		if ai.my_firms("FACTORY").is_empty():
			now = day % 5 == f.obj_id % 5
		if now:
			if not think_build_factory(ai, f, f.raw):
				f.factory_count = 0
			_think_build_market(ai, f)
	_process_work(ai, f, day)


## Firm::think_build_factory: three checks in a row that all say a factory is
## needed - every factory of the material full-staffed, short of stock and
## not keeping a market supplied - and labour to spare.
static func think_build_factory(ai: NationAI, f: Firm, raw: String) -> bool:
	if f.no_neighbor_space or not ai.can_ai_build("FACTORY"):
		return false
	var factories := 0
	for x in f.linked_firms:
		if x.code != "FACTORY" or x.nation_id != f.nation_id or x.raw != raw:
			continue
		if ai.total_jobless() < Defs.MAX_WORKER * 2 * (50 + ai.pref("inc_pop_by_growth")) / 100:
			return false
		if x.workers() < Defs.MAX_WORKER:
			return false
		if x.stock > MAX_STOCK * 0.1:
			return false
		for m in x.linked_firms:
			if m.code == "MARKET" and ai.g.link_on(x, m) and float(m.goods.get(raw, 0.0)) > 100.0:
				return false
		factories += 1
	if factories >= 1 and not ai.has_enough_food():
		return false
	if f.code == "MINE" and f.reserve < 1000.0 and factories >= 1:
		return false
	if ai.total_jobless() < factories * Defs.MAX_WORKER:
		return false
	f.factory_count += 1
	if f.factory_count >= 3:
		var at := ai.find_best_place("FACTORY", f)
		if at.x < 0:
			f.no_neighbor_space = true
			return false
		ai.add_action(at, Vector2i(f.x1, f.y1), NationAI.BUILD_FIRM, "FACTORY")
		f.factory_count = 0
	return true


## FirmMine/FirmFactory::think_build_market: one market of our own next to it.
static func _think_build_market(ai: NationAI, f: Firm) -> bool:
	if f.no_neighbor_space:
		return false
	if f.code == "MINE" and f.stock < MAX_STOCK * 0.2:
		return false
	if not ai.can_ai_build("MARKET"):
		return false
	if f.code == "FACTORY" and ai.build_action_near("MARKET", f.center_loc()):
		return false
	if f.linked_firms.any(func(x): return x.code == "MARKET" and x.nation_id == f.nation_id):
		return false
	return build_neighbor_firm(ai, f, "MARKET")


## FirmFactory::process_ai
static func _process_factory(ai: NationAI, f: Firm, day: int) -> void:
	if day % 15 == f.obj_id % 15 and _think_change_production(ai, f):
		return
	if day % 30 == f.obj_id % 30:
		_think_build_market(ai, f)
	_process_work(ai, f, day)


## FirmFactory::think_change_production: a factory standing idle takes up
## whatever its linked mines and markets have most of (its own first); with
## nothing for two months it is closed.
static func _think_change_production(ai: NationAI, f: Firm) -> bool:
	if f.month_output + f.last_month_output > 0.0 or f.raw_stock > 0.0:
		return false
	if ai.g.day < f.setup_day + 30:
		return false
	var best := ""
	var best_r := 0.0
	var best_own := false
	for x in f.linked_firms:
		if x.code != "MINE" and x.code != "MARKET":
			continue
		if not ai.g.link_side(f, x):
			ai.g.set_link(f, x, true)
		if not ai.g.link_on(f, x):
			continue
		var own: bool = x.nation_id == f.nation_id
		if x.code == "MINE":
			if x.stock >= MIN_FACTORY_IMPORT_STOCK_QTY and x.stock > best_r and (own or not best_own):
				best_r = x.stock
				best = x.raw
				best_own = own
		else:
			for r in x.raws:
				var q := float(x.raws[r])
				if q >= MIN_FACTORY_IMPORT_STOCK_QTY and q > best_r and (own or not best_own):
					best_r = q
					best = r
					best_own = own
	if best != "":
		Economy.set_production(f, best)
		return true
	if ai.g.day > f.setup_day + 60:
		del_firm(ai, f)
		return true
	return false


# ------------------------------------------------------------ markets ---

## FirmMarket::process_ai
static func _process_market(ai: NationAI, f: Firm, day: int) -> void:
	var id := f.obj_id
	if day % 30 == id % 30 and _market_think_del(ai, f):
		return
	if day % 60 == id % 60:
		_think_market_build_factory(ai, f)
	if day < f.last_import_day + 60:
		return
	if Caravans.can_hire(f) > 0:
		var interval := 10 + (100 - ai.pref("trading_tendency")) / 5
		if _linked_to_town(ai, f, false):
			if day % interval == id % interval:
				_think_import_new_product(ai, f)
			if day % 60 == (id + 20) % 60 and (f.last_import_day <= 0 or day > f.last_import_day + 180):
				_think_increase_existing_supply(ai, f)
		# think_export_product: the original looks for a town to export to but
		# never acts on it


static func _linked_to_town(ai: NationAI, f: Firm, own_base_only: bool) -> bool:
	for t in f.linked_towns:
		if not ai.g.link_on(f, t):
			continue
		if not own_base_only or (t.nation_id == f.nation_id and t.is_base_town):
			return true
	return false


## FirmMarket::think_del: a market no town uses goes, once it has been idle a while.
static func _market_think_del(ai: NationAI, f: Firm) -> bool:
	if not f.linked_towns.is_empty():
		f.no_town_since = 0
		return false
	if f.no_town_since == 0:
		f.no_town_since = ai.g.day
	if stock_value_index(f) >= 10 and ai.g.day < f.no_town_since + 180 + 180 * ai.pref("trading_tendency") / 100:
		return false
	del_firm(ai, f)
	return true


## FirmMarket::think_market_build_factory: raw materials piling up from afar get a factory.
static func _think_market_build_factory(ai: NationAI, f: Firm) -> void:
	if f.no_neighbor_space:
		return
	f.factory_count = 2
	for r in f.raws:
		if float(f.raws[r]) < 250.0:
			continue
		if f.linked_firms.any(func(x): return x.code == "MINE" and x.nation_id == f.nation_id and x.raw == r):
			continue
		if think_build_factory(ai, f, r):
			return


## Town::update_product_supply: the goods an own market linked to the town sells.
static func town_supply(t: Town) -> Dictionary:
	var out := {}
	for m in t.linked_firms:
		if m.nation_id == t.nation_id and m.code == "MARKET":
			for p in m.goods:
				if float(m.goods[p]) > 0.0:
					out[p] = true
	return out


## FirmMarket::think_import_new_product
static func _think_import_new_product(ai: NationAI, f: Firm) -> bool:
	var need := {}
	for t in f.linked_towns:
		if not ai.g.link_on(f, t) or not t.is_base_town:
			continue
		var has := town_supply(t)
		for p in Economy.raw_types():
			if not has.has(p):
				need[p] = int(need.get(p, 0)) + t.population
	for p in Economy.raw_types():
		if int(need.get(p, 0)) >= 10 and _think_import_specific_product(ai, f, p):
			f.last_import_day = ai.g.day
			return true
	if _linked_to_town(ai, f, true) and not f.no_neighbor_space and ai.total_jobless() >= Defs.MAX_WORKER * 2 \
			and Caravans.can_hire(f) >= 2 and ai.can_ai_build("FACTORY"):
		for p in Economy.raw_types():
			if int(need.get(p, 0)) >= 10 and _think_mft_specific_product(ai, f, p):
				f.last_import_day = ai.g.day
				return true
	return false


## FirmMarket::think_increase_existing_product_supply
static func _think_increase_existing_supply(ai: NationAI, f: Firm) -> bool:
	for p in f.goods:
		var supply := float(f.month_supply.get(p, 0.0)) + float(f.last_month_supply.get(p, 0.0))
		if float(f.goods[p]) < MAX_STOCK / 10.0 and float(f.demand.get(p, 0.0)) * 0.8 > supply:
			if _think_import_specific_product(ai, f, p):
				return true
	return false


## FirmMarket::think_import_specific_product: the best source of the goods -
## our own factories and markets, or a trading partner's well-stocked market.
static func _think_import_specific_product(ai: NationAI, f: Firm, p: String) -> bool:
	var best: Firm = null
	var best_r := 0
	for x in ai.g.firms:
		if x == f or x.dead or x.under_construction:
			continue
		var level := 0
		if x.code == "FACTORY":
			if x.nation_id != f.nation_id or x.raw != p:
				continue
			level = 100 * int(x.stock) / int(MAX_STOCK)
		elif x.code == "MARKET":
			if x.nation_id != f.nation_id:
				if not x.linked_towns.any(func(t): return t.nation_id == x.nation_id):
					continue
				var xn := x.nation()
				if xn == null or not Diplomacy.has_trade(xn, f.nation_id):
					continue
			var sup := float(x.month_supply.get(p, 0.0)) + float(x.last_month_supply.get(p, 0.0))
			if x.goods.has(p) and sup > 0.0:
				level = 100 * int(x.goods[p]) / int(MAX_STOCK)
		else:
			continue
		var r := 0
		if x.nation_id == f.nation_id:
			if level < 10:
				continue
			r = 50
		else:
			if level < 20:
				continue
			r = Diplomacy.level(ai.relation(x.nation_id)) * 5
		r += level / 2 + ai.distance_rating(f.center_loc(), x.center_loc())
		if r > best_r:
			best_r = r
			best = x
	if best:
		return create_new_trade(ai, f, best, "", "P:" + p)
	return false


## FirmMarket::think_mft_specific_product: raw material from a partner's
## mine-fed market, to make the goods ourselves.
static func _think_mft_specific_product(ai: NationAI, f: Firm, r: String) -> bool:
	var best: Firm = null
	var best_r := 0
	for x in ai.g.firms:
		if x == f or x.dead or x.code != "MARKET" or x.nation_id == f.nation_id:
			continue
		var xn := x.nation()
		if xn == null or not Diplomacy.has_trade(xn, f.nation_id):
			continue
		if not x.linked_firms.any(func(m): return m.code == "MINE" and m.nation_id == x.nation_id and m.raw == r):
			continue
		var level := 0
		if float(x.raws.get(r, 0.0)) > MAX_STOCK / 5.0:
			level = 100 * int(x.raws[r]) / int(MAX_STOCK)
		if level < 50:
			continue
		var rating := level - 100 * int(maxf(absf(f.center_loc().x - x.center_loc().x), absf(f.center_loc().y - x.center_loc().y))) / ai.g.world.w
		rating += Diplomacy.level(ai.relation(x.nation_id)) * 20
		if rating > best_r:
			best_r = rating
			best = x
	if best == null:
		return false
	return create_new_trade(ai, f, best, "", "R:" + r)


## FirmMarket::ai_create_new_trade: add the goods to a caravan already on the
## route, or hire one (no more than two to a route).
static func create_new_trade(ai: NationAI, f: Firm, other: Firm, pick1: String, pick2: String) -> bool:
	var on_route := 0
	for u in ai.g.units:
		if not u.is_caravan or u.dead or u.nation_id != f.nation_id or u.stops.size() < 2:
			continue
		var s1 := -1
		var s2 := -1
		if u.stops[0]["firm"] == f and u.stops[1]["firm"] == other:
			s1 = 0
			s2 = 1
		elif u.stops[1]["firm"] == f and u.stops[0]["firm"] == other:
			s1 = 1
			s2 = 0
		else:
			continue
		var changed := false
		if pick1 != "" and not (pick1 in u.stops[s1]["picks"]):
			if u.inside_firm == null:
				Caravans.set_pick_up(u, s1, pick1)
			changed = true
		if pick2 != "" and not (pick2 in u.stops[s2]["picks"]):
			if u.inside_firm == null:
				Caravans.set_pick_up(u, s2, pick2)
			changed = true
		if changed:
			return true
		on_route += 1
	if on_route >= 2:
		return false
	var c := Caravans.hire(f)
	if c == null:
		return false
	Caravans.set_stop(c, 1, other)
	Caravans.set_pick_up(c, 0, "none")
	Caravans.set_pick_up(c, 1, "none")
	if pick1 != "":
		Caravans.set_pick_up(c, 0, pick1)
	if pick2 != "":
		Caravans.set_pick_up(c, 1, pick2)
	return true


# ------------------------------------------- towers, war factories, inns ---

## FirmResearch::think_del: everything learnt, or nobody to work there.
static func _research_think_del(ai: NationAI, f: Firm) -> bool:
	if not Defs.research_techs().any(func(t): return Defs.can_research(ai.n, t)):
		del_firm(ai, f)
		return true
	return _work_think_del(f)


## FirmWar/FirmResearch::think_del: no workers and no working link to a town.
static func _work_think_del(f: Firm) -> bool:
	if f.workers() > 0:
		return false
	for t in f.linked_towns:
		if Game.inst.link_on(f, t):
			return false
	del_firm(Game.inst.nation(f.nation_id).ai, f)
	return true


## FirmWar::think_new_production: the machine we have fewest of, newer types first.
static func _war_think_new_production(ai: NationAI, f: Firm) -> void:
	if not _should_build_new_weapon(ai, f):
		return
	var types := 0
	var total := 0
	for w in Defs.WEAPONS:
		if ai.n.tech_level(w) == 0 or w == "EXPCART":
			continue
		types += 1
		total += ai.g.units.filter(func(u): return u.sprite_code == w and u.nation_id == ai.n.id and not u.dead).size()
	if types == 0:
		return
	var avg := total / types
	var best := ""
	var best_r := 0
	for w in Defs.WEAPONS:
		var lvl := ai.n.tech_level(w)
		if lvl == 0 or w == "EXPCART":
			continue
		var count := ai.g.units.filter(func(u): return u.sprite_code == w and u.nation_id == ai.n.id and not u.dead).size()
		var r := avg - count + lvl * 3
		if r > best_r:
			best_r = r
			best = w
	if best != "":
		f.queue_weapon(best)


## FirmWar::should_build_new_weapon
static func _should_build_new_weapon(ai: NationAI, f: Firm) -> bool:
	if ai.true_profit() < 0.0 and ai.n.cash < 15000 * (100 + ai.pref("cash_reserve")) / 200:
		return false
	var weapons_cost := float(ai.n.last_expense_by.get("Weapons", 0.0)) + float(ai.n.expense_by.get("Weapons", 0.0))
	var income := maxf(ai.n.last_income_year, ai.n.income_year)
	if weapons_cost > income * (30 + ai.pref("use_weapon") / 2) / 100.0:
		return false
	return ai.camps().any(func(c): return c.soldiers.size() < NationAI.MAX_SOLDIER)


## FirmInn::think_del
static func _inn_think_del(ai: NationAI, f: Firm) -> bool:
	if ai.n.cash < 500 + 500 * ai.pref("cash_reserve") / 100 and ai.true_profit() < 0.0:
		del_firm(ai, f)
		return true
	if ai.my_firms("INN").size() > AITown.supported_inn_count(ai) + 2:
		del_firm(ai, f)
		return true
	var reach := Defs.effective_distance("INN", "")
	for t in ai.my_towns():
		if maxf(absf(t.center_loc().x - f.center_loc().x), absf(t.center_loc().y - f.center_loc().y)) <= reach:
			return false
	del_firm(ai, f)
	return true


## FirmInn::think_hire_spy: our inns offer no spies (heroes only), so this
## finds nothing, as with an inn of the original that has no spy for hire.
static func _inn_think_hire_spy(ai: NationAI, f: Firm) -> bool:
	if not ai.should_spend(ai.pref("spy") / 2):
		return false
	for i in f.heroes.size():
		var h: Dictionary = f.heroes[i]
		if int(h.get("spy_skill", 0)) == 0:
			continue
		for t in ai.g.towns:
			if t.race == h["race"] and t.nation_id == 0 and int(t.target_resistance.get(ai.n.id, -1)) == int(t.resistance_to(ai.n.id)):
				var u := f.hire_hero(i)
				if u:
					ai.add_action(Vector2i(t.x1, t.y1), Vector2i(-1, -1), NationAI.ASSIGN_SPY, t.nation_id, 1, u)
				return true
	return false


## FirmInn::think_hire_general: a hero at least 10 points better than a camp's commander.
static func _inn_think_hire_general(ai: NationAI, f: Firm) -> bool:
	if not ai.should_spend(ai.pref("military_development") / 2):
		return false
	for i in f.heroes.size():
		var h: Dictionary = f.heroes[i]
		var best: Firm = null
		var best_r := 10
		for c in ai.camps():
			var r := new_commander_leadership(ai, c, h["race"], int(h["leadership"])) - cur_commander_leadership(ai, c)
			if r > best_r and ai.find_action(Vector2i(c.x1, c.y1), Vector2i(-1, -1), NationAI.ASSIGN_OVERSEER, c.code) == null:
				best_r = r
				best = c
		if best:
			var u := f.hire_hero(i)
			if u:
				ai.add_action(Vector2i(best.x1, best.y1), Vector2i(-1, -1), NationAI.ASSIGN_OVERSEER, best.code, 1, u)
			return true
	return false
