class_name Firm
extends GameObj
## A building. One class covers every firm type; behaviour switches on `code`.
## Rules follow the 7k2 source: of_camp.cpp, of_mine.cpp, of_fact.cpp,
## of_mark.cpp, of_rese.cpp, of_war.cpp, of_inn.cpp, of_base.cpp, of_lair.cpp.

const WORK_FIRMS := ["MINE", "FACTORY", "RESEARCH", "WAR", "BASE"]
const MILITARY_FIRMS := ["CAMP", "FORT"]
## Fryhtan and siege structures that shoot at enemies on their own
## (FirmLishorr / FirmOffensive2::process_monster_firm): [damage, range, delay].
const TOWER_FIRMS := {
	"LISHORR": [12.0, 8.0, 20], "WLISHORR": [12.0, 8.0, 20], "MAGIC": [30.0, 9.0, 40],
	"OFF_BLD1": [40.0, 9.0, 40], "OFF_BLD2": [40.0, 9.0, 40], "OFF_BLD3": [60.0, 9.0, 40], "OFF_BLD4": [100.0, 10.0, 60],
}
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
var worker_from := {}               # Town -> workers supplied this day
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
var research_tech := ""
var research_points := 0.0
var weapon := ""
var weapon_progress := 0.0
var weapon_queue := 0
var heroes: Array = []              # inn: heroes for hire
var monster_code := ""              # lair: monster unit sprite
var raid_timer := 0
var build_row := 0                  # FBUILD record when the variant was given explicitly (scenarios)
var _tower_timer := 0

var anim_index := 0
var anim_timer := 0
var _defend_timer := 0


func setup(firm_code: String, nation: int, build_race: String, at: Vector2i) -> void:
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


func is_military() -> bool:
	return code in MILITARY_FIRMS or code == "LAIR"


func is_work_firm() -> bool:
	return code in WORK_FIRMS


func capacity() -> int:
	match code:
		"FORT":
			return Defs.MAX_SOLDIER
		"CAMP":
			return 8
		"LAIR":
			return 8
	return 0


func workers() -> int:
	var n := 0
	for t in worker_from:
		n += worker_from[t]
	return n


func productivity() -> float:
	return 100.0 * workers() / Defs.MAX_WORKER


func armor() -> float:
	return 0.0


# --------------------------------------------------------------- garrison ---

## A unit arrives at the building (Unit::ENTER order).
func accept_unit(u: Unit) -> bool:
	if under_construction or u.nation_id != nation_id or dead:
		return false
	if not is_military():
		return false
	if code != "LAIR" and not u.is_human():
		return false
	if code == "LAIR" and u.home_firm == self:
		u.home_firm = null      # a raider coming home always fits; it counted toward the brood
		soldiers.append(u)
		_hide_unit(u)
		return true
	var leads := u.can_lead() if code != "LAIR" else (u.rank >= Defs.Rank.GENERAL and nation_id != GameObj.MONSTER_NATION)
	if leads and overseer == null:
		overseer = u
	elif soldiers.size() < capacity():
		soldiers.append(u)
	else:
		return false
	_hide_unit(u)
	return true


## Puts a general from the garrison in command; the previous commander joins the soldiers.
func make_overseer(u: Unit) -> void:
	if not u in soldiers or not u.can_lead():
		return
	soldiers.erase(u)
	if overseer:
		soldiers.append(overseer)
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


func eject_all() -> void:
	for s in soldiers.duplicate():
		release_unit(s)
	if overseer:
		release_unit(overseer)


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


## Towers fire at the nearest hostile unit in range.
func _tower_shoot() -> void:
	var spec: Array = TOWER_FIRMS[code]
	_tower_timer = 5
	var g := Game.inst
	var best: Unit = null
	var best_d: float = spec[1]
	for u in g.units:
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
	if code.ends_with("LISHORR") and g.weather.rain_scale() <= 0:
		dmg *= 2.0       # Lishorrs are deadlier in dry weather
	var spr: String = build.get("bullet", "")
	if spr == "" or not Assets.has_sprite(spr):
		spr = "NO_ARROW"
	g.spawn_town_arrow(self, best, spr, dmg)


