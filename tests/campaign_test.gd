extends Node
## The campaign: texts, the province map, every stage's battle built and run for
## a while, and the event chain driven with automatic replies.

var ok := true
var replies := 0


class StubUI:
	var rng := RandomNumberGenerator.new()
	var log: Array = []
	func narrative(t: String) -> void:
		log.append("N " + t.substr(0, 40))
	func letter(t: String) -> int:
		var parts := CampaignText.letter_parts(t)
		log.append("L %d replies" % parts["replies"].size())
		return rng.randi_range(1, maxi(1, parts["replies"].size()))
	func attack(a: int, b: int, r: int, a2: int) -> void:
		log.append("A %d->%d %d" % [a, b, r])
	func pick_state(c: Array) -> int:
		return c[rng.randi() % c.size()]


func check(cond: bool, what: String) -> void:
	print(("ok   " if cond else "FAIL ") + what)
	if not cond:
		ok = false


func _ready() -> void:
	if Assets.load_install() != "":
		get_tree().quit(1); return
	Defs.load_from_assets()
	check(CampaignText.has_text(), "campaign texts found in the install")
	var t1 := CampaignText.stage("1INTRO")
	check(t1.length() > 20, "stage 1 intro: " + t1.substr(0, 60).replace("\n", " "))
	var l := CampaignText.letter_parts(CampaignText.event("3B"))
	check(l["replies"].size() == 2 and l["head"].begins_with("A messenger"), "letter 3B has a heading and two replies")
	check(CampaignText.format("%s of %d", ["a", 5]) == "a of 5", "printf substitution")

	var c := Campaign.new()
	var ui := StubUI.new()
	ui.rng.seed = 5
	c.ui = ui
	c.init_new("NORMAN", 3, 1234)
	print("nations: ", c.nations.values().map(func(n): return "%s %s (%s) %d states" % [n["type"], n["name"], n["race"], c.map.nation_state_count(n["id"])]))
	check(c.map.size() == 12, "12 provinces")
	check(c.map.nation_state_count(c.western) >= 2 and c.map.nation_state_count(c.eastern) >= 1, "both empires hold provinces")
	check(c.nations.values().filter(func(n): return n["type"] == "monster").size() >= 1, "Fryhtan kingdoms exist")
	var adj_ok := true
	for s in range(1, 13):
		if c.map.get_state(s)["adj"].is_empty():
			adj_ok = false
	check(adj_ok, "every province has neighbours")

	# ---- every stage's battle
	var monster := 0
	for id in c.nations:
		if c.is_monster(id):
			monster = id
			break
	for st in range(1, 29):
		var cc := Campaign.new()
		cc.ui = ui
		cc.init_new("NORMAN", 3, 1000 + st)
		cc.set_stage(st)
		_pick_states(cc, st)
		await cc.stage_prelude()
		var g := Game.new()
		add_child(g)
		var cb := CampaignBattle.create(cc)
		g.start({"seed": 100 + st, "campaign_battle": cb, "reveal": true})
		var p := g.player()
		var mine_units := g.units.filter(func(u): return u.nation_id == p.id).size()
		var mine_towns := g.towns.filter(func(t): return t.nation_id == p.id).size()
		var foes := g.nations.filter(func(n): return n.id != p.id).map(func(n): return "%s%s" % [n.name.substr(0, 14), " (F)" if n.is_fryhtan else ""])
		for d in 40:
			for f in Defs.FRAMES_PER_DAY:
				g.sim_frame()
		var goals: Array = g.goals.win.map(func(x): return x["text"])
		print("stage %2d %-26s units %3d towns %2d firms %3d plot %-2s rivals %s goals %s" % [st, cc.stage_name(), mine_units, mine_towns,
			g.firms.filter(func(f): return f.nation_id == p.id).size(), cb.plot, foes, goals])
		check(p != null and (mine_units > 0 or mine_towns > 0), "stage %d: you have an army or towns" % st)
		# stage 6's hero arrives at a random edge, as in the original, and may meet
		# the Fryhtan army there: losing him is a legitimate early defeat
		var hero_fell: bool = st == 6 and g.over and g.goals.lost_id == Goals.KILL_UNIT
		if hero_fell:
			print("     stage 6: the hero fell early (he arrived at a random edge)")
		check(g.nations.size() >= 1 and not g.over or st in [3] or hero_fell, "stage %d: battle running after 40 days" % st)
		if st == 2:
			cc.save()
			SaveGame.save(g, "campaign_test")
			var g2 := Game.new()
			add_child(g2)
			var err := SaveGame.load_into(g2, "campaign_test")
			check(err == "" and g2.campaign_battle != null and g2.campaign_battle.vars.get("reinforce", 0) == cb.vars.get("reinforce", -1) 				and g2.year0 == g.year0 and g2.goals.win.size() == g.goals.win.size(), "a campaign battle saves and loads (%s)" % err)
			g2.queue_free()
			Game.inst = g
		await cc.process_game_result(true, Goals.DEFEAT_ALL_OTHER_KINGDOMS if st != 15 else Goals.ACQUIRE_TECH, -1, 2)
		check(cc.event_id > 0 or cc.stage_id > 0 or cc.finished, "stage %d: the campaign moves on (event %d stage %d)" % [st, cc.event_id, cc.stage_id])
		cc.update_royals(g)
		g.queue_free()
		await get_tree().process_frame
		Game.inst = null

	# ---- the event chain
	var stages_seen := {}
	var steps := 0
	while steps < 400 and not c.finished:
		steps += 1
		if c.event_id:
			await c.process_event()
		else:
			stages_seen[c.stage_id] = true
			await c.stage_prelude()
			# pretend the battle was fought: won two times in three
			var won := c.rng.randi_range(0, 2) > 0
			await c.process_game_result(won, Goals.DEFEAT_ALL_OTHER_KINGDOMS if c.stage_id != 15 else Goals.ACQUIRE_TECH, -1 if won else Goals.DEFEAT_OWN_KINGDOM)
	print("event chain: %d steps, stages %s, finished %s victory %s, player provinces %d" % [steps, stages_seen.keys(), c.finished, c.victory, c.map.nation_state_count(c.western)])
	print("journal tail: ", c.journal.slice(-6))
	check(stages_seen.size() >= 4, "the event chain leads to several stages")

	# ---- save and load
	c.save()
	var c2 := Campaign.load_saved()
	check(c2 != null and c2.stage_id == c.stage_id and c2.event_id == c.event_id and c2.map.size() == 12 and c2.nations.size() == c.nations.size(), "the campaign saves and loads")
	print("RESULT: ", "PASS" if ok else "FAIL")
	get_tree().quit()


