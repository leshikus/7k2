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
var size_opt: OptionButton
var setup_pages: SetupPages
const SIZES := [120, 160, 200]      # the original's world is 200 x 200 (MAX_MAP_WIDTH)
var roster_check: CheckBox
var seed_edit: LineEdit
var name_edit: LineEdit
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
var mp_box: VBoxContainer
var mode_tabs: TabBar
var mode_note: Label
var kingdom_box: GridContainer
var map_box: VBoxContainer
var scn_box: VBoxContainer
var camp_box: VBoxContainer
var camp_diff: OptionButton
var camp_continue: CheckBox
var tut_box: VBoxContainer
var tut_opt: OptionButton
var tut_text: Label
var saved_box: VBoxContainer
var saved_opt: OptionButton

## The kinds of game, one tab each: [id, tab title, what it is]
const MODES := [
	["new", "New game", "A new world: choose your kingdom, the map and your opponents."],
	["scenario", "Scenario", "A premade scenario with its own map, kingdoms and goals."],
	["campaign", "Campaign", "The Fryhtan Wars: lead the Western Empire of your nationality through a campaign of battles."],
	["tutorial", "Tutorial", "The original's lessons, one step at a time."],
	["network", "Network", "Host or join a game over the network; once the others have joined, the host starts it with the settings below."],
	["saved", "Saved game", "Carry on from a saved game."],
	["editor", "Editor", "Make a scenario on a new map with these settings: place towns, buildings, armies and treasure, set up the kingdoms and their goals."],
]


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
	# the player profile (PlayerProfile::register_menu)
	var prow := HBoxContainer.new()
	vb.add_child(prow)
	profile_label = Label.new()
	profile_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prow.add_child(profile_label)
	var pbtn := Button.new()
	pbtn.text = "Change player"
	pbtn.pressed.connect(_show_profiles)
	prow.add_child(pbtn)
	_update_profile_label()

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
	setup_box.add_theme_constant_override("separation", 8)
	vb.add_child(setup_box)
	# what kind of game: one tab each, one Start button for all of them
	mode_tabs = TabBar.new()
	mode_tabs.clip_tabs = false
	for m in MODES:
		mode_tabs.add_tab(m[1])
	mode_tabs.tab_changed.connect(func(_i): _show_mode())
	setup_box.add_child(mode_tabs)
	mode_note = Label.new()
	mode_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mode_note.add_theme_font_size_override("font_size", 12)
	mode_note.add_theme_color_override("font_color", Color(0.75, 0.7, 0.6))
	setup_box.add_child(mode_note)

	# your kingdom (new game, campaign, network game, editor)
	kingdom_box = GridContainer.new()
	kingdom_box.columns = 2
	setup_box.add_child(kingdom_box)
	name_edit = _row(kingdom_box, "Kingdom name", LineEdit.new())
	race_opt = _row(kingdom_box, "Nationality", OptionButton.new())
	race_opt.item_selected.connect(func(_i): _update_picture())

	# the map and the opponents (new game, network game, editor)
	map_box = VBoxContainer.new()
	setup_box.add_child(map_box)
	var grid := GridContainer.new()
	grid.columns = 2
	map_box.add_child(grid)
	size_opt = _options(grid, "Map size", ["Small (120)", "Medium (160)", "Original (200)"], 2)
	seed_edit = _row(grid, "Map seed", LineEdit.new())
	seed_edit.text = str(randi() % 100000)
	setup_pages = SetupPages.new()
	map_box.add_child(setup_pages)
	roster_check = CheckBox.new()
	roster_check.text = "Bring the heroes and items of your profile"
	roster_check.tooltip_text = "Heroes who survived your won games, and the items your men carried (PlayerProfile)."
	setup_box.add_child(roster_check)

	# premade scenarios
	scn_box = VBoxContainer.new()
	setup_box.add_child(scn_box)
	scn_opt = OptionButton.new()
	scn_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scn_opt.item_selected.connect(func(_i): _update_scenario())
	scn_box.add_child(scn_opt)
	scn_text = Label.new()
	scn_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	scn_text.custom_minimum_size = Vector2(520, 0)
	scn_text.add_theme_font_size_override("font_size", 12)
	scn_box.add_child(scn_text)
	spectate_check = CheckBox.new()
	spectate_check.text = "Watch AI vs AI (every kingdom is computer-controlled)"
	setup_box.add_child(spectate_check)

	# the campaign: the Fryhtan Wars
	camp_box = VBoxContainer.new()
	setup_box.add_child(camp_box)
	camp_diff = OptionButton.new()
	for k in ["Difficulty 1 (easiest)", "Difficulty 2", "Difficulty 3", "Difficulty 4", "Difficulty 5 (hardest)"]:
		camp_diff.add_item(k)
	camp_diff.select(2)
	camp_box.add_child(camp_diff)
	camp_continue = CheckBox.new()
	camp_continue.text = "Continue the campaign in progress"
	camp_continue.visible = Campaign.exists()
	camp_continue.button_pressed = Campaign.exists()
	camp_continue.toggled.connect(func(_on): _show_mode())
	camp_box.add_child(camp_continue)

	# the learning campaigns: the original's tutorial lessons
	tut_box = VBoxContainer.new()
	setup_box.add_child(tut_box)
	tut_opt = OptionButton.new()
	for l in Tutorial.LESSONS:
		tut_opt.add_item(l["name"])
	tut_opt.item_selected.connect(func(_i): _show_mode())
	tut_box.add_child(tut_opt)
	tut_text = Label.new()
	tut_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tut_text.custom_minimum_size = Vector2(520, 0)
	tut_text.add_theme_font_size_override("font_size", 12)
	tut_box.add_child(tut_text)

	# a network game (Net): host or join; the host starts with the settings above
	mp_box = VBoxContainer.new()
	setup_box.add_child(mp_box)
	var mh := HBoxContainer.new()
	mp_box.add_child(mh)
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
			mp_status.text = err
		_show_mode())
	mh.add_child(hb)
	var jb := Button.new()
	jb.text = "Join"
	jb.pressed.connect(func():
		var err := Net.join(addr_edit.text.strip_edges(), port_edit.text.to_int(), _player_name(), _race_code())
		if err != "":
			mp_status.text = err
		_show_mode())
	mh.add_child(jb)
	var lb2 := Button.new()
	lb2.text = "Leave"
	lb2.pressed.connect(func():
		Net.leave()
		mp_status.text = ""
		mp_status.visible = false
		_show_mode())
	mh.add_child(lb2)
	mp_status = Label.new()
	mp_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mp_status.add_theme_font_size_override("font_size", 12)
	mp_box.add_child(mp_status)
	mp_players = Label.new()
	mp_players.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mp_box.add_child(mp_players)
	mp_status.visible = false
	mp_players.visible = false
	Net.net_status.connect(func(t):
		mp_status.text = t
		mp_status.visible = t != "")
	Net.lobby_changed.connect(_refresh_lobby)
	race_opt.item_selected.connect(func(_i):
		if Net.online():
			Net.set_race(_race_code()))

	# saved games
	saved_box = VBoxContainer.new()
	setup_box.add_child(saved_box)
	saved_opt = OptionButton.new()
	saved_box.add_child(saved_opt)
	for slot in [["quick", "Saved game"], ["autosave", "Autosave"]]:
		if SaveGame.exists(slot[0]):
			saved_opt.add_item("%s: %s" % [slot[1], SaveGame.describe(slot[0])])
			saved_opt.set_item_metadata(saved_opt.item_count - 1, slot[0])

	start_btn = Button.new()
	start_btn.text = "Start game"
	start_btn.custom_minimum_size = Vector2(0, 44)
	start_btn.add_theme_font_size_override("font_size", 18)
	start_btn.pressed.connect(_start)
	setup_box.add_child(start_btn)
	_refresh_lobby()
	_show_mode()
	var cred := Button.new()
	cred.text = "Credits"
	cred.pressed.connect(_show_credits)
	vb.add_child(cred)
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


