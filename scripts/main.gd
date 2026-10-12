extends Node
## Scene root: start menu, then the game with camera, HUD and player input.

const EDGE_SCROLL := 6
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
	_show_menu()
	# Command-line shortcut for automated runs: --autostart [seed]
	var args := OS.get_cmdline_user_args()
	if "--autostart" in args and Assets.ready_ok:
		_start({"seed": 7, "size": 100, "race": "NORMAN", "ai_count": 3, "cash": 3000})
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
		"spies":
			var home: Town = game.towns.filter(func(t): return t.nation_id == p.id)[0]
			home.loyalty = 80.0
			var col := game.spawn_firm("SPY", p.id, p.race, game._place_near(home.footprint(), 5, 5, 8, [home.center_loc()]), true)
			game.update_links()
			var s1 := game.spy_spawn(col)
			var s2 := game.spy_spawn(col)
			var indep: Array = game.towns.filter(func(t): return t.nation_id == 0)
			if s1 and not indep.is_empty():
				game.spy_enter(s1, indep[0])
			_set_selection([col])
			camera.iso_pos = Iso.to_screen(col.center_loc())
			hud.toggle_spies()
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
	menu = MainMenu.new()
	add_child(menu)
	menu.start_game.connect(_start)
	menu.load_game.connect(func(slot): load_game.call_deferred(slot))


func _teardown() -> void:
	for n in [hud, game, camera, view3d, overlay_layer, select_layer, menu]:
		if n and is_instance_valid(n):
			n.queue_free()
	hud = null
	game = null
	camera = null
	view3d = null
	overlay_layer = null
	menu = null
	ghost = null
	build_code = ""


func _start(cfg: Dictionary) -> void:
	_teardown()
	game = Game.new()
	add_child(game)
	game.start(cfg)
	_attach_game()
	if cfg.get("autoplay", false):
		game.notify("AI against AI: every kingdom is computer-controlled. Sit back and watch.", Vector2(-1, -1))
	else:
		game.notify("Welcome, ruler of the %s. Expand your realm and defeat the rival kingdoms!" % game.player().name, Vector2(-1, -1))


## Loads a saved game ("quick", "autosave" ...) and resumes play.
func load_game(slot: String) -> bool:
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
	game.notify("Game loaded (%s)." % game.date_string(), Vector2(-1, -1))
	return true


func save_game(slot: String) -> void:
	if game == null or game.over:
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
	# 3D models replacing the sprite cards, when the model library is present
	if ResourceLoader.exists(MODEL_LIBRARY):
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
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		v.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		v.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		v.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
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
	if v != Vector2.ZERO:
		camera.pan(v * PAN_SPEED * delta)
	camera.clamp_to(game.world.w, game.world.h)
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


func _mouse_loc() -> Vector2:
	return Iso.to_loc(_world_mouse())


# ---------------------------------------------------------------- build ---

func _begin_build(code: String) -> void:
	build_code = code
	ghost.visible = true
	game.notify("Place the %s. Left-click to build, right-click to cancel." % Defs.firm_types.get(code, {}).get("name", "Lair" if code == "LAIR" else code), Vector2(-1, -1))


func _placement() -> Dictionary:
	var p := game.player()
	var b := Assets.firm_build(build_code, p.race)
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
		ok = game.world.can_place(pos.x, pos.y, w, h) and not game._overlaps_site(r) and game.is_loc_explored(r.get_center())
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
	if build_code == "LAIR":
		cost = FryhtanAI.LAIR_COST
		if p.live_points < FryhtanAI.LAIR_LIVE:
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
	var f := game.spawn_firm(build_code, p.id, p.race, pl["pos"], false)
	if f == null:
		return
	p.add_cash(-cost)
	if build_code == "LAIR":
		f.monster_code = p.monster_code
		p.live_points -= FryhtanAI.LAIR_LIVE
	var c := f.center_loc()
	builders.sort_custom(func(a, b): return a.center_loc().distance_to(c) < b.center_loc().distance_to(c))
	builders[0].order_build(f)
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
			KEY_SPACE:
				hud._set_speed(0.0)
			KEY_F5:
				save_game("quick")
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
			KEY_Q:
				camera.turn(-1)
			KEY_E:
				camera.turn(1)
			KEY_R:
				camera.tilt(5.0)
			KEY_F:
				camera.tilt(-5.0)
			KEY_H:
				_center_home()
			KEY_N:
				sfx.enabled = not sfx.enabled
				game.notify("Sound effects %s." % ("on" if sfx.enabled else "off"), Vector2(-1, -1))
			KEY_M:
				_music_on = not _music_on
				if _music_on:
					_next_track()
				else:
					music.stop()
			KEY_B:
				if game.selected.any(func(o): return o is Unit and o.nation_id == game.player_id and o.is_human()):
					hud.build_menu_open = true
			_:
				if k.keycode >= KEY_1 and k.keycode <= KEY_9:
					var gi := k.keycode - KEY_1
					if k.ctrl_pressed:
						_groups[gi] = game.selected.filter(func(o): return o is Unit)
					elif _groups.has(gi):
						_set_selection(_groups[gi].filter(func(o): return is_instance_valid(o) and not o.dead))


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
	if o == null:
		if not add:
			_set_selection([])
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
	# spies slip into enemy and independent towns and buildings instead of attacking
	var spies_sel: Array = own.filter(func(u): return u.is_spy)
	if target and not spies_sel.is_empty() and target.nation_id != game.player_id and (target is Town or target is Firm):
		for u in spies_sel:
			u.order_infiltrate(target)
		own = own.filter(func(u): return not u.is_spy)
		if own.is_empty():
			return
	if target and not own.has(target):
		if target is Firm and target.nation_id == game.player_id:
			var f := target as Firm
			if f.under_construction:
				var humans := own.filter(func(u): return u.is_human())
				if not humans.is_empty():
					humans[0].order_build(f)
				return
			if f.is_military():
				for u in own:
					u.order_enter(f)
				return
		elif target.nation_id != game.player_id:
			var hostile := game.is_hostile(own[0], target) or target.is_monster()
			if not hostile and target is Town and target.nation_id == 0:
				hostile = true
				game.player().change_reputation(-1.0)
			elif not hostile and target.nation_id > 0:
				if force_attack:
					hostile = true
				else:
					game.notify("Not at war with the %s. Ctrl+right-click to attack anyway." % target.nation().name, Vector2(-1, -1))
					return
			if hostile:
				for u in own:
					if u.can_attack():
						u.order_attack(target)
				return
	_formation_move(own, Vector2i(_mouse_loc().floor()))


func _formation_move(units: Array, dest: Vector2i) -> void:
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
		u.home_firm = null
		u.order_move(cells[i] if i < cells.size() else dest)
