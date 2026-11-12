class_name DayNight
extends Node3D
## Day / night cycle: sun and moon lights, sky shader, fog, ambient light and exposure transitions.
## Exposes `night_factor` (0 day .. 1 deep night) which drives predator activity and ambience.

signal phase_changed(phase: StringName)
signal day_passed(day: int)

const ENV_PATH := "res://environments/jungle_environment.tres"
const SKY_SHADER := preload("res://shaders/sky.gdshader")

@export var day_length_seconds := 840.0     ## real seconds for a full 24 h
@export var night_speedup := 1.35           ## nights pass a little faster than days
@export var time_of_day := 7.5              ## hours, 0..24
@export var paused := false

var day := 1
var night_factor := 0.0
var day_factor := 1.0
var sunset_factor := 0.0
var phase: StringName = &"day"

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var env: Environment
var world_env: WorldEnvironment
var sky_material: ShaderMaterial
var water_material: ShaderMaterial

const FOG_DAY := Color(0.60, 0.70, 0.64)
const FOG_NIGHT := Color(0.016, 0.024, 0.045)
const FOG_SUNSET := Color(0.86, 0.52, 0.30)
const SUN_NOON := Color(1.0, 0.96, 0.88)
const SUN_LOW := Color(1.0, 0.56, 0.28)


static func build_environment() -> Environment:
	var e := Environment.new()
	var sm := ShaderMaterial.new()
	sm.shader = SKY_SHADER
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.008
	noise.fractal_octaves = 5
	var nt := NoiseTexture2D.new()
	nt.width = 512
	nt.height = 512
	nt.seamless = true
	nt.generate_mipmaps = true
	nt.noise = noise
	sm.set_shader_parameter("noise_tex", nt)
	var sky := Sky.new()
	sky.sky_material = sm
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_color = Color(0.25, 0.32, 0.42)
	e.ambient_light_sky_contribution = 0.75
	e.ambient_light_energy = 1.0
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.0
	e.tonemap_white = 6.0
	e.ssao_enabled = true
	e.ssao_radius = 1.4
	e.ssao_intensity = 2.2
	e.ssao_power = 1.6
	e.ssao_light_affect = 0.15
	e.glow_enabled = true
	e.glow_intensity = 0.55
	e.glow_bloom = 0.06
	e.glow_hdr_threshold = 1.1
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	e.fog_density = 0.0055
	e.fog_light_color = FOG_DAY
	e.fog_sun_scatter = 0.25
	e.fog_aerial_perspective = 0.45
	e.fog_sky_affect = 0.25
	e.fog_height = 30.0
	e.fog_height_density = 0.02
	e.volumetric_fog_enabled = true
	e.volumetric_fog_density = 0.006
	e.volumetric_fog_albedo = Color(0.86, 0.93, 0.86)
	e.volumetric_fog_anisotropy = 0.72
	e.volumetric_fog_length = 110.0
	e.volumetric_fog_detail_spread = 2.2
	e.volumetric_fog_ambient_inject = 0.25
	e.volumetric_fog_sky_affect = 0.0
	e.volumetric_fog_temporal_reprojection_enabled = true
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.06
	e.adjustment_contrast = 1.04
	return e


func _ready() -> void:
	if ResourceLoader.exists(ENV_PATH):
		env = (load(ENV_PATH) as Environment).duplicate(true)
	else:
		env = build_environment()
	sky_material = env.sky.sky_material as ShaderMaterial
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 170.0
	sun.directional_shadow_split_1 = 0.07
	sun.directional_shadow_split_2 = 0.2
	sun.directional_shadow_split_3 = 0.45
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.6
	sun.shadow_blur = 1.2
	sun.light_angular_distance = 0.6
	sun.light_volumetric_fog_energy = 1.6
	sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(sun)

	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.55, 0.68, 1.0)
	moon.shadow_enabled = true
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	moon.directional_shadow_max_distance = 90.0
	moon.shadow_normal_bias = 2.0
	moon.shadow_blur = 2.0
	moon.light_volumetric_fog_energy = 0.6
	moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(moon)

	Settings.changed.connect(_on_settings_changed)
	_apply_quality()
	_update_lighting()


func _on_settings_changed(section: String, _key: String) -> void:
	if section == "graphics":
		_apply_quality()


