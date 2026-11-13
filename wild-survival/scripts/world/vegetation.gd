class_name Vegetation
extends Node3D
## Places the static jungle: trees, palms, bushes (cover), undergrowth, food plants, rocks, cliffs,
## logs, water plants, safe groves and landmark set-pieces. Everything is rendered with per-chunk
## MultiMeshes (distance culled) and collides through per-chunk static bodies on the physics server.

signal progress(fraction: float)

const CHUNK := 64.0
const RANGE := {"trees": 270.0, "palms": 250.0, "dead": 230.0, "bushes": 135.0, "food": 135.0,
	"plants": 75.0, "water_plants": 90.0, "rocks": 210.0, "cliffs": 320.0, "logs": 120.0}
const NO_SHADOW := ["plants", "water_plants", "grass"]
const TRUNK_RADIUS := {"banyan": 1.3, "baobab": 1.5, "strangler": 0.8, "fig": 0.7, "oak_large": 0.6, "oak_dead": 0.5,
	"teak": 0.42, "tree_tropic": 0.5, "tropic_forest": 0.42, "mangrove": 0.7, "palm": 0.3, "bamboo": 0.5,
	"banana": 0.28, "tree_dead": 0.4, "elm_dead": 0.4}
const CYL_RADII := [0.3, 0.45, 0.6, 0.8, 1.1, 1.5, 2.0, 3.2]

var world: WorldData
var lib: FloraLibrary
var range_scale := 1.0

## Edible plants: {pos: Vector3, amount: float, capacity: float, name: String}
var food_sites: Array[Dictionary] = []
var counts: Dictionary = {}

var _cyl_shapes: Array[CylinderShape3D] = []
var _hull_shapes: Array[ConvexPolygonShape3D] = []
var _bodies: Array[RID] = []
var _instances: Array[MultiMeshInstance3D] = []
var _batch: Dictionary = {}       ## Entry -> Array[Transform3D]  (current chunk)
var _body: RID
var _body_origin: Vector3
var _reserved: Array[Vector3] = [] ## x, z, radius: no generic trees here (groves, landmarks)


func _exit_tree() -> void:
	for b in _bodies:
		PhysicsServer3D.free_rid(b)
	_bodies.clear()


func build(p_world: WorldData, p_lib: FloraLibrary) -> void:
	world = p_world
	lib = p_lib
	range_scale = float(Settings.get_value("graphics", "vegetation_distance"))
	for r: float in CYL_RADII:
		var c := CylinderShape3D.new()
		c.radius = r
		c.height = 7.0
		_cyl_shapes.append(c)
	for g in world.groves:
		_reserved.append(Vector3(g["center"].x, g["center"].y, float(g["radius"]) + 5.0))
	for p in world.pois:
		if p["type"] == "elder_tree":
			_reserved.append(Vector3(p["pos"].x, p["pos"].y, 13.0))
		elif p["type"] == "salt_lick":
			_reserved.append(Vector3(p["pos"].x, p["pos"].y, 8.0))
	_reserved.append(Vector3(world.spawn_point.x, world.spawn_point.y, 7.0))

	var n := int(WorldData.SIZE / CHUNK)
	var done := 0
	for cz in n:
		for cx in n:
			_build_chunk(cx, cz)
			done += 1
		progress.emit(float(done) / float(n * n))
		await get_tree().process_frame
	for i in food_sites.size():
		food_sites[i]["id"] = i


func apply_range_scale(scale_value: float) -> void:
	range_scale = scale_value
	for mmi in _instances:
		mmi.visibility_range_end = float(mmi.get_meta("base_range")) * range_scale


# ------------------------------------------------------------------ chunk assembly

