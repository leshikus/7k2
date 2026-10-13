class_name Diplomacy
extends RefCounted
## Diplomatic messages between kingdoms (otalkres.cpp, otalkmsg.cpp) and how a
## computer kingdom answers and starts them (oai_talk.cpp, oai_dipl.cpp).
## Our relations map the original's: War = hostile, Neutral = tense/neutral
## after a cease-fire, Peace treaty = friendly treaty, Alliance = alliance.
## A trade treaty is separate: caravans trade only with markets of kingdoms
## that have one with theirs (UnitCaravan::can_set_stop).

## talk id -> [name, needs a reply]
const TALKS := {
	"TRADE": ["Propose a trade treaty", true],
	"FRIENDLY": ["Propose a friendly treaty", true],
	"ALLIANCE": ["Propose an alliance treaty", true],
	"END_TRADE": ["Terminate our trade treaty", false],
	"END_FRIENDLY": ["Terminate our friendly treaty", false],
	"END_ALLIANCE": ["Terminate our alliance treaty", false],
	"MILITARY_AID": ["Request immediate military aid", true],
	"EMBARGO": ["Request a trade embargo", true],
	"CEASE_WAR": ["Request a cease-fire", true],
	"REQUEST_WAR": ["Request a declaration of war", true],
	"BUY_FOOD": ["Request to purchase food", true],
	"DECLARE_WAR": ["Declare war", false],
	"GIVE_TRIBUTE": ["Offer tribute", true],
	"DEMAND_TRIBUTE": ["Demand tribute", true],
	"GIVE_AID": ["Offer aid", true],
	"DEMAND_AID": ["Request aid", true],
	"EXCHANGE_TECH": ["Exchange technology", true],
	"REQUEST_SURRENDER": ["Offer to purchase the kingdom", true],
	"SURRENDER": ["Surrender", false],
}

const AMOUNTS := [500, 1000, 2000, 4000]
const FOOD_QTY := [500, 1000, 2000, 4000]
const FOOD_PRICES := [5, 10, 15, 20]     # per 10 units of food


# ------------------------------------------------------------- state ---

## The original's status * RELATION_LEVEL_PER_STATUS (hostile 0, neutral 40,
## friendly 60, alliance 80).
static func level(status: int) -> int:
	return [0, 40, 60, 80][clampi(status, 0, 3)]


static func ai_rel(n: Nation, other: int) -> int:
	if not n.ai_rel.has(other):
		# NationBase::init_relation: its status's level with -20..+20 randomness
		n.ai_rel[other] = clampi(level(n.relation(other)) + absi(hash([n.id, other])) % 41 - 20, 0, 100)
	return n.ai_rel[other]


static func change_ai_rel(n: Nation, other: int, v: int) -> void:
	n.ai_rel[other] = clampi(ai_rel(n, other) + v, 0, 100)


static func has_trade(a: Nation, b_id: int) -> bool:
	return a != null and (a.id == b_id or a.trade_treaty.get(b_id, false))


static func set_trade(g: Game, a: int, b: int, on: bool) -> void:
	var na := g.nation(a)
	var nb := g.nation(b)
	if na and nb:
		na.trade_treaty[b] = on
		nb.trade_treaty[a] = on


## NationBase::set_relation_status for both sides.
static func set_status(g: Game, a: int, b: int, status: int) -> void:
	var na := g.nation(a)
	var nb := g.nation(b)
	if na == null or nb == null:
		return
	for pair in [[na, b], [nb, a]]:
		var n: Nation = pair[0]
		n.relations[pair[1]] = status
		n.status_day[pair[1]] = g.day
		# RELATION_LEVEL_PER_STATUS: the feeling drops to the new status's level
		if level(status) < ai_rel(n, pair[1]):
			n.ai_rel[pair[1]] = level(status)
	if status == Defs.Relation.WAR:
		set_trade(g, a, b, false)
	if status != Defs.Relation.WAR:
		for u in g.units:
			if (u.nation_id == a or u.nation_id == b) and u.order == Unit.Order.ATTACK and u.target \
					and is_instance_valid(u.target) and (u.target.nation_id == a or u.target.nation_id == b):
				u.stop()
		for n in [na, nb]:
			if n.ai and n.ai.war_target in [a, b]:
				n.ai.war_target = 0


