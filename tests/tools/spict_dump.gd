extends Node
## Saves I_SPICT.RES pictures whose names contain a filter as PNGs: -- COINS <dir>
func _ready() -> void:
	Assets.load_install()
	var a := OS.get_cmdline_user_args()
	for k in Assets._idx(Assets._res_path("I_SPICT.RES")).keys():
		if k.contains(a[0]):
			var t: Texture2D = Assets.spict(k, Color.WHITE)
			if t:
				t.get_image().save_png(a[1].path_join(k + ".png"))
				print(k, " ", t.get_size())
	get_tree().quit()
