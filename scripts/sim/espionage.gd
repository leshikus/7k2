class_name Espionage
## Spies (ospy.cpp, ospya.cpp, ospy2.cpp, of_campb.cpp): disguise, infiltration,
## sowing dissent, counter-espionage, bribery, assassination, stealing technology,
## creating incidents, reading a kingdom's secret reports and capturing a fort
## whose general has been bought.
##
## A spy unit keeps its own kingdom's nation_id; while disguised its `cloak_id`
## is the kingdom it passes for (the original stores the cloak in nation_recno
## and the true side in the Spy record). An infiltrated spy hides inside a town
## or a fort/camp (`spy_place`). A bribed general or soldier stays in his fort as
## a sleeper (`sleeper_for` = the kingdom he secretly serves).

const BRIBE_AMOUNTS := [500, 1000, 1500, 2000, 3000, 4000]
const MAX_BRIBE_AMOUNT := 4000
const MIN_VIEW_SECRET_SKILL := 20
const MIN_BRIBE_SKILL := 30
const MIN_ASSASSIN_SKILL := 50
const MIN_STEAL_TECH_SKILL := 70
const MIN_INCIDENT_SKILL := 90
const ENEMY_RANGE := 5             # SPY_ENEMY_RANGE: no disguise change with enemies this close
const MIN_CAMOUFLAGE_POWER := 20
const SLEEPER_SKILL := 10          # a bribed unit's spying skill

enum { ASSASSINATE_FAIL, ASSASSINATE_SUCCEED_AT_LARGE, ASSASSINATE_SUCCEED_KILLED }

## Tally of spy events this session (for computer-only test games).
static var stats := {}


static func _log(kind: String) -> void:
	stats[kind] = stats.get(kind, 0) + 1


static func is_camp(p) -> bool:
	return p is Firm and not p.dead and p.code in ["CAMP", "FORT"]


## Where a spy may go: any town, and forts and camps (FirmCamp; the original has
## no spies among workers). A kingdom's fort only takes a spy wearing its colours.
static func can_enter(u: Unit, place: GameObj) -> bool:
	if place == null or place.dead or not u.is_spy:
		return false
	if place is Town:
		return true
	return is_camp(place) and not place.under_construction


static func cloak_needed(u: Unit, place: GameObj) -> int:
	if place.nation_id == u.nation_id or place.nation_id == 0:
		return 0
	return place.nation_id


# ------------------------------------------------------------- disguise ---

## Unit::can_spy_change_nation: only a spy in the field, and only with no enemy
## within ENEMY_RANGE; it can always return to its own colours.
static func can_change_cloak(u: Unit, to_nation: int) -> bool:
	if not u.is_spy or u.dead or u.inside_firm or u.has_meta("hidden"):
		return false
	if to_nation == u.nation_id:
		return true
	if to_nation == 0:
		return not enemy_near(u)
	var g := Game.inst
	var n := g.nation(to_nation)
	if n == null or not n.alive or n.is_fryhtan:
		return false
	return not enemy_near(u)


static func enemy_near(u: Unit) -> bool:
	var g := Game.inst
	var own := g.nation(u.nation_id)
	for o in g.units_near(u.center_loc(), ENEMY_RANGE + 1):
		if o == u or o.dead or o.inside_firm or o.has_meta("hidden"):
			continue
		if maxf(absf(o.loc.x - u.loc.x), absf(o.loc.y - u.loc.y)) > ENEMY_RANGE:
			continue
		if o.is_monster():
			return true
		if o.nation_id > 0 and o.nation_id != u.nation_id and (own == null or own.relation(o.nation_id) != Defs.Relation.ALLIANCE):
			return true
	return false


static func set_cloak(u: Unit, to_nation: int) -> bool:
	if not can_change_cloak(u, to_nation):
		return false
	u.cloak_id = 0 if to_nation == u.nation_id else (INDEPENDENT_CLOAK if to_nation == 0 else to_nation)
	if u.cloak_id == 0:
		stop_camouflage(u)
	u.queue_redraw()
	return true


static func drop_cloak(u: Unit) -> void:
	u.cloak_id = 0
	stop_camouflage(u)
	u.queue_redraw()