static func same_kind(a: Nation, b: Nation) -> bool:
	return a.is_fryhtan == b.is_fryhtan


# ------------------------------------------------------- ratings ---

static func _rank(g: Game, n: Nation, kind: int) -> int:
	var best := 1
	for o in g.nations:
		if o.alive:
			best = maxi(best, Goals.score(g, o, kind) if kind > 0 else Goals.total_score(g, o))
	var mine := Goals.score(g, n, kind) if kind > 0 else Goals.total_score(g, n)
	return 100 * mine / best


static func military_rank(g: Game, n: Nation) -> int:
	return _rank(g, n, 2)


static func overall_rank(g: Game, n: Nation) -> int:
	return _rank(g, n, 0)


static func _raws(g: Game, nid: int) -> Dictionary:
	var out := {}
	for f in g.firms:
		if f.code == "MINE" and f.nation_id == nid and not f.dead:
			out[f.raw] = true
	return out


## Nation::ai_trade_with_rating: what the two could trade (raw types one has
## and the other lacks).
static func trade_with_rating(g: Game, me: Nation, other: Nation) -> int:
	var mine := _raws(g, me.id)
	var theirs := _raws(g, other.id)
	var r := 0
	for k in mine:
		if not theirs.has(k):
			r += mini(30, Goals.score(g, other, 1) / 3)
	for k in theirs:
		if not mine.has(k):
			r += 30
	return r


## NationBase::trade_rating: 0..100, how much the trade with `other` matters:
## the two kingdoms' trade over the year against 5000, or the imports each way
## against our income and expenses.
static func trade_rating(g: Game, me: Nation, other: Nation) -> int:
	var mine := float(me.last_import_year.get(other.id, 0.0)) + float(me.import_year.get(other.id, 0.0))
	var theirs := float(other.last_import_year.get(me.id, 0.0)) + float(other.import_year.get(me.id, 0.0))
	var r1 := int(100.0 * (mine + theirs) / 5000.0)
	var r2 := int(50.0 * theirs / (me.last_income_year + 1.0) + 50.0 * mine / (me.last_expense_year + 1.0))
	return mini(100, maxi(r1, r2))


static func _alliance_rating(g: Game, me: Nation, other: Nation) -> int:
	var r := ai_rel(me, other.id) - 20 - int(me.war_count.get(other.id, 0)) * 20
	r += trade_rating(g, me, other) + trade_with_rating(g, me, other) / 2
	var power := military_rank(g, other) - military_rank(g, me)
	if power > 0:
		r += power
	return r


static func _overall_relation(g: Game, me: Nation, other: Nation) -> int:
	return ai_rel(me, other.id) + int(other.reputation) + military_rank(g, other) \
		+ trade_rating(g, me, other) + trade_with_rating(g, me, other) / 2


static func _should_consider_friendly(g: Game, me: Nation, other: Nation) -> bool:
	if overall_rank(g, me) > 50:
		var biggest: Nation = null
		for o in g.nations:
			if o.alive and o.id != me.id and (biggest == null or Goals.total_score(g, o) > Goals.total_score(g, biggest)):
				biggest = o
		if biggest == other:
			return false
	return other.reputation >= minf(20.0, me.reputation) - 20.0


static func _enemy_military(g: Game, me: Nation) -> int:
	var t := 0
	for o in g.nations:
		if o.alive and o.id != me.id and me.relation(o.id) == Defs.Relation.WAR:
			t += military_rank(g, o)
	return t


static func _pref(n: Nation, k: String) -> int:
	if not n.prefs.has(k):
		n.prefs[k] = absi(hash([n.id, k])) % 101
	return n.prefs[k]


static func _yearly_food_use(g: Game, n: Nation) -> float:
	return Goals.score(g, n, 1) * Defs.UNIT_FOOD_YEAR_CONSUMPTION


static func _fixed_expense(n: Nation) -> float:
	return maxf(1.0, n.last_expense_year if n.last_expense_year > 0 else n.expense_year)


