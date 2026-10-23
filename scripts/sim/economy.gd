class_name Economy
extends RefCounted
## The flow of goods (of_mine.cpp, of_fact.cpp, of_mark.cpp, otown.cpp
## distribute_demand): every three days a mine digs raw material and a factory
## makes goods; each passes its stock to the next linked building in turn
## (next_output_firm) that comes to take it - a factory from mines and from
## markets holding raw material, a market from mines and factories, 50 at a
## time. Markets keep raw materials and goods apart (a slot for each of the
## three of each) and sell goods to the towns linked to them, by the towns'
## monthly demand shared out every 15 days among the markets that supply them.

const MAX_STOCK := 500.0                 # DEFAULT_MINE_MAX_STOCK_QTY, factory stocks, MAX_MARKET_STOCK
const MARKET_INPUT := 50.0               # FirmMarket::input_goods(50)
const PEASANT_GOODS_MONTH_DEMAND := 0.5
const WORKER_GOODS_MONTH_DEMAND := 1.0


static func raw_types() -> Array:
	return Assets.table("RAW").slice(0, 3).map(func(r): return r["NAME"])


## Whether goods may pass between two buildings: a trade pair (mine, factory,
## market) over a link that both ends have on.
static func trade_link(a: Firm, b: Firm) -> bool:
	return not b.dead and not b.under_construction and Game.goods_linkable(a.code, b.code) and Game.inst.link_on(a, b)


## set_next_output_firm: the next linked building of the kinds it supplies.
static func next_output(f: Firm, kinds: Array) -> void:
	var lf := f.linked_firms
	f.next_output = null
	for i in lf.size():
		f._out_idx = (f._out_idx + 1) % maxi(1, lf.size())
		var o: Firm = lf[f._out_idx]
		if o.code in kinds and trade_link(f, o):
			f.next_output = o
			return


static func _import(buyer: Firm, seller: Firm, qty: float, price: float) -> float:
	if seller.nation_id == buyer.nation_id or seller.nation_id <= 0:
		return qty
	var n := buyer.nation()
	if n == null:
		return 0.0
	qty = minf(qty, maxf(0.0, n.cash) / price)
	if qty > 0.0:
		n.import_goods(seller.nation_id, qty * price)
	return qty


# ----------------------------------------------------------------- mine ---

## FirmMine::produce_raw: 100 x productivity of the deposit dug, half of it
## (and a quarter more a level of Advanced Mining) won.
static func mine_day(f: Firm) -> void:
	_produce_raw(f)
	next_output(f, ["FACTORY", "MARKET"])


static func _produce_raw(f: Firm) -> void:
	if f.site == null or f.reserve <= 0.0 or f.stock >= MAX_STOCK:
		return
	var n := f.nation()
	var yield_rate := 0.5 + (0.25 * n.tech_level("MINING") if n else 0.0)
	var raw_qty := 100.0 * f.productivity() / 100.0
	var produce := raw_qty * yield_rate
	if raw_qty > f.reserve:
		raw_qty = f.reserve
		produce = raw_qty * yield_rate
	if produce > MAX_STOCK - f.stock:
		produce = MAX_STOCK - f.stock
		raw_qty = produce / yield_rate
	f.reserve -= raw_qty
	f.stock += produce
	f.month_output += produce
	f.site.reserve = f.reserve
	if f.reserve <= 0.0:
		f.reserve = 0.0
		if f.nation_id == Game.inst.player_id:
			Game.inst.notify("A %s mine has run out of deposits." % f.raw, f.center_loc())


# -------------------------------------------------------------- factory ---

static func factory_day(f: Firm) -> void:
	if f.raw == "":
		auto_set_product(f)
		if f.raw == "":
			return
	_input_raw(f)
	if f.raw_stock <= 0.0 and f.auto_switch:
		var first := f.raw
		for i in raw_types().size():
			change_production(f)
			_input_raw(f)
			if f.raw_stock > 0.0 or f.raw == first:
				break
	_manufacture(f, 20.0 * f.productivity() / 100.0)
	next_output(f, ["MARKET"])


## FirmFactory::auto_set_product: the raw material of a linked mine (or market)
## no other factory there makes; otherwise the nearest.
static func auto_set_product(f: Firm) -> void:
	var best := ""
	var best_d := INF
	for o in f.linked_firms:
		if not trade_link(f, o):
			continue
		var raws: Array = []
		if o.code == "MINE" and o.raw != "":
			raws = [o.raw]
		elif o.code == "MARKET":
			raws = o.raws.keys().filter(func(r): return o.raws[r] > 0.0)
		for r in raws:
			var taken: bool = o.linked_firms.any(func(x): return x != f and x.code == "FACTORY" and x.raw == r and Game.inst.link_on(o, x))
			if not taken:
				f.raw = r
				return
			var d := f.center_loc().distance_to(o.center_loc())
			if d < best_d:
				best_d = d
				best = r
	f.raw = best


