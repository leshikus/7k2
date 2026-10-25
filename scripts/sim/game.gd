class_name Game
extends Node2D
## The running game: world, kingdoms, objects, time and fog of war.

signal message(text: String, loc: Vector2)
signal game_over(victory: bool, text: String)
signal sound_event(kind: String, code: String, action: String, world_pos: Vector2)

static var inst: Game = null

var rng := RandomNumberGenerator.new()
var world: WorldMap
var nations: Array[Nation] = []
var player_id := 1
var units: Array[Unit] = []
var firms: Array[Firm] = []
var towns: Array[Town] = []
var sites: Array[Site] = []
var bullets: Array[Bullet] = []
var effects_list: Array = []      # FirmEffect and SpriteEffect nodes
var rubble: Array = []        # [texture, screen position, expiry frame]
var tornadoes: Array[Tornado] = []
var treasures: Array[Treasure] = []   # scrolls, gold, items and blueprints lying about
signal shake(strength: float)
signal lightning(world_pos: Vector2)
var weather := Weather.new()
var selected: Array = []

var frame := 0
var day := 0
var speed := 1.0
var paused := false
var reveal_all := false
var over := false
var goals: Goals = null      # a scenario's win and lose conditions
var _accum := 0.0

const GRID_SHIFT := 3                 # unit grid blocks of 8 x 8 locations
var unit_grid := {}                   # Vector2i block -> Array[Unit], rebuilt every frame
var fog := PackedByteArray()        # 0 unexplored, 1 explored, 2 visible (player)
var terrain_view: TerrainView
var ground_layer: GroundLayer
var objects: Node2D
var effects: Node2D
var fog_view: FogView
var _ground_dirty := true

const START_YEAR := 1000
var year0 := START_YEAR              # the year the game starts in (a campaign battle's year)
## Campaign: technologies unveiled so far (code -> highest level); null elsewhere.
var tech_available = null
var campaign_battle = null           # CampaignBattle building and running this game
## Random numbers for pictures only (fires, smoke): what one player sees must
## never change the game shared in lockstep (Net).
var fx_rng := RandomNumberGenerator.new()
var peace_offers := {}               # nation -> {nation that offered peace: true}
var talks: Array = []                # diplomatic messages awaiting a human kingdom's reply
var contacts_ready := false          # the opening contacts have been made
var rebels: Array = []               # rebel bands (RebelArray)
var next_rebel_id := 1
var event_days := -1                 # days to the next random event (RandomEvent::day_to_event)
## WarPointArray: 8x8 zones where the player's men or buildings are under
## attack, flashing on the minimap; strength halves every frame. Display only.
var war_points := {}                 # zone -> strength
const WAR_ZONE := 8
var talk_log: Array = []             # the latest messages and their answers
var fog_of_war := true             # Config::fog_of_war: what is out of sight goes dark again
var last_new_nation_day := -1000    # NationArray::last_new_nation_date
var last_del_nation_day := -1000    # NationArray::last_del_nation_date
var hero_info: Array = []          # HeroRes::hero_info_array (HeroRes.init)
var hero_appear := true            # HeroRes::hero_appear_flag
var race_wanderers := {}            # TownArray::race_wander_pop_array: race -> people
var std_raw_sites := 0              # SiteArray::std_raw_site_count (0: not a set-up game)
var fast_build := false              # tutorial lessons: building and training ten times faster (config.fast_build)


## How much faster the player's construction and training go.
func work_speed(nid: int) -> float:
	return 10.0 if fast_build and nid == player_id else 1.0


func _init() -> void:
	inst = self


func _exit_tree() -> void:
	if inst == self:
		inst = null


# ------------------------------------------------------------------ setup ---

## cfg: {seed, size, race, ai_count, cash, indep_towns, lairs}
var config := {}
var last_winner := ""


## Config::terrain_set and its latitude (ogamsing.cpp: 45, 20, 70).
const TERRAIN_LATITUDE := [45, 20, 70]


func _apply_terrain_set() -> void:
	var ts := clampi(int(config.get("terrain_set", 1)), 1, 2)
	Assets.use_terrain_set(ts)
	weather.init_latitude(TERRAIN_LATITUDE[ts - 1])


## The colours at the start (Config::player_nation_color): the player's
## chosen one first, the others in their order.
func _start_color(i: int, _human: bool, cfg: Dictionary) -> Color:
	var all: Array = Defs.NATION_COLORS + Defs.EXTRA_NATION_COLORS
	var c: Color = all[clampi(int(cfg.get("color", 0)), 0, Defs.NATION_COLORS.size() - 1)]
	var order: Array = [c] + all.filter(func(x): return x != c)
	return order[i % order.size()]


func start(cfg: Dictionary) -> void:
	Defs.load_from_assets()
	config = cfg.duplicate()
	_apply_terrain_set()
	rng.seed = cfg.get("seed", randi())
	HeroRes.init(self)
	if cfg.get("campaign_battle") != null:
		var cb = cfg["campaign_battle"]
		var csize: int = cb.WORLD
		world = WorldMap.new(csize, csize)
		world.generate(rng)
		setup_layers()
		reveal_all = cfg.get("reveal", false)
		Assets.load_rocks()
		campaign_battle = cb
		cb.build(self)
		_generate_rocks(csize)
		_generate_trees(csize)
		update_links()
		_update_fog()
		_ground_dirty = true
		return
	if str(cfg.get("scenario", "")).get_extension() == "json":
		# a scenario made in the editor: a saved game that starts afresh
		var err := SaveGame.load_path(self, cfg["scenario"])
		if err != "":
			push_error(err)
		config = cfg.duplicate()
		day = 0
		frame = 0
		reveal_all = cfg.get("reveal", false)
		fog.fill(0)
		_update_fog()
		return
	if cfg.get("scenario", "") != "":
		var sf := ScenarioFile.new()
		if sf.load_file(cfg["scenario"]):
			ScenarioLoader.new().build(self, sf, cfg)
			config["size"] = world.w
			for t in towns:
				if t.nation_id > 0 and t.nation_id != GameObj.MONSTER_NATION:
					start_points.append(t.center_loc())
			return
		push_error("scenario: " + sf.error)
	var size: int = cfg.get("size", 120)
	world = WorldMap.new(size, size)
	world.generate(rng)
	setup_layers()
	reveal_all = cfg.get("reveal", false)
	fog_of_war = cfg.get("fog", true) if cfg.get("setup", false) else true
	_create_nations(cfg)
	_generate_starts(size)
	_generate_sites(size)
	_generate_independents(size, cfg)
	_generate_lairs(size, cfg)
	_generate_items()
	_generate_rocks(size)
	_generate_trees(size)
	update_links()
	if cfg.get("setup", false):
		_apply_setup(cfg)
	_update_fog()
	_ground_dirty = true


## Config settings applied once the map is made: the explored map, the spying
## methods everyone knows, the goals (Battle::create_pregame_object, ogame.cpp).
func _apply_setup(cfg: Dictionary) -> void:
	if cfg.get("explore", false):
		# explore_whole_map: the land is known from the start; with fog of war
		# off what has been seen stays in view (Location::visit_level)
		fog.fill(1 if fog_of_war else 2)
		for a in nations:
			for b in nations:
				if a != b:
					a.contact[b.id] = true
	if cfg.get("spy_methodology", false):
		# NationBase::init: inc_tech_class_level(TECH_CLASS_SPYING)
		for n in nations:
			if not n.is_fryhtan:
				for t in Defs.TECHS:
					if t.get("spy", false) and n.tech_level(t["code"]) == 0:
						n.tech[t["code"]] = 1
	var wins: Array = []
	if cfg.get("goal_destroy_monster", false):
		wins.append({"id": Goals.DEFEAT_ALL_FRYHTAN})
	if cfg.get("goal_population_flag", false):
		wins.append({"id": Goals.REACH_POPULATION, "p2": int(cfg["goal_population"])})
		wins.append({"id": Goals.REACH_FRYHTAN, "p2": int(cfg["goal_population"])})
	if cfg.get("goal_economic_flag", false):
		wins.append({"id": Goals.REACH_ECONOMY, "p2": int(cfg["goal_economic"])})
	if cfg.get("goal_total_flag", false):
		wins.append({"id": Goals.REACH_TOTAL, "p2": int(cfg["goal_total"])})
	if cfg.get("goal_alliance_flag", false) and nations.size() >= 4:
		wins.append({"id": Goals.DEFEAT_EXCEPT_ALLIANCE, "player_only": true})
	var years := int(cfg.get("goal_years", 0)) if cfg.get("goal_year_flag", false) else 0
	if wins.is_empty() and years == 0:
		return
	# ogame.cpp: every game is won by defeating the others and lost with one's own kingdom
	wins.push_front({"id": Goals.DEFEAT_ALL_OTHER_KINGDOMS, "player_only": true})
	goals = Goals.random_map(wins, years)


## Creates the render layers for an existing `world` (new game or loaded game).
func setup_layers() -> void:
	var size := world.w
	terrain_view = TerrainView.new()
	add_child(terrain_view)
	terrain_view.build(world)
	ground_layer = GroundLayer.new()
	ground_layer.game = self
	add_child(ground_layer)
	objects = Node2D.new()
	objects.y_sort_enabled = true
	add_child(objects)
	effects = Node2D.new()
	effects.z_index = 10
	add_child(effects)
	fog_view = FogView.new()
	add_child(fog_view)
	fog_view.build(size, size)
	fog.resize(size * size)


## NationBase::repair_all_building: order (or stop) repairs everywhere.
func repair_all(nid: int, on: bool) -> void:
	for f in firms:
		if f.nation_id == nid and not f.dead and (not on or f.hp < f.max_hp):
			f.repair = on
	for t in towns:
		if t.nation_id == nid and not t.dead and (not on or (t.wall_level > 0 and t.wall_hp < t.wall_max_hp())):
			t.repair_wall = on


## NationArray::new_nation during a game: a computer-run kingdom of `race`
## (Town::form_new_nation), neutral to all, in an unused colour.
func add_nation(race: String) -> Nation:
	var used := nations.map(func(x): return x.color)
	var col: Color = Defs.free_nation_color(used, nations.size())
	var n := Nation.new(nations.size() + 1, race, col, true)
	for o in nations:
		o.relations[n.id] = Defs.Relation.NEUTRAL
		n.relations[o.id] = Defs.Relation.NEUTRAL
	nations.append(n)
	var start := GameSetup.start_cash(config, true, false)
	n.cash = start[0]
	n.food = start[1]
	n.ai = NationAI.new(n, self)
	n.had_base = true
	return n


## Kingdoms: the player first, then AI rivals with different races.
func _create_nations(cfg: Dictionary) -> void:
	var race_pool: Array = Defs.races.map(func(r): return r["code"])
	race_pool.erase(cfg.get("race", "NORMAN"))
	var player_species := {}
	for m in Defs.monsters:
		if m["unit"] == cfg.get("race", ""):
			player_species = m
	# a network game: one kingdom for each player, in the host's order
	var humans: Array = cfg.get("mp", [{"race": cfg.get("race", "NORMAN"), "name": cfg.get("kingdom_name", "")}])
	for h in humans:
		race_pool.erase(h["race"])
	_shuffle(race_pool)
	var count: int = humans.size() + cfg.get("ai_count", 3)
	for i in count:
		var human := i < humans.size()
		var race: String = humans[i]["race"] if human else race_pool[(i - humans.size()) % race_pool.size()]
		if not human and cfg.get("random_start", false):
			race = Defs.races[rng.randi() % Defs.races.size()]["code"]     # Battle::create_ai_nation: any race
		var n := Nation.new(i + 1, race, _start_color(i, human, cfg), not human or cfg.get("autoplay", false))
		n.is_player = human
		player_species = {}
		for m in Defs.monsters:
			if human and m["unit"] == race:
				player_species = m
		if n.is_player and not player_species.is_empty():
			# the player leads a Fryhtan kingdom
			n.is_fryhtan = true
			n.monster_code = player_species["unit"]
			n.name = "%s Fryhtans" % player_species["name"]
			n.live_points = 600.0
		n.cash = float(cfg.get("cash", 3000))
		n.food = 0.0 if n.is_fryhtan else 1500.0
		if cfg.get("setup", false):
			var start := GameSetup.start_cash(cfg, n.is_ai and not human, n.is_fryhtan)
			n.cash = start[0]
			n.food = start[1]
			if n.is_fryhtan:
				n.live_points = start[2]
		if human and str(humans[i].get("name", "")) != "":
			if not cfg.has("mp"):
				n.name = humans[i]["name"]          # the kingdom's name from the start screen
			elif player_species.is_empty():
				n.name = "%s's Kingdom" % humans[i]["name"]
			else:
				n.name = "%s's Fryhtans" % humans[i]["name"]
		nations.append(n)
	# Fryhtan kingdoms (NationMonster): each a species with a lair and a brood.
	var species: Array = Defs.monsters.filter(func(m): return not humans.any(func(h): return h["race"] == m["unit"]))
	_shuffle(species)
	for i in int(cfg.get("fryhtan_count", 1)):
		if species.is_empty():
			break
		var m: Dictionary = species[i % species.size()]
		if cfg.get("random_start", false):
			m = Defs.monsters[rng.randi() % Defs.monsters.size()]
		var n := Nation.new(nations.size() + 1, m["unit"], Defs.free_nation_color(nations.map(func(x): return x.color), nations.size()), true)
		n.is_fryhtan = true
		n.monster_code = m["unit"]
		n.name = "%s Fryhtans" % m["name"]
		n.cash = float(cfg.get("cash", 3000)) * 0.7
		n.food = 0.0
		n.live_points = 600.0
		if cfg.get("setup", false):
			var start := GameSetup.start_cash(cfg, true, true)
			n.cash = start[0]
			n.food = start[1]
			n.live_points = start[2]
		nations.append(n)
	for a in nations:
		for b in nations:
			if a != b:
				# humans and Fryhtans start at war; everyone else neutral
				a.relations[b.id] = Defs.Relation.WAR if a.is_fryhtan != b.is_fryhtan else Defs.Relation.NEUTRAL
		if a.is_ai:
			a.ai = FryhtanAI.new(a, self) if a.is_fryhtan else NationAI.new(a, self)


func _random_free_rect(rw: int, rh: int, margin: int, avoid: Array, min_dist: float, tries := 400) -> Vector2i:
	for i in tries:
		var x := rng.randi_range(margin, world.w - rw - margin)
		var y := rng.randi_range(margin, world.h - rh - margin)
		if not world.can_place(x - 2, y - 2, rw + 4, rh + 4):
			continue
		if _overlaps_site(Rect2i(x - 2, y - 2, rw + 4, rh + 4)):
			continue
		var c := Vector2(x + rw * 0.5, y + rh * 0.5)
		var ok := true
		for p in avoid:
			if c.distance_to(p) < min_dist:
				ok = false
				break
		if ok:
			return Vector2i(x, y)
	return Vector2i(-1, -1)


## Fisher-Yates shuffle with the game's seeded generator (Array.shuffle uses the global one).
func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


const INTER_PLACE_SPACE := 2       # gamedef.h: free cells kept between places


## World::can_build_firm: the ground is free, and a band of INTER_PLACE_SPACE
## cells around it is free of buildings, towns and raw deposits (trees
## there are fine), so a way stays open between places. A mine (or an
## Alchemist Tor) stands on its deposit.
func can_build_firm(code: String, pos: Vector2i, w: int, h: int) -> bool:
	var on_raw := code in ["MINE", "ALCHEMY"]
	if not world.can_place(pos.x, pos.y, w, h, code == "MINE"):
		return false
	var r := Rect2i(pos, Vector2i(w, h))
	# the free band must lie within the map: no building hard against its edge
	# (an addition - the original lets the band end at the edge)
	if not Rect2i(0, 0, world.w, world.h).encloses(r.grow(INTER_PLACE_SPACE)):
		return false
	var outer := r.grow(INTER_PLACE_SPACE).intersection(Rect2i(0, 0, world.w, world.h))
	for y in range(outer.position.y, outer.end.y):
		for x in range(outer.position.x, outer.end.x):
			if not r.has_point(Vector2i(x, y)) and world.occupant[y * world.w + x] != null:
				return false
	for s in sites:
		var sf: Rect2i = s.footprint()
		if not sf.intersects(outer):
			continue
		if not (on_raw and sf.intersects(r)):       # its own deposit
			return false
	# an item, gold, a scroll or plans on the ground is a site too: nothing is
	# built over it (World::can_build_firm, locPtr->has_site())
	for t in treasures:
		if is_instance_valid(t) and r.has_point(t.cell):
			return false
	return true


