class_name Inn
extends RefCounted
## The inn (of_inn.cpp): soldiers and spies of every nationality come by to
## be hired, now and then a hero among them; each stays 10-14 updates, and
## updates come less often as the years pass. Inns within a firm's reach of
## one another share 24 places. Items the guests carry can be bought. A spy
## disguised as an independent can slip in among the guests, and whoever
## hires him gets a spy of his true master (the sleeper of Espionage).
##
## A guest (InnUnit) is a dictionary: sprite, race, name, combat, max_combat,
## leadership, spy_skill, hp (-1: unhurt), item_id, item_para, hero_id,
## stay, cost, spy_of (the true kingdom of a sneaked-in spy, else 0) and
## spy_loyalty. The list is the firm's `heroes`.

const MAX_INN_UNIT := 12
const MAX_INN_UNIT_PER_REGION := 24


## FirmInn::next_day
static func next_day(f: Firm, day: int) -> void:
	var g := Game.inst
	var interval := 10 + (g.day / 365) * 2
	if day % interval == f.obj_id % interval:
		_update_add_hire_list(f)
		_update_del_hire_list(f)
	if day % 15 == f.obj_id % 15:
		_recover_hit_point(f)
	if day % 5 == f.obj_id % 5:
		run_policy(f)


static func _update_add_hire_list(f: Firm) -> void:
	if f.heroes.size() < MAX_INN_UNIT - 1 and _should_add(f):      # -1: always one free place for spies
		add_inn_unit(f, Defs.races[Game.inst.rng.randi() % Defs.races.size()]["code"])


static func _update_del_hire_list(f: Firm) -> void:
	for i in range(f.heroes.size() - 1, -1, -1):
		if i >= f.heroes.size():
			continue
		var h: Dictionary = f.heroes[i]
		h["stay"] = int(h["stay"]) - 1
		if int(h["stay"]) == 0:
			if int(h.get("spy_of", 0)) > 0 and (_transfer(f, i) or hire(f, i, f.nation_id, true) != null):
				pass      # a spy moves on to another inn, or else slips out
			else:
				del_inn_unit(f, i)


## FirmInn::should_add_inn_unit: the inns about share 24 places.
static func _should_add(f: Firm) -> bool:
	var total := f.heroes.size()
	for o in neighbours(f):
		total += o.heroes.size()
	return total < MAX_INN_UNIT_PER_REGION


## The inns linked to this one (inns link only to inns, within a firm's reach).
static func neighbours(f: Firm) -> Array:
	var reach := Defs.effective_distance("INN", "INN")
	var c := f.center_loc()
	var out := []
	for o in Game.inst.firms:
		if o != f and not o.dead and o.code == "INN" and maxf(absf(o.center_loc().x - c.x), absf(o.center_loc().y - c.y)) <= reach:
			out.append(o)
	return out


static func _count(f: Firm, spies: bool) -> int:
	return f.heroes.filter(func(h): return (int(h["spy_skill"]) > 0) == spies).size()


