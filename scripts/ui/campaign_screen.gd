class_name CampaignScreen
extends Control
## The campaign's strategic screen (Campaign::disp_strategic_screen): the map of
## provinces in their kingdoms' colours, the reports and letters of the story
## with your replies, and the briefing before each battle.

signal start_battle
signal back_to_menu

var campaign: Campaign
var map_view: Control
var text: RichTextLabel
var title: Label
var buttons: HBoxContainer
var legend: RichTextLabel
var status_label: Label

var _highlight := {}          # state id -> Color
var _arrow := []              # [from state, to state, color]
var _picking: Array = []
var _hover := 0
signal _picked(state: int)
signal _replied(n: int)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Hud.make_theme()
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.04, 0.03)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var pic := TextureRect.new()
	pic.set_anchors_preset(Control.PRESET_FULL_RECT)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	pic.texture = Assets.image("campaign.jpg")
	pic.modulate = Color(1, 1, 1, 0.35)
	add_child(pic)
	var hb := HBoxContainer.new()
	hb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 16
	hb.offset_top = 16
	hb.offset_right = -16
	hb.offset_bottom = -16
	hb.add_theme_constant_override("separation", 16)
	add_child(hb)
	# --- map and legend
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.1
	hb.add_child(left)
	var head := Label.new()
	head.text = "The Fryhtan Wars"
	head.add_theme_font_size_override("font_size", 26)
	head.add_theme_color_override("font_color", Color(1, 0.85, 0.45))
	left.add_child(head)
	status_label = Label.new()
	left.add_child(status_label)
	var frame := PanelContainer.new()
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(frame)
	map_view = Control.new()
	map_view.custom_minimum_size = Vector2(420, 420)
	map_view.mouse_filter = Control.MOUSE_FILTER_STOP
	map_view.draw.connect(_draw_map)
	map_view.gui_input.connect(_map_input)
	frame.add_child(map_view)
	legend = RichTextLabel.new()
	legend.bbcode_enabled = true
	legend.fit_content = true
	legend.custom_minimum_size = Vector2(0, 110)
	left.add_child(legend)
	# --- the story
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(right)
	title = Label.new()
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.45))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(title)
	var tp := PanelContainer.new()
	tp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(tp)
	text = RichTextLabel.new()
	text.bbcode_enabled = true
	text.scroll_active = true
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text.add_theme_font_size_override("normal_font_size", 15)
	tp.add_child(text)
	buttons = HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	right.add_child(buttons)
	var bottom := HBoxContainer.new()
	right.add_child(bottom)
	var menu_btn := Button.new()
	menu_btn.text = "Main menu"
	menu_btn.pressed.connect(func(): back_to_menu.emit())
	bottom.add_child(menu_btn)
	refresh()


func refresh() -> void:
	if campaign == null:
		return
	status_label.text = "Year %d   Difficulty %d   Score %d   %s" % [campaign.game_year, campaign.difficulty, campaign.score,
		("Battle: " + campaign.stage_name()) if campaign.event_id == 0 and campaign.stage_id > 0 else ""]
	var lines := []
	var ids: Array = campaign.nations.keys()
	ids.sort()
	for id in ids:
		var n: Dictionary = campaign.nations[id]
		var col: Color = Defs.NATION_COLORS[n["color"] % Defs.NATION_COLORS.size()]
		var kind := "you" if id == campaign.western else ("Fryhtans" if n["type"] == "monster" else "")
		var rel := ""
		if id != campaign.western and n["type"] != "monster":
			rel = ", " + Defs.RELATION_NAMES[campaign.relation(id)].to_lower()
		lines.append("[color=#%s]■[/color] %s (%s%s) — %d province%s" % [col.to_html(false), n["name"], kind if kind != "" else campaign.race_name(id), rel,
			campaign.map.nation_state_count(id), "" if campaign.map.nation_state_count(id) == 1 else "s"])
	if campaign.map.nation_state_count(0) > 0:
		lines.append("[color=#%s]■[/color] Independent — %d" % [Defs.INDEPENDENT_COLOR.to_html(false), campaign.map.nation_state_count(0)])
	legend.text = "\n".join(lines)
	map_view.queue_redraw()


