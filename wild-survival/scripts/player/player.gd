class_name Player
extends CharacterBody3D
## The deer: movement (walk / trot / sprint / sneak / jump / swim), survival stats, stealth,
## grazing and drinking, footsteps and breathing.

signal damaged(amount: float, source: String)
signal died(cause: String)
signal interaction_changed(text: String)

enum Mode { NORMAL, EATING, DRINKING, DEAD }

const SNEAK_SPEED := 1.9
const TROT_SPEED := 5.4
const SPRINT_SPEED := 12.2
const TIRED_SPEED := 4.2
const SWIM_SPEED := 2.7
const ACCEL := 13.0
const DECEL := 16.0
const GRAVITY := 21.0
const JUMP_VELOCITY := 7.4

# --- survival stats
var max_health := 100.0
var max_stamina := 100.0
var health := 100.0
var stamina := 100.0
var hunger := 100.0      ## fullness: 100 = fed, 0 = starving
var thirst := 100.0      ## hydration: 100 = quenched, 0 = parched
var stamina_regen_bonus := 1.0
var exhausted := false

# --- stealth outputs (read by predators and the HUD)
var visibility := 1.0
var noise_radius := 0.0
var cover := 0.0
var is_sneaking := false
var is_sprinting := false
var in_grove := false
var in_water := false
var swimming := false
var mode: int = Mode.NORMAL

var world: WorldData
var vegetation: Vegetation
var camera_rig: Node3D
var rig: AnimalRig
var control_enabled := true

var _heading := 0.0
var _speed := 0.0
var _invulnerable := 0.0
var _since_damage := 99.0
var _sprint_rest := 0.0
const BREATH_MAX_GAIN := 0.14   # linear gain of the panting loop at full exhaustion (about -17 dB)
var _step_accum := 0.0
var _air_time := 0.0
var _idle_time := 0.0
var _idle_clip := "Idle"
var _hint := ""
var _poll := 0.0
var _food_site: Dictionary = {}
var _bite_timer := 0.0
var _rustle_cd := 0.0
var _last_pos := Vector3.ZERO
var _breath: AudioStreamPlayer
var _heart: AudioStreamPlayer
var _was_in_water := false
var _rng := RandomNumberGenerator.new()
var _starve_warned := false
var _thirst_warned := false
var _effects: PlayerEffects


func _ready() -> void:
	add_to_group("player")
	collision_layer = 4
	collision_mask = 11
	floor_max_angle = deg_to_rad(52.0)
	floor_snap_length = 0.5
	_rng.randomize()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.36
	shape.height = 1.25
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 0.63
	add_child(cs)
	rig = AnimalRig.new()
	rig.name = "Rig"
	add_child(rig)
	rig.setup("res://models/animals/deer.glb", 0.82)
	rig.play("Idle")
	_effects = PlayerEffects.new()
	add_child(_effects)
	_breath = AudioStreamPlayer.new()
	_breath.stream = AudioManager.looped("res://audio/deer/breath_pant.ogg")
	_breath.bus = "SFX"
	_breath.volume_db = -60.0
	add_child(_breath)
	_breath.play()
	_heart = AudioStreamPlayer.new()
	_heart.stream = AudioManager.looped("res://audio/ui/heartbeat.ogg")
	_heart.bus = "SFX"
	_heart.volume_db = -60.0
	add_child(_heart)
	_heart.play()
	_last_pos = global_position


func forward() -> Vector3:
	return Vector3(-sin(_heading), 0.0, -cos(_heading))


func face(dir: Vector3) -> void:
	_heading = atan2(-dir.x, -dir.z)
	rotation.y = _heading


func is_dead() -> bool:
	return mode == Mode.DEAD


func horizontal_speed() -> float:
	return Vector2(velocity.x, velocity.z).length()


# ------------------------------------------------------------------ main loop

