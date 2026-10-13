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


func _init() -> void:
	inst = self


func _exit_tree() -> void:
	if inst == self:
		inst = null


# ------------------------------------------------------------------ setup ---

## cfg: {seed, size, race, ai_count, cash, indep_towns, lairs}
var config := {}
var last_winner := ""


func start(cfg: Dictionary) -> void:
	Defs.load_from_assets()
	config = cfg.duplicate()
	rng.seed = cfg.get("seed", randi())
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
	_create_nations(cfg)
	_generate_starts(size)
	_generate_sites(size)
	_generate_independents(size, cfg)
	_generate_lairs(size, cfg)
	_generate_items()
	_generate_rocks(size)
	_generate_trees(size)
	update_links()
	_update_fog()
	_ground_dirty = true


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
		var n := Nation.new(i + 1, race, Defs.NATION_COLORS[i % Defs.NATION_COLORS.size()], not human or cfg.get("autoplay", false))
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
		var n := Nation.new(nations.size() + 1, m["unit"], Defs.NATION_COLORS[nations.size() % Defs.NATION_COLORS.size()], true)
		n.is_fryhtan = true
		n.monster_code = m["unit"]
		n.name = "%s Fryhtans" % m["name"]
		n.cash = float(cfg.get("cash", 3000)) * 0.7
		n.food = 0.0
		n.live_points = 600.0
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
		var town := spawn_town(nat.race, nat.id, tpos, rng.randi_range(32, 42))
		town.loyalty = 70.0
		# Fort next to the town, commanded by the king.
		var fort_build := Assets.firm_build("FORT", nat.race)
		var fw: int = fort_build.get("loc_w", 6)
		var fpos := _place_near(Rect2i(tpos, Vector2i(6, 6)), fw, fort_build.get("loc_h", 6))
		var fort := spawn_firm("FORT", nat.id, nat.race, fpos, true)
		var king := spawn_unit(Defs.unit_sprite(nat.race, "INF"), nat.id, Vector2i(fpos.x, fpos.y + fw + 1), 60.0)
		king.rank = Defs.Rank.KING
		king.leadership = 70.0
		king.max_hp *= 2.0
		king.hp = king.max_hp
		nat.king = king
		if fort:
			fort.accept_unit(king)
			for k in 4:
				var s := spawn_unit(Defs.unit_sprite(nat.race, "INF"), nat.id, Vector2i(fpos.x, fpos.y + fw + 1), float(rng.randi_range(20, 35)))
				s.leadership = float(rng.randi_range(10, 40))
				fort.accept_unit(s)
		# A general and two soldiers outside, ready to build and explore.
		var spot := world.adjacent_to_rect(town.footprint(), Vector2i(tpos.x + 3, tpos.y + 7))
		var g := spawn_unit(Defs.unit_sprite(nat.race, "INF"), nat.id, spot, 35.0)
		g.rank = Defs.Rank.GENERAL
		g.leadership = float(rng.randi_range(40, 60))
		for k in 2:
			spawn_unit(Defs.unit_sprite(nat.race, "INF"), nat.id, spot + Vector2i(k + 1, 0), 25.0)


## A Fryhtan kingdom starts with a lair commanded by its leader and a brood.
func _start_fryhtan(nat: Nation, at: Vector2i) -> void:
	var lair := spawn_firm("LAIR", nat.id, nat.monster_code, at, true)
	if lair == null:
		return
	lair.monster_code = nat.monster_code
	var leader := spawn_unit(nat.monster_code, nat.id, Vector2i(at.x, at.y + lair.h + 1), 70.0)
	if leader:
		leader.rank = Defs.Rank.KING
		leader.leadership = 70.0
		leader.max_hp *= 2.0
		leader.hp = leader.max_hp
		nat.king = leader
		lair.accept_unit(leader)
	for k in 5:
		var u := spawn_unit(nat.monster_code, nat.id, Vector2i(at.x, at.y + lair.h + 1), float(rng.randi_range(30, 50)))
		if u:
			lair.accept_unit(u)
	var spot := world.adjacent_to_rect(lair.footprint(), Vector2i(at.x + 3, at.y + lair.h + 2))
	for k in 2:
		spawn_unit(nat.monster_code, nat.id, spot + Vector2i(k, 0), 40.0)


