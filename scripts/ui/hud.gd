class_name Hud
extends CanvasLayer
## In-game interface: resource bar, info/action panel, minimap, messages,
## diplomacy window and game-over screen.

signal build_requested(code: String)
signal item_target_requested(u: Unit)
signal spell_target_requested(f: Firm, spell: String)
signal rally_requested(f: Firm)
signal caravan_route_requested(u: Unit)
signal found_town_requested(u: Unit)
signal cast_target_requested(u: Unit)

var inspected_treasure: Treasure = null   # a scroll or item clicked on the map
signal center_on(loc: Vector2)
signal move_selected_to(loc: Vector2)
signal menu_new_game
signal speed_changed
signal save_requested
signal load_requested

const PANEL_W := 300

var game: Game
var camera: CameraRig

var top_label: RichTextLabel
var speed_buttons: Array[Button] = []
var panel: PanelContainer
var minimap: Minimap
var title_label: Label
var portrait: TextureRect
var info_label: RichTextLabel
var actions: GridContainer
var log_box: VBoxContainer
var diplo: PanelContainer
var diplo_list: VBoxContainer
var overlay: PanelContainer
var overlay_label: Label
var overlay_image: TextureRect
var overlay_new_btn: Button
var chat_edit: LineEdit
var reports: ReportsWindow
var tutorial_panel: TutorialPanel
var ui_root: Control
var editor: ScenarioEditorWindow
var pause_menu: PanelContainer
var tooltip_label: Label
var build_menu_open := false

var _refresh_timer := 0.0
var _last_sel_key := ""
var _messages: Array = []
var _top_buttons: HBoxContainer


func setup(g: Game, cam: CameraRig) -> void:
	game = g
	camera = cam
	_build_ui()
	minimap.setup(g, cam)
	g.message.connect(_on_message)
	g.game_over.connect(_on_game_over)


static func make_theme() -> Theme:
	var t := Theme.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.11, 0.09, 0.07, 0.94)
	bg.border_color = Color(0.55, 0.43, 0.22)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(3)
	bg.set_content_margin_all(8)
	t.set_stylebox("panel", "PanelContainer", bg)
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(0.27, 0.21, 0.13)
	btn.border_color = Color(0.62, 0.5, 0.27)
	btn.set_border_width_all(1)
	btn.set_corner_radius_all(3)
	btn.set_content_margin_all(5)
	var hov := btn.duplicate()
	hov.bg_color = Color(0.38, 0.29, 0.16)
	var prs := btn.duplicate()
	prs.bg_color = Color(0.5, 0.38, 0.18)
	var dis := btn.duplicate()
	dis.bg_color = Color(0.18, 0.16, 0.14)
	dis.border_color = Color(0.3, 0.27, 0.22)
	t.set_stylebox("normal", "Button", btn)
	t.set_stylebox("hover", "Button", hov)
	t.set_stylebox("pressed", "Button", prs)
	t.set_stylebox("disabled", "Button", dis)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", Color(0.96, 0.9, 0.75))
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.47, 0.42))
	t.set_color("font_color", "Label", Color(0.95, 0.9, 0.78))
	t.set_color("default_color", "RichTextLabel", Color(0.93, 0.88, 0.76))
	t.set_font_size("font_size", "Button", 13)
	t.set_font_size("font_size", "Label", 13)
	t.set_font_size("normal_font_size", "RichTextLabel", 13)
	t.set_font_size("bold_font_size", "RichTextLabel", 13)
	return t


func _build_ui() -> void:
	var root := Control.new()
	ui_root = root
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = make_theme()
	add_child(root)

	# --- top bar
	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_bottom = 38
	root.add_child(top)
	var hb := HBoxContainer.new()
	top.add_child(hb)
	top_label = RichTextLabel.new()
	top_label.bbcode_enabled = true
	top_label.fit_content = true
	top_label.scroll_active = false
	top_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	top_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(top_label)
	# the original's help for its top bar readouts (HELP.RES screen areas)
	top_label.mouse_filter = Control.MOUSE_FILTER_PASS
	top_label.tooltip_text = "
".join(["Treasure", "Food", "Reputation", "Date", "Life Points"].map(func(k): return HelpText.area_text(k)).filter(func(x): return x != ""))
	for s in [["⏸", 0.0, "Pause"], ["▶", 1.0, "Normal speed"], ["⏩", 2.0, "Double speed"], ["⏭", 4.0, "Four times as fast"]]:
		var b := Button.new()
		b.text = s[0]
		b.tooltip_text = s[2]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(34, 0)
		var spd: float = s[1]
		b.pressed.connect(func(): _set_speed(spd))
		hb.add_child(b)
		speed_buttons.append(b)
	var dip := Button.new()
	_icon_button(dip, "🤝", "Diplomacy")
	dip.pressed.connect(toggle_diplomacy)
	hb.add_child(dip)
	var spy_btn := Button.new()
	_icon_button(spy_btn, "🕵", "Spies")
	spy_btn.pressed.connect(toggle_spies)
	hb.add_child(spy_btn)
	_top_buttons = hb
	var rep_btn := Button.new()
	_icon_button(rep_btn, "📊", "Reports: Kingdoms F1, Towns F2, Economy F3, Trade F4, Military F5, Technology F6, Espionage F7, Ranking F8")
	rep_btn.pressed.connect(func(): reports.open())
	hb.add_child(rep_btn)
	var menu := Button.new()
	_icon_button(menu, "☰", "Menu")
	menu.pressed.connect(toggle_pause_menu)
	hb.add_child(menu)

	# --- right panel
	panel = PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -PANEL_W
	panel.offset_top = 40
	root.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)
	minimap = Minimap.new()
	minimap.custom_minimum_size = Vector2(PANEL_W - 20, 150)
	minimap.jump_to.connect(func(l): center_on.emit(l))
	minimap.order_to.connect(func(l): move_selected_to.emit(l))
	vb.add_child(minimap)
	# map mode buttons (MAP-1, MAP-2, MAP-3), the filters and Hide Buildings
	var mrow := HBoxContainer.new()
	vb.add_child(mrow)
	for spec in [["⛰", "Terrain Map", func(): minimap.set_mode(Minimap.Mode.TERRAIN)],
			["🗺", "World Political Map (again: kingdoms' zones)", func(): minimap.set_mode(Minimap.Mode.POWER)],
			["⚖", "Trade Map", func(): minimap.set_mode(Minimap.Mode.TRADE)],
			["🏳", "NATION", func(): minimap.toggle_filter_nation()],
			["◈", "OBJECT", func(): minimap.toggle_filter_kind()],
			["🙈", "Hide Buildings", func():
				game.hide_buildings = not game.hide_buildings]]:
		var mb := Button.new()
		mb.text = spec[0]
		mb.add_theme_font_size_override("font_size", 16)
		mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var h := HelpText.by_code(spec[1])
		mb.tooltip_text = (h["title"] + ": " + h["text"]) if not h.is_empty() else HelpText.area_text(spec[1])
		if mb.tooltip_text == "":
			mb.tooltip_text = spec[1]
		mb.pressed.connect(spec[2])
		mrow.add_child(mb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	portrait = TextureRect.new()
	portrait.custom_minimum_size = Vector2(64, 48)
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	head.add_child(portrait)
	title_label = Label.new()
	title_label.add_theme_font_size_override("font_size", 16)
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)
	info_label = RichTextLabel.new()
	info_label.bbcode_enabled = true
	info_label.fit_content = true
	info_label.scroll_active = false
	info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(info_label)
	actions = GridContainer.new()
	actions.columns = 4
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inner.add_child(actions)
	tooltip_label = Label.new()
	tooltip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tooltip_label.add_theme_color_override("font_color", Color(0.8, 0.78, 0.65))
	tooltip_label.add_theme_font_size_override("font_size", 12)
	tooltip_label.custom_minimum_size = Vector2(PANEL_W - 24, 0)
	inner.add_child(tooltip_label)

	# --- message log
	log_box = VBoxContainer.new()
	log_box.anchor_top = 1.0
	log_box.anchor_bottom = 1.0
	log_box.offset_left = 10
	log_box.offset_top = -150
	log_box.offset_bottom = -10
	log_box.offset_right = 700
	log_box.alignment = BoxContainer.ALIGNMENT_END
	log_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(log_box)

	# --- diplomacy window
	diplo = PanelContainer.new()
	diplo.position = Vector2(200, 80)
	diplo.custom_minimum_size = Vector2(620, 0)
	diplo.visible = false
	root.add_child(diplo)
	var dv := VBoxContainer.new()
	diplo.add_child(dv)
	var dt := Label.new()
	dt.text = "Diplomacy"
	dt.add_theme_font_size_override("font_size", 18)
	dv.add_child(dt)
	diplo_list = VBoxContainer.new()
	dv.add_child(diplo_list)
	var dclose := Button.new()
	_icon_button(dclose, "✖", "Close")
	dclose.pressed.connect(toggle_diplomacy)
	dv.add_child(dclose)

	# --- reports
	reports = ReportsWindow.new()
	reports.game = game
	root.add_child(reports)

	# --- pause menu
	pause_menu = PanelContainer.new()
	pause_menu.set_anchors_preset(Control.PRESET_CENTER)
	pause_menu.visible = false
	root.add_child(pause_menu)
	var pv := VBoxContainer.new()
	pv.custom_minimum_size = Vector2(240, 0)
	pause_menu.add_child(pv)
	var pt := Label.new()
	pt.text = "Game paused"
	pt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(pt)
	var reveal := func():
		game.reveal_all = not game.reveal_all
		game._update_fog()
	var do_save := func():
		save_requested.emit()
		toggle_pause_menu()
	var do_load := func(): load_requested.emit()
	var prow := HBoxContainer.new()
	prow.alignment = BoxContainer.ALIGNMENT_CENTER
	pv.add_child(prow)
	var hint := Label.new()
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(hint)
	for item in [["▶", "Resume", toggle_pause_menu], ["💾", "Save game (Ctrl+S)", do_save], ["📂", "Load game (F9)", do_load], ["⚙", "Options", toggle_options],
			["👁", "Reveal map (cheat)", reveal],
			["🧠", "Computer's information (cheat)", func():
				GameOptions.set_opt("show_ai_info", not GameOptions.get_opt("show_ai_info"))
				game.notify("Computer's information %s." % ("shown" if GameOptions.get_opt("show_ai_info") else "hidden"), Vector2(-1, -1))],
			["🆕", "New game", func(): menu_new_game.emit()], ["🚪", "Quit", func(): get_tree().quit()]]:
		var b := Button.new()
		_icon_button(b, item[0], item[1])
		b.custom_minimum_size = Vector2(56, 52)
		b.add_theme_font_size_override("font_size", 26)
		var words: String = item[1]
		b.mouse_entered.connect(func(): hint.text = words)
		b.pressed.connect(item[2])
		prow.add_child(b)

	# --- game over overlay
	overlay = PanelContainer.new()
	overlay.set_anchors_preset(Control.PRESET_CENTER)
	overlay.visible = false
	root.add_child(overlay)
	var ov := VBoxContainer.new()
	overlay.add_child(ov)
	overlay_image = TextureRect.new()
	overlay_image.custom_minimum_size = Vector2(480, 300)
	overlay_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	overlay_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ov.add_child(overlay_image)
	overlay_label = Label.new()
	overlay_label.add_theme_font_size_override("font_size", 20)
	overlay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	overlay_label.custom_minimum_size = Vector2(480, 0)
	ov.add_child(overlay_label)
	var ob := Button.new()
	ob.text = "New game"
	ob.pressed.connect(func(): menu_new_game.emit())
	ov.add_child(ob)
	overlay_new_btn = ob
	var oq := Button.new()
	oq.text = "Quit"
	oq.pressed.connect(func(): get_tree().quit())
	ov.add_child(oq)
	_sync_speed_buttons()
	# network game: a line to talk to the other players (Enter)
	chat_edit = LineEdit.new()
	chat_edit.placeholder_text = "Message to the other players (Enter to send, Esc to close)"
	chat_edit.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	chat_edit.offset_left = -260
	chat_edit.offset_right = 260
	chat_edit.offset_top = -96
	chat_edit.offset_bottom = -64
	chat_edit.visible = false
	chat_edit.text_submitted.connect(func(t):
		if t.strip_edges() != "":
			Net.say(t.strip_edges())
		chat_edit.text = ""
		chat_edit.visible = false
		chat_edit.release_focus())
	root.add_child(chat_edit)


