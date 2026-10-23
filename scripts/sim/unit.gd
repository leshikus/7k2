class_name Unit
extends GameObj
## A mobile unit: soldier, general, king, hero, siege weapon, Fryhtan or Greater Being.

enum Order { IDLE, MOVE, ATTACK, ENTER, BUILD, RETURN, DYING }

var utype: Dictionary = {}
var sprite_code := ""
var race := ""
var unit_name := ""
var rank := Defs.Rank.SOLDIER
## Combat level. A living unit's hit points follow it (Skill::actual_max_hit_points:
## the table's hit points times combat level over 100).
var combat := 10.0:
	set(v):
		combat = v
		refresh_max_hp()
var hp_scale := 1.0               # extra toughness of kings and leaders of armies
var leadership := 0.0
var loc := Vector2.ZERO           # continuous location; integers are location corners

var order := Order.IDLE
var target: GameObj = null
var order_firm: Firm = null
var resume_target: GameObj = null    # building to return to after fighting off defenders
var path: Array[Vector2i] = []
var path_i := 0
var goal := Vector2i(-1, -1)

var dir := 4
var action := "S"
var anim_frame := 0
var attacking := false
var attack_cooldown := 0
var repath_timer := 0
var scan_timer := 0

var home_town: Town = null        # set for town defenders
var home_firm: Firm = null        # set for soldiers who sallied out of a camp
var inside_firm: Firm = null
var is_hero := false
var is_god := false
var is_weapon := false
var life_frames := -1
var invulnerable_until := -1     # Athena's protection (frame)
var is_caravan := false
var is_spy := false
var spy_skill := 0.0
var spy_place: GameObj = null    # town or firm the spy has infiltrated
var spy_action := "dissent"      # idle (sleep: never caught) | dissent (Spy::action_mode)
var cloak_id := 0                # disguise: the kingdom a mobile spy passes for (0 = its own colours)
var camouflage_days := 0         # camouflaged spy: unseen by other kingdoms while > 0
var camouflage_power := 0        # recharges a day at a time (Spy::camouflage_power)
var sleeper_for := 0             # a bribed general or soldier: the kingdom he secretly serves
var loyalty := 70.0              # a soldier's or general's loyalty to his kingdom (Unit::loyalty)
var nation_contribution := 0     # Unit::nation_contribution: a point for every blow struck
var total_reward := 0            # Unit::total_reward: gold he has been rewarded with
var stops: Array = []             # caravan: up to two stops {firm, x, y, pick, picks} (UnitCaravan::stop_array)
var dest_stop := -1               # caravan: the stop it is heading for (dest_stop_id)
var journey := "none"             # caravan: none | on_way | surround | inside (journey_status)
var wait := 0                     # caravan: frames to wait (wait_count)
var market_auto := true           # caravan: markets pick up automatically (default_market_trade_mode)
var last_load_day := 0            # caravan: last_load_goods_date
var processed := {}               # caravan: what it unloaded at this stop (processed_*_qty_array)
var cargo := {}                   # caravan: "R:<raw>" / "P:<raw>" -> quantity
var wagon_pop := 0               # a wagon's settlers (UnitWagon::population)
var wagon_race := ""             # and their race
var found_site := Vector2i(-1, -1)   # where this unit goes to build a town (UNIT_SETTLE_TOWN)
var potential := 0               # Skill::skill_potential: how fast he learns (0, or 10-100)
var basic_days := 0              # days of basic training left (Soldier::remain_build_days)
var guard_frames := 0            # a raised shield (Sprite::guard_count)
var spab := ""                    # special ability in use: mirage, reflect or freeze
var spab_day := -1000             # when it was last used (last_special_ability_start_date)
var leader: Unit = null           # the general leading this man (Unit::leader_unit_recno)
var formation := 0               # a general's troop formation (TeamInfo::formation_id), 0 none
var formation_dir := Vector2.ZERO   # its facing set with the number pad (formation_direction)
var rebel_id := 0                # member of a rebel band (Unit::unit_mode REBEL)
var frozen_until := -1           # Amaterasu's freeze (frame)
var waypoints: Array = []       # further places to go after this move (Shift+right-click)
var weapon_version := 0          # war machine / Fryhtan unit: tech level it was built at (get_weapon_version)
enum Behavior { AGGRESSIVE = 1, DEFENSIVE, STAND_GROUND }
var build_plan := {}             # a building to lay out on arrival (Unit::cur_order UNIT_BUILD_FIRM)
var spy_notify := false         # Spy::notify_cloaked_nation_flag: a disguised spy keeps up his cover against his own side
var auto_retreat := 0            # Unit::auto_retreat_hit_point: % of hit points to go home at (0 off; any fighting unit here, generals only in the original)
var auto_reward := 0             # not in the original: rewarded automatically below this loyalty (0 off)
const AUTO_RETREAT_LEVELS := [0, 10, 20, 30]
const AUTO_REWARD_LEVELS := [0, 30, 40, 50]
var behavior_mode := Behavior.AGGRESSIVE    # Unit::behavior_mode
var hero_id := 0                  # HeroRes: which hero of the list he is (0: none)
var max_combat := 0               # Skill::max_combat_level (heroes and powerful units)
var item_id := 0                  # the item carried (Items.TABLE), 0 = none
var item_para := 0                # its charges, uses or time (Item::para)
var death_frames := 0
var ai_action_id := 0               # Unit::cur_order.ai_action_id: the computer's queued action it carries out
var in_attack_mission := false      # Unit::in_ai_attack_mission
var ai_no_action := false           # Unit::ai_no_suitable_action
var _speed := 4.0


func setup(sprite: String, nation: int, at: Vector2i, skill := 20.0) -> void:
	sprite_code = sprite
	utype = Defs.unit_types.get(sprite, {})
	race = utype.get("race", "")
	nation_id = nation
	loc = Vector2(at)
	is_weapon = utype.get("class", "") in ["WEAPON", "BIO_WEAP"]
	is_god = utype.get("class", "") == "GOD"
	is_caravan = utype.get("class", "") == "CARAVAN"
	combat = skill
	hp = max_hp
	_speed = float(Assets.sprites.get(sprite, {}).get("speed", 4))
	var n := Game.inst.nation(nation) if Game.inst else null
	var vt := sprite if is_weapon and Defs.unit_tech(sprite) == "" else Defs.unit_tech(sprite)
	if n and vt != "":
		weapon_version = maxi(1, n.tech_level(vt))
	# Unit::init: a unit that dies with its blow starts defensive
	behavior_mode = Behavior.DEFENSIVE if is_die_after_attack() else Behavior.AGGRESSIVE
	unit_name = Defs.random_person_name(race, Game.inst.rng) if race != "" else utype.get("name", sprite)
	# Skill::init: one in fifteen has a talent of 50-100, one 25-50, one 10-25
	match Game.inst.rng.randi() % 15:
		0: potential = 50 + Game.inst.rng.randi() % 51
		1: potential = 25 + Game.inst.rng.randi() % 26
		2: potential = 10 + Game.inst.rng.randi() % 15
	position = Iso.to_screen(loc)


## Weapons, caravans and Greater Beings keep the default combat level of 100
## (Unit::init: skill.init(unit_id, 100)); living beings scale with theirs.
func refresh_max_hp() -> void:
	var base := float(utype.get("hp", 200))
	var lvl := 100.0 if is_weapon or is_caravan or is_god else combat_level()
	max_hp = maxf(1.0, base * lvl / 100.0 * hp_scale)
	if hp > max_hp:
		hp = max_hp


## Kings and army leaders are made tougher by `k`.
func scale_hp(k: float) -> void:
	hp_scale *= k
	refresh_max_hp()
	hp = max_hp


func footprint() -> Rect2i:
	return Rect2i(cell(), Vector2i.ONE)


