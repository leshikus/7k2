extends SceneTree
## Headless check of the asset decoders: writes sample PNGs to user://dump/.
func _init() -> void:
	var A = load("res://scripts/assets/assets.gd").new()
	A._ready()
	var t0 := Time.get_ticks_msec()
	var err: String = A.load_install()
	print("load: '", err, "' in ", Time.get_ticks_msec() - t0, " ms; path=", A.install_path)
	if err != "":
		quit(1); return
	DirAccess.make_dir_recursive_absolute("user://dump")
	print("sprites=", A.sprites.size(), " firm_builds=", A.firm_builds.size(), " plants=", A.plant_bitmaps.size(), " layouts=", A.town_layouts.size(), " terrain=", A.terrain_textures.keys())
	var f = A.sprite_frame("NO_INF", "M", 3, 0, Color(0.9, 0.2, 0.2))
	f[0].get_image().save_png("user://dump/no_inf.png")
	for code in ["FORT", "CAMP", "MINE", "FACTORY", "MARKET", "INN", "RESEARCH", "WAR", "BASE", "LAIR"]:
		var b: Dictionary = A.firm_build(code, "NORMAN")
		print(code, " loc=", b.get("loc_w"), "x", b.get("loc_h"), " frames=", b.get("frames", []).size(), " ground=", b.get("ground"), " res=", b.get("res_name"))
		if b.is_empty() or b["frames"].is_empty(): continue
		for rec in b["frames"][0]["bitmaps"]:
			var r = A.firm_bitmap(b, rec, Color(0.2, 0.3, 0.9))
			if r.size() > 0:
				r[0].get_image().save_png("user://dump/firm_%s_%d.png" % [code, rec])
				print("   bmp ", rec, " ofs=", r[1], " layer=", r[2], " size=", r[0].get_size())
	var h = A.town_house("NORMAN", 3)
	if h.size() > 0: h[0].get_image().save_png("user://dump/house.png")
	var g = A.picture("I_TPICT1.RES", "TOWNGD1")
	print("town ground: ", g)
	if g: g.get_image().save_png("user://dump/townground.png")
	A.plant_bitmaps[3]["tex"].get_image().save_png("user://dump/tree.png")
	A.terrain_textures["G"].get_image().save_png("user://dump/ter_G.png")
	A.terrain_textures["D"].get_image().save_png("user://dump/ter_D.png")
	for row in A.table("UNIT"):
		if row["SPRITE"] == "NO_INF":
			var ic = A.unit_icon("I_UNITLI.RES", row["LICONPTR"])
			if ic: ic.get_image().save_png("user://dump/icon_no_inf.png"); print("icon ", ic.get_size())
	print("dump dir: ", ProjectSettings.globalize_path("user://dump"))
	quit(0)
