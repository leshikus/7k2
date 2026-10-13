extends Node
## Scene root: start menu, then the game with camera, HUD and player input.

const EDGE_SCROLL := 6
const LOC_PIXELS := 32.0          # a location's width on screen at normal zoom
var _scroll_wait := 0.0
const PAN_SPEED := 900.0
const MODEL_LIBRARY := "res://scripts/models/model_library.gd"

var menu: MainMenu
var game: Game
var hud: Hud
var camera: CameraRig
var view3d: View3D
var overlay_layer: CanvasLayer
var ghost: BuildGhost
var select_layer: CanvasLayer
var select_box: SelectBox
var music: AudioStreamPlayer
var sfx: SoundFX
var rain_layer: RainLayer
var rain_player: AudioStreamPlayer

var build_code := ""
var build_race := ""
var _editor_tool := {}         # scenario editor: what a left click places
var _rally_firm: Firm = null   # building waiting for its rally point click
var _cast_god: Unit = null         # Greater Being waiting for the click on where to cast
var _found_town_unit: Unit = null  # unit waiting for the click on its new town's site
var _route_caravan: Unit = null  # caravan waiting for the click on a stop
var _route_stop := 0
var _spell_firm: Firm = null   # spell building waiting for its target click
var _spell_code := ""
var _spell_unit: Unit = null    # teleport: the unit picked by the first click
var _item_user: Unit = null  # unit about to use an item on what is clicked next        # race of the building to place (a Seat of Power's god)
var _drag_from := Vector2.ZERO
var _dragging := false
var _left_down := false
var _orbiting := false
var _groups := {}
var _music_files: Array[String] = []
var _music_on := true
var _music_thread: Thread = null


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.02, 0.02, 0.02))
	sfx = SoundFX.new()
	add_child(sfx)
	rain_player = AudioStreamPlayer.new()
	rain_player.volume_db = -14.0
	add_child(rain_player)
	music = AudioStreamPlayer.new()
	music.volume_db = -10.0
	music.finished.connect(_next_track)
	add_child(music)
	Net.game_start.connect(_start, CONNECT_DEFERRED)
	_show_menu()
	# Command-line shortcut for automated runs: --autostart [seed]
	var args := OS.get_cmdline_user_args()
	if "--autostart" in args and Assets.ready_ok:
		var race := "NORMAN"
		for a in args:
			if a.begins_with("--race="):
				race = a.substr(7)       # a Fryhtan species (GITH, PLANT ...) leads a Fryhtan kingdom
		_start({"seed": 7, "size": 100, "race": race, "ai_count": 3, "cash": 3000})
	# --campaign [--race=X]: a new campaign; --campaign-battle goes straight to its first battle
	if "--campaign" in args and Assets.ready_ok:
		Defs.load_from_assets()
		var crace := "NORMAN"
		for a in args:
			if a.begins_with("--race="):
				crace = a.substr(7)
		campaign = Campaign.new()
		campaign.init_new(crace, 3, 77)
		if "--campaign-battle" in args:
			while campaign.event_id != 0 and not campaign.finished:
				campaign.ui = _AutoUI.new()
				await campaign.process_event()
			campaign.ui = _AutoUI.new()
			await campaign.stage_prelude()
			_start_campaign_battle()
		else:
			_show_campaign()
	if "--credits" in args and menu:
		menu._show_credits.call_deferred()
	# --show-paths (with --autostart): march the starting army and show its path, for screenshots
	if "--show-paths" in args and game:
		GameOptions.reset()
		GameOptions._values["show_unit_path"] = 3
		var men := game.units.filter(func(u): return u.nation_id == game.player_id and u.inside_firm == null and not u.dead)
		for u in men:
			u.order_move_free(Vector2i(u.cell()) + Vector2i(14, 10))
		game.selected = men
	# --editor: the scenario editor on a new map
	if "--editor" in args and Assets.ready_ok:
		Defs.load_from_assets()
		_start({"editor": true, "seed": 7, "size": 100, "race": "NORMAN", "ai_count": 2, "fryhtan_count": 1, "indep_towns": 6, "lairs": 2, "reveal": true})
	# --tutorial=<lesson id>: start a lesson of the learning campaign
	for a in args:
		if a.begins_with("--tutorial=") and Assets.ready_ok:
			Defs.load_from_assets()
			var l := Tutorial.lesson_by_id(a.substr(11).to_int())
			if not l.is_empty():
				_start({"scenario": Tutorial.map_path(l), "seed": 1, "tutorial": l["id"]})
	# --scenario=<file name> [--spectate]: start a premade scenario
	for a in args:
		if a.begins_with("--scenario=") and Assets.ready_ok:
			Defs.load_from_assets()
			for info in ScenarioFile.list_premade():
				if info["path"].get_file().get_basename().to_lower() == a.substr(11).to_lower():
					_start({"scenario": info["path"], "autoplay": "--spectate" in args, "reveal": "--spectate" in args})
	# --shot=<png> [--shot-after=<seconds>] [--shot-speed=<x>]: save a screenshot and quit
	for a in args:
		if a.begins_with("--shot="):
			_shot_path = a.substr(7)
		elif a.begins_with("--shot-after="):
			_shot_after = a.substr(13).to_float()
		elif a.begins_with("--shot-speed=") and game:
			game.speed = a.substr(13).to_float()
		elif a.begins_with("--demo=") and game:
			_demo(a.substr(7))
		elif a.begins_with("--yaw=") and camera:
			camera._yaw_target = a.substr(6).to_float()
			camera.yaw = camera._yaw_target
		elif a.begins_with("--pitch=") and camera:
			camera.pitch = clampf(a.substr(8).to_float(), camera.pitch_min, camera.pitch_max)
		elif a.begins_with("--look=") and camera:
			var xy := a.substr(7).split(",")
			camera.focus_on(Vector2(xy[0].to_float(), xy[1].to_float()))
			camera.zoom = Vector2(1.5, 1.5)
		elif a.begins_with("--bench="):
			_bench(a.substr(8).to_float())
		elif a == "--free-camera" and camera:
			camera.set_free(true)
		elif a == "--fixed-camera" and camera:
			camera.set_free(false)
		elif a == "--reveal" and game:
			game.reveal_all = true
			game._update_fog()
	if _shot_path != "":
		get_tree().create_timer(_shot_after).timeout.connect(_take_shot)


