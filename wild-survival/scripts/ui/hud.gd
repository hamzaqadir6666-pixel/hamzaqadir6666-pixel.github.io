class_name HUD
extends CanvasLayer
## In-game HUD: survival bars, clock, threat / stealth status, interaction prompt, notifications
## and damage feedback.

var player: Player
var day_night: DayNight
var predators: PredatorManager
var camera: ThirdPersonCamera

var _root: Control
var _bars: Dictionary = {}
var _bar_values: Dictionary = {}
var _clock: Label
var _day: Label
var _threat: Label
var _threat_detail: Label
var _stealth: Label
var _awareness: ProgressBar
var _status: Label
var _hint: Label
var _notes: VBoxContainer
var _vignette: ColorRect
var _discoveries: Label
var _stats: PanelContainer
var touch: TouchControls
var _flash := 0.0
var _icons: Dictionary = {}          ## stat -> HudIcon
var _values: Dictionary = {}         ## stat -> Label (number on the bar)
var _ability_icons: Dictionary = {}  ## ability id -> HudIcon
var _ability_row: HBoxContainer
var _speed_label: Label
var _goal_box: PanelContainer
var _goal_title: Label
var _goal_time: Label
var _goal_plants: Label
var _goal_time_bar: ProgressBar
var _weather_icon: HudIcon
var _weather_label: Label
var _wildlife: Label
var _sense: Label
var weather: Weather
var forage: Forage

const STAT_ICONS := [["health", "heart", "Health"], ["stamina", "bolt", "Stamina"], ["hunger", "leaf", "Food"], ["thirst", "drop", "Water"]]
const ABILITY_COLOR := {"swift": Color(0.45, 1.0, 0.5), "night_vision": Color(0.6, 0.8, 1.0), "iron_hide": Color(0.9, 0.5, 0.3),
	"deep_lungs": Color(1.0, 0.82, 0.25), "silent_step": Color(0.85, 0.95, 0.92), "keen_senses": Color(0.95, 0.62, 1.0),
	"high_leap": Color(1.0, 0.6, 0.78), "otter_blood": Color(0.45, 0.9, 1.0)}
var _pulse := 0.0

const THREAT_TEXT := ["", "Something is watching...", "You are being stalked", "HUNTED - RUN!"]
const THREAT_COLOR := [Color(0.7, 0.8, 0.6), Color(0.95, 0.85, 0.4), Color(1.0, 0.6, 0.25), Color(1.0, 0.3, 0.22)]


