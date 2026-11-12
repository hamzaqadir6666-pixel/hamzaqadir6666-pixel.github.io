class_name Predator
extends CharacterBody3D
## Shared predator brain: perception (sight cone + line of sight + hearing + cover), an awareness meter,
## a finite state machine (rest / patrol / investigate / chase / attack / search / return), steering with
## terrain and obstacle avoidance, animation and vocalisation. Species scripts override the hooks.

signal state_changed(predator: Predator, state: int)

enum State { REST, PATROL, INVESTIGATE, STALK, CHASE, ATTACK, SEARCH, RETURN, SPECIAL }
const STATE_NAMES := ["REST", "PATROL", "INVESTIGATE", "STALK", "CHASE", "ATTACK", "SEARCH", "RETURN", "SPECIAL"]

# ---- species configuration (set in _configure)
var species := "predator"
var display_name := "Predator"
var model_path := ""
var model_scale := 1.0
var clip_aliases: Dictionary = {}
var walk_speed := 1.8
var trot_speed := 4.0
var run_speed := 10.0
var acceleration := 9.0
var turn_rate := 4.5              ## rad/s at low speed
var turn_speed_penalty := 0.05    ## how much speed reduces agility
var vision_range := 45.0
var vision_fov_cos := 0.2         ## cos(half angle)
var hearing := 1.0
var night_vision := 0.9           ## multiplier on vision range at night
var night_activity := 1.2         ## >1: more active/dangerous at night
var attack_range := 2.1
var attack_damage := 25.0
var attack_cooldown := 1.5
var attack_anim_time := 0.8
var chase_stamina := 9.0          ## seconds of full sprint
var stamina_recover := 0.45       ## per second while not sprinting (fraction of drain)
var tired_speed_factor := 0.6
var lose_sight_time := 3.5
var search_time := 14.0
var territory_radius := 70.0
var leash_radius := 150.0
var can_swim := false
var awareness_gain := 1.5
var walk_anim_rate := 1.0         ## playback rate at walk_speed
var run_anim_rate := 2.4          ## playback rate at run_speed
var body_radius := 0.45
var body_length := 1.5
var eye_height := 0.9
var sounds: Dictionary = {}       ## growl / roar / attack : Array[String]
var voice_pitch := 1.0

# ---- runtime
var world: WorldData
var player: Player
var day_night: DayNight
var manager: Node
var rig: AnimalRig
var home := Vector2.ZERO
var state: int = State.PATROL
var state_time := 0.0
var awareness := 0.0
var sees_player := false
var hears_player := false
var last_known := Vector3.ZERO
var last_known_dir := Vector3.ZERO
var time_since_contact := 99.0
var stamina := 1.0                ## 0..1
var tired := false
var move_target := Vector3.ZERO
var move_speed := 0.0
var has_target := false
var player_distance := 999.0
var rng := RandomNumberGenerator.new()
var dormant := false

var _heading := 0.0
var _speed := 0.0
var _think_timer := 0.0
var _think_interval := 0.15
var _attack_cd := 0.0
var _attack_hit_done := false
var _avoid_bias := 0.0
var _avoid_time := 0.0
var _stuck_timer := 0.0
var _stuck_ref := Vector3.ZERO
var _voice_cd := 0.0
var _idle_clip := "Idle"
var _idle_switch := 0.0
var _search_points: Array[Vector3] = []
var _wait := 0.0
var _dormant_tick := 0
var _voice: AudioStreamPlayer3D
var _step_accum := 0.0


func _ready() -> void:
	add_to_group("predators")
	rng.randomize()
	_configure()
	collision_layer = 8
	collision_mask = 7
	floor_max_angle = deg_to_rad(55.0)
	floor_snap_length = 0.6
	var shape := CapsuleShape3D.new()
	shape.radius = body_radius
	shape.height = maxf(body_radius * 2.0 + 0.3, 1.1)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = shape.height * 0.5
	add_child(cs)
	rig = AnimalRig.new()
	rig.name = "Rig"
	add_child(rig)
	rig.setup(model_path, model_scale, clip_aliases)
	rig.play("Idle")
	_voice = AudioStreamPlayer3D.new()
	_voice.bus = "SFX"
	_voice.unit_size = 14.0
	_voice.max_distance = 160.0
	_voice.position.y = eye_height
	_voice.attenuation_filter_cutoff_hz = 7000.0
	add_child(_voice)
	_think_timer = rng.randf() * 0.3
	_heading = rng.randf() * TAU
	_voice_cd = rng.randf_range(10.0, 40.0)
	home = Vector2(global_position.x, global_position.z)
	_on_spawned()
	set_state(State.PATROL)


