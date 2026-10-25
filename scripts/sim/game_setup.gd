class_name GameSetup
extends RefCounted
## The game settings of the start screen (Config, oconfig.cpp; the setup pages of
## ogamsing.cpp): kingdoms, treasure, the computer's aggressiveness, the map and
## its towns, natural resources and events, and the goals. The eight difficulty
## levels set them all at once (Config::change_difficulty); changing any one
## makes the setting "custom". The difficulty rating (single_player_difficulty)
## scales the final score.

enum { NONE, LOW, MODERATE, HIGH, VERY_HIGH }
const CUSTOM := 8
const DIFFICULTY_NAMES := ["Easiest", "Very easy", "Easy", "Below average", "Average", "Above average", "Hard", "Hardest", "Custom"]

const START_CASH := [4000, 7000, 12000, 20000]       # NationBase::init_cash, by treasure level 1..4
const START_LIVE := [800, 1500, 2500, 4000]
const START_FOOD := 5000
const TOWN_COUNTS := [7, 15, 30]                     # "Few", "Normal", "Many" independent towns
const TREASURE_NAMES := ["Small", "Moderate", "Large", "Huge"]
const AGGRESSIVE_NAMES := ["None", "Low", "Moderate", "High", "Very high"]
const LEVEL_NAMES := ["Low", "Moderate", "High"]
const EVENT_NAMES := ["Never", "Seldom", "Occasionally", "Frequently"]

## Config::change_difficulty's tables, easiest to hardest.
const PRESETS := {
	"ai_humans": [1, 2, 2, 3, 3, 3, 3, 3],
	"ai_fryhtans": [1, 1, 2, 2, 3, 3, 3, 3],
	"treasure": [VERY_HIGH, VERY_HIGH, HIGH, MODERATE, MODERATE, MODERATE, LOW, LOW],
	"ai_treasure": [LOW, LOW, MODERATE, MODERATE, MODERATE, HIGH, VERY_HIGH, VERY_HIGH],
	"aggressiveness": [NONE, NONE, LOW, MODERATE, MODERATE, HIGH, HIGH, VERY_HIGH],
	"indep_towns": [30, 30, 30, 15, 15, 15, 7, 7],
	"raw_sites": [7, 7, 7, 6, 5, 5, 4, 3],
	"explore": [true, true, true, true, false, false, false, false],
	"fog": [false, false, false, false, false, true, true, true],
	"town_emerge": [true, true, true, true, true, true, true, true],
	"resistance": [LOW, LOW, MODERATE, MODERATE, MODERATE, HIGH, HIGH, HIGH],
	"random_events": [NONE, NONE, LOW, LOW, LOW, MODERATE, MODERATE, MODERATE],
	"nation_emerge": [false, false, false, true, true, true, true, true],
	"mine_nearby": [true, true, true, false, false, false, false, false],
	"random_start": [false, false, false, false, false, false, true, true],
	"spy_methodology": [true, true, true, true, false, false, false, false],
}


## Config::default_game_setting, which ends by choosing "very easy".
static func defaults() -> Dictionary:
	var s := {
		"difficulty": 1, "ai_humans": 4, "ai_fryhtans": 2,
		"goal_destroy_monster": false, "goal_population_flag": false, "goal_economic_flag": false,
		"goal_total_flag": false, "goal_year_flag": false, "goal_alliance_flag": false,
		"goal_population": 300, "goal_economic": 1200, "goal_total": 1800, "goal_years": 20,
		"terrain_set": 1, "color": 0,
	}
	apply_difficulty(s, 1)
	return s


static func apply_difficulty(s: Dictionary, level: int) -> void:
	s["difficulty"] = level
	if level < 0 or level >= CUSTOM:
		return
	for k in PRESETS:
		s[k] = PRESETS[k][level]


## Whether the settings are still those of their difficulty level.
static func matches_level(s: Dictionary, level: int) -> bool:
	if level < 0 or level >= CUSTOM:
		return false
	for k in PRESETS:
		if s.get(k) != PRESETS[k][level]:
			return false
	return true


## Config::single_player_difficulty: `human` for a human kingdom, else a Fryhtan one.
static func rating(s: Dictionary, human := true) -> int:
	var score := 10
	score += (int(s.get("ai_humans", 0)) + int(s.get("ai_fryhtans", 0))) * 6
	if not s.get("explore", true):
		score += 7
	if s.get("fog", false):
		score += 7
	if human:
		score += (7 - int(s.get("raw_sites", 6))) * 5
	else:
		score += int(s.get("raw_sites", 6)) * 2
	score += (4 - int(s.get("treasure", MODERATE))) * 6
	score += (int(s.get("ai_treasure", MODERATE)) - 1) * 6
	score += (int(s.get("aggressiveness", MODERATE)) - 1) * 10
	score += (int(s.get("resistance", MODERATE)) - 1) * 5
	if s.get("nation_emerge", true):
		score += 6
	score += int(s.get("random_events", 0)) * 2
	if human and not s.get("mine_nearby", false):
		score += 6
	if human and not s.get("spy_methodology", false):
		score += 2
	return score


## Config::multi_player_difficulty: each remote player counts as a computer rival.
static func rating_multi(s: Dictionary, remote_players: int, human := true) -> int:
	var ai := int(s.get("ai_humans", 0)) + int(s.get("ai_fryhtans", 0))
	var total := mini(ai + remote_players, Defs.MAX_NATION - 1)
	return rating(s, human) + (total - ai) * 6


## Fills Game.start's config from the settings.
static func to_config(s: Dictionary, cfg: Dictionary) -> Dictionary:
	for k in ["treasure", "ai_treasure", "aggressiveness", "raw_sites", "explore", "fog", "town_emerge",
			"resistance", "random_events", "nation_emerge", "mine_nearby", "random_start", "spy_methodology",
			"goal_destroy_monster", "goal_population_flag", "goal_economic_flag", "goal_total_flag",
			"goal_year_flag", "goal_alliance_flag", "goal_population", "goal_economic", "goal_total", "goal_years"]:
		cfg[k] = s[k]
	cfg["terrain_set"] = int(s.get("terrain_set", 1))
	cfg["color"] = int(s.get("color", 0))
	cfg["setup"] = true
	cfg["ai_count"] = int(s["ai_humans"])
	cfg["fryhtan_count"] = int(s["ai_fryhtans"])
	cfg["indep_towns"] = int(s["indep_towns"])
	cfg["reveal"] = false
	cfg["difficulty_rating"] = rating(s, not Defs.is_monster_code(str(cfg.get("race", ""))))
	return cfg


## The cash and food a kingdom starts with (NationBase::init_cash).
static func start_cash(cfg: Dictionary, ai: bool, fryhtan: bool) -> Array:
	var level := int(cfg.get("ai_treasure" if ai else "treasure", MODERATE))
	var cash := float(START_CASH[clampi(level, 1, 4) - 1])
	var food := float(START_FOOD)
	var live := 0.0
	if fryhtan:
		cash /= 2.0
		food /= 2.0
		live = float(START_LIVE[clampi(int(cfg.get("treasure", MODERATE)), 1, 4) - 1])
	return [cash, food, live]


## TownArray::independent_town_resistance
static func town_resistance(cfg: Dictionary, rng: RandomNumberGenerator) -> int:
	match int(cfg.get("resistance", MODERATE)):
		LOW: return 50 + rng.randi() % 30
		MODERATE: return 70 + rng.randi() % 30
		HIGH: return 90 + rng.randi() % 10
	return 60 + rng.randi() % 40