func _overlaps_site(r: Rect2i) -> bool:
	for s in sites:
		if s.footprint().intersects(r):
			return true
	return false


func _occupied_centers() -> Array:
	var out := []
	for t in towns:
		out.append(t.center_loc())
	for f in firms:
		out.append(f.center_loc())
	return out


var start_points: Array = []
var _used_town_names := {}


func _generate_starts(size: int) -> void:
	var n := nations.size()
	var radius := size * 0.34
	var phase := rng.randf() * TAU
	for i in n:
		var nat := nations[i]
		var ang := phase + TAU * i / n
		var c := Vector2(size / 2.0, size / 2.0) + Vector2(cos(ang), sin(ang)) * radius
		var tpos := Vector2i(-1, -1)
		for t in 300:
			var p := Vector2i(c + Vector2(rng.randf_range(-8, 8), rng.randf_range(-8, 8)))
			if world.can_place(p.x - 2, p.y - 2, 10, 10):
				tpos = p
				break
		if tpos.x < 0:
			tpos = _random_free_rect(6, 6, 6, start_points, 20.0)
		start_points.append(Vector2(tpos) + Vector2(3, 3))
		if nat.is_fryhtan:
			_start_fryhtan(nat, tpos)
			continue
		var setup: bool = config.get("setup", false)
		# Battle::create_town: 60 people of loyalty 100 (30-60 with a random start)
		var pop := (30 + rng.randi() % 31 if config.get("random_start", false) else 60) if setup else rng.randi_range(32, 42)
		var town := spawn_town(nat.race, nat.id, tpos, pop)
		town.loyalty = 100.0 if setup else 70.0
		# Fort next to the town, commanded by the king.
		var fort_build := Assets.firm_build("FORT", nat.race)
		var fw: int = fort_build.get("loc_w", 6)
		var fpos := _place_near(Rect2i(tpos, Vector2i(6, 6)), fw, fort_build.get("loc_h", 6), 8, [Vector2(tpos) + Vector2(3, 3)])
		if fpos.x < 0:
			fpos = _place_near(Rect2i(tpos, Vector2i(6, 6)), fw, fort_build.get("loc_h", 6))
		var fort := spawn_firm("FORT", nat.id, nat.race, fpos, true)
		# Battle::create_unit: the king has combat and leadership 100
		var king := spawn_unit(Defs.unit_sprite(nat.race, "INF"), nat.id, Vector2i(fpos.x, fpos.y + fw + 1), 100.0)
		king.rank = Defs.Rank.KING
		king.leadership = 100.0
		# the player's king bears the player's name (config.player_name)
		if nat.id == player_id and str(config.get("player_name", "")) != "":
			king.unit_name = str(config["player_name"])
		nat.king = king
		if fort:
			if config.get("setup", false):
				fort.archers = 5           # create_human_town_unit: five archers on the walls
				fort.target_archers = 5
			fort.accept_unit(king)
			# create_human_town_unit: seven soldiers of basic training (combat 20)
			for k in 7:
				var s := spawn_unit(Defs.unit_sprite(nat.race, "INF"), nat.id, Vector2i(fpos.x, fpos.y + fw + 1), 20.0)
				s.leadership = 20.0
				fort.accept_unit(s)
		var spot := exit_cell(town.footprint(), Vector2i(tpos.x + 3, tpos.y + 7))
		if setup:
			# create_one_human_asset: only a random start adds men outside, the
			# fewer people the town has the more (soldiers 20-80, generals 30-100)
			if config.get("random_start", false):
				for k in (60 - town.population) / 3:
					var r: String = nat.race if rng.randi() % 2 == 0 else Defs.races[rng.randi() % Defs.races.size()]["code"]
					var gen := rng.randi() % 4 == 0
					var u := spawn_unit(Defs.unit_sprite(r, "INF"), nat.id, spot + Vector2i(k % 4, k / 4), float(30 + rng.randi() % 70) if gen else float(20 + rng.randi() % 60))
					if u:
						u.rank = Defs.Rank.GENERAL if gen else Defs.Rank.SOLDIER
						u.leadership = float(40 + rng.randi() % 50) if gen else float(10 + rng.randi() % 10)
						u.loyalty = float(80 + rng.randi() % 20)
			# start_up_has_mine_nearby: a deposit by the player's town
			if config.get("mine_nearby", false) and nat.id == player_id:
				var rows: Array = Assets.table("RAW").slice(0, 3)
				if not rows.is_empty():
					_add_site(rows[rng.randi() % rows.size()], Vector2(town.center_loc()), 9.0, 16.0)
			continue
		# A general and two soldiers outside, ready to build and explore.
		# generals 30-100 combat, 40-90 leadership; soldiers 20-80 (Battle::create_unit)
		var g := spawn_unit(Defs.unit_sprite(nat.race, "INF"), nat.id, spot, float(30 + rng.randi() % 70))
		g.rank = Defs.Rank.GENERAL
		g.leadership = float(40 + rng.randi() % 50)
		for k in 2:
			spawn_unit(Defs.unit_sprite(nat.race, "INF"), nat.id, spot + Vector2i(k + 1, 0), float(20 + rng.randi() % 60))


## A Fryhtan kingdom starts with a lair commanded by its leader and a brood.
func _start_fryhtan(nat: Nation, at: Vector2i) -> void:
	var lair := spawn_firm("LAIR", nat.id, nat.monster_code, at, true)
	if lair == null:
		return
	lair.monster_code = nat.monster_code
	# Battle::create_monster_town: the leader has combat 50-100, skill 20-100
	var leader := spawn_unit(nat.monster_code, nat.id, Vector2i(at.x, at.y + lair.h + 1), float(50 + rng.randi() % 50))
	if leader:
		leader.rank = Defs.Rank.KING
		leader.leadership = float(20 + rng.randi() % 80)
		nat.king = leader
		lair.accept_unit(leader)
	if config.get("setup", false):
		# Battle::create_one_monster_asset: a king of skill 100 and 300 hit
		# points' worth of brood at combat 20, inside the lair
		if leader:
			leader.leadership = 100.0
			leader.combat = 100.0
		var hp := int(Defs.unit_types.get(nat.monster_code, {}).get("hp", 100))
		for k in 300 / maxi(1, hp * 20 / 100):
			var u := spawn_unit(nat.monster_code, nat.id, Vector2i(at.x, at.y + lair.h + 1), 20.0)
			if u:
				u.leadership = 20.0
				lair.accept_unit(u)
		return
	for k in 5:
		var u := spawn_unit(nat.monster_code, nat.id, Vector2i(at.x, at.y + lair.h + 1), 20.0)
		if u:
			lair.accept_unit(u)
	var spot := exit_cell(lair.footprint(), Vector2i(at.x + 3, at.y + lair.h + 2))
	for k in 2:
		spawn_unit(nat.monster_code, nat.id, spot + Vector2i(k, 0), 40.0)


## Free position for a w x h building next to `r`. When `anchors` (location
## centres) are given, the building's centre must be within linking distance
## of every one of them.
func _place_near(r: Rect2i, fw: int, fh: int, max_gap := 8, anchors: Array = []) -> Vector2i:
	# the free band takes INTER_PLACE_SPACE cells of every gap
	for gap in range(INTER_PLACE_SPACE + 1, max_gap + INTER_PLACE_SPACE):
		var cands: Array[Vector2i] = []
		for x in range(r.position.x - fw - gap, r.end.x + gap + 1):
			cands.append(Vector2i(x, r.position.y - fh - gap))
			cands.append(Vector2i(x, r.end.y + gap))
		for y in range(r.position.y - fh - gap, r.end.y + gap + 1):
			cands.append(Vector2i(r.position.x - fw - gap, y))
			cands.append(Vector2i(r.end.x + gap, y))
		_shuffle(cands)
		for c in cands:
			# World::can_build_firm: the free band of INTER_PLACE_SPACE around it too
			if can_build_firm("", c, fw, fh):
				var center := Vector2(c) + Vector2(fw, fh) * 0.5
				if anchors.all(func(a): return _center_dist(center, a) <= Defs.EFFECTIVE_FIRM_TOWN_DISTANCE - 1):
					return c
	if not anchors.is_empty():
		return Vector2i(-1, -1)
	return _random_free_rect(fw, fh, 2, [], 0.0)


func _generate_sites(size: int) -> void:
	var raw_rows: Array = Assets.table("RAW").slice(0, 3)
	if raw_rows.is_empty():
		return
	if config.get("setup", false):
		# SiteArray::generate_raw_site(start_up_raw_site) anywhere on the land
		std_raw_sites = int(config.get("raw_sites", 6))
		for i in std_raw_sites:
			_add_site(raw_rows[rng.randi() % raw_rows.size()], Vector2(-1, -1), 0, 0)
		return
	var count := maxi(nations.size() + 2, size * size / 1100)
	# One deposit near every kingdom so each can start an economy.
	for p in start_points:
		_add_site(raw_rows[rng.randi() % raw_rows.size()], Vector2(p), 9.0, 16.0)
	for i in count - start_points.size():
		_add_site(raw_rows[rng.randi() % raw_rows.size()], Vector2(-1, -1), 0, 0)


func _add_site(row: Dictionary, near: Vector2, min_r: float, max_r: float) -> Site:
	var sw: int = row["LOC_WIDTH"].to_int()
	var sh: int = row["LOC_HEIGHT"].to_int()
	for t in 400:
		var x: int
		var y: int
		if near.x >= 0:
			var a := rng.randf() * TAU
			var d := rng.randf_range(min_r, max_r)
			x = int(near.x + cos(a) * d - sw / 2.0)
			y = int(near.y + sin(a) * d - sh / 2.0)
		else:
			x = rng.randi_range(4, world.w - sw - 4)
			y = rng.randi_range(4, world.h - sh - 4)
		if not world.can_place(x - 1, y - 1, sw + 2, sh + 2) or _overlaps_site(Rect2i(x - 3, y - 3, sw + 6, sh + 6)):
			continue
		var s := Site.new()
		s.raw = row["NAME"]
		s.row = row
		s.x1 = x
		s.y1 = y
		s.w = sw
		s.h = sh
		s.reserve = Defs.MAX_RAW_RESERVE_QTY * rng.randf_range(0.6, 1.0)
		sites.append(s)
		return s
	return null


func _generate_independents(size: int, cfg: Dictionary) -> void:
	var count: int = cfg.get("indep_towns", maxi(6, size * size / 1000))
	var used := _used_town_names
	var setup: bool = cfg.get("setup", false)
	# Battle::create_independent_town: the kingdoms' races and others up to seven
	var town_races: Array = []
	for n in nations:
		if not n.is_fryhtan and not town_races.has(n.race):
			town_races.append(n.race)
	while setup and town_races.size() < mini(7, Defs.races.size()):
		var r: String = Defs.races[rng.randi() % Defs.races.size()]["code"]
		if not town_races.has(r):
			town_races.append(r)
	for i in count:
		var avoid := _occupied_centers()
		var p := _random_free_rect(6, 6, 4, avoid, 13.0)
		if p.x < 0:
			continue
		if setup:
			var race_s: String = town_races[i % town_races.size()]
			var ts := spawn_town(race_s, 0, p, 30 + rng.randi() % 21, _town_name(used, race_s))
			var res := GameSetup.town_resistance(cfg, rng)
			for n in nations:
				ts.resistance[n.id] = float(res)
			ts.base_resistance = float(res)
			# independent towns with walls by the Resistance setting
			var wr := rng.randi() % 11
			match int(cfg.get("resistance", GameSetup.MODERATE)):
				GameSetup.MODERATE:
					ts.set_wall_level(2 if wr >= 9 else (1 if wr >= 4 else 0))
				GameSetup.HIGH:
					ts.set_wall_level(2 if wr >= 7 else 1)
			continue
		var race: String = Defs.races[rng.randi() % Defs.races.size()]["code"]
		var name := _town_name(used, race)
		var t := spawn_town(race, 0, p, rng.randi_range(15, 45), name)
		for n in nations:
			t.resistance[n.id] = float(rng.randi_range(50, 90)) if n.race != race else float(rng.randi_range(35, 70))


func _town_name(used: Dictionary, race := "") -> String:
	var pool: Array = Defs.town_names_by_race.get(race, Defs.town_names)
	for i in 50:
		var n: String = pool[rng.randi() % pool.size()] if not pool.is_empty() else "Town"
		if not used.has(n):
			used[n] = true
			return n
	return "Town %d" % used.size()


func _generate_lairs(size: int, cfg: Dictionary) -> void:
	var count: int = cfg.get("lairs", maxi(3, size * size / 2600))
	if cfg.get("setup", false):
		count = 7          # Battle::create_monster_lair(0, MAX_MONSTER_TYPE)
	for i in count:
		var m: Dictionary = Defs.monsters[rng.randi() % Defs.monsters.size()]
		var b := Assets.firm_build("LAIR", m["unit"])
		var lw: int = b.get("loc_w", 6)
		var lh: int = b.get("loc_h", 6)
		var p := Vector2i(-1, -1)
		for t in 200:
			var cand := _random_free_rect(lw, lh, 4, _occupied_centers(), 12.0, 50)
			if cand.x < 0:
				continue
			var ok := true
			for sp in start_points:
				if Vector2(cand).distance_to(sp) < 24.0:
					ok = false
					break
			if ok:
				p = cand
				break
		if p.x < 0:
			continue
		var lair := spawn_firm("LAIR", GameObj.MONSTER_NATION, m["unit"], p, true)
		if lair == null:
			continue
		lair.monster_code = m["unit"]
		if cfg.get("setup", false):
			# a general of combat 50-99 and skill 20-99, and 15/4 + 0-4 + 1 recruits
			var chief := spawn_unit(m["unit"], GameObj.MONSTER_NATION, Vector2i(p.x, p.y + lh), float(50 + rng.randi() % 50))
			if chief:
				chief.rank = Defs.Rank.GENERAL
				chief.leadership = float(20 + rng.randi() % 80)
				lair.accept_unit(chief)
			for k in 15 / 4 + rng.randi() % 5 + 1:
				var su := spawn_unit(m["unit"], GameObj.MONSTER_NATION, Vector2i(p.x, p.y + lh), 20.0)
				if su:
					lair.accept_unit(su)
			continue
		for k in rng.randi_range(3, 6):
			var u := spawn_unit(m["unit"], GameObj.MONSTER_NATION, Vector2i(p.x, p.y + lh), 20.0)
			if u:
				lair.accept_unit(u)


func _generate_trees(size: int) -> void:
	if Assets.plant_bitmaps.is_empty():
		return
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.08
	for y in world.h:
		for x in world.w:
			var c := Vector2i(x, y)
			if not world.is_free(c) or _overlaps_site(Rect2i(c, Vector2i.ONE)) or _near_building(c):
				continue
			var v := noise.get_noise_2d(x, y)
			if v > 0.25 and rng.randf() < 0.45 or rng.randf() < 0.01:
				_add_tree(c)
	# World::plant_init ends with plant_death(1, 2): every tree crowded by
	# more than two plants within two cells dies, leaving groves and copses
	for y in world.h:
		for x in world.w:
			var c := Vector2i(x, y)
			if not _plants.has(c):
				continue
			var near := 0
			for sy in range(y - 2, y + 3):
				for sx in range(x - 2, x + 3):
					if _plants.has(Vector2i(sx, sy)):
						near += 1
			if near > 2:
				_clear_trees(Rect2i(c, Vector2i.ONE))


func _near_building(c: Vector2i) -> bool:
	for t in towns:
		if t.footprint().grow(2).has_point(c):
			return true
	for f in firms:
		if f.footprint().grow(1).has_point(c):
			return true
	return false


func _add_tree(c: Vector2i) -> void:
	# keep a clear ring around start points
	for sp in start_points:
		if Vector2(c).distance_to(sp) < 9.0:
			return
	place_tree(c, rng.randi() % Assets.plant_bitmaps.size())


