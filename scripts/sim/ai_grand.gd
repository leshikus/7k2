class_name AIGrand
extends RefCounted
## The grand plans (oai_gran.cpp): finishing off a beaten enemy, rallying
## allies and embargoes against the others, striking the human player's mines
## when he holds them all, leaning on the strongest kingdom for tribute,
## surrendering when all is lost, and uniting under the second-best computer
## kingdom against a human player who has outgrown them all (on_human.cpp).


## Nation::think_grand_plan
static func think_grand_plan(ai: NationAI) -> void:
	think_deal_with_all_enemy(ai)
	think_against_mine_monopoly(ai)
	think_ally_against_big_enemy(ai)


static func total_enemy_count(ai: NationAI) -> int:
	return ai.g.nations.filter(func(o): return o.alive and o != ai.n and ai.relation(o.id) == Defs.Relation.WAR).size()


## Nation::total_alliance_military
static func total_alliance_military(ai: NationAI) -> int:
	var p := ai.military_rank()
	for o in ai.g.nations:
		if o.alive and o != ai.n and ai.relation(o.id) == Defs.Relation.ALLIANCE:
			p += Diplomacy.military_rank(ai.g, o) * 3 / 4
	return p


static func _population(g: Game, nid: int) -> int:
	var p := 0
	for t in g.towns:
		if t.nation_id == nid and not t.dead:
			p += t.population
	return p


## Nation::think_deal_with_all_enemy: a beaten or feeble last enemy is hunted
## down - its buildings, then towns, then units; others are dealt with by
## diplomacy.
static func think_deal_with_all_enemy(ai: NationAI) -> void:
	var ours := ai.military_rank()
	var enemies := total_enemy_count(ai)
	for o in ai.g.nations:
		if not o.alive or o == ai.n or ai.relation(o.id) != Defs.Relation.WAR:
			continue
		var finish := _population(ai.g, o.id) == 0
		if enemies == 1 and ours > 100 - ai.pref("military_courage") / 5:
			var theirs := Diplomacy.military_rank(ai.g, o)
			if theirs < 20 and ai.should_spend_war(theirs):
				finish = true
		if finish:
			if _eliminate_firm(ai, o.id):
				continue
			if _eliminate_town(ai, o.id):
				continue
			_eliminate_unit(ai, o.id)
			continue
		_deal_with_one_enemy(ai, o.id)


## Nation::think_deal_with_one_enemy
static func _deal_with_one_enemy(ai: NationAI, enemy: int) -> void:
	var g := ai.g
	for o in g.nations:
		if not o.alive or o == ai.n or o.id == enemy:
			continue
		if o.is_fryhtan != ai.n.is_fryhtan:
			continue
		var theirs := o.relation(ai.n.id)
		if theirs == Defs.Relation.ALLIANCE and o.relation(enemy) != Defs.Relation.WAR:
			if Diplomacy._may_retry(g, ai.n, "REQUEST_WAR", o.id):
				Diplomacy._ai_send(g, ai.n, o.id, "REQUEST_WAR", enemy)
				continue
		if o.relation(enemy) < Defs.Relation.PEACE:
			if theirs >= Defs.Relation.NEUTRAL and Diplomacy.has_trade(o, enemy):
				if Diplomacy._may_retry(g, ai.n, "EMBARGO", o.id):
					Diplomacy._ai_send(g, ai.n, o.id, "EMBARGO", enemy)
		elif theirs != Defs.Relation.WAR:
			if not Diplomacy.has_trade(o, ai.n.id):
				if Diplomacy._may_retry(g, ai.n, "TRADE", o.id):
					Diplomacy._ai_send(g, ai.n, o.id, "TRADE")
			elif theirs == Defs.Relation.PEACE:
				if Diplomacy._may_retry(g, ai.n, "ALLIANCE", o.id):
					Diplomacy._ai_send(g, ai.n, o.id, "ALLIANCE")
			elif Diplomacy.trade_rating(g, o, ai.n) > 10 or Diplomacy.trade_with_rating(g, o, ai.n) >= 50:
				if Diplomacy._may_retry(g, ai.n, "FRIENDLY", o.id):
					Diplomacy._ai_send(g, ai.n, o.id, "FRIENDLY")


