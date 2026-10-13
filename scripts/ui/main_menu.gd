class_name MainMenu
extends Control
## Start screen: locate the original game data and set up a new game.

signal start_game(cfg: Dictionary)
signal load_game(slot: String)
signal start_campaign(race: String, difficulty: int)
signal continue_campaign

const RACE_IMAGES := {
	"NORMAN": "Norman.jpg", "VIKING": "Viking.jpg", "CELTIC": "Celtic.jpg", "ROMAN": "Roman.jpg",
	"GREEK": "Greek.jpg", "CARTH": "Carth.jpg", "CHINESE": "Chinese.jpg", "JAPANESE": "Japanese.jpg",
	"MONGOL": "Mongol.jpg", "EGYPTIAN": "Egyptian.jpg", "PERSIAN": "Persian.jpg", "INDIAN": "Indian.jpg",
}

var path_edit: LineEdit
var status: Label
var race_opt: OptionButton
var ai_spin: SpinBox
var size_opt: OptionButton
var cash_opt: OptionButton
var towns_opt: OptionButton
var lairs_opt: OptionButton
var fryhtan_opt: OptionButton
var seed_edit: LineEdit
var name_edit: LineEdit
var reveal_check: CheckBox
var start_btn: Button
var picture: TextureRect
var setup_box: VBoxContainer
var spectate_check: CheckBox
var scn_opt: OptionButton
var scn_text: Label
var scenarios: Array = []
var addr_edit: LineEdit
var port_edit: LineEdit
var mp_status: Label
var mp_players: Label
var mp_start: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Hud.make_theme()
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.05, 0.04)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	picture = TextureRect.new()
	picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	picture.modulate = Color(1, 1, 1, 0.55)
	add_child(picture)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	# the panel scrolls when the window is too short for all of it
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(560, minf(780.0, get_viewport_rect().size.y - 24.0))
	panel.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(540, 0)
	vb.add_theme_constant_override("separation", 8)
	scroll.add_child(vb)
	var title := Label.new()
	title.text = "Seven Kingdoms II"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.45))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var sub := Label.new()
	sub.text = "The Fryhtan Wars — Godot edition"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)

	var ph := HBoxContainer.new()
	vb.add_child(ph)
	var pl := Label.new()
	pl.text = "Game folder"
	ph.add_child(pl)
	path_edit = LineEdit.new()
	path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	path_edit.placeholder_text = "Folder of your Seven Kingdoms II installation"
	path_edit.text = Assets.install_path
	ph.add_child(path_edit)
	var load_btn := Button.new()
	load_btn.text = "Load"
	load_btn.pressed.connect(_load_data)
	ph.add_child(load_btn)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(status)

	setup_box = VBoxContainer.new()
	vb.add_child(setup_box)
	var grid := GridContainer.new()
	grid.columns = 2
	setup_box.add_child(grid)
	name_edit = _row(grid, "Kingdom name", LineEdit.new())
	race_opt = _row(grid, "Nationality", OptionButton.new())
	race_opt.item_selected.connect(func(_i): _update_picture())
	ai_spin = _row(grid, "Rival kingdoms", SpinBox.new())
	ai_spin.min_value = 1
	ai_spin.max_value = 6
	ai_spin.value = 3
	size_opt = _options(grid, "Map size", ["Small (90)", "Medium (120)", "Large (160)"], 1)
	cash_opt = _options(grid, "Starting gold", ["1500", "3000", "6000"], 1)
	towns_opt = _options(grid, "Independent towns", ["Few", "Normal", "Many"], 1)
	lairs_opt = _options(grid, "Fryhtan lairs", ["Few", "Normal", "Many"], 1)
	fryhtan_opt = _options(grid, "Fryhtan kingdoms", ["None", "One", "Two"], 1)
	seed_edit = _row(grid, "Map seed", LineEdit.new())
	seed_edit.text = str(randi() % 100000)
	reveal_check = CheckBox.new()
	reveal_check.text = "Reveal the whole map"
	setup_box.add_child(reveal_check)
	spectate_check = CheckBox.new()
	spectate_check.text = "Watch AI vs AI (every kingdom is computer-controlled)"
	setup_box.add_child(spectate_check)
	start_btn = Button.new()
	start_btn.text = "Start game"
	start_btn.custom_minimum_size = Vector2(0, 40)
	start_btn.pressed.connect(_start)
	setup_box.add_child(start_btn)
	# premade scenarios of the original game
	var sh := HBoxContainer.new()
	setup_box.add_child(sh)
	var scn_label := Label.new()
	scn_label.text = "Scenario"
	sh.add_child(scn_label)
	scn_opt = OptionButton.new()
	scn_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scn_opt.item_selected.connect(func(_i): _update_scenario())
	sh.add_child(scn_opt)
	var play := Button.new()
	play.text = "Play scenario"
	play.pressed.connect(_start_scenario)
	sh.add_child(play)
	scn_text = Label.new()
	scn_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scn_text.custom_minimum_size = Vector2(520, 0)
	scn_text.add_theme_font_size_override("font_size", 12)
	setup_box.add_child(scn_text)
	# a network game (Net): host or join, then the host starts with the settings above
	var mp_box := VBoxContainer.new()
	setup_box.add_child(mp_box)
	var mh := HBoxContainer.new()
	mp_box.add_child(mh)
	var ml := Label.new()
	ml.text = "Network game"
	mh.add_child(ml)
	addr_edit = LineEdit.new()
	addr_edit.text = "127.0.0.1"
	addr_edit.placeholder_text = "Host address"
	addr_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mh.add_child(addr_edit)
	port_edit = LineEdit.new()
	port_edit.text = str(Net.PORT)
	port_edit.custom_minimum_size = Vector2(64, 0)
	mh.add_child(port_edit)
	var hb := Button.new()
	hb.text = "Host"
	hb.pressed.connect(func():
		var err := Net.host(port_edit.text.to_int(), _player_name(), _race_code())
		if err != "":
			mp_status.text = err)
	mh.add_child(hb)
	var jb := Button.new()
	jb.text = "Join"
	jb.pressed.connect(func():
		var err := Net.join(addr_edit.text.strip_edges(), port_edit.text.to_int(), _player_name(), _race_code())
		if err != "":
			mp_status.text = err)
	mh.add_child(jb)
	var lb2 := Button.new()
	lb2.text = "Leave"
	lb2.pressed.connect(func():
		Net.leave()
		mp_status.text = ""
		mp_status.visible = false)
	mh.add_child(lb2)
	mp_status = Label.new()
	mp_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mp_status.add_theme_font_size_override("font_size", 12)
	mp_box.add_child(mp_status)
	mp_players = Label.new()
	mp_players.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mp_box.add_child(mp_players)
	mp_start = Button.new()
	mp_start.text = "Start the network game"
	mp_start.visible = false
	mp_start.pressed.connect(_start_network)
	mp_box.add_child(mp_start)
	mp_status.visible = false
	mp_players.visible = false
	Net.net_status.connect(func(t):
		mp_status.text = t
		mp_status.visible = t != "")
	Net.lobby_changed.connect(_refresh_lobby)
	race_opt.item_selected.connect(func(_i):
		if Net.online():
			Net.set_race(_race_code()))
	_refresh_lobby()
	# the learning campaigns: the original's tutorial lessons
	var th := HBoxContainer.new()
	setup_box.add_child(th)
	var tl := Label.new()
	tl.text = "Tutorial"
	th.add_child(tl)
	var tut_opt := OptionButton.new()
	for l in Tutorial.LESSONS:
		tut_opt.add_item(l["name"])
	tut_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tut_opt.item_selected.connect(func(i): scn_text.text = Tutorial.description(Tutorial.LESSONS[i]))
	th.add_child(tut_opt)
	var tb := Button.new()
	tb.text = "Learn"
	tb.pressed.connect(func():
		var l: Dictionary = Tutorial.LESSONS[tut_opt.selected]
		var path := Tutorial.map_path(l)
		if path == "":
			status.text = "The lesson's map is missing from the Tutorial folder of your install."
			return
		start_game.emit({"scenario": path, "seed": 1, "tutorial": l["id"]}))
	th.add_child(tb)
	# the campaign: the Fryhtan Wars
	var ch := HBoxContainer.new()
	setup_box.add_child(ch)
	var cl := Label.new()
	cl.text = "Campaign"
	ch.add_child(cl)
	var diff := OptionButton.new()
	for k in ["Difficulty 1 (easiest)", "Difficulty 2", "Difficulty 3", "Difficulty 4", "Difficulty 5 (hardest)"]:
		diff.add_item(k)
	diff.select(2)
	diff.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ch.add_child(diff)
	var cb := Button.new()
	cb.text = "New campaign"
	cb.tooltip_text = "The Fryhtan Wars: lead the Western Empire of your nationality through a campaign of battles."
	cb.pressed.connect(func():
		if _is_fryhtan_pick():
			status.text = "A campaign is led by a human nationality."
			return
		start_campaign.emit(_race_code(), diff.selected + 1))
	ch.add_child(cb)
	if Campaign.exists():
		var cc := Button.new()
		cc.text = "Continue the campaign"
		cc.pressed.connect(func(): continue_campaign.emit())
		setup_box.add_child(cc)
	for slot in [["quick", "Load saved game"], ["autosave", "Continue from autosave"]]:
		if SaveGame.exists(slot[0]):
			var lb := Button.new()
			lb.text = "%s: %s" % [slot[1], SaveGame.describe(slot[0])]
			var sl: String = slot[0]
			lb.pressed.connect(func(): load_game.emit(sl))
			setup_box.add_child(lb)
	var ed := Button.new()
	ed.text = "Scenario editor"
	ed.tooltip_text = "Make a scenario on a new map with the settings above: place towns, buildings, armies and treasure, set up the kingdoms and their goals."
	ed.pressed.connect(func():
		var sizes := [90, 120, 160]
		start_game.emit({"editor": true, "seed": seed_edit.text.to_int() if seed_edit.text.is_valid_int() else seed_edit.text.hash(),
			"size": sizes[size_opt.selected], "race": _race_code(), "kingdom_name": name_edit.text, "ai_count": int(ai_spin.value),
			"cash": [1500, 3000, 6000][cash_opt.selected], "indep_towns": 0 if towns_opt.selected == 0 else maxi(3, int(sizes[size_opt.selected] * sizes[size_opt.selected] / 1000.0)),
			"lairs": 0 if lairs_opt.selected == 0 else 2, "fryhtan_count": fryhtan_opt.selected, "reveal": true}))
	vb.add_child(ed)
	var hall := Button.new()
	hall.text = "Hall of Fame"
	hall.pressed.connect(_show_hall)
	vb.add_child(hall)
	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(func(): get_tree().quit())
	vb.add_child(quit)
	var note := Label.new()
	note.text = "Graphics and data are read from your own copy of the game; none are included here."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", Color(0.65, 0.6, 0.5))
	vb.add_child(note)
	_load_data()


