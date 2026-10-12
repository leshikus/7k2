extends Node
## Parses every premade scenario and prints counts plus a terrain checksum.
func _ready() -> void:
	Assets.load_install()
	for info in ScenarioFile.list_premade():
		var s := ScenarioFile.new()
		var t0 := Time.get_ticks_msec()
		var ok := s.load_file(info["path"])
		var t1 := Time.get_ticks_msec()
		var cor := s.terrain_corners() if ok else PackedByteArray()
		var t2 := Time.get_ticks_msec()
		var sum := 0
		for i in cor.size():
			sum = (sum * 31 + cor[i]) % 1000000007
		var soldiers := 0
		for f in s.firms:
			soldiers += f["soldiers"].size()
		print("%s ok=%s err=%s units=%d towns=%d nations=%d firms=%d soldiers=%d sites=%d rocks=%d dirt=%d terrain=%d parse=%dms gen=%dms" % [
			info["path"].get_file(), ok, s.error, s.units.size(), s.towns.size(), s.nations.size(), s.firms.size(), soldiers,
			s.sites.size(), s.rocks.size(), s.dirts.size(), sum, t1 - t0, t2 - t1])
	get_tree().quit()