func _begin_chunk(origin: Vector3) -> void:
	_batch.clear()
	_body = PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(_body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_collision_layer(_body, 2)
	PhysicsServer3D.body_set_collision_mask(_body, 0)
	_body_origin = origin
	PhysicsServer3D.body_set_state(_body, PhysicsServer3D.BODY_STATE_TRANSFORM, Transform3D(Basis(), origin))


func _end_chunk(origin: Vector3) -> void:
	if PhysicsServer3D.body_get_shape_count(_body) > 0:
		PhysicsServer3D.body_set_space(_body, get_world_3d().space)
		_bodies.append(_body)
	else:
		PhysicsServer3D.free_rid(_body)
	for e: FloraLibrary.Entry in _batch:
		var xforms: Array = _batch[e]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = e.mesh
		mm.instance_count = xforms.size()
		for i in xforms.size():
			var t: Transform3D = xforms[i]
			t.origin -= origin
			mm.set_instance_transform(i, t)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.position = origin
		var base: float = RANGE.get(e.category, 150.0)
		mmi.set_meta("base_range", base)
		mmi.visibility_range_end = base * range_scale
		mmi.visibility_range_end_margin = 12.0
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if e.category in NO_SHADOW \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(mmi)
		_instances.append(mmi)
		counts[e.category] = int(counts.get(e.category, 0)) + xforms.size()


func _add(e: FloraLibrary.Entry, pos: Vector3, yaw: float, s: float, tilt := Vector3.UP) -> void:
	var b := Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s))
	if tilt != Vector3.UP:
		var axis := Vector3.UP.cross(tilt)
		if axis.length() > 0.001:
			b = Basis(axis.normalized(), Vector3.UP.angle_to(tilt)) * b
	if not _batch.has(e):
		_batch[e] = []
	_batch[e].append(Transform3D(b, pos))


func _add_trunk(pos: Vector3, radius: float) -> void:
	var idx := 0
	for i in CYL_RADII.size():
		if CYL_RADII[i] <= radius * 1.15:
			idx = i
	PhysicsServer3D.body_add_shape(_body, _cyl_shapes[idx].get_rid(),
		Transform3D(Basis(), pos + Vector3(0.0, 2.5, 0.0) - _body_origin))


func _add_hull(e: FloraLibrary.Entry, pos: Vector3, yaw: float, s: float) -> void:
	if e.hull.is_empty():
		return
	var pts := PackedVector3Array()
	pts.resize(e.hull.size())
	for i in e.hull.size():
		pts[i] = e.hull[i] * s
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	_hull_shapes.append(shape)
	PhysicsServer3D.body_add_shape(_body, shape.get_rid(), Transform3D(Basis(Vector3.UP, yaw), pos - _body_origin))


func _trunk_radius(entry_name: String) -> float:
	for key: String in TRUNK_RADIUS:
		if entry_name.begins_with(key):
			return TRUNK_RADIUS[key]
	return 0.45


func _is_reserved(x: float, z: float) -> bool:
	for r in _reserved:
		var dx := x - r.x
		var dz := z - r.y
		if dx * dx + dz * dz < r.z * r.z:
			return true
	return false


func _pick(rng: RandomNumberGenerator, list: Array) -> FloraLibrary.Entry:
	return list[rng.randi() % list.size()]


func _palette(rng: RandomNumberGenerator, pool: Array, count: int) -> Array:
	var out: Array = []
	if pool.is_empty():
		return out
	for i in count:
		out.append(pool[rng.randi() % pool.size()])
	return out


