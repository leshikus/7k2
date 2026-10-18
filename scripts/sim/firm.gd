class_name Firm
extends GameObj
## A building. One class covers every firm type; behaviour switches on `code`.
## Rules follow the 7k2 source: of_camp.cpp, of_mine.cpp, of_fact.cpp,
## of_mark.cpp, of_rese.cpp, of_war.cpp, of_inn.cpp, of_base.cpp, of_lair.cpp.

const WORK_FIRMS := ["MINE", "FACTORY", "RESEARCH", "WAR", "BASE"]
const MILITARY_FIRMS := ["CAMP", "FORT"]
## Structures that shoot at enemies on their own (FirmLishorr /
## FirmOffensive2::process_monster_firm): [damage, range, delay]. A Lishorr's
## damage follows SpecialFirms.lishorr_damage.
const TOWER_FIRMS := {
	"LISHORR": [12.0, 8.0, 20], "WLISHORR": [12.0, 8.0, 20], "OFF_BLD3": [60.0, 9.0, 40],
}
const FORTRESS_TICK := 5
const STOCK_CAP := 500.0

var code := ""
var ftype: Dictionary = {}
var build: Dictionary = {}
var race := ""
var x1 := 0
var y1 := 0
var w := 3
var h := 3

var under_construction := false
var progress := 0.0                 # construction progress 0..100
var builder: Unit = null

var overseer: Unit = null
var soldiers: Array[Unit] = []
var worker_towns: Array = []        # FirmWork::worker_array: each worker's home town
var needed_workers := 10            # FirmWork::needed_worker_count (INIT_NEEDED_WORKER_COUNT; 20 at towers and Seats)
var linked_towns: Array[Town] = []
var linked_firms: Array[Firm] = []

# production
var site: Site = null
var raw := ""                       # mine raw type / factory product type
var reserve := 0.0
var stock := 0.0
var raw_stock := 0.0
var goods := {}                     # market: product type -> stock
var market_sales := 0.0             # market: income this year
var raws := {}                      # market: raw material -> stock (its raw slots)
var demand := {}                    # market: product -> the towns' monthly demand (MarketGoods::month_demand)
var month_supply := {}              # market: product -> supplied this month
var last_month_supply := {}
var month_sales := {}               # market: product -> sold this month
var last_month_sales := {}
var month_output := 0.0             # mine/factory: produced this month
var last_month_output := 0.0
var backup := {}                    # factory: raw -> [raw stock, goods stock] of products not being made
var auto_switch := false            # factory: FirmFactory::auto_switch_flag
var next_output: Firm = null        # mine/factory/market: next_output_firm
var _out_idx := -1
## A Tower of Science works on its kingdom's research (NationBase::research_tech_id):
## every tower adds to the same technology, whose progress is kept per tech.
var research_tech: String:
	get:
		var n := nation()
		return n.research_tech if n and code == "RESEARCH" else ""
	set(v):
		var n := nation()
		if n and code == "RESEARCH":
			n.start_research(v)
## Percent done of the kingdom's current research.
var research_points: float:
	get:
		var n := nation()
		return n.research_progress_of(n.research_tech) if n and code == "RESEARCH" else 0.0
	set(v):
		var n := nation()
		if n and code == "RESEARCH" and n.research_tech != "":
			n.research_progress[n.research_tech] = v
var weapon := ""
var weapon_progress := 0.0
var weapon_queue := 0
var heroes: Array = []              # inn: heroes for hire
var trainees: Array = []            # training ground, espionage college: Training records (FirmTrain::trainee_array)
var monster_code := ""              # lair: monster unit sprite
var raid_timer := 0
var build_row := 0                  # FBUILD record when the variant was given explicitly (scenarios)
var _tower_timer := 0
var cast_charge := Defs.MAX_CAST_DELAY   # spell building: FirmMagic::cast_delay
var shown_until := 0                # camouflaged Lishorr/Fortress: seen until this frame after firing
var extra_units: Array[Unit] = []   # Fortress: the Grokkens it was made of
var animals: Array = []             # Keraal: beasts for hire
var alchemy_mode := ""              # Alchemist Tor: conversion in use (a tech code)
var propagate := 1                  # Wilde Lishorr: seedlings it may still spread
var revealed_to := {}              # nation id -> true: a Persian god showed it what goes on inside (reveal_info)
var archers := 0                    # fort: FirmFort::current_archer_count
var target_archers := 0             # FirmFort::target_archer_count
var archer_progress := 0            # FirmFort::train_archer_progress (days)
var _archer_fired: Array = []       # FirmFort::last_archer_fire_frame
var repair := false                 # Firm::repair_flag: repairs ordered
var rally := Vector2i(-1, -1)       # where the units it makes go (Firm::rally_dest)

var anim_index := 0
var anim_timer := 0
var _defend_timer := 0


func setup(firm_code: String, nation: int, build_race: String, at: Vector2i) -> void:
	needed_workers = Defs.MAX_WORKER if firm_code in ["RESEARCH", "BASE"] else 10
	code = firm_code
	nation_id = nation
	race = build_race
	ftype = Defs.firm_types.get(code, {})
	build = Assets.firm_build_by_row(build_row) if build_row > 0 else {}
	if build.is_empty() or build.get("firm", "") != code:
		build = Assets.firm_build(code, race)
		build_row = 0
	w = build.get("loc_w", 3)
	h = build.get("loc_h", 3)
	x1 = at.x
	y1 = at.y
	max_hp = float(ftype.get("hp", 400))
	hp = max_hp
	raid_timer = 200 + Game.inst.rng.randi_range(0, 300)
	position = Iso.to_screen(center_loc())


