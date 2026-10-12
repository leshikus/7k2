class_name WorldMap
extends RefCounted
## Location grid: terrain corner types, occupancy and path finding.

enum Terrain { DARK_GRASS, LIGHT_GRASS, DIRT }

var w := 0
var h := 0
var corners := PackedByteArray()   # (w+1)*(h+1) terrain types at location corners
var occupant: Array = []           # w*h: GameObj occupying a location, or null
var plant := PackedByteArray()      # w*h: 1 if a tree stands here
var astar := AStarGrid2D.new()


func _init(width: int, height: int) -> void:
	w = width
	h = height
	corners.resize((w + 1) * (h + 1))
	occupant.resize(w * h)
	plant.resize(w * h)
	astar.region = Rect2i(0, 0, w, h)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()


func inside(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < w and c.y < h


func generate(rng: RandomNumberGenerator) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi()
	noise.frequency = 0.035
	noise.fractal_octaves = 4
	var noise2 := FastNoiseLite.new()
	noise2.seed = rng.randi()
	noise2.frequency = 0.06
	for y in h + 1:
		for x in w + 1:
			var v := noise.get_noise_2d(x, y)
			var t := Terrain.DARK_GRASS
			if v > 0.32:
				t = Terrain.DIRT
			elif noise2.get_noise_2d(x, y) > 0.05:
				t = Terrain.LIGHT_GRASS
			corners[y * (w + 1) + x] = t


func corner(x: int, y: int) -> int:
	return corners[clampi(y, 0, h) * (w + 1) + clampi(x, 0, w)]


func is_hill(c: Vector2i) -> bool:
	var n := 0
	for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		if corner(c.x + d.x, c.y + d.y) == Terrain.DIRT:
			n += 1
	return n >= 3


func _refresh_solid(c: Vector2i) -> void:
	var i := c.y * w + c.x
	astar.set_point_solid(c, occupant[i] != null or plant[i] == 1)


func is_free(c: Vector2i) -> bool:
	if not inside(c):
		return false
	var i := c.y * w + c.x
	return occupant[i] == null and plant[i] == 0


func is_walkable(c: Vector2i) -> bool:
	return inside(c) and not astar.is_point_solid(c)


## True when the rect is inside the map and empty. Trees are allowed (they are cleared).
func can_place(x: int, y: int, rw: int, rh: int, allow_hill := false) -> bool:
	if x < 0 or y < 0 or x + rw > w or y + rh > h:
		return false
	for yy in range(y, y + rh):
		for xx in range(x, x + rw):
			if occupant[yy * w + xx] != null:
				return false
			if not allow_hill and is_hill(Vector2i(xx, yy)):
				return false
	return true


func occupy(obj: Object, x: int, y: int, rw: int, rh: int) -> void:
	for yy in range(y, y + rh):
		for xx in range(x, x + rw):
			if inside(Vector2i(xx, yy)):
				occupant[yy * w + xx] = obj
				plant[yy * w + xx] = 0
				_refresh_solid(Vector2i(xx, yy))


func release(x: int, y: int, rw: int, rh: int) -> void:
	for yy in range(y, y + rh):
		for xx in range(x, x + rw):
			if inside(Vector2i(xx, yy)):
				occupant[yy * w + xx] = null
				_refresh_solid(Vector2i(xx, yy))


func set_plant(c: Vector2i, on: bool) -> void:
	if inside(c):
		plant[c.y * w + c.x] = 1 if on else 0
		_refresh_solid(c)


func object_at(c: Vector2i) -> Object:
	if not inside(c):
		return null
	return occupant[c.y * w + c.x]


## Nearest walkable location to `c` (spiral search).
func nearest_walkable(c: Vector2i, max_r := 12) -> Vector2i:
	c = Vector2i(clampi(c.x, 0, w - 1), clampi(c.y, 0, h - 1))
	if is_walkable(c):
		return c
	for r in range(1, max_r + 1):
		var best := Vector2i(-1, -1)
		var best_d := INF
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var p := c + Vector2i(dx, dy)
				if is_walkable(p):
					var d := Vector2(dx, dy).length_squared()
					if d < best_d:
						best_d = d
						best = p
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


## Walkable location next to a rectangle, closest to `from`.
func adjacent_to_rect(rect: Rect2i, from: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for y in range(rect.position.y - 1, rect.end.y + 1):
		for x in range(rect.position.x - 1, rect.end.x + 1):
			if rect.has_point(Vector2i(x, y)):
				continue
			var p := Vector2i(x, y)
			if is_walkable(p):
				var d := Vector2(p - from).length_squared()
				if d < best_d:
					best_d = d
					best = p
	if best.x < 0:
		best = nearest_walkable(rect.get_center(), maxi(rect.size.x, rect.size.y) + 6)
	return best


func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not inside(from) or not inside(to):
		return result
	if not is_walkable(to):
		to = nearest_walkable(to)
		if to.x < 0:
			return result
	var was_solid := astar.is_point_solid(from)
	if was_solid:
		astar.set_point_solid(from, false)
	var pts := astar.get_id_path(from, to)
	if was_solid:
		astar.set_point_solid(from, true)
	for p in pts:
		result.append(p)
	return result
