class_name WorldData
extends RefCounted
## Procedural description of the jungle: height field, water, trails, clearings, forest density,
## points of interest and fast spatial queries used by gameplay, AI and vegetation placement.

const SIZE := 1024.0          ## world edge length in metres
const HALF := 512.0
const CELL := 2.0             ## height-field resolution
const N := 513                ## samples per side
const WATER_LEVEL := 0.0
const PLAY_LIMIT := 478.0     ## soft boundary for animals

static var instance: WorldData

var seed_value := 20260
var height := PackedFloat32Array()
var wdist := PackedFloat32Array()    ## metres to nearest water edge (negative inside water)
var trail := PackedFloat32Array()
var clearing := PackedFloat32Array()
var forest := PackedFloat32Array()   ## tree density 0..1

var river_points: PackedVector2Array = []
var lakes: Array[Dictionary] = []       ## {name, center: Vector2, radii: Vector2}
var clearings: Array[Dictionary] = []   ## {center: Vector2, radius}
var groves: Array[Dictionary] = []      ## safe thickets {id, name, center: Vector2, radius}
var pois: Array[Dictionary] = []        ## {id, type, name, pos: Vector2, radius}
var trails: Array[PackedVector2Array] = []
var spawn_point := Vector2(70.0, 40.0)

var _cover_cells: Dictionary = {}       ## Vector2i -> Array of Vector4(x, z, radius, strength)
const COVER_CELL := 8.0

var _n_hills := FastNoiseLite.new()
var _n_detail := FastNoiseLite.new()
var _n_ridge := FastNoiseLite.new()
var _n_mask := FastNoiseLite.new()
var _n_forest := FastNoiseLite.new()


func _init(p_seed := 20260) -> void:
	seed_value = p_seed
	instance = self
	_setup_noise()
	_layout()


func _setup_noise() -> void:
	_n_hills.seed = seed_value
	_n_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_hills.frequency = 0.006
	_n_hills.fractal_octaves = 3
	_n_detail.seed = seed_value + 1
	_n_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_n_detail.frequency = 0.035
	_n_detail.fractal_octaves = 2
	_n_ridge.seed = seed_value + 2
	_n_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_n_ridge.frequency = 0.008
	_n_ridge.fractal_octaves = 3
	_n_mask.seed = seed_value + 3
	_n_mask.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_mask.frequency = 0.0028
	_n_mask.fractal_octaves = 1
	_n_forest.seed = seed_value + 4
	_n_forest.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_n_forest.frequency = 0.011
	_n_forest.fractal_octaves = 2