func footprint() -> Rect2i:
	return Rect2i(x1, y1, w, h)


func display_name() -> String:
	if code == "STABLE":
		var bn: String = build.get("name", "")
		var printable := bn != "" and bn.to_ascii_buffer().size() == bn.length() and not bn.contains("?")
		return bn if printable else ftype.get("name", "Training Center")
	if code == "LAIR":
		return build["name"] if build.get("name", "") != "" else _monster_name() + " Lair"
	return ftype.get("name", code)


func _monster_name() -> String:
	return Defs.unit_types.get(monster_code, {}).get("name", "Fryhtan")


## A camouflaged building other kingdoms cannot see (SpecialFirms.hidden_from).
func hidden_from(nid: int) -> bool:
	return SpecialFirms.hidden_from(self, nid)


func is_military() -> bool:
	return code in MILITARY_FIRMS or code == "LAIR"


func is_work_firm() -> bool:
	return code in WORK_FIRMS


func capacity() -> int:
	match code:
		"FORT", "CAMP", "LAIR":
			return Defs.MAX_SOLDIER        # FirmCamp::is_soldier_full: all camps hold MAX_SOLDIER
		"FORTRESS":
			return SpecialFirms.FORTRESS_ARCHERS
	return 0


func workers() -> int:
	return worker_towns.size()


## FirmWork::recruit_worker (every 5 days): one worker from the linked town with
## the most (and the largest share of) jobless people, over an enabled link.
func recruit_worker() -> void:
	if workers() >= needed_workers:
		return
	var g := Game.inst
	var best: Town = null
	var best_r := 0
	for t in linked_towns:
		if t.dead or not g.work_link_on(self, t):
			continue
		var jl := t.jobless()
		if jl <= 0:
			continue
		var r := 100 * jl / maxi(1, t.population) + jl * 2
		if r > best_r:
			best_r = r
			best = t
	if best:
		worker_towns.append(best)
		best.employed += 1


const WORKER_YEAR_SALARY := 5.0
const RESISTANCE_DECREASE_PER_WORKER := 0.2


## FirmWork::next_day and pay_expense: hire every 5 days; every 15 days each
## worker from an independent town wears down its resistance; wages daily.
func _work_day(day: int) -> void:
	if day % 5 == obj_id % 5:
		recruit_worker()
	if day % 15 == obj_id % 15 and nation_id > 0:
		for t in worker_towns:
			if is_instance_valid(t) and t.nation_id == 0:
				t.resistance[nation_id] = maxf(0.0, t.resistance_to(nation_id) - RESISTANCE_DECREASE_PER_WORKER)
	var n := nation()
	if n and workers() > 0:
		n.add_cash(-WORKER_YEAR_SALARY * workers() / 365.0, "Workers")


## FirmWork::resign_worker / set_needed_worker_count
func resign_worker(i: int) -> void:
	if i < 0 or i >= worker_towns.size():
		return
	var t: Town = worker_towns[i]
	worker_towns.remove_at(i)
	if is_instance_valid(t):
		t.employed = maxi(0, t.employed - 1)


func resign_all_workers() -> void:
	for i in range(worker_towns.size() - 1, -1, -1):
		resign_worker(i)


func set_needed_workers(v: int) -> void:
	needed_workers = clampi(v, 0, Defs.MAX_WORKER)
	while workers() > needed_workers:
		resign_worker(workers() - 1)


func productivity() -> float:
	return 100.0 * workers() / Defs.MAX_WORKER


func armor() -> float:
	return 0.0


func defense() -> Array:
	return build.get("def", [100, 0])


# --------------------------------------------------------------- garrison ---

## A unit arrives at the building (Unit::ENTER order).
func accept_unit(u: Unit) -> bool:
	if under_construction or u.nation_id != nation_id or dead:
		return false
	if code == "FORTRESS":
		# FirmMonsterFortress::can_accept_assign: Fryhtans of the kingdom man its walls
		if not SpecialFirms.is_fryhtan_unit(u) or soldiers.size() >= capacity():
			return false
		soldiers.append(u)
		_hide_unit(u)
		return true
	if not is_military():
		return false
	if code != "LAIR" and (not u.is_human() or u.is_civilian()):
		return false      # FirmCamp::assign_unit: only military units
	if code == "LAIR" and u.home_firm == self:
		u.home_firm = null      # a raider coming home always fits; it counted toward the brood
		soldiers.append(u)
		_hide_unit(u)
		return true
	var leads := u.can_lead() if code != "LAIR" else (u.rank >= Defs.Rank.GENERAL and nation_id != GameObj.MONSTER_NATION)
	if leads:
		# FirmCamp::assign_overseer: a general or king always takes command;
		# the commander he replaces comes out
		var old := overseer
		overseer = u
		_hide_unit(u)
		if old:
			release_unit(old)
		return true
	elif soldiers.size() < capacity():
		soldiers.append(u)
	else:
		return false
	_hide_unit(u)
	return true