# ------------------------------------------------- what may be sent ---

## TalkRes::can_send_msg plus the menu's own rules: whether `from` may send
## this message to `to` now.
static func can_send(g: Game, from: int, to: int, id: String) -> bool:
	var a := g.nation(from)
	var b := g.nation(to)
	if a == null or b == null or not a.alive or not b.alive or from == to:
		return false
	if not g.contacts_ready:
		g._init_contacts()
	if not a.contact.has(to) and id != "SURRENDER":
		return false             # TalkRes: only kingdoms that have met can talk
	var rel := a.relation(to)
	var trade := has_trade(a, to)
	if g.talks.any(func(m): return m["from"] == from and m["to"] == to and m["id"] == id):
		return false
	match id:
		"TRADE": return not trade and rel != Defs.Relation.WAR
		"FRIENDLY": return rel == Defs.Relation.NEUTRAL
		"ALLIANCE": return rel == Defs.Relation.NEUTRAL or rel == Defs.Relation.PEACE
		"END_TRADE": return trade and rel != Defs.Relation.ALLIANCE
		"END_FRIENDLY": return rel == Defs.Relation.PEACE
		"END_ALLIANCE": return rel == Defs.Relation.ALLIANCE
		"MILITARY_AID": return rel == Defs.Relation.ALLIANCE or rel == Defs.Relation.PEACE
		"EMBARGO", "REQUEST_WAR": return rel >= Defs.Relation.PEACE and not third_parties(g, from, to, id).is_empty()
		"CEASE_WAR": return rel == Defs.Relation.WAR
		"BUY_FOOD": return rel != Defs.Relation.WAR
		"DECLARE_WAR": return rel == Defs.Relation.NEUTRAL
		"GIVE_TRIBUTE": return rel <= Defs.Relation.NEUTRAL and a.cash >= AMOUNTS[0]
		"DEMAND_TRIBUTE": return rel <= Defs.Relation.NEUTRAL
		"GIVE_AID": return rel >= Defs.Relation.PEACE and a.cash >= AMOUNTS[0]
		"DEMAND_AID": return rel >= Defs.Relation.PEACE
		"EXCHANGE_TECH": return rel != Defs.Relation.WAR and not tech_pairs(a, b).is_empty()
		"REQUEST_SURRENDER": return a.cash >= AMOUNTS[0] and not b.is_player
		"SURRENDER": return true
	return false


## Kingdoms an embargo or a war may be asked against: those the receiver has a
## trade treaty with (embargo) or is not at war with (war), other than the sender.
static func third_parties(g: Game, from: int, to: int, id: String) -> Array:
	var b := g.nation(to)
	var out := []
	for o in g.nations:
		if not o.alive or o.id == from or o.id == to:
			continue
		if id == "EMBARGO" and has_trade(b, o.id):
			out.append(o.id)
		elif id == "REQUEST_WAR" and b.relation(o.id) != Defs.Relation.WAR and g.nation(from).relation(o.id) == Defs.Relation.WAR:
			out.append(o.id)
	return out


## Technologies one kingdom has and the other lacks: [[give, want], ...] for
## the sender `a`.
static func tech_pairs(a: Nation, b: Nation) -> Array:
	var give := []
	var want := []
	for t in Defs.research_techs():
		var c: String = t["code"]
		if a.tech_level(c) > b.tech_level(c):
			give.append(c)
		elif b.tech_level(c) > a.tech_level(c):
			want.append(c)
	var out := []
	for gv in give.slice(0, 4):
		for w in want.slice(0, 4):
			out.append([gv, w])
	return out


