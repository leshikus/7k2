extends Node
## Weather statistics over three years and rain slowdown on units.
func _ready() -> void:
	Assets.load_install()
	var g := Game.new()
	add_child(g)
	g.start({"seed": 5, "size": 90, "race": "NORMAN", "ai_count": 1, "fryhtan_count": 0, "autoplay": true})
	var rain_days := 0
	var storm_days := 0
	var by_month := []
	by_month.resize(12)
	by_month.fill(0)
	var strikes := [0]
	g.lightning.connect(func(_p): strikes[0] += 1)
	for d in 365 * 3:
		for f in Defs.FRAMES_PER_DAY: g.sim_frame()
		if g.weather.rain_scale() > 0:
			rain_days += 1
			by_month[(d % 365) / 31 if (d % 365) / 31 < 12 else 11] += 1
		if g.weather.is_lightning():
			storm_days += 1
	var u: Unit = g.spawn_unit("NO_INF", 1, Vector2i(45, 45), 20.0)
	g.weather.cloud_str = 0
	var dry := u.speed_loc()
	g.weather.cloud_str = 9
	var wet := u.speed_loc()
	print("rain days ", rain_days, "/1095, storm days ", storm_days, ", lightning strikes ", strikes[0])
	print("rainy days per month (3 yrs): ", by_month)
	print("NO_INF speed dry %.3f wet %.3f" % [dry, wet])
	print("RESULT: ", "PASS" if rain_days > 30 and rain_days < 700 and wet < dry else "FAIL")
	get_tree().quit()
