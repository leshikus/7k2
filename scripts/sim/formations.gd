class_name Formations
extends RefCounted
## Troop formations (oformat.cpp, UnitGroup::formation): a group with a general
## can be set in one of seven formations; the general keeps it (TeamInfo::
## formation_id) and the troop re-forms in it wherever it stops, facing the
## way it marched or the direction set with the number pad
## (formation_direction). The shapes follow the original's names; the exact
## placement rules of its 6000 lines are simplified to these patterns.

const NAMES := ["None", "Vanguard", "Line", "Circle", "Arc", "Staggered", "Square", "Sandwich"]

## Number pad keys -> facing (LEADER_AT_* in the original: where the general stands
## relative to his troop, i.e. the troop faces away from him).
const NUMPAD := {
	KEY_KP_8: Vector2(0, -1), KEY_KP_9: Vector2(1, -1), KEY_KP_6: Vector2(1, 0), KEY_KP_3: Vector2(1, 1),
	KEY_KP_2: Vector2(0, 1), KEY_KP_1: Vector2(-1, 1), KEY_KP_4: Vector2(-1, 0), KEY_KP_7: Vector2(-1, -1),
}


## Slot offsets (in the formation's frame: +y forward, +x right) for `n` men
## other than the general, who stands at (0, 0).
static func slots(kind: int, n: int) -> Array:
	var out: Array = []
	match kind:
		1:  # Vanguard: a wedge pointing forward, the general behind its point
			var row := 1
			while out.size() < n:
				for i in row:
					out.append(Vector2(i - (row - 1) / 2.0, 4 - row))
				row += 1
		2:  # Line: one rank across the front
			for i in n:
				out.append(Vector2((i + 1) / 2 * (1 if i % 2 == 0 else -1), 1))
		3:  # Circle: a ring around the general
			var r := maxf(1.5, n / 5.0)
			for i in n:
				var a := TAU * i / n
				out.append(Vector2(cos(a), sin(a)) * r)
		4:  # Arc: a half circle bowed toward the enemy
			var r := maxf(2.0, n / 3.0)
			for i in n:
				var a := PI * (i + 0.5) / n
				out.append(Vector2(-cos(a) * r, sin(a) * r * 0.8))
		5:  # Staggered: ranks with the men of each rank in the gaps of the last
			var per := maxi(2, int(ceil(sqrt(n * 2.0))))
			for i in n:
				var rank := i / per
				out.append(Vector2((i % per) * 2 - per + 1 + (rank % 2), 1 + rank))
		6:  # Square: a hollow square around the general
			var side := maxi(3, int(ceil(n / 4.0)) + 1)
			var h := side / 2
			var edge: Array = []
			for x in range(-h, h + 1):
				edge.append(Vector2(x, -h))
				edge.append(Vector2(x, h))
			for y in range(-h + 1, h):
				edge.append(Vector2(-h, y))
				edge.append(Vector2(h, y))
			for i in n:
				out.append(edge[i % edge.size()] + Vector2(0, (i / edge.size()) * 0.0))
		7:  # Sandwich: a rank in front and one behind, the general between
			for i in n:
				var front := i % 2 == 0
				var k := i / 2
				out.append(Vector2((k + 1) / 2 * (1 if k % 2 == 0 else -1), 1.5 if front else -1.5))
	return out.slice(0, n)


## Cells for the men of `units` (the first general found leads) at `at`, facing `facing`.
static func place(g: Game, units: Array, at: Vector2i, facing: Vector2, kind: int) -> Dictionary:
	var general: Unit = null
	for u in units:
		if u.rank >= Defs.Rank.GENERAL and general == null:
			general = u
	var out := {}
	if general == null or kind <= 0:
		return out
	var men := units.filter(func(u): return u != general)
	var f := facing.normalized() if facing.length() > 0.01 else Vector2(0, 1)
	var right := Vector2(-f.y, f.x)
	var taken := {}
	out[general] = g.world.nearest_walkable(at)
	taken[out[general]] = true
	var sl := slots(kind, men.size())
	for i in men.size():
		var o: Vector2 = sl[i] if i < sl.size() else Vector2.ZERO
		var c := Vector2i((Vector2(at) + right * o.x + f * o.y).round())
		c = g.world.nearest_walkable(c)
		var tries := 0
		while taken.has(c) and tries < 24:
			c = g.world.nearest_walkable(c + Vector2i(tries % 3 - 1, tries / 3 % 3 - 1))
			tries += 1
		taken[c] = true
		out[men[i]] = c
	return out