# ---------------------------------------------------------------- map ---

func _map_rect() -> Rect2:
	var s := minf(map_view.size.x, map_view.size.y)
	return Rect2((map_view.size - Vector2(s, s)) / 2.0, Vector2(s, s))


func _state_color(id: int) -> Color:
	var nid: int = campaign.map.get_state(id).get("nation", 0)
	if nid == 0 or not campaign.nations.has(nid):
		return Defs.INDEPENDENT_COLOR
	return Defs.NATION_COLORS[campaign.nations[nid]["color"] % Defs.NATION_COLORS.size()]


func _draw_map() -> void:
	if campaign == null:
		return
	var r := _map_rect()
	var cell := r.size.x / StateMap.W
	var m := campaign.map
	for y in StateMap.H:
		for x in StateMap.W:
			var s := m.state_at(x, y)
			var col := _state_color(s).darkened(0.35)
			if _highlight.has(s):
				col = col.lerp(_highlight[s], 0.45)
			if s == _hover and s in _picking:
				col = col.lightened(0.35)
			map_view.draw_rect(Rect2(r.position + Vector2(x, y) * cell, Vector2(cell + 0.6, cell + 0.6)), col)
	# borders
	for y in StateMap.H:
		for x in StateMap.W:
			var s := m.state_at(x, y)
			var p := r.position + Vector2(x, y) * cell
			if x + 1 < StateMap.W and m.state_at(x + 1, y) != s:
				map_view.draw_line(p + Vector2(cell, 0), p + Vector2(cell, cell), Color(0, 0, 0, 0.8), 1.5)
			if y + 1 < StateMap.H and m.state_at(x, y + 1) != s:
				map_view.draw_line(p + Vector2(0, cell), p + Vector2(cell, cell), Color(0, 0, 0, 0.8), 1.5)
	var font := get_theme_default_font()
	for s in range(1, m.size() + 1):
		var st := m.get_state(s)
		var c := r.position + Vector2(st["cx"] + 0.5, st["cy"] + 0.5) * cell
		var nid: int = st["nation"]
		map_view.draw_circle(c, 5.0, Color(1, 0.95, 0.7) if nid == campaign.western else Color(0.1, 0.08, 0.05))
		if s in _picking:
			map_view.draw_arc(c, 11.0, 0, TAU, 24, Color(1, 0.9, 0.3), 2.5)
	if not _arrow.is_empty() and _arrow[0] > 0:
		var a := m.get_state(_arrow[0])
		var b := m.get_state(_arrow[1])
		var pa := r.position + Vector2(a["cx"] + 0.5, a["cy"] + 0.5) * cell
		var pb := r.position + Vector2(b["cx"] + 0.5, b["cy"] + 0.5) * cell
		var col: Color = _arrow[2]
		map_view.draw_line(pa, pb, col, 4.0)
		var dir := (pb - pa).normalized()
		map_view.draw_colored_polygon(PackedVector2Array([pb, pb - dir * 16 + dir.orthogonal() * 8, pb - dir * 16 - dir.orthogonal() * 8]), col)
	if font:
		map_view.draw_string(font, r.position + Vector2(6, r.size.y - 6), "West", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.6))
		map_view.draw_string(font, r.position + Vector2(r.size.x - 36, r.size.y - 6), "East", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.6))


func _state_under(pos: Vector2) -> int:
	var r := _map_rect()
	var cell := r.size.x / StateMap.W
	var q := (pos - r.position) / cell
	return campaign.map.state_at(int(q.x), int(q.y))


func _map_input(ev: InputEvent) -> void:
	if campaign == null:
		return
	if ev is InputEventMouseMotion:
		var s := _state_under(ev.position)
		if s != _hover:
			_hover = s
			map_view.queue_redraw()
			var nid: int = campaign.map.get_state(s).get("nation", 0) if s else 0
			map_view.tooltip_text = ("Province of the %s" % campaign.nation_name(nid)) if s else ""
	elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and not _picking.is_empty():
		var s := _state_under(ev.position)
		if s in _picking:
			_picked.emit(s)