func _demo(what: String) -> void:
	var p := game.player()
	match what:
		"fort":
			var f: Array = game.firms.filter(func(x): return x.nation_id == p.id)
			_set_selection([f[0]])
		"battle":
			var home: Town = game.towns.filter(func(t): return t.nation_id == p.id)[0]
			var c := Vector2i(home.center_loc()) + Vector2i(-8, 8)
			var mine: Array = []
			for i in 6:
				var sp := "NO_INF" if i < 4 else "NO_SPU"
				mine.append(game.spawn_unit(sp, p.id, c + Vector2i(i % 3, i / 3), 60.0))
			for i in 4:
				var m: Unit = game.spawn_unit(["GITH", "HOBGLOB", "LYW", "GIANTET"][i], GameObj.MONSTER_NATION, c + Vector2i(6 + i % 2, 3 + i / 2), 40.0)
				for u in mine:
					if u: u.order_attack(m)
				m.order_attack(mine[i])
			camera.iso_pos = Iso.to_screen(Vector2(c) + Vector2(3, 2))
			camera.zoom = Vector2(1.4, 1.4)
			_set_selection(mine.filter(func(u): return u != null))
			var grid := GridOverlay.new()
			grid.rect = Rect2i(c - Vector2i(3, 3), Vector2i(14, 12))
			game.add_child(grid)
		"align":
			var base := Vector2i(30, 30)
			game.world.release(base.x - 4, base.y - 4, 40, 14)
			for c in game._plants.keys():
				if Rect2i(base - Vector2i(4, 4), Vector2i(40, 14)).has_point(c):
					game._plants[c].queue_free()
					game._plants.erase(c)
			var codes := ["FORT", "CAMP", "MINE"]
			for i in codes.size():
				var at := base + Vector2i(i * 10, 0)
				if codes[i] == "MINE":
					var site := Site.new()
					site.raw = "Iron"
					site.x1 = at.x
					site.y1 = at.y
					game.sites.append(site)
				var f := game.spawn_firm(codes[i], p.id, "NORMAN", at, i != 1)
				if i == 1:
					f.progress = 60.0
				f.selected = true
				f.queue_redraw()
			var grid := GridOverlay.new()
			grid.rect = Rect2i(base - Vector2i(2, 2), Vector2i(32, 10))
			game.add_child(grid)
			camera.iso_pos = Iso.to_screen(Vector2(base) + Vector2(14, 3))
			camera.zoom = Vector2(0.7, 0.7)
		"towns":
			# one town of every race, selected, over the location grid
			var base := Vector2i(12, 12)
			var area := Rect2i(base - Vector2i(2, 2), Vector2i(8 * 6 + 4, 8 * 2 + 4))
			for t in game.towns.duplicate():
				if area.intersects(t.footprint()):
					game.on_town_destroyed(t)
			for f in game.firms.duplicate():
				if area.intersects(f.footprint()):
					game.on_firm_destroyed(f, null)
			for u in game.units.duplicate():
				if area.has_point(u.cell()):
					game.remove_unit(u)
			for c in game._plants.keys():
				if area.has_point(c):
					game._plants[c].queue_free()
					game._plants.erase(c)
					game.world.set_plant(c, false)
			var made: Array = []
			for i in Defs.races.size():
				var at := base + Vector2i((i % 6) * 8, (i / 6) * 8)
				var t := game.spawn_town(Defs.races[i]["code"], p.id if i % 2 == 0 else 0, at, 20 + (i * 7) % 80)
				made.append(t)
			_set_selection(made)
			if "--walls" in OS.get_cmdline_user_args():
				for i in made.size():
					made[i].wall_level = i % 3
					made[i].wall_hp = made[i].wall_max_hp() * (1.0 if i < 6 else 0.4)
			var grid := GridOverlay.new()
			grid.rect = area
			game.add_child(grid)
			camera.iso_pos = Iso.to_screen(Vector2(base) + Vector2(24, 7))
			camera.zoom = Vector2(0.6, 0.6)
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--focus="):
					var t: Town = made[a.substr(8).to_int()]
					camera.iso_pos = Iso.to_screen(t.center_loc() + Vector2(2, 0))
					camera.zoom = Vector2(1.5, 1.5)
		"dirs":
			# eight soldiers each walking one way, to check sprite facings
			var home: Town = game.towns.filter(func(t): return t.nation_id == p.id)[0]
			var c := Vector2i(home.center_loc()) + Vector2i(-10, 10)
			for x in range(c.x - 8, c.x + 9):
				for y in range(c.y - 8, c.y + 9):
					var cc := Vector2i(x, y)
					if game._plants.has(cc):
						game._plants[cc].queue_free()
						game._plants.erase(cc)
						game.world.set_plant(cc, false)
			var steps := [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1)]
			var dbg := DirDebug.new()
			for i in 8:
				var spr := "NO_INF"
				for a in OS.get_cmdline_user_args():
					if a.begins_with("--dir-sprite="):
						spr = a.substr(13)
				var u := game.spawn_unit(spr, p.id, c + steps[i] * 2, 30.0)
				u.order_move(c + steps[i] * 7)
				dbg.pairs.append([u, Vector2(c + steps[i] * 7)])
			game.add_child(dbg)
			camera.iso_pos = Iso.to_screen(Vector2(c))
			camera.zoom = Vector2(1.3, 1.3)
		"destroy":
			# a burning camp and a building being destroyed, for effect checks
			var home: Town = game.towns.filter(func(t): return t.nation_id == p.id)[0]
			var b := Assets.firm_build("CAMP", p.race)
			var pos1 := game._place_near(home.footprint(), b["loc_w"], b["loc_h"], 8)
			var c1 := game.spawn_firm("CAMP", p.id, p.race, pos1, true)
			c1.hp = c1.max_hp * 0.08
			for i in 12:
				c1.next_day(i)
			var fort: Firm = game.firms.filter(func(x): return x.code == "FORT" and x.nation_id == p.id)[0]
			var timer := get_tree().create_timer(1.0)
			timer.timeout.connect(func(): fort.die(null))
			camera.iso_pos = Iso.to_screen((c1.center_loc() + fort.center_loc()) * 0.5)
			camera.zoom = Vector2(0.8, 0.8)
		"overview":
			camera.iso_pos = Iso.to_screen(Vector2(game.world.w, game.world.h) * 0.5)
			camera.zoom = Vector2(0.4, 0.4)
		"rocks":
			# close-up of the largest mountain group
			var best: Rock = null
			for rk in game.rocks:
				if rk.tex and (best == null or rk.w * rk.h > best.w * best.h):
					best = rk
			if best:
				camera.iso_pos = Iso.to_screen(Vector2(best.x1 + best.w / 2.0, best.y1 + best.h / 2.0))
				camera.zoom = Vector2(0.9, 0.9)
		"fryhtan":
			for i in 3000:
				game.sim_frame()
			var fry: Array = game.nations.filter(func(nn): return nn.is_fryhtan)
			if not fry.is_empty():
				var lairs: Array = game.firms.filter(func(f): return f.nation_id == fry[0].id)
				if not lairs.is_empty():
					var newest: Firm = lairs.back()
					camera.iso_pos = Iso.to_screen(newest.center_loc())
					_set_selection([newest])
			camera.zoom = Vector2(0.75, 0.75)
		"god":
			var home: Town = game.towns.filter(func(t): return t.nation_id == p.id)[0]
			var c := Vector2i(home.center_loc()) + Vector2i(-6, 8)
			var gi: Dictionary = Defs.gods["INDIAN"]
			var god := game.spawn_unit(gi["unit"], p.id, c, 100.0)
			p.prayer_points = 400.0
			god.cast_power()
			var rg: Dictionary = Defs.gods["ROMAN"]
			var god2 := game.spawn_unit(rg["unit"], p.id, c + Vector2i(4, -2), 100.0)
			god2.cast_power()
			_set_selection([god])
			camera.iso_pos = Iso.to_screen(Vector2(c))
			camera.zoom = Vector2(1.2, 1.2)
		"storm":
			game.weather.cloud_str = 10
			game.weather.cloud_type = Weather.RAIN_CLOUD | Weather.LIGHTNING_CLOUD
			game.weather.cloud_len = 99
			var home: Town = game.towns.filter(func(t): return t.nation_id == p.id)[0]
			camera.iso_pos = Iso.to_screen(home.center_loc())
			get_tree().create_timer(1.6).timeout.connect(func(): game._lightning_strike(); _on_lightning(camera.iso_pos + Vector2(-120, 60)))
		"reports":
			# the Reports window on a page (--report=0..6), after some days of play
			for i in Defs.FRAMES_PER_DAY * 120:
				game.sim_frame()
			hud.reports.open()
			for a in OS.get_cmdline_user_args():
				if a.begins_with("--report="):
					hud.reports.tabs.current_tab = a.substr(9).to_int()
			hud.reports.refresh()
		"specials":
			# every special building of the kingdom (Fryhtan or offensive), all techs known
			p.cash = 30000.0
			p.live_points = 30000.0
			var anchor: Rect2i
			var codes: Array
			if p.is_fryhtan:
				for t in Defs.FRYHTAN_TECHS:
					p.tech[t["code"]] = t["max"]
				anchor = game.firms.filter(func(f): return f.nation_id == p.id)[0].footprint()
				codes = Defs.FRYHTAN_FIRMS.filter(func(c): return c != "WLISHORR")   # it would turn on us
			else:
				for t in Defs.research_techs():
					if t.has("firm") or t["code"] in Defs.WEAPONS or t["code"].begins_with("SPU"):
						p.tech[t["code"]] = t["max"]
				anchor = game.towns.filter(func(t): return t.nation_id == p.id)[0].footprint()
				codes = Defs.OFFENSIVE_FIRMS
			var made: Array = []
			for code in codes:
				var b := Assets.firm_build(code, p.race)
				var at := game._place_near(anchor, b.get("loc_w", 4), b.get("loc_h", 4), 12)
				if at.x >= 0:
					var f := game.spawn_firm(code, p.id, p.race, at, true)
					if f:
						made.append(f)
			if p.is_fryhtan:
				var c := game._place_near(anchor, 4, 4, 14) + Vector2i(1, 1)
				var grok: Array = []
				for o in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
					grok.append(game.spawn_unit("GITH", p.id, c + o, 40.0))
				_set_selection(grok.filter(func(u): return u != null))
			elif not made.is_empty():
				_set_selection([made[0]])
			camera.iso_pos = Iso.to_screen(Vector2(anchor.get_center()))
			camera.zoom = Vector2(0.8, 0.8)
		"spies":
			var home: Town = game.towns.filter(func(t): return t.nation_id == p.id)[0]
			home.loyalty = 80.0
			var col := game.spawn_firm("SPY", p.id, p.race, game._place_near(home.footprint(), 5, 5, 8, [home.center_loc()]), true)
			game.update_links()
			var s1: Unit = null
			var s2: Unit = null
			for k in 2:
				Training.order_train(col, Training.CIVILIAN)
				col.trainees[-1]["training"] = false
				col.trainees[-1]["spy_skill"] = 40.0
			if col.trainees.size() == 2:
				s1 = Training.mobilize(col, 1)
				s2 = Training.mobilize(col, 0)
			var indep: Array = game.towns.filter(func(t): return t.nation_id == 0)
			if s1 and not indep.is_empty():
				game.spy_enter(s1, indep[0])
			# a spy inside an enemy fort, with the spying techs, to show the missions
			var foe_f: Array = game.firms.filter(func(f): return Espionage.is_camp(f) and f.nation_id != p.id and f.nation_id > 0 and f.overseer != null)
			if s2 and not foe_f.is_empty():
				for k in ["STEALINF", "BRIBE", "ASSASSIN", "STEALTEC", "INCIDENT", "AGITATE", "COUNTERS", "CAMOUFLG"]:
					p.tech[k] = 1
				s2.spy_skill = 95.0
				game.spy_enter(s2, foe_f[0])
				p.cash = 20000.0
				_set_selection([foe_f[0]])
				camera.iso_pos = Iso.to_screen(foe_f[0].center_loc())
			else:
				_set_selection([col])
				camera.iso_pos = Iso.to_screen(col.center_loc())
		"menus":
			# the build menu of a general and the pause menu, to look at the icons
			var gen2: Array = game.units.filter(func(u): return u.nation_id == p.id and u.rank == Defs.Rank.GENERAL)
			_set_selection([gen2[0]])
			hud.build_menu_open = true
			hud.refresh_selection(true)
			hud.toggle_pause_menu()
		"college":
			# an Espionage College with trainees, to show the training panel
			var home: Town = game.towns.filter(func(t): return t.nation_id == p.id)[0]
			home.loyalty = 80.0
			var col := game.spawn_firm("SPY", p.id, p.race, game._place_near(home.footprint(), 5, 5, 8, [home.center_loc()]), true)
			game.update_links()
			for k in 3:
				Training.order_train(col, [Training.CIVILIAN, Training.INFANTRY, Training.CIVILIAN][k])
			if not col.trainees.is_empty():
				col.trainees[0]["training"] = false
				col.trainees[0]["spy_skill"] = 35.0
			_set_selection([col])
			camera.iso_pos = Iso.to_screen(col.center_loc())
		"gallery":
			# every work building in all four architectural styles, for visual checks
			var base := Vector2i(10, 10)
			var codes := ["MINE", "FACTORY", "WAR", "INN", "RESEARCH", "MARKET"]
			var races := ["NORMAN", "ROMAN", "CHINESE", "EGYPTIAN"]
			if "--stables" in OS.get_cmdline_user_args():
				codes = ["STABLE", "STABLE", "STABLE", "STABLE"]
				races = ["NORMAN", "VIKING", "CELTIC"]
			for ri in races.size():
				for ci in codes.size():
					var at := base + Vector2i(ci * 8, ri * 8)
					game.world.release(at.x - 1, at.y - 1, 9, 9)
					if codes[ci] == "MINE":
						var site := Site.new()
						site.raw = "Iron"
						site.x1 = at.x
						site.y1 = at.y
						site.reserve = 5000
						game.sites.append(site)
					var race_code: String = races[ri]
					if "--stables" in OS.get_cmdline_user_args():
						race_code = Defs.races[(ri * 4 + ci) % 12]["code"]
					var f := game.spawn_firm(codes[ci], p.id, race_code, at, true)
					if f:
						f.anim_index = 2 % maxi(1, f.build["frames"].size())
			camera.iso_pos = Iso.to_screen(Vector2(base) + Vector2(22, 14))
			camera.zoom = Vector2(0.55, 0.55)
			if "--outline" in OS.get_cmdline_user_args():
				_set_selection(game.firms.filter(func(x): return x.nation_id == p.id))
		"build":
			var gen: Array = game.units.filter(func(u): return u.nation_id == p.id and u.rank == Defs.Rank.GENERAL)
			_set_selection([gen[0]])
			_begin_build("CAMP")
			Input.warp_mouse(Vector2(450, 520))


