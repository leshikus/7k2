class_name Profiles
extends RefCounted
## Player profiles (oprofile.cpp, oprofil2.cpp: PlayerProfile::register_menu):
## the player logs in under a name; each profile keeps its own saved games and
## campaign, and the name is given to the player's king (config.player_name).

const ROOT := "user://profiles"
const NAME_LEN := 20


static func current() -> String:
	var cf := ConfigFile.new()
	if cf.load(Assets.SETTINGS_PATH) != OK:
		return ""
	return str(cf.get_value("profile", "name", ""))


static func set_current(player_name: String) -> void:
	var cf := ConfigFile.new()
	cf.load(Assets.SETTINGS_PATH)
	cf.set_value("profile", "name", player_name)
	cf.save(Assets.SETTINGS_PATH)


static func _safe(player_name: String) -> String:
	var out := ""
	for ch in player_name.strip_edges():
		out += ch if ch.is_valid_identifier() or ch.is_valid_int() or ch in [" ", "-"] else "_"
	return out.strip_edges()


## PlayerProfile::save_game_path: where this profile's games are saved
## (the shared folder when no one has logged in).
static func save_dir() -> String:
	var n := _safe(current())
	return "user://saves" if n == "" else "%s/%s/saves" % [ROOT, n]


static func list() -> Array:
	var out: Array = []
	var d := DirAccess.open(ROOT)
	if d:
		for sub in d.get_directories():
			out.append(sub)
	out.sort()
	return out


## Creates (or selects) a profile; returns false for an empty or too long name.
static func login(player_name: String) -> bool:
	var n := _safe(player_name)
	if n == "" or n.length() > NAME_LEN:
		return false
	DirAccess.make_dir_recursive_absolute("%s/%s/saves" % [ROOT, n])
	set_current(n)
	return true


static func remove(player_name: String) -> void:
	var dir := "%s/%s" % [ROOT, _safe(player_name)]
	for sub in ["saves"]:
		var d := DirAccess.open(dir.path_join(sub))
		if d:
			for f in d.get_files():
				d.remove(f)
			DirAccess.remove_absolute(dir.path_join(sub))
	DirAccess.remove_absolute(dir)
	if current() == _safe(player_name):
		set_current("")
