extends Node
## Prints every unit sprite (with its actions), firm and monster of the install.
func _ready() -> void:
	if Assets.load_install() != "":
		get_tree().quit(1); return
	Defs.load_from_assets()
	for code in Defs.unit_types:
		var t: Dictionary = Defs.unit_types[code]
		var acts := []
		for k in ["S", "M", "A1", "A2", "A3", "D", "I"]:
			if Assets.has_action(code, k):
				acts.append("%s:%d" % [k, Assets.action_len(code, k, 0)])
		print("U|%s|%s|%s|%s|%s|fly=%s|%s" % [code, t["name"], t["race"], t["class"], t["attacks"].map(func(x): return x["action"]+"/"+str(x["range"])+"/"+x["bullet"]), t["flying"], acts])
	for f in Defs.firm_types:
		print("F|%s|%s" % [f, Defs.firm_types[f]["name"]])
	for m in Defs.monsters:
		print("M|%s|%s|%d" % [m["unit"], m["name"], m["level"]])
	get_tree().quit()