func _show_hall() -> void:
	var dlg := AcceptDialog.new()
	dlg.title = "Hall of Fame"
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.custom_minimum_size = Vector2(620, 380)
	r.text = HallOfFame.describe()
	dlg.add_child(r)
	add_child(dlg)
	dlg.popup_centered()


func _player_name() -> String:
	var n := name_edit.text.strip_edges()
	for pre in ["Kingdom of ", "The "]:
		if n.begins_with(pre):
			n = n.substr(pre.length())
	if n.ends_with(" Fryhtans"):
		n = n.substr(0, n.length() - 9)
	return n if n != "" else "Player"


func _refresh_lobby() -> void:
	if mp_players == null:
		return
	if not Net.online() or Net.players.is_empty():
		mp_players.text = ""
		mp_players.visible = false
		mp_start.visible = false
		return
	mp_players.visible = true
	var ids: Array = Net.players.keys()
	ids.sort()
	var lines := []
	for id in ids:
		var p: Dictionary = Net.players[id]
		var race := Defs.race_name(p["race"])
		for m in Defs.monsters:
			if m["unit"] == p["race"]:
				race = m["name"] + " Fryhtans"
		lines.append("%s%s — %s" % ["(host) " if id == 1 else "", p["name"], race])
	mp_players.text = "Players:
