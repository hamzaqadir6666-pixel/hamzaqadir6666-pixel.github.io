class_name Lion
extends Predator
## Lion: territorial. Walks a fixed patrol circuit around its pride ground, dozes through the heat of
## the day, announces a hunt with a roar, then commits to a powerful but short sprint. Tires quickly
## and will not follow far beyond its territory.

var _circuit: Array[Vector3] = []
var _circuit_index := 0
var _windup := 0.0


func _configure() -> void:
	species = "lion"
	display_name = "Lion"
	model_path = "res://models/animals/lion.glb"
	model_scale = 1.0
	walk_speed = 1.7
	trot_speed = 4.2
	run_speed = 11.7
	acceleration = 8.0
	turn_rate = 4.0
	turn_speed_penalty = 0.07
	vision_range = 48.0
	vision_fov_cos = 0.25
	hearing = 1.0
	night_vision = 1.0
	night_activity = 1.35
	attack_range = 2.3
	attack_damage = 34.0
	attack_cooldown = 1.7
	attack_anim_time = 0.8
	chase_stamina = 8.5
	stamina_recover = 0.35
	tired_speed_factor = 0.55
	lose_sight_time = 3.0
	search_time = 12.0
	territory_radius = 60.0
	leash_radius = 135.0
	walk_anim_rate = 3.0
	run_anim_rate = 2.7
	body_radius = 0.5
	eye_height = 1.1
	sounds = {
		"roar": ["res://audio/animals/lion_roar1.ogg", "res://audio/animals/lion_roar2.ogg"],
		"growl": ["res://audio/animals/lion_growl.ogg"],
		"attack": ["res://audio/animals/lion_attack1.ogg", "res://audio/animals/lion_attack2.ogg", "res://audio/animals/lion_attack3.ogg"],
		"call": ["res://audio/animals/lion_roar1.ogg", "res://audio/animals/lion_growl.ogg"],
	}


func _on_spawned() -> void:
	# a patrol circuit of landmarks around the territory
	var count := 5
	var start := rng.randf() * TAU
	for i in count:
		var ang := start + TAU * i / count
		var c := home + Vector2(cos(ang), sin(ang)) * territory_radius * rng.randf_range(0.55, 0.9)
		_circuit.append(random_point_near(c, 8.0))


func _next_patrol_point() -> Vector3:
	_circuit_index = (_circuit_index + 1) % _circuit.size()
	return _circuit[_circuit_index]


func _think_patrol(dt: float) -> void:
	if _react_to_awareness():
		return
	if at_target():
		# lions sleep most of the day, patrol most of the night
		var rest_chance := lerpf(0.75, 0.15, night())
		if has_target and rng.randf() < rest_chance:
			set_state(State.REST)
			return
		go_to(_next_patrol_point(), walk_speed)


func _think_rest(dt: float) -> void:
	stop_moving()
	if _react_to_awareness():
		return
	if _wait <= 0.0:
		_wait = rng.randf_range(14.0, 30.0) * lerpf(1.0, 0.35, night())
	if state_time > _wait:
		set_state(State.PATROL)


func _on_detected() -> void:
	# roar first: an honest warning before the charge
	_windup = 0.9
	vocalize("roar", 4.0, true)
	set_state(State.CHASE)
	if manager != null:
		manager.alert_allies(self, last_known, 0.7, 45.0)


func _think_chase(dt: float) -> void:
	if _windup > 0.0:
		_windup -= dt
		stop_moving()
		_face_point(player.global_position)
		return
	super._think_chase(dt)


func _should_give_up() -> bool:
	if pos2().distance_to(home) > leash_radius:
		return true
	# a spent lion gives up as soon as the prey has any real lead
	if tired and (player_distance > 11.0 or state_time > 14.0):
		return true
	return false
