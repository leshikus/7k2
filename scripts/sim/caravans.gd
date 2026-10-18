class_name Caravans
extends RefCounted
## Caravans (ou_cara.cpp, ou_carat.cpp, ou_caras.cpp, ou_caraa.cpp): up to two
## stops - markets of its own kingdom or of one with a trade treaty, its own
## mines and factories - each with what to pick up there: automatically
## (markets: whatever is above 100 in stock and was not just unloaded), none,
## or chosen goods. At a stop it unloads what the place takes, loads, goes in
## for a moment and sets out for the other stop. With a single stop it waits
## by it and unloads now and then. Hiring is free; a kingdom keeps one caravan
## for every ten people (FirmMarket::can_hire_caravan).

const MAX_STOPS := 2
const CARRY := 200.0                   # MAX_CARAVAN_CARRY_QTY
const WAIT_TERM := 8                   # MAX_CARAVAN_WAIT_TERM (frames inside a stop)
const SURROUND_WAIT := 80              # WAIT_TERM x SURROUND_FIRM_WAIT_FACTOR
const MIN_FIRM_STOCK := 100.0          # MIN_FIRM_STOCK_QTY: auto loading leaves this much
const POPULATION_PER_CARAVAN := 10


## Pick-up keys: "R:<raw>" for raw materials, "P:<raw>" for goods made of it.
static func goods_keys() -> Array:
	var out: Array = []
	for r in Economy.raw_types():
		out.append("R:" + r)
	for r in Economy.raw_types():
		out.append("P:" + r)
	return out


static func key_name(k: String) -> String:
	return (k.substr(2) + " goods") if k.begins_with("P:") else k.substr(2)


# --------------------------------------------------------------- hiring ---

static func count(g: Game, nid: int) -> int:
	return g.units.filter(func(u): return u.is_caravan and not u.dead and u.nation_id == nid).size()


## FirmMarket::can_hire_caravan: how many more the kingdom can support.
static func can_hire(m: Firm) -> int:
	var g := Game.inst
	var n := m.nation()
	if n == null or n.cash < 0.0 or m.under_construction or m.code != "MARKET":
		return 0
	var pop := 0
	for t in g.towns:
		if t.nation_id == n.id and not t.dead:
			pop += t.population
	var supported := maxi(1, pop / POPULATION_PER_CARAVAN)
	return maxi(0, supported - count(g, n.id))


## FirmMarket::hire_caravan: loyal, its first stop the market itself.
static func hire(m: Firm) -> Unit:
	if can_hire(m) <= 0 or not Assets.has_sprite("CARAVAN"):
		return null
	var g := Game.inst
	var c := g.exit_cell(m.footprint(), m.door())
	var u := g.spawn_unit("CARAVAN", m.nation_id, c, 10.0)
	if u:
		u.loyalty = 100.0
		set_stop(u, 0, m)
	return u


# ---------------------------------------------------------------- stops ---

## UnitCaravan::can_set_stop
static func can_set_stop(u: Unit, f: Firm) -> bool:
	if f == null or f.dead or f.under_construction:
		return false
	match f.code:
		"MARKET":
			var n := u.nation()
			return f.nation_id == u.nation_id or (n != null and n.trade_treaty.has(f.nation_id))
		"MINE", "FACTORY":
			return f.nation_id == u.nation_id
	return false


## UnitCaravan::set_stop: stop `i` (0 or 1) becomes `f`; a mine picks up its
## raw material, a factory its goods, a market by the caravan's market mode.
static func set_stop(u: Unit, i: int, f: Firm) -> bool:
	if i < 0 or i >= MAX_STOPS or not can_set_stop(u, f):
		return false
	for s in u.stops:
		if s["firm"] == f:
			return false
	var st := {"firm": f, "x": f.x1, "y": f.y1, "pick": "none", "picks": []}
	match f.code:
		"MINE":
			if f.raw != "":
				st["pick"] = "sel"
				st["picks"] = ["R:" + f.raw]
		"FACTORY":
			if f.raw != "":
				st["pick"] = "sel"
				st["picks"] = ["P:" + f.raw]
		"MARKET":
			st["pick"] = "auto" if u.market_auto else "sel"
	var old_dest: Firm = u.stops[u.dest_stop]["firm"] if u.dest_stop >= 0 and u.dest_stop < u.stops.size() else null
	while u.stops.size() <= i:
		u.stops.append({})
	u.stops[i] = st
	update_stops(u)
	if u.dest_stop < 0 and not u.stops.is_empty():
		u.dest_stop = 0
	if u.dest_stop >= 0 and u.stops[u.dest_stop]["firm"] != old_dest:
		u.journey = "on_way"
		_go(u, u.stops[u.dest_stop]["firm"])
	return true