## Nation::think_surrender: with no people (or no money and no income) left,
## to the kingdom we think most of - unless pref_surrender is 0.
static func think_surrender(ai: NationAI) -> bool:
	if ai.pref("surrender") == 0:
		return false
	var hopeless := ai.total_population() == 0
	if ai.n.cash <= 0.0 and ai.n.last_income_year + ai.n.income_year <= 0.0:
		hopeless = true
	if not hopeless:
		return false
	var best_r := 70 - ai.pref("surrender")
	if ai.n.king == null or not is_instance_valid(ai.n.king) or ai.n.king.dead:
		best_r = -100
	var best := 0
	for o in ai.g.nations:
		if not o.alive or o == ai.n or o.cash <= 300.0 or o.is_fryhtan != ai.n.is_fryhtan:
			continue
		if ai.g.day < int(ai.n.never_until.get("SURRENDER:%d" % o.id, -1)):
			continue
		var r := surrender_to_rating(ai, o) + 50 - ai.total_unit_count() * 5
		if r > best_r:
			best_r = r
			best = o.id
	if best > 0:
		Diplomacy.surrender(ai.g, ai.n.id, best)
		return true
	return false


## Nation::ai_surrender_to_rating (good_relation_duration_rating is never
## raised in the original, so it adds nothing)
static func surrender_to_rating(ai: NationAI, o: Nation) -> int:
	var r := Diplomacy.overall_rank(ai.g, o) - ai.overall_rank()
	r += Diplomacy.ai_rel(ai.n, o.id) - 40
	r += int(o.reputation / 2.0)
	if ai.relation(o.id) == Defs.Relation.WAR:
		r -= 100
	if o.race == ai.n.race:
		r += 20
	return r


## NationHuman::think_unite_against_big_enemy: after three to six years, at
## high aggressiveness, when a human player leads and the best computer
## kingdom lags far behind, the others surrender to it.
static func think_unite_against_big_enemy(ai: NationAI) -> bool:
	if ai.g.day < 365 * 3 * (100 + ai.pref("military_development")) / 100:
		return false
	var aggr := ai._aggressiveness()
	if aggr < GameSetup.HIGH:
		return false
	if aggr == GameSetup.HIGH:
		if ai.g.rng.randi() % 10 != 0:
			return false
	elif ai.g.rng.randi() % 5 != 0:
		return false
	var leader := AICapture._max_overall_nation(ai)
	var ln := ai.g.nation(leader)
	if ln == null or ln.is_ai:
		return false
	var second: Nation = null
	var second_r := 0
	for o in ai.g.nations:
		if not o.alive or o.id == leader or not o.is_ai:
			continue
		var r := Diplomacy.overall_rank(ai.g, o)
		if r > second_r:
			second_r = r
			second = o
	if second == null or second == ai.n:
		return false
	if ai.relation(second.id) < Defs.Relation.NEUTRAL:
		return false
	if second_r < (50 if aggr == GameSetup.HIGH else 80):
		Diplomacy.surrender(ai.g, ai.n.id, second.id)
		return true
	return false


## Nation::think_eliminate_enemy_town
static func _eliminate_town(ai: NationAI, enemy: int) -> bool:
	for t in ai.g.towns:
		if t.dead or t.nation_id != enemy:
			continue
		if not ai.n.is_fryhtan and not ai.my_towns().any(func(o): return o.is_base_town):
			continue
		var m := AICapture.mobile_defense_combat_level(ai, t.center_loc(), t.nation_id, true)
		if m[1] == -1:
			continue
		return AIAttack.attack_target(ai, t, m[0] + AITown.protection_available(t))
	return false


## Nation::think_eliminate_enemy_firm
static func _eliminate_firm(ai: NationAI, enemy: int) -> bool:
	for f in ai.g.firms:
		if f.dead or f.nation_id != enemy:
			continue
		if not ai.n.is_fryhtan and not ai.my_towns().any(func(o): return o.is_base_town):
			continue
		var m := AICapture.mobile_defense_combat_level(ai, f.center_loc(), f.nation_id, true)
		if m[1] == -1:
			continue
		var lvl := AIFirm.total_combat_level(f) if Espionage.is_camp(f) or f.code == "LAIR" else 0
		return AIAttack.attack_target(ai, f, m[0] + lvl)
	return false


## Nation::think_eliminate_enemy_unit
static func _eliminate_unit(ai: NationAI, enemy: int) -> bool:
	for u in ai.g.units:
		if u.dead or u.nation_id != enemy or u.inside_firm != null or u.has_meta("hidden"):
			continue
		if not ai.n.is_fryhtan and not ai.my_towns().any(func(o): return o.is_base_town):
			continue
		var m := AICapture.mobile_defense_combat_level(ai, u.center_loc(), u.nation_id, true)
		if m[1] == -1:
			continue
		return AIAttack.attack_target(ai, u, m[0] + int(u.obj_power()))
	return false