func next_day(day: int) -> void:
	if dead:
		return
	if under_construction:
		if builder != null and is_instance_valid(builder) and not builder.dead:
			progress += 100.0 / 30.0      # about 30 days to build
			hp = maxf(hp, max_hp * progress / 100.0)
			if progress >= 100.0:
				_complete()
		queue_redraw()
		return
	# Badly damaged buildings burn (Firm::next_day fires below 30% / 10% hit points).
	if visible and hp < max_hp * 0.3:
		var rng := Game.inst.rng
		var tries := 2 if hp < max_hp * 0.1 else 1
		for i in tries:
			if rng.randf() < 0.7:
				Game.inst.spawn_effect(3, Vector2(x1 + rng.randi_range(0, w - 1), y1 + rng.randi_range(0, h - 1)))
	var n := nation()
	if n and n.is_fryhtan:
		n.live_points = maxf(0.0, n.live_points - float(ftype.get("year_cost", 0)) / 365.0 * 0.5)
	var unpaid := false
	if n and not n.is_fryhtan and ftype.get("year_cost", 0) > 0:
		# Firm::pay_expense: a building the treasury cannot pay for decays instead
		var cost := float(ftype["year_cost"]) / 365.0
		if n.cash >= cost:
			n.add_cash(-cost)
		else:
			unpaid = true
			hp -= 1.0
			if hp <= 0.0:
				die(null)
				return
	if not unpaid and hp < max_hp and Game.inst.frame - last_attacked_frame > 200:
		hp = minf(max_hp, hp + max_hp * 0.002)
	match code:
		"CAMP", "FORT":
			_train()
		"MINE":
			if day % Defs.PROCESS_GOODS_INTERVAL == obj_id % Defs.PROCESS_GOODS_INTERVAL:
				_produce_raw()
		"FACTORY":
			if day % Defs.PROCESS_GOODS_INTERVAL == obj_id % Defs.PROCESS_GOODS_INTERVAL:
				_factory()
		"MARKET":
			_market(day)
		"RESEARCH":
			_research()
		"WAR":
			_war_factory()
		"INN":
			_inn(day)
		"STABLE":
			_train_special()
		"SPY":
			_train_spies()
		"BASE":
			_pray()
		"LAIR":
			_lair(day)


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


## Soldiers in a camp train toward a cap set by the general's leadership.
func _train() -> void:
	if overseer == null:
		return
	var lead := overseer.leadership
	var cap := minf(Defs.MAX_COMBAT_TRAIN, 30.0 + lead * 0.7)
	for s in soldiers:
		if s.combat < cap:
			s.combat = minf(cap, s.combat + 0.2 * (1.0 + lead / 100.0))
		s.hp = minf(s.max_hp, s.hp + s.max_hp * 0.02)
	if overseer.leadership < 100.0:
		overseer.leadership = minf(100.0, overseer.leadership + 0.03)
	overseer.hp = minf(overseer.max_hp, overseer.hp + overseer.max_hp * 0.02)


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


func _produce_raw() -> void:
	if site == null or reserve <= 0.0 or stock >= STOCK_CAP:
		return
	var n := nation()
	var yield_rate := 0.5 + (0.25 * n.tech_level("MINING") if n else 0.0)
	var raw_qty := minf(100.0 * productivity() / 100.0, reserve)
	var produce := minf(raw_qty * yield_rate, STOCK_CAP - stock)
	reserve -= produce / yield_rate if yield_rate > 0 else produce
	stock += produce
	site.reserve = reserve
	if reserve <= 0.0:
		reserve = 0.0
		if nation_id == Game.inst.player_id:
			Game.inst.notify("A %s mine has run out of deposits." % raw, center_loc())


