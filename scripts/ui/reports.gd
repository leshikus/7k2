class_name ReportsWindow
extends PanelContainer
## The kingdom's reports (or_rank.cpp, or_nat.cpp, or_town.cpp, or_eco.cpp,
## or_mil.cpp, or_tech.cpp, or_trade.cpp, or_news.cpp): rankings of the
## kingdoms, your towns, money by kind this year and last, your armies, your
## technologies, markets and caravans, and the news so far.

const TABS := ["Kingdoms", "Towns", "Economy", "Military", "Technology", "Trade", "News", "AI"]

var game: Game
var news: Array = []          # [date, text] most recent last
var tabs: TabContainer
var pages := {}
var _timer := 0.0


func _ready() -> void:
	position = Vector2(150, 60)
	custom_minimum_size = Vector2(760, 560)
	var vb := VBoxContainer.new()
	add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	var title := Label.new()
	title.text = "Reports"
	title.add_theme_font_size_override("font_size", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func(): visible = false)
	head.add_child(close)
	tabs = TabContainer.new()
	tabs.custom_minimum_size = Vector2(740, 500)
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(tabs)
	for t in TABS:
		var r := RichTextLabel.new()
		r.name = t
		r.bbcode_enabled = true
		r.scroll_active = true
		r.add_theme_font_size_override("normal_font_size", 13)
		r.add_theme_font_size_override("bold_font_size", 13)
		tabs.add_child(r)
		pages[t] = r
	tabs.tab_changed.connect(func(_i): refresh())
	# HELP.RES: "Kingdoms Report (hotkey: F1)" ... on each page's tab
	for i in TABS.size():
		var h := HelpText.area_text(TABS[i] + " Report")
		if h != "":
			tabs.set_tab_tooltip(i, h)
	visible = false


func open() -> void:
	tabs.set_tab_hidden(TABS.find("AI"), not GameOptions.get_opt("show_ai_info"))
	# Reports background (Config::opaque_report): see-through or solid
	self_modulate = Color(1, 1, 1, 1.0 if int(GameOptions.get_opt("opaque_report")) == 1 else 0.82)
	visible = not visible
	if visible:
		refresh()


## A report hotkey: open on that page, or close when it is already showing.
func show_tab(name: String) -> void:
	var i := TABS.find(name)
	if visible and tabs.current_tab == i:
		visible = false
		return
	visible = true
	tabs.current_tab = i
	refresh()


func _process(delta: float) -> void:
	if not visible or game == null:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = 1.5
		refresh()


func refresh() -> void:
	if game == null or game.player() == null:
		return
	var t: String = TABS[tabs.current_tab]
	var r: RichTextLabel = pages[t]
	var scroll := r.get_v_scroll_bar().value
	r.text = call("_" + t.to_lower())
	r.get_v_scroll_bar().value = scroll


## Report of the computer kingdoms' thinking (or_ai.cpp, shown with Inside
## Information): their war, feelings toward the other kingdoms, treaties,
## personality and recent diplomacy.
func _ai() -> String:
	if not GameOptions.get_opt("show_ai_info"):
		return "The computer kingdoms' information is hidden (the game menu's cheat shows it)."
	var s := ""
	for n in game.nations:
		if not n.alive or n.ai == null:
			continue
		s += "[b]%s[/b]
" % _col(n.color, n.name)
		var wt: int = n.ai.war_target if "war_target" in n.ai else 0
		s += "  At war with: %s
" % (game.nation(wt).name if wt > 0 and game.nation(wt) else "nobody in particular")
		var feel: Array = []
		for o in game.nations:
			if o.alive and o.id != n.id:
				feel.append("%s %d%s%s" % [o.name, Diplomacy.ai_rel(n, o.id), " (trade)" if Diplomacy.has_trade(n, o.id) else "", "" if n.contact.has(o.id) else " (not met)"])
		s += "  Feelings: %s
