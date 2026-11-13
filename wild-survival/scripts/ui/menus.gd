class_name Menus
extends CanvasLayer
## Front-end screens: loading, main menu, pause, game over. Emits intent signals; `main.gd` acts.

signal start_requested
signal resume_requested
signal restart_requested
signal menu_requested
signal quit_requested

const SETTINGS_SCENE := preload("res://scenes/ui/settings_menu.tscn")

var _root: Control
var _loading: Control
var _loading_bar: ProgressBar
var _loading_text: Label
var _main: Control
var _pause: Control
var _over: Control
var _over_title: Label
var _over_cause: Label
var _over_stats: Label
var _help: Control
var _best: Label
var settings: SettingsMenu
var _return_to: Control

const DEATH_TEXT := {
	"Lion": "Run down by a lion",
	"Tiger": "Ambushed by a tiger",
	"Cheetah": "Caught by a cheetah",
	"Hyena": "Brought down by hyenas",
	"starvation": "Starved",
	"thirst": "Died of thirst",
	"drowned": "Drowned, exhausted, in deep water",
}


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.theme = UITheme.get_theme()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	UITheme.fill(_root)
	_build_main()
	_build_pause()
	_build_over()
	_build_loading()
	settings = SETTINGS_SCENE.instantiate()
	_root.add_child(settings)
	UITheme.fill(settings)
	settings.hide()
	settings.closed.connect(_on_settings_closed)


## A full-screen page with a dimmed background. Everything on a page is laid out by containers, so
## it stays where it belongs at any window size or aspect ratio.
func _screen(dim: float) -> Control:
	var c := Control.new()
	_root.add_child(c)
	UITheme.fill(c)
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.03, 0.01, dim)
	c.add_child(bg)
	UITheme.fill(bg)
	c.hide()
	return c


func _centered(parent: Control) -> CenterContainer:
	var center := CenterContainer.new()
	parent.add_child(center)
	UITheme.fill(center)
	return center


