extends Node
## Ground fire and splash damage (obullet.cpp, ow_fire.cpp): fire bombs set the
## ground alight, burning trees and hurting whoever stands there until the
## fire dies down; a big shell hurts everyone near its impact but the shooter's
## own men.

var ok := true


func check(cond: bool, what: String) -> void:
	print(("ok   " if cond else "FAIL ") + what)
	if not cond:
		ok = false


func frames(g: Game, n: int) -> void:
	for i in n:
		g.sim_frame()


func _ready() -> void:
	if Assets.load_install() != "":
		get_tree().quit(1); return
	Defs.load_from_assets()
	var g := Game.new()
	add_child(g)
	g.start({"seed": 3, "size": 90, "race": "NORMAN", "ai_count": 1, "fryhtan_count": 0, "reveal": true})
	g.weather.cloud_str = 0
	var p := g.player()
	var foe: Nation = g.nations.filter(func(n): return n.id != p.id)[0]
	g.declare_war(p.id, foe.id)
	check(Defs.unit_types["CATAPULT"]["attacks"].any(func(a): return a["fire"] > 0 and a["radius"] > 32), "catapult attacks carry fire and blast radii")

	# a tree on fire burns away; the fire dies down
	var tree: Vector2i = g._plants.keys()[0]
	for t in g._plants.keys():
		if not g.world.is_hill(t) and not (g.world.object_at(t) is Rock):
			tree = t      # fire does not take on hills or rocks
			break
	g.set_fire(tree, 1)
	check(g.fires.has(tree), "the fire bomb sets the ground alight")
	frames(g, Game.FIRE_SCAN * 2)
	check(not g._plants.has(tree), "the tree burns")
	frames(g, Game.FIRE_SCAN * 40)
	check(not g.fires.has(tree), "the fire has died down")

	# a man standing in the fire is hurt
	var spot := g.world.nearest_walkable(Vector2i(45, 45))
	var u := g.spawn_unit(Defs.unit_sprite("NORMAN", "INF"), foe.id, spot, 20.0)
	u.stop()
	u.frozen_until = g.frame + 100000     # held there: a computer's unit would walk out (Unit::ai_escape_fire)
	var hp0 := u.hp
	g.set_fire(u.cell(), 1)
	frames(g, Game.FIRE_SCAN * 5)
	check(u.hp < hp0, "a unit in the fire is burnt (%.1f -> %.1f)" % [hp0, u.hp])

	# rain puts fires out sooner
	var dry := Vector2i(10, 10)
	g.fires.clear()
	g.weather.cloud_str = 0       # a dry day, whatever the weather has been
	g.set_fire(dry, 1)
	var dry_scans := 0
	while g.fires.has(dry) and dry_scans < 200:
		g._process_fires()
		dry_scans += 1
	g.weather.cloud_str = 10
	g.set_fire(dry, 1)
	var wet_scans := 0
	while g.fires.has(dry) and wet_scans < 200:
		g._process_fires()
		wet_scans += 1
	g.weather.cloud_str = 0
	check(wet_scans < dry_scans, "rain shortens a fire (%d scans against %d)" % [wet_scans, dry_scans])

	# a heavy shell hurts the enemies around its target, not the shooter's men
	var c := g.world.nearest_walkable(Vector2i(30, 60))
	var shooter := g.spawn_unit("CATAPULT", p.id, c + Vector2i(-6, 0), 50.0)
	var tgt := g.spawn_unit(Defs.unit_sprite("NORMAN", "INF"), foe.id, c, 20.0)
	var near := g.spawn_unit(Defs.unit_sprite("NORMAN", "INF"), foe.id, g.free_unit_cell(c + Vector2i(1, 0)), 20.0)
	var mine := g.spawn_unit(Defs.unit_sprite("NORMAN", "INF"), p.id, g.free_unit_cell(c + Vector2i(0, 1)), 20.0)
	for x in [tgt, near, mine, shooter]:
		x.stop()
	g.sim_frame()
	print("     target at ", tgt.cell(), ", neighbour at ", near.cell(), ", own man at ", mine.cell())
	var h := [tgt.hp, near.hp, mine.hp]
	var b := g.spawn_bullet(shooter, tgt, "CATFIRE", 16.0, 10.0)
	b.radius = 62
	b.fire = 1
	for i in 200:
		b.sim_frame()
		if b.done:
			break
	check(tgt.hp < h[0], "the target is hit")
	check(near.hp < h[1] and near.hp > h[1] - 10.0, "the man beside it takes part of the blow (%.1f)" % (h[1] - near.hp))
	check(is_equal_approx(mine.hp, h[2]), "the shooter's own man is spared")
	check(g.fires.has(Vector2i(tgt.center_loc().floor())) or g.fires.size() > 0, "the impact burns")

	# a blow at the player's man marks the minimap; the mark fades
	g.war_points.clear()
	mine.take_damage(1.0, tgt)
	check(g.war_points.has(Vector2i(int(mine.center_loc().x) / Game.WAR_ZONE, int(mine.center_loc().y) / Game.WAR_ZONE)), "an attack on our man flashes on the minimap")
	# nothing else may strike him while the mark fades
	g.fires.clear()
	for x in g.units.duplicate():
		if x.nation_id != p.id and not x.dead and x.center_loc().distance_to(mine.center_loc()) < 15.0:
			x.die(null)
	frames(g, 30)
	var zone := Vector2i(int(mine.center_loc().x) / Game.WAR_ZONE, int(mine.center_loc().y) / Game.WAR_ZONE)
	check(not g.war_points.has(zone), "and fades")

	# save and load keep the fires
	var fc := Vector2i(20, 20)
	while g.world.is_hill(fc) or g.world.object_at(fc) is Rock:
		fc += Vector2i(1, 0)
	g.set_fire(fc, 1)
	SaveGame.save(g, "test_fire")
	var g2 := Game.new()
	add_child(g2)
	SaveGame.load_into(g2, "test_fire")
	DirAccess.remove_absolute(SaveGame.path_for("test_fire"))
	check(g2.fires.has(fc), "fires are saved")
	print("RESULT: ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