func cell() -> Vector2i:
	return Vector2i(roundi(loc.x), roundi(loc.y))


func center_loc() -> Vector2:
	return loc + Vector2(0.5, 0.5)


func armor() -> float:
	var a := float(utype.get("armor", 0))
	var n := nation()
	if n and race != "":
		a += 2.0 * n.tech_level("INFDEFEN")
	return a + item_ability(Items.Ability.ARMOR)


## What the carried item adds toward an ability now (ItemRes::ability).
func item_ability(ab: int) -> int:
	return Items.ability(item_id, item_para, ab) if item_id > 0 else 0


## The item did its work once: spend a use or charge (ItemRes::use_now).
func use_item() -> void:
	item_para = Items.use_now(item_id, item_para)
	if item_para < 0:
		item_id = 0
		item_para = 0


## Switches on a timed item (Staff of Invincibility, Unseen Torque).
func turn_on_item() -> bool:
	if not Items.can_turn_on(item_id, item_para):
		return false
	item_para = Items.turn_on(item_id, item_para)
	return true


## ItemRes::use_manually: Heimdall's Horn summons a Fryhtan to fight for us, the
## Judas Ring wins over a unit and the Judas Rod a town, the Neutralizer frees a
## town, the Telecordial carries the unit anywhere. Returns "" or why it failed.
## The player's use of the item: a refusal is reported to its owner.
func use_item_cmd(target = null) -> void:
	var err := use_manual_item(target)
	if err != "" and nation_id == Game.inst.player_id:
		Game.inst.notify(err, Vector2(-1, -1))


func use_manual_item(target = null) -> String:
	var g := Game.inst
	match item_id:
		13:
			var m: Dictionary = Defs.monsters[g.rng.randi() % Defs.monsters.size()]
			var level := maxi(3, int(m["level"]))
			var skill := minf(Defs.MAX_COMBAT_TRAIN, float(7 * int(Defs.MAX_COMBAT_TRAIN) + g.rng.randi() % int(Defs.MAX_COMBAT_TRAIN)) / (5 + level))
			if g.spawn_unit(m["unit"], nation_id, cell() + Vector2i(2, 2), skill) == null:
				return "There is no room to summon a Fryhtan here."
		25:
			var t := target as Unit
			if t == null or t.dead or t.rank == Defs.Rank.KING or t.nation_id == nation_id or t.nation_id <= 0 					or t.is_monster() or t.inside_firm or distance_to(t) > 8.0:
				return "Use the Judas Ring on an enemy unit (not a king) within 8 squares."
			g.defect_unit(t, nation_id)
		26:
			var t := target as Town
			if t == null or t.dead or t.nation_id == nation_id or distance_to(t) > 8.0:
				return "Use the Judas Rod on another kingdom's or an independent town within 8 squares."
			t.surrender(nation_id)
		27:
			var t := target as Town
			if t == null or t.dead or t.nation_id <= 0 or distance_to(t) > 8.0:
				return "Use the Neutralizer on a kingdom's town within 8 squares."
			var old := t.nation_id
			t.nation_id = 0
			for nid in g.nation_ids():
				t.resistance[nid] = 60.0
			g.on_town_changed(t, old)
			t.queue_redraw()
		28:
			var c: Vector2i = target if target is Vector2i else Vector2i(-1, -1)
			if c.x < 0 or not g.world.is_free(c) or not g.is_loc_explored(c):
				return "Teleport to an explored, open spot."
			stop()
			loc = Vector2(c)
			position = Iso.to_screen(loc)
		_:
			return "This item works by itself."
	use_item()
	return ""


## Skill::combat_level: training plus the item's bonus (Excalibur).
func combat_level() -> float:
	return combat + item_ability(Items.Ability.COMBAT_LEVEL)


## Skill::skill_level: leadership plus the item's bonus (The Art of War).
func lead_skill() -> float:
	return leadership + item_ability(Items.Ability.SKILL_LEVEL)


## UnitInfo::is_human: a person - not a war machine, a Greater Being or a
## Fryhtan (whose species stands in for its race).
func is_human() -> bool:
	return race != "" and not is_weapon and not is_god and not (utype.get("class", "") in SpecialFirms.FRYHTAN_CLASSES)


## Villagers (the *_CIV sprites) build, settle and spy but never garrison a fort.
func is_civilian() -> bool:
	return sprite_code.ends_with("_CIV")


func can_lead() -> bool:
	return is_human() and (rank >= Defs.Rank.GENERAL)


func display_name() -> String:
	var title := ""
	match rank:
		Defs.Rank.KING:
			title = "King "
		Defs.Rank.GENERAL:
			title = "General "
	if is_human():
		return title + unit_name
	return utype.get("name", sprite_code)


func type_name() -> String:
	return utype.get("name", sprite_code)


func speed_loc() -> float:
	var sp := _speed + item_ability(Items.Ability.SPEED)
	# SpriteRes::update_speed: rain slows units by their RAIN_SLOW value
	var rain := mini(7, Game.inst.weather.rain_scale())
	var slow: int = Assets.sprites.get(sprite_code, {}).get("rain_slow", 0)
	if rain > 0 and slow > 0:
		sp = maxf(1.0, sp - (rain * slow / 8 + 1))
	var s := sp / Defs.LOC
	if Game.inst.world.is_hill(cell()):
		s *= 0.75
	return s


# ------------------------------------------------------------------ orders ---

func stop() -> void:
	build_plan = {}
	resume_target = null
	order = Order.IDLE
	target = null
	order_firm = null
	path.clear()
	path_i = 0


func order_move(dest: Vector2i) -> void:
	if dead or inside_firm:
		return
	stop()
	order = Order.MOVE
	_path_to(dest)


## A disguised spy is judged by its cloak (see Game.is_hostile).
func seen_nation() -> int:
	return Espionage.cloak_nation(self) if is_spy else nation_id


func order_attack(obj: GameObj) -> void:
	if cloak_id != 0 and obj and obj.nation_id != nation_id:
		Espionage.drop_cloak(self)     # attacking gives a disguised spy away
	if dead or inside_firm or obj == null or obj == self or not can_attack():
		return
	stop()
	order = Order.ATTACK
	target = obj
	repath_timer = 0


## Spy: walk to a town, fort or camp and slip inside. A kingdom's place only
## lets in one of its own, so the spy first puts on its colours (which fails
## with enemies close by). Returns false when the spy cannot go there.
func order_infiltrate(target_obj: GameObj) -> bool:
	if not is_spy or dead or inside_firm or target_obj == null or not Espionage.can_enter(self, target_obj):
		return false
	var need := Espionage.cloak_needed(self, target_obj)
	if need > 0 and cloak_id != need and not Espionage.set_cloak(self, need):
		return false
	stop()
	order = Order.ENTER
	order_firm = null
	spy_place = target_obj
	_path_to(Game.inst.world.adjacent_to_rect(target_obj.footprint(), cell()))
	return true


func order_enter(f: Firm) -> void:
	if dead or inside_firm:
		return
	stop()
	order = Order.ENTER
	order_firm = f
	_path_to(Game.inst.world.adjacent_to_rect(f.footprint(), cell()))


## Walk to the nearest own town of the same race and rejoin its population.
## Player commands (sent through Net.cmd in a network game).
const PROMOTE_LOYALTY_INCREASE := 20.0     # gamedef.h
const DEMOTE_LOYALTY_DECREASE := 40.0


## Unit::set_rank(RANK_GENERAL): loyalty +20, out of his general's team, and
## a leadership of up to 39 if he had hardly any.
func promote() -> void:
	if is_human() and rank == Defs.Rank.SOLDIER and not is_civilian():
		loyalty = minf(100.0, loyalty + PROMOTE_LOYALTY_INCREASE)
		leader = null
		rank = Defs.Rank.GENERAL
		if leadership < 10.0:
			leadership = float(Game.inst.rng.randi() % 40)


