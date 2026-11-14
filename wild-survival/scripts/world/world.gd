class_name GameWorld
extends Node3D
## Builds and owns the whole jungle: terrain data, terrain mesh + collision, vegetation, grass,
## sky / lighting, ambience, effects, the deer and the predators.

signal loading(text: String, fraction: float)
signal ready_to_play

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const START_TIME := 7.5

var data: WorldData
var flora: FloraLibrary
var terrain: Terrain
var vegetation: Vegetation
var grass: GrassStreamer
var day_night: DayNight
var ambience: Ambience
var effects: WorldEffects
var player: Player
var camera: ThirdPersonCamera
var predators: PredatorManager
var prey: PreyManager
var weather: Weather
var forage: Forage
var birds: Birds
var map_texture: ImageTexture
var _rng := RandomNumberGenerator.new()
var _spot_timer := 0.0
var built := false
var _thread: Thread


func build(seed_value := 20260) -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	loading.emit("Shaping the land...", 0.02)
	await get_tree().process_frame
	data = WorldData.new(seed_value)
	_thread = Thread.new()
	_thread.start(data.generate)
	while _thread.is_alive():
		await get_tree().process_frame
	_thread.wait_to_finish()

	loading.emit("Raising mountains and rivers...", 0.22)
	await get_tree().process_frame
	terrain = Terrain.new()
	terrain.name = "Terrain"
	terrain.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(terrain)
	terrain.build(data)

	day_night = DayNight.new()
	day_night.name = "DayNight"
	day_night.time_of_day = START_TIME
	day_night.paused = true
	add_child(day_night)
	day_night.water_material = terrain.water_material

	loading.emit("Growing the jungle...", 0.3)
	await get_tree().process_frame
	flora = FloraLibrary.new()
	flora.load_all()
	loading.emit("Planting trees...", 0.4)
	await get_tree().process_frame
	vegetation = Vegetation.new()
	vegetation.name = "Vegetation"
	add_child(vegetation)
	vegetation.progress.connect(func(f: float) -> void: loading.emit("Planting trees...", 0.4 + f * 0.45))
	await vegetation.build(data, flora)

	loading.emit("Waking the animals...", 0.88)
	await get_tree().process_frame
	grass = GrassStreamer.new()
	grass.name = "Grass"
	add_child(grass)
	grass.setup(data, flora)

	player = PLAYER_SCENE.instantiate()
	player.world = data
	player.vegetation = vegetation
	var sp := data.spawn_point
	player.position = Vector3(sp.x, data.height_at(sp.x, sp.y) + 0.3, sp.y)
	add_child(player)
	player.control_enabled = false

	camera = ThirdPersonCamera.new()
	camera.name = "CameraRig"
	camera.target = player
	camera.world = data
	add_child(camera)
	camera.snap_to_target()
	player.camera_rig = camera
	grass.target = player

	predators = PredatorManager.new()
	predators.name = "Predators"
	add_child(predators)
	predators.setup(data, player, day_night)
	predators.spawn_default_roster()
	predators.process_mode = Node.PROCESS_MODE_DISABLED

	prey = PreyManager.new()
	prey.name = "Prey"
	add_child(prey)
	prey.setup(data, player, predators)
	prey.spawn_default_roster()
	prey.process_mode = Node.PROCESS_MODE_DISABLED

	ambience = Ambience.new()
	ambience.name = "Ambience"
	add_child(ambience)
	ambience.setup(data, day_night)
	ambience.listener_target = player

	effects = WorldEffects.new()
	effects.name = "Effects"
	add_child(effects)
	effects.setup(data, day_night)
	effects.follow = player

	weather = Weather.new()
	weather.name = "Weather"
	add_child(weather)
	weather.setup(day_night)
	weather.follow = player
	predators.weather = weather

	forage = Forage.new()
	forage.name = "Forage"
	add_child(forage)
	forage.setup(data)
	forage.scatter(data.spawn_point)
	player.forage = forage
	forage.player = player
	loading.emit("Drawing the map...", 0.95)
	await get_tree().process_frame
	map_texture = ImageTexture.create_from_image(WorldMap.build_image(data, 512))

	birds = Birds.new()
	birds.name = "Birds"
	add_child(birds)
	birds.setup(data)
	birds.follow = player
	prey.prey_killed.connect(func(a: Prey, _by: Node3D) -> void: birds.gather_over(a.global_position))
	_rng.randomize()

	Settings.changed.connect(_on_settings_changed)
	loading.emit("Ready", 1.0)
	await get_tree().process_frame
	built = true
	ready_to_play.emit()


func _exit_tree() -> void:
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()


