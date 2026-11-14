class_name SettingsMenu
extends Control
## Settings panel (graphics / audio / controls with rebindable keys). Used from the main menu and
## the pause menu.

signal closed

var _rebinding := ""
var _key_buttons: Dictionary = {}
var _controls: Dictionary = {}
var _syncing := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UITheme.get_theme()
	UITheme.fill(self)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	add_child(dim)
	UITheme.fill(dim)
	var center := CenterContainer.new()
	add_child(center)
	UITheme.fill(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(820, 640)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	panel.add_child(v)
	v.add_child(UITheme.label("SETTINGS", 34, UITheme.ACCENT))
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(tabs)
	tabs.add_child(_scrolled(_graphics_tab()))
	tabs.add_child(_scrolled(_audio_tab()))
	tabs.add_child(_controls_tab())
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	v.add_child(row)
	row.add_child(UITheme.button("Back", close, 180.0))
	Settings.changed.connect(_on_changed)


func close() -> void:
	_rebinding = ""
	Settings.save()
	hide()
	closed.emit()


## Tabs scroll rather than push the panel off a small screen.
func _scrolled(g: GridContainer) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = g.name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	g.name = "Grid"
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(g)
	return scroll


func _grid(tab_name: String) -> GridContainer:
	var g := GridContainer.new()
	g.name = tab_name
	g.columns = 2
	g.add_theme_constant_override("h_separation", 28)
	g.add_theme_constant_override("v_separation", 12)
	return g


func _row(g: GridContainer, text: String, control: Control) -> void:
	var l := UITheme.label(text, 19)
	l.custom_minimum_size.x = 300
	g.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_child(control)


func _slider(section: String, key: String, min_v: float, max_v: float, step: float, suffix := "") -> Control:
	var box := HBoxContainer.new()
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = float(Settings.get_value(section, key))
	s.custom_minimum_size = Vector2(260, 28)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var val := UITheme.label("", 17, UITheme.MUTED)
	val.custom_minimum_size.x = 70
	var fmt := func(x: float) -> String:
		if suffix == "%":
			return "%d%%" % int(round(x * 100.0))
		return ("%d" % int(x)) + suffix if step >= 1.0 else "%.2f" % x
	val.text = fmt.call(s.value)
	s.value_changed.connect(func(x: float) -> void:
		val.text = fmt.call(x)
		if not _syncing:
			Settings.set_value(section, key, x, false))
	s.drag_ended.connect(func(_c: bool) -> void: Settings.save())
	box.add_child(s)
	box.add_child(val)
	_controls[section + "/" + key] = s
	return box


func _check(section: String, key: String) -> Control:
	var c := CheckButton.new()
	c.button_pressed = bool(Settings.get_value(section, key))
	c.text = "On" if c.button_pressed else "Off"
	c.toggled.connect(func(on: bool) -> void:
		c.text = "On" if on else "Off"
		if not _syncing:
			AudioManager.click()
			Settings.set_value(section, key, on))
	_controls[section + "/" + key] = c
	return c


func _option(section: String, key: String, items: Array) -> Control:
	var o := OptionButton.new()
	for i in items.size():
		o.add_item(items[i], i)
	o.selected = int(Settings.get_value(section, key))
	o.item_selected.connect(func(i: int) -> void:
		if not _syncing:
			AudioManager.click()
			Settings.set_value(section, key, i))
	_controls[section + "/" + key] = o
	return o


func _graphics_tab() -> Control:
	var g := _grid("Graphics")
	_row(g, "Quality preset", _option("graphics", "preset", ["Low", "Medium", "High", "Ultra"]))
	_row(g, "Window  (F11 toggles)", _option("graphics", "window_mode", ["Window (resizable)", "Maximised window", "Fullscreen"]))
	_row(g, "Auto performance (lower quality if slow)", _check("graphics", "auto_quality"))
	_row(g, "V-Sync", _check("graphics", "vsync"))
	_row(g, "Frame rate limit", _option("graphics", "fps_limit", ["30", "60", "No limit"]))
	_row(g, "Render scale", _slider("graphics", "render_scale", 0.5, 1.0, 0.05, "%"))
	_row(g, "Shadow quality", _option("graphics", "shadows", ["Low", "Medium", "High", "Ultra"]))
	_row(g, "Volumetric fog & sun shafts", _check("graphics", "volumetric_fog"))
	_row(g, "Ambient occlusion", _check("graphics", "ssao"))
	_row(g, "Sun and moon shadows", _check("graphics", "light_shadows"))
	_row(g, "Animal shadows", _check("graphics", "animal_shadows"))
	_row(g, "Glow", _check("graphics", "glow"))
	_row(g, "Vegetation distance", _slider("graphics", "vegetation_distance", 0.5, 1.5, 0.05, "%"))
	_row(g, "Grass density", _slider("graphics", "grass_density", 0.2, 1.6, 0.1, "%"))
	_row(g, "Field of view", _slider("graphics", "fov", 55.0, 95.0, 1.0, " deg"))
	return g


func _audio_tab() -> Control:
	var g := _grid("Audio")
	_row(g, "Master volume", _slider("audio", "master", 0.0, 1.0, 0.01, "%"))
	_row(g, "Music", _slider("audio", "music", 0.0, 1.0, 0.01, "%"))
	_row(g, "Animals & effects", _slider("audio", "sfx", 0.0, 1.0, 0.01, "%"))
	_row(g, "Ambience", _slider("audio", "ambience", 0.0, 1.0, 0.01, "%"))
	return g


func _controls_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "Controls"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var g := _grid("Grid")
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(g)
	_row(g, "Touch controls", _option("controls", "touch_controls", ["Auto (on for phones)", "On", "Off"]))
	_row(g, "Look sensitivity", _slider("controls", "mouse_sensitivity", 0.05, 1.0, 0.01, "%"))
	_row(g, "Invert vertical look", _check("controls", "invert_y"))
	_row(g, "Camera distance", _slider("controls", "camera_distance", 2.5, 10.0, 0.5, " m"))
	for action: String in Settings.ACTIONS:
		var b := Button.new()
		b.text = Settings.binding_text(action)
		b.custom_minimum_size = Vector2(220, 40)
		b.pressed.connect(_start_rebind.bind(action))
		_key_buttons[action] = b
		_row(g, Settings.ACTIONS[action][0], b)
	_row(g, "", UITheme.button("Reset key bindings", Settings.reset_bindings, 220.0))
	return scroll


func _start_rebind(action: String) -> void:
	AudioManager.click()
	_rebinding = action
	(_key_buttons[action] as Button).text = "Press a key..."


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if _rebinding != "":
		if event is InputEventKey and event.pressed and not event.echo:
			get_viewport().set_input_as_handled()
			var action := _rebinding
			_rebinding = ""
			if (event as InputEventKey).physical_keycode != KEY_ESCAPE or action == "pause":
				Settings.rebind(action, event)
			_refresh_keys()
		elif event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index > MOUSE_BUTTON_MIDDLE:
			pass
		return
	if event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close()


func _refresh_keys() -> void:
	for action: String in _key_buttons:
		(_key_buttons[action] as Button).text = Settings.binding_text(action)


func _on_changed(section: String, key: String) -> void:
	if section == "keys":
		_refresh_keys()
	elif section == "graphics" and key == "preset":
		# the preset rewrites several values: reflect them in the widgets
		_syncing = true
		for id: String in _controls:
			var parts := id.split("/")
			if parts[0] != "graphics" or parts[1] == "preset":
				continue
			var c: Control = _controls[id]
			var v: Variant = Settings.get_value("graphics", parts[1])
			if c is HSlider:
				(c as HSlider).value = float(v)
			elif c is CheckButton:
				(c as CheckButton).button_pressed = bool(v)
			elif c is OptionButton:
				(c as OptionButton).selected = int(v)
		_syncing = false
