class_name Campaign
extends RefCounted
## The Fryhtan Wars campaign (CampaignEastWest: ocampgn*.cpp, oc_east*.cpp,
## oc_easte.cpp). Your Western Empire, the Eastern Empire and two or three
## Fryhtan kingdoms share a map of provinces. Events (letters and reports, some
## asking for your decision) move provinces between kingdoms and lead to stages:
## battles played on a map of their own, whose outcome changes the provinces.
## The flow follows the original event by event; the battles are built by
## CampaignBattle.
##
## The screen showing it (CampaignScreen) is `ui`, with the coroutines
## narrative(text), letter(text) -> reply number, attack(from, to, result, from2)
## and pick_state(candidates) -> state.

enum {
	STAGE_FRYHTAN_INVASION_1 = 1, STAGE_FRYHTAN_INVASION_2, STAGE_BUILD_UP, STAGE_BATTLE_EAST,
	STAGE_DEFENSE, STAGE_HERO_DEBUT, STAGE_FIGHT_BACK_1, STAGE_FIGHT_BACK_2,
	STAGE_EASTERN_EMPIRE_INVADE_OUR_LAND, STAGE_OPPORTUNISTIC_ATTACK, STAGE_FRYHTAN_JOINT_ATTACK,
	STAGE_FRYHTAN_RAGE_ATTACK, STAGE_JOINT_FIGHT_BACK, STAGE_DEEP_INTO_FRYHTAN_LAND,
	STAGE_ACQUIRE_MEGA_WEAPON, STAGE_USE_MEGA_WEAPON, STAGE_TERMINATE_FRYHTAN,
	STAGE_JOINT_TERMINATE_FRYHTAN, STAGE_ATTACK_EASTERN_EMPIRE_1, STAGE_ATTACK_EASTERN_EMPIRE_2,
	STAGE_NEW_KINGDOM_INVASION, STAGE_ATTACK_NEW_KINGDOM, STAGE_LAST_BATTLE,
	STAGE_EAST_JOINT_ATTACK_FRYHTAN, STAGE_UPRISING, STAGE_TRAIN_LEADERS, STAGE_GROW_POPULATION,
	STAGE_RESTORE_PROSPERITY,
}
enum {
	EVENT_FRYHTAN_TAKEOVER = 1, EVENT_RANDOM_POINT_1, EVENT_STATE_BETRAYAL, EVENT_FRYHTAN_OFFER_PEACE,
	EVENT_GIVE_THRONE, EVENT_RANDOM_POINT_2, EVENT_EASTERN_EMPIRE_OFFER_HELP,
	EVENT_FRYHTAN_ATTACK_FRYHTAN, EVENT_FRYHTAN_ASK_FOR_JOINT_ATTACK, EVENT_RANDOM_POINT_3,
	EVENT_FRYHTAN_THINK_SURRENDER, EVENT_ASK_EASTERN_EMPIRE_FOR_HELP, EVENT_ATTEMPT_TO_UNITE,
	EVENT_RANDOM_POINT_4, EVENT_ULTIMATE_VICTORY, EVENT_FRYHTAN_INVADE_EAST,
	EVENT_EAST_ASK_FOR_JOINT_ATTACK, EVENT_FRYHTAN_BREAK_UP, EVENT_PLAYER_TAKE_OVER_FRYHTAN,
	EVENT_DISBAND_FRYHTAN_ARMY, EVENT_INDEPENDENT_SURRENDER, EVENT_FRYHTAN_ARMY_REVOLT,
	EVENT_PLAYER_TAKE_OVER_EAST,
}
const STAGE_NAMES := ["", "Fryhtan Invasion", "Fryhtan Invasion", "Build Up", "Battle with the East",
	"Defence", "The Hero", "Fight Back", "Fight Back", "The Eastern Invasion", "Opportunistic Attack",
	"Joint Attack", "Fryhtan Rage", "Joint Fight Back", "Deep into Fryhtan Land", "The Mega Weapon",
	"Using the Mega Weapon", "Terminate the Fryhtans", "Joint Termination", "Attack the East",
	"Attack the East", "The New Kingdom Invades", "Attack the New Kingdom", "The Last Battle",
	"Joint Attack with the East", "Uprising", "Train Leaders", "Grow Population", "Restore Prosperity"]
const MAX_NATION := 7
const MAX_DIFFICULTY := 5
const BONUS_MAX_YEAR := 30
const SAVE_PATH := "user://saves/campaign.json"

const MINISTER_OF_WAR := "war"
const MINISTER_OF_FOREIGN_AFFAIRS := "foreign"
const MINISTER_HOME := "home"
const MINISTER_ORDO := "ordo"

var ui = null
var rng := RandomNumberGenerator.new()
var difficulty := 3
var player_race := "NORMAN"
var map := StateMap.new()
## Campaign nations by id 1..MAX_NATION: {id, type ("own"|"ai"|"monster"), race,
## color, name, king, ministers {}, relation (to you), know_base {race: true}}.
var nations := {}
var western := 1
var eastern := 2
var cur_monster := 0
var target_monster := 0
var new_kingdom := 0

var stage_id := 0
var event_id := 0
var return_event_id := 0
var stage_runs := {}
var event_runs := {}
var attacker_state := 0
var attacker2_state := 0
var target_state := 0

var hero_debut_state_count := 1
var player_beat_fryhtan_count := 0
var player_beat_fryhtan_max := 1
var monster_take_over_east_count := 0
var east_joint_attack_fryhtan_win_count := 0
var saved_player_state_count := 0
var use_fryhtan_count := 0
var use_fryhtan_max := 3
var disband_fryhtan_reply := 0
var fryhtan_surrendered_state := 0
var surrendered_fryhtan := ""
var can_use_fryhtan := false
var this_battle_use_fryhtan := false
var fryhtan_joint_attack_reward := false
var defeated_eastern_empire_invasion := false
var mega_tech := ""
var old_king_name := ""

var game_year := 1000
var score := 0
var finished := false
var victory := false
## Battle parameters chosen in a stage's prelude (goal numbers, years ...).
var stage_vars := {}
## The player's king and nobles carried from battle to battle (CampaignMember).
var king := {}
var nobles: Array = []
## Technologies unveiled so far: code -> highest level researchable
## (TechInfo::available_level, raised by unveil_new_tech).
var tech_available := {}
var win_to_unveil_tech := ""
var _last_unveil_stage := 0
var _saved_seed := 0
var _chance := 0
var _chance_acc := 0
var journal: Array = []   # what has happened, for the campaign screen


# ------------------------------------------------------------ setup ---

## Campaign::init_new_campaign + CampaignEastWest::init_new_campaign_derived.
func init_new(race: String, diff: int, seed_value: int) -> void:
	Defs.load_from_assets()
	rng.seed = seed_value
	player_race = race
	difficulty = clampi(diff, 1, MAX_DIFFICULTY)
	player_beat_fryhtan_max = 1 + rng.randi_range(0, 2)
	use_fryhtan_max = 3 + rng.randi_range(0, 2)
	map.generate(12, rng)
	nations.clear()
	add_nation("own", race)
	add_nation("ai")
	western = 1
	eastern = 2
	nations[western]["name"] = "Western Empire"
	nations[eastern]["name"] = "Eastern Empire"
	nations[western]["know_base"][race] = true
	_set_state_nations()
	_init_techs()
	king = {"name": nations[western]["king"], "combat": 60.0, "leadership": 70.0}
	if map.nation_state_count(western) == 1 or rng.randi_range(0, 2) == 0:
		set_event(EVENT_RANDOM_POINT_1)
	elif rng.randi_range(0, 1) == 0:
		set_stage(STAGE_FRYHTAN_INVASION_1)
	else:
		cur_monster = random_pick_monster_nation()
		set_event(EVENT_FRYHTAN_TAKEOVER)
	log_line("The campaign begins. Your %s holds %d provinces." % [nation_name(western), map.nation_state_count(western)])


## CampaignEastWest::set_state_nation: Fryhtans take provinces on the left edge,
## the Western Empire the rest of the left, the Eastern Empire the right.
func _set_state_nations() -> void:
	var monster_count := 0
	var max_monster := 2 + rng.randi_range(0, 1)
	var to_add := 4 + rng.randi_range(0, 2)
	var s := rng.randi_range(0, map.size() - 1) + 1
	for i in map.size():
		s += 1
		if s > map.size():
			s = 1
		var st := map.get_state(s)
		if st["cx"] > StateMap.W * 70 / 100 or not st["border"]:
			continue
		if rng.randi_range(0, 2) == 0 or monster_count == max_monster:
			for j in range(map.size(), 0, -1):
				var s2 := map.get_state(j)
				if map.is_adjacent(j, s) and s2["nation"] > 0 and is_monster(s2["nation"]):
					st["nation"] = s2["nation"]
					break
		if st["nation"] == 0:
			st["nation"] = add_nation("monster")
			monster_count += 1
		to_add -= 1
		if to_add == 0:
			break
	for i in range(1, map.size() + 1):
		var st := map.get_state(i)
		if st["nation"] != 0:
			continue
		st["nation"] = western if st["cx"] < StateMap.W * 30 / 100 else eastern
	var loops := 0
	while map.nation_state_count(western) < 2 and loops < 100:
		loops += 1
		var change := 0
		for i in range(1, map.size() + 1):
			if map.get_state(i)["nation"] == eastern and map.is_adjacent_to_nation(i, western):
				change = i
				break
		if change == 0:
			for i in range(1, map.size() + 1):
				if map.get_state(i)["nation"] == eastern:
					change = i
					break
		if change == 0:
			break
		map.get_state(change)["nation"] = western
	if map.nation_state_count(eastern) == 0:
		for i in range(map.size(), 0, -1):
			if map.get_state(i)["nation"] == western and map.nation_state_count(western) > 2:
				map.get_state(i)["nation"] = eastern
				break