## The original's credits (ogamcred.cpp): CREDIT.RES over Credits1.jpg.
func _show_credits() -> void:
	# The HD release's index offsets are stale (they cut names in half), so
	# take the whole text from the first entry to the end of the file.
	var d := FileAccess.get_file_as_bytes(SK2Files.find_file(Assets.install_path.path_join("Resource"), "CREDIT.RES"))
	var txt := ""
	if d.size() > 15:
		for ch in d.slice(d.decode_u32(11)):
			if ch != 13 and ch != 11:
				txt += char(ch)
	var layer := Control.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(layer)
	var bg := TextureRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture = Assets.image("Credits1.jpg")
	layer.add_child(bg)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -320
	panel.offset_right = 320
	panel.offset_top = -330
	panel.offset_bottom = 330
	layer.add_child(panel)
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	var r := RichTextLabel.new()
	r.text = txt if txt.strip_edges() != "" else "Seven Kingdoms II: The Fryhtan Wars, by Enlight Software."
	r.size_flags_vertical = Control.SIZE_EXPAND_FILL
	r.custom_minimum_size = Vector2(620, 600)
	vb.add_child(r)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(layer.queue_free)
	vb.add_child(close)


var profile_label: Label


func _update_profile_label() -> void:
	var n := Profiles.current()
	profile_label.text = "Player: %s" % (n if n != "" else "(none: games are saved for everyone)")