func open_chat() -> void:
	if not Net.active:
		return
	chat_edit.visible = true
	chat_edit.grab_focus()


## True when the mouse is over an interface element (the map should ignore it).
func is_over_ui(p: Vector2) -> bool:
	for c in [panel, diplo, pause_menu, overlay, spies_panel, reports, editor, tutorial_panel, chat_edit]:
		if c == null:
			continue
		if c.visible and c.get_global_rect().has_point(p):
			return true
	return p.y < 40


func _set_speed(s: float) -> void:
	if Net.active and not Net.is_host:
		game.notify("The host sets the game speed.", Vector2(-1, -1))
		return
	if s == 0.0:
		_do(game, "set_paused", [not game.paused])
	else:
		_do(game, "set_speed", [s])
	_sync_speed_buttons()
	speed_changed.emit()


func _sync_speed_buttons() -> void:
	if game == null or speed_buttons.is_empty():
		return
	speed_buttons[0].button_pressed = game.paused
	for i in range(1, 4):
		speed_buttons[i].button_pressed = not game.paused and game.speed == [0.0, 1.0, 2.0, 4.0][i]


var options_panel: PanelContainer


## The Options menu (ooptmenu.cpp): sound and music volume, help, news, unit
## identities, unit paths, inside information, scrolling speed. Kept between games.
func toggle_options() -> void:
	if options_panel == null:
		options_panel = PanelContainer.new()
		options_panel.set_anchors_preset(Control.PRESET_CENTER)
		pause_menu.get_parent().add_child(options_panel)
		var v := VBoxContainer.new()
		options_panel.add_child(v)
		var t := Label.new()
		t.text = "Options"
		t.add_theme_font_size_override("font_size", 18)
		v.add_child(t)
		var grid := GridContainer.new()
		grid.columns = 2
		v.add_child(grid)
		var choice := func(label: String, key: String, items: Array, values: Array):
			var l := Label.new()
			l.text = label
			grid.add_child(l)
			var ob := OptionButton.new()
			for it in items:
				ob.add_item(it)
			ob.select(maxi(0, values.find(GameOptions.get_opt(key))))
			ob.item_selected.connect(func(i): GameOptions.set_opt(key, values[i]))
			grid.add_child(ob)
		var slider := func(label: String, key: String, lo: float, hi: float):
			var l := Label.new()
			l.text = label
			grid.add_child(l)
			var sl := HSlider.new()
			sl.min_value = lo
			sl.max_value = hi
			sl.step = 1
			sl.custom_minimum_size = Vector2(180, 0)
			sl.value = float(GameOptions.get_opt(key))
			sl.value_changed.connect(func(x): GameOptions.set_opt(key, int(x)))
			grid.add_child(sl)
		slider.call("Sound effects volume", "sfx_volume", 0, 100)
		slider.call("Music volume", "music_volume", 0, 100)
		choice.call("Help", "help_mode", ["None", "Brief", "Detailed"], [0, 1, 2])
		choice.call("Display news", "news", ["Major news", "All news"], [0, 1])
		choice.call("Show unit identities", "show_unit_icons", ["When pointed at", "Always"], [0, 1])
		choice.call("Show unit paths", "show_unit_path", ["No", "Main map", "World map", "Both"], [0, 1, 2, 3])
		choice.call("Inside information", "inside_info", ["None", "Cursor", "Always"], [0, 1, 2])
		choice.call("Reports background", "opaque_report", ["Transparent", "Opaque"], [0, 1])
		choice.call("Scrolling method", "scroll_method", ["Comfort", "Speed"], [0, 1])
		slider.call("Scrolling speed", "scroll_speed", 1, 10)
		var close := Button.new()
		_icon_button(close, "✖", "Close")
		close.pressed.connect(func(): options_panel.visible = false)
		v.add_child(close)
		options_panel.visible = false
	options_panel.visible = not options_panel.visible


func toggle_pause_menu() -> void:
	pause_menu.visible = not pause_menu.visible
	game.paused = pause_menu.visible
	_sync_speed_buttons()


var spies_panel: PanelContainer
var spies_list: VBoxContainer


func toggle_spies() -> void:
	if spies_panel == null:
		spies_panel = PanelContainer.new()
		spies_panel.position = Vector2(200, 80)
		spies_panel.custom_minimum_size = Vector2(620, 0)
		diplo.get_parent().add_child(spies_panel)
		var v := VBoxContainer.new()
		spies_panel.add_child(v)
		var t := Label.new()
		t.text = "Spies"
		t.add_theme_font_size_override("font_size", 18)
		v.add_child(t)
		spies_list = VBoxContainer.new()
		v.add_child(spies_list)
		var close := Button.new()
		_icon_button(close, "✖", "Close")
		close.pressed.connect(func(): spies_panel.visible = false)
		v.add_child(close)
		spies_panel.visible = false
	spies_panel.visible = not spies_panel.visible
	if spies_panel.visible:
		_fill_spies()


func _fill_spies() -> void:
	for c in spies_list.get_children():
		c.queue_free()
	var mine := game.units.filter(func(u): return u.is_spy and u.nation_id == game.player_id and not u.dead)
	if mine.is_empty():
		var l := Label.new()
		l.text = "You have no spies. Build an Espionage College and train some."
		spies_list.add_child(l)
		return
	for u in mine:
		var row := HBoxContainer.new()
		spies_list.add_child(row)
		var l := Label.new()
		var where := "in %s" % u.spy_place.display_name() if u.spy_place and is_instance_valid(u.spy_place) and u.has_meta("hidden") else "in the field"
		if u.cloak_id > 0 and game.nation(u.cloak_id):
			where += ", disguised as %s" % game.nation(u.cloak_id).name
		l.text = "%s (skill %d) — %s" % [u.unit_name, int(u.spy_skill), where]
		l.custom_minimum_size = Vector2(330, 0)
		row.add_child(l)
		if u.has_meta("hidden") and u.spy_place.nation_id != game.player_id:
			var mode := Button.new()
			_icon_button(mode, "🗣" if u.spy_action == "dissent" else "💤", "Sow dissent" if u.spy_action == "dissent" else "Sleep")
			mode.tooltip_text = "Click to switch between sowing dissent and lying low."
			mode.pressed.connect(func():
				_do(u, "set", ["spy_action", "idle" if u.spy_action == "dissent" else "dissent"])
				_fill_spies.call_deferred())
			row.add_child(mode)
		var go := Button.new()
		_icon_button(go, "👁", "Show")
		go.pressed.connect(func():
			var o: GameObj = u.spy_place if u.has_meta("hidden") else u
			for x in game.selected:
				if is_instance_valid(x):
					x.selected = false
			game.selected = [o]
			o.selected = true
			camera.focus_on(o.center_loc()))
		row.add_child(go)
		if u.has_meta("hidden"):
			var rc := Button.new()
			_icon_button(rc, "↩", "Recall")
			rc.pressed.connect(func():
				_do(game, "spy_leave", [u])
				_fill_spies.call_deferred())
			row.add_child(rc)


func toggle_diplomacy() -> void:
	diplo.visible = not diplo.visible
	if diplo.visible and tutorial_panel and tutorial_panel.tutorial:
		tutorial_panel.tutorial.press("<diplomacy>")
	if diplo.visible:
		_fill_diplomacy()


