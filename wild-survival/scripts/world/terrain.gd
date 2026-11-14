class_name Terrain
extends Node3D
## Visual terrain (shared, heightmap-displaced chunk meshes with two LODs), collision height field,
## coarse occluder for occlusion culling and the water surface.

const CHUNK := 64.0
const LOD_SWITCH := 230.0
const TERRAIN_SHADER := preload("res://shaders/terrain.gdshader")
const WATER_SHADER := preload("res://shaders/water.gdshader")
const TERRAIN_LITE_SHADER := preload("res://shaders/terrain_lite.gdshader")
const WATER_LITE_SHADER := preload("res://shaders/water_lite.gdshader")
const TERRAIN_MATERIAL := "res://materials/terrain_material.tres"
const WATER_MATERIAL := "res://materials/water_material.tres"

var material: ShaderMaterial
var water_material: ShaderMaterial
## Phones and the OpenGL renderer get a baked-height terrain and simpler shaders.
var lite := false


func build(world: WorldData) -> void:
	lite = Settings.lite_world()
	_build_material(world)
	if lite:
		_build_chunks_lite(world)
	else:
		_build_chunks()
	_build_collision(world)
	_build_occluder(world)
	_build_water(world)


static func _tex(path: String) -> Texture2D:
	return load(path) if ResourceLoader.exists(path) else null


func _build_material(world: WorldData) -> void:
	if lite:
		material = ShaderMaterial.new()
		material.shader = TERRAIN_LITE_SHADER
		material.set_shader_parameter("world_size", WorldData.SIZE)
		material.set_shader_parameter("control_map", world.build_control_texture())
		var full := build_terrain_material()
		for u: String in ["grass_albedo", "forest_albedo", "dirt_albedo", "rock_albedo", "sand_albedo", "macro_noise"]:
			material.set_shader_parameter(u, full.get_shader_parameter(u))
		return
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


## Water is only built where there is water: the river, the lakes and their banks. (It used to be
## one sheet under the whole map, which the GPU had to shade everywhere.) Each vertex stores the
## depth of the water under it in its colour, for the lite shader.
const WATER_STEP := 4.0
const WATER_CHUNK := 128.0
var water_quads := 0


func _build_water(world: WorldData) -> void:
	if lite:
		water_material = ShaderMaterial.new()
		water_material.shader = WATER_LITE_SHADER
		water_material.set_shader_parameter("normal_a", _tex("res://textures/water/water_normal_1.png"))
		water_material.set_shader_parameter("normal_b", _tex("res://textures/water/water_normal_3.png"))
	elif ResourceLoader.exists(WATER_MATERIAL):
		water_material = (load(WATER_MATERIAL) as ShaderMaterial).duplicate()
	else:
		water_material = build_water_material()
	var pad := int(CHUNK / WATER_STEP)                    # the river runs on a little past the map edge
	var n := int(WorldData.SIZE / WATER_STEP) + 2 * pad   # cells per side
	var origin := -WorldData.HALF - pad * WATER_STEP
	# ground height at every grid corner
	var hs := PackedFloat32Array()
	hs.resize((n + 1) * (n + 1))
	for iz in n + 1:
		for ix in n + 1:
			hs[iz * (n + 1) + ix] = world.height_at(clampf(origin + ix * WATER_STEP, -WorldData.HALF, WorldData.HALF),
				clampf(origin + iz * WATER_STEP, -WorldData.HALF, WorldData.HALF))
	# a cell is wet when any corner is under the surface; one extra ring of cells covers the bank
	var wet := PackedByteArray()
	wet.resize(n * n)
	var top := WorldData.WATER_LEVEL + 0.1
	for iz in n:
		for ix in n:
			var i := iz * (n + 1) + ix
			if hs[i] < top or hs[i + 1] < top or hs[i + n + 1] < top or hs[i + n + 2] < top:
				wet[iz * n + ix] = 1
	var cover := PackedByteArray()
	cover.resize(n * n)
	for iz in n:
		for ix in n:
			if wet[iz * n + ix] == 0:
				continue
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var jx := ix + dx
					var jz := iz + dz
					if jx >= 0 and jz >= 0 and jx < n and jz < n:
						cover[jz * n + jx] = 1
	_water_cover = cover
	_water_n = n
	_water_origin = origin
	var per := int(WATER_CHUNK / WATER_STEP)
	var holder := Node3D.new()
	holder.name = "Water"
	holder.position.y = WorldData.WATER_LEVEL
	add_child(holder)
	water_quads = 0
	for cz in range(0, n, per):
		for cx in range(0, n, per):
			var verts := PackedVector3Array()
			var normals := PackedVector3Array()
			var colors := PackedColorArray()
			for iz in range(cz, mini(cz + per, n)):
				for ix in range(cx, mini(cx + per, n)):
					if cover[iz * n + ix] == 0:
						continue
					for c: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
						var vx := ix + c.x
						var vz := iz + c.y
						verts.append(Vector3(origin + vx * WATER_STEP, 0.0, origin + vz * WATER_STEP))
						normals.append(Vector3.UP)
						var depth := WorldData.WATER_LEVEL - hs[vz * (n + 1) + vx]
						colors.append(Color(clampf(depth / 4.0, 0.0, 1.0), 0.0, 0.0, 1.0))
					water_quads += 1
			if verts.is_empty():
				continue
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_NORMAL] = normals
			arrays[Mesh.ARRAY_COLOR] = colors
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(0, water_material)
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			holder.add_child(mi)


