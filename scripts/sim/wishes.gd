class_name Wishes
extends RefCounted
## The Seat of Power's blessing (of_basew.cpp, FirmBase::invoke_random_effect):
## with the kingdom's prayer points full, the Bless button draws one of the
## original's 23 wishes, weighted by rarity. A wish that finds nothing to do
## halves the points; any other uses them all.

const FULL := 400.0     # MAX_PRAY_POINTS in our kingdom-wide prayer pool

## [id, rarity weight, description] as wish_info_array.
const TABLE := [
	["FINISH_TECH", 90, "Technology breakthrough - complete the current research instantly"],
	["NEW_TECH", 80, "Technology breakthrough - gain a new technology"],
	["NEW_HUMAN", 90, "A veteran human unit comes to serve you"],
	["NEW_MONSTER", 50, "A fryhtan unit comes to serve you"],
	["NEW_SPY", 85, "A veteran spy unit comes to serve you"],
	["NEW_HERO", 80, "A hero comes to serve you"],
	["ITEM", 60, "An item"],
	["CASH", 90, "Cash bonus"],
	["FOOD", 90, "Food bonus"],
	["RAW", 60, "A new mineral deposit with a mine on top of it"],
	["CAPTURE_UNIT", 70, "Convert an enemy unit (except king) to your side"],
	["CAPTURE_CAMP", 40, "Instantly capture an enemy fort or camp"],
	["CAPTURE_TOWN", 40, "Instantly capture an enemy town"],
	["KILL_SPY_BUILDING", 60, "Reveal and kill a few enemy spies in a town or structure of yours"],
	["KILL_SPY_NATION", 40, "Reveal and kill a few enemy spies in your kingdom"],
	["CLEAR_SPY_NATION", 10, "Reveal and kill every enemy spy in your kingdom"],
	["HEAL_BUILDING", 80, "Heal all of your wounded soldiers in a structure"],
	["HEAL_NATION", 10, "Heal all of your wounded soldiers in your kingdom"],
	["LOYALTY_BUILDING_S", 5, "Increase the loyalty of a town or structure by 20-50"],
	["LOYALTY_BUILDING_L", 10, "Increase the loyalty of a town or structure to 100"],
	["LOYALTY_NATION_S", 10, "Increase the loyalty of everybody in your kingdom by 20-50"],
	["LOYALTY_NATION_L", 20, "Increase the loyalty of everybody in your kingdom to 100"],
	["COMBAT_BUILDING", 50, "Increase the combat level of all soldiers in a structure by 30-70"],
]


static func can_wish(f: Firm) -> bool:
	var n := f.nation()
	return f.code == "BASE" and not f.under_construction and n != null and n.prayer_points >= FULL


## The whole wish: draws one (or uses `wish_id`), applies it and returns what
## happened ("" when nothing could be done).
static func invoke(f: Firm, wish_id := "") -> String:
	if not can_wish(f):
		return ""
	var g := Game.inst
	var n := f.nation()
	if wish_id == "":
		var total := 0
		for w in TABLE:
			total += w[1]
		var r := g.rng.randi() % total
		for w in TABLE:
			r -= w[1]
			if r < 0:
				wish_id = w[0]
				break
	var at := [Vector2(-1, -1)]
	var result := _apply(g, f, n, wish_id, at)
	if result == "":
		result = "No effect!"
		n.prayer_points /= 2.0
	else:
		n.prayer_points = 0.0
	f.set_meta("wish_text", result)
	if f.nation_id == g.player_id:
		g.notify(result, at[0])
	return result


