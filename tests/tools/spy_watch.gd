extends Node
## A computer-only game with four kingdoms, to watch espionage:
##   godot --headless --path . res://tests/tools/spy_watch.tscn -- days=2000 seed=3
func _ready() -> void:
	if Assets.load_install() != "":
		get_tree().quit(1); return
	var days := 2000
	var seed := 3
	for a in OS.get_cmdline_user_args():
		if a.begins_with("days="): days = a.substr(5).to_int()
		elif a.begins_with("seed="): seed = a.substr(5).to_int()
	var g := Game.new()
	add_child(g)
	g.start({"seed": seed, "size": 160, "race": "NORMAN", "ai_count": 3, "autoplay": true, "reveal": true})
	g.message.connect(func(t, _l): if t.contains("spy") or t.contains("bribe") or t.contains("assassin") or t.contains("incident") or t.contains("Bribed"): print("  day %d: %s" % [g.day, t]))
	for d in days:
		for f in Defs.FRAMES_PER_DAY:
			g.sim_frame()
		if d % 500 == 499:
			var spies := g.units.filter(func(u): return u.is_spy and not u.dead)
			print("day %d: %d spies (%d inside), sleepers %d, events %s" % [g.day, spies.size(), g.spies.size(),
				g.units.filter(func(u): return u.sleeper_for > 0 and not u.dead).size(), Espionage.stats])
			for sp in g.spies:
				var pl = sp.spy_place
				var why := "%s skill %d in %s of %d" % [g.nation(sp.nation_id).name, int(sp.spy_skill), pl.display_name(), pl.nation_id]
				if Espionage.is_camp(pl) and pl.overseer and pl.nation_id != sp.nation_id:
					var o: Unit = pl.overseer
					why += " | general lead %d loyal %d king %s, chance@0 %d @4000 %d, cash %d, assassinate %d%%" % [int(o.lead_skill()), int(o.loyalty), o.rank == Defs.Rank.KING,
						Espionage.bribe_chance(sp, pl, o, 0), Espionage.bribe_chance(sp, pl, o, 4000), int(g.nation(sp.nation_id).cash), Espionage.assassinate_chance(sp, pl)]
				print("     ", why)
			for n in g.nations:
				var st := []
				for t in Defs.TECHS:
					if t.get("spy", false) and n.tech_level(t["code"]) > 0:
						st.append(t["code"])
				print("   %s alive=%s cash=%d spy tech %s" % [n.name, n.alive, int(n.cash), st])
	get_tree().quit()
