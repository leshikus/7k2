class_name AISpy
extends RefCounted
## A computer kingdom's espionage: the college trains a spy only when it has
## a target for one and sends trained spies out (of_spya.cpp); targets are
## camps with a disloyal commander, inns, towns of the spy's race, or our own
## towns short of counter-spies (oai_spy.cpp); and each spy thinks for itself
## (ospy2.cpp): rewarded to stay loyal, sowing dissent in towns, capturing,
## bribing, assassinating, stealing technology or staging incidents in camps,
## and when out in the field finding a new target or dropping its identity.

const MIN_NATION_DEFEND_LOYALTY := 30
const MIN_INDEPENDENT_DEFEND_LOYALTY := 30


static func process_all(ai: NationAI, day: int) -> void:
	for u in ai.g.units.duplicate():
		if u.is_spy and not u.dead and u.nation_id == ai.n.id:
			process(ai, u, day)


static func spies_of(ai: NationAI) -> Array:
	return ai.g.units.filter(func(u): return u.is_spy and not u.dead and u.nation_id == ai.n.id)


static func _spy_expense_365(n: Nation) -> float:
	return n._y365(float(n.last_expense_by.get("Spies", 0.0)), float(n.expense_by.get("Spies", 0.0)))


static func _too_many(ai: NationAI, pref_key: String) -> bool:
	var n := ai.n
	if spies_of(ai).size() > ai.total_population() * (10 + ai.pref("spy") / 5) / 100:
		return true
	return _spy_expense_365(n) > n.expense_365() * (50 + ai.pref(pref_key)) / 400.0


# ------------------------------------------------------------ targets ---

## Nation::think_assign_spy_target_camp: a foreign camp with a commander of
## the spy's race and room, the least loyal commander first.
static func target_camp(ai: NationAI, race: String) -> Firm:
	var best: Firm = null
	var best_r := 0
	for f in ai.g.firms:
		if f.dead or f.nation_id == ai.n.id or not Espionage.is_camp(f) or f.overseer == null:
			continue
		if f.soldiers.size() >= NationAI.MAX_SOLDIER or AIFirm.majority_race(f) != race:
			continue
		if f.overseer.sleeper_for > 0 or f.overseer.is_spy:
			continue
		var r := 100 - int(f.overseer.loyalty)
		if r > best_r:
			best_r = r
			best = f
	return best


## Nation::think_assign_spy_target_inn: any foreign inn, from a random start.
static func target_inn(ai: NationAI) -> Firm:
	var inns: Array = ai.g.firms.filter(func(f): return not f.dead and f.code == "INN" and f.nation_id != ai.n.id)
	if inns.is_empty():
		return null
	return inns[ai.g.rng.randi() % inns.size()]


## Nation::think_assign_spy_target_town: a foreign or independent town of the
## spy's race whose loyalty or resistance is still worth lowering.
static func target_town(ai: NationAI, race: String) -> Town:
	var towns: Array = ai.g.towns.filter(func(t): return not t.dead)
	if towns.is_empty():
		return null
	var start := ai.g.rng.randi() % towns.size()
	for i in towns.size():
		var t: Town = towns[(start + i + 1) % towns.size()]
		if t.nation_id == ai.n.id or t.population > Defs.MAX_TOWN_POPULATION - 5 or t.under_construction:
			continue
		var tn := ai.g.nation(t.nation_id) if t.nation_id > 0 else null
		if tn and not tn.is_ai and ai.g.rng.randi() % 3 != 0:
			continue        # the player's towns less often
		if t.nation_id > 0:
			if t.loyalty < MIN_NATION_DEFEND_LOYALTY:
				continue
		elif t.resistance_to(ai.n.id) < MIN_INDEPENDENT_DEFEND_LOYALTY:
			continue
		if t.race != race:
			continue
		return t
	return null


