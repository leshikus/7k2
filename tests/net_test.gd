extends Node
## Two machines in lockstep: this process hosts and launches a second Godot
## process as the client; both run the same game with scripted commands from
## each player and must end with identical simulations.
##   godot --headless --path . res://tests/net_test.tscn

var END_FRAME := 600
var DROP_FRAME := 0          # the client leaves at this frame (0 = never)
const PORT := 7391

var role := "host"
var game: Game = null
var ok := true
var client_pid := -1
var my_hash := 0
var their_hash := 0
var desync := false
var hashes_checked := 0
var started := false
var done := false
var t0 := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("role="):
			role = a.substr(5)
		elif a.begins_with("frames="):
			END_FRAME = a.substr(7).to_int()
		elif a.begins_with("drop="):
			DROP_FRAME = a.substr(5).to_int()
	if Assets.load_install() != "":
		get_tree().quit(1); return
	Defs.load_from_assets()
	t0 = Time.get_ticks_msec()
	Net.game_start.connect(_on_start)
	Net.desynced.connect(func(_t): desync = true)
	Net.chat.connect(_on_chat)
	if role == "host":
		var err := Net.host(PORT, "Host", "NORMAN")
		if err != "":
			print("FAIL host: ", err)
			get_tree().quit(1)
			return
		var exe := OS.get_executable_path()
		client_pid = OS.create_process(exe, ["--headless", "--path", ProjectSettings.globalize_path("res://"),
			"res://tests/net_test.tscn", "--", "role=client", "frames=%d" % END_FRAME, "drop=%d" % DROP_FRAME])
		print("host: client process ", client_pid)
	else:
		await get_tree().create_timer(0.5).timeout
		Net.join("127.0.0.1", PORT, "Client", "VIKING")


func _on_start(cfg: Dictionary) -> void:
	game = Game.new()
	game.player_id = Net.nation_of(Net.my_id())
	Net.game = game
	add_child(game)
	game.start(cfg)
	started = true
	print("%s: game started as nation %d (%s), %d nations" % [role, game.player_id, game.player().name, game.nations.size()])


func _on_chat(text: String) -> void:
	if role == "host" and text.contains("HASH "):
		their_hash = text.get_slice("HASH ", 1).to_int()


func _process(_delta: float) -> void:
	if Time.get_ticks_msec() - t0 > 150000 + END_FRAME * 60:
		_finish("timeout")
		return
	if role == "host" and not started and Net.players.size() == 2:
		started = true
		Net.start_game({"seed": 4242, "size": 90, "ai_count": 1, "fryhtan_count": 1, "cash": 3000, "indep_towns": 4, "lairs": 2, "reveal": true})
		return
	if game == null or done:
		return
	# scripted orders from each player, issued at different frames
	var p := game.player()
	if role == "client" and DROP_FRAME > 0 and game.frame >= DROP_FRAME:
		print("client: leaving at frame %d" % game.frame)
		_finish("")
		return
	if _once("move", 40 if role == "host" else 43):
		for u in game.units.filter(func(x): return x.nation_id == p.id and x.inside_firm == null):
			Net.cmd(u, "order_move_free", [u.cell() + Vector2i(4 if role == "host" else -4, 3)])
	if _once("recruit", 120):
		for t in game.towns.filter(func(x): return x.nation_id == p.id):
			Net.cmd(t, "recruit")
	if role == "client" and _once("fill", 200):
		var f: Array = game.firms.filter(func(x): return x.nation_id == p.id and x.code in Firm.MILITARY_FIRMS)
		if not f.is_empty():
			Net.cmd(f[0], "fill_from_towns")
	if role == "host" and _once("war", 260):
		Net.cmd(game, "declare_war", [p.id, 2])
		Net.cmd(game, "set_speed", [2.0])
	if game.frame < END_FRAME:
		game._accum = 0.0
		for i in 8:
			if game.frame >= END_FRAME or not Net.can_run_frame(game.frame + 1):
				break
			game.sim_frame()
		return
	if my_hash == 0:
		my_hash = game.state_hash()
		print("%s: frame %d hash %d (speed %.1f, at war %s, units %d)" % [role, game.frame, my_hash, game.speed, game.player().relation(1 if role == "client" else 2) == Defs.Relation.WAR, game.units.size()])
		if role == "client":
			Net.say("HASH %d" % my_hash)
			await get_tree().create_timer(1.0).timeout
			_finish("")
			return
	if role == "host" and DROP_FRAME > 0:
		var n2 := game.nation(2)
		var took := n2 != null and n2.is_ai and n2.ai != null
		print(("ok   " if took else "FAIL ") + "the computer took over the kingdom of the player who left")
		ok = ok and took
		_finish("")
		return
	if role == "host" and their_hash != 0:
		var match_ok := their_hash == my_hash
		print(("ok   " if match_ok else "FAIL ") + "both machines end with the same simulation")
		ok = ok and match_ok
		print(("ok   " if not desync else "FAIL ") + "no drift reported along the way")
		ok = ok and not desync
		print(("ok   " if game.speed == 2.0 else "FAIL ") + "the host's speed change took effect")
		ok = ok and game.speed == 2.0
		var war := game.player().relation(2) == Defs.Relation.WAR
		print(("ok   " if war else "FAIL ") + "the host's declaration of war took effect")
		ok = ok and war
		_finish("")


var _done_steps := {}


func _once(key: String, at_frame: int) -> bool:
	if game.frame >= at_frame and not _done_steps.has(key):
		_done_steps[key] = true
		return true
	return false


func _finish(why: String) -> void:
	if done:
		return
	done = true
	if why != "":
		print("FAIL ", why)
		ok = false
	if role == "host":
		print("RESULT: ", "PASS" if ok else "FAIL")
	Net.leave()
	get_tree().quit()
