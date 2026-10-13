class_name Goals
extends RefCounted
## A scenario's win and lose conditions (EndCondition, oend_con.cpp), checked for
## the player every day (NationBase::check_win / check_lose). Random maps have none
## and keep the plain rule: defeat every other kingdom.

enum {
	DEFEAT_ALL_OTHER_KINGDOMS, DEFEAT_OWN_KINGDOM, DEFEAT_KINGDOM, FORM_ALLY_WITH_KINGDOM,
	DEFEAT_ALL_FRYHTAN, DEFEAT_EXCEPT_ALLIANCE, REACH_POPULATION, REACH_FRYHTAN,
	REACH_UNIT_COUNT, REACH_ECONOMY, REACH_MILITARY, REACH_TOTAL, KILL_MONSTER_SCORE,
	TRAIN_10_GENERAL, KILL_UNIT, KEEP_UNIT_ALIVE, MEET_UNIT, CONQUER_ALL_TOWN, CONQUER_TOWN,
	DESTROY_FIRM, GET_SCROLL, ACQUIRE_ITEM, NATION_SURVIVE, ACQUIRE_TECH, CONQUER_ALL_FIRM,
	CONQUER_FIRM,
}
const MEET_UNIT_RANGE := 2

var require_all := false
## Conditions: {id, p1, p2, years, player_only, text, result, target, supported}.
## `target` is the Nation id, Unit, Town or Firm the condition names, or the tech
## or sprite code; a target that disappears turns the condition true or dead as the
## original does.
var win: Array = []
var lose: Array = []
var result_text := ""
var won_id := -1        # the condition that won or lost the game (result_win/lose_condition_id)
var lost_id := -1
var year_limit := 0     # Config::goal_year_limit (Game::set_win_deadline)


## EndCondition::cond_text: what a condition asks, for one without a text of
## its own (the start screen's goals, scenarios made here).
static func describe(c: Dictionary) -> String:
	var t = c.get("target")
	var tname := ""
	if t is Town:
		tname = t.town_name
	elif t is Unit:
		tname = t.unit_name
	elif t is Firm:
		tname = t.display_name()
	elif t is int and Game.inst and Game.inst.nation(t):
		tname = Game.inst.nation(t).name
	elif t is String:
		tname = Defs.tech_def(t).get("name", t)
	var y := int(c.get("years", 0))
	var p2 := int(c.get("p2", 0))
	match int(c["id"]):
		DEFEAT_ALL_OTHER_KINGDOMS: return "Defeat all other kingdoms"
		DEFEAT_OWN_KINGDOM: return "Your kingdom is defeated"
		DEFEAT_KINGDOM: return "Defeat the %s" % tname
		FORM_ALLY_WITH_KINGDOM: return "Form an alliance with the %s" % tname
		DEFEAT_ALL_FRYHTAN: return "Destroy all the Fryhtans"
		DEFEAT_EXCEPT_ALLIANCE: return "Be the last kingdom standing but for an ally"
		REACH_POPULATION: return "Reach a population of %d" % p2
		REACH_FRYHTAN: return "Command %d Fryhtans" % p2
		REACH_ECONOMY: return "Reach an economic score of %d" % p2
		REACH_MILITARY: return "Reach a military score of %d" % p2
		REACH_TOTAL: return "Reach a total score of %d" % p2
		KILL_MONSTER_SCORE: return "Reach a Fryhtan battling score of %d" % p2
		TRAIN_10_GENERAL: return "Train ten generals of leadership %d" % p2
		KILL_UNIT: return "%s is killed" % tname
		KEEP_UNIT_ALIVE: return "Keep %s alive for %d year%s" % [tname, y, "" if y == 1 else "s"]
		MEET_UNIT: return "Meet %s" % tname
		CONQUER_ALL_TOWN: return "Bring every independent town under your rule"
		CONQUER_TOWN: return "Conquer %s" % tname
		DESTROY_FIRM: return "Destroy %s" % tname
		ACQUIRE_TECH: return "Acquire the secret of %s" % tname
		NATION_SURVIVE: return "Survive for %d years" % p2
		CONQUER_ALL_FIRM: return "Take every building"
		CONQUER_FIRM: return "Take %s" % tname
	return "A goal"


static func _fill_texts(gl: Goals) -> void:
	for c in gl.win + gl.lose:
		if str(c.get("text", "")) == "":
			c["text"] = describe(c)


## The goals chosen on the start screen (Battle::create_pregame_object):
## win conditions any one of which wins, and a time limit in years.
static func random_map(wins: Array, years: int) -> Goals:
	var gl := Goals.new()
	gl.year_limit = years
	for w in wins:
		var c := {"id": w["id"], "p1": 0, "p2": w.get("p2", 0), "years": 0, "player_only": w.get("player_only", false),
			"text": "", "result": "", "target": null, "met": false}
		c["supported"] = _supported(c)
		c["text"] = describe(c)
		gl.win.append(c)
	gl.lose.append({"id": DEFEAT_OWN_KINGDOM, "p1": 0, "p2": 0, "years": 0, "player_only": true, "text": "", "result": "",
		"target": null, "met": false, "supported": true})
	return gl


