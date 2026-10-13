class_name Tutorial
extends RefCounted
## The learning campaigns (otutor.cpp, otutor3.cpp): a lesson is a prepared
## map from the install's Tutorial folder with texts from TUT_TEXT.RES, taught
## objective by objective. Each objective has its pages of text and hints, and
## a condition (Tutor::update_tutorial_objective_finish_count) that moves the
## lesson on: select something, press a button, build something, or simply
## Continue. The lesson is won by the map's own goals.

## The lessons shipped with the game (TUT_LIST.RES); "id" is the original's
## cur_tutor_id, "file" the map in the Tutorial folder.
const LESSONS := [
	{"id": 1, "code": "HLC1", "file": "Hlc1", "name": "Human Training One", "desc": "DHLC1"},
	{"id": 2, "code": "FLC1", "file": "Flc1", "name": "Fryhtan Training One", "desc": "DFLC1"},
	{"id": 3, "code": "HLC2", "file": "Hlc2", "name": "Human Training Game One", "desc": "DHLC2"},
	{"id": 4, "code": "FLC2", "file": "Flc2", "name": "Fryhtan Training Game One", "desc": "DFLC2"},
	{"id": 5, "code": "HLC3", "file": "Hlc3", "name": "Human Training Two", "desc": "DHLC3"},
	{"id": 7, "code": "HLC4", "file": "Hlc4", "name": "Human Training Game Two", "desc": "DHLC4"},
	{"id": 9, "code": "HLC5", "file": "Hlc5", "name": "Human Training Three", "desc": "DHLC5"},
	{"id": 11, "code": "HLC6", "file": "Hlc6", "name": "Human Training Game Three", "desc": "DHLC6"},
]

## The original's button codes and the actions of this interface that do the same.
const BUTTONS := {
	"TRAIN": ["Fill from towns"], "PATROL": ["Send out soldiers"], "RETCAMP": ["Return"],
	"BUILD": ["Build..."], "PROMOTE": ["Promote to General"], "F_PATROL": ["Send out brood"],
	"F_RETCMP": ["Return"], "F_PROMOT": ["Promote to General"], "F_GRANT": ["Take over"],
	"HIRECARA": ["Hire caravan"], "S_TRAIN": ["Train "], "MAKEWEAP": ["Catapult", "Ballista", "Spitfire", "Cannon", "Porcupine", "Unicorn", "Mega"],
	"GDINVOKE": ["Invoke Greater Being"], "BLESS": ["Special Blessing"], "CARACOPY": ["Clone caravan"], "GB-B1": ["Special Blessing"], "TRAIN-C": ["Train spy"], "TRAIN-I": ["Train spy"], "TRAIN-S": ["Train spy"],
	"SPYNOTI0": ["Disguise"], "SPYNOTI1": ["Disguise", "Camouflage"], "SPYMENU": ["Mission", "Bribe", "Offer", "Assassinate", "Steal", "Incident", "Secret", "Recall"],
	"CHG-MISS": ["Mission"],
}

var lesson: Dictionary = {}
var blocks: Array = []          # {obj, button, title, text}
var hints: Array = []           # {obj, text}: what the original pointed at on the map
var achieved := {}              # objective -> true
var current := 1                # the objective being taught
var page := 0                   # page among the current objective's blocks
var continue_pressed := false
var pressed: Array = []         # action labels pressed since the last check
var par1 = null                 # a town remembered between objectives (lesson 1)
var finished := false
var g: Game


static func lesson_by_id(id: int) -> Dictionary:
	for l in LESSONS:
		if l["id"] == id:
			return l
	return {}


static func map_path(l: Dictionary) -> String:
	var dir := Assets.install_path.path_join("Tutorial")
	for suffix in ["L", "l", "S", "s"]:
		var p := SK2Files.find_file(dir, l["file"] + suffix + ".tut")
		if p != "":
			return p
	return ""


static func texts() -> Dictionary:
	return CampaignText.load_res(SK2Files.find_file(Assets.install_path.path_join("Resource"), "TUT_TEXT.RES"))


static func description(l: Dictionary) -> String:
	return texts().get(l["desc"], "").strip_edges()


func setup(game: Game, id: int) -> void:
	g = game
	lesson = lesson_by_id(id)
	var all := texts()
	blocks = _parse(all.get(lesson.get("code", ""), ""))
	hints = _parse(all.get("B" + lesson.get("code", ""), "")).map(func(b): return {"obj": b["obj"], "text": b["text"]})
	current = 1
	if blocks.is_empty():
		finished = true