func _factory() -> void:
	var n := nation()
	# Choose the product from the first linked mine if not yet set.
	if raw == "":
		for f in linked_firms:
			if f.code == "MINE" and not f.under_construction and f.nation_id == nation_id:
				raw = f.raw
				break
	if raw == "":
		return
	for f in linked_firms:
		if f.code == "MINE" and f.raw == raw and f.stock > 0 and not f.under_construction:
			var qty := minf(f.stock, STOCK_CAP - raw_stock)
			if f.nation_id != nation_id:
				qty = minf(qty, n.cash / Defs.RAW_PRICE)
				n.add_cash(-qty * Defs.RAW_PRICE)
				var other := f.nation()
				if other:
					other.add_cash(qty * Defs.RAW_PRICE)
			f.stock -= qty
			raw_stock += qty
	var rate := 1.0 + 0.25 * n.tech_level("MANUFACT")
	var produce := minf(20.0 * productivity() / 100.0 * Defs.PROCESS_GOODS_INTERVAL * rate, raw_stock)
	produce = minf(produce, STOCK_CAP - stock)
	raw_stock -= produce
	stock += produce


func _market(day: int) -> void:
	if day % Defs.PROCESS_GOODS_INTERVAL == obj_id % Defs.PROCESS_GOODS_INTERVAL:
		for f in linked_firms:
			if f.code == "FACTORY" and f.raw != "" and f.stock > 0 and not f.under_construction:
				var cur: float = goods.get(f.raw, 0.0)
				var qty := minf(f.stock, STOCK_CAP - cur)
				if f.nation_id != nation_id:
					var n := nation()
					qty = minf(qty, n.cash / Defs.PRODUCT_PRICE)
					n.add_cash(-qty * Defs.PRODUCT_PRICE)
					if f.nation():
						f.nation().add_cash(qty * Defs.PRODUCT_PRICE)
				f.stock -= qty
				goods[f.raw] = cur + qty
	# Sell to linked towns of any nation: demand is proportional to their population.
	var pop := 0
	for t in linked_towns:
		pop += t.population
	if pop == 0:
		return
	for g in goods:
		var sale := minf(goods[g], pop * 1.0 / 30.0)
		if sale <= 0:
			continue
		goods[g] -= sale
		var income := sale * Defs.CONSUMER_PRICE
		if Game.inst.blessed(nation_id, "CHINESE"):
			income *= 1.3
		market_sales += income
		var n := nation()
		if n:
			n.add_cash(income)


const CARAVAN_COST := 100.0
const MAX_CARAVANS := 3


func hire_caravan() -> Unit:
	var n := nation()
	if code != "MARKET" or under_construction or n == null or not n.can_afford(CARAVAN_COST):
		return null
	if Game.inst.caravans_of(self) >= MAX_CARAVANS or not Assets.has_sprite("CARAVAN"):
		return null
	var c := Game.inst.world.adjacent_to_rect(footprint(), door())
	var u := Game.inst.spawn_unit("CARAVAN", nation_id, c, 10.0)
	if u:
		n.add_cash(-CARAVAN_COST)
		u.caravan_home = self
	return u


func goods_types_available() -> Array:
	var out := []
	for g in goods:
		if goods[g] > 0.5:
			out.append(g)
	return out


static func research_cost(t: Dictionary, level: int) -> float:
	return float(t["cost"]) * 15.0 * (level + 1)


func _research() -> void:
	var n := nation()
	if n == null:
		return
	if research_tech == "" or n.tech_level(research_tech) >= Defs.tech_def(research_tech).get("max", 0):
		research_tech = ""
		return
	var t := Defs.tech_def(research_tech)
	research_points += 3.0 * productivity() / 100.0
	var cost := research_cost(t, n.tech_level(research_tech))
	n.research_progress[research_tech] = research_points / cost
	if research_points >= cost:
		research_points = 0.0
		n.tech[research_tech] = n.tech_level(research_tech) + 1
		n.research_progress.erase(research_tech)
		if nation_id == Game.inst.player_id:
			Game.inst.notify("Research complete: %s level %d." % [t["name"], n.tech[research_tech]], center_loc())
		if n.tech[research_tech] >= t["max"]:
			research_tech = ""


