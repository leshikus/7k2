class_name AIDiplomacy
extends RefCounted
## A computer kingdom's diplomacy (oai_dipl.cpp, NationMonster::think_diplomacy):
## war on a kingdom it has come to hate, food when short, cease-fires, trade,
## alliance and friendly treaties, ending treaties, tribute and aid, technology
## exchanges and offers to buy a weaker throne; and its reaction to the
## answers it gets (ai_notify_reply). The answers it gives are Diplomacy.consider.


## Nation::think_diplomacy (Fryhtans: NationMonster::think_diplomacy)
static func think(ai: NationAI) -> void:
	var g := ai.g
	var me := ai.n
	if think_declare_war(ai):
		return
	if not me.is_fryhtan or not ai.my_towns().is_empty():
		think_request_buy_food(ai)       # don't return even if this request is sent
	think_request_cease_war(ai)
	if not me.is_fryhtan or (not ai.my_towns().is_empty() and not ai.my_firms("MARKET").is_empty()):
		if think_trade_treaty(ai):
			return
	if not me.is_fryhtan:
		if think_propose_treaty(ai, "ALLIANCE"):
			return
		if think_propose_treaty(ai, "FRIENDLY"):
			return
	if think_end_treaty(ai):
		return
	if think_demand_tribute_aid(ai):
		return
	if think_exchange_tech(ai):
		return
	think_request_surrender(ai)


## Nation::should_diplomacy_retry
static func may_retry(ai: NationAI, id: String, to: int) -> bool:
	if not Diplomacy.can_send(ai.g, ai.n.id, to, id):
		return false
	return Diplomacy._may_retry(ai.g, ai.n, id, to)


static func _send(ai: NationAI, to: int, id: String, p1 = 0, p2 = 0) -> bool:
	return Diplomacy._ai_send(ai.g, ai.n, to, id, p1, p2)


static func _others(ai: NationAI) -> Array:
	return ai.g.nations.filter(func(o): return o.alive and o != ai.n)


## Nation::think_declare_war: with no enemy now, on the weakest kingdom it has
## come to hate (relation below 10), if the trade with it is worth less.
static func think_declare_war(ai: NationAI) -> bool:
	var g := ai.g
	if _others(ai).any(func(o): return ai.relation(o.id) == Defs.Relation.WAR):
		return false
	var best := 0
	var min_s := 0x1000
	for o in _others(ai):
		if not ai.n.contact.has(o.id) or Diplomacy.ai_rel(ai.n, o.id) >= 10:
			continue
		if not ai.should_spend(100 - Diplomacy.trade_rating(g, ai.n, o)):
			continue
		var s := Diplomacy.military_rank(g, o) + Diplomacy._rank(g, o, 1) / 2 + Diplomacy._rank(g, o, 3) / 3
		if s < min_s:
			min_s = s
			best = o.id
	if best > 0 and may_retry(ai, "DECLARE_WAR", best):
		return _send(ai, best, "DECLARE_WAR")
	return false


## Nation::think_request_buy_food: short of food for a year or more (by the
## food reserve preference), from the friendliest kingdom with plenty.
static func think_request_buy_food(ai: NationAI) -> bool:
	var g := ai.g
	var me := ai.n
	var change := ai.yearly_food_change()
	var needed := 0
	if change > 0:
		if me.food > 0:
			return false
		needed = int(-me.food)
	else:
		needed = int(-change * (100 + ai.pref("food_reserve")) / 50)
		if me.food > needed:
			return false
	var best: Nation = null
	var best_r := 0
	for o in _others(ai):
		if o.food < 500:
			continue
		var rel := ai.relation(o.id)
		if rel == Defs.Relation.WAR or not me.contact.has(o.id):
			continue
		var o_change := Diplomacy.yearly_food_change(g, o)
		if o_change < 0 and o.food < 1500:
			continue
		if not may_retry(ai, "BUY_FOOD", o.id):
			continue
		var r := Diplomacy.level(rel) + int(o.food) / 100 + int(o_change) / 10     # relation_status * 20
		if r > best_r:
			best_r = r
			best = o
	if best == null:
		return false
	var qty := 0
	for i in range(Diplomacy.FOOD_QTY.size() - 1, -1, -1):
		if best.food / 2 > Diplomacy.FOOD_QTY[i]:
			qty = Diplomacy.FOOD_QTY[i]
			break
	if qty == 0:
		return false
	var price := 10
	if me.food < needed / 4:
		price = 30
	elif me.food < needed / 3:
		price = 20
	elif best.food > Goals.score(g, best, 1) * Defs.UNIT_FOOD_YEAR_CONSUMPTION * 5 and best.cash < best.fixed_expense_365() / 2:
		price = 5
	return _send(ai, best.id, "BUY_FOOD", qty, price)


