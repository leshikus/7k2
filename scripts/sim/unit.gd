class_name Unit
extends GameObj
## A mobile unit: soldier, general, king, hero, siege weapon, Fryhtan or Greater Being.

enum Order { IDLE, MOVE, ATTACK, ENTER, BUILD, RETURN, DYING }

var utype: Dictionary = {}
var sprite_code := ""
var race := ""
var unit_name := ""
var rank := Defs.Rank.SOLDIER
var combat := 10.0
var leadership := 0.0
var loc := Vector2.ZERO           # continuous location; integers are location corners

var order := Order.IDLE
var target: GameObj = null
var order_firm: Firm = null
var resume_target: GameObj = null    # building to return to after fighting off defenders
var path: Array[Vector2i] = []
var path_i := 0
var goal := Vector2i(-1, -1)

var dir := 4
var action := "S"
var anim_frame := 0
var attacking := false
var attack_cooldown := 0
var repath_timer := 0
var scan_timer := 0

var home_town: Town = null        # set for town defenders
var home_firm: Firm = null        # set for soldiers who sallied out of a camp
var inside_firm: Firm = null
var is_hero := false
var is_god := false
var is_weapon := false
var life_frames := -1
var invulnerable_until := -1     # Athena's protection (frame)
var is_caravan := false
var is_spy := false
var spy_skill := 0.0
var spy_place: GameObj = null    # town or firm the spy has infiltrated
var spy_action := "agitate"      # agitate | sabotage | steal
var caravan_home: Firm = null     # market the caravan was hired at
var caravan_dest: Firm = null     # the other market on its route
var caravan_leg := 0              # 0 heading to dest, 1 heading home
var cargo := {}                   # goods type -> quantity
var _caravan_wait := 0
var frozen_until := -1           # Amaterasu's freeze (frame)
var death_frames := 0
var _speed := 4.0


func setup(sprite: String, nation: int, at: Vector2i, skill := 20.0) -> void:
	sprite_code = sprite
	utype = Defs.unit_types.get(sprite, {})
	race = utype.get("race", "")
	nation_id = nation
	loc = Vector2(at)
	combat = skill
	max_hp = float(utype.get("hp", 200)) * 0.5
	hp = max_hp
	is_weapon = utype.get("class", "") in ["WEAPON", "BIO_WEAP"]
	is_god = utype.get("class", "") == "GOD"
	is_caravan = utype.get("class", "") == "CARAVAN"
	_speed = float(Assets.sprites.get(sprite, {}).get("speed", 4))
	unit_name = Defs.random_person_name(race, Game.inst.rng) if race != "" else utype.get("name", sprite)
	position = Iso.to_screen(loc)


func footprint() -> Rect2i:
	return Rect2i(cell(), Vector2i.ONE)


func cell() -> Vector2i:
	return Vector2i(roundi(loc.x), roundi(loc.y))


func center_loc() -> Vector2:
	return loc + Vector2(0.5, 0.5)


func armor() -> float:
	var a := float(utype.get("armor", 0))
	var n := nation()
	if n and race != "":
		a += 2.0 * n.tech_level("INFDEFEN")
	return a


func is_human() -> bool:
	return race != "" and not is_weapon and not is_god


func can_lead() -> bool:
	return is_human() and (rank >= Defs.Rank.GENERAL)


func display_name() -> String:
	var title := ""
	match rank:
		Defs.Rank.KING:
			title = "King "
		Defs.Rank.GENERAL:
			title = "General "
	if is_human():
		return title + unit_name
	return utype.get("name", sprite_code)


func type_name() -> String:
	return utype.get("name", sprite_code)


func speed_loc() -> float:
	var sp := _speed
	# SpriteRes::update_speed: rain slows units by their RAIN_SLOW value
	var rain := mini(7, Game.inst.weather.rain_scale())
	var slow: int = Assets.sprites.get(sprite_code, {}).get("rain_slow", 0)
	if rain > 0 and slow > 0:
		sp = maxf(1.0, sp - (rain * slow / 8 + 1))
	var s := sp / Defs.LOC
	if Game.inst.world.is_hill(cell()):
		s *= 0.75
	return s


# ------------------------------------------------------------------ orders ---

func stop() -> void:
	resume_target = null
	order = Order.IDLE
	target = null
	order_firm = null
	path.clear()
	path_i = 0


func order_move(dest: Vector2i) -> void:
	if dead or inside_firm:
		return
	stop()
	order = Order.MOVE
	_path_to(dest)


func order_attack(obj: GameObj) -> void:
	if dead or inside_firm or obj == null or obj == self or not can_attack():
		return
	stop()
	order = Order.ATTACK
	target = obj
	repath_timer = 0


