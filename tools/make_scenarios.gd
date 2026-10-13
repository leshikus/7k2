extends Node
## Builds the scenarios shipped in res://scenario/*.json with the game's own
## API, so they stay valid as the save format changes. Run:
##   godot --headless --path . res://tools/make_scenarios.tscn
## Each is a game set up and saved as the scenario editor saves one.

const OUT := "res://scenario"


func _ready() -> void:
	Assets.load_install()
	Defs.load_from_assets()
	for f in [silk_road, siege_of_carthage, fryhtan_plague, shadow_war, lord_of_the_lair, the_relic]:
		var g := Game.new()
		add_child(g)
		var info: Array = f.call(g)
		var path := "%s/%s.json" % [OUT, info[0]]
		var ok := SaveGame.save_path(g, path, {"scenario_name": info[1], "scenario_text": info[2]})
		print(("saved " if ok else "FAILED ") + path)
		g.queue_free()
		await get_tree().process_frame
	get_tree().quit()


# ------------------------------------------------------------- helpers ---

func _start(g: Game, seed_: int, race: String, ai: int, fry: int, extra := {}) -> void:
	var cfg := {"seed": seed_, "size": 140, "race": race, "ai_count": ai, "fryhtan_count": fry, "indep_towns": 8, "lairs": 3, "reveal": false}
	cfg.merge(extra, true)
	g.start(cfg)


func _home(g: Game, nid: int) -> Town:
	for t in g.towns:
		if t.nation_id == nid and not t.dead:
			return t
	return null


func _near(g: Game, t: Town, code: String, nid: int, race: String, gap := 8) -> Firm:
	var b := Assets.firm_build(code, race)
	var p := g._place_near(t.footprint(), b.get("loc_w", 5), b.get("loc_h", 5), gap, [t.center_loc()])
	return g.spawn_firm(code, nid, race, p, true) if p.x >= 0 else null


func _men(g: Game, nid: int, sprite: String, at: Vector2i, count: int, combat: float, lead := 20.0) -> Array:
	var out: Array = []
	for i in count:
		var u := g.spawn_unit(sprite, nid, g.free_unit_cell(at + Vector2i(i % 5, i / 5)), combat)
		if u:
			u.leadership = lead
			out.append(u)
	return out


func _general(g: Game, nid: int, race: String, at: Vector2i, combat: float, lead: float) -> Unit:
	var u := g.spawn_unit(Defs.unit_sprite(race, "INF"), nid, g.free_unit_cell(at), combat)
	if u:
		u.rank = Defs.Rank.GENERAL
		u.leadership = lead
	return u


func _cond(id: int, p2 := 0, target = null, years := 0, player_only := true) -> Dictionary:
	var c := {"id": id, "p1": 0, "p2": p2, "years": years, "player_only": player_only, "text": "", "result": "", "target": target, "met": false}
	c["supported"] = Goals._supported(c)
	return c


func _goals(g: Game, wins: Array, loses: Array, years := 0) -> void:
	var gl := Goals.new()
	gl.year_limit = years
	gl.win = wins
	gl.lose = [_cond(Goals.DEFEAT_OWN_KINGDOM)] + loses
	g.goals = gl


func _ally(g: Game, a: int, b: int) -> void:
	g.nation(a).relations[b] = Defs.Relation.ALLIANCE
	g.nation(b).relations[a] = Defs.Relation.ALLIANCE
	Diplomacy.set_trade(g, a, b, true)


# ----------------------------------------------------------- scenarios ---

## Economy: a Chinese kingdom between two trading partners must build the
## richest markets in the land.
func silk_road(g: Game) -> Array:
	_start(g, 101, "CHINESE", 2, 0, {"cash": 6000})
	var p := g.player()
	p.cash = 6000.0
	for n in g.nations:
		if n.id != p.id:
			n.relations[p.id] = Defs.Relation.PEACE
			p.relations[n.id] = Defs.Relation.PEACE
			Diplomacy.set_trade(g, p.id, n.id, true)
	var home := _home(g, p.id)
	home.population = 50
	_near(g, home, "MARKET", p.id, p.race)
	for n in g.nations:
		if n.id != p.id:
			var t := _home(g, n.id)
			if t:
				var m := _near(g, t, "MARKET", n.id, n.race)
				if m:
					for r in Economy.raw_types():
						m.goods[r] = 300.0
	_goals(g, [_cond(Goals.DEFEAT_ALL_OTHER_KINGDOMS), _cond(Goals.REACH_ECONOMY, 1500)], [], 12)
	return ["SilkRoad", "The Silk Road",
		"Your Chinese kingdom lies between two rich neighbours who trade with you in peace. Open mines, build factories and markets, send caravans along the road, and make yours the strongest economy in the land (an economic score of 1500) within twelve years."]


