class_name CampaignBattle
extends RefCounted
## Builds and runs one campaign battle (stage_n_create_game, stage_n_next_day and
## the plots of oc_pl*.cpp) on a fresh map, with the helpers of ocampgn4.cpp:
## towns with forts, Fryhtan lairs with enslaved villages, economic and military
## buildings, troops arriving from the map edge, rebellions, defecting generals
## and Fryhtan reinforcements.

const WORLD := 140
const TEAM := 16                 # MAX_TEAM_MEMBER
const STD_MONSTER_HP := 300.0    # troop sizes are scaled to this many hit points
const WAGON_POP := 10            # MAX_WAGON_POPULATION

var c: Campaign
var g: Game
var stage := 0
var d := 3                       # campaign difficulty
var gn := {}                     # campaign nation id -> game nation id
var plot := ""                   # "A1" ... "D5", "" for none
var plot_vars := {}
var vars := {}                   # rebellions, defections, reinforcements, the hero ...
var situation := {}              # cur_situation levels (0 = none)
var last_loc := Vector2i(-1, -1) # create_unit_x_loc / y_loc
var won_tech := ""               # offensive building tech met in this battle


static func create(campaign: Campaign) -> CampaignBattle:
	var b := CampaignBattle.new()
	b.c = campaign
	b.stage = campaign.stage_id
	b.d = campaign.difficulty
	return b


func rnd(n: int) -> int:
	return g.rng.randi_range(0, n - 1) if n > 1 else 0


# ============================================================ building ===

## Called by Game.start once the terrain exists.
func build(game: Game) -> void:
	g = game
	g.year0 = c.game_year
	g.tech_available = c.tech_available
	vars = {"rebel_count": 0, "next_rebel": 0, "defect_count": 0, "next_defect": 0,
		"reinforce": 0, "next_reinforce": 0, "edge": 0, "hero": null}
	# CampaignEastWest::stage_prelude: E_DEFEAT_EXCEPT_ALLIANCE in every battle
	var win: Array = [_cond(Goals.DEFEAT_EXCEPT_ALLIANCE, "Defeat every kingdom but your ally")]
	var lose: Array = []
	g.goals = Goals.new()
	g.goals.win = win
	g.goals.lose = lose
	call("_stage_%d" % stage)
	_plot_create()
	if stage not in [20, 21, 22, 23, 24, 25, 26, 27, 28]:
		_add_sites(2 + rnd(2))
	_royals()
	g.update_links()
	_set_all_loyalty()


func _cond(id: int, text: String, p2 := 0, years := 0, target = null) -> Dictionary:
	return {"id": id, "p1": 0, "p2": p2, "years": years, "player_only": true, "text": text,
		"result": "", "target": target, "supported": true, "met": false}


func _reset_win() -> void:
	g.goals.win.clear()


func _situation(id: int) -> void:
	# Campaign::init_situation: six typical states of a province, randomised a little
	var base := {"cash": 50, "food": 50, "mine_raw": 50, "site_raw": 50, "population": 50, "reputation": 50,
		"tech": 50, "economy": 50, "military": 50, "town_loyalty": 50, "unit_loyalty": 50}
	var presets := [
		{"cash": 100, "mine_raw": 10, "site_raw": 30},
		{"cash": 80, "food": 10, "population": 25, "economy": 80},
		{"cash": 20, "economy": 20, "military": 80},
		{"cash": 25, "population": 30, "economy": 25, "town_loyalty": 80, "unit_loyalty": 80},
		{"tech": 90, "economy": 70, "military": 15},
		{"cash": 25, "food": 25, "mine_raw": 25, "site_raw": 25, "tech": 75, "military": 75},
	]
	if id > 0:
		base.merge(presets[id - 1], true)
		for k in base:
			base[k] += rnd(11) - 5
	situation = base


func _std_situation() -> void:
	situation = {"cash": 50, "food": 50, "mine_raw": 50, "site_raw": 50, "population": 50, "reputation": 50,
		"tech": 50, "economy": 50, "military": 50, "town_loyalty": 50, "unit_loyalty": 50}


# ----------------------------------------------------------- nations ---

## StateInfo::add_game_nation: the kingdom of a campaign province joins the battle.
func add_game_nation(cnid: int) -> int:
	if gn.has(cnid):
		return gn[cnid]
	var cn: Dictionary = c.nations.get(cnid, {})
	if cn.is_empty():
		return 0
	var id := g.nations.size() + 1
	var player := cnid == c.western
	var n := Nation.new(id, cn["race"], Defs.NATION_COLORS[cn["color"] % Defs.NATION_COLORS.size()], not player)
	n.is_player = player
	n.name = cn["name"]
	if cn["type"] == "monster":
		n.is_fryhtan = true
		n.monster_code = cn["race"]
		n.name = "%s Fryhtans of %s" % [c.race_name(cnid), cn["name"]]
	for r in cn.get("know_base", {}):
		n.known_gods[r] = true
	_add(n)
	gn[cnid] = id
	return id


## A kingdom that exists only in this battle (rebels, plot kingdoms).
func new_game_nation(race: String, fryhtan := false) -> int:
	var id := g.nations.size() + 1
	var used := g.nations.map(func(x): return x.color)
	var col: Color = Defs.NATION_COLORS[(id - 1) % Defs.NATION_COLORS.size()]
	for cc in Defs.NATION_COLORS:
		if not cc in used:
			col = cc
			break
	var n := Nation.new(id, race, col, true)
	if fryhtan:
		n.is_fryhtan = true
		n.monster_code = race
		n.name = "%s Fryhtans" % _species_name(race)
	_add(n)
	return id


func _add(n: Nation) -> void:
	for o in g.nations:
		o.relations[n.id] = Defs.Relation.NEUTRAL
		n.relations[o.id] = Defs.Relation.NEUTRAL
	g.nations.append(n)
	if n.is_ai:
		n.ai = FryhtanAI.new(n, g) if n.is_fryhtan else NationAI.new(n, g)
	n.cash = 1000.0
	n.food = 0.0 if n.is_fryhtan else 1000.0
	if n.is_fryhtan:
		n.live_points = 500.0


func _species_name(code: String) -> String:
	for m in Defs.monsters:
		if m["unit"] == code:
			return m["name"]
	return code.capitalize()


func set_hostile(a: int, b: int) -> void:
	var na := g.nation(a)
	var nb := g.nation(b)
	if na and nb:
		na.relations[b] = Defs.Relation.WAR
		nb.relations[a] = Defs.Relation.WAR


func set_allied(a: int, b: int) -> void:
	var na := g.nation(a)
	var nb := g.nation(b)
	if na and nb:
		na.relations[b] = Defs.Relation.ALLIANCE
		nb.relations[a] = Defs.Relation.ALLIANCE
		Diplomacy.set_trade(g, a, b, true)      # allies are obliged to trade


## Campaign::init_player_resource: the easier the campaign, the richer you are.
func init_player_resource(level: int) -> void:
	var n := g.player()
	var t := Campaign.MAX_DIFFICULTY - d + 1
	var cash_l: int = situation.get("cash", level) if not situation.is_empty() else level
	var food_l: int = situation.get("food", level) if not situation.is_empty() else level
	var rep_l: int = situation.get("reputation", level) if not situation.is_empty() else level
	var amt := (20 + cash_l) * 50
	n.cash = float(amt * t + rnd(amt))
	amt = maxi(1, food_l * 30)
	n.food = float(amt * t + rnd(amt))
	amt = maxi(1, rep_l / 5)
	n.reputation = float(amt * t + rnd(amt))
	if n.is_fryhtan:
		n.live_points = float(level * 35 * t)


## Campaign::init_nation_resource: enemies grow richer with the difficulty.
func init_nation_resource(nid: int, level: int) -> void:
	var n := g.nation(nid)
	if n == null:
		return
	var t := Campaign.MAX_DIFFICULTY - d + 1 if nid == g.player_id or g.player().relation(nid) == Defs.Relation.ALLIANCE else d - 1
	var amt := level * 70
	n.cash = float(amt * t + rnd(amt))
	amt = level * 35
	n.food = float(amt * t + rnd(amt))
	if n.is_fryhtan:
		n.live_points = float(level * 35 * t + rnd(level * 35))
	else:
		amt = maxi(1, level / 5)
		n.reputation = float(amt * t + rnd(amt))


func _set_all_loyalty() -> void:
	for t in g.towns:
		if t.nation_id > 0:
			t.update_target_loyalty()
			t.loyalty = maxf(t.loyalty, t.target_loyalty)


# -------------------------------------------------------- placement ---

func _loc(sx: float, sy: float) -> Vector2i:
	return Vector2i(int(sx * WORLD / 100.0), int(sy * WORLD / 100.0))


## Centres of `count` evenly spread areas on the 100 x 100 layout map (a
## StateArray's capitals), in the order the original walks them.
func _spread(count: int) -> Array:
	var sep := sqrt(10000.0 / count)
	var pts: Array = []
	for i in count:
		for trial in (i + 1) * 16 + 1:
			var p := Vector2(rnd(100), rnd(100))
			if pts.all(func(q): return maxf(absf(p.x - q.x), absf(p.y - q.y)) * 2.0 >= sep):
				pts.append(p)
				break
	pts.reverse()
	return pts


func _free_rect_near(at: Vector2i, w: int, h: int, r := 6) -> Vector2i:
	for rad in range(0, r + 1):
		for dy in range(-rad, rad + 1):
			for dx in range(-rad, rad + 1):
				if maxi(absi(dx), absi(dy)) != rad:
					continue
				var p := at + Vector2i(dx, dy)
				if p.x < 2 or p.y < 2 or p.x + w > WORLD - 2 or p.y + h > WORLD - 2:
					continue
				if g.world.can_place(p.x - 1, p.y - 1, w + 2, h + 2) and not g._overlaps_site(Rect2i(p - Vector2i(1, 1), Vector2i(w + 2, h + 2))):
					return p
	return Vector2i(-1, -1)


func _firm_size(code: String, race: String) -> Vector2i:
	var b := Assets.firm_build(code, race)
	return Vector2i(b.get("loc_w", 4), b.get("loc_h", 4))


## Firm next to a town or building (create_firm_next_to_place).
func firm_next_to(place: GameObj, code: String, race: String, nid: int) -> Firm:
	var sz := _firm_size(code, race)
	var anchors: Array = [place.center_loc()] if place is Town else []
	var p := g._place_near(place.footprint(), sz.x, sz.y, 7, anchors)
	if p.x < 0:
		p = g._place_near(place.footprint(), sz.x, sz.y, 9)
	if p.x < 0:
		return null
	var f := g.spawn_firm(code, nid, race, p, true)
	return f


