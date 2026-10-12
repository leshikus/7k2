class_name Town
extends GameObj
## A village of a single race. Loyalty, resistance, growth, taxes and
## surrender follow otown.cpp / otownpop.cpp of the 7k2 source.

var town_name := ""
var race := "NORMAN"
var x1 := 0
var y1 := 0
var population := 20
var employed := 0
var loyalty := 50.0
var target_loyalty := 50.0
var resistance := {}            # nation id -> resistance (independent towns)
var target_resistance := {}     # nation id -> target, -1 if no influence
var quality_of_life := 30
var bonus_loyalty := 0.0
var population_growth := 0.0
var tax_penalty := 0
var recruit_penalty := 0
var auto_tax_loyalty := 0       # collect tax whenever loyalty reaches this (0 = off)
var auto_grant_loyalty := 0     # grant gold whenever loyalty falls below this (0 = off)
var grant_penalty := 0
var linked_firms: Array[Firm] = []
var defenders: Array[Unit] = []
var aggressors := {}            # nation id -> last frame it attacked this town
var layout: Dictionary = {}
var _damage_acc := 0.0
var wall_level := 0             # 0 fence, 1 basic wall, 2 advanced wall
var target_wall_level := 0
var wall_progress := 0.0        # towards MAX_WALL_PROGRESS
var wall_hp := 0.0
var archer_energy := 0          # jobless villagers able to shoot this day
var _shoot_timer := 0

const MAX_WALL_PROGRESS := 1000.0
const WALL_COST := [0, 500, 1000]
const WALL_BUILDERS := 5
var last_rebel_day := -1000


func setup(name_: String, race_: String, nation: int, at: Vector2i, pop: int) -> void:
	town_name = name_
	race = race_
	nation_id = nation
	x1 = at.x
	y1 = at.y
	population = pop
	max_hp = 100.0
	hp = 100.0
	_pick_layout()
	position = Iso.to_screen(center_loc())


## Bigger towns use layouts with more houses (TOWNLAY.BUILDCOUNT 1..3).
func _pick_layout() -> void:
	var want := 1 if population < 30 else (2 if population < 60 else 3)
	for l in Assets.town_layouts:
		if l.get("buildings", 0) == want:
			if layout != l:
				layout = l
				if Game.inst and Game.inst.ground_layer:
					Game.inst._ground_dirty = true
			return
	if layout.is_empty() and not Assets.town_layouts.is_empty():
		layout = Assets.town_layouts[0]


func footprint() -> Rect2i:
	return Rect2i(x1, y1, Defs.TOWN_SIZE, Defs.TOWN_SIZE)


func display_name() -> String:
	return town_name


func jobless() -> int:
	return maxi(0, population - employed)


func has_linked_camp(nid: int) -> bool:
	for f in linked_firms:
		if f.is_military() and f.code != "LAIR" and f.nation_id == nid and f.overseer != null and not f.under_construction:
			return true
	return false


func resistance_to(nid: int) -> float:
	return resistance.get(nid, 70.0)


# -------------------------------------------------------------- influence ---

## Town::camp_influence: leadership, race of the general and reputation.
func camp_influence(f: Firm) -> int:
	if f.overseer == null:
		return 0
	var n := f.nation()
	if f.is_fryhtan_lair():
		# Fryhtans rule by fear: no race bonus or penalty, reputation does not help
		return clampi(int(minf(100.0, f.overseer.lead_skill()) * 0.6) + 15, 0, 100)
	var inf := int(minf(100.0, f.overseer.lead_skill()) / 2.0)
	if f.overseer.race == race:
		inf += inf / 3
	else:
		inf -= 20
	if n:
		inf += int(n.reputation / 2.0)
	if f.overseer.rank == Defs.Rank.KING:
		inf += 20
	if f.code == "FORT":
		inf += 15
	return clampi(inf, 0, 100)