# ------------------------------------------------------------- the UI ---

func _clear_buttons() -> void:
	for b in buttons.get_children():
		b.queue_free()


func _button(label: String, n: int) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(0, 34)
	b.pressed.connect(func(): _replied.emit(n))
	buttons.add_child(b)
	return b


func _show(head: String, body: String) -> void:
	title.text = head
	text.text = body
	text.scroll_to_line(0)
	refresh()


## A report: shown until you press Continue.
func narrative(t: String) -> void:
	if t.strip_edges() == "":
		return
	var parts := CampaignText.letter_parts(t)
	_show(parts["head"] if parts["head"] != "" else "News", parts["body"])
	_clear_buttons()
	_button("Continue", 1)
	await _replied


## A letter: a reply button for each reply it offers.
func letter(t: String) -> int:
	var parts := CampaignText.letter_parts(t)
	_show(parts["head"] if parts["head"] != "" else "A letter", parts["body"])
	_clear_buttons()
	var replies: Array = parts["replies"]
	if replies.is_empty():
		_button("Continue", 1)
		return await _replied
	text.text += "\n\n[color=#e0c070]Your reply:[/color]"
	for i in replies.size():
		text.text += "\n[color=#e0c070]%d.[/color] %s" % [i + 1, replies[i]]
		_button("Reply %d" % (i + 1), i + 1)
	return await _replied


## An attack on a province, drawn as an arrow for a moment.
func attack(from: int, to: int, result: int, from2: int) -> void:
	_highlight = {to: Color(1, 0.3, 0.2)}
	if from2:
		_highlight[from2] = Color(0.4, 0.7, 1.0)
	_arrow = [from, to, Color(1, 0.4, 0.2) if result >= 0 else Color(0.6, 0.6, 0.6)]
	map_view.queue_redraw()
	if is_inside_tree():
		await get_tree().create_timer(1.2).timeout
	_arrow = []
	_highlight = {}
	refresh()


## You choose a province to attack on the map.
func pick_state(cands: Array) -> int:
	_picking = cands
	title.text = "Choose a province to attack"
	text.text = "Click one of the marked provinces on the map."
	_clear_buttons()
	map_view.queue_redraw()
	var s: int = await _picked
	_picking = []
	map_view.queue_redraw()
	return s


# ------------------------------------------------------------ the loop ---

## Runs events until a battle is due (start_battle) or the campaign ends.
func run() -> void:
	campaign.ui = self
	refresh()
	while not campaign.finished:
		if campaign.event_id:
			await campaign.process_event()
			campaign.save()
			continue
		await campaign.stage_prelude()
		campaign.save()
		var goal := campaign.goal_text()
		var intro := campaign.intro_text()
		_show("Battle: %s" % campaign.stage_name(), (intro + "\n\n[color=#e0c070]Objective[/color]\n" + goal).strip_edges())
		_clear_buttons()
		_button("Begin the battle", 1)
		await _replied
		start_battle.emit()
		return
	_finale()


func _finale() -> void:
	refresh()
	if campaign.victory:
		_show("Ultimate Victory", "The Fryhtan Wars are over. Your empire stands united and the land is free.\n\nYour score: %d" % campaign.score)
	else:
		_show("Defeat", "Your empire has fallen. Perhaps another ruler will rise to drive back the Fryhtans.")
	_clear_buttons()
	var b := Button.new()
	b.text = "Back to the main menu"
	b.pressed.connect(func(): back_to_menu.emit())
	buttons.add_child(b)


## After a battle: its outcome changes the provinces, then the story goes on.
func after_battle(won: bool, win_id: int, lose_id: int, years: int) -> void:
	campaign.ui = self
	await campaign.process_game_result(won, win_id, lose_id, years)
	campaign.save()
	run()
