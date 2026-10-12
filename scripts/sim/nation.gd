class_name Nation
extends RefCounted
## A kingdom: treasury, food, reputation, technology and diplomacy.

var id := 0
var name := ""
var race := "NORMAN"
var color := Color.WHITE
var is_ai := true
var is_player := false
var alive := true

var cash := 0.0
var food := 0.0
var reputation := 20.0        # -100..100
var king: Unit = null
var tech := {}                # code -> level
var research_progress := {}   # code -> points toward next level
var relations := {}           # other nation id -> Defs.Relation
var prayer_points := 0.0
var is_fryhtan := false       # a Fryhtan kingdom: lairs and monsters instead of towns
var monster_code := ""        # its species (unit sprite code)
var live_points := 0.0        # Fryhtan currency for breeding, gained by killing
var god_summoned := false
var homeless_days := 0        # days without any town or building

# yearly statistics, reset every January
var income_year := 0.0
var expense_year := 0.0

var ai: NationAI = null


func _init(nation_id: int, nation_race: String, nation_color: Color, ai_controlled: bool) -> void:
	id = nation_id
	race = nation_race
	color = nation_color
	is_ai = ai_controlled
	name = "Kingdom of " + Defs.race_name(race)


func tech_level(code: String) -> int:
	return tech.get(code, 0)


func relation(other_id: int) -> int:
	if other_id == id:
		return Defs.Relation.ALLIANCE
	if other_id == 0:
		return Defs.Relation.NEUTRAL
	return relations.get(other_id, Defs.Relation.NEUTRAL)


func is_hostile_to(other_id: int) -> bool:
	return other_id != id and other_id > 0 and relation(other_id) == Defs.Relation.WAR


func add_cash(v: float) -> void:
	cash += v
	if v >= 0:
		income_year += v
	else:
		expense_year -= v


func change_reputation(v: float) -> void:
	reputation = clampf(reputation + v, -100.0, 100.0)


func can_afford(v: float) -> bool:
	return cash >= v