static func del_stop(u: Unit, i: int) -> void:
	if i >= 0 and i < u.stops.size():
		u.stops[i] = {}
		update_stops(u)


## UnitCaravan::update_stop_list: gone or moved places, places it can no
## longer trade at and repeats are dropped; with no place of its own kingdom
## left, all are.
static func update_stops(u: Unit) -> void:
	var next: Firm = u.stops[u.dest_stop].get("firm") if u.dest_stop >= 0 and u.dest_stop < u.stops.size() else null
	var kept: Array = []
	for s in u.stops:
		if s.is_empty():
			continue
		var f: Firm = s["firm"]
		if not is_instance_valid(f) or f.dead or not can_set_stop(u, f) or f.x1 != s["x"] or f.y1 != s["y"]:
			continue
		if not kept.is_empty() and kept[-1]["firm"] == f:
			continue
		kept.append(s)
	if kept.size() > 1 and kept[0]["firm"] == kept[-1]["firm"]:
		kept.pop_back()
	if not kept.any(func(s): return s["firm"].nation_id == u.nation_id):
		kept.clear()
	u.stops = kept
	if kept.is_empty():
		u.dest_stop = -1
		u.journey = "none"
		return
	u.dest_stop = 0
	var best_d := INF
	for i in kept.size():
		if kept[i]["firm"] == next:
			u.dest_stop = i
			return
		var d: float = u.center_loc().distance_to(kept[i]["firm"].center_loc())
		if d < best_d:
			best_d = d
			u.dest_stop = i


## UnitCaravan::set_stop_pick_up: "auto", "none", or a goods key to toggle.
static func set_pick_up(u: Unit, i: int, what: String) -> void:
	if i < 0 or i >= u.stops.size():
		return
	var st: Dictionary = u.stops[i]
	match what:
		"auto":
			st["pick"] = "auto"
		"none":
			st["pick"] = "none"
			st["picks"] = []
		_:
			var picks: Array = st["picks"]
			if what in picks:
				picks.erase(what)
			else:
				picks.append(what)
			st["pick"] = "sel" if not picks.is_empty() or st["firm"].code == "MARKET" else "none"
			if picks.is_empty():
				st["pick"] = "none"
			if st["firm"].code == "MARKET":
				u.market_auto = false        # default_market_trade_mode: manual from now on


## CaravanStop::update_pick_up: a mine or factory offers only what it makes.
static func _update_pick_up(st: Dictionary) -> void:
	var f: Firm = st["firm"]
	if f.code == "MINE" or f.code == "FACTORY":
		var k := ("R:" if f.code == "MINE" else "P:") + f.raw
		if f.raw == "" or not k in st["picks"]:
			st["pick"] = "none"
			st["picks"] = []


# ------------------------------------------------------------- per frame ---

static func think(u: Unit) -> void:
	var g := Game.inst
	if u.stops.is_empty():
		# a caravan with nowhere to go must not sit on a deposit
		if u.nation_id > 0 and g.sites.any(func(s): return Rect2i(s.x1, s.y1, s.w, s.h).has_point(u.cell())):
			var n := u.nation()
			if n:
				n.change_reputation(-0.02)
		u.journey = "none"
		return
	if u.stops.size() == 1:
		_single_stop(u)
		return
	if u.journey == "inside":
		_in_firm(u)
	else:
		_on_way(u)


static func _near(u: Unit, f: Firm) -> bool:
	var c := u.cell()
	return c.x >= f.x1 - 1 and c.x <= f.x1 + f.w and c.y >= f.y1 - 1 and c.y <= f.y1 + f.h