var _shot_path := ""
var _shot_after := 4.0


func _take_shot() -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_shot_path)
	get_tree().quit()


func _show_menu() -> void:
	_teardown()
	campaign = null
	if Net.active:
		Net.leave()
	menu = MainMenu.new()
	add_child(menu)
	menu.start_game.connect(_start)
	menu.load_game.connect(func(slot): load_game.call_deferred(slot))
	menu.start_campaign.connect(func(race, diff):
		campaign = Campaign.new()
		campaign.init_new(race, diff, randi())
		campaign.save()
		_show_campaign())
	menu.continue_campaign.connect(func():
		campaign = Campaign.load_saved()
		if campaign:
			_show_campaign()
		else:
			menu.status.text = "The saved campaign could not be read.")


# ------------------------------------------------------------ campaign ---

var campaign: Campaign = null
var campaign_screen: CampaignScreen = null


## The strategic screen; with `result` it first applies a finished battle.
func _show_campaign(result: Dictionary = {}) -> void:
	_teardown()
	campaign_screen = CampaignScreen.new()
	campaign_screen.campaign = campaign
	add_child(campaign_screen)
	campaign_screen.start_battle.connect(_start_campaign_battle, CONNECT_DEFERRED)
	campaign_screen.back_to_menu.connect(_show_menu, CONNECT_DEFERRED)
	if result.is_empty():
		campaign_screen.run()
	else:
		campaign_screen.after_battle(result["won"], result["win_id"], result["lose_id"], result["years"])


func _start_campaign_battle() -> void:
	var cb := CampaignBattle.create(campaign)
	_start({"campaign_battle": cb, "seed": campaign.rng.randi()})
	game.config.erase("campaign_battle")
	game.config["campaign"] = true
	_attach_campaign()
	var goals := game.goals.win.map(func(c): return c["text"])
	game.notify("%s. Your goal%s: %s." % [campaign.stage_name(), "s" if game.goals.require_all and goals.size() > 1 else "",
		(" and " if game.goals.require_all else " or ").join(goals)], Vector2(-1, -1))