" + "
".join(lines)
	mp_start.visible = Net.is_host
	mp_start.disabled = Net.players.size() < 2


func _start_network() -> void:
	var sizes := [90, 120, 160]
	var size: int = sizes[size_opt.selected]
	var area := size * size
	Net.start_game({
		"seed": seed_edit.text.to_int() if seed_edit.text.is_valid_int() else seed_edit.text.hash(),
		"size": size,
		"ai_count": int(ai_spin.value) - 1,
		"cash": [1500, 3000, 6000][cash_opt.selected],
		"indep_towns": maxi(3, int(area / 1000.0 * [0.6, 1.0, 1.6][towns_opt.selected])),
		"lairs": maxi(1, int(area / 2600.0 * [0.5, 1.0, 1.8][lairs_opt.selected])),
		"reveal": reveal_check.button_pressed,
		"fryhtan_count": fryhtan_opt.selected,
	})


func _row(grid: GridContainer, label: String, ctl: Control) -> Control:
	var l := Label.new()
	l.text = label
	grid.add_child(l)
	ctl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctl.custom_minimum_size = Vector2(260, 0)
	grid.add_child(ctl)
	return ctl


func _options(grid: GridContainer, label: String, items: Array, sel: int) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(it)
	o.select(sel)
	_row(grid, label, o)
	return o