func _physics_process(delta: float) -> void:
	if world == null:
		return
	if mode == Mode.DEAD:
		velocity.x = move_toward(velocity.x, 0.0, DECEL * delta)
		velocity.z = move_toward(velocity.z, 0.0, DECEL * delta)
		velocity.y -= GRAVITY * delta
		move_and_slide()
		return
	_invulnerable = maxf(_invulnerable - delta, 0.0)
	_since_damage += delta
	_rustle_cd = maxf(_rustle_cd - delta, 0.0)

	var input := Vector2.ZERO
	var want_sprint := false
	var want_sneak := false
	var want_jump := false
	var want_interact := false
	if control_enabled:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		want_sprint = Input.is_action_pressed("sprint")
		want_sneak = Input.is_action_pressed("sneak")
		want_jump = Input.is_action_just_pressed("jump")
		want_interact = Input.is_action_pressed("interact")
	_move(delta, input, want_sprint, want_sneak, want_jump)
	_interact(delta, want_interact, input.length() > 0.1)
	_update_stats(delta)
	_update_stealth()
	_animate(delta)
	_footsteps(delta)
	_update_audio(delta)
	_poll -= delta
	if _poll <= 0.0:
		_poll = 0.4
		_check_surroundings()
	var moved := global_position - _last_pos
	moved.y = 0.0
	if moved.length() < 5.0:
		GameState.distance_travelled += moved.length()
	_last_pos = global_position


func _move(delta: float, input: Vector2, want_sprint: bool, want_sneak: bool, want_jump: bool) -> void:
	var ground_h := world.height_at(global_position.x, global_position.z)
	var depth := WorldData.WATER_LEVEL - ground_h
	in_water = depth > 0.12 and global_position.y < WorldData.WATER_LEVEL + 0.2
	swimming = depth > 1.0 and global_position.y < WorldData.WATER_LEVEL - 0.6

	var moving := input.length() > 0.1
	is_sprinting = moving and want_sprint and not exhausted and stamina > 0.0 and not swimming and mode == Mode.NORMAL
	is_sneaking = want_sneak and not is_sprinting and not swimming
	var target := 0.0
	if moving:
		if mode != Mode.NORMAL:
			_set_mode(Mode.NORMAL)
		if swimming:
			target = SWIM_SPEED
		elif is_sprinting:
			target = SPRINT_SPEED
		elif is_sneaking:
			target = SNEAK_SPEED
		else:
			target = TROT_SPEED
		if exhausted and not is_sneaking and not swimming:
			target = minf(target, TIRED_SPEED)
		if in_water and not swimming:
			target *= lerpf(1.0, 0.6, clampf(depth / 0.9, 0.0, 1.0))
		# starving / parched animals are weaker
		if hunger <= 0.0 or thirst <= 0.0:
			target *= 0.85
		# camera-relative direction
		var cam_yaw := camera_rig.rotation.y if camera_rig != null else 0.0
		var dir := Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, cam_yaw).normalized()
		var want_heading := atan2(-dir.x, -dir.z)
		var turn_rate := lerpf(9.0, 4.2, clampf(_speed / SPRINT_SPEED, 0.0, 1.0))
		_heading = rotate_toward(_heading, want_heading, turn_rate * delta)
		# slow down through sharp turns so the body does not skate sideways
		var diff := absf(angle_difference(_heading, want_heading))
		if diff > 1.2:
			target *= 0.45
	var rate := ACCEL if target > _speed else DECEL
	if not is_on_floor() and not swimming:
		rate *= 0.35
	_speed = move_toward(_speed, target, rate * delta)
	rotation.y = _heading
	var fwd := forward()
	velocity.x = fwd.x * _speed
	velocity.z = fwd.z * _speed

	if swimming:
		# float with the back just above the surface
		var float_y := WorldData.WATER_LEVEL - 0.95
		velocity.y = (float_y - global_position.y) * 5.0
		_air_time = 0.0
	elif is_on_floor():
		if _air_time > 0.35:
			AudioManager.play_at("res://audio/deer/land.ogg", global_position, -6.0, _rng.randf_range(0.95, 1.05), 5.0, 40.0)
		_air_time = 0.0
		velocity.y = -1.0
		if want_jump and stamina >= 6.0 and mode == Mode.NORMAL:
			velocity.y = JUMP_VELOCITY
			stamina -= 6.0
			_sprint_rest = 0.6
			floor_snap_length = 0.0
	else:
		_air_time += delta
		velocity.y -= GRAVITY * delta
		if velocity.y < 0.0:
			floor_snap_length = 0.5
	move_and_slide()
	# world boundary: the mountain ring is steep, this is only a safety net
	var lim := WorldData.PLAY_LIMIT + 8.0
	if absf(global_position.x) > lim or absf(global_position.z) > lim:
		global_position.x = clampf(global_position.x, -lim, lim)
		global_position.z = clampf(global_position.z, -lim, lim)
	if global_position.y < ground_h - 3.0:
		global_position.y = ground_h + 0.5
		velocity.y = 0.0
	if in_water and not _was_in_water and _speed > 2.0:
		AudioManager.play_at("res://audio/deer/splash.ogg", global_position, -3.0, _rng.randf_range(0.9, 1.1), 7.0, 60.0)
	_was_in_water = in_water
	if _effects != null:
		_effects.update(in_water and _speed > 1.5 and not swimming or (swimming and _speed > 0.8),
			is_sprinting and is_on_floor() and not in_water, world.surface_at(global_position.x, global_position.z))


