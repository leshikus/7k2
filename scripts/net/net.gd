extends Node
## Multiplayer over the network, in lockstep as the original plays it (remote.cpp:
## every machine runs the same simulation; only the players' commands travel).
##
## A player's actions become commands: Net.cmd(target, "method", [args]). Alone,
## a command runs at once. In a network game it is sent to the host, which
## gathers every player's commands for a turn (TURN_FRAMES frames) and sends the
## bundle back to all; each machine runs a turn only once it has its bundle, and
## a command issued during turn t runs at turn t + DELAY_TURNS everywhere. The
## host stands in for players who leave, whose kingdoms the computer takes over.
## Every few turns each machine sends a checksum of its simulation to the host,
## which warns if the games have drifted apart.

signal lobby_changed
signal game_start(cfg: Dictionary)
signal net_status(text: String)
signal desynced(turn: int)
signal chat(text: String)

const PORT := 7272
const TURN_FRAMES := 4
const DELAY_TURNS := 2
const MAX_PLAYERS := 7
const HASH_EVERY := 25
## Static classes a command may call (resolved by name on every machine).
const STATIC_TARGETS := ["Espionage", "SpecialFirms", "Training", "Economy"]

var peer: ENetMultiplayerPeer = null
var is_host := false
var active := false               # a network game is running
var players := {}                 # peer id -> {"name", "race"}
var order: Array = []             # peer ids in nation order (host first)
var my_name := "Player"
var my_race := "NORMAN"
var game: Game = null

var turn := 0                     # the next turn to run
var _bundles := {}                # turn -> [[peer, [cmd...]], ...] (from the host)
var _outbox: Array = []           # commands issued since the last turn boundary
# host only
var _inbox := {}                  # turn -> {peer: [cmd...]}
var _gone := {}                   # peer -> true: left during the game
var _drops: Array = []            # nations to hand to the computer in the next bundle
var _hashes := {}                 # turn -> {peer: hash}


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(func(): rpc_id(1, "_hello", my_name, my_race))
	multiplayer.connection_failed.connect(func(): _status("Could not connect."); leave())
	multiplayer.server_disconnected.connect(_on_server_gone)


func online() -> bool:
	return peer != null


func my_id() -> int:
	return multiplayer.get_unique_id() if peer else 1


# ------------------------------------------------------------- lobby ---

func host(port: int, name: String, race: String) -> String:
	leave()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS - 1)
	if err != OK:
		peer = null
		return "Could not open port %d (error %d)." % [port, err]
	multiplayer.multiplayer_peer = peer
	is_host = true
	my_name = name
	my_race = race
	players = {1: {"name": name, "race": race}}
	_status("Hosting on port %d. Waiting for players..." % port)
	lobby_changed.emit()
	return ""


func join(address: String, port: int, name: String, race: String) -> String:
	leave()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		peer = null
		return "Could not connect to %s:%d (error %d)." % [address, port, err]
	multiplayer.multiplayer_peer = peer
	is_host = false
	my_name = name
	my_race = race
	players.clear()
	_status("Connecting to %s:%d..." % [address, port])
	return ""


func leave() -> void:
	if peer:
		peer.close()
	multiplayer.multiplayer_peer = null
	peer = null
	is_host = false
	active = false
	players.clear()
	order.clear()
	_reset_lockstep()
	lobby_changed.emit()


func set_race(race: String) -> void:
	my_race = race
	if is_host:
		players[1]["race"] = race
		rpc("_lobby", players)
		lobby_changed.emit()
	elif peer:
		rpc_id(1, "_hello", my_name, race)


@rpc("any_peer", "reliable")
func _hello(name: String, race: String) -> void:
	if not is_host or active:
		return
	var from := multiplayer.get_remote_sender_id()
	players[from] = {"name": name, "race": race}
	rpc("_lobby", players)
	lobby_changed.emit()
	_status("%s has joined." % name)


@rpc("authority", "reliable")
func _lobby(list: Dictionary) -> void:
	players = {}
	for k in list:
		players[int(k)] = list[k]
	lobby_changed.emit()
	_status("In the lobby of %s." % players.get(1, {}).get("name", "the host"))


func _on_peer_connected(_id: int) -> void:
	pass


func _on_peer_disconnected(id: int) -> void:
	if not is_host:
		return
	var who: String = players.get(id, {}).get("name", "A player")
	if active:
		_gone[id] = true
		var idx := order.find(id)
		if idx >= 0:
			_drops.append(idx + 1)
		_try_bundles()
	else:
		players.erase(id)
		rpc("_lobby", players)
		lobby_changed.emit()
	_status("%s has left." % who)
	rpc("_chat_in", "%s has left the game." % who)


func _on_server_gone() -> void:
	_status("The host has left the game.")
	if active and game:
		game.notify("The host has left: the network game is over.", Vector2(-1, -1))
	leave()


## Host: everyone in the lobby starts the game with the same settings.
func start_game(cfg: Dictionary) -> void:
	if not is_host:
		return
	var ids: Array = players.keys()
	ids.sort()
	cfg = cfg.duplicate()
	cfg["mp"] = ids.map(func(id): return {"peer": id, "name": players[id]["name"], "race": players[id]["race"]})
	rpc("_start", cfg)
	_start(cfg)


@rpc("authority", "reliable")
func _start(cfg: Dictionary) -> void:
	order = cfg["mp"].map(func(p): return int(p["peer"]))
	_reset_lockstep()
	active = true
	game_start.emit(cfg)


## The nation a peer leads (players take nations 1, 2, ... in peer order).
func nation_of(peer_id: int) -> int:
	return order.find(peer_id) + 1