## Tutor::load: two heading lines, then blocks split by "~", each with an
## optional "Button : X" line and a "Title: * NN" line naming its objective.
static func _parse(t: String) -> Array:
	var out: Array = []
	var lines := t.split("\n")
	var body := "\n".join(lines.slice(2)) if lines.size() > 2 else ""
	for raw in body.split("~"):
		var blk := raw.strip_edges()
		if blk == "":
			continue
		var b := {"obj": 0, "button": "", "title": "", "text": ""}
		var rest: Array = []
		for ln in blk.split("\n"):
			var l := ln.strip_edges()
			if l.begins_with("Button"):
				b["button"] = l.get_slice(":", 1).strip_edges()
			elif l.begins_with("Title"):
				var tt := l.get_slice(":", 1).strip_edges()
				if tt.contains("**"):
					b["title"] = tt.replace("**", "").strip_edges()
				elif tt.begins_with("*"):
					b["obj"] = tt.substr(1).strip_edges().to_int()
				else:
					b["title"] = tt
			else:
				rest.append(ln.strip_edges(false, true))
		b["text"] = "\n".join(rest).strip_edges()
		if b["text"] != "":
			out.append(b)
	return out


func pages() -> Array:
	return blocks.filter(func(b): return b["obj"] == current)


func current_hints() -> Array:
	return hints.filter(func(h): return h["obj"] == current).map(func(h): return h["text"])


func last_objective() -> int:
	var m := 0
	for b in blocks:
		m = maxi(m, b["obj"])
	return m


## Whether the current objective waits for the Continue button.
func wants_continue() -> bool:
	return _has_continue(_cond(current))


static func _has_continue(c: Array) -> bool:
	if c.is_empty():
		return false
	if c[0] == "continue":
		return true
	if c[0] in ["and", "or"]:
		return _has_continue(c[1]) or _has_continue(c[2])
	return false


func press(label: String) -> void:
	pressed.append(label)


## Checked a few times a second: the current objective done, the next begins.
func check() -> bool:
	if finished or g == null or g.player() == null:
		return false
	var c := _cond(current)
	var done := _eval(c)
	pressed.clear()
	if not done:
		if not wants_continue():
			continue_pressed = false
		return false
	achieved[current] = true
	continue_pressed = false
	current += 1
	page = 0
	if current > last_objective():
		finished = true
	return true


# --------------------------------------------------------- conditions ---

