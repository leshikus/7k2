class_name AIUnit
extends RefCounted
## A computer kingdom's units outside buildings (oun_ai.cpp, Unit::process_ai):
## rewards for loyalty, items, kings and generals fleeing to safety, giving up
## a chase that has gone too far, returning to their camp, and - when idle -
## leaders taking command of camps, soldiers joining camps, villagers joining
## towns (or founding them), war machines joining camps, and a fort or lair
## built when the troops have nowhere to go.

const INTER_PLACE_SPACE := 1


static func process(ai: NationAI, u: Unit, day: int) -> void:
	if u.dead or u.inside_firm != null or u.home_town != null or u.is_caravan or u.is_god or u.rebel_id > 0:
		return
	if u.is_caravan:
		return
	var id := u.obj_id
	# a spy of another kingdom in our colours is not ours to command
	if u.is_spy and u.nation_id != ai.n.id:
		return
	var leader_race := u.is_human() or SpecialFirms.is_fryhtan_unit(u)     # race_id: people and Fryhtans
	if u.is_human() and u.rank != Defs.Rank.KING and day % 5 == id % 5:
		think_reward(ai, u)
	if u.has_meta("hidden"):          # Unit::is_visible: on the map (our .visible is the fog of war)
		return
	if think_use_item(ai, u):
		return
	if leader_race and u.rank == Defs.Rank.KING and think_king_flee(ai, u):
		return
	if leader_race and u.rank == Defs.Rank.GENERAL and day % 7 == id % 7 and think_general_flee(ai, u):
		return
	# stop attacking a village that has no resistance left
	if u.order == Unit.Order.ATTACK and u.target is Town and u.target.nation_id == 0 and u.target.resistance_to(ai.n.id) < 1.0:
		u.stop()
		return
	if u.order != Unit.Order.IDLE:
		think_stop_chase(ai, u)
		return
	if _escape_fire(ai, u):
		return
	if u.is_spy:
		move_to_nearby_town(ai, u)       # Unit::think_spy_action
	if u.in_attack_mission and attack_next_target(ai, u):
		return
	if u.home_firm != null:
		var hf := u.home_firm
		var room := false
		if is_instance_valid(hf) and not hf.dead:
			if Espionage.is_camp(hf) or hf.code == "LAIR":
				room = hf.soldiers.size() < NationAI.MAX_SOLDIER if u.rank == Defs.Rank.SOLDIER else hf.overseer == null
			elif hf.code == "FORTRESS":
				room = hf.soldiers.size() < hf.capacity()
		if room and u.return_to_base():
			return
		u.home_firm = null
	if u.order != Unit.Order.IDLE:
		return
	if leader_race and u.rank == Defs.Rank.KING:
		if u.is_human():
			think_leader_action(ai, u)
		else:
			think_normal_monster_action(ai, u)
	elif leader_race and u.rank == Defs.Rank.GENERAL:
		think_general_action(ai, u)
	elif u.is_weapon:
		if day % 15 == id % 15:
			think_weapon_action(ai, u)
	elif SpecialFirms.is_fryhtan_unit(u):
		if u.ai_no_action and day % 15 != id % 15:
			return
		if not think_normal_monster_action(ai, u):
			u.ai_no_action = true
			move_to_nearby_firm(ai, u, "LAIR")
	elif u.is_wagon():
		think_assign_human_to_town(ai, u)
	elif u.is_human():
		if u.ai_no_action and day % 15 != id % 15:
			return
		if not think_normal_human_action(ai, u):
			u.ai_no_action = true
			move_to_nearby_town(ai, u)


static func _dist(a: Vector2, b: Vector2) -> float:
	return maxf(absf(a.x - b.x), absf(a.y - b.y))


## Unit::think_stop_chase: give up a unit chased too far from where it was first attacked.
static func think_stop_chase(ai: NationAI, u: Unit) -> bool:
	if u.order != Unit.Order.ATTACK or not u.has_meta("ai_chase_from"):
		return false
	var t := u.target
	if t == null or not is_instance_valid(t) or t.dead:
		u.stop()
		return true
	if not (t is Unit):
		return false
	if t.inside_firm != null or t.has_meta("hidden"):
		u.stop()
		return true
	var from: Vector2 = u.get_meta("ai_chase_from")
	if _dist(t.center_loc(), from) <= 10 + ai.pref("military_courage") / 20:
		return false
	u.stop()
	var lead: Unit = u.leader if u.leader and is_instance_valid(u.leader) else u
	for m in ai.g.units:
		if m.leader == lead and not m.dead:
			m.stop()
	lead.stop()
	return true


