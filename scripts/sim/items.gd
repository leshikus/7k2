class_name Items
## The original's items (oitemres.cpp item_info_array): what each does and how it
## is used up or recharged. A unit carries at most one item (Unit::item); its
## `item_para` holds the charges, uses left or remaining time.

enum Ability {
	NONE, MELEE_DAMAGE, ARROW_DAMAGE, DAMAGE, ATTACK_SPEED, DEC_LOYALTY, FREEZE, ANTI_MONSTER,
	ARMOR, ABSORB_HIT, RECOVERY, INVINCIBLE, SPEED, INVISIBLE, SCOUT_RANGE, COMBAT_LEVEL,
	SKILL_LEVEL, TRAIN, SUMMON, UNIT_BETRAY, TOWN_BETRAY, TOWN_FREE, TELEPORT,
}
enum Para { NONE, ENHANCE, USE, USE_MANUAL, CHARGE, USE_TIMED, CHARGE_TIMED }

const MIN_RARITY := 0
const MAX_RARITY := 3

## id -> [name, rare, cost, ability, value, para type, use rate, use limit,
##        recover rate, para max, magic, magic para, init para, init random, bitmap, description]
const TABLE := {
	1: ["Berserker Sword", 0, 100, Ability.MELEE_DAMAGE, 5, Para.NONE, 0, 0, 0, 0, 0, 0, 0, 0, "SWORD_2", "Close attack +5"],
	2: ["Bow of Odysseus", 0, 100, Ability.ARROW_DAMAGE, 5, Para.NONE, 0, 0, 0, 0, 0, 0, 0, 0, "BOW_1", "Range attack +5"],
	3: ["Aegis Shield", 0, 100, Ability.ARMOR, 5, Para.NONE, 0, 0, 0, 0, 0, 0, 0, 0, "SHIELD_1", "Defense +5"],
	4: ["Excalibur", 0, 200, Ability.COMBAT_LEVEL, 30, Para.NONE, 0, 0, 0, 0, 0, 0, 0, 0, "SWORD_1", "Combat level +30"],
	5: ["The Art of War", 2, 300, Ability.SKILL_LEVEL, 20, Para.NONE, 0, 0, 0, 0, 0, 0, 0, 0, "BOOK_1", "Leadership +20"],
	6: ["Raptorsclaw", 0, 100, Ability.ATTACK_SPEED, 2, Para.NONE, 0, 0, 0, 0, 0, 0, 0, 0, "SWORD_3", "Attack speed +2"],
	7: ["Ring of Life", 1, 200, Ability.RECOVERY, 4, Para.NONE, 0, 0, 0, 0, 0, 0, 0, 0, "RING_1", "Recover life"],
	8: ["Boots of Hermes", 0, 150, Ability.SPEED, 2, Para.NONE, 0, 0, 0, 0, 0, 0, 0, 0, "BOOT_1", "Speed +2"],
	9: ["Aegis Field", 3, 500, Ability.ABSORB_HIT, 1, Para.USE, 1, 0, 0, 0, 0, 0, 50, 50, "WRIST_1", "Absorb hits"],
	10: ["Staff of Invincibility", 2, 350, Ability.INVINCIBLE, 1, Para.USE_TIMED, 1, 0, 0, 0, 0, 0, 20, 10, "STAFF_1", "Invincibility"],
	11: ["Heartchanger", 1, 300, Ability.DEC_LOYALTY, 40, Para.NONE, 0, 0, 0, 0, 0, 0, 0, 0, "HAT_1", "Decrease enemy's Loyalty"],
	12: ["Cyrostaff", 2, 1000, Ability.FREEZE, 20, Para.NONE, 0, 0, 0, 0, 0, 0, 0, 0, "STAFF_2", "Freeze enemy"],
	13: ["Heimdall's Horn", 1, 700, Ability.SUMMON, 1, Para.USE_MANUAL, 1, 0, 0, 1, 0, 0, 1, 0, "HORN_1", "Summon fryhtan"],
	14: ["Unseen Torque", 2, 500, Ability.INVISIBLE, 1, Para.CHARGE_TIMED, 1, 2, 1, 50, 0, 0, 50, 0, "AMULET_1", "Invisibility"],
	15: ["Vistastaff", 0, 100, Ability.SCOUT_RANGE, 2, Para.NONE, 0, 0, 0, 0, 0, 0, 0, 0, "STAFF_3", "Scouting range"],
	16: ["Cordial of Combat", 1, 250, Ability.DAMAGE, 8, Para.CHARGE, 4, 8, 1, 20, 0, 0, 20, 0, "POTION_1", "Berserker damage"],
	17: ["The Art of Training", 3, 800, Ability.TRAIN, 100, Para.ENHANCE, 0, 0, 0, 0, 0, 0, 0, 0, "BOOK_3", "Increase training speed"],
	18: ["Kharshuf's Bane", 3, 1000, Ability.ANTI_MONSTER, 20, Para.NONE, 0, 0, 0, 0, 0, 0, 1, 0, "STAFF_4", "Extra Damage against Kharshuf"],
	19: ["Bregma's Bane", 3, 1000, Ability.ANTI_MONSTER, 20, Para.NONE, 0, 0, 0, 0, 0, 0, 2, 0, "STAFF_4", "Extra Damage against Bregma"],
	20: ["Kerassos' Bane", 3, 1000, Ability.ANTI_MONSTER, 20, Para.NONE, 0, 0, 0, 0, 0, 0, 3, 0, "STAFF_4", "Extra Damage against Kerassos"],
	21: ["Minotauros' Bane", 3, 1000, Ability.ANTI_MONSTER, 20, Para.NONE, 0, 0, 0, 0, 0, 0, 4, 0, "STAFF_4", "Extra Damage against Minotauros"],
	22: ["Grokken's Bane", 3, 1000, Ability.ANTI_MONSTER, 20, Para.NONE, 0, 0, 0, 0, 0, 0, 5, 0, "STAFF_4", "Extra Damage against Grokken"],
	23: ["Ezpinez's Bane", 3, 1000, Ability.ANTI_MONSTER, 20, Para.NONE, 0, 0, 0, 0, 0, 0, 6, 0, "STAFF_4", "Extra Damage against Ezpinez"],
	24: ["Exovum's Bane", 3, 1000, Ability.ANTI_MONSTER, 20, Para.NONE, 0, 0, 0, 0, 0, 0, 7, 0, "STAFF_4", "Extra Damage against Exovum"],
	25: ["Judas Ring", 4, 2000, Ability.UNIT_BETRAY, 8, Para.USE_MANUAL, 1, 0, 0, 1, 0, 1, 1, 0, "RING_3", "Convert an opponent to your side"],
	26: ["Judas Rod", 4, 3000, Ability.TOWN_BETRAY, 8, Para.USE_MANUAL, 1, 0, 0, 1, 0, 2, 1, 0, "ROD_1", "Convert a town to your side"],
	27: ["Neutralizer", 4, 2000, Ability.TOWN_FREE, 8, Para.USE_MANUAL, 1, 0, 0, 1, 0, 2, 1, 0, "ROD_2", "Turn a town independent"],
	28: ["Telecordial", 4, 500, Ability.TELEPORT, 1, Para.USE_MANUAL, 1, 0, 0, 1, 0, 3, 1, 0, "POTION_2", "Teleport across the world"],
	29: ["Unseen Torque", 4, 200, Ability.INVISIBLE, 1, Para.USE_TIMED, 1, 2, 0, 100, 0, 0, 100, 0, "AMULET_1", "Invisibility"],
}
const NAME := 0
const RARE := 1
const COST := 2
const ABILITY := 3
const VALUE := 4
const PARA := 5
const USE_RATE := 6
const USE_LIMIT := 7
const RECOVER := 8
const PARA_MAX := 9
const MAGIC_PARA := 11
const INIT := 12
const INIT_RANDOM := 13
const BITMAP := 14
const DESC := 15