static func _go(u: Unit, f: Firm) -> void:
	u.order_move_free(Game.inst.world.adjacent_to_rect(f.footprint(), u.cell()))


static func _treaty(u: Unit, f: Firm) -> bool:
	var n := u.nation()
	return f.nation_id == u.nation_id or (n != null and n.trade_treaty.has(f.nation_id))


static func _single_stop(u: Unit) -> void:
	var st: Dictionary = u.stops[0]
	var f: Firm = st["firm"]
	if not is_instance_valid(f) or f.dead or f.x1 != st["x"] or f.y1 != st["y"]:
		update_stops(u)
		return
	if not _near(u, f):
		if u.order == Unit.Order.IDLE:
			_go(u, f)
		u.journey = "on_way"
		return
	u.journey = "surround"
	if _treaty(u, f):
		if u.wait <= 0:
			u.dest_stop = 0
			if f.code == "FACTORY":
				_factory_unload(u, f)
			elif f.code == "MARKET":
				_market_unload(u, f)
			u.wait = SURROUND_WAIT
		else:
			u.wait -= 1


## UnitCaravan::caravan_on_way: arriving by a stop it trades and goes in.
static func _on_way(u: Unit) -> void:
	if u.wait > 0:
		u.wait -= 1
		return
	var st: Dictionary = u.stops[u.dest_stop]
	var f: Firm = st["firm"]
	if not is_instance_valid(f) or f.dead:
		update_stops(u)
		if not u.stops.is_empty():
			_go(u, u.stops[u.dest_stop]["firm"])
		return
	if not _near(u, f):
		if u.order == Unit.Order.IDLE:
			_go(u, f)
			if u.path.is_empty() and not _near(u, f):
				u.wait = 60
		return
	_update_pick_up(st)
	if _treaty(u, f):
		var other_own := false
		for i in u.stops.size():
			if i != u.dest_stop and u.stops[i]["firm"].nation_id == u.nation_id:
				other_own = true
		u.processed = {}
		match f.code:
			"MINE":
				if other_own:
					_mine_load(u, f, st)
			"FACTORY":
				_factory_unload(u, f)
				if other_own:
					_factory_load(u, f, st)
			"MARKET":
				_market_unload(u, f)
				if other_own:
					if st["pick"] == "auto":
						_market_auto_load(u, f)
					elif st["pick"] != "none":
						_market_load(u, f, st)
	# it goes in for a while (deinit_sprite)
	u.stop()
	u.journey = "inside"
	u.wait = WAIT_TERM
	u.visible = false
	u.set_meta("hidden", true)
	Game.inst.deselect(u)


## UnitCaravan::caravan_in_firm: out again and on to the next stop; it dies
## with the building it is in.
static func _in_firm(u: Unit) -> void:
	var st: Dictionary = u.stops[u.dest_stop] if u.dest_stop >= 0 and u.dest_stop < u.stops.size() else {}
	var f: Firm = st.get("firm")
	if f == null or not is_instance_valid(f) or f.dead:
		u.remove_meta("hidden")
		u.die(null)
		return
	if u.wait > 0:
		u.wait -= 1
		return
	u.remove_meta("hidden")
	u.visible = true
	var c := Game.inst.exit_cell(f.footprint(), u.cell())
	u.loc = Vector2(c)
	u.position = Iso.to_screen(u.loc)
	var nxt := (u.dest_stop + 1) % u.stops.size()
	update_stops(u)
	if u.stops.is_empty():
		return
	if u.stops.size() == 1:
		u.dest_stop = 0
		u.journey = "surround"
		return
	u.dest_stop = mini(nxt, u.stops.size() - 1)
	u.journey = "on_way"
	_go(u, u.stops[u.dest_stop]["firm"])


# -------------------------------------------------------- loading goods ---

static func _qty(u: Unit, k: String) -> float:
	return float(u.cargo.get(k, 0.0))


static func _add(u: Unit, k: String, q: float) -> void:
	var v := _qty(u, k) + q
	if v > 0.001:
		u.cargo[k] = v
	else:
		u.cargo.erase(k)