## FirmFactory::change_production / set_production: the stocks of each product
## are kept aside while making another.
static func change_production(f: Firm) -> void:
	var types := raw_types()
	if types.is_empty():
		return
	var i := types.find(f.raw)
	set_production(f, types[(i + 1) % types.size()])


static func set_production(f: Firm, raw: String) -> void:
	if f.raw != "":
		f.backup[f.raw] = [f.raw_stock, f.stock]
	f.raw = raw
	var b: Array = f.backup.get(raw, [0.0, 0.0])
	f.raw_stock = float(b[0])
	f.stock = float(b[1])


## FirmFactory::input_raw: from mines and markets whose turn it is to supply it.
static func _input_raw(f: Firm) -> void:
	for o in f.linked_firms:
		if o.next_output != f or not trade_link(f, o):
			continue
		var room := MAX_STOCK - f.raw_stock
		if room <= 0.0:
			return
		if o.code == "MINE" and o.raw == f.raw and o.stock > 0.0:
			var qty := _import(f, o, minf(o.stock, room), Defs.RAW_PRICE)
			o.stock -= qty
			f.raw_stock += qty
		elif o.code == "MARKET" and float(o.raws.get(f.raw, 0.0)) > 0.0:
			var qty := _import(f, o, minf(o.raws[f.raw], room), Defs.RAW_PRICE)
			o.raws[f.raw] -= qty
			f.raw_stock += qty


## FirmFactory::manufacture: a quarter more a level of Advanced Manufacturing.
static func _manufacture(f: Firm, max_qty: float) -> void:
	if f.raw_stock <= 0.0 or f.stock >= MAX_STOCK:
		return
	var n := f.nation()
	var yield_rate := 1.0 + (0.25 * n.tech_level("MANUFACT") if n else 0.0)
	var input := max_qty
	var output := input * yield_rate
	if input > f.raw_stock:
		input = f.raw_stock
		output = input * yield_rate
	if output > MAX_STOCK - f.stock:
		output = MAX_STOCK - f.stock
		input = output / yield_rate
	if input <= 0.0:
		return
	f.raw_stock -= input
	f.stock += output
	f.month_output += output


# --------------------------------------------------------------- market ---

static func market_day(f: Firm, day: int) -> void:
	_update_trade_link(f)
	if day % Defs.PROCESS_GOODS_INTERVAL == f.obj_id % Defs.PROCESS_GOODS_INTERVAL:
		_input_goods(f)
		next_output(f, ["FACTORY"])
	_sell_goods(f)


## FirmMarket::update_trade_link: a kingdom's town buys at a market of its own
## kingdom or one it has a trade treaty with.
static func _update_trade_link(f: Firm) -> void:
	var g := Game.inst
	var n := f.nation()
	for t in f.linked_towns:
		if t.nation_id <= 0 or t.dead:
			continue
		var ok := t.nation_id == f.nation_id or (n != null and n.trade_treaty.has(t.nation_id))
		if g.link_on(f, t) != ok:
			g.set_link(f, t, ok, true)


## FirmMarket::input_goods: from the mines and factories whose turn it is.
## Goods a factory made of its other products before it switched (kept in
## FirmFactory::backup_product_array) go to the market too, so a switch
## strands nothing (an addition: in the original they wait until the
## factory switches back).
static func _input_stored_products(f: Firm, o: Firm) -> void:
	for r in o.backup.keys():
		var b: Array = o.backup[r]
		if float(b[1]) <= 0.0 or r == o.raw:
			continue
		var cur := float(f.goods.get(r, 0.0))
		var qty := _import(f, o, minf(minf(float(b[1]), MARKET_INPUT), MAX_STOCK - cur), Defs.PRODUCT_PRICE)
		if qty <= 0.0:
			continue
		b[1] = float(b[1]) - qty
		f.goods[r] = cur + qty
		f.month_supply[r] = float(f.month_supply.get(r, 0.0)) + qty


