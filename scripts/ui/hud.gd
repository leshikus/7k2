class_name Hud
extends CanvasLayer
## In-game interface: resource bar, info/action panel, minimap, messages,
## diplomacy window and game-over screen.

signal build_requested(code: String)
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
var pause_menu: PanelContainer
var tooltip_label: Label
var build_menu_open := false

var _refresh_timer := 0.0
var _last_sel_key := ""
var _messages: Array = []


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
	for s in [["II", 0.0], ["1x", 1.0], ["2x", 2.0], ["4x", 4.0]]:
		var b := Button.new()
		b.text = s[0]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(34, 0)
		var spd: float = s[1]
		b.pressed.connect(func(): _set_speed(spd))
		hb.add_child(b)
		speed_buttons.append(b)
	var dip := Button.new()
	dip.text = "Diplomacy"
	dip.pressed.connect(toggle_diplomacy)
	hb.add_child(dip)
	var spy_btn := Button.new()
	spy_btn.text = "Spies"
	spy_btn.pressed.connect(toggle_spies)
	hb.add_child(spy_btn)
	var menu := Button.new()
	menu.text = "Menu"
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
	actions.columns = 2
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
	dclose.text = "Close"
	dclose.pressed.connect(toggle_diplomacy)
	dv.add_child(dclose)

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
	for item in [["Resume", toggle_pause_menu], ["Save game (F5)", do_save], ["Load game (F9)", do_load], ["Reveal map (cheat)", reveal],
			["New game", func(): menu_new_game.emit()], ["Quit", func(): get_tree().quit()]]:
		var b := Button.new()
		b.text = item[0]
		b.pressed.connect(item[1])
		pv.add_child(b)

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
	ov.add_child(overlay_label)
	var ob := Button.new()
	ob.text = "New game"
	ob.pressed.connect(func(): menu_new_game.emit())
	ov.add_child(ob)
	var oq := Button.new()
	oq.text = "Quit"
	oq.pressed.connect(func(): get_tree().quit())
	ov.add_child(oq)
	_sync_speed_buttons()


## True when the mouse is over an interface element (the map should ignore it).
func is_over_ui(p: Vector2) -> bool:
	for c in [panel, diplo, pause_menu, overlay, spies_panel]:
		if c == null:
			continue
		if c.visible and c.get_global_rect().has_point(p):
			return true
	return p.y < 40


func _set_speed(s: float) -> void:
	if s == 0.0:
		game.paused = not game.paused
	else:
		game.paused = false
		game.speed = s
	_sync_speed_buttons()
	speed_changed.emit()


func _sync_speed_buttons() -> void:
	if game == null or speed_buttons.is_empty():
		return
	speed_buttons[0].button_pressed = game.paused
	for i in range(1, 4):
		speed_buttons[i].button_pressed = not game.paused and game.speed == [0.0, 1.0, 2.0, 4.0][i]


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
		close.text = "Close"
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
		var where := "infiltrated in %s" % u.spy_place.display_name() if u.spy_place and is_instance_valid(u.spy_place) and u.has_meta("hidden") else "in the field"
		l.text = "%s (skill %d) — %s" % [u.unit_name, int(u.spy_skill), where]
		l.custom_minimum_size = Vector2(330, 0)
		row.add_child(l)
		if u.has_meta("hidden") and u.spy_place is Firm:
			var sab := Button.new()
			sab.text = "Sabotage"
			sab.pressed.connect(func():
				u.spy_action = "sabotage"
				_fill_spies())
			row.add_child(sab)
			if (u.spy_place as Firm).code == "RESEARCH":
				var st := Button.new()
				st.text = "Steal tech"
				st.disabled = u.spy_skill < Defs.MIN_TECH_THEFT_SPYING_SKILL
				st.tooltip_text = "Needs spying skill %d." % Defs.MIN_TECH_THEFT_SPYING_SKILL
				st.pressed.connect(func():
					u.spy_action = "steal"
					_fill_spies())
				row.add_child(st)
		if u.has_meta("hidden"):
			var rc := Button.new()
			rc.text = "Recall"
			rc.pressed.connect(func():
				game.spy_leave(u)
				_fill_spies())
			row.add_child(rc)


func toggle_diplomacy() -> void:
	diplo.visible = not diplo.visible
	if diplo.visible:
		_fill_diplomacy()


