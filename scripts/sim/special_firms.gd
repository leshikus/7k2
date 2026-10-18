class_name SpecialFirms
extends RefCounted
## Fryhtan special buildings and the human offensive buildings, after
## of_lair.cpp (buy_tech, grant_to_non_own_lair), of_mtrn.cpp (Bheema Hyfe,
## Tarmes Mownd), of_anim.cpp (Keraal), of_alch.cpp (Alchemist Tor),
## of_incu.cpp (Vapngart), of_mfort.cpp (Fortress), of_lish.cpp (Lishorr) and
## of_magi.cpp (Mage Tor, Teledamnum, Preuser, Archimedetron).

const TRAIN_UNITS := {"BEE": ["BEE"], "TERMITE": ["TERMITE"]}
const INCUBATE_UNITS := ["F__BALLI", "F_CATAPU", "F_CANNON"]
const ANIMAL_UNITS := ["JAGUAR", "GORILLA", "RHINOCER"]
const ANIMAL_UPDATE_INTERVAL := 14
const MAX_ANIMAL_UNIT := 5
const ALCHEMY_MAX_CONSUME := 60.0
const ALCHEMY_MODES := ["LIVEGOLD", "GOLDLIVE", "MINELIVE", "MINEGOLD"]
const FORTRESS_ARCHERS := 4
const FORTRESS_BUILDERS := 4
const FORTRESS_RANGE := 8.0
const LISHORR_BULLET_DAMAGE := 12.0
const SHOWN_AFTER_FIRING := 40          # frames a camouflaged building stays visible after it fires
## Spell damage is halved as unit hit points are halved in this port.
const SPELL_DAMAGE_SCALE := 0.5
const FRYHTAN_CLASSES := ["MONSTER", "INSECT", "ANIMAL"]


static func is_spell_firm(code: String) -> bool:
	return Defs.FIRM_SPELLS.has(code)


static func is_fryhtan_unit(u: Unit) -> bool:
	return u.utype.get("class", "") in FRYHTAN_CLASSES


## Life points it costs to put up a building (FirmInfo::setup_live_points_cost).
static func setup_live(code: String) -> float:
	var row: Dictionary = {}
	for f in Assets.table("FIRM"):
		if f["CODE"] == code:
			row = f
			break
	return float(row.get("SETUP_LIVE", "0").to_int()) if not row.is_empty() else 0.0


# -------------------------------------------------------- lair techs ---

## The Fryhtan species of a lair (its race in the original).
static func lair_species(lair: Firm) -> String:
	return Defs.unit_types.get(lair.monster_code, {}).get("race", "")


static func can_buy_tech(lair: Firm, t: Dictionary) -> bool:
	var n := lair.nation()
	if n == null or not n.is_fryhtan or lair.under_construction:
		return false
	if t.get("species", "") != lair_species(lair) or not Defs.can_research(n, t):
		return false
	return n.live_points >= Defs.fryhtan_tech_live_cost(t)


## FirmLair::buy_tech: the next level of a species technology, bought at once
## with life points.
static func buy_tech(lair: Firm, code: String) -> bool:
	var t := Defs.tech_def(code)
	if t.is_empty() or not can_buy_tech(lair, t):
		return false
	var n := lair.nation()
	n.live_points -= Defs.fryhtan_tech_live_cost(t)
	n.tech[code] = n.tech_level(code) + 1
	if n.id == Game.inst.player_id:
		Game.inst.notify("Your brood has learnt %s (level %d)." % [t["name"], n.tech[code]], lair.center_loc())
	return true


## FirmLair::grant_to_non_own_lair_cost.
static func take_lair_cost(lair: Firm) -> float:
	var power := lair.soldiers.size() * 30 + (lair.overseer.combat_level() if lair.overseer else 0.0)
	return maxf(2000.0, 1000.0 + power * 5.0)