## The kingdoms a spy can pass for, its own first.
## The colours a spy can put on (oun_if.cpp disp_spy_cloak): its own, an
## independent's (0), or those of a kingdom its own has met.
static func cloak_choices(u: Unit) -> Array:
	var out := [u.nation_id, 0]
	var own := Game.inst.nation(u.nation_id)
	for n in Game.inst.nations:
		if n.alive and not n.is_fryhtan and n.id != u.nation_id and (own == null or own.contact.has(n.id)):
			out.append(n.id)
	return out


const INDEPENDENT_CLOAK := -1     # cloak_id of a spy passing for an independent


## The kingdom a spy now passes for (0: independent).
static func cloak_nation(u: Unit) -> int:
	if u.cloak_id == INDEPENDENT_CLOAK:
		return 0
	return u.cloak_id if u.cloak_id > 0 else u.nation_id


# ----------------------------------------------------------- camouflage ---

static func max_camouflage(u: Unit) -> int:
	return int(u.spy_skill) / 2 + 15


## Spy::can_camouflage: needs the Camouflage technology and a disguise.
static func can_camouflage(u: Unit) -> bool:
	var n := Game.inst.nation(u.nation_id)
	return u.is_spy and u.camouflage_days <= 0 and u.camouflage_power >= MIN_CAMOUFLAGE_POWER \
		and n != null and n.tech_level("CAMOUFLG") > 0 and u.cloak_id != 0


static func start_camouflage(u: Unit) -> void:
	if not can_camouflage(u):
		return
	u.camouflage_days = u.camouflage_power
	u.camouflage_power = 0


static func stop_camouflage(u: Unit) -> void:
	if u.camouflage_days <= 0:
		return
	u.camouflage_power = mini(max_camouflage(u), u.camouflage_power + u.camouflage_days)
	u.camouflage_days = 0


# --------------------------------------------------------------- places ---

## Infiltrated spies (of any kingdom) in a place.
static func spies_in(place: GameObj) -> Array:
	return Game.inst.spies.filter(func(s): return s.spy_place == place and not s.dead)


static func occupants(f: Firm) -> Array:
	var out: Array = []
	if f.overseer and not f.overseer.dead:
		out.append(f.overseer)
	out.append_array(f.soldiers.filter(func(s): return not s.dead))
	return out


## A unit inside `f` secretly serving `nation` (a bribed general or soldier).
static func is_ours(u: Unit, nation_id: int) -> bool:
	return u.sleeper_for == nation_id


static func tech(nation_id: int, code: String) -> int:
	var n := Game.inst.nation(nation_id)
	return n.tech_level(code) if n else 0


## Persian Greater Being's blessing counts as one more level of spying technology.
static func persian_bonus(nation_id: int) -> int:
	var n := Game.inst.nation(nation_id)
	return 1 if n and n.god_summoned and n.race == "PERSIAN" else 0


# -------------------------------------------------------------- daily ---

## Spy::update_loyalty: towards 50, a quarter of the kingdom's reputation and
## of its ranking, and 20 more for a spy of the kingdom's own race.
static func update_spy_loyalty(g: Game, u: Unit) -> void:
	var n := g.nation(u.nation_id)
	if n == null:
		return
	var t := 50 + int(n.reputation) / 4 + Diplomacy.overall_rank(g, n) / 4
	if u.race == Unit.kingdom_race(n):
		t += 20
	t = mini(t, 100)
	if u.loyalty > t:
		u.loyalty -= 1.0
	elif u.loyalty < t:
		u.loyalty += 1.0


## The kingdom a spy passes for: his disguise in the field, or the colours of
## the place he has slipped into.
static func spy_cloaked_nation(u: Unit) -> int:
	if u.spy_place != null and is_instance_valid(u.spy_place):
		return u.spy_place.nation_id
	return cloak_nation(u)


## Spy::think_betray: below 30, a spy who passes for another kingdom may turn
## to it - its reputation, and its race, against his loyalty.
static func spy_think_betray(g: Game, u: Unit) -> bool:
	if u.loyalty >= Defs.UNIT_BETRAY_LOYALTY:
		return false
	var cn := spy_cloaked_nation(u)
	if cn == u.nation_id or cn <= 0:
		return false
	var n := g.nation(cn)
	if n == null or not n.alive:
		return false
	var score := int(n.reputation)
	if Unit.kingdom_race(n) == u.race:
		score += 30
	if u.loyalty < score or u.loyalty <= 0.0:
		g.notify_nation(u.nation_id, "Your spy %s has gone over to the %s." % [u.display_name(), n.name], u.center_loc())
		drop_identity_in_place(g, u, cn)
		return true
	return false