## Fixed (seeded) placement of the river, lakes, clearings, safe groves and trails.
func _layout() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# Main river: north -> south with meanders.
	var z := -HALF - 30.0
	while z <= HALF + 30.0:
		var x := 85.0 * sin(z * 0.0075 + 0.4) + 70.0 * sin(z * 0.0031 + 1.3) - 40.0
		river_points.append(Vector2(x, z))
		z += 24.0
	lakes = [
		{"name": "Mirror Lake", "center": Vector2(-285.0, -170.0), "radii": Vector2(74.0, 52.0)},
		{"name": "Reed Pond", "center": Vector2(265.0, 235.0), "radii": Vector2(46.0, 38.0)},
		{"name": "Moon Pool", "center": Vector2(300.0, -290.0), "radii": Vector2(36.0, 30.0)},
	]
	clearings = [
		{"center": Vector2(70.0, 40.0), "radius": 34.0},
		{"center": Vector2(-150.0, 120.0), "radius": 48.0},
		{"center": Vector2(190.0, -120.0), "radius": 44.0},
		{"center": Vector2(-330.0, 300.0), "radius": 40.0},
		{"center": Vector2(330.0, 60.0), "radius": 38.0},
		{"center": Vector2(-120.0, -340.0), "radius": 46.0},
		{"center": Vector2(130.0, 350.0), "radius": 42.0},
		{"center": Vector2(-380.0, 20.0), "radius": 32.0},
		{"center": Vector2(60.0, -250.0), "radius": 30.0},
	]
	groves = [
		{"id": "grove_fern", "name": "Fern Hollow", "center": Vector2(150.0, 130.0), "radius": 11.0},
		{"id": "grove_banyan", "name": "Banyan Sanctuary", "center": Vector2(-230.0, 40.0), "radius": 12.0},
		{"id": "grove_bamboo", "name": "Bamboo Thicket", "center": Vector2(240.0, -210.0), "radius": 11.0},
		{"id": "grove_mist", "name": "Misty Thicket", "center": Vector2(-200.0, -280.0), "radius": 11.0},
		{"id": "grove_palm", "name": "Palm Refuge", "center": Vector2(-60.0, 300.0), "radius": 12.0},
		{"id": "grove_east", "name": "Sunrise Covert", "center": Vector2(390.0, -80.0), "radius": 11.0},
	]
	pois = [
		{"id": "salt_north", "type": "salt_lick", "name": "Northern Salt Lick", "pos": Vector2(40.0, -150.0), "radius": 5.0},
		{"id": "salt_west", "type": "salt_lick", "name": "Red Clay Lick", "pos": Vector2(-330.0, 180.0), "radius": 5.0},
		{"id": "salt_east", "type": "salt_lick", "name": "Stone Lick", "pos": Vector2(360.0, 170.0), "radius": 5.0},
		{"id": "elder_one", "type": "elder_tree", "name": "The Elder Banyan", "pos": Vector2(-90.0, -90.0), "radius": 9.0},
		{"id": "elder_two", "type": "elder_tree", "name": "The Twin Stranglers", "pos": Vector2(200.0, 330.0), "radius": 9.0},
		{"id": "elder_three", "type": "elder_tree", "name": "Old Father Fig", "pos": Vector2(-390.0, -330.0), "radius": 9.0},
		{"id": "orchard_a", "type": "orchard", "name": "Wild Banana Grove", "pos": Vector2(110.0, -40.0), "radius": 14.0},
		{"id": "orchard_b", "type": "orchard", "name": "Berry Hollow", "pos": Vector2(-260.0, 250.0), "radius": 14.0},
		{"id": "orchard_c", "type": "orchard", "name": "Hidden Berry Glade", "pos": Vector2(310.0, -380.0), "radius": 14.0},
	]
	for lake in lakes:
		pois.append({"id": "lake_" + String(lake["name"]).to_snake_case(), "type": "lake", "name": lake["name"],
			"pos": lake["center"], "radius": maxf(lake["radii"].x, lake["radii"].y) + 6.0})
	# Trails link clearings, groves and water.
	var links := [
		[clearings[0]["center"], groves[0]["center"]], [clearings[0]["center"], pois[6]["pos"]],
		[pois[6]["pos"], clearings[2]["center"]], [clearings[2]["center"], groves[2]["center"]],
		[groves[2]["center"], lakes[2]["center"]], [clearings[0]["center"], clearings[6]["center"]],
		[clearings[6]["center"], lakes[1]["center"]], [groves[0]["center"], clearings[4]["center"]],
		[clearings[1]["center"], groves[1]["center"]], [groves[1]["center"], lakes[0]["center"]],
		[clearings[1]["center"], groves[4]["center"]], [clearings[1]["center"], clearings[3]["center"]],
		[lakes[0]["center"], clearings[5]["center"]], [clearings[5]["center"], groves[3]["center"]],
		[clearings[7]["center"], groves[1]["center"]], [clearings[8]["center"], pois[0]["pos"]],
		[pois[0]["pos"], clearings[0]["center"]], [clearings[4]["center"], groves[5]["center"]],
		[clearings[1]["center"], Vector2(-70.0, 60.0)], [Vector2(-70.0, 60.0), clearings[0]["center"]],
	]
	for link: Array in links:
		var a: Vector2 = link[0]
		var b: Vector2 = link[1]
		var pts := PackedVector2Array()
		var steps := int(a.distance_to(b) / 14.0) + 2
		var side := (b - a).normalized().orthogonal()
		var ph := rng.randf() * TAU
		for i in steps + 1:
			var t := float(i) / steps
			var wob := sin(t * PI) * (sin(t * 7.0 + ph) * 12.0 + sin(t * 17.0 + ph * 2.0) * 4.0)
			pts.append(a.lerp(b, t) + side * wob)
		trails.append(pts)
	GameState.total_discoveries = groves.size() + pois.size()