func _load_data() -> void:
	var p := path_edit.text.strip_edges()
	if p == "":
		p = Assets.detect_install()
		path_edit.text = p
	if Assets.ready_ok and p == Assets.install_path:
		_on_loaded()
		return
	var err := Assets.load_install(p)
	if err != "":
		status.text = err
		status.add_theme_color_override("font_color", Color(1, 0.5, 0.4))
		setup_box.visible = false
		return
	_on_loaded()


func _on_loaded() -> void:
	Defs.load_from_assets()
	status.text = "Game data loaded from " + Assets.install_path
	status.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
	setup_box.visible = true
	race_opt.clear()
	for r in Defs.races:
		race_opt.add_item(r["name"])
	# Fryhtan species follow the human nationalities, as in the original's list
	for m in Defs.monsters:
		race_opt.add_item("Fryhtans: " + m["name"])
	race_opt.select(0)
	_update_picture()
	scenarios = ScenarioFile.list_premade()
	scn_opt.clear()
	for s in scenarios:
		scn_opt.add_item("%s  (%s)" % [s["name"], ("difficulty %d" % s["difficulty"]) if s["source"] == "original" else "community"])
	scn_opt.get_parent().visible = not scenarios.is_empty()
	scn_text.text = ""


func _update_picture() -> void:
	if race_opt.item_count == 0:
		return
	var code := _race_code()
	picture.texture = Assets.image(RACE_IMAGES.get(code, "Feature1.jpg"))
	var nm := _race_name()
	if name_edit.text == "" or name_edit.text.begins_with("Kingdom of ") or name_edit.text.ends_with(" Fryhtans"):
		name_edit.text = (nm + " Fryhtans") if _is_fryhtan_pick() else ("Kingdom of " + nm)


func _is_fryhtan_pick() -> bool:
	return race_opt.selected >= Defs.races.size()


## Race code of the chosen nationality, or the species' unit code for Fryhtans.
func _race_code() -> String:
	if _is_fryhtan_pick():
		return Defs.monsters[race_opt.selected - Defs.races.size()]["unit"]
	return Defs.races[race_opt.selected]["code"]


func _race_name() -> String:
	if _is_fryhtan_pick():
		return Defs.monsters[race_opt.selected - Defs.races.size()]["name"]
	return Defs.races[race_opt.selected]["name"]


func _update_scenario() -> void:
	if scn_opt.selected < 0 or scn_opt.selected >= scenarios.size():
		return
	var s: Dictionary = scenarios[scn_opt.selected]
	scn_text.text = s["text"]
	var img_path: String = s["path"].get_basename() + ".scp"
	for cand in [img_path, img_path.get_base_dir().path_join(img_path.get_file().capitalize().replace(" ", ""))]:
		if FileAccess.file_exists(cand):
			var img := Image.new()
			if img.load_jpg_from_buffer(FileAccess.get_file_as_bytes(cand)) == OK:
				picture.texture = ImageTexture.create_from_image(img)
				return


func _start_scenario() -> void:
	if scn_opt.selected < 0 or scn_opt.selected >= scenarios.size():
		return
	start_game.emit({
		"scenario": scenarios[scn_opt.selected]["path"],
		"seed": randi(),
		"autoplay": spectate_check.button_pressed,
		"reveal": reveal_check.button_pressed or spectate_check.button_pressed,
	})


func _start() -> void:
	var sizes := [90, 120, 160]
	var size: int = sizes[size_opt.selected]
	var area := size * size
	var towns_mul: float = [0.6, 1.0, 1.6][towns_opt.selected]
	var lairs_mul: float = [0.5, 1.0, 1.8][lairs_opt.selected]
	start_game.emit({
		"seed": seed_edit.text.to_int() if seed_edit.text.is_valid_int() else seed_edit.text.hash(),
		"size": size,
		"race": _race_code(),
		"kingdom_name": name_edit.text,
		"ai_count": int(ai_spin.value),
		"cash": [1500, 3000, 6000][cash_opt.selected],
		"indep_towns": maxi(3, int(area / 1000.0 * towns_mul)),
		"lairs": maxi(1, int(area / 2600.0 * lairs_mul)),
		"reveal": reveal_check.button_pressed or spectate_check.button_pressed,
		"fryhtan_count": fryhtan_opt.selected,
		"autoplay": spectate_check.button_pressed,
	})