func _fill_diplomacy() -> void:
	for c in diplo_list.get_children():
		c.queue_free()
	var p := game.player()
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
		var ratio := game.military_strength(n.id) / maxf(1.0, game.military_strength(p.id))
		var strength := "weaker" if ratio < 0.8 else ("stronger" if ratio > 1.25 else "similar")
		l.text = "[color=#%s]■[/color] [b]%s[/b] — %s\n   Reputation %d, army %s than yours" % [n.color.to_html(false), n.name, status, int(n.reputation), strength]
		row.add_child(l)
		if not n.alive:
			continue
		var rel := p.relation(n.id)
		if rel == Defs.Relation.WAR or rel == Defs.Relation.NEUTRAL:
			var b := Button.new()
			b.text = "Propose peace"
			var nid := n.id
			b.pressed.connect(func():
				var ok := game.propose_peace(p.id, nid)
				if not ok:
					game.notify("The %s rejects your offer of peace." % game.nation(nid).name, Vector2(-1, -1))
				_fill_diplomacy())
			row.add_child(b)
		if rel != Defs.Relation.WAR:
			var w := Button.new()
			w.text = "Declare war"
			var nid2 := n.id
			w.pressed.connect(func():
				game.declare_war(p.id, nid2)
				_fill_diplomacy())
			row.add_child(w)


func _on_message(text: String, _loc: Vector2) -> void:
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
	var rebuild := force or key != _last_sel_key
	_last_sel_key = key
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
	if not p.tech.is_empty():
		s += "\nTechnology:\n"
		for k in p.tech:
			s += "  %s %d\n" % [Defs.tech_def(k).get("name", k), p.tech[k]]
	s += "\n[color=#b0a890]Left-click to select, drag to box-select. Right-click to give orders. WASD / arrows / screen edge to scroll, wheel to zoom, Space to pause.[/color]"
	return s


func _clear_actions() -> void:
	for c in actions.get_children():
		actions.remove_child(c)
		c.queue_free()
	tooltip_label.text = ""


func _add_action(text: String, cb: Callable, enabled := true, tip := "", right_cb := Callable()) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.clip_text = true
	b.custom_minimum_size = Vector2(130, 28)
	b.pressed.connect(func():
		cb.call()
		refresh_selection(true))
	if tip != "":
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
	if u.is_spy:
		s += "[color=#c0a0ff]Spy[/color], spying skill %d\nRight-click an enemy or independent town or building to infiltrate it.\n" % int(u.spy_skill)
	if u.life_frames > 0:
		s += "Vanishes in %d days\n" % (u.life_frames / Defs.FRAMES_PER_DAY)
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
			u.stop())
	if own.any(func(u): return u.is_human()) or game.player().is_fryhtan:
		_add_action("Build...", func(): build_menu_open = true, true, "Choose a building to construct. The nearest selected unit will build it.")
	if own.size() == 1:
		var u: Unit = own[0]
		if u.is_human() and u.rank == Defs.Rank.SOLDIER:
			var promote := func():
				u.rank = Defs.Rank.GENERAL
				u.leadership = maxf(u.leadership, 25.0)
			_add_action("Promote to General", promote, true, "A general can command a camp, extending the kingdom's influence over nearby towns.")
		if u.rank == Defs.Rank.GENERAL and not u.is_hero:
			_add_action("Demote to Soldier", func(): u.rank = Defs.Rank.SOLDIER)
		if u.home_town == null and u.is_human():
			_add_action("Settle in town", func(): _settle(u), true, "Walk to the nearest own town and rejoin its population.")
		if u.is_god:
			var gi := u.god_info()
			if not gi.is_empty() and Defs.GOD_POWERS.has(gi["race"]):
				_add_action("Cast power (%d)" % gi["power_pray"], func(): u.cast_power(), u.can_cast_power(), Defs.GOD_POWERS[gi["race"]] + ". Costs prayer points.")


func _settle(u: Unit) -> void:
	var best: Town = null
	var best_d := INF
	for t in game.towns:
		if t.nation_id == u.nation_id and t.race == u.race:
			var d := t.center_loc().distance_to(u.center_loc())
			if d < best_d:
				best_d = d
				best = t
	if best:
		u.home_town = best
		u.stop()
		u.order = Unit.Order.RETURN
	else:
		game.notify("No town of the same race to settle in.", Vector2(-1, -1))