## Objective n of the lesson as a condition (after otutor3.cpp):
## ["continue"], ["sel_town", goal], ["sel_firm", goal], ["sel_type", code],
## ["button", code], ["built", code], ["goal", k], ["attack_town", goal],
## ["return_to", goal], ["sel_unit"], ["and", a, b], ["or", a, b], ["never"], ...
func _cond(n: int) -> Array:
	match int(lesson.get("id", 0)):
		1:
			match n:
				1: return ["and", ["sel_firm", 2], ["continue"]]
				2: return ["or", ["button", "TRAIN"], ["sel_full_fort"]]
				3, 4, 7, 8, 11, 13, 16, 19, 22: return ["continue"]
				5: return ["and", ["sel_firm", 2], ["and", ["firm_manned", 2], ["continue"]]]
				6: return ["button", "PATROL"]
				9: return ["and", ["continue"], ["sel_unit"]]
				10: return ["or", ["button", "RETCAMP"], ["any_return"]]
				12, 21: return ["sel_indep_same_race"]
				14, 17: return ["sel_soldier"]
				15: return ["button", "BUILD"]
				18: return ["button", "PROMOTE"]
				20: return ["any_full_camp"]
				23: return ["par1_mine"]
				24: return ["goal", 5]
				25: return ["goal", 6]
		2:
			match n:
				1, 7: return ["sel_town", 1]
				2, 8, 13: return ["sel_firm", 5]
				3, 9: return ["button", "F_PATROL"]
				4: return ["attack_town", 1]
				5: return ["goal", 1]
				6, 12: return ["or", ["button", "F_RETCMP"], ["return_to", 5]]
				10: return ["attack_town", 2]
				11: return ["goal", 2]
				14: return ["idle_unit"]
				15, 18: return ["sel_unit"]
				16: return ["button", "F_PROMOT"]
				17, 21: return ["sel_firm", 3]
				19: return ["button", "BUILD"]
				20: return ["lair_linked_to", 3]
				22: return ["button", "F_GRANT"]
				23: return ["goal", 3]
				24: return ["goal", 4]
		3, 7, 11:
			if n == 1 or (int(lesson["id"]) == 11 and n <= 6):
				return ["continue"]
			return ["never"]
		4:
			match n:
				1: return ["sel_type", "LAIR"]
				2: return ["fryhtan_tech"]
				3: return ["and", ["sel_type", "MAGIC"], ["built", "MAGIC"]]
				4, 5: return ["continue"]
				_: return ["never"]
		5:
			match n:
				1, 6, 8, 9, 10, 12, 13, 19, 22, 23, 24, 27: return ["continue"]
				2: return ["built", "MINE"]
				3: return ["built", "FACTORY"]
				4: return ["built", "MARKET"]
				5, 16: return ["sel_type", "MARKET"]
				7: return ["sel_town_with_general"]
				11: return ["sel_any_town"]
				14: return ["diplomacy"]
				15: return ["talk", "TRADE"]     # custom_detect_talk_message_id(TALK_PROPOSE_TRADE_TREATY)
				17: return ["button", "HIRECARA"]
				18, 21, 25: return ["sel_caravan"]
				20: return ["foreign_caravan"]
				26: return ["button", "CARACOPY"]
				_: return ["never"]
		9:
			match n:
				1: return ["built", "RESEARCH"]
				2: return ["sel_type", "RESEARCH"]
				3: return ["researching"]
				4, 5, 9, 10, 14, 19, 22, 24, 25, 27, 28, 32, 37, 42, 44, 45, 46, 49, 50, 51, 52, 53: return ["continue"]
				6: return ["built", "STABLE"]
				7: return ["sel_type", "STABLE"]
				8: return ["or", ["button", "S_TRAIN"], ["stable_busy"]]
				11: return ["built", "WAR"]
				12: return ["sel_type", "WAR"]
				13: return ["or", ["button", "MAKEWEAP"], ["war_busy"]]
				15: return ["built", "BASE"]
				16, 20: return ["sel_type", "BASE"]
				17: return ["button", "GDINVOKE"]
				18: return ["sel_god"]
				21: return ["button", "BLESS"]
				23, 26: return ["sel_type", "INN"]
				29: return ["sel_type", "SPY"]
				30: return ["or", ["button", "TRAIN-C"], ["college_busy"]]
				31: return ["spy_in_sel_town", true]
				33: return ["sel_spy"]
				34: return ["and", ["continue"], ["sel_unit"]]
				35: return ["button", "SPYNOTI0"]
				36: return ["button", "SPYNOTI1"]
				38: return ["spy_in_sel_town", false]
				39, 48: return ["button", "SPYMENU"]
				40: return ["button", "CHG-MISS"]
				41, 47: return ["spy_in_sel_camp"]
				43: return ["and", ["continue"], ["spy_in_sel_camp"]]
				_: return ["never"]
	return ["goal", n] if n > 0 else ["never"]