static func describe(g: Game, m: Dictionary) -> String:
	var from := g.nation(m["from"])
	var to := g.nation(m["to"])
	var fn := from.name if from else "?"
	var tn := to.name if to else "?"
	var p1 = m.get("p1", 0)
	var p2 = m.get("p2", 0)
	match m["id"]:
		"TRADE": return "The %s proposes a trade treaty with the %s." % [fn, tn]
		"FRIENDLY": return "The %s proposes a friendly treaty with the %s." % [fn, tn]
		"ALLIANCE": return "The %s proposes an alliance with the %s." % [fn, tn]
		"END_TRADE": return "The %s terminates its trade treaty with the %s." % [fn, tn]
		"END_FRIENDLY": return "The %s terminates its friendly treaty with the %s." % [fn, tn]
		"END_ALLIANCE": return "The %s terminates its alliance with the %s." % [fn, tn]
		"MILITARY_AID": return "The %s requests immediate military aid from the %s." % [fn, tn]
		"EMBARGO": return "The %s asks the %s to end its trade with the %s." % [fn, tn, _name(g, p1)]
		"CEASE_WAR": return "The %s requests a cease-fire with the %s." % [fn, tn]
		"REQUEST_WAR": return "The %s asks the %s to declare war on the %s." % [fn, tn, _name(g, p1)]
		"BUY_FOOD": return "The %s offers to buy %d food from the %s at $%d per 10." % [fn, int(p1), tn, int(p2)]
		"DECLARE_WAR": return "The %s declares war on the %s!" % [fn, tn]
		"GIVE_TRIBUTE": return "The %s offers the %s a tribute of $%d." % [fn, tn, int(p1)]
		"DEMAND_TRIBUTE": return "The %s demands a tribute of $%d from the %s." % [fn, int(p1), tn]
		"GIVE_AID": return "The %s offers the %s $%d in aid." % [fn, tn, int(p1)]
		"DEMAND_AID": return "The %s requests $%d in aid from the %s." % [fn, int(p1), tn]
		"EXCHANGE_TECH": return "The %s offers %s for %s of the %s." % [fn, Defs.tech_def(str(p1)).get("name", p1), Defs.tech_def(str(p2)).get("name", p2), tn]
		"REQUEST_SURRENDER": return "The %s offers $%d to take over the %s." % [fn, int(p1), tn]
		"SURRENDER": return "The %s surrenders to the %s." % [fn, tn]
	return ""


static func _name(g: Game, nid) -> String:
	var n := g.nation(int(nid))
	return n.name if n else "?"


# ------------------------------------------------------------ sending ---

## TalkRes::send_talk_msg: a computer kingdom answers at once; a human one
## finds it among the messages in its Diplomacy window.
static func send(g: Game, from: int, to: int, id: String, p1 = 0, p2 = 0) -> void:
	if not TALKS.has(id) or not can_send(g, from, to, id):
		return
	var m := {"from": from, "to": to, "id": id, "p1": p1, "p2": p2, "day": g.day}
	_log(g, m, "")
	var b := g.nation(to)
	if not TALKS[id][1]:
		_apply(g, m)
		if b.ai:
			_notify_ai(g, b, m)
		_tell(g, m, describe(g, m))
		return
	if b.ai:
		var yes := consider(g, b, m)
		reply(g, m, yes)
		return
	g.talks.append(m)
	if to == g.player_id:
		g.notify(describe(g, m) + " Reply in the Diplomacy window.", Vector2(-1, -1))
	elif from == g.player_id:
		g.notify("Your message has been sent to the %s." % b.name, Vector2(-1, -1))


## The receiver's answer (TalkRes::reply_talk_msg).
static func reply(g: Game, m: Dictionary, accept: bool) -> void:
	g.talks = g.talks.filter(func(x): return not (x["from"] == m["from"] and x["to"] == m["to"] and x["id"] == m["id"]))
	var a := g.nation(m["from"])
	if a == null or not a.alive:
		return
	if accept and not _affordable(g, m):
		accept = false
	_log(g, m, "accepted" if accept else "rejected")
	if accept:
		_apply(g, m)
	else:
		a.reject_day["%s:%d" % [m["id"], m["to"]]] = g.day
	var to_name := _name(g, m["to"])
	var what: String = TALKS[m["id"]][0].to_lower()
	_tell(g, m, "The %s %s: %s." % [to_name, "accepts" if accept else "rejects", what])