## Built by ScenarioLoader, which resolves the scenario's record numbers.
static func from_scenario(data: Dictionary, resolve: Callable) -> Goals:
	var gl := Goals.new()
	gl.require_all = data.get("require_all", false)
	for side in ["win", "lose"]:
		for c in data.get(side, []):
			var cond: Dictionary = c.duplicate()
			cond["target"] = resolve.call(cond)
			cond["supported"] = _supported(cond)
			cond["met"] = false
			(gl.win if side == "win" else gl.lose).append(cond)
	_fill_texts(gl)
	return gl


static func _supported(c: Dictionary) -> bool:
	match c["id"]:
		GET_SCROLL, ACQUIRE_ITEM:
			return c["target"] is int and c["target"] > 0
		ACQUIRE_TECH:
			return c["target"] is String and not Defs.tech_def(c["target"]).is_empty()
		KILL_UNIT, KEEP_UNIT_ALIVE, MEET_UNIT, CONQUER_TOWN, DESTROY_FIRM, CONQUER_FIRM, DEFEAT_KINGDOM, FORM_ALLY_WITH_KINGDOM:
			return c["target"] != null
	return true


## Years until the last win condition's time limit runs out (0 = no deadline).
func deadline_day() -> int:
	var years := year_limit
	for c in win:
		years = maxi(years, c["years"])
	return years * 365


## "won", "lost" or "" for the player today.
func check(g: Game) -> String:
	var p := g.player()
	for c in lose:
		if c["supported"] and _true(c, g, p):
			result_text = _result(c, p, false)
			lost_id = c["id"]
			return "lost"
	var any := false
	var all := true
	for c in win:
		if not c["supported"]:
			continue          # cannot be met here: does not block an all-goals win
		var t := _true(c, g, p)
		c["met"] = t
		any = any or t
		all = all and t
		if t and not require_all:
			result_text = _result(c, p, true)
			won_id = c["id"]
			return "won"
	if require_all and all and win.any(func(c): return c["supported"]):
		result_text = _result(win[0], p, true)
		won_id = win[0]["id"]
		return "won"
	var dl := deadline_day()
	if dl > 0 and g.day >= dl:
		result_text = "Time is up: the scenario's goals were not met in time."
		lost_id = NATION_SURVIVE
		return "lost"
	return ""


static func _result(c: Dictionary, p: Nation, won: bool) -> String:
	var r: String = c["result"]
	if r.contains("%1s"):
		r = r.replace("%1s", "Your kingdom")
	elif r.begins_with(" "):
		r = "Your kingdom" + r
	if r.strip_edges() == "":
		r = "Your kingdom has won!" if won else "Your kingdom has been defeated."
	return r


func _true(c: Dictionary, g: Game, n: Nation) -> bool:
	if c["player_only"] and (n == null or n.is_ai):
		return false
	if c["years"] > 0 and g.day > c["years"] * 365:
		return false
	var tgt = c["target"]
	match c["id"]:
		DEFEAT_ALL_OTHER_KINGDOMS:
			return n.alive and g.nations.all(func(o): return o == n or not o.alive)
		DEFEAT_OWN_KINGDOM:
			return not n.alive
		DEFEAT_KINGDOM:
			var o := g.nation(tgt)
			return o == null or not o.alive
		FORM_ALLY_WITH_KINGDOM:
			var o := g.nation(tgt)
			return o != null and o.alive and n.relation(o.id) == Defs.Relation.ALLIANCE
		DEFEAT_ALL_FRYHTAN:
			if g.firms.any(func(f): return f.code == "LAIR" and f.nation_id == GameObj.MONSTER_NATION and not f.dead):
				return false
			return g.nations.all(func(o): return o == n or not o.alive or o.kill_monster_score <= n.kill_monster_score)
		DEFEAT_EXCEPT_ALLIANCE:
			var allies := 0
			for o in g.nations:
				if o == n or not o.alive:
					continue
				if n.relation(o.id) != Defs.Relation.ALLIANCE:
					return false
				allies += 1
			return allies <= 1      # every rival gone, but for one ally at most
		REACH_POPULATION:
			return score(g, n, 1) >= c["p2"]
		REACH_FRYHTAN:
			return g.units.filter(func(u): return u.nation_id == n.id and not u.dead and not u.is_human()).size() >= c["p2"]
		REACH_UNIT_COUNT:
			return g.units.filter(func(u): return u.nation_id == n.id and not u.dead and u.sprite_code == tgt).size() >= c["p2"]
		REACH_ECONOMY:
			return score(g, n, 3) >= c["p2"]
		REACH_MILITARY:
			return score(g, n, 2) >= c["p2"]
		REACH_TOTAL:
			return total_score(g, n) >= c["p2"]
		KILL_MONSTER_SCORE:
			return score(g, n, 5) >= c["p2"]
		TRAIN_10_GENERAL:
			return g.units.filter(func(u): return u.nation_id == n.id and not u.dead and u.rank == Defs.Rank.GENERAL and u.leadership >= c["p2"]).size() >= 10
		KILL_UNIT:
			return _gone(tgt)
		KEEP_UNIT_ALIVE:
			return g.day == c["years"] * 365 and not _gone(tgt)
		MEET_UNIT:
			if _gone(tgt) or tgt.inside_firm != null:
				return false
			var r := Rect2i(tgt.cell() - Vector2i.ONE * MEET_UNIT_RANGE, Vector2i.ONE * (MEET_UNIT_RANGE * 2 + 1))
			return g.units.any(func(u): return u.nation_id == n.id and not u.dead and u.inside_firm == null and r.has_point(u.cell()))
		CONQUER_ALL_TOWN:
			return not g.towns.any(func(t): return t.nation_id == 0 and not t.dead and t.tribute_to() == 0)
		CONQUER_TOWN:
			if not is_instance_valid(tgt) or tgt.dead:
				c["target"] = null
				c["supported"] = false     # destroyed: can never be conquered now
				return false
			return tgt.nation_id == n.id or (n.is_fryhtan and tgt.tribute_to() == n.id)
		DESTROY_FIRM:
			return not is_instance_valid(tgt) or tgt.dead
		GET_SCROLL:
			return g.taken_sites.get(tgt, 0) == n.id
		ACQUIRE_ITEM:
			return n.items_acquired.has(tgt)
		NATION_SURVIVE:
			return n.alive and g.day > c["p2"] * 365
		ACQUIRE_TECH:
			return n.tech_level(tgt) > 0
		CONQUER_ALL_FIRM:
			return g.firms.all(func(f): return f.dead or f.nation_id == n.id)
		CONQUER_FIRM:
			if not is_instance_valid(tgt) or tgt.dead:
				c["target"] = null
				c["supported"] = false
				return false
			return tgt.nation_id == n.id
	return false