## FirmInn::add_inn_unit: half soldiers, half spies; one soldier in twenty
## is a hero, the others powerful units of power 20-39.
static func add_inn_unit(f: Firm, race: String) -> void:
	var g := Game.inst
	var rng := g.rng
	var spy := false
	if _count(f, false) >= MAX_INN_UNIT / 2:
		spy = true
	elif _count(f, true) >= MAX_INN_UNIT / 2:
		spy = false
	else:
		spy = rng.randi() % 2 == 1
	var h := {"spy_skill": 0, "hp": -1, "item_id": 0, "item_para": 0, "hero_id": 0, "spy_of": 0, "spy_loyalty": 0, "max_combat": 0}
	if not spy:
		if rng.randi() % 20 == 0:
			var hero := HeroRes.pick_hero(g, "", 1)
			if hero.is_empty():
				return
			var sprite := HeroRes.hero_sprite(g, hero)
			rng.randi()      # create_powerful_unit draws a loyalty first
			var st := HeroRes.powerful_stats(g, sprite, 0, 1 if hero["historic"] else 0)
			h.merge(st, true)
			h["sprite"] = sprite
			h["race"] = hero["race"]
			h["name"] = hero["name"]
			h["hero_id"] = hero["id"]
			hero["appeared"] = true
		else:
			var power := 20 + rng.randi() % 20
			var sprite2 := Defs.unit_sprite(race, "INF" if rng.randi() % 2 == 0 else "SPU")
			rng.randi()
			h.merge(HeroRes.powerful_stats(g, sprite2, power), true)
			h["sprite"] = sprite2
			h["race"] = race
			h["name"] = Defs.random_person_name(race, rng)
	else:
		h["race"] = race
		h["name"] = Defs.random_person_name(race, rng)
		match rng.randi() % 3:
			0:
				h["sprite"] = Defs.unit_sprite(race, "CIV")
				h["combat"] = int(Defs.CITIZEN_COMBAT_LEVEL)
				h["leadership"] = 0
			1:
				h["sprite"] = Defs.unit_sprite(race, "INF")
				h["combat"] = 20 + rng.randi() % 30
				h["leadership"] = 20 + rng.randi() % 30
			_:
				h["sprite"] = Defs.unit_sprite(race, "SPU")
				h["combat"] = 30 + rng.randi() % 30
				h["leadership"] = 10 + rng.randi() % 20
		h["spy_skill"] = 30 + rng.randi() % 40
		if rng.randi() % 4 == 0:
			h["spy_skill"] = int(h["spy_skill"]) + rng.randi() % 30
		elif rng.randi() % 2 == 0:
			h["spy_skill"] = int(h["spy_skill"]) + rng.randi() % 15
	if not Defs.unit_types.has(h["sprite"]):
		return
	_set_cost(h)
	h["stay"] = 10 + rng.randi() % 5
	f.heroes.append(h)


## InnUnit::set_hire_cost
static func _set_cost(h: Dictionary) -> void:
	h["cost"] = HeroRes.hire_cost(int(h["combat"]), int(h.get("max_combat", 0)), int(h["leadership"]), int(h["spy_skill"]), int(h["item_id"]))


static func is_civilian(h: Dictionary) -> bool:
	return str(h["sprite"]).ends_with("_CIV")


## FirmInn::del_inn_unit: a hero who leaves may appear again.
static func del_inn_unit(f: Firm, i: int) -> void:
	if i < 0 or i >= f.heroes.size():
		return
	var h: Dictionary = f.heroes[i]
	if int(h.get("hero_id", 0)) > 0:
		var info := HeroRes.info(Game.inst, int(h["hero_id"]))
		if not info.is_empty():
			info["appeared"] = false
	f.heroes.remove_at(i)


## The price a kingdom pays for a guest (its own sneaked-in spy comes free).
static func price(f: Firm, i: int, nid: int) -> int:
	var h: Dictionary = f.heroes[i]
	if int(h.get("spy_of", 0)) > 0 and int(h["spy_of"]) == nid:
		return 0
	return int(h["cost"])