static func _affordable(g: Game, m: Dictionary) -> bool:
	var a := g.nation(m["from"])
	var b := g.nation(m["to"])
	match m["id"]:
		"GIVE_TRIBUTE", "GIVE_AID", "REQUEST_SURRENDER":
			return a.cash >= float(m["p1"])
		"DEMAND_TRIBUTE", "DEMAND_AID":
			return b.cash >= float(m["p1"])
		"BUY_FOOD":
			return b.food >= float(m["p1"]) and a.cash >= float(m["p1"]) * float(m["p2"]) / 10.0
	return true


static func _tell(g: Game, m: Dictionary, text: String) -> void:
	if m["from"] == g.player_id or m["to"] == g.player_id or g.observer():
		g.notify(text, Vector2(-1, -1))


static func _log(g: Game, m: Dictionary, result: String) -> void:
	var e := m.duplicate()
	e["result"] = result
	g.talk_log.append(e)
	if g.talk_log.size() > 40:
		g.talk_log.pop_front()


## TalkMsg::process_accepted_reply and the notification messages.
static func _apply(g: Game, m: Dictionary) -> void:
	var from: int = m["from"]
	var to: int = m["to"]
	var a := g.nation(from)
	var b := g.nation(to)
	var p1 = m.get("p1", 0)
	var p2 = m.get("p2", 0)
	match m["id"]:
		"TRADE":
			set_trade(g, from, to, true)
		"FRIENDLY":
			set_status(g, from, to, Defs.Relation.PEACE)
		"ALLIANCE":
			set_status(g, from, to, Defs.Relation.ALLIANCE)
			set_trade(g, from, to, true)      # allies are obliged to trade
		"END_TRADE":
			set_trade(g, from, to, false)
			a.change_reputation(-5.0)
			b.never_until["TRADE:%d" % from] = g.day + 180
			a.never_until["TRADE:%d" % to] = g.day + 180
		"END_FRIENDLY", "END_ALLIANCE":
			set_status(g, from, to, Defs.Relation.NEUTRAL)
			a.change_reputation(-5.0)
			for k in ["FRIENDLY", "ALLIANCE"]:
				b.never_until["%s:%d" % [k, from]] = g.day + 180
		"MILITARY_AID":
			# the ally turns its army against the requester's enemy
			var enemy := 0
			for o in g.nations:
				if o.alive and a.relation(o.id) == Defs.Relation.WAR and o.id != to:
					enemy = o.id
					break
			if enemy:
				if b.relation(enemy) != Defs.Relation.WAR:
					g.declare_war(to, enemy)
				if b.ai:
					b.ai.war_target = enemy
					b.ai.war_start_day = g.day
					a.last_aid_day = g.day
		"EMBARGO":
			set_trade(g, to, int(p1), false)
		"CEASE_WAR":
			set_status(g, from, to, Defs.Relation.NEUTRAL)
		"REQUEST_WAR":
			g.declare_war(to, int(p1))
			if b.ai:
				b.ai.war_target = int(p1)
				b.ai.war_start_day = g.day
		"BUY_FOOD":
			var cost := float(p1) * float(p2) / 10.0
			b.food -= float(p1)
			a.food += float(p1)
			a.add_cash(-cost, "Food")
			b.add_cash(cost, "Food")
		"DECLARE_WAR":
			g.declare_war(from, to)
		"GIVE_TRIBUTE", "GIVE_AID":
			a.add_cash(-float(p1), "Tribute")
			b.add_cash(float(p1), "Tribute")
		"DEMAND_TRIBUTE", "DEMAND_AID":
			b.add_cash(-float(p1), "Tribute")
			a.add_cash(float(p1), "Tribute")
		"EXCHANGE_TECH":
			var gv := str(p1)
			var w := str(p2)
			b.tech[gv] = maxi(b.tech_level(gv), a.tech_level(gv))
			a.tech[w] = maxi(a.tech_level(w), b.tech_level(w))
		"REQUEST_SURRENDER":
			a.add_cash(-float(p1), "Other")
			surrender(g, to, from)
		"SURRENDER":
			surrender(g, from, to)