## Technologies start veiled in a campaign and are unveiled stage by stage.
func _init_techs() -> void:
	tech_available.clear()
	for t in ["MINING", "MANUFACT", "FARMING", "INFCLOSE", "INFRANGE", "INFDEFEN", "CATAPULT"]:
		tech_available[t] = 1


func add_nation(type: String, race := "") -> int:
	var id := 0
	for i in range(1, MAX_NATION + 1):
		if not nations.has(i):
			id = i
			break
	if id == 0:
		return 0
	if race == "":
		race = random_unused_race(type == "monster")
	var used_colors := nations.values().map(func(n): return n["color"])
	var color := 0
	for c in Defs.NATION_COLORS.size():
		if not c in used_colors:
			color = c
			break
	var n := {"id": id, "type": type, "race": race, "color": color, "relation": Defs.Relation.NEUTRAL,
		"know_base": {}, "ministers": {}}
	n["king"] = _person_name(n)
	if type == "monster":
		n["name"] = "%s's Kwyzan" % n["king"]
		n["relation"] = Defs.Relation.WAR
	else:
		n["name"] = "%s's Kingdom" % n["king"].get_slice(" ", 0)
	nations[id] = n
	return id


func random_unused_race(monster: bool) -> String:
	var used := nations.values().map(func(n): return n["race"])
	var pool: Array = Defs.monsters.map(func(m): return m["unit"]) if monster else Defs.races.map(func(r): return r["code"])
	var free := pool.filter(func(r): return not r in used)
	if free.is_empty():
		free = pool
	return free[rng.randi() % free.size()]


func _person_name(n: Dictionary) -> String:
	if n["type"] == "monster":
		return monster_name(rng)
	return Defs.random_person_name(n["race"], rng)


## MonsterRes name syllables (MNAMEA/B/C) in one of six patterns.
static func monster_name(r: RandomNumberGenerator) -> String:
	var parts := {}
	for k in ["A", "B", "C"]:
		parts[k] = Assets.table("MNAME" + k).map(func(x): return str(x.values()[0]).strip_edges()).filter(func(x): return x != "")
		if parts[k].is_empty():
			parts[k] = {"A": ["Kra", "Zor", "Gul"], "B": ["ath", "ok", "ung"], "C": ["ax", "orr", "ith"]}[k]
	var fmt: String = ["ABABC", "ABC", "ABCABC", "ABAB", "BCBC", "BCABC"][r.randi() % 6]
	var s := ""
	for ch in fmt:
		var l: Array = parts[ch]
		s += l[r.randi() % l.size()]
	return s.substr(0, 1).to_upper() + s.substr(1).to_lower()


func is_nation_deleted(id: int) -> bool:
	return not nations.has(id)


func is_monster(id: int) -> bool:
	return nations.has(id) and nations[id]["type"] == "monster"


func is_human(id: int) -> bool:
	return nations.has(id) and nations[id]["type"] != "monster"


func race_name(id: int) -> String:
	if not nations.has(id):
		return ""
	var r: String = nations[id]["race"]
	if is_monster(id):
		for m in Defs.monsters:
			if m["unit"] == r:
				return m["name"]
	return Defs.race_name(r)


func nation_name(id: int) -> String:
	return nations[id]["name"] if nations.has(id) else "independent provinces"


func king_name(id: int) -> String:
	if id == western and not king.is_empty():
		return king.get("name", "")
	return nations[id]["king"] if nations.has(id) else ""


func minister_name(id: int, office: String) -> String:
	if not nations.has(id):
		return ""
	var n: Dictionary = nations[id]
	if not n["ministers"].has(office):
		n["ministers"][office] = _person_name(n)
	return n["ministers"][office]


## Campaign::del_nation + CampaignEastWest::del_nation.
func del_nation(id: int) -> void:
	nations.erase(id)
	if id == eastern:
		eastern = 0
	if id == cur_monster:
		cur_monster = 0
	if id == new_kingdom:
		new_kingdom = 0
		for i in nations:
			if is_human(i) and i != western and i != eastern:
				new_kingdom = i
				break


func packed_nation_count() -> int:
	return nations.size()


func state_change_nation(state: int, nid: int) -> void:
	var st := map.get_state(state)
	var old: int = st["nation"]
	st["nation"] = nid
	if old != 0 and old != western and map.nation_state_count(old) == 0:
		log_line("The %s is no more." % nation_name(old))
		del_nation(old)


func relation(nid: int) -> int:
	return nations[nid]["relation"] if nations.has(nid) else Defs.Relation.NEUTRAL


func set_relation(nid: int, rel: int) -> void:
	if nations.has(nid):
		nations[nid]["relation"] = rel


func log_line(t: String) -> void:
	journal.append("%d: %s" % [game_year, t])


# ---------------------------------------------------- random helpers ---

func random(n: int) -> int:
	return rng.randi_range(0, maxi(1, n) - 1) if n > 1 else 0


func randomize_chance() -> void:
	_chance = random(100) + 1
	_chance_acc = 0


func chance(c: int) -> bool:
	_chance_acc += c
	return _chance < _chance_acc


func set_stage(s: int) -> void:
	stage_id = s
	set_event(0)
	if s:
		stage_runs[s] = stage_runs.get(s, 0) + 1


func set_event(e: int) -> void:
	event_id = e
	if e:
		event_runs[e] = event_runs.get(e, 0) + 1
		attacker_state = 0
		attacker2_state = 0
		target_state = 0
		this_battle_use_fryhtan = false


func has_stage_run(s: int) -> bool:
	return stage_runs.get(s, 0) > 0


func has_event_run(e: int) -> bool:
	return event_runs.get(e, 0) > 0


func run_stage_once(s: int) -> bool:
	if has_stage_run(s):
		return false
	set_stage(s)
	return true


func run_event_once(e: int) -> bool:
	if has_event_run(e):
		return false
	set_event(e)
	return true


## Campaign::random_pick_attack_state: a state of the attacker next to one of
## the target nation's states, and that target state.
func random_pick_attack_state(attacker: int, target_nation: int, excluded := 0) -> bool:
	attacker_state = 0
	target_state = 0
	var cands := []
	for i in range(1, map.size() + 1):
		var st := map.get_state(i)
		if attacker and st["nation"] != attacker:
			continue
		for j in range(1, map.size() + 1):
			if map.is_adjacent(i, j) and map.get_state(j)["nation"] == target_nation and (excluded == 0 or excluded != j):
				cands.append(i)
				break
	if cands.is_empty():
		return false
	attacker_state = cands[random(cands.size())]
	var targets := []
	for j in range(1, map.size() + 1):
		if map.is_adjacent(attacker_state, j) and map.get_state(j)["nation"] == target_nation:
			targets.append(j)
	target_state = targets[random(targets.size())]
	return true


func random_pick_state(nid: int, neighbor := 0) -> int:
	var cands := []
	for i in range(1, map.size() + 1):
		if map.get_state(i)["nation"] != nid:
			continue
		if neighbor and not map.is_adjacent(i, neighbor):
			continue
		cands.append(i)
	return cands[random(cands.size())] if not cands.is_empty() else 0


## Campaign::random_pick_monster_campaign_nation.
func random_pick_monster_nation(excluded_state := 0, next_to := -1, must_next_to := false) -> int:
	if next_to < 0:
		next_to = western
	var cands := []
	var any := 0
	var sa := attacker_state
	var st := target_state
	for i in nations:
		if not is_monster(i):
			continue
		any += 1
		if random_pick_attack_state(i, next_to, excluded_state):
			cands.append(i)
	attacker_state = sa
	target_state = st
	if cands.is_empty():
		if must_next_to or any == 0:
			return 0
		for i in nations:
			if is_monster(i):
				return i
		return 0
	return cands[random(cands.size())]


func most_state_nation(race_type: int, next_to: int) -> int:
	var best := 0
	var mx := 0
	for i in nations:
		if race_type == 1 and not is_human(i) or race_type == -1 and not is_monster(i):
			continue
		if next_to and not map.are_nations_adjacent(i, next_to):
			continue
		var t := map.nation_state_count(i)
		if t > mx:
			mx = t
			best = i
	return best