func _ready() -> void:
	layer = 5
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UITheme.get_theme()
	add_child(_root)

	_vignette = ColorRect.new()
	_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://shaders/vignette.gdshader")
	_vignette.material = sm
	_root.add_child(_vignette)

	# --- survival bars (bottom left)
	var stats := PanelContainer.new()
	stats.add_theme_stylebox_override("panel", UITheme.box(Color(0.05, 0.07, 0.05, 0.62), 8, 1, Color(0.5, 0.45, 0.28, 0.5), 14.0))
	stats.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	stats.position = Vector2(28, -196)
	stats.grow_vertical = Control.GROW_DIRECTION_BEGIN
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(stats)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.add_child(col)
	var colors := {"health": UITheme.HEALTH, "stamina": UITheme.STAMINA, "hunger": UITheme.FOOD, "thirst": UITheme.WATER}
	for item: Array in STAT_ICONS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.tooltip_text = item[2]
		col.add_child(row)
		var icon := HudIcon.make(item[1], colors[item[0]], 30.0)
		row.add_child(icon)
		_icons[item[0]] = icon
		var b := UITheme.bar(colors[item[0]], Vector2(230.0, 18.0))
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(b)
		var num := UITheme.label("100", 13, Color(1, 1, 1, 0.92))
		num.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		num.add_theme_constant_override("outline_size", 4)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		b.add_child(num)
		UITheme.fill(num)
		_values[item[0]] = num
		_bars[item[0]] = b
		_bar_values[item[0]] = 100.0
	# abilities won from rare plants: dim until unlocked
	_ability_row = HBoxContainer.new()
	_ability_row.add_theme_constant_override("separation", 7)
	_ability_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_ability_row)
	for id: String in GameState.ABILITIES:
		var ai := HudIcon.make(id, ABILITY_COLOR[id], 26.0)
		ai.dim = true
		ai.tooltip_text = GameState.ABILITIES[id][0]
		_ability_row.add_child(ai)
		_ability_icons[id] = ai
	_speed_label = UITheme.label("", 14, ABILITY_COLOR["swift"])
	_speed_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_ability_row.add_child(_speed_label)
	_status = UITheme.label("", 18, UITheme.ACCENT)
	_status.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_status.position = Vector2(30, -232)
	_root.add_child(_status)

	# --- clock (top left)
	var clock_box := VBoxContainer.new()
	clock_box.position = Vector2(28, 22)
	clock_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(clock_box)
	_day = UITheme.label("Day 1", 24, UITheme.TEXT)
	_clock = UITheme.label("07:30", 18, UITheme.MUTED)
	_discoveries = UITheme.label("", 15, UITheme.MUTED)
	clock_box.add_child(_day)
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 8)
	crow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weather_icon = HudIcon.make("sun", Color(1.0, 0.86, 0.4), 24.0)
	crow.add_child(_weather_icon)
	crow.add_child(_clock)
	_weather_label = UITheme.label("", 15, UITheme.MUTED)
	crow.add_child(_weather_label)
	clock_box.add_child(crow)
	clock_box.add_child(_discoveries)
	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 6)
	wrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrow.add_child(HudIcon.make("paw", UITheme.MUTED, 18.0))
	_wildlife = UITheme.label("", 15, UITheme.MUTED)
	wrow.add_child(_wildlife)
	clock_box.add_child(wrow)

	# --- level goal (under the clock)
	_goal_box = PanelContainer.new()
	_goal_box.add_theme_stylebox_override("panel", UITheme.box(Color(0.05, 0.07, 0.05, 0.62), 8, 1, Color(0.5, 0.45, 0.28, 0.5), 10.0))
	_goal_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clock_box.add_child(_goal_box)
	var gv := VBoxContainer.new()
	gv.add_theme_constant_override("separation", 4)
	gv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_goal_box.add_child(gv)
	_goal_title = UITheme.label("", 17, UITheme.ACCENT)
	gv.add_child(_goal_title)
	var g1 := HBoxContainer.new()
	g1.add_theme_constant_override("separation", 6)
	g1.add_child(HudIcon.make("clock", UITheme.TEXT, 20.0))
	_goal_time = UITheme.label("", 15, UITheme.TEXT)
	g1.add_child(_goal_time)
	gv.add_child(g1)
	_goal_time_bar = UITheme.bar(UITheme.LEAF, Vector2(210.0, 6.0))
	gv.add_child(_goal_time_bar)
	var g2 := HBoxContainer.new()
	g2.add_theme_constant_override("separation", 6)
	g2.add_child(HudIcon.make("flower", Color(0.6, 0.85, 1.0), 20.0))
	_goal_plants = UITheme.label("", 15, UITheme.TEXT)
	g2.add_child(_goal_plants)
	gv.add_child(g2)

	# --- threat (top centre)
	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.position.y = 24
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(top)
	_threat = UITheme.label("", 28, THREAT_COLOR[0])
	_threat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_threat_detail = UITheme.label("", 17, UITheme.TEXT)
	_threat_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_awareness = UITheme.bar(UITheme.ACCENT, Vector2(260.0, 7.0))
	_awareness.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_stealth = UITheme.label("", 16, UITheme.MUTED)
	_stealth.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sense = UITheme.label("", 16, ABILITY_COLOR["keen_senses"])
	_sense.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_threat)
	top.add_child(_threat_detail)
	top.add_child(_awareness)
	top.add_child(_stealth)
	top.add_child(_sense)

	# --- interaction prompt (bottom centre)
	_hint = UITheme.label("", 22, UITheme.TEXT)
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint.position.y = -150
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root.add_child(_hint)

	# --- notifications (top right)
	_notes = VBoxContainer.new()
	_notes.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_notes.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_notes.position = Vector2(-28, 24)
	_notes.custom_minimum_size.x = 400
	_notes.add_theme_constant_override("separation", 8)
	_notes.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_notes)

	# --- touch controls (phones / tablets); the bars move up out of the left thumb's way
	_stats = stats
	touch = TouchControls.new()
	touch.name = "TouchControls"
	_root.add_child(touch)
	Settings.changed.connect(func(section: String, _key: String) -> void:
		if section == "controls":
			_apply_touch_layout())
	_apply_touch_layout()

	GameState.notification_posted.connect(_on_notification)
	GameState.threat_changed.connect(_on_threat_changed)


## With touch controls the bottom corners belong to the thumbs: survival bars go under the clock
## (top left) and notifications drop below the pause button (top right).
func _apply_touch_layout() -> void:
	if Settings.touch_active():
		_dock(_stats, Control.PRESET_TOP_LEFT, Vector2(300, 22))
		_dock(_status, Control.PRESET_TOP_LEFT, Vector2(302, 222))
		_dock(_notes, Control.PRESET_TOP_RIGHT, Vector2(-28, 140))
		_dock(_hint, Control.PRESET_CENTER_BOTTOM, Vector2(0, -80))
	else:
		_dock(_stats, Control.PRESET_BOTTOM_LEFT, Vector2(28, -28))
		_dock(_status, Control.PRESET_BOTTOM_LEFT, Vector2(30, -236))
		_dock(_notes, Control.PRESET_TOP_RIGHT, Vector2(-28, 24))
		_dock(_hint, Control.PRESET_CENTER_BOTTOM, Vector2(0, -120))


