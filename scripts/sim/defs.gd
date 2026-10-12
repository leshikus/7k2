class_name Defs
## Game rules and constants. Values are taken from the 7k2 GPL source
## (gamedef.h, otown.h, ofirm.h) and from the STD.SET tables of the install.

const FRAMES_PER_DAY := 10
const SIM_FPS := 20.0               # simulation frames per second at normal speed
const LOC := 32                      # world pixels per location (LOCATE_WIDTH)

const MAX_TOWN_POPULATION := 100
const MAX_WORKER := 20
const MAX_SOLDIER := 15
const MIN_RECRUIT_LOYALTY := 30
const CITIZEN_COMBAT_LEVEL := 10.0     # every villager leaving a town starts here (CITIZEN_COMBAT_LEVEL)
const MIN_TECH_THEFT_SPYING_SKILL := 70
const UNIT_BETRAY_LOYALTY := 30      # a unit whose loyalty falls below this may desert (gamedef.h)
const SPY_COST := 80
const SURRENDER_LOYALTY := 30
const SURRENDER_RESISTANCE := 30
const REBEL_LOYALTY := 29
const TAX_PER_UNIT := 3
const COLLECT_TAX_LOYALTY_DECREASE := 10
const GRANT_RESISTANCE_DECREASE := 10
const GRANT_COST_PER_UNIT := 10
const PEASANT_FOOD_YEAR_PRODUCTION := 30
const UNIT_FOOD_YEAR_CONSUMPTION := 10
const RAW_PRICE := 1.5
const PRODUCT_PRICE := 3.0
const CONSUMER_PRICE := 4.5
const PROCESS_GOODS_INTERVAL := 3
const EFFECTIVE_FIRM_TOWN_DISTANCE := 16
const EFFECTIVE_FIRM_FIRM_DISTANCE := 16
const MAX_COMBAT_TRAIN := 100
const MAX_RAW_RESERVE_QTY := 20000
const EXPLORE_RANGE := 10
const TOWN_SIZE := 6

enum Rank { SOLDIER, GENERAL, KING }
enum Relation { WAR, NEUTRAL, PEACE, ALLIANCE }

const RELATION_NAMES := ["War", "Neutral", "Peace treaty", "Alliance"]

## Race code -> sprite prefix used by the unit sprites (NO_INF, VI_CIV ...).
const RACE_PREFIX := {
	"NORMAN": "NO", "VIKING": "VI", "CELTIC": "CE", "ROMAN": "RO", "GREEK": "GR", "CARTH": "CT",
	"CHINESE": "CH", "JAPANESE": "JA", "MONGOL": "MO", "EGYPTIAN": "EG", "PERSIAN": "PE", "INDIAN": "IN",
}

const NATION_COLORS := [
	Color(0.85, 0.15, 0.12), Color(0.15, 0.35, 0.95), Color(0.95, 0.80, 0.10), Color(0.60, 0.20, 0.80),
	Color(0.10, 0.75, 0.75), Color(0.95, 0.50, 0.10), Color(0.95, 0.95, 0.95),
]
const INDEPENDENT_COLOR := Color(0.55, 0.55, 0.55)
const MONSTER_COLOR := Color(0.35, 0.65, 0.20)

## Buildings a human kingdom can construct, in menu order.
const HUMAN_FIRMS := ["CAMP", "FORT", "MINE", "FACTORY", "MARKET", "RESEARCH", "WAR", "STABLE", "SPY", "INN", "BASE"]

const FIRM_HELP := {
	"CAMP": "Military camp. A general here gives the kingdom influence over nearby towns; soldiers train here.",
	"FORT": "Stronger military base with more influence.",
	"MINE": "Must be built on a raw-material deposit. Workers come from linked towns.",
	"FACTORY": "Turns raw materials from linked mines into goods.",
	"MARKET": "Sells goods from linked factories to linked towns.",
	"RESEARCH": "Scientists research new technologies.",
	"WAR": "Builds siege weapons once researched.",
	"INN": "Heroes for hire visit here.",
	"STABLE": "Trains your race's special unit from volunteers of linked loyal towns.",
	"SPY": "Espionage College. Trains spies to infiltrate enemy and independent towns and buildings.",
	"BASE": "Seat of Power. Linked people of the kingdom's race pray to summon their Greater Being.",
}

