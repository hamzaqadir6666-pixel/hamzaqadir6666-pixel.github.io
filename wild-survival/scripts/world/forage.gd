class_name Forage
extends Node3D
## Rare plants hidden through the jungle. Each kind gives the deer something different: speed,
## night vision, new abilities, healing - or poison. They are scattered afresh for every run, many
## of them tucked into cover, so exploring is always worth it.

## kind -> name, count, colour, shape, where it grows, effect text
const KINDS := {
	"clover": {"name": "Swift Clover", "count": 16, "color": Color(0.35, 1.0, 0.45), "shape": "clover", "where": "open",
		"text": "Your legs feel lighter. You run faster."},
	"moonpetal": {"name": "Moonpetal", "count": 4, "color": Color(0.55, 0.75, 1.0), "shape": "flower", "where": "cover",
		"text": "The dark opens up. You can see at night."},
	"ironbark": {"name": "Ironbark Root", "count": 6, "color": Color(0.85, 0.45, 0.25), "shape": "root", "where": "cover",
		"text": "Your hide toughens. Max health +10."},
	"sunberry": {"name": "Sunberry", "count": 7, "color": Color(1.0, 0.8, 0.2), "shape": "berry", "where": "any",
		"text": "Your chest swells. Max stamina +10."},
	"ghostfern": {"name": "Ghost Fern", "count": 3, "color": Color(0.8, 0.95, 0.9), "shape": "fern", "where": "cover",
		"text": "Your steps fall silent. Hunters hear you far less."},
	"owlcap": {"name": "Owl-eye Mushroom", "count": 3, "color": Color(0.95, 0.6, 1.0), "shape": "mushroom", "where": "cover",
		"text": "Your senses sharpen. You always know where the nearest hunter is."},
	"springlily": {"name": "Spring Lily", "count": 3, "color": Color(1.0, 0.55, 0.75), "shape": "flower", "where": "open",
		"text": "Your hind legs coil like springs. You jump higher."},
	"lotus": {"name": "Lotus Root", "count": 3, "color": Color(0.4, 0.9, 1.0), "shape": "flower", "where": "shore",
		"text": "Water no longer tires you. You swim fast."},
	"herb": {"name": "Healing Herb", "count": 10, "color": Color(0.6, 1.0, 0.7), "shape": "fern", "where": "any",
		"text": "Wounds close. Health restored."},
	"honey": {"name": "Wild Honeycomb", "count": 6, "color": Color(1.0, 0.65, 0.1), "shape": "berry", "where": "cover",
		"text": "Rich and sweet. Hunger gone, stamina full."},
	"toadstool": {"name": "Red Toadstool", "count": 9, "color": Color(1.0, 0.12, 0.1), "shape": "mushroom", "where": "any",
		"text": "Poison! You feel sick and slow."},
}
## Kinds that count toward a level's "rare plants" goal (everything except the poison).
const ABILITY_OF := {"clover": "swift", "moonpetal": "night_vision", "ironbark": "iron_hide", "sunberry": "deep_lungs",
	"ghostfern": "silent_step", "owlcap": "keen_senses", "springlily": "high_leap", "lotus": "otter_blood"}

var world: WorldData
var items: Array[Dictionary] = []   ## {kind, name, pos: Vector3, node: Node3D, eaten: bool}
var _rng := RandomNumberGenerator.new()
var _meshes: Dictionary = {}
var _mats: Dictionary = {}
var _time := 0.0
var player: Player
var _notice := 0.0
var fixed_count := 0            ## the first `fixed_count` items are the same every game
const NOTICE_RANGE := 22.0      ## the deer notices a rare plant from this far; then it shows on the map
## The plants grow in the same places every game (so a map of them stays true); only the few extra
## ones near the deer's random starting point differ.
const FIXED_SEED := 7000


func setup(p_world: WorldData) -> void:
	world = p_world
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


## Remove everything and scatter a fresh set. `near` is where the deer starts: one Moonpetal and a
## couple of clovers always grow within reach of it, so every run can get going.
func scatter(near: Vector2, seed_value := 0) -> void:
	for it in items:
		(it["node"] as Node3D).queue_free()
	items.clear()
	_rng.seed = seed_value if seed_value != 0 else FIXED_SEED
	for kind: String in KINDS:
		var cfg: Dictionary = KINDS[kind]
		for i in int(cfg["count"]):
			var p := _find_spot(String(cfg["where"]), Vector2.ZERO, WorldData.PLAY_LIMIT * 0.86, 0.0)
			_add(kind, p)
	fixed_count = items.size()
	if seed_value == 0:
		_rng.randomize()
	_add("moonpetal", _find_spot("any", near, 75.0, 30.0))
	_add("clover", _find_spot("any", near, 45.0, 14.0))
	_add("clover", _find_spot("any", near, 90.0, 40.0))
	_add("sunberry", _find_spot("any", near, 70.0, 25.0))
	_add("herb", _find_spot("any", near, 60.0, 20.0))


