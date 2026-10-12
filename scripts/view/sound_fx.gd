class_name SoundFX
extends Node
## Plays the original sound effects through a small pool of players.
## Sounds far from the centre of the screen are quieter or skipped.

const POOL := 8
const HEARING := 1100.0      # screen pixels from the view centre

var enabled := true
var camera: CameraRig
var _players: Array[AudioStreamPlayer] = []
var _recent := {}            # wave name -> msec last played


func _ready() -> void:
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.volume_db = -6.0
		add_child(p)
		_players.append(p)


## kind: "S" sprite, "F" firm; code: sprite or firm code; action: A1, DIE, SEL ...
## `world_pos` (screen-space world coordinates) attenuates by distance; null = interface sound.
func play_event(kind: String, code: String, action: String, world_pos = null) -> void:
	if not enabled:
		return
	var files := Assets.sound_files(kind, code, action)
	if files.is_empty():
		return
	play(files[randi() % files.size()], world_pos)


func play(wave: String, world_pos = null) -> void:
	if not enabled:
		return
	var now := Time.get_ticks_msec()
	if now - int(_recent.get(wave, -1000)) < 120:
		return
	var vol := -6.0
	if world_pos != null and camera:
		var d: float = (world_pos - camera.iso_pos).length() * camera.zoom.x
		if d > HEARING:
			return
		vol -= d / HEARING * 18.0
	var player: AudioStreamPlayer = null
	for p in _players:
		if not p.playing:
			player = p
			break
	if player == null:
		return
	var s := Assets.sound(wave)
	if s == null:
		return
	_recent[wave] = now
	player.stream = s
	player.volume_db = vol
	player.play()