func _build_menu() -> void:
	var p := game.player()
	if p.is_fryhtan:
		_add_action("Lair (%d gold, %d life)" % [int(FryhtanAI.LAIR_COST), int(FryhtanAI.LAIR_LIVE)], func():
			build_menu_open = false
			build_requested.emit("LAIR"), p.cash >= FryhtanAI.LAIR_COST and p.live_points >= FryhtanAI.LAIR_LIVE,
			"A new lair breeds more of your brood and spreads your terror to nearby villages.")
		_add_action("Cancel", func(): build_menu_open = false)
		return
	for code in Defs.HUMAN_FIRMS:
		var ft: Dictionary = Defs.firm_types.get(code, {})
		var cost: int = ft.get("cost", 0)
		var c: String = code
		var pick := func():
			build_menu_open = false
			build_requested.emit(c)
		_add_action("%s (%d)" % [ft.get("name", code), cost], pick, p.cash >= cost, Defs.FIRM_HELP.get(code, ""))
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
	info_label.text = s
	if not rebuild:
		return
	_clear_actions()
	if t.nation_id == game.player_id:
		var do_recruit := func():
			var u := t.recruit()
			if u:
				game.selected = [u]
				u.selected = true
		_add_action("Recruit peasant", do_recruit, t.can_recruit(), "Recruit a villager as a peasant unit; peasants become soldiers in a fort. Needs loyalty %d+." % Defs.MIN_RECRUIT_LOYALTY)
		var do_tax := func():
			var tax := t.collect_tax()
			game.notify("Collected %d gold from %s." % [int(tax), t.town_name], t.center_loc())
		_add_action("Collect tax" + (" (auto %d)" % t.auto_tax_loyalty if t.auto_tax_loyalty > 0 else ""), do_tax, t.has_linked_camp(t.nation_id),
			"Needs a linked camp with a general. Lowers loyalty. Right-click: collect automatically when loyalty reaches %s." % "/".join(Town.AUTO_TAX_LEVELS.slice(1).map(func(v): return str(v))),
			func(): t.auto_tax_loyalty = Town.next_level(Town.AUTO_TAX_LEVELS, t.auto_tax_loyalty))
		_add_action("Grant gold (%d)" % int(t.grant_cost()) + (" (auto <%d)" % t.auto_grant_loyalty if t.auto_grant_loyalty > 0 else ""), func(): t.grant(game.player_id), game.player().cash >= t.grant_cost(),
			"Raise the town's loyalty. Right-click: grant automatically when loyalty falls below %s." % "/".join(Town.AUTO_GRANT_LEVELS.slice(1).map(func(v): return str(v))),
			func(): t.auto_grant_loyalty = Town.next_level(Town.AUTO_GRANT_LEVELS, t.auto_grant_loyalty))
		if t.target_wall_level < 2:
			var lvl := t.target_wall_level + 1
			_add_action("Build %s (%d)" % ["wall" if lvl == 1 else "fortified wall", Town.WALL_COST[lvl]], func(): t.build_wall(), game.player().cash > 0,
				"Jobless villagers build it. Walls absorb attacks and shield the town from enemy influence.")
	elif t.nation_id == 0:
		_add_action("Grant gold (%d)" % int(t.grant_cost()), func(): t.grant(game.player_id),
			game.player().cash >= t.grant_cost() and t.has_linked_camp(game.player_id), "Lower the town's resistance to you. Needs one of your camps linked to it.")


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
	if own or f.is_monster():
		match f.code:
			"CAMP", "FORT", "LAIR":
				if f.overseer:
					s += "Commander: %s (leadership %d)\n" % [f.overseer.display_name(), int(f.overseer.leadership)]
				elif f.code != "LAIR":
					s += "[color=#ff9060]No general. Send a general here to gain influence.[/color]\n"
				s += "Soldiers %d / %d\n" % [f.soldiers.size(), f.capacity()]
				for u in f.soldiers:
					s += "  %s — combat %d, HP %d\n" % [u.display_name() if u.is_human() else u.type_name(), int(u.combat), int(u.hp)]
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
					s += "Researching %s %d: %d%%\n" % [t["name"], lvl + 1, int(100.0 * f.research_points / Firm.research_cost(t, lvl))]
				else:
					s += "Choose a technology to research.\n"
			"STABLE":
				if f.weapon != "":
					s += "Training %s: %d%% (%d queued)\n" % [Defs.unit_types[f.weapon]["name"], int(f.weapon_progress), f.weapon_queue]
				else:
					s += "Trains: %s\n" % Defs.unit_types.get(f.special_unit(), {}).get("name", "?")
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
				s += "Worshippers %d / %d\nPrayer points %d / %d\n" % [f.workers(), Defs.MAX_WORKER, int(game.player().prayer_points), int(f.god_cost())]
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
	info_label.text = s
	if not rebuild:
		return
	_clear_actions()
	if not own:
		return
	var p := game.player()
	match f.code:
		"CAMP", "FORT":
			_add_action("Eject all", func(): f.eject_all())
			_add_action("Fill from towns", func(): _fill_camp(f), true, "Villagers from your linked towns join this fort at once (towns need loyalty %d+)." % Defs.MIN_RECRUIT_LOYALTY)
			if not f.soldiers.is_empty():
				_add_action("Send out soldiers", func():
					for su in f.soldiers.duplicate():
						f.release_unit(su))
			_occupant_buttons(f)
		"LAIR":
			if f.is_fryhtan_lair():
				var ut: Dictionary = Defs.unit_types.get(f.monster_code, {})
				_add_action("Breed %s (%d gold, %d life)" % [ut.get("name", f.monster_code), int(ut.get("cost", 100)), int(ut.get("live_cost", 50))], func(): f.breed(),
					f.soldiers.size() < f.capacity() and p.cash >= ut.get("cost", 100) and p.live_points >= ut.get("live_cost", 50),
					"Breed a new Fryhtan in this lair. Life points come from slaying enemies.")
			if not f.soldiers.is_empty():
				_add_action("Send out brood", func():
					for su in f.soldiers.duplicate():
						f.release_unit(su))
			_occupant_buttons(f)
		"MARKET":
			var partner := game.find_trade_partner(f, f.nation_id)
			var tip := "A caravan carries goods to %s." % (partner.display_name() + " of the " + (partner.nation().name if partner.nation() else "") if partner else "another market (none in reach yet: build one further away, or make peace with a neighbour)")
			_add_action("Hire caravan (%d)" % int(Firm.CARAVAN_COST), func(): f.hire_caravan(), p.cash >= Firm.CARAVAN_COST and game.caravans_of(f) < Firm.MAX_CARAVANS, tip)
		"RESEARCH":
			for t in Defs.TECHS:
				var lvl := p.tech_level(t["code"])
				var ok: bool = lvl < t["max"]
				if t.has("req") and p.tech_level(t["req"]) < t["req_lvl"]:
					ok = false
				var tc: String = t["code"]
				var label := "%s %d" % [t["name"], lvl + 1] if lvl < t["max"] else "%s (max)" % t["name"]
				var b := _add_action(label, func(): f.start_research(tc), ok)
				if f.research_tech == tc:
					b.text = "▶ " + label
		"WAR":
			for wcode in Defs.WEAPONS:
				var ut: Dictionary = Defs.unit_types.get(wcode, {})
				var wc: String = wcode
				_add_action("%s (%d)" % [ut.get("name", wcode), ut.get("cost", 0)], func(): f.queue_weapon(wc), p.tech_level(wcode) > 0,
					"Research %s at a Tower of Science first." % ut.get("name", wcode) if p.tech_level(wcode) == 0 else "")
		"SPY":
			var can_spy := f.linked_towns.any(func(t): return t.nation_id == f.nation_id and t.can_recruit())
			_add_action("Train spy (%d)" % Defs.SPY_COST, func(): f.weapon_queue += 1, can_spy and p.cash >= Defs.SPY_COST,
				"Needs a linked town of yours with loyalty %d+. Right-click a spy on an enemy or independent town or building to infiltrate it." % Defs.MIN_RECRUIT_LOYALTY)
		"STABLE":
			var spu := f.special_unit()
			var ut: Dictionary = Defs.unit_types.get(spu, {})
			var can := f.linked_towns.any(func(t): return t.nation_id == f.nation_id and t.can_recruit())
			_add_action("Train %s (%d)" % [ut.get("name", spu), ut.get("cost", 0)], func(): f.queue_weapon(spu), can and p.cash >= ut.get("cost", 0),
				"Needs a linked town of yours with loyalty %d+ to supply a volunteer." % Defs.MIN_RECRUIT_LOYALTY)
		"INN":
			for i in f.heroes.size():
				var hdef: Dictionary = f.heroes[i]
				var idx := i
				var hire := func():
					var u := f.hire_hero(idx)
					if u:
						game.notify("%s has joined you." % u.unit_name, u.center_loc())
				_add_action("Hire %s" % hdef["name"], hire, p.cash >= hdef["cost"])
		"BASE":
			var invoke := func():
				var u := f.invoke_god()
				if u:
					game.notify("%s answers your prayers!" % u.type_name(), u.center_loc())
			_add_action("Invoke Greater Being", invoke, p.prayer_points >= f.god_cost())
	_add_action("Demolish", func(): f.die(null), true, "Destroy this building. Units inside will leave.")


## One button per occupant: left-click sends him out and selects him,
## right-click makes a soldier the commander (swapping with the current one).
func _occupant_buttons(f: Firm) -> void:
	var occupants: Array = ([f.overseer] if f.overseer else []) + f.soldiers
	for su in occupants:
		var who: Unit = su
		var lbl := ("★ " if who == f.overseer else "") + (who.display_name() if who.is_human() else who.type_name()) + " (%d)" % int(who.combat)
		var out := func():
			f.release_unit(who)
			for o in game.selected:
				if is_instance_valid(o):
					o.selected = false
			game.selected = [who]
			who.selected = true
		var promote := func():
			if who != f.overseer and who.can_lead():
				f.make_overseer(who)
		_add_action(lbl, out, true, "Left-click: send out. Right-click a general: make him commander.", promote)


func _fill_camp(f: Firm) -> void:
	var n := 0
	for t in f.linked_towns:
		if t.nation_id != f.nation_id:
			continue
		while f.soldiers.size() < f.capacity() and t.can_recruit():
			if t.draft_into(f) == null:
				break
			n += 1
	if n == 0:
		game.notify("No loyal linked town can supply recruits.", f.center_loc())