## Items used from the unit panel; the magic para says what they are aimed at
## (0 itself, 1 a unit, 2 a town, 3 a place).
## Items the campaign hands out (ITEM_LEADER, ITEM_REGENERATE, ITEM_UNIT_CHANGE_NATION ...).
const LEADER_ITEM := 5
const REGEN_ITEM := 7
const UNIT_CHANGE_ITEM := 25
const TOWN_CHANGE_ITEM := 26
const TOWN_FREE_ITEM := 27
const TELEPORT_ITEM := 28
const INVISIBLE_ITEM := 29

const MANUAL_TARGET := {13: "self", 25: "unit", 26: "town", 27: "town", 28: "place"}


static func info(id: int) -> Array:
	return TABLE.get(id, [])


static func item_name(id: int) -> String:
	return TABLE[id][NAME] if TABLE.has(id) else ""


static func description(id: int, para: int) -> String:
	if not TABLE.has(id):
		return ""
	var t: Array = TABLE[id]
	var s: String = t[DESC]
	match t[PARA]:
		Para.USE, Para.CHARGE:
			s += " (%d left)" % para
		Para.USE_TIMED, Para.CHARGE_TIMED:
			s += " (active, %d days)" % -para if para < 0 else " (%d)" % para
		Para.ENHANCE:
			s += " +%d" % para
	return s