## Spy: walk to an enemy or independent town/building and slip inside.
func order_infiltrate(target_obj: GameObj) -> void:
	if not is_spy or dead or inside_firm or target_obj == null:
		return
	stop()
	order = Order.ENTER
	order_firm = null
	spy_place = target_obj
	_path_to(Game.inst.world.adjacent_to_rect(target_obj.footprint(), cell()))


func order_enter(f: Firm) -> void:
	if dead or inside_firm:
		return
	stop()
	order = Order.ENTER
	order_firm = f
	_path_to(Game.inst.world.adjacent_to_rect(f.footprint(), cell()))


func order_build(f: Firm) -> void:
	var n := nation()
	if dead or inside_firm or not (is_human() or (n and n.is_fryhtan)):
		return
	stop()
	order = Order.BUILD
	order_firm = f
	_path_to(Game.inst.world.adjacent_to_rect(f.footprint(), cell()))


func can_attack() -> bool:
	return not utype.get("attacks", []).is_empty()


func _path_to(dest: Vector2i) -> void:
	goal = dest
	path = Game.inst.world.find_path(cell(), dest)
	path_i = 0
	if not path.is_empty() and path[0] == cell():
		path_i = 1


# --------------------------------------------------------------- simulation ---

func sim_frame() -> void:
	if inside_firm or spy_place != null and has_meta("hidden"):
		return
	if dead:
		_dying()
		return
	if life_frames > 0:
		life_frames -= 1
		if life_frames == 0:
			die(null)
			return
	if attack_cooldown > 0:
		attack_cooldown -= 1
	if frozen_until > Game.inst.frame:
		queue_redraw()
		return
	var moved := false
	if attacking:
		_attack_anim()
	else:
		match order:
			Order.IDLE:
				if is_caravan:
					_caravan_think()
				else:
					_idle()
			Order.MOVE:
				moved = true
				if _step_move():
					stop()
			Order.ATTACK:
				moved = _do_attack()
			Order.ENTER, Order.BUILD:
				moved = _do_enter()
			Order.RETURN:
				moved = _do_return()
	if not attacking:
		action = "M" if moved else "S"
		anim_frame = anim_frame + 1 if moved else 0
	position = Iso.to_screen(loc)
	queue_redraw()


func _step_move() -> bool:
	if path_i >= path.size():
		return true
	var next := path[path_i]
	if not Game.inst.world.is_walkable(next) and next != cell():
		# The way got blocked (a building went up): look for a new path.
		_path_to(goal)
		if path.is_empty():
			return true
		return false
	var d := Vector2(next) - loc
	var step := speed_loc()
	var nd := Iso.dir_of(d)
	if nd >= 0:
		dir = nd
	if d.length() <= step:
		loc = Vector2(next)
		path_i += 1
		return path_i >= path.size()
	loc += d.normalized() * step
	return false


func _idle() -> void:
	scan_timer -= 1
	if scan_timer > 0:
		return
	scan_timer = 10 + (obj_id % 7)
	# Step aside when sharing a location with another unit.
	var c := cell()
	if Game.inst.unit_cells.get(c, 0) > 1 and obj_id % 2 == 0 and not is_god:
		var free := Game.inst.free_unit_cell(c)
		if free != c:
			order = Order.MOVE
			_path_to(free)
			return
	if not can_attack():
		return
	var enemy := Game.inst.find_enemy_near(self, float(utype.get("vis", 5)))
	if enemy:
		order_attack(enemy)
		return
	if home_firm and (not is_instance_valid(home_firm) or home_firm.dead):
		home_firm = null
	if home_town and (not is_instance_valid(home_town) or home_town.dead):
		home_town = null
	if home_firm:
		order_enter(home_firm)
	elif home_town:
		order = Order.RETURN


# ------------------------------------------------------------- caravans ---

const CARAVAN_CARRY := 200.0      # MAX_CARAVAN_CARRY_QTY
const TRADE_SHARE := 0.4          # share of the goods' value earned by each side of a foreign sale


