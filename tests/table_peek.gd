extends Node
func _ready() -> void:
	Assets.load_install()
	var name := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "FIRM"
	var t: Array = Assets.table(name)
	print(t[0].keys())
	for r in t:
		print(r)
	get_tree().quit()