## A Fryhtan kingdom may buy an independent lair linked to one of its own
## lairs that has a commander (FirmLair::can_grant_to_non_own_lair).
static func can_take_lair(lair: Firm, nid: int, check_cash := true) -> bool:
	if lair.code != "LAIR" or lair.nation_id != GameObj.MONSTER_NATION or lair.dead:
		return false
	var n := Game.inst.nation(nid)
	if n == null or not n.is_fryhtan:
		return false
	if check_cash and n.cash < take_lair_cost(lair):
		return false
	for f in Game.inst.firms:
		if f.code == "LAIR" and f.nation_id == nid and f.overseer != null and not f.dead \
				and Game._center_dist(f.center_loc(), lair.center_loc()) <= Defs.EFFECTIVE_FIRM_FIRM_DISTANCE:
			return true
	return false


static func take_lair(lair: Firm, nid: int) -> bool:
	if not can_take_lair(lair, nid):
		return false
	var n := Game.inst.nation(nid)
	n.add_cash(-take_lair_cost(lair), "Grants")
	lair.change_nation(nid)
	for u in Espionage.occupants(lair):
		u.loyalty = 60.0
	Game.inst.update_links()
	if nid == Game.inst.player_id:
		Game.inst.notify("The %s now serves you." % lair.display_name(), lair.center_loc())
	return true


# ------------------------------------------------------------ daily ---

static func next_day(f: Firm, day: int) -> void:
	match f.code:
		"BEE", "TERMITE":
			_build_unit(f, false)
		"INCUBAT":
			_build_unit(f, true)
		"ANIMAL":
			if day % ANIMAL_UPDATE_INTERVAL == f.obj_id % ANIMAL_UPDATE_INTERVAL:
				_update_animals(f)
		"ALCHEMY":
			if day % Defs.PROCESS_GOODS_INTERVAL == f.obj_id % Defs.PROCESS_GOODS_INTERVAL:
				_alchemy(f)
		"WLISHORR":
			_wild_lishorr(f, day)
	if is_spell_firm(f.code):
		# FirmMagic::next_day: the charge builds while the building is unhurt
		if f.cast_charge < Defs.MAX_CAST_DELAY and f.hp >= f.max_hp * 0.999:
			f.cast_charge += 1
		var n := f.nation()
		if n == null or n.is_ai:
			auto_cast(f)


## Units a training ground or the Vapngart can make, given the kingdom's techs.
static func buildable_units(f: Firm) -> Array:
	var n := f.nation()
	var list: Array = INCUBATE_UNITS if f.code == "INCUBAT" else TRAIN_UNITS.get(f.code, [])
	if n == null:
		return []
	return list.filter(func(s): return n.tech_level(Defs.unit_tech(s)) > 0 and Assets.has_sprite(s))


static func unit_price(sprite: String) -> Array:
	var ut: Dictionary = Defs.unit_types.get(sprite, {})
	return [float(ut.get("cost", 100)), float(ut.get("live_cost", 0))]


## FirmMonsterTrain::basic_train / FirmIncubator::process_build: one unit at a
## time; its gold and life points are paid when the work starts.
static func _build_unit(f: Firm, weapon: bool) -> void:
	var n := f.nation()
	if f.weapon == "" or n == null:
		return
	if f.weapon_progress <= 0.0:
		var price := unit_price(f.weapon)
		if n.cash < price[0] or n.live_points < price[1]:
			return
		n.add_cash(-price[0], "Training")
		n.live_points -= price[1]
		f.weapon_progress = 0.01
	var days := float(Defs.unit_types.get(f.weapon, {}).get("build_days", 30))
	f.weapon_progress += 100.0 / maxf(1.0, days)
	if f.weapon_progress < 100.0:
		return
	f.weapon_progress = 0.0
	var c := Game.inst.exit_cell(f.footprint(), f.door())
	var u := Game.inst.spawn_unit(f.weapon, f.nation_id, c, 20.0 if not weapon else 30.0)
	f.send_to_rally(u)
	if u:
		u.loyalty = float(70 + Game.inst.rng.randi_range(0, 19))
		if f.nation_id == Game.inst.player_id and not Game.inst.observer():
			Game.inst.notify("%s ready." % u.type_name(), f.center_loc())
	f.weapon_queue -= 1
	if f.weapon_queue <= 0:
		f.weapon_queue = 0
		f.weapon = ""


