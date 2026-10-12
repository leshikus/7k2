class_name SK2Files
## Readers for the original Seven Kingdoms II data formats.
## Formats follow the GPL 7k2 source (ores.cpp, oresx.cpp, odb.cpp, imgfun/ib_trd.cpp).

const SHADOW_CODE := 0x00
const MIN_EFFECT_CODE := 0xEF
const MANY_TRANSPARENT_CODE := 0xF8
const FIRST_REMAP_KEY := 0xE0
const REMAP_KEY_COUNT := 8


static func read_file(path: String) -> PackedByteArray:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	return f.get_buffer(f.get_length())


## Case-insensitive lookup of a file inside a directory (the install mixes upper/lower case).
static func find_file(dir_path: String, file_name: String) -> String:
	var direct := dir_path.path_join(file_name)
	if FileAccess.file_exists(direct):
		return direct
	var d := DirAccess.open(dir_path)
	if d == null:
		return ""
	var want := file_name.to_upper()
	for f in d.get_files():
		if f.to_upper() == want:
			return dir_path.path_join(f)
	return ""


static func _cstr(data: PackedByteArray, start: int, length: int) -> String:
	var s := ""
	for k in length:
		var b := data[start + k]
		if b == 0:
			break
		s += char(b)
	return s.strip_edges()


## ResourceIdx file: <u16 count> then (count+1) x {char name[9]; u32 offset}.
## Returns name (upper case) -> PackedByteArray of the record.
static func parse_res_idx(data: PackedByteArray) -> Dictionary:
	var out := {}
	if data.size() < 2:
		return out
	var n := data.decode_u16(0)
	var names: Array[String] = []
	var ptrs: Array[int] = []
	for i in n + 1:
		var o := 2 + i * 13
		names.append(_cstr(data, o, 9).to_upper())
		ptrs.append(data.decode_u32(o + 9))
	for i in n:
		out[names[i]] = data.slice(ptrs[i], ptrs[i + 1])
	return out


## dBase III table. Returns Array of Dictionary(field -> String or int).
## Four-byte fields whose name ends in "PTR" are binary little-endian offsets.
static func parse_dbf(buf: PackedByteArray) -> Array:
	var rows: Array = []
	if buf.size() < 32:
		return rows
	var last_rec := buf.decode_u32(4)
	var data_off := buf.decode_u16(8)
	var rec_size := buf.decode_u16(10)
	var fields: Array = []
	var p := 32
	while p < buf.size() and buf[p] != 0x0D:
		var fname := _cstr(buf, p, 11)
		var ftype := char(buf[p + 11])
		var flen: int = buf[p + 16]
		if ftype == "C":
			flen = buf.decode_u16(p + 16)
		fields.append([fname, flen, fname.ends_with("PTR") and flen == 4])
		p += 32
	for r in last_rec:
		var q := data_off + 1 + r * rec_size
		if q + rec_size > buf.size():
			break
		var row := {}
		for f in fields:
			if f[2]:
				row[f[0]] = buf.decode_u32(q)
			else:
				row[f[0]] = _cstr(buf, q, f[1])
			q += f[1]
		rows.append(row)
	return rows


## Palette stored as 8-byte header + 256 RGB triples, at `off` inside `buf`.
## Shorter palettes (e.g. PAL_TER1 with 224 entries) are padded with black.
static func palette_at(buf: PackedByteArray, off: int) -> PackedByteArray:
	if off < 0 or off + 8 + 3 > buf.size():
		return PackedByteArray()
	var p := buf.slice(off + 8, mini(off + 8 + 768, buf.size()))
	p.resize(768)
	return p


## Palette inside an "imported" resource (u32 size prefix before each record).
static func imported_palette(buf: PackedByteArray, off: int) -> PackedByteArray:
	return palette_at(buf, off + 4)


static func bitmap_size(data: PackedByteArray, off: int) -> Vector2i:
	if off < 0 or off + 4 > data.size():
		return Vector2i.ZERO
	return Vector2i(data.decode_u16(off), data.decode_u16(off + 2))


