extends Node
## Drives the real main scene with synthetic mouse/keyboard events, the way a
## player would: click-select, box-select, right-click orders, build menu,
## building placement, garrisoning and recruiting.

var main: Node
var game: Game
var ok := true


func _ready() -> void:
	get_window().size = Vector2i(1280, 800)
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	if not Assets.ready_ok:
		print("FAIL: no game data")
		get_tree().quit(1)
		return
	main._start({"seed": 7, "size": 100, "race": "NORMAN", "ai_count": 1, "cash": 3000, "lairs": 0, "no_tips": true})
	game = main.game
	game.make_peace(1, 2)
	await _frames(5)
	await _run()
	print("RESULT: ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 2)


func _check(cond: bool, what: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + what)
	if not cond:
		ok = false


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _sim(frames: int) -> void:
	for i in frames:
		game.sim_frame()
	await _frames(2)


func _screen(world_pos: Vector2) -> Vector2:
	return main.camera.iso_to_screen(world_pos)


func _mouse(button: int, pos: Vector2, pressed: bool, ctrl := false, shift := false) -> void:
	var m := InputEventMouseMotion.new()
	m.position = pos
	m.global_position = pos
	if button == MOUSE_BUTTON_LEFT and not pressed:
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(m)
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	e.ctrl_pressed = ctrl
	e.shift_pressed = shift
	Input.parse_input_event(e)
	await _frames(2)


func _click(button: int, pos: Vector2, ctrl := false) -> void:
	await _mouse(button, pos, true, ctrl)
	await _mouse(button, pos, false, ctrl)


func _drag(a: Vector2, b: Vector2) -> void:
	await _mouse(MOUSE_BUTTON_LEFT, a, true)
	for i in 5:
		var m := InputEventMouseMotion.new()
		m.position = a.lerp(b, (i + 1) / 5.0)
		m.global_position = m.position
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(m)
		await _frames(1)
	await _mouse(MOUSE_BUTTON_LEFT, b, false)


func _press_hud_button(prefix: String) -> bool:
	for b in main.hud.actions.get_children():
		if b is Button and String(b.get_meta("label", b.text)).begins_with(prefix) and not b.disabled:
			b.pressed.emit()
			await _frames(2)
			return true
	return false


func _center_on(loc: Vector2) -> void:
	main.camera.focus_on(loc)
	main.camera.apply()
	main.camera.zoom = Vector2.ONE
	await _frames(3)


func _run() -> void:
	var p := game.player()
	var gen: Unit = game.units.filter(func(u): return u.nation_id == p.id and u.rank == Defs.Rank.GENERAL)[0]
	await _center_on(gen.center_loc())

	# 1. click-select the general
	var sp0 := _screen(gen.position + Vector2(-6, 0))
	await _mouse(MOUSE_BUTTON_LEFT, sp0, false)
	print("  dbg: gen.pos=", gen.position, " screen=", sp0, " world_mouse=", main._world_mouse(), " vp_mouse=", get_viewport().get_mouse_position(), " cam=", main.camera.iso_pos, " vp=", get_viewport().get_visible_rect().size)
	await _click(MOUSE_BUTTON_LEFT, sp0)
	_check(game.selected == [gen], "left-click selects the general")
	main.hud.refresh_selection(true)
	_check(main.hud.title_label.text.contains(gen.unit_name), "info panel shows the general's name")

	# 2. right-click on open ground moves him there
	var dest := game.world.nearest_walkable(gen.cell() + Vector2i(4, 2))
	await _click(MOUSE_BUTTON_RIGHT, _screen(Iso.to_screen(Vector2(dest) + Vector2(0.5, 0.5))))
	_check(gen.order == Unit.Order.MOVE, "right-click on ground gives a move order")
	await _sim(200)
	_check(gen.cell().distance_to(dest) <= 1.5, "general walked to the clicked spot (at %s, wanted %s)" % [gen.cell(), dest])

	# 3. build a camp through the build menu, placed with the mouse
	await _center_on(gen.center_loc())
	main.hud.refresh_selection(true)
	_check(await _press_hud_button("Build"), "Build... button available")
	main.hud.refresh_selection(true)
	_check(await _press_hud_button("Camp"), "Camp button in the build menu")
	_check(main.build_code == "CAMP", "placement mode active")
	var spot := Vector2i(-1, -1)
	var b := Assets.firm_build("CAMP", p.race)
	for r in range(3, 14):
		for dx in range(-r, r + 1):
			for dy in [-r, r]:
				var c := gen.cell() + Vector2i(dx, dy)
				var rr := Rect2i(c, Vector2i(b["loc_w"], b["loc_h"]))
				if spot.x < 0 and game.world.can_place(c.x, c.y, b["loc_w"], b["loc_h"]) and not game._overlaps_site(rr) and game.is_loc_explored(rr.get_center()) and game.is_loc_explored(rr.position) and game.is_loc_explored(rr.end - Vector2i.ONE):
					spot = c
	var firms_before := game.firms.size()
	var center := Vector2(spot) + Vector2(b["loc_w"], b["loc_h"]) * 0.5
	await _center_on(center)
	var mp := _screen(Iso.to_screen(center))
	var mm := InputEventMouseMotion.new()
	mm.position = mp
	mm.global_position = mp
	Input.parse_input_event(mm)
	Input.warp_mouse(mp)
	await _frames(3)
	main._mouse_pos = mp
	_check(main._placement()["ok"], "placement preview shows the spot as valid (spot %s)" % spot)
	await _click(MOUSE_BUTTON_LEFT, mp)
	_check(game.firms.size() == firms_before + 1, "left-click placed the camp")
	var camp: Firm = game.firms.back()
	_check(camp.code == "CAMP" and camp.under_construction, "camp is under construction")
	_check((gen.order == Unit.Order.BUILD and gen.order_firm == camp) or camp.builder == gen, "general sent to build it")
	await _sim(500)
	_check(not camp.under_construction, "camp completed")
	_check(camp.overseer == gen, "general took command of the camp he built")

	# 4. box-select the two soldiers standing outside
	var soldiers: Array = game.units.filter(func(u): return u.nation_id == p.id and u.rank == Defs.Rank.SOLDIER and u.inside_firm == null and not u.dead)
	if soldiers.size() >= 2:
		var c0: Vector2 = (soldiers[0].center_loc() + soldiers[1].center_loc()) * 0.5
		await _center_on(c0)
		var pa: Vector2 = _screen(soldiers[0].position)
		var pb: Vector2 = _screen(soldiers[1].position)
		var lo := Vector2(minf(pa.x, pb.x), minf(pa.y, pb.y)) - Vector2(40, 40)
		var hi := Vector2(maxf(pa.x, pb.x), maxf(pa.y, pb.y)) + Vector2(40, 40)
		await _drag(lo, hi)
		_check(soldiers[0] in game.selected and soldiers[1] in game.selected, "box-select picked both soldiers (%d selected)" % game.selected.size())
		# 5. right-click the new camp to garrison it
		await _center_on(camp.center_loc())
		await _click(MOUSE_BUTTON_RIGHT, _screen(Iso.to_screen(camp.center_loc())))
		_check(soldiers[0].order == Unit.Order.ENTER, "right-click on own camp orders soldiers in")
		await _sim(400)
		_check(soldiers[0].inside_firm == camp and soldiers[1].inside_firm == camp, "soldiers garrisoned the camp")
	else:
		_check(false, "two soldiers outside at start")

	# 6. select the home town and recruit through its panel
	var town: Town = game.towns.filter(func(t): return t.nation_id == p.id)[0]
	await _center_on(town.center_loc())
	await _click(MOUSE_BUTTON_LEFT, _screen(Iso.to_screen(town.center_loc())))
	_check(game.selected == [town], "left-click selects the town")
	main.hud.refresh_selection(true)
	var units_before := game.units.size()
	var pop_before := town.population
	_check(await _press_hud_button("Recruit"), "Recruit button enabled")
	_check(game.units.size() == units_before + 1 and town.population == pop_before - 1, "recruiting sends a peasant out of the town")

	# 5b. double-click a soldier selects every soldier of that type on screen
	var outside: Array = game.units.filter(func(u): return u.nation_id == p.id and u.sprite_code == "NO_CIV" and u.inside_firm == null and not u.dead)
	_check(not outside.is_empty(), "a peasant is outside to test with")
	if not outside.is_empty():
		await _center_on(outside[0].center_loc())
		var dp := _screen(outside[0].position + Vector2(-6, 0))
		await _click(MOUSE_BUTTON_LEFT, dp)
		await _click(MOUSE_BUTTON_LEFT, dp)
		_check(game.selected.size() >= 1 and game.selected.all(func(o): return o is Unit and o.sprite_code == "NO_CIV"), "double-click selects same-type units (%d)" % game.selected.size())
		# 5c. right-click on the minimap sends them there
		var mini: Minimap = main.hud.minimap
		var target := Vector2(40, 40)
		var local: Vector2 = mini._xf() * target
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_RIGHT
		ev.pressed = true
		ev.position = local
		mini._gui_input(ev)
		await _frames(2)
		var u0: Unit = game.selected[0]
		_check(u0.order == Unit.Order.MOVE and Vector2(u0.goal).distance_to(target) < 4, "right-click on the minimap orders a move (goal %s)" % u0.goal)

	# 7. Escape clears the selection, Space pauses
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.pressed = true
	Input.parse_input_event(esc)
	await _frames(2)
	_check(game.selected.is_empty(), "Escape clears the selection")
	var sp := InputEventKey.new()
	sp.keycode = KEY_SPACE
	sp.pressed = true
	Input.parse_input_event(sp)
	await _frames(2)
	_check(game.paused, "Space pauses the game")

	# 7b. F3 opens the Economy report, pressing it again closes it
	var f3 := InputEventKey.new()
	f3.keycode = KEY_F3
	f3.pressed = true
	Input.parse_input_event(f3)
	await _frames(2)
	_check(main.hud.reports.visible and main.hud.reports.tabs.current_tab == ReportsWindow.TABS.find("Economy"), "F3 opens the Economy report")
	Input.parse_input_event(f3)
	await _frames(2)
	_check(not main.hud.reports.visible, "F3 again closes it")

	# 7c. the original's letter keys find your buildings (Sys::detect_key)
	var fk := InputEventKey.new()
	fk.keycode = KEY_F
	fk.pressed = true
	Input.parse_input_event(fk)
	await _frames(2)
	var fsel: Array = main.game.selected
	_check(fsel.size() == 1 and fsel[0] is Firm and fsel[0].code in ["FORT", "CAMP"] and fsel[0].nation_id == main.game.player_id, "F finds your fort")
	var qk := InputEventKey.new()
	qk.keycode = KEY_Q
	qk.pressed = true
	var mode0: int = main.hud.minimap.mode
	Input.parse_input_event(qk)
	await _frames(2)
	_check(main.hud.minimap.mode != mode0, "Q changes the map mode")
	main._set_selection([])

	# 8. Ctrl+S quicksave, F9 quickload
	var units_now: int = main.game.units.filter(func(u): return not u.dead).size()   # a save leaves out the dying
	var day_now: int = main.game.day
	var f5 := InputEventKey.new()
	f5.keycode = KEY_S
	f5.ctrl_pressed = true
	f5.pressed = true
	Input.parse_input_event(f5)
	await _frames(2)
	_check(SaveGame.exists("quick"), "Ctrl+S writes a quicksave")
	var old_game: Game = main.game
	var f9 := InputEventKey.new()
	f9.keycode = KEY_F9
	f9.pressed = true
	Input.parse_input_event(f9)
	await _frames(4)
	_check(main.game != old_game and absi(main.game.day - day_now) <= 1 and absi(main.game.units.filter(func(u): return not u.dead).size() - units_now) <= 5, "F9 reloads the quicksave (day %d, %d units, %d before)" % [main.game.day, main.game.units.size(), units_now])
	DirAccess.remove_absolute(SaveGame.path_for("quick"))
