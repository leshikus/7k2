extends Node
func _ready() -> void:
	Assets.load_install()
	Defs.load_from_assets()
	var missing := []
	var found := 0
	for code in Defs.unit_types:
		for act in ["SEL", "ACK", "DIE", "A1"]:
			for f in Assets.sound_files("S", code, act):
				if Assets.sound(f) == null: missing.append(f)
				else: found += 1
	for code in Defs.HUMAN_FIRMS:
		for f in Assets.sound_files("F", code, "SEL"):
			if Assets.sound(f) == null: missing.append(f)
			else: found += 1
	var s := Assets.sound("CE-SEL1")
	print("streams found=", found, " missing=", missing, " sample: ", s.mix_rate if s else -1, "Hz len=", s.data.size() if s else 0)
	print("RESULT: ", "PASS" if missing.is_empty() and found > 100 else "FAIL")
	get_tree().quit()