# ------------------------------------------------------------------ generation

func generate() -> void:
	var total := N * N
	height.resize(total)
	wdist.resize(total)
	trail.resize(total)
	clearing.resize(total)
	forest.resize(total)
	wdist.fill(80.0)
	trail.fill(0.0)
	clearing.fill(0.0)
	_stamp_water()
	_stamp_trails()
	_stamp_clearings()
	_build_heights()


func _idx(ix: int, iz: int) -> int:
	return iz * N + ix


func _stamp_distance(target: PackedFloat32Array, a: Vector2, b: Vector2, half_width: float, reach: float) -> void:
	var minx := int(floor((minf(a.x, b.x) - reach - half_width + HALF) / CELL))
	var maxx := int(ceil((maxf(a.x, b.x) + reach + half_width + HALF) / CELL))
	var minz := int(floor((minf(a.y, b.y) - reach - half_width + HALF) / CELL))
	var maxz := int(ceil((maxf(a.y, b.y) + reach + half_width + HALF) / CELL))
	minx = clampi(minx, 0, N - 1)
	maxx = clampi(maxx, 0, N - 1)
	minz = clampi(minz, 0, N - 1)
	maxz = clampi(maxz, 0, N - 1)
	var ab := b - a
	var len2 := maxf(ab.length_squared(), 0.0001)
	for iz in range(minz, maxz + 1):
		var pz := iz * CELL - HALF
		for ix in range(minx, maxx + 1):
			var px := ix * CELL - HALF
			var t := clampf(((px - a.x) * ab.x + (pz - a.y) * ab.y) / len2, 0.0, 1.0)
			var dx := px - (a.x + ab.x * t)
			var dz := pz - (a.y + ab.y * t)
			var d := sqrt(dx * dx + dz * dz) - half_width
			var i := iz * N + ix
			if d < target[i]:
				target[i] = d


func river_half_width(z: float) -> float:
	return 6.0 + 2.5 * sin(z * 0.021) + 1.5 * sin(z * 0.057 + 2.0)


func _stamp_water() -> void:
	for i in river_points.size() - 1:
		var a := river_points[i]
		var b := river_points[i + 1]
		_stamp_distance(wdist, a, b, river_half_width((a.y + b.y) * 0.5), 60.0)
	for lake in lakes:
		var c: Vector2 = lake["center"]
		var r: Vector2 = lake["radii"]
		var reach := 60.0
		var minx := clampi(int((c.x - r.x - reach + HALF) / CELL), 0, N - 1)
		var maxx := clampi(int((c.x + r.x + reach + HALF) / CELL) + 1, 0, N - 1)
		var minz := clampi(int((c.y - r.y - reach + HALF) / CELL), 0, N - 1)
		var maxz := clampi(int((c.y + r.y + reach + HALF) / CELL) + 1, 0, N - 1)
		var rmin := minf(r.x, r.y)
		for iz in range(minz, maxz + 1):
			var pz := iz * CELL - HALF
			for ix in range(minx, maxx + 1):
				var px := ix * CELL - HALF
				var q := Vector2((px - c.x) / r.x, (pz - c.y) / r.y)
				var wob := 1.0 + 0.12 * sin(atan2(q.y, q.x) * 5.0 + c.x) + 0.07 * sin(atan2(q.y, q.x) * 9.0)
				var d := (q.length() / wob - 1.0) * rmin
				var i := iz * N + ix
				if d < wdist[i]:
					wdist[i] = d