## Unit::ai_move_to_nearby_town
static func move_to_nearby_town(ai: NationAI, u: Unit, assign := false) -> void:
	var best: Town = null
	var best_r := 0
	for t in ai.g.towns:
		if t.dead or t.nation_id != u.nation_id:
			continue
		var d := _dist(u.center_loc(), t.center_loc())
		if d < 10.0:
			return
		var r := 100 - 100 * int(d) / ai.g.world.w + t.population
		if u.race == t.race:
			r += 100
		if r > best_r:
			best_r = r
			best = t
	if best:
		if assign and u.can_settle():
			u.order_settle_into(best)
		else:
			u.order_move(Vector2i(best.x1, best.y1))


## Unit::ai_move_to_nearby_firm
static func move_to_nearby_firm(ai: NationAI, u: Unit, code: String, code2 := "") -> void:
	var best: Firm = null
	var best_r := 0
	for f in ai.g.firms:
		if f.dead or f.nation_id != u.nation_id or (f.code != code and f.code != code2):
			continue
		var r := ai.distance_rating(u.center_loc(), f.center_loc())
		if u.race == f.race:
			r += 100
		if r > best_r:
			best_r = r
			best = f
	if best:
		u.order_move(Vector2i(best.x1, best.y1))


## Unit::ai_escape_fire
static func _escape_fire(ai: NationAI, u: Unit) -> bool:
	if u.attacking or not ai.g.fires.has(u.cell()):
		return false
	for r in range(1, 20):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var c := u.cell() + Vector2i(dx, dy)
				if ai.g.world.inside(c) and ai.g.world.is_walkable(c) and not ai.g.fires.has(c):
					u.order_move(c)
					return true
	return false


## Unit::think_general_action: take a camp; a general with a small troop or
## too little leadership (or with too many camps already) is made a soldier.
static func think_general_action(ai: NationAI, u: Unit) -> bool:
	if think_leader_action(ai, u):
		return true
	var members := _team(ai, u).size()
	var demote := members <= 1
	if not demote and int(u.lead_skill()) + members * 4 < 40 + ai.pref("keep_general") / 5:
		demote = true
	if not demote and ai.has_too_many_camps():
		demote = true
	if demote:
		u.rank = Defs.Rank.SOLDIER
		return think_normal_human_action(ai, u)
	return false


## The general and the men he leads.
static func _team(ai: NationAI, u: Unit) -> Array:
	var out: Array = [u]
	for m in ai.g.units:
		if m != u and not m.dead and m.leader == u and m.inside_firm == null:
			out.append(m)
	return out


## Unit::think_leader_action: the camp where he would add most leadership
## (the king always goes to one); his troop goes with him if there is room.
static func think_leader_action(ai: NationAI, u: Unit) -> bool:
	var best: Firm = null
	var best_r := -1000 if u.rank == Defs.Rank.KING else 10
	var del_action = null
	for c in ai.camps():
		if c.should_close or c.overseer == ai.n.king:
			continue
		var r := AIFirm.new_commander_leadership(ai, c, u.race, int(u.lead_skill())) - AIFirm.cur_commander_leadership(ai, c)
		if c.overseer == null:
			r = int(u.lead_skill())
		if r > best_r:
			var a = null
			if u.rank != Defs.Rank.KING:
				a = ai.find_action(Vector2i(c.x1, c.y1), Vector2i(-1, -1), NationAI.ASSIGN_OVERSEER, c.code)
				if a != null and a["processing"] > 0:
					continue
			best_r = r
			best = c
			del_action = a
	if best == null:
		return false
	if del_action != null:
		ai.actions.erase(del_action)
	var team := _team(ai, u)
	if team.size() - 1 <= NationAI.MAX_SOLDIER - best.soldiers.size():
		for m in team:
			m.order_enter(best)
		return true
	return not ai.add_action(Vector2i(best.x1, best.y1), Vector2i(-1, -1), NationAI.ASSIGN_OVERSEER, best.code, 1, u).is_empty()