func start_research(tech_code: String) -> void:
	if research_tech != tech_code:
		research_tech = tech_code
		research_points = 0.0


func _war_factory() -> void:
	var n := nation()
	if weapon == "" or n == null:
		return
	if weapon_progress <= 0.0:
		var cost := float(Defs.unit_types.get(weapon, {}).get("cost", 100))
		if not n.can_afford(cost):
			return
		n.add_cash(-cost)
		weapon_progress = 0.01
	var days := float(Defs.unit_types.get(weapon, {}).get("build_days", 60))
	weapon_progress += 100.0 / days * productivity() / 100.0 * (1.0 + 0.25 * n.tech_level("WAR_PROD"))
	if weapon_progress >= 100.0:
		weapon_progress = 0.0
		var c := Game.inst.world.adjacent_to_rect(footprint(), door())
		var u := Game.inst.spawn_unit(weapon, nation_id, c, 30.0)
		if u and nation_id == Game.inst.player_id:
			Game.inst.notify("%s built." % u.type_name(), center_loc())
		weapon_queue -= 1
		if weapon_queue <= 0:
			weapon_queue = 0
			weapon = ""


## Special unit trained at this race's training centre (FirmTrain, simplified):
## a volunteer from a linked loyal town plus the unit's cost.
func special_unit() -> String:
	return Defs.unit_sprite(race, "SPU")


func _train_special() -> void:
	var n := nation()
	if weapon == "" or n == null:
		return
	if weapon_progress <= 0.0:
		var cost := float(Defs.unit_types.get(weapon, {}).get("cost", 50))
		if not n.can_afford(cost):
			return
		var town: Town = null
		for t in linked_towns:
			if t.nation_id == nation_id and t.can_spare_trainee():
				town = t
				break
		if town == null:
			return
		town.population -= 1
		town._check_empty()
		town.loyalty = maxf(0.0, town.loyalty - 1.0)
		n.add_cash(-cost)
		weapon_progress = 0.01
	var days := float(Defs.unit_types.get(weapon, {}).get("build_days", 30))
	weapon_progress += 100.0 / days
	if weapon_progress >= 100.0:
		weapon_progress = 0.0
		var c := Game.inst.world.adjacent_to_rect(footprint(), door())
		var u := Game.inst.spawn_unit(weapon, nation_id, c, float(Game.inst.rng.randi_range(35, 55)))
		if u:
			u.leadership = float(Game.inst.rng.randi_range(20, 50))
			if nation_id == Game.inst.player_id and not Game.inst.observer():
				Game.inst.notify("%s trained." % u.type_name(), center_loc())
		weapon_queue -= 1
		if weapon_queue <= 0:
			weapon_queue = 0
			weapon = ""


## Espionage College: queued spies are trained one every 20 days.
func _train_spies() -> void:
	if weapon_queue <= 0:
		return
	weapon_progress += 5.0
	if weapon_progress >= 100.0:
		weapon_progress = 0.0
		var u := Game.inst.spy_spawn(self)
		if u:
			weapon_queue -= 1
			if nation_id == Game.inst.player_id:
				Game.inst.notify("A spy has been trained (skill %d)." % int(u.spy_skill), center_loc())


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
	n.add_cash(-float(hdef["cost"]))
	heroes.remove_at(i)
	var sprite := Defs.unit_sprite(hdef["race"], "SPU" if hdef["special"] else "INF")
	var c := Game.inst.world.adjacent_to_rect(footprint(), door())
	var u := Game.inst.spawn_unit(sprite, nation_id, c, hdef["combat"])
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
		n.prayer_points = minf(400.0, n.prayer_points + workers() * 0.03)


func god_cost() -> float:
	return 150.0


