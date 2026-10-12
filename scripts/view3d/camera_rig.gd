class_name CameraRig
extends Node3D
## Camera orbiting a focus point on the ground. It is a free camera, but while the
## original sprites stand in for 3D models it is held to what they can show: `yaw_step`
## snaps turning to quarter turns (0 = free) and `pitch_min`..`pitch_max` keeps the
## original's 30° view. Lift the limits once models replace the sprites.
##
## World space: x = location x, z = location y, y up; one location is one unit.
## `iso_pos`, `zoom` and `offset` keep the 2D camera's meaning (the original's
## isometric pixels), so code written for the 2D view keeps working.

const PX_PER_UNIT := 45.254834    # a 64px tile diagonal spans sqrt(2) locations

var iso_pos := Vector2.ZERO       # focus point in the original's isometric pixels
var zoom := Vector2.ONE           # screen pixels per original pixel
var offset := Vector2.ZERO        # screen shake, in screen pixels

var yaw := 0.0                    # degrees; 0 = the original's view
var pitch := 30.0                 # degrees above the ground
var yaw_step := 90.0              # 0 = free rotation
var pitch_min := 30.0
var pitch_max := 30.0
var cam: Camera3D
var _yaw_target := 0.0


func _init() -> void:
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.near = 0.05
	cam.far = 4000.0
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	cam.environment = env
	add_child(cam)


func make_current() -> void:
	cam.make_current()


func focus_loc() -> Vector2:
	return Iso.to_loc(iso_pos)


func focus_on(loc: Vector2) -> void:
	iso_pos = Iso.to_screen(loc)


## Turn by `steps` quarter turns (snapping mode) or by `steps` * 15 degrees (free mode).
func turn(steps: int) -> void:
	_yaw_target += steps * (yaw_step if yaw_step > 0.0 else 15.0)


func tilt(deg: float) -> void:
	pitch = clampf(pitch + deg, pitch_min, pitch_max)


## Moves the focus by a screen-space vector (pixels), whatever the view angle.
func pan(screen_delta: Vector2) -> void:
	var c := get_viewport().get_visible_rect().size * 0.5
	var a := screen_to_loc(c)
	var b := screen_to_loc(c + screen_delta)
	if a.x > -1e8 and b.x > -1e8:
		focus_on(focus_loc() + (b - a))


func clamp_to(w: int, h: int) -> void:
	var f := focus_loc()
	focus_on(Vector2(clampf(f.x, 0.0, w), clampf(f.y, 0.0, h)))


func _process(delta: float) -> void:
	yaw = move_toward(yaw, _yaw_target, 270.0 * delta)
	pitch = clampf(pitch, pitch_min, pitch_max)
	apply()


func apply() -> void:
	if not is_inside_tree():
		return
	var f := focus_loc()
	var target := Vector3(f.x, 0.0, f.y)
	var vp := get_viewport().get_visible_rect().size
	cam.size = vp.y / (zoom.y * PX_PER_UNIT)
	var dist := 600.0
	# yaw 0 looks from the south-east of the map (+x, +y), as the original does
	var horiz := Vector3(1, 0, 1).normalized().rotated(Vector3.UP, deg_to_rad(yaw))
	var p := deg_to_rad(pitch)
	var eye := target + horiz * cos(p) * dist + Vector3.UP * sin(p) * dist
	cam.look_at_from_position(eye, target, Vector3.UP)
	if offset != Vector2.ZERO:
		var k := 1.0 / (zoom.x * PX_PER_UNIT)
		cam.global_position += cam.global_basis.x * offset.x * k - cam.global_basis.y * offset.y * k


## Ground location under a viewport point (x < -1e8 when the ray misses the ground).
func screen_to_loc(p: Vector2) -> Vector2:
	var o := cam.project_ray_origin(p)
	var n := cam.project_ray_normal(p)
	if absf(n.y) < 1e-6:
		return Vector2(-1e9, -1e9)
	var hit := o + n * (-o.y / n.y)
	return Vector2(hit.x, hit.z)


func loc_to_screen(l: Vector2) -> Vector2:
	return cam.unproject_position(Vector3(l.x, 0.0, l.y))


## Viewport position of a point given in the original's isometric pixels.
func iso_to_screen(p: Vector2) -> Vector2:
	return loc_to_screen(Iso.to_loc(p))


## Screen-facing direction (0..7) for each world direction under the current view,
## so pre-rendered sprites face the way their unit moves after the camera turns.
func direction_map() -> PackedInt32Array:
	var m := PackedInt32Array()
	m.resize(8)
	var f := focus_loc()
	var p0 := loc_to_screen(f)
	var squash := sin(deg_to_rad(pitch))
	for d in 8:
		var a := d * PI / 4.0
		var loc_delta := Iso.to_loc(Vector2(sin(a), -cos(a) * 0.5) * 32.0)
		var sv := loc_to_screen(f + loc_delta) - p0
		m[d] = posmod(int(round(atan2(sv.x, -sv.y / maxf(squash, 0.05)) / (PI / 4.0))), 8)
	return m