static func _apply(g: Game, f: Firm, n: Nation, id: String, at: Array) -> String:
	var rng := g.rng
	var nid := n.id
	match id:
		"FINISH_TECH":
			for r in _own_firms(g, nid):
				if r.code == "RESEARCH" and r.research_tech != "":
					var code: String = r.research_tech
					n.tech[code] = n.tech_level(code) + 1
					n.research_progress.erase(code)
					r.research_points = 0.0
					if n.tech[code] >= Defs.tech_def(code).get("max", 0):
						r.research_tech = ""
					at[0] = r.center_loc()
					return "Technology breakthrough! Your present research project has been completed!"
		"NEW_TECH":
			var valid := Defs.research_techs().filter(func(t):
				return Defs.can_research(n, t) and not _researching(g, nid, t["code"]))
			if not valid.is_empty():
				var t: Dictionary = valid[rng.randi() % valid.size()]
				n.tech[t["code"]] = n.tech_level(t["code"]) + 1
				return "Technology breakthrough! You have acquired %s technology!" % t["name"]
		"NEW_HUMAN", "NEW_SPY":
			var kind := "INF" if rng.randi() % 2 == 0 else "SPU"
			var u := _make_unit(g, f, Defs.unit_sprite(f.race, kind), float(rng.randi_range(60, 99)))
			if u:
				u.loyalty = 100.0
				at[0] = u.center_loc()
				if id == "NEW_SPY":
					u.is_spy = true
					u.spy_skill = float(100 - rng.randi() % 20)
					return "A veteran %s spy has entered your service!" % Defs.race_adj(f.race)
				return "A veteran %s soldier has entered your service!" % Defs.race_adj(f.race)
		"NEW_MONSTER":
			var ms: Array = Defs.monsters.filter(func(m): return Assets.has_sprite(m["unit"]))
			if not ms.is_empty():
				var u := _make_unit(g, f, ms[rng.randi() % ms.size()]["unit"], float(rng.randi_range(20, 99)))
				if u:
					u.loyalty = 100.0
					at[0] = u.center_loc()
					return "A Fryhtan has entered your service!"
		"NEW_HERO":
			var u := _make_unit(g, f, Defs.unit_sprite(f.race, "INF"), float(rng.randi_range(50, 90)))
			if u:
				var hl: Array = Defs.heroes.filter(func(x): return x["race"] == f.race)
				u.unit_name = hl[rng.randi() % hl.size()]["name"] if not hl.is_empty() else Defs.random_person_name(f.race, rng)
				u.leadership = float(rng.randi_range(40, 90))
				u.is_hero = true
				u.rank = Defs.Rank.GENERAL
				u.loyalty = 100.0
				at[0] = u.center_loc()
				return "A Hero, %s, has offered you his service!" % u.unit_name
		"ITEM":
			var item := Items.random_id(rng, Items.MAX_RARITY - 1, Items.MAX_RARITY)
			if item == 0:
				item = Items.random_id(rng, Items.MIN_RARITY, Items.MAX_RARITY)
			var c := g._free_treasure_cell(Vector2i(f.x1 - 2, f.y1 + f.h + 1))
			if item != 0 and c.x >= 0:
				g.spawn_treasure(Treasure.Kind.ITEM, item, Items.random_para(item, rng), c)
				at[0] = Vector2(c)
				return "An artifact has been uncovered near here! Pick it up before it is discovered by your enemies."
		"CASH":
			n.add_cash((20 + rng.randi() % 51) * 100.0, "Treasure")
			return "A peasant has discovered a hidden hoard of gold and has gladly turned it all over to you!"
		"FOOD":
			n.food += (20 + rng.randi() % 51) * 100.0
			return "A large amount of food has been discovered in a secret peasant cache and turned over to you."
		"RAW":
			var rows: Array = Assets.table("RAW").slice(0, 3)
			if not rows.is_empty():
				var s: Site = g._add_site(rows[rng.randi() % rows.size()], Vector2(-1, -1), 0, 0)
				if s:
					var m := g.spawn_firm("MINE", nid, f.race, Vector2i(s.x1, s.y1), true)
					if m:
						at[0] = m.center_loc()
						return "A deposit has been found and a new mine built on top of it!"
		"CAPTURE_UNIT":
			for u in _rotated(g.units, rng):
				if not u.dead and u.nation_id != nid and u.nation_id > 0 and u.rank != Defs.Rank.KING \
						and u.inside_firm == null and not u.is_spy and not u.is_god and not u.is_caravan \
						and not u.is_weapon and u.spy_place == null:
					g.defect_unit(u, nid)
					at[0] = u.center_loc()
					return "An enemy %s has defected and joined your Kingdom!" % u.type_name()
		"CAPTURE_CAMP":
			for c in _rotated(g.firms, rng):
				if Espionage.is_camp(c) and not c.under_construction and c.nation_id != nid \
						and c.nation_id != GameObj.MONSTER_NATION \
						and (c.overseer == null or c.overseer.rank != Defs.Rank.KING):
					var old: int = c.nation_id
					c.change_nation(nid)
					g.on_firm_changed(c, old)
					at[0] = c.center_loc()
					return "An enemy %s has recognized your greatness and surrendered to you!" % c.display_name()
		"CAPTURE_TOWN":
			for t in _rotated(g.towns, rng):
				if not t.dead and t.nation_id != nid:
					t.surrender(nid)
					if t.nation_id == nid:
						at[0] = t.center_loc()
						return "An enemy town, tired of living under oppressive rule, has declared for you!"
		"KILL_SPY_BUILDING":
			var place: GameObj = null
			for s in _rotated(g.spies, rng):
				if is_instance_valid(s.spy_place) and s.spy_place.nation_id == nid and s.nation_id != nid:
					place = s.spy_place
					break
			if place:
				var killed := _expose(g, nid, 7, place)
				if killed > 0:
					at[0] = place.center_loc()
					return "%d enemy spies have been exposed and executed!" % killed
		"KILL_SPY_NATION":
			var killed := _expose(g, nid, 3)
			if killed > 0:
				return "%d enemy spies in your Kingdom have been exposed and executed!" % killed
		"CLEAR_SPY_NATION":
			_expose(g, nid, 9)
			return "Every single enemy spy in your Kingdom has been exposed and executed!"
		"HEAL_BUILDING":
			var best: Firm = null
			var best_w := 16.0      # don't heal if they are healthy
			for c in _own_firms(g, nid):
				if Espionage.is_camp(c):
					var w := 0.0
					for u in Espionage.occupants(c):
						w += u.max_hp - u.hp
					if w > best_w:
						best_w = w
						best = c
			if best:
				for u in Espionage.occupants(best):
					u.hp = minf(u.max_hp, u.hp + 200.0)
				at[0] = best.center_loc()
				return "All of the wounded in a %s of yours have been healed of their wounds!" % best.display_name()
		"HEAL_NATION":
			for u in g.units:
				if u.nation_id == nid and not u.dead:
					u.hp = minf(u.max_hp, u.hp + 100.0)
			return "Every soldier in your Kingdom has been healed of his wounds!"
		"LOYALTY_BUILDING_S", "LOYALTY_BUILDING_L":
			var inc := 100.0 if id.ends_with("L") else float(20 + rng.randi() % 30)
			if rng.randi() % 2 == 0:
				for t in _rotated(g.towns, rng):
					if not t.dead and t.nation_id == nid:
						t.loyalty = minf(100.0, t.loyalty + inc)
						at[0] = t.center_loc()
						return ("The loyalty of the people of %s has increased to its maximum!" % t.display_name()) if inc >= 100.0 \
							else ("The loyalty of the people of %s has increased by %d points!" % [t.display_name(), int(inc)])
			else:
				for c in _rotated(_own_firms(g, nid), rng):
					if Espionage.is_camp(c) and not Espionage.occupants(c).is_empty():
						for u in Espionage.occupants(c):
							u.loyalty = minf(100.0, u.loyalty + inc)
						at[0] = c.center_loc()
						return ("The loyalty of everyone in a %s of yours has increased to its maximum!" % c.display_name()) if inc >= 100.0 \
							else ("The loyalty of everyone in a %s of yours has increased by %d points!" % [c.display_name(), int(inc)])
		"LOYALTY_NATION_S", "LOYALTY_NATION_L":
			var inc := 100.0 if id.ends_with("L") else float(20 + rng.randi() % 30)
			for u in g.units:
				if u.nation_id == nid and not u.dead:
					u.loyalty = minf(100.0, u.loyalty + inc)
			for t in g.towns:
				if not t.dead and t.nation_id == nid:
					t.loyalty = minf(100.0, t.loyalty + inc)
			return "The loyalty of every subject in your Kingdom has increased to its maximum!" if inc >= 100.0 \
				else "The loyalty of every subject in your Kingdom has increased by %d points!" % int(inc)
		"COMBAT_BUILDING":
			var inc := float(30 + rng.randi() % 40)
			for c in _rotated(_own_firms(g, nid), rng):
				if Espionage.is_camp(c) and not Espionage.occupants(c).is_empty():
					for u in Espionage.occupants(c):
						u.combat = minf(Defs.MAX_COMBAT_TRAIN, u.combat + inc)
					at[0] = c.center_loc()
					return "The combat level of all soldiers in a %s of yours has increased by %d points!" % [c.display_name(), int(inc)]
	return ""