# ---------------------------------------------------------- creation ---

func _infantry(nid: int) -> String:
	var n := g.nation(nid)
	if n == null:
		return "NO_INF"
	return n.monster_code if n.is_fryhtan else Defs.unit_sprite(n.race, "INF")


## Campaign::create_nation_town: a town of the kingdom with a fort, its king or a
## general in command and soldiers of the town's people.
func create_nation_town(nid: int, at: Vector2i, build_fort: bool, same_race := true, soldiers := 100, combat := 0) -> Town:
	var n := g.nation(nid)
	var race := n.race
	if not same_race and rnd(2) == 0:
		race = Defs.races[rnd(Defs.races.size())]["code"]
	var p := _free_rect_near(at, Defs.TOWN_SIZE, Defs.TOWN_SIZE, 5)
	if p.x < 0:
		return null
	var pop: int
	var loyal: float
	if not situation.is_empty():
		loyal = minf(100.0, situation["town_loyalty"] + rnd(20))
		pop = clampi(Defs.MAX_TOWN_POPULATION * situation["population"] / 100 + rnd(20) - 10, 10, Defs.MAX_TOWN_POPULATION)
	else:
		loyal = 60.0 + rnd(30)
		pop = 30 + rnd(30)
	var t := g.spawn_town(race, nid, p, pop)
	t.loyalty = loyal
	t.bonus_loyalty = 30.0
	if not build_fort:
		return t
	var f := firm_next_to(t, "FORT", n.race, nid)
	if f == null:
		return t
	var lead := g.spawn_unit(_infantry(nid), nid, f.door(), 50.0 + rnd(30))
	if lead == null:
		return t
	lead.leadership = 40.0 + rnd(40)
	if n.king == null:
		lead.rank = Defs.Rank.KING
		lead.leadership = maxf(lead.leadership, 60.0)
		n.king = lead
	else:
		lead.rank = Defs.Rank.GENERAL
	if not situation.is_empty():
		lead.loyalty = minf(float(situation["unit_loyalty"] + rnd(30)), 90.0 + rnd(10))
	f.accept_unit(lead)
	for i in mini(soldiers, f.capacity()):
		var lvl := clampf(combat + rnd(20) - 10, 0.0, 100.0) if combat > 0 else float(30 + rnd(30))
		var sp := Defs.unit_sprite(t.race, "INF") if not n.is_fryhtan else n.monster_code
		var s := g.spawn_unit(sp, nid, f.door(), lvl)
		if s:
			if not situation.is_empty():
				s.loyalty = minf(100.0, situation["unit_loyalty"] + rnd(20))
			f.accept_unit(s)
	return t


func create_independent_town(at: Vector2i, race: String, pop: int, resistance: int) -> Town:
	var p := _free_rect_near(at, Defs.TOWN_SIZE, Defs.TOWN_SIZE, 5)
	if p.x < 0:
		return null
	var t := g.spawn_town(race, 0, p, pop)
	for n in g.nations:
		t.resistance[n.id] = float(resistance)
	return t


## Battle::create_independent_town: villages scattered over free land.
func create_independent_towns(count: int) -> void:
	for i in count:
		var p := g._random_free_rect(Defs.TOWN_SIZE, Defs.TOWN_SIZE, 4, g._occupied_centers(), 13.0)
		if p.x < 0:
			continue
		var race: String = Defs.races[rnd(Defs.races.size())]["code"]
		var t := g.spawn_town(race, 0, p, 20 + rnd(30))
		for n in g.nations:
			t.resistance[n.id] = float(50 + rnd(40))


## Campaign::create_monster_lair: a lair with its commander and brood.
func create_monster_lair(at: Vector2i, nid: int, soldiers: int, avg_combat: int, species := "") -> Firm:
	var n := g.nation(nid)
	if species == "":
		species = n.monster_code
	var sz := _firm_size("LAIR", species)
	var p := _free_rect_near(at, sz.x, sz.y, 5)
	if p.x < 0:
		return null
	var f := g.spawn_firm("LAIR", nid, species, p, true)
	if f == null:
		return null
	f.monster_code = species
	var lead := g.spawn_unit(species, nid, f.door(), float(clampi(avg_combat + 10, 20, 100)))
	if lead:
		lead.leadership = 50.0 + rnd(30)
		if n.king == null:
			lead.rank = Defs.Rank.KING
			lead.max_hp *= 2.0
			lead.hp = lead.max_hp
			n.king = lead
		else:
			lead.rank = Defs.Rank.GENERAL
		f.accept_unit(lead)
	var hp := float(Defs.unit_types.get(species, {}).get("hp", 300))
	var count := clampi(int(soldiers * STD_MONSTER_HP / maxf(1.0, hp)), 1, f.capacity())
	for i in count:
		var u := g.spawn_unit(species, nid, f.door(), float(clampi(avg_combat + rnd(30) - 15, 20, 100)))
		if u:
			f.accept_unit(u)
	return f


## A village enslaved by the lair next to it (create_slave_town).
func create_slave_town(lair: Firm, race: String) -> Town:
	var p := g._place_near(lair.footprint(), Defs.TOWN_SIZE, Defs.TOWN_SIZE, 6, [lair.center_loc()])
	if p.x < 0:
		return null
	var t := g.spawn_town(race, 0, p, 30 + rnd(30))
	for n in g.nations:
		t.resistance[n.id] = 60.0
	t.resistance[lair.nation_id] = 0.0
	return t


## Campaign::create_economic_firm: a mine on a deposit near the town, a factory
## and a market, already stocked.
func create_economic_firm(t: Town) -> bool:
	if t == null:
		return false
	var nid := t.nation_id
	var n := g.nation(nid)
	var site: Site = null
	for s in g.sites:
		if s.mine == null and Game._center_dist(s.center_loc(), t.center_loc()) <= Defs.EFFECTIVE_FIRM_TOWN_DISTANCE:
			site = s
			break
	if site == null:
		var raw_rows: Array = Assets.table("RAW").slice(0, 3)
		if raw_rows.is_empty():
			return false
		var before := g.sites.size()
		g._add_site(raw_rows[rnd(raw_rows.size())], t.center_loc(), 8.0, 13.0)
		if g.sites.size() == before:
			return false
		site = g.sites[-1]
	var mine := g.spawn_firm("MINE", nid, n.race, Vector2i(site.x1, site.y1), true)
	if mine == null:
		return false
	mine.stock = float(100 + rnd(400))
	if not situation.is_empty():
		mine.reserve = mine.reserve * situation["mine_raw"] / 100.0
		site.reserve = mine.reserve
	var fac_sz := _firm_size("FACTORY", n.race)
	var fp := g._place_near(mine.footprint(), fac_sz.x, fac_sz.y, 8, [mine.center_loc(), t.center_loc()])
	if fp.x < 0:
		fp = g._place_near(mine.footprint(), fac_sz.x, fac_sz.y, 8)
	if fp.x < 0:
		return true
	var fac := g.spawn_firm("FACTORY", nid, n.race, fp, true)
	if fac == null:
		return true
	fac.stock = float(100 + rnd(400))
	fac.raw = mine.raw
	var mk_sz := _firm_size("MARKET", n.race)
	var mp := g._place_near(fac.footprint(), mk_sz.x, mk_sz.y, 8, [fac.center_loc(), t.center_loc()])
	if mp.x < 0:
		mp = g._place_near(fac.footprint(), mk_sz.x, mk_sz.y, 8)
	if mp.x >= 0:
		g.spawn_firm("MARKET", nid, n.race, mp, true)
	return true


## Campaign::create_military_firm: some of a training centre (with trainees), a
## Tower of Science, a War Factory and a Seat of Power, by the power rating.
func create_military_firm(t: Town, power := 100) -> bool:
	if t == null:
		return false
	var nid := t.nation_id
	var n := g.nation(nid)
	var build := [false, false, false, false]
	var cnt := 4 * power / 100
	var k := 0
	while k < cnt:
		var j := rnd(4)
		if not build[j]:
			build[j] = true
			k += 1
	if build[0] and n.tech_level(Defs.spu_structure_tech(t.race)) > 0:
		var st := firm_next_to(t, "STABLE", t.race, nid)
		if st:
			for i in 2 + rnd(3):
				var u := g.spawn_unit(Defs.unit_sprite(t.race, "SPU"), nid, st.door(), 40.0 + rnd(20))
				if u:
					u.leadership = 20.0 + rnd(30)
	if build[1]:
		firm_next_to(t, "RESEARCH", n.race, nid)
	if build[2] and Defs.WEAPONS.any(func(w): return n.tech_level(w) > 0):
		firm_next_to(t, "WAR", n.race, nid)
	if build[3] and power >= 70 and n.known_gods.has(n.race):
		firm_next_to(t, "BASE", n.race, nid)
	return true


func create_work_firm(t: Town, code: String) -> Firm:
	return firm_next_to(t, code, g.nation(t.nation_id).race, t.nation_id)


## The town whose fort the king commands (king_oversee_town_recno).
func king_town(nid: int) -> Town:
	var n := g.nation(nid)
	if n == null:
		return null
	if n.king and is_instance_valid(n.king) and n.king.inside_firm:
		for t in n.king.inside_firm.linked_towns:
			if t.nation_id == nid:
				return t
	for t in g.towns:
		if t.nation_id == nid and not t.dead:
			if n.king == null:
				var k := g.spawn_unit(_infantry(nid), nid, Vector2i(t.x1, t.y1 + Defs.TOWN_SIZE + 1), 60.0)
				if k:
					k.rank = Defs.Rank.KING
					k.leadership = 60.0
					n.king = k
			return t
	return null


## A town of the kingdom with a linked camp and few links (random_pick_town_with_camp).
func town_with_camp(nid: int, max_links: int) -> Town:
	var list := g.towns.filter(func(t): return t.nation_id == nid and not t.dead and t.has_linked_camp(nid) and t.linked_firms.size() <= max_links)
	return list[rnd(list.size())] if not list.is_empty() else null


## Campaign::create_town: several towns of the kingdom, a share with forts.
func create_town(nid: int, count: int, fort_pct: int, combat := 0) -> void:
	var pts := _spread(30)
	var step := maxi(1, 100 / maxi(1, fort_pct))
	for i in pts.size():
		if count <= 0:
			break
		var fort := (pts.size() - i) % step == 0
		if create_nation_town(nid, _loc(pts[i].x, pts[i].y), fort, true, 100, combat):
			count -= 1
	g.update_links()