" % ", ".join(feel)
		var prefs: Array = []
		for k in ["peace", "allying", "trading", "courage", "cash_reserve", "honesty"]:
			prefs.append("%s %d" % [k.replace("_", " "), Diplomacy._pref(n, k)])
		s += "  Personality: %s
" % ", ".join(prefs)
	var recent := game.talk_log.slice(-10)
	if not recent.is_empty():
		s += "
[b]Latest diplomacy[/b]
"
		for m in recent:
			s += "  %s%s
" % [Diplomacy.describe(game, m), (" — " + m["result"]) if m["result"] != "" else ""]
	return s


func _col(c: Color, s: String) -> String:
	return "[color=#%s]%s[/color]" % [c.to_html(false), s]


func _table(rows: Array, widths: Array) -> String:
	var out := "[table=%d]" % widths.size()
	for row in rows:
		for cell in row:
			out += "[cell]%s  [/cell]" % str(cell)
	return out + "[/table]"


# --------------------------------------------------------------- pages ---

func _kingdoms() -> String:
	var p := game.player()
	var rows := [["[b]Kingdom[/b]", "[b]Relation[/b]", "[b]Population[/b]", "[b]Military[/b]", "[b]Economy[/b]", "[b]Reputation[/b]", "[b]Fryhtans slain[/b]", "[b]Total[/b]"]]
	var list := game.nations.filter(func(n): return n.alive)
	list.sort_custom(func(a, b): return Goals.total_score(game, a) > Goals.total_score(game, b))
	for n in list:
		var rel: String = "you" if n.id == p.id else Defs.RELATION_NAMES[p.relation(n.id)]
		rows.append([_col(n.color, "■") + " " + n.name, rel, Goals.score(game, n, 1), Goals.score(game, n, 2), Goals.score(game, n, 3),
			Goals.score(game, n, 4), Goals.score(game, n, 5), "[b]%d[/b]" % Goals.total_score(game, n)])
	var s := _table(rows, rows[0])
	var fallen := game.nations.filter(func(n): return not n.alive).map(func(n): return n.name)
	if not fallen.is_empty():
		s += "\n[color=#888]Fallen: %s[/color]" % ", ".join(fallen)
	s += "\n\nScores are those of the original's rankings: population over 100, military strength over 200, economy over 6000, reputation, and the Fryhtan battling score over 1000."
	if p.king and is_instance_valid(p.king):
		s += "\n\nYour king: %s, leadership %d, combat %d." % [p.king.unit_name, int(p.king.leadership), int(p.king.combat)]
	return s


func _towns() -> String:
	var p := game.player()
	var mine := game.towns.filter(func(t): return t.nation_id == p.id and not t.dead)
	if mine.is_empty():
		return "You have no towns." if not p.is_fryhtan else "Fryhtans keep no towns; your lairs enslave villages that pay tribute."
	var rows := [["[b]Town[/b]", "[b]Race[/b]", "[b]People[/b]", "[b]Jobless[/b]", "[b]Loyalty[/b]", "[b]Wall[/b]", "[b]Camp[/b]"]]
	var pop := 0
	var loyal := 0.0
	for t in mine:
		pop += t.population
		loyal += t.loyalty
		var lc := Color(0.6, 1, 0.6) if t.loyalty >= 60 else (Color(1, 0.85, 0.4) if t.loyalty >= 35 else Color(1, 0.5, 0.4))
		rows.append([t.town_name, Defs.race_name(t.race), t.population, t.jobless(), _col(lc, "%d → %d" % [int(t.loyalty), int(t.target_loyalty)]),
			["fence", "wall", "fortified"][clampi(t.wall_level, 0, 2)], "yes" if t.has_linked_camp(p.id) else _col(Color(1, 0.5, 0.4), "none")])
	var s := _table(rows, rows[0])
	s += "\n%d towns, %d people, average loyalty %d." % [mine.size(), pop, int(loyal / mine.size())]
	var tribute := game.towns.filter(func(t): return t.nation_id == 0 and t.tribute_to() == p.id)
	if not tribute.is_empty():
		s += "\nVillages paying you tribute: %s." % ", ".join(tribute.map(func(t): return t.town_name))
	return s


