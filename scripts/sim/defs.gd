class_name Defs
## Game rules and constants. Values are taken from the 7k2 GPL source
## (gamedef.h, otown.h, ofirm.h) and from the STD.SET tables of the install.

const FRAMES_PER_DAY := 10
const SIM_FPS := 20.0               # simulation frames per second at normal speed
const LOC := 32                      # world pixels per location (LOCATE_WIDTH)

const MAX_TOWN_POPULATION := 100
const MAX_WAGON_POPULATION := 10   # ou_wagon.h
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
const ATTACK_SLOW_DOWN := 3.0
const EFFECTIVE_LEADING_DISTANCE := 10.0
const EFFECTIVE_DEFEND_DISTANCE := 10.0    # camps defend places this close (ounit.h)
const GUARD_COUNT_MAX := 5                 # frames a raised shield stays up (osprite.h)
const SPECIAL_ABILITY_DELAY := 15          # days between special abilities (oun_spab.cpp)
const SPECIAL_ABILITY_DURATION := 10
## Unit::use_special_ability: each infantry and special unit's power.
const SPECIAL_ABILITY := {
	"NO_INF": "mirage", "NO_SPU": "reflect", "VI_INF": "freeze", "VI_SPU": "mirage",
	"CE_INF": "freeze", "CE_SPU": "mirage", "RO_INF": "reflect", "RO_SPU": "reflect",
	"GR_INF": "reflect", "GR_SPU": "reflect", "CT_INF": "reflect", "CT_SPU": "freeze",
	"CH_INF": "mirage", "CH_SPU": "reflect", "JA_INF": "freeze", "JA_SPU": "mirage",
	"MO_INF": "freeze", "MO_SPU": "mirage", "EG_INF": "mirage", "EG_SPU": "mirage",
	"PE_INF": "reflect", "PE_SPU": "mirage", "IN_INF": "mirage", "IN_SPU": "mirage",
}  # a general leads men within this many cells (ounit.h)


## AttackAttribute::effectiveness: how well an attack works on a target's
## defence: ((sturdiness + explosiveness)/2 * target sturdiness
## + (100 - target sturdiness) * heat + wood favour * is wood) / 10000 + 1.
static func effectiveness(att: Array, defense: Array) -> float:
	return ((att[0] + att[1]) / 2 * defense[0] + (100 - defense[0]) * att[2] + att[3] * defense[1]) / 10000.0 + 1.0      # how many times all attack damage is reduced (gamedef.h)
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
	"OFF_BLD1": "Teledamnum. Calls down a thunderbolt on enemies and buildings up to 20 cells away. Costs gold per strike.",
	"OFF_BLD2": "Preuser. Freezes every enemy within 10 cells for 20 days. Costs gold per blast.",
	"OFF_BLD3": "Testudo. A tower that shoots at enemies on its own.",
	"OFF_BLD4": "Archimedetron. Burns every enemy within 8 cells. Costs gold per blast.",
	"LISHORR": "Lishorr. A Fryhtan plant that shoots at enemies, harder in clear weather.",
	"WLISHORR": "Wilde Lishorr. Grows wild once planted: it shoots at everyone and spreads in February and July.",
	"BEE": "Bheema Hyfe. Breeds Bheema, fierce flying insects.",
	"TERMITE": "Tarmes Mownd. Breeds Tarmes, armoured insects.",
	"ANIMAL": "Keraal. Wild beasts the brood has tamed come here to be hired.",
	"ALCHEMY": "Alchemist Tor. Turns gold and life points into each other, or minerals into either when built on a deposit.",
	"INCUBAT": "Vapngart. Grows living war machines: Cobrez, Peltez and Nemezez.",
	"MAGIC": "Mage Tor. Casts the spells your brood has learnt: damage buildings, freeze or wound units, teleport.",
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
	{"code": "EXPCART", "name": "Porcupine", "max": 3, "cost": 50, "req": "FLAMETHR", "req_lvl": 2},
	{"code": "F_BALLIS", "name": "Unicorn", "max": 3, "cost": 50, "req": "EXPCART", "req_lvl": 1},
	# Offensive Buildings (TECH class OFF_BLD, complexity 200)
	{"code": "OFF_BLD1", "name": "Teledamnum", "max": 1, "cost": 200, "firm": "OFF_BLD1"},
	{"code": "OFF_BLD2", "name": "Preuser", "max": 1, "cost": 200, "firm": "OFF_BLD2"},
	{"code": "OFF_BLD3", "name": "Testudo", "max": 1, "cost": 200, "firm": "OFF_BLD3"},
	{"code": "OFF_BLD4", "name": "Archimedetron", "max": 1, "cost": 200, "firm": "OFF_BLD4"},
]
const WEAPONS := ["CATAPULT", "BALLISTA", "FLAMETHR", "CANNON", "EXPCART", "F_BALLIS"]
## Mega weapons cannot be researched: their plans are taken from a fallen king
## (TECH class MEGA_WEP); a War Factory builds them once known.
const MEGA_WEAPONS := ["M_CANNON", "M_F_BALL", "M_SAW"]
const MEGA_TECHS := [
	{"code": "M_CANNON", "name": "Mega Cannon", "max": 1, "cost": 500, "mega": true},
	{"code": "M_F_BALL", "name": "Mega Unicorn", "max": 1, "cost": 500, "mega": true},
	{"code": "M_SAW", "name": "Mega Saw", "max": 1, "cost": 500, "mega": true},
]
## Offensive buildings a human kingdom builds once researched.
const OFFENSIVE_FIRMS := ["OFF_BLD1", "OFF_BLD2", "OFF_BLD3", "OFF_BLD4"]

