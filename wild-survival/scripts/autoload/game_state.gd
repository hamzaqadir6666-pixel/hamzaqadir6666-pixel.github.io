extends Node
## Session-level state shared between scenes: run statistics, flow flags and global signals.

signal notification_posted(title: String, body: String)
signal discovery_made(id: String, count: int, total: int)
signal threat_changed(level: int)

enum Threat { CALM, WATCHED, STALKED, HUNTED }

## When true the main scene skips the menu and starts a run immediately (used by Restart).
var skip_menu := false
var in_game := false

var days_survived := 0
var time_survived := 0.0
var distance_travelled := 0.0
var escapes := 0
var discoveries: Dictionary = {}
var total_discoveries := 0
var cause_of_death := ""
var threat: int = Threat.CALM
var best_time := 0.0

# ---------------------------------------------------------------- campaign
signal objective_changed
signal level_completed(index: int)
signal abilities_changed

## mode: campaign levels with goals, or the classic endless survival run.
enum Mode { CAMPAIGN, ENDLESS }

## Each level: survive `minutes` and find `plants` rare plants. `preds` = lion, tiger, cheetah,
## hyena packs, crocodile, wolves. `speed` / `damage` scale the hunters, `drain` scales hunger and
## thirst, `rain` is how stormy the weather is (0 fair .. 1 monsoon), `start` the hour of day.
const LEVELS := [
	{"name": "First Steps", "minutes": 3.0, "plants": 2, "preds": [1, 1, 1, 1, 2, 0], "speed": 0.84, "damage": 0.65, "drain": 0.8, "rain": 0.15, "start": 7.5,
		"brief": "Learn the jungle. Few hunters roam and they are slow."},
	{"name": "The Green Maze", "minutes": 4.0, "plants": 3, "preds": [2, 2, 1, 1, 2, 0], "speed": 0.9, "damage": 0.8, "drain": 0.9, "rain": 0.3, "start": 8.0,
		"brief": "More territories are taken. Search the undergrowth for rare plants."},
	{"name": "Monsoon", "minutes": 5.0, "plants": 4, "preds": [3, 3, 2, 2, 3, 3], "speed": 0.95, "damage": 0.9, "drain": 1.0, "rain": 0.85, "start": 10.0,
		"brief": "The rains arrive. Rain hides your sound and scent - and theirs. Wolves have come."},
	{"name": "Dusk Hunters", "minutes": 6.0, "plants": 5, "preds": [4, 4, 3, 2, 4, 3], "speed": 1.0, "damage": 1.0, "drain": 1.0, "rain": 0.4, "start": 16.5,
		"brief": "The light is failing and the cats are waking."},
	{"name": "The Long Night", "minutes": 7.0, "plants": 5, "preds": [5, 5, 4, 3, 4, 4], "speed": 1.03, "damage": 1.1, "drain": 1.15, "rain": 0.5, "start": 19.3,
		"brief": "Survive in the dark. Moonpetal lets you see at night."},
	{"name": "Drought", "minutes": 8.0, "plants": 6, "preds": [5, 5, 4, 3, 6, 4], "speed": 1.06, "damage": 1.2, "drain": 1.7, "rain": 0.0, "start": 11.0,
		"brief": "Thirst is the enemy now, and crocodiles guard every shore."},
	{"name": "Blood Moon", "minutes": 9.0, "plants": 7, "preds": [6, 6, 5, 4, 5, 6], "speed": 1.1, "damage": 1.35, "drain": 1.3, "rain": 0.7, "start": 20.0,
		"brief": "EXTREME. Every hunter in the jungle is out tonight, in a storm."},
	{"name": "Apex", "minutes": 12.0, "plants": 8, "preds": [7, 7, 6, 5, 6, 8], "speed": 1.17, "damage": 1.6, "drain": 1.5, "rain": 0.6, "start": 17.5,
		"brief": "EXTREME. Faster, stronger, everywhere. Only a deer that found every gift survives."},
]
## Classic endless run: the full roster at normal strength.
const ENDLESS := {"name": "Endless Survival", "minutes": 0.0, "plants": 0, "preds": [5, 5, 4, 3, 4, 3], "speed": 1.0, "damage": 1.0, "drain": 1.0, "rain": 0.45, "start": 7.5, "brief": ""}

## Permanent gifts from special plants: id -> [name, description]
const ABILITIES := {
	"swift": ["Swift Hooves", "You run faster."],
	"night_vision": ["Night Vision", "You can see in the dark."],
	"iron_hide": ["Iron Hide", "More health."],
	"deep_lungs": ["Deep Lungs", "More stamina."],
	"silent_step": ["Silent Step", "You make far less noise."],
	"keen_senses": ["Keen Senses", "You sense the nearest hunter."],
	"high_leap": ["High Leap", "You jump higher and farther."],
	"otter_blood": ["Otter Blood", "You swim fast without tiring."],
}
const SWIFT_START := 0.8        ## speed multiplier of a deer that has found nothing
const SWIFT_STEP := 0.035       ## added by each Swift Clover
const SWIFT_MAX := 13           ## clovers that still help (0.8 -> 1.255)
const WILDLIFE := ["Lion", "Tiger", "Cheetah", "Hyena", "Wolf", "Crocodile", "Gazelle", "Boar", "Goat", "Buffalo", "Fox", "Junglefowl", "Hawk", "Crow"]

