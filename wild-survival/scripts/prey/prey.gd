class_name Prey
extends CharacterBody3D
## A wild grazing animal (gazelle, boar). It lives in a small herd, grazes and wanders, bolts from
## predators and from a deer that blunders too close, and can be run down and killed by any predator.
## Prey gives the hunters something to do besides the player - and a hunt nearby is a warning.

enum State { GRAZE, WANDER, FLEE, DEAD }

const KINDS := {
	"gazelle": {
		"name": "Gazelle", "model": "res://models/animals/gazelle.glb", "scale": 0.285,
		"walk": 0.9, "run": 13.2, "accel": 11.0, "turn": 5.5, "alarm": 26.0, "stamina": 16.0,
		"radius": 0.3, "length": 1.1, "pitch": 1.25,
	},
	"boar": {
		"name": "Boar", "model": "res://models/animals/boar.glb", "scale": 0.43,
		"walk": 1.1, "run": 9.2, "accel": 8.0, "turn": 4.0, "alarm": 17.0, "stamina": 11.0,
		"radius": 0.38, "length": 1.4, "pitch": 0.8,
	},
}

var kind := "gazelle"
var display_name := "Gazelle"
var world: WorldData
var player: Player
var manager: Node
var rig: AnimalRig
var herd_id := 0
var home := Vector2.ZERO
var state: int = State.GRAZE
var state_time := 0.0
var hunter: Node3D = null        ## the predator currently chasing this animal, if any
var dormant := false

var walk_speed := 1.3
var run_speed := 13.0
var acceleration := 10.0
var turn_rate := 5.0
var alarm_radius := 24.0
var flee_stamina := 14.0
var body_length := 1.2

var _cfg: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _heading := 0.0
var _speed := 0.0
var _target := Vector3.ZERO
var _has_target := false
var _wait := 0.0
var _think := 0.0
var _threat_pos := Vector3.ZERO
var _calm := 0.0
var _tired := 0.0
var _carcass_time := 0.0
var _fall := 0.0
var _tick := 0
var _avoid_bias := 0.0
var _avoid_time := 0.0
var _bound_phase := 0.0
var _shape: CollisionShape3D


func _ready() -> void:
	add_to_group("prey")
	_rng.randomize()
	_cfg = KINDS[kind]
	display_name = _cfg["name"]
	walk_speed = _cfg["walk"]
	run_speed = _cfg["run"] * _rng.randf_range(0.94, 1.04)
	acceleration = _cfg["accel"]
	turn_rate = _cfg["turn"]
	alarm_radius = _cfg["alarm"]
	flee_stamina = _cfg["stamina"]
	body_length = _cfg["length"]
	# own layer: prey never blocks the deer or the hunters, it only collides with ground and trees
	collision_layer = 16
	collision_mask = 3
	floor_max_angle = deg_to_rad(55.0)
	floor_snap_length = 0.6
	var shape := CapsuleShape3D.new()
	shape.radius = _cfg["radius"]
	shape.height = maxf(shape.radius * 2.0 + 0.2, 0.9)
	_shape = CollisionShape3D.new()
	_shape.shape = shape
	_shape.position.y = shape.height * 0.5
	add_child(_shape)
	rig = AnimalRig.new()
	rig.name = "Rig"
	add_child(rig)
	rig.setup(_cfg["model"], float(_cfg["scale"]) * _rng.randf_range(0.93, 1.07), {}, false)
	rig.play("Idle")
	_heading = _rng.randf() * TAU
	rotation.y = _heading
	_think = _rng.randf() * 0.3
	home = Vector2(global_position.x, global_position.z)
	_enter(State.GRAZE)


func alive() -> bool:
	return state != State.DEAD


func is_fleeing() -> bool:
	return state == State.FLEE


func pos2() -> Vector2:
	return Vector2(global_position.x, global_position.z)


func forward() -> Vector3:
	return Vector3(-sin(_heading), 0.0, -cos(_heading))


func _enter(s: int) -> void:
	state = s
	state_time = 0.0
	_wait = 0.0


## Put a (possibly dead) animal back into the world at a new place.
func respawn_at(p: Vector2) -> void:
	global_position = Vector3(p.x, world.height_at(p.x, p.y) + 0.1, p.y)
	home = p
	hunter = null
	_speed = 0.0
	_fall = 0.0
	_tired = 0.0
	_has_target = false
	velocity = Vector3.ZERO
	_shape.disabled = false
	rig.rotation = Vector3.ZERO
	rig.position = Vector3.ZERO
	rig.lift = 0.0
	rig.set_paused(false)
	rig.play("Idle", 1.0, 0.0, true)
	visible = true
	_enter(State.GRAZE)
	reset_physics_interpolation()