## Special Unit Structure (SPUS_xxx: build the race's training centre) and Special
## Unit Berserker (SPUB_xxx: its power attack). Race-specific: a kingdom researches
## them only for races it has towns of (TechInfo::can_research).
const SPU_TECH_SUFFIX := {
	"NORMAN": "NOR", "VIKING": "VIK", "CELTIC": "CEL", "ROMAN": "ROM", "GREEK": "GRE", "CARTH": "CAR",
	"CHINESE": "CHI", "JAPANESE": "JAP", "MONGOL": "MON", "EGYPTIAN": "EGY", "PERSIAN": "PER", "INDIAN": "IND",
}

## Fryhtan technologies (TECH classes PLANT ... GREMJERM). A Fryhtan kingdom buys
## them at a lair of the species with life points (FirmLair::buy_tech); the price
## is complexity x 20 (TechInfo::live_points_cost).
const FRYHTAN_TECHS := [
	{"code": "LISHORR", "name": "Lishorr", "max": 3, "cost": 50, "species": "PLANT", "firm": "LISHORR"},
	{"code": "WLISHORR", "name": "Wilde Lishorr", "max": 1, "cost": 70, "species": "PLANT", "firm": "WLISHORR", "req": "LISHORR", "req_lvl": 1},
	{"code": "LISH_CAM", "name": "Camouflage Ability", "max": 1, "cost": 50, "species": "PLANT", "req": "LISHORR", "req_lvl": 1, "req2": "WLISHORR", "req2_lvl": 1},
	{"code": "FBEE", "name": "Bheema Hyfe", "max": 3, "cost": 50, "species": "LYW", "firm": "BEE", "unit": "BEE"},
	{"code": "FTERMITE", "name": "Tarmes Mownd", "max": 3, "cost": 50, "species": "LYW", "firm": "TERMITE", "unit": "TERMITE"},
	{"code": "JAGUAR", "name": "Jaguara", "max": 2, "cost": 50, "species": "HOBGLOB", "firm": "ANIMAL", "unit": "JAGUAR"},
	{"code": "GORILLA", "name": "Goril", "max": 2, "cost": 50, "species": "HOBGLOB", "firm": "ANIMAL", "unit": "GORILLA"},
	{"code": "RHINOCER", "name": "Rhinokeros", "max": 1, "cost": 50, "species": "HOBGLOB", "firm": "ANIMAL", "unit": "RHINOCER"},
	{"code": "LIVEGOLD", "name": "Life Points to Gold", "max": 1, "cost": 50, "species": "GIANTET", "firm": "ALCHEMY"},
	{"code": "GOLDLIVE", "name": "Gold to Life Points", "max": 1, "cost": 100, "species": "GIANTET", "firm": "ALCHEMY"},
	{"code": "MINELIVE", "name": "Minerals to Life Points", "max": 1, "cost": 150, "species": "GIANTET", "firm": "ALCHEMY"},
	{"code": "MINEGOLD", "name": "Minerals to Gold", "max": 1, "cost": 150, "species": "GIANTET", "firm": "ALCHEMY"},
	{"code": "ALCHEMY", "name": "Advanced Alchemy", "max": 2, "cost": 100, "species": "GIANTET"},
	{"code": "FORTRESS", "name": "Fortress", "max": 3, "cost": 50, "species": "GITH", "firm": "FORTRESS"},
	{"code": "FORT_CAM", "name": "Camouflaged Fortress", "max": 1, "cost": 50, "species": "GITH", "req": "FORTRESS", "req_lvl": 1},
	{"code": "WEAPON1", "name": "Cobrez", "max": 3, "cost": 30, "species": "ROCKMAN", "firm": "INCUBAT", "unit": "F__BALLI"},
	{"code": "WEAPON2", "name": "Peltez", "max": 3, "cost": 50, "species": "ROCKMAN", "firm": "INCUBAT", "unit": "F_CATAPU"},
	{"code": "WEAPON3", "name": "Nemezez", "max": 3, "cost": 70, "species": "ROCKMAN", "firm": "INCUBAT", "unit": "F_CANNON"},
	{"code": "MAGIC1", "name": "Damage Building", "max": 1, "cost": 90, "species": "GREMJERM", "firm": "MAGIC"},
	{"code": "MAGIC2", "name": "Freeze Units", "max": 1, "cost": 40, "species": "GREMJERM", "firm": "MAGIC"},
	{"code": "MAGIC3", "name": "Wound Units", "max": 1, "cost": 60, "species": "GREMJERM", "firm": "MAGIC"},
	{"code": "MAGIC4", "name": "Teleport Unit", "max": 1, "cost": 40, "species": "GREMJERM", "firm": "MAGIC"},
]
const FRYHTAN_TECH_LIVE_FACTOR := 20.0      # TechInfo::live_points_cost: complexity x 20
## Fryhtan special buildings placed like other buildings, in menu order. The
## Fortress is not placed: four Grokkens turn into one.
const FRYHTAN_FIRMS := ["LISHORR", "WLISHORR", "BEE", "TERMITE", "ANIMAL", "ALCHEMY", "INCUBAT", "MAGIC"]
const FORTRESS_BUILDER := "GITH"

