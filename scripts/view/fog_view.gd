class_name FogView
extends Node2D
## Black shroud over unexplored land and a dim veil over land not currently seen.

const SHADER := """
shader_type canvas_item;
uniform sampler2D fog : filter_linear;
uniform vec2 map_size;
void fragment() {
	vec2 loc = UV * map_size;
	float v = texture(fog, loc / map_size).r;
	COLOR = vec4(0.0, 0.0, 0.0, 1.0 - v);
}
"""

var map_w := 0
var map_h := 0
var image: Image
var texture: ImageTexture


func build(w: int, h: int) -> void:
	map_w = w
	map_h = h
	image = Image.create(w, h, false, Image.FORMAT_L8)
	texture = ImageTexture.create_from_image(image)
	var sh := Shader.new()
	sh.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("fog", texture)
	mat.set_shader_parameter("map_size", Vector2(w, h))
	material = mat
	z_index = 50
	queue_redraw()


## `data` holds one byte per location: 0 unexplored, 1 explored, 2 visible.
func update_from(data: PackedByteArray) -> void:
	var px := PackedByteArray()
	px.resize(data.size())
	for i in data.size():
		var v := data[i]
		px[i] = 255 if v == 2 else (150 if v == 1 else 0)
	image.set_data(map_w, map_h, false, Image.FORMAT_L8, px)
	texture.update(image)


func _draw() -> void:
	if map_w == 0:
		return
	var pts := PackedVector2Array([
		Iso.to_screen(Vector2(0, 0)), Iso.to_screen(Vector2(map_w, 0)),
		Iso.to_screen(Vector2(map_w, map_h)), Iso.to_screen(Vector2(0, map_h))])
	var uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	draw_polygon(pts, PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]), uvs)
