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
var had_base := false         # has owned a town or building (scenario armies start without)

# yearly statistics, reset every January
var income_year := 0.0
var expense_year := 0.0
## This year's and last year's money by kind (the original's INCOME_* and
## EXPENSE_* types), for the economy report.
var income_by := {}
var expense_by := {}
var last_income_by := {}
var last_expense_by := {}
var last_income_year := 0.0
var last_expense_year := 0.0
var known_gods := {}             # race -> true: Scrolls of Power held (GodInfo::nation_know_array)
var items_acquired := {}         # item id -> true, for scenario goals
var contact := {}                 # nation id -> true: the two know each other (NationRelation::has_contact)
var trade_treaty := {}            # nation id -> true: caravans may trade there (NationRelation::trade_treaty)
var ai_rel := {}                  # nation id -> 0..100: how the computer feels about it (ai_relation_level)
var status_day := {}              # nation id -> day the relation last changed
var war_count := {}               # nation id -> wars it started on us (started_war_on_us_count)
var never_until := {}             # "TALK:nation" -> day before which such a message is refused
var reject_day := {}              # "TALK:nation" -> day our message was last rejected
var sent_day := {}                # "TALK:nation" -> day we last sent it
var prefs := {}                   # the computer's personality, 0..100 (pref_*)
var last_aid_day := -1000         # last military aid received
var kill_monster_score := 0.0   # Fryhtans slain: 1 a soldier, 5 a general, 20 a king (Unit::die)

var ai: NationAI = null


func _init(nation_id: int, nation_race: String, nation_color: Color, ai_controlled: bool) -> void:
	id = nation_id
	race = nation_race
	color = nation_color
	is_ai = ai_controlled
	name = "Kingdom of " + Defs.race_name(race)
	known_gods[race] = true          # NationBase::init: a kingdom knows its own Greater Being


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


## Money in (v > 0) or out, of a kind such as "Taxes" or "Buildings".
func add_cash(v: float, kind := "Other") -> void:
	cash += v
	if v >= 0:
		income_year += v
		income_by[kind] = income_by.get(kind, 0.0) + v
	else:
		expense_year -= v
		expense_by[kind] = expense_by.get(kind, 0.0) - v


func new_year() -> void:
	last_income_year = income_year
	last_expense_year = expense_year
	income_year = 0.0
	expense_year = 0.0
	last_income_by = income_by
	last_expense_by = expense_by
	income_by = {}
	expense_by = {}


func change_reputation(v: float) -> void:
	reputation = clampf(reputation + v, -100.0, 100.0)


func can_afford(v: float) -> bool:
	return cash >= v
