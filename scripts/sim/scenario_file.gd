class_name ScenarioFile
extends RefCounted
## Reader for the original game's premade scenarios (Scenario/Premade/*.scn).
##
## A scenario is an ordinary 7k2 saved game (ogfile*.cpp). Every section starts
## with a book mark (0x1000+n); records written with File::file_write() carry a
## u16 size prefix, and the object records are written field by field by the
## FileIOVisitor templates in ogfile3.cpp, so their offsets below are the packed
## sums of those field lists. Only what this port can use is extracted: the
## terrain (regenerated from the saved map seed), plants, rocks, raw sites,
## kingdoms, towns, buildings with their garrisons, and units.

const BOOK_MARK := 0x1000
const UNIT_REC := 233
const FIRM_REC := 296
const TOWN_REC := 402
const NATION_REC := 3180
const NATION_ARRAY_REC := 859
const DYN_ARRAY_REC := 29
const SOLDIER_SIZE := 45

## Location flags (olocate.h).
const LOCATE_BLOCK_MASK := 0xf00
const LOCATE_IS_PLANT := 0x200

## Firm ids (ofirmid.h) -> rows of the FIRM table; the codes come from the table.
const FIRM_CAMP_LAYOUT := [2, 3, 12]   # FirmFort, FirmCamp, FirmLair keep FirmCamp's soldier array

var data := PackedByteArray()
var w := 0
var h := 0
var map_seed := 0
var planes := {}        # name -> PackedByteArray (w*h)
var nations: Array = []
var towns: Array = []
var firms: Array = []
var units: Array = []
var sites: Array = []
var rocks: Array = []
var dirts: Array = []
## Scenario goals from the Game record: {require_all, win: [...], lose: [...]},
## each condition {id, p1, p2, years, player_only, text, result} (oend_con.h).
var goals := {}
var error := ""
var _p := 0


# ------------------------------------------------------------- listing ---

## Scenarios to offer: the install's premade ones, then the community collection
## in the project's scenario/ folder. [{path, name, text, difficulty, source}]
static func list_premade() -> Array:
	var out: Array = []
	if Assets.install_path != "":
		out.append_array(_list_dir(Assets.install_path.path_join("Scenario").path_join("Premade"), "original"))
	var extra := _list_dir(ProjectSettings.globalize_path("res://scenario"), "community")
	extra.sort_custom(func(a, b): return a["name"].to_lower() < b["name"].to_lower())
	out.sort_custom(func(a, b): return a["name"] < b["name"])
	out.append_array(extra)
	return out


