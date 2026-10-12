extends Node
## Times the parts of Game.sim_frame on a big scenario (scn=<file in scenario/>).
func _ready() -> void:
	Assets.load_install()
	Defs.load_from_assets()
	var file := "HailtotheEmpire.scn"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("scn="): file = a.substr(4)
	var g := Game.new()
	add_child(g)
	g.start({"scenario": ProjectSettings.globalize_path("res://scenario/" + file), "autoplay": true, "reveal": true, "seed": 1})
	for i in 300: g.sim_frame()
	var t := {"cells": 0, "units": 0, "firms": 0, "towns": 0, "bullets": 0, "day": 0, "vis": 0}
	var by_order := {}
	var n_frames := 300
	for i in n_frames:
		g.frame += 1
		var t0 := Time.get_ticks_usec()
		g.unit_cells.clear()
		for u in g.units:
			if not u.dead and u.inside_firm == null:
				var c := u.cell()
				g.unit_cells[c] = g.unit_cells.get(c, 0) + 1
		var t1 := Time.get_ticks_usec()
		for u in g.units.duplicate():
			if is_instance_valid(u):
				var k := "%s%s" % [u.order, " atk" if u.attacking else ""]
				var a := Time.get_ticks_usec()
				u.sim_frame()
				by_order[k] = by_order.get(k, 0) + Time.get_ticks_usec() - a
		var t2 := Time.get_ticks_usec()
		for f in g.firms: f.sim_frame()
		var t3 := Time.get_ticks_usec()
		for tw in g.towns: tw.town_shoot()
		var t4 := Time.get_ticks_usec()
		for b in g.bullets.duplicate():
			b.sim_frame()
			if b.done:
				g.bullets.erase(b); b.queue_free()
		for e in g.effects_list.duplicate():
			e.sim_frame()
			if e.done:
				g.effects_list.erase(e); e.queue_free()
		var t5 := Time.get_ticks_usec()
		if g.frame % Defs.FRAMES_PER_DAY == 0:
			g.next_day(); g._process_spies()
		var t6 := Time.get_ticks_usec()
		if g.frame % 5 == 0: g._update_visibility()
		var t7 := Time.get_ticks_usec()
		t["cells"] += t1 - t0; t["units"] += t2 - t1; t["firms"] += t3 - t2; t["towns"] += t4 - t3
		t["bullets"] += t5 - t4; t["day"] += t6 - t5; t["vis"] += t7 - t6
	print("units ", g.units.size(), " firms ", g.firms.size(), " towns ", g.towns.size())
	for k in t: print("  %-8s %7.2f ms/frame" % [k, t[k] / 1000.0 / n_frames])
	print("  unit time by order (0 idle,1 move,2 attack,...):")
	for k in by_order: print("    order ", k, ": %7.2f ms/frame" % (by_order[k] / 1000.0 / n_frames))
	get_tree().quit()