## FirmCamp::promote_soldier: with no commander, a trained soldier of at least
## a villager's skill is made a general and takes command.
func make_overseer(u: Unit) -> void:
	if overseer or not u in soldiers or u.basic_days > 0 or u.combat < Defs.CITIZEN_COMBAT_LEVEL:
		return
	if code != "LAIR" and not u.is_human():
		return
	soldiers.erase(u)
	u.rank = Defs.Rank.GENERAL
	overseer = u
	Game.inst.update_links()


func _hide_unit(u: Unit) -> void:
	u.stop()
	u.inside_firm = self
	u.home_firm = null
	u.selected = false
	u.visible = false
	Game.inst.deselect(u)


## Units come and go through the right-down face of the footprint (the side drawn
## nearest the viewer on the right, where the buildings have their doors).
func door() -> Vector2i:
	return Vector2i(x1 + w, y1 + h / 2)


func release_unit(u: Unit, attack_target: GameObj = null) -> void:
	if u == overseer:
		overseer = null
	soldiers.erase(u)
	u.inside_firm = null
	if u.sleeper_for > 0 and u.sleeper_for != nation_id:
		Game.inst.sleeper_wakes(u, self)
	var c := Game.inst.world.adjacent_to_rect(footprint(), door())
	if c.x < 0:
		c = Vector2i(x1 + w, y1 + h - 1)
	u.loc = Vector2(c)
	u.position = Iso.to_screen(u.loc)
	u.visible = true
	u.stop()
	if attack_target:
		u.home_firm = self
		u.order_attack(attack_target)


## Firm::process_repair: when ordered, a point a day at the building's cost
## (and life points for a Fryhtan one), not while under attack.
func _process_repair() -> void:
	if not repair or hp >= max_hp or Game.inst.frame - last_attacked_frame <= Defs.FRAMES_PER_DAY:
		return
	var n := nation()
	if n:
		var cost := float(ftype.get("cost", 0)) * 1.0 / maxf(1.0, max_hp)
		var live := float(ftype.get("live_cost", 0)) * 1.0 / maxf(1.0, max_hp)
		if n.cash < cost or n.live_points < live:
			return
		n.add_cash(-cost, "Construction")
		n.live_points -= live
	hp += 1.0
	if hp >= max_hp:
		hp = max_hp
		repair = false


func set_repair(on: bool) -> void:
	repair = on


## The building changes hands (Firm::change_nation): its men serve the new
## kingdom; work in progress is lost.
func change_nation(to_nation: int) -> void:
	var old := nation_id
	nation_id = to_nation
	for i in range(worker_towns.size() - 1, -1, -1):
		var wt: Town = worker_towns[i]
		if not is_instance_valid(wt) or (wt.nation_id != 0 and wt.nation_id != to_nation):
			resign_worker(i)
	for u in Espionage.occupants(self):
		u.nation_id = to_nation
		if u.sleeper_for == to_nation:
			u.sleeper_for = 0       # Spy::drop_spy_identity: no longer a spy
			u.remove_meta("sleeper_skill")
	alchemy_mode = ""
	animals.clear()
	weapon = ""
	weapon_queue = 0
	weapon_progress = 0.0
	# spies of the new owner now sit in their own building
	Game.inst.on_firm_changed(self, old)
	queue_redraw()


## Buildings that make units and may have a rally point (send_to_rally_point).
const RALLY_FIRMS := ["WAR", "STABLE", "SPY", "INN", "BASE", "BEE", "TERMITE", "INCUBAT", "ANIMAL"]


func set_rally(at: Vector2i) -> void:
	rally = at


func clear_rally() -> void:
	rally = Vector2i(-1, -1)


## A unit just made here walks to the rally point, if there is one.
func send_to_rally(u: Unit) -> void:
	if u and rally.x >= 0 and not u.dead:
		u.order_move(rally)


## FirmCamp::patrol: the sortie. ALL - the commander leads out every trained
## soldier; NO_GENERAL - the soldiers go without him; NO_INJURED - only those
## (commander too) within 25 hit points of full health. Men still in training
## stay inside. The player's sortie is selected.
enum { PATROL_ALL, PATROL_NO_GENERAL, PATROL_NO_INJURED }


func patrol(kind: int) -> Array:
	var out: Array = []
	var general: Unit = null
	if overseer and (kind == PATROL_ALL or (kind == PATROL_NO_INJURED and overseer.hp >= overseer.max_hp - 25.0)):
		general = overseer
		release_unit(general)
		out.append(general)
	for s in soldiers.duplicate():
		if s.basic_days > 0:
			continue
		if kind == PATROL_NO_INJURED and s.hp < s.max_hp - 25.0:
			continue
		release_unit(s)
		s.leader = general
		out.append(s)
	if nation_id == Game.inst.player_id and not out.is_empty():
		for o in Game.inst.selected:
			if is_instance_valid(o):
				o.selected = false
		Game.inst.selected = out.duplicate()
		for u in out:
			u.selected = true
	return out


func release_all_soldiers() -> void:
	for s in soldiers.duplicate():
		release_unit(s)


## "Fill from towns": villagers of linked loyal towns join at once.
func fill_from_towns() -> int:
	var n := 0
	for t in linked_towns:
		if t.nation_id != nation_id:
			continue
		while soldiers.size() < capacity() and t.can_recruit():
			if t.draft_into(self) == null:
				break
			n += 1
	return n


