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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var cfg := ConfigFile.new()
	if cfg.load("user://records.cfg") == OK:
		best_time = float(cfg.get_value("records", "best_time", 0.0))


func reset_run() -> void:
	days_survived = 0
	time_survived = 0.0
	distance_travelled = 0.0
	escapes = 0
	discoveries.clear()
	cause_of_death = ""
	threat = Threat.CALM


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
		var cfg := ConfigFile.new()
		cfg.set_value("records", "best_time", best_time)
		cfg.save("user://records.cfg")


static func format_time(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d" % [s / 60, s % 60]