## The usual first two buildings of a kingdom: an economy by one town and
## military buildings by another (stage_n_create_firm).
func create_firms(nid: int, set_race := true, military_power := 100) -> void:
	var n := g.nation(nid)
	g.update_links()
	var t1 := king_town(nid)
	var t2 := town_with_camp(nid, 2)
	if t2 == t1:
		t2 = null
	if t2 and rnd(2) == 0:
		var tt := t1
		t1 = t2
		t2 = tt
	if set_race:
		if t1:
			t1.race = n.race
		if t2:
			t2.race = n.race
	create_economic_firm(t1)
	if t2:
		create_military_firm(t2, military_power)
	g.update_links()


## Campaign::create_troop: an army at the map edge in teams led by generals
## (the first unit is the king if the kingdom has none), with supply wagons.
func create_troop(nid: int, total: int, avg_combat := 0, sprite := "", use_last := false) -> void:
	if total <= 0:
		return
	if nid == g.player_id and c.this_battle_use_fryhtan and c.surrendered_fryhtan != "" and sprite == "":
		_troop(nid, total / 2, avg_combat, sprite, use_last)
		_troop(nid, total / 2, avg_combat, c.surrendered_fryhtan, true)
	else:
		_troop(nid, total, avg_combat, sprite, use_last)
	var n := g.nation(nid)
	if n and not n.is_fryhtan and (nid == g.player_id or g.player().relation(nid) == Defs.Relation.ALLIANCE):
		create_wagon(nid, 60 - d * 10 + rnd(10), true)


func _troop(nid: int, total: int, avg_combat: int, sprite: String, use_last: bool) -> void:
	var at := last_loc if use_last and last_loc.x >= 0 else _edge_loc(0)
	var teams := ceili(total / float(TEAM))
	var size := total / maxi(1, teams)
	var made: Array = []
	for i in teams:
		made.append_array(create_unit_group(nid, size + rnd(3) - 1, sprite, true, at))
		if at.x <= 2 or at.x >= WORLD - 3:
			at.y = mini(WORLD - 3, at.y + 5)
		else:
			at.x = mini(WORLD - 3, at.x + 5)
	last_loc = at
	if avg_combat > 0:
		for u in made:
			if u.rank == Defs.Rank.GENERAL:
				u.combat = float(clampi(avg_combat + 30 + rnd(30) - 15, 20, 100))
			elif u.rank == Defs.Rank.SOLDIER:
				u.combat = float(clampi(avg_combat + rnd(30) - 15, 20, 100))


## Campaign::create_unit_group: up to a team of units at a place, the first a
## general (or the king when the kingdom has none).
func create_unit_group(nid: int, count: int, sprite := "", adjust := false, at := Vector2i(-1, -1), edge := 0) -> Array:
	var n := g.nation(nid)
	if n == null:
		return []
	if sprite == "":
		sprite = _infantry(nid)
	count = mini(count, TEAM)
	if adjust and Defs.unit_types.get(sprite, {}).get("class", "") == "MONSTER":
		count = int(count * STD_MONSTER_HP / maxf(1.0, float(Defs.unit_types[sprite]["hp"])))
	count = clampi(count, 1, TEAM)
	if at.x < 0:
		at = _edge_loc(edge)
	var has_race: bool = Defs.unit_types.get(sprite, {}).get("race", "") != ""
	var out: Array = []
	for i in count:
		var u := g.spawn_unit(sprite, nid, at + Vector2i(i % 4, i / 4), 30.0 + rnd(20))
		if u == null:
			break
		if has_race and (i == 0 or n.king == null):
			if n.king == null:
				u.rank = Defs.Rank.KING
				u.leadership = 60.0 + rnd(20)
				n.king = u
			else:
				u.rank = Defs.Rank.GENERAL
				u.leadership = 30.0 + rnd(40)
		out.append(u)
	return out


## Wagons of settlers following an army (UnitWagon): villagers here.
func create_wagon(nid: int, pop: int, use_last := false) -> void:
	var n := g.nation(nid)
	if n == null or n.is_fryhtan:
		return
	var at := last_loc if use_last and last_loc.x >= 0 else _edge_loc(0)
	for i in maxi(1, pop / WAGON_POP):
		g.spawn_unit(Defs.unit_sprite(n.race, "CIV"), nid, at + Vector2i(i % 3, 2 + i / 3), 10.0)


## Campaign::random_edge_location.
func _edge_loc(edge: int) -> Vector2i:
	match edge:
		1: return Vector2i(rnd(WORLD - 6) + 3, 3)
		2: return Vector2i(rnd(WORLD - 6) + 3, WORLD - 6)
		3: return Vector2i(3, rnd(WORLD - 6) + 3)
		4: return Vector2i(WORLD - 6, rnd(WORLD - 6) + 3)
	if rnd(2) == 0:
		return Vector2i(3 if rnd(2) == 0 else WORLD - 6, rnd(WORLD - 6) + 3)
	return Vector2i(rnd(WORLD - 6) + 3, 3 if rnd(2) == 0 else WORLD - 6)


## Campaign::create_lair: Fryhtan lairs over the map, each with an enslaved
## village, some with special buildings, and free villages between them.
func create_lair(cnid: int, nid: int, lairs: int, indep: int, specials: int, combat := 0) -> void:
	var n := g.nation(nid)
	for p in _spread(20):
		var at := _loc(p.x, p.y)
		if lairs > 0:
			var lvl := combat + rnd(30) - 15 if combat > 0 else 30 + d * 10
			var species: String = n.monster_code if rnd(2) == 0 else Defs.monsters[rnd(Defs.monsters.size())]["unit"]
			var hp := float(Defs.unit_types.get(species, {}).get("hp", 300))
			lvl = clampi(int(lvl * STD_MONSTER_HP / maxf(1.0, hp)), 20, 100)
			var f := create_monster_lair(at, nid, Defs.MAX_SOLDIER / 2 + rnd(Defs.MAX_SOLDIER / 4), lvl, species)
			if f == null:
				continue
			var race: String = g.player().race if rnd(2) == 0 and not g.player().is_fryhtan else Defs.races[rnd(Defs.races.size())]["code"]
			create_slave_town(f, race)
			lairs -= 1
			if specials > 0:
				create_monster_special_firm(f)
				specials -= 1
		elif indep > 0:
			create_independent_town(at, Defs.races[rnd(Defs.races.size())]["code"], 30 + rnd(30), 60 + rnd(40))
			indep -= 1
	g.update_links()


## Campaign::create_monster_special_firm: the Fryhtan kingdom learns its special
## buildings and puts one up by the lair (never a Fortress).
func create_monster_special_firm(lair: Firm) -> Firm:
	var nid := lair.nation_id
	var n := g.nation(nid)
	for t in Defs.FRYHTAN_TECHS:
		if t.has("firm"):
			n.tech[t["code"]] = maxi(1, n.tech_level(t["code"]))
	var kinds: Array = Defs.FRYHTAN_FIRMS.filter(func(code): return code != "WLISHORR")
	if g.firms.filter(func(f): return f.nation_id == nid and f.code == "ALCHEMY").size() >= 1:
		kinds.erase("ALCHEMY")
	if g.firms.filter(func(f): return f.nation_id == nid and f.code == "INCUBAT").size() >= 2:
		kinds.erase("INCUBAT")
	if g.firms.filter(func(f): return f.nation_id == nid and f.code == "ANIMAL").size() >= 2:
		kinds.erase("ANIMAL")
	if kinds.is_empty():
		return null
	return firm_next_to(lair, kinds[rnd(kinds.size())], lair.race, nid)


## Campaign::create_offensive_structure: offensive buildings by the kingdom's
## towns; winning the battle unveils their technology to you.
func create_offensive_structure(nid: int, count: int) -> void:
	var code: String = Defs.OFFENSIVE_FIRMS[rnd(4)]
	_offensive_known(nid, code)
	var tries := 30
	while count > 0 and tries > 0:
		tries -= 1
		var t := king_town(nid) if tries == 29 else town_with_camp(nid, 10)
		if t == null:
			break
		if firm_next_to(t, code, g.nation(nid).race, nid):
			count -= 1


func create_offensive_structure_at(t: Town) -> void:
	if t == null:
		return
	var code: String = Defs.OFFENSIVE_FIRMS[rnd(4)]
	_offensive_known(t.nation_id, code)
	firm_next_to(t, code, g.nation(t.nation_id).race, t.nation_id)


func _offensive_known(nid: int, code: String) -> void:
	g.nation(nid).tech[code] = 1
	c.win_to_unveil_tech = code


## Campaign::add_weapon_to_camp: a war machine stands by the fort.
func add_weapon_to_camp(f: Firm) -> void:
	var n := g.nation(f.nation_id)
	if not Defs.WEAPONS.any(func(w): return n.tech_level(w) > 0):
		n.tech["CATAPULT"] = 1
	var known := Defs.WEAPONS.filter(func(w): return n.tech_level(w) > 0 and Assets.has_sprite(w))
	if known.is_empty():
		return
	var at := g.world.adjacent_to_rect(f.footprint(), f.door())
	g.spawn_unit(known[rnd(known.size())], f.nation_id, at, 30.0)


## Campaign::create_rebel_nation: a rebel kingdom with towns and buildings.
func create_rebel_nation(towns: int, fort_pct: int, strength: int) -> int:
	var used := g.nations.map(func(x): return x.race)
	var free: Array = Defs.races.map(func(r): return r["code"]).filter(func(r): return not r in used)
	if free.is_empty():
		free = Defs.races.map(func(r): return r["code"])
	var nid := new_game_nation(free[rnd(free.size())])
	create_town(nid, towns, fort_pct)
	var t1 := king_town(nid)
	var t2 := town_with_camp(nid, 2)
	create_economic_firm(t1)
	if t2 and t2 != t1:
		create_military_firm(t2, strength)
	set_hostile(g.player_id, nid)
	return nid


# ------------------------------------------------------------ royals ---

