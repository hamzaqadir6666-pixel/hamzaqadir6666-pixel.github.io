extends Node
## Game flow: loading -> main menu -> playing <-> paused -> game over -> restart.

enum Flow { LOADING, MENU, PLAYING, PAUSED, GAME_OVER }

const WORLD_SCENE := preload("res://scenes/world/world.tscn")
const HUD_SCENE := preload("res://scenes/ui/hud.tscn")
const MENUS_SCENE := preload("res://scenes/ui/menus.tscn")

var flow: int = Flow.LOADING
var world: GameWorld
var hud: HUD
var menus: Menus
var _death_timer := -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	menus = MENUS_SCENE.instantiate()
	add_child(menus)
	menus.start_requested.connect(start_game)
	menus.resume_requested.connect(resume)
	menus.restart_requested.connect(start_game)
	menus.menu_requested.connect(to_menu)
	menus.quit_requested.connect(func() -> void: get_tree().quit())
	menus.show_loading("Loading...", 0.0)

	world = WORLD_SCENE.instantiate()
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(world)
	world.loading.connect(menus.show_loading)
	await world.build()

	hud = HUD_SCENE.instantiate()
	add_child(hud)
	hud.bind(world.player, world.day_night, world.predators, world.camera)
	hud.visible = false
	world.player.died.connect(_on_player_died)
	world.day_night.day_passed.connect(_on_day_passed)
	if GameState.skip_menu:
		GameState.skip_menu = false
		start_game()
	else:
		to_menu()


func to_menu() -> void:
	get_tree().paused = false
	flow = Flow.MENU
	GameState.in_game = false
	GameState.set_threat(GameState.Threat.CALM)
	_death_timer = -1.0
	hud.visible = false
	world.predators.process_mode = Node.PROCESS_MODE_DISABLED
	world.player.control_enabled = false
	if world.player.is_dead():
		world.player.reset_at(world.player.global_position, 0.0)
	world.camera.input_enabled = false
	world.day_night.paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menus.show_main()
	AudioManager.play_music("menu", 2.0, -9.0)


func start_game() -> void:
	get_tree().paused = false
	GameState.reset_run()
	GameState.in_game = true
	_death_timer = -1.0
	world.begin_run()
	world.camera.input_enabled = true
	hud.visible = true
	menus.hide_all()
	flow = Flow.PLAYING
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	AudioManager.play_music("day", 3.0, -15.0)
	GameState.notify("Survive", "Eat, drink, stay hidden. Find the safe thickets before nightfall.")


func pause() -> void:
	if flow != Flow.PLAYING:
		return
	flow = Flow.PAUSED
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menus.show_pause()


func resume() -> void:
	if flow != Flow.PAUSED:
		return
	flow = Flow.PLAYING
	menus.hide_all()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if flow == Flow.PLAYING:
			pause()
			get_viewport().set_input_as_handled()
		elif flow == Flow.PAUSED and not menus.is_settings_open():
			resume()
			get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and flow == Flow.PLAYING:
		pause()


func _process(delta: float) -> void:
	match flow:
		Flow.MENU:
			world.camera.orbit(delta)
		Flow.PLAYING:
			GameState.time_survived += delta
			if _death_timer >= 0.0:
				_death_timer -= delta
				if _death_timer < 0.0:
					_show_game_over()


func _on_day_passed(day: int) -> void:
	if flow == Flow.PLAYING:
		GameState.days_survived = day - 1
		GameState.notify("Dawn of day %d" % day, "You survived the night.")


func _on_player_died(cause: String) -> void:
	if flow != Flow.PLAYING:
		return
	GameState.finish_run(cause)
	world.player.control_enabled = false
	_death_timer = 2.6
	AudioManager.play_music("gameover", 1.5, -8.0)


func _show_game_over() -> void:
	flow = Flow.GAME_OVER
	hud.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menus.show_game_over(world.day_night.day)