func _stamp_trails() -> void:
	var tmp := PackedFloat32Array()
	tmp.resize(N * N)
	tmp.fill(20.0)
	for pts in trails:
		for i in pts.size() - 1:
			_stamp_distance(tmp, pts[i], pts[i + 1], 0.0, 7.0)
	for i in N * N:
		var d := tmp[i]
		if d < 7.0:
			trail[i] = 1.0 - smoothstep(1.2, 5.5, d)


func _stamp_clearings() -> void:
	for cl in clearings:
		var c: Vector2 = cl["center"]
		var r: float = cl["radius"]
		var minx := clampi(int((c.x - r - 14.0 + HALF) / CELL), 0, N - 1)
		var maxx := clampi(int((c.x + r + 14.0 + HALF) / CELL) + 1, 0, N - 1)
		var minz := clampi(int((c.y - r - 14.0 + HALF) / CELL), 0, N - 1)
		var maxz := clampi(int((c.y + r + 14.0 + HALF) / CELL) + 1, 0, N - 1)
		for iz in range(minz, maxz + 1):
			var pz := iz * CELL - HALF
			for ix in range(minx, maxx + 1):
				var px := ix * CELL - HALF
				var ang := atan2(pz - c.y, px - c.x)
				var rr := r * (1.0 + 0.18 * sin(ang * 3.0 + c.x) + 0.1 * sin(ang * 7.0 + c.y))
				var v := 1.0 - smoothstep(rr - 8.0, rr + 6.0, Vector2(px - c.x, pz - c.y).length())
				var i := iz * N + ix
				if v > clearing[i]:
					clearing[i] = v


## Land height before water carving and site levelling.
func _raw_height(px: float, pz: float, cl: float, tr: float) -> float:
	var hills := _n_hills.get_noise_2d(px, pz) * 5.5 + _n_detail.get_noise_2d(px, pz) * 0.7
	var mask := smoothstep(0.18, 0.55, _n_mask.get_noise_2d(px, pz))
	var ridge := (_n_ridge.get_noise_2d(px, pz) * 0.5 + 0.5)
	var edge_d := HALF - maxf(absf(px), absf(pz))
	var edge := 1.0 - smoothstep(0.0, 95.0, edge_d)
	var base := 4.2 + hills * (1.0 - cl * 0.6)
	base += mask * ridge * ridge * 30.0 * (1.0 - cl)
	base += pow(edge, 1.6) * (46.0 + ridge * 22.0)
	# keep dry land dry: only the mapped river and lakes go below the water table
	base = maxf(base, 1.0 + (base - 1.0) * 0.15)
	# trails are slightly worn into the ground
	return base - tr * 0.25


## Groves and landmarks sit on levelled ground so they are always reachable.
func _stamp_level_sites(weight: PackedFloat32Array, level: PackedFloat32Array) -> void:
	var sites: Array[Vector3] = []
	for g in groves:
		sites.append(Vector3(g["center"].x, g["center"].y, float(g["radius"]) + 6.0))
	for p in pois:
		if p["type"] != "lake":
			sites.append(Vector3(p["pos"].x, p["pos"].y, float(p["radius"]) + 6.0))
	for s in sites:
		var target := minf(_raw_height(s.x, s.y, 0.0, 0.0), 16.0)
		var reach := s.z + 16.0
		var minx := clampi(int((s.x - reach + HALF) / CELL), 0, N - 1)
		var maxx := clampi(int((s.x + reach + HALF) / CELL) + 1, 0, N - 1)
		var minz := clampi(int((s.y - reach + HALF) / CELL), 0, N - 1)
		var maxz := clampi(int((s.y + reach + HALF) / CELL) + 1, 0, N - 1)
		for iz in range(minz, maxz + 1):
			var pz := iz * CELL - HALF
			for ix in range(minx, maxx + 1):
				var px := ix * CELL - HALF
				var w := 1.0 - smoothstep(s.z, reach, Vector2(px - s.x, pz - s.y).length())
				var i := iz * N + ix
				if w > weight[i]:
					weight[i] = w
					level[i] = target


