extends Node
## Persistent user settings: graphics, audio, controls and key bindings.

signal changed(section: String, key: String)

const PATH := "user://settings.cfg"

## Rebindable actions: name -> [label, default physical keycode or mouse button (negative)]
const ACTIONS := {
	"move_forward": ["Move Forward", KEY_W],
	"move_back": ["Move Back", KEY_S],
	"move_left": ["Move Left", KEY_A],
	"move_right": ["Move Right", KEY_D],
	"sprint": ["Sprint", KEY_SHIFT],
	"sneak": ["Sneak / Crouch", KEY_CTRL],
	"jump": ["Jump", KEY_SPACE],
	"interact": ["Graze / Drink", KEY_E],
	"pause": ["Pause", KEY_ESCAPE],
	"map": ["Map", KEY_M],
}

const DEFAULTS := {
	"graphics": {
		"preset": 2, # 0 low, 1 medium, 2 high, 3 ultra
		"fullscreen": false,
		"window_mode": 0, # 0 window, 1 maximised window, 2 fullscreen
		"auto_quality": true,
		"animal_shadows": true,
		"light_shadows": true, # sun and moon shadows; off on Low
		"glow": true,
		"fps_limit": 1, # 0 = 30, 1 = 60, 2 = no limit
		"vsync": true,
		"render_scale": 1.0,
		"shadows": 2,
		"volumetric_fog": true,
		"ssao": true,
		"vegetation_distance": 1.0,
		"grass_density": 1.0,
		"fov": 70.0,
	},
	"audio": {"master": 0.9, "music": 0.55, "sfx": 0.9, "ambience": 0.8},
	"controls": {"mouse_sensitivity": 0.5, "invert_y": false, "camera_distance": 5.5, "touch_controls": 0}, # touch: 0 auto, 1 on, 2 off
	"keys": {},
}

const PRESETS := [
	{"render_scale": 0.5, "shadows": 0, "volumetric_fog": false, "ssao": false, "vegetation_distance": 0.5, "grass_density": 0.2, "animal_shadows": false, "light_shadows": false, "glow": false},
	{"render_scale": 0.8, "shadows": 1, "volumetric_fog": false, "ssao": false, "vegetation_distance": 0.8, "grass_density": 0.65, "animal_shadows": true, "light_shadows": true, "glow": true},
	{"render_scale": 1.0, "shadows": 2, "volumetric_fog": true, "ssao": true, "vegetation_distance": 1.0, "grass_density": 1.0, "animal_shadows": true, "light_shadows": true, "glow": true},
	{"render_scale": 1.0, "shadows": 3, "volumetric_fog": true, "ssao": true, "vegetation_distance": 1.4, "grass_density": 1.4, "animal_shadows": true, "light_shadows": true, "glow": true},
]

var data: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	data = DEFAULTS.duplicate(true)
	if is_mobile() and not FileAccess.file_exists(PATH):
		# first launch on a phone or tablet: start from the lightest graphics preset
		data["graphics"]["preset"] = 0
		for k: String in PRESETS[0]:
			data["graphics"][k] = PRESETS[0][k]
	elif not FileAccess.file_exists(PATH):
		# first launch on a PC: pick a preset the hardware can run (integrated graphics -> Low)
		_set_preset_silently(guess_preset())
	_load()
	# older saves only had the fullscreen switch
	if bool(data["graphics"].get("fullscreen", false)) and int(data["graphics"].get("window_mode", 0)) == 0:
		data["graphics"]["window_mode"] = 2
	_register_actions()
	apply_all()


func _set_preset_silently(index: int) -> void:
	data["graphics"]["preset"] = index
	for k: String in PRESETS[index]:
		data["graphics"][k] = PRESETS[index][k]