## The profile menu: choose a player, register a new one, or delete one.
func _show_profiles() -> void:
	var layer := PanelContainer.new()
	layer.set_anchors_preset(Control.PRESET_CENTER)
	add_child(layer)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(360, 0)
	layer.add_child(v)
	var t := Label.new()
	t.text = "Who is playing?"
	t.add_theme_font_size_override("font_size", 18)
	v.add_child(t)
	for n in Profiles.list():
		var row := HBoxContainer.new()
		v.add_child(row)
		var b := Button.new()
		b.text = n + (" ✓" if n == Profiles.current() else "")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pn: String = n
		b.pressed.connect(func():
			Profiles.login(pn)
			_update_profile_label()
			layer.queue_free())
		row.add_child(b)
		var del := Button.new()
		del.text = "Delete"
		del.tooltip_text = "Remove this player and his saved games."
		del.pressed.connect(func():
			Profiles.remove(pn)
			_update_profile_label()
			layer.queue_free()
			_show_profiles())
		row.add_child(del)
	var hb := HBoxContainer.new()
	v.add_child(hb)
	var name_in := LineEdit.new()
	name_in.placeholder_text = "New player's name"
	name_in.max_length = Profiles.NAME_LEN
	name_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(name_in)
	var ok := Button.new()
	ok.text = "Register"
	ok.pressed.connect(func():
		if Profiles.login(name_in.text):
			_update_profile_label()
			layer.queue_free())
	hb.add_child(ok)
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(layer.queue_free)
	v.add_child(close)


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
		_show_mode()
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
	_show_mode()


func _start_network() -> void:
	var cfg := GameSetup.to_config(setup_pages.setup, {
		"seed": seed_edit.text.to_int() if seed_edit.text.is_valid_int() else seed_edit.text.hash(),
		"size": SIZES[size_opt.selected],
	})
	# Config::multi_player_difficulty: the other players count as rivals
	cfg["difficulty_rating"] = GameSetup.rating_multi(setup_pages.setup, maxi(0, Net.players.size() - 1))
	Net.start_game(cfg)


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
		scn_opt.add_item("%s  (%s)" % [s["name"], ("difficulty %d" % s["difficulty"]) if s["source"] == "original" else s["source"]])
	scn_text.text = ""
	_update_scenario()
	_show_mode()


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