func place_tree(c: Vector2i, variant: int) -> void:
	var pb: Dictionary = Assets.plant_bitmaps[variant % Assets.plant_bitmaps.size()]
	var p := Plant.new()
	p.variant = variant
	p.tex = pb["tex"]
	p.ofs = pb["ofs"]
	p.position = Iso.to_screen(Vector2(c))
	p.set_meta("cell", c)
	objects.add_child(p)
	world.set_plant(c, true)
	_plants[c] = p


var _plants := {}
var rocks: Array[Rock] = []
var lakes: Array = []       # [type index, x1, y1] flat lake decals drawn by the ground layer


## World::gen_rocks / gen_dirt: mountain groups ringed by boulders, single
## boulders, and lakes, kept clear of towns, buildings and deposits.
func _generate_rocks(size: int) -> void:
	var types := Assets.load_rocks()
	if types.is_empty():
		return
	var area := size * size
	var groups := maxi(3, area / 1100)
	var large := maxi(4, area / 900)
	var small := maxi(4, area / 700)
	var lake_count := maxi(2, area / 2500)
	var trials := (groups + large + small + lake_count) * 8
	while trials > 0 and (groups > 0 or large > 0 or small > 0 or lake_count > 0):
		trials -= 1
		if groups > 0:
			var at := Vector2i(rng.randi_range(4, world.w - 12), rng.randi_range(4, world.h - 12))
			var big := _pick_rock("R", 4, 8, at)
			if big >= 0 and _try_add_rock(big, at):
				groups -= 1
				var t: Dictionary = types[big]
				for sub in 12:
					var a := rng.randf() * TAU
					var sp := Vector2i(Vector2(at) + Vector2(t["w"], t["h"]) * 0.5 + Vector2(cos(a), sin(a)) * (t["w"] / 2.0 + 2.0))
					var smallr := _pick_rock("R", 1, 3, sp)
					if smallr >= 0:
						_try_add_rock(smallr, sp)
		if large > 0:
			var at := Vector2i(rng.randi_range(2, world.w - 6), rng.randi_range(2, world.h - 6))
			var r := _pick_rock("R", 2, 3, at)
			if r >= 0 and _try_add_rock(r, at):
				large -= 1
		if small > 0:
			var at := Vector2i(rng.randi_range(2, world.w - 4), rng.randi_range(2, world.h - 4))
			var r := _pick_rock("R", 1, 2, at)
			if r >= 0 and _try_add_rock(r, at):
				small -= 1
		if lake_count > 0:
			var at := Vector2i(rng.randi_range(4, world.w - 10), rng.randi_range(4, world.h - 10))
			var r := _pick_rock("P", 1, 8, at)
			if r >= 0 and _try_add_rock(r, at):
				lake_count -= 1


## Random rock type of `type` whose size is within [min_s, max_s] and whose
## terrain range accepts the terrain at `at`; -1 if none.
func _pick_rock(type: String, min_s: int, max_s: int, at: Vector2i) -> int:
	var cands: Array[int] = []
	var terr := world.corner(at.x, at.y)
	for i in Assets.rock_types.size():
		var t: Dictionary = Assets.rock_types[i]
		if t["type"] != type or t["w"] < min_s or t["w"] > max_s or t["h"] < min_s or t["h"] > max_s:
			continue
		if terr < t["t1"] or terr > t["t2"]:
			continue
		cands.append(i)
	if cands.is_empty():
		return -1
	return cands[rng.randi() % cands.size()]


func _try_add_rock(type_index: int, at: Vector2i) -> bool:
	var t: Dictionary = Assets.rock_types[type_index]
	var r := Rect2i(at, Vector2i(t["w"], t["h"]))
	if r.position.x < 1 or r.position.y < 1 or r.end.x >= world.w - 1 or r.end.y >= world.h - 1:
		return false
	# every corner of the footprint must suit the rock (RockInfo::valid_terrain)
	for c in [r.position, Vector2i(r.end.x, r.position.y), Vector2i(r.position.x, r.end.y), r.end]:
		var terr := world.corner(c.x, c.y)
		if terr < t["t1"] or terr > t["t2"]:
			return false
	if not world.can_place(r.position.x, r.position.y, r.size.x, r.size.y, true):
		return false
	# keep INTER_PLACE_SPACE*2 clear of towns, buildings and raw sites
	var outer := r.grow(4)
	if _overlaps_site(outer):
		return false
	for tw in towns:
		if tw.footprint().intersects(outer):
			return false
	for f in firms:
		if f.footprint().intersects(outer):
			return false
	for sp in start_points:
		if Rect2(Vector2(r.position), Vector2(r.size)).grow(6).has_point(sp):
			return false
	add_rock(type_index, at)
	return true


func add_rock(type_index: int, at: Vector2i) -> void:
	var t: Dictionary = Assets.rock_types[type_index]
	if t["type"] == "P":
		lakes.append([type_index, at.x, at.y])
		var marker := Rock.new()       # invisible blocker for the lake's locations
		marker.setup(type_index, at)
		marker.tex = null
		world.occupy(marker, at.x, at.y, t["w"], t["h"])
		rocks.append(marker)
		_ground_dirty = true
		return
	var rk := Rock.new()
	rk.setup(type_index, at)
	objects.add_child(rk)
	world.occupy(rk, at.x, at.y, t["w"], t["h"])
	rocks.append(rk)


## World::plant_ops as the shipped game runs it: its plant_limit is never set,
## so trees neither seed nor spread; a sample of them grows a stage, and trees
## crowded by more than two plants within three cells die off.
func _plant_ops() -> void:
	if _plants.is_empty():
		return
	const DENSITY := 16
	var yb := rng.randi() % DENSITY
	var xb := rng.randi() % DENSITY
	for y in range(yb, world.h, DENSITY):
		for x in range(xb, world.w, DENSITY):
			var c := Vector2i(x, y)
			if _plants.has(c) and rng.randi() % 100 < 40:
				var v: int = _plants[c].variant % Assets.plant_bitmaps.size()
				if v + 1 < Assets.plant_bitmaps.size() and Assets.plant_bitmaps[v + 1]["plant"] == Assets.plant_bitmaps[v]["plant"]:
					_plants[c].queue_free()
					_plants.erase(c)
					place_tree(c, v + 1)
	yb = rng.randi() % DENSITY
	xb = rng.randi() % DENSITY
	for y in range(yb, world.h, DENSITY):
		for x in range(xb, world.w, DENSITY):
			var c := Vector2i(x, y)
			if not _plants.has(c):
				continue
			var near := 0
			for sy in range(y - 3, y + 4):
				for sx in range(x - 3, x + 4):
					if _plants.has(Vector2i(sx, sy)):
						near += 1
			if near > 2:
				_clear_trees(Rect2i(c, Vector2i.ONE))


func _clear_trees(r: Rect2i) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, y)
			if _plants.has(c):
				_plants[c].queue_free()
				_plants.erase(c)
				world.set_plant(c, false)


# ---------------------------------------------------------------- spawning ---

func spawn_unit(sprite: String, nation_id: int, at: Vector2i, skill: float) -> Unit:
	if not Defs.unit_types.has(sprite) or not Assets.has_sprite(sprite):
		return null
	var c := world.nearest_walkable(at)
	if c.x < 0:
		c = at
	var u := Unit.new()
	u.setup(sprite, nation_id, c, skill)
	objects.add_child(u)
	units.append(u)
	return u


func spawn_town(race: String, nation_id: int, at: Vector2i, pop: int, name := "") -> Town:
	var t := Town.new()
	if name == "":
		name = _town_name(_used_town_names, race)
	_used_town_names[name] = true
	t.setup(name, race, nation_id, at, pop)
	objects.add_child(t)
	towns.append(t)
	world.occupy(t, at.x, at.y, Defs.TOWN_SIZE, Defs.TOWN_SIZE)
	_clear_trees(t.footprint().grow(2))
	_ground_dirty = true
	return t


## World::can_build_town: a free town-sized place with a cell of room around it.
func can_build_town(at: Vector2i) -> bool:
	# World::can_build_town: the same free band of INTER_PLACE_SPACE as a firm
	return can_build_firm("", at, Defs.TOWN_SIZE, Defs.TOWN_SIZE)


const TOWN_BUILDING_COST := 200.0


## TownArray::build_town: the unit (or wagon) builds a town and moves in when
## it is finished.
func found_town(u: Unit, at: Vector2i) -> Town:
	if not u.can_found_town() or not can_build_town(at):
		if u.nation_id == player_id:
			notify("A town cannot be built there.", u.center_loc())
		return null
	var n := u.nation()
	if n and not n.can_afford(TOWN_BUILDING_COST):
		if u.nation_id == player_id:
			notify("Building a town costs %d gold." % int(TOWN_BUILDING_COST), u.center_loc())
		return null
	if n:
		n.add_cash(-TOWN_BUILDING_COST, "Construction")
	var t := spawn_town(u.settler_race(), u.nation_id, at, 0)
	t.under_construction = true
	t.build_progress = 0.0
	t.builder_pop = u.settlers()
	t.builder_loyalty = u.loyalty if u.nation_id > 0 else 50.0
	if u.nation_id == 0:
		for nid in nation_ids():
			t.resistance[nid] = 60.0
	remove_unit(u)
	update_links()
	return t


func spawn_firm(code: String, nation_id: int, race: String, at: Vector2i, complete: bool, build_row := 0) -> Firm:
	var f := Firm.new()
	f.build_row = build_row
	f.setup(code, nation_id, race, at)
	if code == "ALCHEMY":
		var s := site_at_rect(f.footprint())
		if s and s.mine == null:
			f.site = s
			f.raw = s.raw
			f.reserve = s.reserve
			s.mine = f
	if code == "MINE":
		var s := site_at_rect(f.footprint())
		if s == null or s.mine != null:
			f.free()
			return null
		f.x1 = s.x1
		f.y1 = s.y1
		f.position = Iso.to_screen(f.center_loc())
		f.site = s
		f.raw = s.raw
		f.reserve = s.reserve
		s.mine = f
	# a new building site never goes on top of another place
	if not complete and not world.can_place(f.x1, f.y1, f.w, f.h, code == "MINE"):
		if f.site and f.site.mine == f:
			f.site.mine = null
		f.free()
		return null
	objects.add_child(f)
	firms.append(f)
	world.occupy(f, f.x1, f.y1, f.w, f.h)
	_clear_trees(f.footprint().grow(1))
	if complete:
		f.under_construction = false
		f.progress = 100.0
	else:
		f.under_construction = true
		f.progress = 0.0
		f.hp = f.max_hp * 0.1
	_ground_dirty = true
	update_links()
	return f


## Arrow shot by a town's villagers (Town::process_attack_target).
## Worshippers at a kingdom's Seat of Power (god_res[...]->nation_prayer_count).
func prayer_count(nid: int) -> int:
	var c := 0
	for f in firms:
		if f.nation_id == nid and f.code == "BASE" and not f.under_construction and not f.dead:
			c += f.workers()
	return c


## GodInfo::nation_prayer_count: worshippers at the kingdom's Seats of Power of `race`.
func god_worshippers(nid: int, race: String) -> int:
	var n := 0
	for f in firms:
		if f.code == "BASE" and f.race == race and f.nation_id == nid and not f.dead:
			n += f.workers()
	return n


func god_worshipped(nid: int, race: String) -> bool:
	return nid > 0 and god_worshippers(nid, race) > 0


## True when nation `nid` is of `race` and has worshippers: its god's blessing applies.
func blessed(nid: int, race: String) -> bool:
	var n := nation(nid)
	return n != null and n.race == race and not n.is_fryhtan and prayer_count(nid) > 0


## A lightning bolt hits near a random unit (olightn.cpp); units at the spot
## take their sprite's LIGHTN_DMG.
func _lightning_strike() -> void:
	var pool := units.filter(func(u): return not u.dead and u.inside_firm == null)
	if pool.is_empty():
		return
	var u: Unit = pool[rng.randi() % pool.size()]
	var at := u.center_loc() + Vector2(rng.randf_range(-3, 3), rng.randf_range(-3, 3))
	for v in units.duplicate():
		if v.dead or v.inside_firm or v.center_loc().distance_to(at) > 1.2:
			continue
		var dmg := float(Assets.sprites.get(v.sprite_code, {}).get("lightning", 50))
		if dmg > 0:
			v.take_damage(dmg, null)
	lightning.emit(Iso.to_screen(at))


## Nearest market a caravan from `home` could trade with: one it is not
## already linked to, owned by the same kingdom or one at peace with it.
func find_trade_partner(home: Firm, nid: int) -> Firm:
	var n := nation(nid)
	var best: Firm = null
	var best_d := 90.0
	for f in firms:
		if f == home or f.dead or f.code != "MARKET" or f.under_construction:
			continue
		if f in home.linked_firms:
			continue
		if f.nation_id != nid and not Diplomacy.has_trade(n, f.nation_id):
			continue
		var d := f.center_loc().distance_to(home.center_loc())
		if d > 8.0 and d < best_d:
			best_d = d
			best = f
	return best


## Caravans with a stop at this market.
func caravans_of(market: Firm) -> int:
	return units.filter(func(u): return u.is_caravan and not u.dead and u.stops.any(func(s): return s.get("firm") == market)).size()


# ------------------------------------------------------------ espionage ---

var spies: Array[Unit] = []        # spies currently inside a town or building


func spy_enter(u: Unit, place: GameObj) -> void:
	u.stop()
	Espionage.stop_camouflage(u)
	u.inside_firm = null
	u.visible = false
	u.spy_place = place
	u.set_meta("hidden", true)
	deselect(u)
	if not spies.has(u):
		spies.append(u)
	if u.nation_id == player_id:
		if place.nation_id == player_id:
			notify("Your spy is watching for enemy spies in %s." % place.display_name(), place.center_loc())
		else:
			notify("Your spy has infiltrated %s." % place.display_name(), place.center_loc())


## Spy::mobilize_spy: the spy walks out wearing the colours of the place he left.
func spy_leave(u: Unit) -> void:
	spies.erase(u)
	if u.dead:
		return
	var place := u.spy_place
	u.spy_place = null
	u.remove_meta("hidden")
	u.visible = true
	if place and is_instance_valid(place):
		u.cloak_id = place.nation_id if place.nation_id > 0 and place.nation_id != u.nation_id and nation(place.nation_id) and not nation(place.nation_id).is_fryhtan else 0
		var c := exit_cell(place.footprint(), Vector2i(place.center_loc()))
		u.loc = Vector2(c)
		u.position = Iso.to_screen(u.loc)
	u.queue_redraw()


## A spy unmasked by counter-espionage (SpyArray::catch_spy -> Spy::get_killed).
func spy_caught(u: Unit) -> void:
	var place := u.spy_place
	if place and place.nation_id == player_id:
		notify("An enemy spy was caught in %s!" % place.display_name(), place.center_loc())
	elif u.nation_id == player_id:
		notify("Your spy in %s has been caught and executed." % place.display_name(), place.center_loc())
	kill_spy(u)


## A spy dies on a failed mission or when caught. Spying on a kingdom at peace
## costs reputation.
func kill_spy(u: Unit) -> void:
	var place := u.spy_place
	spies.erase(u)
	var n := nation(u.nation_id)
	if n and place and is_instance_valid(place):
		var victim := nation(place.nation_id)
		if victim and victim.id != n.id and victim.relation(u.nation_id) >= Defs.Relation.PEACE:
			n.change_reputation(-5.0)
	u.spy_place = null
	u.remove_meta("hidden")
	u.die(null)
	remove_unit(u)


## Kills a man inside a building (an assassinated general).
func kill_inside(f: Firm, u: Unit) -> void:
	if f.overseer == u:
		f.overseer = null
	f.soldiers.erase(u)
	u.inside_firm = null
	u.die(null)
	remove_unit(u)
	update_links()