func _build_chunk(cx: int, cz: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector3i(cx, cz, world.seed_value))
	var x0 := -WorldData.HALF + cx * CHUNK
	var z0 := -WorldData.HALF + cz * CHUNK
	var origin := Vector3(x0 + CHUNK * 0.5, 0.0, z0 + CHUNK * 0.5)
	_begin_chunk(origin)

	# --- biome palette (broad-leaf jungle vs palm jungle), a handful of species per chunk
	var biome := sin(origin.x * 0.006 + 1.0) * cos(origin.z * 0.007 - 0.5) + rng.randf_range(-0.3, 0.3)
	var broad: Array = lib.category("trees")
	var palms: Array = lib.category("palms")
	var tree_set: Array = []
	if biome > 0.25:
		tree_set = _palette(rng, palms, 4) + _palette(rng, broad, 2)
	else:
		tree_set = _palette(rng, broad, 4) + _palette(rng, palms, 2)
	var dead_set := _palette(rng, lib.category("dead"), 1)
	var bush_set := _palette(rng, lib.category("bushes"), 3)
	var plant_set := _palette(rng, lib.category("plants"), 2)
	var rock_set := _palette(rng, lib.category("rocks"), 2)
	var reed_set := _palette(rng, lib.find_prefix("reeds") + lib.find_prefix("cattails"), 2)
	var lily_set := lib.find_prefix("water_lillies") + lib.find_prefix("pond_lillies")
	var mangroves := lib.find_prefix("mangrove")
	var food_set: Array = lib.category("food")
	var cliff_set: Array = lib.category("cliffs")
	var log_set: Array = lib.category("logs")

	# --- trees
	var step := 7.5
	var gx := 0.0
	while gx < CHUNK:
		var gz := 0.0
		while gz < CHUNK:
			var x := x0 + gx + rng.randf() * step
			var z := z0 + gz + rng.randf() * step
			gz += step
			var f := world.forest_at(x, z)
			if rng.randf() > f * 0.95:
				continue
			var h := world.height_at(x, z)
			if h < 0.5 or world.slope_at(x, z) > 0.33 or _is_reserved(x, z):
				continue
			var e: FloraLibrary.Entry
			var wd := world.water_distance(x, z)
			if wd < 9.0 and not mangroves.is_empty() and rng.randf() < 0.5:
				e = _pick(rng, mangroves)
			elif not dead_set.is_empty() and rng.randf() < 0.035:
				e = dead_set[0]
			else:
				e = _pick(rng, tree_set)
			var s := rng.randf_range(0.85, 1.35)
			if e.half_width > 6.0:
				s = rng.randf_range(0.8, 1.05)
			var pos := Vector3(x, h - 0.2, z)
			_add(e, pos, rng.randf() * TAU, s)
			_add_trunk(pos, _trunk_radius(e.name) * s)
		gx += step

	# --- bushes (hiding cover)
	step = 6.0
	gx = 0.0
	while gx < CHUNK:
		var gz := 0.0
		while gz < CHUNK:
			var x := x0 + gx + rng.randf() * step
			var z := z0 + gz + rng.randf() * step
			gz += step
			var cl := world.clearing_at(x, z)
			var chance := lerpf(0.22 + world.forest_at(x, z) * 0.5, 0.07, cl)
			if rng.randf() > chance or world.trail_at(x, z) > 0.3:
				continue
			var h := world.height_at(x, z)
			if h < 0.35 or world.slope_at(x, z) > 0.3 or _is_reserved(x, z):
				continue
			var e := _pick(rng, bush_set)
			var s := rng.randf_range(0.8, 1.3)
			_add(e, Vector3(x, h - 0.05, z), rng.randf() * TAU, s)
			world.add_cover(x, z, maxf(e.half_width * s * 0.8, 1.2), 0.92 if e.height * s > 1.9 else 0.75)
		gx += step

	# --- undergrowth
	step = 4.2
	gx = 0.0
	while gx < CHUNK:
		var gz := 0.0
		while gz < CHUNK:
			var x := x0 + gx + rng.randf() * step
			var z := z0 + gz + rng.randf() * step
			gz += step
			if rng.randf() > 0.12 + world.forest_at(x, z) * 0.55 or world.trail_at(x, z) > 0.4:
				continue
			var h := world.height_at(x, z)
			if h < 0.3 or world.slope_at(x, z) > 0.35:
				continue
			_add(_pick(rng, plant_set), Vector3(x, h - 0.03, z), rng.randf() * TAU, rng.randf_range(0.7, 1.4),
				world.normal_at(x, z))
		gx += step

	# --- food plants, rocks, logs (sparse)
	for i in 9:
		var x := x0 + rng.randf() * CHUNK
		var z := z0 + rng.randf() * CHUNK
		var h := world.height_at(x, z)
		var slope := world.slope_at(x, z)
		if h < 0.4 or _is_reserved(x, z):
			continue
		if i < 2:
			if slope < 0.25 and world.trail_at(x, z) < 0.3 and rng.randf() < 0.75:
				_place_food(rng, _pick(rng, food_set), x, z)
		elif i < 6:
			if rng.randf() < 0.3 + slope * 2.0 and world.trail_at(x, z) < 0.5:
				var e := _pick(rng, rock_set)
				var s := rng.randf_range(0.6, 1.5)
				var yaw := rng.randf() * TAU
				var pos := Vector3(x, h - 0.25 * s, z)
				_add(e, pos, yaw, s)
				_add_hull(e, pos, yaw, s)
		elif i < 7:
			if slope > 0.3 and h > 8.0 and not cliff_set.is_empty():
				var e := _pick(rng, cliff_set)
				var yaw := rng.randf() * TAU
				var pos := Vector3(x, h - 1.0, z)
				_add(e, pos, yaw, 1.0)
				_add_hull(e, pos, yaw, 1.0)
		elif slope < 0.2 and not log_set.is_empty() and rng.randf() < 0.55 and world.forest_at(x, z) > 0.15:
			var e := _pick(rng, log_set)
			var s := rng.randf_range(1.0, 1.6)
			var yaw := rng.randf() * TAU
			var pos := Vector3(x, h + 0.02, z)
			_add(e, pos, yaw, s)
			_add_hull(e, pos, yaw, s)

	# --- reeds along the banks, lilies on calm water
	step = 3.4
	gx = 0.0
	while gx < CHUNK:
		var gz := 0.0
		while gz < CHUNK:
			var x := x0 + gx + rng.randf() * step
			var z := z0 + gz + rng.randf() * step
			gz += step
			var wd := world.water_distance(x, z)
			if wd > 3.0:
				continue
			var h := world.height_at(x, z)
			if h > -0.45 and h < 0.3 and rng.randf() < 0.55 and not reed_set.is_empty() and world.trail_at(x, z) < 0.2:
				_add(_pick(rng, reed_set), Vector3(x, h - 0.05, z), rng.randf() * TAU, rng.randf_range(0.8, 1.4))
			elif h < -0.5 and h > -1.6 and rng.randf() < 0.07 and not lily_set.is_empty():
				_add(_pick(rng, lily_set), Vector3(x, WorldData.WATER_LEVEL + 0.02, z), rng.randf() * TAU, rng.randf_range(0.7, 1.2))
		gx += step

	_place_set_pieces(rng, Rect2(x0, z0, CHUNK, CHUNK))
	_end_chunk(origin)