## Spells of the Mage Tor and the human offensive buildings
## (FirmMagic::magic_info_array): live/cost are the minimum price, "extra_*" the
## price per cell beyond the cast range; delay is taken from the 100-point charge.
const SPELLS := {
	"DESTROY": {"short": "Blast", "name": "Damage Building", "tech": "MAGIC1", "live": 30, "cost": 0, "delay": 61, "effect": 50, "range": 20, "radius": 0, "extra_live": 5, "extra_cost": 0},
	"FREEZE": {"short": "Freeze", "name": "Freeze Units", "tech": "MAGIC2", "live": 30, "cost": 0, "delay": 30, "effect": 12, "range": 20, "radius": 3, "extra_live": 4, "extra_cost": 0},
	"WOUND": {"short": "Wound", "name": "Wound Units", "tech": "MAGIC3", "live": 100, "cost": 0, "delay": 10, "effect": 100, "range": 8, "radius": 3, "extra_live": 6, "extra_cost": 0},
	"TELEPORT": {"short": "Teleport", "name": "Teleport Unit", "tech": "MAGIC4", "live": 15, "cost": 0, "delay": 5, "effect": 0, "range": 50, "radius": 0, "extra_live": 1, "extra_cost": 0},
	"FREEZE_LASER": {"short": "Freeze", "name": "Freezing Blast", "tech": "", "live": 0, "cost": 120, "delay": 50, "effect": 20, "range": 0, "radius": 10, "extra_live": 0, "extra_cost": 0},
	"GOD_POWER": {"short": "Thunderbolt", "name": "Thunderbolt", "tech": "", "live": 0, "cost": 140, "delay": 50, "effect": 100, "range": 20, "radius": 3, "extra_live": 0, "extra_cost": 5},
	"LASER": {"short": "Death ray", "name": "Death Ray", "tech": "", "live": 0, "cost": 70, "delay": 50, "effect": 150, "range": 0, "radius": 8, "extra_live": 0, "extra_cost": 0},
}
const FIRM_SPELLS := {
	"MAGIC": ["DESTROY", "FREEZE", "WOUND", "TELEPORT"],
	"OFF_BLD1": ["GOD_POWER"], "OFF_BLD2": ["FREEZE_LASER"], "OFF_BLD4": ["LASER"],
}
const MAX_CAST_DELAY := 100

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
				"pierce": ar["PIERCE_DMG"].to_int(), "bullet": ar["BUL_SPRITE"], "consume": ar["CONSUME_P"].to_int(),
				"bullet_speed": maxi(4, ar["BUL_SPEED"].to_int()), "action": "A%d" % ar["ATTK_ID"].to_int(),
				"radius": ar.get("BUL_RADIUS", "0").to_int(), "fire": ar.get("FL_RADIUS", "0").to_int(),
				# AttackAttribute: sturdiness, explosiveness, heat, wood favour
				"att": [ar.get("STURDINESS", "0").to_int(), ar.get("EXPLOSIVE", "0").to_int(), ar.get("HEAT", "0").to_int(), ar.get("WOOD_FAVOR", "0").to_int()],
			})
		# DefenseAttribute: sturdiness and whether it is made of wood
		t["def"] = [u.get("STURDINESS", "0").to_int(), u.get("IS_WOOD", "0").to_int()]
		t["guard_level"] = u.get("GUARDLEVEL", "0").to_int()      # UnitInfo::guard_combat_level
		t["weapon_power"] = u.get("WEAPONPOW", "0").to_int()
		unit_types[u["SPRITE"]] = t
	for f in Assets.table("FIRM"):
		firm_types[f["CODE"]] = {
			"code": f["CODE"], "name": f["NAME"], "hp": maxi(100, f["HITPOINTS"].to_int()),
			"cost": f["SETUP_COST"].to_int(), "year_cost": f["YEAR_COST"].to_int(), "live_cost": f["SETUP_LIVE"].to_int(),
			"overseer": f["OVERTITLE"], "worker": f["WORKTITLE"],
		}
	for m in Assets.table("MONSTER"):
		monsters.append({"unit": m["UNIT"], "name": m["NAME"], "level": m["LEVEL"].to_int()})
	for h in Assets.table("HERO"):
		heroes.append({"name": h["NAME"], "race": h["RACE"]})
	for g in Assets.table("GOD"):
		gods[g["RACE"]] = {"unit": g["UNIT"], "exist_pray": g["EXISTPRAY"].to_int(),
			"power_pray": maxi(10, g["POWERPRAY"].to_int()), "can_cast": g["CANCAST"] == "1",
			"cast_range": maxi(1, g["CASTRANGE"].to_int()), "race": g["RACE"]}
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
	"CARTH": "Earthquake: everything within 32 cells is shaken for two days",
	"JAPANESE": "Expose the enemy spies near by; mercenaries at inns ask 30% less and stay",
	"MONGOL": "Enemy units turn to your side, the less loyal the likelier",
	"PERSIAN": "Reveal what goes on inside the buildings near by",
	"EGYPTIAN": "Ten more people in each of your towns near by",
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