## A bribed man let out of his fort turns to his true master as a spy in the
## field, still wearing the colours he served (Spy::mobilize_firm_spy).
func sleeper_wakes(u: Unit, f: Firm) -> void:
	var master := u.sleeper_for
	u.sleeper_for = 0
	u.nation_id = master
	u.is_spy = true
	u.spy_skill = float(u.get_meta("sleeper_skill", Espionage.SLEEPER_SKILL))
	u.remove_meta("sleeper_skill")
	u.cloak_id = f.nation_id if nation(f.nation_id) and not nation(f.nation_id).is_fryhtan else 0
	u.rank = Defs.Rank.SOLDIER if u.rank == Defs.Rank.GENERAL else u.rank
	u.home_firm = null
	notify_nation(master, "%s, who took your bribe, has left %s and reports to you." % [u.display_name(), f.display_name()], f.center_loc())


## A building has changed hands: links, the AI's bookkeeping, messages.
func on_firm_changed(f: Firm, old_nation: int) -> void:
	deselect(f)
	update_links()
	var n := nation(f.nation_id)
	if observer():
		notify("%s now belongs to the %s." % [f.display_name(), n.name if n else "independents"], f.center_loc())


func spawn_tornado(caster: Unit, at: Vector2) -> void:
	var t := Tornado.new()
	t.setup(caster.nation_id, at)
	effects.add_child(t)
	tornadoes.append(t)


## A one-shot animated sprite (spell effects such as RO_EFF1) at a location.
func spawn_sprite_effect(code: String, at: Vector2, color: Color) -> void:
	var e := SpriteEffect.new()
	e.setup(code, at, color)
	effects.add_child(e)
	effects_list.append(e)


## Earthquakes (World::earth_quake, Weather::quake_rate): within the radius
## the rate is 100 less half the distance; buildings lose that many hit points,
## town walls take it and the towns lose people, units lose the rate times
## their hit points over 400 (at least 5, never their last point). A god's
## quake (MagicWeather::cast_quake) lasts two days; with random events on,
## nature sends one now and then anywhere (Weather::day_to_quake).
var quake := {}                      # {x, y, radius, days}
var day_to_quake := -1


func cast_quake(at: Vector2i, radius: int) -> void:
	quake = {"x": at.x, "y": at.y, "radius": radius, "days": 2}


func quake_rate(c: Vector2) -> int:
	if quake.is_empty():
		return 0
	var d := int(c.distance_to(Vector2(quake["x"], quake["y"])))
	return maxi(0, 100 - d / 2) if d <= int(quake["radius"]) else 0


func _quake_next_day() -> void:
	var freq := int(config.get("random_events", 0))
	if freq > 0:
		var period := 2000 - freq * 400 + int(config.get("seed", 0)) % 300
		if day_to_quake < 0:
			day_to_quake = period + rng.randi() % period
		day_to_quake -= 1
		if day_to_quake <= 0:
			day_to_quake = period + rng.randi() % period
			quake = {"x": rng.randi() % world.w, "y": rng.randi() % world.h, "radius": 500, "days": 1}
	if quake.is_empty():
		return
	earth_quake()
	quake["days"] -= 1
	if quake["days"] <= 0:
		quake = {}


func earth_quake() -> void:
	for f in firms.duplicate():
		if f.dead:
			continue
		var r := quake_rate(f.center_loc())
		if r <= 0:
			continue
		f.hp -= r
		if f.hp <= 0.0:
			f.hp = 0.0
			f.die(null)
	for t in towns:
		if t.dead or t.population == 0:
			continue
		var dmg := quake_rate(t.center_loc())
		if dmg <= 0:
			continue
		if t.wall_level > 0 and t.wall_hp >= dmg:
			t.wall_hp -= dmg
			dmg /= 2
		elif t.wall_level > 0:
			dmg -= int(t.wall_hp) / 2
			t.wall_hp = 0.0
		for k in dmg / 20:
			if t.population > 0:
				t.population -= 1
		t.queue_redraw()
	for u in units:
		if u.dead or u.inside_firm != null or u.utype.get("flying", false):
			continue
		var r := quake_rate(u.center_loc())
		if r <= 0:
			continue
		var dmg := float(r) * u.max_hp / 400.0
		if dmg >= u.hp:
			dmg = u.hp - 1.0
		dmg = maxf(dmg, 5.0)
		u.hp -= dmg
		if u.hp <= 0.0:
			u.hp = 0.0
			u.die(null)
	shake.emit(10.0)
	if player():
		notify("An earthquake has struck!", Vector2(quake["x"], quake["y"]))


## Weather::has_tornado: twenty days at least after the last, in hot windy
## weather, a tornado comes in from the edge the wind blows from (random events on).
var tornado_count := 1


func _natural_tornado() -> void:
	if int(config.get("random_events", 0)) == 0:
		return
	if tornado_count > 20 and weather.base_temp() >= 25 and weather.wind_spd >= 40 and rng.randi() % 10 < 2:
		tornado_count = 0
		var d := (weather.wind_dir + 180) % 360
		var mx := world.w
		var my := world.h
		var x: int
		var y: int
		if d < 45:
			x = mx * (d + 45) / 90
			y = 0
		elif d < 135:
			x = mx - 1
			y = my * (d - 45) / 90
		elif d < 225:
			x = mx * (224 - d) / 90
			y = my - 1
		elif d < 315:
			x = 0
			y = my * (314 - d) / 90
		else:
			x = mx * (d - 315) / 90
			y = 0
		var t := Tornado.new()
		t.setup(0, Vector2(x, y))
		t.life = 600
		effects.add_child(t)
		tornadoes.append(t)
	else:
		tornado_count += 1


## Mithra: the land around is revealed (for the player's fog of war).
func reveal_area(nid: int, c: Vector2i, r: int) -> void:
	if nid != player_id:
		return
	_reveal(c, r)
	for i in fog.size():
		if fog[i] == 2 and fog_of_war:
			fog[i] = 1
	_reveal(c, r)
	fog_view.update_from(fog)
	_ground_dirty = true
	_explore_contacts()


## NationBase::init_relation: computer kingdoms know each other from the start,
## as do the human rulers of a network game; a human ruler meets a computer
## kingdom when exploring reveals its town or building, or at once on a
## revealed map.
func _init_contacts() -> void:
	contacts_ready = true
	for a in nations:
		for b in nations:
			if a.id < b.id and (a.is_ai == b.is_ai or reveal_all):
				establish_contact(a.id, b.id)


## World::explore: an explored town or building of a kingdom we have not met
## makes the contact (a command, so every machine of a network game agrees).
var _contact_asked := {}


func _explore_contacts() -> void:
	var me := player()
	if me == null or reveal_all or not contacts_ready:
		return
	var found := {}
	for t in towns:
		if t.nation_id > 0 and t.nation_id != me.id and not me.contact.has(t.nation_id) and not _contact_asked.has(t.nation_id) and is_explored_rect(t.footprint()):
			found[t.nation_id] = true
	for f in firms:
		if f.nation_id > 0 and f.nation_id != GameObj.MONSTER_NATION and f.nation_id != me.id and not me.contact.has(f.nation_id) and not _contact_asked.has(f.nation_id) and is_explored_rect(f.footprint()):
			found[f.nation_id] = true
	for nid in found:
		_contact_asked[nid] = true    # asked once (not game state); the command makes it mutual
		Net.cmd(self, "establish_contact", [me.id, nid])


func establish_contact(a: int, b: int) -> void:
	var na := nation(a)
	var nb := nation(b)
	if na == null or nb == null or a == b:
		return
	var new := not (na.contact.has(b) and nb.contact.has(a))
	na.contact[b] = true
	nb.contact[a] = true
	if new and contacts_ready and (a == player_id or b == player_id) and day > 1:
		notify("You have made contact with the %s." % (nb.name if a == player_id else na.name), Vector2(-1, -1))


## Tengri: a unit changes sides (Unit::betray).
func defect_unit(u: Unit, to_nation: int) -> void:
	if u.inside_firm:
		return
	var old := u.nation_id
	u.stop()
	u.home_firm = null
	u.home_town = null
	u.rank = Defs.Rank.SOLDIER if u.rank == Defs.Rank.GENERAL else u.rank
	u.nation_id = to_nation
	u.queue_redraw()
	deselect(u)
	if observer():
		var tn := nation(to_nation)
		notify("A %s has defected to the %s." % [u.type_name(), tn.name if tn else "independents"], u.center_loc())
	elif to_nation == player_id:
		notify("A %s has joined your side!" % u.type_name(), u.center_loc())
	elif old == player_id:
		notify("One of your units has defected!", u.center_loc())


func spawn_town_arrow(from: GameObj, to: Unit, sprite: String, dmg: float, spd := 16.0) -> void:
	var b := Bullet.new()
	b.shooter = from
	b.target = to
	b.sprite_code = sprite
	b.speed = spd
	b.damage = dmg
	b.color = from.nation_color()
	b.position = Iso.to_screen(from.center_loc()) + Vector2(0, -30)
	b.dest = Iso.to_screen(to.center_loc())
	b.dir = maxi(0, Iso.dir_of(to.center_loc() - from.center_loc()))
	b.z_index = 2
	effects.add_child(b)
	bullets.append(b)


func spawn_effect(part: int, at: Vector2, loops := 0) -> FirmEffect:
	var e := FirmEffect.new()
	e.setup(part, at, loops)
	effects.add_child(e)
	effects_list.append(e)
	return e


func spawn_bullet(from: Unit, to: GameObj, sprite: String, spd: float, dmg: float) -> Bullet:
	var b := Bullet.new()
	b.setup(from, to, sprite, spd, dmg)
	effects.add_child(b)
	bullets.append(b)
	return b


# ------------------------------------------------------------ ground fire ---
# World::spread_fire with the original's default settings (fire_spread_rate 0:
# fires do not spread): a burning cell hurts whoever stands on it and the
# building over it, burns its tree, and dies down in a few days; rain and snow
# put it out sooner (Location::fire_str / fire_src).

const FIRE_SCAN := 16               # each cell is looked at every SCAN_FIRE_DIST^2 frames
const FIRE_DAMAGE := 2.0 / 3.0      # config.fire_damage / ATTACK_SLOW_DOWN

var fires := {}                     # cell -> [fire strength, flammability]


## The unit paths to draw (draw_unit_path_on_zoom_map): the selected units of
## the player that are on the move, when "Show Unit Paths" is on for this map
## (`bit` 1 the main view, 2 the world map), and, while the player's Japanese
## Greater Being has worshippers, the paths of units marching to attack him
## (in red). Returns [[points in locations], is_attacker], display only.
func unit_paths(bit: int) -> Array:
	var out: Array = []
	var own := int(GameOptions.get_opt("show_unit_path")) & bit != 0
	var inside := bool(GameOptions.get_opt("show_ai_info"))
	var warned := firms.any(func(f): return f.code == "BASE" and f.race == "JAPANESE" and f.nation_id == player_id and not f.dead and f.workers() > 0)
	if not own and not warned:
		return out
	for u in units:
		if u.dead or u.inside_firm != null or not u.visible or u.path.is_empty() or u.path_i >= u.path.size():
			continue
		var attacker := false
		if own and u in selected and (u.nation_id == player_id or inside) and u.order != Unit.Order.IDLE:
			pass
		elif warned and u.order == Unit.Order.ATTACK and u.target and is_instance_valid(u.target) 				and u.target.nation_id == player_id and not u.attacking:
			attacker = true
		else:
			continue
		var pts: Array = [u.center_loc()]
		for i in range(u.path_i, u.path.size()):
			pts.append(Vector2(u.path[i]) + Vector2(0.5, 0.5))
		if not attacker:
			for w in u.waypoints:
				pts.append(Vector2(w) + Vector2(0.5, 0.5))
		out.append([pts, attacker])
	return out


## UnitGroup::formation (a command): the general among `units` keeps the
## formation, and the troop forms up in it where the general stands.
func form_troop(units: Array, kind: int, facing: Vector2) -> void:
	var own := units.filter(func(u): return u is Unit and not u.dead and u.inside_firm == null)
	var general = null
	for u in own:
		if u.rank >= Defs.Rank.GENERAL:
			general = u
			break
	if general == null:
		return
	general.formation = kind
	if facing.length() > 0.01:
		general.formation_dir = facing
	move_troop(own, general.cell())


## A group move: in its general's formation when he has one, facing the
## way it marches unless he has a set facing.
func move_troop(units: Array, dest: Vector2i, facing := Vector2.ZERO) -> bool:
	var general = null
	for u in units:
		if u is Unit and u.rank >= Defs.Rank.GENERAL and u.formation > 0:
			general = u
			break
	if general == null:
		return false
	# the general's set direction, or the first that fits (no set direction)
	for u in units:
		if u != general:
			u.leader = general          # the troop follows its general (TeamInfo)
	var cells := Formations.place(self, units, dest, general.formation_dir, general.formation)
	if cells.is_empty():
		# no direction fits there: the troop goes as a plain group
		var spot := dest
		for u in units:
			u.order_move_free(free_unit_cell(spot))
			spot = free_unit_cell(spot)
		return true
	for u in cells:
		u.order_move_free(cells[u])
	return true


## WarPoint::inc
func add_war_point(at: Vector2) -> void:
	var z := Vector2i(int(at.x) / WAR_ZONE, int(at.y) / WAR_ZONE)
	war_points[z] = mini(0x1000000, int(war_points.get(z, 0)) + 0x100000)


## Bullet::process_die: a fire bomb sets the cells within `radius` alight.
func set_fire(c: Vector2i, radius: int) -> void:
	for y in range(c.y - radius + 1, c.y + radius):
		for x in range(c.x - radius + 1, c.x + radius):
			var p := Vector2i(x, y)
			var dist := absi(x - c.x) + absi(y - c.y)
			if dist > radius or not world.inside(p) or world.is_hill(p) or world.object_at(p) is Rock:
				continue
			var strength := 30 if radius == 1 else maxi(10, 30 - dist * 7)
			var f: Array = fires.get(p, [-100, 1])
			f[0] = maxi(f[0], strength)
			f[1] = 1           # such that the fire will be put out quickly
			fires[p] = f


func _process_fires() -> void:
	var rain := 0
	if weather.rain_scale() > 0:
		rain = 5 + weather.rain_scale() / 4      # RAIN_SNOW_REDUCTION (the shipped game has no snow)
	for p in fires.keys():
		var f: Array = fires[p]
		var old: int = f[0]
		var strength: int = maxi(-100, f[0] - rain)
		var flam: int = f[1]
		if strength > 0:
			var hit := false
			for u in unit_grid.get(Vector2i(p.x >> GRID_SHIFT, p.y >> GRID_SHIFT), []):
				if not u.dead and u.cell() == p:
					u.take_damage(2.0 * FIRE_DAMAGE, null)
					hit = true
					break
			if not hit:
				var o = world.object_at(p)
				if o is Firm and not o.dead:
					o.take_damage(FIRE_DAMAGE, null)
			if flam > 0:
				strength = mini(100, strength + 1)
				flam -= 2
			elif flam >= -50:
				strength -= 2
				flam = maxi(-50, flam - 2)
			else:
				strength = -100
			if flam <= 0 and _plants.has(p):
				_clear_trees(Rect2i(p, Vector2i.ONE))
			if visible and is_loc_visible(p) and fx_rng.randf() < 0.5:
				spawn_effect(3, Vector2(p))
		else:
			strength = maxi(-100, strength - 1)
		if strength <= 0 and old > 0:
			strength -= 50
		if strength <= 0:
			fires.erase(p)
		else:
			fires[p] = [strength, flam]


# ------------------------------------------------------------- treasures ---

## Scenario site numbers of scrolls and items taken, and by whom (for goals).
var taken_sites := {}


func spawn_treasure(kind: int, obj: int, para: int, at: Vector2i, recno := 0) -> Treasure:
	var t := Treasure.new()
	t.setup(kind, obj, para, at)
	t.recno = recno
	objects.add_child(t)
	treasures.append(t)
	return t


## Battle::create_random_item: three to six ordinary items about the map.
func _generate_items() -> void:
	var n := 3 + rng.randi_range(0, 3)
	for i in n:
		var id := Items.random_id(rng, Items.MIN_RARITY, Items.MIN_RARITY + 1)
		if id == 0:
			break
		var r := _random_free_rect(3, 3, 4, [], 0.0)
		if r.x < 0:
			break
		spawn_treasure(Treasure.Kind.ITEM, id, Items.random_para(id, rng), r + Vector2i.ONE)


