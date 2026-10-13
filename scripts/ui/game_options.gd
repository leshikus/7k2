class_name GameOptions
extends RefCounted
## The original's Options menu (ooptmenu.cpp, Config): kept in user://settings.cfg.

const SECTION := "options"
const DEFAULTS := {
	"show_unit_path": 0,     # bit 0 the main view, bit 1 the world map (No / Main Map / World Map / Both)
	"help_mode": 2,          # 0 no help, 1 brief (titles), 2 detailed (help_mode)
	"news": 1,               # 0 major news only, 1 all news (disp_news_flag)
	"sfx_volume": 100,       # sound_effect_volume
	"music_volume": 100,     # wav_music_volume
	"scroll_speed": 5,       # 1..10 (scroll_speed)
	"show_unit_icons": 1,    # unit identities: 0 when pointed at, 1 always (show_all_unit_icon)
	"inside_info": false,    # show the computer's information (show_ai_info)
	"scroll_method": 0,      # 0 comfort, 1 speed
}

static var _values := {}
static var _loaded := false


static func _load() -> void:
	_loaded = true
	_values = DEFAULTS.duplicate()
	var cf := ConfigFile.new()
	if cf.load(Assets.SETTINGS_PATH) == OK:
		for k in DEFAULTS:
			_values[k] = cf.get_value(SECTION, k, DEFAULTS[k])


static func get_opt(key: String):
	if not _loaded:
		_load()
	return _values.get(key, DEFAULTS.get(key))


static func set_opt(key: String, v) -> void:
	if not _loaded:
		_load()
	_values[key] = v
	var cf := ConfigFile.new()
	cf.load(Assets.SETTINGS_PATH)
	cf.set_value(SECTION, key, v)
	cf.save(Assets.SETTINGS_PATH)


## For tests: options in memory only.
static func reset() -> void:
	_values = DEFAULTS.duplicate()
	_loaded = true