## FirmInn::hire: the guest comes out, at a loyalty of 30 + half the
## reputation (+20 of the kingdom's race), 40 to 100. A spy for hire becomes
## our spy; a sneaked-in spy serves his true master in secret, or - his own
## master hiring him, or slipping out - simply goes back to him.
static func hire(f: Firm, i: int, nid := -1, escape := false, exit_firm: Firm = null) -> Unit:
	var g := Game.inst
	if i < 0 or i >= f.heroes.size():
		return null
	if nid < 0:
		nid = f.nation_id
	var h: Dictionary = f.heroes[i]
	var n := g.nation(nid)
	var spy_of := int(h.get("spy_of", 0))
	var free := spy_of > 0 and (escape or spy_of == nid)
	if not free:
		if n == null or n.cash < float(h["cost"]):
			return null
	var ef: Firm = exit_firm if exit_firm != null else f
	var c := g.exit_cell(ef.footprint(), ef.door())
	var owner := spy_of if free else nid
	var u := g.spawn_unit(h["sprite"], owner, c, float(h["combat"]))
	if u == null:
		return null
	if not free:
		n.add_cash(-float(h["cost"]), "Hiring")
	u.leadership = float(h["leadership"])
	u.max_combat = int(h.get("max_combat", 0))
	u.item_id = int(h["item_id"])
	u.item_para = int(h["item_para"])
	u.refresh_max_hp()
	u.hp = u.max_hp if float(h["hp"]) < 0.0 else minf(float(h["hp"]), u.max_hp)
	u.unit_name = h["name"]
	var ln := g.nation(owner)
	var loy := 30 + (int(ln.reputation) / 2 if ln else 0)
	if free:
		loy = int(h.get("spy_loyalty", loy))
	if ln and u.race == ln.race:
		loy += 20
	u.loyalty = float(clampi(loy, 40, 100))
	if int(h["spy_skill"]) > 0 and spy_of == 0:
		u.is_spy = true                      # a spy for hire is ours
		u.spy_skill = float(h["spy_skill"])
	elif spy_of > 0:
		if free:
			u.is_spy = true
			u.spy_skill = float(h["spy_skill"])
		else:
			u.sleeper_for = spy_of           # he serves his true master in secret
			u.set_meta("sleeper_skill", float(h["spy_skill"]))
	if int(h.get("hero_id", 0)) > 0:
		u.hero_id = int(h["hero_id"])
		u.is_hero = true
	f.heroes.remove_at(i)       # the hero stays appeared: he is in the world now
	f.send_to_rally(u)
	return u


## FirmInn::transfer_inn_unit: a spy whose stay is over moves to another inn
## with room - his own kingdom's only if no other - or, failing that, comes
## out at one of his kingdom's inns.
static func _transfer(f: Firm, i: int) -> bool:
	var g := Game.inst
	var h: Dictionary = f.heroes[i]
	var spy_of := int(h.get("spy_of", 0))
	if spy_of == 0:
		return false
	var inns: Array = g.firms.filter(func(o): return o.code == "INN" and not o.dead and not o.under_construction)
	if inns.is_empty():
		return false
	var start := g.rng.randi() % inns.size()
	var target: Firm = null
	var own: Firm = null
	var any_own: Firm = null
	for k in inns.size():
		var o: Firm = inns[(start + k) % inns.size()]
		if o.nation_id == spy_of and any_own == null:
			any_own = o
		if o == f or o.heroes.size() >= MAX_INN_UNIT:
			continue
		if o.nation_id == spy_of:
			if own == null:
				own = o
			continue
		target = o
		break
	if target == null:
		target = own
	if target:
		var nh := h.duplicate()
		nh["stay"] = 10 + g.rng.randi() % 5
		_set_cost(nh)
		target.heroes.append(nh)
		f.heroes.remove_at(i)
		return true
	if any_own:
		return hire(f, i, spy_of, true, any_own) != null
	return false


## FirmInn::recover_hit_point: a point every 15 days, more with a Ring of Life.
static func _recover_hit_point(f: Firm) -> void:
	for h in f.heroes:
		if float(h["hp"]) < 0.0:
			continue
		var maxhp := _max_hp(h)
		var inc := 1 + (1 + Items.ability(int(h["item_id"]), int(h["item_para"]), Items.Ability.RECOVERY)) / 2
		h["hp"] = minf(maxhp, float(h["hp"]) + inc)
		if float(h["hp"]) >= maxhp:
			h["hp"] = -1


static func _max_hp(h: Dictionary) -> float:
	var t: Dictionary = Defs.unit_types.get(h["sprite"], {})
	return maxf(1.0, float(t.get("hp", 200)) * float(h["combat"]) / 100.0)