## Unit::think_normal_human_action
static func think_normal_human_action(ai: NationAI, u: Unit) -> bool:
	if u.home_firm != null:
		return false
	if ai.camps().is_empty() or AIFirm.total_camp_space(ai, false) <= ai.total_unit_count():
		if ai_build_firm(ai, u):
			return true
	if u.leader and is_instance_valid(u.leader) and not u.leader.dead and u.leader.inside_firm == null:
		return false
	if not u.is_civilian():
		return think_assign_soldier_to_camp(ai, u)
	return think_assign_human_to_town(ai, u)


## Unit::think_normal_monster_action
static func think_normal_monster_action(ai: NationAI, u: Unit) -> bool:
	if u.home_firm != null:
		return false
	if ai.n.is_fryhtan and (ai.camps().is_empty() or AIFirm.total_camp_space(ai, false) <= ai.total_unit_count()):
		return ai_build_firm(ai, u)
	if u.leader and is_instance_valid(u.leader) and not u.leader.dead and u.leader.inside_firm == null:
		return false
	return think_assign_soldier_to_camp(ai, u)


## Unit::think_assign_soldier_to_camp: a camp with room (or one whose weakest
## man he outclasses), near and of his race.
static func think_assign_soldier_to_camp(ai: NationAI, u: Unit) -> bool:
	var best: Firm = null
	var best_r := 0
	var skill := int(u.combat)
	for c in ai.camps():
		if not _can_accept(c, u):
			continue
		var r := 0
		if c.soldiers.size() + c.patrol_units.size() + c.coming_units.size() >= NationAI.MAX_SOLDIER:
			var min_skill := 100
			for s in c.soldiers:
				if s.basic_days <= 0:
					min_skill = mini(min_skill, int(s.combat))
			if skill < min_skill + (10 if AIFirm.majority_race(c) == u.race else 30):
				continue
		else:
			r += 300
		r += ai.distance_rating(u.center_loc(), c.center_loc())
		if AIFirm.majority_race(c) == u.race:
			r += 70
		r += (NationAI.MAX_SOLDIER - c.soldiers.size()) * 10
		if r > best_r:
			best_r = r
			best = c
	if best:
		u.order_enter(best)
		return true
	return false


## FirmCamp::can_accept_assign
static func _can_accept(c: Firm, u: Unit) -> bool:
	if c.under_construction or c.dead or c.nation_id != u.nation_id:
		return false
	if c.code == "LAIR":
		return SpecialFirms.is_fryhtan_unit(u)
	return (u.is_human() and not u.is_civilian()) or u.is_weapon


## Unit::think_assign_human_to_town: the nearest town of ours with room (of
## his race, when the kingdom cares for its towns' defence); with none in
## reach, build a fort or settle a village by one.
static func think_assign_human_to_town(ai: NationAI, u: Unit) -> bool:
	if not u.is_human() and not u.is_wagon():
		return false
	var best: Town = null
	var best_r := 0
	var any := false
	var race := u.settler_race()
	for t in ai.my_towns():
		if t.under_construction or t.population + u.settlers() > Defs.MAX_TOWN_POPULATION:
			continue
		any = true
		if t.race != race:          # Town::can_accept_assign: its own race only
			continue
		var r: int = ai.distance_rating(u.center_loc(), t.center_loc()) + Defs.MAX_TOWN_POPULATION - t.population
		if r > best_r:
			best_r = r
			best = t
	if best:
		u.order_settle_into(best)
		return true
	if not any:
		if ai.camps().is_empty():
			if u.leader == null or not is_instance_valid(u.leader):
				ai_build_firm(ai, u)
		else:
			ai_settle_new_town(ai, u)
		return true
	return false


## Unit::think_weapon_action: join a camp with room, else build a fort.
static func think_weapon_action(ai: NationAI, u: Unit) -> bool:
	var best: Firm = null
	var best_r := 0
	for c in ai.camps():
		if c.soldiers.size() + c.patrol_units.size() >= NationAI.MAX_SOLDIER or not _can_accept(c, u):
			continue
		var r: int = ai.distance_rating(u.center_loc(), c.center_loc()) + (NationAI.MAX_SOLDIER - c.soldiers.size()) * 10
		if r > best_r:
			best_r = r
			best = c
	if best:
		u.order_enter(best)
		return true
	if ai.n.is_fryhtan:
		return false
	var town: Town = null
	var tr := 0
	for t in ai.my_towns():
		if not t.is_base_town or t.no_neighbor_space:
			continue
		var r := ai.distance_rating(u.center_loc(), t.center_loc())
		if r > tr:
			tr = r
			town = t
	if town:
		return AITown.build_neighbor_firm(ai, town, "FORT")
	return false