func _fill_diplomacy() -> void:
	for c in diplo_list.get_children():
		c.queue_free()
	var p := game.player()
	# messages waiting for our answer (TalkRes: the reply choices)
	for m in game.talks.filter(func(x): return x["to"] == p.id):
		var row0 := HBoxContainer.new()
		diplo_list.add_child(row0)
		var ml := Label.new()
		ml.text = Diplomacy.describe(game, m)
		ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ml.custom_minimum_size = Vector2(380, 0)
		ml.add_theme_color_override("font_color", Color(1, 0.85, 0.45))
		row0.add_child(ml)
		for yes in [true, false]:
			var rb := Button.new()
			_icon_button(rb, "✔" if yes else "✖", "Accept" if yes else "Reject")
			var mm: Dictionary = m
			var y: bool = yes
			rb.pressed.connect(func():
				_do(game, "talk_reply", [mm["from"], mm["to"], mm["id"], y])
				_fill_diplomacy.call_deferred())
			row0.add_child(rb)
	for n in game.nations:
		if n.id == p.id:
			continue
		var row := HBoxContainer.new()
		diplo_list.add_child(row)
		var l := RichTextLabel.new()
		l.bbcode_enabled = true
		l.fit_content = true
		l.scroll_active = false
		l.custom_minimum_size = Vector2(380, 0)
		var status: Variant = "[color=#888]destroyed[/color]" if not n.alive else Defs.RELATION_NAMES[p.relation(n.id)]
		if n.alive and Diplomacy.has_trade(p, n.id):
			status = str(status) + ", trade treaty"
		var ratio := game.military_strength(n.id) / maxf(1.0, game.military_strength(p.id))
		var strength := "weaker" if ratio < 0.8 else ("stronger" if ratio > 1.25 else "similar")
		l.text = "[color=#%s]■[/color] [b]%s[/b] — %s
   Reputation %d, army %s than yours, cash $%d, food %d" % [n.color.to_html(false), n.name, status, int(n.reputation), strength, int(n.cash), int(n.food)]
		row.add_child(l)
		if not n.alive:
			continue
		var rel := p.relation(n.id)
		if game.peace_offers.get(p.id, {}).has(n.id) and rel <= Defs.Relation.NEUTRAL:
			var acc := Button.new()
			_icon_button(acc, "🕊", "Accept peace")
			var nid3 := n.id
			acc.pressed.connect(func():
				_do(game, "make_peace", [nid3, p.id])
				_fill_diplomacy.call_deferred())
			row.add_child(acc)
		var talk := MenuButton.new()
		_icon_button(talk, "✉ ▾", "Send message")
		talk.flat = false
		var pm := talk.get_popup()
		var opts := _talk_options(p, n)
		for i in opts.size():
			pm.add_item(opts[i][0], i)
		talk.disabled = opts.is_empty()
		var to_id := n.id
		pm.id_pressed.connect(func(i):
			var o: Array = opts[i]
			_do(game, "talk", [p.id, to_id, o[1], o[2], o[3]])
			_fill_diplomacy.call_deferred())
		row.add_child(talk)
		if rel != Defs.Relation.WAR and rel >= Defs.Relation.PEACE:
			var w := Button.new()
			_icon_button(w, "⚔", "Declare war")
			w.tooltip_text = "Breaking a treaty costs reputation."
			var nid2 := n.id
			w.pressed.connect(func():
				_do(game, "declare_war", [p.id, nid2])
				_fill_diplomacy.call_deferred())
			row.add_child(w)
	if not game.talk_log.is_empty():
		var hist := Label.new()
		var lines: Array = []
		for e in game.talk_log.slice(-6):
			if e["from"] == p.id or e["to"] == p.id:
				lines.append(Diplomacy.describe(game, e) + ((" — " + e["result"]) if e["result"] != "" else ""))
		hist.text = "Recent messages:
" + "
".join(lines) if not lines.is_empty() else ""
		hist.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hist.add_theme_color_override("font_color", Color(0.7, 0.7, 0.65))
		diplo_list.add_child(hist)


## The messages the player may send `n` now, as [label, talk id, para1, para2]
## (TalkRes::add_talk_choice and its sub-menus of amounts, technologies, kingdoms).
func _talk_options(p: Nation, n: Nation) -> Array:
	var out: Array = []
	for id in Diplomacy.TALKS:
		if not Diplomacy.can_send(game, p.id, n.id, id):
			continue
		var label: String = Diplomacy.TALKS[id][0]
		match id:
			"GIVE_TRIBUTE", "GIVE_AID", "DEMAND_TRIBUTE", "DEMAND_AID":
				for amt in Diplomacy.AMOUNTS:
					if id.begins_with("GIVE") and p.cash < amt:
						continue
					out.append(["%s: $%d" % [label, amt], id, amt, 0])
			"BUY_FOOD":
				for q in Diplomacy.FOOD_QTY:
					for pr in Diplomacy.FOOD_PRICES:
						if p.cash >= q * pr / 10.0:
							out.append(["%s: %d at $%d per 10" % [label, q, pr], id, q, pr])
			"EMBARGO", "REQUEST_WAR":
				for t in Diplomacy.third_parties(game, p.id, n.id, id):
					out.append(["%s against the %s" % [label, game.nation(t).name], id, t, 0])
			"EXCHANGE_TECH":
				for pr in Diplomacy.tech_pairs(p, n):
					out.append(["%s: our %s for their %s" % [label, Defs.tech_def(pr[0])["name"], Defs.tech_def(pr[1])["name"]], id, pr[0], pr[1]])
			"REQUEST_SURRENDER":
				var offer := int(n.cash * 1.25 / 500.0 + 1) * 500
				if p.cash >= offer:
					out.append(["%s for $%d" % [label, offer], id, offer, 0])
			_:
				out.append([label, id, 0, 0])
	return out


func _on_message(text: String, _loc: Vector2) -> void:
	if reports:
		reports.add_news(game.date_string(), text)
	# NewsArray::disp: major news only, as chosen (and always in a tutorial)
	if game.last_message_minor and (int(GameOptions.get_opt("news")) == 0 or game.config.has("tutorial")):
		return
	var l := Label.new()
	l.text = "[%s] %s" % [game.date_string(), text]
	l.add_theme_color_override("font_color", Color(1, 0.93, 0.7))
	l.add_theme_color_override("font_shadow_color", Color.BLACK)
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	log_box.add_child(l)
	_messages.append([l, 12.0])
	while log_box.get_child_count() > 7:
		var c := log_box.get_child(0)
		log_box.remove_child(c)
		c.queue_free()
		_messages.pop_front()


func _on_game_over(victory: bool, text: String) -> void:
	overlay.visible = true
	overlay_label.text = text
	overlay_image.texture = Assets.image("Huwin01.jpg" if victory else "Losegame.jpg")
	# the final score and the Hall of Fame, for games of one player (ogamend.cpp)
	if game.observer() or Net.active or game.campaign_battle != null or game.config.get("campaign", false):
		return
	var p := game.player()
	if p == null:
		return
	var total := Goals.total_score(game, p)
	var rating := HallOfFame.difficulty_rating(game.config)
	var final_score := total * rating / 100
	overlay_label.text += "

Total score %d × difficulty %d%% = final score %d" % [total, rating, final_score]
	var place := HallOfFame.add(game, final_score, rating)
	if place > 0:
		overlay_label.text += "
You enter the Hall of Fame in place %d!" % place


## The scenario editor's window.
func open_editor() -> ScenarioEditorWindow:
	editor = ScenarioEditorWindow.new()
	editor.game = game
	ui_root.add_child(editor)
	return editor


## A lesson of the learning campaign: its box over the map.
func start_tutorial(t: Tutorial) -> void:
	tutorial_panel = TutorialPanel.new()
	tutorial_panel.tutorial = t
	ui_root.add_child(tutorial_panel)
	tutorial_panel.show_target.connect(func(l): center_on.emit(l))
	# a top bar button brings the hidden lesson box back
	var tb := Button.new()
	tb.text = "Tutorial"
	tb.pressed.connect(func(): tutorial_panel.visible = not tutorial_panel.visible)
	_top_buttons.add_child(tb)
	_top_buttons.move_child(tb, 0)


## x: clear the news messages (NewsArray::clear_news_disp).
func clear_messages() -> void:
	for c in log_box.get_children():
		c.queue_free()
	_messages.clear()


## A campaign battle: the end-of-battle panel leads back to the campaign.
func set_campaign_continue(text: String, on_continue: Callable) -> void:
	overlay_label.text = text
	for c in overlay_new_btn.pressed.get_connections():
		overlay_new_btn.pressed.disconnect(c["callable"])
	overlay_new_btn.text = "Continue the campaign"
	overlay_new_btn.pressed.connect(on_continue)


# --------------------------------------------------------------- refresh ---

func _process(delta: float) -> void:
	if game == null:
		return
	for m in _messages.duplicate():
		m[1] -= delta
		if m[1] < 2.0 and is_instance_valid(m[0]):
			m[0].modulate.a = maxf(0.0, m[1] / 2.0)
		if m[1] <= 0.0:
			_messages.erase(m)
			if is_instance_valid(m[0]):
				m[0].queue_free()
	_refresh_timer -= delta
	if _refresh_timer > 0.0:
		return
	_refresh_timer = 0.25
	_update_top()
	refresh_selection()


func _update_top() -> void:
	if game.observer():
		var parts := ["[b]AI vs AI[/b]"]
		for n in game.nations:
			if n.alive:
				parts.append("[color=#%s]■[/color] %s" % [n.color.to_html(false), n.name])
		var t := "   ".join(parts) + "   [color=#c8c0a8]%s[/color]   [color=#a8b8d0]%s[/color]" % [game.date_string(), game.weather.describe()]
		if game.paused:
			t += "   [color=#ff8060]PAUSED[/color]"
		top_label.text = t
		return
	var p := game.player()
	var txt := "[color=#%s]■[/color] [b]%s[/b]   Gold [color=#ffd860]%d[/color]   Food [color=#a0e070]%d[/color]   Reputation %d" % [
		p.color.to_html(false), p.name, int(p.cash), int(p.food), int(p.reputation)]
	if p.is_fryhtan:
		txt = "[color=#%s]■[/color] [b]%s[/b]   Gold [color=#ffd860]%d[/color]   Life points [color=#80e0a0]%d[/color]   Reputation %d" % [
			p.color.to_html(false), p.name, int(p.cash), int(p.live_points), int(p.reputation)]
	if p.prayer_points > 0:
		txt += "   Prayer %d" % int(p.prayer_points)
	var pop := 0
	for t in game.towns:
		if t.nation_id == p.id:
			pop += t.population
	txt += "   Population %d   [color=#c8c0a8]%s[/color]   [color=#a8b8d0]%s[/color]" % [pop, game.date_string(), game.weather.describe()]
	if game.paused:
		txt += "   [color=#ff8060]PAUSED[/color]"
	top_label.text = txt


## Rebuilds the info panel when the selection changes, updates text otherwise.
func refresh_selection(force := false) -> void:
	var sel: Array = game.selected.filter(func(o): return is_instance_valid(o) and not o.dead)
	var key := ",".join(sel.map(func(o): return str(o.obj_id))) + "|" + str(build_menu_open)
	if sel.size() == 1 and sel[0] is Firm and Training.is_train_firm(sel[0]):
		key += "|" + Training.signature(sel[0])     # the buttons follow the trainees
	var rebuild := force or key != _last_sel_key
	_last_sel_key = key
	if sel.is_empty() and is_instance_valid(inspected_treasure) and inspected_treasure.is_inside_tree():
		portrait.texture = null
		title_label.text = inspected_treasure.title()
		info_label.text = inspected_treasure.description()
		if rebuild:
			_clear_actions()
		return
	if sel.is_empty():
		portrait.texture = null
		title_label.text = game.player().name if not game.observer() else "Kingdoms"
		info_label.text = _kingdom_summary() if not game.observer() else _scoreboard()
		if rebuild:
			_clear_actions()
		return
	var o: GameObj = sel[0]
	if sel.size() > 1:
		portrait.texture = null
		title_label.text = "%d units" % sel.size()
		var counts := {}
		for u in sel:
			var tn: String = u.type_name() if u is Unit else u.display_name()
			counts[tn] = counts.get(tn, 0) + 1
		var lines := []
		for k in counts:
			lines.append("%d × %s" % [counts[k], k])
		info_label.text = "\n".join(lines) + "\n\n[color=#b0a890]Right-click ground to move, an enemy to attack, a camp to garrison it.[/color]"
		if rebuild:
			_unit_actions(sel.filter(func(x): return x is Unit))
		return
	if o is Unit:
		_show_unit(o as Unit, rebuild)
	elif o is Town:
		_show_town(o as Town, rebuild)
	elif o is Firm:
		_show_firm(o as Firm, rebuild)