# ------------------------------------------------------------------ eating / drinking

func can_drink() -> bool:
	var p := global_position
	if world.water_depth(p.x, p.z) > 0.02 and not swimming:
		return true
	var f := forward()
	return world.height_at(p.x + f.x * 1.3, p.z + f.z * 1.3) < WorldData.WATER_LEVEL - 0.03 \
		or world.water_distance(p.x, p.z) < 0.8


func _interact(delta: float, want: bool, moving: bool) -> void:
	var hint := ""
	_food_site = vegetation.nearest_food(global_position, 2.8) if vegetation != null else {}
	var drink_ok := can_drink()
	var graze_ok := is_on_floor() and world.surface_at(global_position.x, global_position.z) == &"grass"
	var key := Settings.binding_text("interact")
	if drink_ok and thirst < 99.0:
		hint = "Hold [%s] to drink" % key
	elif not _food_site.is_empty() and hunger < 99.0:
		hint = "Hold [%s] to eat %s" % [key, _food_site["name"]]
	elif graze_ok and hunger < 80.0:
		hint = "Hold [%s] to graze" % key
	if want and not moving and is_on_floor() and _speed < 0.5:
		if drink_ok and thirst < 99.5:
			_set_mode(Mode.DRINKING)
			thirst = minf(thirst + 15.0 * delta, 100.0)
			hint = "Drinking..."
		elif not _food_site.is_empty() and hunger < 99.5:
			_set_mode(Mode.EATING)
			var bite := minf(10.0 * delta, float(_food_site["amount"]))
			_food_site["amount"] = float(_food_site["amount"]) - bite * 1.6
			hunger = minf(hunger + bite, 100.0)
			thirst = minf(thirst + bite * 0.12, 100.0)
			hint = "Eating %s..." % _food_site["name"]
		elif graze_ok and hunger < 80.0:
			_set_mode(Mode.EATING)
			hunger = minf(hunger + 3.2 * delta, 80.0)
			hint = "Grazing..."
		else:
			_set_mode(Mode.NORMAL)
		if mode != Mode.NORMAL:
			_bite_timer -= delta
			if _bite_timer <= 0.0:
				_bite_timer = 1.6 if mode == Mode.EATING else 2.2
				var snd := "res://audio/deer/eat.ogg" if mode == Mode.EATING else "res://audio/deer/drink.ogg"
				AudioManager.play_at(snd, global_position, -7.0, _rng.randf_range(0.94, 1.06), 4.0, 30.0)
	elif mode != Mode.NORMAL:
		_set_mode(Mode.NORMAL)
	if hint != _hint:
		_hint = hint
		interaction_changed.emit(hint)