func _build_loading() -> void:
	_loading = _screen(1.0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	_centered(_loading).add_child(v)
	var title := UITheme.label("WILD SURVIVAL", 64, UITheme.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	_loading_text = UITheme.label("Loading...", 20, UITheme.MUTED)
	_loading_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_loading_text)
	_loading_bar = UITheme.bar(UITheme.LEAF, Vector2(520, 14))
	_loading_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_loading_bar.value = 0.0
	v.add_child(_loading_bar)


func _build_main() -> void:
	_main = _screen(0.0)
	# soft dark band on the left so the menu stays readable over the live jungle
	var grad := Gradient.new()
	grad.set_color(0, Color(0.01, 0.03, 0.01, 0.85))
	grad.set_color(1, Color(0.01, 0.03, 0.01, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	var tex := TextureRect.new()
	tex.texture = gt
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_SCALE
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_main.add_child(tex)
	tex.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	tex.offset_right = 780.0

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 90)
	margin.add_theme_constant_override("margin_right", 70)
	margin.add_theme_constant_override("margin_top", 40)
	margin.add_theme_constant_override("margin_bottom", 40)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_main.add_child(margin)
	UITheme.fill(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(v)
	v.add_child(UITheme.label("WILD SURVIVAL", 76, UITheme.ACCENT))
	v.add_child(UITheme.label("You are the prey. The jungle is hungry.", 22, UITheme.MUTED))
	var gap := Control.new()
	gap.custom_minimum_size.y = 26
	v.add_child(gap)
	for item: Array in [
			["Start", func() -> void: start_requested.emit()],
			["Settings", func() -> void: _open_settings(_main)],
			["How to Survive", func() -> void: _help.visible = not _help.visible],
			["Quit", func() -> void: quit_requested.emit()]]:
		var b := UITheme.button(item[0], item[1], 320.0)
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		v.add_child(b)
	_best = UITheme.label("", 17, UITheme.MUTED)
	v.add_child(_best)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	_help = PanelContainer.new()
	_help.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_help)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 8)
	_help.add_child(hv)
	hv.add_child(UITheme.label("HOW TO SURVIVE", 26, UITheme.ACCENT))
	var text := UITheme.label("", 17, UITheme.TEXT)
	text.custom_minimum_size.x = 560
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var touch_help := Settings.touch_active()
	text.text = "\n".join([
		"Left stick move  -  RUN and SNEAK toggle  -  JUMP" if touch_help else "WASD move  -  Shift sprint  -  Ctrl sneak  -  Space jump",
		"Hold EAT to eat, graze or drink  -  Drag to look  -  Pinch to zoom" if touch_help else "Hold E to eat, graze or drink  -  Mouse look  -  Wheel zoom  -  Esc pause",
		"",
		"Sprinting drains stamina and is loud. Sneaking and standing in bushes hides you.",
		"Eat berry bushes and leafy plants, or graze slowly on grass. Drink at the river and lakes.",
		"",
		"LION - roars before it charges. Powerful, but tires fast and will not leave its territory.",
		"TIGER - silent. Creeps up while you look away, then pounces. Keep facing it and keep moving.",
		"CHEETAH - fastest animal alive in the open. Turn sharply or dive into dense forest.",
		"HYENA - roams in packs, relentless and erratic. Break line of sight; they cannot swim.",
		"",
		"Gazelle and boar share the jungle. Predators hunt them too - a hunter busy with a kill",
		"is a hunter not looking for you, and a herd bolting is a warning.",
		"",
		"Six safe thickets are too dense for predators. Find them - and the other secrets of the jungle.",
		"Night is darker and far more dangerous.",
	])
	hv.add_child(text)
	_help.hide()


func _build_pause() -> void:
	_pause = _screen(0.55)
	var center := _centered(_pause)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var t := UITheme.label("PAUSED", 40, UITheme.ACCENT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	v.add_child(UITheme.button("Resume", func() -> void: resume_requested.emit(), 320.0))
	v.add_child(UITheme.button("Settings", func() -> void: _open_settings(_pause), 320.0))
	v.add_child(UITheme.button("Restart", func() -> void: restart_requested.emit(), 320.0))
	v.add_child(UITheme.button("Main Menu", func() -> void: menu_requested.emit(), 320.0))
	v.add_child(UITheme.button("Quit Game", func() -> void: quit_requested.emit(), 320.0))


func _build_over() -> void:
	_over = _screen(0.72)
	var center := _centered(_over)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 560
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	_over_title = UITheme.label("THE JUNGLE CLAIMED YOU", 38, UITheme.HEALTH)
	_over_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_over_title)
	_over_cause = UITheme.label("", 22, UITheme.TEXT)
	_over_cause.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_over_cause)
	_over_stats = UITheme.label("", 19, UITheme.MUTED)
	_over_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_over_stats)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	row.add_child(UITheme.button("Try Again", func() -> void: restart_requested.emit(), 240.0))
	row.add_child(UITheme.button("Main Menu", func() -> void: menu_requested.emit(), 240.0))


func _open_settings(from: Control) -> void:
	_return_to = from
	from.hide()
	settings.show()


func _on_settings_closed() -> void:
	if _return_to != null:
		_return_to.show()
		_return_to = null


func hide_all() -> void:
	for c: Control in [_loading, _main, _pause, _over, settings]:
		c.hide()
	_return_to = null


func show_loading(text: String, fraction: float) -> void:
	_loading.show()
	_loading_text.text = text
	_loading_bar.value = fraction * 100.0


func show_main() -> void:
	hide_all()
	_best.text = "Longest survival: %s" % GameState.format_time(GameState.best_time) if GameState.best_time > 0.0 else ""
	_main.show()


func show_pause() -> void:
	hide_all()
	_pause.show()


func show_game_over(day: int) -> void:
	hide_all()
	_over_cause.text = DEATH_TEXT.get(GameState.cause_of_death, "Killed by a %s" % GameState.cause_of_death)
	_over_stats.text = "Survived %s  (day %d)\nDistance travelled  %.1f km\nPredators escaped  %d\nDiscoveries  %d / %d\nBest time  %s" % [
		GameState.format_time(GameState.time_survived), day, GameState.distance_travelled / 1000.0, GameState.escapes,
		GameState.discoveries.size(), GameState.total_discoveries, GameState.format_time(GameState.best_time)]
	_over.show()


func is_settings_open() -> bool:
	return settings.visible


func current_screen() -> String:
	if settings.visible:
		return "settings"
	if _loading.visible:
		return "loading"
	if _main.visible:
		return "main"
	if _pause.visible:
		return "pause"
	if _over.visible:
		return "gameover"
	return ""
