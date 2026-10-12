extends Node
## Writes one image of every map-tree species (largest growth stage) for reference.
func _ready() -> void:
	if Assets.load_install() != "":
		get_tree().quit(1); return
	var out := "C:/Users/admin/sk2assets/ref"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("out="): out = a.substr(4)
	var ims := []
	for i in range(2, Assets.plant_bitmaps.size(), 3):
		var im: Image = Assets.plant_bitmaps[i]["tex"].get_image()
		im.convert(Image.FORMAT_RGBA8)
		ims.append(im)
	var w := 0; var h := 0
	for im in ims: w += im.get_width() + 6; h = maxi(h, im.get_height())
	var sheet := Image.create(w, h, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.55, 0.6, 0.5))
	var x := 0
	for im in ims:
		sheet.blend_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i(x, h - im.get_height()))
		x += im.get_width() + 6
	sheet.save_png(out.path_join("plants.png"))
	get_tree().quit()