## Override: set species parameters.
func _configure() -> void:
	pass


## Override: called once after the node is placed in the world.
func _on_spawned() -> void:
	pass


# ------------------------------------------------------------------ helpers

func pos2() -> Vector2:
	return Vector2(global_position.x, global_position.z)


func forward() -> Vector3:
	return Vector3(-sin(_heading), 0.0, -cos(_heading))


func night() -> float:
	return day_night.night_factor if day_night != null else 0.0


func activity() -> float:
	return lerpf(1.0, night_activity, night())


func state_name() -> String:
	return STATE_NAMES[state]


func set_state(s: int) -> void:
	var prev := state
	state = s
	state_time = 0.0
	_wait = 0.0
	_on_state_enter(s, prev)
	state_changed.emit(self, s)


func threat_level() -> int:
	match state:
		State.CHASE, State.ATTACK:
			return GameState.Threat.HUNTED
		State.STALK:
			return GameState.Threat.STALKED
		State.INVESTIGATE, State.SEARCH:
			return GameState.Threat.WATCHED
	return GameState.Threat.WATCHED if awareness > 0.45 else GameState.Threat.CALM


func go_to(target: Vector3, speed: float) -> void:
	move_target = target
	move_speed = speed
	has_target = true


func stop_moving() -> void:
	has_target = false
	move_speed = 0.0


func at_target(tolerance := 1.6) -> bool:
	return not has_target or pos2().distance_to(Vector2(move_target.x, move_target.z)) < tolerance


func walkable(x: float, z: float) -> bool:
	if not world.is_walkable(x, z, can_swim):
		return false
	return not world.in_safe_zone(Vector2(x, z), 1.2)


func random_point_near(center: Vector2, radius: float, min_radius := 0.0) -> Vector3:
	for attempt in 20:
		var ang := rng.randf() * TAU
		var r := sqrt(rng.randf()) * (radius - min_radius) + min_radius
		var p := center + Vector2(cos(ang), sin(ang)) * r
		if walkable(p.x, p.y):
			return Vector3(p.x, world.height_at(p.x, p.y), p.y)
	return Vector3(center.x, world.height_at(center.x, center.y), center.y)


func vocalize(kind: String, volume_db := 0.0, force := false) -> void:
	if not sounds.has(kind) or (_voice.playing and not force):
		return
	var list: Array = sounds[kind]
	if list.is_empty():
		return
	_voice.stream = AudioManager.stream(list[rng.randi() % list.size()])
	_voice.volume_db = volume_db
	_voice.pitch_scale = voice_pitch * rng.randf_range(0.94, 1.06)
	_voice.play()


# ------------------------------------------------------------------ perception

## Returns the strength (0..1) with which the predator currently perceives the player.
func sense() -> float:
	sees_player = false
	hears_player = false
	if player == null or player.is_dead():
		return 0.0
	var to := player.global_position - global_position
	player_distance = to.length()
	var d := player_distance
	if player.in_grove:
		return 0.0
	var engaged := state == State.CHASE or state == State.ATTACK
	var vis := player.visibility
	if engaged:
		# already locked on: cover only helps once the deer has opened a gap
		vis = maxf(vis, 0.4 if d < 14.0 else 0.12)
	var vrange := vision_range * lerpf(1.0, night_vision, night())
	if state == State.REST:
		vrange *= 0.55
	var eff := vrange * clampf(vis, 0.0, 1.0)
	var flat := Vector3(to.x, 0.0, to.z).normalized()
	var facing := forward().dot(flat)
	if facing < vision_fov_cos and not engaged:
		eff *= 0.22   # peripheral / behind
	var sight := 0.0
	if d < eff and _line_of_sight():
		sight = clampf(1.15 - d / eff, 0.15, 1.0)
		sees_player = true
	var hr := player.noise_radius * hearing * lerpf(1.0, 1.2, night())
	if state == State.REST:
		hr *= 0.7
	var heard := 0.0
	if d < hr:
		heard = clampf(1.0 - d / hr, 0.1, 1.0) * 0.85
		hears_player = true
	if d < 2.6 and vis > 0.03:
		sight = 1.0
		sees_player = true
	return maxf(sight, heard)


