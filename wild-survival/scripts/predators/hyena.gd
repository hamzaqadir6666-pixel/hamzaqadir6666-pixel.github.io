class_name Hyena
extends Predator
## Hyena: nomadic pack scavenger with no fixed territory. Not especially fast or strong but tireless
## and erratic - it keeps switching between shadowing, circling, feinting, harassing and backing off,
## calls its pack mates in, and grows bold when the prey is weak, alone in the open, or it is dark.

enum Tactic { SHADOW, CIRCLE, FEINT, HARASS, BACK_OFF }
const TACTIC_NAMES := ["SHADOW", "CIRCLE", "FEINT", "HARASS", "BACK_OFF"]

var tactic: int = Tactic.SHADOW
var pack_id := 0
var _tactic_time := 0.0
var _circle_dir := 1.0
var _feint_phase := 0
var _roam_target := Vector3.ZERO


func _configure() -> void:
	species = "hyena"
	display_name = "Hyena"
	model_path = "res://models/animals/hyena.glb"
	model_scale = 0.21
	clip_aliases = {"Run": "Gallop"}
	walk_speed = 1.9
	trot_speed = 4.8
	run_speed = 9.9
	acceleration = 10.0
	turn_rate = 5.5
	turn_speed_penalty = 0.04
	vision_range = 44.0
	vision_fov_cos = 0.1
	hearing = 1.35
	night_vision = 1.1
	night_activity = 1.4
	attack_range = 1.9
	attack_damage = 15.0
	attack_cooldown = 1.2
	attack_anim_time = 0.7
	chase_stamina = 30.0
	stamina_recover = 0.6
	tired_speed_factor = 0.75
	lose_sight_time = 5.0
	search_time = 20.0
	territory_radius = 140.0
	leash_radius = 9999.0
	awareness_gain = 1.5
	walk_anim_rate = 1.0
	run_anim_rate = 1.05
	body_radius = 0.38
	eye_height = 0.75
	sounds = {
		"roar": ["res://audio/animals/hyena_whoop.ogg"],
		"growl": ["res://audio/animals/hyena_growl.ogg"],
		"attack": ["res://audio/animals/hyena_attack1.ogg", "res://audio/animals/hyena_attack2.ogg"],
		"call": ["res://audio/animals/hyena_whoop.ogg", "res://audio/animals/hyena_giggle.ogg"],
		"giggle": ["res://audio/animals/hyena_giggle.ogg"],
	}


## Nomadic: roams the whole map, drifting toward water, clearings and - loosely - the deer's scent.
func _next_patrol_point() -> Vector3:
	var roll := rng.randf()
	var center := pos2()
	if roll < 0.42 and player != null:
		center = center.lerp(Vector2(player.global_position.x, player.global_position.z), 0.5)
	elif roll < 0.65:
		var cl: Dictionary = world.clearings[rng.randi() % world.clearings.size()]
		center = center.lerp(cl["center"], 0.4)
	home = center
	return random_point_near(center, 90.0, 20.0)


func _think_patrol(_dt: float) -> void:
	if _react_to_awareness():
		return
	if at_target():
		if has_target and rng.randf() < 0.2 / activity():
			set_state(State.REST)
			return
		# trots between places, sometimes ambles
		go_to(_next_patrol_point(), trot_speed if rng.randf() < 0.6 else walk_speed * 1.3)
	# stay loosely with the pack
	if manager != null and rng.randf() < 0.02:
		var mate: Predator = manager.pack_mate(self)
		if mate != null and mate.global_position.distance_to(global_position) > 35.0:
			go_to(mate.global_position + Vector3(rng.randf_range(-6, 6), 0.0, rng.randf_range(-6, 6)), trot_speed)


func _think_rest(dt: float) -> void:
	stop_moving()
	if _react_to_awareness():
		return
	if state_time > rng.randf_range(5.0, 12.0):
		set_state(State.PATROL)


func _on_detected() -> void:
	vocalize("roar", 3.0, true)
	_choose_tactic()
	set_state(State.CHASE)
	# whoop the pack in (after switching state, so the call cannot echo back and forth)
	if manager != null:
		manager.alert_allies(self, last_known, 1.0, 70.0, "hyena")