## UnitCaravan::market_unload_goods: only at its own kingdom's market; each
## kind fills its place up to the market's stock limit.
static func _market_unload(u: Unit, m: Firm) -> void:
	u.processed = {}
	if m.nation_id != u.nation_id:
		return
	for k in u.cargo.keys():
		var r := String(k).substr(2)
		var store: Dictionary = m.raws if String(k).begins_with("R:") else m.goods
		var cur := float(store.get(r, 0.0))
		var q := minf(_qty(u, k), Economy.MAX_STOCK - cur)
		if q > 0.0:
			store[r] = cur + q
			_add(u, k, -q)
			u.processed[k] = 2
		elif _qty(u, k) > 0.0:
			u.processed[k] = 1


## UnitCaravan::market_auto_load_goods: everything above 100 that it did not
## just bring.
static func _market_auto_load(u: Unit, m: Firm) -> void:
	for k in goods_keys():
		if int(u.processed.get(k, 0)) == 2:
			continue
		var stock := float((m.raws if k.begins_with("R:") else m.goods).get(k.substr(2), 0.0))
		if stock > MIN_FIRM_STOCK:
			_load_now(u, m, k, stock - MIN_FIRM_STOCK)


## UnitCaravan::market_load_goods: all of the chosen kinds.
static func _market_load(u: Unit, m: Firm, st: Dictionary) -> void:
	for k in st["picks"]:
		var stock := float((m.raws if k.begins_with("R:") else m.goods).get(String(k).substr(2), 0.0))
		if stock > 0.0:
			_load_now(u, m, k, stock)


## UnitCaravan::market_load_goods_now: bought when the market is another kingdom's.
static func _load_now(u: Unit, m: Firm, k: String, want: float) -> void:
	var raw := k.begins_with("R:")
	var q := floorf(minf(CARRY - _qty(u, k), want))
	if q <= 0.0:
		return
	if m.nation_id != u.nation_id:
		var n := u.nation()
		var price := Defs.RAW_PRICE if raw else Defs.PRODUCT_PRICE
		q = floorf(minf(q, maxf(0.0, n.cash) / price)) if n and n.cash > 0.0 else 0.0
		if q > 0.0:
			n.import_goods(m.nation_id, q * price)
	if q <= 0.0:
		return
	var store: Dictionary = m.raws if raw else m.goods
	store[k.substr(2)] = float(store.get(k.substr(2), 0.0)) - q
	_add(u, k, q)
	u.last_load_day = Game.inst.day


## UnitCaravan::mine_load_goods: at its own mine; chosen goods all, else above 100.
static func _mine_load(u: Unit, f: Firm, st: Dictionary) -> void:
	if st["pick"] == "none" or f.nation_id != u.nation_id or f.raw == "":
		return
	var k := "R:" + f.raw
	if st["pick"] != "auto" and not k in st["picks"]:
		return
	var avail := f.stock if st["pick"] != "auto" else maxf(0.0, f.stock - MIN_FIRM_STOCK)
	var q := floorf(minf(CARRY - _qty(u, k), avail))
	if q > 0.0:
		f.stock -= q
		_add(u, k, q)
	if avail > 0.0:
		u.last_load_day = Game.inst.day


## UnitCaravan::factory_unload_goods: raw material for what it makes; an idle,
## empty factory takes up the caravan's only raw material.
static func _factory_unload(u: Unit, f: Firm) -> void:
	if f.nation_id != u.nation_id:
		return
	if f.stock <= 0.0 and f.raw_stock <= 0.0 and f.last_month_output <= 0.0 and f.month_output <= 0.0:
		var raws: Array = u.cargo.keys().filter(func(k): return String(k).begins_with("R:"))
		if raws.size() == 1:
			Economy.set_production(f, String(raws[0]).substr(2))
	var k := "R:" + f.raw
	if f.raw != "" and _qty(u, k) > 0.0:
		var q := minf(_qty(u, k), Economy.MAX_STOCK - f.raw_stock)
		_add(u, k, -q)
		f.raw_stock += q


