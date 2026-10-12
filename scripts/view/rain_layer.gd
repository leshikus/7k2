class_name RainLayer
extends Control
## Screen-space rain: slanted streaks blown by the wind, a dim overcast tint,
## and a white flash for lightning.

var game: Game
var drops: PackedVector2Array = PackedVector2Array()
var flash := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func lightning_flash() -> void:
	flash = 1.0


func _process(delta: float) -> void:
	if game == null:
		return
	var scale := game.weather.rain_scale() if not game.paused else 0
	var want := scale * 90
	var vs := get_viewport_rect().size
	if vs.y < 10.0:
		return
	while drops.size() < want:
		drops.append(Vector2(randf() * vs.x, randf() * vs.y))
	if drops.size() > want:
		drops.resize(want)
	var wind := clampf(game.weather.wind_spd / 40.0, -1.0, 2.0)
	var v := Vector2(120.0 * wind + 60.0, 900.0) * delta * (1.0 if not game.paused else 0.0)
	for i in drops.size():
		var p := drops[i] + v
		if p.y > vs.y:
			p = Vector2(randf() * vs.x, -randf() * vs.y * 0.3)
		if p.x > vs.x:
			p.x -= vs.x
		drops[i] = p
	flash = maxf(0.0, flash - delta * 3.0)
	queue_redraw()


func _draw() -> void:
	if game == null:
		return
	var scale := game.weather.rain_scale()
	if scale > 0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.07, 0.12, minf(0.35, 0.03 * scale)))
		var wind := clampf(game.weather.wind_spd / 40.0, -1.0, 2.0)
		var tail := Vector2(-(wind * 4.0 + 2.0), -14.0)
		for p in drops:
			draw_line(p, p + tail, Color(0.75, 0.8, 0.9, 0.45), 1.0)
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, flash * 0.5))