func _reset_lockstep() -> void:
	turn = 0
	_bundles.clear()
	_outbox.clear()
	_inbox.clear()
	_gone.clear()
	_drops.clear()
	_hashes.clear()
	for t in DELAY_TURNS:
		_bundles[t] = []


func _status(t: String) -> void:
	net_status.emit(t)


func say(text: String) -> void:
	if peer:
		rpc("_chat_in", "%s: %s" % [my_name, text])
	_chat_in("%s: %s" % [my_name, text])


@rpc("any_peer", "reliable")
func _chat_in(text: String) -> void:
	chat.emit(text)
	if game:
		game.notify(text, Vector2(-1, -1))


# ---------------------------------------------------------- commands ---

## Runs `target.method(args)` now (alone) or at the same turn on every machine.
func cmd(target, method: String, args: Array = []) -> void:
	if not active:
		_call(target, method, args)
		return
	_outbox.append([_pack(target), method, args.map(_pack)])


func _call(target, method: String, args: Array) -> void:
	if target == null:
		return
	if target is Object and not is_instance_valid(target):
		return
	if target is GameObj and (target as GameObj).dead and method != "die":
		return
	if method == "set":
		target.set(args[0], args[1])
	else:
		target.callv(method, args)


func _pack(v):
	if v is GameObj:
		return {"o": (v as GameObj).obj_id}
	if v is Nation:
		return {"n": (v as Nation).id}
	if v is Game:
		return {"g": 1}
	if v is GDScript:
		for s in STATIC_TARGETS:
			if v == _static(s):
				return {"s": s}
	if v is Vector2i:
		return {"v2i": [v.x, v.y]}
	if v is Vector2:
		return {"v2": [v.x, v.y]}
	if v is Array:
		return {"a": v.map(_pack)}
	return v


func _unpack(v):
	if v is Dictionary:
		if v.has("o"):
			return game.find_obj(int(v["o"])) if game else null
		if v.has("n"):
			return game.nation(int(v["n"])) if game else null
		if v.has("g"):
			return game
		if v.has("s"):
			return _static(v["s"])
		if v.has("v2i"):
			return Vector2i(int(v["v2i"][0]), int(v["v2i"][1]))
		if v.has("v2"):
			return Vector2(float(v["v2"][0]), float(v["v2"][1]))
		if v.has("a"):
			return v["a"].map(_unpack)
	if v is float and v == floorf(v) and absf(v) < 1e9:
		return int(v)
	return v


func _static(name: String) -> GDScript:
	match name:
		"Espionage": return Espionage
		"SpecialFirms": return SpecialFirms
		"Training": return Training
		"Economy": return Economy
	return null


# ---------------------------------------------------------- lockstep ---

## Game asks before each frame: may it run? At a turn boundary the turn's
## commands run first, and this machine's commands are sent for a later turn.
func can_run_frame(frame: int) -> bool:
	if not active:
		return true
	if (frame - 1) % TURN_FRAMES != 0:
		return true
	if not _bundles.has(turn):
		return false
	var bundle: Array = _bundles[turn]
	_bundles.erase(turn)
	for entry in bundle:
		for c in entry[1]:
			_call(_unpack(c[0]), c[1], c[2].map(_unpack))
	var due := turn + DELAY_TURNS
	var mine := _outbox.duplicate()
	_outbox.clear()
	if is_host:
		_receive(due, 1, mine)
	else:
		rpc_id(1, "_commands", due, mine)
	if turn > 0 and turn % HASH_EVERY == 0 and game:
		var h := game.state_hash()
		if is_host:
			_check_hash(turn, 1, h)
		else:
			rpc_id(1, "_hash", turn, h)
	turn += 1
	return true


@rpc("any_peer", "reliable")
func _commands(t: int, cmds: Array) -> void:
	if is_host:
		_receive(t, multiplayer.get_remote_sender_id(), cmds)


func _receive(t: int, from: int, cmds: Array) -> void:
	if not _inbox.has(t):
		_inbox[t] = {}
	_inbox[t][from] = cmds
	_try_bundles()


## Host: a turn's bundle goes out once every remaining player's commands are in.
func _try_bundles() -> void:
	var ts: Array = _inbox.keys()
	ts.sort()
	for t in ts:
		var got: Dictionary = _inbox[t]
		var complete := true
		for id in order:
			if not got.has(id) and not _gone.has(id):
				complete = false
				break
		if not complete:
			return
		var bundle: Array = []
		for id in order:
			if got.has(id) and not _gone.has(id):
				bundle.append([id, got[id]])
		for nid in _drops:
			bundle.append([0, [[{"g": 1}, "mp_drop_player", [nid]]]])
		_drops.clear()
		_inbox.erase(t)
		rpc("_bundle", t, bundle)
		_bundle(t, bundle)


@rpc("authority", "reliable")
func _bundle(t: int, bundle: Array) -> void:
	_bundles[t] = bundle


@rpc("any_peer", "reliable")
func _hash(t: int, h: int) -> void:
	if is_host:
		_check_hash(t, multiplayer.get_remote_sender_id(), h)


func _check_hash(t: int, from: int, h: int) -> void:
	if not _hashes.has(t):
		_hashes[t] = {}
	_hashes[t][from] = h
	var vals: Array = _hashes[t].values()
	if vals.size() >= order.size() - _gone.size():
		if vals.any(func(v): return v != vals[0]):
			desynced.emit(t)
			rpc("_desync_in", t)
			_desync_in(t)
		_hashes.erase(t)


@rpc("authority", "reliable")
func _desync_in(t: int) -> void:
	desynced.emit(t)
	if game:
		game.notify("Warning: the games have drifted apart (turn %d)." % t, Vector2(-1, -1))