func _mode() -> String:
	return MODES[mode_tabs.current_tab][0] if mode_tabs else "new"


## Show the settings the chosen kind of game uses, and whether it can start.
func _show_mode() -> void:
	if mode_tabs == null or start_btn == null:
		return
	var m := _mode()
	mode_note.text = MODES[mode_tabs.current_tab][2]
	var continuing := m == "campaign" and camp_continue.button_pressed
	kingdom_box.visible = m in ["new", "network", "editor"] or (m == "campaign" and not continuing)
	map_box.visible = m in ["new", "network", "editor"]
	roster_check.visible = m == "new"
	spectate_check.visible = m in ["new", "scenario"]
	scn_box.visible = m == "scenario"
	camp_box.visible = m == "campaign"
	camp_diff.visible = not continuing
	tut_box.visible = m == "tutorial"
	mp_box.visible = m == "network"
	saved_box.visible = m == "saved"
	if m == "tutorial" and tut_opt.selected >= 0:
		tut_text.text = Tutorial.description(Tutorial.LESSONS[tut_opt.selected])
	var ok := true
	var why := ""
	match m:
		"scenario":
			ok = not scenarios.is_empty()
			why = "No scenarios were found."
		"campaign":
			ok = continuing or not _is_fryhtan_pick()
			why = "A campaign is led by a human nationality."
		"network":
			ok = Net.online() and Net.is_host and Net.players.size() >= 2
			why = "Host a game and wait for another player to join." if not Net.online() or Net.is_host else "The host starts the game."
		"saved":
			ok = saved_opt.item_count > 0
			why = "There is no saved game."
	start_btn.disabled = not ok
	start_btn.tooltip_text = "" if ok else why
	start_btn.text = "Open the editor" if m == "editor" else ("Continue" if m == "saved" or continuing else "Start game")


func _seed() -> int:
	return seed_edit.text.to_int() if seed_edit.text.is_valid_int() else seed_edit.text.hash()


## The one Start button: begins the kind of game chosen on the tabs.
func _start() -> void:
	match _mode():
		"new":
			var cfg := GameSetup.to_config(setup_pages.setup, {
				"seed": _seed(),
				"size": SIZES[size_opt.selected],
				"race": _race_code(),
				"kingdom_name": name_edit.text,
				"player_name": Profiles.current(),
				"bring_roster": roster_check.button_pressed and Profiles.current() != "",
				"autoplay": spectate_check.button_pressed,
			})
			if spectate_check.button_pressed:
				cfg["reveal"] = true
			start_game.emit(cfg)
		"scenario":
			if scn_opt.selected < 0 or scn_opt.selected >= scenarios.size():
				return
			start_game.emit({
				"scenario": scenarios[scn_opt.selected]["path"],
				"seed": randi(),
				"autoplay": spectate_check.button_pressed,
				"reveal": spectate_check.button_pressed,
			})
		"campaign":
			if camp_continue.button_pressed:
				continue_campaign.emit()
			elif _is_fryhtan_pick():
				status.text = "A campaign is led by a human nationality."
			else:
				start_campaign.emit(_race_code(), camp_diff.selected + 1)
		"tutorial":
			var l: Dictionary = Tutorial.LESSONS[tut_opt.selected]
			var path := Tutorial.map_path(l)
			if path == "":
				status.text = "The lesson's map is missing from the Tutorial folder of your install."
				return
			start_game.emit({"scenario": path, "seed": 1, "tutorial": l["id"]})
		"network":
			_start_network()
		"saved":
			if saved_opt.selected >= 0:
				load_game.emit(saved_opt.get_item_metadata(saved_opt.selected))
		"editor":
			var ecfg := GameSetup.to_config(setup_pages.setup, {"editor": true, "seed": _seed(),
				"size": SIZES[size_opt.selected], "race": _race_code(), "kingdom_name": name_edit.text})
			ecfg["reveal"] = true
			start_game.emit(ecfg)
