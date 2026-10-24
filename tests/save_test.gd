extends Node
## Save/load round trip: play, save, load into a fresh game, compare, keep playing.
func _ready() -> void:
	if Assets.load_install() != "":
		get_tree().quit(1); return
	var g := Game.new()
	add_child(g)
	g.start({"seed": 5, "size": 100, "race": "ROMAN", "ai_count": 3, "autoplay": true})
	for i in 4000: g.sim_frame()
	var before := _summary(g)
	var ok := SaveGame.save(g, "test_roundtrip")
	print("saved: ", ok, " ", SaveGame.describe("test_roundtrip"))
	g.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	var g2 := Game.new()
	add_child(g2)
	var err := SaveGame.load_into(g2, "test_roundtrip")
	print("load error: '", err, "'")
	var after := _summary(g2)
	var same := true
	for k in before:
		if str(before[k]) != str(after[k]):
			same = false
			print("  MISMATCH ", k)
			if before[k] is Array and after[k] is Array:
				for i in maxi(before[k].size(), after[k].size()):
					var a = before[k][i] if i < before[k].size() else null
					var b = after[k][i] if i < after[k].size() else null
					if str(a) != str(b):
						print("    before: ", a, "\n    after:  ", b)
			else:
				print("    before: ", str(before[k]).left(300), "\n    after:  ", str(after[k]).left(300))
	print("summary keys compared: ", before.size(), " identical: ", same)
	for i in 4000: g2.sim_frame()
	print("continued 400 days after load: day=", g2.day, " units=", g2.units.size(), " firms=", g2.firms.size())
	print("RESULT: ", "PASS" if same and err == "" else "FAIL")
	DirAccess.remove_absolute(SaveGame.path_for("test_roundtrip"))
	get_tree().quit(0 if same else 2)

func _summary(g: Game) -> Dictionary:
	var d := {"day": g.day, "frame": g.frame}
	d["nations"] = g.nations.map(func(n): return [n.id, n.name, n.race, roundi(n.cash), roundi(n.food), int(n.reputation), n.alive, n.tech, n.relations, n.king.obj_id if n.king else 0])
	var towns := g.towns.map(func(t): return [t.obj_id, t.town_name, t.nation_id, t.x1, t.y1, t.population, int(t.loyalty), t.resistance.keys().size()])
	towns.sort()
	d["towns"] = towns
	var firms := g.firms.map(func(f): return [f.obj_id, f.code, f.nation_id, f.x1, f.y1, f.under_construction, roundi(f.hp), f.overseer.obj_id if f.overseer else 0, f.soldiers.map(func(s): return s.obj_id), snappedf(f.stock, 0.001), f.research_tech])
	firms.sort()
	d["firms"] = firms
	var units := g.units.filter(func(u): return not u.dead).map(func(u): return [u.obj_id, u.sprite_code, u.nation_id, u.cell(), u.rank, int(u.combat), roundi(u.hp), u.inside_firm.obj_id if u.inside_firm else 0])
	units.sort()
	d["units"] = units
	d["ai"] = g.nations.filter(func(n): return n.ai is NationAI).map(func(n): return [n.id, n.ai.actions.map(func(a): return [a["mode"], str(a["para"]), a["x"], a["y"], a["processing"], a["unit"].obj_id if a["unit"] and not a["unit"].dead else 0]), n.ai.attack_camps.size(), n.ai.capture_town.obj_id if n.ai.capture_town else 0, n.ai.secret_attack.keys(), n.prefs.get("peacefulness", -1), roundi(n.true_profit_365())])
	d["firm_ai"] = g.firms.map(func(f): return [f.obj_id, f.should_close, f.setup_day, f.patrol_units.filter(func(u): return is_instance_valid(u) and not u.dead).size(), f.is_attack_camp])
	d["trees"] = g._plants.size()
	d["fog"] = g.fog.count(1) + 1000 * g.fog.count(2)
	d["sites"] = g.sites.map(func(s): return [s.x1, s.y1, roundi(s.reserve), s.mine.obj_id if s.mine else 0])
	return d