func least_state_nation(race_type: int, next_to: int) -> int:
	var best := 0
	var mn := 1000
	for i in nations:
		if race_type == 1 and not is_human(i) or race_type == -1 and not is_monster(i):
			continue
		if next_to and not map.are_nations_adjacent(i, next_to):
			continue
		var t := map.nation_state_count(i)
		if t < mn:
			mn = t
			best = i
	return best


## CampaignEastWest::player_pick_attack_target: you choose a province next to
## your empire held by a Fryhtan ("monster") or human ("ai") kingdom.
func player_pick_attack_target(kind: String) -> int:
	var cands := []
	for i in range(1, map.size() + 1):
		var nid: int = map.get_state(i)["nation"]
		if nid == 0 or nid == western or not map.is_adjacent_to_nation(i, western):
			continue
		if kind == "monster" and not is_monster(nid) or kind == "ai" and not is_human(nid):
			continue
		cands.append(i)
	if cands.is_empty():
		return 0
	if cands.size() == 1:
		target_state = cands[0]
	else:
		target_state = await ui.pick_state(cands)
	var tn: int = map.get_state(target_state)["nation"]
	if kind == "monster":
		cur_monster = tn
	attacker_state = 0
	for i in range(1, map.size() + 1):
		if map.get_state(i)["nation"] == western and map.is_adjacent(i, target_state):
			attacker_state = i
			break
	return tn


## Campaign::attack_state: the attack is shown on the map; result 1 hands the
## target province to the attacker, -1 or 0 leaves it.
func attack_state(from: int, to: int, result: int, from2 := 0) -> void:
	await ui.attack(from, to, result, from2)
	if result == 1 and from:
		var winner: int = map.get_state(from)["nation"]
		var loser: int = map.get_state(to)["nation"]
		log_line("The %s takes a province from the %s." % [nation_name(winner), nation_name(loser)])
		state_change_nation(to, winner)


func rebel_attack_state(state: int, result: int) -> void:
	await ui.attack(0, state, result, 0)
	if result == -1:
		log_line("Rebels seize a province.")
		state_change_nation(state, 0)


## Triangle of a player state, a neighbouring state of one Fryhtan kingdom and
## one of another that touches both (get_triangle_states1).
func triangle_states1() -> Array:
	for h in range(map.size(), 0, -1):
		if map.get_state(h)["nation"] != western:
			continue
		for m1 in range(map.size(), 0, -1):
			var n1: int = map.get_state(m1)["nation"]
			if not is_monster(n1) or not map.is_adjacent(h, m1):
				continue
			for m2 in range(map.size(), 0, -1):
				var n2: int = map.get_state(m2)["nation"]
				if is_monster(n2) and n1 != n2 and map.is_adjacent(h, m2) and map.is_adjacent(m1, m2):
					return [h, m1, m2]
	return []


## A player state, an Eastern state and a Fryhtan state all touching (get_triangle_states2).
func triangle_states2() -> Array:
	for h in range(map.size(), 0, -1):
		if map.get_state(h)["nation"] != western:
			continue
		for e in range(map.size(), 0, -1):
			if map.get_state(e)["nation"] != eastern or eastern == 0 or not map.is_adjacent(h, e):
				continue
			for m in range(map.size(), 0, -1):
				if is_monster(map.get_state(m)["nation"]) and map.is_adjacent(h, m) and map.is_adjacent(e, m):
					return [h, e, m]
	return []


# ------------------------------------------------------------ text ---

func narrative(key: String, args: Array = []) -> void:
	await ui.narrative(CampaignText.format(CampaignText.event(key), args))


func letter(key: String, args: Array = []) -> int:
	return await ui.letter(CampaignText.format(CampaignText.event(key), args))


func war_minister() -> String:
	return minister_name(western, MINISTER_OF_WAR)


# ---------------------------------------------------------- events ---

var _idle_runs := 0

## Runs the current event. An event that comes to nothing (returns false and
## stays the current event) is run again, as the original's main loop does; after
## many fruitless runs the campaign moves on by force so it can never stall.
func process_event() -> bool:
	var e := event_id
	var r := await _run_event()
	if not r and event_id == e:
		_idle_runs += 1
		if _idle_runs > 40:
			_idle_runs = 0
			_force_progress()
	else:
		_idle_runs = 0
	return r


func _force_progress() -> void:
	match event_id:
		EVENT_RANDOM_POINT_1:
			cur_monster = random_pick_monster_nation()
			if cur_monster and random_pick_attack_state(cur_monster, western):
				set_stage(STAGE_FRYHTAN_INVASION_2 if has_stage_run(STAGE_FRYHTAN_INVASION_1) else STAGE_FRYHTAN_INVASION_1)
			else:
				set_event(EVENT_RANDOM_POINT_2)
		EVENT_RANDOM_POINT_4:
			if new_kingdom and random_pick_attack_state(western, new_kingdom):
				set_stage(STAGE_ATTACK_NEW_KINGDOM)
			elif eastern and random_pick_attack_state(western, eastern):
				set_stage(STAGE_ATTACK_EASTERN_EMPIRE_2 if map.nation_state_count(eastern) > 1 else STAGE_LAST_BATTLE)
			else:
				set_event(EVENT_ULTIMATE_VICTORY)
		_:
			set_event(EVENT_RANDOM_POINT_2 if event_id < EVENT_RANDOM_POINT_2 else EVENT_RANDOM_POINT_4)


func _run_event() -> bool:
	match event_id:
		EVENT_FRYHTAN_TAKEOVER: return await event_fryhtan_takeover()
		EVENT_RANDOM_POINT_1: return await event_random_point_1()
		EVENT_STATE_BETRAYAL: return await event_state_betrayal()
		EVENT_FRYHTAN_OFFER_PEACE: return await event_fryhtan_offer_peace()
		EVENT_GIVE_THRONE: return await event_give_throne()
		EVENT_RANDOM_POINT_2: return await event_random_point_2()
		EVENT_EASTERN_EMPIRE_OFFER_HELP: return await event_eastern_empire_offer_help()
		EVENT_FRYHTAN_ATTACK_FRYHTAN: return await event_fryhtan_attack_fryhtan()
		EVENT_FRYHTAN_ASK_FOR_JOINT_ATTACK: return await event_fryhtan_ask_for_joint_attack()
		EVENT_RANDOM_POINT_3: return await event_random_point_3()
		EVENT_FRYHTAN_THINK_SURRENDER: return await event_fryhtan_think_surrender()
		EVENT_ASK_EASTERN_EMPIRE_FOR_HELP: return await event_ask_eastern_empire_for_help()
		EVENT_ATTEMPT_TO_UNITE: return await event_attempt_to_unite()
		EVENT_RANDOM_POINT_4: return await event_random_point_4()
		EVENT_ULTIMATE_VICTORY: return await event_ultimate_victory()
		EVENT_FRYHTAN_INVADE_EAST: return await event_fryhtan_invade_east()
		EVENT_EAST_ASK_FOR_JOINT_ATTACK: return await event_east_ask_for_joint_attack()
		EVENT_FRYHTAN_BREAK_UP: return await event_fryhtan_break_up()
		EVENT_PLAYER_TAKE_OVER_FRYHTAN: return await event_player_take_over_fryhtan()
		EVENT_DISBAND_FRYHTAN_ARMY: return await event_disband_fryhtan_army()
		EVENT_INDEPENDENT_SURRENDER: return await event_independent_surrender()
		EVENT_FRYHTAN_ARMY_REVOLT: return await event_fryhtan_army_revolt()
		EVENT_PLAYER_TAKE_OVER_EAST: return await event_player_take_over_east()
	set_event(EVENT_RANDOM_POINT_1)
	return false


func event_fryhtan_takeover() -> bool:
	if cur_monster == 0:
		cur_monster = random_pick_monster_nation(0, eastern)
	if cur_monster and map.nation_state_count(western) > 1 and random_pick_attack_state(cur_monster, western):
		var two := random(2) == 0
		await narrative("1A" if two else "1A1", [race_name(cur_monster), nation_name(cur_monster)])
		await attack_state(attacker_state, target_state, 1)
		await letter("1B" if two else "1B1", [race_name(cur_monster), nation_name(cur_monster), war_minister()])
	else:
		cur_monster = random_pick_monster_nation()
	set_event(EVENT_RANDOM_POINT_1)
	return true


