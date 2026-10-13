class_name HallOfFame
extends RefCounted
## The Hall of Fame (ogamhall.cpp): the ten best games of human and of Fryhtan
## rulers. A game's final score is its total ranking score times the difficulty
## rating of its settings, divided by 100 (ogamend.cpp disp_score).

const PATH := "user://hall_of_fame.json"
const SIZE := 10


## Config::human_difficulty_rating, approximated from the start screen's
## settings: more rivals and Fryhtans and less gold make a harder game.
static func difficulty_rating(cfg: Dictionary) -> int:
	var r := 40 + 12 * int(cfg.get("ai_count", 3)) + 12 * int(cfg.get("fryhtan_count", 1))
	r += {1500: 20, 3000: 0, 6000: -20}.get(int(cfg.get("cash", 3000)), 0)
	r += int(cfg.get("lairs", 4)) / 2
	if cfg.get("reveal", false):
		r -= 15
	return clampi(r, 10, 200)


static func load_all() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {"human": [], "fryhtan": []}
	var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return d if d is Dictionary else {"human": [], "fryhtan": []}


## Records a finished game; returns its place (1..10) or 0.
static func add(g: Game, final_score: int, rating: int) -> int:
	var p := g.player()
	if p == null:
		return 0
	var all := load_all()
	var kind := "fryhtan" if p.is_fryhtan else "human"
	var list: Array = all.get(kind, [])
	var entry := {"king": p.king.unit_name if p.king and is_instance_valid(p.king) else p.name, "kingdom": p.name,
		"race": p.race, "start": g.year0, "end": g.year0 + g.day / 365, "score": final_score,
		"population": Goals.score(g, p, 1), "rating": rating}
	var place := 0
	for i in list.size():
		if final_score > int(list[i]["score"]):
			list.insert(i, entry)
			place = i + 1
			break
	if place == 0 and list.size() < SIZE:
		list.append(entry)
		place = list.size()
	if place == 0:
		return 0
	all[kind] = list.slice(0, SIZE)
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(all))
	return place


static func describe() -> String:
	var all := load_all()
	var s := ""
	for kind in ["human", "fryhtan"]:
		s += "[b]%s[/b]\n" % ("Human rulers" if kind == "human" else "Fryhtan rulers")
		var list: Array = all.get(kind, [])
		if list.is_empty():
			s += "  none yet\n"
		for i in list.size():
			var e: Dictionary = list[i]
			s += "  %2d. %s of the %s — %d (%d–%d, population %d, difficulty %d)\n" % [i + 1, e["king"], e["kingdom"], int(e["score"]),
				int(e["start"]), int(e["end"]), int(e["population"]), int(e["rating"])]
		s += "\n"
	return s
