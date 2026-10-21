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
var received_hits := 0.0         # Town::received_hit_count
var last_attack_nation := 0      # Town::last_attack_nation_recno (independent towns)
var town_combat_level := 0       # Town::town_combat_level: its defenders' skill
var repair_wall := false         # Town::repair_flag
var join_min_rating := -1        # Town::independent_unit_join_nation_min_rating (-1: not drawn yet)
var base_resistance := 70.0     # what kingdoms it has not met yet start from (Town::init_resistance)
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
var wall_busy := 0               # peasants at work on the wall today (Town::process_wall's man power)
var last_rebel_day := -1000
var under_construction := false  # built by a unit or wagon (Town::process_construction)
var build_progress := 0.0
var builder_pop := 0             # the people who move in when it is done
var builder_loyalty := 50.0
var is_base_town := false           # Town::is_base_town (the computer's)
var no_neighbor_space := false      # Town::no_neighbor_space
var setup_day := 0                  # Town::setup_date


func setup(name_: String, race_: String, nation: int, at: Vector2i, pop: int) -> void:
	# Town::init_resistance: an independent town's defenders by the Resistance setting
	if nation == 0 and Game.inst:
		town_combat_level = {GameSetup.LOW: 10, GameSetup.MODERATE: 30, GameSetup.HIGH: 50}.get(
			int(Game.inst.config.get("resistance", GameSetup.LOW)), 10)
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


## Town::linked_town_array: the towns within the town-to-town distance.
func linked_towns() -> Array:
	var out: Array = []
	var d := Defs.effective_distance("", "")
	for t in Game.inst.towns:
		if t != self and not t.dead and maxf(absf(t.center_loc().x - center_loc().x), absf(t.center_loc().y - center_loc().y)) <= d:
			out.append(t)
	return out


## Town::move_pop: a villager moves to another of the kingdom's towns of the same race.
func migrate_to(dest: Town) -> bool:
	if dest == self or dest.nation_id != nation_id or dest.race != race or jobless() <= 0 \
			or dest.population >= Defs.MAX_TOWN_POPULATION or dest.under_construction:
		return false
	population -= 1
	dest.population += 1
	_check_empty()
	queue_redraw()
	dest.queue_redraw()
	return true


func jobless() -> int:
	return maxi(0, population - employed)


func has_linked_camp(nid: int) -> bool:
	for f in linked_firms:
		if f.is_military() and f.code != "LAIR" and f.nation_id == nid and f.overseer != null and not f.under_construction:
			return true
	return false


func resistance_to(nid: int) -> float:
	return resistance.get(nid, base_resistance)


func set_wall_level(level: int) -> void:
	wall_level = level
	target_wall_level = level
	wall_hp = wall_max_hp()


# -------------------------------------------------------------- influence ---

## Town::camp_influence: half the commander's leadership (at most 100), a third
## more for his own race or 20 less for another, plus half the kingdom's
## reputation; only human commanders have influence; a fort adds 15.
func camp_influence(f: Firm) -> int:
	if f.overseer == null or not f.overseer.is_human():
		return 0
	var inf := commander_influence(f.overseer, f.nation())
	if f.code == "FORT":
		inf += 15
	return inf


func commander_influence(u: Unit, n: Nation) -> int:
	var inf := int(minf(100.0, u.lead_skill())) / 2
	if u.race == race:
		inf += inf / 3
	else:
		inf -= 20
	if n:
		inf += int(n.reputation / 2.0)
	return clampi(inf, 0, 100)


## FirmCamp / FirmFort::loyalty_adjustment and resistance_adjustment: a fort
## has its full influence on towns, a camp (or lair) 80%.
static func influence_adjustment(f: Firm) -> int:
	return 100 if f.code == "FORT" else 80


## Town::update_target_loyalty: 10, the bonus, half the reputation, a quarter
## of the quality of life, up to 30 for employment and 20 for the ruler's race;
## then the influence of linked camps with a commander: our own raise it,
## another kingdom's (only while we have none of our own linked) lower it for
## the people of their commander's race, less a sound wall's protection.
func update_target_loyalty() -> void:
	var parts := target_loyalty_parts()
	if not parts.is_empty():
		target_loyalty = float(parts[-1][1])


