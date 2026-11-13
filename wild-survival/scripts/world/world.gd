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


func _process(delta: float) -> void:
	if not built:
		return
	flora.set_player_position(player.global_position)
	vegetation.regrow(delta)


## Start (or restart) a run: fresh deer, fresh predators, morning light.
func begin_run() -> void:
	var sp := data.spawn_point
	player.reset_at(Vector3(sp.x, data.height_at(sp.x, sp.y) + 0.3, sp.y), 0.0)
	player.control_enabled = true
	for p in predators.predators.duplicate():
		predators.despawn(p)
	predators._night_pack.clear()
	predators.spawn_default_roster()
	predators.process_mode = Node.PROCESS_MODE_INHERIT
	prey.clear()
	prey.spawn_default_roster()
	prey.process_mode = Node.PROCESS_MODE_INHERIT
	for site in vegetation.food_sites:
		site["amount"] = site["capacity"]
	day_night.day = 1
	day_night.set_time(START_TIME)
	day_night.paused = false
	camera.snap_to_target()