# --------------------------------------------------------- Keraal ---

## FirmAnimal::update_add_hire_list / update_del_hire_list: wild beasts of the
## kinds the kingdom has tamed come to the Keraal and leave after a while.
static func _update_animals(f: Firm) -> void:
	var n := f.nation()
	if n == null:
		return
	var rng := Game.inst.rng
	for a in f.animals:
		a["days"] -= ANIMAL_UPDATE_INTERVAL
	f.animals = f.animals.filter(func(a): return a["days"] > 0)
	if f.animals.size() >= MAX_ANIMAL_UNIT:
		return
	var kinds := ANIMAL_UNITS.filter(func(s): return n.tech_level(Defs.unit_tech(s)) > 0 and Assets.has_sprite(s))
	if kinds.is_empty():
		return
	var sprite: String = kinds[rng.randi() % kinds.size()]
	var lvl := n.tech_level(Defs.unit_tech(sprite))
	# level 1: combat 20-30; level 2: 50-100 (FirmAnimal::add_animal_unit)
	var cmb := float(rng.randi_range(20, 30)) if lvl <= 1 else float(rng.randi_range(50, 100))
	var price := unit_price(sprite)
	f.animals.append({"unit": sprite, "combat": cmb, "cost": price[0] * (1.0 + cmb / 100.0), "live": price[1], "days": 120})


static func can_hire_animal(f: Firm, i: int) -> bool:
	var n := f.nation()
	if n == null or i < 0 or i >= f.animals.size():
		return false
	var a: Dictionary = f.animals[i]
	return n.tech_level(Defs.unit_tech(a["unit"])) > 0 and n.cash >= a["cost"] and n.live_points >= a["live"]


static func hire_animal(f: Firm, i: int) -> Unit:
	if not can_hire_animal(f, i):
		return null
	var n := f.nation()
	var a: Dictionary = f.animals[i]
	var c := Game.inst.exit_cell(f.footprint(), f.door())
	var u := Game.inst.spawn_unit(a["unit"], f.nation_id, c, a["combat"])
	if u == null:
		return null
	f.send_to_rally(u)
	n.add_cash(-a["cost"], "Hiring")
	n.live_points -= a["live"]
	u.loyalty = clampf(30.0 + n.reputation / 2.0, 40.0, 100.0)
	f.animals.remove_at(i)
	return u


# ---------------------------------------------------- Alchemist Tor ---

static func can_convert(f: Firm, mode: String) -> bool:
	var n := f.nation()
	if n == null or n.tech_level(mode) <= 0:
		return false
	if mode.begins_with("MINE"):
		return f.site != null and f.reserve > 0.0
	return true


## FirmMonsterAlchemy::produce_raw: every few days up to 60 units are
## converted (half that before Advanced Alchemy): two life points or gold
## make one of the other; a unit of raw material makes 0.2 life or 0.4 gold.
static func _alchemy(f: Firm) -> void:
	var n := f.nation()
	if n == null or f.alchemy_mode == "" or not can_convert(f, f.alchemy_mode):
		return
	var adv := Defs.tech_def("ALCHEMY")
	var maxl := float(adv.get("max", 2))
	var consume := ALCHEMY_MAX_CONSUME * (maxl + n.tech_level("ALCHEMY")) / (maxl * 2.0)
	var gold := 0.0
	var live := 0.0
	match f.alchemy_mode:
		"LIVEGOLD":
			if n.live_points >= consume:
				live = -consume
				gold = consume * 0.5
		"GOLDLIVE":
			if n.cash >= consume:
				gold = -consume
				live = consume * 0.5
		"MINELIVE", "MINEGOLD":
			var raw := minf(consume, f.reserve)
			f.reserve -= raw
			if f.site:
				f.site.reserve = f.reserve
			if f.alchemy_mode == "MINELIVE":
				live = raw * 0.2
			else:
				gold = raw * 0.4
			if f.reserve <= 0.0 and f.site:
				f.site.mine = null
				f.site = null
				if f.nation_id == Game.inst.player_id:
					Game.inst.notify("The deposit under the %s is exhausted." % f.display_name(), f.center_loc())
	if gold != 0.0:
		n.add_cash(gold, "Conversion")
	if live != 0.0:
		n.live_points = maxf(0.0, n.live_points + live)
	f.stock += maxf(gold, 0.0) + maxf(live, 0.0)     # produced this year, for the panel