## Unit::think_reward: keep loyalty above the betrayal level, more for those
## commanding many men or of high skill; a commander about to betray is
## rewarded at once.
static func think_reward(ai: NationAI, u: Unit) -> bool:
	if u.is_spy or u.is_civilian() and u.ai_action_id == 0:
		return false
	var needed := 0
	if u.ai_action_id > 0:
		needed = Defs.UNIT_BETRAY_LOYALTY + 10
	elif not u.is_civilian():
		needed = _commanded(ai, u) * 5 + int(u.combat)
		if u.inside_firm and u.inside_firm.overseer == u:
			if u.loyalty < Defs.UNIT_BETRAY_LOYALTY:
				u.reward(ai.n.id)
				return true
			needed += 30
		needed = clampi(needed, Defs.UNIT_BETRAY_LOYALTY + 10, 100)
	else:
		return false
	if u.loyalty >= needed:
		return false
	var need_r := needed - int(u.loyalty)
	if u.loyalty < Defs.UNIT_BETRAY_LOYALTY + 5:
		need_r += 50
	if ai.should_spend(need_r):
		u.reward(ai.n.id)
		return true
	return false


## Unit::commanded_soldier_count
static func _commanded(ai: NationAI, u: Unit) -> int:
	if u.inside_firm and u.inside_firm.overseer == u:
		return u.inside_firm.soldiers.size()
	return _team(ai, u).size() - 1


## Unit::ai_leader_being_attacked: the king always (weekly), a capable
## general fortnightly, calls the kingdom to his defence.
static func leader_attacked(ai: NationAI, u: Unit, attacker: GameObj) -> void:
	if attacker == null or not is_instance_valid(attacker) or attacker.nation_id == u.nation_id:
		return
	var interval := 0
	if u.rank == Defs.Rank.KING:
		interval = 7
	elif u.rank == Defs.Rank.GENERAL and u.lead_skill() >= 30 + (100 - ai.pref("keep_general")) / 2:
		interval = 15
	else:
		return
	var last := int(u.get_meta("ai_defend_day", -1000))
	if ai.g.day > last + interval:
		u.set_meta("ai_defend_day", ai.g.day)
		ai.ai_defend(attacker)


## Unit::think_king_flee: alone and idle, or hurt - to the nearest camp when
## fighting, else home.
static func think_king_flee(ai: NationAI, u: Unit) -> bool:
	if u.has_meta("ai_fleeing") and u.order != Unit.Order.IDLE:
		return true
	u.remove_meta("ai_fleeing")
	var alone := _team(ai, u).size() <= 1 and u.ai_action_id == 0
	if not (alone or u.hp < u.max_hp * (150 - ai.pref("military_courage") / 2) / 200.0):
		return false
	var best: Firm = null
	if u.attacking:
		var best_r := 0
		for c in ai.camps():
			var r := ai.distance_rating(u.center_loc(), c.center_loc())
			if r > best_r:
				best_r = r
				best = c
	elif u.home_firm and is_instance_valid(u.home_firm) and not u.home_firm.dead:
		best = u.home_firm
	if best:
		u.order_enter(best)
		if ai._aggressiveness() > GameSetup.LOW:
			u.set_meta("ai_fleeing", true)
	else:
		think_leader_action(ai, u)
	return u.order != Unit.Order.IDLE


## Unit::think_general_flee
static func think_general_flee(ai: NationAI, u: Unit) -> bool:
	if u.has_meta("ai_fleeing") and u.order != Unit.Order.IDLE:
		return true
	u.remove_meta("ai_fleeing")
	var alone := _team(ai, u).size() <= 1 and u.ai_action_id == 0
	if not (alone or u.hp < u.max_hp * (75 + ai.pref("military_courage") / 2) / 200.0):
		return false
	var best: Firm = null
	if u.attacking:
		var best_r := 0
		for c in ai.camps():
			var r := ai.distance_rating(u.center_loc(), c.center_loc())
			if r > best_r:
				best_r = r
				best = c
	elif u.home_firm and is_instance_valid(u.home_firm) and not u.home_firm.dead:
		best = u.home_firm
	if best:
		if best.overseer:
			u.order_move(Vector2i(best.x1, best.y1))
			if ai._aggressiveness() > GameSetup.LOW:
				u.set_meta("ai_fleeing", true)
		else:
			u.order_enter(best)
	else:
		think_leader_action(ai, u)
	return u.order != Unit.Order.IDLE