func eject_all() -> void:
	for s in soldiers.duplicate():
		release_unit(s)
	if overseer:
		release_unit(overseer)
	for u in extra_units:
		if is_instance_valid(u) and not u.dead:
			release_unit(u)
	extra_units.clear()


func set_builder(u: Unit) -> bool:
	if not under_construction or u.nation_id != nation_id:
		return false
	if builder != null and is_instance_valid(builder) and not builder.dead:
		return false
	builder = u
	_hide_unit(u)
	return true


# ------------------------------------------------------------- simulation ---

func sim_frame() -> void:
	if dead:
		return
	var frames: Array = build.get("frames", [])
	if not under_construction and frames.size() > 1:
		anim_timer += 1
		if anim_timer >= frames[anim_index].get("delay", 1) * 2:
			anim_timer = 0
			anim_index = (anim_index + 1) % frames.size()
			if anim_index == 0 and not build.get("use_first", true):
				anim_index = 1
			queue_redraw()
	if not under_construction and (is_military()):
		_defend_timer -= 1
		if _defend_timer <= 0:
			_defend_timer = 15
			_defend()
	if not under_construction and TOWER_FIRMS.has(code):
		_tower_timer -= 1
		if _tower_timer <= 0:
			_tower_shoot()
	if code == "FORTRESS" and not soldiers.is_empty() and Game.inst.frame % FORTRESS_TICK == obj_id % FORTRESS_TICK:
		SpecialFirms.fortress_shoot(self)


# -------------------------------------------------------- fort archers ---
# FirmFort (of_fort.cpp): up to five archers on the walls, trained for 120
# gold over 60 days each and paid 24 a year; they shoot back at whoever hits
# the fort (Place::being_attack_hit -> return_fire), and a hit may cost one.

const MAX_FORT_ARCHER := 5
const MAX_TRAIN_ARCHER_PROGRESS := 60
const TRAIN_ARCHER_COST := 120
const COST_PER_ARCHER := 24
const MIN_ARCHER_DELAY := 5
const MAX_ARCHER_SIMULTANEOUS := 2
const FORT_BULLET_DAMAGE := 14.0
const FORT_BULLET_RANGE := 8.0


## FirmFort::set_target_archer: -1 one more, -2 one fewer, else the number.
func set_target_archers(v: int) -> void:
	if v == -1:
		target_archers = mini(MAX_FORT_ARCHER, target_archers + 1)
	elif v == -2:
		if target_archers > archers:
			target_archers -= 1
	elif v >= 0 and v <= MAX_FORT_ARCHER:
		target_archers = v


## FirmFort::process_train_archer (daily)
func _train_archer() -> void:
	var g := Game.inst
	var n := nation()
	if archers >= target_archers or (n and n.cash <= TRAIN_ARCHER_COST):
		return
	archer_progress += 1
	if archer_progress > MAX_TRAIN_ARCHER_PROGRESS or (g.fast_build and nation_id == g.player_id):
		archer_progress = 0
		archers += 1
	if n:
		n.add_cash(-float(TRAIN_ARCHER_COST) / MAX_TRAIN_ARCHER_PROGRESS, "Buildings")


## FirmFort::pay_expense: archers are dismissed when they cannot be paid.
func _pay_archers() -> void:
	var n := nation()
	if archers <= 0 or n == null:
		return
	var cost := archers * float(COST_PER_ARCHER) / 365.0
	if n.cash >= cost:
		n.add_cash(-cost, "Buildings")
	else:
		archers = 0
		target_archers = mini(target_archers, 0)


## FirmFort::being_attack_hit: a hit may kill an archer; the others shoot back.
func _fort_hit(attacker: GameObj) -> void:
	if archers > 0:
		var chance := int(hp) - archers * 5
		if chance <= 0 or Game.inst.rng.randi() % chance == 0:
			archers -= 1
			target_archers = mini(target_archers, maxi(archers, target_archers))
	_return_fire(attacker)


## FirmFort::return_fire: a ready archer shoots, at most two in a frame.
func _return_fire(target: GameObj) -> void:
	var g := Game.inst
	if archers <= 0 or target == null or not is_instance_valid(target) or target.dead or not (target is Unit) or target.inside_firm != null:
		return
	if distance_to(target) > FORT_BULLET_RANGE:
		return
	while _archer_fired.size() < MAX_FORT_ARCHER:
		_archer_fired.append(-1000)
	var ready := -1
	var now := 0
	for a in archers:
		var since: int = g.frame - int(_archer_fired[a])
		if since == 0:
			now += 1
		if ready < 0 and since > MIN_ARCHER_DELAY:
			ready = a
	if ready < 0 or now >= MAX_ARCHER_SIMULTANEOUS:
		return
	_archer_fired[ready] = g.frame
	g.spawn_town_arrow(self, target, "ARROW" if Assets.has_sprite("ARROW") else "NO_ARROW", FORT_BULLET_DAMAGE, 18.0)     # FORT_BULLET_SPEED