## Killed by a predator.
func kill(by: Node3D) -> void:
	if state == State.DEAD:
		return
	_enter(State.DEAD)
	hunter = by
	_has_target = false
	_carcass_time = _rng.randf_range(40.0, 60.0)
	_shape.set_deferred("disabled", true)
	velocity = Vector3.ZERO
	_speed = 0.0
	AudioManager.play_at("res://audio/deer/hurt%d.ogg" % (1 + _rng.randi() % 2), global_position, -2.0,
		float(_cfg["pitch"]) * _rng.randf_range(0.95, 1.05), 8.0, 70.0)
	if manager != null:
		manager.on_killed(self, by)


## Something frightening at `pos` - run from it.
func startle(pos: Vector3) -> void:
	if state == State.DEAD:
		return
	_threat_pos = pos
	_calm = _rng.randf_range(5.0, 8.0)
	if state != State.FLEE:
		_enter(State.FLEE)
		if manager != null:
			manager.alarm_herd(self, pos)


func _physics_process(delta: float) -> void:
	if world == null:
		return
	state_time += delta
	if state == State.DEAD:
		_dead(delta)
		return
	var pd := 999.0
	if player != null:
		pd = global_position.distance_to(player.global_position)
	dormant = pd > 150.0 and state != State.FLEE
	if dormant:
		_tick += 1
		rig.set_paused(true)
		if _tick % 8 == 0:
			_decide(delta * 8.0)
			_dormant_move(delta * 8.0)
		return
	rig.set_paused(false)
	_think -= delta
	if _think <= 0.0:
		_think = 0.2 if state != State.FLEE else 0.1
		_decide(_think)
	_move(delta)
	_animate(delta)


# ------------------------------------------------------------------ brain

func _decide(dt: float) -> void:
	_watch(dt)
	match state:
		State.GRAZE:
			_has_target = false
			if _wait <= 0.0:
				_wait = _rng.randf_range(4.0, 12.0)
			if state_time > _wait:
				_enter(State.WANDER)
				_target = _pick_wander()
				_has_target = true
		State.WANDER:
			if not _has_target or _flat_dist(_target) < 1.2 or state_time > 25.0:
				_enter(State.GRAZE)
		State.FLEE:
			_calm -= dt
			_tired += dt
			if _calm <= 0.0:
				hunter = null
				_tired = 0.0
				home = pos2()
				_enter(State.GRAZE)
				return
			var away := global_position - _threat_pos
			away.y = 0.0
			if away.length() < 0.1:
				away = forward()
			away = away.normalized()
			# keep running broadly away, drifting back toward the herd rather than scattering forever
			_target = global_position + away * 14.0
			_has_target = true


## Look out for danger: hunters closing in, or the deer blundering into the herd.
func _watch(_dt: float) -> void:
	if manager == null:
		return
	var danger: Node3D = null
	var best := INF
	for p: Node3D in manager.threats():
		var d := global_position.distance_to(p.global_position)
		var r := alarm_radius
		if p.get("_speed") != null and float(p.get("_speed")) < 2.6:
			r *= 0.45       # a predator strolling past or creeping in is noticed late
		elif p == hunter:
			r *= 1.6        # one charging straight at it is seen from far off
		if d < r and d < best:
			best = d
			danger = p
	if danger != null:
		startle(danger.global_position)
		return
	if player != null and not player.is_dead():
		var d := global_position.distance_to(player.global_position)
		var r := 3.5 if player.is_sneaking else (11.0 if player.is_sprinting else 7.0)
		if d < r:
			startle(player.global_position)


func _pick_wander() -> Vector3:
	for attempt in 12:
		var ang := _rng.randf() * TAU
		var p := home + Vector2(cos(ang), sin(ang)) * _rng.randf_range(3.0, 16.0)
		if _walkable(p.x, p.y):
			return Vector3(p.x, world.height_at(p.x, p.y), p.y)
	return global_position


func _walkable(x: float, z: float) -> bool:
	return world.is_walkable(x, z, false)