# -------------------------------------------------------- Lishorr ---

## FirmLishorr::bullet_damage (GAME_VERSION > 101): stronger with the Lishorr
## technology and twice as strong under a clear sky.
static func lishorr_damage(f: Firm) -> float:
	var clear := Game.inst.weather.rain_scale() <= 0
	var n := f.nation()
	if n and n.is_fryhtan:
		var shift := 2 if clear else 1
		return LISHORR_BULLET_DAMAGE * (6 + (n.tech_level("LISHORR") << shift)) / 4.0
	return LISHORR_BULLET_DAMAGE * 2.0 * (2.0 if clear else 1.0)


## A Wilde Lishorr turns wild once grown and spreads in February and July
## (FirmLishorr::process_monster_firm).
static func _wild_lishorr(f: Firm, _day: int) -> void:
	var g := Game.inst
	if f.nation_id != GameObj.MONSTER_NATION:
		var old := f.nation_id
		f.change_nation(GameObj.MONSTER_NATION)
		if old == g.player_id:
			g.notify("The Wilde Lishorr has gone wild.", f.center_loc())
		return
	if f.propagate <= 0:
		return
	var month := g.month()
	if month != 2 and month != 7:
		return
	var chance := 1500
	for o in g.firms:
		if o.code == "WLISHORR":
			chance += 10
	var t := maxi(1, g.weather.base_temp() >> 2)
	if g.rng.randi_range(0, chance - 1) >= t:
		return
	for k in 12:
		var at := Vector2i(f.x1 + g.rng.randi_range(-6, 6), f.y1 + g.rng.randi_range(-6, 6))
		if g.world.can_place(at.x, at.y, f.w, f.h) and not g._overlaps_site(Rect2i(at, Vector2i(f.w, f.h))):
			var nf := g.spawn_firm("WLISHORR", GameObj.MONSTER_NATION, "", at, true)
			if nf:
				f.propagate -= 1
			return


# ------------------------------------------------------- camouflage ---

## FirmLishorr::is_visible / FirmMonsterFortress::is_visible: a camouflaged
## Lishorr or Fortress looks like a plant or a rock to other kingdoms until it fires.
static func hidden_from(f: Firm, nid: int) -> bool:
	if nid == f.nation_id or f.under_construction or Game.inst.frame < f.shown_until:
		return false
	var n := f.nation()
	match f.code:
		"WLISHORR":
			return true
		"LISHORR":
			return n == null or n.tech_level("LISH_CAM") > 0
		"FORTRESS":
			return n != null and n.tech_level("FORT_CAM") > 0
	return false


# --------------------------------------------------------- Fortress ---