func _line_of_sight() -> bool:
	var space := get_world_3d().direct_space_state
	if space == null:
		return true
	var from := global_position + Vector3(0.0, eye_height, 0.0)
	var to := player.global_position + Vector3(0.0, 0.9, 0.0)
	var q := PhysicsRayQueryParameters3D.create(from, to, 3)
	return space.intersect_ray(q).is_empty()


func _update_awareness(dt: float) -> void:
	var s := sense()
	if s > 0.0:
		awareness = minf(awareness + s * awareness_gain * activity() * dt, 1.0)
		last_known = player.global_position
		var pv := player.velocity
		pv.y = 0.0
		last_known_dir = pv.normalized() if pv.length() > 0.5 else Vector3.ZERO
		time_since_contact = 0.0
	else:
		time_since_contact += dt
		var decay := 0.07 if state == State.SEARCH or state == State.INVESTIGATE else 0.16
		awareness = maxf(awareness - decay * dt, 0.0)


## Called by pack mates / the manager to share a sighting.
func alert(pos: Vector3, level := 1.0) -> void:
	if state == State.CHASE or state == State.ATTACK:
		return
	awareness = maxf(awareness, level)
	last_known = pos
	time_since_contact = 0.0
	if level >= 1.0:
		_on_detected()
	elif state == State.REST or state == State.PATROL or state == State.RETURN:
		set_state(State.INVESTIGATE)


# ------------------------------------------------------------------ main loop

func _physics_process(delta: float) -> void:
	if world == null or player == null:
		return
	state_time += delta
	_attack_cd = maxf(_attack_cd - delta, 0.0)
	_voice_cd -= delta
	player_distance = global_position.distance_to(player.global_position)

	# far away and not hunting: cheap simulation (no physics body movement, slow thinking)
	var engaged := state == State.CHASE or state == State.ATTACK or state == State.STALK
	dormant = player_distance > 170.0 and not engaged
	if dormant:
		_dormant_tick += 1
		if _dormant_tick % 6 == 0:
			var dt := delta * 6.0
			_think(dt)
			_dormant_move(dt)
		rig.set_paused(true)
		return
	rig.set_paused(false)

	_think_timer -= delta
	if _think_timer <= 0.0:
		var interval := _think_interval if player_distance < 90.0 else _think_interval * 2.5
		_think_timer = interval
		_update_awareness(interval)
		_think(interval)
	_update_stamina(delta)
	if state == State.ATTACK:
		_attack_update(delta)
	_steer(delta)
	_animate(delta)
	_footsteps(delta)
	if _voice_cd <= 0.0:
		_voice_cd = rng.randf_range(25.0, 70.0) / activity()
		_ambient_voice()


func _update_stamina(delta: float) -> void:
	var sprinting := _speed > trot_speed * 1.25
	if sprinting:
		stamina -= delta / chase_stamina
	else:
		stamina += delta / chase_stamina * stamina_recover
	stamina = clampf(stamina, 0.0, 1.0)
	if stamina <= 0.0:
		tired = true
	elif tired and stamina > 0.45:
		tired = false


func current_run_speed() -> float:
	var s := run_speed * lerpf(1.0, 1.05, night() * (night_activity - 1.0) * 2.0)
	if tired:
		s *= tired_speed_factor
	return s


# ------------------------------------------------------------------ state machine