static func _own_firms(g: Game, nid: int) -> Array:
	return g.firms.filter(func(c): return not c.dead and c.nation_id == nid and not c.under_construction)


static func _researching(g: Game, nid: int, code: String) -> bool:
	return g.firms.any(func(c): return not c.dead and c.nation_id == nid and c.research_tech == code)


## The original walks its arrays from a random start.
static func _rotated(a: Array, rng: RandomNumberGenerator) -> Array:
	if a.is_empty():
		return []
	var k := rng.randi() % a.size()
	return a.slice(k) + a.slice(0, k)


## Enemy spies in the kingdom's towns and forts (or in one place), each caught
## with a chance of `tenths` in ten.
static func _expose(g: Game, nid: int, tenths: int, place: GameObj = null) -> int:
	var killed := 0
	for s in g.spies.duplicate():
		if not is_instance_valid(s.spy_place) or s.spy_place.nation_id != nid or s.nation_id == nid:
			continue
		if place != null and s.spy_place != place:
			continue
		if g.rng.randi() % 10 < tenths:
			g.spy_caught(s)
			killed += 1
	return killed


static func _make_unit(g: Game, f: Firm, sprite: String, skill: float) -> Unit:
	if not Assets.has_sprite(sprite):
		return null
	var c := g.exit_cell(f.footprint(), f.door())
	var u := g.spawn_unit(sprite, f.nation_id, c, skill)
	f.send_to_rally(u)
	return u