const TECHS := [
	{"code": "MINING", "name": "Advanced Mining", "max": 2, "cost": 20},
	{"code": "MANUFACT", "name": "Advanced Manufacturing", "max": 2, "cost": 20},
	{"code": "FARMING", "name": "Advanced Farming", "max": 4, "cost": 20},
	{"code": "WAR_PROD", "name": "War Machine Production", "max": 2, "cost": 20},
	{"code": "INFCLOSE", "name": "Infantry Close Combat", "max": 2, "cost": 20},
	{"code": "INFRANGE", "name": "Infantry Range Attack", "max": 2, "cost": 20},
	{"code": "INFDEFEN", "name": "Infantry Defense", "max": 2, "cost": 20},
	{"code": "CATAPULT", "name": "Catapult", "max": 3, "cost": 20},
	{"code": "BALLISTA", "name": "Ballista", "max": 3, "cost": 30},
	{"code": "FLAMETHR", "name": "SpitFire", "max": 3, "cost": 30, "req": "CATAPULT", "req_lvl": 2},
	{"code": "CANNON", "name": "Cannon", "max": 3, "cost": 70, "req": "BALLISTA", "req_lvl": 2},
	# Spying Methodology (TECH table class SPYING)
	{"code": "AGITATE", "name": "Advanced Agitation", "max": 1, "cost": 12, "spy": true},
	{"code": "COUNTERS", "name": "Advanced Counter-spy", "max": 1, "cost": 14, "spy": true},
	{"code": "STEALINF", "name": "Information Theft", "max": 1, "cost": 16, "spy": true},
	{"code": "BRIBE", "name": "Advanced Bribing", "max": 1, "cost": 18, "spy": true, "req": "AGITATE", "req_lvl": 1},
	{"code": "ASSASSIN", "name": "Advanced Assassination", "max": 1, "cost": 20, "spy": true, "req": "BRIBE", "req_lvl": 1},
	{"code": "STEALTEC", "name": "Technology Theft", "max": 1, "cost": 22, "spy": true, "req": "STEALINF", "req_lvl": 1},
	{"code": "CAMOUFLG", "name": "Camouflage", "max": 1, "cost": 26, "spy": true, "req": "COUNTERS", "req_lvl": 1, "req2": "ASSASSIN", "req2_lvl": 1},
	{"code": "INCIDENT", "name": "Create Incident", "max": 1, "cost": 28, "spy": true, "req": "CAMOUFLG", "req_lvl": 1},
]
const WEAPONS := ["CATAPULT", "BALLISTA", "FLAMETHR", "CANNON"]

static var races: Array = []          # [{code, name, adj}]
static var unit_types := {}           # sprite code -> unit type dict
static var firm_types := {}           # firm code -> firm type dict
static var monsters: Array = []       # [{unit, name, level}]
static var heroes: Array = []         # [{name, race}]
static var gods := {}                 # race -> {unit, exist_pray}
static var town_names: Array = []
static var town_names_by_race := {}
static var first_names := {}
static var last_names := {}
static var loaded := false