## Town::needed_anti_spy_level
static func needed_anti_spy_level(ai: NationAI, t: Town) -> int:
	return (t.linked_firms.size() * 10 + 100 * t.population / Defs.MAX_TOWN_POPULATION) * ai.pref("counter_spy") / 100


## Nation::think_assign_spy_own_town: one of our towns of the spy's race
## whose counter-spies fall short.
static func target_own_town(ai: NationAI, race: String) -> Town:
	var towns := ai.my_towns()
	if towns.is_empty():
		return null
	var start := ai.g.rng.randi() % towns.size()
	for i in towns.size():
		var t: Town = towns[(start + i + 1) % towns.size()]
		if t.population > Defs.MAX_TOWN_POPULATION - 5 or t.race != race:
			continue
		var level := 0
		for s in Espionage.spies_in(t):
			if s.nation_id == ai.n.id:
				level += int(s.spy_skill)
		if needed_anti_spy_level(ai, t) > level + 30:
			return t
	return null


static func _counter_spy_roll(ai: NationAI) -> bool:
	var c := ai.pref("counter_spy")
	if c < 25:
		return ai.g.rng.randi() % 3 == 0
	if c < 75:
		return ai.g.rng.randi() % 2 == 0
	return ai.g.rng.randi() % 3 != 0


# ------------------------------------------------------------ college ---

## FirmSpy::process_ai
static func college(ai: NationAI, f: Firm, day: int) -> void:
	if day % 30 == f.obj_id % 30:
		_train_new(ai, f)
	if day % 30 == (f.obj_id + 15) % 30:
		_spy_action(ai, f)
	if day % 30 == f.obj_id % 30 and f.linked_towns.is_empty():
		AIFirm.del_firm(ai, f)


## FirmSpy::think_train_new: a civilian spy for a town (ours or a target) or
## a military one for a camp, only when there is somewhere to send it.
static func _train_new(ai: NationAI, f: Firm) -> void:
	if ai.total_population() < 30 - ai.pref("spy") / 10:
		return
	if spies_of(ai).size() > ai.total_population() * (10 + ai.pref("spy") / 5) / 100:
		return
	if not ai.should_spend(25 + ai.pref("spy") / 2):
		return
	if _spy_expense_365(ai.n) > ai.n.expense_365() * (50 + ai.pref("spy")) / 400.0:
		return
	if f.linked_towns.is_empty():
		return
	var start := ai.g.rng.randi() % f.linked_towns.size()
	for i in f.linked_towns.size():
		var t: Town = f.linked_towns[(start + i + 1) % f.linked_towns.size()]
		if ai.g.rng.randi() % 2 == 0:
			if _has_spy(f, t.race, true):
				continue
			if Training.can_train_from_town(f, t, Training.CIVILIAN):
				var ok := target_own_town(ai, t.race) != null if _counter_spy_roll(ai) else target_town(ai, t.race) != null
				if ok:
					Training.recruit(f, t, Training.CIVILIAN)
					return
		else:
			if _has_spy(f, t.race, false):
				continue
			var type := Training.INFANTRY if ai.g.rng.randi() % 2 == 0 else Training.SPECIAL
			if Training.can_train_from_town(f, t, type) and target_camp(ai, t.race) != null:
				Training.recruit(f, t, type)
				return


static func _has_spy(f: Firm, race: String, civilian: bool) -> bool:
	return f.trainees.any(func(rec): return rec["race"] == race and (int(rec["type"]) == Training.CIVILIAN) == civilian)