## A campaign battle's end leads back to the strategic screen.
func _attach_campaign() -> void:
	if game.campaign_battle == null:
		return
	if campaign == null:
		campaign = game.campaign_battle.c
	game.game_over.connect(func(victory: bool, _text: String):
		var won := victory
		var info: Dictionary = game.campaign_battle.result_info()
		campaign.stage_vars["hero_alive"] = info["hero_alive"]
		campaign.stage_vars["kill_monster_score"] = info["kill_monster_score"]
		var result := {"won": won, "win_id": game.goals.won_id if game.goals else -1,
			"lose_id": game.goals.lost_id if game.goals else Goals.DEFEAT_OWN_KINGDOM, "years": game.day / 365 + 1}
		if won:
			campaign.update_royals(game)
		hud.set_campaign_continue(campaign.end_text(won, result["win_id"], result["lose_id"]),
			func(): _show_campaign.call_deferred(result)), CONNECT_DEFERRED)


func _teardown() -> void:
	# an unfinished game: the heroes it took from the roster come back (or not)
	if game and is_instance_valid(game) and not game.over and game.config.get("bring_roster", false):
		Roster.settle(game, false)
	for n in [hud, game, camera, view3d, overlay_layer, select_layer, menu, campaign_screen]:
		if n and is_instance_valid(n):
			n.queue_free()
	hud = null
	game = null
	camera = null
	view3d = null
	overlay_layer = null
	menu = null
	campaign_screen = null
	ghost = null
	build_code = ""


func _start(cfg: Dictionary) -> void:
	_teardown()
	game = Game.new()
	if cfg.has("mp"):
		# a network game: this machine leads one of the players' kingdoms
		game.player_id = Net.nation_of(Net.my_id())
		Net.game = game
	add_child(game)
	game.start(cfg)
	_attach_game()
	if cfg.get("bring_roster", false) and not cfg.has("mp") and not cfg.has("tutorial") and cfg.get("campaign_battle") == null:
		var came := Roster.bring(game)
		if came > 0:
			game.notify("%d hero%s of yours %s joined you." % [came, "" if came == 1 else "es", "has" if came == 1 else "have"], Vector2(-1, -1))
	if not cfg.has("mp") and not cfg.has("tutorial") and cfg.get("campaign_battle") == null and Profiles.current() != "":
		game.game_over.connect(func(victory: bool, _t: String): Roster.settle(game, victory))
	if cfg.get("autoplay", false):
		game.notify("AI against AI: every kingdom is computer-controlled. Sit back and watch.", Vector2(-1, -1))
	if not cfg.get("autoplay", false) and not cfg.has("mp") and not cfg.has("tutorial") and not cfg.get("editor", false) 			and not cfg.get("no_tips", false) and TipsBox.enabled() and not Array(OS.get_cmdline_user_args()).any(func(a): return a.begins_with("--shot") or a.begins_with("--demo")):
		var tb := TipsBox.new()
		var section := "CAMPAIGN" if game.campaign_battle != null else ("FRYHTAN" if game.player() and game.player().is_fryhtan else "HUMAN")
		if tb.setup(section, randi()):
			hud.ui_root.add_child(tb)
		else:
			tb.free()
	if cfg.get("autoplay", false):
		pass
	elif cfg.get("editor", false):
		game.reveal_all = true
		game._update_fog()
		var ed := hud.open_editor()
		ed.tool_selected.connect(func(t): _editor_tool = t)
		ed.play_requested.connect(func(path): _start.call_deferred({"scenario": path, "seed": randi()}))
		game.notify("Scenario editor: time stands still while you shape the land.", Vector2(-1, -1))
	elif cfg.has("tutorial"):
		var tut := Tutorial.new()
		tut.setup(game, int(cfg["tutorial"]))
		hud.start_tutorial(tut)
		game.fast_build = int(cfg["tutorial"]) in [1, 2, 4, 9]      # Tutor::set_fast_build
	elif cfg.has("mp"):
		var others := game.nations.filter(func(n): return n.is_player and n.id != game.player_id).map(func(n): return n.name)
		game.notify("A network game with %s. Press Enter to send a message." % ", ".join(others), Vector2(-1, -1))
	elif game.goals:
		var goals := game.goals.win.filter(func(c): return c["supported"]).map(func(c): return c["text"])
		game.notify("Welcome, ruler of the %s. Your goal%s: %s." % [game.player().name, "s" if game.goals.require_all and goals.size() > 1 else "",
			(" and " if game.goals.require_all else " or ").join(goals)], Vector2(-1, -1))
	else:
		game.notify("Welcome, ruler of the %s. Expand your realm and defeat the rival kingdoms!" % game.player().name, Vector2(-1, -1))


## Loads a saved game ("quick", "autosave" ...) and resumes play.
func load_game(slot: String) -> bool:
	if Net.active:
		return false
	if not SaveGame.exists(slot):
		if game:
			game.notify("No saved game to load.", Vector2(-1, -1))
		return false
	_teardown()
	game = Game.new()
	add_child(game)
	var err := SaveGame.load_into(game, slot)
	if err != "":
		push_error(err)
		_show_menu()
		menu.status.text = err
		return false
	_attach_game()
	_attach_campaign()
	game.notify("Game loaded (%s)." % game.date_string(), Vector2(-1, -1))
	return true


func save_game(slot: String) -> void:
	if game == null or game.over:
		return
	if Net.active:
		game.notify("A network game cannot be saved.", Vector2(-1, -1))
		return
	if SaveGame.save(game, slot):
		if slot != "autosave":
			game.notify("Game saved.", Vector2(-1, -1))
	else:
		game.notify("Could not save the game!", Vector2(-1, -1))


var _last_autosave_year := -1
var _shake := 0.0


## Camera, HUD and input layers around a started or loaded game.
func _attach_game() -> void:
	_last_autosave_year = game.day / 365
	camera = CameraRig.new()
	add_child(camera)
	camera.make_current()
	sfx.camera = camera
	# the world is shown in 3D; the simulation's 2D nodes only provide the drawing
	game.visible = false
	view3d = View3D.new()
	add_child(view3d)
	overlay_layer = CanvasLayer.new()
	overlay_layer.layer = 0
	var overlay := View3DOverlay.new()
	overlay_layer.add_child(overlay)
	add_child(overlay_layer)
	view3d.setup(game, camera, overlay)
	# 3D models replacing the sprite cards: off for now, the original sprites are the
	# look of the game; --models turns them on
	if ResourceLoader.exists(MODEL_LIBRARY) and "--models" in OS.get_cmdline_user_args():
		view3d.model_provider = load(MODEL_LIBRARY).new()
		# with models the camera is free; sprites alone hold it to quarter turns
		camera.set_free(true)
	game.shake.connect(func(strength): _shake = maxf(_shake, strength))
	game.sound_event.connect(func(k, c, a, wp): sfx.play_event(k, c, a, wp))
	var p := game.player()
	var home: Array = game.towns.filter(func(t): return t.nation_id == p.id)
	if home.is_empty():
		home = game.firms.filter(func(f): return f.nation_id == p.id)
	if not home.is_empty():
		camera.iso_pos = Iso.to_screen(home[0].center_loc()) + Vector2(150, 0)
	ghost = BuildGhost.new()
	game.add_child(ghost)
	ghost.visible = false
	view3d.extra_nodes = [ghost]
	hud = Hud.new()
	add_child(hud)
	hud.setup(game, camera)
	hud.build_requested.connect(_begin_build)
	hud.item_target_requested.connect(func(u):
		_item_user = u
		game.notify("Click the target for the %s; right-click to cancel." % Items.item_name(u.item_id), Vector2(-1, -1)))
	hud.cast_target_requested.connect(func(u):
		_cast_god = u
		game.notify("Click where the Greater Being should cast his power; right-click to cancel.", Vector2(-1, -1)))
	hud.found_town_requested.connect(func(u):
		_found_town_unit = u
		game.notify("Click where the new town should stand; right-click to cancel.", Vector2(-1, -1)))
	hud.caravan_route_requested.connect(func(u, i):
		_route_stop = i
		_route_caravan = u
		game.notify("Click the market this caravan should trade with; right-click to cancel.", Vector2(-1, -1)))
	hud.rally_requested.connect(func(f):
		_rally_firm = f
		game.notify("Click where the units made here should gather; right-click to cancel.", Vector2(-1, -1)))
	hud.spell_target_requested.connect(func(f, sp):
		_spell_firm = f
		_spell_code = sp
		_spell_unit = null
		game.notify("Click %s; right-click to cancel." % ("the unit to teleport" if sp == "TELEPORT" else "the target"), Vector2(-1, -1)))
	hud.center_on.connect(func(l): camera.iso_pos = Iso.to_screen(l))
	hud.menu_new_game.connect(_show_menu)
	hud.move_selected_to.connect(func(l):
		var own: Array = game.selected.filter(func(o): return o is Unit and o.nation_id == game.player_id and not o.dead and o.inside_firm == null)
		if not own.is_empty():
			sfx.play_event("S", own[0].sprite_code, "ACK")
			_formation_move(own, Vector2i(l.floor())))
	hud.save_requested.connect(func(): save_game("quick"))
	hud.load_requested.connect(func(): load_game.call_deferred("quick"))
	select_layer = CanvasLayer.new()
	select_layer.layer = 5
	add_child(select_layer)
	var weather_layer := CanvasLayer.new()
	weather_layer.layer = 1
	select_layer.add_child(weather_layer)
	hud.layer = 3
	rain_layer = RainLayer.new()
	rain_layer.game = game
	weather_layer.add_child(rain_layer)
	game.lightning.connect(_on_lightning)
	select_box = SelectBox.new()
	select_layer.add_child(select_box)
	if _music_files.is_empty():
		_music_files = Assets.music_files()
	if music.stream == null and not "--nomusic" in OS.get_cmdline_user_args():
		_next_track()