## Nation::think_ally_against_big_enemy: warm to everyone but the leader;
## while still on good terms with it, ask it for aid or tribute.
static func think_ally_against_big_enemy(ai: NationAI) -> bool:
	var g := ai.g
	if g.day < 365 + ai.n.id * 70:
		return false
	var enemy := AICapture._max_overall_nation(ai)
	if enemy == ai.n.id or enemy == 0:
		return false
	var en := g.nation(enemy)
	var aggr := ai._aggressiveness()
	if aggr >= GameSetup.HIGH:
		if en.is_ai:
			return false
	elif aggr <= GameSetup.LOW:
		if not en.is_ai:
			return false
	var inc := (100 - ai.overall_rank()) / 10
	for o in g.nations:
		if not o.alive or o == ai.n or o.id == enemy:
			continue
		Diplomacy.change_ai_rel(ai.n, o.id, inc * (100 - Diplomacy.ai_rel(ai.n, o.id)) / 100)
	var ai_count := g.nations.filter(func(o): return o.alive and o.is_ai).size()
	if g.rng.randi() % maxi(1, ai_count) == 0:
		return false
	if Diplomacy.trade_rating(g, ai.n, en) + Diplomacy.trade_with_rating(g, ai.n, en) > 100 - ai.pref("trading_tendency") / 3:
		return false
	if Diplomacy.ai_rel(ai.n, enemy) > 30:
		var id := "DEMAND_AID" if ai.relation(enemy) >= Defs.Relation.PEACE else "DEMAND_TRIBUTE"
		if Diplomacy._may_retry(g, ai.n, id, enemy):
			Diplomacy._ai_send(g, ai.n, enemy, id, [500, 1000, 2000][g.rng.randi() % 3])
	return false


## Nation::ai_should_attack_friendly
static func should_attack_friendly(ai: NationAI, nid: int, temptation: int) -> bool:
	if ai.g.day < int(ai.n.status_day.get(nid, -10000)) + 60 + ai.pref("honesty") / 2:
		return false
	var o := ai.g.nation(nid)
	var r := Diplomacy.military_rank(ai.g, o) - ai.military_rank()
	r += Diplomacy.ai_rel(ai.n, nid) - 50
	r += Diplomacy.trade_rating(ai.g, ai.n, o)
	return temptation > r


## Nation::ai_end_treaty
static func end_treaty(ai: NationAI, nid: int) -> void:
	match ai.relation(nid):
		Defs.Relation.PEACE:
			Diplomacy.send(ai.g, ai.n.id, nid, "END_FRIENDLY")
		Defs.Relation.ALLIANCE:
			Diplomacy.send(ai.g, ai.n.id, nid, "END_ALLIANCE")


## Nation::think_against_mine_monopoly: in the first year, at high
## aggressiveness, short of money and without a mine, strike a human
## player's mine - or first ask him for aid while relations are still good.
static func think_against_mine_monopoly(ai: NationAI) -> bool:
	var g := ai.g
	if ai._aggressiveness() < GameSetup.HIGH or g.day > 365 or ai.true_profit() > 0.0:
		return false
	if ai._aggressiveness() < GameSetup.VERY_HIGH and ai.n.cash > 2000 + 1000 * ai.pref("cash_reserve") / 100:
		return false
	if ai.my_towns().is_empty() or not ai.my_firms("MINE").is_empty() or g.sites.is_empty():
		return false
	var best := 0
	var best_r := 0
	for o in g.nations:
		if not o.alive or o.is_ai or o == ai.n:
			continue
		var mines := g.firms.filter(func(f): return f.code == "MINE" and f.nation_id == o.id and not f.dead).size()
		var r := mines * 100 - Diplomacy.ai_rel(ai.n, o.id) - Diplomacy.trade_rating(g, ai.n, o)
		if r > best_r:
			best_r = r
			best = o.id
	if best == 0:
		return false
	if Diplomacy.ai_rel(ai.n, best) > 30:
		var id := "DEMAND_AID" if ai.relation(best) >= Defs.Relation.PEACE else "DEMAND_TRIBUTE"
		if Diplomacy._may_retry(g, ai.n, id, best):
			Diplomacy._ai_send(g, ai.n, best, id, [500, 1000, 2000][g.rng.randi() % 3])
		return false
	for f in g.firms:
		if f.dead or f.code != "MINE" or f.nation_id != best:
			continue
		return AIAttack.attack_target(ai, f, AICapture.enemy_firm_combat_level(ai, f, true), false, null, true)
	return false