## Spy::drop_spy_identity for a spy anywhere: in the field he becomes a unit
## of the side he passes for; in a town he becomes one of its people; in a
## fort an ordinary man of it.
static func drop_identity_in_place(g: Game, u: Unit, to: int) -> void:
	if u.spy_place != null and is_instance_valid(u.spy_place):
		var place = u.spy_place
		g.spies.erase(u)
		u.spy_place = null
		if place is Town:
			g.remove_unit(u)           # one of the townspeople now (the town's count already holds him)
			return
		u.remove_meta("hidden")
		u.visible = true
	u.is_spy = false
	u.spy_skill = 0.0
	u.cloak_id = 0
	u.camouflage_days = 0
	if to != u.nation_id:
		g.defect_unit(u, to)


static func next_day(g: Game) -> void:
	var day := g.day
	# infiltrated spies: actions, skill
	var places := {}
	for u in g.spies.duplicate():
		if u.dead or not is_instance_valid(u.spy_place) or u.spy_place.dead:
			g.spy_leave(u)
			continue
		places[u.spy_place] = true
		if day % 30 == u.obj_id % 30 and u.spy_action == "dissent":
			if u.spy_place is Town:
				_town_dissent(u, u.spy_place)
			else:
				_camp_dissent(u, u.spy_place)
		var every := 80 if u.spy_action == "idle" else 40
		if day % every == u.obj_id % every and u.spy_skill < 100.0:
			u.spy_skill += 1.0
	# Spy::next_day: every 60 days a spy's loyalty to his true kingdom moves a
	# point, and one losing faith may go over to the side he passes for
	for u in g.units.duplicate():
		if u.is_spy and not u.dead and u.nation_id > 0 and day % 60 == u.obj_id % 60:
			update_spy_loyalty(g, u)
			spy_think_betray(g, u)
	# counter-espionage: every place looks for intruders once a month
	for p in places:
		if day % 30 == p.obj_id % 30:
			catch_spy(g, p)
	# spies in the field: camouflage runs down or recharges
	for u in g.units:
		if not u.is_spy or u.dead or u.has_meta("hidden"):
			continue
		if u.camouflage_days > 0:
			if u.cloak_id != 0:
				u.camouflage_days -= 1
			else:
				stop_camouflage(u)
		elif u.camouflage_power < max_camouflage(u):
			u.camouflage_power += 1


## Spy::process_town_action: the more people, the longer it takes.
static func _town_dissent(u: Unit, t: Town) -> void:
	if t.population <= spies_in(t).size() or t.nation_id == u.nation_id:
		return
	var dec := u.spy_skill / 4.0 / maxf(1.0, float(t.population))
	dec *= 1.0 + tech(u.nation_id, "AGITATE")
	if t.nation_id == 0:
		t.resistance[u.nation_id] = maxf(0.0, t.resistance_to(u.nation_id) - dec)
		t.think_surrender()
	else:
		t.loyalty = maxf(0.0, t.loyalty - dec)


## Spy::process_firm_action: generals and soldiers of the spy's own race lose loyalty.
static func _camp_dissent(u: Unit, f: Firm) -> void:
	if f.nation_id == u.nation_id:
		return
	var rng := Game.inst.rng
	var lvl := tech(u.nation_id, "AGITATE")
	var o := f.overseer
	if o and o.race == u.race and o.loyalty > 0.0 and o.sleeper_for == 0:
		var r := maxi(1, int(100.0 - u.spy_skill + o.lead_skill()) / 10)
		if rng.randi() % r <= lvl:
			o.loyalty = maxf(0.0, o.loyalty - 1.0)
	for s in f.soldiers:
		if s.race != u.race or s.sleeper_for > 0 or s.loyalty <= 0.0:
			continue
		if rng.randi() % maxi(1, 11 - int(u.spy_skill) / 10) <= lvl:
			s.loyalty -= 1.0


## SpyArray::catch_spy: the defenders' own spies in the place (counter-spies)
## raise the chance; a sleeping spy is very hard to catch.
static func catch_spy(g: Game, place: GameObj) -> void:
	var owner := place.nation_id
	var here := spies_in(place)
	var counter := 0.0
	var enemies := 0
	var lvl := tech(owner, "COUNTERS") if owner > 0 else 0
	for s in here:
		if s.nation_id == owner:
			counter += s.spy_skill + s.spy_skill * lvl / 2.0
		else:
			enemies += 1
	var pop: int = place.population if place is Town else occupants(place).size()
	if enemies >= pop:
		return
	for s in here:
		if s.spy_action == "idle" or s.nation_id == owner:
			continue
		var escape := maxi(int(s.spy_skill) / 10, int(100.0 + s.spy_skill - counter))
		if g.rng.randi() % maxi(1, escape) == 0:
			_log("caught")
			g.spy_caught(s)
			return