## The terms of Town::update_target_loyalty, as [label, points] pairs; the
## last pair is the resulting target.
func target_loyalty_parts() -> Array:
	var n := nation()
	if n == null:
		return []
	var parts := [["base", 10]]
	if int(bonus_loyalty) != 0:
		parts.append(["recent change of kingdom", int(bonus_loyalty)])
	parts.append(["reputation / 2", int(n.reputation) / 2])
	parts.append(["quality of life / 4", quality_of_life / 4])
	var t := 10 + int(bonus_loyalty) + int(n.reputation) / 2 + quality_of_life / 4
	if population > 0:
		parts.append(["employment", 30 - 30 * jobless() / population])
		t += 30 - 30 * jobless() / population
	if race == n.race:
		parts.append(["the ruler's race", 20])
		t += 20
	t = clampi(t, 0, 100)
	var own_camp := has_linked_camp(nation_id)
	for f in linked_firms:
		if not (Espionage.is_camp(f) or f.code == "LAIR") or f.overseer == null or f.nation_id <= 0 or f.under_construction:
			continue
		if f.nation_id != nation_id and own_camp:
			continue          # the town shuts out a foreign camp while it has its own
		var fnat := f.nation()
		var o := f.overseer
		var inf := int(o.lead_skill()) / 3
		if o.rank == Defs.Rank.KING:
			inf += 20
		if o.race == race:
			inf += 8
		if fnat and fnat.race == race:
			inf += 8
		var who := "%s %s (%s)" % [Defs.firm_types.get(f.code, {}).get("name", f.code), o.display_name(), "leadership %d" % int(o.lead_skill())]
		if f.nation_id == nation_id:
			t += inf * influence_adjustment(f) / 100
			parts.append([who, inf * influence_adjustment(f) / 100])
		elif o.race == race:
			if wall_level > 0:
				inf -= int(20 * wall_level * wall_hp / maxf(1.0, wall_max_hp()))
			t -= inf * influence_adjustment(f) / 100
			parts.append(["enemy " + who, -(inf * influence_adjustment(f) / 100)])
	parts.append(["target", clampi(t, 0, 100)])
	return parts


func wall_max_hp() -> float:
	return wall_level * 100.0


## Town::process_wall: one villager (target_wall_man_power) raises the next
## wall level, 10 of 1000 a day at the wall's cost, or repairs a damaged wall a
## point a day when repairs are ordered; a Greek Greater Being raises (20 a
## day) and repairs walls for free. A fallen wall is gone. Returns the
## villagers at work, who do not farm that day.
const WALL_MAN_POWER := 1
const REPAIR_POINTS_PER_DAY := 1.0


func _process_wall() -> void:
	wall_busy = 0
	if Game.inst.frame - last_attacked_frame <= Defs.FRAMES_PER_DAY * 4:
		return
	var g := Game.inst
	var gods := nation_id > 0 and g.god_worshipped(nation_id, "GREEK")
	if gods and target_wall_level < 2:
		target_wall_level = 2
	var man := mini(WALL_MAN_POWER, jobless())
	var n := nation()
	if wall_level > 0 and wall_hp <= 0.0:
		wall_level = 0
		wall_hp = 0.0
		target_wall_level = mini(target_wall_level, 1)
	elif wall_hp < wall_max_hp():
		if gods:
			wall_hp += REPAIR_POINTS_PER_DAY
		if wall_hp < wall_max_hp() and repair_wall and man > 0 and (n == null or n.cash > 0):
			wall_hp += man * REPAIR_POINTS_PER_DAY
			if n:
				n.add_cash(-float(WALL_COST[wall_level]) * man * REPAIR_POINTS_PER_DAY / wall_max_hp(), "Walls")
			wall_busy = man
		if wall_hp >= wall_max_hp():
			wall_hp = wall_max_hp()
			repair_wall = false
	elif wall_level < target_wall_level:
		var p := 0.0
		if gods:
			p += 80.0 if g.fast_build and nation_id == g.player_id else 20.0
			if man == 1:
				man = 0
		if man > 0 and (n == null or n.cash > 0):
			p += man * (40.0 if g.fast_build and nation_id == g.player_id else 10.0)
			if n:
				n.add_cash(-float(WALL_COST[wall_level + 1]) * man * 10.0 / MAX_WALL_PROGRESS, "Walls")
			wall_busy = man
		wall_progress += p
		if wall_progress >= MAX_WALL_PROGRESS:
			wall_progress -= MAX_WALL_PROGRESS
			wall_level += 1
			wall_hp += 100.0
			if nation_id == g.player_id:
				g.notify("%s has completed its %s." % [town_name, "wall" if wall_level == 1 else "fortified wall"], center_loc())
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
	# Town::bullet_id: the villagers throw stones and bricks, by turns
	var missile := "ROCK" if (g.frame + obj_id) & 1 else "BRICK"
	g.spawn_town_arrow(self, best, missile, dmg, 15.0)       # TOWN_BULLET_SPEED
	archer_energy >>= 2