## Nation::think_request_cease_war: ask where the war is no longer worth it,
## else the feeling warms a little while no battle is fought.
static func think_request_cease_war(ai: NationAI) -> void:
	for o in _others(ai):
		if ai.relation(o.id) != Defs.Relation.WAR or not may_retry(ai, "CEASE_WAR", o.id):
			continue
		if Diplomacy.consider_cease_war(ai.g, ai.n, o) > 0:
			_send(ai, o.id, "CEASE_WAR")
		else:
			Diplomacy.change_ai_rel(ai.n, o.id, 1)


## Nation::think_trade_treaty
static func think_trade_treaty(ai: NationAI) -> bool:
	for o in _others(ai):
		if o.is_fryhtan != ai.n.is_fryhtan or not ai.n.contact.has(o.id) or Diplomacy.has_trade(ai.n, o.id):
			continue
		if ai.g.day < int(ai.n.never_until.get("END_TRADE:%d" % o.id, -1)):
			continue
		if int(ai.n.prefs.get("_demand_trade:%d" % o.id, 0)) > 0 or Diplomacy.trade_with_rating(ai.g, ai.n, o) > 0:
			if may_retry(ai, "TRADE", o.id):
				ai.n.prefs.erase("_demand_trade:%d" % o.id)
				return _send(ai, o.id, "TRADE")
	return false


## Nation::think_propose_alliance_treaty / think_propose_friendly_treaty: to
## the kingdom with the best rating above what it needs.
static func think_propose_treaty(ai: NationAI, id: String) -> bool:
	var g := ai.g
	var best := 0
	var best_r := 0
	for o in _others(ai):
		if o.is_fryhtan != ai.n.is_fryhtan or not ai.n.contact.has(o.id):
			continue
		var rel := ai.relation(o.id)
		if id == "ALLIANCE" and rel == Defs.Relation.ALLIANCE:
			continue
		if id == "FRIENDLY" and rel >= Defs.Relation.PEACE:
			continue
		if not may_retry(ai, id, o.id):
			continue
		var r := consider_treaty(ai, o, id)
		if r > best_r:
			best_r = r
			best = o.id
	if best > 0:
		return _send(ai, best, id)
	return false


## Nation::consider_friendly_treaty / consider_alliance_treaty: the rating
## above the acceptance level (negative or -1 for no).
static func consider_treaty(ai: NationAI, o: Nation, id: String) -> int:
	var g := ai.g
	var rel := ai.relation(o.id)
	if id == "ALLIANCE":
		if rel >= Defs.Relation.ALLIANCE or Diplomacy.ai_rel(ai.n, o.id) < 40 or not Diplomacy._should_consider_friendly(g, ai.n, o):
			return -1
		return Diplomacy._alliance_rating(g, ai.n, o) - (80 - ai.pref("allying_tendency") / 4 - ai.pref("peacefulness") / 8)
	if rel >= Defs.Relation.PEACE or Diplomacy.ai_rel(ai.n, o.id) < 20 or not Diplomacy._should_consider_friendly(g, ai.n, o):
		return -1
	return Diplomacy._alliance_rating(g, ai.n, o) - (60 - ai.pref("allying_tendency") / 8 - ai.pref("peacefulness") / 4)


## Nation::think_end_treaty: an honest kingdom formally ends a treaty with a
## kingdom it plans to attack or dislikes and trades little with.
static func think_end_treaty(ai: NationAI) -> bool:
	var g := ai.g
	if ai.pref("honesty") < 30:
		return false
	for o in _others(ai):
		var rel := ai.relation(o.id)
		if rel < Defs.Relation.PEACE:
			continue
		if not (ai.secret_attack.has(o.id) or (Diplomacy.ai_rel(ai.n, o.id) < 30 and Diplomacy.trade_rating(g, ai.n, o) < 50)):
			continue
		if g.day < int(ai.n.status_day.get(o.id, -10000)) + 60 + ai.pref("honesty") / 2:
			continue
		var id := "END_FRIENDLY" if rel == Defs.Relation.PEACE else "END_ALLIANCE"
		if not Diplomacy.can_send(g, ai.n.id, o.id, id):
			continue
		if ai.pref("honesty") - 50 > Diplomacy.overall_rank(g, o) - ai.overall_rank():
			return _send(ai, o.id, id)
	return false