## Four Grokkens side by side may turn into a Fortress (FirmMonsterFortress::
## check_transform_from_units); returns where it would stand, or (-1, -1).
static func fortress_spot(units: Array) -> Vector2i:
	var grok := units.filter(func(u): return u is Unit and not u.dead and u.inside_firm == null and u.sprite_code == Defs.FORTRESS_BUILDER)
	if grok.size() < FORTRESS_BUILDERS:
		return Vector2i(-1, -1)
	var nid: int = grok[0].nation_id
	var n := Game.inst.nation(nid)
	if n == null or n.tech_level("FORTRESS") <= 0 or grok.any(func(u): return u.nation_id != nid):
		return Vector2i(-1, -1)
	grok = grok.slice(0, FORTRESS_BUILDERS)
	var c := Vector2.ZERO
	for u in grok:
		c += u.center_loc()
	c /= grok.size()
	for u in grok:
		if u.center_loc().distance_to(c) > 4.0:
			return Vector2i(-1, -1)     # they must stand together
	var b := Assets.firm_build("FORTRESS", "")
	var w: int = b.get("loc_w", 4)
	var h: int = b.get("loc_h", 4)
	var g := Game.inst
	var base := Vector2i(floori(c.x - w / 2.0), floori(c.y - h / 2.0))
	for r in 3:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var at := base + Vector2i(dx, dy)
				if _fortress_fits(at, w, h, grok) and not g._overlaps_site(Rect2i(at, Vector2i(w, h))):
					return at
	return Vector2i(-1, -1)


static func _fortress_fits(at: Vector2i, w: int, h: int, builders: Array) -> bool:
	var world := Game.inst.world
	for y in range(at.y, at.y + h):
		for x in range(at.x, at.x + w):
			var c := Vector2i(x, y)
			if not world.inside(c) or world.object_at(c) != null or not world.is_walkable(c):
				return false
	for u in Game.inst.units:
		if not u.dead and u.inside_firm == null and not u in builders and Rect2i(at, Vector2i(w, h)).has_point(u.cell()):
			return false
	return true


static func transform_to_fortress(units: Array) -> Firm:
	var at := fortress_spot(units)
	if at.x < 0:
		return null
	var grok := units.filter(func(u): return u is Unit and not u.dead and u.inside_firm == null and u.sprite_code == Defs.FORTRESS_BUILDER).slice(0, FORTRESS_BUILDERS)
	var nid: int = grok[0].nation_id
	var n := Game.inst.nation(nid)
	var cost := float(Defs.firm_types.get("FORTRESS", {}).get("cost", 50))
	if n.cash < cost:
		return null
	var f := Game.inst.spawn_firm("FORTRESS", nid, "", at, true)
	if f == null:
		return null
	n.add_cash(-cost, "Construction")
	# FirmMonsterFortress::init_derived: hit points grow with the tech level
	f.max_hp *= 0.75 + 0.25 * n.tech_level("FORTRESS")
	f.hp = f.max_hp
	for u in grok:
		f.extra_units.append(u)
		f._hide_unit(u)
	return f


## FirmMonsterFortress::process_scan_target: the Fryhtans posted in a fortress
## shoot at enemies within eight cells. A Grokken inside fires as if 25 combat
## levels higher.
static func fortress_shoot(f: Firm) -> void:
	var g := Game.inst
	var target: Unit = null
	var best := FORTRESS_RANGE + maxf(f.w, f.h) / 2.0
	for u in g.units_near(f.center_loc(), best + 1.0):
		if u.dead or u.inside_firm or u.has_meta("hidden") or u.hidden_from(f.nation_id) or not g.is_hostile(f, u):
			continue
		var d := f.distance_to(u)
		if d <= FORTRESS_RANGE and d < best:
			best = d
			target = u
	if target == null:
		return
	var fired := false
	for a in f.soldiers:
		if a.attack_cooldown > 0:
			a.attack_cooldown -= f.FORTRESS_TICK
			continue
		var bonus := 25.0 if a.sprite_code == Defs.FORTRESS_BUILDER else 0.0
		var att: Dictionary = {}
		for x in a.attack_list():
			if x["range"] > 1 and x["combat_lvl"] <= a.combat_level() + bonus and (att.is_empty() or x["damage"] > att["damage"]):
				att = x
		if att.is_empty():
			continue
		var spr: String = att["bullet"] if att["bullet"] != "" and Assets.has_sprite(att["bullet"]) else "NO_ARROW"
		var dmg := float(att["damage"]) + float(att["pierce"]) * minf(a.combat_level() + bonus, 100.0) / 200.0
		g.spawn_town_arrow(f, target, spr, dmg)
		a.attack_cooldown = int(att["delay"]) * 2
		fired = true
	if fired:
		f.shown_until = g.frame + SHOWN_AFTER_FIRING