## Free position for a w x h building next to `r`. When `anchors` (location
## centres) are given, the building's centre must be within linking distance
## of every one of them.
func _place_near(r: Rect2i, fw: int, fh: int, max_gap := 8, anchors: Array = []) -> Vector2i:
	for gap in range(1, max_gap):
		var cands: Array[Vector2i] = []
		for x in range(r.position.x - fw - gap, r.end.x + gap + 1):
			cands.append(Vector2i(x, r.position.y - fh - gap))
			cands.append(Vector2i(x, r.end.y + gap))
		for y in range(r.position.y - fh - gap, r.end.y + gap + 1):
			cands.append(Vector2i(r.position.x - fw - gap, y))
			cands.append(Vector2i(r.end.x + gap, y))
		_shuffle(cands)
		for c in cands:
			if world.can_place(c.x, c.y, fw, fh) and not _overlaps_site(Rect2i(c, Vector2i(fw, fh))):
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
	var count := maxi(nations.size() + 2, size * size / 1100)
	# One deposit near every kingdom so each can start an economy.
	for p in start_points:
		_add_site(raw_rows[rng.randi() % raw_rows.size()], Vector2(p), 9.0, 16.0)
	for i in count - start_points.size():
		_add_site(raw_rows[rng.randi() % raw_rows.size()], Vector2(-1, -1), 0, 0)


func _add_site(row: Dictionary, near: Vector2, min_r: float, max_r: float) -> void:
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
		return


func _generate_independents(size: int, cfg: Dictionary) -> void:
	var count: int = cfg.get("indep_towns", maxi(6, size * size / 1000))
	var used := _used_town_names
	for i in count:
		var avoid := _occupied_centers()
		var p := _random_free_rect(6, 6, 4, avoid, 13.0)
		if p.x < 0:
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
		for k in rng.randi_range(3, 6):
			var u := spawn_unit(m["unit"], GameObj.MONSTER_NATION, Vector2i(p.x, p.y + lh), float(rng.randi_range(20, 50)))
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
		if f.nation_id != nid and (n == null or n.relation(f.nation_id) < Defs.Relation.PEACE):
			continue
		var d := f.center_loc().distance_to(home.center_loc())
		if d > 8.0 and d < best_d:
			best_d = d
			best = f
	return best


func caravans_of(market: Firm) -> int:
	return units.filter(func(u): return u.is_caravan and not u.dead and u.caravan_home == market).size()


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
		var c := world.adjacent_to_rect(place.footprint(), Vector2i(place.center_loc()))
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


func spy_spawn(college: Firm) -> Unit:
	var n := college.nation()
	if n == null or not n.can_afford(Defs.SPY_COST):
		return null
	var town: Town = null
	for t in college.linked_towns:
		if t.nation_id == college.nation_id and t.can_spare_trainee():
			town = t
			break
	if town == null:
		return null
	town.population -= 1
	town._check_empty()
	n.add_cash(-float(Defs.SPY_COST), "Spies")
	var c := world.adjacent_to_rect(college.footprint(), Vector2i(college.center_loc()))
	var u := spawn_unit(Defs.unit_sprite(town.race, "CIV"), college.nation_id, c, 10.0)
	if u:
		u.is_spy = true
		u.spy_skill = float(rng.randi_range(25, 50))
	return u


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


## Baal-Hammon's earthquake: enemy buildings and units in range are shaken.
func earthquake(nid: int, c: Vector2, r: float) -> void:
	var n := nation(nid)
	for f in firms.duplicate():
		if f.dead or f.nation_id == nid or f.center_loc().distance_to(c) > r:
			continue
		if n and f.nation_id > 0 and f.nation_id != GameObj.MONSTER_NATION and not n.is_hostile_to(f.nation_id):
			continue
		f.take_damage(f.max_hp * 0.25, null)
	for u in units.duplicate():
		if u.dead or u.inside_firm or u.nation_id == nid or u.center_loc().distance_to(c) > r:
			continue
		if n and u.nation_id > 0 and u.nation_id != GameObj.MONSTER_NATION and not n.is_hostile_to(u.nation_id):
			continue
		u.take_damage(25.0, null)
	shake.emit(10.0)