func invoke_god() -> Unit:
	var n := nation()
	if n == null or n.prayer_points < god_cost():
		return null
	var g: Dictionary = Defs.gods.get(n.race, {})
	if g.is_empty() or not Assets.has_sprite(g["unit"]):
		return null
	n.prayer_points -= god_cost()
	var c := Game.inst.world.adjacent_to_rect(footprint(), door())
	var u := Game.inst.spawn_unit(g["unit"], nation_id, c, 100.0)
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
		var u := Game.inst.spawn_unit(monster_code, nation_id, Vector2i(x1, y1 + h), float(rng.randi_range(20, 60)))
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
	var u := Game.inst.spawn_unit(monster_code, nation_id, Vector2i(x1, y1 + h), float(Game.inst.rng.randi_range(25, 50)))
	if u == null:
		return null
	n.add_cash(-cost)
	n.live_points -= live
	accept_unit(u)
	return u


func is_fryhtan_lair() -> bool:
	if code != "LAIR" or nation_id == GameObj.MONSTER_NATION:
		return false
	var n := nation()
	return n != null and n.is_fryhtan


func on_attacked(attacker: GameObj) -> void:
	if attacker and is_instance_valid(attacker) and not attacker.dead:
		Game.inst.on_object_attacked(self, attacker)
		_defend_timer = 0


func die(killer: GameObj) -> void:
	if dead:
		return
	dead = true
	Game.inst.on_firm_destroyed(self, killer)


# ------------------------------------------------------------------ draw ---

func _origin() -> Vector2:
	return Iso.to_screen(Vector2(x1, y1)) - position


func _draw() -> void:
	var col := nation_color()
	var o := _origin()
	if selected:
		_draw_footprint(col.lightened(0.3))
		for t in linked_towns:
			draw_line(Vector2.ZERO, Iso.to_screen(t.center_loc()) - position, Color(1, 0.9, 0.3, 0.7), 2.0)
		for f in linked_firms:
			if f.nation_id == nation_id:
				draw_line(Vector2.ZERO, Iso.to_screen(f.center_loc()) - position, Color(0.5, 0.8, 1.0, 0.7), 2.0)
	var frames: Array = build.get("frames", [])
	if frames.is_empty():
		_draw_footprint(col)
		return
	# Frame 1 is the whole building; later frames only hold the animated parts
	# drawn on top of it (Firm::draw_frame in the original).
	var bitmaps: Array = frames[0]["bitmaps"].duplicate()
	var mod := Color.WHITE
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
		draw_texture(b[0], o + b[1], mod)
	# Construction flags at the four corners (Firm::draw_full_size).
	if under_construction:
		var flag := Assets.spict("FLAG-S0", col)
		if flag:
			for corner in [Vector2(x1, y1), Vector2(x1 + w, y1), Vector2(x1, y1 + h), Vector2(x1 + w, y1 + h)]:
				draw_texture(flag, Iso.to_screen(corner) - position + Vector2(-4, -25))
	if selected or hp < max_hp or under_construction:
		draw_hp_bar(o + Vector2(0, -24), 60)
	if under_construction:
		var bar := Rect2(o + Vector2(-30, -34), Vector2(60, 5))
		draw_rect(bar, Color(0, 0, 0, 0.7))
		draw_rect(Rect2(bar.position + Vector2(1, 1), Vector2(58 * progress / 100.0, 3)), Color(0.4, 0.7, 1.0))


func _draw_footprint(col: Color) -> void:
	var p := PackedVector2Array([
		Iso.to_screen(Vector2(x1, y1)) - position, Iso.to_screen(Vector2(x1 + w, y1)) - position,
		Iso.to_screen(Vector2(x1 + w, y1 + h)) - position, Iso.to_screen(Vector2(x1, y1 + h)) - position,
	])
	p.append(p[0])
	draw_polyline(p, col, 2.0)


## Ground bitmap drawn by the ground layer under every object.
func draw_ground(ci: CanvasItem) -> void:
	var g: int = build.get("ground", 0)
	if g <= 0:
		return
	var b := Assets.firm_bitmap(build, g, nation_color())
	if not b.is_empty():
		ci.draw_texture(b[0], Iso.to_screen(Vector2(x1, y1)) + b[1])