## Nation::think_demand_tribute_aid: from a weaker kingdom (tribute) or a
## friend when we are short of money (aid). Outside the tutorials the
## original then simply adds the amount to its own treasury and goes on.
static func think_demand_tribute_aid(ai: NationAI) -> bool:
	var g := ai.g
	var me := ai.n
	if g.day < 180 + me.id * 50:
		return false
	var others := _others(ai)
	if others.is_empty():
		return false
	var ours := ai.military_rank()
	var our_econ := Diplomacy._rank(g, me, 3)
	var fixed := me.fixed_expense_365()
	var start := g.rng.randi() % others.size()
	for k in others.size():
		var o: Nation = others[(start + k + 1) % others.size()]
		var id := "DEMAND_TRIBUTE" if ai.relation(o.id) <= Defs.Relation.NEUTRAL else "DEMAND_AID"
		var r := 0
		var need := 0
		if id == "DEMAND_TRIBUTE":
			if not may_retry(ai, id, o.id):
				continue
			r = ours - Diplomacy.military_rank(g, o)
			if me.is_fryhtan and not o.is_fryhtan:
				r *= 2
				if me.live_points < 500 * (100 + ai.pref("live_points_reserve")) / 100:
					r *= 2
			if r < 0:
				continue
			if ai.pref("economic_development") > 50:
				r += maxi(0, Diplomacy._rank(g, o, 3) - our_econ)
			need = 20 + Diplomacy.trade_rating(g, me, o) / 2 + (100 - ai.pref("peacefulness")) / 3
			if me.cash < fixed and fixed != 0.0:
				need -= int(need * me.cash / fixed)
		else:
			if me.cash >= fixed:
				continue
			if me.cash > fixed * (50 + ai.pref("cash_reserve")) / 300.0 and not may_retry(ai, id, o.id):
				continue
			r = (ours - Diplomacy.military_rank(g, o)) / 2 + (Diplomacy._rank(g, o, 3) - our_econ)
			need = 20 + 50 * int(me.cash / maxf(1.0, fixed))
		if not o.is_ai:
			match ai._aggressiveness():
				GameSetup.NONE:
					need += 60
				GameSetup.LOW:
					need += 40
				GameSetup.HIGH:
					need -= 20
				GameSetup.VERY_HIGH:
					need -= 40
			if o.cash > me.cash and ai._aggressiveness() >= GameSetup.HIGH:
				need -= int((o.cash - me.cash) / 500.0)
		if r > need:
			var d := r - need
			var amount := 4000 if d > 120 else (3000 if d > 80 else (2000 if d > 40 else (1000 if d > 20 else 500)))
			if not g.config.has("tutorial"):
				me.add_cheat(float(amount))
				return false
			return _send(ai, o.id, id, amount)
	return false


## Nation::think_exchange_tech: one time in ten, a technology we have for one
## we lack, with a kingdom not hostile to us.
static func think_exchange_tech(ai: NationAI) -> bool:
	var g := ai.g
	if g.rng.randi() % 10 > 0:
		return false
	var others := _others(ai)
	if others.is_empty():
		return false
	var start := g.rng.randi() % others.size()
	for k in others.size():
		var o: Nation = others[(start + k + 1) % others.size()]
		if o.tech.is_empty() or not may_retry(ai, "EXCHANGE_TECH", o.id):
			continue
		if ai.relation(o.id) < Defs.Relation.NEUTRAL:
			continue
		var give := ""
		var get := ""
		for t in Defs.research_techs():
			var c: String = t["code"]
			if give == "" and ai.n.tech_level(c) > o.tech_level(c):
				give = c
			if get == "" and o.tech_level(c) > ai.n.tech_level(c):
				get = c
		if give == "" or get == "":
			continue
		return _send(ai, o.id, "EXCHANGE_TECH", get, give)
	return false


## Nation::think_request_surrender: after two years, rich enough, an offer
## for the throne of a kingdom no stronger than us (or out of money).
static func think_request_surrender(ai: NationAI) -> bool:
	var g := ai.g
	var me := ai.n
	if g.day < 365 * 2 or g.rng.randi() % 5 != 0:
		return false
	var fixed := me.fixed_expense_365()
	if me.cash < fixed + 5000 + 10000 * ai.pref("cash_reserve") / 100:
		return false
	if me.profit_365() < 0.0 and me.cash < 20000:
		return false
	var offer := int(me.cash) - mini(5000, int(fixed))
	var amounts := [5000, 10000, 20000, 35000, 50000, 75000, 100000, 150000]
	var chosen := 0
	for i in range(amounts.size() - 1, -1, -1):
		if offer >= amounts[i]:
			chosen = amounts[i]
			break
	if chosen == 0:
		return false
	var ours := ai.overall_rank()
	var others := _others(ai)
	if others.is_empty():
		return false
	var start := g.rng.randi() % others.size()
	for k in others.size():
		var o: Nation = others[(start + k + 1) % others.size()]
		if o.cash > 100 and Diplomacy.overall_rank(g, o) > ours:
			continue
		if not may_retry(ai, "REQUEST_SURRENDER", o.id):
			continue
		return _send(ai, o.id, "REQUEST_SURRENDER", chosen)
	return false