## Campaign::create_royal_units: your king and nobles from earlier battles.
func _royals() -> void:
	var p := g.player()
	if p == null or p.is_fryhtan:
		return
	if p.king == null:
		for u in g.units:
			if u.nation_id == p.id and not u.dead and u.is_human() and not u.is_civilian():
				u.rank = Defs.Rank.KING
				p.king = u
				break
	if p.king == null:
		return
	if not c.king.is_empty():
		p.king.unit_name = c.king.get("name", p.king.unit_name)
		p.king.combat = maxf(p.king.combat, float(c.king.get("combat", 60)))
		p.king.leadership = maxf(p.king.leadership, float(c.king.get("leadership", 70)))
	var at := p.king.inside_firm.door() if p.king.inside_firm else p.king.cell()
	for nb in c.nobles:
		var sp: String = nb.get("sprite", Defs.unit_sprite(p.race, "INF"))
		var u := g.spawn_unit(sp, p.id, at + Vector2i(rnd(5) - 2, 2 + rnd(3)), float(nb.get("combat", 50)))
		if u:
			u.unit_name = nb.get("name", u.unit_name)
			u.leadership = float(nb.get("leadership", 40))
			u.rank = Defs.Rank.GENERAL
			u.set_meta("royal", true)


func _add_sites(count: int) -> void:
	var raw_rows: Array = Assets.table("RAW").slice(0, 3)
	if raw_rows.is_empty():
		return
	if not situation.is_empty():
		count = maxi(1, 5 * situation["site_raw"] / 100)
	for i in count:
		g._add_site(raw_rows[rnd(raw_rows.size())], Vector2(-1, -1), 0, 0)


# ============================================================== stages ===

func _player_from(state: int) -> int:
	return add_game_nation(c.western)


func _enemy_of(state: int) -> int:
	var st := c.map.get_state(state)
	return add_game_nation(st.get("nation", 0)) if not st.is_empty() else 0


## The usual layout of your provinces: towns spread over the map, the first
## with a full fort (stage 1, 5, 6, 9, 12, 21 create_town).
func _player_towns(count: int, same_race: bool, soldiers_fn: Callable) -> void:
	var added := 0
	for p in _spread(13):
		if added >= count:
			break
		if create_nation_town(g.player_id, _loc(p.x, p.y), true, same_race, soldiers_fn.call(added)):
			added += 1
	g.update_links()


func _full_then_half(i: int) -> int:
	return Defs.MAX_SOLDIER if i == 0 else Defs.MAX_SOLDIER / 2 + rnd(Defs.MAX_SOLDIER / 2) + 1


func _stage_1() -> void:
	var p := _player_from(c.target_state)
	var m := _enemy_of(c.attacker_state)
	_player_towns(4 + rnd(2), true, _full_then_half)
	create_firms(p)
	create_troop(m, [6, 10, 22, 31, 42][d - 1])
	init_player_resource(30)
	init_nation_resource(m, 20)
	set_hostile(p, m)


func _stage_2() -> void:
	Assets.load_rocks()
	var p := _player_from(c.target_state)
	var m := _enemy_of(c.attacker_state)
	# a mountain range with two passes splits your land from the Fryhtans'
	var horizontal := rnd(2) == 0
	var low_side := rnd(2) == 0
	var wall := 70 if low_side else 30
	vars["edge"] = (4 if low_side else 3) if horizontal else (2 if low_side else 1)
	var gap1 := 33 + rnd(20) - 10
	var gap2 := 66 + rnd(20) - 10
	for i in 100:
		if (i >= gap1 and i <= gap1 + 20) or (i >= gap2 and i <= gap2 + 20):
			continue
		for k in 3:
			var cell := _loc(wall + k, i) if horizontal else _loc(i, wall + k)
			var ri := g._pick_rock("R", 1, 2, cell)
			if ri >= 0:
				g._try_add_rock(ri, cell)
	var towns := 5 + rnd(3)
	var lairs := 3
	for pt in _spread(13):
		var mine_side: bool
		if horizontal:
			mine_side = pt.x <= 70 if low_side else pt.x >= 30
		else:
			mine_side = pt.y <= 70 if low_side else pt.y >= 30
		if mine_side:
			if towns > 0 and create_nation_town(p, _loc(pt.x, pt.y), true):
				towns -= 1
		elif lairs > 0 and create_monster_lair(_loc(pt.x, pt.y), m, Defs.MAX_SOLDIER, 25 + d * 5):
			lairs -= 1
	g.update_links()
	create_firms(p)
	vars["rebel_count"] = maxi(1, d - 1)
	vars["next_rebel"] = 30 + rnd(30)
	vars["defect_count"] = maxi(1, d / 2)
	vars["next_defect"] = 30 + rnd(30)
	vars["reinforce"] = [10, 25, 50, 85, 130][d - 1]
	vars["next_reinforce"] = (Campaign.MAX_DIFFICULTY - d + 1) * 20
	init_player_resource(60)
	init_nation_resource(m, 50)
	g.goals.win.append(_cond(Goals.KILL_MONSTER_SCORE, "Reach a Fryhtan battling score of %d" % c.stage_vars.get("kill_score", 0), c.stage_vars.get("kill_score", 0)))
	set_hostile(p, m)


func _stage_3() -> void:
	_situation(rnd(6) + 1)
	var p := _player_from(c.target_state)
	var towns := 10 + rnd(3)
	var indep := 3 + rnd(3)
	var pts := _spread(30)
	for i in pts.size():
		var at := _loc(pts[i].x, pts[i].y)
		if towns > 0:
			if create_nation_town(p, at, (pts.size() - i) % 3 == 0):
				towns -= 1
		elif indep > 0:
			create_independent_town(at, Defs.races[rnd(Defs.races.size())]["code"], 30 + rnd(30), 60 + rnd(40))
			indep -= 1
	g.update_links()
	create_firms(p)
	vars["rebel_count"] = 1 + d
	vars["next_rebel"] = 0
	init_player_resource(50)
	_reset_win()
	g.goals.win.append(_cond(Goals.REACH_MILITARY, "Reach a military score of 300", 300, 30))
	g.goals.win.append(_cond(Goals.REACH_ECONOMY, "Reach an economic score of 300", 300, 30))
	g.goals.require_all = true


func _stage_4() -> void:
	var p := _player_from(c.attacker_state)
	var e := _enemy_of(c.target_state)
	create_town(e, 5 + rnd(3), 50)
	create_firms(e)
	for t in g.towns:
		if t.nation_id == e:
			t.race = g.player().race    # the defected province's people are your own
	create_troop(p, 65 - d * 10, 65 - d * 5)
	vars["rebel_count"] = 0
	vars["next_rebel"] = 90 + rnd(60)
	init_player_resource(40)
	init_nation_resource(e, 35)
	set_hostile(p, e)
	for t in g.towns:
		if t.nation_id == e and rnd(2) == 0:
			g.reveal_area(p, Vector2i(t.center_loc()), 8)


func _stage_5() -> void:
	_situation(rnd(6) + 1)
	var p := _player_from(c.target_state)
	var m := _enemy_of(c.attacker_state)
	_player_towns(6 + rnd(3), false, _full_then_half)
	_firms_with_extras(p)
	create_troop(m, 5 + d * 10)
	vars["reinforce"] = [10, 20, 40, 70, 90][d - 1]
	vars["next_reinforce"] = (Campaign.MAX_DIFFICULTY - d + 2) * 30
	init_player_resource(65)
	init_nation_resource(m, 40)
	set_hostile(p, m)


## stage 5 and 12: the first two buildings plus one or two more of either kind.
func _firms_with_extras(p: int) -> void:
	create_firms(p, false)
	for i in 1 + rnd(2):
		var t := town_with_camp(p, 2)
		if t == null:
			break
		var economic: bool = rnd(situation["economy"] + situation["military"]) < situation["economy"] if not situation.is_empty() else rnd(2) == 0
		if economic:
			create_economic_firm(t)
		else:
			create_military_firm(t, 30 + rnd(30))


func _stage_6() -> void:
	_std_situation()
	situation["population"] = 80 + rnd(20)
	situation["town_loyalty"] = 80 + rnd(20)
	situation["unit_loyalty"] = 80 + rnd(20)
	var p := _player_from(c.target_state)
	var m := _enemy_of(c.attacker_state)
	_player_towns(5 + rnd(2), false, func(_i): return Defs.MAX_SOLDIER / 4 + rnd(Defs.MAX_SOLDIER / 4) + 1)
	create_economic_firm(king_town(p))
	create_troop(m, d * 7, 40 + d * 5)
	vars["reinforce"] = [8, 16, 30, 50, 80][d - 1]
	vars["next_reinforce"] = (Campaign.MAX_DIFFICULTY - d + 1) * 30
	init_player_resource(70)
	init_nation_resource(m, 50)
	set_hostile(p, m)


func _stage_7() -> void:
	var p := _player_from(c.attacker_state)
	var m := _enemy_of(c.target_state)
	plot_vars["enemy"] = m
	create_lair(c.cur_monster, m, 5 + rnd(2), 0, 0)
	create_troop(p, 33 - d * 3, 80)
	init_player_resource(30)
	init_nation_resource(m, 30)
	set_hostile(p, m)
	vars["free_villages"] = true


func _stage_8() -> void:
	var p := _player_from(c.attacker_state)
	var m := _enemy_of(c.target_state)
	plot_vars["enemy"] = m
	create_lair(c.cur_monster, m, 6 + rnd(3), 6 + rnd(3), 3 + rnd(3))
	create_troop(p, 56 - d * 6, 80)
	init_player_resource(40)
	init_nation_resource(m, 40)
	set_hostile(p, m)


func _stage_9() -> void:
	var p := _player_from(c.target_state)
	var e := _enemy_of(c.attacker_state)
	_player_towns(4 + rnd(2), true, _full_then_half)
	create_independent_towns(4 + rnd(3))
	create_firms(p)
	create_troop(e, 10 + d * 12)
	create_wagon(e, 10 + d * 15 + rnd(10), true)
	vars["rebel_count"] = rnd(d / 2)
	vars["next_rebel"] = rnd(300)
	vars["defect_count"] = rnd(d / 2)
	vars["next_defect"] = rnd(300)
	vars["enemy_attack"] = e
	init_player_resource(50)
	init_nation_resource(e, 60)
	set_hostile(p, e)


func _stage_10() -> void:
	var p := _player_from(c.attacker_state)
	var m := _enemy_of(c.target_state)
	plot_vars["enemy"] = m
	create_lair(c.cur_monster, m, 5 + rnd(2), 0, 0)
	create_troop(p, 65 - d * 5, 75)
	vars["reinforce"] = 1
	vars["enemy_attack"] = m
	init_player_resource(40)
	init_nation_resource(m, 40)
	set_hostile(p, m)