## Town::update_target_resistance: each kingdom's camps with a commander set
## what the resistance falls to, the strongest counting; a wall shields the
## villagers, a camp has 80% of a fort's influence, and a Mongol Greater Being
## takes 20 more off.
func update_target_resistance() -> void:
	target_resistance.clear()
	for f in linked_firms:
		if not (Espionage.is_camp(f) or f.code == "LAIR") or f.overseer == null or f.nation_id <= 0 or f.under_construction:
			continue
		if not Game.inst.link_on(f, self) and f.code != "LAIR" and not Espionage.is_camp(f):
			continue
		var inf_adj := 100
		if wall_level > 0 and wall_hp > 0.0:
			inf_adj -= int(wall_hp / 10.0)
		inf_adj = inf_adj * influence_adjustment(f) / 100
		var v := 100 - camp_influence(f) * inf_adj / 100
		if Game.inst.god_worshipped(f.nation_id, "MONGOL"):
			v -= 20
		v = maxi(v, 0)
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
		var inc := maxf(0.5, (target_loyalty - loyalty) / 30.0)
		# an Egyptian Greater Being's worshippers slow the rise of Egyptian loyalty
		if race == "EGYPTIAN" and Game.inst.god_worshipped(nation_id, "EGYPTIAN"):
			var pc := Game.inst.god_worshippers(nation_id, "EGYPTIAN")
			inc = inc * (Defs.MAX_WORKER * 2) / (Defs.MAX_WORKER * 2 + pc)
		loyalty = minf(100.0, loyalty + inc)
	elif loyalty > target_loyalty:
		loyalty = maxf(0.0, loyalty - maxf(0.5, (loyalty - target_loyalty) / 30.0))


func update_resistance() -> void:
	for nid in target_resistance:
		var tr := float(target_resistance[nid])
		var cur := resistance_to(nid)
		if cur > tr:
			# the decrease is slower with the Resistance setting (66% moderate, 33% high)
			var dec := (cur - tr) / 30.0
			match int(Game.inst.config.get("resistance", GameSetup.LOW)):
				GameSetup.MODERATE: dec = dec * 2.0 / 3.0
				GameSetup.HIGH: dec = dec / 3.0
			cur = maxf(tr, cur - maxf(1.0, dec))
			resistance[nid] = cur
	think_surrender()


## Town::think_surrender: an independent town gives itself to the kingdom whose
## camp has the most influence among those it resists least than 30; a
## kingdom's town with no camp of its own, a foreign camp linked and loyalty
## below SURRENDER_LOYALTY, to a foreign commander whose influence beats its
## loyalty. Only to humans; never while paying a Fryhtan tribute.
func think_surrender() -> bool:
	if tribute_to() > 0:
		return false
	if nation_id > 0:
		if has_linked_camp(nation_id) or not linked_firms.any(func(f): return Espionage.is_camp(f) and f.nation_id > 0 and f.nation_id != nation_id and f.overseer):
			return false
		if loyalty >= Defs.SURRENDER_LOYALTY:
			return false
	var best := 0
	var best_r := int(loyalty) if nation_id > 0 else 0
	for f in linked_firms:
		if not Espionage.is_camp(f) or f.nation_id == nation_id or f.nation_id <= 0 or f.overseer == null or f.is_fryhtan_lair():
			continue
		var fn := f.nation()
		if fn == null or fn.is_fryhtan:
			continue
		if nation_id == 0 and resistance_to(f.nation_id) >= Defs.SURRENDER_RESISTANCE:
			continue
		var r := camp_influence(f)
		if r > best_r:
			best_r = r
			best = f.nation_id
	if best > 0:
		surrender(best)
		return true
	return false