## SiteArray::next_day: a unit standing on a treasure takes it (Site::get_site_object).
func _pick_up_treasures() -> void:
	for t in treasures.duplicate():
		# SiteArray::next_day takes it for the unit standing on it; one that
		# cannot be stood on (built over, blocked) is taken from beside it
		var blocked := not world.is_walkable(t.cell)
		for u in units_near(t.center_loc(), 1.5):
			if u.dead or u.inside_firm:
				continue
			if u.cell() != t.cell and not (blocked and maxi(absi(u.cell().x - t.cell.x), absi(u.cell().y - t.cell.y)) <= 1):
				continue
			if _take(t, u):
				break
	if day % 5 == 0 and frame % Defs.FRAMES_PER_DAY == 0:
		for t in treasures.duplicate():
			if is_instance_valid(t):
				_ai_get_site_object(t)


## Site::ai_get_site_object (every 5 days): the computer's fighters near an
## item, gold, a scroll (of their race) or plans on the ground go for it - the
## nearest five, from 10 cells away at first to 30 after three years.
const MAX_NOTIFY_GET_RANGE := 30
const MAX_UNIT_TO_ORDER := 5


func _ai_get_site_object(t: Treasure) -> void:
	var rng_cells := mini(MAX_NOTIFY_GET_RANGE, 10 + day / 60)
	var cands: Array = []
	for u in units_near(t.center_loc(), float(rng_cells)):
		if u.dead or u.inside_firm != null or u.race == "" or u.is_civilian() or u.is_weapon or u.is_caravan:
			continue
		if u.item_id != 0 or u.ai_action_id > 0:
			continue
		var n: Nation = u.nation()
		if n == null or n.ai == null or u.nation_id == player_id:
			continue
		if t.kind == Treasure.Kind.SCROLL and u.race != t.race():
			continue
		if t.kind == Treasure.Kind.ITEM and not Items.can_pick(u):
			continue
		if u.attacking or u.order == Unit.Order.ATTACK:
			continue
		cands.append(u)
	cands.sort_custom(func(a, b): return a.center_loc().distance_to(t.center_loc()) < b.center_loc().distance_to(t.center_loc()))
	var ordered := 0
	for u in cands:
		u.order_move(t.cell)
		if maxi(absi(u.cell().x - t.cell.x), absi(u.cell().y - t.cell.y)) <= 1:
			return              # one standing next to it will do
		ordered += 1
		if ordered >= MAX_UNIT_TO_ORDER:
			return


func _take(t: Treasure, u: Unit) -> bool:
	var n := nation(u.nation_id)
	if n == null:
		return false          # independents and wild Fryhtans leave treasure where it lies
	var what := ""
	match t.kind:
		Treasure.Kind.SCROLL:
			if u.race != t.race():
				return false
			n.known_gods[t.race()] = true
			what = "the %s Scroll of Power" % Defs.race_name(t.race())
		Treasure.Kind.GOLD:
			n.add_cash(float(t.object_id), "Treasure")
			if n.is_fryhtan:
				n.live_points += float(t.para)
			what = "a treasure of %d gold" % t.object_id
		Treasure.Kind.ITEM:
			if u.item_id != 0 or not Items.can_pick(u):
				return false
			u.item_id = t.object_id
			u.item_para = t.para
			n.items_acquired[t.object_id] = true
			what = Items.item_name(t.object_id)
		Treasure.Kind.BLUEPRINT:
			# the plans let the kingdom research the weapon at a Tower of Science
			var code := t.tech_code()
			if code != "":
				n.mega_plans[code] = true
			what = "the plans of the %s - it can now be researched at a Tower of Science" % t.tech_name()
	if t.recno > 0:
		taken_sites[t.recno] = n.id
	notify_nation(n.id, "%s has found %s." % [u.display_name(), what], t.center_loc())
	treasures.erase(t)
	t.queue_free()
	return true


## Unit::drop_item: a fallen unit's item lies where it fell.
func _drop_item(u: Unit) -> void:
	if u.item_id == 0:
		return
	var c := _free_treasure_cell(u.cell())
	if c.x >= 0:
		spawn_treasure(Treasure.Kind.ITEM, u.item_id, u.item_para, c)
	u.item_id = 0
	u.item_para = 0


## Unit::king_die: a fallen king drops one of his kingdom's Scrolls of Power.
func _drop_scroll(n: Nation, at: Vector2i) -> void:
	var known := n.known_gods.keys()
	if known.is_empty():
		return
	var race: String = known[rng.randi() % known.size()]
	var ri := Defs.races.map(func(r): return r["code"]).find(race)
	var c := _free_treasure_cell(at)
	if ri < 0 or c.x < 0:
		return
	n.known_gods.erase(race)
	spawn_treasure(Treasure.Kind.SCROLL, ri + 1, 0, c)


## Unit::die: a fallen king drops the plans of a mega weapon his kingdom holds.
func _drop_mega_plans(n: Nation, at: Vector2i) -> void:
	var techs := Assets.table("TECH")
	for code in Defs.MEGA_WEAPONS:
		if n.tech_level(code) <= 0:
			continue
		var row := -1
		for i in techs.size():
			if techs[i]["TECH"] == code:
				row = i + 1
				break
		var c := _free_treasure_cell(at)
		if row > 0 and c.x >= 0:
			n.tech.erase(code)
			n.mega_plans.erase(code)
			spawn_treasure(Treasure.Kind.BLUEPRINT, row, 0, c)
		return


func _free_treasure_cell(at: Vector2i) -> Vector2i:
	for r in 4:
		for y in range(at.y - r, at.y + r + 1):
			for x in range(at.x - r, at.x + r + 1):
				var c := Vector2i(x, y)
				if world.is_free(c) and not treasures.any(func(t): return t.cell == c):
					return c
	return Vector2i(-1, -1)


## ItemRes::next_day for every carried item; the Ring of Life heals.
func _items_next_day() -> void:
	for u in units:
		if u.item_id == 0 or u.dead:
			continue
		u.item_para = Items.next_day(u.item_id, u.item_para)
		if u.item_para < 0:
			u.item_id = 0
			u.item_para = 0
			continue
		var heal := u.item_ability(Items.Ability.RECOVERY)
		if heal > 0:
			u.hp = minf(u.max_hp, u.hp + heal * 2.0)


func remove_unit(u: Unit) -> void:
	units.erase(u)
	deselect(u)
	if is_instance_valid(u):
		u.queue_free()


## Nearest walkable cell to `c` that no other unit stands on.
## World::locate_space for a unit coming out of a building or town: the
## empty walkable cell nearest `from`, in rings around the place; the cell is
## counted as taken at once, so units let out together stand apart.
func exit_cell(rect: Rect2i, from: Vector2i) -> Vector2i:
	for r in range(1, 12):
		var best := Vector2i(-1, -1)
		var best_d := INF
		var outer := rect.grow(r)
		for y in range(outer.position.y, outer.end.y):
			for x in range(outer.position.x, outer.end.x):
				if x > outer.position.x and x < outer.end.x - 1 and y > outer.position.y and y < outer.end.y - 1:
					continue        # only the ring
				var p := Vector2i(x, y)
				if not world.is_walkable(p) or unit_cells.get(p, 0) > 0:
					continue
				var d := Vector2(p - from).length_squared()
				if d < best_d:
					best_d = d
					best = p
		if best.x >= 0:
			unit_cells[best] = unit_cells.get(best, 0) + 1
			return best
	return world.adjacent_to_rect(rect, from)


func free_unit_cell(c: Vector2i) -> Vector2i:
	for r in range(1, 4):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var p := c + Vector2i(dx, dy)
				if world.is_walkable(p) and unit_cells.get(p, 0) == 0:
					return p
	return c


func site_at_rect(r: Rect2i) -> Site:
	for s in sites:
		if s.footprint().intersects(r):
			return s
	return null


# ----------------------------------------------------------------- queries ---

func nation(id: int) -> Nation:
	if id >= 1 and id <= nations.size():
		return nations[id - 1]
	return null


func nation_ids() -> Array:
	return nations.filter(func(n): return n.alive).map(func(n): return n.id)


func player() -> Nation:
	return nation(player_id)


## Whether a and b fight. A disguised spy is judged by the colours it wears
## (Unit::nation_recno is the cloaked nation in the original); its own side
## always knows it.
func is_hostile(a: GameObj, b: GameObj) -> bool:
	if a == null or b == null:
		return false
	# Unit::can_attack_target: a disguised spy and his true side leave each
	# other alone unless he keeps up his cover (Spy::notify_cloaked_nation_flag);
	# keeping it, he is what he passes for
	if a.nation_id == b.nation_id:
		var cover := false
		for o in [a, b]:
			if o is Unit and o.is_spy and o.cloak_id != 0 and o.spy_notify:
				cover = true
		if not cover:
			return false
	if a.is_monster() or b.is_monster():
		return true
	var sa := a.seen_nation()
	var sb := b.seen_nation()
	if sa == sb:
		return false
	if sa == 0 or sb == 0:
		var indep := a if sa == 0 else b
		var other := b if indep == a else a
		if indep is Unit and (indep as Unit).rebel_id > 0:
			return Rebels.is_hostile_to(self, indep, other.seen_nation())
		if other is Unit and (other as Unit).rebel_id > 0:
			return false
		var town: Town = null
		if indep is Town:
			town = indep
		elif indep is Unit:
			town = (indep as Unit).home_town
		return town != null and is_instance_valid(town) and not town.dead and town.aggressors.has(other.seen_nation())
	var na := nation(sa)
	return na != null and na.is_hostile_to(sb)


## Nearest hostile unit (or, for Fryhtans, any human object) within `range`.
## Units outside buildings whose cell lies within `r` of `c` (a superset: callers
## still check the exact distance). Uses the grid built at the start of the frame.
func units_near(c: Vector2, r: float) -> Array:
	var out: Array = []
	var b0 := Vector2i(floori(c.x - r) >> GRID_SHIFT, floori(c.y - r) >> GRID_SHIFT)
	var b1 := Vector2i(floori(c.x + r) >> GRID_SHIFT, floori(c.y + r) >> GRID_SHIFT)
	for by in range(b0.y, b1.y + 1):
		for bx in range(b0.x, b1.x + 1):
			var l = unit_grid.get(Vector2i(bx, by))
			if l != null:
				out.append_array(l)
	# a unit freed since the grid was built this frame is left out
	return out.filter(func(u): return is_instance_valid(u))


func find_enemy_near(obj: GameObj, range: float) -> GameObj:
	var best: GameObj = null
	var best_d := range + 0.01
	var c := obj.center_loc()
	for u in units_near(c, range + 2.0):
		if u.dead or u.inside_firm or u == obj or u.has_meta("hidden") or not is_hostile(obj, u):
			continue
		if u.hidden_from(obj.nation_id):
			continue          # a camouflaged spy or Porcupine is not seen by other kingdoms
		var d := c.distance_to(u.center_loc())
		if d < best_d:
			best_d = d
			best = u
	return best


## Target for a Fryhtan raid: the nearest kingdom town or building.
## Independent villages are left alone, as lairs mostly guard their own land.
func find_raid_target(lair: Firm, range: float) -> GameObj:
	var best: GameObj = null
	var best_d := range
	var c := lair.center_loc()
	for t in towns:
		if t.dead or t.nation_id <= 0:
			continue
		var d := c.distance_to(t.center_loc())
		if d < best_d:
			best_d = d
			best = t
	for f in firms:
		if f.dead or f.nation_id <= 0 or f.nation_id == GameObj.MONSTER_NATION:
			continue
		var d := c.distance_to(f.center_loc())
		if d < best_d:
			best_d = d
			best = f
	return best


func is_loc_visible(c: Vector2i) -> bool:
	if reveal_all:
		return true
	if not world.inside(c):
		return false
	return fog[c.y * world.w + c.x] == 2


func is_loc_explored(c: Vector2i) -> bool:
	if reveal_all:
		return true
	if not world.inside(c):
		return false
	return fog[c.y * world.w + c.x] >= 1


func is_explored_rect(r: Rect2i) -> bool:
	return is_loc_explored(r.position) or is_loc_explored(r.end - Vector2i.ONE) or is_loc_explored(r.get_center())


## The topmost visible object under a screen-space point (world coordinates).
func object_at_screen(p: Vector2) -> GameObj:
	var best: GameObj = null
	var best_d := 26.0
	for u in units:
		if u.dead or u.inside_firm or not u.visible:
			continue
		var d := p.distance_to(u.position + Vector2(0, -6))
		if d < best_d:
			best_d = d
			best = u
	if best:
		return best
	var loc := Iso.to_loc(p)
	var c := Vector2i(floori(loc.x), floori(loc.y))
	var o := world.object_at(c)
	if o is GameObj and (o as GameObj).visible and is_loc_explored(c):
		return o
	return null


# ------------------------------------------------------------------- time ---

func _process(delta: float) -> void:
	# a network game runs on even after this player's end, in step with the others
	if world == null or paused or (over and not Net.active) or config.get("editor", false):
		return
	_accum += delta * speed * Defs.SIM_FPS
	var steps := 0
	while _accum >= 1.0 and steps < 12:
		if not Net.can_run_frame(frame + 1):
			_accum = minf(_accum, 2.0)
			break
		_accum -= 1.0
		steps += 1
		sim_frame()
	if steps >= 12:
		_accum = 0.0


var unit_cells := {}       # cell -> number of standing units, rebuilt every frame


func sim_frame() -> void:
	frame += 1
	unit_cells.clear()
	unit_grid.clear()
	for u in units:
		if not u.dead and u.inside_firm == null:
			var c := u.cell()
			unit_cells[c] = unit_cells.get(c, 0) + 1
			var b := Vector2i(c.x >> GRID_SHIFT, c.y >> GRID_SHIFT)
			if unit_grid.has(b):
				unit_grid[b].append(u)
			else:
				unit_grid[b] = [u]
	for u in units.duplicate():
		if is_instance_valid(u):
			u.sim_frame()
	for f in firms:
		f.sim_frame()
	for t in towns:
		t.town_shoot()
		if t.under_construction:
			t.process_construction()
	for z in war_points.keys():
		war_points[z] >>= 1
		if war_points[z] == 0:
			war_points.erase(z)
	if frame % FIRE_SCAN == 0 and not fires.is_empty():
		_process_fires()
	for b in bullets.duplicate():
		b.sim_frame()
		if b.done:
			bullets.erase(b)
			b.queue_free()
	for t in tornadoes.duplicate():
		t.sim_frame()
		if t.done:
			tornadoes.erase(t)
			t.queue_free()
	for e in effects_list.duplicate():
		e.sim_frame()
		if e.done:
			effects_list.erase(e)
			e.queue_free()
	if frame % 50 == 0 and not rubble.is_empty():
		var before := rubble.size()
		rubble = rubble.filter(func(r): return r[2] > frame)
		if rubble.size() != before:
			_ground_dirty = true
	if frame % 10 == 0 and not treasures.is_empty():
		_pick_up_treasures()
	if frame % Defs.FRAMES_PER_DAY == 0:
		next_day()
		Espionage.next_day(self)
	if frame % 5 == 0:
		_update_visibility()
	if frame % 3 == 0:
		for t in towns:
			if t.nation_id > 0 and t.visible:
				t.queue_redraw()
	if _ground_dirty:
		_ground_dirty = false
		ground_layer.queue_redraw()