const REWARD_COST := 30.0                # gamedef.h
const REWARD_LOYALTY_INCREASE := 10.0


## Unit::reward: 30 gold for 10 more loyalty; not the king, not a war machine.
func reward(from_nation: int) -> void:
	var n := Game.inst.nation(from_nation)
	if n == null or n.cash < REWARD_COST or rank == Defs.Rank.KING or not is_human():
		return
	if nation_id == from_nation:
		total_reward += int(REWARD_COST)
		loyalty = minf(100.0, loyalty + REWARD_LOYALTY_INCREASE)
	n.add_cash(-REWARD_COST, "Rewards")


## The share of hit points this unit goes home at: its own setting, else a
## computer kingdom's standing order (an addition) - generals at 30%, the
## other fighting men at 20%.
func retreat_level() -> int:
	if auto_retreat > 0:
		return auto_retreat
	var n := nation()
	if n and n.ai != null and nation_id != Game.inst.player_id and can_attack() and not is_caravan and not is_wagon():
		return 30 if rank == Defs.Rank.GENERAL else 20
	return 0


## UnitArray::process (auto_retreat_hit_point) and the automatic reward,
## once a day for a unit in the field (rewards in buildings too).
func auto_orders() -> void:
	if dead or rank == Defs.Rank.KING:
		return
	if auto_reward > 0 and loyalty < auto_reward and is_human() and not is_civilian() and nation_id > 0:
		var n := nation()
		if n and n.cash >= REWARD_COST:
			reward(nation_id)
	var ar := retreat_level()
	if ar > 0 and inside_firm == null and not has_meta("hidden") and hp < max_hp * ar / 100.0 \
			and order != Order.ENTER and can_attack():
		return_to_base()


## Unit::resign: the unit is disbanded. People let go wander the land (two
## for one, so that it shows); Fryhtans give their life to the other Fryhtan
## kingdoms.
func resign() -> void:
	var g := Game.inst
	if dead or rank == Defs.Rank.KING:
		return
	if is_human():
		g.race_wanderers[race] = int(g.race_wanderers.get(race, 0)) + 2
	var n := nation()
	if n and n.is_fryhtan:
		var others: Array = g.nations.filter(func(o): return o.alive and o.is_fryhtan and o.id != nation_id)
		for o in others:
			o.live_points += (10.0 if is_human() else 4.0) / others.size()
	if inside_firm:
		inside_firm.release_unit(self)
	g._drop_item(self)
	for m in g.units:
		if m.leader == self:
			m.leader = null
	g.remove_unit(self)


## Spy::drop_spy_identity: no longer a spy - an ordinary unit of the side he
## now passes for.
func drop_spy_identity() -> void:
	if not is_spy or dead or inside_firm != null or has_meta("hidden"):
		return
	var to := Espionage.cloak_nation(self)
	is_spy = false
	spy_skill = 0.0
	camouflage_days = 0
	cloak_id = 0
	if to != nation_id:
		Game.inst.defect_unit(self, to)
	queue_redraw()


## Unit::can_succeed_king: while the throne is empty, any soldier or general
## of a human kingdom, or a Fryhtan of the kingdom's own species.
func can_succeed_king() -> bool:
	var n := nation()
	if n == null or dead or rank == Defs.Rank.KING:
		return false
	if n.king != null and is_instance_valid(n.king) and not n.king.dead:
		return false
	if n.is_fryhtan:
		return sprite_code == n.monster_code
	return is_human() and not is_civilian()


## Unit::set_rank(RANK_SOLDIER): loyalty -40, and the men he led have no
## general any more.
func demote() -> void:
	if rank == Defs.Rank.GENERAL:
		loyalty = maxf(0.0, loyalty - DEMOTE_LOYALTY_DECREASE)
		for m in Game.inst.units:
			if m.leader == self:
				m.leader = null
		rank = Defs.Rank.SOLDIER


## "Return": back into the nearest building of the kingdom that has room for
## him (a fort or camp, a lair or Fortress for Fryhtans).
func return_to_base() -> bool:
	# Unit::return_camp: the home camp first, if it still has room
	if home_firm and is_instance_valid(home_firm) and not home_firm.dead and home_firm.nation_id == nation_id \
			and home_firm.soldiers.size() < home_firm.capacity() and (home_firm.is_military() or home_firm.code == "FORTRESS"):
		order_enter(home_firm)
		return true
	var best: Firm = null
	var bd := INF
	for f in Game.inst.firms:
		if f.nation_id != nation_id or f.dead or f.under_construction:
			continue
		if not (f.is_military() or f.code == "FORTRESS") or f.soldiers.size() >= f.capacity():
			continue
		if f.code in ["CAMP", "FORT"] and not can_garrison():
			continue
		if f.code in ["LAIR", "FORTRESS"] and is_human() and Defs.unit_types.get(sprite_code, {}).get("class", "") == "HUMAN":
			continue
		var dd := distance_to(f)
		if dd < bd:
			bd = dd
			best = f
	if best == null:
		return false
	order_enter(best)
	return true


func can_settle() -> bool:
	return Game.inst.towns.any(func(t): return t.nation_id == nation_id and t.race == settler_race() and not t.dead and not t.under_construction)


## A move ordered by the player: the unit no longer belongs to a camp's sally.
func order_move_free(dest: Vector2i) -> void:
	home_firm = null
	found_site = Vector2i(-1, -1)
	waypoints.clear()
	order_move(dest)


## Shift+right-click: one more place on the way (owaypnt.cpp).
func add_waypoint(dest: Vector2i) -> void:
	if order == Order.MOVE:
		waypoints.append(dest)
	else:
		order_move_free(dest)


func is_wagon() -> bool:
	return sprite_code == "WAGON"


## The people a unit brings to a town: a wagon's settlers, or himself.
func settlers() -> int:
	return wagon_pop if is_wagon() else 1


func settler_race() -> String:
	return wagon_race if is_wagon() else race


## Human units other than the king, and wagons, may build a town (SETTLE).
func can_found_town() -> bool:
	return not dead and inside_firm == null and rank != Defs.Rank.KING and (is_wagon() or (is_human() and not is_spy and not is_caravan))


## Unit::settle_town: go to the place and build a town there.
func order_found_town(at: Vector2i) -> void:
	if not can_found_town():
		return
	order_move_free(Game.inst.world.adjacent_to_rect(Rect2i(at, Vector2i.ONE * Defs.TOWN_SIZE), cell()))
	found_site = at


func order_settle() -> bool:
	var best: Town = null
	var best_d := INF
	for t in Game.inst.towns:
		if t.nation_id == nation_id and t.race == settler_race() and not t.dead and not t.under_construction \
				and t.population + settlers() <= Defs.MAX_TOWN_POPULATION:
			var d := t.center_loc().distance_to(center_loc())
			if d < best_d:
				best_d = d
				best = t
	if best == null:
		return false
	stop()
	home_town = best
	order = Order.RETURN
	return true


## Unit::assign to a town: walk to the given town of the kingdom and join it.
func order_settle_into(t: Town) -> bool:
	if t == null or t.dead or t.nation_id != nation_id or t.race != settler_race() or t.under_construction \
			or t.population + settlers() > Defs.MAX_TOWN_POPULATION or rank == Defs.Rank.KING:
		return false
	stop()
	home_town = t
	order = Order.RETURN
	return true


func order_build(f: Firm) -> void:
	var n := nation()
	if dead or inside_firm or not (is_human() or (n and n.is_fryhtan)):
		return
	stop()
	order = Order.BUILD
	order_firm = f
	_path_to(Game.inst.world.adjacent_to_rect(f.footprint(), cell()))


