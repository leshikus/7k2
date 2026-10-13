class_name Formations
extends RefCounted
## Troop formations (oformat.cpp, UnitGroup::*_formation): a group with a
## general can be set in one of seven formations; the general keeps it
## (TeamInfo::formation_id) and the troop re-forms in it wherever it stops,
## facing the way it marched or the direction set with the number pad
## (formation_direction). Each shape follows the original's placement rules,
## in the formation's own frame (+y toward the enemy, +x to the right); the
## original's search for a fitting orientation is replaced by turning the
## shape to the facing and moving each place to the nearest open ground.

const NAMES := ["None", "Vanguard", "Line", "Circle", "Arc", "Staggered", "Square", "Sandwich"]
enum { NONE, VANGUARD, LINE, CIRCLE, ARC, STAGGERED, SQUARE, SANDWICH }

## Number pad keys -> facing (the LEADER_AT_* directions).
const NUMPAD := {
	KEY_KP_8: Vector2(0, -1), KEY_KP_9: Vector2(1, -1), KEY_KP_6: Vector2(1, 0), KEY_KP_3: Vector2(1, 1),
	KEY_KP_2: Vector2(0, 1), KEY_KP_1: Vector2(-1, 1), KEY_KP_4: Vector2(-1, 0), KEY_KP_7: Vector2(-1, -1),
}


static func _range(u: Unit) -> int:
	var r := 1
	for a in u.utype.get("attacks", []):
		r = maxi(r, int(a["range"]))
	return r


## Unit::max_attack_range > 1: an archer, a war machine.
static func _ranged(u: Unit) -> bool:
	return _range(u) > 1


## Alternating places along a line through the origin: 0, +1, -1, +2, -2 ...
## (tSelected%2 ? right : left).
static func _alt(i: int) -> int:
	return (i + 1) / 2 if i % 2 == 1 else -(i / 2)


## Splits the men into close and ranged fighters as vanguard_formation and
## arc_formation do: no more ranged than close + 4, at most five ranged.
static func _split(men: Array, cap := true) -> Array:
	var rng: Array = men.filter(_ranged)
	var close: Array = men.filter(func(u): return not _ranged(u))
	if cap:
		while rng.size() > close.size() + 4:
			close.append(rng.pop_back())
			close.append(rng.pop_back())
		while rng.size() > 5:
			close.append(rng.pop_back())
	close.sort_custom(func(a, b): return _range(a) < _range(b))
	return [close, rng]