# ----------------------------------------------------------------- music ---

func _next_track() -> void:
	if not _music_on or _music_files.is_empty() or _music_thread != null:
		return
	var path: String = _music_files[randi() % _music_files.size()]
	_music_thread = Thread.new()
	_music_thread.start(_load_track.bind(path))


## Runs on the loader thread; WAV files are large, so decode off the main thread.
func _load_track(path: String) -> void:
	var s := Assets.load_wav(path)
	_play_stream.call_deferred(s)


func _play_stream(s: AudioStreamWAV) -> void:
	if _music_thread:
		_music_thread.wait_to_finish()
		_music_thread = null
	if s and _music_on:
		music.stream = s
		music.play()


func _exit_tree() -> void:
	if _music_thread:
		_music_thread.wait_to_finish()
		_music_thread = null


# --------------------------------------------------------------- camera ---

func _process(delta: float) -> void:
	if game == null or camera == null:
		return
	var v := Vector2.ZERO
	var ctrl := Input.is_key_pressed(KEY_CTRL)
	if Input.is_key_pressed(KEY_LEFT):
		v.x -= 1
	if Input.is_key_pressed(KEY_RIGHT):
		v.x += 1
	if Input.is_key_pressed(KEY_UP) and not ctrl:
		v.y -= 1
	if Input.is_key_pressed(KEY_DOWN) and not ctrl:
		v.y += 1
	var mp := get_viewport().get_mouse_position()
	var vs := get_viewport().get_visible_rect().size
	if DisplayServer.window_is_focused() and Rect2(Vector2.ZERO, vs).has_point(mp):
		if mp.x < EDGE_SCROLL:
			v.x -= 1
		elif mp.x > vs.x - EDGE_SCROLL:
			v.x += 1
		if mp.y < EDGE_SCROLL:
			v.y -= 1
		elif mp.y > vs.y - EDGE_SCROLL:
			v.y += 1
	# World::detect_scroll: "Comfort" moves a location at a time, every
	# 500/(speed+1) ms; "Speed" glides at speed/500 locations a millisecond
	var spd := float(GameOptions.get_opt("scroll_speed"))
	if v == Vector2.ZERO:
		_scroll_wait = 0.0
	elif int(GameOptions.get_opt("scroll_method")) == 0:
		_scroll_wait -= delta
		if _scroll_wait <= 0.0:
			_scroll_wait = 0.5 / (spd + 1.0)
			camera.pan(v.normalized() * LOC_PIXELS)
	else:
		camera.pan(v.normalized() * minf(spd / 0.5 * delta, 2.0) * LOC_PIXELS)
	music.volume_db = -10.0 + linear_to_db(maxf(0.001, float(GameOptions.get_opt("music_volume")) / 100.0))
	camera.clamp_to(game.world.w, game.world.h)
	if Engine.get_process_frames() % 6 == 0:
		game.hovered = _pick()
	_update_ghost()
	if _shake > 0.1:
		camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake
		_shake *= 0.9
	else:
		camera.offset = Vector2.ZERO
	_update_rain_sound()
	if game.day / 365 != _last_autosave_year and not game.over:
		_last_autosave_year = game.day / 365
		save_game("autosave")


var _mouse_pos := Vector2.ZERO     # last mouse position seen in an input event (viewport pixels)


func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_mouse_pos = (event as InputEventMouse).position


func _update_rain_sound() -> void:
	var raining := game.weather.rain_scale() > 0 and not game.paused and sfx.enabled
	if raining and not rain_player.playing:
		var s := Assets.ambient_sound("rain.wav")
		if s:
			s.loop_mode = AudioStreamWAV.LOOP_FORWARD
			s.loop_end = s.data.size() / (2 * (2 if s.stereo else 1))
			rain_player.stream = s
			rain_player.play()
	elif not raining and rain_player.playing:
		rain_player.stop()


func _on_lightning(world_pos: Vector2) -> void:
	var view := Rect2(camera.iso_pos - get_viewport().get_visible_rect().size / camera.zoom * 0.6, get_viewport().get_visible_rect().size / camera.zoom * 1.2)
	if not view.has_point(world_pos):
		return
	rain_layer.lightning_flash()
	var bolt := LightningBolt.new()
	bolt.setup(world_pos)
	game.effects.add_child(bolt)
	if sfx.enabled:
		var t := Assets.ambient_sound("thunder.WAV")
		if t:
			var p := AudioStreamPlayer.new()
			p.stream = t
			p.volume_db = -8.0
			add_child(p)
			p.finished.connect(p.queue_free)
			p.play()


func _world_mouse() -> Vector2:
	return Iso.to_screen(camera.screen_to_loc(_mouse_pos))


## The object under the mouse: units by their on-screen figure, then whatever
## building, town or site stands on the ground location under the cursor.
func _pick() -> GameObj:
	var best: GameObj = null
	var best_d := 26.0 * camera.zoom.x
	for u in game.units:
		if u.dead or u.inside_firm or not u.visible:
			continue
		var d := _mouse_pos.distance_to(camera.iso_to_screen(u.position) + Vector2(0, -6) * camera.zoom.x)
		if d < best_d:
			best_d = d
			best = u
	if best:
		return best
	return game.object_at_screen(_world_mouse())


func _use_item_on_click() -> void:
	var u := _item_user
	_item_user = null
	if not is_instance_valid(u) or u.dead or u.item_id == 0:
		return
	var target = null
	if Items.MANUAL_TARGET.get(u.item_id, "") == "place":
		var l := _mouse_loc()
		target = Vector2i(floori(l.x), floori(l.y))
	else:
		target = _pick()
	Net.cmd(u, "use_item_cmd", [target])
	hud.refresh_selection(true)


## Aim a Mage Tor or offensive building's spell at the clicked place.
func _cast_on_click() -> void:
	var f := _spell_firm
	if not is_instance_valid(f) or f.dead:
		_spell_firm = null
		return
	if _spell_code == "TELEPORT" and _spell_unit == null:
		var u := _pick()
		if u is Unit and u.nation_id == game.player_id:
			_spell_unit = u
			game.notify("Now click where to send it.", Vector2(-1, -1))
		else:
			game.notify("Click one of your units.", Vector2(-1, -1))
		return
	var at := _mouse_loc()
	var o := _pick()
	if o and _spell_code == "DESTROY":
		at = o.center_loc()
	Net.cmd(SpecialFirms, "cast", [f, _spell_code, at, _spell_unit])
	_spell_firm = null
	_spell_unit = null
	hud.refresh_selection(true)


