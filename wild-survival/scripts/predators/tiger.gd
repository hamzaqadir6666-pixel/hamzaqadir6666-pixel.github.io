class_name Tiger
extends Predator
## Tiger: solitary ambush hunter. Lies up in dense cover beside trails and water, creeps toward prey
## while it is not looking, freezes when watched and finishes with an explosive pounce. If the pounce
## fails it breaks off quickly and relocates to a new ambush site. Swims.

enum Tactic { AMBUSH, RELOCATE }

const POUNCE_RANGE := 11.5

var _tactic: int = Tactic.RELOCATE
var _ambush_spot := Vector3.ZERO
var _pouncing := 0.0
var _pounce_bonus := false
var _frozen := false


func _configure() -> void:
	species = "tiger"
	display_name = "Tiger"
	model_path = "res://models/animals/tiger.glb"
	model_scale = 1.0
	walk_speed = 1.6
	trot_speed = 3.6
	run_speed = 10.8
	acceleration = 12.0
	turn_rate = 5.0
	turn_speed_penalty = 0.05
	vision_range = 42.0
	vision_fov_cos = 0.0
	hearing = 1.25
	night_vision = 1.15
	night_activity = 1.3
	attack_range = 2.3
	attack_damage = 36.0
	attack_cooldown = 1.9
	attack_anim_time = 0.85
	chase_stamina = 5.0
	stamina_recover = 0.4
	tired_speed_factor = 0.5
	lose_sight_time = 2.5
	search_time = 10.0
	territory_radius = 75.0
	leash_radius = 140.0
	can_swim = true
	awareness_gain = 1.8
	walk_anim_rate = 1.6
	run_anim_rate = 3.6
	body_radius = 0.48
	eye_height = 0.95
	sounds = {
		"roar": ["res://audio/animals/tiger_roar1.ogg"],
		"growl": ["res://audio/animals/tiger_growl.ogg"],
		"attack": ["res://audio/animals/tiger_attack1.ogg", "res://audio/animals/tiger_attack2.ogg"],
		"call": ["res://audio/animals/tiger_growl.ogg"],
	}


func _on_spawned() -> void:
	_ambush_spot = _find_ambush_spot()


## Best-scoring hiding place: a tall bush close to a trail or the water's edge.
func _find_ambush_spot() -> Vector3:
	var best := Vector3(home.x, world.height_at(home.x, home.y), home.y)
	var best_score := -1.0
	var spots := world.cover_spots_near(home, territory_radius, 0.85)
	for i in mini(spots.size(), 60):
		var c: Vector4 = spots[rng.randi() % spots.size()]
		if not walkable(c.x, c.y) or world.in_safe_zone(Vector2(c.x, c.y), 8.0):
			continue
		var score := c.w + rng.randf() * 0.5
		# cover within pouncing distance of a path or shoreline is ideal
		for a in 6:
			var qx := c.x + cos(a * TAU / 6.0) * 7.0
			var qz := c.y + sin(a * TAU / 6.0) * 7.0
			score += world.trail_at(qx, qz) * 0.5
			if world.water_distance(qx, qz) < 3.0:
				score += 0.3
		if score > best_score:
			best_score = score
			best = Vector3(c.x, world.height_at(c.x, c.y), c.y)
	return best


func threat_level() -> int:
	if state == State.CHASE or state == State.ATTACK:
		return GameState.Threat.HUNTED
	if state == State.STALK:
		return GameState.Threat.STALKED
	return GameState.Threat.CALM


func _on_state_enter(s: int, _prev: int) -> void:
	if s != State.CHASE and s != State.ATTACK:
		_pouncing = 0.0


func _think_patrol(_dt: float) -> void:
	# PATROL for a tiger means: slip quietly to the ambush site, then lie in wait there.
	if awareness >= 0.55:
		set_state(State.STALK)
		return
	if _tactic == Tactic.RELOCATE:
		go_to(_ambush_spot, walk_speed * 1.2)
		if at_target(2.0):
			_tactic = Tactic.AMBUSH
			_wait = rng.randf_range(50.0, 110.0) / activity()
			state_time = 0.0
	else:
		stop_moving()
		# waiting motionless in cover; at night tigers move between sites much more often
		if state_time > _wait:
			_ambush_spot = _find_ambush_spot()
			_tactic = Tactic.RELOCATE


func _think_rest(dt: float) -> void:
	_think_patrol(dt)


func _think_investigate(_dt: float) -> void:
	set_state(State.STALK)


func _on_detected() -> void:
	if state != State.STALK and state != State.CHASE:
		set_state(State.STALK)


func _think_stalk(_dt: float) -> void:
	if player.is_dead() or player.in_grove:
		_break_off()
		return
	if awareness < 0.2 or time_since_contact > 9.0:
		_break_off()
		return
	var d := player_distance
	var to_me := (global_position - player.global_position)
	to_me.y = 0.0
	var watched := d < 30.0 and player.forward().dot(to_me.normalized()) > 0.55 and player.cover < 0.5
	var spooked := player.is_sprinting and d < 22.0
	if d < POUNCE_RANGE or (spooked and d < 18.0):
		_pounce()
		return
	_frozen = watched and d > POUNCE_RANGE + 2.0
	if _frozen:
		# hold perfectly still while the deer looks this way
		stop_moving()
		_face_point(player.global_position)
	else:
		# creep in from behind; faster while the deer is busy feeding or drinking
		var behind := player.global_position - player.forward() * 4.0
		var speed := walk_speed * (1.5 if player.mode != Player.Mode.NORMAL else 1.15)
		if d > 26.0:
			speed = trot_speed
		go_to(behind if sees_player or hears_player else last_known, speed)
	if state_time > 45.0:
		_break_off()


func _pounce() -> void:
	_pounce_bonus = true
	stamina = 1.0
	tired = false
	vocalize("roar", 4.0, true)
	set_state(State.CHASE)
	_pouncing = 2.4


func current_run_speed() -> float:
	if _pouncing > 0.0:
		return 15.5
	return super.current_run_speed()


func _think_chase(dt: float) -> void:
	_pouncing = maxf(_pouncing - dt, 0.0)
	super._think_chase(dt)


func _should_give_up() -> bool:
	# tigers do not run prey down: a failed rush is abandoned within seconds
	if _pouncing > 0.0:
		return false
	if state_time > 6.5 and player_distance > 6.0:
		return true
	return tired or pos2().distance_to(home) > leash_radius


func _attack_damage_now() -> float:
	if _pounce_bonus:
		_pounce_bonus = false
		return attack_damage * 1.3
	return attack_damage


func _give_up() -> void:
	_break_off()


func _break_off() -> void:
	awareness = 0.0
	_pouncing = 0.0
	_ambush_spot = _find_ambush_spot()
	_tactic = Tactic.RELOCATE
	set_state(State.PATROL)


func _begin_search() -> void:
	# a brief look around, then melt back into the jungle
	super._begin_search()
	_search_points.resize(2)


func _think_return(_dt: float) -> void:
	_break_off()


func _animate(delta: float) -> void:
	# crouch low while stalking or lying in ambush
	var crouch := 0.0
	if state == State.STALK or (state == State.PATROL and _tactic == Tactic.AMBUSH):
		crouch = -0.22
	rig.lift = lerpf(rig.lift, crouch, minf(delta * 4.0, 1.0))
	super._animate(delta)


func _ambient_voice() -> void:
	# silent while hunting
	if state == State.PATROL and _tactic == Tactic.RELOCATE and night() > 0.5 and rng.randf() < 0.3:
		vocalize("call", -8.0)
