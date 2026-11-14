class_name Wolf
extends Predator
## Wolf: a pack hunter built for the long chase. Not the fastest and its bite is light, but it does
## not tire, it follows far, and one wolf's howl brings the rest of the pack running.

var pack_id := 0


func _configure() -> void:
	species = "wolf"
	display_name = "Wolf"
	model_path = "res://models/animals/wolf.glb"
	model_scale = 0.37
	model_faces_plus_z = false
	clip_aliases = {"Run": "Walk", "Attack": "Walk"}
	walk_speed = 1.6
	trot_speed = 4.4
	run_speed = 10.6
	acceleration = 9.0
	turn_rate = 5.0
	turn_speed_penalty = 0.05
	vision_range = 46.0
	vision_fov_cos = 0.1
	hearing = 1.25
	night_vision = 1.0
	night_activity = 1.3
	attack_range = 1.9
	attack_damage = 15.0
	attack_cooldown = 1.1
	attack_anim_time = 0.55
	chase_stamina = 20.0
	stamina_recover = 0.6
	tired_speed_factor = 0.75
	lose_sight_time = 5.0
	search_time = 18.0
	territory_radius = 80.0
	leash_radius = 210.0
	walk_anim_rate = 1.0
	run_anim_rate = 3.0
	body_radius = 0.38
	body_length = 1.3
	eye_height = 0.75
	lunge_height = 0.3
	voice_pitch = 0.8
	sounds = {
		"roar": ["res://audio/animals/hyena_growl.ogg"],
		"growl": ["res://audio/animals/hyena_growl.ogg"],
		"attack": ["res://audio/animals/hyena_attack1.ogg", "res://audio/animals/hyena_attack2.ogg"],
		"call": ["res://audio/animals/hyena_growl.ogg"],
	}


func _on_detected() -> void:
	vocalize("roar", 2.0, true)
	set_state(State.CHASE)
	# the pack is called in only after this wolf is already committed (see alert())
	if manager != null:
		manager.alert_allies(self, last_known, 1.0, 70.0)


## Wolves keep together: patrol points are shared around the pack's home.
func _next_patrol_point() -> Vector3:
	return random_point_near(home, territory_radius * 0.6, 6.0)