func next_day() -> void:
	day += 1
	if not contacts_ready:
		_init_contacts()
	_plant_ops()
	weather.next_day(rng)
	if weather.is_lightning() and rng.randf() < 0.35:
		_lightning_strike()
	_update_workers()
	for t in towns.duplicate():
		t.next_day(day)
		if t.jobless() == 0 and day % 30 == t.obj_id % 30:
			_even_out_workers(t)
	for f in firms.duplicate():
		f.next_day(day)
	# Unit::next_day: loyalty monthly, betrayal every 15 days
	for u in units.duplicate():
		if u.dead or u.nation_id <= 0 or u.nation_id == GameObj.MONSTER_NATION:
			continue
		if u.inside_firm == null and day % 30 == u.obj_id % 30:
			Espionage.update_unit_loyalty(u)
		if day % 15 == u.obj_id % 15:
			Espionage.think_betray(self, u)
		if u.auto_retreat > 0 or u.auto_reward > 0 or (u.nation() != null and u.nation().ai != null and u.nation_id != player_id):
			u.auto_orders()
	_pay_units()
	if day % 15 == 0:
		Economy.distribute_demand(self)
	if day % 30 == 0:
		Economy.next_month(self)
	for n in nations:
		if not n.alive:
			continue
		if n.food < 0 and day % 30 == 0 and n.is_player:
			notify("Your people are starving! Build up food by keeping villagers unemployed or researching farming.", Vector2(-1, -1))
		# Nation::next_day: while looking for a successor, a point of
		# everyone's loyalty is lost every 3 days
		if n.had_king() and (n.king == null or not is_instance_valid(n.king) or n.king.dead) and day % 3 == n.id % 3:
			change_all_people_loyalty(n, -1.0)
		if n.ai:
			n.ai.next_day(day)
		if day % 365 == 0:
			n.new_year()
	if campaign_battle != null:
		campaign_battle.next_day()
	RandomEvents.next_day(self)
	HeroRes.think_generate_hero(self)
	_quake_next_day()
	_natural_tornado()
	Rebels.next_day(self)
	Independents.next_day(self)
	for u in units:
		if not u.dead and (u.is_hero or u.combat > 200.0):
			u.think_special_ability()
	_check_homeless()
	_items_next_day()
	if day % 5 == 0:
		_check_end()
	_check_goals()
	_update_fog()


## Unit::pay_expense, FirmCamp::pay_expense / consume_food, Spy::pay_expense:
## soldiers out in the field earn 10 a year and generals 50 (the king nothing),
## and every human eats a unit of food a year; with no food their loyalty
## falls a point every 5 days. Men in forts and camps eat there and are not
## paid, but their commander is. War machines and caravans cost their yearly
## upkeep; a war machine that cannot be paid falls apart. A spy costs 100 a
## year and eats at home, but not while he lives at the enemy's.
const SOLDIER_YEAR_SALARY := 10.0
const GENERAL_YEAR_SALARY := 50.0
const SPY_YEAR_SALARY := 100.0
const NO_FOOD_LOYALTY_DECREASE_INTERVAL := 5


func _pay_units() -> void:
	for u in units.duplicate():
		if u.dead or u.nation_id <= 0 or u.nation_id == GameObj.MONSTER_NATION:
			continue
		var n := nation(u.nation_id)
		if n == null or n.is_fryhtan and not u.is_human():
			continue
		if u.is_spy:
			if n.cash > 0.0:
				n.add_cash(-SPY_YEAR_SALARY / 365.0, "Spies")
			else:
				u.loyalty = maxf(0.0, u.loyalty - 1.0)
			var abroad: bool = u.spy_place != null and is_instance_valid(u.spy_place) and u.spy_place.nation_id != u.nation_id
			if not abroad:
				_feed(n, u)
			continue
		if u.is_human():
			if u.rank == Defs.Rank.KING:
				continue
			var overseer: bool = u.inside_firm != null and u.inside_firm.overseer == u
			if u.inside_firm == null or overseer:
				if n.cash > 0.0:
					if u.rank == Defs.Rank.GENERAL:
						n.add_cash(-GENERAL_YEAR_SALARY / 365.0, "Generals")
					elif u.rank == Defs.Rank.SOLDIER:
						n.add_cash(-SOLDIER_YEAR_SALARY / 365.0, "Units")
			_feed(n, u)
			continue
		if u.is_monster():
			continue
		var cost := float(u.utype.get("year_cost", 0)) / 365.0
		if cost <= 0.0:
			continue
		if n.cash > 0.0:
			n.add_cash(-cost, "Caravans" if u.is_caravan else "Weapons")
		elif not u.is_caravan:
			# Even unpaid caravans stay in service; a war machine wears out
			u.hp -= 1.0
			if u.hp <= 0.0:
				u.hp = 0.0
				if u.inside_firm:
					kill_inside(u.inside_firm, u)
				else:
					u.die(null)


func _feed(n: Nation, u: Unit) -> void:
	if n.food > 0.0:
		n.food -= float(Defs.UNIT_FOOD_YEAR_CONSUMPTION) / 365.0
	elif day % NO_FOOD_LOYALTY_DECREASE_INTERVAL == 0:
		u.loyalty = maxf(0.0, u.loyalty - 1.0)


# -------------------------------------------------------- network play ---

func set_speed(s: float) -> void:
	paused = false
	speed = s


func set_paused(p: bool) -> void:
	paused = p


## The object a network command names by its id.
func find_obj(id: int) -> GameObj:
	for u in units:
		if u.obj_id == id:
			return u
	for f in firms:
		if f.obj_id == id:
			return f
	for t in towns:
		if t.obj_id == id:
			return t
	return null


## A checksum of the simulation, compared between the machines of a network game.
func state_hash() -> int:
	var h := hash([frame, rng.state, units.size(), firms.size(), towns.size()])
	var acc := 0
	for u in units:
		acc = (acc * 31 + int(u.loc.x * 64.0) * 7 + int(u.loc.y * 64.0) * 13 + int(u.hp * 16.0)) % 2147483647
	for t in towns:
		acc = (acc * 31 + t.population * 5 + int(t.loyalty * 16.0)) % 2147483647
	for n in nations:
		acc = (acc * 31 + int(n.cash) + int(n.live_points) * 3) % 2147483647
	return hash([h, acc])


## A player has left a network game: the computer takes over the kingdom.
func mp_drop_player(nid: int) -> void:
	var n := nation(nid)
	if n == null or n.is_ai:
		return
	n.is_ai = true
	n.ai = FryhtanAI.new(n, self) if n.is_fryhtan else NationAI.new(n, self)
	notify("The computer takes over the %s." % n.name, Vector2(-1, -1))


## The player puts up a building: it costs gold (and life points for Fryhtans)
## and the nearest of the chosen units goes to build it.
func cmd_place_building(nid: int, code: String, race: String, pos: Vector2i, builder: Unit, cost: float, live: float, species: String) -> void:
	var n := nation(nid)
	if n == null or n.cash < cost or n.live_points < live:
		return
	var b := Assets.firm_build(code, race)
	if not can_build_firm(code, pos, b.get("loc_w", 3), b.get("loc_h", 3)):
		return
	if builder and is_instance_valid(builder) and not Defs.unit_can_build(builder, code):
		return
	var plan := {"code": code, "race": race, "pos": [pos.x, pos.y], "cost": cost, "live": live, "species": species}
	if builder and is_instance_valid(builder) and not builder.dead:
		# Unit::build_firm: the builder goes there; the site is laid out and
		# paid for only when he arrives (Unit::execute_build_firm)
		builder.order_build_site(plan)
		return
	build_firm_now(nid, plan, null)


## FirmArray::build_firm, when the builder has reached the place: the ground
## must still be free and the treasury able to pay.
func build_firm_now(nid: int, plan: Dictionary, builder: Unit) -> Firm:
	var n := nation(nid)
	var code: String = plan["code"]
	var pos := Vector2i(int(plan["pos"][0]), int(plan["pos"][1]))
	var cost := float(plan["cost"])
	var live := float(plan["live"])
	var b := Assets.firm_build(code, plan["race"])
	if n == null or not can_build_firm(code, pos, b.get("loc_w", 3), b.get("loc_h", 3)):
		notify_nation(nid, "The %s cannot be built there any more." % Defs.firm_types.get(code, {}).get("name", code), Vector2(pos), true)
		return null
	if n.cash < cost or n.live_points < live:
		notify_nation(nid, "Not enough %s to build the %s." % ["life points" if n.live_points < live else "gold", Defs.firm_types.get(code, {}).get("name", code)], Vector2(pos), true)
		return null
	var f := spawn_firm(code, nid, plan["race"], pos, false)
	if f == null:
		return null
	n.add_cash(-cost, "Construction")
	n.live_points -= live
	if code == "LAIR":
		f.monster_code = plan["species"]
	if builder and is_instance_valid(builder) and not builder.dead:
		builder.order_build(f)
	return f


## Month of the year, 1-12, as date_string counts it.
func month() -> int:
	return mini(11, (day % 365) / 31) + 1


## Whether a kingdom has a town of this race (TechInfo::can_research for race techs).
func nation_has_race_town(nid: int, r: String) -> bool:
	for t in towns:
		if t.nation_id == nid and t.race == r and not t.dead:
			return true
	return false


func date_string() -> String:
	var y := year0 + day / 365
	var doy := day % 365
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	var m := mini(11, doy / 31)
	return "%d %s %d" % [doy - m * 31 + 1 if doy - m * 31 + 1 <= 31 else 31, months[m], y]


# ------------------------------------------------------------------ links ---

static func _center_dist(a: Vector2, b: Vector2) -> float:
	return maxf(absf(a.x - b.x), absf(a.y - b.y))


func update_links() -> void:
	for t in towns:
		t.linked_firms.clear()
	for f in firms:
		f.linked_towns.clear()
		f.linked_firms.clear()
	# Firm::setup_link: by World::effective_distance; buildings of one kingdom
	# only (a lair may link to a wild lair); an independent village links to
	# work places, markets and camps, a kingdom's town to its own buildings and
	# to other kingdoms' camps, forts and lairs
	for f in firms:
		if f.dead:
			continue
		var fc := f.center_loc()
		var camp: bool = f.code in ["CAMP", "FORT", "LAIR"]
		var town_reach := Defs.effective_distance(f.code, "")
		for t in towns:
			if t.dead:
				continue
			if t.nation_id == 0:
				if not (f.is_work_firm() or f.code == "MARKET" or camp):
					continue
			elif t.nation_id != f.nation_id and not camp:
				continue
			if not Defs.firm_links_town(f.code, f.race, t.race):
				continue
			if _center_dist(fc, t.center_loc()) <= town_reach:
				f.linked_towns.append(t)
				t.linked_firms.append(f)
		for g in firms:
			if g == f or g.dead:
				continue
			if g.nation_id != f.nation_id and not (f.code == "LAIR" and g.code == "LAIR"):
				continue
			if not Defs.firms_linkable(f.code, g.code):
				continue
			if f.code == "LAIR" and g.code == "LAIR" and not ((f.nation_id == 0) != (g.nation_id == 0)):
				continue       # FirmRes::is_linkable_to_firm: a kingdom's lair to a wild one only
			if _center_dist(fc, g.center_loc()) <= Defs.effective_distance(g.code, f.code):
				f.linked_firms.append(g)


# ------------------------------------------------------------- links ---
# Every link between a building and a town or another building can be switched
# off at either end (linked_firm_enable_array / linked_town_enable_array: a link
# works only when both ends have it on). link_state["a:b"] (a < b, object ids)
# = [a's end on, b's end on].

const INDEPENDENT_LINK_RESISTANCE := 50
var link_state := {}


func _link_key(x: GameObj, y: GameObj) -> Array:
	return ["%d:%d" % [mini(x.obj_id, y.obj_id), maxi(x.obj_id, y.obj_id)], x.obj_id < y.obj_id]


## Whether x's end of the link with y is on.
func link_side(x: GameObj, y: GameObj) -> bool:
	var k := _link_key(x, y)
	var st: Array = link_state.get(k[0], _default_link(x, y) if k[1] else _default_link(y, x))
	return st[0] if k[1] else st[1]


## A link line: a working link solid and bright, one switched off dashed
## and dim, so the two are told apart at a glance.
static func draw_link(cv, from: Vector2, to: Vector2, col: Color, on: bool) -> void:
	if on:
		cv.draw_line(from, to, col, 2.0)
		return
	var dim := Color(col.r * 0.6, col.g * 0.6, col.b * 0.6, 0.6)
	draw_dashes(cv, from, to, dim, 1.5, 6.0)
	var mid := (from + to) * 0.5
	cv.draw_line(mid + Vector2(-4, -4), mid + Vector2(4, 4), Color(1, 0.3, 0.3, 0.8), 2.0)
	cv.draw_line(mid + Vector2(-4, 4), mid + Vector2(4, -4), Color(1, 0.3, 0.3, 0.8), 2.0)


## A dashed line out of plain segments (the 3D view's recorder knows only lines).
static func draw_dashes(cv, from: Vector2, to: Vector2, col: Color, width: float, dash: float) -> void:
	var len := from.distance_to(to)
	if len <= 0.0:
		return
	var d := (to - from) / len
	var t := 0.0
	while t < len:
		cv.draw_line(from + d * t, from + d * minf(len, t + dash), col, width)
		t += dash * 2.0


func link_on(x: GameObj, y: GameObj) -> bool:
	return link_side(x, y) and link_side(y, x)


## Firm::toggle_firm_link / toggle_town_link: x switches its end; between
## objects of one kingdom (or `both`), both ends.
func set_link(x: GameObj, y: GameObj, on: bool, both := false) -> void:
	var k := _link_key(x, y)
	var st: Array = (link_state.get(k[0], _default_link(x, y) if k[1] else _default_link(y, x))).duplicate()
	var both_ends := both or x.nation_id == y.nation_id
	if k[1] or both_ends:
		st[0] = on
	if not k[1] or both_ends:
		st[1] = on
	link_state[k[0]] = st


## Firm::setup_link: the ends' default state, [first, second] in id order.
func _default_link(a: GameObj, b: GameObj) -> Array:
	var f: Firm = a if a is Firm else b
	var other: GameObj = b if a is Firm else a
	var fon := true
	var oon := true
	if other is Town:
		# an independent town only joins a foreign building's link when its
		# resistance to that kingdom is low
		if other.nation_id == 0 and (f.nation_id <= 0 or other.resistance_to(f.nation_id) > INDEPENDENT_LINK_RESISTANCE):
			oon = false
	elif other is Firm:
		var on := f.nation_id == other.nation_id and _default_firm_link(f.code, other.code)
		fon = on
		oon = on
	return [fon, oon] if a == f else [oon, fon]


## FirmInfo::default_firm_link_status: mines do not feed markets unless told to.
static func _default_firm_link(a: String, b: String) -> bool:
	if a == "MINE":
		return b != "MARKET"
	if a == "MARKET":
		return b == "FACTORY"
	if a == "FACTORY":
		return b == "MARKET" or b == "MINE"
	return true


## Whether a building may employ the people of a town (Firm::setup_link's
## rules for work places): its own kingdom's, or an independent one over a
## link both ends have on; a Seat of Power only its own race.
func work_link_on(f: Firm, t: Town) -> bool:
	if t.nation_id != 0 and t.nation_id != f.nation_id:
		return false
	if f.code == "BASE" and t.race != f.race:
		return false
	return link_on(f, t)


## FirmInfo::is_linkable_to_firm: the trade links of mines, factories and markets.
static func goods_linkable(a: String, b: String) -> bool:
	var trade := ["MINE", "FACTORY", "MARKET"]
	return a in trade and b in trade and a != b


## Daily: towns count their workers; a town that has lost people takes some
## back from the buildings (Town::unjob_town_people); workers whose town has
## gone are lost.
func _update_workers() -> void:
	for t in towns:
		t.employed = 0
	for f in firms:
		for i in range(f.worker_towns.size() - 1, -1, -1):
			var t = f.worker_towns[i]
			if not is_instance_valid(t) or t.dead or f.dead:
				f.worker_towns.remove_at(i)
			else:
				t.employed += 1
	for t in towns:
		while t.employed > t.population and t.employed > 0:
			_unjob(t)


## Town::unjob_town_people: the worker most likely to quit is in a distant,
## well-staffed or idle building.
func _unjob(t: Town) -> void:
	var best: Firm = null
	var best_r := -1
	for f in t.linked_firms + firms.filter(func(x): return t in x.worker_towns):
		var idx: int = f.worker_towns.find(t)
		if idx < 0:
			continue
		var r := 100 - int(t.center_loc().distance_to(f.center_loc()))
		r += f.workers() + 10 + 100 * f.workers() / maxi(1, f.needed_workers)
		if f.productivity() <= 0.0:
			r += 100
		if r > best_r:
			best_r = r
			best = f
	if best == null:
		t.employed = mini(t.employed, t.population)
		return
	best.resign_worker(best.worker_towns.find(t))