## Nation::ai_notify_reply: the answer to one of our messages changes how we
## feel; a refusal may be met with tribute and a second request, the end of
## a treaty, or war.
static func notify_reply(ai: NationAI, m: Dictionary, accept: bool) -> void:
	var g := ai.g
	var me := ai.n
	var to: int = m["to"]
	var key := "%s:%d" % [m["id"], to]
	if accept:
		me.reject_day.erase(key)
	var change := 0
	match m["id"]:
		"TRADE":
			change = ai.pref("trading_tendency") / 10 if accept else -ai.pref("trading_tendency") / 10
		"FRIENDLY", "ALLIANCE", "CEASE_WAR":
			change = 0 if accept else -5
		"MILITARY_AID":
			change = 0 if accept else -(20 - ai.pref("military_courage") / 10)
		"EMBARGO":
			change = (10 + ai.pref("trading_tendency") / 10) if accept else -(10 + ai.pref("trading_tendency") / 20)
		"REQUEST_WAR":
			change = ai.pref("allying_tendency") / 10 if accept else -30
		"BUY_FOOD":
			change = ai.pref("food_reserve") / 10 if accept else -ai.pref("food_reserve") / 10
		"DEMAND_TRIBUTE", "DEMAND_AID":
			change = (100 * int(m.get("p1", 0)) / maxi(1000, int(me.cash))) if accept else -(400 - ai.pref("peacefulness")) / 10
		"EXCHANGE_TECH":
			change = (5 + ai.pref("research") / 10) * (1 if accept else -1)
		"GIVE_TRIBUTE", "GIVE_AID":
			change = 0 if accept else -5
	if change < 0:
		change -= change * ai.pref("forgiveness") / 200
	if change != 0:
		Diplomacy.change_ai_rel(me, to, change)
	if accept:
		return
	if _think_give_tribute_aid(ai, m):
		return
	var rel := ai.relation(to)
	if m["id"] != "ALLIANCE" and rel >= Defs.Relation.PEACE and Diplomacy.ai_rel(me, to) < 40 - ai.pref("allying_tendency") / 5:
		_send(ai, to, "END_FRIENDLY" if rel == Defs.Relation.PEACE else "END_ALLIANCE")
	elif Diplomacy.ai_rel(me, to) == 0:
		if ai._aggressiveness() >= GameSetup.HIGH or ai.pref("peacefulness") < 50:
			_send(ai, to, "DECLARE_WAR")
			if ai._aggressiveness() >= GameSetup.VERY_HIGH or (ai._aggressiveness() >= GameSetup.HIGH and ai.pref("peacefulness") < 50):
				var largest: Town = null
				for t in ai.my_towns():
					if largest == null or t.population > largest.population:
						largest = t
				if largest:
					AICapture.think_capture_new_enemy_town(ai, largest, true)


## Nation::think_give_tribute_aid: after a refusal that matters, tribute (or
## aid to a friend) and the request again.
static func _think_give_tribute_aid(ai: NationAI, m: Dictionary) -> bool:
	var g := ai.g
	var me := ai.n
	var to: int = m["to"]
	var other := g.nation(to)
	if other == null:
		return false
	var id := "GIVE_AID" if ai.relation(to) >= Defs.Relation.PEACE else "GIVE_TRIBUTE"
	if g.day < int(me.never_until.get("%s:%d" % [id, to], -1)):
		return false
	var amount: int = [500, 1000][g.rng.randi() % 2]
	if not ai.should_spend(0, float(amount)):
		return false
	var ok := false
	match m["id"]:
		"TRADE":
			ok = Diplomacy.trade_with_rating(g, me, other) > 100 - ai.pref("trading_tendency") / 2
		"FRIENDLY", "ALLIANCE":
			var r := Diplomacy.trade_rating(g, other, me) + Diplomacy.trade_with_rating(g, me, other) + Diplomacy.overall_rank(g, other) - ai.overall_rank()
			ok = r >= 200 - ai.pref("trading_tendency") / 4 - ai.pref("allying_tendency") / 4
		"CEASE_WAR":
			ok = Diplomacy.military_rank(g, other) > ai.military_rank() + (100 - ai.pref("peacefulness")) / 2
	if not ok:
		return false
	_send(ai, to, id, amount)
	me.never_until["%s:%d" % [id, to]] = g.day + 100
	var key := "%s:%d" % [m["id"], to]
	me.reject_day.erase(key)
	me.never_until.erase(key)
	me.sent_day.erase(key)
	_send(ai, to, m["id"], m.get("p1", 0), m.get("p2", 0))
	return true