func _stage_11() -> void:
	var p := _player_from(c.attacker2_state)
	var ally := _enemy_of(c.attacker_state)
	var m := _enemy_of(c.target_state)
	plot_vars["enemy"] = m
	set_allied(p, ally)
	set_hostile(p, m)
	set_hostile(ally, m)
	create_lair(c.cur_monster if c.cur_monster != c.map.get_state(c.attacker_state).get("nation", 0) else c.target_monster, m, 8 + rnd(2), 0, 5 + rnd(2), 54 + d * 6)
	create_troop(ally, 55 - d * 5, 50 + rnd(20))
	create_troop(p, 55 - d * 5, 60 + rnd(10))
	init_player_resource(40)
	init_nation_resource(ally, 40)
	init_nation_resource(m, 70)
	g.goals.win.append(_cond(Goals.DEFEAT_KINGDOM, "Destroy the enemy Fryhtan kingdom", 0, 0, m))
	vars["ally"] = ally


func _stage_12() -> void:
	_situation(rnd(6) + 1)
	var p := _player_from(c.target_state)
	var m := _enemy_of(c.attacker_state)
	_player_towns(8 + rnd(3), false, func(i): return Defs.MAX_SOLDIER / 4 + rnd(Defs.MAX_SOLDIER / 4) + 1 if i % 2 == 0 else Defs.MAX_SOLDIER / 2 + rnd(Defs.MAX_SOLDIER / 2) + 1)
	_firms_with_extras(p)
	create_troop(m, d * 15)
	vars["reinforce"] = d * 10
	vars["next_reinforce"] = (Campaign.MAX_DIFFICULTY - d + 1) * 30
	vars["enemy_attack"] = m
	init_player_resource(65)
	init_nation_resource(m, 80)
	set_hostile(p, m)


func _stage_13() -> void:
	var p := _player_from(c.attacker_state)
	var e := _enemy_of(c.attacker2_state)
	var m := _enemy_of(c.target_state)
	plot_vars["enemy"] = m
	set_hostile(p, m)
	set_allied(p, e)
	set_hostile(e, m)
	create_lair(c.cur_monster, m, 6 + rnd(3), 6 + rnd(3) if rnd(2) == 0 else 0, rnd(5) if rnd(2) == 0 else 0)
	create_troop(p, 55 - d * 6)
	create_troop(e, 55 - d * 6)
	init_player_resource(40)
	init_nation_resource(e, 40)
	init_nation_resource(m, 50)
	g.goals.win.append(_cond(Goals.DEFEAT_KINGDOM, "Destroy the Fryhtan kingdom", 0, 0, m))


func _deep_lairs(m: int, lairs: int, specials: int, combat := 0) -> void:
	create_lair(c.cur_monster, m, lairs, 6 + rnd(3) if rnd(2) == 0 else 0, specials, combat)


func _stage_14() -> void:
	var p := _player_from(c.attacker_state)
	var m := _enemy_of(c.target_state)
	plot_vars["enemy"] = m
	_deep_lairs(m, 8 + rnd(3), 5 + rnd(2), 55 + d * 5)
	create_troop(p, 66 - d * 6, 50 + rnd(20))
	init_player_resource(40)
	init_nation_resource(m, 50)
	set_hostile(p, m)


func _stage_15() -> void:
	var p := _player_from(c.attacker_state)
	var m := _enemy_of(c.target_state)
	_deep_lairs(m, 6 + rnd(2), 4 + rnd(2))
	create_troop(p, 44 - d * 4)
	g.nation(m).tech[c.mega_tech] = 1
	vars["mega_holder"] = m
	init_player_resource(50)
	init_nation_resource(m, 60)
	set_hostile(p, m)
	_reset_win()
	g.goals.win.append(_cond(Goals.ACQUIRE_TECH, "Capture the plans of the %s: slay the Fryhtan king who holds them" % Defs.tech_def(c.mega_tech).get("name", "mega weapon"), 0, 0, c.mega_tech))


func _stage_16() -> void:
	var p := _player_from(c.attacker_state)
	var m := _enemy_of(c.target_state)
	create_lair(c.cur_monster, m, 4 + d + rnd(2), 6 + rnd(3) if rnd(2) == 0 else 0, 2 + rnd(2) + d / 2, 45 + d * 5)
	create_troop(p, 46 - d * 6)
	if c.mega_tech != "":
		g.player().tech[c.mega_tech] = 1
		create_troop(p, 13 - d, 0, c.mega_tech, true)
	init_player_resource(70)
	init_nation_resource(m, 50)
	set_hostile(p, m)


func _stage_17() -> void:
	var p := _player_from(c.attacker_state)
	var m := _enemy_of(c.target_state)
	plot_vars["enemy"] = m
	_deep_lairs(m, 9 + rnd(3), 7 + rnd(2), 55 + d * 5)
	create_troop(p, 100 - d * 6)
	init_player_resource(40)
	init_nation_resource(m, 40)
	set_hostile(p, m)


func _stage_18() -> void:
	var p := _player_from(c.attacker_state)
	var e := _enemy_of(c.attacker2_state)
	var m := _enemy_of(c.target_state)
	plot_vars["enemy"] = m
	set_hostile(p, m)
	set_allied(p, e)
	set_hostile(e, m)
	_deep_lairs(m, 10 + rnd(3), 7 + rnd(2))
	create_troop(p, 70 - d * 5)
	create_troop(e, 70 - d * 5)
	init_player_resource(40)
	init_nation_resource(e, 40)
	init_nation_resource(m, 60)


func _attack_east_base(e: int, towns: int, fort_pct: int, combat := 0) -> void:
	create_town(e, towns, fort_pct, combat)
	create_firms(e)


func _stage_19() -> void:
	var p := _player_from(c.attacker_state)
	var e := _enemy_of(c.target_state)
	_attack_east_base(e, 5 + rnd(3), 70)
	if rnd(2) == 0:
		create_offensive_structure(e, 1 + d / 2)
	create_troop(p, 86 - d * 6)
	init_player_resource(50)
	init_nation_resource(e, 60)
	set_hostile(p, e)


## Stage 20 and 23: the Eastern Empire either fills its forts with war machines
## or has a stronger economy.
func _east_situation(e: int, rich: int) -> void:
	var n := g.nation(e)
	var t1 := king_town(e)
	if rnd(2) == 0:
		if t1:
			create_work_firm(t1, "WAR")
		for f in g.firms.filter(func(x): return x.nation_id == e and x.code in Firm.MILITARY_FIRMS):
			for j in maxi(0, Defs.MAX_SOLDIER - f.soldiers.size() - rnd(3)):
				add_weapon_to_camp(f)
		n.cash += 1000.0 + 1000.0 * d + rich
	else:
		var t2 := town_with_camp(e, 2)
		if t2:
			create_economic_firm(t2)
		n.cash += 2000.0 + 2000.0 * d + rich * 2


func _stage_20() -> void:
	var p := _player_from(c.attacker_state)
	var e := _enemy_of(c.target_state)
	_attack_east_base(e, 5 + rnd(3), 90)
	_east_situation(e, 0)
	create_offensive_structure(e, d)
	create_troop(p, 86 - d * 6)
	init_player_resource(50)
	init_nation_resource(e, 70)
	set_hostile(p, e)


func _stage_21() -> void:
	var p := _player_from(c.target_state)
	var k := _enemy_of(c.attacker_state)
	_player_towns(4 + rnd(2), true, _full_then_half)
	create_independent_towns(4 + rnd(3))
	create_firms(p)
	create_troop(k, 15 + d * 15)
	create_wagon(k, 10 + d * 20, true)
	vars["rebel_count"] = rnd(d / 2)
	vars["next_rebel"] = rnd(300)
	vars["enemy_attack"] = k
	init_player_resource(50)
	init_nation_resource(k, 80)
	set_hostile(p, k)


func _stage_22() -> void:
	var p := _player_from(c.attacker_state)
	var k := _enemy_of(c.target_state)
	create_town(k, 7 + rnd(3), 70)
	g.update_links()
	var t1 := king_town(k)
	create_economic_firm(t1)
	create_military_firm(town_with_camp(k, 2), 70)
	create_military_firm(town_with_camp(k, 2), 50)
	create_offensive_structure(k, d)
	create_troop(p, 55 - d * 5)
	init_player_resource(40)
	init_nation_resource(k, 60)
	set_hostile(p, k)


func _stage_23() -> void:
	var p := _player_from(c.attacker_state)
	var e := _enemy_of(c.target_state)
	create_town(e, 8 + rnd(2), 100, 40 + d * 10)
	g.update_links()
	var t1 := king_town(e)
	var t2 := town_with_camp(e, 2)
	create_economic_firm(t1)
	create_offensive_structure_at(t1)
	if t2 and t2 != t1:
		create_military_firm(t2)
		create_offensive_structure_at(t2)
	_east_situation(e, 1300)
	for lvl in [3, 4, 5]:
		if d >= lvl:
			var t := town_with_camp(e, 2)
			if t:
				t.race = g.nation(e).race
				if lvl == 4:
					create_economic_firm(t)
				else:
					create_military_firm(t)
				create_offensive_structure_at(t)
	create_offensive_structure(e, 1 + d / 2 + rnd(2))
	create_troop(p, 86 - d * 6)
	init_player_resource(50)
	init_nation_resource(e, 100)
	set_hostile(p, e)


func _stage_24() -> void:
	var p := _player_from(c.attacker_state)
	var e := _enemy_of(c.attacker2_state)
	var m := _enemy_of(c.target_state)
	plot_vars["enemy"] = m
	set_hostile(p, m)
	set_allied(p, e)
	set_hostile(e, m)
	create_lair(c.cur_monster, m, 6 + rnd(3), 6 + rnd(3) if rnd(2) == 0 else 0, 3 + rnd(2))
	create_troop(p, 60 - d * 6)
	create_troop(e, 60 - d * 6, 0, "", true)
	init_player_resource(50)
	init_nation_resource(e, 40)
	init_nation_resource(m, 40)
	g.goals.win.append(_cond(Goals.DEFEAT_KINGDOM, "Destroy the Fryhtan kingdom", 0, 0, m))