## Rough guess at what this PC can run, from the graphics adapter name and the CPU core count.
func guess_preset() -> int:
	var gpu := RenderingServer.get_video_adapter_name().to_lower()
	var cores := OS.get_processor_count()
	for weak: String in ["intel", "uhd", "hd graphics", "iris", "vega", "radeon(tm) graphics", "radeon graphics", "llvmpipe", "swiftshader", "mali", "adreno", "microsoft basic"]:
		if gpu.contains(weak):
			return 0
	if cores <= 2:
		return 0
	if cores <= 4:
		return 1
	return 2


var _fps_time := 0.0
var _fps_frames := 0
var _fps_cooldown := 12.0


## Auto performance: if the game cannot hold a playable frame rate, first lower the 3D render
## resolution step by step, then drop to a lighter preset. Never raises quality by itself.
func _process(delta: float) -> void:
	if not bool(get_value("graphics", "auto_quality")) or DisplayServer.get_name() == "headless" or get_tree().paused \
			or not GameState.in_game:
		_fps_time = 0.0
		_fps_frames = 0
		return
	_fps_cooldown -= delta
	_fps_time += delta
	_fps_frames += 1
	if _fps_time < 4.0:
		return
	var fps := _fps_frames / _fps_time
	_fps_time = 0.0
	_fps_frames = 0
	if _fps_cooldown > 0.0 or fps >= 27.0:
		return
	_fps_cooldown = 10.0
	var scale_now := float(get_value("graphics", "render_scale"))
	var preset := int(get_value("graphics", "preset"))
	if scale_now > 0.72:
		set_value("graphics", "render_scale", maxf(scale_now - 0.15, 0.6))
	elif preset > 0:
		set_value("graphics", "preset", preset - 1)
	elif scale_now > 0.5:
		set_value("graphics", "render_scale", 0.5)
	else:
		return
	GameState.notify("Graphics lowered", "The game was running slowly, so quality was reduced. Change it in Settings > Graphics.")


func toggle_fullscreen() -> void:
	set_value("graphics", "window_mode", 0 if int(get_value("graphics", "window_mode")) == 2 else 2)


func is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")


## True when the on-screen touch controls should be used (Settings > Controls > Touch controls).
## "Auto" turns them on for Android / iOS only, so a touchscreen laptop keeps mouse and keyboard.
func touch_active() -> bool:
	match int(get_value("controls", "touch_controls")):
		1:
			return true
		2:
			return false
	return is_mobile()


func get_value(section: String, key: String) -> Variant:
	return data[section].get(key, DEFAULTS[section].get(key))


func set_value(section: String, key: String, value: Variant, persist := true) -> void:
	data[section][key] = value
	if section == "graphics" and key == "preset":
		for k: String in PRESETS[int(value)]:
			data["graphics"][k] = PRESETS[int(value)][k]
	_apply(section)
	changed.emit(section, key)
	if persist:
		save()


func save() -> void:
	var cfg := ConfigFile.new()
	for section: String in data:
		for key: String in data[section]:
			cfg.set_value(section, key, data[section][key])
	cfg.save(PATH)


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for section in cfg.get_sections():
		if not data.has(section):
			continue
		for key in cfg.get_section_keys(section):
			data[section][key] = cfg.get_value(section, key)


func apply_all() -> void:
	for section: String in ["graphics", "audio", "controls"]:
		_apply(section)


func _apply(section: String) -> void:
	match section:
		"graphics":
			_apply_graphics()
		"controls":
			# forcing touch controls on a desktop lets the mouse stand in for one finger
			Input.emulate_touch_from_mouse = touch_active() and not is_mobile()
		"audio":
			for bus: String in ["master", "music", "sfx", "ambience"]:
				var idx := AudioServer.get_bus_index(bus.capitalize())
				if idx >= 0:
					var v := float(get_value("audio", bus))
					AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))
					AudioServer.set_bus_mute(idx, v <= 0.001)