## FirmSpy::think_spy_action: a trained spy is sent out to its target (less
## often when the kingdom's reputation is bad).
static func _spy_action(ai: NationAI, f: Firm) -> void:
	if ai.n.reputation < 0.0 and ai.g.rng.randi() % maxi(1, int(-ai.n.reputation / 5.0)) != 0:
		return
	if f.trainees.is_empty():
		return
	var start := ai.g.rng.randi() % f.trainees.size()
	for k in f.trainees.size():
		var i := (start + k + 1) % f.trainees.size()
		var rec: Dictionary = f.trainees[i]
		if rec.get("training", false):
			continue
		var place: GameObj = null
		if int(rec["type"]) == Training.CIVILIAN:
			place = target_own_town(ai, rec["race"]) if _counter_spy_roll(ai) else target_town(ai, rec["race"])
		else:
			place = target_camp(ai, rec["race"])
			if place == null:
				place = target_inn(ai)
		if place == null:
			continue
		var u := Training.mobilize(f, i)
		if u == null:
			continue
		if not ai.add_action(Vector2i(place.x1, place.y1), Vector2i(-1, -1), NationAI.ASSIGN_SPY, place.nation_id, 1, u).is_empty():
			return


# -------------------------------------------------------- each spy ---

## Spy::process_ai
static func process(ai: NationAI, u: Unit, day: int) -> void:
	var id := u.obj_id
	if day % 30 == id % 30:
		_think_reward(ai, u)
	var place = u.spy_place
	if place != null and is_instance_valid(place) and u.has_meta("hidden"):
		if day % 30 == id % 30:
			if place is Town:
				_think_town_spy(ai, u, place)
			elif place is Firm:
				_think_firm_spy(ai, u, place)
	elif u.inside_firm == null and day % 5 == id % 5:
		if u.order == Unit.Order.IDLE and u.ai_action_id == 0 and u.cloak_id == 0:
			_think_mobile_new_action(ai, u)


## Spy::think_reward
static func _think_reward(ai: NationAI, u: Unit) -> void:
	var need := clampi(int(u.spy_skill) * (100 + ai.pref("loyalty_concern")) / 100, Defs.UNIT_BETRAY_LOYALTY + 10, 100)
	if u.loyalty >= need:
		return
	var r := need - int(u.loyalty)
	if u.loyalty < Defs.UNIT_BETRAY_LOYALTY + 5:
		r += 50
	if ai.should_spend(r):
		u.reward(ai.n.id)


## Spy::think_town_spy: in a village, dissent until its resistance is low,
## then out; in a kingdom's town, mostly asleep (to learn) unless its
## loyalty is already low.
static func _think_town_spy(ai: NationAI, u: Unit, t: Town) -> void:
	if t.nation_id == ai.n.id:
		return
	if t.nation_id == 0:
		u.spy_action = "dissent"
		if t.resistance_to(ai.n.id) < MIN_INDEPENDENT_DEFEND_LOYALTY:
			ai.g.spy_leave(u)
	elif t.loyalty < 50 - ai.pref("loyalty_concern") / 10:
		u.spy_action = "dissent"
	else:
		u.spy_action = "dissent" if ai.g.rng.randi() % 5 == 0 else "idle"


## Spy::think_firm_spy: capture, bribe, assassinate, steal, stage an incident,
## or else idle now and then and sow dissent.
static func _think_firm_spy(ai: NationAI, u: Unit, f: Firm) -> void:
	if f.nation_id == ai.n.id:
		return
	if Espionage.can_capture(f, ai.n.id) and Espionage.capture(f, ai.n.id):
		return
	if _think_bribe(ai, u, f):
		return
	if _think_assassinate(ai, u, f):
		return
	if _think_steal_tech(ai, u, f):
		return
	if _think_create_incident(ai, u, f):
		return
	u.spy_action = "idle" if ai.g.rng.randi() % 3 == 0 else "dissent"