## Unit::execute_build_firm: next to the place, lay the building out.
func _do_build_site() -> bool:
	var r := _plan_rect()
	var c := cell()
	var dx := maxi(0, maxi(r.position.x - c.x, c.x - (r.end.x - 1)))
	var dy := maxi(0, maxi(r.position.y - c.y, c.y - (r.end.y - 1)))
	if maxi(dx, dy) <= 1:
		var plan := build_plan
		stop()
		Game.inst.build_firm_now(nation_id, plan, self)
		return false
	if path_i >= path.size():
		repath_timer -= 1
		if repath_timer <= 0:
			repath_timer = 20
			_path_to(Game.inst.world.adjacent_to_rect(r, c))
			if path.is_empty():
				stop()
		return false
	_step_move()
	return true


## Unit::build_firm: walk to the place; the building is laid out (and paid
## for) on arrival.
func order_build_site(plan: Dictionary) -> void:
	var n := nation()
	if dead or inside_firm or not (is_human() or (n and n.is_fryhtan)):
		return
	stop()
	build_plan = plan
	order = Order.BUILD
	order_firm = null
	_path_to(Game.inst.world.adjacent_to_rect(_plan_rect(), cell()))


func _plan_rect() -> Rect2i:
	var b := Assets.firm_build(build_plan["code"], build_plan["race"])
	return Rect2i(Vector2i(int(build_plan["pos"][0]), int(build_plan["pos"][1])), Vector2i(b.get("loc_w", 3), b.get("loc_h", 3)))


func can_attack() -> bool:
	return sprite_code == "EXPCART" or not utype.get("attacks", []).is_empty()


func _path_to(dest: Vector2i) -> void:
	goal = dest
	path = Game.inst.world.find_path(cell(), dest)
	path_i = 0
	if not path.is_empty() and path[0] == cell():
		path_i = 1


# --------------------------------------------------------------- simulation ---

func sim_frame() -> void:
	if cast_target.x >= 0:
		_check_cast()
	if guard_frames > 0:
		guard_frames += 1
		if guard_frames > Defs.GUARD_COUNT_MAX:
			guard_frames = 0
	if inside_firm or spy_place != null and has_meta("hidden"):
		return
	if dead:
		_dying()
		return
	if life_frames > 0:
		life_frames -= 1
		if life_frames == 0:
			die(null)
			return
	if attack_cooldown > 0:
		attack_cooldown -= 1
	if frozen_until > Game.inst.frame:
		queue_redraw()
		return
	var moved := false
	if attacking:
		_attack_anim()
	else:
		match order:
			Order.IDLE:
				if is_caravan:
					Caravans.think(self)
				else:
					_idle()
			Order.MOVE:
				moved = true
				if _step_move():
					if found_site.x >= 0:
						var site := found_site
						found_site = Vector2i(-1, -1)
						stop()
						Game.inst.found_town(self, site)
					elif waypoints.is_empty():
						stop()
					else:
						order_move(waypoints.pop_front())
			Order.ATTACK:
				moved = _do_attack()
			Order.ENTER, Order.BUILD:
				moved = _do_enter()
			Order.RETURN:
				moved = _do_return()
	if not attacking:
		action = "M" if moved else "S"
		if guard_frames > 0:
			action = "GM" if moved and Assets.has_action(sprite_code, "GM") else ("G" if Assets.has_action(sprite_code, "G") else action)
		anim_frame = anim_frame + 1 if moved else 0
	position = Iso.to_screen(loc)
	queue_redraw()


func _step_move() -> bool:
	if path_i >= path.size():
		return true
	var next := path[path_i]
	if not Game.inst.world.is_walkable(next) and next != cell():
		# The way got blocked (a building went up): look for a new path.
		_path_to(goal)
		if path.is_empty():
			return true
		return false
	var step := speed_loc()
	# A step that reaches a cell carries on toward the next one, so the unit keeps
	# an even pace instead of stalling for a frame at every cell.
	while true:
		var d := Vector2(next) - loc
		var nd := Iso.dir_of(d)
		if nd >= 0:
			dir = nd
		if d.length() > step:
			loc += d.normalized() * step
			return false
		loc = Vector2(next)
		step -= d.length()
		path_i += 1
		if path_i >= path.size():
			return true
		next = path[path_i]
		if step <= 0.0001 or not Game.inst.world.is_walkable(next):
			return false
	return false


func _idle() -> void:
	scan_timer -= 1
	if scan_timer > 0:
		return
	scan_timer = 10 + (obj_id % 7)
	# Step aside when sharing a location with another unit.
	var c := cell()
	if Game.inst.unit_cells.get(c, 0) > 1 and obj_id % 2 == 0 and not is_god:
		var free := Game.inst.free_unit_cell(c)
		if free != c:
			order = Order.MOVE
			_path_to(free)
			return
	if not can_attack() or sprite_code == "EXPCART":
		return      # a Porcupine waits for its orders
	var enemy := Game.inst.find_enemy_near(self, float(utype.get("vis", 5)))
	if enemy and will_engage(enemy):
		order_attack(enemy)
		return
	if home_firm and (not is_instance_valid(home_firm) or home_firm.dead):
		home_firm = null
	if home_town and (not is_instance_valid(home_town) or home_town.dead):
		home_town = null
	if home_firm:
		order_enter(home_firm)
	elif home_town:
		order = Order.RETURN


# ------------------------------------------------------------- caravans ---

const CARAVAN_CARRY := 200.0      # MAX_CARAVAN_CARRY_QTY


## Player commands (UnitCaravan::set_stop, set_stop_pick_up, del_stop,
## duplicate_caravan); the logic is in Caravans.
func set_caravan_stop(i: int, f: Firm) -> bool:
	return Caravans.set_stop(self, i, f)


func del_caravan_stop(i: int) -> void:
	Caravans.del_stop(self, i)


func set_caravan_pick_up(i: int, what: String) -> void:
	Caravans.set_pick_up(self, i, what)


func duplicate_caravan() -> Unit:
	return Caravans.duplicate_of(self)