## Towers fire at the nearest hostile unit in range.
func _tower_shoot() -> void:
	var spec: Array = TOWER_FIRMS[code]
	_tower_timer = 5
	var g := Game.inst
	var best: Unit = null
	var best_d: float = spec[1]
	for u in g.units_near(center_loc(), spec[1] + maxf(w, h)):
		if u.dead or u.inside_firm or not g.is_hostile(self, u):
			continue
		var d := distance_to(u)
		if d < best_d:
			best_d = d
			best = u
	if best == null:
		return
	_tower_timer = spec[2]
	var dmg: float = spec[0]
	if code.ends_with("LISHORR"):
		dmg = SpecialFirms.lishorr_damage(self)
	shown_until = g.frame + SpecialFirms.SHOWN_AFTER_FIRING
	var spr: String = build.get("bullet", "")
	if spr == "" or not Assets.has_sprite(spr):
		spr = "NO_ARROW"
	g.spawn_town_arrow(self, best, spr, dmg)


func next_day(day: int) -> void:
	if dead:
		return
	if code == "FORT" and not under_construction:
		_train_archer()
		_pay_archers()
	if is_work_firm() and not under_construction:
		_work_day(day)
	if under_construction:
		if builder != null and is_instance_valid(builder) and not builder.dead:
			progress += 100.0 / 30.0 * Game.inst.work_speed(nation_id)      # about 30 days to build
			hp = maxf(hp, max_hp * progress / 100.0)
			if progress >= 100.0:
				_complete()
		queue_redraw()
		return
	# Badly damaged buildings burn (Firm::next_day fires below 30% / 10% hit points).
	if visible and hp < max_hp * 0.3:
		var rng := Game.inst.fx_rng
		var tries := 2 if hp < max_hp * 0.1 else 1
		for i in tries:
			if rng.randf() < 0.7:
				Game.inst.spawn_effect(3, Vector2(x1 + rng.randi_range(0, w - 1), y1 + rng.randi_range(0, h - 1)))
	var n := nation()
	var unpaid := false
	if n and ftype.get("year_cost", 0) > 0:
		# Firm::pay_expense: a building the treasury cannot pay for decays instead
		var cost := float(ftype["year_cost"]) / 365.0
		if n.cash >= cost:
			n.add_cash(-cost, "Buildings")
		else:
			unpaid = true
			hp -= 1.0
			if hp <= 0.0:
				die(null)
				return
	if not unpaid:
		_process_repair()
	match code:
		"CAMP", "FORT":
			_train()
			Espionage.update_camp_loyalty(self)
			Espionage.think_desert(self, day)
		"MINE":
			if day % Defs.PROCESS_GOODS_INTERVAL == obj_id % Defs.PROCESS_GOODS_INTERVAL:
				Economy.mine_day(self)
		"FACTORY":
			if day % Defs.PROCESS_GOODS_INTERVAL == obj_id % Defs.PROCESS_GOODS_INTERVAL:
				Economy.factory_day(self)
		"MARKET":
			Economy.market_day(self, day)
		"RESEARCH":
			_research()
		"WAR":
			_war_factory()
		"INN":
			_inn(day)
		"STABLE", "SPY":
			Training.next_day(self, day)
		"BASE":
			_pray()
		"LAIR":
			_lair(day)
	SpecialFirms.next_day(self, day)


func _complete() -> void:
	under_construction = false
	progress = 100.0
	hp = max_hp
	var b := builder
	builder = null
	if b and is_instance_valid(b):
		b.inside_firm = null
		var c := Game.inst.world.adjacent_to_rect(footprint(), door())
		b.loc = Vector2(c)
		b.position = Iso.to_screen(b.loc)
		b.visible = true
		b.stop()
		# A general who builds a camp takes command of it, as in the original.
		if is_military() and b.can_lead() and overseer == null and b.nation_id == nation_id:
			accept_unit(b)
	if nation_id == Game.inst.player_id and not Game.inst.observer():
		Game.inst.notify("%s completed." % display_name(), center_loc())
	Game.inst.update_links()
	queue_redraw()


## FirmCamp::basic_train (daily) and advanced_train (every 30 days): recruits
## train to combat 20 (30 with a Roman Greater Being) over their unit's build
## days; then each month the general's leadership grows with his men, and
## the men grow toward his leadership, by their health and talent.
func _train() -> void:
	var g := Game.inst
	var basic := 20.0 + (10.0 if g.god_worshipped(nation_id, "ROMAN") else 0.0)
	for s in soldiers:
		if s.basic_days > 0:
			var total := maxf(1.0, float(s.utype.get("build_days", 10)))
			s.combat = minf(basic, s.combat + (basic + 0.125) / total)
			s.leadership = minf(20.0, s.leadership + 20.125 / total)
			s.basic_days -= 1
			s.hp = s.max_hp
		else:
			s.hp = minf(s.max_hp, s.hp + s.max_hp * 0.02)
	if overseer:
		overseer.hp = minf(overseer.max_hp, overseer.hp + overseer.max_hp * 0.02)
	if overseer == null or g.day % 30 != obj_id % 30:
		return
	var o := overseer
	var celtic := g.god_worshipped(nation_id, "CELTIC")
	var lead := int(o.lead_skill())
	var trained := soldiers.filter(func(x): return x.basic_days <= 0 and x != o)
	if not trained.is_empty() and o.leadership < 100.0:
		var inc := 5.0 * trained.size() * o.hp / o.max_hp * (100.0 + o.potential * 2) / 100.0
		o.leadership = minf(100.0, o.leadership + inc / 100.0)
	if o.combat < Defs.MAX_COMBAT_TRAIN:
		var inc := 10.0 * o.hp / o.max_hp * (100.0 + o.potential * 2) / 100.0
		if celtic:
			inc += inc / 2.0 if o.race == "CELTIC" else inc / 5.0
		o.combat = minf(Defs.MAX_COMBAT_TRAIN, o.combat + inc / 100.0)
	for s in trained:
		if s.combat < lead and s.combat < Defs.MAX_COMBAT_TRAIN:
			var inc: float = maxf(20.0, lead - s.combat) * s.hp / s.max_hp * (100.0 + s.potential * 2 + o.item_ability(Items.Ability.TRAIN)) / 100.0
			if celtic:
				inc += inc / 2.0 if s.race == "CELTIC" else inc / 5.0
			if s.race == "EGYPTIAN" and g.god_worshipped(nation_id, "EGYPTIAN"):
				var pc := g.god_worshippers(nation_id, "EGYPTIAN")
				inc = inc * (Defs.MAX_WORKER * 2) / (Defs.MAX_WORKER * 2 + pc)
			s.combat = minf(minf(float(lead), Defs.MAX_COMBAT_TRAIN), s.combat + inc / 100.0)
		if s.potential > 0 and s.leadership < 100.0:
			var inc: float = maxf(50.0, lead - s.leadership) * s.hp / s.max_hp * s.potential * 2 / 100.0
			s.leadership = minf(100.0, s.leadership + inc / 100.0)