func _mouse_loc() -> Vector2:
	return Iso.to_loc(_world_mouse())


# ---------------------------------------------------------------- build ---

func _begin_build(code: String) -> void:
	# "BASE|GREEK": a Seat of Power of another race whose Scroll of Power we hold
	build_race = code.get_slice("|", 1) if code.contains("|") else game.player().race
	code = code.get_slice("|", 0)
	build_code = code
	ghost.visible = true
	game.notify("Place the %s. Left-click to build, right-click to cancel." % Defs.firm_types.get(code, {}).get("name", "Lair" if code == "LAIR" else code), Vector2(-1, -1))


func _placement() -> Dictionary:
	var p := game.player()
	var b := Assets.firm_build(build_code, build_race if build_race != "" else p.race)
	var w: int = b.get("loc_w", 3)
	var h: int = b.get("loc_h", 3)
	var loc := _mouse_loc()
	var pos := Vector2i(floori(loc.x - w / 2.0), floori(loc.y - h / 2.0))
	var ok := false
	if build_code == "MINE":
		var s := game.site_at_rect(Rect2i(Vector2i(floori(loc.x), floori(loc.y)), Vector2i.ONE))
		if s:
			pos = Vector2i(s.x1, s.y1)
			ok = s.mine == null and game.world.can_place(pos.x, pos.y, w, h, true)
	else:
		var r := Rect2i(pos, Vector2i(w, h))
		var site_ok := not game._overlaps_site(r)
		if build_code == "ALCHEMY":
			var st := game.site_at_rect(r)
			site_ok = st == null or st.mine == null
		ok = game.world.can_place(pos.x, pos.y, w, h) and site_ok and game.is_loc_explored(r.get_center())
	return {"build": b, "pos": pos, "ok": ok}


func _update_ghost() -> void:
	if build_code == "" or ghost == null:
		return
	var pl := _placement()
	ghost.set_state(pl["build"], pl["pos"], pl["ok"], game.player().color)


func _place_building() -> void:
	var pl := _placement()
	if not pl["ok"]:
		game.notify("Cannot build there." if build_code != "MINE" else "Mines must be built on a raw-material deposit.", Vector2(-1, -1))
		return
	var p := game.player()
	var cost := float(Defs.firm_types.get(build_code, {}).get("cost", 0))
	var live := SpecialFirms.setup_live(build_code) if p.is_fryhtan else 0.0
	if build_code == "LAIR":
		cost = FryhtanAI.LAIR_COST
		live = FryhtanAI.LAIR_LIVE
	if live > 0.0 and p.live_points < live:
		game.notify("Not enough life points.", Vector2(-1, -1))
		return
	if not p.can_afford(cost):
		game.notify("Not enough gold.", Vector2(-1, -1))
		return
	var builders: Array = game.selected.filter(func(o): return o is Unit and o.nation_id == p.id and (o.is_human() or p.is_fryhtan) and not o.dead and not o.is_god)
	if builders.is_empty():
		game.notify("Select a unit to construct the building.", Vector2(-1, -1))
		_cancel_build()
		return
	var b := pl["build"] as Dictionary
	var c := Vector2(pl["pos"]) + Vector2(b.get("loc_w", 3), b.get("loc_h", 3)) * 0.5
	builders.sort_custom(func(a, bb): return a.center_loc().distance_to(c) < bb.center_loc().distance_to(c))
	Net.cmd(game, "cmd_place_building", [p.id, build_code, build_race if build_race != "" else p.race, pl["pos"], builders[0], cost, live, p.monster_code])
	if not Input.is_key_pressed(KEY_SHIFT):
		_cancel_build()


func _cancel_build() -> void:
	build_code = ""
	if ghost:
		ghost.visible = false
		ghost.build = {}


# ---------------------------------------------------------------- input ---