static func _list_dir(dir_path: String, source: String) -> Array:
	var out: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	var files := dir.get_files()
	for f in files:
		if f.get_extension().to_lower() != "scn":
			continue
		var info := {"path": dir_path.path_join(f), "name": f.get_basename().capitalize(), "text": "", "difficulty": 0, "source": source}
		var base := f.get_basename()
		for g in files:
			if g.get_extension().to_lower() == "sct" and g.get_basename().to_lower() == base.to_lower():
				var txt := FileAccess.get_file_as_bytes(dir_path.path_join(g)).get_string_from_ascii()
				var lines := txt.split("
")
				if lines.size() > 0 and lines[0].strip_edges() != "":
					info["name"] = lines[0].strip_edges().trim_suffix(" Scenario")
				var body: Array = []
				var in_body := false
				for l in lines:
					var s: String = l.strip_edges()
					if s.begins_with("Difficulty"):
						info["difficulty"] = s.get_slice(":", 1).strip_edges().to_int()
					elif s.begins_with("---"):
						in_body = true
					elif in_body and s != "":
						body.append(s)
				info["text"] = " ".join(body)
		out.append(info)
	return out


# ------------------------------------------------------------- parsing ---

func load_file(path: String) -> bool:
	data = FileAccess.get_file_as_bytes(path)
	if data.is_empty():
		error = "cannot read " + path
		return false
	_read_goals()
	if not _read_world():
		return false
	var steps := [_read_units, _read_sites, _read_towns, _read_nations, _read_firms, _read_rocks]
	for s in steps:
		if not s.call():
			return false
	return true


func _s8(p: int) -> int: return data.decode_s8(p)
func _u8(p: int) -> int: return data.decode_u8(p)
func _s16(p: int) -> int: return data.decode_s16(p)
func _u16(p: int) -> int: return data.decode_u16(p)
func _s32(p: int) -> int: return data.decode_s32(p)
func _f32(p: int) -> float: return data.decode_float(p)


func _short() -> int:
	var v := _s16(_p)
	_p += 2
	return v


## Reads one size-prefixed record and returns its start offset (skipping it).
func _record(expect := -1) -> int:
	var n := _u16(_p)
	if expect >= 0 and n != expect:
		push_error("scenario: record size %d, expected %d at %d" % [n, expect, _p])
	var start := _p + 2
	_p = start + n
	return start


func _empty_room() -> void:
	if _short() > 0:
		_record()


## Position just after book mark `mark` at or after `from` whose following
## bytes pass `check`.
func _find(mark: int, from: int, check: Callable) -> int:
	var b := BOOK_MARK + mark
	var i := from
	var end := data.size() - 8
	while i < end:
		if _u16(i) == b and check.call(i + 2):
			return i + 2
		i += 1
	return -1


func _ends_section(p: int, mark: int) -> bool:
	if p + 4 > data.size():
		return false
	var c := _s16(p)
	var q := p + 2
	if c > 0:
		q += 2 + _u16(p + 2)
	return q + 2 <= data.size() and _u16(q) == BOOK_MARK + mark


func _read_world() -> bool:
	var at := _find(110, 0, func(p): return _s16(p) >= 50 and _s16(p) <= 400 and _s32(p + 8) == 1 and _s32(p + 12) == 0)
	if at < 0:
		error = "no map in file"
		return false
	w = _s16(at)
	h = _s16(at + 2)
	map_seed = _s32(at + 4)
	_p = at + 16
	# World::write_file: run-length compressed byte planes of the location matrix
	for spec in [["flag_lo", 0xff], ["flag_hi", 0xff], ["road_lo", 0xff], ["road_hi", 0xff], ["cargo_lo", 0xff],
			["cargo_hi", 0xff], ["air_lo", 0xff], ["air_hi", 0xff], ["extra", 0xff], ["fire", 0x80], ["flam", 0x80],
			["power", 0x80], ["region", 0xff], ["visit", 0xff]]:
		var ln := _s32(_p)
		_p += 6       # length, then the record's own u16 size
		planes[spec[0]] = _rle_expand(_p, spec[1], w * h)
		_p += ln
	return true


## Game::write_file writes the Game object raw (ogame.h, packed): five flags, the
## win and lose condition counts, then 8 + 8 EndCondition records of 224 bytes.
const END_CONDITION_SIZE := 224

func _read_goals() -> void:
	var at := _find(101, 0, func(q): return _u16(q) > 3700 and _s32(q + 7) >= 0 and _s32(q + 7) <= 8 		and _s32(q + 11) >= 0 and _s32(q + 11) <= 8)
	if at < 0:
		return
	var g := at + 2
	var wc := _s32(g + 5)
	var lc := _s32(g + 9)
	goals = {"require_all": _u8(g + 4) != 0, "win": [], "lose": []}
	for k in 16:
		if (k < 8 and k >= wc) or (k >= 8 and k - 8 >= lc):
			continue
		var c := g + 13 + k * END_CONDITION_SIZE
		goals["win" if k < 8 else "lose"].append({
			"id": _s32(c), "p1": _s32(c + 4), "p2": _s32(c + 8), "years": _s32(c + 12),
			"player_only": _u8(c + 16) != 0, "text": _latin1(c + 17, 101), "result": _latin1(c + 118, 101)})


func _latin1(p: int, n: int) -> String:
	var s := ""
	for i in n:
		var b := _u8(p + i)
		if b == 0:
			break
		s += String.chr(b)
	return s


func _rle_expand(p: int, key: int, n: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(n)
	var o := 0
	while o < n:
		var b := data[p]
		if b == key:
			var cnt := data[p + 1]
			if cnt == 0:
				break
			var v := data[p + 2]
			for k in cnt:
				if o < n:
					out[o] = v
					o += 1
			p += 3
		else:
			out[o] = b
			o += 1
			p += 1
	return out


func loc_flag(x: int, y: int) -> int:
	var i := y * w + x
	return planes["flag_lo"][i] | (planes["flag_hi"][i] << 8)


func _read_units() -> bool:
	var at := _find(201, _p, _unit_array_check)
	if at < 0:
		error = "no unit array"
		return false
	_p = at
	var cnt := _short()
	_p += 4
	for i in range(1, cnt + 1):
		var uid := _short()
		if uid == 0:
			continue
		var r := _record(UNIT_REC)
		var u := {
			"recno": i, "unit_id": _s16(r + 60), "nation": _s8(r + 11), "race": _s8(r + 12),
			"hp": _f32(r + 21), "x": _s16(r + 44), "y": _s16(r + 46), "rank": _s8(r + 109),
			"hero_id": _s16(r + 112), "royal": _s8(r + 114), "loyalty": _s8(r + 119), "spy": _s16(r + 121),
			"combat": _f32(r + 130), "skill": _f32(r + 134), "mode": _s8(r + 138), "mode_para": _s16(r + 139),
		}
		if _s32(r + 92) != 0 and _s16(r + 96) > 0:
			_record()      # PathResult array
		if _s32(r + 145) != 0:
			_record()      # TeamInfo
		# derived class data (caravans, monsters, gods ...) is one more record
		if i < cnt:
			if not (_u16(_p) == 0 or _u16(_p + 2) == UNIT_REC):
				_record()
		elif not _ends_section(_p, 202):
			_record()
		units.append(u)
	_empty_room()
	return true


func _unit_array_check(p: int) -> bool:
	var cnt := _s16(p)
	if cnt < 0 or cnt > 5000:
		return false
	var q := p + 6
	while q < data.size() - 4 and _s16(q) == 0:
		q += 2
	return q < data.size() - 4 and _u16(q + 2) == UNIT_REC


func _read_sites() -> bool:
	var at := _find(203, _p, func(p): return _u16(p + 12) == DYN_ARRAY_REC)
	if at < 0:
		error = "no site array"
		return false
	_p = at + 12
	var hdr := _record(DYN_ARRAY_REC)
	var last := _s32(hdr + 12)
	var ele := _s32(hdr + 16)
	if last > 0:
		var b := _record()
		for k in last:
			var e := b + k * ele
			if _s16(e) == 0:
				continue
			# Site: recno, type, object_id, reserve_qty, has_mine, map_x_loc, map_y_loc (osite.h)
			sites.append({"recno": _s16(e), "type": _s8(e + 2), "object_id": _s16(e + 3), "qty": _s32(e + 5),
				"has_mine": _s8(e + 9), "x": _s16(e + 10), "y": _s16(e + 12)})
	return true


func _read_towns() -> bool:
	var at := _find(204, _p, func(p): return _s16(p) >= 0 and _s16(p) < 1000)
	if at < 0:
		error = "no town array"
		return false
	_p = at
	var cnt := _short()
	_short()
	_record()        # race_wander_pop_array
	_short()
	for i in range(1, cnt + 1):
		if _short() == 0:
			continue
		var r := _record(TOWN_REC)
		var res: Array = []
		for k in 7:
			res.append(_f32(r + 140 + k * 4))
		towns.append({
			"recno": _s16(r + 64), "nation": _s8(r + 11), "race": _s8(r + 12),
			"x": _s16(r + 35), "y": _s16(r + 37), "name_id": _s16(r + 66), "population": _s16(r + 126),
			"loyalty": _f32(r + 132), "resistance": res, "wall": _s8(r + 192), "target_wall": _s8(r + 193),
		})
	_empty_room()
	return true


func _read_nations() -> bool:
	if _u16(_p) != BOOK_MARK + 205:
		error = "town array misread"
		return false
	_p += 2
	_record(NATION_ARRAY_REC)
	var count := _short()
	var start := _p
	var fpos := _find(206, start, _firm_array_check)
	if fpos < 0:
		error = "no firm array"
		return false
	# each nation record is followed by variable-length AI data: find the
	# headers ([class id][u16 record size][record with the nation recno])
	var j := start
	var last := 0
	while j < fpos - 8:
		if _u16(j + 2) == NATION_REC and _s16(j) >= 1 and _s16(j) <= 10:
			var r := j + 4
			var rn := _s16(r + 4)
			if rn > last and rn <= count:
				var name_bytes := data.slice(r + 16, r + 16 + 51)
				var z := name_bytes.find(0)
				if z >= 0:
					name_bytes = name_bytes.slice(0, z)
				var rel: Array = []
				for k in 7:
					rel.append(_s8(r + 2149 + k))
				nations.append({
					"recno": rn, "type": _s8(r + 6), "race": _s8(r + 9), "color": _s8(r + 10),
					"king": _s16(r + 12), "name": name_bytes.get_string_from_ascii(), "cash": _f32(r + 117),
					"food": _f32(r + 121), "reputation": _f32(r + 129), "live_points": _f32(r + 133),
					"relations": rel, "class": _s16(j),
				})
				last = rn
				j = r + NATION_REC
				continue
		j += 1
	_p = fpos
	return true


func _firm_array_check(p: int) -> bool:
	var cnt := _s16(p)
	if cnt < 0 or cnt > 3000:
		return false
	var q := p + 6
	while q < data.size() - 4 and _s16(q) == 0:
		q += 2
	return q < data.size() - 4 and _u16(q + 2) == FIRM_REC


func _read_firms() -> bool:
	var cnt := _short()
	_p += 4
	for i in range(1, cnt + 1):
		var fid := _short()
		if fid == 0:
			continue
		var r := _record(FIRM_REC)
		var f := {
			"recno": _s16(r + 64), "firm_id": _s8(r + 66), "build_id": _s16(r + 67), "nation": _s8(r + 11),
			"race": _s8(r + 12), "x": _s16(r + 35), "y": _s16(r + 37), "x2": _s16(r + 39), "y2": _s16(r + 41),
			"hp": _f32(r + 21), "max_hp": _f32(r + 29), "under_construction": _s8(r + 59) != 0, "soldiers": [],
		}
		var der := -1
		var der_len := 0
		if i < cnt:
			if not (_u16(_p) == 0 or _u16(_p + 2) == FIRM_REC):
				der_len = _u16(_p)
				der = _record()
		elif not _ends_section(_p, 207):
			der_len = _u16(_p)
			der = _record()
		if der >= 0 and f["firm_id"] in FIRM_CAMP_LAYOUT and der_len >= 2 + SOLDIER_SIZE * 15 + 1:
			var n := clampi(_s8(der + 2 + SOLDIER_SIZE * 15), 0, 15)
			for k in n:
				var s := der + 2 + k * SOLDIER_SIZE
				# Soldier (osoldier.h): race, rank, unit_id, ..., hit_points@16, Skill@24, Item@39
				f["soldiers"].append({"race": _s8(s), "rank": _s8(s + 1), "unit_id": _s16(s + 2),
					"loyalty": _s8(s + 14), "hp": _s16(s + 16), "remain_build_days": _s16(s + 20),
					"combat": _f32(s + 31), "skill": _f32(s + 35)})
		firms.append(f)
	_empty_room()
	return true


func _read_rocks() -> bool:
	for spec in [[212, rocks], [213, dirts]]:
		var at := _find(spec[0], _p, func(p): return _u16(p) == DYN_ARRAY_REC)
		if at < 0:
			continue
		_p = at
		var hdr := _record(DYN_ARRAY_REC)
		var last := _s32(hdr + 12)
		var ele := _s32(hdr + 16)
		if last > 0:
			_p += 2    # record size (0 when the body is over 64K)
			var b := _p
			_p += last * ele
			for k in last:
				var e := b + k * ele
				# Rock: rock_recno, cur_frame, delay_remain, loc_x, loc_y (orock.h)
				spec[1].append({"recno": _s16(e), "x": _s16(e + 4), "y": _s16(e + 6)})
		_empty_room()
	return true


# ------------------------------------------------------------- terrain ---

## Terrain corner types (0 dark grass, 1 light grass, 2 dirt) regenerated from
## the saved seed exactly as World::generate_map(1) does: plasma height map,
## then remove_odd(), then TerrainRes::terrain_height().
func terrain_corners() -> PackedByteArray:
	var gen := _Plasma.new(w, h, map_seed)
	gen.run()
	var out := PackedByteArray()
	out.resize((w + 1) * (h + 1))
	for i in out.size():
		out[i] = _Plasma.terrain_type(gen.m[i]) - 1
	return out


class _Plasma:
	const SHIFT_VALUE := 18
	const MAX_COLOR := 256
	const MIN_HEIGHT := [0, 85, 170, 300]   # terrain_type_min_height_array[][0]

	var mx := 0
	var my := 0
	var seed := 0
	var m := PackedInt32Array()
	var iparmx := 0
	var recur1 := 0
	var recur_level := 0

	func _init(w: int, h: int, s: int) -> void:
		mx = w
		my = h
		seed = s & 0xffffffff
		m.resize((w + 1) * (h + 1))

	## Misc::rand(): the game's linear congruential generator.
	func rand() -> int:
		seed = (0x015a4e35 * seed + 1) & 0xffffffff
		return (seed >> 16) & 0x7fff

	func random(n: int) -> int:
		return n * rand() / 0x8000

	static func terrain_type(height: int) -> int:
		for tc in range(3, -1, -1):
			if height >= MIN_HEIGHT[tc]:
				return tc + 1
		return 1

	func get_pix(x: int, y: int) -> int:
		return m[y * (mx + 1) + x]

	func plot(x: int, y: int, v: int) -> void:
		m[y * (mx + 1) + x] = v

	func run() -> void:
		# heightMap.generate(misc.random(2), 5, misc.rand()): MSVC evaluates
		# the arguments right to left, so rand() is drawn first.
		rand()
		var method := random(2)
		generate(method, 5)
		for y in my + 1:
			for x in mx + 1:
				remove_odd(x, y, 5)

	func generate(method: int, grain: int) -> void:
		iparmx = grain * 8
		var rnd: Array[int] = []
		for n in 4:
			rnd.append(1 + (((rand() / MAX_COLOR) * (MAX_COLOR - 1)) >> (SHIFT_VALUE - 11)))
		plot(0, 0, rnd[0])
		plot(mx, 0, rnd[1])
		plot(mx, my, rnd[2])
		plot(0, my, rnd[3])
		recur_level = 0
		if method == 0:
			sub_divide(0, 0, mx, my)
		else:
			recur1 = 1
			var i := 1
			var k := 1
			while true:
				new_sub_divide(0, 0, mx, my, i)
				k *= 2
				if k > mx and k > my:
					break
				i += 1

	func adjust(xa: int, ya: int, x: int, y: int, xb: int, yb: int) -> int:
		var pr := iparmx * (rand() - 16383)
		pr = (pr * recur1) >> SHIFT_VALUE
		pr = ((get_pix(xa, ya) + get_pix(xb, yb) + 1) >> 1) + pr
		pr = clampi(pr, 1, MAX_COLOR - 1)
		plot(x, y, pr)
		return pr

	func _get_or_adjust(px: int, py: int, xa: int, ya: int, xb: int, yb: int) -> int:
		var v := get_pix(px, py)
		return v if v != 0 else adjust(xa, ya, px, py, xb, yb)

	func sub_divide(x1: int, y1: int, x2: int, y2: int) -> void:
		if x2 - x1 < 2 and y2 - y1 < 2:
			return
		recur_level += 1
		recur1 = 320 >> recur_level
		var x := (x1 + x2) >> 1
		var y := (y1 + y2) >> 1
		var i := _get_or_adjust(x, y1, x1, y1, x2, y1)
		i += _get_or_adjust(x2, y, x2, y1, x2, y2)
		i += _get_or_adjust(x, y2, x1, y2, x2, y2)
		i += _get_or_adjust(x1, y, x1, y1, x1, y2)
		if get_pix(x, y) == 0:
			plot(x, y, ((i + 2) >> 2) & 0xffff)
		sub_divide(x1, y1, x, y)
		sub_divide(x, y1, x2, y)
		sub_divide(x, y, x2, y2)
		sub_divide(x1, y, x, y2)
		recur_level -= 1

	func new_sub_divide(x1: int, y1: int, x2: int, y2: int, recur: int) -> void:
		recur1 = 320 >> recur
		var sv := PackedInt32Array()
		sv.resize(16)
		var sr := PackedInt32Array()
		sr.resize(16)
		var t := 2
		var ny := y2
		var ny1 := y1
		sv[0] = y2
		sv[2] = y1
		sr[0] = 0
		sr[2] = 0
		sr[1] = 1
		var y := (ny1 + ny) >> 1
		sv[1] = y
		while t >= 1:
			while sr[t - 1] < recur:
				t += 1
				ny1 = sv[t - 1]
				sv[t] = ny1
				ny = sv[t - 2]
				sr[t] = sr[t - 1]
				y = (ny1 + ny) >> 1
				sv[t - 1] = y
				sr[t - 1] = maxi(sr[t], sr[t - 2]) + 1
			var xv := PackedInt32Array()
			xv.resize(16)
			var xr := PackedInt32Array()
			xr.resize(16)
			var xt := 2
			var nx := x2
			var nx1 := x1
			xv[0] = x2
			xv[2] = x1
			xr[0] = 0
			xr[2] = 0
			xr[1] = 1
			var x := (nx1 + nx) >> 1
			xv[1] = x
			while xt >= 1:
				while xr[xt - 1] < recur:
					xt += 1
					nx1 = xv[xt - 1]
					xv[xt] = nx1
					nx = xv[xt - 2]
					xr[xt] = xr[xt - 1]
					x = (nx1 + nx) >> 1
					xv[xt - 1] = x
					xr[xt - 1] = maxi(xr[xt], xr[xt - 2]) + 1
				var v := _get_or_adjust(nx, y, nx, ny1, nx, ny)
				v += _get_or_adjust(x, ny, nx1, ny, nx, ny)
				if get_pix(x, y) == 0:
					v += _get_or_adjust(x, ny1, nx1, ny1, nx, ny1)
					v += _get_or_adjust(nx1, y, nx1, ny1, nx1, ny)
					plot(x, y, ((v + 2) >> 2) & 0xffff)
				if xr[xt - 1] == recur:
					xt -= 2
			if sr[t - 1] == recur:
				t -= 2

	## World::remove_odd(): flatten isolated corners into their neighbours' type.
	func remove_odd(x: int, y: int, recur: int) -> void:
		if recur < 0:
			return
		var center := terrain_type(get_pix(x, y))
		var same := 0
		var diff := 0
		var diff_terrain := -1
		var diff_height := 0
		var sx := 0
		var sy := 0
		for d in [[x, y - 1, y > 0], [x, y + 1, y < my], [x - 1, y, x > 0], [x + 1, y, x < mx]]:
			if not d[2]:
				continue
			var hgt := get_pix(d[0], d[1])
			var tt := terrain_type(hgt)
			if tt == center:
				same += 1
				sx = d[0]
				sy = d[1]
			else:
				diff += 1
				if diff_terrain < 0:
					diff_height = hgt
					diff_terrain = tt
				elif diff_terrain != tt:
					return
		if same <= 1 and diff >= 2:
			plot(x, y, diff_height)
			if same == 1:
				remove_odd(sx, sy, recur - 1)