func update_target_loyalty() -> void:
	var n := nation()
	if n == null:
		return
	var t := 10.0 + bonus_loyalty + n.reputation / 2.0 + quality_of_life / 4.0
	if population > 0:
		t += 30.0 - 30.0 * jobless() / population
	if race == n.race:
		t += 20.0
	if n.food < 0:
		t -= 20.0
	if n.cash < 0:
		t -= 10.0      # unpaid debts make the people restless
	t = clampf(t, 0, 100)
	for f in linked_firms:
		if not f.is_military() or f.code == "LAIR" or f.overseer == null or f.under_construction:
			continue
		var fnat := f.nation()
		if fnat == null:
			continue
		var inf := int(f.overseer.lead_skill() / 3.0)
		if f.overseer.rank == Defs.Rank.KING:
			inf += 20
		if f.overseer.race == race:
			inf += 8
		if fnat.race == race:
			inf += 8
		if f.nation_id == nation_id:
			t += inf
		elif f.overseer.race == race:
			if wall_level > 0:
				inf -= int(20 * wall_level * wall_hp / maxf(1.0, wall_max_hp()))
			t -= maxi(0, inf)
	target_loyalty = clampf(t, 0, 100)


func wall_max_hp() -> float:
	return wall_level * 100.0


## Town::process_wall: jobless villagers raise the wall, then repair it.
func _process_wall() -> void:
	if Game.inst.frame - last_attacked_frame < Defs.FRAMES_PER_DAY * 4:
		return
	if nation_id > 0 and Game.inst.blessed(nation_id, "GREEK"):
		target_wall_level = 2
		if wall_level > 0 and wall_hp < wall_max_hp():
			wall_hp = minf(wall_max_hp(), wall_hp + 1.0)
		elif wall_level < target_wall_level:
			wall_progress += 20.0
	var n := nation()
	var man := mini(WALL_BUILDERS, jobless())
	if wall_level > 0 and wall_hp < wall_max_hp():
		if man > 0 and (n == null or n.cash > 0):
			wall_hp = minf(wall_max_hp(), wall_hp + man)
			if n:
				n.add_cash(-float(WALL_COST[wall_level]) * man / wall_max_hp())
	elif wall_level < target_wall_level and man > 0 and (n == null or n.cash > 0):
		wall_progress += man * 10.0
		if n:
			n.add_cash(-float(WALL_COST[wall_level + 1]) * man * 10.0 / MAX_WALL_PROGRESS)
		if wall_progress >= MAX_WALL_PROGRESS:
			wall_progress = 0.0
			wall_level += 1
			wall_hp = wall_max_hp()
			if nation_id == Game.inst.player_id:
				Game.inst.notify("%s has completed its %s." % [town_name, "wall" if wall_level == 1 else "fortified wall"], center_loc())
			queue_redraw()


func build_wall() -> void:
	if target_wall_level < 2:
		target_wall_level = wall_level + 1


## Town::process_attack_target: villagers shoot at hostile units near the town.
func town_shoot() -> void:
	_shoot_timer -= 1
	if _shoot_timer > 0 or archer_energy <= 0 or population <= 0:
		return
	_shoot_timer = 6 + (obj_id % 5)
	var g := Game.inst
	var c := center_loc()
	var best: Unit = null
	var best_d := 6.0 + 3.0
	for u in g.units_near(c, best_d + 4.0):
		if u.dead or u.inside_firm or not g.is_hostile(self, u):
			continue
		if nation_id == 0 and u.nation_id > 0 and resistance_to(u.nation_id) < 1.0:
			continue
		var d := distance_to(u)
		if d < best_d:
			best_d = d
			best = u
	if best == null:
		return
	var dmg: float
	if nation_id > 0:
		dmg = loyalty * 8.0 / 100.0 + 6.0
	elif best.nation_id > 0 and best.nation_id != GameObj.MONSTER_NATION:
		dmg = resistance_to(best.nation_id) * 8.0 / 100.0 + 6.0
	else:
		dmg = 14.0
	var arrow := Defs.unit_sprite(race, "ARROW")
	if not Assets.has_sprite(arrow):
		arrow = "NO_ARROW"
	g.spawn_town_arrow(self, best, arrow, dmg)
	archer_energy >>= 2