## Observer mode: every kingdom's strength side by side.
func _scoreboard() -> String:
	var s := ""
	for n in game.nations:
		var towns := game.towns.filter(func(t): return t.nation_id == n.id)
		var pop := 0
		for t in towns:
			pop += t.population
		var firms := game.firms.filter(func(f): return f.nation_id == n.id).size()
		var units := game.units.filter(func(u): return u.nation_id == n.id and not u.dead).size()
		s += "[color=#%s]■[/color] [b]%s[/b]%s
" % [n.color.to_html(false), n.name, "" if n.alive else "  [color=#ff8060](fallen)[/color]"]
		if not n.alive:
			continue
		if n.is_fryhtan:
			s += "   Lairs %d  Brood %d  Life points %d
" % [firms, units, int(n.live_points)]
		else:
			s += "   Towns %d (pop %d)  Buildings %d
   Units %d  Gold %d  Food %d
" % [towns.size(), pop, firms, units, int(n.cash), int(n.food)]
		var war := game.nations.filter(func(o): return o != n and o.alive and n.relation(o.id) == Defs.Relation.WAR)
		if not war.is_empty():
			s += "   At war with: %s
" % ", ".join(war.map(func(o): return o.name))
	s += "
[color=#b0a890]Every kingdom is computer-controlled. Click anything to inspect it; 2x / 4x speed up the game.[/color]"
	return s


func _kingdom_summary() -> String:
	var p := game.player()
	var towns := game.towns.filter(func(t): return t.nation_id == p.id).size()
	var firms := game.firms.filter(func(f): return f.nation_id == p.id).size()
	var units := game.units.filter(func(u): return u.nation_id == p.id and not u.dead).size()
	var s := "Towns: %d\nBuildings: %d\nUnits: %d\nIncome this year: %d\nExpenses this year: %d\n" % [towns, firms, units, int(p.income_year), int(p.expense_year)]
	if game.goals:
		s += _goals_text()
	if not p.tech.is_empty():
		s += "\nTechnology:\n"
		for k in p.tech:
			s += "  %s %d\n" % [Defs.tech_def(k).get("name", k), p.tech[k]]
	s += "\n[color=#b0a890]Left-click to select, drag to box-select. Right-click to give orders. WASD / arrows / screen edge to scroll, wheel to zoom, Space to pause.[/color]"
	return s


## The scenario's goals with their progress and the time left.
func _goals_text() -> String:
	var gl: Goals = game.goals
	var s := "\n[b]Goals[/b] (%s):\n" % ("all of these" if gl.require_all else "any one of these")
	for c in gl.win:
		if not c["supported"]:
			s += "  [color=#807868]%s (not available in this version)[/color]\n" % c["text"]
		else:
			var now := Goals.progress(game, game.player(), c)
			s += "  %s %s%s\n" % ["[color=#80ff80]✓[/color]" if c.get("met", false) else "•", c["text"],
				"" if now < 0 else " [color=#b0a890](now %d)[/color]" % now]
	for c in gl.lose:
		if c["id"] != Goals.DEFEAT_OWN_KINGDOM:
			s += "  [color=#ff9070]Lose if:[/color] %s\n" % c["text"]
	var dl := gl.deadline_day()
	if dl > 0:
		var left := maxi(0, dl - game.day)
		s += "  Time left: %d years %d days\n" % [left / 365, left % 365]
	return s


func _clear_actions() -> void:
	for c in actions.get_children():
		actions.remove_child(c)
		c.queue_free()
	tooltip_label.text = ""


## A button that shows a symbol, its words as the tooltip.
func _icon_button(b: Button, icon: String, words: String) -> void:
	b.text = icon
	b.tooltip_text = words
	b.set_meta("label", words)
	b.custom_minimum_size = Vector2(38, 0)
	b.add_theme_font_size_override("font_size", 18)


func _add_action(text: String, cb: Callable, enabled := true, tip := "", right_cb := Callable(), icon := "") -> Button:
	var b := Button.new()
	b.text = Icons.caption(text, icon)    # a symbol (and its figures); the words are the tooltip
	b.tooltip_text = text
	b.set_meta("label", text)
	b.disabled = not enabled
	if not enabled:
		b.modulate = Color(1, 1, 1, 0.35)  # colour symbols do not grey out by themselves
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = true
	b.custom_minimum_size = Vector2(52, 36)
	b.add_theme_font_size_override("font_size", 16)
	b.pressed.connect(func():
		if tutorial_panel and tutorial_panel.tutorial:
			tutorial_panel.tutorial.press(text)
		cb.call()
		refresh_selection(true))
	# Help option (Config::help_mode): none, brief (the title), detailed
	var hm := int(GameOptions.get_opt("help_mode"))
	var original := HelpText.for_label(text)
	if hm == 1:
		tip = original.get_slice(":", 0) if original != "" else tip.get_slice(".", 0)
	elif original != "":
		tip = original + ("

" + tip if tip != "" else "")
	if hm == 0:
		tip = ""
	tip = text + ("\n" + tip if tip != "" else "")
	b.mouse_entered.connect(func(): tooltip_label.text = tip)
	if right_cb.is_valid():
		b.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
				right_cb.call()
				b.accept_event()
				refresh_selection(true))
	actions.add_child(b)
	return b


func _bar(v: float, maxv: float, col: String) -> String:
	var n := clampi(int(round(10.0 * v / maxf(maxv, 0.001))), 0, 10)
	return "[color=%s]%s[/color][color=#444]%s[/color]" % [col, "█".repeat(n), "█".repeat(10 - n)]


func _owner_line(o: GameObj) -> String:
	if o.is_monster():
		return "[color=#80c060]Fryhtans[/color]"
	var n := o.nation()
	if n == null:
		return "Independent"
	return "[color=#%s]%s[/color]" % [n.color.to_html(false), n.name]


# ---------------------------------------------------------------- units ---

func _show_unit(u: Unit, rebuild: bool) -> void:
	portrait.texture = Assets.unit_icon("I_UNITLI.RES", u.utype.get("icon_ptr", 0)) if u.utype.get("icon_ptr", 0) > 0 else null
	title_label.text = u.display_name()
	var s := "%s\n%s\n" % [u.type_name(), _owner_line(u)]
	s += "Hit points %d / %d  %s\n" % [int(u.hp), int(u.max_hp), _bar(u.hp, u.max_hp, "#60d060")]
	if u.is_human():
		s += "Combat %d\n" % int(u.combat)
		if u.rank >= Defs.Rank.GENERAL:
			s += "Leadership %d\n" % int(u.leadership)
	if u.is_hero:
		s += "[color=#ffd860]Hero[/color]\n"
	if u.is_spy and u.nation_id == game.player_id:
		s += "[color=#c0a0ff]Spy[/color], spying skill %d\n" % int(u.spy_skill)
		var cn := game.nation(u.cloak_id) if u.cloak_id > 0 else null
		if cn:
			s += "Disguised as one of the [color=#%s]%s[/color]\n" % [cn.color.to_html(false), cn.name]
		if u.camouflage_days > 0:
			s += "Camouflaged: unseen for %d days\n" % u.camouflage_days
		s += "[color=#b0a890]Right-click a town, fort or camp to infiltrate it. A kingdom's place needs its colours, put on automatically when no enemy is near. In your own places spies hunt enemy spies.[/color]\n"
	elif (u.nation_id == game.player_id or GameOptions.get_opt("show_ai_info")) and u.is_human() and not u.is_civilian() and u.rank != Defs.Rank.KING:
		s += "Loyalty %d\n" % int(u.loyalty)
	if u.item_id > 0:
		s += "[color=#ffd860]%s[/color]: %s\n" % [Items.item_name(u.item_id), Items.description(u.item_id, u.item_para)]
	if u.life_frames > 0:
		s += "Vanishes in %d days\n" % (u.life_frames / Defs.FRAMES_PER_DAY)
	if u.is_wagon():
		s += "Carrying %d %s settlers\n" % [u.wagon_pop, Defs.race_adj(u.wagon_race)]
	if u.is_caravan:
		var dest := u.caravan_dest.display_name() if u.caravan_dest and is_instance_valid(u.caravan_dest) else "looking for a market"
		s += "Route: %s ↔ %s\n" % [u.caravan_home.display_name() if u.caravan_home and is_instance_valid(u.caravan_home) else "?", dest]
		var c := []
		for k in u.cargo:
			c.append("%d %s goods" % [int(u.cargo[k]), k])
		s += "Cargo: %s\n" % (", ".join(c) if not c.is_empty() else "empty")
	var orders := {Unit.Order.IDLE: "Idle", Unit.Order.MOVE: "Moving", Unit.Order.ATTACK: "Attacking", Unit.Order.ENTER: "Going to building",
		Unit.Order.BUILD: "Going to construct", Unit.Order.RETURN: "Returning home"}
	s += "Order: %s" % orders.get(u.order, "")
	info_label.text = s
	if rebuild:
		_unit_actions([u])


func _unit_actions(sel: Array) -> void:
	_clear_actions()
	var own: Array = sel.filter(func(u): return u.nation_id == game.player_id)
	if own.is_empty():
		return
	if build_menu_open:
		_build_menu()
		return
	_add_action("Stop", func():
		for u in own:
			_do(u, "stop"))
	if own.any(func(u): return not u.is_civilian() and not u.is_caravan and not u.is_god and not u.is_spy):
		_add_action("Return", func():
			for u in own:
				_do(u, "return_to_base"), true, "Back into the nearest of your forts, camps or lairs that has room.")
	if own.any(func(u): return u.is_human()) or game.player().is_fryhtan:
		_add_action("Build...", func(): build_menu_open = true, true, "Choose a building to construct. The nearest selected unit will build it.")
	if own.any(func(u): return u.sprite_code == Defs.FORTRESS_BUILDER) and game.player().tech_level("FORTRESS") > 0:
		var cost := int(Defs.firm_types.get("FORTRESS", {}).get("cost", 50))
		_add_action("Fortress (%d)" % cost, func():
			if SpecialFirms.fortress_spot(own).x < 0:
				game.notify("Four Grokkens standing together on open ground are needed.", Vector2(-1, -1))
			else:
				_do(SpecialFirms, "transform_to_fortress", [own]),
			SpecialFirms.fortress_spot(own).x >= 0 and game.player().cash >= cost,
			"Four selected Grokkens standing side by side turn into a Fortress, from which Fryhtans posted inside shoot at enemies within %d." % int(SpecialFirms.FORTRESS_RANGE))
	# formations for a troop led by a general (oun_if.cpp: FORMTION buttons)
	if own.size() > 1 and own.any(func(x): return x.rank >= Defs.Rank.GENERAL):
		var cur: int = own.filter(func(x): return x.rank >= Defs.Rank.GENERAL)[0].formation
		for k in range(1, Formations.NAMES.size()):
			var kind: int = k
			_add_action("Formation: " + Formations.NAMES[k] + (" ✓" if cur == k else ""), func(): _do(game, "form_troop", [own, kind, Vector2.ZERO]), true,
				"The troop keeps this formation wherever it stops. Use the number pad to set the direction it faces.")
		if cur > 0:
			_add_action("No formation", func(): _do(game, "form_troop", [own, 0, Vector2.ZERO]))
	if own.size() == 1:
		var u: Unit = own[0]
		if u.is_human() and u.rank == Defs.Rank.SOLDIER and not u.is_civilian():
			var promote := func(): _do(u, "promote")
			_add_action("Promote to General", promote, true, "A general can command a camp, extending the kingdom's influence over nearby towns.")
		if u.rank == Defs.Rank.GENERAL and not u.is_hero:
			_add_action("Demote to Soldier", func(): _do(u, "demote"))
		if u.home_town == null and (u.is_human() or u.is_wagon()):
			_add_action("Settle in town", func(): _settle(u), true, "Walk to the nearest own town of the same race and join its population.")
		if u.can_found_town():
			_add_action("Build a town (%d)" % int(Game.TOWN_BUILDING_COST), func(): found_town_requested.emit(u), game.player().cash >= Game.TOWN_BUILDING_COST,
				"Click where the new town should stand.")
		if u.item_id > 0:
			_item_actions(u)
		if u.is_spy:
			_spy_unit_actions(u)
		if u.is_caravan:
			_add_action("Set destination", func(): caravan_route_requested.emit(u), true,
				"Click a market of yours, or of a kingdom with a trade treaty, for this caravan to trade with.")
			var dm := u.duplicate_market()
			_add_action("Clone caravan (%d)" % int(Firm.CARAVAN_COST), func(): _do(u, "duplicate_caravan"), dm != null,
				"Hire another caravan at its market with the same route and goods.")
			var kinds: Array = []
			for m in [u.caravan_home, u.caravan_dest]:
				if m and is_instance_valid(m):
					for k in m.goods:
						if not k in kinds:
							kinds.append(k)
			for k in u.pick_up + u.cargo.keys():
				if not k in kinds:
					kinds.append(k)
			for k in kinds:
				var gk: String = k
				_add_action(("☑ " if gk in u.pick_up else "☐ ") + gk, func(): _do(u, "toggle_pick_up", [gk]), true,
					"Goods this caravan loads. With none ticked it carries whatever the other market lacks.")
		if u.sprite_code == "EXPCART":
			_add_action("Detonate", func(): _do(u, "explode"), true, "Blow the Porcupine up where it stands, hurting everything next to it.")
		if u.is_god:
			var gi := u.god_info()
			if not gi.is_empty() and Defs.GOD_POWERS.has(gi["race"]):
				_add_action("Cast power (%d)" % gi["power_pray"], func(): cast_target_requested.emit(u), u.can_cast_power(),
					Defs.GOD_POWERS.get(gi["race"], "") + ". Click where to cast it. Costs prayer points.")


## Use, switch on or drop the carried item.
func _item_actions(u: Unit) -> void:
	var name := Items.item_name(u.item_id)
	var aim: String = Items.MANUAL_TARGET.get(u.item_id, "")
	if aim == "self":
		_add_action("Use " + name, func(): _do(u, "use_item_cmd"), true, Items.info(u.item_id)[Items.DESC])
	elif aim != "":
		_add_action("Use " + name + "...", func(): item_target_requested.emit(u), true,
			Items.info(u.item_id)[Items.DESC] + ". Then click the %s." % {"unit": "unit", "town": "town", "place": "place to go"}[aim])
	elif Items.info(u.item_id)[Items.PARA] in [Items.Para.USE_TIMED, Items.Para.CHARGE_TIMED]:
		_add_action("Activate " + name, func(): _do(u, "turn_on_item"), Items.can_turn_on(u.item_id, u.item_para), "Works for a while once activated.")
	_add_action("Drop item", func(): _do(game, "_drop_item", [u]), true, "Leave the item on the ground for another unit.")


## Disguise and camouflage for a spy in the field.
func _spy_unit_actions(u: Unit) -> void:
	var choices := Espionage.cloak_choices(u)
	var cur := choices.find(u.cloak_id if u.cloak_id > 0 else u.nation_id)
	var next: int = choices[(cur + 1) % choices.size()]
	var cn := game.nation(u.cloak_id) if u.cloak_id > 0 else null
	_add_action("Disguise: %s" % (cn.name if cn else "own colours"), func():
		if not Espionage.can_change_cloak(u, next):
			game.notify("Your spy cannot change colours with enemies nearby.", u.center_loc())
		else:
			_do(Espionage, "set_cloak", [u, next]),
		choices.size() > 1,
		"Click: pass for the next kingdom. Right-click: back to your own colours. Units of the kingdom you pass for leave the spy alone; attacking gives the disguise away. Not possible with enemies within %d." % Espionage.ENEMY_RANGE,
		func(): _do(Espionage, "set_cloak", [u, u.nation_id]))
	if game.player().tech_level("CAMOUFLG") > 0:
		_add_action("Camouflage (%d)" % u.camouflage_power, func(): _do(Espionage, "start_camouflage", [u]), Espionage.can_camouflage(u),
			"Become unseen by other kingdoms for as many days as the camouflage power (at least %d). Needs a disguise." % Espionage.MIN_CAMOUFLAGE_POWER)


# ------------------------------------------------------------- espionage ---

var bribe_target := 0          # index among the place's men
var bribe_amount := 1          # index in Espionage.BRIBE_AMOUNTS
var incident_with := 0         # index in Espionage.incident_choices
var secret_for: GameObj = null # place whose secret report is shown


## The player's spies in a place: what they see (the original's spy menu).
func _spy_info(place: GameObj) -> String:
	var mine := Espionage.spies_in(place).filter(func(x): return x.nation_id == game.player_id)
	if mine.is_empty():
		return ""
	var s := "\n[color=#c0a0ff]Your spies here: %s[/color]\n" % ", ".join(mine.map(func(x): return "%s (%d)" % [x.unit_name, int(x.spy_skill)]))
	if place.nation_id == game.player_id:
		return s + "They watch for enemy spies.\n"
	s += "Mission: %s\n" % ("sow dissent" if mine[0].spy_action == "dissent" else "sleep (lie low)")
	if place is Firm:
		var f := place as Firm
		for m in Espionage.occupants(f):
			var mark := " [color=#c0a0ff](yours)[/color]" if m.sleeper_for == game.player_id else ""
			var loy := "" if m.rank == Defs.Rank.KING else " — loyalty %d" % int(m.loyalty)
			s += "  %s%s%s%s\n" % ["★ " if m == f.overseer else "", m.display_name(), loy, mark]
	if secret_for == place:
		s += "\n" + Espionage.secret_report(game, place.nation_id)
	return s


## Spy missions from a place's panel: bribe, capture, assassinate, steal
## technology, create an incident, read the secret report.
func _spy_actions(place: GameObj) -> void:
	var mine := Espionage.spies_in(place).filter(func(x): return x.nation_id == game.player_id)
	if mine.is_empty():
		return
	mine.sort_custom(func(a, b): return a.spy_skill > b.spy_skill)
	var spy: Unit = mine[0]
	var p := game.player()
	_add_action("Recall spy", func(): _do(game, "spy_leave", [mine[-1]]), true, "Your least skilled spy here walks out, wearing the place's colours.")
	if place.nation_id == game.player_id:
		return
	_add_action("Mission: " + ("Dissent" if spy.spy_action == "dissent" else "Sleep"), func():
		var to := "idle" if spy.spy_action == "dissent" else "dissent"
		for x in mine:
			_do(x, "set", ["spy_action", to]), true,
		"Sow dissent: lower the town's loyalty (or its resistance to you), or the loyalty of the men of their own race. Sleep: lie low; a sleeping spy is almost never caught.")
	if place.nation_id > 0 and p.tech_level("STEALINF") > 0:
		_add_action("Secret report", func(): secret_for = null if secret_for == place else place, Espionage.can_view_secret(spy),
			"Read the kingdom's treasury, armies, technology and treaties. Needs spying skill %d." % Espionage.MIN_VIEW_SECRET_SKILL)
	if not Espionage.is_camp(place):
		return
	var f := place as Firm
	var men: Array = Espionage.occupants(f).filter(func(m): return Espionage.can_bribe(f, m, game.player_id))
	if not men.is_empty():
		bribe_target = bribe_target % men.size()
		var who: Unit = men[bribe_target]
		var amt: int = Espionage.BRIBE_AMOUNTS[bribe_amount % Espionage.BRIBE_AMOUNTS.size()]
		var ch := clampi(Espionage.bribe_chance(spy, f, who, amt), 0, 100)
		_add_action("Bribe: %s" % who.display_name().get_slice(" ", 0) if who != f.overseer else "Bribe: general", func(): bribe_target += 1, men.size() > 1, "Click: choose another man.")
		_add_action("Offer %d: %d%%" % [amt, ch], func(): _do(Espionage, "bribe", [spy, f, who, amt]),
			spy.spy_skill >= Espionage.MIN_BRIBE_SKILL and p.cash >= amt,
			"Click: offer the bribe; the gold is spent and, if refused, your spy is executed. Right-click: change the sum. Needs spying skill %d. A bought general can hand the fort over to you." % Espionage.MIN_BRIBE_SKILL,
			func(): bribe_amount = (bribe_amount + 1) % Espionage.BRIBE_AMOUNTS.size())
	if Espionage.can_capture(f, game.player_id):
		_add_action("Capture %s" % f.display_name(), func(): _do(Espionage, "capture", [f, game.player_id]), true,
			"Your bribed general hands the fort over. Soldiers who will not follow him walk out and attack it.")
	if f.overseer and f.overseer.sleeper_for != game.player_id:
		_add_action("Assassinate: %d%%" % Espionage.assassinate_chance(spy, f), func(): _do(Espionage, "assassinate", [spy, f]),
			Espionage.can_assassinate(spy, f),
			"Kill the commander, %s. Needs spying skill %d. Guards make it harder, and with guards about your spy may be caught even when he succeeds." % [f.overseer.display_name(), Espionage.MIN_ASSASSIN_SKILL])
	if p.tech_level("STEALTEC") > 0:
		_add_action("Steal tech: %d%%" % Espionage.steal_rating(spy, f), func(): _do(Espionage, "steal_tech", [spy, f]),
			Espionage.can_steal_tech(spy, f), "Learn one technology they know better than you. Needs spying skill %d. Failure costs the spy." % Espionage.MIN_STEAL_TECH_SKILL)
	if p.tech_level("INCIDENT") > 0:
		var others := Espionage.incident_choices(spy, f)
		if not others.is_empty():
			incident_with = incident_with % others.size()
			var other: Nation = game.nation(others[incident_with])
			_add_action("Incident: %s %d%%" % [Defs.race_name(other.race), Espionage.steal_rating(spy, f, other.id)], func(): _do(Espionage, "create_incident", [spy, f, other.id]),
				Espionage.can_create_incident(spy, f),
				"Stage an incident: the %s and the %s break their treaties and go to war. Right-click: choose another kingdom. Needs spying skill %d." % [f.nation().name, other.name, Espionage.MIN_INCIDENT_SKILL],
				func(): incident_with += 1)


func _settle(u: Unit) -> void:
	if not u.can_settle():
		game.notify("No town of the same race to settle in.", Vector2(-1, -1))
		return
	_do(u, "order_settle")


## A player action: runs at once, or in a network game on every machine at
## the same turn (Net.cmd).
func _do(target, method: String, args: Array = []) -> void:
	Net.cmd(target, method, args)


func _build_menu() -> void:
	var p := game.player()
	if p.is_fryhtan:
		_add_action("Lair (%d gold, %d life)" % [int(FryhtanAI.LAIR_COST), int(FryhtanAI.LAIR_LIVE)], func():
			build_menu_open = false
			build_requested.emit("LAIR"), p.cash >= FryhtanAI.LAIR_COST and p.live_points >= FryhtanAI.LAIR_LIVE,
			"A new lair breeds more of your brood and spreads your terror to nearby villages.")
		for code in Defs.FRYHTAN_FIRMS:
			if not Defs.knows_firm(p, code):
				continue
			var c: String = code
			var fcost := float(Defs.firm_types.get(code, {}).get("cost", 0))
			var flive := SpecialFirms.setup_live(code)
			_add_action("%s (%d gold, %d life)" % [Defs.firm_types.get(code, {}).get("name", code), int(fcost), int(flive)], func():
				build_menu_open = false
				build_requested.emit(c), p.cash >= fcost and p.live_points >= flive, Defs.FIRM_HELP.get(code, ""))
		_add_action("Cancel", func(): build_menu_open = false)
		return
	for code in Defs.HUMAN_FIRMS:
		var ft: Dictionary = Defs.firm_types.get(code, {})
		var cost: int = ft.get("cost", 0)
		# one Seat of Power per Greater Being whose Scroll of Power the kingdom holds
		var variants: Array = [code] if code != "BASE" else p.known_gods.keys().map(func(r): return "BASE|" + r)
		for v in variants:
			var c: String = v
			var pick := func():
				build_menu_open = false
				build_requested.emit(c)
			var label: String = ft.get("name", code)
			if c.contains("|") and p.known_gods.size() > 1:
				label += " (%s)" % Defs.race_name(c.get_slice("|", 1))
			var known: bool = code != "STABLE" or p.tech_level(Defs.spu_structure_tech(p.race)) > 0
			_add_action("%s (%d)" % [label, cost], pick, p.cash >= cost and known,
				Defs.FIRM_HELP.get(code, "") if known else "Research %s at a Tower of Science first." % Defs.tech_def(Defs.spu_structure_tech(p.race)).get("name", "the training centre"))
	for code in Defs.OFFENSIVE_FIRMS:
		if not Defs.knows_firm(p, code):
			continue
		var c2: String = code
		var ocost: int = Defs.firm_types.get(code, {}).get("cost", 0)
		_add_action("%s (%d)" % [Defs.firm_types.get(code, {}).get("name", code), ocost], func():
			build_menu_open = false
			build_requested.emit(c2), p.cash >= ocost, Defs.FIRM_HELP.get(code, ""))
	_add_action("Cancel", func(): build_menu_open = false)


# ---------------------------------------------------------------- towns ---

var _thumbs := {}


## Small picture of a building for the info panel, cut from its own art.
func _thumb_firm(f: Firm) -> Texture2D:
	var key := "F|%s|%s|%s" % [f.code, f.race, f.nation_color().to_html()]
	if _thumbs.has(key):
		return _thumbs[key]
	var frames: Array = f.build.get("frames", [])
	var tex: Texture2D = null
	if not frames.is_empty() and not frames[0]["bitmaps"].is_empty():
		var b := Assets.firm_bitmap(f.build, frames[0]["bitmaps"][0], f.nation_color())
		if not b.is_empty():
			tex = _scaled(b[0], Vector2i(64, 48))
	_thumbs[key] = tex
	return tex


func _thumb_town(t: Town) -> Texture2D:
	var key := "T|" + t.race
	if _thumbs.has(key):
		return _thumbs[key]
	var hb := Assets.town_house(t.race, 3)
	if hb.is_empty():
		hb = Assets.town_house(t.race, 1)
	var tex: Texture2D = _scaled(hb[0], Vector2i(64, 48)) if not hb.is_empty() else null
	_thumbs[key] = tex
	return tex


static func _scaled(src: Texture2D, box: Vector2i) -> Texture2D:
	var img := src.get_image()
	var used := img.get_used_rect()
	if used.size.x > 0:
		img = img.get_region(used)
	var k := minf(float(box.x) / img.get_width(), float(box.y) / img.get_height())
	img.resize(maxi(1, int(img.get_width() * k)), maxi(1, int(img.get_height() * k)), Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)


func _show_town(t: Town, rebuild: bool) -> void:
	portrait.texture = _thumb_town(t)
	title_label.text = t.town_name
	var s := "%s town, %s\n" % [Defs.race_name(t.race), _owner_line(t)]
	if t.under_construction:
		info_label.text = s + "Being built: %d%%  %s\n%d settlers will move in." % [int(t.build_progress), _bar(t.build_progress, 100, "#c0a060"), t.builder_pop]
		if rebuild:
			_clear_actions()
		return
	s += "Population %d (%d employed, %d jobless)\n" % [t.population, t.employed, t.jobless()]
	if t.nation_id > 0:
		s += "Loyalty %d → %d  %s\n" % [int(t.loyalty), int(t.target_loyalty), _bar(t.loyalty, 100, "#e0c040")]
		s += "Quality of life %d\n" % t.quality_of_life
		if t.wall_level > 0:
			s += "%s: %d / %d\n" % ["Wall" if t.wall_level == 1 else "Fortified wall", int(t.wall_hp), int(t.wall_max_hp())]
		if t.target_wall_level > t.wall_level:
			s += "Building wall: %d%%\n" % int(100.0 * t.wall_progress / Town.MAX_WALL_PROGRESS)
	else:
		s += "\nResistance:\n"
		for n in game.nations:
			if not n.alive:
				continue
			var tr: String = (" → %d" % int(t.target_resistance[n.id])) if t.target_resistance.has(n.id) else ""
			s += "[color=#%s]%s[/color] %d%s\n" % [n.color.to_html(false), n.name, int(t.resistance_to(n.id)), tr]
		var trib := t.tribute_to()
		if trib > 0:
			s += "[color=#ff9060]Pays tribute to the %s.[/color] It cannot join you while their lair stands.\n" % game.nation(trib).name
		s += "\n[color=#b0a890]Build a camp nearby with a general inside. A general of the town's own race has far more influence; gold grants lower resistance further. Below %d the town joins you.[/color]\n" % Defs.SURRENDER_RESISTANCE
	var links := t.linked_firms.filter(func(f): return f.nation_id == game.player_id)
	if not links.is_empty():
		s += "Linked: " + ", ".join(links.map(func(f): return f.display_name())) + "\n"
	s += _spy_info(t)
	info_label.text = s
	if not rebuild:
		return
	_clear_actions()
	if t.nation_id == game.player_id:
		var do_recruit := func(): _do(t, "recruit")
		_add_action("Recruit peasant", do_recruit, t.can_recruit(), "Send a villager out as a peasant, to build, found a town or work as a spy. Soldiers come from a fort's \"Fill from towns\". Needs loyalty %d+." % Defs.MIN_RECRUIT_LOYALTY)
		_add_action("Send out wagon (%d)" % mini(t.jobless(), Defs.MAX_WAGON_POPULATION), func(): _do(t, "recruit_wagon"), t.nation_id > 0 and t.jobless() > 1,
			"Up to %d jobless villagers leave together to settle in another town of theirs or found a new one." % Defs.MAX_WAGON_POPULATION)
		var do_tax := func(): _do(t, "collect_tax_cmd")
		_add_action("Collect tax" + (" (auto %d)" % t.auto_tax_loyalty if t.auto_tax_loyalty > 0 else ""), do_tax, t.has_linked_camp(t.nation_id),
			"Needs a linked camp with a general. Lowers loyalty. Right-click: collect automatically when loyalty reaches %s." % "/".join(Town.AUTO_TAX_LEVELS.slice(1).map(func(v): return str(v))),
			func(): _do(t, "set", ["auto_tax_loyalty", Town.next_level(Town.AUTO_TAX_LEVELS, t.auto_tax_loyalty)]))
		_add_action("Grant gold (%d)" % int(t.grant_cost()) + (" (auto <%d)" % t.auto_grant_loyalty if t.auto_grant_loyalty > 0 else ""), func(): _do(t, "grant", [game.player_id]), game.player().cash >= t.grant_cost(),
			"Raise the town's loyalty. Right-click: grant automatically when loyalty falls below %s." % "/".join(Town.AUTO_GRANT_LEVELS.slice(1).map(func(v): return str(v))),
			func(): _do(t, "set", ["auto_grant_loyalty", Town.next_level(Town.AUTO_GRANT_LEVELS, t.auto_grant_loyalty)]))
		if t.target_wall_level < 2:
			var lvl := t.target_wall_level + 1
			_add_action("Build %s (%d)" % ["wall" if lvl == 1 else "fortified wall", Town.WALL_COST[lvl]], func(): _do(t, "build_wall"), game.player().cash > 0,
				"Jobless villagers build it. Walls absorb attacks and shield the town from enemy influence.")
	elif t.nation_id == 0:
		_add_action("Grant gold (%d)" % int(t.grant_cost()), func(): _do(t, "grant", [game.player_id]),
			game.player().cash >= t.grant_cost() and t.has_linked_camp(game.player_id), "Lower the town's resistance to you. Needs one of your camps linked to it.")
	_spy_actions(t)


# ---------------------------------------------------------------- firms ---

func _show_firm(f: Firm, rebuild: bool) -> void:
	portrait.texture = _thumb_firm(f)
	title_label.text = f.display_name()
	var s := "%s\n" % _owner_line(f)
	s += "Hit points %d / %d  %s\n" % [int(f.hp), int(f.max_hp), _bar(f.hp, f.max_hp, "#60d060")]
	var own := f.nation_id == game.player_id
	if f.under_construction:
		s += "Under construction: %d%%\n" % int(f.progress)
		if f.builder == null:
			var coming := game.units.any(func(u): return u.order == Unit.Order.BUILD and u.order_firm == f and not u.dead)
			if coming:
				s += "Builder on the way.\n"
			elif own:
				s += "[color=#ff9060]No builder. Right-click with a unit to resume.[/color]\n"
		info_label.text = s
		if rebuild:
			_clear_actions()
		return
	if own or f.is_monster() or GameOptions.get_opt("show_ai_info") or f.revealed_to.has(game.player_id):
		match f.code:
			"CAMP", "FORT", "LAIR":
				if f.overseer:
					s += "Commander: %s (leadership %d%s)\n" % [f.overseer.display_name(), int(f.overseer.leadership),
						", loyalty %d" % int(f.overseer.loyalty) if f.overseer.rank != Defs.Rank.KING and f.code != "LAIR" else ""]
				elif f.code != "LAIR":
					s += "[color=#ff9060]No general. Send a general here to gain influence.[/color]\n"
				s += "Soldiers %d / %d\n" % [f.soldiers.size(), f.capacity()]
				if f.code == "FORT" and (f.archers > 0 or f.target_archers > 0):
					s += "Archers %d%s\n" % [f.archers, (" (training %d of %d days)" % [f.archer_progress, Firm.MAX_TRAIN_ARCHER_PROGRESS]) if f.target_archers > f.archers else ""]
				for u in f.soldiers:
					s += "  %s — combat %d, HP %d%s\n" % [u.display_name() if u.is_human() else u.type_name(), int(u.combat), int(u.hp),
						", loyalty %d" % int(u.loyalty) if u.is_human() else ""]
				if f.code != "LAIR":
					var towns := f.linked_towns.map(func(t): return t.town_name)
					s += "Influences: %s\n" % (", ".join(towns) if not towns.is_empty() else "no towns in range")
			"MINE":
				s += "%s mine\nReserve %d\nStock %d\nMiners %d / %d\n" % [f.raw, int(f.reserve), int(f.stock), f.workers(), Defs.MAX_WORKER]
			"FACTORY":
				s += "Product: %s\nRaw stock %d\nGoods stock %d\nWorkers %d / %d\n" % [(f.raw + " goods") if f.raw != "" else "none (link a mine)", int(f.raw_stock), int(f.stock), f.workers(), Defs.MAX_WORKER]
			"MARKET":
				s += "Goods:\n"
				for g in f.goods:
					s += "  %s goods: %d\n" % [g, int(f.goods[g])]
				if f.goods.is_empty():
					s += "  none (link a factory)\n"
				s += "Sales this game: %d gold\nCustomers: %s\n" % [int(f.market_sales), ", ".join(f.linked_towns.map(func(t): return t.town_name))]
				s += "Caravans: %d / %d\n" % [game.caravans_of(f), Firm.MAX_CARAVANS]
			"RESEARCH":
				s += "Scientists %d / %d\n" % [f.workers(), Defs.MAX_WORKER]
				if f.research_tech != "":
					var t := Defs.tech_def(f.research_tech)
					var lvl := game.player().tech_level(f.research_tech)
					s += "Researching %s %d: %d%%  (+%.2f%% a day here)\n" % [t["name"], lvl + 1, int(f.research_points), f.research_rate(t, lvl)]
				else:
					s += "Choose a technology to research.\n"
			"BEE", "TERMITE", "INCUBAT":
				if f.weapon != "":
					s += "%s %s: %d%% (%d queued)\n" % ["Growing" if f.code == "INCUBAT" else "Breeding", Defs.unit_types[f.weapon]["name"], int(f.weapon_progress), f.weapon_queue]
				elif SpecialFirms.buildable_units(f).is_empty():
					s += "[color=#ff9060]Buy its technology at a lair first.[/color]\n"
			"ANIMAL":
				s += "Beasts for hire:\n"
				for a in f.animals:
					s += "  %s combat %d — %d gold, %d life\n" % [Defs.unit_types.get(a["unit"], {}).get("name", a["unit"]), int(a["combat"]), int(a["cost"]), int(a["live"])]
				if f.animals.is_empty():
					s += "  none yet (they come every two weeks)\n"
			"ALCHEMY":
				s += "Conversion: %s\n" % (Defs.tech_def(f.alchemy_mode).get("name", "") if f.alchemy_mode != "" else "none")
				if f.site:
					s += "%s deposit: %d left\n" % [f.raw, int(f.reserve)]
				s += "Produced: %d\n" % int(f.stock)
			"FORTRESS":
				s += "Defenders %d / %d (shoot within %d)\n" % [f.soldiers.size(), f.capacity(), int(SpecialFirms.FORTRESS_RANGE)]
				for u in f.soldiers:
					s += "  %s — combat %d, HP %d\n" % [u.type_name(), int(u.combat), int(u.hp)]
				if f.soldiers.is_empty():
					s += "[color=#ff9060]Right-click it with Fryhtans to post them inside.[/color]\n"
				if SpecialFirms.hidden_from(f, -1):
					s += "Camouflaged: other kingdoms see only a rock.\n"
			"LISHORR":
				s += "Shoots for %d damage%s\n" % [int(SpecialFirms.lishorr_damage(f)), " (double under a clear sky)"]
				if SpecialFirms.hidden_from(f, -1):
					s += "Camouflaged: other kingdoms see only a plant.\n"
			"MAGIC", "OFF_BLD1", "OFF_BLD2", "OFF_BLD4":
				s += "Charge %d / %d  %s\n" % [f.cast_charge, Defs.MAX_CAST_DELAY, _bar(f.cast_charge, Defs.MAX_CAST_DELAY, "#a080ff")]
				if f.hp < f.max_hp:
					s += "[color=#ff9060]Recharges only when undamaged.[/color]\n"
			"STABLE", "SPY":
				if f.code == "STABLE":
					s += "Trains: %s\n" % Defs.unit_types.get(f.special_unit(), {}).get("name", "?")
				if own or GameOptions.get_opt("show_ai_info") or f.revealed_to.has(game.player_id):
					s += "Trainees %d / %d\n" % [f.trainees.size(), Training.MAX_TRAINEE]
					for rec in f.trainees:
						s += "  " + Training.describe(rec) + "\n"
			"WAR":
				s += "Workers %d / %d\n" % [f.workers(), Defs.MAX_WORKER]
				if f.weapon != "":
					s += "Building %s: %d%% (%d queued)\n" % [Defs.unit_types[f.weapon]["name"], int(f.weapon_progress), f.weapon_queue]
			"INN":
				s += "Heroes for hire:\n"
				for hdef in f.heroes:
					s += "  %s (%s) combat %d, leadership %d — %d gold\n" % [hdef["name"], Defs.race_name(hdef["race"]), int(hdef["combat"]), int(hdef["leadership"]), hdef["cost"]]
				if f.heroes.is_empty():
					s += "  nobody at the moment\n"
			"BASE":
				var g: Dictionary = Defs.gods.get(game.player().race, {})
				s += "Worshippers %d / %d\nPrayer points %d (Greater Being %d, Special Blessing %d)\n" % [f.workers(), Defs.MAX_WORKER, int(game.player().prayer_points), int(f.god_cost()), int(Wishes.FULL)]
				if f.has_meta("wish_text"):
					s += "Blessing: %s\n" % f.get_meta("wish_text")
				if not g.is_empty():
					s += "Greater Being: %s\n" % Defs.unit_types.get(g["unit"], {}).get("name", "?")
					if Defs.GOD_POWERS.has(game.player().race):
						s += "Power: %s\n" % Defs.GOD_POWERS[game.player().race]
				if Defs.GOD_BLESSINGS.has(game.player().race):
					s += "[color=#e0d080]Blessing while worshipped: %s[/color]\n" % Defs.GOD_BLESSINGS[game.player().race]
		if own and f.is_work_firm() and f.code != "BASE":
			var links := f.linked_towns.filter(func(t): return t.nation_id == f.nation_id)
			if links.is_empty():
				s += "[color=#ff9060]No own town in range to supply workers.[/color]\n"
	s += _spy_info(f)
	info_label.text = s
	if not rebuild:
		return
	_clear_actions()
	if not own:
		if f.code == "LAIR" and game.player().is_fryhtan and f.is_monster():
			_add_action("Take over (%d)" % int(SpecialFirms.take_lair_cost(f)), func(): _do(SpecialFirms, "take_lair", [f, game.player_id]),
				SpecialFirms.can_take_lair(f, game.player_id), "Buy this lair's allegiance. Needs a lair of yours with a commander nearby.")
		_spy_actions(f)
		return
	var p := game.player()
	match f.code:
		"CAMP", "FORT":
			if f.code == "FORT":
				_add_action("Archers %d/%d: train one (%d)" % [f.archers, f.target_archers, Firm.TRAIN_ARCHER_COST], func(): _do(f, "set_target_archers", [-1]),
					f.target_archers < Firm.MAX_FORT_ARCHER and p.cash > Firm.TRAIN_ARCHER_COST,
					"Archers on the walls shoot back at whoever attacks the fort. Each takes 60 days to train and costs %d a year. Right-click: one fewer." % Firm.COST_PER_ARCHER,
					func(): _do(f, "set_target_archers", [-2]), "🏹")
			_add_action("Eject all", func(): _do(f, "eject_all"))
			_add_action("Fill from towns", func(): _fill_camp(f), true, "Villagers from your linked towns join this fort at once (towns need loyalty %d+)." % Defs.MIN_RECRUIT_LOYALTY)
			if not f.soldiers.is_empty():
				_add_action("Send out soldiers", func(): _do(f, "release_all_soldiers"))
			_occupant_buttons(f)
		"LAIR":
			if f.is_fryhtan_lair():
				for t in Defs.fryhtan_techs(SpecialFirms.lair_species(f)):
					var tc: String = t["code"]
					var lvl := p.tech_level(tc)
					if lvl >= t["max"]:
						continue
					_add_action("Learn %s %d (%d life)" % [t["name"], lvl + 1, int(Defs.fryhtan_tech_live_cost(t))], func(): _do(SpecialFirms, "buy_tech", [f, tc]),
						SpecialFirms.can_buy_tech(f, t), _fryhtan_tech_tip(t))
				var ut: Dictionary = Defs.unit_types.get(f.monster_code, {})
				_add_action("Breed %s (%d gold, %d life)" % [ut.get("name", f.monster_code), int(ut.get("cost", 100)), int(ut.get("live_cost", 50))], func(): _do(f, "breed"),
					f.soldiers.size() < f.capacity() and p.cash >= ut.get("cost", 100) and p.live_points >= ut.get("live_cost", 50),
					"Breed a new Fryhtan in this lair. Life points come from slaying enemies.")
			if not f.soldiers.is_empty():
				_add_action("Send out brood", func(): _do(f, "release_all_soldiers"))
			_occupant_buttons(f)
		"MARKET":
			var partner := game.find_trade_partner(f, f.nation_id)
			var tip := "A caravan carries goods to %s." % (partner.display_name() + " of the " + (partner.nation().name if partner.nation() else "") if partner else "another market (none in reach yet: build one further away, or make peace with a neighbour)")
			_add_action("Hire caravan (%d)" % int(Firm.CARAVAN_COST), func(): _do(f, "hire_caravan"), p.cash >= Firm.CARAVAN_COST and game.caravans_of(f) < Firm.MAX_CARAVANS, tip)
		"RESEARCH":
			for t in Defs.research_techs():
				if t.has("race") and not game.nation_has_race_town(p.id, t["race"]):
					continue
				var lvl := p.tech_level(t["code"])
				var ok := Defs.can_research(p, t)
				var tc: String = t["code"]
				var label := "%s %d" % [t["name"], lvl + 1] if lvl < t["max"] else "%s (max)" % t["name"]
				var b := _add_action(label, func(): _do(f, "start_research", [tc]), ok)
				if f.research_tech == tc:
					b.text = Icons.caption("▶ " + label)
		"WAR":
			for wcode in Defs.WEAPONS + Defs.MEGA_WEAPONS.filter(func(w): return p.tech_level(w) > 0 and Assets.has_sprite(w)):
				var ut: Dictionary = Defs.unit_types.get(wcode, {})
				var wc: String = wcode
				_add_action("%s (%d)" % [ut.get("name", wcode), ut.get("cost", 0)], func(): _do(f, "queue_weapon", [wc]), p.tech_level(wcode) > 0,
					"Research %s at a Tower of Science first." % ut.get("name", wcode) if p.tech_level(wcode) == 0 else "")
		"SPY", "STABLE":
			_train_actions(f)
		"BEE", "TERMITE", "INCUBAT":
			for sprite in SpecialFirms.buildable_units(f):
				var sc: String = sprite
				var price := SpecialFirms.unit_price(sc)
				_add_action("%s %s (%d gold, %d life)" % ["Grow" if f.code == "INCUBAT" else "Breed", Defs.unit_types[sc]["name"], int(price[0]), int(price[1])],
					func(): _do(f, "queue_weapon", [sc]), p.cash >= price[0] and p.live_points >= price[1],
					"Version %d (from the tech level)." % maxi(1, p.tech_level(Defs.unit_tech(sc))))
		"ANIMAL":
			for i in f.animals.size():
				var idx := i
				var a: Dictionary = f.animals[i]
				_add_action("Hire %s (%d)" % [Defs.unit_types.get(a["unit"], {}).get("name", a["unit"]), int(a["cost"])], func(): _do(SpecialFirms, "hire_animal", [f, idx]),
					SpecialFirms.can_hire_animal(f, idx), "Also costs %d life points." % int(a["live"]))
		"ALCHEMY":
			_add_action(("▶ " if f.alchemy_mode == "" else "") + "Stop converting", func(): _do(f, "set", ["alchemy_mode", ""]))
			for mode in SpecialFirms.ALCHEMY_MODES:
				var m: String = mode
				if p.tech_level(m) <= 0:
					continue
				_add_action(("▶ " if f.alchemy_mode == m else "") + Defs.tech_def(m)["name"], func(): _do(f, "set", ["alchemy_mode", m]), SpecialFirms.can_convert(f, m),
					"Needs the tor to stand on a mineral deposit." if m.begins_with("MINE") and f.site == null else "")
		"FORTRESS":
			if not f.soldiers.is_empty():
				_add_action("Send out defenders", func(): _do(f, "release_all_soldiers"))
			_occupant_buttons(f)
		"MAGIC", "OFF_BLD1", "OFF_BLD2", "OFF_BLD4":
			for sp in Defs.FIRM_SPELLS[f.code]:
				var spc: String = sp
				var d: Dictionary = Defs.SPELLS[sp]
				if d["tech"] != "" and p.tech_level(d["tech"]) <= 0:
					continue
				var price: int = d["live"] if d["live"] > 0 else d["cost"]
				_add_action("%s (%d)" % [d.get("short", d["name"]), price], func():
					if SpecialFirms.self_aimed(spc):
						_do(SpecialFirms, "cast", [f, spc, f.center_loc()])
					else:
						spell_target_requested.emit(f, spc), SpecialFirms.can_cast(f, spc), _spell_tip(spc))
		"INN":
			for i in f.heroes.size():
				var hdef: Dictionary = f.heroes[i]
				var idx := i
				var hire := func(): _do(f, "hire_hero", [idx])
				_add_action("Hire %s" % hdef["name"], hire, p.cash >= hdef["cost"])
		"BASE":
			var invoke := func(): _do(f, "invoke_god")
			_add_action("Invoke Greater Being", invoke, p.prayer_points >= f.god_cost())
			if Wishes.can_wish(f):
				_add_action("Special Blessing", func(): _do(f, "bless"), true,
					"Prayer points are full: receive a random blessing from your Greater Being. Uses up all prayer points.")
	if f.code in Firm.RALLY_FIRMS:
		_add_action("Rally point" + (" ✓" if f.rally.x >= 0 else ""), func(): rally_requested.emit(f), true,
			"Click: choose where the units made here gather. Right-click: clear it.", func(): _do(f, "clear_rally"))
	_add_action("Demolish", func(): _do(f, "die", [null]), true, "Destroy this building. Units inside will leave.")


## FirmTrain's panel: a button per trainee (left-click: he walks out, or quits
## training and goes home), "mobilize all", and the train buttons - one per
## race that a linked town can supply (FirmSpy: civilian, infantry, special).
const TRAIN_ICONS := ["🕵", "🗡", "🐎"]     # civilian, infantry, special-unit trainees


func _train_actions(f: Firm) -> void:
	var p := game.player()
	for i in f.trainees.size():
		var rec: Dictionary = f.trainees[i]
		var idx := i
		var ut: Dictionary = Defs.unit_types.get(rec["unit"], {})
		_add_action(("Cancel " if rec["training"] else "Mobilize ") + str(ut.get("name", rec["unit"])), func(): _do(Training, "order_mobilize", [f, idx]), true,
			Training.describe(rec) + (". He goes back to his town and the cost is refunded." if rec["training"] else ". He walks out."))
	if f.trainees.any(func(rec): return not rec["training"]):
		_add_action("Mobilize all", func(): _do(Training, "order_mobilize_all", [f]), true, "Every trained man walks out.")
	for type in Training.train_types(f):
		var ty: int = type
		var towns := Training.best_towns(f, ty)
		if towns.is_empty():
			var need: String = Training.REQUIRED_LINKED[ty]
			var label: String = ("Train %s spy" % Training.TYPE_NAME[ty]) if f.code == "SPY" else ("Train %s" % Defs.unit_types.get(f.special_unit(), {}).get("name", "?"))
			_add_action(label, func(): pass, false,
				"Needs a linked town of yours%s with loyalty above %d%s." % [" of this race" if Training.same_race(f) else "", Defs.MIN_RECRUIT_LOYALTY,
				(", itself linked to a %s" % Defs.firm_types.get(need, {}).get("name", need)) if need != "" else ""], Callable(), TRAIN_ICONS[ty])
			continue
		for t in towns:
			var town: Town = t
			var sprite := Training.unit_of(town.race, ty)
			var cost := int(Training.build_cost(sprite))
			var nm: String = Defs.unit_types.get(sprite, {}).get("name", sprite)
			var label := "Train %s%s (%d)" % [nm, " spy" if f.code == "SPY" else "", cost]
			_add_action(label, func(): _do(Training, "order_train", [f, ty, town.race]), Training.can_recruit(f, town, ty) and p.cash >= cost,
				"A volunteer from %s (loyalty %d) trains here until you mobilize him." % [town.town_name, int(town.loyalty)], Callable(), TRAIN_ICONS[ty])


## One button per occupant: left-click sends him out and selects him,
## right-click makes a soldier the commander (swapping with the current one).
func _occupant_buttons(f: Firm) -> void:
	var occupants: Array = ([f.overseer] if f.overseer else []) + f.soldiers
	for su in occupants:
		var who: Unit = su
		var lbl := ("★ " if who == f.overseer else "") + (who.display_name() if who.is_human() else who.type_name()) + " (%d)" % int(who.combat)
		var out := func():
			_do(f, "release_unit", [who])
			for o in game.selected:
				if is_instance_valid(o):
					o.selected = false
			game.selected = [who]
			who.selected = true
		var promote := func():
			if who != f.overseer and who.can_lead():
				_do(f, "make_overseer", [who])
		var icon := "👹" if not who.is_human() else ("👑" if who.rank == Defs.Rank.KING else ("🎖" if who.rank == Defs.Rank.GENERAL else "💂"))
		_add_action(lbl, out, true, "Left-click: send out. Right-click a general: make him commander.", promote, icon)


func _fryhtan_tech_tip(t: Dictionary) -> String:
	var tip := ""
	if t.has("firm"):
		tip = "Lets your brood build the %s." % Defs.firm_types.get(t["firm"], {}).get("name", t["firm"])
	if t.has("unit"):
		tip += " Higher levels make stronger %s." % Defs.unit_types.get(t["unit"], {}).get("name", t["unit"])
	if t.has("req"):
		tip += " Needs %s %d." % [Defs.tech_def(t["req"]).get("name", t["req"]), t["req_lvl"]]
	return tip.strip_edges()


func _spell_tip(sp: String) -> String:
	var d: Dictionary = Defs.SPELLS[sp]
	var what: String = {
		"DESTROY": "Strike an enemy building for half its strength, or a town's wall and people",
		"FREEZE": "Freeze enemies within %d cells of the target for %d days" % [d["radius"], d["effect"]],
		"WOUND": "Wound enemies within %d cells of the target" % d["radius"],
		"TELEPORT": "Click one of your units, then the place to send it",
		"FREEZE_LASER": "Freeze all enemies within %d cells of the building for %d days" % [d["radius"], d["effect"]],
		"GOD_POWER": "Thunderbolt on enemies and buildings within %d cells of the target" % d["radius"],
		"LASER": "Burn all enemies within %d cells of the building" % d["radius"],
	}[sp]
	var reach := ". Range %d; further costs more." % d["range"] if d["range"] > 0 else "."
	var price := "%d life points" % d["live"] if d["live"] > 0 else "%d gold" % d["cost"]
	return what + reach + " Costs %s and %d of the charge." % [price, d["delay"]]


func _fill_camp(f: Firm) -> void:
	if not f.linked_towns.any(func(t): return t.nation_id == f.nation_id and t.can_recruit()):
		game.notify("No loyal linked town can supply recruits.", f.center_loc())
		return
	_do(f, "fill_from_towns")