## True if the water surface is drawn at this spot.
func has_water_surface(x: float, z: float) -> bool:
	var ix := int(floor((x - _water_origin) / WATER_STEP))
	var iz := int(floor((z - _water_origin) / WATER_STEP))
	if ix < 0 or iz < 0 or ix >= _water_n or iz >= _water_n:
		return false
	return _water_cover[iz * _water_n + ix] == 1


var _water_cover := PackedByteArray()
var _water_n := 0
var _water_origin := 0.0


# ------------------------------------------------------------- lite terrain (phones, OpenGL)

## Chunk mesh with the real heights and normals in its vertices, so the shader reads no height map.
func _baked_chunk(world: WorldData, center: Vector3, cells: int) -> ArrayMesh:
	var step := CHUNK / cells
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	for iz in cells + 1:
		for ix in cells + 1:
			var lx := -CHUNK * 0.5 + ix * step
			var lz := -CHUNK * 0.5 + iz * step
			var wx := clampf(center.x + lx, -WorldData.HALF, WorldData.HALF)
			var wz := clampf(center.z + lz, -WorldData.HALF, WorldData.HALF)
			verts.append(Vector3(lx, world.height_at(wx, wz), lz))
			normals.append(world.normal_at(wx, wz))
	for iz in cells:
		for ix in cells:
			var i := iz * (cells + 1) + ix
			idx.append_array([i, i + 1, i + cells + 1, i + 1, i + cells + 2, i + cells + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh


func _build_chunks_lite(world: WorldData) -> void:
	var count := int(WorldData.SIZE / CHUNK)
	var holder := Node3D.new()
	holder.name = "Chunks"
	add_child(holder)
	for cz in range(-1, count + 1):
		for cx in range(-1, count + 1):
			var pos := Vector3(-WorldData.HALF + (cx + 0.5) * CHUNK, 0.0, -WorldData.HALF + (cz + 0.5) * CHUNK)
			var outer := cx < 0 or cz < 0 or cx >= count or cz >= count
			if not outer:
				var a := MeshInstance3D.new()
				a.mesh = _baked_chunk(world, pos, 32)   # 2 m, the same grid the collision uses
				a.position = pos
				a.visibility_range_end = LOD_SWITCH
				a.visibility_range_end_margin = 8.0
				a.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				holder.add_child(a)
			var b := MeshInstance3D.new()
			b.mesh = _baked_chunk(world, pos, 8)
			b.position = pos
			if not outer:
				b.visibility_range_begin = LOD_SWITCH
				b.visibility_range_begin_margin = 8.0
			b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			holder.add_child(b)
