class_name Terrain
extends Node3D
## Visual terrain (shared, heightmap-displaced chunk meshes with two LODs), collision height field,
## coarse occluder for occlusion culling and the water surface.

const CHUNK := 64.0
const LOD_SWITCH := 230.0
const TERRAIN_SHADER := preload("res://shaders/terrain.gdshader")
const WATER_SHADER := preload("res://shaders/water.gdshader")
const TERRAIN_MATERIAL := "res://materials/terrain_material.tres"
const WATER_MATERIAL := "res://materials/water_material.tres"

var material: ShaderMaterial
var water_material: ShaderMaterial


func build(world: WorldData) -> void:
	_build_material(world)
	_build_chunks()
	_build_collision(world)
	_build_occluder(world)
	_build_water()


static func _tex(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null


func _build_material(world: WorldData) -> void:
	if ResourceLoader.exists(TERRAIN_MATERIAL):
		material = (load(TERRAIN_MATERIAL) as ShaderMaterial).duplicate()
		material.set_shader_parameter("height_map", world.build_height_texture())
		material.set_shader_parameter("control_map", world.build_control_texture())
		return
	material = build_terrain_material()
	material.set_shader_parameter("height_map", world.build_height_texture())
	material.set_shader_parameter("control_map", world.build_control_texture())


## Static part of the terrain material (saved to materials/terrain_material.tres by the bake tool).
static func build_terrain_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = TERRAIN_SHADER
	material.set_shader_parameter("world_size", WorldData.SIZE)
	material.set_shader_parameter("cell_size", WorldData.CELL)
	for layer: String in ["grass", "forest_floor", "dirt", "mud", "rock", "sand"]:
		var uniform_name := "forest" if layer == "forest_floor" else layer
		material.set_shader_parameter(uniform_name + "_albedo", _tex("res://textures/terrain/%s_albedo.jpg" % layer))
		material.set_shader_parameter(uniform_name + "_normal", _tex("res://textures/terrain/%s_normal.jpg" % layer))
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	nt.generate_mipmaps = true
	nt.noise = noise
	material.set_shader_parameter("macro_noise", nt)
	return material


static func build_water_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WATER_SHADER
	m.set_shader_parameter("normal_a", _tex("res://textures/water/water_normal_1.png"))
	m.set_shader_parameter("normal_b", _tex("res://textures/water/water_normal_3.png"))
	return m


func _build_chunks() -> void:
	var near := PlaneMesh.new()
	near.size = Vector2(CHUNK, CHUNK)
	near.subdivide_width = 31
	near.subdivide_depth = 31
	near.material = material
	var far := PlaneMesh.new()
	far.size = Vector2(CHUNK, CHUNK)
	far.subdivide_width = 7
	far.subdivide_depth = 7
	far.material = material
	var count := int(WorldData.SIZE / CHUNK)
	var aabb := AABB(Vector3(-CHUNK * 0.5, -6.0, -CHUNK * 0.5), Vector3(CHUNK, 96.0, CHUNK))
	var holder := Node3D.new()
	holder.name = "Chunks"
	add_child(holder)
	# one ring of low-detail chunks outside the map hides the world edge behind the mountains
	for cz in range(-1, count + 1):
		for cx in range(-1, count + 1):
			var pos := Vector3(-WorldData.HALF + (cx + 0.5) * CHUNK, 0.0, -WorldData.HALF + (cz + 0.5) * CHUNK)
			var outer := cx < 0 or cz < 0 or cx >= count or cz >= count
			if not outer:
				var a := MeshInstance3D.new()
				a.mesh = near
				a.position = pos
				a.custom_aabb = aabb
				a.visibility_range_end = LOD_SWITCH
				a.visibility_range_end_margin = 8.0
				a.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				holder.add_child(a)
			var b := MeshInstance3D.new()
			b.mesh = far
			b.position = pos
			b.custom_aabb = aabb
			if not outer:
				b.visibility_range_begin = LOD_SWITCH
				b.visibility_range_begin_margin = 8.0
			b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			holder.add_child(b)


func _build_collision(world: WorldData) -> void:
	var body := StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := HeightMapShape3D.new()
	shape.map_width = WorldData.N
	shape.map_depth = WorldData.N
	shape.map_data = world.height
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3(WorldData.CELL, 1.0, WorldData.CELL)
	body.add_child(cs)
	add_child(body)


## Coarse terrain proxy (sunk slightly) so hills and the mountain ring occlude what is behind them.
func _build_occluder(world: WorldData) -> void:
	var step := 16.0
	var n := int(WorldData.SIZE / step) + 1
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	verts.resize(n * n)
	for iz in n:
		for ix in n:
			var x := -WorldData.HALF + ix * step
			var z := -WorldData.HALF + iz * step
			# use the lowest nearby height so the occluder never pokes above the real surface
			var h := world.height_at(x, z)
			for o: Vector2 in [Vector2(-8, 0), Vector2(8, 0), Vector2(0, -8), Vector2(0, 8)]:
				h = minf(h, world.height_at(x + o.x, z + o.y))
			verts[iz * n + ix] = Vector3(x, h - 1.5, z)
	for iz in n - 1:
		for ix in n - 1:
			var i := iz * n + ix
			idx.append_array([i, i + 1, i + n, i + 1, i + n + 1, i + n])
	var occ := ArrayOccluder3D.new()
	occ.set_arrays(verts, idx)
	var inst := OccluderInstance3D.new()
	inst.name = "TerrainOccluder"
	inst.occluder = occ
	add_child(inst)


func _build_water() -> void:
	if ResourceLoader.exists(WATER_MATERIAL):
		water_material = (load(WATER_MATERIAL) as ShaderMaterial).duplicate()
	else:
		water_material = build_water_material()
	var plane := PlaneMesh.new()
	plane.size = Vector2(WorldData.SIZE + 2.0 * CHUNK, WorldData.SIZE + 2.0 * CHUNK)
	plane.material = water_material
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = plane
	mi.position.y = WorldData.WATER_LEVEL
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
