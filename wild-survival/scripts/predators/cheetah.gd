class_name Cheetah
extends Predator
## Cheetah: sight hunter of the open clearings. Slow build-up, then by far the highest top speed in
## the jungle - but it corners badly at speed, is hampered by dense forest, burns out in seconds and
## must lie panting afterwards. Mostly diurnal: sees poorly and hunts little at night.

var _exhausted_until := 0.0
var _burst := 0.0


func _configure() -> void:
	species = "cheetah"
	display_name = "Cheetah"
	model_path = "res://models/animals/cheetah.glb"
	model_scale = 1.0
	walk_speed = 1.55
	trot_speed = 4.6
	run_speed = 18.5
	acceleration = 6.5
	turn_rate = 3.6
	turn_speed_penalty = 0.2
	vision_range = 72.0
	vision_fov_cos = 0.3
	hearing = 0.8
	night_vision = 0.45
	night_activity = 0.7
	attack_range = 2.1
	attack_damage = 24.0
	attack_cooldown = 1.3
	attack_anim_time = 0.7
	chase_stamina = 6.5
	stamina_recover = 0.22
	tired_speed_factor = 0.4
	lose_sight_time = 2.5
	search_time = 9.0
	territory_radius = 55.0
	leash_radius = 170.0
	awareness_gain = 1.7
	walk_anim_rate = 3.0
	run_anim_rate = 3.5
	body_radius = 0.4
	eye_height = 0.9
	voice_pitch = 1.0
	sounds = {
		"roar": ["res://audio/animals/cheetah_growl.ogg"],
		"growl": ["res://audio/animals/cheetah_growl.ogg"],
		"attack": ["res://audio/animals/cheetah_attack1.ogg", "res://audio/animals/cheetah_attack2.ogg"],
		"call": ["res://audio/animals/cheetah_chirp.ogg"],
	}


func _next_patrol_point() -> Vector3:
	# prefers open ground where it can use its speed
	var best := random_point_near(home, territory_radius, 6.0)
	var best_open := -1.0
	for i in 5:
		var p := random_point_near(home, territory_radius, 6.0)
		var open := 1.0 - world.forest_at(p.x, p.z)
		if open > best_open:
			best_open = open
			best = p
	return best


func _think_patrol(dt: float) -> void:
	if _react_to_awareness():
		return
	if at_target():
		var rest_chance := lerpf(0.3, 0.85, night())
		if has_target and rng.randf() < rest_chance:
			set_state(State.REST)
			return
		go_to(_next_patrol_point(), walk_speed * 1.15)


func _react_to_awareness() -> bool:
	# still recovering from the last sprint: ignores prey
	if Time.get_ticks_msec() * 0.001 < _exhausted_until:
		awareness = minf(awareness, 0.3)
		return false
	return super._react_to_awareness()


func _on_detected() -> void:
	_burst = 0.0
	vocalize("growl", 2.0, true)
	set_state(State.CHASE)


## Dense jungle robs the cheetah of its top speed.
func _speed_limit() -> float:
	var f := world.forest_at(global_position.x, global_position.z)
	return lerpf(run_speed, run_speed * 0.52, smoothstep(0.25, 0.75, f))


func _think_chase(dt: float) -> void:
	_burst += dt
	super._think_chase(dt)


func _should_give_up() -> bool:
	if tired:
		return true
	return pos2().distance_to(home) > leash_radius


func _give_up() -> void:
	# spent: collapses and pants, completely harmless for a while
	_exhausted_until = Time.get_ticks_msec() * 0.001 + 14.0
	awareness = 0.0
	stamina = 0.0
	vocalize("call", -2.0, true)
	set_state(State.REST)


func _think_rest(dt: float) -> void:
	stop_moving()
	if Time.get_ticks_msec() * 0.001 < _exhausted_until:
		awareness = minf(awareness, 0.3)
		return
	super._think_rest(dt)
