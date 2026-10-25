class_name Weather
extends RefCounted
## Seasonal weather after oweather.cpp. Clouds form in spells of a few days;
## strong clouds bring rain (rain_scale = strength*2-8) and sometimes lightning.
## The shipped game has snow disabled (Weather::snow_scale returns 0), so
## there is none here either.

const RAIN_CLOUD := 1
const WINDY := 2
const LIGHTNING_CLOUD := 4

var season_phase := 0
var avg_temp := 17        # 35 - |latitude|/90*40 at about 40 degrees
var temp_amp := 12
var cloud_str := 0
var cloud_len := 5
var cloud_type := 0
var wind_dir := 0
var wind_spd := 10


## Weather::init_date: the average temperature and its seasonal swing from
## the latitude (45 for fertile land, 20 for badlands).
func init_latitude(latitude: int) -> void:
	avg_temp = int(35.0 - absf(latitude / 90.0 * 40.0))
	temp_amp = int(17.0 * sin(latitude * PI / 180.0))


func base_temp() -> int:
	return int(avg_temp + temp_amp * sin(season_phase / 365.0 * TAU))


## Weather::next_day (cloud generation).
func next_day(rng: RandomNumberGenerator) -> void:
	season_phase = (season_phase + 1) % 365
	wind_dir = (wind_dir + rng.randi_range(0, 4)) % 360
	wind_spd = clampi(wind_spd + rng.randi_range(0, 8) - 4, -10, 110)
	if cloud_len > 0:
		cloud_len -= 1
		return
	var t := base_temp()
	var max_str := 10 if t >= 30 else (4 if t <= 18 else (t - 18) / 2 + 4)
	cloud_str = maxi(0, rng.randi_range(0, max_str + 3) - 3)
	cloud_len = 2 + rng.randi_range(0, 2) + rng.randi_range(0, 2)
	cloud_type = 0
	if cloud_str > 4:
		if rng.randi_range(0, 9) < cloud_str:
			cloud_type |= RAIN_CLOUD
		if rng.randi_range(0, 9) < cloud_str - 2:
			cloud_type |= WINDY
	if cloud_type & WINDY == 0 and cloud_str > 4 and rng.randi_range(0, 49) < cloud_str + 2:
		cloud_type |= LIGHTNING_CLOUD


func rain_scale() -> int:
	return cloud_str * 2 - 8 if cloud_str > 4 else 0


func is_lightning() -> bool:
	return cloud_type & LIGHTNING_CLOUD != 0 and rain_scale() > 0


func describe() -> String:
	var r := rain_scale()
	if r <= 0:
		return "Cloudy" if cloud_str >= 3 else "Clear"
	var s := "Light rain" if r <= 2 else ("Rain" if r <= 6 else "Heavy rain")
	if is_lightning():
		s = "Thunderstorm"
	return s


func to_dict() -> Dictionary:
	return {"phase": season_phase, "str": cloud_str, "len": cloud_len, "type": cloud_type, "wdir": wind_dir, "wspd": wind_spd}


func from_dict(d: Dictionary) -> void:
	season_phase = int(d.get("phase", 0))
	cloud_str = int(d.get("str", 0))
	cloud_len = int(d.get("len", 5))
	cloud_type = int(d.get("type", 0))
	wind_dir = int(d.get("wdir", 0))
	wind_spd = int(d.get("wspd", 10))