## Send the garrison out against enemies that come close.
func _defend() -> void:
	if soldiers.is_empty():
		return
	var enemy := Game.inst.find_enemy_near(self, 7.0)
	if enemy == null:
		return
	var out := soldiers.size() if code == "LAIR" else maxi(1, soldiers.size() * 2 / 3)
	for s in soldiers.duplicate():
		if out <= 0:
			break
		if s.hp < s.max_hp * 0.3:
			continue
		release_unit(s, enemy)
		out -= 1


## FirmMarket::hire_caravan (free; one for every ten of the kingdom's people).
func hire_caravan() -> Unit:
	return Caravans.hire(self)


func goods_types_available() -> Array:
	var out := []
	for g in goods:
		if goods[g] > 0.5:
			out.append(g)
	return out


## FirmResearch::progress_research: a day's work of the tower, in percent of
## the technology: productivity / 300 x 30 / complexity, slower at higher levels,
## 30% faster with an Indian Greater Being.
func research_rate(t: Dictionary, level: int) -> float:
	var g := Game.inst
	var p := productivity() / 100.0 + 0.5 if g.fast_build and nation_id == g.player_id else productivity() / 300.0
	p = p * 30.0 / maxf(1.0, float(t["cost"])) / ((level + 2) / 2.0)
	if nation_id > 0 and g.god_worshipped(nation_id, "INDIAN"):
		p *= 1.3
	return p


func _research() -> void:
	var n := nation()
	if n == null or n.research_tech == "":
		return
	var t := Defs.tech_def(n.research_tech)
	if t.is_empty() or n.tech_level(n.research_tech) >= t.get("max", 0):
		n.research_tech = ""
		return
	n.progress_research(research_rate(t, n.tech_level(n.research_tech)), center_loc())


func start_research(tech_code: String) -> void:
	research_tech = tech_code


func _war_factory() -> void:
	var n := nation()
	if weapon == "" or n == null:
		return
	if weapon_progress <= 0.0:
		var cost := float(Defs.unit_types.get(weapon, {}).get("cost", 100))
		if not n.can_afford(cost):
			return
		n.add_cash(-cost, "Weapons")
		weapon_progress = 0.01
	var days := float(Defs.unit_types.get(weapon, {}).get("build_days", 60))
	weapon_progress += 100.0 / days * productivity() / 100.0 * (1.0 + 0.25 * n.tech_level("WAR_PROD")) * Game.inst.work_speed(nation_id)
	if weapon_progress >= 100.0:
		weapon_progress = 0.0
		var c := Game.inst.world.adjacent_to_rect(footprint(), door())
		var u := Game.inst.spawn_unit(weapon, nation_id, c, 30.0)
		send_to_rally(u)
		if u and nation_id == Game.inst.player_id:
			Game.inst.notify("%s built." % u.type_name(), center_loc())
		weapon_queue -= 1
		if weapon_queue <= 0:
			weapon_queue = 0
			weapon = ""


## The special unit of this training ground's race.
func special_unit() -> String:
	return Defs.unit_sprite(race, "SPU")


func queue_weapon(unit_code: String) -> void:
	if weapon != unit_code:
		weapon = unit_code
		weapon_progress = 0.0
		weapon_queue = 0
	weapon_queue += 1


func _inn(day: int) -> void:
	for hdef in heroes:
		hdef["days"] -= 1
	heroes = heroes.filter(func(x): return x["days"] > 0)
	if day % 30 == obj_id % 30 and heroes.size() < 4:
		var rng := Game.inst.rng
		var r: Dictionary = Defs.races[rng.randi() % Defs.races.size()]
		var hl: Array = Defs.heroes.filter(func(x): return x["race"] == r["code"])
		var hname: String = hl[rng.randi() % hl.size()]["name"] if not hl.is_empty() else Defs.random_person_name(r["code"], rng)
		var cmb := float(rng.randi_range(30, 90))
		var lead := float(rng.randi_range(20, 90))
		heroes.append({"name": hname, "race": r["code"], "combat": cmb, "leadership": lead,
			"cost": int(80 + cmb * 4 + lead * 4), "days": 150, "special": rng.randf() < 0.3})