## Caravans shuttle goods between their market and another one (ou_cara.cpp, simplified).
func _caravan_think() -> void:
	if _caravan_wait > 0:
		_caravan_wait -= 1
		return
	var g := Game.inst
	if caravan_home == null or not is_instance_valid(caravan_home) or caravan_home.dead:
		caravan_home = null
		return
	if caravan_dest == null or not is_instance_valid(caravan_dest) or caravan_dest.dead or not _can_trade_with(caravan_dest):
		caravan_dest = g.find_trade_partner(caravan_home, nation_id)
		caravan_leg = 0
		if caravan_dest == null:
			_caravan_wait = 60
			return
	var stop: Firm = caravan_dest if caravan_leg == 0 else caravan_home
	if distance_to(stop) <= 1.0:
		_trade_at(stop, caravan_home if caravan_leg == 0 else caravan_dest)
		caravan_leg = 1 - caravan_leg
		_caravan_wait = 40
		return
	order = Order.MOVE
	_path_to(g.world.adjacent_to_rect(stop.footprint(), cell()))
	if path.is_empty():
		order = Order.IDLE
		_caravan_wait = 60


func _can_trade_with(f: Firm) -> bool:
	if f.nation_id == nation_id:
		return true
	var n := nation()
	return n != null and n.relation(f.nation_id) >= Defs.Relation.PEACE


## Unload everything into `m`, then load what the next stop lacks.
func _trade_at(m: Firm, next_stop: Firm) -> void:
	var n := nation()
	for gtype in cargo.keys():
		var qty: float = minf(cargo[gtype], Firm.STOCK_CAP - float(m.goods.get(gtype, 0.0)))
		if qty <= 0:
			continue
		m.goods[gtype] = float(m.goods.get(gtype, 0.0)) + qty
		cargo[gtype] -= qty
		if m.nation_id != nation_id:
			var value := qty * Defs.PRODUCT_PRICE * TRADE_SHARE
			if n:
				n.add_cash(value)
			var other := m.nation()
			if other:
				other.add_cash(value)
	cargo = _nonzero(cargo)
	if next_stop == null or not is_instance_valid(next_stop):
		return
	var room := CARAVAN_CARRY
	for gtype in m.goods:
		if room <= 0:
			break
		var have: float = m.goods[gtype]
		var there: float = next_stop.goods.get(gtype, 0.0)
		if have > 60.0 and there < 150.0:
			var take := minf(room, have - 30.0)
			m.goods[gtype] = have - take
			cargo[gtype] = float(cargo.get(gtype, 0.0)) + take
			room -= take