func _flat_dist(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()


func current_run_speed() -> float:
	# a long chase wears the animal down, which is how the slower hunters ever catch one
	return run_speed * lerpf(1.0, 0.68, clampf((_tired - flee_stamina) / 6.0, 0.0, 1.0))


# ------------------------------------------------------------------ movement

func _move(delta: float) -> void:
	var target_speed := 0.0
	var desired := _heading
	if _has_target:
		var to := _target - global_position
		to.y = 0.0
		var dist := to.length()
		if dist > 0.5:
			var dir := _avoid(to / dist, delta)
			desired = atan2(-dir.x, -dir.z)
			target_speed = current_run_speed() if state == State.FLEE else walk_speed
			if state != State.FLEE and dist < 2.0:
				target_speed = minf(target_speed, maxf(dist, 0.5))
	var agility := turn_rate / (1.0 + _speed * 0.04)
	var diff := absf(angle_difference(_heading, desired))
	_heading = rotate_toward(_heading, desired, agility * delta)
	if diff > 1.2 and state != State.FLEE:
		target_speed *= 0.5
	if world.water_depth(global_position.x, global_position.z) > 0.25:
		target_speed *= 0.6
	var rate := acceleration if target_speed > _speed else acceleration * 1.5
	_speed = move_toward(_speed, target_speed, rate * delta)
	rotation.y = _heading
	var fwd := forward()
	velocity.x = fwd.x * _speed
	velocity.z = fwd.z * _speed
	if is_on_floor():
		velocity.y = -1.0
	else:
		velocity.y -= 21.0 * delta
	move_and_slide()
	var ground := world.height_at(global_position.x, global_position.z)
	if global_position.y < ground - 2.0:
		global_position.y = ground + 0.3
		velocity.y = 0.0


func _avoid(dir: Vector3, delta: float) -> Vector3:
	if _avoid_time > 0.0:
		_avoid_time -= delta
		dir = dir.rotated(Vector3.UP, _avoid_bias)
	var look := clampf(_speed * 0.5, 2.0, 6.0)
	var p := global_position
	if _walkable(p.x + dir.x * look, p.z + dir.z * look):
		return dir
	for a: float in [0.6, -0.6, 1.2, -1.2, 1.9, -1.9, 2.6, -2.6]:
		var d2 := dir.rotated(Vector3.UP, a)
		if _walkable(p.x + d2.x * look, p.z + d2.z * look):
			_avoid_bias = a
			_avoid_time = 0.5
			return d2
	return dir


func _dormant_move(dt: float) -> void:
	_speed = 0.0
	velocity = Vector3.ZERO
	if not _has_target:
		return
	var to := _target - global_position
	to.y = 0.0
	var dist := to.length()
	if dist < 0.5:
		return
	var dir := to / dist
	var stepv := dir * minf(walk_speed * dt, dist)
	var nx := global_position.x + stepv.x
	var nz := global_position.z + stepv.z
	if _walkable(nx, nz):
		global_position = Vector3(nx, world.height_at(nx, nz), nz)
		_heading = atan2(-dir.x, -dir.z)
		rotation.y = _heading
		reset_physics_interpolation()
	else:
		_has_target = false


# ------------------------------------------------------------------ presentation

func _animate(delta: float) -> void:
	if _speed > 0.25 or (rig.current == "Walk" and _speed > 0.1):
		# the models only have a walk cycle; played fast it reads as a run
		var cap := lerpf(1.8, 3.2, clampf(_speed / run_speed, 0.0, 1.0))
		rig.play("Walk", rig.stride_rate("Walk", _speed, 0.4, cap, clampf(_speed / walk_speed, 0.6, 3.0)), 0.2)
	else:
		rig.play("Idle", 1.0, 0.35)
	# a gazelle in flight bounds along ("stotting") rather than scurrying
	var bound := 0.0
	if kind == "gazelle" and _speed > 5.0:
		_bound_phase += delta * 9.0
		bound = absf(sin(_bound_phase)) * 0.22 * clampf((_speed - 5.0) / 4.0, 0.0, 1.0)
	rig.lift = lerpf(rig.lift, bound, minf(delta * 14.0, 1.0))
	rig.fit_to_ground(world, global_position, forward(), body_length * 0.5, delta, is_on_floor())


func _dead(delta: float) -> void:
	# topple onto its side and lie still
	if _fall < 1.0:
		_fall = minf(_fall + delta * 2.2, 1.0)
		rig.set_paused(true)
		var e := 1.0 - pow(1.0 - _fall, 2.0)
		rig.rotation = Vector3(0.0, 0.0, e * 1.5)
		rig.position.y = e * float(_cfg["radius"]) * 0.75
		var ground := world.height_at(global_position.x, global_position.z)
		global_position.y = move_toward(global_position.y, ground, delta * 3.0)
	_carcass_time -= delta
	if _carcass_time <= 0.0 and manager != null:
		manager.recycle(self)
