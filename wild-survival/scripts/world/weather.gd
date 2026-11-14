class_name Weather
extends Node3D
## Dynamic weather: fair -> overcast -> rain -> storm and back, with rain streaks that follow the
## camera, splashes, darker skies, thicker air, a rain sound loop, thunder and lightning.
## Rain also changes the game: hunters see and hear less, and the deer slowly takes on water.

signal changed(state: int)

enum State { CLEAR, OVERCAST, RAIN, STORM }
const NAMES := ["Clear", "Overcast", "Rain", "Storm"]
const TARGET_RAIN := [0.0, 0.0, 0.6, 1.0]
const TARGET_CLOUD := [0.0, 0.7, 0.9, 1.0]

var day_night: DayNight
var follow: Node3D
var state: int = State.CLEAR
var rain := 0.0          ## 0..1 how hard it is raining right now
var cloud := 0.0         ## 0..1 how overcast the sky is
var storminess := 0.45   ## 0 never rains .. 1 rains most of the time (set per level)
var auto := true         ## change by itself over time
var flash := 0.0         ## lightning brightness, decays quickly
var _timer := 40.0
var _rng := RandomNumberGenerator.new()
var _rain: GPUParticles3D
var _splash: GPUParticles3D
var _rain_mat: ParticleProcessMaterial
var _loop: AudioStreamPlayer
var _thunder_cd := 8.0
var _max_drops := 1800


func setup(p_day_night: DayNight) -> void:
	day_night = p_day_night
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_rng.randomize()
	_build_rain()
	_loop = AudioStreamPlayer.new()
	_loop.stream = make_rain_stream()
	_loop.bus = "Ambience"
	_loop.volume_db = -60.0
	add_child(_loop)
	Settings.changed.connect(func(section: String, _k: String) -> void:
		if section == "graphics":
			_apply_quality())
	_apply_quality()


func _apply_quality() -> void:
	var preset := int(Settings.get_value("graphics", "preset"))
	_max_drops = [500, 1000, 1800, 2600][clampi(preset, 0, 3)]
	_rain.amount = _max_drops
	_splash.amount = maxi(_max_drops / 8, 40)


