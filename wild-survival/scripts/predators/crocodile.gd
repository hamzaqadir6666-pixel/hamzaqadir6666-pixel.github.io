class_name Crocodile
extends Predator
## Crocodile: lies motionless at the water's edge and in the shallows. Nearly blind to anything far
## off, but a deer that comes down to drink within its reach gets a sudden, crushing lunge.
## Slow over land and quickly out of breath - step back from the shore and it gives up.


func _configure() -> void:
	species = "crocodile"
	display_name = "Crocodile"
	model_path = "res://models/animals/crocodile.glb"
	model_scale = 0.34
	model_faces_plus_z = false
	clip_aliases = {"Run": "Walk", "Attack": "Walk"}
	walk_speed = 0.8
	trot_speed = 2.0
	run_speed = 7.6
	acceleration = 16.0
	turn_rate = 3.0
	turn_speed_penalty = 0.1
	vision_range = 21.0
	vision_fov_cos = -0.2
	hearing = 0.75
	night_vision = 1.0
	night_activity = 1.1
	attack_range = 2.9
	attack_damage = 40.0
	attack_cooldown = 2.4
	attack_anim_time = 0.6
	chase_stamina = 3.2
	stamina_recover = 0.3
	tired_speed_factor = 0.35
	lose_sight_time = 2.0
	search_time = 6.0
	territory_radius = 11.0
	leash_radius = 34.0
	can_swim = true
	awareness_gain = 2.2
	walk_anim_rate = 1.0
	run_anim_rate = 3.0
	body_radius = 0.55
	body_length = 3.4
	eye_height = 0.4
	lunge_height = 0.12
	hunts_prey = false
	voice_pitch = 0.55
	sounds = {
		"roar": ["res://audio/animals/tiger_growl.ogg"],
		"growl": ["res://audio/animals/tiger_growl.ogg"],
		"attack": ["res://audio/animals/tiger_attack1.ogg"],
	}


## Mostly lies still; now and then shifts a few metres along the bank.
func _think_patrol(_dt: float) -> void:
	if _react_to_awareness():
		return
	if at_target():
		if has_target or rng.randf() < 0.8:
			set_state(State.REST)
			return
		go_to(_next_patrol_point(), walk_speed)


func _think_rest(_dt: float) -> void:
	stop_moving()
	if _react_to_awareness():
		return
	if _wait <= 0.0:
		_wait = rng.randf_range(25.0, 60.0)
	if state_time > _wait:
		set_state(State.PATROL)


func _on_detected() -> void:
	vocalize("roar", 0.0, true)
	set_state(State.CHASE)


func _should_give_up() -> bool:
	return pos2().distance_to(home) > leash_radius or (tired and player_distance > 5.0) or state_time > 9.0


func _ambient_voice() -> void:
	pass
