extends Node
## Prints the PLANT table and the plant id of each map-tree bitmap (debug aid).
func _ready() -> void:
	if Assets.load_install() != "":
		get_tree().quit(1); return
	for r in Assets.table("PLANT"):
		print("PLANT ", r)
	var ids := {}
	for i in Assets.plant_bitmaps.size():
		var b: Dictionary = Assets.plant_bitmaps[i]
		ids[b["plant"]] = ids.get(b["plant"], []) + [i]
	print("BITMAPS by plant: ", ids)
	get_tree().quit()