var mode: int = Mode.CAMPAIGN
var level := 0                   ## index into LEVELS
var unlocked := 0                ## highest level reached
var abilities: Dictionary = {}   ## id -> stack count; kept across campaign levels
var plants_found := 0            ## rare plants eaten this level
var spotted: Dictionary = {}     ## wildlife species seen this run
var level_done := false
## Tests and tools: fixed spawn, full-speed deer, fair weather.
var test_mode := false
var _campaign_abilities: Dictionary = {}


func set_mode(m: int) -> void:
	if m == mode:
		return
	if m == Mode.ENDLESS:
		_campaign_abilities = abilities
		abilities = {}
	else:
		abilities = _campaign_abilities
	mode = m
	abilities_changed.emit()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cfg := ConfigFile.new()
	if cfg.load("user://records.cfg") == OK:
		best_time = float(cfg.get_value("records", "best_time", 0.0))
		unlocked = clampi(int(cfg.get_value("campaign", "unlocked", 0)), 0, LEVELS.size() - 1)
		level = clampi(int(cfg.get_value("campaign", "level", 0)), 0, LEVELS.size() - 1)
		var saved: Variant = cfg.get_value("campaign", "abilities", {})
		if saved is Dictionary:
			abilities = saved


func save_progress() -> void:
	if test_mode:
		return
	var cfg := ConfigFile.new()
	cfg.load("user://records.cfg")
	cfg.set_value("records", "best_time", best_time)
	cfg.set_value("campaign", "unlocked", unlocked)
	cfg.set_value("campaign", "level", level)
	cfg.set_value("campaign", "abilities", abilities if mode == Mode.CAMPAIGN else _campaign_abilities)
	cfg.save("user://records.cfg")


func level_info() -> Dictionary:
	return ENDLESS if mode == Mode.ENDLESS else LEVELS[clampi(level, 0, LEVELS.size() - 1)]


func new_campaign() -> void:
	set_mode(Mode.CAMPAIGN)
	level = 0
	abilities = {}
	abilities_changed.emit()
	save_progress()


func has_ability(id: String) -> bool:
	return int(abilities.get(id, 0)) > 0


func stacks(id: String) -> int:
	return int(abilities.get(id, 0))


func grant(id: String) -> int:
	abilities[id] = stacks(id) + 1
	abilities_changed.emit()
	return int(abilities[id])


func speed_multiplier() -> float:
	if test_mode:
		return 1.0
	return SWIFT_START + SWIFT_STEP * mini(stacks("swift"), SWIFT_MAX)


## A rare plant was eaten: counts toward the level goal.
func plant_found() -> void:
	plants_found += 1
	objective_changed.emit()


func spot(species: String) -> bool:
	if spotted.has(species):
		return false
	spotted[species] = true
	return true


func goal_seconds() -> float:
	return float(level_info()["minutes"]) * 60.0


## Campaign goal check, called by the game flow every frame while playing.
func check_objective() -> bool:
	if mode != Mode.CAMPAIGN or level_done or not in_game:
		return false
	var info := level_info()
	if time_survived >= goal_seconds() and plants_found >= int(info["plants"]):
		level_done = true
		unlocked = maxi(unlocked, mini(level + 1, LEVELS.size() - 1))
		level_completed.emit(level)
		return true
	return false


func is_last_level() -> bool:
	return level >= LEVELS.size() - 1


func advance_level() -> void:
	level = mini(level + 1, LEVELS.size() - 1)
	save_progress()


func reset_run() -> void:
	days_survived = 0
	time_survived = 0.0
	distance_travelled = 0.0
	escapes = 0
	discoveries.clear()
	cause_of_death = ""
	threat = Threat.CALM
	plants_found = 0
	spotted.clear()
	level_done = false
	if mode == Mode.ENDLESS:
		abilities = {}


func notify(title: String, body: String = "") -> void:
	notification_posted.emit(title, body)


func discover(id: String) -> bool:
	if discoveries.has(id):
		return false
	discoveries[id] = true
	discovery_made.emit(id, discoveries.size(), total_discoveries)
	return true


func set_threat(level: int) -> void:
	if level != threat:
		if threat == Threat.HUNTED and level < Threat.HUNTED and in_game:
			escapes += 1
		threat = level
		threat_changed.emit(level)


func finish_run(cause: String) -> void:
	cause_of_death = cause
	in_game = false
	if time_survived > best_time:
		best_time = time_survived
	save_progress()


static func format_time(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d" % [s / 60, s % 60]
