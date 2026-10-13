class_name ScenarioEditorWindow
extends PanelContainer
## The scenario editor (oseditor.cpp and osedit_*.cpp), a mode of the game in
## which time stands still. Pages: Place (people and their buildings, Fryhtans
## and theirs, nature, deposits, treasure and items), Selected (edit or remove
## the selected object), Kingdoms (players, gold, food, reputation, life
## points, technologies), Diplomacy, Goals (victory and defeat conditions) and
## Scenario (name, briefing, save, try it).

signal tool_selected(tool: Dictionary)
signal play_requested(path: String)

var game: Game
var tabs: TabContainer
var place_nation: OptionButton
var place_list: ItemList
var place_items: Array = []
var sel_box: VBoxContainer
var kingdom_box: VBoxContainer
var diplo_box: VBoxContainer
var goals_box: VBoxContainer
var name_edit: LineEdit
var text_edit: TextEdit
var status: Label
var _last_sel = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(4, 44)
	custom_minimum_size = Vector2(380, 600)
	var vb := VBoxContainer.new()
	add_child(vb)
	var head := Label.new()
	head.text = "Scenario editor"
	head.add_theme_font_size_override("font_size", 18)
	head.add_theme_color_override("font_color", Color(1, 0.85, 0.45))
	vb.add_child(head)
	var tip := Label.new()
	tip.text = "Time stands still. Pick something, then left-click the map to place it; right-click to stop."
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size = Vector2(370, 0)
	tip.add_theme_font_size_override("font_size", 12)
	vb.add_child(tip)
	tabs = TabContainer.new()
	tabs.custom_minimum_size = Vector2(370, 520)
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(tabs)
	_build_place()
	sel_box = _page("Selected")
	kingdom_box = _page("Kingdoms")
	diplo_box = _page("Diplomacy")
	goals_box = _page("Goals")
	_build_scenario()
	tabs.tab_changed.connect(func(_i): refresh())
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(370, 0)
	status.add_theme_font_size_override("font_size", 12)
	vb.add_child(status)