# ------------------------------------------------------------- loyalty ---

## FirmCamp::update_loyalty and Unit::update_loyalty for a fort's men: loyalty
## rises gradually toward its target and falls a point a day.
static func update_camp_loyalty(f: Firm) -> void:
	# FirmLair::next_day calls FirmCamp's: a Fryhtan kingdom's lair too
	if f.code == "LAIR" and (f.nation_id <= 0 or f.nation_id == GameObj.MONSTER_NATION):
		return
	for s in f.soldiers:
		_approach(s, soldier_target_loyalty(f, s))
	if f.overseer and f.overseer.rank != Defs.Rank.KING:
		_approach(f.overseer, general_target_loyalty(f, f.overseer))


static func _approach(u: Unit, target: float) -> void:
	if target > u.loyalty:
		u.loyalty = minf(target, u.loyalty + maxf(1.0, floorf((target - u.loyalty) / 10.0)))
	elif target < u.loyalty:
		u.loyalty -= 1.0


## Soldier::target_loyalty
static func soldier_target_loyalty(f: Firm, s: Unit) -> float:
	var o := f.overseer
	if o == null or o.dead:
		return s.loyalty
	var lead := o.lead_skill()
	var t := 30.0 + lead / 2.0 - s.combat / 2.0
	if s.leadership > lead:
		t -= s.leadership - lead
	if o.rank == Defs.Rank.KING:
		t += 20.0
	if s.race == o.race:
		t += 20.0
	if s.sleeper_for > 0:
		t = maxf(t, 30.0 + s.obj_id % 10)
	return clampf(t, 0.0, 100.0)


## Unit::update_loyalty for a general: his command (the people of the towns he
## influences), his race, the kingdom's reputation and the king's leadership.
static func general_target_loyalty(f: Firm, o: Unit) -> float:
	var n := f.nation()
	if n == null:
		return o.loyalty
	var t := float(commander_power(f))
	if Unit.kingdom_race(n) == o.race:
		t += 20.0
	t += n.reputation / 4.0
	if n.king and is_instance_valid(n.king) and not n.king.dead:
		t += n.king.lead_skill() / 4.0
	t -= contribution_penalty(o)
	t = clampf(t, 0.0, 100.0)
	if o.sleeper_for > 0:
		t = maxf(t, 30.0 + o.obj_id % 10)
	return t


## Unit::update_loyalty: a general rewarded less than half of what he has
## done for the kingdom grows unhappy (up to 50 points).
static func contribution_penalty(o: Unit) -> float:
	if o.nation_contribution > o.total_reward * 2:
		return minf(50.0, (o.nation_contribution - o.total_reward * 2) / 2.0)
	return 0.0


## Unit::update_loyalty for a unit out in the field (monthly): a general by
## the men he leads, a soldier by his general - and a soldier with no
## general drifts to nothing; villagers keep theirs.
static func update_unit_loyalty(u: Unit) -> void:
	var n := u.nation()
	if n == null or u.rank == Defs.Rank.KING or not u.has_loyalty() or u.is_civilian() or u.is_weapon:
		return
	var t := 0.0
	if u.rank >= Defs.Rank.GENERAL:
		var led := Game.inst.units.filter(func(m): return m.leader == u and not m.dead and m.inside_firm == null).size()
		t = led * 3.0
		if Unit.kingdom_race(n) == u.race:
			t += 20.0
		t += n.reputation / 4.0
		if n.king and is_instance_valid(n.king) and not n.king.dead:
			t += n.king.lead_skill() / 4.0
		t -= contribution_penalty(u)
		t = clampf(t, 0.0, 100.0)
		if u.is_spy:
			t = maxf(t, 30.0 + u.obj_id % 10)
	else:
		var l := u.leader
		if l and is_instance_valid(l) and not l.dead:
			var lead := l.lead_skill()
			t = 30.0 + lead - u.combat / 2.0 - u.lead_skill()
			if l.rank == Defs.Rank.KING:
				t += 20.0
			if l.race == u.race:
				t += 20.0
			t = clampf(t, 0.0, 100.0)
		else:
			t = 0.0
	_approach(u, t)


