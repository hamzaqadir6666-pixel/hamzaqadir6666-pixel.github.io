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
}

const DEFAULTS := {
	"graphics": {
		"preset": 2, # 0 low, 1 medium, 2 high, 3 ultra
		"fullscreen": false,
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
	{"render_scale": 0.7, "shadows": 0, "volumetric_fog": false, "ssao": false, "vegetation_distance": 0.6, "grass_density": 0.4},
	{"render_scale": 0.85, "shadows": 1, "volumetric_fog": false, "ssao": true, "vegetation_distance": 0.8, "grass_density": 0.7},
	{"render_scale": 1.0, "shadows": 2, "volumetric_fog": true, "ssao": true, "vegetation_distance": 1.0, "grass_density": 1.0},
	{"render_scale": 1.0, "shadows": 3, "volumetric_fog": true, "ssao": true, "vegetation_distance": 1.4, "grass_density": 1.4},
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
	_load()
	_register_actions()
	apply_all()


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
	var want_full: bool = g["fullscreen"]
	var is_full := win.mode == Window.MODE_FULLSCREEN or win.mode == Window.MODE_EXCLUSIVE_FULLSCREEN
	if want_full != is_full:
		win.mode = Window.MODE_FULLSCREEN if want_full else Window.MODE_WINDOWED
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if g["vsync"] else DisplayServer.VSYNC_DISABLED)
	var vp := get_viewport()
	vp.scaling_3d_scale = clampf(float(g["render_scale"]), 0.5, 1.0)
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if vp.scaling_3d_scale < 0.99 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.msaa_3d = Viewport.MSAA_2X if int(g["preset"]) >= 2 else Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	var shadow_sizes := [2048, 4096, 4096, 8192]
	RenderingServer.directional_shadow_atlas_set_size(shadow_sizes[clampi(int(g["shadows"]), 0, 3)], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(
		[RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_HIGH][clampi(int(g["shadows"]), 0, 3)])


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