## Town::evenly_distribute_worker: with no jobless left, a worker moves from a
## building above the town's average employment to one below it.
func _even_out_workers(t: Town) -> void:
	if t.jobless() > 0:
		return
	var wf: Array = t.linked_firms.filter(func(f): return f.is_work_firm() and f.needed_workers > 0 and not f.dead and work_link_on(f, t))
	if wf.is_empty():
		return
	var total := 0
	for f in wf:
		total += 100 * f.workers() / f.needed_workers
	var avg := total / wf.size()
	for f in wf:
		if 100 * f.workers() / f.needed_workers >= avg or f.workers() >= f.needed_workers:
			continue
		for o in wf:
			if o == f or 100 * o.workers() / o.needed_workers <= avg:
				continue
			var k: int = o.worker_towns.find(t)
			if k < 0:
				continue
			if 100 * (o.workers() - 1) / o.needed_workers >= avg or f.needed_workers < o.needed_workers:
				o.worker_towns.remove_at(k)
				f.worker_towns.append(t)
				return


# ------------------------------------------------------------------- fog ---

func _update_fog() -> void:
	if reveal_all:
		fog.fill(2)
		fog_view.update_from(fog)
		return
	for i in fog.size():
		if fog[i] == 2 and fog_of_war:
			fog[i] = 1
	for u in units:
		if u.nation_id == player_id and not u.dead and not u.inside_firm:
			_reveal(u.cell(), int(u.utype.get("vis", 6)) + 1 + u.item_ability(Items.Ability.SCOUT_RANGE))
	for f in firms:
		if f.nation_id == player_id and not f.dead:
			_reveal(Vector2i(f.center_loc()), Defs.EXPLORE_RANGE)
	for t in towns:
		if t.nation_id == player_id and not t.dead:
			_reveal(Vector2i(t.center_loc()), Defs.EXPLORE_RANGE)
	fog_view.update_from(fog)
	_ground_dirty = true
	_explore_contacts()


func _reveal(c: Vector2i, r: int) -> void:
	var r2 := r * r
	for y in range(maxi(0, c.y - r), mini(world.h, c.y + r + 1)):
		for x in range(maxi(0, c.x - r), mini(world.w, c.x + r + 1)):
			var dx := x - c.x
			var dy := y - c.y
			if dx * dx + dy * dy <= r2:
				fog[y * world.w + x] = 2


func _update_visibility() -> void:
	for u in units:
		if u.inside_firm:
			continue
		if u.has_meta("hidden"):
			u.visible = false
			continue
		u.visible = u.nation_id == player_id or ((reveal_all or is_loc_visible(u.cell())) and (not u.hidden_from(player_id) or observer()))
	for f in firms:
		f.visible = f.nation_id == player_id or (is_explored_rect(f.footprint()) and (not f.hidden_from(player_id) or observer()))
	for t in towns:
		t.visible = t.nation_id == player_id or is_explored_rect(t.footprint())
	for c in _plants:
		var p: Plant = _plants[c]
		p.visible = is_loc_explored(c)
	for tr in treasures:
		tr.visible = is_loc_explored(tr.cell)
	if frame % 20 == 0:
		for rk in rocks:
			if rk.tex:
				rk.visible = is_explored_rect(rk.footprint())


# ---------------------------------------------------------------- events ---

func play_sound(kind: String, code: String, action: String, loc: Vector2) -> void:
	sound_event.emit(kind, code, action, Iso.to_screen(loc))


## A news message. `minor` news (News::is_major false: buildings and towns
## attacked, lost or taken, idle buildings, Fryhtan lairs and gold, tornados,
## migrations) is only shown when the Display News option is "All news".
var last_message_minor := false
var hovered: GameObj = null          # the object under the mouse (display only)
var hide_buildings := false          # Hide Buildings: squares and names instead of buildings


## World::set_power: each town and building claims the land within
## EFFECTIVE_POWER_DISTANCE of it, in a diamond, first come first served.
## Returns nation id per cell (0 none), for the political map's zones.
const EFFECTIVE_POWER_DISTANCE := 3


func power_map() -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(world.w * world.h)
	var claim := func(x1: int, y1: int, x2: int, y2: int, nid: int):
		var ax1 := maxi(0, x1 - EFFECTIVE_POWER_DISTANCE + 1)
		var ay1 := maxi(0, y1 - EFFECTIVE_POWER_DISTANCE + 1)
		var ax2 := mini(world.w - 1, x2 + EFFECTIVE_POWER_DISTANCE - 1)
		var ay2 := mini(world.h - 1, y2 + EFFECTIVE_POWER_DISTANCE - 1)
		var cy := (ay1 + ay2) / 2
		for y in range(ay1, ay2 + 1):
			var t := absi(y - cy) / 2
			for x in range(ax1 + t, ax2 - t + 1):
				if out[y * world.w + x] == 0:
					out[y * world.w + x] = nid
	for t in towns:
		if t.nation_id > 0 and t.nation_id < 255 and not t.dead:
			claim.call(t.x1, t.y1, t.x1 + Defs.TOWN_SIZE - 1, t.y1 + Defs.TOWN_SIZE - 1, t.nation_id)
	for f in firms:
		if f.nation_id > 0 and f.nation_id < 255 and not f.dead and not f.under_construction:
			claim.call(f.x1, f.y1, f.x1 + f.w - 1, f.y1 + f.h - 1, f.nation_id)
	return out


func notify(text: String, loc: Vector2, minor := false) -> void:
	last_message_minor = minor
	message.emit(text, loc)
	last_message_minor = false


## True when nobody plays: every kingdom is AI-controlled and the human watches.
func observer() -> bool:
	return config.get("autoplay", false)


func notify_nation(nid: int, text: String, loc: Vector2, minor := false) -> void:
	if nid == player_id and not observer():
		notify(text, loc, minor)


## The tutorial's computer side stays idle (FirmTrain::basic_train in GAME_TUTORIAL).
func tutorial_ai_idle(nid: int) -> bool:
	return config.has("tutorial") and nid != player_id


func select_only(o: GameObj) -> void:
	for x in selected:
		if is_instance_valid(x):
			x.selected = false
			x.queue_redraw()
	selected = [o]
	o.selected = true
	o.queue_redraw()
	if o is Town:
		for t in (o as Town).linked_towns():
			t.queue_redraw()       # their migrate icons


func deselect(o: GameObj) -> void:
	if o in selected:
		selected.erase(o)
		o.selected = false
		o.queue_redraw()
		if o is Town:
			for t in (o as Town).linked_towns():
				t.queue_redraw()


## BaseObj::calc_live_points_bonus: a person is worth his hit points, a
## Fryhtan half of them, a Lishorr half its strength; the worth doubles every
## five years (up to five times).
func live_points_bonus(o: GameObj) -> float:
	var v := 0.0
	if o is Unit:
		if o.is_human():
			v = o.max_hp
		elif o.is_monster() or SpecialFirms.is_fryhtan_unit(o):
			v = o.max_hp / 2.0
	elif o is Firm and o.code == "LISHORR":
		v = o.max_hp / 2.0
	var inc := minf(4.0, float(day) / (365.0 * 5.0))
	return v + v * inc


## BaseObj::being_killed: half for a killer who is not a Fryhtan himself.
func _gain_live_points(killer: GameObj, victim: GameObj) -> void:
	var kn := nation(killer.nation_id)
	if kn == null or not kn.is_fryhtan:
		return
	var v := live_points_bonus(victim)
	if not (killer is Unit and (killer.is_monster() or SpecialFirms.is_fryhtan_unit(killer))):
		v /= 2.0
	kn.live_points += v


## Unit::being_killed_leave_money: a king is worth 2000 x (leadership +
## combat/2) / 150, a general 600, a soldier 300, a villager 20; give or take
## a fifth by the unit.
func _kill_money(u: Unit, killer: GameObj) -> void:
	if killer.nation_id <= 0 or killer.nation_id == GameObj.MONSTER_NATION or killer.nation_id == u.nation_id:
		return
	if u.sprite_code == "EXPCART" and u.hp <= 0.0 and killer == u:
		return
	var kn := nation(killer.nation_id)
	if kn == null:
		return
	var worth := int(u.lead_skill()) + int(u.combat) / 2
	var money := 0
	match u.rank:
		Defs.Rank.KING:
			money = 2000 * worth / 150
		Defs.Rank.GENERAL:
			money = 600 * worth / 150
		_:
			money = 20 if u.is_civilian() else 300 * worth / 150
	money = money * (80 + u.obj_id % 40) / 100
	if money > 0:
		kn.add_cash(float(money), "Treasure")


## Unit::being_killed_subordinate_betray: with their general fallen, up to
## three of his men nearby may go over to the victor - the more so hurt,
## disloyal and outnumbered - or to the strongest kingdom about.
func _subordinates_betray(gen: Unit, killer: GameObj) -> void:
	if killer.nation_id <= 0 or killer.nation_id == GameObj.MONSTER_NATION:
		return
	var c := gen.center_loc()
	var net := net_attacker_power(c, killer.nation_id, gen.nation_id, Defs.EFFECTIVE_LEADING_DISTANCE)
	var counts := {}
	for o in units_near(c, Defs.EFFECTIVE_LEADING_DISTANCE):
		if not o.dead and o.nation_id > 0 and o.nation_id != GameObj.MONSTER_NATION and o.inside_firm == null:
			counts[o.nation_id] = int(counts.get(o.nation_id, 0)) + 1
	var most := killer.nation_id
	var best := -1
	for k in counts:
		if int(counts[k]) > best:
			best = int(counts[k])
			most = int(k)
	var allow := 1 + rng.randi() % 3
	for m in units.duplicate():
		if m.dead or m == gen or m.leader != gen or m.inside_firm != null or m.race == "" or not m.has_loyalty():
			continue
		if maxf(absf(m.center_loc().x - c.x), absf(m.center_loc().y - c.y)) > Defs.EFFECTIVE_LEADING_DISTANCE:
			continue
		var chance := 50 + int(net) / 20 - 50 * int(m.hp) / maxi(1, int(m.max_hp)) - int(m.loyalty) / 2
		if rng.randi() % 100 < chance:
			Espionage.betray(self, m, killer.nation_id)
			allow -= 1
			if allow == 0:
				return
		elif most != killer.nation_id and most != m.nation_id:
			chance = 40 - 50 * int(m.hp) / maxi(1, int(m.max_hp)) - int(m.loyalty) / 2
			if rng.randi() % 100 < chance:
				Espionage.betray(self, m, most)


func on_unit_died(u: Unit, killer: GameObj) -> void:
	deselect(u)
	if u.home_town and is_instance_valid(u.home_town):
		u.home_town.defender_killed(u, killer)
		u.home_town._check_empty()
	var victim_nation := nation(u.nation_id)
	if killer and is_instance_valid(killer) and killer.nation_id > 0 and killer.nation_id != u.nation_id and (u.is_monster() or (victim_nation and victim_nation.is_fryhtan)):
		var kn := nation(killer.nation_id)
		if kn and not kn.is_fryhtan:
			if u.is_monster():
				kn.change_reputation(0.2)
			kn.kill_monster_score += [1.0, 5.0, 20.0][clampi(u.rank, 0, 2)]
			# a Fryhtan All-high slain may bring a wandering hero to the victor
			if u.rank == Defs.Rank.KING:
				HeroRes.induce_hero_join_nation(self, kn.id, (int(u.lead_skill()) + int(u.combat) / 2) / 2)
	if killer and is_instance_valid(killer):
		# BaseObj::being_killed: a Fryhtan kingdom absorbs the life of what it kills
		_gain_live_points(killer, u)
		# Unit::being_killed_leave_money: the victor takes the fallen's money
		_kill_money(u, killer)
		# Unit::being_killed_subordinate_betray
		if u.rank >= Defs.Rank.GENERAL:
			_subordinates_betray(u, killer)
	_drop_item(u)
	var n := nation(u.nation_id)
	if n and n.king == u:
		# the throne stays empty until a successor is chosen (the player's
		# Succeed King button, the computer's think_succeed_king)
		if n.king_leadership == 0:
			n.king_leadership = maxi(1, int(u.lead_skill()))     # a first king's, set at the start
		n.king = null
		n.change_reputation(-10.0)
		_drop_scroll(n, u.cell())
		_drop_mega_plans(n, u.cell())
		if has_king_successor_candidate(n):
			notify_nation(n.id, "Your king has died! Select a soldier or general and press Succeed King to crown a successor. Until then your people lose loyalty.", u.center_loc())
		else:
			notify_nation(n.id, "Your king has died and there is no one to succeed him!", u.center_loc())
		if n.id != player_id or observer():
			notify("The king of the %s has fallen." % n.name, u.center_loc())


## NationBase::succeed_king: the chosen unit becomes king. Everyone's loyalty
## falls by a third of what the new king lacks in leadership (at least 20
## is assumed), and by 20 more unless he was a general; if he is of another
## race, his race gains 20 - and, as in the original, the old king's race
## gains 30 too (DIFFERENT_RACE_LOYALTY_DEC is added, not subtracted). The
## kingdom takes the new king's race.
func succeed_king(n: Nation, u: Unit) -> void:
	if u == null or u.dead or u.nation_id != n.id or not u.can_succeed_king():
		return
	if u.inside_firm:
		u.inside_firm.release_unit(u)
	var lead := maxi(20, int(u.lead_skill()))
	var change := 0
	if lead < n.king_leadership:
		change = (lead - n.king_leadership) / 3
	if u.rank != Defs.Rank.GENERAL:
		change -= 20
	var old_race := n.race
	var race_change := func(r: String) -> int:
		if u.race != old_race and not n.is_fryhtan:
			if r == u.race:
				return 20
			elif r == old_race:
				return 30
		return 0
	for m in units:
		if m == u or m.dead or m.nation_id != n.id or not m.is_human():
			continue
		m.loyalty = clampf(m.loyalty + change + race_change.call(m.race), 0.0, 100.0)
	for t in towns:
		if t.nation_id == n.id and not t.dead and t.population > 0:
			t.loyalty = clampf(t.loyalty + change + race_change.call(t.race), 0.0, 100.0)
	# Spy::think_become_king: a bribed man (secretly another kingdom's) on the
	# throne hands a computer kingdom over to his master when loyal enough to
	# him - the more so the weaker his new kingdom is - or else keeps it
	var master := u.sleeper_for
	if master > 0 and nation(master) != null and nation(master).alive:
		var accept := 90 + Diplomacy.overall_rank(self, n) - Diplomacy.overall_rank(self, nation(master))
		u.sleeper_for = 0
		if u.loyalty >= accept and n.ai != null and n.id != player_id:
			notify("%s, secretly in the service of the %s, takes the throne and hands the %s over." % [u.unit_name, nation(master).name, n.name], u.center_loc())
			Diplomacy.surrender(self, n.id, master)
			return
	u.rank = Defs.Rank.KING
	u.leader = null
	u.loyalty = 100.0
	n.king = u
	n.king_leadership = int(u.lead_skill())
	if not n.is_fryhtan:
		n.race = u.race
	notify_nation(n.id, "%s takes the throne." % u.unit_name, u.center_loc())
	if n.id != player_id or observer():
		notify("%s is the new ruler of the %s." % [u.unit_name, n.name], u.center_loc())


func cmd_succeed_king(nid: int, u: Unit) -> void:
	var n := nation(nid)
	if n and u and is_instance_valid(u):
		succeed_king(n, u)


## NationBase::has_king_successor_candidate
func has_king_successor_candidate(n: Nation) -> bool:
	return units.any(func(m): return m.nation_id == n.id and not m.dead and m.can_succeed_king())


## NationBase::change_all_people_loyalty
func change_all_people_loyalty(n: Nation, v: float) -> void:
	for m in units:
		if m.nation_id == n.id and not m.dead and m != n.king and m.is_human():
			m.loyalty = clampf(m.loyalty + v, 0.0, 100.0)
	for t in towns:
		if t.nation_id == n.id and not t.dead:
			t.loyalty = clampf(t.loyalty + v, 0.0, 100.0)