func _unhandled_input(event: InputEvent) -> void:
	if game == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if hud.is_over_ui(mb.position) and mb.pressed:
			return
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					camera.zoom = (camera.zoom * 1.1).clamp(Vector2(0.35, 0.35), Vector2(2, 2))
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					camera.zoom = (camera.zoom / 1.1).clamp(Vector2(0.35, 0.35), Vector2(2, 2))
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					if build_code != "":
						_place_building()
						return
					if _item_user != null:
						_use_item_on_click()
						return
					if _spell_firm != null:
						_cast_on_click()
						return
					if _cast_god != null:
						if is_instance_valid(_cast_god) and not _cast_god.dead:
							var cl := _mouse_loc()
							Net.cmd(_cast_god, "order_cast_power", [Vector2i(floori(cl.x), floori(cl.y))])
						_cast_god = null
						return
					if _found_town_unit != null:
						var l := _mouse_loc()
						var site := Vector2i(floori(l.x) - Defs.TOWN_SIZE / 2, floori(l.y) - Defs.TOWN_SIZE / 2)
						if is_instance_valid(_found_town_unit) and not _found_town_unit.dead:
							if game.can_build_town(site):
								Net.cmd(_found_town_unit, "order_found_town", [site])
							else:
								game.notify("A town cannot be built there.", Vector2(-1, -1))
						_found_town_unit = null
						return
					if _route_caravan != null:
						var mk = game.object_at_screen(_world_mouse())
						if mk is Firm and is_instance_valid(_route_caravan) and not _route_caravan.dead:
							if Caravans.can_set_stop(_route_caravan, mk):
								Net.cmd(_route_caravan, "set_caravan_stop", [_route_stop, mk])
								game.notify("Stop %d: %s." % [_route_stop + 1, mk.display_name()], Vector2(-1, -1))
							else:
								game.notify("A caravan stops at your markets, mines and factories, and at markets of kingdoms you have a trade treaty with.", Vector2(-1, -1))
						_route_caravan = null
						return
					if _rally_firm != null:
						if is_instance_valid(_rally_firm) and not _rally_firm.dead:
							Net.cmd(_rally_firm, "set_rally", [Vector2i(_mouse_loc().floor())])
							game.notify("Rally point set.", Vector2(-1, -1))
						_rally_firm = null
						return
					if not _editor_tool.is_empty() and hud.editor:
						var l := _mouse_loc()
						if not hud.editor.place(_editor_tool, Vector2i(floori(l.x), floori(l.y))):
							game.notify("Cannot place it there.", Vector2(-1, -1))
						return
					_left_down = true
					_drag_from = mb.position
					_dragging = false
				elif _left_down:
					_left_down = false
					if _dragging:
						_box_select(_drag_from, mb.position, mb.shift_pressed)
					elif mb.double_click or Time.get_ticks_msec() - _last_click_ms < 350:
						_select_same_type()
					else:
						_click_select(mb.shift_pressed)
					_last_click_ms = Time.get_ticks_msec()
					_dragging = false
					select_box.hide_rect()
			MOUSE_BUTTON_MIDDLE:
				_orbiting = mb.pressed
			MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					if build_code != "":
						_cancel_build()
					elif _item_user != null:
						_item_user = null
					elif _spell_firm != null:
						_spell_firm = null
					elif _rally_firm != null:
						_rally_firm = null
					elif _route_caravan != null:
						_route_caravan = null
					elif _found_town_unit != null:
						_found_town_unit = null
					elif _cast_god != null:
						_cast_god = null
					elif not _editor_tool.is_empty():
						_editor_tool = {}
					else:
						_command(mb.ctrl_pressed)
	elif event is InputEventMouseMotion and _orbiting:
		camera.orbit((event as InputEventMouseMotion).relative)
	elif event is InputEventMouseMotion and _left_down:
		var mm := event as InputEventMouseMotion
		if mm.position.distance_to(_drag_from) > 6:
			_dragging = true
			select_box.show_rect(_drag_from, mm.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		match k.keycode:
			KEY_ENTER, KEY_KP_ENTER:
				hud.open_chat()
			KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4, KEY_KP_6, KEY_KP_7, KEY_KP_8, KEY_KP_9:
				# the number pad turns a general's troop to face that way
				var troop := game.selected.filter(func(u): return u is Unit and u.nation_id == game.player_id)
				var gen := troop.filter(func(u): return u.rank >= Defs.Rank.GENERAL)
				if not gen.is_empty():
					Net.cmd(game, "form_troop", [troop, maxi(gen[0].formation, 2), Formations.NUMPAD[k.keycode]])
			KEY_SPACE, KEY_P:
				hud._set_speed(0.0)
			KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F8:
				# the original's report hotkeys (HELP.RES): Kingdoms F1, Towns F2,
				# Economy F3, Trade F4, Military F5, Technology F6, Ranking F8
				hud.reports.show_tab({KEY_F1: "Kingdoms", KEY_F2: "Towns", KEY_F3: "Economy", KEY_F4: "Trade",
					KEY_F5: "Military", KEY_F6: "Technology", KEY_F8: "Kingdoms"}[k.keycode])
			KEY_F7:
				hud.toggle_spies()
			KEY_F9:
				load_game.call_deferred("quick")
			KEY_ESCAPE:
				if build_code != "":
					_cancel_build()
				elif hud.build_menu_open:
					hud.build_menu_open = false
				elif not game.selected.is_empty():
					_set_selection([])
				else:
					hud.toggle_pause_menu()
			KEY_EQUAL, KEY_KP_ADD:
				hud._set_speed(minf(4.0, game.speed * 2.0))
			KEY_MINUS, KEY_KP_SUBTRACT:
				hud._set_speed(maxf(1.0, game.speed / 2.0))
			KEY_BRACKETLEFT:
				camera.turn(-1)
			KEY_BRACKETRIGHT:
				camera.turn(1)
			KEY_UP:
				if k.ctrl_pressed:
					camera.tilt(5.0)
			KEY_DOWN:
				if k.ctrl_pressed:
					camera.tilt(-5.0)
			KEY_TAB:
				# Tab: stop all selected units
				for u in game.selected:
					if u is Unit and u.nation_id == game.player_id:
						Net.cmd(u, "stop")
			KEY_COMMA, KEY_PERIOD:
				# the tutorial's previous / next text block
				if hud.tutorial_panel and hud.tutorial_panel.tutorial:
					hud.tutorial_panel.turn_page(-1 if k.keycode == KEY_COMMA else 1)
			KEY_PAGEUP, KEY_PAGEDOWN, KEY_HOME, KEY_END:
				# World::disp_next: the previous / next object of the selected one's kind,
				# of any kingdom (Page Up/Down) or of the same kingdom (Home/End)
				if not game.config.has("tutorial") or k.keycode in [KEY_HOME, KEY_END]:
					_disp_next(-1 if k.keycode in [KEY_PAGEUP, KEY_HOME] else 1, k.keycode in [KEY_HOME, KEY_END])
			_:
				if k.keycode == KEY_S and k.ctrl_pressed:
					save_game("quick")
				elif k.keycode >= KEY_A and k.keycode <= KEY_Z and not k.ctrl_pressed and not k.alt_pressed:
					_letter_key(k.keycode, k.shift_pressed)
				if k.keycode >= KEY_1 and k.keycode <= KEY_9:
					var gi := k.keycode - KEY_1
					if k.ctrl_pressed:
						_groups[gi] = game.selected.filter(func(o): return o is Unit)
					elif _groups.has(gi):
						_set_selection(_groups[gi].filter(func(o): return is_instance_valid(o) and not o.dead))


# --------------------------------------------------------------- hotkeys ---
# Sys::detect_key: the letter keys find your buildings and units one after
# another, as in the original.

const LOCATE_FIRMS := {
	KEY_D: ["BASE"], KEY_E: ["SPY"], KEY_F: ["FORT", "CAMP", "LAIR", "FORTRESS"],
	KEY_H: ["STABLE", "BEE", "TERMITE"], KEY_I: ["INN", "ANIMAL"], KEY_M: ["MARKET"],
	KEY_N: ["MAGIC", "LISHORR", "OFF_BLD1", "OFF_BLD2", "OFF_BLD3", "OFF_BLD4"],
	KEY_T: ["RESEARCH"], KEY_U: ["MINE", "ALCHEMY"], KEY_V: ["WAR", "INCUBAT"], KEY_B: ["FACTORY"],
}
var _cycle := {}       # key -> index of the last object found


func _letter_key(key: int, shift: bool) -> void:
	var p := game.player()
	var own := func(o): return is_instance_valid(o) and not o.dead and o.nation_id == p.id
	match key:
		KEY_A:
			_locate(key, game.treasures.filter(func(t): return is_instance_valid(t) and game.is_loc_explored(t.cell)))
		KEY_B:
			# b: keep only the bees of the selection, or find a factory; B: drop the bees
			var bees := game.selected.filter(func(u): return u is Unit and u.sprite_code == "BEE")
			if shift:
				_set_selection(game.selected.filter(func(u): return not (u is Unit and u.sprite_code == "BEE")))
			elif not bees.is_empty() and bees.size() < game.selected.size():
				_set_selection(bees)
			else:
				_locate(key, game.firms.filter(func(f): return own.call(f) and f.code in LOCATE_FIRMS[key]))
		KEY_C:
			_locate(key, game.units.filter(func(u): return own.call(u) and u.is_caravan))
		KEY_G, KEY_K:
			var rank := Defs.Rank.GENERAL if key == KEY_G else Defs.Rank.KING
			_locate(key, game.units.filter(func(u): return own.call(u) and u.rank == rank))
		KEY_J:
			_locate(key, game.sites.filter(func(s): return game.is_loc_explored(Vector2i(s.x1, s.y1))))
		KEY_L:
			load_game.call_deferred("quick")
		KEY_O:
			hud.toggle_options()
		KEY_Q:
			hud.minimap.set_mode((hud.minimap.mode + 1) % 3)
		KEY_R:
			_locate(key, game.units.filter(func(u): return own.call(u) and u.has_meta("royal")))
		KEY_S:
			save_game("quick")
		KEY_W:
			_locate(key, game.units.filter(func(u): return own.call(u) and u.is_wagon()))
		KEY_X:
			hud.clear_messages()
		KEY_Y:
			_locate(key, game.units.filter(func(u): return own.call(u) and u.is_spy))
		KEY_Z:
			# find a Greater Being; with one selected, it casts its power
			var sel = game.selected[0] if game.selected.size() == 1 else null
			if sel is Unit and sel.is_god and sel.nation_id == p.id and sel.can_cast_power():
				Net.cmd(sel, "cast_power")
			else:
				_locate(key, game.units.filter(func(u): return own.call(u) and u.is_god))
		_:
			if LOCATE_FIRMS.has(key):
				_locate(key, game.firms.filter(func(f): return own.call(f) and f.code in LOCATE_FIRMS[key]))


## Selects and centres on the next of `objs`, round and round.
func _locate(key: int, objs: Array) -> void:
	if objs.is_empty():
		return
	var i: int = (int(_cycle.get(key, -1)) + 1) % objs.size()
	_cycle[key] = i
	var o = objs[i]
	var at: Vector2 = o.inside_firm.center_loc() if o is Unit and o.inside_firm else (Vector2(o.cell) + Vector2(0.5, 0.5) if o is Treasure else (Vector2(o.x1 + o.w / 2.0, o.y1 + o.h / 2.0) if o is Site else o.center_loc()))
	camera.iso_pos = Iso.to_screen(at)
	if o is GameObj and not (o is Unit and o.inside_firm):
		_set_selection([o])


## World::disp_next: step through the objects of the selected one's kind.
func _disp_next(step: int, same_nation: bool) -> void:
	if game.selected.is_empty():
		return
	var cur = game.selected[0]
	var pool: Array = []
	if cur is Unit:
		pool = game.units.filter(func(u): return not u.dead and u.inside_firm == null and u.visible and u.sprite_code == cur.sprite_code)
	elif cur is Firm:
		pool = game.firms.filter(func(f): return not f.dead and f.visible and f.code == cur.code)
	elif cur is Town:
		pool = game.towns.filter(func(t): return not t.dead and t.visible)
	if same_nation:
		pool = pool.filter(func(o): return o.nation_id == cur.nation_id)
	var i := pool.find(cur)
	if pool.is_empty() or i < 0:
		return
	var nxt = pool[posmod(i + step, pool.size())]
	_set_selection([nxt])
	camera.iso_pos = Iso.to_screen(nxt.center_loc())


func _center_home() -> void:
	var p := game.player()
	if p.king and is_instance_valid(p.king) and not p.king.dead:
		var at: Vector2 = p.king.inside_firm.center_loc() if p.king.inside_firm else p.king.center_loc()
		camera.iso_pos = Iso.to_screen(at)


func _set_selection(objs: Array) -> void:
	for o in game.selected:
		if is_instance_valid(o):
			o.selected = false
			o.queue_redraw()
	game.selected = objs
	for o in objs:
		o.selected = true
		o.queue_redraw()
	hud.build_menu_open = false
	if not objs.is_empty() and objs[0].nation_id == game.player_id:
		if objs[0] is Unit:
			sfx.play_event("S", objs[0].sprite_code, "SEL")
		elif objs[0] is Firm:
			sfx.play_event("F", objs[0].code, "SEL")


func _click_select(add: bool) -> void:
	var o := _pick()
	hud.inspected_treasure = null
	if o == null:
		if not add:
			_set_selection([])
			hud.inspected_treasure = _treasure_at_mouse()
		return
	if add and o is Unit and o.nation_id == game.player_id:
		var cur: Array = game.selected.filter(func(x): return x is Unit and x.nation_id == game.player_id)
		if o in cur:
			cur.erase(o)
		else:
			cur.append(o)
		_set_selection(cur)
	else:
		_set_selection([o])


var _last_click_ms := -1000


func _treasure_at_mouse() -> Treasure:
	for t in game.treasures:
		if t.visible and _mouse_pos.distance_to(camera.iso_to_screen(t.position + Vector2(0, 16))) < 22.0 * camera.zoom.x:
			return t
	return null


## Double-click: every own unit of the clicked type that is on screen.
func _select_same_type() -> void:
	var o := _pick()
	if not (o is Unit) or o.nation_id != game.player_id:
		_click_select(false)
		return
	var view := get_viewport().get_visible_rect()
	var picked: Array = []
	for u in game.units:
		if u.nation_id == game.player_id and not u.dead and u.inside_firm == null and u.sprite_code == o.sprite_code:
			if view.has_point(camera.iso_to_screen(u.position)):
				picked.append(u)
	_set_selection(picked)


func _box_select(a: Vector2, b: Vector2, add: bool) -> void:
	var r := Rect2(a, b - a).abs()
	var picked: Array = game.selected.duplicate() if add else []
	for u in game.units:
		if u.nation_id != game.player_id or u.dead or u.inside_firm:
			continue
		if r.has_point(camera.iso_to_screen(u.position) + Vector2(0, 6) * camera.zoom.x) and not (u in picked):
			picked.append(u)
	_set_selection(picked)


## Right-click orders for the selected units.
func _command(force_attack: bool) -> void:
	var own: Array = game.selected.filter(func(o): return o is Unit and o.nation_id == game.player_id and not o.dead and o.inside_firm == null)
	if own.is_empty():
		return
	sfx.play_event("S", own[0].sprite_code, "ACK")
	var target := _pick()
	# spies slip into towns, forts and camps (their own ones to hunt enemy spies)
	var spies_sel: Array = own.filter(func(u): return u.is_spy)
	if target and not spies_sel.is_empty() and (target is Town or Espionage.is_camp(target)):
		var refused := 0
		for u in spies_sel:
			if not Espionage.can_enter(u, target) or (Espionage.cloak_needed(u, target) > 0 and not Espionage.can_change_cloak(u, Espionage.cloak_needed(u, target))):
				refused += 1
			else:
				Net.cmd(u, "order_infiltrate", [target])
		if refused > 0:
			var tn := game.nation(target.nation_id)
			game.notify("A spy cannot put on the colours of the %s with enemies nearby." % tn.name if tn else "The spy cannot go there.", spies_sel[0].center_loc())
		own = own.filter(func(u): return not u.is_spy)
		if own.is_empty():
			return
	if target and not own.has(target):
		if target is Firm and target.nation_id == game.player_id:
			var f := target as Firm
			if f.under_construction:
				var humans := own.filter(func(u): return u.is_human())
				if not humans.is_empty():
					Net.cmd(humans[0], "order_build", [f])
				return
			if f.is_military() or f.code == "FORTRESS":
				for u in own:
					Net.cmd(u, "order_enter", [f])
				return
		elif target.nation_id != game.player_id:
			var hostile := game.is_hostile(own[0], target) or target.is_monster()
			if not hostile and target is Town and target.nation_id == 0:
				hostile = true
				Net.cmd(game.player(), "change_reputation", [-1.0])
			elif not hostile and target.nation_id > 0:
				if force_attack:
					hostile = true
				else:
					game.notify("Not at war with the %s. Ctrl+right-click to attack anyway." % target.nation().name, Vector2(-1, -1))
					return
			if hostile:
				for u in own:
					if u.can_attack():
						Net.cmd(u, "order_attack", [target])
				return
	if Input.is_key_pressed(KEY_SHIFT):
		for u in own:
			Net.cmd(u, "add_waypoint", [Vector2i(_mouse_loc().floor())])
		return
	_formation_move(own, Vector2i(_mouse_loc().floor()))


func _formation_move(units: Array, dest: Vector2i) -> void:
	if units.any(func(u): return u.rank >= Defs.Rank.GENERAL and u.formation > 0):
		Net.cmd(game, "move_troop", [units, dest])
		return
	var cells: Array[Vector2i] = []
	var r := 0
	while cells.size() < units.size() and r < 12:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c := dest + Vector2i(dx, dy)
				if game.world.is_walkable(c):
					cells.append(c)
		r += 1
	for i in units.size():
		var u: Unit = units[i]
		Net.cmd(u, "order_move_free", [cells[i] if i < cells.size() else dest])


## --bench=<seconds>: after a second's warm-up, print frame time, draw calls and
## object counts over the given span, then quit.
func _bench(seconds: float) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	await get_tree().create_timer(1.0).timeout
	var times: Array[float] = []
	var v3d := 0.0
	var shown := 0
	var draws := 0.0
	var prims := 0.0
	var proc := 0.0
	var t0 := Time.get_ticks_usec()
	var last := t0
	while Time.get_ticks_usec() - t0 < seconds * 1e6:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		v3d += view3d.usec / 1000.0
		shown += view3d.models_shown
	var n := float(times.size())
	times.sort()
	print("BENCH frames %d  avg %.1f ms (%.0f fps)  p95 %.1f ms  process %.1f ms  view3d %.1f ms  models shown %d  draw calls %d  triangles %dk  units %d  nodes %d" % [
		times.size(), times.reduce(func(a, b): return a + b) / n, n / seconds,
		times[int(n * 0.95)], proc / n, v3d / n, int(shown / n), int(draws / n), int(prims / n / 1000.0), game.units.size() if game else 0,
		Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	get_tree().quit()


## Answers the campaign's questions with the first reply (for --campaign-battle).
class _AutoUI:
	func narrative(_t: String) -> void:
		pass
	func letter(_t: String) -> int:
		return 1
	func attack(_a: int, _b: int, _r: int, _a2: int) -> void:
		pass
	func pick_state(c: Array) -> int:
		return c[0]