## Unit::think_betray (every 15 days): below 30 a unit in the field, or the
## commander of a camp with his whole camp, goes over to the kingdom with
## the best reputation and standing; with none and no loyalty left, he leaves.
static func think_betray(g: Game, u: Unit) -> void:
	if u.dead or u.is_spy or u.sleeper_for > 0 or u.rank == Defs.Rank.KING or not u.has_loyalty() or u.is_civilian():
		return
	if u.nation_id <= 0 or u.home_town != null or u.home_firm != null or u.loyalty >= Defs.UNIT_BETRAY_LOYALTY:
		return
	if u.inside_firm != null and u.inside_firm.overseer != u:
		return
	var cur := u.nation()
	if cur == null:
		return
	var best := 0
	var best_s := -100 if u.loyalty <= 0.0 else int(u.loyalty)
	for o in g.nations:
		if not o.alive or o == cur or not cur.contact.has(o.id) or o.is_fryhtan != cur.is_fryhtan:
			continue
		if not g.towns.any(func(t): return t.nation_id == o.id and not t.dead):
			continue
		var s := int(o.reputation) + Diplomacy.overall_rank(g, o) - Diplomacy.overall_rank(g, cur)
		if o.race == u.race:
			s += 30
		if s > best_s:
			best_s = s
			best = o.id
	if best > 0:
		betray(g, u, best)
	elif u.loyalty <= 0.0 and u.inside_firm == null:
		g.notify_nation(u.nation_id, "%s has left your service." % u.display_name(), u.center_loc())
		g.remove_unit(u)


## Unit::betray: the unit (a commander with his camp, a general with his
## men) changes side, at a loyalty of 40-60 lifted by the new kingdom's
## reputation and race.
static func betray(g: Game, u: Unit, to: int) -> void:
	var old := u.nation_id
	var team: Array = g.units.filter(func(m): return m.leader == u and not m.dead and m.inside_firm == null)
	if u.inside_firm != null:
		AIFirm.firm_captured(u.inside_firm, to)       # FirmCamp: the whole camp goes over
		u.inside_firm.change_nation(to)
		g.update_links()
	else:
		var rank := u.rank
		g.defect_unit(u, to)
		u.rank = rank
		for m in team:
			g.defect_unit(m, to)
			m.leader = u
	var n := g.nation(to)
	u.loyalty = float(Defs.UNIT_BETRAY_LOYALTY + 10 + g.rng.randi() % 20)
	if n.reputation > 0.0:
		u.loyalty += n.reputation
	if Unit.kingdom_race(n) == u.race:
		u.loyalty += 30.0
	u.loyalty = clampf(u.loyalty, 0.0, 100.0)
	g.notify_nation(old, "%s has betrayed you and gone over to the %s." % [u.display_name(), n.name], u.center_loc())
	g.notify_nation(to, "%s has come over to your side." % u.display_name(), u.center_loc())


## Unit::commander_power: villagers of the linked own towns, shared among their camps.
static func commander_power(f: Firm) -> int:
	var p := 0
	for t in f.linked_towns:
		if t.nation_id != f.nation_id:
			continue
		var camps := t.linked_firms.filter(func(x): return is_camp(x) and x.nation_id == t.nation_id and x.overseer != null).size()
		if camps > 0:
			p += t.population / camps
	return p + f.soldiers.size() * 3       # and 3 for every soldier under him


# --------------------------------------------------------------- bribe ---

## FirmCamp::can_spy_bribe: not the king, not a war machine, not our own man.
static func can_bribe(f: Firm, target: Unit, briber: int) -> bool:
	if target == null or target.dead or target.inside_firm != f:
		return false
	if target.sleeper_for == briber or target.nation_id == briber:
		return false
	return target.is_human() and not target.is_weapon and target.rank != Defs.Rank.KING


## FirmCamp::spy_bribe_succeed_chance
static func bribe_chance(spy: Unit, f: Firm, target: Unit, amount: int) -> int:
	if target.sleeper_for > 0:
		return 0                     # already somebody's spy
	var n := Game.inst.nation(spy.nation_id)
	var lvl := tech(spy.nation_id, "BRIBE") + persian_bonus(spy.nation_id)
	var loyalty := int(target.loyalty)
	var command := commander_power(f) if target == f.overseer else 0
	var chance := int(spy.spy_skill) - loyalty - command + int(n.reputation if n else 0.0) \
		+ 200 * (1 + lvl) * amount / MAX_BRIBE_AMOUNT
	if spy.race == target.race:
		chance += 10
	if n and n.race == target.race:
		chance += 10
	if loyalty > 60:
		chance -= loyalty - 60
	if loyalty >= 100:
		chance = 0
	return chance