func _economy() -> String:
	var p := game.player()
	var s := "Treasury: [b]%d[/b] gold" % int(p.cash)
	if p.is_fryhtan:
		s += "    Life points: [b]%d[/b]" % int(p.live_points)
	else:
		s += "    Food: [b]%d[/b]" % int(p.food)
	s += "\n\n"
	var kinds_in := {}
	for k in p.income_by.keys() + p.last_income_by.keys():
		kinds_in[k] = true
	var kinds_out := {}
	for k in p.expense_by.keys() + p.last_expense_by.keys():
		kinds_out[k] = true
	var rows := [["[b]Income[/b]", "[b]This year[/b]", "[b]Last year[/b]"]]
	for k in kinds_in:
		rows.append([k, int(p.income_by.get(k, 0.0)), int(p.last_income_by.get(k, 0.0))])
	rows.append(["[b]Total[/b]", "[b]%d[/b]" % int(p.income_year), "[b]%d[/b]" % int(p.last_income_year)])
	s += _table(rows, rows[0]) + "\n"
	rows = [["[b]Expenses[/b]", "[b]This year[/b]", "[b]Last year[/b]"]]
	for k in kinds_out:
		rows.append([k, int(p.expense_by.get(k, 0.0)), int(p.last_expense_by.get(k, 0.0))])
	rows.append(["[b]Total[/b]", "[b]%d[/b]" % int(p.expense_year), "[b]%d[/b]" % int(p.last_expense_year)])
	s += _table(rows, rows[0])
	var net := p.income_year - p.expense_year
	s += "\nBalance this year: %s" % _col(Color(0.6, 1, 0.6) if net >= 0 else Color(1, 0.5, 0.4), "%+d" % int(net))
	var upkeep := 0.0
	for f in game.firms:
		if f.nation_id == p.id and not f.dead:
			upkeep += float(f.ftype.get("year_cost", 0))
	s += "\nBuilding upkeep: %d a year." % int(upkeep)
	if not p.is_fryhtan:
		var farm := 0.0
		var eat := 0.0
		for t in game.towns:
			if t.nation_id == p.id:
				farm += t.jobless() * (1.0 + 0.25 * p.tech_level("FARMING")) * Defs.PEASANT_FOOD_YEAR_PRODUCTION
				eat += t.population * float(Defs.UNIT_FOOD_YEAR_CONSUMPTION)
		s += "\nFood: %d grown and %d eaten a year." % [int(farm), int(eat)]
	return s


func _military() -> String:
	var p := game.player()
	var s := ""
	var rows := [["[b]Building[/b]", "[b]Commander[/b]", "[b]Leadership[/b]", "[b]Soldiers[/b]", "[b]Avg. combat[/b]"]]
	for f in game.firms:
		if f.nation_id != p.id or f.dead or not (f.is_military() or f.code == "FORTRESS"):
			continue
		var avg := 0.0
		for u in f.soldiers:
			avg += u.combat
		avg = avg / f.soldiers.size() if not f.soldiers.is_empty() else 0.0
		rows.append([f.display_name(), f.overseer.display_name() if f.overseer else "[color=#ff9060]none[/color]",
			int(f.overseer.leadership) if f.overseer else "-", "%d / %d" % [f.soldiers.size(), f.capacity()], int(avg)])
	if rows.size() > 1:
		s += _table(rows, rows[0]) + "\n"
	var field := {}
	for u in game.units:
		if u.nation_id == p.id and not u.dead and u.inside_firm == null and not u.is_caravan and not u.has_meta("hidden"):
			var k := u.type_name() + (" (general)" if u.rank == Defs.Rank.GENERAL else (" (king)" if u.rank == Defs.Rank.KING else ""))
			field[k] = field.get(k, 0) + 1
	s += "\n[b]In the field[/b]\n"
	var keys := field.keys()
	keys.sort()
	for k in keys:
		s += "  %s: %d\n" % [k, field[k]]
	if field.is_empty():
		s += "  nobody\n"
	s += "\nMilitary score %d. Spies: %d." % [Goals.score(game, p, 2), game.units.filter(func(u): return u.is_spy and u.nation_id == p.id and not u.dead).size()]
	return s