## Snap a control to a corner / edge of the screen at its minimum size, then nudge it inward.
## Works through anchors and offsets, so it is correct whatever the screen size is.
func _dock(c: Control, preset: Control.LayoutPreset, nudge: Vector2) -> void:
	c.set_anchors_and_offsets_preset(preset, Control.PRESET_MODE_MINSIZE)
	c.offset_left += nudge.x
	c.offset_right += nudge.x
	c.offset_top += nudge.y
	c.offset_bottom += nudge.y


func bind(p_player: Player, p_day_night: DayNight, p_predators: PredatorManager, p_camera: ThirdPersonCamera) -> void:
	touch.camera = p_camera
	player = p_player
	day_night = p_day_night
	predators = p_predators
	camera = p_camera
	player.damaged.connect(_on_damaged)
	player.interaction_changed.connect(func(text: String) -> void: _hint.text = text)


func _on_damaged(amount: float, _source: String) -> void:
	_flash = clampf(0.45 + amount / 60.0, 0.0, 1.0)
	if camera != null:
		camera.shake = clampf(amount / 14.0, 1.0, 3.5)


func _on_threat_changed(level: int) -> void:
	if level == GameState.Threat.HUNTED and GameState.in_game:
		AudioManager.play_ui("res://audio/ui/alert_sting.ogg", -4.0)


func _on_notification(title: String, body: String) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UITheme.box(Color(0.06, 0.09, 0.06, 0.8), 8, 1, UITheme.EDGE, 12.0))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_child(UITheme.label(title, 20, UITheme.ACCENT))
	if body != "":
		var b := UITheme.label(body, 16, UITheme.TEXT)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size.x = 370
		v.add_child(b)
	panel.add_child(v)
	_notes.add_child(panel)
	while _notes.get_child_count() > 4:
		_notes.get_child(0).free()
	panel.modulate.a = 0.0
	var tw := panel.create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.3)
	tw.tween_interval(5.5)
	tw.tween_property(panel, "modulate:a", 0.0, 0.8)
	tw.tween_callback(panel.queue_free)


func notification_count() -> int:
	return _notes.get_child_count()