## The provinces a stage is about, as the events leading to it would choose them.
func _pick_states(cc: Campaign, st: int) -> void:
	var mon := 0
	for id in cc.nations:
		if cc.is_monster(id) and cc.random_pick_attack_state(cc.western, id):
			mon = id
			break
	if mon == 0:
		for id in cc.nations:
			if cc.is_monster(id):
				mon = id
	cc.cur_monster = mon
	match st:
		1, 2, 5, 6, 12:
			if not cc.random_pick_attack_state(mon, cc.western):
				cc.random_pick_attack_state(0, cc.western)
		4, 19, 20, 22, 23:
			cc.random_pick_attack_state(cc.western, cc.eastern)
		9, 21:
			cc.random_pick_attack_state(cc.eastern, cc.western)
		11, 13, 18, 24:
			var tri := cc.triangle_states2()
			if tri.is_empty() or st == 11:
				cc.random_pick_attack_state(cc.western, mon)
				cc.attacker2_state = cc.attacker_state
				# an allied Fryhtan province (for 11) or the Eastern one
				for s in range(1, cc.map.size() + 1):
					var n: int = cc.map.get_state(s)["nation"]
					if (st == 11 and cc.is_monster(n) and n != mon) or (st != 11 and n == cc.eastern):
						cc.attacker_state = s if st == 11 else cc.attacker_state
						cc.attacker2_state = s if st != 11 else cc.attacker2_state
						break
				cc.target_monster = mon
			else:
				cc.attacker_state = tri[0]
				cc.attacker2_state = tri[1]
				cc.target_state = tri[2]
		_:
			cc.random_pick_attack_state(cc.western, mon)