## Looping rain: filtered noise with a slow swell, generated once (no audio file needed).
static func make_rain_stream() -> AudioStreamWAV:
	var rate := 22050
	var n := rate * 3
	var data := PackedByteArray()
	data.resize(n * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var lp := 0.0
	var lp2 := 0.0
	var fade := rate / 8
	var raw := PackedFloat32Array()
	raw.resize(n + fade)
	for i in n + fade:
		var w := rng.randf() * 2.0 - 1.0
		lp += (w - lp) * 0.55          # soften the hiss
		lp2 += (w - lp2) * 0.02        # low rumble of heavy drops
		raw[i] = (lp - lp2 * 0.5) * 0.55 + lp2 * 0.9
	for i in n:
		var v := raw[i]
		if i < fade:                    # cross-fade the tail into the head for a seamless loop
			var k := float(i) / fade
			v = raw[i] * k + raw[n + i] * (1.0 - k)
		data.encode_s16(i * 2, int(clampf(v, -1.0, 1.0) * 30000.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = false
	s.data = data
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = n
	return s


func _streak_texture() -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 8
	t.height = 4
	t.fill_from = Vector2(0, 0.5)
	t.fill_to = Vector2(1, 0.5)
	return t


func _build_rain() -> void:
	# falling streaks: thin tall quads that only turn around the vertical axis
	_rain = GPUParticles3D.new()
	_rain.name = "Rain"
	var quad := QuadMesh.new()
	quad.size = Vector2(0.022, 0.85)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.78, 0.85, 0.95, 0.42)
	m.albedo_texture = _streak_texture()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.disable_receive_shadows = true
	m.no_depth_test = false
	quad.material = m
	_rain.draw_pass_1 = quad
	_rain_mat = ParticleProcessMaterial.new()
	_rain_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_rain_mat.emission_box_extents = Vector3(20.0, 0.5, 20.0)
	_rain_mat.direction = Vector3(0.12, -1.0, 0.05)
	_rain_mat.spread = 2.0
	_rain_mat.initial_velocity_min = 19.0
	_rain_mat.initial_velocity_max = 24.0
	_rain_mat.gravity = Vector3(0.0, -6.0, 0.0)
	_rain.process_material = _rain_mat
	_rain.amount = _max_drops
	_rain.lifetime = 0.8
	_rain.preprocess = 0.8
	_rain.local_coords = false
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain.visibility_aabb = AABB(Vector3(-26, -30, -26), Vector3(52, 40, 52))
	_rain.emitting = false
	add_child(_rain)

	# splashes where the drops land
	_splash = GPUParticles3D.new()
	_splash.name = "Splash"
	var sq := QuadMesh.new()
	sq.size = Vector2(0.16, 0.16)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = Color(0.85, 0.9, 1.0, 0.35)
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	if ResourceLoader.exists("res://textures/particles/dust_256a.png"):
		sm.albedo_texture = load("res://textures/particles/dust_256a.png")
	sq.material = sm
	_splash.draw_pass_1 = sq
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(12.0, 0.05, 12.0)
	pm.direction = Vector3.UP
	pm.spread = 40.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.4
	pm.gravity = Vector3(0, -5.0, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	_splash.process_material = pm
	_splash.amount = 200
	_splash.lifetime = 0.35
	_splash.local_coords = false
	_splash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_splash.visibility_aabb = AABB(Vector3(-16, -4, -16), Vector3(32, 8, 32))
	_splash.emitting = false
	add_child(_splash)


func is_raining() -> bool:
	return rain > 0.15


func state_name() -> String:
	return NAMES[state]


## How much rain blunts the hunters' eyes and ears (1 = no effect).
func sense_factor() -> float:
	return 1.0 - 0.32 * rain


func set_state(s: int, instant := false) -> void:
	if s != state:
		state = s
		changed.emit(s)
		if GameState.in_game:
			match s:
				State.RAIN:
					GameState.notify("Rain", "Rain masks your sound and scent. Hunters sense less - and so do you.")
				State.STORM:
					GameState.notify("Storm", "A monsoon storm breaks over the jungle.")
				State.CLEAR:
					GameState.notify("The sky clears", "")
	if instant:
		rain = TARGET_RAIN[s]
		cloud = TARGET_CLOUD[s]
		_apply()


func reset(p_storminess: float) -> void:
	storminess = p_storminess
	_timer = _rng.randf_range(35.0, 70.0)
	flash = 0.0
	set_state(State.CLEAR, true)


func _next_state() -> int:
	var r := _rng.randf()
	match state:
		State.CLEAR:
			return State.OVERCAST if r < 0.25 + storminess * 0.75 else State.CLEAR
		State.OVERCAST:
			return State.RAIN if r < 0.2 + storminess * 0.7 else State.CLEAR
		State.RAIN:
			if r < storminess * 0.5:
				return State.STORM
			return State.RAIN if r < storminess else State.OVERCAST
	return State.RAIN


func _process(delta: float) -> void:
	if day_night == null:
		return
	if auto and not day_night.paused and storminess > 0.0:
		_timer -= delta
		if _timer <= 0.0:
			set_state(_next_state())
			_timer = _rng.randf_range(45.0, 100.0) * (0.7 if state >= State.RAIN and storminess < 0.4 else 1.0)
	rain = move_toward(rain, TARGET_RAIN[state], delta * 0.07)
	cloud = move_toward(cloud, TARGET_CLOUD[state], delta * 0.09)
	flash = maxf(flash - delta * 3.5, 0.0)
	if state == State.STORM and rain > 0.7:
		_thunder_cd -= delta
		if _thunder_cd <= 0.0:
			_thunder_cd = _rng.randf_range(9.0, 24.0)
			strike()
	_apply()


## Lightning flash followed by thunder.
func strike() -> void:
	flash = 1.0
	if ResourceLoader.exists("res://audio/ambience/thunder_a.ogg"):
		AudioManager.play_ui("res://audio/ambience/thunder_a.ogg", _rng.randf_range(-7.0, -2.0), _rng.randf_range(0.8, 1.1))


func _apply() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var anchor: Vector3 = cam.global_position if cam != null else (follow.global_position if follow != null else Vector3.ZERO)
	_rain.emitting = rain > 0.02
	_splash.emitting = rain > 0.1
	if _rain.emitting:
		_rain.global_position = anchor + Vector3(0.0, 13.0, 0.0)
		_rain.amount_ratio = clampf(rain, 0.08, 1.0)
		var ground := follow.global_position if follow != null else anchor - Vector3(0, 2, 0)
		_splash.global_position = Vector3(ground.x, ground.y + 0.05, ground.z)
		_splash.amount_ratio = clampf(rain, 0.1, 1.0)
	var vol := linear_to_db(clampf(rain * 0.55, 0.0001, 1.0))
	_loop.volume_db = vol
	if rain > 0.01 and not _loop.playing:
		_loop.play()
	elif rain <= 0.01 and _loop.playing:
		_loop.stop()
	day_night.cloud = cloud
	day_night.rain = rain
	day_night.flash = flash