## ItemRes::ability: what the item gives toward `ab` right now (0 when spent or off).
static func ability(id: int, para: int, ab: int) -> int:
	if not TABLE.has(id):
		return 0
	var t: Array = TABLE[id]
	var bonus := 0
	match t[PARA]:
		Para.ENHANCE:
			bonus = para
		Para.USE, Para.CHARGE:
			if para < t[USE_LIMIT] or (t[PARA] == Para.USE and para <= 0):
				return 0
		Para.USE_TIMED, Para.CHARGE_TIMED:
			if para > 0:        # positive: not switched on
				return 0
	if t[ABILITY] == ab:
		return t[VALUE] + bonus
	if t[ABILITY] == Ability.DAMAGE and (ab == Ability.MELEE_DAMAGE or ab == Ability.ARROW_DAMAGE):
		return t[VALUE] + bonus
	return 0


## ItemRes::use_now: returns the para left; -1 when the item is used up.
static func use_now(id: int, para: int) -> int:
	var t: Array = TABLE.get(id, [])
	if t.is_empty():
		return -1
	match t[PARA]:
		Para.USE, Para.USE_MANUAL:
			para -= t[USE_RATE]
			return para if para > 0 else -1
		Para.CHARGE:
			return para - t[USE_LIMIT]
	return para


## ItemRes::next_day: timed items run down, charged ones recharge. -1 = used up.
static func next_day(id: int, para: int) -> int:
	var t: Array = TABLE.get(id, [])
	if t.is_empty():
		return para
	match t[PARA]:
		Para.USE_TIMED:
			if para < 0:
				para += t[USE_RATE]
				if para >= 0:
					return -1
		Para.CHARGE_TIMED:
			if para < 0:
				para = mini(0, para + t[USE_RATE])
			else:
				para = mini(t[PARA_MAX], para + t[RECOVER])
		Para.CHARGE:
			para = mini(t[PARA_MAX], para + t[RECOVER])
	return para


## Timed items are switched on from the unit panel: the time left goes negative.
static func can_turn_on(id: int, para: int) -> bool:
	var t: Array = TABLE.get(id, [])
	return not t.is_empty() and t[PARA] in [Para.USE_TIMED, Para.CHARGE_TIMED] and para > 0 \
		and (t[PARA] == Para.USE_TIMED or para >= t[USE_LIMIT])


static func turn_on(id: int, para: int) -> int:
	return -para


static func random_para(id: int, rng: RandomNumberGenerator) -> int:
	var t: Array = TABLE.get(id, [])
	if t.is_empty():
		return 0
	return t[INIT] + (rng.randi() % t[INIT_RANDOM] if t[INIT_RANDOM] > 0 else 0)


## Item::init_random: an item of the given rarity, or 0.
static func random_id(rng: RandomNumberGenerator, low: int, high: int) -> int:
	var pick := 0
	var match_n := 0
	for id in TABLE:
		var r: int = TABLE[id][RARE]
		if r >= low and r <= high:
			match_n += 1
			if rng.randi() % match_n == 0:
				pick = id
	return pick


## ItemRes::can_pick: fighting humans and Fryhtans; not peasants, carts or machines.
static func can_pick(u: Unit) -> bool:
	if u.dead or u.is_weapon or u.is_civilian() or u.sprite_code in ["CARAVAN", "WAGON"]:
		return false
	return u.is_human() or u.is_monster() or (u.nation() != null and u.nation().is_fryhtan)


## The Fryhtan species a Bane item is aimed at (para 1..7 = MONSTER table rows).
static func bane_target(para: int) -> String:
	return Defs.monsters[para - 1]["unit"] if para >= 1 and para <= Defs.monsters.size() else ""


## The Bane item that hurts a Fryhtan species more (ITEM_MONSTER1_BOOK + id).
static func bane_for(species: String) -> int:
	for id in range(18, 25):
		if bane_target(TABLE[id][INIT]) == species:
			return id
	return 0