func _stage_25() -> void:
	_situation(6)
	var p := _player_from(c.target_state)
	create_town(p, 4 + rnd(2), 50)
	g.update_links()
	create_military_firm(king_town(p), 80)
	var t2 := town_with_camp(p, 2)
	if t2:
		create_military_firm(t2, 80)
	for i in d:
		create_rebel_nation(2, 50, 20 + d * 10)
	init_player_resource(50)
	general_defect_form_new_nation(p)
	g.goals.win.append(_cond(Goals.REACH_TOTAL, "Reach a total score of %d" % c.stage_vars.get("score", 0), c.stage_vars.get("score", 0), c.stage_vars.get("years", 0)))
	g.goals.require_all = true


func _stage_26() -> void:
	_std_situation()
	situation["military"] = 45 - d * 5
	situation["cash"] = 25
	var p := _player_from(c.target_state)
	create_independent_towns(3 + rnd(2))
	create_town(p, 5 + rnd(3), 50)
	create_firms(p)
	vars["rebel_count"] = maxi(1, d - 1)
	vars["next_rebel"] = 30 + rnd(30)
	vars["new_nations"] = 5
	vars["thin_inns"] = true
	init_player_resource(25)
	_reset_win()
	var lead: int = c.stage_vars.get("leadership", 90)
	g.goals.win.append(_cond(Goals.TRAIN_10_GENERAL, "Train ten generals of leadership %d" % lead, lead, c.stage_vars.get("years", 0)))


func _stage_27() -> void:
	_situation(rnd(6) + 1)
	var p := _player_from(c.target_state)
	create_independent_towns(4 + rnd(3))
	create_town(p, 4, 100)
	g.update_links()
	create_economic_firm(king_town(p))
	var t2 := town_with_camp(p, 2)
	if t2:
		create_military_firm(t2, 100)
	init_player_resource(50)
	_reset_win()
	var pop: int = c.stage_vars.get("population", 300)
	g.goals.win.append(_cond(Goals.REACH_POPULATION, "Reach a population of %d" % pop, pop, c.stage_vars.get("years", 0)))
	general_defect_form_new_nation(p)
	# an Egyptian kingdom that knows its Seat of Power
	var eg := new_game_nation("EGYPTIAN")
	create_town(eg, 2, 100)
	g.update_links()
	create_economic_firm(king_town(eg))
	var et := town_with_camp(eg, 2)
	if et:
		create_military_firm(et, 30 + d * 10)
	g.nation(eg).known_gods["EGYPTIAN"] = true


func _stage_28() -> void:
	var p := _player_from(c.target_state)
	create_independent_towns(5 + rnd(3))
	create_troop(p, 16, 50)
	var n := g.player()
	if n.king:
		for i in 25 + rnd(6):
			g.spawn_unit(Defs.unit_sprite(n.race, "CIV"), p, n.king.cell() + Vector2i(i % 6, 2 + i / 6), 10.0)
	init_player_resource(60)
	var pop: int = c.stage_vars.get("population", 300)
	var eco: int = c.stage_vars.get("economy", 300)
	var yrs: int = c.stage_vars.get("years", 0)
	g.goals.win.append(_cond(Goals.REACH_POPULATION, "Reach a population of %d" % pop, pop, yrs))
	g.goals.win.append(_cond(Goals.REACH_ECONOMY, "Reach an economic score of %d" % eco, eco, yrs))
	g.goals.require_all = true


# ============================================================= next day ===

## Called every day of the battle (CampaignEastWest::next_day).
func next_day() -> void:
	if g == null or g.over:
		return
	_plot_next_day()
	var p := g.player_id
	match stage:
		2:
			if _should_rebel(30):
				town_defect(p)
			if _should_defect(30):
				general_defect_form_new_nation(p)
			var m := _gid(c.attacker_state)
			if _alive(m):
				monster_reinforcement_to_lair(vars["edge"])
				monster_reinforcement(m, vars["edge"])
		3:
			if g.day >= vars["next_rebel"] and vars["rebel_count"] > 0:
				vars["rebel_count"] -= 1
				vars["next_rebel"] = g.day + 30 + rnd(30)
				town_defect(p, 0)
				if vars["rebel_count"] % 3 == 0 or (rnd((Campaign.MAX_DIFFICULTY - d) / 2 + g.nations.size() - 1) == 0 and g.day > 90):
					rebel_form_nation()
		4:
			var e := _gid(c.target_state)
			if g.day >= vars["next_rebel"] and _alive(e):
				var mine := Goals.total_score(g, g.player())
				var theirs := maxi(1, Goals.total_score(g, g.nation(e)))
				if 5 * mine / theirs > vars["rebel_count"] or d == 1:
					var t := town_defect(e, p)
					if t:
						t.loyalty = 80.0 - d * 5
						t.bonus_loyalty = 30.0 - d * 5
					vars["rebel_count"] += 1
				vars["next_rebel"] = g.day + 60 + rnd(60)
		5, 12:
			var m := _gid(c.attacker_state)
			if _alive(m):
				think_enemy_attack(m, p)
				monster_reinforcement_to_lair()
				monster_reinforcement(m)
		6:
			var m := _gid(c.attacker_state)
			if _alive(m):
				think_enemy_attack(m, p)
				monster_reinforcement_to_lair()
				_hero()
		7:
			for t in g.towns:
				if t.nation_id == 0 and not t.dead and t.tribute_to() == 0:
					t.surrender(p)     # freed villages join you at once
		9, 21:
			var e: int = vars.get("enemy_attack", 0)
			if _alive(e):
				think_enemy_attack(e, p)
				if _should_rebel(150):
					town_defect(p)
				if stage == 9 and _should_defect(300):
					general_defect_form_new_nation(p)
		10:
			var m: int = vars.get("enemy_attack", 0)
			if _alive(m):
				if vars["reinforce"] > 0 and g.day % 5 == 0 and Goals.score(g, g.nation(m), 2) <= 50:
					create_troop(m, 10 + d * 10)
					vars["reinforce"] = 0
				think_enemy_attack(m, p)
		15:
			var m: int = vars.get("mega_holder", 0)
			if _alive(m) and c.mega_tech != "":
				g.nation(m).tech[c.mega_tech] = 1
		26:
			if _should_rebel(30):
				town_defect(p)
			if rnd(60 + g.nations.size() * 100) == 0 and g.nations.filter(func(n): return n.alive).size() < d + 1 and vars.get("new_nations", 0) > 0:
				vars["new_nations"] -= 1
				rebel_form_nation()
			if g.day % 15 == 0:
				for f in g.firms:
					if f.code == "INN" and not f.heroes.is_empty():
						f.heroes.remove_at(rnd(f.heroes.size()))
						break
		28:
			if rnd((12 - d * 2 + g.nations.size() * 2) * 15) == 0:
				rebel_form_nation()


func _gid(state: int) -> int:
	return gn.get(c.map.get_state(state).get("nation", -1), 0)


func _alive(nid: int) -> bool:
	var n := g.nation(nid)
	return n != null and n.alive


func _should_rebel(interval: int) -> bool:
	if vars["rebel_count"] <= 0 or g.day < vars["next_rebel"]:
		return false
	vars["rebel_count"] -= 1
	vars["next_defect"] += rnd(interval)
	vars["next_rebel"] = g.day + interval + rnd(interval * 2)
	return true


func _should_defect(interval: int) -> bool:
	if vars["defect_count"] <= 0 or g.day < vars["next_defect"] or g.nations.size() >= Campaign.MAX_NATION + 2:
		return false
	vars["defect_count"] -= 1
	vars["next_defect"] = g.day + interval + rnd(interval * 2)
	vars["next_rebel"] = g.day + interval + rnd(interval * 2)
	return true


## Campaign::town_defect: a town (preferably without a camp of its own) rebels,
## joining another human kingdom or becoming independent.
func town_defect(nid: int, to := 0) -> Town:
	var towns := g.towns.filter(func(t): return t.nation_id == nid and not t.dead and t.population > 0)
	if towns.is_empty():
		return null
	var free := towns.filter(func(t): return not t.has_linked_camp(nid))
	var pick: Town = (free if not free.is_empty() else towns)[rnd((free if not free.is_empty() else towns).size())]
	if to == 0 and rnd(2) == 0:
		var others := g.nations.filter(func(n): return n.alive and n.id != nid and not n.is_fryhtan)
		if not others.is_empty():
			to = others[rnd(others.size())].id
	pick.surrender(to)
	if nid == g.player_id:
		g.notify("%s has rebelled against you!" % pick.town_name, pick.center_loc())
	return pick


## Campaign::general_defect_form_new_nation: a general takes his fort and the
## towns around it and proclaims a kingdom of his own.
func general_defect_form_new_nation(nid: int) -> int:
	var forts := g.firms.filter(func(f): return f.nation_id == nid and f.code in Firm.MILITARY_FIRMS and f.overseer != null \
		and f.overseer.is_human() and f.overseer.rank != Defs.Rank.KING)
	if forts.is_empty():
		return 0
	var f: Firm = forts[rnd(forts.size())]
	var gen := f.overseer
	var nn := new_game_nation(gen.race)
	var n := g.nation(nn)
	n.name = "%s's Kingdom" % gen.unit_name.get_slice(" ", 0)
	gen.rank = Defs.Rank.KING
	n.king = gen
	n.cash = 1000.0 + d * 500
	f.change_nation(nn)
	for t in f.linked_towns:
		if t.nation_id == nid:
			t.surrender(nn)
			t.bonus_loyalty = 30.0
			for lf in t.linked_firms:
				if lf.nation_id == nid and not lf.code in Firm.MILITARY_FIRMS:
					lf.change_nation(nn)
	set_hostile(nid, nn)
	if nid == g.player_id:
		g.notify("General %s has rebelled and founded a kingdom of his own!" % gen.unit_name, f.center_loc())
	g.update_links()
	return nn


## Campaign::rebel_form_nation: an independent town forms a new kingdom.
func rebel_form_nation() -> int:
	if g.nations.size() >= Campaign.MAX_NATION + 3:
		return 0
	var indep := g.towns.filter(func(t): return t.nation_id == 0 and not t.dead and t.population >= 10)
	if indep.is_empty():
		return 0
	var t: Town = indep[rnd(indep.size())]
	var nn := new_game_nation(t.race)
	var n := g.nation(nn)
	n.cash = 3000.0 + d * 3000 + rnd(3000)
	n.food = 1500.0 + d * 1500 + rnd(1500)
	t.surrender(nn)
	var k := g.spawn_unit(Defs.unit_sprite(t.race, "INF"), nn, Vector2i(t.x1, t.y1 + Defs.TOWN_SIZE + 1), 50.0)
	if k:
		k.rank = Defs.Rank.KING
		k.leadership = 50.0 + rnd(30)
		n.king = k
	for i in 4:
		g.spawn_unit(Defs.unit_sprite(t.race, "INF"), nn, Vector2i(t.x1 + 1 + i, t.y1 + Defs.TOWN_SIZE + 1), 30.0 + rnd(20))
	set_hostile(g.player_id, nn)
	g.notify("%s has risen and founded a new kingdom." % t.town_name, t.center_loc())
	return nn