## Decode an 8-bit bitmap ({u16 w, u16 h, pixels}) to an RGBA image.
## Compressed bitmaps use 0xF8 <n> / 0xF9-0xFF run-length transparency and
## 0xEF-0xF7 as shadow effect codes.
static func decode_bitmap(data: PackedByteArray, off: int, pal: PackedByteArray, compressed := true, transparent_index := -1) -> Image:
	var sz := bitmap_size(data, off)
	var w := sz.x
	var h := sz.y
	if w <= 0 or h <= 0 or w > 4096 or h > 4096 or pal.size() < 768:
		return null
	var n := w * h
	var out := PackedByteArray()
	out.resize(n * 4)
	out.fill(0)
	var i := off + 4
	var size := data.size()
	var px := 0
	if compressed:
		while px < n and i < size:
			var c: int = data[i]
			i += 1
			if c == SHADOW_CODE:
				out[px * 4 + 3] = 100  # shadow: translucent black
				px += 1
			elif c < MIN_EFFECT_CODE:
				var q := px * 4
				var pp := c * 3
				out[q] = pal[pp]
				out[q + 1] = pal[pp + 1]
				out[q + 2] = pal[pp + 2]
				out[q + 3] = 255
				px += 1
			elif c < MANY_TRANSPARENT_CODE:
				out[px * 4 + 3] = 96  # shadow / tint effect: draw as translucent black
				px += 1
			elif c == MANY_TRANSPARENT_CODE:
				px += data[i] if i < size else n
				i += 1
			else:
				px += 256 - c
	else:
		for k in n:
			if i + k >= size:
				break
			var c: int = data[i + k]
			if c == transparent_index:
				continue
			var q := k * 4
			var pp := c * 3
			out[q] = pal[pp]
			out[q + 1] = pal[pp + 1]
			out[q + 2] = pal[pp + 2]
			out[q + 3] = 255
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, out)


## Blend bitmap (IMGbltBlendRemap): per pixel a colour index and a "log alpha"
## shift applied to the background. Returned premultiplied: draw with a
## premultiplied-alpha material so the result is colour + background * 2^-shift.
static func decode_blend_bitmap(data: PackedByteArray, off: int, pal: PackedByteArray) -> Image:
	var sz := bitmap_size(data, off)
	var w := sz.x
	var h := sz.y
	if w <= 0 or h <= 0 or w > 4096 or h > 4096 or off + 4 + w * h * 2 > data.size():
		return null
	var out := PackedByteArray()
	out.resize(w * h * 4)
	var i := off + 4
	for k in w * h:
		var idx: int = data[i]
		var la: int = data[i + 1]
		i += 2
		var q := k * 4
		var pp := idx * 3
		out[q] = pal[pp]
		out[q + 1] = pal[pp + 1]
		out[q + 2] = pal[pp + 2]
		out[q + 3] = clampi(int(255.0 * (1.0 - 1.0 / float(1 << mini(la, 8)))), 0, 255)
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, out)


## Copy of `pal` with the eight nation-colour keys (0xE0-0xE7) recoloured.
## Each key keeps its original brightness so shading in the art is preserved.
static func remap_palette(pal: PackedByteArray, nation_color: Color) -> PackedByteArray:
	var p := pal.duplicate()
	for k in REMAP_KEY_COUNT:
		var idx := (FIRST_REMAP_KEY + k) * 3
		var lum := (0.299 * pal[idx] + 0.587 * pal[idx + 1] + 0.114 * pal[idx + 2]) / 255.0
		var f := 0.35 + lum * 1.15
		p[idx] = clampi(int(nation_color.r * 255.0 * f), 0, 255)
		p[idx + 1] = clampi(int(nation_color.g * 255.0 * f), 0, 255)
		p[idx + 2] = clampi(int(nation_color.b * 255.0 * f), 0, 255)
	return p