# ----------------------------------------------------------- spells ---

static func spell_def(sp: String) -> Dictionary:
	return Defs.SPELLS.get(sp, {})


## A spell aimed at the building itself (range 0: Preuser, Archimedetron).
static func self_aimed(sp: String) -> bool:
	return int(spell_def(sp).get("range", 0)) == 0 and sp != "TELEPORT"


## FirmMagic::calc_live_point_cost / calc_cash_cost: [life points, gold].
static func spell_price(f: Firm, sp: String, at: Vector2, unit: Unit = null) -> Array:
	var d := spell_def(sp)
	var rng := float(d["range"])
	var extra := maxf(0.0, f.center_loc().distance_to(at) - rng) if rng > 0 else 0.0
	if unit:
		extra += maxf(0.0, unit.center_loc().distance_to(at) - rng)
	extra = floorf(extra)
	return [float(d["live"]) + float(d["extra_live"]) * extra, float(d["cost"]) + float(d["extra_cost"]) * extra]


## FirmMagic::can_cast: full charge, the spell researched and its minimum price.
static func can_cast(f: Firm, sp: String) -> bool:
	if f.under_construction or f.dead or f.cast_charge < Defs.MAX_CAST_DELAY:
		return false
	if not sp in Defs.FIRM_SPELLS.get(f.code, []):
		return false
	var d := spell_def(sp)
	var n := f.nation()
	if n == null:
		return f.nation_id == GameObj.MONSTER_NATION or f.nation_id == 0
	if d["tech"] != "" and n.tech_level(d["tech"]) <= 0:
		return false
	return n.live_points >= float(d["live"]) and n.cash >= float(d["cost"])


static func _enemy(f: Firm, o: GameObj) -> bool:
	if o == null or o.dead or o.nation_id == f.nation_id:
		return false
	if o is Unit and ((o as Unit).inside_firm != null or o.has_meta("hidden")):
		return false
	if o.nation_id == 0 or o.is_monster() or f.is_monster():
		return true
	return Game.inst.is_hostile(f, o)


## FirmMagic::cast_magic plus process_delayed_magic, applied at once.
## `at` is the target location; `unit` the unit to teleport.
static func cast(f: Firm, sp: String, at: Vector2, unit: Unit = null) -> bool:
	if not can_cast(f, sp):
		return false
	var g := Game.inst
	var d := spell_def(sp)
	if self_aimed(sp):
		at = f.center_loc()
	var price := spell_price(f, sp, at, unit)
	var n := f.nation()
	if n and (n.live_points < price[0] or n.cash < price[1]):
		return false
	var ok := false
	var radius := float(d["radius"])
	match sp:
		"DESTROY":
			var o = g.world.object_at(Vector2i(floori(at.x), floori(at.y)))
			if o is Firm and _enemy(f, o):
				var tf := o as Firm
				tf.on_attacked(f)
				tf.hp -= tf.max_hp * float(d["effect"]) / 100.0
				if tf.hp <= 0.0:
					tf.hp = 0.0
					tf.die(f)
				ok = true
			elif o is Town and _enemy(f, o):
				_blast_town(f, o as Town, float(d["effect"]))
				ok = true
		"FREEZE", "FREEZE_LASER":
			for u in _units_in(at, radius):
				if _enemy(f, u):
					u.frozen_until = maxi(u.frozen_until, g.frame + int(d["effect"]) * Defs.FRAMES_PER_DAY)
			ok = true
		"WOUND", "LASER", "GOD_POWER":
			var dmg := float(d["effect"]) * SPELL_DAMAGE_SCALE
			for u in _units_in(at, radius):
				if _enemy(f, u):
					u.take_damage(dmg, f)
			if sp == "GOD_POWER":
				for o in g.firms + g.towns:
					if _enemy(f, o) and _rect_near(o.footprint(), at, radius):
						o.take_damage(dmg, f)
			ok = true
		"TELEPORT":
			if unit and not unit.dead and unit.nation_id == f.nation_id and unit.inside_firm == null:
				var c := g.world.nearest_walkable(Vector2i(floori(at.x), floori(at.y)), 3)
				if c.x >= 0:
					unit.stop()
					unit.loc = Vector2(c)
					unit.position = Iso.to_screen(unit.loc)
					ok = true
	if not ok:
		return false
	if n:
		n.live_points -= price[0]
		n.add_cash(-price[1], "Weapons")
	f.cast_charge -= int(d["delay"])
	f.shown_until = g.frame + SHOWN_AFTER_FIRING
	g.spawn_effect(1, at - Vector2(0.5, 0.5))
	g.play_sound("F", f.code, "A1", f.center_loc())
	return true