## FirmInn::can_accept_assign: only a military spy disguised as an independent.
static func can_accept(f: Firm, u: Unit) -> bool:
	return not f.under_construction and u.rank != Defs.Rank.KING and u.is_spy and not u.is_civilian() \
		and u.seen_nation() == 0 and f.heroes.size() < MAX_INN_UNIT and _count(f, false) < MAX_INN_UNIT / 2


## FirmInn::assign_unit: the spy takes a place among the guests.
static func assign_unit(f: Firm, u: Unit) -> bool:
	if not can_accept(f, u):
		return false
	var h := {"sprite": u.sprite_code, "race": u.race, "name": u.unit_name, "combat": int(u.combat), "max_combat": u.max_combat,
		"leadership": int(u.leadership), "spy_skill": int(u.spy_skill), "hp": u.hp if u.hp < u.max_hp else -1.0,
		"item_id": u.item_id, "item_para": u.item_para, "hero_id": u.hero_id, "spy_of": u.nation_id,
		"spy_loyalty": int(u.loyalty)}
	_set_cost(h)
	h["stay"] = 10 + Game.inst.rng.randi() % 5
	f.heroes.append(h)
	u.hero_id = 0
	u.item_id = 0
	Game.inst.remove_unit(u)
	return true


## FirmInn::buy_item: the guest's item, set down outside the inn.
static func buy_item(f: Firm, i: int, nid := -1) -> bool:
	var g := Game.inst
	if i < 0 or i >= f.heroes.size():
		return false
	if nid < 0:
		nid = f.nation_id
	var h: Dictionary = f.heroes[i]
	if int(h["item_id"]) == 0:
		return false
	var cost := float(Items.TABLE.get(int(h["item_id"]), [0, 0, 0])[Items.COST])
	var n := g.nation(nid)
	var own := int(h.get("spy_of", 0)) == nid
	if not own and (n == null or n.cash < cost):
		return false
	var fp := f.footprint()
	var c := g._free_treasure_cell(Vector2i(fp.end.x, fp.end.y))
	if c.x < 0:
		return false
	g.spawn_treasure(Treasure.Kind.ITEM, int(h["item_id"]), int(h["item_para"]), c)
	if not own:
		n.add_cash(-cost, "Hiring")
	h["item_id"] = 0
	h["item_para"] = 0
	_set_cost(h)
	return true


# ------------------------------------------------- recruiting policies ---
# Not in the original: a player's standing orders for an inn. Every 5 days
# it hires the guests that fit and sends each to a fort or camp of the
# kingdom, keeping a reserve in the treasury.

enum Policy { OFF, SOLDIERS, GENERALS, BOTH }
const POLICY_NAMES := ["off", "soldiers", "generals", "soldiers and generals"]
const POLICY_RESERVE := 1000.0
const PRICE_CAPS := [600, 800, 1000]     # the standing orders' price limits (right-click)


## A spy among the guests - one for hire or another kingdom's sneaked in.
## Standing orders never hire one.
static func is_spy_guest(h: Dictionary) -> bool:
	return int(h["spy_skill"]) > 0 or int(h.get("spy_of", 0)) > 0


static func next_price_cap(cur: int) -> int:
	var i := PRICE_CAPS.find(cur)
	return PRICE_CAPS[(i + 1) % PRICE_CAPS.size()]


## (Units of combat or leadership 100 or more - heroes and their like, dear
## to hire - are left to the player.)
## A fighting man whose leadership is far below his combat (at most half):
## a soldier to fill a fort, special units included.
static func fits_soldier(h: Dictionary) -> bool:
	return int(h["combat"]) < 100 and int(h["leadership"]) < 100 and int(h["spy_skill"]) == 0 and not is_civilian(h) and int(h["leadership"]) * 2 <= int(h["combat"])