## A kingdom gives itself up: its towns, buildings and men pass to the victor.
static func surrender(g: Game, loser: int, winner: int) -> void:
	var w := g.nation(winner)
	var l := g.nation(loser)
	if w == null or l == null:
		return
	w.cash += maxf(0.0, l.cash)
	w.food += maxf(0.0, l.food)
	l.cash = 0.0
	for t in g.towns.duplicate():
		if t.nation_id == loser and not t.dead:
			t.surrender(winner)
	for f in g.firms.duplicate():
		if f.nation_id == loser and not f.dead:
			f.change_nation(winner)
			g.on_firm_changed(f, loser)
	for u in g.units.duplicate():
		if u.nation_id == loser and not u.dead and u.inside_firm == null:
			if u.rank == Defs.Rank.KING:
				u.die(null)
				g.remove_unit(u)
			else:
				g.defect_unit(u, winner)
	g.notify("The %s has surrendered to the %s." % [l.name, w.name], Vector2(-1, -1))


# ---------------------------------------------- the computer's answers ---

## Nation::consider_talk_msg
static func consider(g: Game, me: Nation, m: Dictionary) -> bool:
	var from: int = m["from"]
	var other := g.nation(from)
	var id: String = m["id"]
	if g.day < int(me.never_until.get("%s:%d" % [id, from], -1)):
		return false
	var p1 = m.get("p1", 0)
	var rel := me.relation(from)
	match id:
		"TRADE":
			if not same_kind(me, other):
				return false
			return trade_with_rating(g, me, other) > 0 or ai_rel(me, from) >= 50
		"FRIENDLY":
			if not same_kind(me, other) or rel >= Defs.Relation.PEACE or ai_rel(me, from) < 20 or not _should_consider_friendly(g, me, other):
				return false
			return _alliance_rating(g, me, other) >= 60 - _pref(me, "allying") / 8 - _pref(me, "peace") / 4
		"ALLIANCE":
			if not same_kind(me, other) or rel >= Defs.Relation.ALLIANCE or ai_rel(me, from) < 40 or not _should_consider_friendly(g, me, other):
				return false
			return _alliance_rating(g, me, other) >= 80 - _pref(me, "allying") / 4 - _pref(me, "peace") / 8
		"CEASE_WAR":
			return consider_cease_war(g, me, other) >= 0
		"MILITARY_AID":
			if ai_rel(me, from) < 60 or g.day < other.last_aid_day + 200 - _pref(me, "allying"):
				return false
			if not g.nations.any(func(o): return o.alive and other.relation(o.id) == Defs.Relation.WAR and o.id != me.id):
				return false
			if me.cash < 2000 * _pref(me, "cash_reserve") / 100:
				return false
			return me.ai != null and me.ai.has_method("idle_units") and me.ai.idle_units(false).size() >= 4
		"EMBARGO", "REQUEST_WAR":
			var against := g.nation(int(p1))
			if against == null:
				return false
			if trade_rating(g, me, against) > 40 or me.cash < 2000 * _pref(me, "cash_reserve") / 100:
				return false
			var diff := _overall_relation(g, me, other) - _overall_relation(g, me, against)
			var need := 75 if id == "EMBARGO" else 100 + _enemy_military(g, against) - military_rank(g, me)
			if me.relation(int(p1)) >= Defs.Relation.PEACE:
				need += 100
			return diff > need
		"BUY_FOOD":
			if rel == Defs.Relation.WAR:
				return false
			var left := me.food - float(p1)
			var offered := int(m.get("p2", 0))
			if left < 1000 + 1000 * _pref(me, "food_reserve") / 100:
				return false
			var reserve := _yearly_food_use(g, me) * (100 + _pref(me, "food_reserve")) / 100.0
			if ai_rel(me, from) >= 50:
				offered += 5
			elif ai_rel(me, from) < 30:
				offered -= 5
			return (offered >= 10 and left > reserve) or left > reserve * 2 or (offered >= 20 and left > reserve / 2)
		"GIVE_TRIBUTE", "GIVE_AID":
			var significance := 100 * int(p1) / maxi(1000, int(me.cash))
			if me.income_year >= me.expense_year and significance < (100 - ai_rel(me, from)) / 5:
				return false
			change_ai_rel(me, from, significance * (100 + _pref(me, "cash_reserve")) / 200)
			return true
		"DEMAND_TRIBUTE":
			if me.last_income_year < me.last_expense_year and g.day > 365:
				return false
			var reserve_years := 1 + 3 * _pref(me, "cash_reserve") / 100
			if me.cash - float(p1) < _fixed_expense(me) * reserve_years * 0.25:
				return false
			if military_rank(g, other) - military_rank(g, me) > 10 + _pref(me, "courage") / 2:
				me.never_until["%s:%d" % [id, from]] = g.day + 180
				return true
			return false
		"DEMAND_AID":
			if rel < Defs.Relation.PEACE or me.cash - float(p1) < _fixed_expense(me) * 0.5:
				return false
			if g.day > int(me.status_day.get(from, 0)) + 720 - _pref(me, "allying"):
				me.never_until["%s:%d" % [id, from]] = g.day + 180
				return true
			return false
		"EXCHANGE_TECH":
			if rel == Defs.Relation.WAR or not same_kind(me, other):
				return false
			var gain := other.tech_level(str(p1)) - me.tech_level(str(p1))
			var give := me.tech_level(str(m.get("p2", ""))) - other.tech_level(str(m.get("p2", "")))
			if gain <= 0:
				return false
			if gain < give and rel < Defs.Relation.PEACE + (give - gain - 1):
				return false
			if gain == give and rel == Defs.Relation.NEUTRAL and _pref(me, "peace") < 30:
				return false
			change_ai_rel(me, from, gain * (5 + _pref(me, "use_weapon") / 10))
			return true
		"REQUEST_SURRENDER":
			if not same_kind(me, other):
				return false
			var weak := not g.towns.any(func(t): return t.nation_id == me.id) and not g.firms.any(func(f): return f.nation_id == me.id)
			if not weak:
				if overall_rank(g, other) < overall_rank(g, me) or overall_rank(g, me) > 30 + _pref(me, "peace") / 4:
					return false
				if float(p1) < me.cash * (75 + _pref(me, "cash_reserve") / 2) / 100.0:
					return false
			return 100 - overall_rank(g, me) + 100 * int(p1) / 10000 > overall_rank(g, me) * 13 / 10 + 50
	return false