func event_random_point_1() -> bool:
	cur_monster = random_pick_monster_nation()
	if cur_monster == 0:
		set_event(EVENT_RANDOM_POINT_4)
		return true
	if random(2) == 0 and not has_event_run(EVENT_FRYHTAN_BREAK_UP) and map.nation_state_count(cur_monster) >= 2:
		if player_beat_fryhtan_count >= player_beat_fryhtan_max or (player_beat_fryhtan_count >= 1 and eastern == 0) \
				or random((player_beat_fryhtan_max - player_beat_fryhtan_count) / 2) == 0:
			set_event(EVENT_FRYHTAN_BREAK_UP)
			return true
	if map.nation_state_count(western) <= hero_debut_state_count or eastern == 0:
		if random_pick_attack_state(cur_monster, western):
			if run_stage_once(STAGE_HERO_DEBUT):
				return true
	randomize_chance()
	if chance(16) or random(6) == 0:
		if map.nation_state_count(western) > 1 and eastern and run_event_once(EVENT_STATE_BETRAYAL):
			return true
		return false
	if chance(16) and map.nation_state_count(western) > 1:
		if run_event_once(EVENT_FRYHTAN_OFFER_PEACE):
			return true
		return false
	if chance(16):
		if not has_stage_run(STAGE_DEFENSE) or random(10):
			cur_monster = least_state_nation(-1, western)
			if cur_monster and random_pick_attack_state(cur_monster, western):
				set_stage(STAGE_FRYHTAN_INVASION_2)
				return true
		return false
	if chance(32):
		if monster_take_over_east_count >= 1 and not has_event_run(EVENT_EAST_ASK_FOR_JOINT_ATTACK) and not triangle_states2().is_empty():
			return_event_id = EVENT_RANDOM_POINT_1
			set_event(EVENT_EAST_ASK_FOR_JOINT_ATTACK)
			return true
		cur_monster = random_pick_monster_nation(0, eastern, true) if eastern else 0
		if cur_monster:
			return_event_id = EVENT_RANDOM_POINT_1
			set_event(EVENT_FRYHTAN_INVADE_EAST)
			return true
	if random(event_runs.get(EVENT_FRYHTAN_TAKEOVER, 0)) == 0 and map.nation_state_count(western) > 1:
		if cur_monster == 0:
			cur_monster = random_pick_monster_nation(0, eastern)
		if cur_monster:
			set_event(EVENT_FRYHTAN_TAKEOVER)
			return true
	return false


func event_state_betrayal() -> bool:
	if eastern == 0 or not random_pick_attack_state(eastern, western):
		set_event(EVENT_RANDOM_POINT_1)
		return true
	await letter("3A", [war_minister()])
	state_change_nation(target_state, eastern)
	log_line("A province betrays you to the Eastern Empire.")
	if random_pick_state(western, target_state) == 0:
		set_event(EVENT_RANDOM_POINT_1)
		return true
	if await letter("3B", [war_minister()]) == 2:
		set_event(EVENT_RANDOM_POINT_1)
		return true
	await letter("3C", [minister_name(eastern, MINISTER_OF_FOREIGN_AFFAIRS)])
	if await letter("3D", [war_minister()]) == 2:
		set_event(EVENT_RANDOM_POINT_1)
		return true
	# the stolen province is the target; the attack comes from a neighbouring one of ours
	var lost := target_state
	attacker_state = random_pick_state(western, lost)
	target_state = lost
	set_stage(STAGE_BATTLE_EAST)
	return true


func event_fryhtan_offer_peace() -> bool:
	cur_monster = most_state_nation(-1, western)
	if cur_monster == 0:
		set_event(EVENT_RANDOM_POINT_1)
		return true
	var reply := await letter("4A", [race_name(cur_monster), nation_name(cur_monster), minister_name(cur_monster, MINISTER_ORDO), king_name(cur_monster)])
	if reply == 1:
		if random_pick_attack_state(cur_monster, western):
			state_change_nation(target_state, cur_monster)
			log_line("You cede a province to the %s for peace." % nation_name(cur_monster))
		set_stage(STAGE_BUILD_UP)
	elif random_pick_attack_state(cur_monster, western):
		set_stage(STAGE_DEFENSE)
	else:
		set_event(EVENT_RANDOM_POINT_1)
	return true


func event_give_throne() -> bool:
	await narrative("5A", [old_king_name, king_name(western), old_king_name, king_name(western)])
	if await player_pick_attack_target("monster"):
		set_stage(STAGE_FIGHT_BACK_1)
	else:
		set_event(EVENT_RANDOM_POINT_2)
	return true


func event_random_point_2() -> bool:
	if random(4) == 0:
		if random(2) == 0 and not has_stage_run(STAGE_TRAIN_LEADERS):
			return_event_id = EVENT_RANDOM_POINT_2
			set_stage(STAGE_TRAIN_LEADERS)
			return true
		elif not has_stage_run(STAGE_GROW_POPULATION) and player_race != "EGYPTIAN" and not nations[western]["know_base"].has("EGYPTIAN"):
			return_event_id = EVENT_RANDOM_POINT_2
			set_stage(STAGE_GROW_POPULATION)
			return true
	if random(4) == 0 and cur_monster and random_pick_attack_state(western, cur_monster) and not has_stage_run(STAGE_ACQUIRE_MEGA_WEAPON):
		set_stage(STAGE_ACQUIRE_MEGA_WEAPON)
		return true
	if map.nation_state_count(western) >= 4 and not has_stage_run(STAGE_DEEP_INTO_FRYHTAN_LAND):
		if await player_pick_attack_target("monster"):
			set_stage(STAGE_DEEP_INTO_FRYHTAN_LAND)
			return true
	if eastern:
		if (relation(eastern) >= Defs.Relation.NEUTRAL or random(2) == 0) and random(event_runs.get(EVENT_EASTERN_EMPIRE_OFFER_HELP, 0) + 2) == 0:
			set_event(EVENT_EASTERN_EMPIRE_OFFER_HELP)
			return true
		elif relation(eastern) < Defs.Relation.NEUTRAL and map.nation_state_count(western) > 1 and not defeated_eastern_empire_invasion \
				and not has_stage_run(STAGE_EASTERN_EMPIRE_INVADE_OUR_LAND) and random(2) == 0 and random_pick_attack_state(eastern, western):
			set_stage(STAGE_EASTERN_EMPIRE_INVADE_OUR_LAND)
			return true
	cur_monster = random_pick_monster_nation()
	if cur_monster == 0:
		await ui.narrative("The Fryhtan kingdoms are no more. The land is free of their terror.")
		set_event(EVENT_RANDOM_POINT_4)
		return true
	if random(2) == 0 or has_event_run(EVENT_FRYHTAN_BREAK_UP):
		if not triangle_states1().is_empty():
			if has_event_run(EVENT_FRYHTAN_ATTACK_FRYHTAN) and not has_event_run(EVENT_FRYHTAN_ASK_FOR_JOINT_ATTACK):
				set_event(EVENT_FRYHTAN_ASK_FOR_JOINT_ATTACK)
			else:
				set_event(EVENT_FRYHTAN_ATTACK_FRYHTAN)
			return true
	if await player_pick_attack_target("monster"):
		if eastern and map.is_adjacent_to_nation(target_state, eastern):
			if random(2) == 0 and not has_event_run(EVENT_ASK_EASTERN_EMPIRE_FOR_HELP):
				set_event(EVENT_ASK_EASTERN_EMPIRE_FOR_HELP)
				return true
			elif not has_event_run(EVENT_EAST_ASK_FOR_JOINT_ATTACK):
				return_event_id = EVENT_RANDOM_POINT_2
				set_event(EVENT_EAST_ASK_FOR_JOINT_ATTACK)
				return true
		set_stage(STAGE_FIGHT_BACK_2)
		return true
	cur_monster = random_pick_monster_nation(0, eastern) if eastern else 0
	if cur_monster:
		return_event_id = EVENT_RANDOM_POINT_2
		set_event(EVENT_FRYHTAN_INVADE_EAST)
		return true
	set_event(EVENT_RANDOM_POINT_3)
	return true


func event_eastern_empire_offer_help() -> bool:
	var tri := triangle_states2()
	if tri.is_empty():
		set_event(EVENT_RANDOM_POINT_2)
		return true
	if await letter("7A", [minister_name(eastern, MINISTER_OF_FOREIGN_AFFAIRS)]) == 1:
		attacker_state = tri[0]
		attacker2_state = tri[1]
		target_state = tri[2]
		cur_monster = map.get_state(tri[2])["nation"]
		set_relation(eastern, Defs.Relation.ALLIANCE)
		set_stage(STAGE_JOINT_FIGHT_BACK)
	else:
		set_relation(eastern, Defs.Relation.NEUTRAL)
		set_event(EVENT_RANDOM_POINT_2)
	return true


func event_fryhtan_attack_fryhtan() -> bool:
	var tri := triangle_states1()
	if tri.is_empty():
		set_event(EVENT_RANDOM_POINT_2)
		return true
	var n1: int = map.get_state(tri[1])["nation"]
	var n2: int = map.get_state(tri[2])["nation"]
	await narrative("8A", [race_name(n1), nation_name(n1), race_name(n2), nation_name(n2)])
	await attack_state(tri[1], tri[2], -1)
	var rc := await letter("8B", [war_minister(), race_name(n1), race_name(n2), race_name(n2), race_name(n1)])
	if rc == 1:
		cur_monster = n2
		attacker_state = tri[0]
		target_state = tri[2]
		set_stage(STAGE_OPPORTUNISTIC_ATTACK)
	elif rc == 2:
		cur_monster = n1
		attacker_state = tri[0]
		target_state = tri[1]
		set_stage(STAGE_OPPORTUNISTIC_ATTACK)
	else:
		set_event(EVENT_FRYHTAN_ASK_FOR_JOINT_ATTACK)
	return true