func _find_spot(where: String, center: Vector2, radius: float, min_radius: float) -> Vector2:
	var fallback := center
	for attempt in 80:
		var ang := _rng.randf() * TAU
		var r := sqrt(_rng.randf()) * (radius - min_radius) + min_radius
		var p := center + Vector2(cos(ang), sin(ang)) * r
		if not world.is_walkable(p.x, p.y) or world.water_depth(p.x, p.y) > 0.0 or world.slope_at(p.x, p.y) > 0.45:
			continue
		if world.height_at(p.x, p.y) < WorldData.WATER_LEVEL + 0.25:
			continue
		fallback = p
		var cover := world.cover_at(p.x, p.y)
		match where:
			"cover":
				if cover < 0.3 and attempt < 60:
					continue
			"open":
				if cover > 0.35 and attempt < 60:
					continue
			"shore":
				if world.water_distance(p.x, p.y) > 9.0 and attempt < 70:
					continue
		return p
	return fallback


func _add(kind: String, p: Vector2) -> void:
	var cfg: Dictionary = KINDS[kind]
	var node := _build(kind, cfg)
	var pos := Vector3(p.x, world.height_at(p.x, p.y), p.y)
	node.position = pos
	node.rotation.y = _rng.randf() * TAU
	add_child(node)
	items.append({"kind": kind, "name": cfg["name"], "pos": pos, "node": node, "eaten": false, "seen": false})


func _mat(color: Color, glow: float) -> StandardMaterial3D:
	var key := "%s_%.1f" % [color.to_html(), glow]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.7
	m.emission_enabled = glow > 0.0
	m.emission = color
	m.emission_energy_multiplier = glow
	_mats[key] = m
	return m


func _mesh(id: String) -> Mesh:
	if _meshes.has(id):
		return _meshes[id]
	var m: PrimitiveMesh
	match id:
		"stem":
			var c := CylinderMesh.new()
			c.top_radius = 0.02
			c.bottom_radius = 0.03
			c.height = 1.0
			c.radial_segments = 5
			c.rings = 1
			m = c
		"cap":
			var s := SphereMesh.new()
			s.radius = 0.5
			s.height = 0.5
			s.is_hemisphere = true
			s.radial_segments = 10
			s.rings = 4
			m = s
		"ball":
			var s2 := SphereMesh.new()
			s2.radius = 0.5
			s2.height = 1.0
			s2.radial_segments = 8
			s2.rings = 4
			m = s2
		_:
			var q := PrismMesh.new()      # a leaf / petal
			q.size = Vector3(0.5, 1.0, 0.03)
			m = q
	_meshes[id] = m
	return m


