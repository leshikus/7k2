class_name TipsBox
extends PanelContainer
## Tips at the start of a game (otips.cpp): from the install's TIPS.RES, in
## sections for human rulers, Fryhtan rulers and the campaign.

const PREFS := "user://tips.cfg"

var tips: Array = []
var index := 0
var label: Label


static func load_tips(section: String) -> Array:
	var path := SK2Files.find_file(Assets.install_path.path_join("Resource"), "TIPS.RES")
	if path == "":
		return []
	var txt := FileAccess.get_file_as_bytes(path).get_string_from_ascii().replace("\r", "")
	var out: Array = []
	for sec in txt.split("@").slice(1):
		var name := sec.get_slice("\n", 0).strip_edges()
		if name != section:
			continue
		for t in sec.substr(sec.find("\n") + 1).split("~"):
			if t.strip_edges() != "":
				out.append(t.strip_edges())
	return out


static func enabled() -> bool:
	var cf := ConfigFile.new()
	return cf.load(PREFS) != OK or cf.get_value("tips", "show", true)


func setup(section: String, rng_seed: int) -> bool:
	tips = load_tips(section)
	if tips.is_empty():
		return false
	index = posmod(rng_seed, tips.size())
	return true


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -220
	offset_right = 220
	offset_top = -110
	var vb := VBoxContainer.new()
	add_child(vb)
	var t := Label.new()
	t.text = "Tip"
	t.add_theme_font_size_override("font_size", 16)
	t.add_theme_color_override("font_color", Color(1, 0.85, 0.45))
	vb.add_child(t)
	label = Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(420, 90)
	vb.add_child(label)
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	var never := CheckBox.new()
	never.text = "Don't show tips"
	never.toggled.connect(func(on):
		var cf := ConfigFile.new()
		cf.load(PREFS)
		cf.set_value("tips", "show", not on)
		cf.save(PREFS))
	never.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(never)
	var nx := Button.new()
	nx.text = "Next tip"
	nx.pressed.connect(func():
		index = (index + 1) % tips.size()
		label.text = tips[index])
	hb.add_child(nx)
	var ok := Button.new()
	ok.text = "OK"
	ok.pressed.connect(queue_free)
	hb.add_child(ok)
	label.text = tips[index]