func event_fryhtan_ask_for_joint_attack() -> bool:
	var tri := triangle_states1()
	if tri.is_empty():
		set_event(EVENT_RANDOM_POINT_2)
		return true
	if random(2) == 0:
		attacker_state = tri[1]
		target_state = tri[2]
	else:
		attacker_state = tri[2]
		target_state = tri[1]
	attacker2_state = tri[0]
	var human_state: int = tri[0]
	cur_monster = map.get_state(attacker_state)["nation"]
	target_monster = map.get_state(target_state)["nation"]
	var mn := cur_monster
	var rc := await letter("9A", [race_name(mn), minister_name(mn, MINISTER_ORDO), king_name(mn)])
	if rc == 1:
		fryhtan_joint_attack_reward = false
		set_stage(STAGE_FRYHTAN_JOINT_ATTACK)
	elif rc == 2:
		if random(2) == 0:
			target_state = human_state
			set_stage(STAGE_FRYHTAN_RAGE_ATTACK)
		else:
			if random(2) == 0:
				await attack_state(attacker_state, target_state, 1)
				await narrative("9C1", [race_name(mn), king_name(mn)])
			else:
				await attack_state(attacker_state, target_state, -1)
				await narrative("9C2", [race_name(mn), king_name(mn)])
			set_event(EVENT_RANDOM_POINT_2)
	else:
		if random(2) == 0:
			await letter("9D1", [race_name(mn), minister_name(mn, MINISTER_ORDO), king_name(mn)])
			fryhtan_joint_attack_reward = true
			set_stage(STAGE_FRYHTAN_JOINT_ATTACK)
		else:
			await letter("9D2", [race_name(mn), minister_name(mn, MINISTER_ORDO), king_name(mn)])
			target_state = human_state
			set_stage(STAGE_FRYHTAN_RAGE_ATTACK)
	return true


func event_random_point_3() -> bool:
	if disband_fryhtan_reply == 0 and use_fryhtan_count >= 1 and (use_fryhtan_count >= use_fryhtan_max or random(use_fryhtan_max - use_fryhtan_count) == 0):
		return_event_id = EVENT_RANDOM_POINT_3
		set_event(EVENT_DISBAND_FRYHTAN_ARMY)
		return true
	if disband_fryhtan_reply == -1 and use_fryhtan_count - use_fryhtan_max >= random(3) and packed_nation_count() < MAX_NATION:
		set_event(EVENT_FRYHTAN_ARMY_REVOLT)
		return true
	if random(4) == 0:
		if random(2) == 0 and not has_stage_run(STAGE_TRAIN_LEADERS):
			return_event_id = EVENT_RANDOM_POINT_2
			set_stage(STAGE_TRAIN_LEADERS)
			return true
		elif not has_stage_run(STAGE_GROW_POPULATION) and player_race != "EGYPTIAN" and not nations[western]["know_base"].has("EGYPTIAN"):
			return_event_id = EVENT_RANDOM_POINT_2
			set_stage(STAGE_GROW_POPULATION)
			return true
	for i in range(map.size(), 0, -1):
		var nid: int = map.get_state(i)["nation"]
		if is_monster(nid) and map.is_adjacent_to_nation(i, western):
			if random(2) == 0:
				if await player_pick_attack_target("monster"):
					set_stage(STAGE_TERMINATE_FRYHTAN)
					return true
			cur_monster = random_pick_monster_nation()
			if cur_monster and random_pick_attack_state(western, cur_monster):
				set_event(EVENT_PLAYER_TAKE_OVER_FRYHTAN)
				return true
	cur_monster = random_pick_monster_nation(0, eastern) if eastern else 0
	if cur_monster:
		return_event_id = EVENT_RANDOM_POINT_3
		set_event(EVENT_FRYHTAN_INVADE_EAST)
		return true
	if eastern:
		await ui.narrative("The Fryhtan kingdoms are no more. The land is free of their terror.")
		set_event(EVENT_ATTEMPT_TO_UNITE)
	else:
		set_event(EVENT_ULTIMATE_VICTORY)
	return true


func event_fryhtan_think_surrender() -> bool:
	if not (cur_monster and nations.has(cur_monster) and fryhtan_surrendered_state == 0 and random(3) > 0):
		set_event(EVENT_RANDOM_POINT_3)
		return true
	var mn := cur_monster
	if await letter("11A", [king_name(mn), race_name(mn), king_name(mn), race_name(mn)]) == 1:
		var s := random_pick_state(mn)
		if s:
			fryhtan_surrendered_state = s
			surrendered_fryhtan = nations[mn]["race"]
			state_change_nation(s, western)
			log_line("A Fryhtan kingdom surrenders a province to you.")
			if await letter("11B", [race_name(mn), war_minister()]) == 1:
				can_use_fryhtan = true
	set_event(EVENT_RANDOM_POINT_3)
	return true


func event_ask_eastern_empire_for_help() -> bool:
	var tri := triangle_states2()
	if tri.is_empty():
		set_event(EVENT_RANDOM_POINT_3)
		return false
	if await letter("12A", [war_minister()]) == 1:
		if random(10) < 3:
			attacker_state = tri[0]
			attacker2_state = tri[1]
			target_state = tri[2]
			cur_monster = map.get_state(tri[2])["nation"]
			set_stage(STAGE_JOINT_TERMINATE_FRYHTAN)
		elif map.nation_state_count(western) > 1:
			if await letter("12B", [minister_name(eastern, MINISTER_OF_FOREIGN_AFFAIRS)]) == 1:
				random_pick_attack_state(eastern, western, tri[0])
				var s := target_state
				if s == 0:
					s = random_pick_state(western)
				if s:
					state_change_nation(s, eastern)
				attacker_state = tri[0]
				attacker2_state = tri[1]
				target_state = tri[2]
				cur_monster = map.get_state(tri[2])["nation"]
				set_stage(STAGE_JOINT_TERMINATE_FRYHTAN)
			else:
				set_event(EVENT_RANDOM_POINT_3)
		else:
			set_event(EVENT_RANDOM_POINT_3)
	else:
		set_event(EVENT_RANDOM_POINT_3)
	return true


func event_attempt_to_unite() -> bool:
	if await letter("13A", [war_minister()]) == 1 and eastern:
		await letter("13B", [king_name(eastern), minister_name(eastern, MINISTER_OF_FOREIGN_AFFAIRS)])
		set_event(EVENT_RANDOM_POINT_4)
	else:
		var t := await player_pick_attack_target("ai")
		if t and t == eastern:
			set_stage(STAGE_ATTACK_EASTERN_EMPIRE_1)
			return true
		elif t and t == new_kingdom:
			set_stage(STAGE_ATTACK_NEW_KINGDOM)
			return true
		set_event(EVENT_RANDOM_POINT_4)
	return true