## NationBase::defeated: a kingdom with no king, nobody to succeed him and
## no surrender is gone - its people try to go over to another kingdom (else
## they leave), its buildings close down and its towns become independent.
func defeat_nation(n: Nation) -> void:
	if not n.alive:
		return
	for m in units.duplicate():
		if m.nation_id != n.id or m.dead:
			continue
		if m.inside_firm != null and m.inside_firm.overseer != m:
			continue
		m.loyalty = 0.0
		if m.is_human():
			Espionage.think_betray(self, m)
		if m.nation_id == n.id and not m.dead:
			if m.inside_firm:
				m.inside_firm.release_unit(m)
			remove_unit(m)
	for f in firms.duplicate():
		if f.nation_id == n.id and not f.dead:
			f.die(null)
	for t in towns.duplicate():
		if t.nation_id == n.id and not t.dead:
			t.surrender(0)
	n.alive = false
	last_del_nation_day = day
	notify("The %s is no more." % n.name, Vector2(-1, -1))


func _best_heir(n: Nation) -> Unit:
	var best: Unit = null
	for u in units:
		if u.dead or u.nation_id != n.id or not u.is_human():
			continue
		var score := u.leadership + (100.0 if u.rank == Defs.Rank.GENERAL else 0.0)
		if best == null or score > best.leadership + (100.0 if best.rank == Defs.Rank.GENERAL else 0.0):
			best = u
	return best


func on_firm_destroyed(f: Firm, killer: GameObj) -> void:
	deselect(f)
	if killer and is_instance_valid(killer) and not f.has_meta("sold"):
		_gain_live_points(killer, f)        # BaseObj::being_killed (a Lishorr)
	f.resign_all_workers()        # FirmWork::free_all_people: the workers go home
	if Training.is_train_firm(f):
		Training.free_all(f)
	f.eject_all()
	if f.builder and is_instance_valid(f.builder):
		f.builder.inside_firm = null
		f.builder.visible = true
		f.builder = null
	world.release(f.x1, f.y1, f.w, f.h)
	if f.site:
		f.site.mine = null
	if not f.under_construction and f.visible and not f.has_meta("sold"):
		spawn_effect(1, Vector2(f.x1, f.y1))
		# rubble sized to the building (FirmDie parts 6: 3x3, 5: 6x6, 4: others)
		var part := 6 if f.w <= 3 else (5 if f.w >= 6 else 4)
		var rr := Assets.die_part(part)
		if not rr.is_empty():
			var b := Assets.die_bitmap(rr[0])
			if not b.is_empty():
				rubble.append([b[0], Iso.to_screen(Vector2(f.x1, f.y1)) + b[1], frame + Defs.FRAMES_PER_DAY * 60])
		play_sound("F", f.code, "DIE", f.center_loc())
	firms.erase(f)
	if f.code == "LAIR" and killer and killer.nation_id > 0 and killer.nation_id != GameObj.MONSTER_NATION:
		var kn := nation(killer.nation_id)
		if kn:
			var treasure := float(rng.randi_range(500, 1500))
			kn.add_cash(treasure, "Treasure")
			kn.change_reputation(5.0)
			notify_nation(kn.id, "Fryhtan lair destroyed! Treasure found: %d gold." % int(treasure), f.center_loc(), true)
	elif observer() and f.nation_id > 0 and nation(f.nation_id):
		notify("The %s has lost a %s." % [nation(f.nation_id).name, f.display_name()], f.center_loc(), true)
	elif f.nation_id == player_id:
		notify("%s destroyed!" % f.display_name(), f.center_loc(), true)
	f.queue_free()
	update_links()
	_ground_dirty = true


func on_town_changed(t: Town, old_nation: int) -> void:
	# Town::set_nation_unjob_worker: a kingdom's people work only for it
	if t.nation_id != 0:
		for f in firms:
			if f.nation_id != t.nation_id:
				for i in range(f.worker_towns.size() - 1, -1, -1):
					if f.worker_towns[i] == t:
						f.resign_worker(i)
	if observer():
		var tn := nation(t.nation_id)
		notify("%s now belongs to the %s." % [t.town_name, tn.name] if tn else "%s has become independent." % t.town_name, t.center_loc(), true)
	elif t.nation_id == player_id:
		notify("%s has joined your kingdom!" % t.town_name, t.center_loc(), true)
	elif old_nation == player_id:
		notify("%s has been lost!" % t.town_name, t.center_loc(), true)
	var n := nation(t.nation_id)
	if n:
		n.change_reputation(1.0)
	# FirmCamp::think_linked_town_change_nation: a computer's camp trying to win
	# a village another kingdom has taken gives up, unless the village has no
	# protection
	if old_nation == 0 and t.nation_id > 0:
		for f in t.linked_firms:
			var fn := nation(f.nation_id)
			if fn and fn.ai is NationAI and f.nation_id != t.nation_id and Espionage.is_camp(f):
				if AITown.protection_available(t) > 0:
					f.should_close = true


func on_town_destroyed(t: Town) -> void:
	deselect(t)
	world.release(t.x1, t.y1, Defs.TOWN_SIZE, Defs.TOWN_SIZE)
	towns.erase(t)
	if t.nation_id == player_id or observer():
		notify("%s has been wiped out." % t.town_name, t.center_loc())
	t.queue_free()
	update_links()
	_ground_dirty = true


## A nation's object was attacked: declare war on neutral attackers and rally help.
func on_object_attacked(victim: GameObj, attacker: GameObj) -> void:
	if victim.nation_id > 0 and attacker.nation_id > 0 and victim.nation_id != GameObj.MONSTER_NATION and attacker.nation_id != GameObj.MONSTER_NATION:
		var an := nation(attacker.nation_id)
		if an and an.relation(victim.nation_id) != Defs.Relation.WAR:
			declare_war(attacker.nation_id, victim.nation_id)
	call_for_help(victim, attacker)
	if not (victim is Unit):
		invoke_camp_defense(victim, attacker)
	# the computer answers attacks on its places (Place::being_attack_hit) and leaders (Unit::ai_leader_being_attacked)
	var vn := nation(victim.nation_id) if victim.nation_id > 0 else null
	if vn and vn.ai is NationAI and attacker.nation_id != victim.nation_id and not victim.dead:
		if victim is Unit:
			if (victim.is_human() or SpecialFirms.is_fryhtan_unit(victim)) and victim.rank >= Defs.Rank.GENERAL:
				AIUnit.leader_attacked(vn.ai, victim, attacker)
		else:
			vn.ai.ai_defend(attacker)


## World::net_attacker_power_in_area: the power of the attacker's moving or
## attacking units within `r`, less the defender's.
func net_attacker_power(c: Vector2, attacker_nid: int, defender_nid: int, r: float) -> float:
	var net := 0.0
	for u in units_near(c, r):
		if u.dead or u.inside_firm != null or absf(u.center_loc().x - c.x) > r or absf(u.center_loc().y - c.y) > r:
			continue
		if u.order != Unit.Order.MOVE and u.order != Unit.Order.ATTACK:
			continue
		if u.nation_id == attacker_nid:
			net += u.obj_power()
		elif u.nation_id == defender_nid:
			net -= u.obj_power()
	return net


## Place::invoke_camp_defense: a town or building under attack calls the
## soldiers of its kingdom's forts and camps within EFFECTIVE_DEFEND_DISTANCE;
## each sends out men until their power is two and a half times the
## attackers' (FirmCamp::invoke_defense). A village paying tribute calls on
## the lair it pays.
var _defense_frame := {}


func invoke_camp_defense(victim: GameObj, attacker: GameObj) -> void:
	if attacker == null or not is_instance_valid(attacker) or attacker.dead:
		return
	if frame - int(_defense_frame.get(victim, -100)) < 20:
		return             # once in a while, not at every blow
	_defense_frame[victim] = frame
	var c := victim.center_loc()
	var camps: Array = []
	if victim.nation_id > 0 and victim.nation_id != GameObj.MONSTER_NATION:
		camps = firms.filter(func(f): return not f.dead and f.nation_id == victim.nation_id and Espionage.is_camp(f) \
			and f.center_loc().distance_to(c) <= Defs.EFFECTIVE_DEFEND_DISTANCE)
	elif victim is Town and victim.tribute_to() > 0:
		camps = firms.filter(func(f): return not f.dead and f.code == "LAIR" and f.nation_id == victim.tribute_to() \
			and f.center_loc().distance_to(c) <= Defs.EFFECTIVE_DEFEND_DISTANCE * 2.0)
	if camps.is_empty():
		return
	var need := net_attacker_power(c, attacker.nation_id, victim.nation_id if victim.nation_id > 0 else -1, Defs.EFFECTIVE_DEFEND_DISTANCE)
	if need <= 0.0:
		return
	for f in camps:
		if not f.defense_flag:
			continue        # FirmCamp::invoke_defense: only with the defense mode on
		var power := 0.0
		for s in f.soldiers.duplicate():
			if power > need * 2.5:
				break
			if s == f.overseer or s.hp < s.max_hp * 0.3:
				continue
			power += s.obj_power()
			f.release_unit(s, attacker)
			s.home_firm = f


func call_for_help(victim: GameObj, attacker: GameObj) -> void:
	if attacker == null or not is_instance_valid(attacker) or attacker.dead or victim.nation_id <= 0:
		return
	if frame % 4 != 0:
		return
	var c := victim.center_loc()
	for u in units:
		if u.nation_id != victim.nation_id or u.dead or u.inside_firm or not u.can_attack():
			continue
		var sieging := u.order == Unit.Order.ATTACK and u.target != null and is_instance_valid(u.target) and not (u.target is Unit)
		if u.order != Unit.Order.IDLE and not sieging:
			continue
		# Unit::ask_team_help: one standing its ground helps only within reach
		if u.get_behavior_mode() == Unit.Behavior.STAND_GROUND and u.distance_to(attacker) > u.max_attack_range():
			continue
		if u.center_loc().distance_to(c) <= 8.0 and is_hostile(u, attacker):
			var building: GameObj = u.target if sieging else null
			u.order_attack(attacker)
			u.resume_target = building


## Game::game_end(retireFlag): the player retires; the game is scored and
## may enter the Hall of Fame.
func retire() -> void:
	if over or player() == null or not player().alive:
		return
	over = true
	game_over.emit(false, "You have retired from the throne of the %s." % player().name)


func declare_war(a: int, b: int) -> void:
	var na := nation(a)
	var nb := nation(b)
	if na == null or nb == null or na.relation(b) == Defs.Relation.WAR:
		return
	if na.relation(b) >= Defs.Relation.PEACE:
		na.change_reputation(-15.0)     # breaking a treaty hurts reputation
	nb.war_count[a] = int(nb.war_count.get(a, 0)) + 1
	Diplomacy.set_status(self, a, b, Defs.Relation.WAR)
	if observer():
		notify("The %s has declared war on the %s." % [na.name, nb.name], Vector2(-1, -1))
	elif a == player_id:
		notify("You have declared war on the %s." % nb.name, Vector2(-1, -1))
	elif b == player_id:
		notify("The %s has declared war on you!" % na.name, Vector2(-1, -1))


## A diplomatic message (sim command): see Diplomacy.send.
func talk(from: int, to: int, id: String, p1 = 0, p2 = 0) -> void:
	Diplomacy.send(self, from, to, id, p1, p2)


## A human kingdom's answer to a message waiting for it (sim command).
func talk_reply(from: int, to: int, id: String, accept: bool) -> void:
	for m in talks:
		if m["from"] == from and m["to"] == to and m["id"] == id:
			Diplomacy.reply(self, m, accept)
			return


func make_peace(a: int, b: int) -> void:
	var na := nation(a)
	var nb := nation(b)
	if na == null or nb == null:
		return
	if peace_offers.has(a):
		peace_offers[a].erase(b)
	if peace_offers.has(b):
		peace_offers[b].erase(a)
	Diplomacy.set_status(self, a, b, Defs.Relation.PEACE)
	for u in units:
		if (u.nation_id == a or u.nation_id == b) and u.order == Unit.Order.ATTACK and u.target and (u.target.nation_id == a or u.target.nation_id == b):
			u.stop()
	if a == player_id or b == player_id or observer():
		notify("Peace treaty signed between the %s and the %s." % [na.name, nb.name], Vector2(-1, -1))


## The player's offer of peace: a computer kingdom answers at once; another
## player sees the offer in the Diplomacy window and may accept it.
func offer_peace(from: int, to: int) -> void:
	var nt := nation(to)
	if nt == null:
		return
	if nt.ai != null:
		if not propose_peace(from, to) and from == player_id:
			notify("The %s rejects your offer of peace." % nt.name, Vector2(-1, -1))
		return
	if not peace_offers.has(to):
		peace_offers[to] = {}
	peace_offers[to][from] = true
	if to == player_id:
		notify("The %s offers you peace. Accept it in the Diplomacy window." % nation(from).name, Vector2(-1, -1))
	elif from == player_id:
		notify("Your offer of peace has been sent to the %s." % nt.name, Vector2(-1, -1))


## Player diplomacy: the AI accepts peace when it is weaker or tired of war.
func propose_peace(from: int, to: int) -> bool:
	var nt := nation(to)
	if nt == null or nt.ai == null:
		return false
	if nt.ai.accepts_peace(from):
		make_peace(from, to)
		return true
	return false


func military_strength(nid: int) -> float:
	var s := 0.0
	for u in units:
		if u.nation_id == nid and not u.dead and u.can_attack():
			s += u.combat + u.max_hp * 0.2
	return s


## A kingdom that has lost all its towns and buildings and stays without them for
## 60 days surrenders: its remaining troops disband (NationBase::think_surrender /
## defeated()). Armies that start without a home (scenario invaders) are exempt
## until they win one; they live as long as they have units.
func _check_homeless() -> void:
	for n in nations:
		if not n.alive:
			continue
		var has_base := firms.any(func(f): return f.nation_id == n.id and not f.dead)
		if not has_base and not n.is_fryhtan:
			has_base = towns.any(func(t): return t.nation_id == n.id)
		if has_base:
			n.homeless_days = 0
			n.had_base = true
			continue
		if not n.had_base:
			continue
		n.homeless_days += 1
		if n.homeless_days < 60:
			continue
		for u in units.duplicate():
			if u.nation_id == n.id and not u.dead:
				remove_unit(u)
		n.alive = false
		last_del_nation_day = day
		notify("The %s has no strongholds left; its last troops have disbanded." % n.name, Vector2(-1, -1))


## Scenario goals, checked daily for the player (NationBase::check_win/check_lose).
func _check_goals() -> void:
	if goals == null or over or config.get("autoplay", false) or player() == null:
		return
	var dl := goals.deadline_day()
	if dl > 0 and (dl - day) % 365 == 0 and (dl - day) / 365 in [1, 2, 3, 4, 5]:
		notify("%d year%s left to achieve the scenario's goals." % [(dl - day) / 365, "" if dl - day == 365 else "s"], Vector2(-1, -1))
	var r := goals.check(self)
	if r != "":
		over = true
		game_over.emit(r == "won", goals.result_text)


func _check_end() -> void:
	if over:
		return
	for n in nations:
		if not n.alive:
			continue
		var has_any := false
		for t in towns:
			if t.nation_id == n.id:
				has_any = true
				break
		if not has_any:
			for f in firms:
				if f.nation_id == n.id:
					has_any = true
					break
		if not has_any:
			for u in units:
				if u.nation_id == n.id and not u.dead:
					has_any = true
					break
		if not has_any:
			n.alive = false
			last_del_nation_day = day
			if n.id != player_id:
				notify("The %s has been destroyed." % n.name, Vector2(-1, -1))
	if config.get("autoplay", false):
		# AI against AI: the game ends when one kingdom is left standing
		var alive := nations.filter(func(n): return n.alive)
		if alive.size() <= 1:
			over = true
			var winner: String = alive[0].name if alive.size() == 1 else "nobody"
			game_over.emit(true, "Victory goes to the %s." % winner if alive.size() == 1 else "Every kingdom has fallen.")
			last_winner = winner
		return
	var p := player()
	if not p.alive:
		over = true
		game_over.emit(false, "Your kingdom has fallen.")
		return
	var rivals := nations.filter(func(n): return n.id != player_id and n.alive)
	if rivals.is_empty() and goals == null:      # a scenario's own goals decide its end
		over = true
		game_over.emit(true, "All rival kingdoms have been vanquished. You rule the land!")
