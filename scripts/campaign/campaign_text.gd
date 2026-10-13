class_name CampaignText
extends RefCounted
## The campaign's texts from the install's Campaign folder (EAST.STG stage texts,
## EAST.EVT event letters, EAST.PLT plot notes), read like ResourceIdx: a count,
## then 13-byte entries (9-byte name, 4-byte offset), then the texts. A letter is
## split by "~" lines into its heading, its body and the replies to choose from.

static var _files := {}


static func _dir() -> String:
	var root := Assets.install_path
	for d in ["Campaign", "CAMPAIGN", "campaign"]:
		if DirAccess.dir_exists_absolute(root.path_join(d)):
			return root.path_join(d)
	return root.path_join("Campaign")


static func _load(file: String) -> Dictionary:
	if _files.has(file):
		return _files[file]
	var out := {}
	var path := SK2Files.find_file(_dir(), file)
	var d := FileAccess.get_file_as_bytes(path) if path != "" else PackedByteArray()
	if d.size() > 2:
		var n := d.decode_u16(0)
		var entries: Array = []
		for i in n + 1:
			var off := 2 + i * 13
			if off + 13 > d.size():
				break
			var name := ""
			for k in 9:
				var ch := d[off + k]
				if ch == 0:
					break
				name += char(ch)
			entries.append([name, d.decode_u32(off + 9)])
		for i in mini(n, entries.size() - 1):
			var a: int = entries[i][1]
			var b: int = mini(entries[i + 1][1], d.size())
			if a < b:
				out[entries[i][0]] = _decode(d.slice(a, b))
	_files[file] = out
	return out


## Windows-1252 text without its terminator, with plain newlines.
static func _decode(b: PackedByteArray) -> String:
	var s := ""
	for ch in b:
		if ch == 0:
			break
		if ch == 13:
			continue
		s += char(ch)
	return s


static func has_text() -> bool:
	return not _load("EAST.STG").is_empty()


static func stage(key: String) -> String:
	return _load("EAST.STG").get(key, "")


static func event(key: String) -> String:
	return _load("EAST.EVT").get(key, "")


static func plot(key: String) -> String:
	return _load("EAST.PLT").get(key, "")


## printf-style substitution: %s, %d, %1s ... take the arguments in order.
static func format(text: String, args: Array = []) -> String:
	var out := ""
	var ai := 0
	var i := 0
	while i < text.length():
		var ch := text[i]
		if ch == "%" and i + 1 < text.length():
			var j := i + 1
			if text[j] == "%":
				out += "%"
				i += 2
				continue
			while j < text.length() and (text[j].is_valid_int() or text[j] in ["-", "."]):
				j += 1
			if j < text.length() and text[j] in ["s", "d", "i", "u", "f", "c"]:
				out += str(args[ai]) if ai < args.size() else ""
				ai += 1
				i = j + 1
				continue
		out += ch
		i += 1
	return out


## A letter: {"head": who it comes from, "body": the letter, "replies": [...]}.
## Texts without "~" are plain narratives.
static func letter_parts(text: String) -> Dictionary:
	var parts := text.split("\n~\n")
	if parts.size() == 1:
		parts = text.split("~")
	var out := {"head": "", "body": text.strip_edges(), "replies": []}
	if parts.size() >= 2:
		out["head"] = parts[0].strip_edges()
		out["body"] = parts[1].strip_edges()
		for k in range(2, parts.size()):
			var r := parts[k].strip_edges()
			if r != "":
				out["replies"].append(r)
	return out
