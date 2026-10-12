extends Node
## Prints the picture names in a ResourceIdx file: -- I_SPICT.RES [filter]
func _ready() -> void:
	Assets.load_install()
	var a := OS.get_cmdline_user_args()
	var idx := Assets._idx(Assets._res_path(a[0]))
	var names := idx.keys().filter(func(k): return a.size() < 2 or k.contains(a[1]))
	print(a[0], ": ", names)
	get_tree().quit()