func update_target_resistance() -> void:
	target_resistance.clear()
	for f in linked_firms:
		if not f.is_military() or f.overseer == null or f.nation_id <= 0 or f.under_construction:
			continue
		if f.code == "LAIR" and not f.is_fryhtan_lair():
			continue
		# a wall shields the villagers from outside influence (Town::update_target_resistance)
		var inf_adj := 100
		if wall_level > 0 and wall_hp > 0.0:
			inf_adj -= int(wall_hp / 10.0)
		var v := maxi(0, 100 - camp_influence(f) * inf_adj / 100)
		if Game.inst.blessed(f.nation_id, "MONGOL"):
			v = maxi(0, v - 20)
		if not target_resistance.has(f.nation_id) or v < target_resistance[f.nation_id]:
			target_resistance[f.nation_id] = v


func update_loyalty() -> void:
	if loyalty < target_loyalty:
		var own := has_linked_camp(nation_id)
		var enemy := false
		for f in linked_firms:
			if f.is_military() and f.nation_id != nation_id and f.nation_id > 0 and f.overseer:
				enemy = true
		if not own and enemy:
			return
		loyalty = minf(100.0, loyalty + maxf(0.5, (target_loyalty - loyalty) / 30.0))
	elif loyalty > target_loyalty:
		loyalty = maxf(0.0, loyalty - maxf(0.5, (loyalty - target_loyalty) / 30.0))


func update_resistance() -> void:
	for nid in target_resistance:
		var tr := float(target_resistance[nid])
		var cur := resistance_to(nid)
		if cur > tr:
			cur = maxf(tr, cur - maxf(1.0, (cur - tr) / 30.0))
			resistance[nid] = cur
	think_surrender()


## Independent towns surrender to the kingdom whose camp has worn their
## resistance down; nation towns defect when disloyal and only enemy camps link.
func think_surrender() -> bool:
	var best := 0
	if nation_id > 0:
		if has_linked_camp(nation_id) or loyalty >= Defs.SURRENDER_LOYALTY:
			return false
		var best_inf := int(loyalty)
		for f in linked_firms:
			if f.is_military() and f.code != "LAIR" and f.nation_id > 0 and f.nation_id != nation_id and f.overseer:
				var inf := camp_influence(f)
				if inf > best_inf:
					best_inf = inf
					best = f.nation_id
	else:
		if tribute_to() > 0:
			return false        # enslaved: cannot join a human kingdom while the lair stands
		var best_res := float(Defs.SURRENDER_RESISTANCE)
		for nid in resistance:
			if resistance[nid] < best_res and has_linked_camp(nid):
				best_res = resistance[nid]
				best = nid
	if best > 0:
		surrender(best)
		return true
	return false


func surrender(to_nation: int) -> void:
	var old := nation_id
	nation_id = to_nation
	var n := nation()
	loyalty = 40.0 if n and n.race == race else 30.0
	bonus_loyalty = 20.0
	resistance.clear()
	aggressors.clear()
	for d in defenders.duplicate():
		if is_instance_valid(d) and not d.dead:
			d.nation_id = to_nation
			d.home_town = self
	Game.inst.on_town_changed(self, old)
	queue_redraw()


func think_rebel(day: int) -> void:
	if nation_id <= 0 or loyalty > Defs.REBEL_LOYALTY or day < last_rebel_day + 90:
		return
	if Game.inst.frame - last_attacked_frame < 300:
		return
	if Game.inst.rng.randf() > 0.3:
		return
	last_rebel_day = day
	var old := nation_id
	nation_id = 0
	for nid in Game.inst.nation_ids():
		resistance[nid] = 60.0 if nid == old else 50.0
	Game.inst.on_town_changed(self, old)
	Game.inst.notify_nation(old, "%s has rebelled and declared independence!" % town_name, center_loc())
	queue_redraw()


# ------------------------------------------------------------------- daily ---