func hire_hero(i: int) -> Unit:
	if i < 0 or i >= heroes.size():
		return null
	var hdef: Dictionary = heroes[i]
	var n := nation()
	if n == null or not n.can_afford(hdef["cost"]):
		return null
	n.add_cash(-float(hdef["cost"]), "Hiring")
	heroes.remove_at(i)
	var sprite := Defs.unit_sprite(hdef["race"], "SPU" if hdef["special"] else "INF")
	var c := Game.inst.world.adjacent_to_rect(footprint(), door())
	var u := Game.inst.spawn_unit(sprite, nation_id, c, hdef["combat"])
	send_to_rally(u)
	if u:
		u.unit_name = hdef["name"]
		u.leadership = hdef["leadership"]
		u.is_hero = true
		u.rank = Defs.Rank.GENERAL
	return u


## Seat of Power: linked people pray, building up the kingdom's prayer points.
func _pray() -> void:
	var n := nation()
	if n:
		# fast build (the tutorials): FirmBase::next_day adds the full productivity a day
		var rate := productivity() if Game.inst.fast_build and nation_id == Game.inst.player_id else workers() * 0.03
		n.prayer_points = minf(Wishes.FULL, n.prayer_points + rate)


## The Special Blessing (FirmBase::invoke_random_effect).
func bless() -> void:
	Wishes.invoke(self)


func god_cost() -> float:
	return 150.0


func invoke_god() -> Unit:
	var n := nation()
	if n == null or n.prayer_points < god_cost():
		return null
	# FirmBase: the Greater Being of the Seat's race, if its Scroll of Power is held
	if not n.known_gods.has(race):
		return null
	var g: Dictionary = Defs.gods.get(race, {})
	if g.is_empty() or not Assets.has_sprite(g["unit"]):
		return null
	n.prayer_points -= god_cost()
	var c := Game.inst.world.adjacent_to_rect(footprint(), door())
	var u := Game.inst.spawn_unit(g["unit"], nation_id, c, 100.0)
	send_to_rally(u)
	if u:
		u.life_frames = int(Defs.FRAMES_PER_DAY * 120)
	return u


## Fryhtan lair: breeds Fryhtans and periodically sends them raiding.
func _lair(day: int) -> void:
	if nation_id != GameObj.MONSTER_NATION:
		return      # a Fryhtan kingdom's lair breeds and raids on its AI's orders
	var rng := Game.inst.rng
	# Breed only while the whole brood (inside and out on raids) is below capacity.
	var outside := 0
	for u in Game.inst.units:
		if u.home_firm == self and not u.dead and u.inside_firm == null:
			outside += 1
	if soldiers.size() + outside < capacity() and rng.randf() < 0.02:
		var u := Game.inst.spawn_unit(monster_code, nation_id, Vector2i(x1, y1 + h), 20.0)   # recruited and trained to BASIC_COMBAT_TRAIN
		if u:
			accept_unit(u)
	raid_timer -= 1
	if raid_timer <= 0 and soldiers.size() >= 5 and day > 365:
		raid_timer = 500 + rng.randi_range(0, 500)
		var tgt := Game.inst.find_raid_target(self, 24.0)
		if tgt:
			var out := soldiers.size() / 3
			for s in soldiers.duplicate():
				if out <= 0:
					break
				release_unit(s, tgt)
				out -= 1


## Fryhtan kingdom lair: breed one Fryhtan for gold and life points (FirmLair::recruit_soldier).
func breed() -> Unit:
	var n := nation()
	if n == null or not n.is_fryhtan or soldiers.size() >= capacity() or under_construction:
		return null
	var ut: Dictionary = Defs.unit_types.get(monster_code, {})
	var cost := float(ut.get("cost", 100))
	var live := float(ut.get("live_cost", 50))
	if n.cash < cost or n.live_points < live:
		return null
	var u := Game.inst.spawn_unit(monster_code, nation_id, Vector2i(x1, y1 + h), 20.0)   # FirmLair::recruit_soldier, basic training
	if u == null:
		return null
	n.add_cash(-cost, "Training")
	n.live_points -= live
	accept_unit(u)
	return u


func is_fryhtan_lair() -> bool:
	if code != "LAIR" or nation_id == GameObj.MONSTER_NATION:
		return false
	var n := nation()
	return n != null and n.is_fryhtan


func on_attacked(attacker: GameObj) -> void:
	if code == "FORT" and not under_construction:
		_fort_hit(attacker)
	if attacker and is_instance_valid(attacker) and not attacker.dead:
		Game.inst.on_object_attacked(self, attacker)
		_defend_timer = 0


const CAN_SELL_HIT_POINTS_PERCENT := 80


## Firm::can_sell: only a building in good repair can be sold.
func can_sell() -> bool:
	return not under_construction and int(hp) >= int(max_hp) * CAN_SELL_HIT_POINTS_PERCENT / 100


## Firm::sell_firm: half the setup cost (and life points, for Fryhtans)
## back, in proportion to the building's hit points.
func sell_firm() -> void:
	var n := nation()
	if n == null or dead or not can_sell():
		return
	var ft: Dictionary = Defs.firm_types.get(code, {})
	var k := float(int(hp)) / maxf(1.0, float(int(max_hp)))
	n.add_cash(float(ft.get("cost", 0)) / 2.0 * k, "Sold buildings")
	if n.is_fryhtan:
		n.live_points += float(ft.get("live_cost", 0)) / 2.0 * k
	Game.inst.play_sound("F", code, "SELL", center_loc())
	die(null)