const MAX_NATION := 7             # gamedef.h: kingdoms in a game


## Whether a race code names a Fryhtan species (a monster's unit sprite).
static func is_monster_code(code: String) -> bool:
	return monsters.any(func(m): return m["unit"] == code)


static func race_name(code: String) -> String:
	for r in races:
		if r["code"] == code:
			return r["name"]
	return code.capitalize()


## World::effective_distance (building_size 2, the game's set): "" is a town.
static func effective_distance(a: String, b: String) -> int:
	if a == "" and b == "":
		return 12              # EFFECTIVE_TOWN_TOWN_DISTANCE
	if a == "":
		var t := a
		a = b
		b = t
	if b == "":
		if a in ["CAMP", "FORT", "LAIR"]:
			return 10          # EFFECTIVE_CAMP_TOWN_DISTANCE
		return 16              # EFFECTIVE_FIRM_TOWN_DISTANCE
	if a == "LAIR" and b == "LAIR":
		return 9               # EFFECTIVE_LAIR_LAIR_DISTANCE
	return 15                  # EFFECTIVE_FIRM_FIRM_DISTANCE


static func unit_sprite(race: String, kind: String) -> String:
	return RACE_PREFIX.get(race, "NO") + "_" + kind


## Whether a nation may research the next level of a technology now.
static func can_research(n, t: Dictionary) -> bool:
	if n.tech_level(t["code"]) >= t["max"] or t.get("mega", false):
		return false
	# a campaign unveils technologies stage by stage (TechInfo::available_level)
	if Game.inst and Game.inst.tech_available != null and n.tech_level(t["code"]) >= int(Game.inst.tech_available.get(t["code"], 0)):
		return false
	if t.has("race") and not Game.inst.nation_has_race_town(n.id, t["race"]):
		return false
	if t.has("req") and n.tech_level(t["req"]) < t["req_lvl"]:
		return false
	if t.has("req2") and n.tech_level(t["req2"]) < t["req2_lvl"]:
		return false
	return true