func next_day(day: int) -> void:
	if dead:
		return
	if population <= 0:
		_check_empty()
		if dead:
			return
	var n := nation()
	_update_quality_of_life()
	if day % 30 == obj_id % 30:
		_grow()
	if day % 15 == obj_id % 15:
		if n:
			update_target_loyalty()
		else:
			update_target_resistance()
	if day % 5 == obj_id % 5:
		if n:
			update_loyalty()
		else:
			update_resistance()
	if n and day % 15 == obj_id % 15:
		think_rebel(day)
		if nation_id > 0:
			think_surrender()
	if nation_id == 0 and day % 30 == obj_id % 30:
		_pay_tribute()
	_process_wall()
	archer_energy = jobless()
	n = nation()
	if n:
		var farm := 1.0 + 0.25 * n.tech_level("FARMING")
		if Game.inst.blessed(nation_id, "CARTH"):
			farm += 0.05 * Game.inst.prayer_count(nation_id)
		n.food += jobless() * farm * Defs.PEASANT_FOOD_YEAR_PRODUCTION / 365.0
		n.food -= population * float(Defs.UNIT_FOOD_YEAR_CONSUMPTION) / 365.0
		if day % 365 == 0 and day > 0:
			n.add_cash(population * float(Defs.TAX_PER_UNIT))
	_auto_tax_and_grant()
	tax_penalty = maxi(0, tax_penalty - 1)
	recruit_penalty = maxi(0, recruit_penalty - 1)
	grant_penalty = maxi(0, grant_penalty - 1)
	if bonus_loyalty > 0 and day % 10 == obj_id % 10:
		bonus_loyalty -= 1
	for nid in aggressors.keys():
		if Game.inst.frame - aggressors[nid] > 1200:
			aggressors.erase(nid)


func _update_quality_of_life() -> void:
	var kinds := {}
	for f in linked_firms:
		if f.code == "MARKET" and not f.under_construction:
			for g in f.goods_types_available():
				kinds[g] = true
	quality_of_life = mini(100, 25 + 25 * kinds.size())


## The Fryhtan kingdom this independent town pays tribute to (Town::pay_tribute_to_monster), or 0.
func tribute_to() -> int:
	if nation_id != 0:
		return 0
	for f in linked_firms:
		if f.is_fryhtan_lair() and f.overseer and resistance_to(f.nation_id) < Defs.SURRENDER_RESISTANCE:
			return f.nation_id
	return 0


func _pay_tribute() -> void:
	var lairs := linked_firms.filter(func(f): return f.is_fryhtan_lair() and f.overseer and resistance_to(f.nation_id) < Defs.SURRENDER_RESISTANCE)
	for f in lairs:
		var skill := minf(100.0, f.overseer.lead_skill())
		var amount := population * 5.0 / lairs.size() * (100.0 + skill) / 200.0
		var n: Nation = f.nation()
		if n:
			n.add_cash(amount)
			n.live_points += population * 0.5 / lairs.size()


func _grow() -> void:
	if population >= Defs.MAX_TOWN_POPULATION:
		return
	var inc := 0.0
	if nation_id > 0:
		inc = population * (100.0 + quality_of_life / 2.0) / 100.0
	else:
		inc = population / 2.0
	if tribute_to() > 0:
		inc /= 2.0          # paying tribute halves growth
	if Game.inst.blessed(nation_id, "EGYPTIAN"):
		inc += inc * Game.inst.prayer_count(nation_id) / (Defs.MAX_WORKER * 3.0)
	population_growth += inc / 2.0
	while population_growth > 100.0 and population < Defs.MAX_TOWN_POPULATION:
		population_growth -= 100.0
		population += 1
	queue_redraw()


# ---------------------------------------------------------------- actions ---

func can_recruit() -> bool:
	return nation_id > 0 and jobless() > 0 and loyalty >= Defs.MIN_RECRUIT_LOYALTY


## Whether a building may draw a villager from this town for training. The
## computer keeps at least AI_MIN_POP people so its towns are not emptied.
const AI_MIN_POP := 20
func can_spare_trainee() -> bool:
	if not can_recruit():
		return false
	var n := nation()
	return n == null or not n.is_ai or population > AI_MIN_POP