func _technology() -> String:
	var p := game.player()
	var s := ""
	var known := []
	for code in p.tech:
		var t := Defs.tech_def(code)
		if not t.is_empty() and p.tech[code] > 0:
			known.append("%s %d / %d" % [t["name"], p.tech[code], t["max"]])
	known.sort()
	s += "[b]Known[/b]\n" + ("\n".join(known.map(func(x): return "  " + x)) if not known.is_empty() else "  nothing yet") + "\n"
	s += "\n[b]In progress[/b]\n"
	var any := false
	for f in game.firms:
		if f.nation_id == p.id and f.code == "RESEARCH" and f.research_tech != "":
			var t := Defs.tech_def(f.research_tech)
			s += "  %s %d at %s: %d%%\n" % [t["name"], p.tech_level(f.research_tech) + 1, f.display_name(), int(f.research_points)]
			any = true
	if not any:
		s += "  none\n"
	if game.tech_available != null:
		s += "\n[color=#c8c0a8]In this campaign more technologies are unveiled with each new battle.[/color]\n"
	var gods := p.known_gods.keys().map(func(r): return Defs.race_name(r))
	s += "\n[b]Scrolls of Power[/b]: %s\n" % ", ".join(gods)
	var megas := Defs.MEGA_WEAPONS.filter(func(m): return p.tech_level(m) > 0)
	if not megas.is_empty():
		s += "[b]Mega weapons[/b]: %s\n" % ", ".join(megas.map(func(m): return Defs.tech_def(m)["name"]))
	return s


func _trade() -> String:
	var p := game.player()
	var s := "[b]Markets[/b]\n"
	var any := false
	for f in game.firms:
		if f.nation_id == p.id and f.code == "MARKET" and not f.dead:
			any = true
			var goods := []
			for g in f.goods:
				goods.append("%s %d" % [g, int(f.goods[g])])
			s += "  %s — sales %d gold; goods: %s; caravans %d\n" % [f.display_name(), int(f.market_sales), ", ".join(goods) if not goods.is_empty() else "none", game.caravans_of(f)]
	if not any:
		s += "  none\n"
	s += "\n[b]Caravans[/b]\n"
	any = false
	for u in game.units:
		if u.is_caravan and u.nation_id == p.id and not u.dead:
			any = true
			var cargo := []
			for g in u.cargo:
				cargo.append("%s %d" % [g, int(u.cargo[g])])
			var route: Array = u.stops.map(func(st): return st["firm"].display_name() + ("" if st["firm"].nation_id == p.id or st["firm"].nation() == null else " of the " + st["firm"].nation().name))
			s += "  %s, carrying %s\n" % [" ↔ ".join(route) if not route.is_empty() else "no stops", ", ".join(cargo) if not cargo.is_empty() else "nothing"]
	if not any:
		s += "  none\n"
	s += "\nExports this year: %d gold. Imports: %d gold." % [int(p.income_by.get("Exports", 0.0)), int(p.expense_by.get("Imports", 0.0))]
	return s


func _news() -> String:
	if news.is_empty():
		return "No news yet."
	var lines := []
	for i in range(news.size() - 1, -1, -1):
		lines.append("[color=#c8c0a8]%s[/color]  %s" % news[i])
	return "\n".join(lines)


func add_news(date: String, text: String) -> void:
	news.append([date, text])
	if news.size() > 300:
		news.pop_front()
