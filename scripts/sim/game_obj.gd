class_name GameObj
extends Node2D
## Common base of units, firms and towns.

const MONSTER_NATION := 99

static var _next_id := 1

var obj_id := 0
var nation_id := 0
var hp := 100.0
var max_hp := 100.0
var dead := false
var selected := false
var last_attacker: GameObj = null
var last_attacked_frame := -1000


func _init() -> void:
	obj_id = _next_id
	_next_id += 1


func game() -> Game:
	return Game.inst


## Location rectangle covered by this object.
func footprint() -> Rect2i:
	return Rect2i(0, 0, 1, 1)


## Centre in location coordinates.
func center_loc() -> Vector2:
	var r := footprint()
	return Vector2(r.position) + Vector2(r.size) * 0.5


func armor() -> float:
	return 0.0


func display_name() -> String:
	return "Object"


func is_monster() -> bool:
	return nation_id == MONSTER_NATION


func nation() -> Nation:
	return Game.inst.nation(nation_id) if Game.inst else null


## The kingdom others take this object for: its own, or a disguised spy's cloak.
func seen_nation() -> int:
	return nation_id


func nation_color() -> Color:
	if nation_id == MONSTER_NATION:
		return Defs.MONSTER_COLOR
	var n := Game.inst.nation(seen_nation()) if Game.inst else null
	return n.color if n else Defs.INDEPENDENT_COLOR


## Distance in locations between the edges of two objects' footprints.
func distance_to(other: GameObj) -> float:
	var a := footprint()
	var b := other.footprint()
	var dx := maxi(0, maxi(a.position.x - b.end.x + 1, b.position.x - a.end.x + 1))
	var dy := maxi(0, maxi(a.position.y - b.end.y + 1, b.position.y - a.end.y + 1))
	return float(maxi(dx, dy))


## Applies damage reduced by armour. The original subtracts armour outright
## (BaseObj::being_attack_hit); with this project's halved hit points a
## proportional reduction keeps fights from stalling at 1 damage per hit.
func take_damage(amount: float, attacker: GameObj) -> void:
	if dead:
		return
	# BaseObj::being_attack_hit: armour is taken off the blow (a blow weaker
	# than the armour still does 1/(armour - damage)), never more than the blow
	# itself, and every hit is slowed down by ATTACK_SLOW_DOWN
	if amount > 0.0:
		var d := amount - armor()
		if d <= -1.0:
			d = -1.0 / d
		elif d < 1.0:
			d = 1.0
		amount = minf(d, amount)
	hp -= amount / Defs.ATTACK_SLOW_DOWN
	# BaseObj::being_attack_hit: every blow struck at a Fryhtan adds to the
	# attacking kingdom's Fryhtan battling score
	if attacker and is_instance_valid(attacker) and attacker.nation_id > 0 and attacker.nation_id != nation_id:
		var vn := nation()
		if is_monster() or (vn and vn.is_fryhtan):
			var an := attacker.nation()
			if an and not an.is_fryhtan:
				an.kill_monster_score += 0.1
	last_attacker = attacker
	last_attacked_frame = Game.inst.frame
	if nation_id == Game.inst.player_id:
		Game.inst.add_war_point(center_loc())
	on_attacked(attacker)
	if hp <= 0.0:
		hp = 0.0
		die(attacker)


func on_attacked(_attacker: GameObj) -> void:
	pass


func die(_killer: GameObj) -> void:
	dead = true


func is_visible_to_player() -> bool:
	var g := Game.inst
	if g == null or g.reveal_all or nation_id == g.player_id:
		return true
	var r := footprint()
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if g.is_loc_visible(Vector2i(x, y)):
				return true
	return false


func draw_hp_bar_on(cv, at: Vector2, width: float) -> void:
	var f := clampf(hp / max_hp, 0.0, 1.0)
	cv.draw_rect(Rect2(at - Vector2(width * 0.5, 0), Vector2(width, 4)), Color(0, 0, 0, 0.7))
	var c := Color(0.2, 0.9, 0.2) if f > 0.5 else (Color(0.95, 0.8, 0.1) if f > 0.25 else Color(0.95, 0.2, 0.1))
	cv.draw_rect(Rect2(at - Vector2(width * 0.5 - 1, -1), Vector2((width - 2) * f, 2)), c)