func event_random_point_4() -> bool:
	if packed_nation_count() == 1 or (eastern == 0 and new_kingdom == 0):
		set_event(EVENT_ULTIMATE_VICTORY)
		return true
	if saved_player_state_count == 0:
		saved_player_state_count = map.nation_state_count(western)
	randomize_chance()
	if chance(35) and eastern and new_kingdom == 0 and map.nation_state_count(eastern) >= 2:
		var s := random_pick_state(eastern)
		if s:
			state_change_nation(s, 0)
			await letter("14A", [minister_name(western, MINISTER_OF_FOREIGN_AFFAIRS)])
		set_event(EVENT_RANDOM_POINT_4)
		return true
	elif chance(20) and eastern:
		var s := random_pick_state(eastern)
		if s:
			state_change_nation(s, western)
			await letter("14B", [minister_name(western, MINISTER_OF_FOREIGN_AFFAIRS)])
		set_event(EVENT_RANDOM_POINT_4)
		return true
	if map.nation_state_count(0) > 0 and new_kingdom == 0 and packed_nation_count() < MAX_NATION:
		new_kingdom = add_nation("ai")
		var s := random_pick_state(0)
		if s:
			state_change_nation(s, new_kingdom)
		await letter("14C", [minister_name(western, MINISTER_OF_FOREIGN_AFFAIRS)])
		set_event(EVENT_RANDOM_POINT_4)
		return true
	if not has_stage_run(STAGE_UPRISING):
		if (map.nation_state_count(western) - saved_player_state_count >= 2 and random(2) == 0) or random(4) == 0:
			set_stage(STAGE_UPRISING)
			return true
	if eastern and map.nation_state_count(eastern) == 1 and (new_kingdom == 0 or map.nation_state_count(new_kingdom) == 0):
		if random_pick_attack_state(western, eastern):
			set_stage(STAGE_LAST_BATTLE)
			return true
	if new_kingdom and random(2) == 0:
		if random(2) == 0 and not has_stage_run(STAGE_NEW_KINGDOM_INVASION) and random_pick_attack_state(new_kingdom, western):
			set_stage(STAGE_NEW_KINGDOM_INVASION)
			return true
		elif eastern and (random(2) == 0) and random_pick_attack_state(new_kingdom, eastern):
			var win := random(2) == 1
			await attack_state(attacker_state, target_state, 1 if win else -1)
			var kn := king_name(new_kingdom)
			if win:
				await letter("14D1", [kn, minister_name(western, MINISTER_OF_FOREIGN_AFFAIRS)])
			else:
				await letter("14D2", [kn, kn, minister_name(western, MINISTER_OF_FOREIGN_AFFAIRS)])
			set_event(EVENT_RANDOM_POINT_4)
			return true
	if eastern and new_kingdom and map.nation_state_count(eastern) > 1:
		if await letter("14E", [war_minister(), nation_name(eastern), nation_name(new_kingdom)]) == 1:
			if random_pick_attack_state(western, eastern):
				set_stage(STAGE_ATTACK_EASTERN_EMPIRE_2)
				return true
		elif random_pick_attack_state(western, new_kingdom):
			set_stage(STAGE_ATTACK_NEW_KINGDOM)
			return true
	elif eastern and map.nation_state_count(eastern) > 1:
		var t := await player_pick_attack_target("ai")
		if t == eastern:
			if not has_stage_run(STAGE_ATTACK_EASTERN_EMPIRE_2):
				set_stage(STAGE_ATTACK_EASTERN_EMPIRE_2)
			else:
				set_event(EVENT_PLAYER_TAKE_OVER_EAST)
			return true
		elif t and t == new_kingdom:
			set_stage(STAGE_ATTACK_NEW_KINGDOM)
			return true
	elif eastern == 0 and new_kingdom:
		if random_pick_attack_state(western, new_kingdom):
			set_stage(STAGE_ATTACK_NEW_KINGDOM)
			return true
	return false


func event_ultimate_victory() -> bool:
	await letter("15A", ["%d" % game_year, war_minister()])
	log_line("Ultimate victory!")
	finished = true
	victory = true
	set_event(0)
	return true


func event_fryhtan_invade_east() -> bool:
	cur_monster = random_pick_monster_nation(0, eastern) if eastern else 0
	if cur_monster == 0 or not random_pick_attack_state(cur_monster, eastern):
		set_event(return_event_id if return_event_id else EVENT_RANDOM_POINT_1)
		return false
	await narrative("16A")
	var result := 1 if random(2) == 0 else -1
	await attack_state(attacker_state, target_state, result)
	if result == 1:
		monster_take_over_east_count += 1
	await narrative("16B" if result == 1 else "16C")
	set_event(return_event_id if return_event_id else EVENT_RANDOM_POINT_1)
	return true


func event_east_ask_for_joint_attack() -> bool:
	var tri := triangle_states2()
	if tri.is_empty():
		set_event(return_event_id if return_event_id else EVENT_RANDOM_POINT_2)
		return true
	if await letter("17A", [minister_name(eastern, MINISTER_OF_FOREIGN_AFFAIRS)]) == 1:
		attacker_state = tri[0]
		attacker2_state = tri[1]
		target_state = tri[2]
		cur_monster = map.get_state(tri[2])["nation"]
		set_relation(eastern, Defs.Relation.ALLIANCE)
		set_stage(STAGE_EAST_JOINT_ATTACK_FRYHTAN)
	else:
		set_relation(eastern, Defs.Relation.NEUTRAL)
		set_event(return_event_id if return_event_id else EVENT_RANDOM_POINT_2)
	return true


func event_fryhtan_break_up() -> bool:
	if packed_nation_count() >= MAX_NATION:
		set_event(EVENT_RANDOM_POINT_2)
		return false
	var orig := 0
	for i in nations:
		if is_monster(i) and map.nation_state_count(i) >= 2:
			orig = i
	if orig == 0:
		set_event(EVENT_RANDOM_POINT_2)
		return false
	var nn := add_nation("monster", nations[orig]["race"])
	var s := random_pick_state(orig)
	await narrative("18A")
	state_change_nation(s, nn)
	var a := random_pick_state(orig, s)
	if a == 0:
		set_event(EVENT_RANDOM_POINT_2)
		return false
	if random(2) == 0:
		var t := a
		a = s
		s = t
	var result := 1 if random(2) == 0 else -1
	var att: int = map.get_state(a)["nation"]
	await narrative("18B" if result == 1 else "18C", [king_name(att)])
	await attack_state(a, s, result)
	await narrative("18D")
	var mine := random_pick_state(western, s)
	if mine:
		await attack_state(mine, s, 1)
	set_event(EVENT_RANDOM_POINT_2)
	return true


func event_player_take_over_fryhtan() -> bool:
	cur_monster = random_pick_monster_nation()
	if cur_monster == 0 or not random_pick_attack_state(western, cur_monster):
		set_event(EVENT_RANDOM_POINT_3)
		return false
	await narrative("19A", [king_name(cur_monster)])
	await attack_state(attacker_state, target_state, 1)
	if random(3) == 0 and not has_stage_run(STAGE_RESTORE_PROSPERITY):
		return_event_id = EVENT_RANDOM_POINT_3
		set_stage(STAGE_RESTORE_PROSPERITY)
	else:
		set_event(EVENT_RANDOM_POINT_3)
	return true


func event_disband_fryhtan_army() -> bool:
	disband_fryhtan_reply = 1 if await letter("20A", [minister_name(western, MINISTER_HOME)]) == 1 else -1
	if disband_fryhtan_reply == 1:
		can_use_fryhtan = false
	set_event(return_event_id if return_event_id else EVENT_RANDOM_POINT_3)
	return true


func event_independent_surrender() -> bool:
	var s := random_pick_state(0)
	if s == 0:
		set_event(EVENT_RANDOM_POINT_4)
		return false
	await narrative("21A")
	state_change_nation(s, western)
	set_event(EVENT_RANDOM_POINT_4)
	return true


func event_fryhtan_army_revolt() -> bool:
	var s := 0
	if fryhtan_surrendered_state and map.get_state(fryhtan_surrendered_state).get("nation", 0) == western:
		s = fryhtan_surrendered_state
	else:
		for i in range(map.size(), 0, -1):
			if map.get_state(i)["nation"] == western and map.nation_state_count(western) > 1:
				for j in map.get_state(i)["adj"]:
					if map.get_state(j)["nation"] != western:
						s = i
						break
			if s:
				break
	if s == 0:
		set_event(EVENT_RANDOM_POINT_3)
		return false
	await narrative("22A")
	var nn := add_nation("ai")
	if nn:
		state_change_nation(s, nn)
		if new_kingdom == 0:
			new_kingdom = nn
	set_event(EVENT_RANDOM_POINT_3)
	return true


func event_player_take_over_east() -> bool:
	if eastern == 0 or not random_pick_attack_state(western, eastern):
		set_event(EVENT_RANDOM_POINT_4)
		return false
	await narrative("23A")
	await attack_state(attacker_state, target_state, 1)
	if random(3) == 0 and not has_stage_run(STAGE_RESTORE_PROSPERITY):
		return_event_id = EVENT_RANDOM_POINT_4
		set_stage(STAGE_RESTORE_PROSPERITY)
	else:
		set_event(EVENT_RANDOM_POINT_4)
	return true


# ----------------------------------------------------------- stages ---

func stage_name() -> String:
	return STAGE_NAMES[stage_id] if stage_id > 0 and stage_id < STAGE_NAMES.size() else ""


func stage_text(suffix: String) -> String:
	var key := "%d%s" % [stage_id, suffix]
	if suffix == "PRELUDE" and stage_id >= 10:
		key = "%dPRELUD" % stage_id
	return CampaignText.stage(key)


## The goal numbers a stage's texts need (stage_n_intro_text / goal_text).
func stage_args() -> Array:
	match stage_id:
		2:
			return [stage_vars.get("kill_score", 0)]
		25:
			return [stage_vars.get("score", 0), stage_vars.get("years", 0)]
		26:
			return [stage_vars.get("leadership", 0), stage_vars.get("years", 0)]
		27:
			return [stage_vars.get("population", 0), stage_vars.get("years", 0)]
		28:
			return [stage_vars.get("population", 0), stage_vars.get("economy", 0), stage_vars.get("years", 0)]
	return []


func intro_text() -> String:
	return CampaignText.format(stage_text("INTRO"), stage_args())


func goal_text() -> String:
	return CampaignText.format(stage_text("GOAL"), stage_args())