## Places (frame offsets) for each of `men`, the general standing at the origin.
static func offsets(kind: int, men: Array) -> Dictionary:
	var out := {}
	match kind:
		LINE:
			# line_formation: one line through the general, the shortest reach nearest him
			var sorted := men.duplicate()
			sorted.sort_custom(func(a, b): return _range(a) < _range(b))
			for i in sorted.size():
				out[sorted[i]] = Vector2(_alt(i + 1), 0)
		STAGGERED:
			# staggered_formation: the same line, every other pair a step forward;
			# ranged men come in pairs at every fourth place
			var sp := _split(men, false)
			var close: Array = sp[0]
			var rng: Array = sp[1]
			var seq: Array = []
			var t := 1
			while not close.is_empty() or not rng.is_empty():
				if t % 4 == 3 and not rng.is_empty():
					seq.append(rng.pop_front())
					if not rng.is_empty():
						seq.append(rng.pop_front())
						t += 1
				elif not close.is_empty():
					seq.append(close.pop_front())
				else:
					seq.append(rng.pop_front())
				t += 1
			for i in seq.size():
				out[seq[i]] = Vector2(_alt(i + 1), ((i + 2) / 2) % 2)
		CIRCLE:
			# circle_formation: up to four ranged men at the general's corners,
			# the rest on a ring of radius 4, or ((n-1)/5+2) for four or more
			var rng: Array = men.filter(_ranged).slice(0, 4)
			var others: Array = men.filter(func(u): return not u in rng)
			var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]
			for i in rng.size():
				out[rng[i]] = corners[i]
			var n := others.size()
			var r := 4.0 if n < 4 else float((n - 1) / 5 + 2)
			for i in n:
				var a := TAU * i / n
				out[others[i]] = Vector2(sin(a), cos(a)) * r
		VANGUARD:
			# vanguard_formation: a wedge of close fighters, its point two to four
			# places ahead, and the ranged men in a smaller wedge behind its point
			var sp := _split(men)
			var close: Array = sp[0]
			var rng: Array = sp[1]
			var tip := 2 if rng.is_empty() else (3 if rng.size() < 5 else 4)
			for i in close.size():
				var k := (i + 1) / 2
				out[close[i]] = Vector2(k if i % 2 == 1 else -k, tip - k)
			for i in rng.size():
				var k := (i + 1) / 2
				out[rng[i]] = Vector2(k if i % 2 == 1 else -k, tip - 2 - k)
		ARC:
			# arc_formation: the close fighters on an arc of 2.5 radians bowed toward
			# the enemy, the ranged men on a smaller arc behind them
			var sp := _split(men)
			var close: Array = sp[0]
			var rng: Array = sp[1]
			var nc := close.size()
			var nr := rng.size()
			var rc := 3.0 if nc < 4 else float((nc - 1) / 2 + (2 if nc < 8 else 4))
			var rr := 3.0 if nr < 4 else float(nr / 2 + 2)
			var tip := 2.0 if nr == 0 else (3.0 if nr < 5 else 4.0)
			for i in nc:
				var a := 2.5 / maxf(1.0, nc) * ((i + 1) / 2) * (1 if i % 2 == 1 else -1)
				out[close[i]] = Vector2(0, tip - rc) + Vector2(sin(a), cos(a)) * rc
			for i in nr:
				var a := 2.5 / maxf(1.0, nr) * ((i + 1) / 2) * (1 if i % 2 == 1 else -1)
				out[rng[i]] = Vector2(0, tip - 2.0 - rr) + Vector2(sin(a), cos(a)) * rr
		SQUARE:
			# square_formation: a block of min(4, n/5+2) files, the general first
			var files := mini(4, (men.size() + 1) / 5 + 2)
			var all := [null] + men
			var rows := (all.size() - 1) / files + 1
			for t in range(1, all.size()):
				out[all[t]] = Vector2(t % files - files / 2, rows / 2 - t / files)
		SANDWICH:
			# sandwich_formation: close fighters in a rank beside the general,
			# every other pair a step forward; the ranged men in a rank behind
			var sp := _split(men, false)
			var close: Array = sp[0]
			var rng: Array = sp[1]
			for i in close.size():
				var x := (i / 2 + 1) * (1 if i % 2 == 0 else -1)
				out[close[i]] = Vector2(x, ((i + 2) / 2) % 2)
			for i in rng.size():
				out[rng[i]] = Vector2(_alt(i), -1)
	return out


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
	# the eight directions of the original
	var f := facing.normalized() if facing.length() > 0.01 else Vector2(0, 1)
	f = Vector2(signf(roundf(f.x * 1.2)), signf(roundf(f.y * 1.2)))
	if f == Vector2.ZERO:
		f = Vector2(0, 1)
	var right := Vector2(-f.y, f.x)
	var taken := {}
	out[general] = g.world.nearest_walkable(at)
	taken[out[general]] = true
	var offs := offsets(kind, men)
	for u in men:
		var o: Vector2 = offs.get(u, Vector2.ZERO)
		var c := Vector2i((Vector2(at) + right * o.x + f * o.y).round())
		c = g.world.nearest_walkable(c)
		var tries := 0
		while taken.has(c) and tries < 24:
			c = g.world.nearest_walkable(c + Vector2i(tries % 3 - 1, tries / 3 % 3 - 1))
			tries += 1
		taken[c] = true
		out[u] = c
	return out