func die(killer: GameObj) -> void:
	if dead:
		return
	dead = true
	Game.inst.on_firm_destroyed(self, killer)


# ------------------------------------------------------------------ draw ---

func _origin() -> Vector2:
	return Iso.to_screen(Vector2(x1, y1)) - position


func _draw() -> void:
	render(self)


func render(cv) -> void:
	var col := nation_color()
	var o := _origin()
	if selected:
		_draw_footprint(cv, col.lightened(0.3))
		for t in linked_towns:
			cv.draw_line(Vector2.ZERO, Iso.to_screen(t.center_loc()) - position, Color(1, 0.9, 0.3, 0.7), 2.0)
		for f in linked_firms:
			if f.nation_id == nation_id:
				cv.draw_line(Vector2.ZERO, Iso.to_screen(f.center_loc()) - position, Color(0.5, 0.8, 1.0, 0.7), 2.0)
	var frames: Array = build.get("frames", [])
	if frames.is_empty() or Game.inst.hide_buildings:
		# Hide Buildings: a square in the owner's colour with the building's name
		var p := PackedVector2Array([
			Iso.to_screen(Vector2(x1, y1)) - position, Iso.to_screen(Vector2(x1 + w, y1)) - position,
			Iso.to_screen(Vector2(x1 + w, y1 + h)) - position, Iso.to_screen(Vector2(x1, y1 + h)) - position])
		cv.draw_colored_polygon(p, Color(col, 0.55))
		_draw_footprint(cv, col)
		if Game.inst.hide_buildings:
			cv.draw_string(ThemeDB.fallback_font, Vector2(-60, 4), display_name(), HORIZONTAL_ALIGNMENT_CENTER, 120, 13, Color.WHITE)
		return
	# Frame 1 is the whole building; later frames only hold the animated parts
	# drawn on top of it (Firm::draw_frame in the original).
	# Inside Information: the building's name over it (disp_extend_info)
	var ext := int(GameOptions.get_opt("inside_info"))
	if not under_construction and (ext == 2 or (ext == 1 and Game.inst.hovered == self)):
		cv.draw_string(ThemeDB.fallback_font, Vector2(-80, -40), display_name(), HORIZONTAL_ALIGNMENT_CENTER, 160, 12, Color(1, 1, 0.85))
	var bitmaps: Array = frames[0]["bitmaps"].duplicate()
	var mod := Color.WHITE
	if not under_construction and nation_id == Game.inst.player_id and SpecialFirms.hidden_from(self, -1):
		mod = Color(1, 1, 1, 0.6)
	if under_construction:
		# FirmRes::calc_color_remap_table: solid, brightness 40% -> 90% with completion
		var br := (progress / 100.0 * 128.0 + 102.0) / 256.0
		mod = Color(br, br, br, 1.0)
		var uc: int = build.get("underc", 0)
		var ucn: int = build.get("underc_count", 1)
		if uc > 0 and ucn > 1:
			bitmaps = [uc + mini(ucn - 1, int(progress / 100.0 * ucn))]
	elif anim_index > 0:
		bitmaps.append_array(frames[anim_index % frames.size()]["bitmaps"])
	for rec in bitmaps:
		var b := Assets.firm_bitmap(build, rec, col)
		if b.is_empty() or b[2] == 4:
			continue
		cv.draw_texture(b[0], o + b[1], mod)
	# Construction flags at the four corners (Firm::draw_full_size).
	if under_construction:
		var flag := Assets.spict("FLAG-S0", col)
		if flag:
			for corner in [Vector2(x1, y1), Vector2(x1 + w, y1), Vector2(x1, y1 + h), Vector2(x1 + w, y1 + h)]:
				cv.draw_texture(flag, Iso.to_screen(corner) - position + Vector2(-4, -25))
	if selected or hp < max_hp or under_construction:
		draw_hp_bar_on(cv, o + Vector2(0, -24), 60)
	if under_construction:
		var bar := Rect2(o + Vector2(-30, -34), Vector2(60, 5))
		cv.draw_rect(bar, Color(0, 0, 0, 0.7))
		cv.draw_rect(Rect2(bar.position + Vector2(1, 1), Vector2(58 * progress / 100.0, 3)), Color(0.4, 0.7, 1.0))


func _draw_footprint(cv, col: Color) -> void:
	var p := PackedVector2Array([
		Iso.to_screen(Vector2(x1, y1)) - position, Iso.to_screen(Vector2(x1 + w, y1)) - position,
		Iso.to_screen(Vector2(x1 + w, y1 + h)) - position, Iso.to_screen(Vector2(x1, y1 + h)) - position,
	])
	p.append(p[0])
	cv.draw_polyline(p, col, 2.0)


## Ground bitmap drawn by the ground layer under every object.
func draw_ground(ci) -> void:
	var g: int = build.get("ground", 0)
	if g <= 0:
		return
	var b := Assets.firm_bitmap(build, g, nation_color())
	if not b.is_empty():
		ci.draw_texture(b[0], Iso.to_screen(Vector2(x1, y1)) + b[1])