## Town::recruit — a villager joins the army as an infantry soldier.
## FirmCamp's recruit: a villager joins a linked fort or camp straight away,
## without the loyalty cost of recruiting him from the town itself.
func draft_into(f: Firm) -> Unit:
	if not can_recruit() or f.soldiers.size() >= f.capacity():
		return null
	var u := Game.inst.spawn_unit(Defs.unit_sprite(race, "INF"), nation_id, Vector2i(x1, y1), Defs.CITIZEN_COMBAT_LEVEL)
	if u == null:
		return null
	u.leadership = float(Game.inst.rng.randi_range(10, 40))
	if not f.accept_unit(u):
		Game.inst.remove_unit(u)
		return null
	population -= 1
	_check_empty()
	queue_redraw()
	return u


func recruit() -> Unit:
	if not can_recruit():
		return null
	var c := Game.inst.world.adjacent_to_rect(footprint(), Vector2i(x1 + 3, y1 + Defs.TOWN_SIZE))
	# Town::mobilize_town_people: a villager leaves as a civilian, not a soldier
	var u := Game.inst.spawn_unit(Defs.unit_sprite(race, "CIV"), nation_id, c, Defs.CITIZEN_COMBAT_LEVEL)
	if u == null:
		return null
	population -= 1
	loyalty = maxf(0.0, loyalty - minf(10.0, 2.0 + recruit_penalty / 5.0))
	recruit_penalty += 5
	_check_empty()
	queue_redraw()
	return u


func collect_tax() -> float:
	if nation_id <= 0 or not has_linked_camp(nation_id):
		return 0.0
	var dec := minf(20.0, Defs.COLLECT_TAX_LOYALTY_DECREASE + tax_penalty / 5.0)
	if Game.inst.blessed(nation_id, "NORMAN"):
		dec = maxf(1.0, dec - 3.0)
	tax_penalty += 10
	var before := loyalty
	loyalty = maxf(0.0, loyalty - dec)
	var tax := (before - loyalty) * population * Defs.TAX_PER_UNIT / dec
	nation().add_cash(tax)
	return tax


func grant_cost() -> float:
	return float(population * Defs.GRANT_COST_PER_UNIT)


## Grant money: raises loyalty of own towns, lowers resistance of independent ones.
const AUTO_TAX_LEVELS := [0, 60, 70, 80, 90, 100]
const AUTO_GRANT_LEVELS := [0, 30, 40, 50, 60, 70]


## Town::auto_collect_tax / auto_grant: the right-click settings of the town's buttons.
func _auto_tax_and_grant() -> void:
	if nation_id <= 0:
		return
	if auto_tax_loyalty > 0 and loyalty >= auto_tax_loyalty and has_linked_camp(nation_id):
		collect_tax()
	if auto_grant_loyalty > 0 and loyalty < auto_grant_loyalty:
		grant(nation_id)


static func next_level(levels: Array, cur: int) -> int:
	var i := levels.find(cur)
	return levels[(i + 1) % levels.size()]


func grant(from_nation: int) -> bool:
	var n := Game.inst.nation(from_nation)
	if n == null or not n.can_afford(grant_cost()):
		return false
	var amount := maxf(3.0, Defs.GRANT_RESISTANCE_DECREASE - grant_penalty / 5.0)
	grant_penalty += 10
	n.add_cash(-grant_cost())
	if nation_id == from_nation:
		loyalty = minf(100.0, loyalty + amount)
	elif nation_id == 0:
		resistance[from_nation] = maxf(0.0, resistance_to(from_nation) - amount)
		think_surrender()
	return true


# ----------------------------------------------------------------- combat ---

func on_attacked(attacker: GameObj) -> void:
	if attacker == null or not is_instance_valid(attacker) or attacker.dead:
		return
	if attacker.nation_id > 0 and attacker.nation_id != GameObj.MONSTER_NATION:
		aggressors[attacker.nation_id] = Game.inst.frame
	_spawn_defenders(attacker)
	Game.inst.on_object_attacked(self, attacker)


