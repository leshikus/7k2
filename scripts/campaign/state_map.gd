class_name StateMap
extends RefCounted
## The campaign's map of provinces (StateArray, ostate.cpp): a few states on a
## 100 x 100 map, each the region nearest its capital, with their neighbours.
## The original weighs distances with random strengths; additive weights are
## used here, which keeps every province in one piece.

const W := 100
const H := 100

## {id, cx, cy, nation, border, adj: {id: true}}; index 0 is unused (ids start at 1).
var states: Array = [null]
var cells := PackedByteArray()


func size() -> int:
	return states.size() - 1


func get_state(id: int) -> Dictionary:
	return states[id] if id >= 1 and id < states.size() else {}


func generate(count: int, rng: RandomNumberGenerator) -> void:
	var sep := sqrt(W * H / float(count))
	for attempt in 1000:
		states = [null]
		var ok := true
		for s in range(1, count + 1):
			var placed := false
			for trial in s * 16 + 1:
				var x := rng.randi_range(0, W - 1)
				var y := rng.randi_range(0, H - 1)
				var close := false
				for t in range(1, s):
					var o: Dictionary = states[t]
					if maxf(absf(x - o["cx"]), absf(y - o["cy"])) * 2.0 < sep:
						close = true
						break
				if not close:
					states.append({"id": s, "cx": x, "cy": y, "nation": 0, "border": false, "adj": {},
						"w": rng.randf_range(-6.0, 6.0), "sx": rng.randf_range(0.75, 1.3)})
					placed = true
					break
			if not placed:
				ok = false
				break
		if ok:
			break
	cells.resize(W * H)
	for y in H:
		for x in W:
			var best := 1
			var bd := INF
			for s in range(1, states.size()):
				var st: Dictionary = states[s]
				var dx: float = (x - st["cx"]) * st["sx"]
				var dy: float = (y - st["cy"]) / st["sx"]
				var d: float = sqrt(dx * dx + dy * dy) + st["w"]
				if d < bd:
					bd = d
					best = s
			cells[y * W + x] = best
	for y in H:
		for x in W:
			var s := cells[y * W + x]
			if x == 0 or y == 0 or x == W - 1 or y == H - 1:
				states[s]["border"] = true
			for o in [Vector2i(1, 0), Vector2i(0, 1)]:
				var nx: int = x + o.x
				var ny: int = y + o.y
				if nx < W and ny < H:
					var t := cells[ny * W + nx]
					if t != s:
						states[s]["adj"][t] = true
						states[t]["adj"][s] = true
	for s in range(1, states.size()):
		states[s].erase("w")
		states[s].erase("sx")


func state_at(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= W or y >= H:
		return 0
	return cells[y * W + x]


func is_adjacent(a: int, b: int) -> bool:
	return a != b and get_state(a).get("adj", {}).has(b)


func nation_state_count(nid: int) -> int:
	var n := 0
	for s in range(1, states.size()):
		if states[s]["nation"] == nid:
			n += 1
	return n


func is_adjacent_to_nation(state: int, nid: int) -> bool:
	for t in get_state(state).get("adj", {}):
		if states[t]["nation"] == nid:
			return true
	return false


func are_nations_adjacent(a: int, b: int) -> bool:
	for s in range(1, states.size()):
		if states[s]["nation"] == a and is_adjacent_to_nation(s, b):
			return true
	return false


func to_dict() -> Dictionary:
	var sts := []
	for s in range(1, states.size()):
		var st: Dictionary = states[s].duplicate(true)
		st["adj"] = st["adj"].keys()
		sts.append(st)
	return {"states": sts, "cells": Marshalls.raw_to_base64(cells)}


func from_dict(d: Dictionary) -> void:
	states = [null]
	for st in d.get("states", []):
		var s: Dictionary = st.duplicate(true)
		var adj := {}
		for a in s.get("adj", []):
			adj[int(a)] = true
		s["adj"] = adj
		s["id"] = int(s["id"])
		s["nation"] = int(s["nation"])
		states.append(s)
	cells = Marshalls.base64_to_raw(d.get("cells", ""))