func _set_mode(m: int) -> void:
	if mode == Mode.DEAD or mode == m:
		return
	mode = m
	_bite_timer = 0.3


func interaction_hint() -> String:
	return _hint


# ------------------------------------------------------------------ stats

func _update_stats(delta: float) -> void:
	var effort := 1.0
	if is_sprinting:
		effort = 1.9
	elif _speed > 3.0:
		effort = 1.25
	hunger = maxf(hunger - 0.175 * effort * delta, 0.0)
	thirst = maxf(thirst - 0.235 * effort * delta, 0.0)

	if is_sprinting:
		stamina -= 8.5 * delta
		_sprint_rest = 1.1
	elif swimming:
		stamina -= 3.0 * delta
		_sprint_rest = 0.8
	else:
		_sprint_rest -= delta
		if _sprint_rest <= 0.0:
			var regen := 13.0 if _speed < 3.0 else 7.5
			if hunger < 20.0 or thirst < 20.0:
				regen *= 0.5
			if mode != Mode.NORMAL:
				regen *= 1.2
			stamina += regen * stamina_regen_bonus * delta
	stamina = clampf(stamina, 0.0, max_stamina)
	if stamina <= 0.0 and not exhausted:
		exhausted = true
		GameState.notify("Exhausted", "Catch your breath before sprinting again.")
	elif exhausted and stamina >= max_stamina * 0.28:
		exhausted = false

	var drain := 0.0
	if hunger <= 0.0:
		drain += 1.3
		if not _starve_warned:
			_starve_warned = true
			GameState.notify("Starving", "Find berry bushes or graze on grass.")
	elif hunger > 15.0:
		_starve_warned = false
	if thirst <= 0.0:
		drain += 1.7
		if not _thirst_warned:
			_thirst_warned = true
			GameState.notify("Dehydrated", "Find the river or a lake and drink.")
	elif thirst > 15.0:
		_thirst_warned = false
	if swimming and stamina <= 0.0:
		drain += 6.0
	if drain > 0.0:
		health -= drain * delta
		if health <= 0.0:
			var cause := "drowned" if swimming and stamina <= 0.0 else ("thirst" if thirst <= 0.0 else "starvation")
			_die(cause)
	elif _since_damage > 7.0 and hunger > 35.0 and thirst > 35.0 and health < max_health:
		health = minf(health + (1.6 if in_grove else 0.75) * delta, max_health)


func take_damage(amount: float, source: String, from: Vector3 = Vector3.ZERO) -> bool:
	if mode == Mode.DEAD or _invulnerable > 0.0:
		return false
	health -= amount
	_invulnerable = 1.0
	_since_damage = 0.0
	# adrenaline: a wounded deer gets one more burst
	stamina = minf(stamina + 30.0, max_stamina)
	exhausted = false
	if from != Vector3.ZERO:
		var push := (global_position - from)
		push.y = 0.0
		_speed = maxf(_speed, 6.0)
		velocity += push.normalized() * 4.0
	AudioManager.play_at("res://audio/deer/hurt%d.ogg" % (1 + _rng.randi() % 2), global_position, 0.0, _rng.randf_range(0.95, 1.05), 8.0, 60.0)
	damaged.emit(amount, source)
	_set_mode(Mode.NORMAL)
	if health <= 0.0:
		_die(source)
	return true


func heal(amount: float) -> void:
	health = minf(health + amount, max_health)


func _die(cause: String) -> void:
	if mode == Mode.DEAD:
		return
	health = 0.0
	mode = Mode.DEAD
	_speed = 0.0
	is_sprinting = false
	rig.play("Death", 1.0, 0.15, true)
	AudioManager.play_at("res://audio/deer/death.ogg", global_position, 0.0, 1.0, 8.0, 60.0)
	_breath.volume_db = -60.0
	_heart.volume_db = -60.0
	died.emit(cause)


