extends Node
## Rebellions (Town::think_rebel, orebel.cpp): a disloyal town's malcontents
## walk out as an independent rebel band hostile to their kingdom; the town
## stays and grows more loyal; the band attacks or settles; leaderless rebels
## surrender to the most reputable kingdom; bands survive save and load.

var ok := true


func check(cond: bool, what: String) -> void:
	print(("ok   " if cond else "FAIL ") + what)
	if not cond:
		ok = false


func days(g: Game, n: int) -> void:
	for d in n:
		for f in Defs.FRAMES_PER_DAY:
			g.sim_frame()


func _ready() -> void:
	if Assets.load_install() != "":
		get_tree().quit(1); return
	Defs.load_from_assets()
	var g := Game.new()
	add_child(g)
	g.start({"seed": 12, "size": 120, "race": "NORMAN", "ai_count": 1, "fryhtan_count": 0, "reveal": true})
	days(g, 40)
	var p := g.player()
	var t: Town = g.towns.filter(func(x): return x.nation_id == p.id)[0]
	t.population = 40
	t.loyalty = 5.0
	t.last_rebel_day = -1000
	t.last_attacked_frame = -100000
	var pop0 := t.population
	t.think_rebel(g.day)
	check(t.nation_id == p.id, "the town stays with its kingdom")
	check(g.rebels.size() == 1, "a rebel band is formed")
	var r: Dictionary = g.rebels[0]
	var n: int = r["units"].size()
	check(n >= 1 + int((pop0 - 1) * 0.3) - 1 and n <= 1 + int(pop0 * 0.6), "a third to two thirds walk out (%d of %d)" % [n, pop0])
	check(t.population == pop0 - n, "they leave the town's population")
	check(t.loyalty > 5.0, "the town is more loyal once the malcontents are gone (%.1f)" % t.loyalty)
	var leader: Unit = r["leader"]
	check(leader.rank == Defs.Rank.GENERAL and leader.nation_id == 0 and leader.combat > 10.0, "led by a general of the rebels")
	var soldier := g.units.filter(func(u): return u.nation_id == p.id and not u.dead and u.inside_firm == null and not u.is_civilian())[0] as Unit
	check(g.is_hostile(leader, soldier) and g.is_hostile(soldier, leader), "rebels and their old kingdom are enemies")
	var other: Nation = g.nations.filter(func(x): return x.id != p.id)[0]
	var stranger := g.spawn_unit(Defs.unit_sprite(other.race, "INF"), other.id, Vector2i(5, 5), 20.0)
	check(not g.is_hostile(leader, stranger), "but not of other kingdoms")
	t.think_rebel(g.day)
	check(g.rebels.size() == 1, "no second rebellion within three months")

	# the band acts
	for u in r["units"]:
		u.stop()
	Rebels.next_day(g)
	var acted: bool = r["action"] != "idle" or not g.rebels.has(r) or r["units"].any(func(u): return u.order != Unit.Order.IDLE)
	for i in 6:
		if acted:
			break
		Rebels.next_day(g)
		acted = r["action"] != "idle" or not g.rebels.has(r)
	check(acted, "the band takes action (%s)" % r["action"])

	# save and load
	if g.rebels.has(r):
		SaveGame.save(g, "test_rebels")
		var g2 := Game.new()
		add_child(g2)
		SaveGame.load_into(g2, "test_rebels")
		DirAccess.remove_absolute(SaveGame.path_for("test_rebels"))
		check(g2.rebels.size() == 1 and g2.rebels[0]["units"].size() == r["units"].size(), "the band is saved")
		check(g2.rebels[0]["units"].all(func(u): return u.rebel_id == g2.rebels[0]["id"]), "its men remember their band")
		g2.queue_free()
		Game.inst = g

	# a leaderless band surrenders to the most reputable kingdom
	t.loyalty = 5.0
	t.last_rebel_day = -1000
	t.population = 40
	g.rebels.clear()
	t.think_rebel(g.day)
	var r2: Dictionary = g.rebels[0]
	p.reputation = 80.0
	other.reputation = 10.0
	var men: Array = r2["units"].duplicate()
	r2["leader"].die(null)
	Rebels.next_day(g)
	var alive := men.filter(func(u): return not u.dead)
	check(alive.size() > 0 and alive.all(func(u): return u.nation_id == p.id and u.rebel_id == 0), "leaderless, they surrender to the kingdom with the best reputation")
	check(not g.rebels.has(r2), "the band is gone")
	print("RESULT: ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