static func load_from_assets() -> void:
	if loaded:
		return
	races.clear()
	for r in Assets.table("RACE"):
		races.append({"code": r["CODE"], "name": r["NAME"], "adj": r["ADJECTIVE"]})
	var attacks := Assets.table("UNITATTK")
	for u in Assets.table("UNIT"):
		var t := {
			"name": u["NAME"], "sprite": u["SPRITE"], "race": u["RACE"], "class": u["CLASS"],
			"hp": maxi(10, u["HIT_PT"].to_int()), "armor": u["ARMOR"].to_int(),
			"vis": maxi(4, u["VIS_RANGE"].to_int()), "cost": u["BUILDCOST"].to_int(),
			"build_days": maxi(5, u["BUILDDAYS"].to_int()), "year_cost": u["YEARCOST"].to_int(),
			"live_cost": u["BUILDLIVE"].to_int(), "flying": u["MOBILE"] == "A",
			"icon_ptr": u["LICONPTR"], "attacks": [],
		}
		var first: int = u["FIRSTATTK"].to_int()
		for a in range(first, first + u["ATTKCOUNT"].to_int()):
			if a < 1 or a > attacks.size():
				continue
			var ar: Dictionary = attacks[a - 1]
			t["attacks"].append({
				"combat_lvl": ar["COMBAT_LVL"].to_int(), "delay": maxi(1, ar["ATTK_DELAY"].to_int()),
				"range": maxi(1, ar["ATTK_RANGE"].to_int()), "damage": ar["BASIC_DMG"].to_int(),
				"pierce": ar["PIERCE_DMG"].to_int(), "bullet": ar["BUL_SPRITE"],
				"bullet_speed": maxi(4, ar["BUL_SPEED"].to_int()), "action": "A%d" % ar["ATTK_ID"].to_int(),
			})
		unit_types[u["SPRITE"]] = t
	for f in Assets.table("FIRM"):
		firm_types[f["CODE"]] = {
			"code": f["CODE"], "name": f["NAME"], "hp": maxi(100, f["HITPOINTS"].to_int() * 4),
			"cost": f["SETUP_COST"].to_int(), "year_cost": f["YEAR_COST"].to_int(),
			"overseer": f["OVERTITLE"], "worker": f["WORKTITLE"],
		}
	for m in Assets.table("MONSTER"):
		monsters.append({"unit": m["UNIT"], "name": m["NAME"], "level": m["LEVEL"].to_int()})
	for h in Assets.table("HERO"):
		heroes.append({"name": h["NAME"], "race": h["RACE"]})
	for g in Assets.table("GOD"):
		gods[g["RACE"]] = {"unit": g["UNIT"], "exist_pray": g["EXISTPRAY"].to_int(),
			"power_pray": maxi(10, g["POWERPRAY"].to_int()), "can_cast": g["CANCAST"] == "1",
			"cast_range": maxi(6, g["CASTRANGE"].to_int() * 3), "race": g["RACE"]}
	# TOWNNAME is split into "@RACE" sections.
	var tn_race := ""
	for n in Assets.table("TOWNNAME"):
		var nm: String = n["NAME"]
		if nm.begins_with("@"):
			tn_race = nm.substr(1)
		elif nm != "":
			town_names.append(nm)
			if not town_names_by_race.has(tn_race):
				town_names_by_race[tn_race] = []
			town_names_by_race[tn_race].append(nm)
	# RACENAME lists "@1RACE" (first names) and "@2RACE" (last names) sections.
	var cur: Dictionary = {}
	var cur_race := ""
	for r in Assets.table("RACENAME"):
		var nm: String = r["NAME"]
		if nm.begins_with("@"):
			cur_race = nm.substr(2)
			cur = first_names if nm.substr(1, 1) == "1" else last_names
			if not cur.has(cur_race):
				cur[cur_race] = []
		elif cur_race != "" and nm != "":
			cur[cur_race].append(nm)
	loaded = true


## What each Greater Being's power does (ou_god.cpp), shown on its button.
const GOD_POWERS := {
	"ROMAN": "Raise the leadership of nearby generals",
	"GREEK": "Make nearby own units invulnerable for 30 days",
	"CARTH": "Earthquake: shake enemy buildings and units",
	"JAPANESE": "Freeze nearby enemy units for 10 days",
	"MONGOL": "Turn nearby enemy units to your side",
	"PERSIAN": "Reveal the surrounding land",
	"INDIAN": "Summon a tornado",
}

## Passive blessings granted while the Seat of Power has worshippers.
const GOD_BLESSINGS := {
	"NORMAN": "Collecting taxes costs less loyalty.",
	"EGYPTIAN": "Towns grow faster.",
	"CHINESE": "Markets earn 30% more.",
	"CARTH": "Farms yield more food.",
	"MONGOL": "Independent towns resist your camps less.",
	"GREEK": "Towns build and repair walls by themselves.",
}


static func god_for_unit(sprite: String) -> Dictionary:
	for r in gods:
		if gods[r]["unit"] == sprite:
			return gods[r]
	return {}


static func race_name(code: String) -> String:
	for r in races:
		if r["code"] == code:
			return r["name"]
	return code.capitalize()


static func unit_sprite(race: String, kind: String) -> String:
	return RACE_PREFIX.get(race, "NO") + "_" + kind


## Whether a nation may research the next level of a technology now.
static func can_research(n, t: Dictionary) -> bool:
	if n.tech_level(t["code"]) >= t["max"]:
		return false
	if t.has("req") and n.tech_level(t["req"]) < t["req_lvl"]:
		return false
	if t.has("req2") and n.tech_level(t["req2"]) < t["req2_lvl"]:
		return false
	return true


static func tech_def(code: String) -> Dictionary:
	for t in TECHS:
		if t["code"] == code:
			return t
	return {}


static func random_person_name(race: String, rng: RandomNumberGenerator) -> String:
	# famous names (HERO table) are reserved for heroes hired at an inn
	var firsts: Array = first_names.get(race, [])
	if firsts.is_empty():
		return Defs.race_name(race) + " " + str(rng.randi_range(1, 999))
	var name: String = firsts[rng.randi() % firsts.size()]
	var lasts: Array = last_names.get(race, [])
	if not lasts.is_empty():
		name += " " + lasts[rng.randi() % lasts.size()]
	return name