## Mithra: the land around is revealed (for the player's fog of war).
func reveal_area(nid: int, c: Vector2i, r: int) -> void:
	if nid != player_id:
		return
	_reveal(c, r)
	for i in fog.size():
		if fog[i] == 2:
			fog[i] = 1
	_reveal(c, r)
	fog_view.update_from(fog)
	_ground_dirty = true


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


func spawn_town_arrow(from: GameObj, to: Unit, sprite: String, dmg: float) -> void:
	var b := Bullet.new()
	b.shooter = from
	b.target = to
	b.sprite_code = sprite
	b.speed = 16.0
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


func spawn_bullet(from: Unit, to: GameObj, sprite: String, spd: float, dmg: float) -> void:
	var b := Bullet.new()
	b.setup(from, to, sprite, spd, dmg)
	effects.add_child(b)
	bullets.append(b)


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
		for u in units_near(t.center_loc(), 1.5):
			if u.dead or u.inside_firm or u.cell() != t.cell:
				continue
			if _take(t, u):
				break


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
			var code := t.tech_code()
			if code != "" and n.tech_level(code) == 0:
				n.tech[code] = 1
			what = "the plans of the %s" % t.tech_name()
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
	if a == null or b == null or a.nation_id == b.nation_id:
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
	return out


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
	if world == null or paused or (over and not Net.active):
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
	weather.next_day(rng)
	if weather.is_lightning() and rng.randf() < 0.35:
		_lightning_strike()
	_allocate_workers()
	for t in towns.duplicate():
		t.next_day(day)
	for f in firms.duplicate():
		f.next_day(day)
	for n in nations:
		if not n.alive:
			continue
		if n.food < 0 and day % 30 == 0 and n.is_player:
			notify("Your people are starving! Build up food by keeping villagers unemployed or researching farming.", Vector2(-1, -1))
		if n.ai:
			n.ai.next_day(day)
		if day % 365 == 0:
			n.new_year()
	if campaign_battle != null:
		campaign_battle.next_day()
	_check_homeless()
	_items_next_day()
	if day % 5 == 0:
		_check_end()
	_check_goals()
	_update_fog()


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
	if not world.can_place(pos.x, pos.y, b.get("loc_w", 3), b.get("loc_h", 3), code == "MINE"):
		return
	var f := spawn_firm(code, nid, race, pos, false)
	if f == null:
		return
	n.add_cash(-cost, "Construction")
	n.live_points -= live
	if code == "LAIR":
		f.monster_code = species
	if builder and is_instance_valid(builder) and not builder.dead:
		builder.order_build(f)


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
	for f in firms:
		if f.dead:
			continue
		var fc := f.center_loc()
		for t in towns:
			if t.dead:
				continue
			if _center_dist(fc, t.center_loc()) <= Defs.EFFECTIVE_FIRM_TOWN_DISTANCE:
				f.linked_towns.append(t)
				t.linked_firms.append(f)
		for g in firms:
			if g != f and not g.dead and _center_dist(fc, g.center_loc()) <= Defs.EFFECTIVE_FIRM_FIRM_DISTANCE:
				f.linked_firms.append(g)


## Work firms draw workers from linked towns of their own kingdom. Each town
## shares its workforce evenly between its workplaces and keeps 30% of its
## people as farmers so the kingdom does not starve (Town::process_food).
func _allocate_workers() -> void:
	for t in towns:
		t.employed = 0
	for f in firms:
		f.worker_from.clear()
	for t in towns:
		if t.nation_id <= 0 or t.dead:
			continue
		var n := nation(t.nation_id)
		var fl: Array = t.linked_firms.filter(func(f): return not f.dead and not f.under_construction and f.is_work_firm() and f.nation_id == t.nation_id and (f.code != "BASE" or t.race == f.race))
		if fl.is_empty():
			continue
		var avail := int(t.population * 0.7)
		var progress := true
		while avail > 0 and progress:
			progress = false
			for f in fl:
				if avail > 0 and f.workers() < Defs.MAX_WORKER:
					f.worker_from[t] = f.worker_from.get(t, 0) + 1
					t.employed += 1
					avail -= 1
					progress = true


# ------------------------------------------------------------------- fog ---

func _update_fog() -> void:
	if reveal_all:
		fog.fill(2)
		fog_view.update_from(fog)
		return
	for i in fog.size():
		if fog[i] == 2:
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