## FirmCamp::spy_bribe: the gold is spent either way; failure costs the spy.
static func bribe(spy: Unit, f: Firm, target: Unit, amount: int) -> bool:
	var g := Game.inst
	var n := g.nation(spy.nation_id)
	if n == null or not can_bribe(f, target, spy.nation_id) or n.cash < amount or spy.spy_place != f:
		return false
	var chance := bribe_chance(spy, f, target, amount)
	n.add_cash(-float(amount), "Spies")
	if chance > 0 and g.rng.randi() % 100 < chance:
		target.sleeper_for = spy.nation_id
		target.loyalty = clampf(float(chance), 30.0, 100.0)
		target.set_meta("sleeper_skill", SLEEPER_SKILL)
		_log("bribe_ok")
		g.notify_nation(spy.nation_id, "%s has taken your bribe and now secretly serves you." % target.display_name(), f.center_loc())
		return true
	_log("bribe_fail")
	g.notify_nation(spy.nation_id, "The bribe was refused. Your spy %s has been exposed and executed." % spy.unit_name, f.center_loc())
	g.notify_nation(f.nation_id, "A spy tried to bribe %s in %s and was executed." % [target.display_name(), f.display_name()], f.center_loc())
	g.kill_spy(spy)
	return false


## Spy::capture_firm: a fort whose general is our man changes sides. Soldiers
## who will not follow him (other races, weak leadership) walk out and attack.
static func can_capture(f: Firm, nation_id: int) -> bool:
	return is_camp(f) and f.nation_id != nation_id and f.overseer != null and f.overseer.sleeper_for == nation_id


static func capture(f: Firm, nation_id: int) -> bool:
	if not can_capture(f, nation_id):
		return false
	var g := Game.inst
	var gen := f.overseer
	var rep := g.nation(nation_id).reputation if g.nation(nation_id) else 0.0
	var old := f.nation_id
	AIFirm.firm_captured(f, nation_id)
	var leaving: Array = []
	for s in f.soldiers:
		if s.sleeper_for == nation_id:
			continue
		var obey := int(gen.lead_skill() / 2.0 + rep / 2.0)
		if s.race == gen.race:
			obey += 50
		if g.rng.randi() % 100 < obey:
			s.loyalty = maxf(Defs.UNIT_BETRAY_LOYALTY, obey / 2.0)
		else:
			leaving.append(s)
	for s in leaving:
		f.release_unit(s, f)
	g.notify_nation(old, "%s has been captured by the %s: its general was a spy!" % [f.display_name(), g.nation(nation_id).name], f.center_loc(), true)
	g.notify_nation(nation_id, "Your bribed general has handed %s over to you." % f.display_name(), f.center_loc())
	f.change_nation(nation_id)
	_log("capture")
	if g.observer():
		g.notify("Bribed general hands %s to the %s." % [f.display_name(), g.nation(nation_id).name], f.center_loc())
	for s in leaving:
		if not s.dead and s.target == f:
			s.order_attack(f)
	return true


# ----------------------------------------------------------- assassinate ---

## Spy::get_assassinate_rating -> [attack, defense, other defenders]; the chance is
## (attack - defense) percent.
static func assassinate_rating(spy: Unit, f: Firm) -> Array:
	var target := f.overseer
	if target == null:
		return [0, 0, 0]
	var lvl := tech(spy.nation_id, "ASSASSIN") + persian_bonus(spy.nation_id)
	var counter := tech(f.nation_id, "COUNTERS")
	var attack := spy.spy_skill + spy.hp / 2.0 + 50.0 * lvl
	var defense := target.hp / 2.0
	var others := 0
	if target.rank == Defs.Rank.KING:
		defense += 50.0
	for s in spies_in(f):
		if s == spy:
			continue
		if s.nation_id == spy.nation_id:
			attack += floorf(s.spy_skill / 4.0) * (1 + lvl)
		elif s.nation_id == f.nation_id:
			defense += floorf(s.spy_skill / 2.0) * (1 + counter)
			others += 1
	for s in f.soldiers:
		if s.sleeper_for == spy.nation_id:
			attack += floorf(SLEEPER_SKILL / 4.0) * (1 + lvl)
		else:
			defense += 4.0 + floorf(s.hp / 20.0)
			others += 1
	return [int(attack * 3.0), int(defense * 3.0 + 100.0), others]