## Town::surrender / set_nation: loyalty 60 for the ruler's race, 50 for
## another (80 for a town set up by rebels), no bonus, no defenders out; the
## links to the new owner's buildings are switched on at both ends.
func surrender(to_nation: int) -> void:
	var old := nation_id
	nation_id = to_nation
	var n := nation()
	if to_nation == 0:
		loyalty = 80.0
	else:
		loyalty = 60.0 if n and n.race == race else 50.0
	bonus_loyalty = 0.0
	town_combat_level = 0
	join_min_rating = 100 + Game.inst.rng.randi() % 150
	resistance.clear()
	aggressors.clear()
	for d in defenders.duplicate():
		if is_instance_valid(d) and not d.dead:
			d.nation_id = to_nation
			d.home_town = self
	for f in linked_firms:
		if f.nation_id == to_nation and to_nation > 0:
			Game.inst.set_link(f, self, true, true)
	Game.inst.on_town_changed(self, old)
	queue_redraw()


func think_rebel(day: int) -> void:
	if nation_id <= 0 or loyalty > Defs.REBEL_LOYALTY or day < last_rebel_day + 90:
		return
	# no rebellion within 30 days of an attack or while villagers are out defending
	if Game.inst.frame - last_attacked_frame < Defs.FRAMES_PER_DAY * 30:
		return
	if defenders.any(func(d): return is_instance_valid(d) and not d.dead):
		return
	if Rebels.town_rebels(Game.inst, self) > 0:
		last_rebel_day = day
		queue_redraw()


# ------------------------------------------------------------------- daily ---

func next_day(day: int) -> void:
	if dead or under_construction:
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
		# Town::process_food: the peasants not building walls farm; the player
		# reaps 25/30 as much unless he started with a large treasure
		var per_year := float(Defs.PEASANT_FOOD_YEAR_PRODUCTION)
		if not n.is_ai and int(Game.inst.config.get("treasure", GameSetup.MODERATE)) <= GameSetup.MODERATE and Game.inst.config.get("setup", false):
			per_year = per_year * 25.0 / 30.0
		n.food += maxi(0, jobless() - wall_busy) * farm * per_year / 365.0
		n.food -= population * float(Defs.UNIT_FOOD_YEAR_CONSUMPTION) / 365.0
		if day % 365 == 0 and day > 0:
			n.add_cash(population * float(Defs.TAX_PER_UNIT), "Taxes")
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


## Town::is_pay_tribute_to_monster: an independent town pays a Fryhtan
## kingdom whose lair is linked to it once its resistance to that kingdom has
## fallen below 1 (MONSTER_COLLECT_TOWN_TRIBUTE_LOYALTY).
const MONSTER_COLLECT_TOWN_TRIBUTE_LOYALTY := 1.0
const MONSTER_TOWN_TRIBUTE_PER_UNIT := 5.0


func tribute_to() -> int:
	if nation_id != 0:
		return 0
	for f in linked_firms:
		if f.code == "LAIR" and f.nation_id > 0 and f.nation_id != GameObj.MONSTER_NATION and not f.under_construction \
				and resistance_to(f.nation_id) < MONSTER_COLLECT_TOWN_TRIBUTE_LOYALTY:
			return f.nation_id
	return 0


## Town::pay_tribute_to_monster (monthly): 5 a villager, shared among the
## lairs it pays, by their commanders' leadership.
func _pay_tribute() -> void:
	var lairs := linked_firms.filter(func(f): return f.code == "LAIR" and f.nation_id > 0 and f.nation_id != GameObj.MONSTER_NATION \
		and not f.under_construction and resistance_to(f.nation_id) < MONSTER_COLLECT_TOWN_TRIBUTE_LOYALTY)
	for f in lairs:
		if f.overseer == null:
			continue
		var skill := minf(100.0, f.overseer.lead_skill())
		var amount := population * MONSTER_TOWN_TRIBUTE_PER_UNIT / lairs.size() * (100.0 + skill) / 200.0
		var n: Nation = f.nation()
		if n:
			n.add_cash(amount, "Tribute")


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
	if nation_id > 0 and race == "EGYPTIAN":
		inc += inc * Game.inst.god_worshippers(nation_id, "EGYPTIAN") / (Defs.MAX_WORKER * 3.0)
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
	u.loyalty = loyalty          # a recruit brings the town's loyalty with him
	u.basic_days = int(u.utype.get("build_days", 10))     # he arrives for basic training
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
	var c := Game.inst.exit_cell(footprint(), Vector2i(x1 + 3, y1 + Defs.TOWN_SIZE))
	# Town::mobilize_town_people: a villager leaves as a civilian, not a soldier
	var u := Game.inst.spawn_unit(Defs.unit_sprite(race, "CIV"), nation_id, c, Defs.CITIZEN_COMBAT_LEVEL)
	if u == null:
		return null
	u.loyalty = loyalty
	population -= 1
	loyalty = maxf(0.0, loyalty - minf(10.0, 2.0 + recruit_penalty / 5.0))
	recruit_penalty += 5
	_check_empty()
	queue_redraw()
	return u


