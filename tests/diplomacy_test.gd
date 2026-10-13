extends Node
## Diplomatic messages (otalkres.cpp): every kind, the computer's answers, a
## human kingdom's inbox and reply, trade treaties gating caravans, the
## computer starting talks by itself, and save/load.

var ok := true


func check(cond: bool, what: String) -> void:
	print(("ok   " if cond else "FAIL ") + what)
	if not cond:
		ok = false


func days(g: Game, n: int) -> void:
	for d in n:
		for f in Defs.FRAMES_PER_DAY:
			g.sim_frame()


func last(g: Game) -> Dictionary:
	return g.talk_log[-1] if not g.talk_log.is_empty() else {}


func _ready() -> void:
	if Assets.load_install() != "":
		get_tree().quit(1); return
	Defs.load_from_assets()
	var g := Game.new()
	add_child(g)
	g.start({"seed": 21, "size": 120, "race": "NORMAN", "ai_count": 3, "fryhtan_count": 1, "reveal": true})
	var p := g.player()
	var humans: Array = g.nations.filter(func(n): return n.id != p.id and not n.is_fryhtan)
	var a: Nation = humans[0]
	var b: Nation = humans[1]
	var c: Nation = humans[2]
	var fry: Nation = g.nations.filter(func(n): return n.is_fryhtan)[0]

	# ---- what may be sent
	check(Diplomacy.can_send(g, p.id, a.id, "TRADE"), "a trade treaty may be proposed to a neutral kingdom")
	check(not Diplomacy.can_send(g, p.id, a.id, "CEASE_WAR"), "no cease-fire without a war")
	check(not Diplomacy.can_send(g, p.id, a.id, "END_TRADE"), "no treaty to end")
	check(Diplomacy.can_send(g, p.id, fry.id, "CEASE_WAR"), "humans and Fryhtans start at war")

	# ---- the computer answers at once; Fryhtans never trade with humans
	Diplomacy.set_status(g, p.id, fry.id, Defs.Relation.NEUTRAL)
	g.talk(p.id, fry.id, "TRADE")
	check(last(g).get("id") == "TRADE" and last(g).get("result") == "rejected", "the Fryhtans reject a trade treaty")
	# give the player a raw material the other lacks: a trade worth having
	var a_raws := Diplomacy._raws(g, a.id)
	for s in g.sites:
		if s.mine == null and not a_raws.has(s.raw):
			if g.spawn_firm("MINE", p.id, "NORMAN", Vector2i(s.x1, s.y1), true):
				break
	check(Diplomacy.trade_with_rating(g, a, p) > 0, "something to trade")
	g.talk(p.id, a.id, "TRADE")
	check(last(g).get("result") == "accepted" and Diplomacy.has_trade(p, a.id) and Diplomacy.has_trade(a, p.id), "the trade treaty is accepted and binds both")
	check(not Diplomacy.can_send(g, p.id, a.id, "TRADE"), "not twice")

	# ---- trade treaties gate caravans
	var home: Town = g.towns.filter(func(t): return t.nation_id == p.id)[0]
	var bt: Town = g.towns.filter(func(t): return t.nation_id == b.id)[0]
	var m1 := g.spawn_firm("MARKET", p.id, "NORMAN", g._place_near(home.footprint(), 5, 5, 8), true)
	var mb := g.spawn_firm("MARKET", b.id, b.race, g._place_near(bt.footprint(), 5, 5, 8), true)
	g.update_links()
	check(m1 != null and mb != null, "markets built")
	var no_treaty := true
	for d in 3:
		var partner := g.find_trade_partner(m1, p.id)
		if partner == mb:
			no_treaty = false
	check(no_treaty, "no caravan trade with a kingdom without a treaty")
	Diplomacy.set_trade(g, p.id, b.id, true)
	var with_treaty := g.find_trade_partner(m1, p.id)
	check(with_treaty != null and with_treaty.nation_id != p.id, "with a treaty a foreign market is in reach (%s)" % (with_treaty.display_name() if with_treaty else "none"))
	Diplomacy.set_trade(g, p.id, b.id, false)

	# ---- a human kingdom: the message waits for its answer
	b.is_ai = false
	b.ai = null
	g.talk(p.id, b.id, "FRIENDLY")
	check(g.talks.size() == 1 and g.talks[0]["to"] == b.id, "the friendly treaty waits in the other ruler's inbox")
	g.talk_reply(p.id, b.id, "FRIENDLY", true)
	check(g.talks.is_empty() and p.relation(b.id) == Defs.Relation.PEACE and b.relation(p.id) == Defs.Relation.PEACE, "accepted: a friendly treaty")
	g.talk(p.id, b.id, "ALLIANCE")
	g.talk_reply(p.id, b.id, "ALLIANCE", false)
	check(p.relation(b.id) == Defs.Relation.PEACE and last(g).get("result") == "rejected", "rejected: no alliance")
	g.talk(p.id, b.id, "ALLIANCE")
	g.talk_reply(p.id, b.id, "ALLIANCE", true)
	check(p.relation(b.id) == Defs.Relation.ALLIANCE and Diplomacy.has_trade(p, b.id), "an alliance brings a trade treaty")
	g.talk(b.id, p.id, "END_ALLIANCE")
	check(p.relation(b.id) == Defs.Relation.NEUTRAL, "ending the alliance: neutral again")

	# ---- money, food and technology
	p.cash = 10000.0
	b.cash = 5000.0
	g.talk(p.id, b.id, "GIVE_TRIBUTE", 1000)
	g.talk_reply(p.id, b.id, "GIVE_TRIBUTE", true)
	check(is_equal_approx(p.cash, 9000.0) and is_equal_approx(b.cash, 6000.0), "a tribute of 1000 changes hands")
	g.talk(p.id, b.id, "DEMAND_TRIBUTE", 2000)
	g.talk_reply(p.id, b.id, "DEMAND_TRIBUTE", true)
	check(is_equal_approx(p.cash, 11000.0) and is_equal_approx(b.cash, 4000.0), "a demanded tribute is paid")
	b.food = 5000.0
	var food0 := p.food
	g.talk(p.id, b.id, "BUY_FOOD", 1000, 10)
	g.talk_reply(p.id, b.id, "BUY_FOOD", true)
	check(is_equal_approx(p.food, food0 + 1000.0) and is_equal_approx(b.food, 4000.0) and is_equal_approx(p.cash, 10000.0), "1000 food bought at $10 per 10")
	p.tech["MINING"] = 1
	b.tech.erase("MINING")
	b.tech["MANUFACT"] = 1
	p.tech.erase("MANUFACT")
	var pair := Diplomacy.tech_pairs(p, b).filter(func(x): return x == ["MINING", "MANUFACT"])
	check(not pair.is_empty(), "a technology exchange is on offer")
	g.talk(p.id, b.id, "EXCHANGE_TECH", "MINING", "MANUFACT")
	g.talk_reply(p.id, b.id, "EXCHANGE_TECH", true)
	check(b.tech_level("MINING") == 1 and p.tech_level("MANUFACT") == 1, "technologies exchanged")

	# ---- war and cease-fire
	g.talk(p.id, b.id, "DECLARE_WAR")
	check(p.relation(b.id) == Defs.Relation.WAR and not Diplomacy.has_trade(p, b.id), "war declared; the trade treaty ends")
	check(int(b.war_count.get(p.id, 0)) == 1, "remembered: they started a war on us")
	g.talk(b.id, p.id, "CEASE_WAR")
	check(g.talks.size() == 1 and g.talks[0]["to"] == p.id, "their cease-fire request waits for the player")
	g.talk_reply(b.id, p.id, "CEASE_WAR", true)
	check(p.relation(b.id) == Defs.Relation.NEUTRAL, "cease-fire: neutral")

	# ---- embargo and a request for war
	Diplomacy.set_trade(g, b.id, c.id, true)
	g.talk(p.id, b.id, "FRIENDLY")
	g.talk_reply(p.id, b.id, "FRIENDLY", true)
	check(Diplomacy.third_parties(g, p.id, b.id, "EMBARGO") == [c.id], "an embargo may be asked against their trade partner")
	g.talk(p.id, b.id, "EMBARGO", c.id)
	g.talk_reply(p.id, b.id, "EMBARGO", true)
	check(not Diplomacy.has_trade(b, c.id), "embargo: they stop trading with them")
	g.declare_war(p.id, c.id)
	g.talk(p.id, b.id, "REQUEST_WAR", c.id)
	g.talk_reply(p.id, b.id, "REQUEST_WAR", true)
	check(b.relation(c.id) == Defs.Relation.WAR, "they declare war on our enemy")

	# ---- save and load keep treaties, feelings and waiting messages
	g.talk(b.id, p.id, "DEMAND_AID", 500)
	var ai_level := Diplomacy.ai_rel(a, p.id)
	SaveGame.save(g, "test_diplomacy")
	var g2 := Game.new()
	add_child(g2)
	var err := SaveGame.load_into(g2, "test_diplomacy")
	DirAccess.remove_absolute(SaveGame.path_for("test_diplomacy"))
	check(err == "", "reloaded")
	check(Diplomacy.has_trade(g2.player(), a.id) and g2.talks.size() == 1 and g2.talks[0]["id"] == "DEMAND_AID", "treaty and waiting message saved")
	check(Diplomacy.ai_rel(g2.nation(a.id), p.id) == ai_level and int(g2.nation(b.id).war_count.get(p.id, 0)) == 1, "the computer's feelings saved")
	g2.queue_free()

	# ---- surrender
	var a_towns := g.towns.filter(func(t): return t.nation_id == a.id).size()
	var my_towns := g.towns.filter(func(t): return t.nation_id == p.id).size()
	g.talk(a.id, p.id, "SURRENDER")
	check(g.towns.filter(func(t): return t.nation_id == p.id).size() == my_towns + a_towns and not g.towns.any(func(t): return t.nation_id == a.id), "a surrendering kingdom's towns become ours")

	# ---- contact: computer kingdoms know each other; we meet them by exploring
	var g4 := Game.new()
	add_child(g4)
	g4.start({"seed": 30, "size": 120, "race": "NORMAN", "ai_count": 2, "fryhtan_count": 0})
	days(g4, 2)
	var me := g4.player()
	var ais: Array = g4.nations.filter(func(n): return n.id != me.id)
	check(ais[0].contact.has(ais[1].id), "computer kingdoms have contact from the start")
	var far: Nation = ais.filter(func(n): return not me.contact.has(n.id)).front() if ais.any(func(n): return not me.contact.has(n.id)) else null
	check(far != null, "a kingdom not yet met")
	if far:
		check(not Diplomacy.can_send(g4, me.id, far.id, "TRADE"), "no messages before contact")
		var ft: Town = g4.towns.filter(func(t): return t.nation_id == far.id)[0]
		g4.reveal_area(me.id, Vector2i(ft.center_loc()), 8)
		g4._reveal(Vector2i(ft.center_loc()), 8)
		g4._explore_contacts()
		check(me.contact.has(far.id) and far.contact.has(me.id), "exploring its town makes contact")
		check(Diplomacy.can_send(g4, me.id, far.id, "TRADE"), "then they can talk")
	g4.queue_free()
	Game.inst = g

	# ---- the computer starts talks by itself
	var g3 := Game.new()
	add_child(g3)
	g3.start({"seed": 4, "size": 120, "race": "NORMAN", "ai_count": 4, "fryhtan_count": 1, "autoplay": true, "reveal": true})
	days(g3, 900)
	var kinds := {}
	for m in g3.talk_log:
		kinds[m["id"] + (":" + m["result"] if m["result"] != "" else "")] = true
	print("     computer talks: ", kinds.keys())
	var treaties := 0
	for n in g3.nations:
		treaties += n.trade_treaty.values().count(true)
	check(not g3.talk_log.is_empty(), "computer kingdoms send each other messages")
	check(treaties > 0, "and some trade treaties are signed (%d)" % (treaties / 2))
	print("RESULT: ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
