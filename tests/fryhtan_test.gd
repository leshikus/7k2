extends Node
## A Fryhtan kingdom next to an independent village: does it get the village to pay tribute?
func _ready() -> void:
	if Assets.load_install() != "":
		get_tree().quit(1); return
	var g := Game.new()
	add_child(g)
	g.start({"seed": 21, "size": 100, "race": "NORMAN", "ai_count": 1, "fryhtan_count": 1, "lairs": 0, "autoplay": true})
	var fry: Nation = g.nations.filter(func(n): return n.is_fryhtan)[0]
	var lair: Firm = g.firms.filter(func(f): return f.nation_id == fry.id)[0]
	var towns: Array = g.towns.filter(func(t): return t.nation_id == 0)
	towns.sort_custom(func(a, b): return a.center_loc().distance_to(lair.center_loc()) < b.center_loc().distance_to(lair.center_loc()))
	var t: Town = towns[0]
	print("fryhtans=", fry.name, " lair at ", lair.center_loc(), " nearest village ", t.town_name, " pop ", t.population, " dist ", t.center_loc().distance_to(lair.center_loc()), " linked=", t.linked_firms.has(lair), " res=", int(t.resistance_to(fry.id)))
	for d in 1200:
		for f in Defs.FRAMES_PER_DAY: g.sim_frame()
		if d >= 230 and d <= 370 and d % 10 == 0:
			var atk := g.units.filter(func(u): return u.nation_id == fry.id and u.target == t).size()
			print("   sanchi d", d, " dead=", t.dead, " owner=", t.nation_id, " pop=", t.population, " res=", int(t.resistance_to(fry.id)), " defenders=", t.defenders.size(), " fry attackers=", atk, " tribute_to=", t.tribute_to() if not t.dead else -1)
		if d % 60 == 0:
			var lairs := g.firms.filter(func(f): return f.nation_id == fry.id)
			var tribute := g.towns.filter(func(x): return x.tribute_to() == fry.id).map(func(x): return x.town_name)
			var near := g.towns.filter(func(x): return x.nation_id == 0 and x.linked_firms.any(func(f): return f.nation_id == fry.id)).map(func(x): return "%s pop%d res%d tgt%s" % [x.town_name, x.population, int(x.resistance_to(fry.id)), str(x.target_resistance.get(fry.id, "-"))])
			var uc := g.firms.filter(func(f): return f.nation_id == fry.id and f.under_construction)
			for f in uc:
				var b := g.units.filter(func(u): return u.nation_id == fry.id and u.order == Unit.Order.BUILD and u.order_firm == f)
				var idle := g.units.filter(func(u): return u.nation_id == fry.id and not u.dead and u.inside_firm == null and u.order == Unit.Order.IDLE).size()
				print("   site progress=", int(f.progress), " builder=", f.builder != null, " heading=", b.size(), " idle fryhtans=", idle)
			print("d", d, " cash=", int(fry.cash), " live=", int(fry.live_points), " lairs=", lairs.size(), " ov=", lairs.map(func(f): return f.overseer != null), " inside=", lairs.map(func(f): return f.soldiers.size()), " brood=", g.units.filter(func(u): return u.nation_id == fry.id and not u.dead).size(), " linked villages=", near, " tribute=", tribute)
	get_tree().quit()
