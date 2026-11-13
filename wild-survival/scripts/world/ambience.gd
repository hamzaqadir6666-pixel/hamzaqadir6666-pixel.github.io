class_name Ambience
extends Node
## Layered environmental audio: day jungle bed, night crickets, wind, positional water, dawn chorus,
## random 3D one-shots (bird calls, owls, rustling leaves, gusts) and adaptive music.

var world: WorldData
var day_night: DayNight
var listener_target: Node3D

var _day_a: AudioStreamPlayer
var _day_b: AudioStreamPlayer
var _night: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _dawn: AudioStreamPlayer
var _water: AudioStreamPlayer3D
var _lake: AudioStreamPlayer3D
var _oneshot_timer := 4.0
var _water_timer := 0.0
var _music_timer := 0.0
var _chase_hold := 0.0
var _rng := RandomNumberGenerator.new()


func setup(p_world: WorldData, p_day_night: DayNight) -> void:
	world = p_world
	day_night = p_day_night
	_rng.randomize()
	_day_a = _loop("res://audio/ambience/jungle_day_a.ogg")
	_day_b = _loop("res://audio/ambience/jungle_day_b.ogg")
	_night = _loop("res://audio/ambience/night_crickets.ogg")
	_wind = _loop("res://audio/ambience/wind_loop.ogg")
	_dawn = _loop("res://audio/ambience/birds_morning.ogg")
	_water = _loop3d("res://audio/ambience/river.ogg", 9.0, 70.0)
	_lake = _loop3d("res://audio/ambience/lake_shore.ogg", 10.0, 80.0)


func _loop(path: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = AudioManager.looped(path)
	p.bus = "Ambience"
	p.volume_db = -60.0
	add_child(p)
	p.play()
	return p


func _loop3d(path: String, unit: float, max_dist: float) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = AudioManager.looped(path)
	p.bus = "Ambience"
	p.unit_size = unit
	p.max_distance = max_dist
	p.attenuation_filter_cutoff_hz = 8000.0
	add_child(p)
	p.play()
	return p


static func _vol(linear: float) -> float:
	return linear_to_db(clampf(linear, 0.0001, 1.0))


func _process(delta: float) -> void:
	if day_night == null:
		return
	var d := day_night.day_factor
	var n := day_night.night_factor
	var k := minf(delta * 1.5, 1.0)
	_day_a.volume_db = lerpf(_day_a.volume_db, _vol(d * 0.55), k)
	_day_b.volume_db = lerpf(_day_b.volume_db, _vol(d * 0.35), k)
	_night.volume_db = lerpf(_night.volume_db, _vol(n * 0.6), k)
	var gust := 0.22 + 0.12 * sin(Time.get_ticks_msec() * 0.00021) + 0.08 * sin(Time.get_ticks_msec() * 0.00057)
	_wind.volume_db = lerpf(_wind.volume_db, _vol(gust), k)
	var dawn := 1.0 - smoothstep(0.0, 1.6, absf(day_night.time_of_day - 6.3))
	_dawn.volume_db = lerpf(_dawn.volume_db, _vol(dawn * 0.6), k)

	if listener_target == null:
		return
	_water_timer -= delta
	if _water_timer <= 0.0:
		_water_timer = 0.3
		_update_water_emitters()
	_oneshot_timer -= delta
	if _oneshot_timer <= 0.0:
		_oneshot_timer = _rng.randf_range(3.5, 9.0)
		_play_oneshot()
	_update_music(delta)


func _update_water_emitters() -> void:
	var p := listener_target.global_position
	# nearest point on the river polyline
	var best := Vector2.ZERO
	var best_d := INF
	var p2 := Vector2(p.x, p.z)
	for i in world.river_points.size() - 1:
		var q := Geometry2D.get_closest_point_to_segment(p2, world.river_points[i], world.river_points[i + 1])
		var dd := q.distance_squared_to(p2)
		if dd < best_d:
			best_d = dd
			best = q
	_water.global_position = Vector3(best.x, 0.3, best.y)
	var lake_best := INF
	for lake in world.lakes:
		var c: Vector2 = lake["center"]
		var r: Vector2 = lake["radii"]
		var dir := (p2 - c)
		var edge := c + dir.normalized() * minf(dir.length(), minf(r.x, r.y))
		var dd := edge.distance_squared_to(p2)
		if dd < lake_best:
			lake_best = dd
			_lake.global_position = Vector3(edge.x, 0.3, edge.y)


func _play_oneshot() -> void:
	var p := listener_target.global_position
	var ang := _rng.randf() * TAU
	var dist := _rng.randf_range(14.0, 45.0)
	var pos := p + Vector3(cos(ang) * dist, _rng.randf_range(4.0, 14.0), sin(ang) * dist)
	var path := ""
	var vol := -4.0
	var roll := _rng.randf()
	if day_night.night_factor > 0.6:
		if roll < 0.4:
			path = "res://audio/ambience/owl_hoot.ogg"
		elif roll < 0.7:
			path = "res://audio/ambience/leaves_rustle_%s.ogg" % ["a", "b"][_rng.randi() % 2]
			vol = -9.0
		elif roll < 0.85:
			path = "res://audio/ambience/wind_gust.ogg"
			vol = -8.0
	else:
		if roll < 0.3:
			path = "res://audio/ambience/bird_call_peacock.ogg"
			vol = -7.0
		elif roll < 0.55:
			path = "res://audio/ambience/bird_call_wader.ogg"
			vol = -6.0
		elif roll < 0.8:
			path = "res://audio/ambience/leaves_rustle_%s.ogg" % ["a", "b"][_rng.randi() % 2]
			vol = -9.0
		elif roll < 0.92:
			path = "res://audio/ambience/wind_gust.ogg"
			vol = -8.0
	if path != "":
		AudioManager.play_at(path, pos, vol, _rng.randf_range(0.92, 1.08), 14.0, 120.0, "Ambience")


## Music follows the situation: chase drums when hunted, otherwise calm day / night themes.
func _update_music(delta: float) -> void:
	if not GameState.in_game:
		return
	_music_timer -= delta
	if GameState.threat == GameState.Threat.HUNTED:
		_chase_hold = 6.0
	else:
		_chase_hold = maxf(_chase_hold - delta, 0.0)
	if _music_timer > 0.0:
		return
	_music_timer = 0.5
	if _chase_hold > 0.0:
		AudioManager.play_music("chase", 1.2, -9.0)
	elif day_night.night_factor > 0.5:
		AudioManager.play_music("night", 4.0, -13.0)
	else:
		AudioManager.play_music("day", 4.0, -15.0)
