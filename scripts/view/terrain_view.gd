class_name TerrainView
extends Node2D
## Renders the terrain as one isometric diamond. A shader blends the original
## terrain textures (dark grass, light grass, dirt) using per-corner weights.

const SHADER := """
shader_type canvas_item;
uniform sampler2D tex_g : filter_linear, repeat_enable;
uniform sampler2D tex_f : filter_linear, repeat_enable;
uniform sampler2D tex_d : filter_linear, repeat_enable;
uniform sampler2D weights : filter_linear;
uniform sampler2D noise : filter_linear, repeat_enable;
uniform vec2 map_size;

void fragment() {
	vec2 loc = UV * map_size;                       // location coordinates
	vec2 tuv = loc * 32.0 / 512.0;                  // 512px textures, 32px per location
	vec3 w = texture(weights, (loc + 0.5) / (map_size + 1.0)).rgb;
	float n = texture(noise, loc / 23.0).r - 0.5;
	w += vec3(n, -n, n * 1.4) * 0.6;
	w = max(w, vec3(0.0));
	w = pow(w, vec3(4.0));
	w /= max(w.r + w.g + w.b, 0.0001);
	vec3 c = texture(tex_g, tuv).rgb * w.r + texture(tex_f, tuv).rgb * w.g + texture(tex_d, tuv).rgb * w.b;
	// Hills: shade dirt slopes facing the light (top-left) brighter.
	float dx = texture(weights, (loc + vec2(1.0, 0.5)) / (map_size + 1.0)).b - texture(weights, (loc + vec2(0.0, 0.5)) / (map_size + 1.0)).b;
	float dy = texture(weights, (loc + vec2(0.5, 1.0)) / (map_size + 1.0)).b - texture(weights, (loc + vec2(0.5, 0.0)) / (map_size + 1.0)).b;
	c *= 1.0 - (dx + dy) * 0.18;
	COLOR = vec4(c, 1.0);
}
"""

var map_w := 0
var map_h := 0
var _weights_tex: ImageTexture


func build(world: WorldMap) -> void:
	map_w = world.w
	map_h = world.h
	var img := Image.create(world.w + 1, world.h + 1, false, Image.FORMAT_RGB8)
	for y in world.h + 1:
		for x in world.w + 1:
			var t := world.corner(x, y)
			img.set_pixel(x, y, Color(1 if t == 0 else 0, 1 if t == 1 else 0, 1 if t == 2 else 0))
	_weights_tex = ImageTexture.create_from_image(img)
	var nimg := Image.create(64, 64, false, Image.FORMAT_L8)
	var fn := FastNoiseLite.new()
	fn.frequency = 0.15
	for y in 64:
		for x in 64:
			# tileable noise by sampling a torus
			var a := TAU * x / 64.0
			var b := TAU * y / 64.0
			var v := fn.get_noise_3d(cos(a) * 8.0 + sin(b) * 3.0, sin(a) * 8.0, cos(b) * 8.0)
			nimg.set_pixel(x, y, Color(v * 0.5 + 0.5, 0, 0))
	var sh := Shader.new()
	sh.code = SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("tex_g", Assets.terrain_textures.get("G"))
	mat.set_shader_parameter("tex_f", Assets.terrain_textures.get("F"))
	mat.set_shader_parameter("tex_d", Assets.terrain_textures.get("D"))
	mat.set_shader_parameter("weights", _weights_tex)
	mat.set_shader_parameter("noise", ImageTexture.create_from_image(nimg))
	mat.set_shader_parameter("map_size", Vector2(map_w, map_h))
	material = mat
	queue_redraw()


func _draw() -> void:
	if map_w == 0:
		return
	var pts := PackedVector2Array([
		Iso.to_screen(Vector2(0, 0)), Iso.to_screen(Vector2(map_w, 0)),
		Iso.to_screen(Vector2(map_w, map_h)), Iso.to_screen(Vector2(0, map_h))])
	var uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	draw_polygon(pts, PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]), uvs)