## Town::recruit(wagon): up to ten villagers leave together in a wagon to
## settle elsewhere - the jobless first, then workers (recruitable_pop counts
## the whole town); a single one leaves on foot.
func wagon_count() -> int:
	if nation_id <= 0 or under_construction:
		return 0
	return mini(population, Defs.MAX_WAGON_POPULATION)


func recruit_wagon() -> Unit:
	var count := wagon_count()
	if count <= 0:
		return null
	if count == 1:
		return _mobilize_one()
	var c := Game.inst.exit_cell(footprint(), Vector2i(x1 + 3, y1 + Defs.TOWN_SIZE))
	var w := Game.inst.spawn_unit("WAGON", nation_id, c, 100.0)
	if w == null:
		return null
	w.wagon_pop = count
	w.wagon_race = race
	w.loyalty = loyalty
	_recruit_dec_loyalty()
	population -= count
	while employed > population and employed > 0:
		Game.inst._unjob(self)
		employed -= 1
	_check_empty()
	queue_redraw()
	return w


## Town::recruit_dec_loyalty
func _recruit_dec_loyalty() -> void:
	var dec := minf(5.0, float(Defs.MAX_TOWN_POPULATION) / population) if population > 0 else 0.0
	dec = minf(dec + recruit_penalty / 5.0, 10.0)
	recruit_penalty += 5
	loyalty = maxf(0.0, loyalty - dec)


## Town::mobilize_town_people for a wagon of one: the villager walks.
func _mobilize_one() -> Unit:
	var c := Game.inst.exit_cell(footprint(), Vector2i(x1 + 3, y1 + Defs.TOWN_SIZE))
	var u := Game.inst.spawn_unit(Defs.unit_sprite(race, "CIV"), nation_id, c, Defs.CITIZEN_COMBAT_LEVEL)
	if u == null:
		return null
	u.loyalty = loyalty
	_recruit_dec_loyalty()
	population -= 1
	if employed > population:
		Game.inst._unjob(self)
		employed = mini(employed, population)
	_check_empty()
	queue_redraw()
	return u


## Town::process_construction: a percent every other frame (eleven under fast
## build), held up while the site is under attack.
func process_construction() -> void:
	if not under_construction or Game.inst.frame % 2 != 0:
		return
	if Game.inst.frame - last_attacked_frame < Defs.FRAMES_PER_DAY:
		return
	build_progress += 11.0 if Game.inst.fast_build and nation_id == Game.inst.player_id else 1.0
	if build_progress >= 100.0:
		under_construction = false
		population = builder_pop
		loyalty = builder_loyalty
		builder_pop = 0
		Game.inst.update_links()
		if nation_id == Game.inst.player_id:
			Game.inst.notify("The town of %s has been built." % town_name, center_loc())
		queue_redraw()


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
	nation().add_cash(tax, "Taxes")
	return tax


## The player's "Collect tax" (reports the sum to the town's ruler).
func collect_tax_cmd() -> void:
	var tax := collect_tax()
	if nation_id == Game.inst.player_id:
		Game.inst.notify("Collected %d gold from %s." % [int(tax), town_name], center_loc())


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
	n.add_cash(-grant_cost(), "Grants")
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
	Game.inst.on_object_attacked(self, attacker)