static func _nonzero(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		if d[k] > 0.5:
			out[k] = d[k]
	return out


func current_attack() -> Dictionary:
	var best: Dictionary = {}
	var atts: Array = utype.get("attacks", [])
	var far := target != null and is_instance_valid(target) and distance_to(target) > 1.5
	for a in atts:
		if a["combat_lvl"] > combat:
			continue
		if best.is_empty():
			best = a
		elif far and a["range"] > best["range"]:
			best = a
		elif not far and a["range"] <= 1 and a["damage"] > best["damage"]:
			best = a
	if best.is_empty() and not atts.is_empty():
		best = atts[0]
	return best


func _target_gone() -> bool:
	if target == null or not is_instance_valid(target) or target.dead:
		return true
	if target is Unit and (target as Unit).inside_firm != null:
		return true
	# a town or building that has just surrendered to us
	if target.nation_id == nation_id and nation_id != 0:
		return true
	return false


func _do_attack() -> bool:
	if _target_gone():
		var next := resume_target
		stop()
		scan_timer = 0
		if next and is_instance_valid(next) and not next.dead:
			order_attack(next)
		return false
	var att := current_attack()
	if att.is_empty():
		stop()
		return false
	var dist := distance_to(target)
	if dist <= float(att["range"]):
		path.clear()
		path_i = 0
		var nd := Iso.dir_of(target.center_loc() - center_loc())
		if nd >= 0:
			dir = nd
		if attack_cooldown <= 0:
			attacking = true
			action = att["action"]
			anim_frame = 0
		return false
	repath_timer -= 1
	if repath_timer <= 0 or path_i >= path.size():
		repath_timer = 15 + obj_id % 7
		var dest: Vector2i
		if target is Unit:
			dest = (target as Unit).cell()
		else:
			dest = Game.inst.world.adjacent_to_rect(target.footprint(), cell())
		# keep the current path while it still leads near the target: a path search
		# per attacker every few frames dominated big battles
		var moved := float((dest - goal).length_squared())
		var far := float((dest - cell()).length_squared())
		if path_i >= path.size() or moved > 4.0 + far * 0.04:
			_path_to(dest)
			if path.is_empty() and dist > float(att["range"]):
				stop()
				return false
	_step_move()
	return true


func _attack_anim() -> void:
	var n := Assets.action_len(sprite_code, action, dir)
	if n <= 0:
		n = 6
	anim_frame += 1
	if anim_frame >= n:
		attacking = false
		anim_frame = 0
		action = "S"
		if not _target_gone():
			_deliver_hit()


func roll_damage(att: Dictionary) -> float:
	var rng := Game.inst.rng
	var dmg := float(att["damage"]) + rng.randi_range(0, 2)
	dmg += float(att["pierce"]) * rng.randi_range(0, int(minf(combat, Defs.MAX_COMBAT_TRAIN))) / 100.0
	var n := nation()
	if n and is_human():
		dmg += 2.0 * n.tech_level("INFRANGE" if att["range"] > 1 else "INFCLOSE")
	if is_weapon and n:
		dmg *= 1.0 + 0.25 * maxi(0, n.tech_level(sprite_code) - 1)
	if is_weapon and not (target is Unit):
		dmg *= 2.0
	return dmg


func _deliver_hit() -> void:
	var att := current_attack()
	if att.is_empty():
		return
	var dmg := roll_damage(att)
	if visible:
		Game.inst.play_sound("S", sprite_code, att["action"], center_loc())
	if att["range"] > 1 and att["bullet"] != "" and Assets.has_sprite(att["bullet"]):
		Game.inst.spawn_bullet(self, target, att["bullet"], att["bullet_speed"], dmg)
	else:
		target.take_damage(dmg, self)
	gain_experience()
	attack_cooldown = int(att["delay"]) * 2


func gain_experience() -> void:
	if is_human() and combat < Defs.MAX_COMBAT_TRAIN:
		combat = minf(Defs.MAX_COMBAT_TRAIN, combat + 0.06)


func _do_enter() -> bool:
	if is_spy and order_firm == null and spy_place != null:
		return _do_infiltrate()
	if order_firm == null or not is_instance_valid(order_firm) or order_firm.dead:
		stop()
		return false
	if distance_to(order_firm) <= 1.0:
		var ok := false
		if order == Order.BUILD:
			ok = order_firm.set_builder(self)
		else:
			ok = order_firm.accept_unit(self)
		if not ok:
			stop()
		return false
	if path_i >= path.size():
		repath_timer -= 1
		if repath_timer <= 0:
			repath_timer = 20
			_path_to(Game.inst.world.adjacent_to_rect(order_firm.footprint(), cell()))
			if path.is_empty():
				stop()
		return false
	_step_move()
	return true


func _do_infiltrate() -> bool:
	if not is_instance_valid(spy_place) or spy_place.dead:
		spy_place = null
		stop()
		return false
	if distance_to(spy_place) <= 1.0:
		Game.inst.spy_enter(self, spy_place)
		return false
	if path_i >= path.size():
		_path_to(Game.inst.world.adjacent_to_rect(spy_place.footprint(), cell()))
		if path.is_empty():
			stop()
			return false
	_step_move()
	return true


func _do_return() -> bool:
	if home_town == null or not is_instance_valid(home_town) or home_town.dead:
		home_town = null
		stop()
		return false
	if distance_to(home_town) <= 1.0:
		home_town.defender_returned(self)
		return false
	if path_i >= path.size():
		_path_to(Game.inst.world.adjacent_to_rect(home_town.footprint(), cell()))
		if path.is_empty():
			home_town.defender_returned(self)
			return false
	_step_move()
	return true


func take_damage(amount: float, attacker: GameObj) -> void:
	if invulnerable_until > Game.inst.frame:
		return
	super(amount, attacker)


# ---------------------------------------------------------- god powers ---

func god_info() -> Dictionary:
	return Defs.god_for_unit(sprite_code) if is_god else {}


func can_cast_power() -> bool:
	var gi := god_info()
	var n := nation()
	return not gi.is_empty() and gi["can_cast"] and Defs.GOD_POWERS.has(gi["race"]) and n != null and n.prayer_points >= gi["power_pray"]


## UnitGod::cast_power: the race's power around the Greater Being.
func cast_power() -> bool:
	if not can_cast_power():
		return false
	var gi := god_info()
	var g := Game.inst
	var n := nation()
	n.prayer_points -= gi["power_pray"]
	var c := center_loc()
	var r: float = gi["cast_range"]
	var effect: String = Defs.RACE_PREFIX.get(gi["race"], "NO") + "_EFF1"
	if Assets.has_sprite(effect):
		g.spawn_sprite_effect(effect, c, nation_color())
	match gi["race"]:
		"ROMAN":
			for u in g.units:
				if u.nation_id == nation_id and u.is_human() and u.rank != Defs.Rank.SOLDIER and u.center_loc().distance_to(c) <= r:
					u.leadership = minf(100.0, u.leadership + 30.0)
		"GREEK":
			for u in g.units:
				if u.nation_id == nation_id and not u.dead and u.center_loc().distance_to(c) <= r:
					u.invulnerable_until = g.frame + Defs.FRAMES_PER_DAY * 30
		"JAPANESE":
			for u in g.units:
				if not u.dead and g.is_hostile(self, u) and u.center_loc().distance_to(c) <= r:
					u.frozen_until = g.frame + Defs.FRAMES_PER_DAY * 10
					u.stop()
		"MONGOL":
			for u in g.units.duplicate():
				if u.dead or u.inside_firm or u.rank == Defs.Rank.KING or u.nation_id == nation_id or u.nation_id == 0 or u.is_god:
					continue
				if u.center_loc().distance_to(c) <= r and g.rng.randf() < 0.5:
					g.defect_unit(u, nation_id)
		"CARTH":
			g.earthquake(nation_id, c, 16.0)   # cast_quake radius 32 world steps
		"PERSIAN":
			g.reveal_area(nation_id, Vector2i(c), int(r * 4))
		"INDIAN":
			g.spawn_tornado(self, c + Vector2.from_angle(dir * PI / 4.0 - PI / 2.0) * 2.0)
	g.play_sound("S", sprite_code, "A1", c)
	return true


func on_attacked(attacker: GameObj) -> void:
	if attacker == null or not is_instance_valid(attacker) or attacker.dead:
		return
	if (order == Order.IDLE or order == Order.RETURN) and can_attack() and not attacking:
		order_attack(attacker)
	elif order == Order.ATTACK and can_attack() and attacker is Unit and not (target is Unit) and Game.inst.is_hostile(self, attacker):
		# Defend ourselves first, then go back to the building or town we were attacking.
		var building := target
		order_attack(attacker)
		resume_target = building
	Game.inst.call_for_help(self, attacker)


func die(killer: GameObj) -> void:
	if dead:
		return
	dead = true
	order = Order.DYING
	attacking = false
	action = "D"
	anim_frame = 0
	death_frames = 0
	selected = false
	if visible:
		Game.inst.play_sound("S", sprite_code, "DIE", center_loc())
	Game.inst.on_unit_died(self, killer)


func _dying() -> void:
	death_frames += 1
	var n := Assets.action_len(sprite_code, "D", 0)
	if death_frames % 2 == 0 and anim_frame < n - 1:
		anim_frame += 1
	if death_frames > maxi(n * 2, 1) + 60:
		Game.inst.remove_unit(self)
		return
	queue_redraw()


# --------------------------------------------------------------------- draw ---

func _draw() -> void:
	render(self)


func render(cv) -> void:
	if inside_firm:
		return
	var col := nation_color()
	if selected and not dead:
		_draw_selection(cv, col)
	var act := action
	var d := Iso.dir_map[dir]
	if dead:
		act = "D"
		if not Assets.has_action(sprite_code, "D"):
			act = "S"
		d = 0 if act == "D" else Iso.dir_map[dir]
	var fr := Assets.sprite_frame(sprite_code, act, d, anim_frame, col)
	if fr.is_empty() and act != "S":
		fr = Assets.sprite_frame(sprite_code, "S", Iso.dir_map[dir], 0, col)
	if not fr.is_empty():
		var tex: Texture2D = fr[0]
		var mod := Color(1, 1, 1, clampf(1.0 - (death_frames - 40) / 20.0, 0.0, 1.0)) if dead else Color.WHITE
		if frozen_until > Game.inst.frame:
			mod = Color(0.6, 0.8, 1.3)
		elif invulnerable_until > Game.inst.frame:
			mod = Color(1.25, 1.2, 0.8)
		cv.draw_texture(tex, fr[1], mod)
	else:
		cv.draw_circle(Vector2(0, 16), 8, col)
	if dead:
		return
	if rank >= Defs.Rank.GENERAL:
		var top := Vector2(0, -48)
		cv.draw_line(top, top + Vector2(0, -14), Color(0.3, 0.2, 0.1), 2.0)
		var flag := PackedVector2Array([top + Vector2(0, -14), top + Vector2(12, -10), top + Vector2(0, -6)])
		cv.draw_colored_polygon(flag, col)
		if rank == Defs.Rank.KING:
			cv.draw_circle(top + Vector2(0, -16), 3, Color(1, 0.85, 0.2))
	if selected or hp < max_hp:
		draw_hp_bar_on(cv, Vector2(0, -44), 28)


func _draw_selection(cv, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		pts.append(Vector2(cos(a) * 18, 16 + sin(a) * 9))
	pts.append(pts[0])
	cv.draw_polyline(pts, col.lightened(0.3), 1.5)