func _apply_graphics() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var g: Dictionary = data["graphics"]
	var win := get_window()
	# Window: a normal resizable, movable window with title bar and buttons; maximised; or fullscreen.
	if not is_mobile():
		var want := clampi(int(g.get("window_mode", 0)), 0, 2)
		g["fullscreen"] = want == 2
		if want != _window_applied:
			win.borderless = false
			win.unresizable = false
			win.mode = [Window.MODE_WINDOWED, Window.MODE_MAXIMIZED, Window.MODE_FULLSCREEN][want] as Window.Mode
			if want == 0:
				_fit_window(win)
		_window_applied = want
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if g["vsync"] else DisplayServer.VSYNC_DISABLED)
	var vp := get_viewport()
	vp.scaling_3d_scale = clampf(float(g["render_scale"]), 0.5, 1.0)
	# Low: plain bilinear upscale and no anti-aliasing pass at all, the cheapest path there is
	var low := int(g["preset"]) == 0
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if vp.scaling_3d_scale < 0.99 and not low else Viewport.SCALING_3D_MODE_BILINEAR
	vp.msaa_3d = Viewport.MSAA_2X if int(g["preset"]) >= 2 else Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED if low else Viewport.SCREEN_SPACE_AA_FXAA
	# a frame limit keeps a weak laptop from running flat out and overheating
	Engine.max_fps = [30, 60, 0][clampi(int(g.get("fps_limit", 1)), 0, 2)]
	var shadow_sizes := [1024, 2048, 4096, 8192]
	var atlas: int = shadow_sizes[clampi(int(g["shadows"]), 0, 3)] if bool(g.get("light_shadows", true)) else 256
	RenderingServer.directional_shadow_atlas_set_size(atlas, true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
		[RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_HIGH][clampi(int(g["shadows"]), 0, 3)])


var _window_applied := -1


## Size the window to fit comfortably on the screen (never larger than it) and centre it, so the
## title bar and its minimise / maximise / close buttons are always reachable.
func _fit_window(win: Window) -> void:
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	if usable.size.x < 200 or usable.size.y < 200:
		return
	var w := mini(1280, int(usable.size.x * 0.82))
	var h := int(w * 9.0 / 16.0)
	if h > usable.size.y * 0.82:
		h = int(usable.size.y * 0.82)
		w = int(h * 16.0 / 9.0)
	win.size = Vector2i(w, h)
	win.position = usable.position + (usable.size - Vector2i(w, h)) / 2
	win.min_size = Vector2i(640, 360)


# ---------------------------------------------------------------- input map

func _register_actions() -> void:
	for action: String in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		var code: int = int(data["keys"].get(action, ACTIONS[action][1]))
		_set_action_key(action, code)


func _set_action_key(action: String, code: int) -> void:
	InputMap.action_erase_events(action)
	if code < 0:
		var mb := InputEventMouseButton.new()
		mb.button_index = -code as MouseButton
		InputMap.action_add_event(action, mb)
	else:
		var ev := InputEventKey.new()
		ev.physical_keycode = code as Key
		InputMap.action_add_event(action, ev)


func rebind(action: String, event: InputEvent) -> bool:
	var code := 0
	if event is InputEventKey:
		code = (event as InputEventKey).physical_keycode
	elif event is InputEventMouseButton:
		code = -int((event as InputEventMouseButton).button_index)
	if code == 0:
		return false
	# swap if another action already uses the key
	for other: String in ACTIONS:
		if other != action and get_binding(other) == code:
			var prev := get_binding(action)
			data["keys"][other] = prev
			_set_action_key(other, prev)
	data["keys"][action] = code
	_set_action_key(action, code)
	save()
	changed.emit("keys", action)
	return true


func get_binding(action: String) -> int:
	return int(data["keys"].get(action, ACTIONS[action][1]))


func binding_text(action: String) -> String:
	var code := get_binding(action)
	if code < 0:
		return "Mouse %d" % -code
	return OS.get_keycode_string(code as Key)


func reset_bindings() -> void:
	data["keys"] = {}
	_register_actions()
	save()
	changed.emit("keys", "")