## A man who leads better than he fights: a commander for a camp.
static func fits_general(h: Dictionary) -> bool:
	return int(h["combat"]) < 100 and int(h["leadership"]) < 100 and int(h["spy_skill"]) == 0 and not is_civilian(h) and int(h["leadership"]) >= 40 and int(h["leadership"]) > int(h["combat"])


static func run_policy(f: Firm) -> void:
	var g := Game.inst
	var n := f.nation()
	if n == null or f.under_construction or n.is_fryhtan:
		return
	var policy := f.inn_policy
	# the computer hires good soldiers for its forts when its military budget
	# allows (an addition, beside the original's think_hire_general/spy)
	var ai_hire := policy == Policy.OFF and n.ai is NationAI and f.nation_id != g.player_id
	if ai_hire:
		var nai: NationAI = n.ai
		if not (nai.should_spend(nai.pref("military_development") / 4) or n.cash > 2000.0 + 1000.0 * nai.pref("cash_reserve") / 100.0):
			return
		policy = Policy.SOLDIERS
	if policy == Policy.OFF:
		return
	for i in range(f.heroes.size() - 1, -1, -1):
		if i >= f.heroes.size():
			continue
		var h: Dictionary = f.heroes[i]
		if is_spy_guest(h):
			continue
		var cost := float(price(f, i, f.nation_id))
		if n.cash - cost < POLICY_RESERVE:
			continue
		if not ai_hire and cost > float(f.inn_max_price):
			continue
		var as_soldier: bool = policy in [Policy.SOLDIERS, Policy.BOTH] and fits_soldier(h)
		if ai_hire:
			# the computer takes any good fighter (combat 40-99, no spy)
			as_soldier = int(h["spy_skill"]) == 0 and not is_civilian(h) and int(h["combat"]) >= 40 and int(h["combat"]) < 100 and int(h["leadership"]) < 100
		var as_general: bool = policy in [Policy.GENERALS, Policy.BOTH] and fits_general(h)
		if not as_soldier and not as_general:
			continue
		var dest := _general_post(f, h) if as_general else _soldier_post(f)
		if dest == null:
			continue
		var u := hire(f, i)
		if u == null:
			continue
		if as_general:
			u.rank = Defs.Rank.GENERAL
		u.order_enter(dest)
		if ai_hire:
			return        # one at a time for the computer
		g.notify_nation(f.nation_id, "The inn hired %s and sent him to the %s." % [u.unit_name, dest.display_name()], f.center_loc(), true)


## The nearest fort or camp of the kingdom with room for another soldier
## (counting those already on their way).
static func _soldier_post(f: Firm) -> Firm:
	var g := Game.inst
	var best: Firm = null
	var bd := INF
	for c in g.firms:
		if c.dead or c.nation_id != f.nation_id or not (c.code in ["FORT", "CAMP"]) or c.under_construction:
			continue
		var coming := g.units.filter(func(u): return not u.dead and u.order_firm == c and u.order == Unit.Order.ENTER).size()
		if c.soldiers.size() + coming >= c.capacity():
			continue
		var d := c.center_loc().distance_to(f.center_loc())
		if d < bd:
			bd = d
			best = c
	return best


## The nearest camp a new general would improve: one without a commander,
## or with a less able one (the new man then takes command).
static func _general_post(f: Firm, h: Dictionary) -> Firm:
	var g := Game.inst
	var best: Firm = null
	var bd := INF
	for c in g.firms:
		if c.dead or c.nation_id != f.nation_id or not (c.code in ["FORT", "CAMP"]) or c.under_construction:
			continue
		if c.overseer != null and (c.overseer.rank == Defs.Rank.KING or c.overseer.lead_skill() >= float(h["leadership"])):
			continue
		if g.units.any(func(u): return not u.dead and u.order_firm == c and u.order == Unit.Order.ENTER and u.rank >= Defs.Rank.GENERAL):
			continue
		var d := c.center_loc().distance_to(f.center_loc())
		if d < bd:
			bd = d
			best = c
	return best