## Town::mobilize_defender: while the walls are down, villagers come out
## against an attacker near by - not the last one, and not once loyalty (or
## resistance to the attacker) is below 30 or below five per defender out.
## Each takes away twice the loyalty over the population, given back if he
## comes home; he fights at the town's combat level, give or take 10.
const MIN_DEFEND_LOYALTY := 30.0
const EFFECTIVE_DEFEND_DISTANCE := 10.0


func mobilize_defender(attacker: GameObj) -> Unit:
	if population <= 1:
		return null
	var anid := attacker.nation_id if attacker else 0
	var cur := loyalty
	if nation_id == 0:
		if anid <= 0:
			return null
		cur = resistance_to(anid)
	defenders = defenders.filter(func(d): return is_instance_valid(d) and not d.dead)
	if cur < defenders.size() * 5 or cur < MIN_DEFEND_LOYALTY or jobless() <= 0:
		return null
	var dec := 2.0 * cur / population
	if nation_id > 0:
		loyalty = maxf(0.0, loyalty - dec)
	else:
		resistance[anid] = maxf(0.0, cur - dec)
		last_attack_nation = anid
	var c := Game.inst.exit_cell(footprint(), Vector2i(attacker.center_loc()))
	var lvl := clampi(town_combat_level + Game.inst.rng.randi() % 20 - 10, 10, 100)
	var u := Game.inst.spawn_unit(Defs.unit_sprite(race, "CIV"), nation_id, c, float(lvl))
	if u == null:
		return null
	u.home_town = self
	u.set_meta("defend_loyalty", dec)
	population -= 1
	defenders.append(u)
	u.order_attack(attacker)
	return u


## Town::assign_unit: a defender coming home gives back the loyalty he took
## (with resistance, 2 more for the victory - not toward a kingdom the town
## already pays tribute to); a wagon brings all its settlers.
func defender_returned(u: Unit) -> void:
	defenders.erase(u)
	if u.nation_id == nation_id:
		if u.has_meta("defend_loyalty"):
			var back := float(u.get_meta("defend_loyalty"))
			if nation_id > 0:
				loyalty = minf(100.0, loyalty + back)
			elif last_attack_nation > 0 and tribute_to() != last_attack_nation:
				resistance[last_attack_nation] = minf(100.0, resistance_to(last_attack_nation) + back + 2.0)
		population = mini(Defs.MAX_TOWN_POPULATION, population + u.settlers())
	Game.inst.remove_unit(u)
	queue_redraw()


func defender_killed(u: Unit, _killer: GameObj) -> void:
	defenders.erase(u)


## Hits on the town itself kill villagers once no defenders are left.
func defense() -> Array:
	return [80, 100]      # Town::init: defense_attribute.init(80, 100)


## Town::being_attack_hit: a wall takes a fifth of the blow; with the wall
## down the villagers defend an attacker close by, and every 200 points of
## blows kill one (three times as many while defenders are out); with no
## defenders out, loyalty (or resistance to the attacker) wears away, faster
## in a small town; at zero the attackers call it off, and a Fryhtan kingdom
## may win a villager over now and then. An empty town is razed after 800.
const RECEIVED_HIT_PER_KILL := 200.0