static func _blast_town(f: Firm, t: Town, effect: float) -> void:
	t.on_attacked(f)
	var hit := t.wall_max_hp() * effect / 100.0 if t.wall_level > 0 else 0.0
	var pct := effect
	if t.wall_level > 0 and t.wall_hp > 0.0:
		if t.wall_hp >= hit:
			t.wall_hp -= hit
			pct = 0.0
		else:
			pct -= t.wall_hp * effect / maxf(1.0, hit)
			t.wall_hp = 0.0
	var kill := int(t.population * pct / 100.0)
	t.population = maxi(0, t.population - kill)
	t._check_empty()
	t.queue_redraw()


static func _units_in(at: Vector2, radius: float) -> Array:
	var out := []
	for u in Game.inst.units:     # spells are rare: a full scan also sees units made this frame
		if u.dead or u.inside_firm:
			continue
		var c: Vector2 = u.center_loc()
		if absf(c.x - at.x) <= radius + 0.5 and absf(c.y - at.y) <= radius + 0.5:
			out.append(u)
	return out


static func _rect_near(r: Rect2i, at: Vector2, radius: float) -> bool:
	return Rect2(r).grow(radius).has_point(at)


## Computer-run (and ownerless) spell buildings cast at the thickest group of
## enemies in reach, and the Mage Tor at an enemy building (FirmMagic::process_ai).
static func auto_cast(f: Firm) -> void:
	if f.cast_charge < Defs.MAX_CAST_DELAY or f.under_construction:
		return
	var g := Game.inst
	for sp in Defs.FIRM_SPELLS.get(f.code, []):
		if not can_cast(f, sp) or sp == "TELEPORT":
			continue
		var d := spell_def(sp)
		if sp == "DESTROY":
			var best: GameObj = null
			var bd := float(d["range"])
			for o in g.firms + g.towns:
				if _enemy(f, o) and not (o is Town and o.nation_id == 0):
					var dd := f.distance_to(o)
					if dd < bd:
						bd = dd
						best = o
			if best and cast(f, sp, best.center_loc()):
				return
			continue
		var reach := float(d["range"]) if not self_aimed(sp) else 0.0
		var radius := float(d["radius"])
		var best_at := Vector2(-1, -1)
		var best_n := 1 if sp == "FREEZE" else 2
		for u in g.units:
			if not _enemy(f, u) or f.center_loc().distance_to(u.center_loc()) > maxf(reach, radius) + 2.0:
				continue
			var at: Vector2 = u.center_loc() if reach > 0 else f.center_loc()
			if reach > 0 and f.center_loc().distance_to(at) > reach:
				continue
			var cnt := 0
			for v in _units_in(at, radius):
				if _enemy(f, v):
					cnt += 1
				elif v.nation_id == f.nation_id:
					cnt -= 1
			if cnt > best_n:
				best_n = cnt
				best_at = at
			if reach <= 0:
				break
		if best_at.x >= 0 and cast(f, sp, best_at):
			return