static func assassinate_chance(spy: Unit, f: Firm) -> int:
	var r := assassinate_rating(spy, f)
	return clampi(r[0] - r[1], 0, 100)


static func can_assassinate(spy: Unit, f: Firm) -> bool:
	return spy.spy_place == f and is_camp(f) and f.nation_id != spy.nation_id and f.overseer != null \
		and f.overseer.sleeper_for != spy.nation_id and spy.spy_skill >= MIN_ASSASSIN_SKILL


## Spy::assassinate
static func assassinate(spy: Unit, f: Firm) -> int:
	var g := Game.inst
	if not can_assassinate(spy, f):
		return -1
	var r := assassinate_rating(spy, f)
	var target := f.overseer
	var who := target.display_name()
	if g.rng.randi() % 100 < r[0] - r[1]:
		var killed: bool = r[2] > 0 and not (g.rng.randi() % 100 < r[0] - r[1] - 20)
		g.notify_nation(f.nation_id, "%s of %s has been assassinated!" % [who, f.display_name()], f.center_loc())
		g.kill_inside(f, target)
		_log("assassinate_ok")
		if g.observer():
			g.notify("%s of the %s has been assassinated." % [who, g.nation(f.nation_id).name if g.nation(f.nation_id) else "?"], f.center_loc())
		if killed:
			g.notify_nation(spy.nation_id, "%s was assassinated, but your spy was caught and executed." % who, f.center_loc())
			g.kill_spy(spy)
			return ASSASSINATE_SUCCEED_KILLED
		g.notify_nation(spy.nation_id, "Your spy has assassinated %s and remains at large." % who, f.center_loc())
		return ASSASSINATE_SUCCEED_AT_LARGE
	_log("assassinate_fail")
	g.notify_nation(f.nation_id, "An assassin was caught in %s before he could strike at %s." % [f.display_name(), who], f.center_loc())
	g.notify_nation(spy.nation_id, "Your spy failed to assassinate %s and was executed." % who, f.center_loc())
	g.kill_spy(spy)
	return ASSASSINATE_FAIL


# ----------------------------------------------- steal tech, incidents ---

## Spy::get_steal_rating (and get_incident_rating, which also counts the
## involved kingdom's spies as resisters).
static func steal_rating(spy: Unit, f: Firm, involved := -1) -> int:
	var chance := spy.spy_skill + 10.0 * persian_bonus(spy.nation_id)
	var counter := tech(f.nation_id, "COUNTERS")
	var sum_resist := 0.0
	var max_resist := 0.0
	var resist := 0
	var assist := 0.0
	for s in spies_in(f) + occupants(f).filter(func(o): return o.sleeper_for > 0):
		if s == spy:
			continue
		var skill: float = s.spy_skill if s.is_spy else float(SLEEPER_SKILL)
		var side: int = s.nation_id if s.is_spy else s.sleeper_for
		if side == f.nation_id or (involved > 0 and side == involved):
			sum_resist += skill
			max_resist = maxf(max_resist, skill)
			resist += 1
		if side == spy.nation_id:
			assist += skill
	if resist == 0:
		chance -= 20.0 - assist / 10.0
	elif counter > 0:
		chance -= 16.0 + sum_resist / 5.0 + max_resist / 5.0 - assist / 8.0
	else:
		chance -= 16.0 + sum_resist / 8.0 + max_resist / 8.0 - assist / 10.0
	return clampi(int(chance), 0, 100)


static func can_steal_tech(spy: Unit, f: Firm) -> bool:
	return spy.spy_place == f and is_camp(f) and f.nation_id > 0 and f.nation_id != spy.nation_id \
		and spy.spy_skill >= MIN_STEAL_TECH_SKILL and tech(spy.nation_id, "STEALTEC") > 0