## Spy::think_bribe
static func _think_bribe(ai: NationAI, u: Unit, f: Firm) -> bool:
	if u.spy_skill < Espionage.MIN_BRIBE_SKILL or not Espionage.is_camp(f) or f.overseer == null:
		return false
	var o := f.overseer
	if not Espionage.can_bribe(f, o, ai.n.id):
		return false
	if u.spy_skill < minf(50.0, o.lead_skill()) or not ai.should_spend(30):
		return false
	var chance := Espionage.bribe_chance(u, f, o, 0)
	var amount := maxi(100, Espionage.MAX_BRIBE_AMOUNT * (100 - chance) / 100)
	if not ai.should_spend(30, float(amount)):
		return false
	if Espionage.bribe(u, f, o, amount) and Espionage.can_capture(f, ai.n.id):
		Espionage.capture(f, ai.n.id)
	return true


## Spy::think_assassinate
static func _think_assassinate(ai: NationAI, u: Unit, f: Firm) -> bool:
	if u.spy_skill < Espionage.MIN_ASSASSIN_SKILL or not Espionage.is_camp(f) or f.overseer == null:
		return false
	if not Espionage.can_assassinate(u, f):
		return false
	var r := Espionage.assassinate_rating(u, f)
	if int(r[0]) - int(r[1]) + ai.g.rng.randi() % (20 + ai.pref("spy") / 4) > 100:
		Espionage.assassinate(u, f)
		return true
	return false


## Spy::think_steal_tech
static func _think_steal_tech(ai: NationAI, u: Unit, f: Firm) -> bool:
	if u.spy_skill < Espionage.MIN_STEAL_TECH_SKILL or not Espionage.is_camp(f) or f.nation_id <= 0:
		return false
	if not Espionage.can_steal_tech(u, f):
		return false
	if Espionage.steal_rating(u, f) + ai.g.rng.randi() % (20 + ai.pref("spy") / 2) > 100:
		Espionage.steal_tech(u, f)
		return true
	return false


## Spy::think_create_incident: in a fort, between its kingdom and another
## not at war with it (never an ally of ours).
static func _think_create_incident(ai: NationAI, u: Unit, f: Firm) -> bool:
	if u.spy_skill < Espionage.MIN_INCIDENT_SKILL or f.code != "FORT" or f.nation_id <= 0:
		return false
	var tn := ai.g.nation(f.nation_id)
	if tn == null or tn.relation(ai.n.id) == Defs.Relation.ALLIANCE or not Espionage.can_create_incident(u, f):
		return false
	var best := 0
	var best_r := 0
	for o in ai.g.nations:
		if not o.alive or o.id == tn.id or o.id == ai.n.id:
			continue
		if o.relation(ai.n.id) == Defs.Relation.ALLIANCE or tn.relation(o.id) == Defs.Relation.WAR:
			continue
		if not o.id in Espionage.incident_choices(u, f):
			continue
		var r := Espionage.steal_rating(u, f, o.id)
		if r > best_r:
			best_r = r
			best = o.id
	if best > 0 and best_r + ai.g.rng.randi() % (25 + ai.pref("spy") / 2) > 100:
		Espionage.create_incident(u, f, best)
		return true
	return false


## Spy::think_mobile_spy_new_action: a camp (military spies) or a town
## (civilians) to go into; else a town of ours needing counter-spies; with too
## many spies or nowhere to go, the spy becomes an ordinary unit again.
static func _think_mobile_new_action(ai: NationAI, u: Unit) -> void:
	var place: GameObj = null
	if not u.is_civilian():
		place = target_camp(ai, u.race)
	else:
		place = target_town(ai, u.race)
	if place:
		ai.add_action(Vector2i(place.x1, place.y1), Vector2i(-1, -1), NationAI.ASSIGN_SPY, place.nation_id, 1, u)
		return
	var drop := _too_many(ai, "counter_spy")
	if not drop:
		var own := target_own_town(ai, u.race)
		if own:
			ai.add_action(Vector2i(own.x1, own.y1), Vector2i(-1, -1), NationAI.ASSIGN_SPY, own.nation_id, 1, u)
			return
		drop = true
	if drop:
		# Spy::drop_spy_identity
		Espionage.drop_cloak(u)
		u.is_spy = false
