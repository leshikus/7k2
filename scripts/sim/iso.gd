class_name Iso
## Isometric projection used by Seven Kingdoms II (oworldmt.h ZOOM_LOC_* constants):
## one location step in x moves the screen by (+32, +16), one step in y by (-32, +16).

const HALF_W := 32.0
const HALF_H := 16.0


static func to_screen(loc: Vector2) -> Vector2:
	return Vector2((loc.x - loc.y) * HALF_W, (loc.x + loc.y) * HALF_H)


static func to_loc(screen: Vector2) -> Vector2:
	var a := screen.x / HALF_W
	var b := screen.y / HALF_H
	return Vector2((a + b) * 0.5, (b - a) * 0.5)


## Direction 0..7 (N, NE, E, SE, S, SW, W, NW) of a movement in location space,
## measured on screen so it matches the pre-rendered sprite facings.
static func dir_of(delta_loc: Vector2) -> int:
	var s := to_screen(delta_loc)
	if s.length_squared() < 0.0001:
		return -1
	var ang := atan2(s.x, -s.y * 2.0)   # 0 = up on screen, clockwise; undo the 2:1 squash
	return posmod(int(round(ang / (PI / 4.0))), 8)


## Load-time bitmap offset correction applied by the original to every sprite,
## firm, town, plant and raw-site bitmap ("modify offset_x/y for 7k2" in
## ofirmres.cpp, osfrmres.cpp, otownres.cpp, oplant.cpp, orawres.cpp):
##   offset_x += -w*32/2 - (-w*ZOOM_LOC_X_WIDTH/2 + -h*ZOOM_LOC_Y_WIDTH/2)
##   offset_y += -h*32/2 - (-w*ZOOM_LOC_X_HEIGHT/2 + -h*ZOOM_LOC_Y_HEIGHT/2)
static func bitmap_adjust(loc_w: int, loc_h: int) -> Vector2:
	return Vector2(-loc_h * 16.0, loc_w * 8.0 - loc_h * 8.0)