## Campaign::think_enemy_attack: an army without a base sends its generals and
## their men against a town of yours.
func think_enemy_attack(attacker: int, target: int, freq := 50) -> void:
	var interval := maxi(1, [150, 80, 30, 10, 5][d - 1] * (110 - freq) / 50)
	if (g.day + 1) % interval != 0:
		return
	if g.firms.any(func(f): return f.nation_id == attacker and not f.under_construction and (f.code in Firm.MILITARY_FIRMS or f.code == "LAIR")):
		return
	var towns := g.towns.filter(func(t): return t.nation_id == target and not t.dead)
	if towns.is_empty():
		return
	var tgt: Town = towns[rnd(towns.size())]
	for u in g.units:
		if u.nation_id == attacker and not u.dead and u.inside_firm == null and u.rank >= Defs.Rank.GENERAL and u.order == Unit.Order.IDLE:
			u.order_attack(tgt)
			for v in g.units:
				if v.nation_id == attacker and not v.dead and v.inside_firm == null and v.order == Unit.Order.IDLE and v.center_loc().distance_to(u.center_loc()) < 8.0 and v.can_attack():
					v.order_attack(tgt)


## Campaign::monster_reinforcement: more Fryhtans arrive at the map edge.
func monster_reinforcement(nid: int, edge := 0) -> void:
	if vars["reinforce"] <= 0 or g.day < vars["next_reinforce"]:
		return
	var n := mini(3 + d * 3 + rnd(5), vars["reinforce"])
	var made := create_unit_group(nid, n, "", false, Vector2i(-1, -1), edge)
	vars["reinforce"] = maxi(0, vars["reinforce"] - made.size())
	vars["next_reinforce"] = g.day + (Campaign.MAX_DIFFICULTY - d + 1) * 60
	var towns := g.towns.filter(func(t): return t.nation_id == g.player_id and not t.dead)
	if not towns.is_empty() and not made.is_empty():
		var c0: Vector2 = made[0].center_loc()
		towns.sort_custom(func(a, b): return a.center_loc().distance_to(c0) < b.center_loc().distance_to(c0))
		for u in made:
			u.order_attack(towns[0])


## Campaign::monster_reinforcement_to_lair: a lair with room is filled up by
## Fryhtans marching in from the edge.
func monster_reinforcement_to_lair(edge := 0) -> void:
	if vars["reinforce"] <= 0 or g.day % 30 != 0:
		return
	for f in g.firms:
		if f.code == "LAIR" and not f.under_construction and f.nation_id != g.player_id and f.nation_id != GameObj.MONSTER_NATION \
				and f.capacity() - f.soldiers.size() >= 8:
			var n := mini(f.capacity() - f.soldiers.size() - rnd(5), vars["reinforce"])
			var made := create_unit_group(f.nation_id, n, f.monster_code, false, Vector2i(-1, -1), edge)
			vars["reinforce"] = maxi(0, vars["reinforce"] - made.size())
			for u in made:
				if u.rank != Defs.Rank.KING:
					u.rank = Defs.Rank.SOLDIER
					u.order_enter(f)
			vars["next_reinforce"] = g.day + (Campaign.MAX_DIFFICULTY - d + 1) * 60
			return


## Stage 6: a hero appears at the edge to fight for you; his death loses the battle.
func _hero() -> void:
	var h = vars.get("hero")
	if h != null:
		if not is_instance_valid(h) or h.dead or h.nation_id != g.player_id:
			vars["hero"] = null
		return
	if vars.get("hero_made", false):
		return
	vars["hero_made"] = true
	var p := g.player()
	var at := _edge_loc(0)
	var u := g.spawn_unit(Defs.unit_sprite(p.race, "INF"), p.id, at, 100.0)
	if u == null:
		return
	u.unit_name = Defs.random_person_name(p.race, g.rng)
	u.is_hero = true
	u.rank = Defs.Rank.GENERAL
	# stage_6_create_hero: combat and leadership 200 to 300 (max 300)
	u.combat = 200.0 + rnd(100)
	u.leadership = 100.0
	u.max_hp *= u.combat / 100.0
	u.hp = u.max_hp
	if Items.TABLE.has(Items.LEADER_ITEM):
		u.item_id = Items.LEADER_ITEM
	vars["hero"] = u
	g.goals.lose.append(_cond(Goals.KILL_UNIT, "%s must survive" % u.unit_name, 0, 0, u))
	g.notify("The hero %s has come to fight for you. He must not fall!" % u.unit_name, u.center_loc())


## Saved with the game, so a battle in progress can be saved and resumed.
func to_dict(id_of: Callable) -> Dictionary:
	var pack := func(dict: Dictionary) -> Dictionary:
		var out := {}
		for k in dict:
			var v = dict[k]
			out[k] = {"obj": id_of.call(v)} if v is Object else v
		return out
	return {"stage": stage, "plot": plot, "plot_vars": pack.call(plot_vars), "vars": pack.call(vars),
		"gn": gn, "last_loc": [last_loc.x, last_loc.y], "situation": situation}


static func restore(campaign: Campaign, d: Dictionary, game: Game, by_id: Dictionary) -> CampaignBattle:
	var b := CampaignBattle.create(campaign)
	b.g = game
	b.stage = int(d.get("stage", campaign.stage_id))
	b.plot = d.get("plot", "")
	var unpack := func(dict: Dictionary) -> Dictionary:
		var out := {}
		for k in dict:
			var v = dict[k]
			if v is Dictionary and v.has("obj"):
				out[k] = by_id.get(int(v["obj"]))
			elif v is float and v == floorf(v):
				out[k] = int(v)
			else:
				out[k] = v
		return out
	b.plot_vars = unpack.call(d.get("plot_vars", {}))
	b.vars = unpack.call(d.get("vars", {}))
	for k in d.get("gn", {}):
		b.gn[int(k)] = int(d["gn"][k])
	var ll: Array = d.get("last_loc", [-1, -1])
	b.last_loc = Vector2i(int(ll[0]), int(ll[1]))
	b.situation = d.get("situation", {})
	return b


## What the campaign needs to know after the battle.
func result_info() -> Dictionary:
	var h = vars.get("hero")
	return {"hero_alive": h != null and is_instance_valid(h) and not h.dead,
		"hero_name": h.unit_name if h != null and is_instance_valid(h) else "",
		"kill_monster_score": int(g.player().kill_monster_score) if g.player() else 0}


# ================================================================ plots ===