func _build_heights() -> void:
	var lvl_w := PackedFloat32Array()
	var lvl_h := PackedFloat32Array()
	lvl_w.resize(N * N)
	lvl_h.resize(N * N)
	_stamp_level_sites(lvl_w, lvl_h)
	for iz in N:
		var pz := iz * CELL - HALF
		for ix in N:
			var px := ix * CELL - HALF
			var i := iz * N + ix
			var cl := clearing[i]
			var base := _raw_height(px, pz, cl, trail[i])
			if lvl_w[i] > 0.0:
				base = lerpf(base, lvl_h[i], lvl_w[i])
			var wd := wdist[i]
			var h := base
			if wd < 60.0:
				# flatten toward the water over a broad bank, then carve the bed
				var bank := smoothstep(0.0, 46.0, wd)
				h = lerpf(0.55 + maxf(wd, 0.0) * 0.035, base, bank * bank)
				if wd < 3.0:
					var bed := smoothstep(3.0, -5.0, wd)
					var depth := 2.6
					# shallow fords where animals can cross
					var ford := 0.5 + 0.5 * sin(pz * 0.039 + 0.8)
					if ford > 0.86:
						depth = lerpf(2.6, 0.55, smoothstep(0.86, 0.93, ford))
					h = lerpf(h, -depth, bed)
			height[i] = h
			# forest density: dense jungle everywhere except clearings, water, trails, high rock
			var f := 0.62 + _n_forest.get_noise_2d(px, pz) * 0.5
			f *= 1.0 - cl
			f *= smoothstep(1.5, 9.0, wd)
			f *= 1.0 - trail[i] * 0.9
			f *= 1.0 - smoothstep(24.0, 40.0, h)
			forest[i] = clampf(f, 0.0, 1.0)


# ------------------------------------------------------------------ queries

