extends Node
func _ready() -> void:
	Assets.load_install()
	var t: Array = Assets.table("FIRM")
	print(t[0].keys())
	for r in t:
		print(r["CODE"], " ", r)
	get_tree().quit()
