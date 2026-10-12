class_name DrawRecorder
extends RefCounted
## Stands in for a CanvasItem while an object's render(cv) runs: bitmaps are kept
## as [texture, top-left offset, modulate] for the 3D view to turn into cards, and
## every other drawing call is kept for the screen overlay to replay.

var textures: Array = []      # [Texture2D, Vector2, Color]
var vectors: Array = []       # [method name, args]


func clear() -> void:
	textures.clear()
	vectors.clear()


func draw_texture(tex: Texture2D, pos: Vector2, modulate := Color.WHITE) -> void:
	if tex:
		textures.append([tex, pos, modulate])


func draw_line(a: Vector2, b: Vector2, col: Color, width := -1.0, aa := false) -> void:
	vectors.append(["draw_line", [a, b, col, width, aa]])


func draw_rect(r: Rect2, col: Color, filled := true, width := -1.0) -> void:
	vectors.append(["draw_rect", [r, col, filled, width]])


func draw_polyline(pts: PackedVector2Array, col: Color, width := -1.0, aa := false) -> void:
	vectors.append(["draw_polyline", [pts, col, width, aa]])


func draw_circle(pos: Vector2, r: float, col: Color) -> void:
	vectors.append(["draw_circle", [pos, r, col]])


func draw_polygon(pts: PackedVector2Array, cols: PackedColorArray, uvs := PackedVector2Array(), tex: Texture2D = null) -> void:
	vectors.append(["draw_polygon", [pts, cols, uvs, tex]])


func draw_colored_polygon(pts: PackedVector2Array, col: Color, uvs := PackedVector2Array(), tex: Texture2D = null) -> void:
	vectors.append(["draw_colored_polygon", [pts, col, uvs, tex]])


func draw_string(font: Font, pos: Vector2, text: String, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, size := 16, col := Color.WHITE) -> void:
	vectors.append(["draw_string", [font, pos, text, align, width, size, col]])