# ------------------------------------------------------------------ stealth

func _update_stealth() -> void:
	cover = world.cover_at(global_position.x, global_position.z)
	in_grove = world.in_safe_zone(Vector2(global_position.x, global_position.z))
	var v := 1.0
	if is_sprinting:
		v *= 1.0 - cover * 0.25
		noise_radius = 27.0
	elif _speed > 2.5:
		v *= 1.0 - cover * 0.6
		noise_radius = 13.0
	elif _speed > 0.3:
		v *= (1.0 - cover * 0.88) * 0.6
		noise_radius = 3.5
	else:
		v *= (1.0 - cover * 0.95) * 0.66
		noise_radius = 0.0
		if mode == Mode.EATING:
			noise_radius = 5.0
	if in_water:
		noise_radius *= 1.35
		if swimming:
			v *= 0.6
	if in_grove:
		v = 0.0
		noise_radius *= 0.3
	visibility = clampf(v, 0.0, 1.0)


func is_hidden() -> bool:
	return visibility < 0.3


# ------------------------------------------------------------------ presentation

func _animate(delta: float) -> void:
	if mode == Mode.DEAD:
		return
	var on_ground := is_on_floor() or swimming
	if not on_ground and _air_time > 0.12:
		rig.play("Jump", 1.5, 0.15)
	elif mode == Mode.EATING or mode == Mode.DRINKING:
		rig.play("Eat", 1.0, 0.35)
	elif _speed > 6.5:
		rig.play("Run", lerpf(2.3, 3.3, clampf((_speed - 6.5) / 6.0, 0.0, 1.0)), 0.2)
	elif _speed > 3.2:
		rig.play("Run", lerpf(1.7, 2.3, (_speed - 3.2) / 3.3), 0.25)
	elif _speed > 0.25:
		rig.play("Walk", clampf(_speed / 1.25, 0.7, 2.6) * (0.85 if swimming else 1.0), 0.25)
	else:
		_idle_time += delta
		if _idle_time > 5.0 or not rig.current.begins_with("Idle"):
			_idle_time = 0.0
			_idle_clip = ["Idle", "Idle", "Idle2", "Idle3"][_rng.randi() % 4]
		rig.play(_idle_clip, 1.0, 0.4)
	if swimming:
		rig.align_to_ground(Vector3.UP, forward(), delta)
	else:
		rig.align_to_ground(world.normal_at(global_position.x, global_position.z), forward(), delta)


func _footsteps(delta: float) -> void:
	if not is_on_floor() or _speed < 0.4:
		return
	_step_accum += _speed * delta
	var stride := 0.75 if _speed < 3.0 else (1.5 if _speed < 7.0 else 2.6)
	if _step_accum < stride:
		return
	_step_accum = 0.0
	var surface := world.surface_at(global_position.x, global_position.z)
	var path := ""
	# Hoofbeats are only slightly louder at a gallop than at a walk, and the level depends on
	# the current speed alone, so it can never build up over the length of a sprint.
	var vol := lerpf(-17.0, -11.0, clampf(_speed / SPRINT_SPEED, 0.0, 1.0))
	match surface:
		&"water":
			path = "res://audio/deer/splash.ogg"
			vol -= 8.0
		&"mud":
			path = "res://audio/deer/step_mud%d.ogg" % (1 + _rng.randi() % 4)
		&"rock":
			path = "res://audio/deer/step_rock%d.ogg" % (1 + _rng.randi() % 4)
		&"dirt":
			path = "res://audio/deer/step_dirt%d.ogg" % (1 + _rng.randi() % 4)
		_:
			path = "res://audio/deer/step_grass%d.ogg" % (1 + _rng.randi() % 8)
	if is_sneaking:
		vol -= 8.0
	AudioManager.play_at(path, global_position, vol, _rng.randf_range(0.9, 1.1), 4.0, 45.0)
	if cover > 0.45 and _rustle_cd <= 0.0 and _speed > 1.0:
		_rustle_cd = 0.7
		AudioManager.play_at("res://audio/deer/bush_rustle%d.ogg" % (1 + _rng.randi() % 3), global_position,
			vol - 1.0, _rng.randf_range(0.9, 1.1), 5.0, 45.0)


