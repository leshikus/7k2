extends Node
## Autoload "Assets": locates an installed copy of Seven Kingdoms II and serves
## its graphics and data tables to the game. Nothing from the original game is
## shipped with this project; everything is decoded at runtime from the install.

const SETTINGS_PATH := "user://settings.cfg"
const INSTALL_DIR_NAMES := ["Seven Kingdoms 2 HD", "Seven Kingdoms 2", "Seven Kingdoms II", "7K2"]

var install_path := ""
var ready_ok := false
var last_error := ""

var _db := {}                 # table name -> Array of rows
var _pal_std := PackedByteArray()
var _pal_spr_buf := PackedByteArray()
var _pal_firm_buf := PackedByteArray()
var _pal_ter := PackedByteArray()
var _files := {}              # cache: path -> PackedByteArray
var _res_idx := {}            # cache: path -> Dictionary
var _tex_cache := {}          # key -> [Texture2D, Vector2 offset]

var sprites := {}             # sprite code -> info Dictionary
var _sframe: Array = []
var firm_builds := {}         # "CODE|GROUP" -> build Dictionary
var firm_groups := {}         # "CODE|RACE" -> group
var _fframe: Array = []
var _fbitmap: Array = []
var town_layouts: Array = []
var town_houses := {}         # race -> Array of house rows
var plant_bitmaps: Array = [] # Array of {tex, ofs, size}
var plant_variant_of_row := {} # PLANTBM1 record number -> index into plant_bitmaps
var firm_build_rows: Array = []  # FBUILD records in file order
var town_plants: Array = []   # small plant textures for town slots
var terrain_textures := {}    # "G"/"F"/"D"/"R" -> ImageTexture


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		var p: String = cfg.get_value("install", "path", "")
		if p != "" and is_valid_install(p):
			install_path = p
	if install_path == "":
		var env := OS.get_environment("SK2_PATH")
		if env != "" and is_valid_install(env):
			install_path = env
	if install_path == "":
		install_path = detect_install()


static func is_valid_install(p: String) -> bool:
	return SK2Files.find_file(p.path_join("Resource"), "STD.SET") != "" and DirAccess.dir_exists_absolute(p.path_join("Sprite"))


func detect_install() -> String:
	var bases: Array[String] = []
	for drive in ["C", "D", "E", "F", "G"]:
		bases.append(drive + ":/SteamLibrary/steamapps/common")
		bases.append(drive + ":/Steam/steamapps/common")
		bases.append(drive + ":/Program Files (x86)/Steam/steamapps/common")
		bases.append(drive + ":/Program Files/Steam/steamapps/common")
		bases.append(drive + ":/GOG Games")
		bases.append(drive + ":/Games")
	bases.append(OS.get_environment("HOME").path_join(".steam/steam/steamapps/common"))
	bases.append(OS.get_environment("HOME").path_join(".local/share/Steam/steamapps/common"))
	for b in bases:
		for n in INSTALL_DIR_NAMES:
			var p: String = b.path_join(n)
			if is_valid_install(p):
				return p
	return ""