## 0..1: how willing this hyena is to commit to an attack right now.
func courage() -> float:
	var c := 0.3
	c += night() * 0.25
	if player.exhausted or player.stamina < 30.0:
		c += 0.3
	if player.health < player.max_health * 0.5:
		c += 0.25
	if manager != null:
		c += 0.2 * float(manager.allies_engaged(self, 40.0))
	if player.cover < 0.2:
		c += 0.05
	return clampf(c, 0.0, 1.0)


func _choose_tactic() -> void:
	var c := courage()
	var weights := [
		lerpf(1.3, 0.35, c),   # SHADOW
		1.0,                   # CIRCLE
		lerpf(0.6, 1.0, c),    # FEINT
		lerpf(0.35, 2.4, c),   # HARASS
		lerpf(0.8, 0.08, c),   # BACK_OFF
	]
	weights[tactic] *= 0.3     # rarely repeats itself
	var total := 0.0
	for w: float in weights:
		total += w
	var roll := rng.randf() * total
	tactic = Tactic.HARASS
	for i in weights.size():
		roll -= float(weights[i])
		if roll <= 0.0:
			tactic = i
			break
	_tactic_time = rng.randf_range(3.0, 6.5)
	_circle_dir = 1.0 if rng.randf() < 0.5 else -1.0
	_feint_phase = 0
	if tactic == Tactic.HARASS or rng.randf() < 0.25:
		vocalize("giggle", 0.0)


func _think_chase(dt: float) -> void:
	if player.is_dead():
		set_state(State.RETURN)
		return
	var tracking := sees_player or hears_player
	if not tracking:
		go_to(last_known + last_known_dir * 6.0, trot_speed * 1.4)
		if time_since_contact > lose_sight_time:
			_begin_search()
		return
	_tactic_time -= dt
	if _tactic_time <= 0.0:
		_choose_tactic()
	var pp := player.global_position
	var away := global_position - pp
	away.y = 0.0
	var d := away.length()
	var away_n := away / maxf(d, 0.01)
	match tactic:
		Tactic.SHADOW:
			# hang back out of reach and wait for the deer to tire
			var want := 17.0
			if d > want + 4.0:
				go_to(pp + away_n * want, minf(current_run_speed(), 8.0))
			elif d < want - 5.0:
				go_to(pp + away_n * (want + 3.0), trot_speed * 1.3)
			else:
				stop_moving()
				_face_point(pp)
			if courage() > 0.7:
				_tactic_time = 0.0
		Tactic.CIRCLE:
			var radius := 9.5
			var tangent := Vector3(-away_n.z, 0.0, away_n.x) * _circle_dir
			var target := pp + away_n * radius + tangent * 7.0
			go_to(target, 7.5)
			if d < 4.0 and _attack_cd <= 0.0 and rng.randf() < 0.5:
				_begin_attack()
		Tactic.FEINT:
			if _feint_phase == 0:
				go_to(pp, current_run_speed())
				if d < 4.5:
					_feint_phase = 1
					vocalize("giggle", -2.0)
					# sometimes the feint is real
					if rng.randf() < 0.3 + courage() * 0.4 and _attack_cd <= 0.0:
						tactic = Tactic.HARASS
						_tactic_time = 3.0
			else:
				go_to(pp + away_n * 14.0, current_run_speed() * 0.9)
				if d > 12.0:
					_tactic_time = 0.0
		Tactic.HARASS:
			var lead := player.velocity * clampf(d / current_run_speed(), 0.0, 0.7)
			lead.y = 0.0
			go_to(pp + lead, current_run_speed())
			if d < attack_range + 0.5 and _attack_cd <= 0.0 and not player.in_grove:
				_begin_attack()
		Tactic.BACK_OFF:
			go_to(pp + away_n * 30.0, trot_speed * 1.5)
			if d > 26.0:
				_tactic_time = 0.0
	if tired and d > 20.0:
		_give_up()


func _after_attack() -> void:
	super._after_attack()
	# bite and dance away, or press the advantage
	if rng.randf() > courage():
		tactic = Tactic.CIRCLE if rng.randf() < 0.5 else Tactic.BACK_OFF
		_tactic_time = rng.randf_range(2.0, 4.0)
	else:
		tactic = Tactic.HARASS
		_tactic_time = rng.randf_range(2.5, 5.0)


func _think_return(_dt: float) -> void:
	if _react_to_awareness():
		return
	set_state(State.PATROL)


func tactic_name() -> String:
	return TACTIC_NAMES[tactic]
