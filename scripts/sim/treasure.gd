class_name Treasure
extends Node2D
## Something lying on the map for the first unit that steps on it (Site with
## site_type SCROLL, GOLD_COIN, ITEM or WEAPON_BLUEPRINT, osite.cpp): a Scroll of
## Power, a heap of gold, an item, or the plans of a war machine.

enum Kind { SCROLL = 2, GOLD = 3, ITEM = 4, BLUEPRINT = 5 }

var kind := Kind.ITEM
var object_id := 0     # race id (scroll), gold amount, item id, TECH row (blueprint)
var para := 0          # item charges; a Fryhtan kingdom's life points for gold
var cell := Vector2i.ZERO
var recno := 0         # the scenario's site number, for goals
var taken_by := 0      # nation that picked it up


func setup(k: int, obj: int, p: int, at: Vector2i) -> void:
	kind = k
	object_id = obj
	para = p
	cell = at
	position = Iso.to_screen(Vector2(at))


func center_loc() -> Vector2:
	return Vector2(cell) + Vector2(0.5, 0.5)


func footprint() -> Rect2i:
	return Rect2i(cell, Vector2i.ONE)


func title() -> String:
	match kind:
		Kind.SCROLL:
			return "%s Scroll of Power" % Defs.race_name(race())
		Kind.GOLD:
			return "Treasure: %d gold" % object_id
		Kind.ITEM:
			return Items.item_name(object_id)
		Kind.BLUEPRINT:
			return "Scroll of Weapon: %s" % tech_name()
	return ""


func description() -> String:
	match kind:
		Kind.SCROLL:
			var g: Dictionary = Defs.gods.get(race(), {})
			return "A %s unit who picks it up lets its kingdom build the %s Seat of Power and invoke %s." % [
				Defs.race_name(race()), Defs.race_name(race()), Defs.unit_types.get(g.get("unit", ""), {}).get("name", "its Greater Being")]
		Kind.GOLD:
			return "Whoever finds it adds it to the treasury."
		Kind.ITEM:
			return Items.description(object_id, para) + ". Soldiers and Fryhtans can carry one item."
		Kind.BLUEPRINT:
			return "Grants the technology to whoever picks it up."
	return ""


## The race (code) a Scroll of Power belongs to.
func race() -> String:
	return Defs.races[object_id - 1]["code"] if object_id >= 1 and object_id <= Defs.races.size() else ""


func tech_code() -> String:
	var techs := Assets.table("TECH")
	return techs[object_id - 1]["TECH"] if object_id >= 1 and object_id <= techs.size() else ""


func tech_name() -> String:
	var techs := Assets.table("TECH")
	return techs[object_id - 1]["DESC"] if object_id >= 1 and object_id <= techs.size() else "?"


## Site::draw: scrolls and coins from I_SPICT.RES, items from I_ITEMB.RES.
func render(cv) -> void:
	var tex: Texture2D = null
	var at := Vector2.ZERO          # from the location's top corner
	match kind:
		Kind.SCROLL:
			tex = Assets.spict("SCROLL" + race().substr(0, 2), Color.WHITE)
			at = Vector2(-23, -8)
		Kind.GOLD:
			# ositedrw.cpp: COINS-(1 + site_recno % 8); treasures dropped in play vary by cell
			var n := recno if recno > 0 else cell.x * 7 + cell.y
			tex = Assets.spict("COINS-%d" % (1 + posmod(n, 8)), Color.WHITE)
		Kind.ITEM:
			tex = Assets.item_bitmap(Items.info(object_id)[Items.BITMAP]) if Items.TABLE.has(object_id) else null
			if tex:
				at = Vector2(-tex.get_width() / 2.0, 32.0 - tex.get_height())   # bottom centre of the location
		Kind.BLUEPRINT:
			tex = Assets.spict("WEAP-SCR", Color.WHITE)
	if tex == null:
		cv.draw_circle(Vector2(0, 16), 5.0, Color(1.0, 0.85, 0.3))
		return
	if kind == Kind.GOLD or kind == Kind.BLUEPRINT:
		at = Vector2(-tex.get_width() / 2.0, 16.0 - tex.get_height() / 2.0)
	cv.draw_texture(tex, at)
