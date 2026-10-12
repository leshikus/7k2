extends Node
## Writes reference sheets of the original art (for modelling; never commit them):
## one row per unit sprite (stand, attack frames, death), one image per firm/race.
## Usage: godot --headless --path . res://tests/tools/ref_sheet.tscn -- out=<dir>
func _ready() -> void:
	if Assets.load_install() != "":
		get_tree().quit(1); return
	Defs.load_from_assets()
	var out := "user://ref"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4)
	DirAccess.make_dir_recursive_absolute(out)
	var col := Color(0.85, 0.15, 0.12)
	for code in Defs.unit_types:
		var frames := []
		for act in ["S", "M", "A1", "A2", "A3", "D"]:
			if not Assets.has_action(code, act): continue
			var n := Assets.action_len(code, act, 3)
			var picks := [0] if act == "S" else ([0, n / 2] if act == "M" else [0, n / 3, 2 * n / 3, n - 1])
			for f in picks:
				var fr := Assets.sprite_frame(code, act, 3 if act != "D" else 0, f, col)
				if not fr.is_empty(): frames.append(fr[0].get_image())
		if frames.is_empty(): continue
		var w := 0; var h := 0
		for im in frames: w += im.get_width() + 4; h = maxi(h, im.get_height())
		var sheet := Image.create(w, h, false, Image.FORMAT_RGBA8)
		sheet.fill(Color(0.55, 0.6, 0.5))
		var x := 0
		for im in frames:
			im.convert(Image.FORMAT_RGBA8)
			sheet.blend_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i(x, h - im.get_height()))
			x += im.get_width() + 4
		sheet.save_png(out.path_join("unit_%s.png" % code))
	for code in Defs.firm_types:
		for race in Defs.RACE_PREFIX.keys() + ["MONSTER"]:
			var b: Dictionary = Assets.firm_build(code, race)
			if b.is_empty() or b.get("frames", []).is_empty(): continue
			var key := "%s_%s" % [code, b.get("res_name", race)]
			if FileAccess.file_exists(out.path_join("firm_%s.png" % key)): continue
			var parts := []
			var mn := Vector2(1e9, 1e9); var mx := Vector2(-1e9, -1e9)
			for rec in b["frames"][0]["bitmaps"]:
				var r := Assets.firm_bitmap(b, rec, col)
				if r.is_empty(): continue
				parts.append(r); mn = mn.min(r[1]); mx = mx.max(r[1] + Vector2(r[0].get_size()))
			if parts.is_empty(): continue
			var sheet := Image.create(int(mx.x - mn.x), int(mx.y - mn.y), false, Image.FORMAT_RGBA8)
			for r in parts:
				var im: Image = r[0].get_image(); im.convert(Image.FORMAT_RGBA8)
				sheet.blend_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i(r[1] - mn))
			sheet.save_png(out.path_join("firm_%s.png" % key))
			print("firm ", key, " loc ", b.get("loc_w"), "x", b.get("loc_h"))
	get_tree().quit()