## Nation::consider_cease_war
static func consider_cease_war(g: Game, me: Nation, other: Nation) -> int:
	if me.relation(other.id) != Defs.Relation.WAR:
		return -1
	if me.ai and me.ai.war_target == other.id and military_rank(g, me) > military_rank(g, other):
		return -1
	if g.day < int(me.status_day.get(other.id, 0)) + 60 + (100 - _pref(me, "peace")):
		return -1
	var r := _alliance_rating(g, me, other)
	r += _enemy_military(g, me) - military_rank(g, me)
	r += trade_with_rating(g, me, other) * (100 + _pref(me, "trading")) / 300
	r -= (military_rank(g, me) - 50) / 2
	r -= int(me.war_count.get(other.id, 0)) * 10
	return r - _pref(me, "peace") / 4


## Nation::notify_talk_msg: a notice changes how the computer feels.
static func _notify_ai(g: Game, me: Nation, m: Dictionary) -> void:
	var from: int = m["from"]
	var change := 0
	match m["id"]:
		"END_TRADE", "END_FRIENDLY", "END_ALLIANCE":
			change = -5
	if change < 0:
		change -= change * _pref(me, "forgiveness") / 100
	if change != 0:
		change_ai_rel(me, from, change)


# ------------------------------------------ the computer starts talks ---

static func _may_retry(g: Game, me: Nation, id: String, to: int) -> bool:
	if g.day < int(me.never_until.get("%s:%d" % [id, to], -1)):
		return false
	var interval := 90 + 270 * (100 - _pref(me, "retry")) / 100
	if id in ["DEMAND_TRIBUTE", "DEMAND_AID", "EXCHANGE_TECH"]:
		interval = 60 + 60 * (100 - _pref(me, "retry")) / 100
	var last := int(me.reject_day.get("%s:%d" % [id, to], -100000))
	var sent := int(me.sent_day.get("%s:%d" % [id, to], -100000))
	return g.day > last + interval and g.day > sent + 30


