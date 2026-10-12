extends Node
## Lists the treasures lying on each premade scenario's map, for screenshots:
##   godot --headless --path . res://tests/tools/treasure_list.tscn
func _ready() -> void:
	if Assets.load_install() != "":
		get_tree().quit(1); return
	Defs.load_from_assets()
	for info in ScenarioFile.list_premade():
		var g := Game.new()
		add_child(g)
		g.start({"scenario": info["path"]})
		for t in g.treasures:
			print("TREASURE %s | %s at %s" % [info["path"].get_file().get_basename(), t.title(), t.cell])
		g.queue_free()
		await get_tree().process_frame
	get_tree().quit()
