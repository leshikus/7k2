extends Node
## Headless soak test: every kingdom is AI-controlled; runs the simulation
## for a number of game days and prints a summary. Usage:
##   godot --headless --path . res://tests/sim_test.tscn -- days=1500 seed=7
func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2: args[kv[0]] = kv[1]
	var err := Assets.load_install()
	if err != "":
		push_error(err); get_tree().quit(1); return
	var g := Game.new()
	add_child(g)
	var cfg := {"seed": int(args.get("seed", "7")), "size": int(args.get("size", "110")), "race": "NORMAN", "ai_count": int(args.get("ai", "3")), "fryhtan_count": int(args.get("fry", "1")), "autoplay": true}
	if args.has("scn"):
		for info in ScenarioFile.list_premade():
			if info["path"].get_file().get_basename().to_lower() == String(args["scn"]).to_lower():
				cfg["scenario"] = info["path"]
				print("scenario: ", info["name"], " - ", info["text"])
	var t_load := Time.get_ticks_msec()
	g.start(cfg)
	print("started in ", Time.get_ticks_msec() - t_load, " ms")
	_report(g, 0)
	g.message.connect(func(t, _l): if args.has("verbose"): print("  msg: ", t))
	var days := int(args.get("days", "1200"))
	var t0 := Time.get_ticks_msec()
	for d in days:
		for f in Defs.FRAMES_PER_DAY:
			g.sim_frame()
		if d % 300 == 299:
			_report(g, d + 1)
		if g.over: break
	print("simulated ", days, " days in ", Time.get_ticks_msec() - t0, " ms")
	_report(g, days)
	get_tree().quit(0)

func _report(g: Game, d: int) -> void:
	var mons := g.units.filter(func(u): return u.is_monster() and not u.dead)
	var lairs := g.firms.filter(func(f): return f.code == "LAIR")
	print("--- day ", d, " (", g.date_string(), ") units=", g.units.size(), " firms=", g.firms.size(), " towns=", g.towns.size(), " fryhtans=", mons.size(), " (outside ", mons.filter(func(u): return u.inside_firm == null).size(), ") lairs=", lairs.size(), " indep towns=", g.towns.filter(func(t): return t.nation_id == 0).size())
	for n in g.nations:
		var towns := g.towns.filter(func(t): return t.nation_id == n.id)
		var pop := 0
		for t in towns: pop += t.population
		var firms := {}
		for f in g.firms:
			if f.nation_id == n.id: firms[f.code] = firms.get(f.code, 0) + 1
		var rel := []
		for o in g.nations:
			if o != n: rel.append(Defs.RELATION_NAMES[n.relation(o.id)][0])
		if n.is_fryhtan:
			var tribs := g.towns.filter(func(t): return t.tribute_to() == n.id).size()
			print("  %s alive=%s cash=%d live=%d lairs=%d brood=%d tribute towns=%d rel=%s" % [n.name, n.alive, n.cash, n.live_points, g.firms.filter(func(f): return f.nation_id == n.id).size(), g.units.filter(func(u): return u.nation_id == n.id and not u.dead).size(), tribs, "".join(g.nations.filter(func(o): return o != n).map(func(o): return Defs.RELATION_NAMES[n.relation(o.id)][0]))])
			continue
		print("  %s alive=%s cash=%d food=%d rep=%d towns=%d pop=%d units=%d firms=%s tech=%s rel=%s" % [n.name, n.alive, n.cash, n.food, n.reputation, towns.size(), pop, g.units.filter(func(u): return u.nation_id == n.id).size(), firms, n.tech, "".join(rel)])