func _think(dt: float) -> void:
	match state:
		State.REST:
			_think_rest(dt)
		State.PATROL:
			_think_patrol(dt)
		State.INVESTIGATE:
			_think_investigate(dt)
		State.STALK:
			_think_stalk(dt)
		State.CHASE:
			_think_chase(dt)
		State.ATTACK:
			pass
		State.SEARCH:
			_think_search(dt)
		State.RETURN:
			_think_return(dt)
		State.SPECIAL:
			_think_special(dt)


func _on_state_enter(_s: int, _prev: int) -> void:
	pass


## Shared reaction to rising awareness in calm states. Returns true if the state changed.
func _react_to_awareness() -> bool:
	if awareness >= 1.0:
		_on_detected()
		return true
	if awareness > 0.4 and state != State.INVESTIGATE:
		set_state(State.INVESTIGATE)
		return true
	return false


## Override for species-specific reactions (tiger stalks, hyena picks a tactic, ...).
func _on_detected() -> void:
	vocalize("roar", 2.0, true)
	set_state(State.CHASE)


func _think_rest(_dt: float) -> void:
	stop_moving()
	if _react_to_awareness():
		return
	if _wait <= 0.0:
		_wait = rng.randf_range(8.0, 20.0) / activity()
	if state_time > _wait:
		set_state(State.PATROL)


func _think_patrol(_dt: float) -> void:
	if _react_to_awareness():
		return
	if at_target():
		if has_target and rng.randf() < 0.35 / activity():
			set_state(State.REST)
			return
		go_to(_next_patrol_point(), walk_speed)


## Override: where to wander next.
func _next_patrol_point() -> Vector3:
	return random_point_near(home, territory_radius, 8.0)


func _think_investigate(_dt: float) -> void:
	if awareness >= 1.0:
		_on_detected()
		return
	go_to(last_known, walk_speed * 1.35)
	if state_time < 1.2:
		# first stop and stare
		move_speed = 0.0
		_face_point(last_known)
	if awareness < 0.12 or (at_target(3.0) and state_time > 6.0):
		set_state(State.RETURN)


func _think_stalk(_dt: float) -> void:
	set_state(State.CHASE)


func _think_chase(_dt: float) -> void:
	if player.is_dead():
		set_state(State.RETURN)
		return
	var tracking := sees_player or hears_player
	if tracking:
		var lead := player.velocity * clampf(player_distance / maxf(current_run_speed(), 1.0), 0.0, 0.8)
		lead.y = 0.0
		go_to(player.global_position + lead, current_run_speed())
		if player_distance < attack_range + 0.5 and _attack_cd <= 0.0 and not player.in_grove:
			_begin_attack()
			return
	else:
		go_to(last_known + last_known_dir * 6.0, current_run_speed() * 0.85)
		if time_since_contact > lose_sight_time:
			_begin_search()
			return
	if _should_give_up():
		_give_up()


## Override: species specific reasons to abandon a chase.
func _should_give_up() -> bool:
	if pos2().distance_to(home) > leash_radius:
		return true
	return tired and player_distance > 16.0


func _give_up() -> void:
	vocalize("growl", -3.0)
	_begin_search()


func _begin_search() -> void:
	_search_points.clear()
	var base := last_known + last_known_dir * 9.0
	_search_points.append(base)
	for i in 3:
		_search_points.append(random_point_near(Vector2(base.x, base.z), 16.0, 5.0))
	awareness = minf(awareness, 0.6)
	set_state(State.SEARCH)


func _think_search(_dt: float) -> void:
	if awareness >= 1.0 or (sees_player and player_distance < vision_range * 0.5):
		_on_detected()
		return
	if state_time > search_time / maxf(activity() * 0.9, 0.8) + 0.0 or _search_points.is_empty():
		set_state(State.RETURN)
		return
	if _wait > 0.0:
		# sniffing / looking around
		_wait -= _think_interval
		stop_moving()
		_heading += sin(state_time * 2.0) * 0.12
		return
	go_to(_search_points[0], trot_speed)
	if at_target(2.5):
		_search_points.pop_front()
		_wait = rng.randf_range(1.0, 2.4)