static func _ai_send(g: Game, me: Nation, to: int, id: String, p1 = 0, p2 = 0) -> bool:
	if not can_send(g, me.id, to, id):
		return false
	me.sent_day["%s:%d" % [id, to]] = g.day
	send(g, me.id, to, id, p1, p2)
	return true


## Nation::think_diplomacy, every month or so.
static func ai_think(g: Game, me: Nation) -> void:
	var others := g.nations.filter(func(o): return o.alive and o.id != me.id)
	_think_buy_food(g, me, others)
	# cease-fire
	for o in others:
		if me.relation(o.id) == Defs.Relation.WAR and _may_retry(g, me, "CEASE_WAR", o.id):
			if consider_cease_war(g, me, o) > 0:
				if _ai_send(g, me, o.id, "CEASE_WAR"):
					return
			else:
				change_ai_rel(me, o.id, 1)
	# trade treaty
	for o in others:
		if same_kind(me, o) and not has_trade(me, o.id) and me.relation(o.id) != Defs.Relation.WAR \
				and trade_with_rating(g, me, o) > 0 and _may_retry(g, me, "TRADE", o.id):
			if _ai_send(g, me, o.id, "TRADE"):
				return
	# alliance, then friendly treaty: the best candidate
	for id in ["ALLIANCE", "FRIENDLY"]:
		var best: Nation = null
		var best_r := 0
		for o in others:
			if not same_kind(me, o) or not _may_retry(g, me, id, o.id) or not can_send(g, me.id, o.id, id):
				continue
			if ai_rel(me, o.id) < (40 if id == "ALLIANCE" else 20) or not _should_consider_friendly(g, me, o):
				continue
			var need := 80 - _pref(me, "allying") / 4 - _pref(me, "peace") / 8 if id == "ALLIANCE" else 60 - _pref(me, "allying") / 8 - _pref(me, "peace") / 4
			var r := _alliance_rating(g, me, o) - need
			if r > best_r:
				best_r = r
				best = o
		if best and _ai_send(g, me, best.id, id):
			return
	# end a treaty with a kingdom it has come to dislike
	if _pref(me, "honesty") >= 30:
		for o in others:
			var rel := me.relation(o.id)
			if rel >= Defs.Relation.PEACE and ai_rel(me, o.id) < 30 and trade_rating(g, me, o) < 50 \
					and g.day >= int(me.status_day.get(o.id, 0)) + 60 + _pref(me, "honesty") / 2:
				if _ai_send(g, me, o.id, "END_FRIENDLY" if rel == Defs.Relation.PEACE else "END_ALLIANCE"):
					return
	# exchange technology, one time in ten
	if g.rng.randi() % 10 == 0:
		for o in others:
			if me.relation(o.id) == Defs.Relation.WAR or not same_kind(me, o) or not _may_retry(g, me, "EXCHANGE_TECH", o.id):
				continue
			var pairs := tech_pairs(me, o)
			if not pairs.is_empty():
				var pr: Array = pairs[g.rng.randi() % pairs.size()]
				if _ai_send(g, me, o.id, "EXCHANGE_TECH", pr[0], pr[1]):
					return


## Nation::think_request_buy_food
static func _think_buy_food(g: Game, me: Nation, others: Array) -> void:
	var need := _yearly_food_use(g, me) * (100 + _pref(me, "food_reserve")) / 50.0
	if me.food > 0 and me.food > need * 0.25:
		return
	var best: Nation = null
	var best_r := 0
	for o in others:
		if o.food < 1500 or me.relation(o.id) == Defs.Relation.WAR or not _may_retry(g, me, "BUY_FOOD", o.id):
			continue
		var r := me.relation(o.id) * 20 + int(o.food) / 100
		if r > best_r:
			best_r = r
			best = o
	if best == null:
		return
	var qty := 0
	for q in FOOD_QTY:
		if best.food / 2 > q:
			qty = q
	if qty == 0:
		return
	var price := 30 if me.food < need / 4 else (20 if me.food < need / 3 else 10)
	if me.cash >= qty * price / 10.0:
		_ai_send(g, me, best.id, "BUY_FOOD", qty, price)