## Villagers take up arms when the town is attacked.
func _spawn_defenders(attacker: GameObj) -> void:
	defenders = defenders.filter(func(d): return is_instance_valid(d) and not d.dead)
	var want := mini(8, population / 8 + 1)
	while defenders.size() < want and population > 1:
		var c := Game.inst.world.adjacent_to_rect(footprint(), Vector2i(attacker.center_loc()))
		var u := Game.inst.spawn_unit(Defs.unit_sprite(race, "CIV"), nation_id, c, 15.0)
		if u == null:
			break
		u.home_town = self
		population -= 1
		defenders.append(u)
		u.order_attack(attacker)


func defender_returned(u: Unit) -> void:
	defenders.erase(u)
	if u.nation_id == nation_id:
		population = mini(Defs.MAX_TOWN_POPULATION, population + 1)
	Game.inst.remove_unit(u)
	queue_redraw()


## A village broken by a Fryhtan kingdom submits and pays tribute: the
## attackers call off the assault instead of wiping it out.
func _check_submission(nid: int) -> void:
	var n := Game.inst.nation(nid)
	if n == null or not n.is_fryhtan or resistance_to(nid) >= Defs.SURRENDER_RESISTANCE:
		return
	aggressors.erase(nid)
	for u in Game.inst.units:
		if u.nation_id == nid and u.target == self:
			u.stop()
	for d in defenders.duplicate():
		if is_instance_valid(d) and not d.dead and d.target and d.target.nation_id == nid:
			d.stop()
			d.order = Unit.Order.RETURN


func defender_killed(u: Unit, killer: GameObj) -> void:
	defenders.erase(u)
	if killer and killer.nation_id > 0 and killer.nation_id != GameObj.MONSTER_NATION:
		if nation_id == 0:
			# Fryhtan slaughter breaks a village's will far faster than human soldiers do
			var kn := killer.nation()
			var drop := 8.0 if kn and kn.is_fryhtan else 3.0
			resistance[killer.nation_id] = maxf(0.0, resistance_to(killer.nation_id) - drop)
		elif nation_id != killer.nation_id:
			loyalty = maxf(0.0, loyalty - 2.0)
		think_surrender()
		if nation_id == 0:
			_check_submission(killer.nation_id)


## Hits on the town itself kill villagers once no defenders are left.
func take_damage(amount: float, attacker: GameObj) -> void:
	if dead:
		return
	last_attacked_frame = Game.inst.frame
	on_attacked(attacker)
	if wall_level > 0 and wall_hp > 0.0:
		wall_hp -= amount
		if wall_hp <= 0.0:
			wall_hp = 0.0
			wall_level = 0
			target_wall_level = mini(target_wall_level, 1)
			if nation_id == Game.inst.player_id:
				Game.inst.notify("The wall of %s has fallen!" % town_name, center_loc())
		queue_redraw()
		return
	_damage_acc += amount
	while _damage_acc >= 25.0 and population > 0:
		_damage_acc -= 25.0
		population -= 1
		if attacker and is_instance_valid(attacker):
			var an := attacker.nation()
			if an and an.is_fryhtan:
				an.live_points += 15.0
		if attacker and attacker.nation_id > 0 and nation_id == 0 and attacker.nation_id != GameObj.MONSTER_NATION:
			var an2 := attacker.nation()
			resistance[attacker.nation_id] = maxf(0.0, resistance_to(attacker.nation_id) - (3.0 if an2 and an2.is_fryhtan else 1.0))
	if nation_id == 0 and attacker and attacker.nation_id > 0:
		think_surrender()
		_check_submission(attacker.nation_id)
	_check_empty()
	queue_redraw()


func _check_empty() -> void:
	# defenders that died in battle never come back
	defenders = defenders.filter(func(d): return is_instance_valid(d) and not d.dead and d.home_town == self)
	if population <= 0 and defenders.is_empty() and not dead:
		dead = true
		Game.inst.on_town_destroyed(self)


# ------------------------------------------------------------------- draw ---

func _draw() -> void:
	render(self)