## War: a Roman army with siege machines must take Carthage itself.
func siege_of_carthage(g: Game) -> Array:
	_start(g, 202, "ROMAN", 1, 0)
	var p := g.player()
	var foe: Nation = g.nations.filter(func(n): return n.id != p.id)[0]
	foe.race = "CARTH"
	foe.name = "Kingdom of Carthage"
	foe.cash = 8000.0
	var ct := _home(g, foe.id)
	ct.town_name = "Carthago"
	ct.race = "CARTH"
	ct.population = 80
	ct.set_wall_level(2)
	ct.loyalty = 90.0
	var f2 := _near(g, ct, "CAMP", foe.id, "CARTH")
	if f2:
		f2.accept_unit(_general(g, foe.id, "CARTH", f2.door(), 70.0, 80.0))
		for u in _men(g, foe.id, Defs.unit_sprite("CARTH", "INF"), f2.door(), 10, 40.0):
			f2.accept_unit(u)
	g.declare_war(p.id, foe.id)
	p.cash = 5000.0
	p.tech["CATAPULT"] = 2
	p.tech["BALLISTA"] = 1
	var home := _home(g, p.id)
	var camp := home.center_loc() + Vector2(10, 0)
	_general(g, p.id, "ROMAN", Vector2i(camp), 90.0, 90.0)
	_men(g, p.id, Defs.unit_sprite("ROMAN", "INF"), Vector2i(camp) + Vector2i(2, 2), 14, 45.0)
	_men(g, p.id, "CATAPULT", Vector2i(camp) + Vector2i(0, 6), 3, 100.0)
	_men(g, p.id, "BALLISTA", Vector2i(camp) + Vector2i(4, 6), 2, 100.0)
	_goals(g, [_cond(Goals.CONQUER_TOWN, 0, ct)], [], 6)
	return ["SiegeOfCarthage", "The Siege of Carthage",
		"Carthago stands behind fortified walls, and Carthage's army waits in its camp. Lead the legions, the catapults and the ballistae of Rome across the land and take Carthago within six years. Delenda est."]


## Survival: a Norman realm in a land overrun by Fryhtans.
func fryhtan_plague(g: Game) -> Array:
	_start(g, 303, "NORMAN", 0, 3, {"lairs": 8, "indep_towns": 12})
	var p := g.player()
	p.cash = 8000.0
	var home := _home(g, p.id)
	home.population = 70
	home.set_wall_level(1)
	var fort: Firm = g.firms.filter(func(f): return f.nation_id == p.id and f.code == "FORT")[0]
	fort.archers = 5
	fort.target_archers = 5
	_near(g, home, "RESEARCH", p.id, p.race)
	_goals(g, [_cond(Goals.DEFEAT_ALL_FRYHTAN, 0, null, 0, false)], [], 15)
	return ["FryhtanPlague", "The Fryhtan Plague",
		"Three Fryhtan kingdoms and a swarm of lairs have overrun the land; your Norman town is the last free place within reach. Hold the walls, win the villages to your side and wipe out every Fryhtan within fifteen years."]


## Espionage: steal the secret of the cannon from a stronger rival.
func shadow_war(g: Game) -> Array:
	_start(g, 404, "JAPANESE", 1, 0)
	var p := g.player()
	var foe: Nation = g.nations.filter(func(n): return n.id != p.id)[0]
	foe.tech["BALLISTA"] = 3
	foe.tech["CANNON"] = 2
	foe.cash = 15000.0
	p.cash = 6000.0
	for code in ["AGITATE", "COUNTERS", "STEALINF", "BRIBE", "ASSASSIN", "STEALTEC"]:
		p.tech[code] = 1
	var home := _home(g, p.id)
	var col := _near(g, home, "SPY", p.id, p.race)
	if col:
		for i in 3:
			Training.order_train(col, Training.CIVILIAN)
			col.trainees[-1]["training"] = false
			col.trainees[-1]["spy_skill"] = 60.0 + i * 10
	var ft := _home(g, foe.id)
	var rc := _near(g, ft, "RESEARCH", foe.id, foe.race)
	var fc := _near(g, ft, "CAMP", foe.id, foe.race)
	if fc:
		fc.accept_unit(_general(g, foe.id, foe.race, fc.door(), 60.0, 70.0))
	_goals(g, [_cond(Goals.ACQUIRE_TECH, 0, "CANNON")], [], 5)
	return ["ShadowWar", "Shadow War",
		"Your neighbour has learnt to cast cannon and you cannot match its army. Your Espionage College has three trained agents. Slip them into the enemy's camps and Towers of Science and steal the secret of the cannon within five years."]


## Fryhtans: lead a Kharshuf brood and make every village pay tribute.
func lord_of_the_lair(g: Game) -> Array:
	var species: String = Defs.monsters[0]["unit"]
	_start(g, 505, species, 2, 0, {"indep_towns": 10, "lairs": 0})
	var p := g.player()
	p.live_points = 2500.0
	p.cash = 3000.0
	_goals(g, [_cond(Goals.CONQUER_ALL_TOWN), _cond(Goals.DEFEAT_ALL_OTHER_KINGDOMS)], [], 15)
	return ["LordOfTheLair", "Lord of the Lair",
		"You are the Fryhtan lord of %s, and the human villages around your lair do not yet fear you. Break their will until every independent village pays you tribute, or destroy the human kingdoms, within fifteen years." % Defs.monsters[0]["name"]]


## Protection: a hero must survive three years at war.
func the_relic(g: Game) -> Array:
	_start(g, 606, "GREEK", 2, 1)
	var p := g.player()
	for n in g.nations:
		if n.id != p.id and not n.is_fryhtan:
			g.declare_war(p.id, n.id)
	var home := _home(g, p.id)
	var hero := _general(g, p.id, "GREEK", Vector2i(home.center_loc()) + Vector2i(0, 8), 120.0, 95.0)
	hero.unit_name = "Theron the Keeper"
	hero.is_hero = true
	var ally: Nation = g.nations.filter(func(n): return n.id != p.id and not n.is_fryhtan)[0]
	_ally(g, p.id, ally.id)
	p.cash = 7000.0
	_goals(g, [_cond(Goals.KEEP_UNIT_ALIVE, 0, hero, 3), _cond(Goals.DEFEAT_ALL_OTHER_KINGDOMS)],
		[_cond(Goals.KILL_UNIT, 0, hero)], 0)
	return ["TheRelic", "The Keeper of the Relic",
		"Theron the Keeper carries the relic of your city, and every kingdom wants it. Your old ally stands with you. Keep Theron alive for three years - if he falls, all is lost."]