func _part(parent: Node3D, mesh_id: String, mat: Material, pos: Vector3, scl: Vector3, rot := Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh(mesh_id)
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 75.0
	parent.add_child(mi)


## Small glowing plants put together from a handful of shared primitive meshes.
func _build(kind: String, cfg: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = kind
	var col: Color = cfg["color"]
	var glow := _mat(col, 1.6)
	var green := _mat(Color(0.16, 0.42, 0.14), 0.0)
	match String(cfg["shape"]):
		"mushroom":
			for i in 3:
				var o := Vector3(cos(i * 2.1) * 0.16, 0.0, sin(i * 2.1) * 0.16)
				var h := 0.22 + 0.09 * i
				_part(root, "stem", _mat(Color(0.9, 0.88, 0.8), 0.15), o + Vector3(0, h * 0.5, 0), Vector3(2.0, h, 2.0))
				_part(root, "cap", glow, o + Vector3(0, h, 0), Vector3.ONE * (0.2 + 0.05 * i))
		"flower":
			_part(root, "stem", green, Vector3(0, 0.25, 0), Vector3(1.2, 0.5, 1.2))
			for i in 6:
				var a := TAU * i / 6.0
				_part(root, "leaf", glow, Vector3(cos(a) * 0.1, 0.52, sin(a) * 0.1), Vector3(0.3, 0.26, 1.0), Vector3(1.15, -a + PI * 0.5, 0.0))
			_part(root, "ball", _mat(Color(1.0, 0.95, 0.6), 2.0), Vector3(0, 0.54, 0), Vector3.ONE * 0.09)
			for i in 3:
				var a2 := TAU * i / 3.0
				_part(root, "leaf", green, Vector3(cos(a2) * 0.12, 0.1, sin(a2) * 0.12), Vector3(0.4, 0.3, 1.0), Vector3(1.0, -a2 + PI * 0.5, 0.0))
		"berry":
			for i in 5:
				var a3 := TAU * i / 5.0
				_part(root, "leaf", green, Vector3(cos(a3) * 0.14, 0.2, sin(a3) * 0.14), Vector3(0.5, 0.42, 1.0), Vector3(0.5, -a3 + PI * 0.5, 0.0))
				_part(root, "ball", glow, Vector3(cos(a3 + 0.6) * 0.13, 0.26 + 0.05 * (i % 3), sin(a3 + 0.6) * 0.13), Vector3.ONE * 0.1)
		"root":
			for i in 4:
				var a4 := TAU * i / 4.0 + 0.3
				_part(root, "stem", glow, Vector3(cos(a4) * 0.12, 0.08, sin(a4) * 0.12), Vector3(3.0, 0.45, 3.0), Vector3(1.2, -a4, 0.0))
			_part(root, "leaf", green, Vector3(0, 0.3, 0), Vector3(0.4, 0.5, 1.0))
		"fern":
			for i in 7:
				var a5 := TAU * i / 7.0
				_part(root, "leaf", glow if i % 2 == 0 else green, Vector3(cos(a5) * 0.1, 0.22, sin(a5) * 0.1), Vector3(0.22, 0.55, 1.0), Vector3(0.7, -a5 + PI * 0.5, 0.0))
		_:  # clover
			for i in 4:
				var o2 := Vector3(cos(i * 1.7) * 0.14, 0.0, sin(i * 1.7) * 0.14)
				_part(root, "stem", green, o2 + Vector3(0, 0.1, 0), Vector3(0.8, 0.2, 0.8))
				for k in 3:
					var a6 := TAU * k / 3.0
					_part(root, "ball", glow, o2 + Vector3(cos(a6) * 0.05, 0.21, sin(a6) * 0.05), Vector3(0.1, 0.03, 0.1))
	# a soft light so the plant can be spotted through the undergrowth and at night
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 0.7
	light.omni_range = 3.2
	light.position.y = 0.5
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 28.0
	light.distance_fade_length = 8.0
	root.add_child(light)
	return root


func _process(delta: float) -> void:
	# gentle bob so the plants catch the eye
	_time += delta
	_notice -= delta
	if _notice <= 0.0 and player != null:
		_notice = 0.3
		var here := player.global_position
		for it2 in items:
			if not it2["seen"] and (it2["pos"] as Vector3).distance_squared_to(here) < NOTICE_RANGE * NOTICE_RANGE:
				it2["seen"] = true
	var i := 0
	for it in items:
		if not it["eaten"]:
			var n: Node3D = it["node"]
			n.scale = Vector3.ONE * (1.25 + 0.08 * sin(_time * 2.0 + i))
		i += 1


func remaining(kind := "") -> int:
	var n := 0
	for it in items:
		if not it["eaten"] and (kind == "" or it["kind"] == kind):
			n += 1
	return n


func nearest(pos: Vector3, max_dist: float, kind := "") -> Dictionary:
	var best := {}
	var bd := max_dist * max_dist
	for it in items:
		if it["eaten"] or (kind != "" and it["kind"] != kind):
			continue
		var d: float = (it["pos"] as Vector3).distance_squared_to(pos)
		if d < bd:
			bd = d
			best = it
	return best


## The deer eats a plant: apply its gift.
func eat(item: Dictionary, player: Player) -> void:
	if item["eaten"]:
		return
	item["eaten"] = true
	item["seen"] = true
	(item["node"] as Node3D).visible = false
	var kind: String = item["kind"]
	var cfg: Dictionary = KINDS[kind]
	var title := "Eaten: %s" % cfg["name"]
	var body: String = cfg["text"]
	match kind:
		"clover":
			var n := GameState.grant("swift")
			if n > GameState.SWIFT_MAX:
				body = "You are already as fast as a deer can be. Stamina restored."
				player.stamina = player.max_stamina
			else:
				body = "You run faster. Speed %d%%" % int(round(GameState.speed_multiplier() * 100.0))
		"moonpetal":
			GameState.grant("night_vision")
		"ironbark":
			GameState.grant("iron_hide")
			player.max_health += 10.0
			player.heal(25.0)
		"sunberry":
			GameState.grant("deep_lungs")
			player.max_stamina += 10.0
			player.stamina = player.max_stamina
		"ghostfern":
			GameState.grant("silent_step")
		"owlcap":
			GameState.grant("keen_senses")
		"springlily":
			GameState.grant("high_leap")
		"lotus":
			GameState.grant("otter_blood")
		"herb":
			player.heal(45.0)
			player.poisoned = 0.0
		"honey":
			player.hunger = 100.0
			player.stamina = player.max_stamina
			player.exhausted = false
		"toadstool":
			player.poisoned = 12.0
			player.hunger = maxf(player.hunger - 10.0, 0.0)
			title = "Poisoned: %s" % cfg["name"]
	if kind != "toadstool":
		player.hunger = minf(player.hunger + 12.0, 100.0)
		GameState.plant_found()
		AudioManager.play_ui("res://audio/ui/discover.ogg", -5.0)
	player.apply_abilities(false)
	GameState.notify(title, body)