static func _factory_load(u: Unit, f: Firm, st: Dictionary) -> void:
	if st["pick"] == "none" or f.nation_id != u.nation_id or f.raw == "":
		return
	var k := "P:" + f.raw
	if st["pick"] != "auto" and not k in st["picks"]:
		return
	var avail := f.stock if st["pick"] != "auto" else maxf(0.0, f.stock - MIN_FIRM_STOCK)
	var q := floorf(minf(CARRY - _qty(u, k), avail))
	if q > 0.0:
		f.stock -= q
		_add(u, k, q)
	if avail > 0.0:
		u.last_load_day = Game.inst.day


# ------------------------------------------------------------ duplicate ---

## UnitCaravan::can_duplicate_caravan / duplicate_caravan: hired at a market
## of its route (or one linked to a mine or factory of it), with its stops.
static func duplicate_market(u: Unit) -> Firm:
	for s in u.stops:
		var f: Firm = s["firm"]
		if not is_instance_valid(f) or f.nation_id != u.nation_id:
			continue
		if f.code == "MARKET":
			if can_hire(f) > 0:
				return f
		else:
			for o in f.linked_firms:
				if o.nation_id == u.nation_id and o.code == "MARKET" and can_hire(o) > 0:
					return o
	return null


static func duplicate_of(u: Unit) -> Unit:
	var m := duplicate_market(u)
	if m == null:
		return null
	var c := hire(m)
	if c == null:
		return null
	c.market_auto = u.market_auto
	c.stops = []
	for s in u.stops:
		var st: Dictionary = s.duplicate(true)
		c.stops.append(st)
	c.dest_stop = 0
	c.journey = "on_way"
	_go(c, c.stops[0]["firm"])
	return c


# ------------------------------------------------------------------- AI ---

## UnitCaravan::process_ai
static func process_ai(u: Unit, day: int) -> void:
	if u.has_meta("hidden"):
		return
	if day % 30 == u.obj_id % 30:
		if _think_del_stop(u):
			return
		_think_pick_up(u)
	_think_resign(u, day)


static func _think_resign(u: Unit, day: int) -> void:
	if u.stops.size() < 2:
		u.die(null)
		return
	if day % 30 != u.obj_id % 30:
		return
	if day > u.last_load_day + 365 and u.cargo.is_empty():
		u.die(null)
		return
	for s in u.stops:
		var f: Firm = s["firm"]
		if f.code != "MARKET":
			return
		if f.last_month_supply.values().any(func(v): return v > 0.0) or f.month_supply.values().any(func(v): return v > 0.0):
			return
	u.die(null)


static func _think_del_stop(u: Unit) -> bool:
	var n := u.nation()
	for i in range(u.stops.size() - 1, -1, -1):
		var f: Firm = u.stops[i]["firm"]
		if not is_instance_valid(f) or f.dead or f.code != "MARKET" or not _treaty(u, f) \
				or (n and f.nation_id != u.nation_id and n.relation(f.nation_id) == Defs.Relation.WAR):
			del_stop(u, i)
			return true
	return false


## think_set_pick_up_type: between two markets, take goods one supplies and
## drop kinds no longer supplied.
static func _think_pick_up(u: Unit) -> void:
	if u.stops.size() < 2 or u.stops[0]["firm"].code != "MARKET" or u.stops[1]["firm"].code != "MARKET":
		return
	for pair in [[0, 1], [1, 0]]:
		var st: Dictionary = u.stops[pair[0]]
		var from: Firm = st["firm"]
		var to: Firm = u.stops[pair[1]]["firm"]
		if st["pick"] == "auto":
			continue
		for p in from.goods.keys():
			var supplied: float = float(from.month_supply.get(p, 0.0)) + float(from.last_month_supply.get(p, 0.0))
			if supplied > 0.0 and float(to.goods.get(p, 0.0)) <= 0.0 and not ("P:" + p) in st["picks"]:
				set_pick_up(u, pair[0], "P:" + p)
		for k in st["picks"].duplicate():
			var p2 := String(k).substr(2)
			var supplied2: float = float(from.month_supply.get(p2, 0.0)) + float(from.last_month_supply.get(p2, 0.0))
			if supplied2 <= 0.0:
				set_pick_up(u, pair[0], k)