## Unit::ai_build_firm: a fort (a lair for Fryhtans) where the unit stands.
static func ai_build_firm(ai: NationAI, u: Unit) -> bool:
	if ai.n.is_fryhtan != SpecialFirms.is_fryhtan_unit(u):
		return false
	var code := "LAIR" if ai.n.is_fryhtan else "FORT"
	if not ai.n.is_fryhtan and (u.is_civilian() or not u.is_human()):
		return false
	if ai.action_exists(NationAI.BUILD_FIRM, code):
		return false
	var b := Assets.firm_build(code, u.race if not ai.n.is_fryhtan else ai.n.race)
	var w: int = b.get("loc_w", 6) + INTER_PLACE_SPACE * 2
	var h: int = b.get("loc_h", 6) + INTER_PLACE_SPACE * 2
	var at := ai.g._place_near(Rect2i(u.cell(), Vector2i.ONE), w, h, 12)
	if at.x < 0:
		return false
	return not ai.add_action(at + Vector2i.ONE * INTER_PLACE_SPACE, Vector2i(-1, -1), NationAI.BUILD_FIRM, code, 1, u).is_empty()


## Unit::ai_settle_new_town: a village beside our strongest camp.
static func ai_settle_new_town(ai: NationAI, u: Unit) -> bool:
	var best: Firm = null
	var best_r := 0
	for c in ai.camps():
		var r := AIFirm.total_combat_level(c)
		if r > best_r:
			best_r = r
			best = c
	if best == null or not u.can_found_town():
		return false
	var size := Defs.TOWN_SIZE + INTER_PLACE_SPACE * 2
	var at := ai.g._place_near(best.footprint(), size, size, 12)
	if at.x < 0:
		return false
	u.order_found_town(at + Vector2i.ONE * INTER_PLACE_SPACE)
	return true


## Unit::ai_attack_next_target: on an attack mission, the nearest hostile
## place or unit within 30 of the last target.
static func attack_next_target(ai: NationAI, u: Unit) -> bool:
	var from := u.target.center_loc() if u.target and is_instance_valid(u.target) else u.center_loc()
	var best: GameObj = null
	var best_d := 31.0
	for o in ai.g.firms + ai.g.towns:
		if o.dead or o.nation_id <= 0 or ai.relation(o.nation_id) != Defs.Relation.WAR:
			continue
		var d := _dist(o.center_loc(), from)
		if d < best_d:
			best_d = d
			best = o
	for o in ai.g.units_near(from, 30.0):
		if o.dead or o.inside_firm != null or o.nation_id <= 0 or ai.relation(o.nation_id) != Defs.Relation.WAR:
			continue
		var d := _dist(o.center_loc(), from)
		if d < best_d:
			best_d = d
			best = o
	if best:
		u.order_attack(best)
		return true
	u.in_attack_mission = false
	return false


## Unit::think_use_item: a summoning item now and then; invincibility when
## just attacked; invisibility while attacking (a timed item is on while its
## para is negative).
static func think_use_item(ai: NationAI, u: Unit) -> bool:
	var t := Items.info(u.item_id)
	if t.is_empty():
		return false
	var ab: int = t[Items.ABILITY]
	if ab == Items.Ability.SUMMON:
		if ai.g.rng.randi() % 100 == 0:
			u.use_manual_item(null)
			return true
		return false
	var should_on := false
	if ab == Items.Ability.INVINCIBLE:
		should_on = ai.g.frame - u.last_attacked_frame <= Defs.FRAMES_PER_DAY * 2
	elif ab == Items.Ability.INVISIBLE:
		should_on = u.order == Unit.Order.ATTACK
	else:
		return false
	var on := u.item_para < 0
	if not on and should_on:
		return u.turn_on_item()
	if on and not should_on and t[Items.PARA] == Items.Para.CHARGE_TIMED:
		u.item_para = -u.item_para        # Item::turn_off
	return false