static func tech_def(code: String) -> Dictionary:
	for t in research_techs():
		if t["code"] == code:
			return t
	for t in FRYHTAN_TECHS + MEGA_TECHS:
		if t["code"] == code:
			return t
	return {}


static var _research_techs: Array = []

## The research list of the Tower of Science: the common techs plus the
## special-unit techs of every race (offered only for races the kingdom has towns of).
static func research_techs() -> Array:
	if not _research_techs.is_empty():
		return _research_techs
	var out: Array = TECHS.duplicate()
	for r in SPU_TECH_SUFFIX:
		var sfx: String = SPU_TECH_SUFFIX[r]
		var adj := race_adj(r)
		out.append({"code": "SPUS_" + sfx, "name": adj + " Training Centre", "max": 1, "cost": 15, "race": r})
		out.append({"code": "SPUB_" + sfx, "name": adj + " Berserker", "max": 1, "cost": 25, "race": r, "req": "SPUS_" + sfx, "req_lvl": 1})
	if not races.is_empty():
		_research_techs = out
	return out


static func race_adj(code: String) -> String:
	for r in races:
		if r["code"] == code:
			return r["adj"] if r["adj"] != "" else r["name"]
	return code.capitalize()


static func spu_structure_tech(race: String) -> String:
	return "SPUS_" + SPU_TECH_SUFFIX.get(race, "NOR")


static func spu_berserk_tech(race: String) -> String:
	return "SPUB_" + SPU_TECH_SUFFIX.get(race, "NOR")


## Fryhtan techs of one species, bought at its lairs.
static func fryhtan_techs(species: String) -> Array:
	return FRYHTAN_TECHS.filter(func(t): return t["species"] == species)


static func fryhtan_tech_live_cost(t: Dictionary) -> float:
	return float(t["cost"]) * FRYHTAN_TECH_LIVE_FACTOR


## The techs any of which unlocks a Fryhtan or offensive building.
static func firm_techs(code: String) -> Array:
	var out := []
	for t in FRYHTAN_TECHS + TECHS:
		if t.get("firm", "") == code:
			out.append(t["code"])
	return out


## Whether a kingdom knows how to build this Fryhtan or offensive building.
static func knows_firm(n, code: String) -> bool:
	var ts := firm_techs(code)
	if ts.is_empty():
		return true
	for c in ts:
		if n.tech_level(c) > 0:
			return true
	return false


## The tech a Fryhtan unit (insect, animal, bio-weapon) needs.
static func unit_tech(sprite: String) -> String:
	for t in FRYHTAN_TECHS:
		if t.get("unit", "") == sprite:
			return t["code"]
	return ""


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