static func _nonzero(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		if d[k] > 0.5:
			out[k] = d[k]
	return out


## The attacks this unit has: a war machine or Fryhtan unit whose table lists
## one set of attacks per tech level uses the set of its version.
var _atk_cache: Array = []
var _atk_cache_ver := -1


func attack_list() -> Array:
	if _atk_cache_ver == weapon_version:
		return _atk_cache
	var atts: Array = utype.get("attacks", [])
	var maxl := _version_levels()
	if weapon_version > 0 and maxl > 1 and atts.size() >= maxl and atts.size() % maxl == 0:
		var per := atts.size() / maxl
		var v := clampi(weapon_version, 1, maxl)
		atts = atts.slice((v - 1) * per, v * per)
	_atk_cache = atts
	_atk_cache_ver = weapon_version
	return atts


func _version_levels() -> int:
	var vt := Defs.unit_tech(sprite_code)
	if vt == "" and is_weapon:
		vt = sprite_code
	return int(Defs.tech_def(vt).get("max", 0)) if vt != "" else 0


func _versioned_attacks() -> bool:
	return attack_list().size() != utype.get("attacks", []).size()


## Unit::can_attack_with: a special unit's power attack needs the Berserker tech.
func _berserk_locked(a: Dictionary) -> bool:
	if a.get("consume", 0) < 20 or not is_human() or not sprite_code.ends_with("_SPU"):
		return false
	var n := nation()
	return n == null or n.tech_level(Defs.spu_berserk_tech(race)) <= 0


func current_attack() -> Dictionary:
	var best: Dictionary = {}
	var atts: Array = attack_list()
	var far := target != null and is_instance_valid(target) and distance_to(target) > 1.5
	for a in atts:
		if a["combat_lvl"] > combat_level() or _berserk_locked(a):
			continue
		if best.is_empty():
			best = a
		elif far and a["range"] > best["range"]:
			best = a
		elif not far and a["range"] <= 1 and a["damage"] > best["damage"]:
			best = a
	if best.is_empty() and not atts.is_empty():
		best = atts[0]
	return best


func _target_gone() -> bool:
	if target == null or not is_instance_valid(target) or target.dead:
		return true
	if target is Unit and (target as Unit).inside_firm != null:
		return true
	# a town or building that has just surrendered to us
	if target.nation_id == nation_id and nation_id != 0:
		return true
	return false


func _do_attack() -> bool:
	if _target_gone():
		var next := resume_target
		stop()
		scan_timer = 0
		if next and is_instance_valid(next) and not next.dead:
			order_attack(next)
		return false
	if sprite_code == "EXPCART":
		if distance_to(target) <= 1.5:
			explode()
			return false
		var att_c := {"range": 1}
		return _close_in(att_c)
	var att := current_attack()
	if att.is_empty():
		stop()
		return false
	var dist := distance_to(target)
	if dist <= float(att["range"]):
		path.clear()
		path_i = 0
		var nd := Iso.dir_of(target.center_loc() - center_loc())
		if nd >= 0:
			dir = nd
		if attack_cooldown <= 0:
			attacking = true
			action = att["action"]
			anim_frame = 0
		return false
	return _close_in(att)


func _close_in(att: Dictionary) -> bool:
	var dist := distance_to(target)
	repath_timer -= 1
	if repath_timer <= 0 or path_i >= path.size():
		repath_timer = 15 + obj_id % 7
		var dest: Vector2i
		if target is Unit:
			dest = (target as Unit).cell()
		else:
			dest = Game.inst.world.adjacent_to_rect(target.footprint(), cell())
		# keep the current path while it still leads near the target: a path search
		# per attacker every few frames dominated big battles
		var moved := float((dest - goal).length_squared())
		var far := float((dest - cell()).length_squared())
		if path_i >= path.size() or moved > 4.0 + far * 0.04:
			_path_to(dest)
			if path.is_empty() and dist > float(att["range"]):
				stop()
				return false
	_step_move()
	return true


func _attack_anim() -> void:
	var n := Assets.action_len(sprite_code, action, dir)
	if n <= 0:
		n = 6
	anim_frame += 1
	if anim_frame >= n:
		attacking = false
		anim_frame = 0
		action = "S"
		if not _target_gone():
			_deliver_hit()


## Unit::actual_damage: the attack's damage plus 0-2, a share of its piercing
## damage by combat level (up to the trained maximum), the item, a hero's
## extra 1 for every 50 combat, the infantry techs, and the leading general's
## leadership share (at most 10).
func roll_damage(att: Dictionary) -> float:
	var rng := Game.inst.rng
	var base := float(att["damage"]) + rng.randi_range(0, 2)
	var c := combat_level()
	var deci := float(att["pierce"]) * rng.randi_range(0, int(minf(c, Defs.MAX_COMBAT_TRAIN)))
	var extra := item_ability(Items.Ability.ARROW_DAMAGE if att["range"] > 1 else Items.Ability.MELEE_DAMAGE)
	if extra > 0:
		base += extra
		use_item()
	if c > Defs.MAX_COMBAT_TRAIN:
		deci += c * 2.0
	var n := nation()
	if n and is_human() and (sprite_code.ends_with("_INF") or sprite_code.ends_with("_SPU")):
		base += 2.0 * n.tech_level("INFRANGE" if att["range"] > 1 else "INFCLOSE")
	var lead := leading_general()
	if lead:
		var bonus := minf(base * lead.lead_skill(), 1000.0)
		deci += bonus
		if lead.race == "CELTIC" and sprite_code == "CE_SPU":
			deci += bonus
	var dmg := base + deci / 100.0
	if is_weapon and n and not _versioned_attacks():
		dmg *= 1.0 + 0.25 * maxi(0, n.tech_level(sprite_code) - 1)
	# Place::being_attack_hit: a Killer Bee stings buildings five times as hard
	if sprite_code == "BEE" and target and is_instance_valid(target) and not (target is Unit):
		dmg *= 5.0
	# AttackAttribute::effectiveness against the target's defence
	if target and is_instance_valid(target) and target.has_method("defense"):
		dmg *= Defs.effectiveness(att.get("att", [0, 0, 0, 0]), target.defense())
	# a blow from behind does half again, from the side a quarter more
	if target is Unit:
		var diff := absi(dir - (target as Unit).dir) % 8
		diff = mini(diff, 8 - diff)
		dmg += dmg * (4 - diff) / 8.0
	return dmg


## Sprite::can_stand_guard / can_move_guard: the sprite has the shield frames
## and the unit's combat has reached its guard level.
func can_guard(moving: bool) -> bool:
	if combat_level() < int(utype.get("guard_level", 0)):
		return false
	return Assets.has_action(sprite_code, "GM" if moving else "G")


## Unit::obj_power: its hit points, a war machine's weapon power counting 15 a point.
func obj_power() -> float:
	if is_weapon or is_caravan:
		return hp + float(utype.get("weapon_power", 0)) * 15.0 + float(maxi(0, weapon_version - 1)) * 15.0
	return hp


func is_guarding() -> bool:
	return guard_frames > 0


## Bullet::warn_target: an arrow about to land makes the units around raise
## their shields if they can and it comes from the front.
func warned(bullet_dir: int) -> void:
	if dead or guard_frames > 0:
		return
	if order == Order.IDLE and not attacking and can_guard(false):
		dir = (bullet_dir + 4) % 8          # turn to face the arrow
		guard_frames = 1
	elif order == Order.MOVE and can_guard(true) and _dir_diff(dir, bullet_dir) >= 3:
		guard_frames = 1


static func _dir_diff(a: int, b: int) -> int:
	var d := absi(a - b) % 8
	return mini(d, 8 - d)


## Bullet::hit_target's reductions: a shield facing the arrow takes 10 off (4
## while attacking); Japanese and Chinese special units sometimes shrug off up to 9.
func arrow_reduction(dmg: float, bullet_dir: int) -> float:
	if is_guarding() and _dir_diff(dir, bullet_dir) >= 3:
		dmg -= 4.0 if attacking else 10.0
	if sprite_code in ["JA_SPU", "CH_SPU"] and dmg > 0.0:
		var r := Game.inst.rng.randi() % 10
		if r >= 7:
			dmg -= r
	return dmg


func special_ability() -> String:
	var g := Game.inst
	if spab != "" and g.day - spab_day < Defs.SPECIAL_ABILITY_DURATION:
		return spab
	return ""


## Unit::think_use_special_ability (daily): men above battle-hardened combat,
## or heroes who could become so, now and then call on their special power.
func think_special_ability() -> void:
	if not is_human() or is_civilian() or dead:
		return
	var level := 0
	if combat_level() > 200.0:
		level = int(combat_level()) / 4
	elif is_hero:
		level = 1
	else:
		return
	var g := Game.inst
	if g.day - spab_day < Defs.SPECIAL_ABILITY_DELAY:
		return
	if g.rng.randi() % (100 + level) < 100:
		return
	var ab: String = Defs.SPECIAL_ABILITY.get(sprite_code, "")
	if ab == "":
		return
	spab = ab
	# mirage arrows last twice as long
	spab_day = g.day + (Defs.SPECIAL_ABILITY_DURATION if ab == "mirage" else 0)


## Unit::attack (SPAB_FREEZE): a blow freezes enemies of the target's kingdom
## within 8 cells for 40 frames, unless their combat saves them.
func _freeze_around(tgt: GameObj) -> void:
	var g := Game.inst
	for o in g.units_near(center_loc(), 8.5):
		if o == tgt or o.dead or o.inside_firm != null or o.nation_id != tgt.nation_id:
			continue
		if g.rng.randi() % maxi(1, int(o.combat_level())) < g.rng.randi() % maxi(1, int(combat_level() / 2.0)):
			if o.frozen_until <= g.frame:
				o.frozen_until = g.frame + 40


## The general whose leadership counts (leader_unit_recno): one in the field
## within EFFECTIVE_LEADING_DISTANCE, or the commander of the fort the man
## came out of, measured from the fort.
func leading_general() -> Unit:
	var l: Unit = leader
	if (l == null or not is_instance_valid(l) or l.dead) and home_firm and is_instance_valid(home_firm) and not home_firm.dead:
		l = home_firm.overseer
	if l == null or not is_instance_valid(l) or l.dead or l == self or l.nation_id != nation_id:
		return null
	var at: Vector2 = l.inside_firm.center_loc() if l.inside_firm else l.center_loc()
	return l if at.distance_to(center_loc()) <= Defs.EFFECTIVE_LEADING_DISTANCE else null


## UNIT_JAGUAR / UNIT_GORILLA special attack: horsemen nearby panic and flee.
func _frighten() -> void:
	var g := Game.inst
	for o in g.units_near(center_loc(), 4.0):
		if o == self or o == target or o.dead or o.inside_firm != null or not g.is_hostile(self, o):
			continue
		var spu: String = o.sprite_code
		var flees: bool = spu in ["NO_SPU", "RO_SPU", "GR_SPU", "MO_SPU", "EG_SPU"] or (sprite_code == "GORILLA" and spu in ["CT_SPU", "IN_SPU"])
		if not flees or absf(o.center_loc().x - center_loc().x) > 3.5 or absf(o.center_loc().y - center_loc().y) > 3.5:
			continue
		var sx := 1 + g.rng.randi() % 5
		var sy := 1 + g.rng.randi() % 5
		if cell().x > o.cell().x:
			sx = -sx
		if cell().y > o.cell().y:
			sy = -sy
		o.stop()
		o.order_move_free(Vector2i(clampi(o.cell().x + sx, 0, g.world.w - 1), clampi(o.cell().y + sy, 0, g.world.h - 1)))


func _deliver_hit() -> void:
	var att := current_attack()
	if att.is_empty():
		return
	var dmg := roll_damage(att)
	if sprite_code in ["JAGUAR", "GORILLA"] and int(att.get("consume", 0)) > 0:
		_frighten()
	_item_strike(dmg)
	if visible:
		Game.inst.play_sound("S", sprite_code, att["action"], center_loc())
	if att["range"] > 1 and att["bullet"] != "" and Assets.has_sprite(att["bullet"]):
		var b := Game.inst.spawn_bullet(self, target, att["bullet"], att["bullet_speed"], dmg)
		b.radius = att.get("radius", 0)
		b.fire = att.get("fire", 0)
		# SPAB_MIRAGE_ARROW: an arrow for every enemy of the target's kingdom in
		# the same direction and within reach (not those reflecting arrows)
		if int(att.get("consume", 0)) == 0 and special_ability() == "mirage":
			for o in Game.inst.units_near(center_loc(), float(att["range"]) + 0.5):
				if o == target or o == self or o.dead or o.inside_firm != null or o.nation_id != target.nation_id:
					continue
				if o.special_ability() == "reflect" or Iso.dir_of(o.center_loc() - center_loc()) != dir:
					continue
				if o.center_loc().distance_to(center_loc()) <= float(att["range"]) + 0.5:
					var mb := Game.inst.spawn_bullet(self, o, att["bullet"], att["bullet_speed"], dmg)
					mb.radius = b.radius
					mb.fire = b.fire
	else:
		target.take_damage(dmg, self)
		if special_ability() == "freeze":
			_freeze_around(target)
		if att.get("fire", 0) > 0:
			Game.inst.set_fire(target.cell() if target is Unit else Vector2i(target.center_loc()), att["fire"])
	gain_experience()
	# Unit::attack_consume_power: a Bheema dies with its sting
	if att.get("die", false):
		hp = 0.0
		die(null)
		return
	attack_cooldown = int(att["delay"]) * 2
	# Unit::set_remain_attack_delay: Raptorsclaw strikes sooner
	var quick := item_ability(Items.Ability.ATTACK_SPEED)
	if quick > 0:
		attack_cooldown = maxi(2, attack_cooldown - quick * 2)
		use_item()


## Unit::being_attack_hit, the attacker's side: a Bane hurts its Fryhtan species
## more, the Cyrostaff may freeze the target.
func _item_strike(dmg: float) -> void:
	if item_id == 0 or not (target is Unit):
		return
	var t := target as Unit
	var bane := item_ability(Items.Ability.ANTI_MONSTER)
	if bane > 0 and Items.bane_target(item_para) == t.sprite_code:
		t.take_damage(float(bane), self)
		use_item()
	var freeze := item_ability(Items.Ability.FREEZE)
	if freeze > 0 and Game.inst.rng.randi() % 100 < freeze:
		t.frozen_until = maxi(t.frozen_until, Game.inst.frame + freeze * 2)
		use_item()


const MAX_NATION_CONTRIBUTION := 10000


## FirmCamp::can_accept_assign: a land unit that fights - a soldier, a
## Fryhtan or a war machine; not a villager, caravan, wagon or Greater Being.
func can_garrison() -> bool:
	if is_civilian() or is_caravan or is_god or is_wagon() or utype.get("flying", false):
		return false
	return is_human() or is_weapon or SpecialFirms.is_fryhtan_unit(self) or is_monster()


## Unit::is_die_after_attack: one of its attacks costs its life (it starts
## defensive, so as not to waste it).
func is_die_after_attack() -> bool:
	return attack_list().any(func(a): return a.get("die", false))


## Unit::get_behavior_mode: a troop in formation always stands its ground.
func get_behavior_mode() -> int:
	if formation > 0 or (leader and is_instance_valid(leader) and not leader.dead and leader.formation > 0):
		return Behavior.STAND_GROUND
	return behavior_mode


## Unit::max_attack_range
func max_attack_range() -> int:
	var r := 1
	for a in attack_list():
		r = maxi(r, int(a["range"]))
	return r


## Whether this unit takes on `o` of its own accord (Unit::can_attack_target's
## behaviour test): aggressive units anything in sight; defensive and
## stand-ground units only what is within reach of their weapons. Town
## defenders and rebels always fight.
func will_engage(o: GameObj) -> bool:
	if get_behavior_mode() == Behavior.AGGRESSIVE or home_town != null or rebel_id > 0:
		return true
	return not is_die_after_attack() and distance_to(o) <= max_attack_range()


## Skill::max_combat_level: 200 for a living being (MAX_COMBAT_BATTLE),
## a hero's own; Skill::max_skill_level 100 (a hero keeps more if he has it).
func combat_cap() -> float:
	return float(maxi(200, max_combat))


## Unit::gain_experience, at every blow struck: the unit's contribution to
## the kingdom and its combat level grow (more under the Celtic Greater
## Being); the general leading it, if near, gains leadership, and a man with
## a talent for it learns some by watching him.
func gain_experience() -> void:
	var g := Game.inst
	if is_human() and not is_weapon and nation_contribution < MAX_NATION_CONTRIBUTION:
		nation_contribution += 1
	var living := not is_weapon and not is_caravan and not is_god and not is_wagon() and race != ""
	if living:
		var inc := 0.10
		if nation_id > 0 and g.god_worshipped(nation_id, "CELTIC"):
			inc += 0.10 if race == "CELTIC" else 0.04
		combat = maxf(combat, minf(combat_cap(), combat + inc))
	var l := leading_general()
	if l:
		l.leadership = minf(maxf(100.0, l.leadership), l.leadership + 0.06)
		if l.potential > 0 and g.rng.randi() % maxi(1, 10 - l.potential / 10) == 0:
			l.leadership = minf(maxf(100.0, l.leadership), l.leadership + 0.12)
	if leader and is_instance_valid(leader) and not leader.dead and is_human() and potential > 0:
		if g.rng.randi() % maxi(1, 10 - potential / 10) == 0:
			leadership = minf(100.0, leadership + 0.12)


func _do_enter() -> bool:
	if is_spy and order_firm == null and spy_place != null:
		return _do_infiltrate()
	if order == Order.BUILD and order_firm == null and not build_plan.is_empty():
		return _do_build_site()
	if order_firm == null or not is_instance_valid(order_firm) or order_firm.dead:
		stop()
		return false
	if distance_to(order_firm) <= 1.0:
		var ok := false
		if order == Order.BUILD:
			ok = order_firm.set_builder(self)
		else:
			ok = order_firm.accept_unit(self)
		if not ok:
			stop()
		return false
	if path_i >= path.size():
		repath_timer -= 1
		if repath_timer <= 0:
			repath_timer = 20
			_path_to(Game.inst.world.adjacent_to_rect(order_firm.footprint(), cell()))
			if path.is_empty():
				stop()
		return false
	_step_move()
	return true


func _do_infiltrate() -> bool:
	if not is_instance_valid(spy_place) or spy_place.dead:
		spy_place = null
		stop()
		return false
	if distance_to(spy_place) <= 1.0:
		var need := Espionage.cloak_needed(self, spy_place)
		if need > 0 and cloak_id != need:
			spy_place = null       # the place changed hands on the way
			stop()
			return false
		Game.inst.spy_enter(self, spy_place)
		return false
	if path_i >= path.size():
		_path_to(Game.inst.world.adjacent_to_rect(spy_place.footprint(), cell()))
		if path.is_empty():
			stop()
			return false
	_step_move()
	return true


func _do_return() -> bool:
	if home_town == null or not is_instance_valid(home_town) or home_town.dead:
		home_town = null
		stop()
		return false
	if distance_to(home_town) <= 1.0:
		home_town.defender_returned(self)
		return false
	if path_i >= path.size():
		_path_to(Game.inst.world.adjacent_to_rect(home_town.footprint(), cell()))
		if path.is_empty():
			home_town.defender_returned(self)
			return false
	_step_move()
	return true


func take_damage(amount: float, attacker: GameObj) -> void:
	if invulnerable_until > Game.inst.frame:
		return
	# Aegis Field and the Staff of Invincibility take the blow
	if amount > 0.0 and (item_ability(Items.Ability.ABSORB_HIT) > 0 or item_ability(Items.Ability.INVINCIBLE) > 0):
		use_item()
		return
	super(amount, attacker)


# ---------------------------------------------------------- god powers ---

func god_info() -> Dictionary:
	return Defs.god_for_unit(sprite_code) if is_god else {}


func can_cast_power() -> bool:
	var gi := god_info()
	var n := nation()
	return not gi.is_empty() and gi["can_cast"] and Defs.GOD_POWERS.has(gi["race"]) and n != null and n.prayer_points >= gi["power_pray"]


## UnitGod::cast_power: the race's power around the Greater Being.
## Unit::go_cast_power: the god walks to within DO_CAST_POWER_RANGE (3) of
## the place and then casts his power on it.
const DO_CAST_POWER_RANGE := 3.0
var cast_target := Vector2i(-1, -1)


func order_cast_power(at: Vector2i) -> void:
	if not can_cast_power():
		return
	if Vector2(at).distance_to(Vector2(cell())) <= DO_CAST_POWER_RANGE:
		cast_power(at)
		return
	order_move_free(Game.inst.world.nearest_walkable(at))
	cast_target = at


func _check_cast() -> void:
	if cast_target.x < 0:
		return
	if Vector2(cast_target).distance_to(Vector2(cell())) <= DO_CAST_POWER_RANGE:
		var at := cast_target
		cast_target = Vector2i(-1, -1)
		stop()
		cast_power(at)
	elif order == Order.IDLE:
		cast_target = Vector2i(-1, -1)     # could not get there


## UnitGod::cast_power on the location `at` (default: where the god stands).
func cast_power(at := Vector2i(-1, -1)) -> bool:
	if not can_cast_power():
		return false
	var gi := god_info()
	var g := Game.inst
	var n := nation()
	n.prayer_points -= gi["power_pray"]
	if at.x < 0:
		at = cell()
	var c := Vector2(at) + Vector2(0.5, 0.5)
	var r: float = gi["cast_range"]
	var effect: String = Defs.RACE_PREFIX.get(gi["race"], "NO") + "_EFF1"
	if Assets.has_sprite(effect):
		g.spawn_sprite_effect(effect, c, nation_color())
	# UnitGod::cast_power: Indian and Carthaginian gods act on their own;
	# the others act on every location within cast_power_range of the god.
	match gi["race"]:
		"INDIAN":
			g.spawn_tornado(self, c + Vector2.from_angle(dir * PI / 4.0 - PI / 2.0) * 2.0)
		"CARTH":
			g.cast_quake(cell(), 32)          # carth_cast_quake: centred on the god
		_:
			if gi["race"] == "JAPANESE":
				_japanese_kill_spy(int(gi["cast_range"]))
			_cast_area(gi["race"], at, int(gi["cast_range"]))
	g.play_sound("S", sprite_code, "A1", c)
	return true


## UnitGod::cast_on_loc over the square of locations around `at`: units on
## the ground, the commanders of forts and camps (their share of the effect by
## how much of the building lies in it), inns, buildings and towns.
func _cast_area(race_code: String, at: Vector2i, rng_: int) -> void:
	var g := Game.inst
	var area := Rect2i(at - Vector2i.ONE * (rng_ - 1), Vector2i.ONE * (rng_ * 2 - 1))
	for u in g.units.duplicate():
		if not u.dead and u.inside_firm == null and area.has_point(u.cell()):
			_cast_on_unit(race_code, u, 1.0)
	for f in g.firms:
		if f.dead:
			continue
		var cut := area.intersection(f.footprint())
		if cut.size.x <= 0 or cut.size.y <= 0:
			continue
		var divider := float(mini(f.w, rng_) * mini(f.h, rng_))
		var share := float(cut.size.x * cut.size.y) / divider
		if Espionage.is_camp(f) and f.overseer:
			_cast_on_unit(race_code, f.overseer, 1.0 / maxf(0.01, share) if share < 1.0 else 1.0)
		if race_code == "PERSIAN" and nation_id > 0:
			f.revealed_to[nation_id] = true        # Firm::reveal_info
		if race_code == "JAPANESE" and f.code == "INN":
			for hd in f.heroes:                    # japanese_cast_inn
				hd["cost"] = int(hd["cost"] * 7 / 10)
				hd["days"] = maxi(int(hd["days"]), 10)
	if race_code == "EGYPTIAN":
		for t in g.towns:
			if not t.dead and t.nation_id == nation_id and area.intersects(t.footprint()):
				t.population = mini(Defs.MAX_TOWN_POPULATION, t.population + 10)


func _cast_on_unit(race_code: String, u: Unit, divider: float) -> void:
	var g := Game.inst
	match race_code:
		"ROMAN":
			if u.nation_id == nation_id and u.is_human() and u.rank != Defs.Rank.SOLDIER:
				u.leadership = minf(100.0, u.leadership + 30.0 / divider)
		"GREEK":
			if u.nation_id == nation_id:
				u.invulnerable_until = maxi(u.invulnerable_until, g.frame + Defs.FRAMES_PER_DAY * 30)
		"MONGOL":
			# mongol_cast_power: never the king, a spy, an independent or our own
			if u.rank == Defs.Rank.KING or u.inside_firm != null or u.is_spy or u.nation_id == 0 or u.nation_id == nation_id or u.is_god:
				return
			var turn := 100 - int(u.loyalty) / 2
			if divider > 1.0 and turn > 0 and turn < 100:
				turn = 100 - int(exp(log((100.0 - turn) / 100.0) / divider) * 100.0)
			if g.rng.randi() % 100 < turn:
				g.defect_unit(u, nation_id)


## UnitGod::japanese_kill_spy: enemy spies within range in our colours (or
## none), in towns and buildings, are exposed.
func _japanese_kill_spy(rng_: int) -> void:
	var g := Game.inst
	for s in g.spies.duplicate():
		if s.nation_id == nation_id or not is_instance_valid(s.spy_place):
			continue
		if s.cloak_id != 0 and s.cloak_id != nation_id and s.spy_place.nation_id != nation_id:
			continue
		if s.spy_place.center_loc().distance_to(center_loc()) < rng_:
			g.spy_caught(s)


func on_attacked(attacker: GameObj) -> void:
	if attacker == null or not is_instance_valid(attacker) or attacker.dead:
		return
	# Unit::auto_react_attack: standing ground, a moving unit does not turn;
	# defensive or standing ground, only an idle or fighting one fights back;
	# standing ground, only against an enemy within reach
	var mode := get_behavior_mode()
	var idle_or_fighting := order == Order.IDLE or order == Order.ATTACK or attacking
	if mode != Behavior.AGGRESSIVE and not idle_or_fighting:
		Game.inst.call_for_help(self, attacker)
		return
	if mode == Behavior.STAND_GROUND and distance_to(attacker) > max_attack_range():
		Game.inst.call_for_help(self, attacker)
		return
	if (order == Order.IDLE or order == Order.RETURN) and can_attack() and not attacking:
		order_attack(attacker)
	elif order == Order.ATTACK and can_attack() and attacker is Unit and not (is_instance_valid(target) and target is Unit) and Game.inst.is_hostile(self, attacker):
		# Defend ourselves first, then go back to the building or town we were attacking.
		var building := target
		order_attack(attacker)
		resume_target = building
	Game.inst.call_for_help(self, attacker)


## UnitExpCart: the Porcupine blows up, hurting everything within a cell and
## setting off other Porcupines within two (EXPLODE_DAMAGE 50 x ATTACK_SLOW_DOWN).
const EXPLODE_DAMAGE := 150.0


func explode() -> void:
	if dead or sprite_code != "EXPCART":
		return
	var g := Game.inst
	var c := center_loc()
	var dmg := EXPLODE_DAMAGE * (weapon_version * 0.5 if weapon_version > 2 else 1.0)
	hp = 0.0
	die(null)
	g.spawn_effect(1, loc - Vector2(0.5, 0.5))
	for u in g.units_near(c, 3.0):
		if u == self or u.dead or u.inside_firm:
			continue
		var d := c.distance_to(u.center_loc())
		if u.sprite_code == "EXPCART" and d <= 2.5:
			u.call_deferred("explode")
		elif d <= 1.6 and not u.utype.get("flying", false):
			u.take_damage(dmg, self)
	for o in g.firms + g.towns:
		if not o.dead and o.footprint().grow(1).has_point(cell()):
			o.take_damage(dmg, self)


## A Porcupine of version 2 or later is camouflaged from other kingdoms
## (UnitExpCart::is_camouflage), as is a camouflaged spy.
func hidden_from(nid: int) -> bool:
	if nid == nation_id or dead:
		return false
	if camouflage_days > 0:
		return true
	return sprite_code == "EXPCART" and weapon_version > 1


func die(killer: GameObj) -> void:
	if dead:
		return
	dead = true
	# a man dying inside a building leaves its roll
	if inside_firm != null and is_instance_valid(inside_firm):
		if inside_firm.overseer == self:
			inside_firm.overseer = null
		inside_firm.soldiers.erase(self)
		inside_firm = null
	order = Order.DYING
	attacking = false
	action = "D"
	anim_frame = 0
	death_frames = 0
	selected = false
	if visible:
		Game.inst.play_sound("S", sprite_code, "DIE", center_loc())
	Game.inst.on_unit_died(self, killer)


func _dying() -> void:
	death_frames += 1
	var n := Assets.action_len(sprite_code, "D", 0)
	if death_frames % 2 == 0 and anim_frame < n - 1:
		anim_frame += 1
	if death_frames > maxi(n * 2, 1) + 60:
		Game.inst.remove_unit(self)
		return
	queue_redraw()


# --------------------------------------------------------------------- draw ---

func _draw() -> void:
	render(self)


func render(cv) -> void:
	if inside_firm:
		return
	# the place a builder of yours is on his way to (dashed, until he lays it out)
	if not build_plan.is_empty() and nation_id == Game.inst.player_id:
		var r := _plan_rect()
		var o := -position
		var pts := [Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y), Vector2(r.position.x, r.end.y)]
		for i in 4:
			Game.draw_dashes(cv, o + Iso.to_screen(pts[i]), o + Iso.to_screen(pts[(i + 1) % 4]), Color(1, 1, 0.6, 0.8), 1.5, 5.0)
	var col := nation_color()
	if selected and not dead:
		_draw_selection(cv, col)
	var act := action
	var d := Iso.dir_map[dir]
	if dead:
		act = "D"
		if not Assets.has_action(sprite_code, "D"):
			act = "S"
		d = 0 if act == "D" else Iso.dir_map[dir]
	var fr := Assets.sprite_frame(sprite_code, act, d, anim_frame, col)
	if fr.is_empty() and act != "S":
		fr = Assets.sprite_frame(sprite_code, "S", Iso.dir_map[dir], 0, col)
	if not fr.is_empty():
		var tex: Texture2D = fr[0]
		var mod := Color(1, 1, 1, clampf(1.0 - (death_frames - 40) / 20.0, 0.0, 1.0)) if dead else Color.WHITE
		if frozen_until > Game.inst.frame:
			mod = Color(0.6, 0.8, 1.3)
		elif invulnerable_until > Game.inst.frame:
			mod = Color(1.25, 1.2, 0.8)
		if camouflage_days > 0:
			mod.a *= 0.45
		cv.draw_texture(tex, fr[1], mod)
	else:
		cv.draw_circle(Vector2(0, 16), 8, col)
	if dead:
		return
	# Unit::draw_rank_icon: always, or only when selected or pointed at
	# (the Show Unit Identities option, Config::show_all_unit_icon)
	var show_icon := selected or Game.inst.hovered == self or int(GameOptions.get_opt("show_unit_icons")) == 1
	if rank >= Defs.Rank.GENERAL and show_icon:
		# a star over a general (gold for the king), edged in the kingdom's colour
		var sc := Vector2(0, -58)
		var outer := 8.0 if rank == Defs.Rank.KING else 6.5
		var star := PackedVector2Array()
		for i in 10:
			var a := -PI / 2.0 + i * PI / 5.0
			var rr := outer if i % 2 == 0 else outer * 0.42
			star.append(sc + Vector2(cos(a), sin(a)) * rr)
		cv.draw_colored_polygon(star, Color(1, 0.85, 0.2) if rank == Defs.Rank.KING else Color(1, 1, 0.85))
		star.append(star[0])
		cv.draw_polyline(star, col, 1.5)
	if cloak_id != 0 and nation_id == Game.inst.player_id:
		# your disguised spy: its true colours in a little diamond over its head
		var c := Vector2(0, -50)
		var own := Game.inst.nation(nation_id)
		cv.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -5), c + Vector2(5, 0), c + Vector2(0, 5), c + Vector2(-5, 0)]), own.color if own else Color.WHITE)
		cv.draw_polyline(PackedVector2Array([c + Vector2(0, -5), c + Vector2(5, 0), c + Vector2(0, 5), c + Vector2(-5, 0), c + Vector2(0, -5)]), Color.BLACK, 1.0)
	if selected or hp < max_hp:
		draw_hp_bar_on(cv, Vector2(0, -44), 28)


func _draw_selection(cv, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		pts.append(Vector2(cos(a) * 18, 16 + sin(a) * 9))
	pts.append(pts[0])
	cv.draw_polyline(pts, col.lightened(0.3), 1.5)
