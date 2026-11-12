class_name WorldEffects
extends Node3D
## Atmosphere that follows the camera: drifting leaves and pollen by day, fireflies by night,
## slanted light-shaft sprites under the canopy and distant bird flocks circling overhead.

const BIRD_SHADER := preload("res://shaders/birds.gdshader")

var day_night: DayNight
var world: WorldData
var follow: Node3D

var _leaves: GPUParticles3D
var _pollen: GPUParticles3D
var _fireflies: GPUParticles3D
var _shafts: GPUParticles3D
var _flocks: Array[Dictionary] = []
var _bird_material: ShaderMaterial


func setup(p_world: WorldData, p_day_night: DayNight) -> void:
	world = p_world
	day_night = p_day_night
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_leaves = _box_emitter("res://textures/particles/leaf_green_a.png", 70, 9.0, 0.22, Color(0.75, 0.85, 0.5, 0.95),
		Vector3(26, 7, 26), Vector3(0.5, -1.1, 0.3), false)
	_leaves.position.y = 9.0
	(_leaves.process_material as ParticleProcessMaterial).angular_velocity_min = -180.0
	(_leaves.process_material as ParticleProcessMaterial).angular_velocity_max = 180.0
	(_leaves.process_material as ParticleProcessMaterial).turbulence_enabled = true
	(_leaves.process_material as ParticleProcessMaterial).turbulence_noise_strength = 0.6
	_pollen = _box_emitter("res://textures/particles/dust_256a.png", 120, 7.0, 0.07, Color(1.0, 0.97, 0.8, 0.5),
		Vector3(18, 5, 18), Vector3(0.15, 0.03, 0.1), true)
	_pollen.position.y = 2.5
	_fireflies = _box_emitter("res://textures/particles/fireflies.png", 90, 6.0, 0.16, Color(0.8, 1.0, 0.35, 1.0),
		Vector3(24, 3, 24), Vector3(0.0, 0.05, 0.0), true)
	_fireflies.position.y = 1.6
	var fm := _fireflies.process_material as ParticleProcessMaterial
	fm.turbulence_enabled = true
	fm.turbulence_noise_strength = 1.4
	fm.turbulence_noise_scale = 3.0
	_shafts = _box_emitter("res://textures/particles/light_ray.png", 14, 10.0, 9.0, Color(1.0, 0.93, 0.7, 0.07),
		Vector3(40, 1, 40), Vector3.ZERO, true)
	_shafts.position.y = 7.0
	_build_flocks()


func _box_emitter(tex: String, amount: int, lifetime: float, size: float, color: Color, extents: Vector3,
		drift: Vector3, additive: bool) -> GPUParticles3D:
	var p := PlayerEffects.make_particles(tex, amount, lifetime, size, color, additive)
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents
	pm.gravity = drift
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.3
	pm.spread = 180.0
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.15, 0.8, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var ramp := GradientTexture1D.new()
	ramp.gradient = g
	pm.color_ramp = ramp
	p.process_material = pm
	p.preprocess = lifetime
	p.visibility_aabb = AABB(-extents - Vector3(4, 14, 4), extents * 2.0 + Vector3(8, 20, 8))
	p.local_coords = false
	add_child(p)
	return p


func _build_flocks() -> void:
	# a tiny low-poly bird silhouette (only ever seen as a distant speck against the sky)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v: Vector3 in [Vector3(0, 0, -0.35), Vector3(-0.9, 0, 0.1), Vector3(0, 0, 0.3),
			Vector3(0, 0, -0.35), Vector3(0, 0, 0.3), Vector3(0.9, 0, 0.1)]:
		st.add_vertex(v)
	var mesh := st.commit()
	_bird_material = ShaderMaterial.new()
	_bird_material.shader = BIRD_SHADER
	mesh.surface_set_material(0, _bird_material)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for f in 4:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = 9 + rng.randi() % 8
		var offsets: Array[Vector3] = []
		for i in mm.instance_count:
			offsets.append(Vector3(rng.randf_range(-9, 9), rng.randf_range(-2.5, 2.5), rng.randf_range(-9, 9)))
			mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), 0, 0))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.custom_aabb = AABB(Vector3(-20, -6, -20), Vector3(40, 12, 40))
		add_child(mmi)
		mmi.top_level = true
		_flocks.append({"node": mmi, "offsets": offsets,
			"center": Vector2(rng.randf_range(-250, 250), rng.randf_range(-250, 250)),
			"radius": rng.randf_range(90.0, 220.0), "height": rng.randf_range(45.0, 75.0),
			"speed": rng.randf_range(0.035, 0.07) * (1.0 if rng.randf() < 0.5 else -1.0), "phase": rng.randf() * TAU})


func _process(delta: float) -> void:
	if follow != null:
		global_position = follow.global_position
	if day_night == null:
		return
	var d := day_night.day_factor
	_leaves.emitting = d > 0.2
	_pollen.emitting = d > 0.35
	_shafts.emitting = d > 0.5 and bool(Settings.get_value("graphics", "volumetric_fog")) == false
	_fireflies.emitting = day_night.night_factor > 0.45
	_bird_material.set_shader_parameter("fade", d)
	for flock in _flocks:
		var node: MultiMeshInstance3D = flock["node"]
		node.visible = d > 0.1
		if not node.visible:
			continue
		flock["phase"] = float(flock["phase"]) + delta * float(flock["speed"])
		var ph: float = flock["phase"]
		var c: Vector2 = flock["center"]
		var r: float = flock["radius"]
		var pos := Vector3(c.x + cos(ph) * r, float(flock["height"]) + sin(ph * 3.0) * 5.0, c.y + sin(ph) * r)
		var heading := Vector3(-sin(ph), 0.0, cos(ph)) * signf(float(flock["speed"]))
		var basis := Basis.looking_at(heading, Vector3.UP)
		node.global_transform = Transform3D(Basis(), pos)
		var mm := node.multimesh
		var offsets: Array = flock["offsets"]
		for i in mm.instance_count:
			mm.set_instance_transform(i, Transform3D(basis, offsets[i]))