static func _input_goods(f: Firm) -> void:
	for o in f.linked_firms:
		if o.next_output != f or not trade_link(f, o):
			continue
		if o.code == "FACTORY":
			_input_stored_products(f, o)
		if o.stock <= 0.0:
			continue
		if o.code == "MINE" and o.raw != "":
			var cur := float(f.raws.get(o.raw, 0.0))
			var qty := _import(f, o, minf(minf(o.stock, MARKET_INPUT), MAX_STOCK - cur), Defs.RAW_PRICE)
			o.stock -= qty
			f.raws[o.raw] = cur + qty
		elif o.code == "FACTORY" and o.raw != "":
			var cur := float(f.goods.get(o.raw, 0.0))
			var qty := _import(f, o, minf(minf(o.stock, MARKET_INPUT), MAX_STOCK - cur), Defs.PRODUCT_PRICE)
			o.stock -= qty
			f.goods[o.raw] = cur + qty
			f.month_supply[o.raw] = float(f.month_supply.get(o.raw, 0.0)) + qty


## FirmMarket::consumer_price: higher with a larger treasure.
static func consumer_price(f: Firm) -> float:
	var g := Game.inst
	var price := Defs.CONSUMER_PRICE
	var n := f.nation()
	if not g.config.get("setup", false) or n == null:
		return price
	if not n.is_ai:
		price += {GameSetup.VERY_HIGH: 2.5, GameSetup.HIGH: 1.5}.get(int(g.config.get("treasure", 2)), 0.0)
	else:
		price += {GameSetup.VERY_HIGH: 2.0, GameSetup.HIGH: 1.0}.get(int(g.config.get("ai_treasure", 2)), 0.0)
	return price


## FirmMarket::sell_goods: a thirtieth of the month's demand a day.
static func _sell_goods(f: Firm) -> void:
	var g := Game.inst
	var n := f.nation()
	var price := consumer_price(f)
	for p in f.goods.keys():
		var stock: float = f.goods[p]
		if stock <= 0.0:
			continue
		var sale := minf(float(f.demand.get(p, 0.0)) / 30.0, stock)
		if sale <= 0.0:
			continue
		f.goods[p] = stock - sale
		f.month_sales[p] = float(f.month_sales.get(p, 0.0)) + sale
		var income := sale * price
		if f.nation_id > 0 and g.god_worshipped(f.nation_id, "CHINESE"):
			income *= 1.3
		f.market_sales += income
		if n and n.is_ai and int(g.config.get("aggressiveness", GameSetup.MODERATE)) > GameSetup.MODERATE:
			income += income * (int(g.config["aggressiveness"]) - GameSetup.MODERATE) / 4.0
		if n:
			n.add_cash(income, "Sale of goods")


## TownArray::distribute_demand (every 15 days): each town wants half a unit
## of goods a month for each peasant and one for each worker, of each product;
## short supply is shared evenly, plenty first from its own kingdom's markets.
static func distribute_demand(g: Game) -> void:
	for f in g.firms:
		if f.code == "MARKET":
			f.demand = {}
	for t in g.towns:
		if t.dead or t.population <= 0:
			continue
		var markets: Array = t.linked_firms.filter(func(m): return m.code == "MARKET" and not m.dead and not m.under_construction \
			and (t.nation_id == m.nation_id or t.nation_id == 0) and g.link_on(m, t))
		if markets.is_empty():
			continue
		var want := t.jobless() * PEASANT_GOODS_MONTH_DEMAND + t.employed * WORKER_GOODS_MONTH_DEMAND
		for p in raw_types():
			var total := 0.0
			var own := 0.0
			var sellers: Array = []
			# every market has a place for each product (MAX_MARKET_GOODS = 6)
			for m in markets:
				sellers.append(m)
				total += float(m.goods.get(p, 0.0))
				if m.nation_id == t.nation_id:
					own += float(m.goods.get(p, 0.0))
			for m in sellers:
				var s := float(m.goods.get(p, 0.0))
				var d := 0.0
				if total < want:
					d = s + (want - total) / sellers.size()
				else:
					var own_share := minf(want, own)
					if m.nation_id == t.nation_id:
						d = own_share * s / own if own > 0.0 else 0.0
					else:
						d = (want - own_share) * s / total if total > 0.0 else 0.0
				m.demand[p] = float(m.demand.get(p, 0.0)) + d


## Monthly: the month's figures move to "last month".
static func next_month(g: Game) -> void:
	for f in g.firms:
		f.last_month_output = f.month_output
		f.month_output = 0.0
		if f.code == "MARKET":
			f.last_month_sales = f.month_sales
			f.month_sales = {}
			f.last_month_supply = f.month_supply
			f.month_supply = {}