func _sample(field: PackedFloat32Array, x: float, z: float) -> float:
	var fx := clampf((x + HALF) / CELL, 0.0, N - 1.001)
	var fz := clampf((z + HALF) / CELL, 0.0, N - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * N + ix
	var a := lerpf(field[i], field[i + 1], tx)
	var b := lerpf(field[i + N], field[i + N + 1], tx)
	return lerpf(a, b, tz)


func height_at(x: float, z: float) -> float:
	return _sample(height, x, z)


func ground_at(p: Vector3) -> Vector3:
	return Vector3(p.x, height_at(p.x, p.z), p.z)


func normal_at(x: float, z: float) -> Vector3:
	var e := CELL
	return Vector3(height_at(x - e, z) - height_at(x + e, z), 2.0 * e, height_at(x, z - e) - height_at(x, z + e)).normalized()


func slope_at(x: float, z: float) -> float:
	return 1.0 - normal_at(x, z).y


func water_distance(x: float, z: float) -> float:
	return _sample(wdist, x, z)


func water_depth(x: float, z: float) -> float:
	return maxf(WATER_LEVEL - height_at(x, z), 0.0)


func is_water(x: float, z: float) -> bool:
	return height_at(x, z) < WATER_LEVEL - 0.05


func is_deep_water(x: float, z: float) -> bool:
	return height_at(x, z) < WATER_LEVEL - 0.75


func forest_at(x: float, z: float) -> float:
	return _sample(forest, x, z)


func trail_at(x: float, z: float) -> float:
	return _sample(trail, x, z)


func clearing_at(x: float, z: float) -> float:
	return _sample(clearing, x, z)


func in_bounds(x: float, z: float, margin := 0.0) -> bool:
	return absf(x) < PLAY_LIMIT - margin and absf(z) < PLAY_LIMIT - margin


## Footstep / gameplay surface type.
func surface_at(x: float, z: float) -> StringName:
	var h := height_at(x, z)
	if h < WATER_LEVEL - 0.1:
		return &"water"
	if slope_at(x, z) > 0.3 or h > 30.0:
		return &"rock"
	if water_distance(x, z) < 2.5:
		return &"mud"
	if trail_at(x, z) > 0.45:
		return &"dirt"
	return &"grass"


func is_walkable(x: float, z: float, allow_water := false) -> bool:
	if not in_bounds(x, z):
		return false
	if not allow_water and is_deep_water(x, z):
		return false
	return slope_at(x, z) < 0.42


## Random dry, reasonably flat point near a centre (falls back to the centre).
func random_land_point(rng: RandomNumberGenerator, center: Vector2, radius: float, min_radius := 0.0) -> Vector2:
	for attempt in 24:
		var ang := rng.randf() * TAU
		var r := sqrt(rng.randf()) * (radius - min_radius) + min_radius
		var p := center + Vector2(cos(ang), sin(ang)) * r
		if is_walkable(p.x, p.y) and not in_safe_zone(p, 4.0):
			return p
	return center


# ------------------------------------------------------------------ cover / safe zones

func add_cover(x: float, z: float, radius: float, strength: float) -> void:
	var key := Vector2i(int(floor(x / COVER_CELL)), int(floor(z / COVER_CELL)))
	if not _cover_cells.has(key):
		_cover_cells[key] = []
	_cover_cells[key].append(Vector4(x, z, radius, strength))


## Strongest vegetation cover at a position (0 = in the open, 1 = completely hidden).
func cover_at(x: float, z: float) -> float:
	var best := 0.0
	var cx := int(floor(x / COVER_CELL))
	var cz := int(floor(z / COVER_CELL))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var arr: Array = _cover_cells.get(Vector2i(cx + dx, cz + dz), [])
			for c: Vector4 in arr:
				var ddx := x - c.x
				var ddz := z - c.y
				var d2 := ddx * ddx + ddz * ddz
				if d2 < c.z * c.z:
					var k := 1.0 - smoothstep(0.55, 1.0, sqrt(d2) / c.z)
					best = maxf(best, c.w * k)
	return best


## Registered cover spots (x, z, radius, strength) within `radius` of a point.
func cover_spots_near(center: Vector2, radius: float, min_strength := 0.7) -> Array[Vector4]:
	var out: Array[Vector4] = []
	var c0 := Vector2i(int(floor((center.x - radius) / COVER_CELL)), int(floor((center.y - radius) / COVER_CELL)))
	var c1 := Vector2i(int(floor((center.x + radius) / COVER_CELL)), int(floor((center.y + radius) / COVER_CELL)))
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			for c: Vector4 in _cover_cells.get(Vector2i(cx, cz), []):
				if c.w >= min_strength and Vector2(c.x, c.y).distance_to(center) < radius:
					out.append(c)
	return out


func grove_at(p: Vector2, margin := 0.0) -> Dictionary:
	for g in groves:
		if p.distance_to(g["center"]) < float(g["radius"]) + margin:
			return g
	return {}


func in_safe_zone(p: Vector2, margin := 0.0) -> bool:
	return not grove_at(p, margin).is_empty()


# ------------------------------------------------------------------ textures for the terrain shader

func build_height_texture() -> ImageTexture:
	var img := Image.create_from_data(N, N, false, Image.FORMAT_RF, height.to_byte_array())
	return ImageTexture.create_from_image(img)


func build_control_texture() -> ImageTexture:
	var bytes := PackedByteArray()
	bytes.resize(N * N * 4)
	for i in N * N:
		bytes[i * 4] = int(clampf(trail[i], 0.0, 1.0) * 255.0)
		bytes[i * 4 + 1] = int((1.0 - smoothstep(0.0, 7.0, wdist[i])) * 255.0)
		bytes[i * 4 + 2] = int(clampf(forest[i], 0.0, 1.0) * 255.0)
		bytes[i * 4 + 3] = int(clampf(clearing[i], 0.0, 1.0) * 255.0)
	var img := Image.create_from_data(N, N, false, Image.FORMAT_RGBA8, bytes)
	return ImageTexture.create_from_image(img)