## Spy::steal_tech: one technology the victim knows better, chosen at random.
## Returns the tech code, "" when there was nothing to take, or null on failure.
static func steal_tech(spy: Unit, f: Firm) -> Variant:
	var g := Game.inst
	if not can_steal_tech(spy, f):
		return null
	var mine := g.nation(spy.nation_id)
	var theirs := g.nation(f.nation_id)
	if g.rng.randi() % 100 < steal_rating(spy, f):
		var pick := ""
		var n := 0
		for t in Defs.TECHS:
			var c: String = t["code"]
			if theirs.tech_level(c) > mine.tech_level(c):
				n += 1
				if g.rng.randi() % n == 0:
					pick = c
		if pick != "":
			_log("steal_ok")
			mine.tech[pick] = theirs.tech_level(pick)
			g.notify_nation(spy.nation_id, "Your spy stole the secret of %s!" % Defs.tech_def(pick)["name"], f.center_loc())
		else:
			g.notify_nation(spy.nation_id, "The %s know nothing you do not." % theirs.name, f.center_loc())
		return pick
	_log("steal_fail")
	g.notify_nation(spy.nation_id, "Your spy was caught stealing secrets and executed.", f.center_loc())
	g.notify_nation(f.nation_id, "A spy was caught stealing secrets in %s." % f.display_name(), f.center_loc())
	g.kill_spy(spy)
	return null


static func can_create_incident(spy: Unit, f: Firm) -> bool:
	return spy.spy_place == f and is_camp(f) and f.nation_id > 0 and f.nation_id != spy.nation_id \
		and spy.spy_skill >= MIN_INCIDENT_SKILL and tech(spy.nation_id, "INCIDENT") > 0


## Kingdoms the camp's owner can be made to quarrel with.
static func incident_choices(spy: Unit, f: Firm) -> Array:
	var out: Array = []
	for n in Game.inst.nations:
		if n.alive and n.id != f.nation_id and n.id != spy.nation_id and not n.is_fryhtan:
			out.append(n.id)
	return out


## Spy::create_incident -> TalkRes::create_incident: the camp's kingdom breaks
## its treaties with the involved kingdom and the two go to war.
static func create_incident(spy: Unit, f: Firm, involved: int) -> bool:
	var g := Game.inst
	if not can_create_incident(spy, f) or not involved in incident_choices(spy, f):
		return false
	if g.rng.randi() % 100 < steal_rating(spy, f, involved):
		var a := g.nation(f.nation_id)
		var b := g.nation(involved)
		g.declare_war(a.id, b.id)
		_log("incident")
		g.notify("An incident at %s: the %s and the %s are at war!" % [f.display_name(), a.name, b.name], f.center_loc())
		return true
	g.notify_nation(spy.nation_id, "Your spy was caught staging an incident and executed.", f.center_loc())
	g.kill_spy(spy)
	return false


## SpyArray::needed_view_secret_skill / the "view secret" report: a kingdom's
## treasury, armies and research, read by a spy inside one of its places.
static func can_view_secret(spy: Unit) -> bool:
	return spy.has_meta("hidden") and spy.spy_place != null and is_instance_valid(spy.spy_place) \
		and spy.spy_place.nation_id > 0 and spy.spy_place.nation_id != spy.nation_id \
		and spy.spy_skill >= MIN_VIEW_SECRET_SKILL and tech(spy.nation_id, "STEALINF") > 0


static func secret_report(g: Game, nation_id: int) -> String:
	var n := g.nation(nation_id)
	if n == null:
		return ""
	var soldiers := g.units.filter(func(u): return u.nation_id == n.id and not u.dead and u.is_human() and not u.is_civilian()).size()
	var weapons := g.units.filter(func(u): return u.nation_id == n.id and not u.dead and u.is_weapon).size()
	var s := "[b]Secret report: %s[/b]\nTreasury %d gold, food %d\nIncome this year %d, expenses %d\n" % [n.name, int(n.cash), int(n.food), int(n.income_year), int(n.expense_year)]
	s += "Soldiers %d, war machines %d, towns %d, buildings %d\n" % [soldiers, weapons,
		g.towns.filter(func(t): return t.nation_id == n.id and not t.dead).size(), g.firms.filter(func(f): return f.nation_id == n.id and not f.dead).size()]
	var techs := []
	for k in n.tech:
		if n.tech[k] > 0:
			techs.append("%s %d" % [Defs.tech_def(k).get("name", k), n.tech[k]])
	s += "Technology: %s\n" % (", ".join(techs) if not techs.is_empty() else "none")
	var rel := []
	for o in g.nations:
		if o != n and o.alive:
			rel.append("%s: %s" % [o.name, Defs.RELATION_NAMES[n.relation(o.id)]])
	s += "Relations: %s\n" % ", ".join(rel)
	return s