## CampaignEastWest::stage_prelude: the story leading into the battle, and the
## battle's parameters.
func stage_prelude() -> void:
	_saved_seed = rng.state
	stage_vars = {}
	var d := difficulty
	var prelude := stage_text("PRELUDE")
	match stage_id:
		STAGE_FRYHTAN_INVASION_1:
			cur_monster = random_pick_monster_nation()
			if cur_monster:
				random_pick_attack_state(cur_monster, western)
			await ui.narrative(prelude)
			await attack_state(attacker_state, target_state, 0)
		STAGE_FRYHTAN_INVASION_2:
			stage_vars["kill_score"] = 50 + d * 70
			await ui.narrative(CampaignText.format(prelude, [stage_vars["kill_score"]]))
			await attack_state(attacker_state, target_state, 0)
		STAGE_BUILD_UP:
			await ui.narrative(prelude)
			target_state = random_pick_state(western)
			await rebel_attack_state(target_state, 0)
		STAGE_BATTLE_EAST:
			await ui.narrative(prelude)
			if attacker_state == 0:
				attacker_state = random_pick_state(western, target_state)
			await attack_state(attacker_state, target_state, 0)
		STAGE_UPRISING:
			stage_vars["score"] = d * 200
			stage_vars["years"] = 16 - d
			await ui.narrative(prelude)
			target_state = random_pick_state(western)
			await rebel_attack_state(target_state, 0)
		STAGE_TRAIN_LEADERS:
			stage_vars["leadership"] = 90
			stage_vars["years"] = 18 - d * 2
			await ui.narrative(CampaignText.format(prelude, [90, stage_vars["years"]]))
			target_state = random_pick_state(western)
			await ui.attack(0, target_state, 0, 0)
		STAGE_GROW_POPULATION:
			stage_vars["population"] = 200 + d * 100
			stage_vars["years"] = 12 - d
			await ui.narrative(prelude)
			target_state = random_pick_state(western)
			await ui.attack(0, target_state, 0, 0)
		STAGE_RESTORE_PROSPERITY:
			stage_vars["population"] = d * 100
			stage_vars["economy"] = d * 100
			stage_vars["years"] = 32 - d * 3
			await ui.narrative(CampaignText.format(prelude, [stage_vars["population"], stage_vars["economy"], stage_vars["years"]]))
			target_state = random_pick_state(western)
			await ui.attack(0, target_state, 0, 0)
		_:
			if prelude != "":
				await ui.narrative(prelude)
			if target_state:
				await attack_state(attacker_state, target_state, 0, attacker2_state)
	if stage_id == STAGE_ACQUIRE_MEGA_WEAPON:
		mega_tech = ["M_CANNON", "M_F_BALL", "M_SAW"][random(3)]
	if can_use_fryhtan and surrendered_fryhtan != "" and _player_attacks():
		this_battle_use_fryhtan = await ui.letter("Your Fryhtan allies stand ready.\n~\nSire, shall the surrendered Fryhtans march with Our troops in this battle?\n~\nYes, let them fight for Us.\n~\nNo, Our own soldiers will do.\n~\n") == 1
		if this_battle_use_fryhtan:
			use_fryhtan_count += 1
	if _last_unveil_stage != stage_id:
		_last_unveil_stage = stage_id
		unveil_new_tech()


## Stages in which you bring a troop of your own (create_troop for the player).
func _player_attacks() -> bool:
	return stage_id in [4, 7, 8, 10, 11, 13, 14, 15, 16, 17, 18, 19, 20, 22, 23, 24]


## Campaign::unveil_new_tech: each new stage makes up to three human and two
## Fryhtan technologies researchable, and the offensive building faced in the
## last battle won.
func unveil_new_tech() -> void:
	var human_classes := [
		["MINING", "MANUFACT", "FARMING", "WAR_PROD"],
		["INFCLOSE", "INFRANGE", "INFDEFEN"],
		["CATAPULT", "BALLISTA", "FLAMETHR", "CANNON", "EXPCART", "F_BALLIS"],
		["AGITATE", "COUNTERS", "STEALINF", "BRIBE", "ASSASSIN", "STEALTEC", "CAMOUFLG", "INCIDENT"],
	]
	var got := 0
	for k in 10:
		if random(6) == 0:
			if _unveil_spu():
				break
		elif _unveil_one(human_classes):
			got += 1
			if got == 3:
				break
	var fry_classes := []
	for sp in ["PLANT", "LYW", "HOBGLOB", "GIANTET", "GITH", "ROCKMAN", "GREMJERM"]:
		fry_classes.append(Defs.fryhtan_techs(sp).map(func(t): return t["code"]))
	got = 0
	for k in 10:
		if _unveil_one(fry_classes):
			got += 1
			if got == 2:
				break
	if win_to_unveil_tech != "":
		tech_available[win_to_unveil_tech] = maxi(tech_available.get(win_to_unveil_tech, 0), 1)
		win_to_unveil_tech = ""


func _unveil_one(classes: Array) -> bool:
	var cls: Array = classes[random(classes.size())]
	if random(2) == 0:
		for code in cls:
			if tech_available.get(code, 0) == 0:
				tech_available[code] = 1
				return true
	else:
		for code in cls:
			var mx := int(Defs.tech_def(code).get("max", 1))
			if tech_available.get(code, 0) < mx:
				tech_available[code] = tech_available.get(code, 0) + 1
				return true
	return false


func _unveil_spu() -> bool:
	if tech_available.has("SPUS_NOR"):
		if tech_available.has("SPUB_NOR"):
			return false
		for r in Defs.SPU_TECH_SUFFIX:
			tech_available[Defs.spu_berserk_tech(r)] = 1
		return true
	for r in Defs.SPU_TECH_SUFFIX:
		tech_available[Defs.spu_structure_tech(r)] = 1
	return true


## The end-of-battle message (stage_n_disp_end_game_msg).
func end_text(won: bool, win_id: int, lose_id: int) -> String:
	var key := ""
	match stage_id:
		STAGE_FRYHTAN_INVASION_2:
			key = ("2WIN2" if win_id == Goals.KILL_MONSTER_SCORE else "2WIN1") if won else "2LOSE"
		STAGE_BUILD_UP:
			key = "3WIN" if won else ("3LOSE1" if lose_id == Goals.DEFEAT_OWN_KINGDOM else "3LOSE2")
		_:
			key = "%d%s" % [stage_id, "WIN" if won else "LOSE"]
	var t := CampaignText.stage(key)
	if t == "":
		return "Victory!" if won else "Defeat."
	var args: Array = stage_args()
	if stage_id == STAGE_FRYHTAN_INVASION_1 and won:
		args = [stage_vars.get("kill_monster_score", 0)]
	return CampaignText.format(t, args)


func _replay() -> void:
	rng.state = _saved_seed
	set_stage(stage_id)