func _eval(c: Array) -> bool:
	if c.is_empty():
		return false
	var p := g.player()
	var sel: Array = g.selected.filter(func(o): return is_instance_valid(o) and not o.dead)
	var first = sel[0] if not sel.is_empty() else null
	match c[0]:
		"and":
			return _eval(c[1]) and _eval(c[2])
		"or":
			return _eval(c[1]) or _eval(c[2])
		"never":
			return false
		"continue":
			return continue_pressed
		"firm_manned":
			# the fort selected has soldiers in it (soldier_count > 0)
			var f = _target(c[1])
			return f is Firm and not f.soldiers.is_empty()
		"talk":
			return g.talk_log.any(func(m): return m["from"] == p.id and m["id"] == c[1])
		"button":
			for want in BUTTONS.get(c[1], [c[1]]):
				for got in pressed:
					if str(got).begins_with(want):
						return true
			return false
		"goal":
			return g.goals != null and c[1] < g.goals.win.size() and g.goals._true(g.goals.win[c[1]], g, p)
		"sel_town", "sel_firm":
			var t = _target(c[1])
			return t != null and first == t
		"sel_type":
			return first is Firm and first.code == c[1] and first.nation_id == p.id
		"sel_any_town":
			return first is Town
		"sel_unit":
			return first is Unit and first.nation_id == p.id
		"sel_soldier":
			return first is Unit and first.nation_id == p.id and first.rank == Defs.Rank.SOLDIER and first.is_human() and not first.is_civilian()
		"sel_full_fort":
			return first is Firm and first.nation_id == p.id and first.is_military() and first.soldiers.size() >= first.capacity()
		"sel_indep_same_race":
			if first is Town and first.nation_id == 0 and first.race == p.race:
				par1 = first
				return true
			return false
		"par1_mine":
			return par1 != null and is_instance_valid(par1) and par1.nation_id == p.id
		"sel_town_with_general":
			return first is Town and first.nation_id == p.id and first.linked_firms.any(func(f): return f.nation_id == p.id and f.is_military() and f.overseer != null)
		"sel_caravan":
			return first is Unit and first.is_caravan and first.nation_id == p.id
		"sel_god":
			return first is Unit and first.is_god and first.nation_id == p.id
		"sel_spy":
			return first is Unit and first.is_spy and first.nation_id == p.id
		"built":
			return g.firms.any(func(f): return f.nation_id == p.id and f.code == c[1] and not f.under_construction and not f.dead)
		"attack_town":
			var t = _target(c[1])
			return t != null and g.units.any(func(u): return u.nation_id == p.id and not u.dead and u.order == Unit.Order.ATTACK and u.target == t)
		"return_to":
			var t = _target(c[1])
			return t != null and g.units.any(func(u): return u.nation_id == p.id and not u.dead and u.order == Unit.Order.ENTER and u.order_firm == t)
		"any_return":
			return g.units.any(func(u): return u.nation_id == p.id and not u.dead and u.order == Unit.Order.ENTER and u.order_firm and u.order_firm.is_military())
		"idle_unit":
			return g.units.any(func(u): return u.nation_id == p.id and not u.dead and u.inside_firm == null and u.order == Unit.Order.IDLE)
		"any_full_camp":
			return g.firms.any(func(f): return f.nation_id == p.id and f.is_military() and not f.under_construction and f.soldiers.size() >= f.capacity())
		"lair_linked_to":
			var t = _target(c[1])
			return t != null and g.firms.any(func(f): return f.nation_id == p.id and f.code == "LAIR" and f.overseer != null and t in f.linked_firms)
		"fryhtan_tech":
			return Defs.FRYHTAN_TECHS.any(func(t): return p.tech_level(t["code"]) > 0)
		"researching":
			return g.firms.any(func(f): return f.nation_id == p.id and f.code == "RESEARCH" and f.research_tech != "")
		"stable_busy":
			return g.firms.any(func(f): return f.nation_id == p.id and f.code == "STABLE" and f.weapon != "")
		"war_busy":
			return g.firms.any(func(f): return f.nation_id == p.id and f.code == "WAR" and f.weapon != "")
		"college_busy":
			return g.firms.any(func(f): return f.nation_id == p.id and f.code == "SPY" and f.weapon_queue > 0)
		"spy_in_sel_town":
			# c[1]: any town (a spy guarding home counts); false: another kingdom's town
			if not first is Town or (not c[1] and first.nation_id == p.id):
				return false
			return Espionage.spies_in(first).any(func(s): return s.nation_id == p.id)
		"spy_in_sel_camp":
			return first is Firm and first.nation_id != p.id and Espionage.is_camp(first) and Espionage.spies_in(first).any(func(s): return s.nation_id == p.id)
		"diplomacy":
			return pressed.has("<diplomacy>")
		"foreign_caravan":
			return g.units.any(func(u): return u.is_caravan and u.nation_id == p.id and not u.dead and u.caravan_dest and is_instance_valid(u.caravan_dest) and u.caravan_dest.nation_id != p.id)
	return false


func _target(goal_index: int):
	if g.goals == null or goal_index >= g.goals.win.size():
		return null
	var t = g.goals.win[goal_index]["target"]
	return t if t is GameObj and is_instance_valid(t) and not t.dead else null


## The object the current objective is about, for the "Show me" button.
func focus_target() -> GameObj:
	var c := _cond(current)
	for part in [c] + (c.slice(1) if c.size() > 1 and c[0] in ["and", "or"] else []):
		if part is Array and part.size() > 1 and part[0] in ["sel_town", "sel_firm", "attack_town", "return_to", "lair_linked_to"]:
			return _target(part[1])
	return null
