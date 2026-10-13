class_name SetupPages
extends TabContainer
## The start screen's game settings as the original lays them out (ogamsing.cpp):
## rivals and difficulty; map and treasure; land and towns; goals. Choosing a
## difficulty sets every option; changing an option makes it "Custom".

signal changed

var setup: Dictionary = GameSetup.defaults()
var _widgets := {}          # setup key -> Control
var _rating: Label
var _busy := false


func _ready() -> void:
	custom_minimum_size = Vector2(520, 250)
	var p1 := _page("Rivals")
	_choice(p1, "difficulty", "Difficulty", GameSetup.DIFFICULTY_NAMES, "Sets all the options at once.")
	_spin(p1, "ai_humans", "Human rival kingdoms", 0, 6)
	_spin(p1, "ai_fryhtans", "Fryhtan kingdoms", 0, 6)
	_choice(p1, "aggressiveness", "Computer's aggressiveness", GameSetup.AGGRESSIVE_NAMES, "How readily the computer kingdoms attack, and you above all.")
	_check(p1, "nation_emerge", "New kingdoms emerge", "A big independent town may proclaim a kingdom when a rival has fallen.")
	_rating = Label.new()
	p1.add_child(Label.new())
	p1.add_child(_rating)
	var p2 := _page("Map & treasure")
	_check(p2, "explore", "Explored world map", "The land is known from the start, and every kingdom has met the others.")
	_check(p2, "fog", "Fog of war", "What your people cannot see goes dark again.")
	_choice(p2, "treasure", "Your treasure", GameSetup.TREASURE_NAMES, "", 1)
	_choice(p2, "ai_treasure", "Computer's treasure", GameSetup.TREASURE_NAMES, "", 1)
	_check(p2, "spy_methodology", "Espionage methods known", "Every kingdom knows the spying technologies without research.")
	_check(p2, "random_start", "Random start-up", "Rivals of any race; towns of 30-60 with men of several races outside.")
	var p3 := _page("Land & towns")
	_spin(p3, "raw_sites", "Natural resources", 1, 7)
	_check(p3, "mine_nearby", "A deposit near your town", "")
	_choice(p3, "indep_towns", "Independent towns", ["Few (7)", "Normal (15)", "Many (30)"], "", 0, GameSetup.TOWN_COUNTS)
	_choice(p3, "resistance", "Town resistance", GameSetup.LEVEL_NAMES, "Resistance of independent towns, their walls, and how slowly they come round.", 1)
	_check(p3, "town_emerge", "New towns emerge", "Wanderers settle new independent villages.")
	_choice(p3, "random_events", "Random events", GameSetup.EVENT_NAMES, "")
	var p4 := _page("Goals")
	var gl := Label.new()
	gl.text = "Besides defeating every other kingdom, you also win by:"
	p4.add_child(gl)
	_check(p4, "goal_destroy_monster", "Destroying all the Fryhtans", "")
	_check(p4, "goal_alliance_flag", "Being the last kingdom but for an ally", "Needs four kingdoms or more.")
	_goal(p4, "goal_population_flag", "goal_population", "Reaching a population of", 100, 3000, 50)
	_goal(p4, "goal_economic_flag", "goal_economic", "Reaching an economic score of", 100, 9000, 100)
	_goal(p4, "goal_total_flag", "goal_total", "Reaching a total score of", 100, 9000, 100)
	_goal(p4, "goal_year_flag", "goal_years", "Within a time limit of (years)", 1, 100, 1)
	refresh()


func _page(title: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = title
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(sc)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(vb)
	return vb


func _line(parent: Control, label: String, ctl: Control, tip: String) -> void:
	var hb := HBoxContainer.new()
	parent.add_child(hb)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(230, 0)
	hb.add_child(l)
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctl.tooltip_text = tip
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	hb.add_child(ctl)


## An option list; `base` is the value of the first item (treasure and
## resistance count from 1), or `values` maps items to values.
func _choice(parent: Control, key: String, label: String, items: Array, tip: String, base := 0, values: Array = []) -> void:
	var o := OptionButton.new()
	for it in items:
		o.add_item(it)
	o.set_meta("base", base)
	o.set_meta("values", values)
	o.item_selected.connect(func(i):
		var v = values[i] if not values.is_empty() else i + base
		_set_opt(key, v))
	_widgets[key] = o
	_line(parent, label, o, tip)


func _spin(parent: Control, key: String, label: String, lo: int, hi: int) -> void:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.value_changed.connect(func(v): _set_opt(key, int(v)))
	_widgets[key] = s
	_line(parent, label, s, "")


func _check(parent: Control, key: String, label: String, tip: String) -> void:
	var c := CheckBox.new()
	c.toggled.connect(func(on): _set_opt(key, on))
	_widgets[key] = c
	_line(parent, label, c, tip)


func _goal(parent: Control, flag: String, key: String, label: String, lo: int, hi: int, step: int) -> void:
	var hb := HBoxContainer.new()
	parent.add_child(hb)
	var c := CheckBox.new()
	c.text = label
	c.custom_minimum_size = Vector2(300, 0)
	c.toggled.connect(func(on): _set_opt(flag, on))
	hb.add_child(c)
	_widgets[flag] = c
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value_changed.connect(func(v): _set_opt(key, int(v)))
	hb.add_child(s)
	_widgets[key] = s


func _set_opt(key: String, v) -> void:
	if _busy:
		return
	if key == "difficulty":
		GameSetup.apply_difficulty(setup, int(v))
	else:
		setup[key] = v
		if not key.begins_with("goal"):
			setup["difficulty"] = GameSetup.CUSTOM
			for lv in GameSetup.CUSTOM:
				if GameSetup.matches_level(setup, lv):
					setup["difficulty"] = lv
	refresh()
	changed.emit()


func refresh() -> void:
	_busy = true
	for key in _widgets:
		var w: Control = _widgets[key]
		var v = setup.get(key)
		if w is OptionButton:
			var values: Array = w.get_meta("values")
			w.select(values.find(v) if not values.is_empty() else int(v) - int(w.get_meta("base")))
		elif w is SpinBox:
			w.value = int(v)
		elif w is CheckBox:
			w.button_pressed = bool(v)
	_busy = false
	if _rating:
		_rating.text = "Difficulty rating: %d%%  (the final score is the total score times this)" % GameSetup.rating(setup)