func notify(text: String, loc: Vector2) -> void:
	message.emit(text, loc)


## True when nobody plays: every kingdom is AI-controlled and the human watches.
func observer() -> bool:
	return config.get("autoplay", false)


func notify_nation(nid: int, text: String, loc: Vector2) -> void:
	if nid == player_id and not observer():
		notify(text, loc)


func deselect(o: GameObj) -> void:
	if o in selected:
		selected.erase(o)
		o.selected = false
		o.queue_redraw()


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
	# Fryhtan kingdoms absorb the life of what they kill (Unit::calc_live_points_bonus).
	if killer and is_instance_valid(killer):
		var kn := nation(killer.nation_id)
		if kn and kn.is_fryhtan:
			kn.live_points += 10.0 if u.is_human() else 4.0
	_drop_item(u)
	var n := nation(u.nation_id)
	if n and n.king == u:
		n.king = null
		n.change_reputation(-10.0)
		_drop_scroll(n, u.cell())
		_drop_mega_plans(n, u.cell())
		var heir := _best_heir(n)
		if heir:
			heir.rank = Defs.Rank.KING
			n.king = heir
			notify_nation(n.id, "Your king has died. %s takes the throne." % heir.unit_name, u.center_loc())
			if n.id != player_id or observer():
				notify("The king of the %s has fallen; %s takes the throne." % [n.name, heir.unit_name], u.center_loc())
		else:
			notify_nation(n.id, "Your king has died and there is no heir!", u.center_loc())
			if observer():
				notify("The king of the %s has fallen, leaving no heir." % n.name, u.center_loc())


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
	f.eject_all()
	if f.builder and is_instance_valid(f.builder):
		f.builder.inside_firm = null
		f.builder.visible = true
		f.builder = null
	world.release(f.x1, f.y1, f.w, f.h)
	if f.site:
		f.site.mine = null
	if not f.under_construction and f.visible:
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
			notify_nation(kn.id, "Fryhtan lair destroyed! Treasure found: %d gold." % int(treasure), f.center_loc())
	elif observer() and f.nation_id > 0 and nation(f.nation_id):
		notify("The %s has lost a %s." % [nation(f.nation_id).name, f.display_name()], f.center_loc())
	elif f.nation_id == player_id:
		notify("%s destroyed!" % f.display_name(), f.center_loc())
	f.queue_free()
	update_links()
	_ground_dirty = true


func on_town_changed(t: Town, old_nation: int) -> void:
	if observer():
		var tn := nation(t.nation_id)
		notify("%s now belongs to the %s." % [t.town_name, tn.name] if tn else "%s has become independent." % t.town_name, t.center_loc())
	elif t.nation_id == player_id:
		notify("%s has joined your kingdom!" % t.town_name, t.center_loc())
	elif old_nation == player_id:
		notify("%s has been lost!" % t.town_name, t.center_loc())
	var n := nation(t.nation_id)
	if n:
		n.change_reputation(1.0)


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
		if u.center_loc().distance_to(c) <= 8.0 and is_hostile(u, attacker):
			var building: GameObj = u.target if sieging else null
			u.order_attack(attacker)
			u.resume_target = building


func declare_war(a: int, b: int) -> void:
	var na := nation(a)
	var nb := nation(b)
	if na == null or nb == null or na.relation(b) == Defs.Relation.WAR:
		return
	if na.relation(b) >= Defs.Relation.PEACE:
		na.change_reputation(-15.0)     # breaking a treaty hurts reputation
	na.relations[b] = Defs.Relation.WAR
	nb.relations[a] = Defs.Relation.WAR
	if observer():
		notify("The %s has declared war on the %s." % [na.name, nb.name], Vector2(-1, -1))
	elif a == player_id:
		notify("You have declared war on the %s." % nb.name, Vector2(-1, -1))
	elif b == player_id:
		notify("The %s has declared war on you!" % na.name, Vector2(-1, -1))


func make_peace(a: int, b: int) -> void:
	var na := nation(a)
	var nb := nation(b)
	if na == null or nb == null:
		return
	if peace_offers.has(a):
		peace_offers[a].erase(b)
	if peace_offers.has(b):
		peace_offers[b].erase(a)
	na.relations[b] = Defs.Relation.PEACE
	nb.relations[a] = Defs.Relation.PEACE
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