## CampaignEastWest::init_random_plot: some battles get a twist ('A' Fryhtan
## battles, 'C' attacks on kingdoms, 'D' defences); one in seven has none.
func _plot_create() -> void:
	var cat := ""
	match stage:
		2, 5, 9, 12, 21:
			cat = "D"
		4, 19, 20, 22, 23:
			cat = "C"
		7, 8, 10, 11, 13, 14, 17, 18, 24:
			cat = "A"
	var counts := {"A": 7, "C": 4, "D": 5}
	if cat == "" or rnd(7) == 0:
		plot = ""
		return
	plot = "%s%d" % [cat, rnd(counts[cat]) + 1]
	if not plot_vars.has("enemy"):
		for n in g.nations:
			if n.id != g.player_id and g.player().relation(n.id) == Defs.Relation.WAR:
				plot_vars["enemy"] = n.id
				break
	var enemy: int = plot_vars.get("enemy", 0)
	match plot:
		"A1":
			# a rebel kingdom that will ally with you once you have slain enough Fryhtans
			var r := new_game_nation(Defs.races[rnd(Defs.races.size())]["code"])
			create_town(r, 2 + rnd(2), 100)
			g.update_links()
			create_military_firm(king_town(r))
			var t2 := town_with_camp(r, 2)
			if t2:
				create_economic_firm(t2)
			if enemy:
				set_hostile(r, enemy)
			plot_vars["rebel"] = r
		"A2":
			# the Fryhtans are rich and learned; three damaged forts of yours stand by villages
			var mn := g.nation(enemy)
			if mn:
				mn.cash += 20000.0
				mn.food += 20000.0
				mn.live_points += 20000.0
				for t in Defs.FRYHTAN_TECHS:
					mn.tech[t["code"]] = mini(t["max"], mn.tech_level(t["code"]) + 1)
			var kc := g.player().king.center_loc() if g.player().king else Vector2(WORLD / 2.0, WORLD / 2.0)
			var cands := g.towns.filter(func(t): return t.nation_id == 0 and t.tribute_to() == 0)
			cands.sort_custom(func(a, b): return a.center_loc().distance_to(kc) < b.center_loc().distance_to(kc))
			for t in cands.slice(0, 3):
				var f := firm_next_to(t, "FORT", g.player().race, g.player_id)
				if f:
					f.hp = f.max_hp * (0.05 + g.rng.randf() * 0.45)
		"A3":
			# a Viking tribe with Seats of Power that turns to you once its Mongol rival is gone
			var vk := new_game_nation("VIKING")
			g.nation(vk).known_gods["VIKING"] = true
			create_town(vk, 3, 100)
			g.update_links()
			var t := town_with_camp(vk, 2)
			if t:
				t.population = Defs.MAX_TOWN_POPULATION
				t.loyalty = 100.0
				create_economic_firm(t)
			for i in 4:
				var tt := town_with_camp(vk, 8)
				if tt:
					firm_next_to(tt, "BASE", "VIKING", vk)
			var mg := new_game_nation("MONGOL")
			create_town(mg, 2 + rnd(2), 100)
			g.update_links()
			create_military_firm(king_town(mg))
			var t2 := town_with_camp(mg, 2)
			if t2:
				create_economic_firm(t2)
			set_hostile(vk, mg)
			if enemy:
				set_hostile(vk, enemy)
				set_hostile(mg, enemy)
			plot_vars["viking"] = vk
			plot_vars["mongol"] = mg
		"A4":
			# Minotauros alchemists guard the mineral deposits
			var mi := new_game_nation("GIANTET", true)
			for code in ["LIVEGOLD", "GOLDLIVE", "MINELIVE", "MINEGOLD"]:
				g.nation(mi).tech[code] = 1
			set_hostile(g.player_id, mi)
			for s in g.sites.duplicate():
				if s.mine != null:
					continue
				var f := g.spawn_firm("ALCHEMY", mi, "GIANTET", Vector2i(s.x1, s.y1), true)
				if f:
					f.alchemy_mode = "MINEGOLD"
					create_monster_lair(Vector2i(s.x1 + 6, s.y1), mi, Defs.MAX_SOLDIER - rnd(Defs.MAX_SOLDIER / 2), 20 + d * 10, "GIANTET")
		"A5":
			# the Fryhtan king is invulnerable while he lives with his Ring; a Bane lies far away
			var mn := g.nation(enemy)
			if mn and mn.king and is_instance_valid(mn.king) and mn.king.item_id == 0:
				mn.king.item_id = Items.REGEN_ITEM
			var kc := g.player().king.cell() if g.player().king else Vector2i(WORLD / 2, WORLD / 2)
			var far := Vector2i(WORLD - kc.x, WORLD - kc.y)
			var bane := Items.bane_for(mn.monster_code) if mn else 0
			if bane > 0:
				g.spawn_treasure(Treasure.Kind.ITEM, bane, Items.random_para(bane, g.rng), g._free_treasure_cell(far))
			if Items.TELEPORT_ITEM > 0:
				g.spawn_treasure(Treasure.Kind.ITEM, Items.TELEPORT_ITEM, Items.random_para(Items.TELEPORT_ITEM, g.rng), g._free_treasure_cell(kc + Vector2i(10, 4)))
			plot_vars["invulnerable_king"] = mn.king if mn else null
		"A6":
			# three populous villages; items that turn a town to you lie nearby
			var indep := g.towns.filter(func(t): return t.nation_id == 0)
			g._shuffle(indep)
			for t in indep.slice(0, 3):
				t.population = mini(Defs.MAX_TOWN_POPULATION, t.population + 20 + rnd(20))
				t.resistance[g.player_id] = minf(100.0, t.resistance_to(g.player_id) + 30.0)
			var kc := g.player().king.cell() if g.player().king else Vector2i(WORLD / 2, WORLD / 2)
			for i in 3:
				if Items.TOWN_CHANGE_ITEM > 0:
					var at := g._free_treasure_cell(kc + Vector2i(10 + i * 6, -6 + i * 6))
					g.spawn_treasure(Treasure.Kind.ITEM, Items.TOWN_CHANGE_ITEM, Items.random_para(Items.TOWN_CHANGE_ITEM, g.rng), at)
		"A7":
			# Carthaginian rebels with elephant cavalry, your allies, surrender to you at reputation 50
			var ca := new_game_nation("CARTH")
			var cn := g.nation(ca)
			cn.tech[Defs.spu_structure_tech("CARTH")] = 1
			cn.tech[Defs.spu_berserk_tech("CARTH")] = 1
			create_town(ca, 2 + rnd(2), 100)
			g.update_links()
			for t in g.towns.filter(func(x): return x.nation_id == ca):
				firm_next_to(t, "STABLE", "CARTH", ca)
			for f in g.firms.filter(func(x): return x.nation_id == ca and x.code == "FORT"):
				for s in f.soldiers:
					if s.race == "CARTH":
						s.sprite_code = "CA_SPU" if Assets.has_sprite("CA_SPU") else s.sprite_code
						s.utype = Defs.unit_types.get(s.sprite_code, s.utype)
			set_allied(g.player_id, ca)
			if enemy:
				set_hostile(ca, enemy)
			plot_vars["carth"] = ca
		"C1", "C2":
			# your men carry items to turn an enemy general (C1) or free an enemy town (C2)
			var item := Items.UNIT_CHANGE_ITEM if plot == "C1" else Items.TOWN_FREE_ITEM
			var n := 3
			for u in g.units:
				if n <= 0 or item <= 0:
					break
				if u.nation_id == g.player_id and u.item_id == 0 and u.is_human() and not u.is_civilian():
					u.item_id = item
					u.item_para = Items.random_para(item, g.rng)
					n -= 1
			if plot == "C1":
				for t in g.towns.filter(func(x): return x.nation_id == 0):
					g.on_town_destroyed(t)
		"C3":
			# spies of yours already serve in the enemy forts
			var prob := 100
			for f in g.firms:
				if f.nation_id == g.player_id or f.nation_id == 0 or not Espionage.is_camp(f) or f.soldiers.is_empty():
					continue
				if rnd(100) < prob:
					var s: Unit = f.soldiers[rnd(f.soldiers.size())]
					if s.is_human():
						s.sleeper_for = g.player_id
						s.set_meta("sleeper_skill", 50 + rnd(40))
						prob -= 10
		"C4":
			# skilled spies near your king, disguised as enemy soldiers
			var kc := g.player().king.cell() if g.player().king else Vector2i(WORLD / 2, WORLD / 2)
			var humans := g.nations.filter(func(n): return n.id != g.player_id and not n.is_fryhtan)
			for i in 4 + rnd(3):
				if humans.is_empty():
					break
				var other: Nation = humans[rnd(humans.size())]
				var u := g.spawn_unit(Defs.unit_sprite(other.race, "INF"), g.player_id, kc + Vector2i(rnd(12) - 6, rnd(12) - 6), 40.0)
				if u:
					u.is_spy = true
					u.spy_skill = 50.0 + rnd(40)
					u.spy_action = "dissent"
		"D1":
			# your treasury is drained and your mines nearly exhausted
			var p := g.player()
			p.cash /= 4.0
			for f in g.firms:
				if f.nation_id == p.id and f.code == "MINE" and f.site:
					f.reserve /= 10.0
					f.site.reserve = f.reserve
		"D2":
			# the invaders have stirred one of your towns to revolt
			for t in g.towns:
				if t.nation_id == g.player_id:
					t.surrender(0)
					break
		"D3":
			pass       # rumours of invisible Fryhtans: they get the Invisibility item each day
		"D4":
			# two teams of your soldiers wait far from your towns
			var far := Vector2i(WORLD / 2, WORLD / 2)
			var best := -1.0
			for k in 60:
				var at := Vector2i(rnd(WORLD - 16) + 8, rnd(WORLD - 16) + 8)
				var sumd := 0.0
				for t in g.towns:
					if t.nation_id == g.player_id:
						sumd += t.center_loc().distance_squared_to(Vector2(at))
				if sumd > best and g.world.is_walkable(at):
					best = sumd
					far = at
			create_unit_group(g.player_id, TEAM, "", false, far)
			create_unit_group(g.player_id, TEAM, "", false, far + Vector2i(0, 5))
		"D5":
			# the Seat of Power of your ancestors: losing it loses the battle
			for k in 100:
				var t := town_with_camp(g.player_id, 8)
				if t == null:
					break
				var f := firm_next_to(t, "BASE", t.race, g.player_id)
				if f:
					g.goals.lose.append(_cond(Goals.DESTROY_FIRM, "Protect the Seat of Power of your ancestors", 0, 0, f))
					break


func _plot_next_day() -> void:
	match plot:
		"A1":
			var r: int = plot_vars.get("rebel", 0)
			if r and _alive(r):
				var p := g.player()
				if p.kill_monster_score >= 100 and p.relation(r) != Defs.Relation.ALLIANCE and not plot_vars.get("a1_allied", false):
					plot_vars["a1_allied"] = true
					set_allied(g.player_id, r)
					g.notify("The %s offers you an alliance against the Fryhtans." % g.nation(r).name, Vector2(-1, -1))
				if p.kill_monster_score >= 300 and p.relation(r) == Defs.Relation.ALLIANCE:
					_surrender_kingdom(r)
					plot_vars["rebel"] = 0
		"A2":
			var mn := g.nation(plot_vars.get("enemy", 0))
			if mn and mn.alive:
				mn.add_cash(10.0 if mn.cash < 1000 else (2.0 if mn.cash < 5000 else 0.0))
				mn.live_points += 10.0 if mn.live_points < 1000 else (2.0 if mn.live_points < 5000 else 0.0)
		"A3":
			var vk: int = plot_vars.get("viking", 0)
			var mg: int = plot_vars.get("mongol", 0)
			if vk and _alive(vk) and not _alive(mg):
				if _alive(plot_vars.get("enemy", 0)):
					if g.player().relation(vk) != Defs.Relation.ALLIANCE and g.day % 15 == 0:
						set_allied(g.player_id, vk)
						g.notify("The Vikings, freed of their Mongol rivals, ally with you.", Vector2(-1, -1))
				else:
					_surrender_kingdom(vk)
					plot_vars["viking"] = 0
		"A5":
			var k = plot_vars.get("invulnerable_king")
			if k != null and is_instance_valid(k) and not k.dead and k.item_id == Items.REGEN_ITEM:
				k.invulnerable_until = maxi(k.invulnerable_until, g.frame + Defs.FRAMES_PER_DAY * 2)
		"A7":
			var ca: int = plot_vars.get("carth", 0)
			if ca and _alive(ca) and g.player().reputation >= 50.0 and g.player().relation(ca) == Defs.Relation.ALLIANCE:
				_surrender_kingdom(ca)
				plot_vars["carth"] = 0
		"D3":
			if Items.INVISIBLE_ITEM > 0 and g.day % 4 == 0:
				for f in g.firms:
					if f.nation_id != g.player_id and f.nation_id > 0 and g.nation(f.nation_id) and g.nation(f.nation_id).is_fryhtan and f.code == "LAIR":
						for u in ([f.overseer] if f.overseer else []) + f.soldiers:
							if u.item_id == 0:
								u.item_id = Items.INVISIBLE_ITEM
								u.item_para = 100


## A kingdom hands itself over to you (TALK_SURRENDER).
func _surrender_kingdom(nid: int) -> void:
	var n := g.nation(nid)
	if n == null:
		return
	for t in g.towns:
		if t.nation_id == nid:
			t.surrender(g.player_id)
	for f in g.firms:
		if f.nation_id == nid:
			f.change_nation(g.player_id)
	for u in g.units:
		if u.nation_id == nid and not u.dead:
			u.nation_id = g.player_id
			if u.rank == Defs.Rank.KING:
				u.rank = Defs.Rank.GENERAL
	n.alive = false
	g.notify("The %s surrenders to you!" % n.name, Vector2(-1, -1))
	g.update_links()
