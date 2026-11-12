class_name PlayerEffects
extends Node3D
## Small particle effects attached to the deer: water splashes while wading and dust kicked up
## when sprinting on dry ground.

var _splash: GPUParticles3D
var _dust: GPUParticles3D


static func make_particles(texture_path: String, amount: int, lifetime: float, size: float, color: Color,
		additive := false) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = color
	mat.disable_receive_shadows = true
	if ResourceLoader.exists(texture_path):
		mat.albedo_texture = load(texture_path)
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = mat
	p.draw_pass_1 = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


func _ready() -> void:
	_splash = make_particles("res://textures/particles/water_splash.png", 28, 0.7, 0.55, Color(0.9, 0.95, 1.0, 0.7))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.4
	pm.direction = Vector3.UP
	pm.spread = 40.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 3.5
	pm.gravity = Vector3(0.0, -9.0, 0.0)
	pm.scale_min = 0.5
	pm.scale_max = 1.2
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	_splash.process_material = pm
	_splash.emitting = false
	_splash.position.y = 0.1
	add_child(_splash)

	_dust = make_particles("res://textures/particles/dust_256a.png", 18, 1.3, 1.1, Color(0.62, 0.52, 0.38, 0.35))
	var dm := ParticleProcessMaterial.new()
	dm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	dm.emission_sphere_radius = 0.3
	dm.direction = Vector3.UP
	dm.spread = 60.0
	dm.initial_velocity_min = 0.3
	dm.initial_velocity_max = 1.0
	dm.gravity = Vector3(0.0, 0.25, 0.0)
	dm.scale_min = 0.6
	dm.scale_max = 1.5
	dm.color_ramp = ramp
	_dust.process_material = dm
	_dust.emitting = false
	_dust.position.y = 0.15
	add_child(_dust)


func update(splashing: bool, dusty: bool, surface: StringName) -> void:
	if _splash == null:
		return
	_splash.emitting = splashing
	_splash.global_position.y = WorldData.WATER_LEVEL + 0.05 if splashing else global_position.y
	_dust.emitting = dusty and (surface == &"dirt" or surface == &"grass" or surface == &"mud")
