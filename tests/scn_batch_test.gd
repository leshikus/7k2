extends Node
## Loads every .scn in a folder (dir=<path>), plays N days AI vs AI (days=30) and
## reports parse problems, start-up counts and the surviving kingdoms.
func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=", true, 1)
		if kv.size() == 2: args[kv[0]] = kv[1]
	if Assets.load_install() != "":
		get_tree().quit(1); return
	Defs.load_from_assets()
	var dir: String = args.get("dir", "")
	var days := int(args.get("days", "30"))
	var only: String = args.get("only", "")
	var files := []
	for f in DirAccess.get_files_at(dir):
		if f.get_extension().to_lower() == "scn" and (only == "" or f.to_lower().begins_with(only.to_lower())):
			files.append(f)
	files.sort()
	var bad := 0
	for f in files:
		var path := dir.path_join(f)
		var s := ScenarioFile.new()
		if not s.load_file(path):
			print("%-24s PARSE FAIL: %s" % [f, s.error]); bad += 1
			continue
		var g := Game.new()
		add_child(g)
		var t0 := Time.get_ticks_msec()
		g.start({"scenario": path, "autoplay": true, "reveal": true, "seed": 1})
		var t1 := Time.get_ticks_msec()
		var start := _line(g)
		for d in days:
			for k in 30: g.sim_frame()
		print("%-24s %dx%d load %dms | start %s | day %d (%d ms/day) %s" % [f, g.world.w, g.world.h, t1 - t0, start, days, (Time.get_ticks_msec() - t1) / maxi(1, days), _line(g)])
		g.queue_free()
		await get_tree().process_frame
	print("files ", files.size(), " parse failures ", bad)
	get_tree().quit()


func _line(g: Game) -> String:
	var parts := []
	for n in g.nations:
		if not n.alive: continue
		var t := g.towns.filter(func(x): return x.nation_id == n.id).size()
		var f := g.firms.filter(func(x): return x.nation_id == n.id).size()
		var u := g.units.filter(func(x): return x.nation_id == n.id and not x.dead).size()
		parts.append("%s%s t%d f%d u%d" % [n.name.replace("Kingdom of ", ""), "*" if n.is_fryhtan else "", t, f, u])
	return ", ".join(parts)