func take_damage(amount: float, attacker: GameObj) -> void:
	if dead:
		return
	var g := Game.inst
	var anid := 0
	if attacker and is_instance_valid(attacker):
		if attacker.nation_id == nation_id:
			return
		anid = attacker.nation_id if attacker.nation_id != GameObj.MONSTER_NATION else 0
	last_attacked_frame = g.frame
	on_attacked(attacker)
	defenders = defenders.filter(func(d): return is_instance_valid(d) and not d.dead)
	if attacker and is_instance_valid(attacker) and wall_hp <= 0.0 and attacker.center_loc().distance_to(center_loc()) <= EFFECTIVE_DEFEND_DISTANCE:
		while mobilize_defender(attacker) != null:
			pass
	if wall_level > 0 and wall_hp > 0.0:
		wall_hp = maxf(0.0, wall_hp - amount / Defs.ATTACK_SLOW_DOWN / 5.0)
		if wall_hp <= 0.0:
			received_hits = 0.0
			if nation_id == g.player_id:
				g.notify("The wall of %s has fallen!" % town_name, center_loc())
		queue_redraw()
		return
	if population > 0:
		received_hits += amount if defenders.is_empty() else amount / 3.0
		if received_hits >= RECEIVED_HIT_PER_KILL:
			received_hits = 0.0
			kill_town_people(anid)
			if dead:
				return
		if defenders.is_empty() and population > 0:
			var zero := false
			if nation_id > 0:
				var before := loyalty
				var dec := minf((5.0 if has_linked_camp(nation_id) else 10.0) / population, 1.0)
				loyalty = maxf(0.0, loyalty - dec * amount / (20.0 / Defs.ATTACK_SLOW_DOWN))
				if loyalty < 1.0 and think_surrender():
					return
				if loyalty < 1.0 and before >= 1.0:
					_stop_attacks(0)
				zero = loyalty == 0.0
			elif anid > 0:
				var before2 := resistance_to(anid)
				var dec2 := minf(10.0 / population, 1.0)
				resistance[anid] = maxf(0.0, before2 - dec2 * amount / (20.0 / Defs.ATTACK_SLOW_DOWN))
				if resistance_to(anid) < 1.0:
					think_surrender()
					if before2 >= 1.0:
						_stop_attacks(anid)
				zero = resistance_to(anid) == 0.0
			var an := g.nation(anid)
			if zero and an and an.is_fryhtan and g.rng.randi() % 50 == 0 and jobless() > 0:
				var u := recruit()
				if u:
					g.defect_unit(u, anid)
	else:
		received_hits += amount if defenders.is_empty() else amount / 8.0
		if received_hits >= 4.0 * RECEIVED_HIT_PER_KILL:
			population = 0
			defenders.clear()
			_check_empty()
			return
	_check_empty()
	queue_redraw()


## UnitArray::stop_attack_obj: the attackers (of a kingdom, or all) stop.
func _stop_attacks(nid: int) -> void:
	for u in Game.inst.units:
		if u.target == self and (nid == 0 or u.nation_id == nid):
			u.stop()


## Town::kill_town_people: the owner's people and the killer's lose heart
## (NationBase::civilian_killed); a Fryhtan killer gains life points.
func kill_town_people(attacker_nid: int) -> void:
	if population <= 0:
		return
	var g := Game.inst
	if attacker_nid > 0:
		var an := g.nation(attacker_nid)
		if an:
			an.change_all_people_loyalty(-2.0, race)
			an.change_reputation(-1.0)
			if an.is_fryhtan:
				an.live_points += Defs.CITIZEN_COMBAT_LEVEL * 2.0 * 2.0
	population -= 1
	_check_empty()


func _check_empty() -> void:
	# defenders that died in battle never come back
	defenders = defenders.filter(func(d): return is_instance_valid(d) and not d.dead and d.home_town == self)
	if population <= 0 and defenders.is_empty() and not dead and not under_construction:
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
	# Inside Information (ZoomMatrix::draw_objects_now: disp_extend_info): the
	# town's race, loyalty or resistance, and its peasants and workers
	var ext := int(GameOptions.get_opt("inside_info"))
	if ext == 2 or (ext == 1 and Game.inst.hovered == self):
		var lines: Array = ["%s %s" % [Defs.race_adj(race), "Slave Town" if tribute_to() > 0 else "Town"]]
		if population > 0:
			if nation_id > 0:
				lines.append("Loyalty: %d -> %d" % [int(loyalty), int(target_loyalty)])
			elif Game.inst.player_id > 0:
				var pid := Game.inst.player_id
				var tr := "" if not target_resistance.has(pid) or target_resistance[pid] < 0 or target_resistance[pid] > resistance_to(pid) else " -> %d" % int(target_resistance[pid])
				lines.append("Resistance: %d%s" % [int(resistance_to(pid)), tr])
		if nation_id == Game.inst.player_id or nation_id == 0:
			lines.append("Peasants: %d  Workers: %d" % [jobless(), employed])
		var y := -70.0 - 16.0 * lines.size()
		for ln in lines:
			var sz := font.get_string_size(ln, HORIZONTAL_ALIGNMENT_CENTER, -1, 12)
			cv.draw_rect(Rect2(Vector2(-sz.x / 2.0 - 3, y - 11), Vector2(sz.x + 6, 14)), Color(0, 0, 0, 0.5))
			cv.draw_string(font, Vector2(-sz.x / 2.0, y), ln, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 0.85))
			y += 16.0


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