func _apply_quality() -> void:
	env.volumetric_fog_enabled = bool(Settings.get_value("graphics", "volumetric_fog"))
	env.ssao_enabled = bool(Settings.get_value("graphics", "ssao"))
	var q := int(Settings.get_value("graphics", "shadows"))
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if q == 0 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = [90.0, 130.0, 170.0, 220.0][clampi(q, 0, 3)]


func _process(delta: float) -> void:
	if paused:
		return
	var speed := 24.0 / day_length_seconds
	if is_night():
		speed *= night_speedup
	var before := time_of_day
	time_of_day += delta * speed
	if time_of_day >= 24.0:
		time_of_day -= 24.0
	if before < 6.0 and time_of_day >= 6.0:
		day += 1
		day_passed.emit(day)
	_update_lighting()


func is_night() -> bool:
	return time_of_day >= 19.5 or time_of_day < 5.0


func set_time(hours: float) -> void:
	time_of_day = fposmod(hours, 24.0)
	_update_lighting()


func clock_text() -> String:
	var h := int(time_of_day)
	var m := int((time_of_day - h) * 60.0)
	return "%02d:%02d" % [h, m]


func _update_lighting() -> void:
	var a := (time_of_day - 6.0) / 12.0 * PI
	var elev := sin(a)
	var to_sun := Vector3(cos(a), elev, 0.38).normalized()
	day_factor = smoothstep(-0.10, 0.20, elev)
	night_factor = 1.0 - smoothstep(-0.22, 0.06, elev)
	sunset_factor = (1.0 - smoothstep(0.0, 0.38, absf(elev))) * smoothstep(-0.25, -0.02, elev)

	var new_phase: StringName = &"day"
	if time_of_day >= 5.0 and time_of_day < 7.5:
		new_phase = &"dawn"
	elif time_of_day >= 17.5 and time_of_day < 19.5:
		new_phase = &"dusk"
	elif is_night():
		new_phase = &"night"
	if new_phase != phase:
		phase = new_phase
		phase_changed.emit(phase)

	# sun
	var sun_energy := smoothstep(-0.04, 0.22, elev) * 1.35
	sun.visible = sun_energy > 0.01
	if sun.visible:
		sun.look_at_from_position(Vector3.ZERO, -to_sun, Vector3.UP)
		sun.light_energy = sun_energy
		sun.light_color = SUN_LOW.lerp(SUN_NOON, smoothstep(0.05, 0.5, elev))
	# moon rides opposite the sun, never quite at the horizon so nights stay readable
	var to_moon := Vector3(-cos(a), maxf(-elev, 0.0) * 0.8 + 0.35, -0.38).normalized()
	var moon_energy := night_factor * 0.26
	moon.visible = moon_energy > 0.01
	if moon.visible:
		moon.look_at_from_position(Vector3.ZERO, -to_moon, Vector3.UP)
		moon.light_energy = moon_energy
	sun.shadow_enabled = sun_energy >= moon_energy
	moon.shadow_enabled = not sun.shadow_enabled

	# sky / fog / exposure
	sky_material.set_shader_parameter("day_factor", day_factor)
	sky_material.set_shader_parameter("sunset_factor", sunset_factor)
	sky_material.set_shader_parameter("sun_direction", to_sun)
	sky_material.set_shader_parameter("moon_direction", to_moon)
	sky_material.set_shader_parameter("sun_color", sun.light_color)
	sky_material.set_shader_parameter("sun_energy", sun_energy)
	sky_material.set_shader_parameter("moon_energy", moon_energy)
	var fog := FOG_NIGHT.lerp(FOG_DAY, day_factor).lerp(FOG_SUNSET * maxf(day_factor, 0.25), sunset_factor * 0.55)
	env.fog_light_color = fog
	# morning mist, thicker night air
	var mist := (1.0 - smoothstep(0.0, 0.5, absf(time_of_day - 6.2) / 2.0)) * 0.006
	env.fog_density = lerpf(0.0085, 0.0052, day_factor) + mist
	env.volumetric_fog_density = lerpf(0.005, 0.0065, day_factor) + mist * 1.5
	env.volumetric_fog_albedo = Color(0.5, 0.6, 0.8).lerp(Color(0.86, 0.93, 0.86), day_factor)
	env.ambient_light_color = Color(0.10, 0.14, 0.24).lerp(Color(0.42, 0.50, 0.52), day_factor)
	env.ambient_light_energy = lerpf(0.55, 1.0, day_factor)
	env.tonemap_exposure = lerpf(1.25, 1.0, day_factor)
	if water_material != null:
		water_material.set_shader_parameter("night_factor", night_factor)
