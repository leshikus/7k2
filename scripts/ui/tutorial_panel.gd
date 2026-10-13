class_name TutorialPanel
extends PanelContainer
## The tutorial's box (Tutor::disp, disp_guideline, disp_hints): the current
## objective's text page by page, the hints the original pointed out on the
## map, and Continue when the lesson waits for it.

signal show_target(loc: Vector2)

var tutorial: Tutorial
var title: Label
var body: RichTextLabel
var prev_btn: Button
var next_btn: Button
var cont_btn: Button
var show_btn: Button
var _shown := ""
var _timer := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 8
	offset_top = -330
	offset_right = 488
	offset_bottom = -40
	var vb := VBoxContainer.new()
	add_child(vb)
	title = Label.new()
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.45))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(title)
	body = RichTextLabel.new()
	body.bbcode_enabled = true
	body.custom_minimum_size = Vector2(460, 200)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_font_size_override("normal_font_size", 14)
	vb.add_child(body)
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	prev_btn = _btn(hb, "◀", func():
		tutorial.page = maxi(0, tutorial.page - 1)
		_refresh(true))
	next_btn = _btn(hb, "▶", func():
		tutorial.page = mini(tutorial.pages().size() - 1, tutorial.page + 1)
		_refresh(true))
	cont_btn = _btn(hb, "Continue", func():
		tutorial.continue_pressed = true
		_check())
	show_btn = _btn(hb, "Show me", func():
		var t := tutorial.focus_target()
		if t:
			show_target.emit(t.center_loc()))
	var hide_btn := _btn(hb, "Hide", func(): visible = false)
	hide_btn.tooltip_text = "The Tutorial button at the top shows it again."


## , and . turn the lesson's text back and forth (Tutor::prev/next_text_block).
func turn_page(step: int) -> void:
	tutorial.page = clampi(tutorial.page + step, 0, maxi(0, tutorial.pages().size() - 1))
	_refresh(true)


func _btn(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _process(delta: float) -> void:
	if tutorial == null:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.25
		_check()


func _check() -> void:
	var moved := tutorial.check()
	_refresh(moved)


func _refresh(force := false) -> void:
	if tutorial == null:
		return
	var pages := tutorial.pages()
	var key := "%d/%d/%d" % [tutorial.current, tutorial.page, int(tutorial.finished)]
	if key == _shown and not force:
		return
	_shown = key
	if moved_on_sound():
		visible = true
	if tutorial.finished or pages.is_empty():
		title.text = "%s — %s" % [tutorial.lesson.get("name", "Tutorial"), "practice" if not tutorial.finished else "well done"]
		body.text = "You have learnt what this lesson teaches. Now reach the lesson's goals to finish it." if tutorial.finished else "Play on: reach the lesson's goals."
		prev_btn.visible = false
		next_btn.visible = false
		cont_btn.visible = false
		show_btn.visible = false
		return
	tutorial.page = clampi(tutorial.page, 0, pages.size() - 1)
	var b: Dictionary = pages[tutorial.page]
	title.text = "%s — step %d%s" % [tutorial.lesson.get("name", "Tutorial"), tutorial.current, (": " + b["title"]) if b["title"] != "" else ""]
	var txt: String = b["text"]
	var hints := tutorial.current_hints()
	if not hints.is_empty() and tutorial.page == pages.size() - 1:
		txt += "\n\n[color=#a8c8ff]" + "\n".join(hints.map(func(h): return "• " + h)) + "[/color]"
	body.text = txt
	prev_btn.visible = pages.size() > 1
	next_btn.visible = pages.size() > 1
	prev_btn.disabled = tutorial.page == 0
	next_btn.disabled = tutorial.page >= pages.size() - 1
	cont_btn.visible = tutorial.wants_continue()
	cont_btn.disabled = tutorial.page < pages.size() - 1
	show_btn.visible = tutorial.focus_target() != null


func moved_on_sound() -> bool:
	return true
