class_name GrassStreamer
extends Node3D
## Streams dense animated grass around the player. Cells are generated on demand (a couple per frame)
## and their MultiMeshInstances are recycled through a pool when the player moves away.

const CELL := 24.0

var world: WorldData
var lib: FloraLibrary
var target: Node3D
var radius := 78.0
var density := 1.0

var _active: Dictionary = {}                 ## Vector2i -> Array[MultiMeshInstance3D]
var _pool: Array[MultiMeshInstance3D] = []
var _queue: Array[Vector2i] = []
var _grass: Array = []
var _timer := 0.0
var pooled_reuses := 0


func setup(p_world: WorldData, p_lib: FloraLibrary) -> void:
	world = p_world
	lib = p_lib
	_grass = lib.category("grass")
	radius = 78.0 * clampf(float(Settings.get_value("graphics", "vegetation_distance")), 0.6, 1.3)
	density = float(Settings.get_value("graphics", "grass_density"))


func reconfigure() -> void:
	radius = 78.0 * clampf(float(Settings.get_value("graphics", "vegetation_distance")), 0.6, 1.3)
	var d := float(Settings.get_value("graphics", "grass_density"))
	if not is_equal_approx(d, density):
		density = d
		for key: Vector2i in _active.keys():
			_release(key)


func _process(delta: float) -> void:
	if target == null or _grass.is_empty():
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.25
		_refresh()
	var budget := 2
	while budget > 0 and not _queue.is_empty():
		var key: Vector2i = _queue.pop_front()
		if not _active.has(key):
			_build_cell(key)
			budget -= 1


func _refresh() -> void:
	var p := target.global_position
	var c := Vector2i(int(floor(p.x / CELL)), int(floor(p.z / CELL)))
	var reach := int(ceil(radius / CELL))
	var wanted: Dictionary = {}
	var pending: Array[Vector2i] = []
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var key := c + Vector2i(dx, dz)
			var centre := Vector2((key.x + 0.5) * CELL, (key.y + 0.5) * CELL)
			if centre.distance_to(Vector2(p.x, p.z)) > radius + CELL * 0.5:
				continue
			if absf(centre.x) > WorldData.HALF or absf(centre.y) > WorldData.HALF:
				continue
			wanted[key] = true
			if not _active.has(key):
				pending.append(key)
	for key: Vector2i in _active.keys():
		if not wanted.has(key):
			_release(key)
	pending.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - c).length_squared() < (b - c).length_squared())
	_queue = pending


func _release(key: Vector2i) -> void:
	for mmi: MultiMeshInstance3D in _active[key]:
		mmi.visible = false
		_pool.append(mmi)
	_active.erase(key)


func _acquire() -> MultiMeshInstance3D:
	if not _pool.is_empty():
		pooled_reuses += 1
		var m: MultiMeshInstance3D = _pool.pop_back()
		m.visible = true
		return m
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = MultiMesh.new()
	mmi.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(mmi)
	return mmi


func _build_cell(key: Vector2i) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(key.x, key.y, 977))
	var x0 := key.x * CELL
	var z0 := key.y * CELL
	var origin := Vector3(x0 + CELL * 0.5, 0.0, z0 + CELL * 0.5)
	var step := 1.25 / sqrt(maxf(density, 0.2))
	var lists: Array = []
	for i in _grass.size():
		lists.append([])
	var gx := 0.0
	while gx < CELL:
		var gz := 0.0
		while gz < CELL:
			var x := x0 + gx + rng.randf() * step
			var z := z0 + gz + rng.randf() * step
			gz += step
			var h := world.height_at(x, z)
			if h < 0.22:
				continue
			var keep := (1.0 - world.forest_at(x, z) * 0.6) * (1.0 - world.trail_at(x, z) * 1.3)
			keep *= 1.0 - smoothstep(0.2, 0.36, world.slope_at(x, z))
			if rng.randf() > keep:
				continue
			var s := rng.randf_range(0.42, 0.8)
			var n := world.normal_at(x, z)
			var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.2), s))
			var axis := Vector3.UP.cross(n)
			if axis.length() > 0.01:
				b = Basis(axis.normalized(), Vector3.UP.angle_to(n)) * b
			var which := 0 if world.clearing_at(x, z) > 0.4 else rng.randi() % _grass.size()
			lists[which].append(Transform3D(b, Vector3(x, h - 0.04, z) - origin))
		gx += step
	var made: Array = []
	for i in lists.size():
		var arr: Array = lists[i]
		if arr.is_empty():
			continue
		var mmi := _acquire()
		var mm := mmi.multimesh
		mm.instance_count = 0
		mm.mesh = (_grass[i] as FloraLibrary.Entry).mesh
		mm.instance_count = arr.size()
		for j in arr.size():
			mm.set_instance_transform(j, arr[j])
		mmi.position = origin
		mmi.visibility_range_end = radius
		mmi.visibility_range_end_margin = 6.0
		made.append(mmi)
	_active[key] = made


func active_cells() -> int:
	return _active.size()