func render(cv) -> void:
	var base := Iso.to_screen(Vector2(x1, y1)) - position
	var col := nation_color()
	if selected:
		var p := PackedVector2Array([
			base, Iso.to_screen(Vector2(x1 + 6, y1)) - position,
			Iso.to_screen(Vector2(x1 + 6, y1 + 6)) - position, Iso.to_screen(Vector2(x1, y1 + 6)) - position, base])
		cv.draw_polyline(p, col.lightened(0.3), 2.0)
		for f in linked_firms:
			cv.draw_line(Vector2.ZERO, Iso.to_screen(f.center_loc()) - position, f.nation_color().lightened(0.3), 1.5)
	var slots: Array = layout.get("slots", [])
	_pick_layout()
	var wall_origin := Iso.to_screen(Vector2(x1, y1)) - position
	var wb := Assets.town_wall(race, wall_level, wall_hp if wall_level > 0 else 1.0, wall_max_hp() if wall_level > 0 else 1.0, "B")
	if not wb.is_empty():
		cv.draw_texture(wb[0], wall_origin + wb[1])
	_draw_planned_wall(cv, wall_origin, "B")
	for s in slots:
		# Slot positions are world pixels from the town's top-left location (Town::draw).
		var slot_loc := Vector2(x1 + s["x"] / 32.0, y1 + s["y"] / 32.0)
		var at := Iso.to_screen(slot_loc) - position
		match s["type"]:
			"HOUSE":
				var hb := Assets.town_house(race, s["code"])
				if not hb.is_empty():
					# TownBuild::draw: the slot is the building's centre; anchor half its size back
					var anchor := Iso.to_screen(slot_loc - hb[2] * 0.5) - position
					cv.draw_texture(hb[0], anchor + hb[1])
			"PLANT":
				if not Assets.town_plants.is_empty():
					var tex: Texture2D = Assets.town_plants[(obj_id + int(s["x"])) % Assets.town_plants.size()]
					# PlantBitmap::draw_at: centred, base 15px below the slot point
					cv.draw_texture(tex, at + Vector2(-tex.get_width() / 2, -tex.get_height() + 15))
			"FLAG":
				# Animated race flag in the owner's colour (Town::draw_flag); none for independents.
				if nation_id > 0:
					var flag := Assets.spict("FLAG%02d0%d" % [_race_id(), (Game.inst.frame / 3 + obj_id) % 10], col)
					if flag:
						cv.draw_texture(flag, at + Vector2(-9, -97))
	var wf := Assets.town_wall(race, wall_level, wall_hp if wall_level > 0 else 1.0, wall_max_hp() if wall_level > 0 else 1.0, "F")
	if not wf.is_empty():
		cv.draw_texture(wf[0], wall_origin + wf[1])
	_draw_planned_wall(cv, wall_origin, "F")
	if selected and wall_level > 0:
		draw_hp_bar_on(cv, Vector2(0, -56), 60)
	var font := ThemeDB.fallback_font
	var label := "%s (%d)" % [town_name, population]
	var size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, 13)
	var lp := Vector2(-size.x / 2.0, -70)
	cv.draw_rect(Rect2(lp + Vector2(-4, -12), Vector2(size.x + 8, 16)), Color(0, 0, 0, 0.55))
	cv.draw_string(font, lp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col.lightened(0.4))


func _race_id() -> int:
	for i in Defs.races.size():
		if Defs.races[i]["code"] == race:
			return i + 1
	return 1


func draw_ground(ci) -> void:
	var tex := Assets.picture("I_TPICT1.RES", layout.get("ground", "TOWNGD1"))
	if tex:
		# TOWN_ADJ_OFFSET_X/Y in otowndrw.cpp: x of the bottom-left corner, y of the top corner
		ci.draw_texture(tex, Iso.to_screen(Vector2(x1, y1)) + Vector2(Defs.TOWN_SIZE * -32 - 25, -7))


## A wall under construction is shown as a see-through outline of the wall being built.
func _draw_planned_wall(cv, origin: Vector2, part: String) -> void:
	if target_wall_level <= wall_level:
		return
	var w := Assets.town_wall(race, target_wall_level, 1.0, 1.0, part)
	if not w.is_empty():
		cv.draw_texture(w[0], origin + w[1], Color(1, 1, 1, 0.35 + 0.4 * wall_progress / MAX_WALL_PROGRESS))