func _think_return(_dt: float) -> void:
	if _react_to_awareness():
		return
	var h := Vector3(home.x, world.height_at(home.x, home.y), home.y)
	go_to(h, walk_speed * 1.3)
	if at_target(territory_radius * 0.5) or state_time > 40.0:
		set_state(State.PATROL)


func _think_special(_dt: float) -> void:
	set_state(State.PATROL)


# ------------------------------------------------------------------ attack

func _begin_attack() -> void:
	_attack_hit_done = false
	set_state(State.ATTACK)
	var clip := _attack_clip()
	rig.play(clip, rig.length(clip) / attack_anim_time, 0.1, true)
	vocalize("attack", 3.0, true)


func _attack_clip() -> String:
	return "Attack"


func _attack_damage_now() -> float:
	return attack_damage


func _attack_update(_delta: float) -> void:
	var t := state_time / attack_anim_time
	if t < 0.5:
		# lunge
		var lead := player.global_position
		go_to(lead, run_speed * 0.75)
	else:
		stop_moving()
	if not _attack_hit_done and t >= 0.42:
		_attack_hit_done = true
		var to := player.global_position - global_position
		var flat := Vector3(to.x, 0.0, to.z)
		var reach := attack_range + 0.75
		if flat.length() < reach and absf(to.y) < 2.0 and forward().dot(flat.normalized()) > 0.1 and not player.in_grove:
			if player.take_damage(_attack_damage_now(), display_name, global_position):
				_on_attack_landed()
	if t >= 1.0:
		_attack_cd = attack_cooldown
		_after_attack()


func _on_attack_landed() -> void:
	pass


func _after_attack() -> void:
	if player.is_dead():
		vocalize("roar", 0.0, true)
		set_state(State.REST)
	else:
		set_state(State.CHASE)
		# brief recovery so the deer can break away
		_speed *= 0.3


# ------------------------------------------------------------------ movement

func _face_point(p: Vector3) -> void:
	var d := p - global_position
	if Vector2(d.x, d.z).length() > 0.2:
		_heading = rotate_toward(_heading, atan2(-d.x, -d.z), 0.25)


func _speed_limit() -> float:
	return 99.0


func _steer(delta: float) -> void:
	var target_speed := 0.0
	var desired_heading := _heading
	if has_target:
		var to := move_target - global_position
		to.y = 0.0
		var dist := to.length()
		if dist > 0.4:
			target_speed = minf(move_speed, _speed_limit())
			var dir := to / dist
			dir = _avoid(dir, delta)
			desired_heading = atan2(-dir.x, -dir.z)
			if dist < 2.5 and state != State.CHASE and state != State.ATTACK:
				target_speed = minf(target_speed, maxf(dist * 1.5, 0.6))
	var agility := turn_rate / (1.0 + _speed * turn_speed_penalty)
	var diff := absf(angle_difference(_heading, desired_heading))
	_heading = rotate_toward(_heading, desired_heading, agility * delta)
	if diff > 1.0:
		target_speed *= 0.55
	# water slows anything wading
	var depth := world.water_depth(global_position.x, global_position.z)
	if depth > 0.25:
		target_speed *= lerpf(0.8, 0.45, clampf(depth, 0.0, 1.0))
	var rate := acceleration if target_speed > _speed else acceleration * 1.6
	_speed = move_toward(_speed, target_speed, rate * delta)
	rotation.y = _heading
	var fwd := forward()
	velocity.x = fwd.x * _speed
	velocity.z = fwd.z * _speed
	# separation from other predators
	if manager != null:
		for other: Predator in manager.predators:
			if other == self or other.dormant:
				continue
			var off := global_position - other.global_position
			off.y = 0.0
			var l := off.length()
			if l < 1.8 and l > 0.01:
				velocity += off / l * (1.8 - l) * 2.5
	var ground := world.height_at(global_position.x, global_position.z)
	if can_swim and ground < WorldData.WATER_LEVEL - 0.9:
		velocity.y = (WorldData.WATER_LEVEL - 0.8 - global_position.y) * 5.0
	elif is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= 21.0 * delta
	move_and_slide()
	if global_position.y < ground - 2.0:
		global_position.y = ground + 0.3
		velocity.y = 0.0
	# stuck detection -> pick a side and go around
	_stuck_timer += delta
	if _stuck_timer > 0.5:
		var moved := global_position.distance_to(_stuck_ref)
		if target_speed > 1.0 and moved < target_speed * 0.5 * 0.3:
			_avoid_bias = (1.0 if rng.randf() < 0.5 else -1.0) * 1.4
			_avoid_time = 0.9
		_stuck_ref = global_position
		_stuck_timer = 0.0