func _update_audio(delta: float) -> void:
	var tired := 1.0 - stamina / max_stamina
	# Panting only comes in when the deer is nearly out of breath, and stays well under the
	# hoofbeats: it used to swell steadily through a whole sprint and drown everything else.
	var pant := smoothstep(0.6, 0.95, tired)
	_breath.volume_db = lerpf(_breath.volume_db, linear_to_db(maxf(pant * BREATH_MAX_GAIN, 0.0001)), minf(delta * 3.0, 1.0))
	_breath.pitch_scale = lerpf(0.92, 1.12, pant)
	var danger := 1.0 - smoothstep(0.12, 0.4, health / max_health)
	if GameState.threat == GameState.Threat.HUNTED:
		danger = maxf(danger, 0.35)
	_heart.volume_db = lerpf(_heart.volume_db, linear_to_db(maxf(danger * 0.8, 0.0001)), minf(delta * 3.0, 1.0))
	_heart.pitch_scale = lerpf(1.0, 1.35, danger)


# ------------------------------------------------------------------ exploration

var _was_in_grove := false

func _check_surroundings() -> void:
	var p := Vector2(global_position.x, global_position.z)
	var grove := world.grove_at(p)
	if not grove.is_empty():
		if not _was_in_grove:
			if GameState.discover(grove["id"]):
				GameState.notify("Discovered: %s" % grove["name"], "A thicket too dense for predators. You are safe here.")
				AudioManager.play_ui("res://audio/ui/discover.ogg", -6.0)
			else:
				GameState.notify(grove["name"], "Safe thicket - predators cannot follow.")
		_was_in_grove = true
	else:
		_was_in_grove = false
	for poi in world.pois:
		if p.distance_to(poi["pos"]) > float(poi["radius"]):
			continue
		if not GameState.discover(poi["id"]):
			continue
		AudioManager.play_ui("res://audio/ui/discover.ogg", -6.0)
		match poi["type"]:
			"salt_lick":
				max_stamina += 12.0
				heal(40.0)
				GameState.notify("Discovered: %s" % poi["name"], "Minerals strengthen you. Max stamina +12, health restored.")
			"elder_tree":
				max_health += 15.0
				stamina_regen_bonus += 0.12
				heal(999.0)
				stamina = max_stamina
				GameState.notify("Discovered: %s" % poi["name"], "An ancient giant. Max health +15, faster recovery.")
			"orchard":
				GameState.notify("Discovered: %s" % poi["name"], "Plenty of rich food grows here.")
			"lake":
				thirst = minf(thirst + 10.0, 100.0)
				GameState.notify("Discovered: %s" % poi["name"], "Fresh water - but predators drink here too.")


## Put the deer back at a spawn point with fresh stats (new run).
func reset_at(pos: Vector3, facing: float) -> void:
	max_health = 100.0
	max_stamina = 100.0
	health = 100.0
	stamina = 100.0
	hunger = 85.0
	thirst = 85.0
	stamina_regen_bonus = 1.0
	exhausted = false
	mode = Mode.NORMAL
	velocity = Vector3.ZERO
	_speed = 0.0
	_heading = facing
	rotation.y = facing
	global_position = pos
	_last_pos = pos
	_invulnerable = 0.0
	_since_damage = 99.0
	_was_in_grove = false
	_starve_warned = false
	_thirst_warned = false
	rig.play("Idle", 1.0, 0.0, true)
	reset_physics_interpolation()