func _on_settings_changed(section: String, _key: String) -> void:
	if section == "graphics" and built:
		vegetation.apply_range_scale(float(Settings.get_value("graphics", "vegetation_distance")))
		grass.reconfigure()
		apply_animal_shadows()


## Low-end PCs: animal shadows are one of the costlier things on screen (skinned meshes drawn again
## for every shadow split), so they can be switched off.
func apply_animal_shadows() -> void:
	var on := bool(Settings.get_value("graphics", "animal_shadows"))
	for p in predators.predators:
		p.rig.set_shadow(on)
	for a in prey.animals:
		a.rig.set_shadow(on)


func _process(delta: float) -> void:
	if not built:
		return
	flora.set_player_position(player.global_position)
	vegetation.regrow(delta)
	day_night.night_vision = move_toward(day_night.night_vision, 1.0 if GameState.has_ability("night_vision") else 0.0, delta * 0.8)
	if GameState.in_game:
		# standing in the rain slowly quenches thirst
		if weather.is_raining() and not player.is_dead():
			player.thirst = minf(player.thirst + weather.rain * 0.12 * delta, 100.0)
		_spot_timer -= delta
		if _spot_timer <= 0.0:
			_spot_timer = 0.5
			_spot_wildlife()


## Note every kind of animal the deer has actually laid eyes on (shown on the HUD), so the player
## can tell that the whole cast really is out there.
func _spot_wildlife() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var here := player.global_position
	for p in predators.predators:
		if not GameState.spotted.has(p.display_name) and p.global_position.distance_to(here) < 60.0 \
				and cam.is_position_in_frustum(p.global_position + Vector3(0, 0.6, 0)):
			_spotted(p.display_name, "Dangerous - keep your distance.")
	for a in prey.animals:
		if not GameState.spotted.has(a.display_name) and a.alive() and a.global_position.distance_to(here) < 50.0 \
				and cam.is_position_in_frustum(a.global_position + Vector3(0, 0.4, 0)):
			_spotted(a.display_name, "Harmless. Hunters prey on it too.")
	for b in birds.birds:
		var bname: String = String(b["kind"]).capitalize()
		if not GameState.spotted.has(bname) and (b["node"] as Node3D).position.distance_to(here) < 120.0 \
				and cam.is_position_in_frustum((b["node"] as Node3D).position):
			_spotted(bname, "Crows gather above a fresh kill." if bname == "Crow" else "It soars over the open clearings.")


func _spotted(species: String, text: String) -> void:
	if GameState.spot(species):
		GameState.notify("Spotted: %s  (%d / %d)" % [species, GameState.spotted.size(), GameState.WILDLIFE.size()], text)


## Start (or restart) a run: fresh deer at a random place, the level's hunters, weather and plants.
func begin_run() -> void:
	var info := GameState.level_info()
	var test := GameState.test_mode
	var sp := data.spawn_point if test else data.random_spawn(_rng)
	data.run_spawn = sp
	player.drain_mult = 1.0 if test else float(info["drain"])
	player.reset_at(Vector3(sp.x, data.height_at(sp.x, sp.y) + 0.3, sp.y), _rng.randf() * TAU if not test else 0.0)
	player.control_enabled = true
	for p in predators.predators.duplicate():
		predators.despawn(p)
	predators._night_pack.clear()
	if test:
		predators.speed_scale = 1.0
		predators.damage_scale = 1.0
		predators.roam_interval = 0.0
		predators.spawn_default_roster()
	else:
		var hardness := float(GameState.level) / float(GameState.LEVELS.size() - 1) if GameState.mode == GameState.Mode.CAMPAIGN else 0.5
		predators.roam_interval = lerpf(75.0, 30.0, hardness)
		predators._roam_timer = 40.0
		predators.speed_scale = float(info["speed"])
		predators.damage_scale = float(info["damage"])
		predators.shuffle_roster()
		predators.spawn_level_roster(info["preds"])
	predators.process_mode = Node.PROCESS_MODE_INHERIT
	prey.clear()
	prey.spawn_default_roster()
	prey.process_mode = Node.PROCESS_MODE_INHERIT
	for site in vegetation.food_sites:
		site["amount"] = site["capacity"]
	forage.scatter(sp, 1234 if test else 0)
	weather.auto = not test
	weather.reset(0.0 if test else float(info["rain"]))
	day_night.day = 1
	day_night.set_time(START_TIME if test else float(info["start"]))
	day_night.paused = false
	day_night.night_vision = 1.0 if GameState.has_ability("night_vision") else 0.0
	camera.snap_to_target()
	apply_animal_shadows()