## Terrain-aware steering: probe ahead and swing around water, cliffs and safe thickets.
func _avoid(dir: Vector3, delta: float) -> Vector3:
	if _avoid_time > 0.0:
		_avoid_time -= delta
		dir = dir.rotated(Vector3.UP, _avoid_bias)
	var look := clampf(_speed * 0.55, 2.5, 7.0)
	var p := global_position
	if walkable(p.x + dir.x * look, p.z + dir.z * look):
		return dir
	for a: float in [0.6, -0.6, 1.2, -1.2, 1.9, -1.9, 2.6, -2.6]:
		var d2 := dir.rotated(Vector3.UP, a)
		if walkable(p.x + d2.x * look, p.z + d2.z * look):
			_avoid_bias = a
			_avoid_time = 0.5
			return d2
	return dir


func _dormant_move(dt: float) -> void:
	if not has_target:
		return
	var to := move_target - global_position
	to.y = 0.0
	var dist := to.length()
	if dist < 0.5:
		return
	var dir := to / dist
	var stepv := dir * minf(move_speed * dt, dist)
	var nx := global_position.x + stepv.x
	var nz := global_position.z + stepv.z
	if walkable(nx, nz):
		global_position = Vector3(nx, world.height_at(nx, nz), nz)
		_heading = atan2(-dir.x, -dir.z)
		rotation.y = _heading
		reset_physics_interpolation()
	else:
		has_target = false
	_speed = 0.0
	velocity = Vector3.ZERO


# ------------------------------------------------------------------ presentation

func _animate(delta: float) -> void:
	if state == State.ATTACK:
		return
	if _speed > (walk_speed + trot_speed) * 0.55:
		rig.play("Run", run_anim_rate * clampf(_speed / run_speed, 0.45, 1.25), 0.2)
	elif _speed > 0.2:
		rig.play("Walk", walk_anim_rate * clampf(_speed / walk_speed, 0.6, 2.2), 0.3)
	else:
		_idle_switch -= delta
		if _idle_switch <= 0.0 or not rig.current.begins_with("Idle"):
			_idle_switch = rng.randf_range(5.0, 9.0)
			_idle_clip = _pick_idle()
		rig.play(_idle_clip, 1.0, 0.4)
	rig.align_to_ground(world.normal_at(global_position.x, global_position.z), forward(), delta)


func _pick_idle() -> String:
	var options := ["Idle"]
	for c in ["Idle2", "Idle3"]:
		if rig.has(c):
			options.append(c)
	return options[rng.randi() % options.size()]


func _footsteps(delta: float) -> void:
	if _speed < 3.0 or player_distance > 40.0:
		return
	_step_accum += _speed * delta
	if _step_accum > 2.4:
		_step_accum = 0.0
		var surf := world.surface_at(global_position.x, global_position.z)
		var path := "res://audio/deer/step_grass%d.ogg" % (1 + rng.randi() % 8)
		if surf == &"water":
			path = "res://audio/deer/splash.ogg"
		elif surf == &"dirt" or surf == &"mud":
			path = "res://audio/deer/step_dirt%d.ogg" % (1 + rng.randi() % 4)
		AudioManager.play_at(path, global_position, -10.0, rng.randf_range(0.75, 0.9), 5.0, 45.0)


## Occasional territorial calls; louder and more frequent at night.
func _ambient_voice() -> void:
	if state == State.REST or state == State.PATROL:
		if rng.randf() < 0.5 * activity():
			vocalize("call", -4.0)