## CampaignEastWest::process_game_result (stage_n_process_game_result).
## `win_id` / `lose_id` are the Goals conditions that ended the battle.
func process_game_result(won: bool, win_id: int, lose_id: int, years := 1) -> void:
	game_year += maxi(1, years)
	if won:
		score += maxi(1, BONUS_MAX_YEAR - years)
	else:
		win_to_unveil_tech = ""
	var s := stage_id
	log_line("%s: %s." % [stage_name(), "won" if won else "lost"])
	match s:
		STAGE_FRYHTAN_INVASION_1:
			if won:
				set_event(EVENT_RANDOM_POINT_1)
			else:
				_replay()
		STAGE_FRYHTAN_INVASION_2:
			if won:
				if win_id == Goals.KILL_MONSTER_SCORE:
					await ui.narrative(CampaignText.stage("2POST"))
					await attack_state(attacker_state, target_state, 1)
				else:
					hero_debut_state_count += 1
					player_beat_fryhtan_count += 1
				set_event(EVENT_RANDOM_POINT_1)
			else:
				_replay()
		STAGE_BUILD_UP:
			if won:
				hero_debut_state_count += 1
				set_event(EVENT_RANDOM_POINT_1)
			else:
				_replay()
		STAGE_BATTLE_EAST:
			if won:
				await attack_state(attacker_state, target_state, 1)
			set_event(EVENT_RANDOM_POINT_1)
		STAGE_DEFENSE:
			if won:
				hero_debut_state_count += 1
				player_beat_fryhtan_count += 1
				set_event(EVENT_RANDOM_POINT_1)
			else:
				await attack_state(attacker_state, target_state, 1)
				set_event(EVENT_FRYHTAN_TAKEOVER if map.nation_state_count(western) > 1 else EVENT_RANDOM_POINT_1)
		STAGE_HERO_DEBUT:
			if won:
				if stage_vars.get("hero_alive", false):
					set_event(EVENT_GIVE_THRONE)
				else:
					set_event(EVENT_RANDOM_POINT_2)
			else:
				_replay()
		STAGE_FIGHT_BACK_1, STAGE_FIGHT_BACK_2, STAGE_OPPORTUNISTIC_ATTACK, STAGE_JOINT_FIGHT_BACK:
			if won:
				await attack_state(attacker_state, target_state, 1, attacker2_state)
				set_event(EVENT_RANDOM_POINT_2)
			else:
				_replay()
		STAGE_EASTERN_EMPIRE_INVADE_OUR_LAND:
			if won:
				defeated_eastern_empire_invasion = true
			else:
				await attack_state(attacker_state, target_state, 1)
			set_event(EVENT_RANDOM_POINT_2)
		STAGE_FRYHTAN_JOINT_ATTACK:
			if won:
				await attack_state(attacker_state, target_state, 1, attacker2_state)
				if fryhtan_joint_attack_reward and nations.has(cur_monster) and map.nation_state_count(cur_monster) > 1 and random(10) < 7:
					if not random_pick_attack_state(western, cur_monster):
						target_state = random_pick_state(cur_monster)
					if target_state:
						state_change_nation(target_state, western)
						log_line("The Fryhtans keep their word and hand you a province.")
				set_event(EVENT_RANDOM_POINT_2)
			else:
				_replay()
		STAGE_FRYHTAN_RAGE_ATTACK:
			if not won:
				await attack_state(attacker_state, target_state, 1)
			set_event(EVENT_RANDOM_POINT_2)
		STAGE_DEEP_INTO_FRYHTAN_LAND:
			if won:
				await attack_state(attacker_state, target_state, 1)
				set_event(EVENT_RANDOM_POINT_3)
			else:
				cur_monster = random_pick_monster_nation()
				if cur_monster and random_pick_attack_state(western, cur_monster) and not has_stage_run(STAGE_ACQUIRE_MEGA_WEAPON):
					set_stage(STAGE_ACQUIRE_MEGA_WEAPON)
				else:
					set_event(EVENT_RANDOM_POINT_3)
		STAGE_ACQUIRE_MEGA_WEAPON:
			if won and win_id == Goals.ACQUIRE_TECH:
				if await player_pick_attack_target("monster"):
					set_stage(STAGE_USE_MEGA_WEAPON)
				else:
					set_event(EVENT_RANDOM_POINT_3)
			else:
				_replay()
		STAGE_USE_MEGA_WEAPON:
			if won:
				await attack_state(attacker_state, target_state, 1)
				set_event(EVENT_RANDOM_POINT_3)
			else:
				_replay()
		STAGE_TERMINATE_FRYHTAN:
			if won:
				await attack_state(attacker_state, target_state, 1)
				set_event(EVENT_FRYHTAN_THINK_SURRENDER)
			elif eastern:
				set_event(EVENT_ASK_EASTERN_EMPIRE_FOR_HELP)
			else:
				_replay()
		STAGE_JOINT_TERMINATE_FRYHTAN:
			if won:
				await attack_state(attacker_state, target_state, 1)
				set_event(EVENT_FRYHTAN_THINK_SURRENDER)
			else:
				_replay()
		STAGE_ATTACK_EASTERN_EMPIRE_1, STAGE_ATTACK_EASTERN_EMPIRE_2:
			if won:
				await attack_state(attacker_state, target_state, 1)
				if s == STAGE_ATTACK_EASTERN_EMPIRE_2 and map.nation_state_count(0) > 0 and random(3) > 0:
					set_event(EVENT_INDEPENDENT_SURRENDER)
				else:
					set_event(EVENT_RANDOM_POINT_4)
			else:
				_replay()
		STAGE_NEW_KINGDOM_INVASION:
			if not won:
				await attack_state(attacker_state, target_state, 1)
			set_event(EVENT_RANDOM_POINT_4)
		STAGE_ATTACK_NEW_KINGDOM:
			if won:
				await attack_state(attacker_state, target_state, 1)
			set_event(EVENT_RANDOM_POINT_4)
		STAGE_LAST_BATTLE:
			if won:
				await attack_state(attacker_state, target_state, 1)
				set_event(EVENT_ULTIMATE_VICTORY)
			else:
				if eastern and random_pick_attack_state(eastern, western):
					await ui.narrative(CampaignText.stage("23POST"))
					await attack_state(attacker_state, target_state, 1)
				set_event(EVENT_RANDOM_POINT_4)
		STAGE_EAST_JOINT_ATTACK_FRYHTAN:
			if won:
				east_joint_attack_fryhtan_win_count += 1
				if east_joint_attack_fryhtan_win_count % 2 == 1 or eastern == 0:
					player_beat_fryhtan_count += 1
					await attack_state(attacker_state, target_state, 1)
				else:
					await attack_state(attacker2_state, target_state, 1)
			set_event(return_event_id if return_event_id else EVENT_RANDOM_POINT_2)
		STAGE_UPRISING:
			if won:
				set_event(EVENT_RANDOM_POINT_4)
			else:
				_replay()
		STAGE_TRAIN_LEADERS, STAGE_GROW_POPULATION, STAGE_RESTORE_PROSPERITY:
			if won:
				if s == STAGE_GROW_POPULATION:
					nations[western]["know_base"]["EGYPTIAN"] = true
				set_event(return_event_id if return_event_id else EVENT_RANDOM_POINT_2)
			else:
				_replay()
	if map.nation_state_count(western) == 0:
		finished = true
		victory = false
		log_line("Your empire has fallen.")


## Campaign::update_royal_unit: the king and the royal generals who survived
## the battle keep their skills in the next one.
func update_royals(g: Game) -> void:
	var p := g.player()
	if p == null:
		return
	if p.king and is_instance_valid(p.king) and not p.king.dead:
		king = {"name": p.king.unit_name, "combat": p.king.combat, "leadership": p.king.leadership,
			"race": p.king.race, "sprite": p.king.sprite_code}
	var royals := []
	for u in g.units:
		if u.nation_id == p.id and not u.dead and u != p.king and u.has_meta("royal") and royals.size() < 6:
			royals.append({"name": u.unit_name, "combat": u.combat, "leadership": u.leadership, "sprite": u.sprite_code})
	# generals who distinguished themselves join the royal court
	for u in g.units:
		if royals.size() >= 4:
			break
		if u.nation_id == p.id and not u.dead and u != p.king and not u.has_meta("royal") and u.is_human() \
				and u.rank == Defs.Rank.GENERAL and u.leadership >= 60.0:
			royals.append({"name": u.unit_name, "combat": u.combat, "leadership": u.leadership, "sprite": u.sprite_code})
	nobles = royals


# ------------------------------------------------------------- save ---

func to_dict() -> Dictionary:
	var d := {}
	for k in ["difficulty", "player_race", "western", "eastern", "cur_monster", "target_monster", "new_kingdom",
			"stage_id", "event_id", "return_event_id", "attacker_state", "attacker2_state", "target_state",
			"hero_debut_state_count", "player_beat_fryhtan_count", "player_beat_fryhtan_max", "monster_take_over_east_count",
			"east_joint_attack_fryhtan_win_count", "saved_player_state_count", "use_fryhtan_count", "use_fryhtan_max",
			"disband_fryhtan_reply", "fryhtan_surrendered_state", "surrendered_fryhtan", "can_use_fryhtan",
			"this_battle_use_fryhtan", "fryhtan_joint_attack_reward", "defeated_eastern_empire_invasion", "mega_tech",
			"old_king_name", "game_year", "score", "finished", "victory", "stage_vars", "king", "nobles",
			"tech_available", "win_to_unveil_tech", "_last_unveil_stage", "journal"]:
		d[k] = get(k)
	d["nations"] = nations.values()
	d["stage_runs"] = stage_runs
	d["event_runs"] = event_runs
	d["map"] = map.to_dict()
	d["rng_seed"] = rng.seed
	d["rng_state"] = str(rng.state)
	d["saved_seed"] = str(_saved_seed)
	return d


func from_dict(d: Dictionary) -> void:
	for k in d:
		if k in ["nations", "stage_runs", "event_runs", "map", "rng_seed", "rng_state", "saved_seed"]:
			continue
		var v = d[k]
		var cur = get(k)
		if cur is int:
			v = int(v)
		elif cur is bool:
			v = bool(v)
		set(k, v)
	nations.clear()
	for n in d.get("nations", []):
		var nn: Dictionary = n.duplicate(true)
		nn["id"] = int(nn["id"])
		nn["color"] = int(nn["color"])
		nn["relation"] = int(nn["relation"])
		nations[nn["id"]] = nn
	stage_runs.clear()
	for k in d.get("stage_runs", {}):
		stage_runs[int(k)] = int(d["stage_runs"][k])
	event_runs.clear()
	for k in d.get("event_runs", {}):
		event_runs[int(k)] = int(d["event_runs"][k])
	map.from_dict(d.get("map", {}))
	rng.seed = int(d.get("rng_seed", 0))
	rng.state = int(d.get("rng_state", "0"))
	_saved_seed = int(d.get("saved_seed", "0"))


func save() -> bool:
	DirAccess.make_dir_recursive_absolute("user://saves")
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict()))
	return true


static func exists() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


static func load_saved() -> Campaign:
	if not exists():
		return null
	var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not d is Dictionary:
		return null
	Defs.load_from_assets()
	var c := Campaign.new()
	c.from_dict(d)
	return c