func _place_food(rng: RandomNumberGenerator, e: FloraLibrary.Entry, x: float, z: float) -> void:
	var h := world.height_at(x, z)
	if h < 0.3:
		return
	var s := rng.randf_range(0.75, 1.1)
	_add(e, Vector3(x, h - 0.05, z), rng.randf() * TAU, s)
	food_sites.append({"pos": Vector3(x, h, z), "amount": 100.0, "capacity": 100.0, "name": _food_name(e.name)})


func _food_name(n: String) -> String:
	if n.begins_with("berry"):
		return "berry bush"
	if n.contains("flower"):
		return "flowering shrub"
	return "tender leaves"


## Groves, elder trees, salt licks and orchards whose centre lies inside this chunk.
func _place_set_pieces(rng: RandomNumberGenerator, rect: Rect2) -> void:
	for g in world.groves:
		var c: Vector2 = g["center"]
		if not rect.has_point(c):
			continue
		var r: float = g["radius"]
		var ring: Array = lib.find_prefix("bamboo") + lib.find_prefix("banana") + lib.find_prefix("palm_areca")
		var bushes: Array = lib.find_prefix("tropic_bush_biome") + lib.find_prefix("bush_tempe") + lib.find_prefix("shrub_fanpalm")
		var ferns: Array = lib.find_prefix("ferns") + lib.find_prefix("shrub_tropic_plant")
		var count := int(TAU * r / 2.2)
		for i in count:
			var ang := TAU * i / count + rng.randf_range(-0.06, 0.06)
			# two entrances
			if absf(wrapf(ang - 0.6, -PI, PI)) < 0.22 or absf(wrapf(ang - 0.6 - PI, -PI, PI)) < 0.22:
				continue
			var rr := r + rng.randf_range(0.5, 2.5)
			var p := c + Vector2(cos(ang), sin(ang)) * rr
			var h := world.height_at(p.x, p.y)
			if h < 0.3:
				continue
			if i % 3 == 0 and not ring.is_empty():
				_add(_pick(rng, ring), Vector3(p.x, h - 0.1, p.y), rng.randf() * TAU, rng.randf_range(0.8, 1.1))
			_add(_pick(rng, bushes), Vector3(p.x, h - 0.05, p.y), rng.randf() * TAU, rng.randf_range(1.1, 1.5))
		for i in 26:
			var p := c + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * (r - 1.0)
			var h := world.height_at(p.x, p.y)
			if i < 8:
				_add(_pick(rng, bushes), Vector3(p.x, h - 0.05, p.y), rng.randf() * TAU, rng.randf_range(0.8, 1.1))
			else:
				_add(_pick(rng, ferns), Vector3(p.x, h, p.y), rng.randf() * TAU, rng.randf_range(0.9, 1.5))
		_place_food(rng, _pick(rng, lib.category("food")), c.x + 2.0, c.y - 1.5)
		world.add_cover(c.x, c.y, r, 1.0)
	for p in world.pois:
		var c: Vector2 = p["pos"]
		if not rect.has_point(c):
			continue
		var h := world.height_at(c.x, c.y)
		match p["type"]:
			"elder_tree":
				var big: Array = lib.find_prefix("banyan") if p["id"] == "elder_one" else \
					(lib.find_prefix("strangler") if p["id"] == "elder_two" else lib.find_prefix("fig"))
				if p["id"] == "elder_two":
					for o: float in [-3.5, 3.5]:
						_add(big[0], Vector3(c.x + o, h - 0.6, c.y), rng.randf() * TAU, 1.9)
						_add_trunk(Vector3(c.x + o, h, c.y), 1.5)
				else:
					_add(big[0], Vector3(c.x, h - 0.8, c.y), rng.randf() * TAU, 2.3)
					_add_trunk(Vector3(c.x, h, c.y), 3.0)
				for i in 10:
					var q := c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(5.0, 10.0)
					_add(_pick(rng, lib.category("plants")), Vector3(q.x, world.height_at(q.x, q.y), q.y), rng.randf() * TAU, 1.3)
			"salt_lick":
				var stones: Array = lib.find_prefix("stone_granite_med") + lib.find_prefix("stone_granite_boulder")
				for i in 7:
					var ang := TAU * i / 7.0 + rng.randf_range(-0.2, 0.2)
					var q := c + Vector2.from_angle(ang) * rng.randf_range(3.2, 4.6)
					var e := _pick(rng, stones)
					var s := rng.randf_range(0.5, 0.9)
					var yaw := rng.randf() * TAU
					var pos := Vector3(q.x, world.height_at(q.x, q.y) - 0.15, q.y)
					_add(e, pos, yaw, s)
					_add_hull(e, pos, yaw, s)
			"orchard":
				var foods: Array = lib.category("food")
				var bananas: Array = lib.find_prefix("banana")
				for i in 12:
					var q := c + Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * float(p["radius"])
					if world.height_at(q.x, q.y) > 0.4:
						_place_food(rng, _pick(rng, foods), q.x, q.y)
				for i in 6:
					var q := c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(4.0, float(p["radius"]))
					var hh := world.height_at(q.x, q.y)
					if hh > 0.4 and not bananas.is_empty():
						_add(_pick(rng, bananas), Vector3(q.x, hh - 0.1, q.y), rng.randf() * TAU, rng.randf_range(0.9, 1.2))
						_add_trunk(Vector3(q.x, hh, q.y), 0.3)


# ------------------------------------------------------------------ gameplay queries

func nearest_food(pos: Vector3, max_dist: float) -> Dictionary:
	var best := {}
	var best_d := max_dist * max_dist
	for site in food_sites:
		var d: float = (site["pos"] as Vector3).distance_squared_to(pos)
		if d < best_d and float(site["amount"]) > 5.0:
			best_d = d
			best = site
	return best


func regrow(delta: float) -> void:
	for site in food_sites:
		if float(site["amount"]) < float(site["capacity"]):
			site["amount"] = minf(float(site["amount"]) + delta * 0.35, float(site["capacity"]))