func _page(title: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = title
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(sc)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(box)
	return box


func _process(_delta: float) -> void:
	if game == null:
		return
	var s = game.selected[0] if not game.selected.is_empty() and is_instance_valid(game.selected[0]) else null
	if s != _last_sel:
		_last_sel = s
		if tabs.current_tab == 1:
			refresh()


func refresh() -> void:
	match tabs.current_tab:
		0:
			_fill_place_nations()
		1:
			_fill_selected()
		2:
			_fill_kingdoms()
		3:
			_fill_diplomacy()
		4:
			_fill_goals()


# ------------------------------------------------------------------ place ---

func _build_place() -> void:
	var box := _page("Place")
	var hb := HBoxContainer.new()
	box.add_child(hb)
	var l := Label.new()
	l.text = "For"
	hb.add_child(l)
	place_nation = OptionButton.new()
	place_nation.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	place_nation.item_selected.connect(func(_i): _fill_place_list())
	hb.add_child(place_nation)
	place_list = ItemList.new()
	place_list.custom_minimum_size = Vector2(360, 440)
	place_list.item_selected.connect(_on_place_pick)
	box.add_child(place_list)
	_fill_place_nations()


## Kingdom choices: each kingdom, the independents, the wild Fryhtans, nature.
func _fill_place_nations() -> void:
	if place_nation == null or game == null:
		return
	var keep := place_nation.selected
	place_nation.clear()
	for n in game.nations:
		place_nation.add_item(n.name, n.id)
	place_nation.add_item("Independent", 0)
	place_nation.add_item("Wild Fryhtans", GameObj.MONSTER_NATION)
	place_nation.add_item("Nature, deposits and treasure", -1)
	place_nation.select(clampi(keep, 0, place_nation.item_count - 1))
	_fill_place_list()


func _nid() -> int:
	return place_nation.get_item_id(place_nation.selected)


func _fill_place_list() -> void:
	place_list.clear()
	place_items.clear()
	var nid := _nid()
	if nid == -1:
		_item("Tree", {"kind": "tree"})
		_item("Rocks", {"kind": "rock"})
		_item("Lake", {"kind": "lake"})
		for r in Assets.table("RAW").slice(0, 3):
			_item("%s deposit" % r["NAME"], {"kind": "site", "row": r})
		_item("Treasure (1000 gold)", {"kind": "gold"})
		for r in Defs.races:
			_item("Scroll of Power: %s" % r["name"], {"kind": "scroll", "race": r["code"]})
		for id in Items.TABLE:
			_item("Item: %s" % Items.item_name(id), {"kind": "item", "id": id})
		return
	var n := game.nation(nid)
	var fryhtan := nid == GameObj.MONSTER_NATION or (n and n.is_fryhtan)
	if fryhtan:
		var species := [n.monster_code] if n and n.monster_code != "" else Defs.monsters.map(func(m): return m["unit"])
		for sp in species:
			_item("Lair (%s)" % _species(sp), {"kind": "firm", "code": "LAIR", "race": sp})
			_item("%s" % _species(sp), {"kind": "unit", "sprite": sp})
			_item("%s general" % _species(sp), {"kind": "unit", "sprite": sp, "rank": Defs.Rank.GENERAL})
		for code in Defs.FRYHTAN_FIRMS + ["FORTRESS"]:
			_item(Defs.firm_types.get(code, {}).get("name", code), {"kind": "firm", "code": code, "race": ""})
		for sp in ["BEE", "TERMITE", "JAGUAR", "GORILLA", "RHINOCER", "F__BALLI", "F_CATAPU", "F_CANNON"]:
			_item(Defs.unit_types.get(sp, {}).get("name", sp), {"kind": "unit", "sprite": sp})
		return
	var races: Array = [n.race] if n else Defs.races.map(func(r): return r["code"])
	for r in races:
		_item("Town (%s)" % Defs.race_name(r), {"kind": "town", "race": r})
	if n:
		for code in Defs.HUMAN_FIRMS + Defs.OFFENSIVE_FIRMS:
			_item(Defs.firm_types.get(code, {}).get("name", code), {"kind": "firm", "code": code, "race": n.race})
	for r in races:
		for k in [["INF", "infantry"], ["SPU", "special unit"], ["CIV", "villager"]]:
			_item("%s %s" % [Defs.race_name(r), k[1]], {"kind": "unit", "sprite": Defs.unit_sprite(r, k[0])})
		_item("%s general" % Defs.race_name(r), {"kind": "unit", "sprite": Defs.unit_sprite(r, "INF"), "rank": Defs.Rank.GENERAL})
		if n:
			_item("%s king" % Defs.race_name(r), {"kind": "unit", "sprite": Defs.unit_sprite(r, "INF"), "rank": Defs.Rank.KING})
			_item("%s spy" % Defs.race_name(r), {"kind": "unit", "sprite": Defs.unit_sprite(r, "CIV"), "spy": true})
	if n:
		for w in Defs.WEAPONS + Defs.MEGA_WEAPONS:
			_item(Defs.unit_types.get(w, {}).get("name", w), {"kind": "unit", "sprite": w})
		var god: Dictionary = Defs.gods.get(n.race, {})
		if not god.is_empty():
			_item("Greater Being: %s" % Defs.unit_types.get(god["unit"], {}).get("name", "?"), {"kind": "unit", "sprite": god["unit"]})
		for h in Defs.heroes.filter(func(x): return x["race"] == n.race).slice(0, 12):
			_item("Hero: %s" % h["name"], {"kind": "unit", "sprite": Defs.unit_sprite(n.race, "INF"), "hero": h["name"]})


func _species(code: String) -> String:
	for m in Defs.monsters:
		if m["unit"] == code:
			return m["name"]
	return code


func _item(label: String, tool: Dictionary) -> void:
	place_list.add_item(label)
	place_items.append(tool)


func _on_place_pick(i: int) -> void:
	var t: Dictionary = place_items[i].duplicate()
	t["nation"] = _nid()
	tool_selected.emit(t)
	status.text = "Placing: %s. Left-click the map; right-click to stop." % place_list.get_item_text(i)


## Places the chosen thing at a map location (called by main on a click).
func place(t: Dictionary, at: Vector2i) -> bool:
	var g := game
	var nid: int = maxi(0, t.get("nation", 0))
	match t["kind"]:
		"town":
			var p := Vector2i(at.x - Defs.TOWN_SIZE / 2, at.y - Defs.TOWN_SIZE / 2)
			if not g.world.can_place(p.x, p.y, Defs.TOWN_SIZE, Defs.TOWN_SIZE):
				return false
			var town := g.spawn_town(t["race"], nid, p, 30)
			for n in g.nations:
				town.resistance[n.id] = 60.0
			town.loyalty = 60.0
		"firm":
			var b := Assets.firm_build(t["code"], t.get("race", ""))
			var w: int = b.get("loc_w", 3)
			var h: int = b.get("loc_h", 3)
			var p := Vector2i(at.x - w / 2, at.y - h / 2)
			if t["code"] == "MINE":
				var s := g.site_at_rect(Rect2i(at, Vector2i.ONE))
				if s == null:
					status.text = "A mine must stand on a deposit."
					return false
				p = Vector2i(s.x1, s.y1)
			elif not g.world.can_place(p.x, p.y, w, h):
				return false
			var f := g.spawn_firm(t["code"], nid, t.get("race", ""), p, true)
			if f == null:
				return false
			if t["code"] == "LAIR":
				f.monster_code = t["race"] if t.get("race", "") != "" else (g.nation(nid).monster_code if g.nation(nid) else "GITH")
		"unit":
			var u := g.spawn_unit(t["sprite"], nid, at, 40.0)
			if u == null:
				return false
			u.rank = t.get("rank", Defs.Rank.SOLDIER)
			if u.rank >= Defs.Rank.GENERAL:
				u.leadership = 50.0
			if u.rank == Defs.Rank.KING and g.nation(nid):
				if g.nation(nid).king and is_instance_valid(g.nation(nid).king):
					g.nation(nid).king.rank = Defs.Rank.GENERAL
				g.nation(nid).king = u
			if t.has("hero"):
				u.unit_name = t["hero"]
				u.is_hero = true
				u.rank = Defs.Rank.GENERAL
				u.combat = 70.0
				u.leadership = 70.0
			if t.get("spy", false):
				u.is_spy = true
				u.spy_skill = 50.0
		"tree":
			if g.world.object_at(at) != null:
				return false
			g.place_tree(at, g.rng.randi_range(0, 30))
		"rock", "lake":
			var ri := g._pick_rock("R" if t["kind"] == "rock" else "P", 1, 4, at)
			return ri >= 0 and g._try_add_rock(ri, at)
		"site":
			var row: Dictionary = t["row"]
			var sw: int = row["LOC_WIDTH"].to_int()
			var sh: int = row["LOC_HEIGHT"].to_int()
			if not g.world.can_place(at.x, at.y, sw, sh) or g._overlaps_site(Rect2i(at, Vector2i(sw, sh))):
				return false
			var s := Site.new()
			s.raw = row["NAME"]
			s.row = row
			s.x1 = at.x
			s.y1 = at.y
			s.w = sw
			s.h = sh
			s.reserve = Defs.MAX_RAW_RESERVE_QTY * 0.8
			g.sites.append(s)
			g._ground_dirty = true
		"gold":
			g.spawn_treasure(Treasure.Kind.GOLD, 1000, 0, at)
		"scroll":
			var ri := Defs.races.map(func(r): return r["code"]).find(t["race"])
			g.spawn_treasure(Treasure.Kind.SCROLL, ri + 1, 0, at)
		"item":
			g.spawn_treasure(Treasure.Kind.ITEM, t["id"], Items.random_para(t["id"], g.rng), at)
	g.update_links()
	return true


# --------------------------------------------------------------- selected ---

func _clear(box: Container) -> void:
	for c in box.get_children():
		c.queue_free()


func _spin(box: Container, label: String, value: float, lo: float, hi: float, on_change: Callable) -> void:
	var hb := HBoxContainer.new()
	box.add_child(hb)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(150, 0)
	hb.add_child(l)
	var sp := SpinBox.new()
	sp.min_value = lo
	sp.max_value = hi
	sp.value = value
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.value_changed.connect(on_change)
	hb.add_child(sp)


func _owner_picker(box: Container, o: GameObj) -> void:
	var hb := HBoxContainer.new()
	box.add_child(hb)
	var l := Label.new()
	l.text = "Owner"
	l.custom_minimum_size = Vector2(150, 0)
	hb.add_child(l)
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ids := [0] + game.nations.map(func(n): return n.id)
	for id in ids:
		ob.add_item("Independent" if id == 0 else game.nation(id).name, id)
	ob.select(maxi(0, ids.find(o.nation_id)))
	ob.item_selected.connect(func(i):
		var to := ob.get_item_id(i)
		if o is Firm:
			(o as Firm).change_nation(to)
		elif o is Town:
			(o as Town).surrender(to)
		else:
			o.nation_id = to
		game.update_links()
		o.queue_redraw())
	hb.add_child(ob)


func _fill_selected() -> void:
	_clear(sel_box)
	var o = game.selected[0] if not game.selected.is_empty() and is_instance_valid(game.selected[0]) else null
	if o == null:
		var l := Label.new()
		l.text = "Select something on the map to edit it."
		sel_box.add_child(l)
		return
	var title := Label.new()
	title.text = o.display_name()
	title.add_theme_font_size_override("font_size", 16)
	sel_box.add_child(title)
	_owner_picker(sel_box, o)
	if o is Town:
		var t := o as Town
		_spin(sel_box, "Population", t.population, 1, Defs.MAX_TOWN_POPULATION, func(v):
			t.population = int(v)
			t.queue_redraw())
		_spin(sel_box, "Loyalty", t.loyalty, 0, 100, func(v): t.loyalty = v)
		for n in game.nations:
			var nn: Nation = n
			_spin(sel_box, "Resistance to %s" % nn.name.substr(0, 14), t.resistance_to(nn.id), 0, 100, func(v): t.resistance[nn.id] = v)
		_spin(sel_box, "Wall (0-2)", t.wall_level, 0, 2, func(v):
			t.wall_level = int(v)
			t.target_wall_level = int(v)
			t.wall_hp = t.wall_max_hp())
	elif o is Firm:
		var f := o as Firm
		_spin(sel_box, "Hit points", f.hp, 1, f.max_hp, func(v): f.hp = v)
		if f.code == "MINE":
			_spin(sel_box, "Reserve", f.reserve, 0, Defs.MAX_RAW_RESERVE_QTY, func(v):
				f.reserve = v
				if f.site:
					f.site.reserve = v)
	elif o is Unit:
		var u := o as Unit
		_spin(sel_box, "Combat", u.combat, 1, 100, func(v): u.combat = v)
		_spin(sel_box, "Leadership", u.leadership, 0, 100, func(v): u.leadership = v)
		_spin(sel_box, "Hit points", u.hp, 1, u.max_hp, func(v): u.hp = v)
		var rk := OptionButton.new()
		for k in ["Soldier", "General", "King"]:
			rk.add_item(k)
		rk.select(clampi(u.rank, 0, 2))
		rk.item_selected.connect(func(i):
			u.rank = i
			var n := game.nation(u.nation_id)
			if i == Defs.Rank.KING and n:
				if n.king and is_instance_valid(n.king) and n.king != u:
					n.king.rank = Defs.Rank.GENERAL
				n.king = u)
		sel_box.add_child(rk)
		var it := OptionButton.new()
		it.add_item("No item", 0)
		for id in Items.TABLE:
			it.add_item(Items.item_name(id), id)
		it.select(maxi(0, it.get_item_index(u.item_id)))
		it.item_selected.connect(func(i):
			u.item_id = it.get_item_id(i)
			u.item_para = Items.random_para(u.item_id, game.rng) if u.item_id > 0 else 0)
		sel_box.add_child(it)
	var del := Button.new()
	del.text = "Remove"
	del.pressed.connect(func():
		if o is Unit:
			game.remove_unit(o)
		elif o is Firm:
			game.on_firm_destroyed(o, null)
		elif o is Town:
			game.on_town_destroyed(o)
		game.selected = []
		_fill_selected())
	sel_box.add_child(del)


# --------------------------------------------------------------- kingdoms ---

func _fill_kingdoms() -> void:
	_clear(kingdom_box)
	for n in game.nations:
		var nn: Nation = n
		var head := HBoxContainer.new()
		kingdom_box.add_child(head)
		var l := Label.new()
		l.text = "■ " + nn.name
		l.add_theme_color_override("font_color", nn.color)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(l)
		var pl := CheckBox.new()
		pl.text = "You"
		pl.button_pressed = nn.id == game.player_id
		pl.toggled.connect(func(on):
			if on:
				_set_player(nn.id))
		head.add_child(pl)
		var ne := LineEdit.new()
		ne.text = nn.name
		ne.text_submitted.connect(func(t):
			nn.name = t
			_fill_kingdoms())
		ne.focus_exited.connect(func(): nn.name = ne.text)
		kingdom_box.add_child(ne)
		_spin(kingdom_box, "Gold", nn.cash, 0, 1000000, func(v): nn.cash = v)
		if nn.is_fryhtan:
			_spin(kingdom_box, "Life points", nn.live_points, 0, 100000, func(v): nn.live_points = v)
		else:
			_spin(kingdom_box, "Food", nn.food, 0, 1000000, func(v): nn.food = v)
		_spin(kingdom_box, "Reputation", nn.reputation, -100, 100, func(v): nn.reputation = v)
		var tb := Button.new()
		tb.text = "Knows every technology" if nn.tech.size() < 10 else "Forget every technology"
		tb.pressed.connect(func():
			if nn.tech.size() < 10:
				for t in Defs.research_techs() + (Defs.FRYHTAN_TECHS if nn.is_fryhtan else []):
					nn.tech[t["code"]] = t["max"]
			else:
				nn.tech.clear()
			_fill_kingdoms())
		kingdom_box.add_child(tb)
		kingdom_box.add_child(HSeparator.new())
	var add := HBoxContainer.new()
	kingdom_box.add_child(add)
	var race := OptionButton.new()
	for r in Defs.races:
		race.add_item(r["name"])
	for m in Defs.monsters:
		race.add_item("%s Fryhtans" % m["name"])
	race.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add.add_child(race)
	var ab := Button.new()
	ab.text = "Add kingdom"
	ab.disabled = game.nations.size() >= Defs.NATION_COLORS.size()
	ab.pressed.connect(func():
		var i := race.selected
		var fry := i >= Defs.races.size()
		var code: String = Defs.monsters[i - Defs.races.size()]["unit"] if fry else Defs.races[i]["code"]
		var n := Nation.new(game.nations.size() + 1, code, Defs.NATION_COLORS[game.nations.size() % Defs.NATION_COLORS.size()], true)
		if fry:
			n.is_fryhtan = true
			n.monster_code = code
			n.name = "%s Fryhtans" % Defs.monsters[i - Defs.races.size()]["name"]
			n.live_points = 600.0
		n.cash = 3000.0
		n.food = 0.0 if fry else 1500.0
		for o in game.nations:
			o.relations[n.id] = Defs.Relation.WAR if o.is_fryhtan != n.is_fryhtan else Defs.Relation.NEUTRAL
			n.relations[o.id] = o.relations[n.id]
		game.nations.append(n)
		n.ai = FryhtanAI.new(n, game) if fry else NationAI.new(n, game)
		_fill_kingdoms()
		_fill_place_nations())
	add.add_child(ab)


func _set_player(nid: int) -> void:
	for n in game.nations:
		var me: bool = n.id == nid
		n.is_player = me
		n.is_ai = not me
		n.ai = null if me else (FryhtanAI.new(n, game) if n.is_fryhtan else NationAI.new(n, game))
	game.player_id = nid
	_fill_kingdoms()


# -------------------------------------------------------------- diplomacy ---

func _fill_diplomacy() -> void:
	_clear(diplo_box)
	for a in game.nations:
		for b in game.nations:
			if b.id <= a.id:
				continue
			var na: Nation = a
			var nb: Nation = b
			var hb := HBoxContainer.new()
			diplo_box.add_child(hb)
			var l := Label.new()
			l.text = "%s – %s" % [na.name.substr(0, 16), nb.name.substr(0, 16)]
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hb.add_child(l)
			var ob := OptionButton.new()
			for r in Defs.RELATION_NAMES:
				ob.add_item(r)
			ob.select(na.relation(nb.id))
			ob.item_selected.connect(func(i):
				na.relations[nb.id] = i
				nb.relations[na.id] = i
				if i == Defs.Relation.WAR or i == Defs.Relation.ALLIANCE:
					Diplomacy.set_trade(game, na.id, nb.id, i == Defs.Relation.ALLIANCE)
				_fill_diplomacy.call_deferred())
			hb.add_child(ob)
			var tt := CheckBox.new()
			tt.text = "Trade"
			tt.tooltip_text = "A trade treaty: their caravans may trade at each other's markets."
			tt.button_pressed = Diplomacy.has_trade(na, nb.id)
			tt.disabled = na.relation(nb.id) == Defs.Relation.WAR
			tt.toggled.connect(func(on): Diplomacy.set_trade(game, na.id, nb.id, on))
			hb.add_child(tt)


# ------------------------------------------------------------------ goals ---

const GOAL_KINDS := [
	[Goals.DEFEAT_ALL_OTHER_KINGDOMS, "Defeat every other kingdom", ""],
	[Goals.DEFEAT_EXCEPT_ALLIANCE, "Defeat every kingdom but one ally", ""],
	[Goals.DEFEAT_KINGDOM, "Defeat a kingdom", "kingdom"],
	[Goals.FORM_ALLY_WITH_KINGDOM, "Ally with a kingdom", "kingdom"],
	[Goals.DEFEAT_ALL_FRYHTAN, "Defeat all Fryhtans", ""],
	[Goals.REACH_POPULATION, "Population reaches", "number"],
	[Goals.REACH_ECONOMY, "Economic score reaches", "number"],
	[Goals.REACH_MILITARY, "Military score reaches", "number"],
	[Goals.REACH_TOTAL, "Total score reaches", "number"],
	[Goals.KILL_MONSTER_SCORE, "Fryhtan battling score reaches", "number"],
	[Goals.TRAIN_10_GENERAL, "Train 10 generals of leadership", "number"],
	[Goals.CONQUER_ALL_TOWN, "Conquer all independent towns", ""],
	[Goals.CONQUER_TOWN, "Conquer the selected town", "selected"],
	[Goals.DESTROY_FIRM, "Destroy the selected building", "selected"],
	[Goals.CONQUER_FIRM, "Capture the selected building", "selected"],
	[Goals.KILL_UNIT, "Kill the selected unit", "selected"],
	[Goals.KEEP_UNIT_ALIVE, "Keep the selected unit alive", "selected"],
	[Goals.MEET_UNIT, "Meet the selected unit", "selected"],
	[Goals.NATION_SURVIVE, "Survive for years", "number"],
]


func _fill_goals() -> void:
	_clear(goals_box)
	if game.goals == null:
		game.goals = Goals.new()
	var gl := game.goals
	for side in ["win", "lose"]:
		var h := Label.new()
		h.text = "Victory (any of these)" if side == "win" and not gl.require_all else ("Victory (all of these)" if side == "win" else "Defeat")
		h.add_theme_color_override("font_color", Color(1, 0.85, 0.45))
		goals_box.add_child(h)
		var list: Array = gl.win if side == "win" else gl.lose
		for c in list.duplicate():
			var hb := HBoxContainer.new()
			goals_box.add_child(hb)
			var l := Label.new()
			l.text = c["text"] + (" (within %d years)" % c["years"] if c["years"] > 0 else "")
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hb.add_child(l)
			var rm := Button.new()
			rm.text = "✕"
			var cc: Dictionary = c
			rm.pressed.connect(func():
				list.erase(cc)
				_fill_goals())
			hb.add_child(rm)
	var all := CheckBox.new()
	all.text = "Victory needs all goals"
	all.button_pressed = gl.require_all
	all.toggled.connect(func(on):
		gl.require_all = on
		_fill_goals())
	goals_box.add_child(all)
	goals_box.add_child(HSeparator.new())
	var kind := OptionButton.new()
	for k in GOAL_KINDS:
		kind.add_item(k[1])
	goals_box.add_child(kind)
	var target := OptionButton.new()
	for n in game.nations:
		target.add_item(n.name, n.id)
	goals_box.add_child(target)
	var hb2 := HBoxContainer.new()
	goals_box.add_child(hb2)
	var num := SpinBox.new()
	num.max_value = 100000
	num.value = 100
	num.prefix = "Value"
	hb2.add_child(num)
	var years := SpinBox.new()
	years.max_value = 100
	years.prefix = "Years"
	years.tooltip_text = "0: no time limit"
	hb2.add_child(years)
	var add_w := Button.new()
	add_w.text = "Add victory goal"
	add_w.pressed.connect(func(): _add_goal(gl.win, GOAL_KINDS[kind.selected], target.get_item_id(target.selected), int(num.value), int(years.value)))
	goals_box.add_child(add_w)
	var add_l := Button.new()
	add_l.text = "Add defeat condition"
	add_l.pressed.connect(func(): _add_goal(gl.lose, GOAL_KINDS[kind.selected], target.get_item_id(target.selected), int(num.value), int(years.value)))
	goals_box.add_child(add_l)


func _add_goal(list: Array, k: Array, nation_id: int, value: int, years: int) -> void:
	var c := {"id": k[0], "p1": 0, "p2": value, "years": years, "player_only": true, "text": k[1], "result": "", "target": null, "supported": true, "met": false}
	match k[2]:
		"kingdom":
			c["target"] = nation_id
			c["text"] = "%s: %s" % [k[1], game.nation(nation_id).name]
		"number":
			c["text"] = "%s %d" % [k[1], value]
		"selected":
			var o = game.selected[0] if not game.selected.is_empty() and is_instance_valid(game.selected[0]) else null
			if o == null:
				status.text = "Select the object on the map first."
				return
			c["target"] = o
			c["text"] = k[1].replace("the selected", "").strip_edges() + " " + o.display_name()
	if c["id"] == Goals.NATION_SURVIVE:
		c["p2"] = value
		c["text"] = "Survive for %d years" % value
	list.append(c)
	_fill_goals()


# --------------------------------------------------------------- scenario ---

func _build_scenario() -> void:
	var box := _page("Scenario")
	var l := Label.new()
	l.text = "Name"
	box.add_child(l)
	name_edit = LineEdit.new()
	name_edit.text = "My scenario"
	box.add_child(name_edit)
	var l2 := Label.new()
	l2.text = "Briefing"
	box.add_child(l2)
	text_edit = TextEdit.new()
	text_edit.custom_minimum_size = Vector2(360, 200)
	text_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.add_child(text_edit)
	var save := Button.new()
	save.text = "Save scenario"
	save.pressed.connect(func():
		var path := _save()
		status.text = ("Saved as %s. It is listed with the scenarios on the start screen." % path) if path != "" else "Could not save the scenario.")
	box.add_child(save)
	var play := Button.new()
	play.text = "Save and play it"
	play.pressed.connect(func():
		var path := _save()
		if path != "":
			play_requested.emit(ProjectSettings.globalize_path(path)))
	box.add_child(play)


func _save() -> String:
	if game.player() == null:
		status.text = "Choose your kingdom on the Kingdoms page first."
		return ""
	return SaveGame.save_scenario(game, name_edit.text, text_edit.text)
