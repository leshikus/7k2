class_name HelpText
extends RefCounted
## The original's help (ohelp.cpp, HELP.RES): texts keyed by the help code of
## each button. Our action buttons show the original text for the button they
## stand for, followed by any note of our own. (The file's other entries name
## screen areas of the original 800x600 layout, which this interface does not
## have.)

## our button label (its start) -> the original's help code
const CODES := {
	"Promote to General": "PROMOTE", "Demote to Soldier": "DEMOTE", "Build...": "BUILD",
	"Return": "RETCAMP", "Send out soldiers": "PATROL", "Send out defenders": "PATROL",
	"Send out brood": "F_PATROL", "Fill from towns": "TRAIN", "Hire caravan": "HIRECARA",
	"Clone caravan": "CARACOPY", "Set destination": "CSETSTOP", "Invoke Greater Being": "GDINVOKE",
	"Special Blessing": "BLESS", "Collect tax": "COLLTAX", "Grant gold": "GRANT",
	"Recruit peasant": "RECRUIT", "Demolish": "DESTFIRM", "Sell building": "SELLFIRM", "Rally point": "RALLY",
	"Build a town": "SETTLE", "Send out wagon": "WAGON", "Bribe": "BRIBE", "Assassinate": "ASSASSIN",
	"Steal tech": "STEAL_T", "Incident": "INCIDENT", "Secret report": "VSECRET",
	"Capture": "CAPTURE", "Mission": "CHG-MISS", "Recall spy": "MOBILSPY", "Take over": "F_GRANT",
	"Train spy": "TRAIN-S", "Hire ": "HIREUNIT", "Eject all": "MOBILIZE", "Disguise": "SPYNOTI0",
	"Camouflage": "SPYNOTI1", "Cast power": "MAGIC", "Formation": "FORMTION",
}

static var _texts := {}
static var _areas := {}      # title -> text of the screen-area entries
static var _loaded := false


static func _load() -> void:
	_loaded = true
	var path := SK2Files.find_file(Assets.install_path.path_join("Resource"), "HELP.RES")
	if path == "":
		return
	var txt := FileAccess.get_file_as_bytes(path).get_string_from_ascii().replace("\r", "")
	for blk in txt.split("~"):
		var lines := Array(blk.strip_edges().split("\n"))
		if lines.size() < 2:
			continue
		var head: String = lines[0].strip_edges()
		if head != "" and head[0] >= "0" and head[0] <= "9" and lines.size() >= 3:
			# a screen area of the original layout: keep it by its title
			_areas[String(lines[2]).strip_edges()] = " ".join(lines.slice(3).map(func(l): return String(l).strip_edges())).strip_edges()
			continue
		if head == "" or not (head[0] >= "A" and head[0] <= "Z"):
			continue
		var code := head.get_slice(",", 0).get_slice(" ", 0).strip_edges()
		_texts[code] = {"title": String(lines[1]).strip_edges(),
			"text": " ".join(lines.slice(2).map(func(l): return String(l).strip_edges())).strip_edges()}


static func by_code(code: String) -> Dictionary:
	if not _loaded:
		_load()
	return _texts.get(code, {})


static func code_for(label: String) -> String:
	for k in CODES:
		if label.begins_with(k):
			return CODES[k]
	return ""


## The text of the screen-area help entry whose title starts with `title`
## (the report buttons, the top bar's readouts, the map buttons).
static func area_text(title: String) -> String:
	if not _loaded:
		_load()
	for k in _areas:
		if k.begins_with(title):
			return "%s: %s" % [k, _areas[k]]
	return ""


## The original help for a button with this label, as "Title: text".
static func for_label(label: String) -> String:
	var h := by_code(code_for(label))
	if h.is_empty():
		return ""
	return "%s: %s" % [h["title"], h["text"]] if h["text"] != "" else h["title"]