static func _gone(u) -> bool:
	return u == null or not is_instance_valid(u) or u.dead


# ------------------------------------------------------------- scores ---
# Info::get_rank_score: each rating scaled to 100 at the original's reference
# value: population 100, military 200, economy 6000, reputation 100, Fryhtan kills 1000.

static func score(g: Game, n: Nation, kind: int) -> int:
	match kind:
		1:
			# NationBase::all_population: villagers plus every unit
			var pop := 0
			for t in g.towns:
				if t.nation_id == n.id and not t.dead:
					pop += t.population
			for u in g.units:
				if u.nation_id == n.id and not u.dead:
					pop += 1
			return pop
		2:
			# NationArray::update_military_rating: hit points (+90 for war machines)
			# and 20 per unit, over 50
			var pts := 0.0
			for u in g.units:
				if u.nation_id == n.id and not u.dead:
					pts += u.hp + (90.0 if u.is_weapon else 0.0) + 20.0
			return int(pts / 50.0 * 100.0 / 200.0)
		3:
			# NationBase::get_economic_rating: cash/300 + income/2 + profit, over a year
			var f := float(posmod(g.day, 365)) / 365.0
			var income := n.income_year + n.last_income_year * (1.0 - f)
			var expense := n.expense_year + n.last_expense_year * (1.0 - f)
			var rating := n.cash / 300.0 + income / 2.0 + (income - expense)
			return maxi(0, int(rating * 100.0 / 6000.0))
		4:
			return maxi(0, int(n.reputation))
		5:
			return int(n.kill_monster_score * 100.0 / 1000.0)
	return 0


## The current value a score goal measures, or -1 for other goals.
static func progress(g: Game, n: Nation, c: Dictionary) -> int:
	match c["id"]:
		REACH_POPULATION: return score(g, n, 1)
		REACH_MILITARY: return score(g, n, 2)
		REACH_ECONOMY: return score(g, n, 3)
		KILL_MONSTER_SCORE: return score(g, n, 5)
		REACH_TOTAL: return total_score(g, n)
	return -1


static func total_score(g: Game, n: Nation) -> int:
	var t := 0
	for k in range(1, 6):
		t += score(g, n, k)
	return t


# ------------------------------------------------------------- save ---

func to_dict(id_of: Callable) -> Dictionary:
	var pack := func(list: Array) -> Array:
		return list.map(func(c):
			var d: Dictionary = c.duplicate()
			var t = c["target"]
			d["target"] = id_of.call(t) if t is Object else t
			d["target_obj"] = t is Object
			return d)
	return {"require_all": require_all, "win": pack.call(win), "lose": pack.call(lose), "year_limit": year_limit}


static func from_dict(d: Dictionary, by_id: Dictionary) -> Goals:
	var gl := Goals.new()
	gl.require_all = d.get("require_all", false)
	gl.year_limit = int(d.get("year_limit", 0))
	for side in ["win", "lose"]:
		for c in d.get(side, []):
			var cond: Dictionary = c.duplicate()
			if cond.get("target_obj", false):
				cond["target"] = by_id.get(int(cond["target"]))
			cond.erase("target_obj")
			for k in ["id", "p1", "p2", "years"]:
				cond[k] = int(cond[k])
			(gl.win if side == "win" else gl.lose).append(cond)
	_fill_texts(gl)
	return gl