func save_install_path(p: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("install", "path", p)
	cfg.save(SETTINGS_PATH)


## Load every table and palette. Returns "" on success or an error message.
func load_install(p: String = "") -> String:
	if p != "":
		install_path = p
	if install_path == "" or not is_valid_install(install_path):
		last_error = "Seven Kingdoms II installation not found. Set its folder on the start screen."
		return last_error
	var set_data := _file(_res_path("STD.SET"))
	var set_idx := SK2Files.parse_res_idx(set_data)
	if set_idx.is_empty():
		last_error = "Could not read Resource/STD.SET"
		return last_error
	for k in set_idx:
		_db[k] = SK2Files.parse_dbf(set_idx[k])
	_pal_std = SK2Files.palette_at(_file(_res_path("PAL_STD.RES")), 0)
	_pal_spr_buf = _file(_res_path("PAL_SPR.RES"))
	_pal_firm_buf = _file(_res_path("PAL_FIRM.RES"))
	_pal_ter = SK2Files.palette_at(_file(_res_path("PAL_TER1.RES")), 0)
	_build_sprites()
	_build_firms()
	_build_towns()
	_build_plants()
	_build_terrain()
	ready_ok = true
	save_install_path(install_path)
	return ""


func table(name: String) -> Array:
	return _db.get(name, [])


func _res_path(file_name: String) -> String:
	return SK2Files.find_file(install_path.path_join("Resource"), file_name)


func _file(path: String) -> PackedByteArray:
	if path == "":
		return PackedByteArray()
	if not _files.has(path):
		_files[path] = SK2Files.read_file(path)
	return _files[path]


func _idx(path: String) -> Dictionary:
	if not _res_idx.has(path):
		_res_idx[path] = SK2Files.parse_res_idx(_file(path))
	return _res_idx[path]


func _make_tex(img: Image) -> Texture2D:
	return ImageTexture.create_from_image(img) if img != null else null


# --------------------------------------------------------------- sprites ---

func _build_sprites() -> void:
	_sframe = table("SFRAME")
	var actions := table("SACTION")
	for row in table("SPRITE"):
		var code: String = row["NAME"]
		var info := {
			"code": code,
			"type": row["TYPE"],
			"speed": maxi(1, row["SPEED"].to_int()),
			"loc_w": maxi(1, row["LOC_WIDTH"].to_int()),
			"loc_h": maxi(1, row["LOC_HEIGHT"].to_int()),
			"turn_res": maxi(1, row["TURN_RES"].to_int()),
			"pal": _pal_std,
			"actions": {},
			"blend": not (row["REMAP_BMP"] in ["", "0", " "]),
			"rain_slow": row["RAIN_SLOW"].to_int(),
			"lightning": maxi(0, row["LIGHTN_DMG"].to_int()),
		}
		if row["PAL_NAME"] != "":
			var pal := SK2Files.imported_palette(_pal_spr_buf, row["PAL_PTR"])
			if pal.size() == 768:
				info["pal"] = pal
		var first: int = row["FIRSTACT"].to_int()
		var count: int = row["ACTCOUNT"].to_int()
		for r in range(first, first + count):
			if r < 1 or r > actions.size():
				continue
			var a: Dictionary = actions[r - 1]
			var act: String = a["ACTION"]
			if not info["actions"].has(act):
				info["actions"][act] = {}
			info["actions"][act][a["DIRID"].to_int()] = [a["FIRSTFRAME"].to_int(), a["FRAMECOUNT"].to_int()]
		# Stop frames default to the first movement frame, as in SpriteRes::load_sprite_info.
		if not info["actions"].has("S") and info["actions"].has("M"):
			var stop := {}
			for d in info["actions"]["M"]:
				stop[d] = [info["actions"]["M"][d][0], 1]
			info["actions"]["S"] = stop
		sprites[code] = info


var _blend_material: CanvasItemMaterial


## Material for sprites stored as blend bitmaps (effects, tornado, magic arrows).
func blend_material() -> CanvasItemMaterial:
	if _blend_material == null:
		_blend_material = CanvasItemMaterial.new()
		_blend_material.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	return _blend_material


func is_blend_sprite(code: String) -> bool:
	return sprites.get(code, {}).get("blend", false)


func has_sprite(code: String) -> bool:
	return sprites.has(code)


## Number of frames for an action in a direction (0 if absent).
func action_len(code: String, action: String, dir: int) -> int:
	var info: Dictionary = sprites.get(code, {})
	var acts: Dictionary = info.get("actions", {}).get(action, {})
	if acts.is_empty():
		return 0
	if not acts.has(dir):
		dir = acts.keys()[0]
	return acts[dir][1]


func has_action(code: String, action: String) -> bool:
	return sprites.get(code, {}).get("actions", {}).has(action)


## Returns [Texture2D, Vector2 offset] for a sprite frame, or [] if missing.
## `dir` is 0..7 (N, NE, E, SE, S, SW, W, NW).
func sprite_frame(code: String, action: String, dir: int, frame: int, color: Color) -> Array:
	var info: Dictionary = sprites.get(code, {})
	if info.is_empty():
		return []
	var acts: Dictionary = info["actions"].get(action, {})
	if acts.is_empty():
		return []
	if not acts.has(dir):
		dir = acts.keys()[0]
	var a: Array = acts[dir]
	if a[1] <= 0:
		return []
	var rec: int = a[0] + posmod(frame, a[1])
	var key := "S|%s|%d|%s" % [code, rec, color.to_html(false)]
	if _tex_cache.has(key):
		return _tex_cache[key]
	if rec < 1 or rec > _sframe.size():
		return []
	var fr: Dictionary = _sframe[rec - 1]
	var data := _file(SK2Files.find_file(install_path.path_join("Sprite"), code + ".SPR"))
	var pal := SK2Files.remap_palette(info["pal"], color)
	var img: Image
	if info.get("blend", false):
		img = SK2Files.decode_blend_bitmap(data, fr["BITMAPPTR"] + 4, pal)
	else:
		img = SK2Files.decode_bitmap(data, fr["BITMAPPTR"] + 4, pal, true)
	var result := []
	if img != null:
		var off := Vector2(fr["OFFSET_X"].to_int(), fr["OFFSET_Y"].to_int()) + Iso.bitmap_adjust(info["loc_w"], info["loc_h"])
		# The SW, W and NW frames are stored facing the other way (note their shadows):
		# the original draws them mirrored in place, at the stored offset
		# (Sprite::need_mirror, put_bitmap_*_hmirror at x1 = x + offset_x).
		if dir >= 5 and acts.size() == 8:
			img.flip_x()
		result = [_make_tex(img), off]
	_tex_cache[key] = result
	return result


# ----------------------------------------------------------------- firms ---

func _build_firms() -> void:
	_fframe = table("FFRAME")
	_fbitmap = table("FBITMAP")
	for g in table("FGROUP"):
		firm_groups[g["FIRM"] + "|" + g["RACE"]] = g["GROUP"].to_int()
	for b in table("FBUILD"):
		var build := {
			"firm": b["FIRM"],
			"group": b["GROUP"].to_int(),
			"name": b["NAME"],
			"use_first": b["USE_FIRST"] != "0",
			"res_name": b["RES_NAME"],
			"pal": _pal_std,
			"frames": [],
			"ground": b["GROUND_BMP"].to_int(),
			"underc": b["UNDERC_BMP"].to_int(),
			"underc_count": b["UNDERC_MAX"].to_int(),
			"idle": b["IDLE_BMP"].to_int(),
			"def": [b.get("STURDINESS", "0").to_int(), b.get("IS_WOOD", "0").to_int()],
			"loc_w": 3,
			"loc_h": 3,
		}
		for k in b:
			if String(k).begins_with("BUL") and not String(k).ends_with("ID"):
				build["bullet"] = String(b[k]).strip_edges()
		if b["PAL_NAME"] != "":
			var pal := SK2Files.imported_palette(_pal_firm_buf, b["PAL_PTR"])
			if pal.size() == 768:
				build["pal"] = pal
		var first: int = b["FIRSTFRAME"].to_int()
		for f in range(first, first + b["FRAMECOUNT"].to_int()):
			if f < 1 or f > _fframe.size():
				continue
			var fr: Dictionary = _fframe[f - 1]
			var bmps: Array = []
			var fb: int = fr["FIRSTBMP"].to_int()
			for k in range(fb, fb + fr["BMPCOUNT"].to_int()):
				bmps.append(k)
			build["frames"].append({"delay": maxi(1, fr["DELAY"].to_int()), "bitmaps": bmps})
		if build["underc"] == 0 and not build["frames"].is_empty() and not build["frames"][0]["bitmaps"].is_empty():
			build["underc"] = build["frames"][0]["bitmaps"][0]
			build["underc_count"] = 1
		var probe: int = build["frames"][0]["bitmaps"][0] if not build["frames"].is_empty() and not build["frames"][0]["bitmaps"].is_empty() else build["ground"]
		if probe >= 1 and probe <= _fbitmap.size():
			build["loc_w"] = maxi(1, _fbitmap[probe - 1]["LOC_WIDTH"].to_int())
			build["loc_h"] = maxi(1, _fbitmap[probe - 1]["LOC_HEIGHT"].to_int())
		build["row"] = firm_build_rows.size() + 1
		firm_build_rows.append(build)
		firm_builds[b["FIRM"] + "|" + str(build["group"])] = build


## The building variant a race uses for a firm type (falls back to group 1).
func firm_build(firm_code: String, race_code: String) -> Dictionary:
	var g: int = firm_groups.get(firm_code + "|" + race_code, 1)
	if firm_builds.has(firm_code + "|" + str(g)):
		return firm_builds[firm_code + "|" + str(g)]
	return firm_builds.get(firm_code + "|1", {})


## A building variant by its FBUILD record number (Firm::firm_build_id).
func firm_build_by_row(row: int) -> Dictionary:
	if row < 1 or row > firm_build_rows.size():
		return {}
	return firm_build_rows[row - 1]


func firm_bitmap_info(rec: int) -> Dictionary:
	if rec < 1 or rec > _fbitmap.size():
		return {}
	return _fbitmap[rec - 1]


## Returns [Texture2D, Vector2 offset, layer] for an FBITMAP record of a build.
func firm_bitmap(build: Dictionary, rec: int, color: Color) -> Array:
	var key := "F|%s|%d|%s" % [build.get("res_name", ""), rec, color.to_html(false)]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var row := firm_bitmap_info(rec)
	var result := []
	if not row.is_empty():
		var path := SK2Files.find_file(install_path.path_join("Firm"), build["res_name"] + ".FRM")
		var data := _file(path)
		var pal := SK2Files.remap_palette(build["pal"], color)
		var img := SK2Files.decode_bitmap(data, row["BITMAPPTR"] + 4, pal, true)
		if img != null:
			var adj := Iso.bitmap_adjust(maxi(1, row["LOC_WIDTH"].to_int()), maxi(1, row["LOC_HEIGHT"].to_int()))
			result = [_make_tex(img), Vector2(row["OFFSET_X"].to_int(), row["OFFSET_Y"].to_int()) + adj, row["LAYER"].to_int()]
	_tex_cache[key] = result
	return result


# ----------------------------------------------------------------- towns ---

func _build_towns() -> void:
	var slots := table("TOWNSLOT")
	for lay in table("TOWNLAY"):
		var l := {"code": lay["CODE"], "ground": lay["GROUNDNAME"], "slots": [], "buildings": lay["BUILDCOUNT"].to_int()}
		var first: int = lay["FIRSTSLOT"].to_int()
		for s in range(first, first + lay["SLOTCOUNT"].to_int()):
			if s >= 1 and s <= slots.size():
				var sr: Dictionary = slots[s - 1]
				l["slots"].append({"x": sr["BASE_X"].to_int(), "y": sr["BASE_Y"].to_int(), "type": sr["TYPE"], "code": sr["CODE"].to_int()})
		town_layouts.append(l)
	for h in table("TOWNBULD"):
		if not town_houses.has(h["RACE"]):
			town_houses[h["RACE"]] = []
		town_houses[h["RACE"]].append(h)


## [Texture2D, offset] for a town house of a race (code 1..3), or [].
func town_house(race_code: String, code: int) -> Array:
	var list: Array = town_houses.get(race_code, town_houses.get("NORMAN", []))
	var row: Dictionary = {}
	for h in list:
		if h["CODE"].to_int() == code:
			row = h
			break
	if row.is_empty():
		return []
	var key := "H|%s|%d" % [race_code, code]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var data := _file(_res_path("I_TOWN.RES"))
	var img := SK2Files.decode_bitmap(data, row["BITMAPPTR"] + 4, _pal_std, true)
	var lw := maxi(1, row["LOC_WIDTH"].to_int())
	var lh := maxi(1, row["LOC_HEIGHT"].to_int())
	var adj := Iso.bitmap_adjust(lw, lh)
	# [texture, offset, loc size]; TownBuild::draw anchors at slot - loc size/2
	var result := [] if img == null else [_make_tex(img), Vector2(row["OFFSET_X"].to_int(), row["OFFSET_Y"].to_int()) + adj, Vector2(lw, lh)]
	_tex_cache[key] = result
	return result


## A named picture from an indexed picture resource (e.g. town ground, flags).
func picture(res_file: String, name: String, compressed := true) -> Texture2D:
	var key := "P|%s|%s" % [res_file, name]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var idx := _idx(_res_path(res_file))
	var tex: Texture2D = null
	if idx.has(name.to_upper()):
		var img := SK2Files.decode_bitmap(idx[name.to_upper()], 0, _pal_std, compressed, 255)
		tex = _make_tex(img)
	_tex_cache[key] = tex
	return tex


## Picture from I_SPICT.RES recoloured for a nation (flags).
func spict(name: String, color: Color) -> Texture2D:
	var key := "SP|%s|%s" % [name, color.to_html(false)]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var idx := _idx(_res_path("I_SPICT.RES"))
	var tex: Texture2D = null
	if idx.has(name.to_upper()):
		tex = _make_tex(SK2Files.decode_bitmap(idx[name.to_upper()], 0, SK2Files.remap_palette(_pal_std, color), true))
	_tex_cache[key] = tex
	return tex


## Item picture lying on the map, from I_ITEMB.RES (ItemRes::item_bitmap).
func item_bitmap(name: String) -> Texture2D:
	var key := "IT|" + name
	if _tex_cache.has(key):
		return _tex_cache[key]
	var idx := _idx(_res_path("I_ITEMB.RES"))
	var tex: Texture2D = null
	if idx.has(name.to_upper()):
		var img := SK2Files.decode_bitmap(idx[name.to_upper()], 0, _pal_std, true)
		if img == null:
			img = SK2Files.decode_bitmap(idx[name.to_upper()], 0, _pal_std, false, 255)
		tex = _make_tex(img)
	_tex_cache[key] = tex
	return tex


# ---------------------------------------------------------------- plants ---

func _build_plants() -> void:
	var data := _file(_res_path("I_PLANT1.RES"))
	var rows := SK2Files.parse_dbf(_file(_res_path("PLANTBM1.RES")))
	for ri in rows.size():
		var r: Dictionary = rows[ri]
		var img := SK2Files.decode_bitmap(data, r["BITMAPPTR"] + 4, _pal_std, true)
		# Young plants decorate town slots; the larger growth stages are map trees.
		if img != null and r["SIZE"].to_int() <= 2:
			town_plants.append(_make_tex(img))
		if r["SIZE"].to_int() < 2:
			plant_variant_of_row[ri + 1] = maxi(0, plant_bitmaps.size() - 1)
			continue
		if img != null:
			plant_variant_of_row[ri + 1] = plant_bitmaps.size()
			plant_bitmaps.append({"tex": _make_tex(img), "ofs": Vector2(r["OFFSET_X"].to_int(), r["OFFSET_Y"].to_int()) + Iso.bitmap_adjust(1, 1), "plant": r["PLANT"]})


# --------------------------------------------------------------- terrain ---

## Builds one seamless 512x512 texture per terrain type from the 16x16 grid of
## 32x32 texture cells in TERTEX1/I_TERX1 (cell id = (y&15)<<4 | (x&15)).
func _build_terrain() -> void:
	var data := _file(_res_path("I_TERX1.RES"))
	var rows := SK2Files.parse_dbf(_file(_res_path("TERTEX1.RES")))
	var imgs := {}
	for r in rows:
		var t: String = r["TERA_TYPE"]
		if not imgs.has(t):
			imgs[t] = Image.create(512, 512, false, Image.FORMAT_RGBA8)
		var cell: int = r["CELL_ID"].hex_to_int()
		var tile := SK2Files.decode_bitmap(data, r["BITMAPPTR"] + 4, _pal_ter, false)
		if tile == null:
			continue
		imgs[t].blit_rect(tile, Rect2i(0, 0, 32, 32), Vector2i((cell & 15) * 32, (cell >> 4) * 32))
	for t in imgs:
		terrain_textures[t] = ImageTexture.create_from_image(imgs[t])


# ----------------------------------------------------------------- icons ---

## Unit portrait from one of the I_UNIT?I.RES files (imported resources).
func unit_icon(res_file: String, ptr: int) -> Texture2D:
	var key := "I|%s|%d" % [res_file, ptr]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var data := _file(_res_path(res_file))
	var img := SK2Files.decode_bitmap(data, ptr + 4, _pal_std, true)
	if img == null or img.get_width() < 4:
		img = SK2Files.decode_bitmap(data, ptr + 4, _pal_std, false, 255)
	var tex := _make_tex(img)
	_tex_cache[key] = tex
	return tex


## Raw-material site graphic from I_RAW.RES.
func raw_icon(ptr: int) -> Array:
	var key := "R|%d" % ptr
	if _tex_cache.has(key):
		return _tex_cache[key]
	var img := SK2Files.decode_bitmap(_file(_res_path("I_RAW.RES")), ptr + 4, _pal_std, true)
	var result := [] if img == null else [_make_tex(img)]
	_tex_cache[key] = result
	return result


# ----------------------------------------------------------- images/audio ---

## A JPEG from the install's Image folder (race portraits, victory screens).
func image(file_name: String) -> Texture2D:
	var key := "J|" + file_name
	if _tex_cache.has(key):
		return _tex_cache[key]
	var path := SK2Files.find_file(install_path.path_join("Image"), file_name)
	var tex: Texture2D = null
	if path != "":
		var img := Image.new()
		if img.load_jpg_from_buffer(SK2Files.read_file(path)) == OK:
			tex = ImageTexture.create_from_image(img)
	_tex_cache[key] = tex
	return tex


func music_files() -> Array[String]:
	var out: Array[String] = []
	var dir := install_path.path_join("Music")
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.to_upper().begins_with("BKMUSIC") and f.to_upper().ends_with(".WAV"):
			out.append(dir.path_join(f))
	out.sort()
	return out


## Minimal RIFF/WAVE PCM reader producing an AudioStreamWAV.
static func load_wav(path: String) -> AudioStreamWAV:
	return wav_from_bytes(SK2Files.read_file(path))


static func wav_from_bytes(data: PackedByteArray) -> AudioStreamWAV:
	if data.size() < 44 or data.slice(0, 4).get_string_from_ascii() != "RIFF":
		return null
	var p := 12
	var channels := 2
	var rate := 22050
	var bits := 16
	var pcm := PackedByteArray()
	while p + 8 <= data.size():
		var id := data.slice(p, p + 4).get_string_from_ascii()
		var size := data.decode_u32(p + 4)
		if id == "fmt ":
			channels = data.decode_u16(p + 10)
			rate = data.decode_u32(p + 12)
			bits = data.decode_u16(p + 22)
		elif id == "data":
			pcm = data.slice(p + 8, mini(p + 8 + size, data.size()))
			break
		p += 8 + size + (size & 1)
	if pcm.is_empty():
		return null
	var s := AudioStreamWAV.new()
	if bits == 8:
		for i in pcm.size():
			pcm[i] = (pcm[i] + 128) & 0xFF   # unsigned -> signed
		s.format = AudioStreamWAV.FORMAT_8_BITS
	else:
		s.format = AudioStreamWAV.FORMAT_16_BITS
	s.stereo = channels == 2
	s.mix_rate = rate
	s.data = pcm
	return s


# ---------------------------------------------------------- sound effects ---

var _sound_table := {}        # "S|NO_INF|A1" -> [wave names]
var _sound_cache := {}


func sound_files(kind: String, code: String, action: String) -> Array:
	if _sound_table.is_empty():
		for r in table("SOUNDRES"):
			var key: String = "%s|%s|%s" % [r["SUBJ_TYPE"], r["SUBJ_CODE"], r["ACTION"]]
			if not _sound_table.has(key):
				_sound_table[key] = []
			_sound_table[key].append(r["FILENAME"])
	return _sound_table.get("%s|%s|%s" % [kind, code, action], [])


## A WAV from the install's Sound folder (rain, thunder, wind ...).
func ambient_sound(file_name: String) -> AudioStreamWAV:
	var key := "AMB|" + file_name
	if _sound_cache.has(key):
		return _sound_cache[key]
	var path := SK2Files.find_file(install_path.path_join("Sound"), file_name)
	var s: AudioStreamWAV = load_wav(path) if path != "" else null
	_sound_cache[key] = s
	return s


## A wave from A_WAVE1.RES (battle) or A_WAVE2.RES (voices, interface).
func sound(name: String) -> AudioStreamWAV:
	name = name.to_upper()
	if _sound_cache.has(name):
		return _sound_cache[name]
	var s: AudioStreamWAV = null
	for f in ["A_WAVE1.RES", "A_WAVE2.RES"]:
		var idx := _idx(_res_path(f))
		if idx.has(name):
			s = wav_from_bytes(idx[name])
			break
	_sound_cache[name] = s
	return s


# ------------------------------------------------------ destruction effects ---

var die_parts := {}           # ani part -> Array of FDBITMAP record numbers, in frame order
var _die_pal := PackedByteArray()


## Explosion (1), small fire (2), large fire (3) and rubble (4: 5x5, 5: 6x6, 6: 3x3)
## from FDBUILD/FDFRAME/FDBITMAP and Firm/FIRM_DIE.FRM (ofirmdie.cpp).
func _build_die() -> void:
	var frames := table("FDFRAME")
	var bmps := table("FDBITMAP")
	for fr in frames:
		if fr["FIRM"] != "BASE" or fr["GROUP"].to_int() != 1:
			continue
		var first: int = fr["FIRSTBMP"].to_int()
		for k in range(first, first + fr["BMPCOUNT"].to_int()):
			if k < 1 or k > bmps.size():
				continue
			var part: int = bmps[k - 1]["ANI_PART"].to_int()
			if not die_parts.has(part):
				die_parts[part] = []
			die_parts[part].append(k)
	_die_pal = SK2Files.imported_palette(_file(_res_path("PALFIRMD.RES")), 0)
	if _die_pal.size() != 768:
		_die_pal = _pal_std


func die_bitmap(rec: int) -> Array:
	var key := "D|%d" % rec
	if _tex_cache.has(key):
		return _tex_cache[key]
	if die_parts.is_empty():
		_build_die()
	var bmps := table("FDBITMAP")
	var result := []
	if rec >= 1 and rec <= bmps.size():
		var row: Dictionary = bmps[rec - 1]
		var data := _file(SK2Files.find_file(install_path.path_join("Firm"), "FIRM_DIE.FRM"))
		var img := SK2Files.decode_bitmap(data, row["BITMAPPTR"] + 4, _die_pal, true)
		if img != null:
			var lw := maxi(1, row["LOC_WIDTH"].to_int())
			var lh := maxi(1, row["LOC_HEIGHT"].to_int())
			result = [_make_tex(img), Vector2(row["OFFSET_X"].to_int(), row["OFFSET_Y"].to_int()) + Iso.bitmap_adjust(lw, lh), Vector2i(lw, lh)]
	_tex_cache[key] = result
	return result


func die_part(part: int) -> Array:
	if die_parts.is_empty():
		_build_die()
	return die_parts.get(part, [])


# --------------------------------------------------- rocks, hills and lakes ---

var rock_types: Array = []    # {id, type, w, h, t1, t2, tex, ofs}


## ROCK1/ROCKBMP1/I_ROCK1: mountains (H*, type R), boulders (R*) and lakes (P*).
func load_rocks() -> Array:
	if not rock_types.is_empty():
		return rock_types
	var infos := SK2Files.parse_dbf(_file(_res_path("ROCK1.RES")))
	var bmps := SK2Files.parse_dbf(_file(_res_path("ROCKBMP1.RES")))
	var data := _file(_res_path("I_ROCK1.RES"))
	var codes := {"G": 0, "F": 1, "D": 2}
	for ri in infos.size():
		var r: Dictionary = infos[ri]
		var first: int = r["FIRST_ANIM"].to_int()
		if first < 1 or first > bmps.size():
			continue
		var b: Dictionary = bmps[first - 1]
		var img := SK2Files.decode_bitmap(data, b["BITMAPPTR"] + 4, _pal_std, true)
		if img == null:
			continue
		var w: int = maxi(1, r["LOC_WIDTH"].to_int())
		var h: int = maxi(1, r["LOC_HEIGHT"].to_int())
		rock_types.append({
			"id": r["ROCKID"], "row": ri + 1, "type": r["TYPE"], "w": w, "h": h,
			"t1": codes.get(r["TERRAIN_1"], 0), "t2": codes.get(r["TERRAIN_2"], 2),
			"tex": _make_tex(img),
			"ofs": Vector2(b["OFFSET_X"].to_int(), b["OFFSET_Y"].to_int()) + Iso.bitmap_adjust(w, h),
		})
	return rock_types


# ------------------------------------------------------------- town walls ---

var _wall_race := {}          # race -> [fence wall, basic wall, advanced wall] codes
var _walls := {}              # wall code -> {max_frame, bitmaps: {"frame|mode": row}}


func _load_walls() -> void:
	if not _wall_race.is_empty():
		return
	for r in table("TWALLRAC"):
		_wall_race[r["RACE"]] = [r["FENCE"], r["BAS_WALL"], r["ADV_WALL"]]
	var bmps := table("TWALLBMP")
	for w in table("TWALL"):
		var info := {"max_frame": maxi(1, w["MAX_FRAME"].to_int()), "bitmaps": {}}
		var first: int = w["FIRST_REC"].to_int()
		for k in range(first, first + w["REC_COUNT"].to_int()):
			if k >= 1 and k <= bmps.size():
				var b: Dictionary = bmps[k - 1]
				info["bitmaps"]["%d|%s" % [b["FRAME"].to_int(), b["MODE"]]] = b
		_walls[w["WALL"]] = info


## [texture, offset] of a town wall half ("B" back, "F" front) for a race and level
## (0 fence, 1 basic, 2 advanced), picking the damage frame like TownWallRes::search.
func town_wall(race: String, level: int, hp: float, full_hp: float, mode: String) -> Array:
	_load_walls()
	var codes: Array = _wall_race.get(race, _wall_race.get("NORMAN", []))
	if codes.is_empty():
		return []
	var info: Dictionary = _walls.get(codes[clampi(level, 0, 2)], {})
	if info.is_empty():
		return []
	var mf: int = info["max_frame"]
	var frame := mini(mf, 1 + int(hp * mf / maxf(1.0, full_hp)))
	var row: Dictionary = info["bitmaps"].get("%d|%s" % [frame, mode], {})
	if row.is_empty():
		return []
	var key := "W|%s|%d|%s" % [codes[clampi(level, 0, 2)], frame, mode]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var img := SK2Files.decode_bitmap(_file(_res_path("I_TWALL.RES")), row["BITMAPPTR"] + 4, _pal_std, true)
	var lw := maxi(1, row["LOC_WIDTH"].to_int())
	var lh := maxi(1, row["LOC_HEIGHT"].to_int())
	var result := [] if img == null else [_make_tex(img), Vector2(row["OFFSET_X"].to_int(), row["OFFSET_Y"].to_int()) + Iso.bitmap_adjust(lw, lh)]
	_tex_cache[key] = result
	return result