func _process(delta: float) -> void:
	if player == null:
		return
	var k := minf(delta * 8.0, 1.0)
	var values := {
		"health": player.health / player.max_health * 100.0,
		"stamina": player.stamina / player.max_stamina * 100.0,
		"hunger": player.hunger,
		"thirst": player.thirst,
	}
	for key: String in values:
		_bar_values[key] = lerpf(_bar_values[key], values[key], k)
		var bar: ProgressBar = _bars[key]
		bar.value = _bar_values[key]
		# low values pulse
		var low := float(values[key]) < 25.0
		bar.modulate = Color(1, 1, 1, 0.65 + 0.35 * sin(Time.get_ticks_msec() * 0.012)) if low else Color.WHITE
		# the icon beats when the stat is low
		var icon: HudIcon = _icons[key]
		icon.pivot_offset = icon.size * 0.5
		icon.scale = Vector2.ONE * (1.0 + 0.16 * absf(sin(Time.get_ticks_msec() * 0.008))) if low else Vector2.ONE
	(_values["health"] as Label).text = "%d / %d" % [int(ceil(player.health)), int(player.max_health)]
	(_values["stamina"] as Label).text = "%d / %d" % [int(player.stamina), int(player.max_stamina)]
	(_values["hunger"] as Label).text = "%d%%" % int(player.hunger)
	(_values["thirst"] as Label).text = "%d%%" % int(player.thirst)
	for id: String in _ability_icons:
		(_ability_icons[id] as HudIcon).dim = not GameState.has_ability(id)
	_speed_label.text = "%d%%" % int(round(player.speed_mult * 100.0))
	_update_goal()
	if weather != null:
		var wk: String = ["sun", "cloud", "rain", "storm"][weather.state]
		if _weather_icon.kind != wk:
			_weather_icon.kind = wk
			_weather_icon.color = Color(1.0, 0.86, 0.4) if wk == "sun" else Color(0.78, 0.82, 0.88)
			_weather_icon.queue_redraw()
		_weather_label.text = weather.state_name()
	_wildlife.text = "Wildlife seen %d / %d" % [GameState.spotted.size(), GameState.WILDLIFE.size()]

	_day.text = "Day %d" % day_night.day
	_clock.text = "%s  -  %s" % [day_night.clock_text(), String(day_night.phase).capitalize()]
	_discoveries.text = "Discoveries %d / %d" % [GameState.discoveries.size(), GameState.total_discoveries]

	var problems: PackedStringArray = []
	if player.poisoned > 0.0:
		problems.append("Poisoned")
	if player.hunger <= 0.0:
		problems.append("Starving")
	elif player.hunger < 25.0:
		problems.append("Hungry")
	if player.thirst <= 0.0:
		problems.append("Dehydrated")
	elif player.thirst < 25.0:
		problems.append("Thirsty")
	if player.exhausted:
		problems.append("Exhausted")
	if player.swimming:
		problems.append("Swimming")
	if player.health < player.max_health * 0.3:
		problems.append("Badly wounded")
	_status.text = "  |  ".join(problems)

	var level := GameState.threat
	_threat.text = THREAT_TEXT[level]
	_threat.add_theme_color_override("font_color", THREAT_COLOR[level])
	_threat_detail.text = ""
	if level == GameState.Threat.HUNTED and predators.nearest_hunter != null and is_instance_valid(predators.nearest_hunter):
		var h := predators.nearest_hunter
		_threat_detail.text = "%s  -  %d m %s" % [h.display_name, int(h.player_distance), _relative_direction(h.global_position)]
	_awareness.visible = predators.max_awareness > 0.05 and level < GameState.Threat.HUNTED
	_awareness.value = predators.max_awareness * 100.0

	if player.in_grove:
		_stealth.text = "Safe thicket - predators cannot follow"
		_stealth.add_theme_color_override("font_color", UITheme.FOOD)
	elif player.is_hidden():
		_stealth.text = "Hidden in cover"
		_stealth.add_theme_color_override("font_color", UITheme.FOOD)
	elif player.cover > 0.3:
		_stealth.text = "Partly concealed" + ("" if not player.is_sprinting else " - running gives you away")
		_stealth.add_theme_color_override("font_color", UITheme.STAMINA)
	elif player.is_sneaking:
		_stealth.text = "Sneaking"
		_stealth.add_theme_color_override("font_color", UITheme.MUTED)
	else:
		_stealth.text = "Exposed" if level > 0 else ""
		_stealth.add_theme_color_override("font_color", UITheme.MUTED)

	# Keen Senses: always know where the nearest hunter is
	_sense.text = ""
	if GameState.has_ability("keen_senses") and level < GameState.Threat.HUNTED:
		var near := predators.nearest()
		if near != null and is_instance_valid(near) and near.player_distance < 90.0:
			_sense.text = "You sense a %s  -  %d m %s" % [near.display_name.to_lower(), int(near.player_distance), _relative_direction(near.global_position)]

	# damage flash + low health pulse
	_flash = maxf(_flash - delta * 1.2, 0.0)
	_pulse += delta * 3.0
	var low_health := 1.0 - smoothstep(0.1, 0.4, player.health / player.max_health)
	var strength := maxf(_flash, low_health * (0.35 + 0.15 * sin(_pulse)))
	(_vignette.material as ShaderMaterial).set_shader_parameter("strength", strength)


func _relative_direction(pos: Vector3) -> String:
	if camera == null:
		return ""
	var to := pos - player.global_position
	to.y = 0.0
	var local := to.rotated(Vector3.UP, -camera.rotation.y)
	var ang := atan2(local.x, -local.z)
	if absf(ang) < 0.7:
		return "ahead"
	if absf(ang) > 2.4:
		return "behind you"
	return "to your right" if ang > 0.0 else "to your left"


func _update_goal() -> void:
	var info := GameState.level_info()
	if GameState.mode == GameState.Mode.ENDLESS:
		_goal_title.text = "Endless Survival"
		_goal_time.text = "Survived %s" % GameState.format_time(GameState.time_survived)
		_goal_time_bar.visible = false
		_goal_plants.text = "Rare plants eaten  %d" % GameState.plants_found
		return
	_goal_title.text = "Level %d  -  %s" % [GameState.level + 1, info["name"]]
	var goal := GameState.goal_seconds()
	_goal_time_bar.visible = true
	_goal_time_bar.value = clampf(GameState.time_survived / maxf(goal, 1.0), 0.0, 1.0) * 100.0
	var t_done := GameState.time_survived >= goal
	_goal_time.text = "Survive  %s / %s%s" % [GameState.format_time(minf(GameState.time_survived, goal)), GameState.format_time(goal), "  - done" if t_done else ""]
	_goal_time.add_theme_color_override("font_color", UITheme.FOOD if t_done else UITheme.TEXT)
	var need := int(info["plants"])
	var p_done := GameState.plants_found >= need
	_goal_plants.text = "Rare plants  %d / %d%s" % [mini(GameState.plants_found, need), need, "  - done" if p_done else ""]
	_goal_plants.add_theme_color_override("font_color", UITheme.FOOD if p_done else UITheme.TEXT)
