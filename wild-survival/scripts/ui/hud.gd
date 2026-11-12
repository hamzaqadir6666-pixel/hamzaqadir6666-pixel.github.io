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
var _flash := 0.0
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
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 9)
	stats.add_child(grid)
	for item: Array in [["health", "HEALTH", UITheme.HEALTH], ["stamina", "STAMINA", UITheme.STAMINA],
			["hunger", "FOOD", UITheme.FOOD], ["thirst", "WATER", UITheme.WATER]]:
		grid.add_child(UITheme.label(item[1], 15, UITheme.MUTED))
		var b := UITheme.bar(item[2], Vector2(240.0, 17.0))
		grid.add_child(b)
		_bars[item[0]] = b
		_bar_values[item[0]] = 100.0
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
	clock_box.add_child(_clock)
	clock_box.add_child(_discoveries)

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
	top.add_child(_threat)
	top.add_child(_threat_detail)
	top.add_child(_awareness)
	top.add_child(_stealth)

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

	GameState.notification_posted.connect(_on_notification)
	GameState.threat_changed.connect(_on_threat_changed)


func bind(p_player: Player, p_day_night: DayNight, p_predators: PredatorManager, p_camera: ThirdPersonCamera) -> void:
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

	_day.text = "Day %d" % day_night.day
	_clock.text = "%s  -  %s" % [day_night.clock_text(), String(day_night.phase).capitalize()]
	_discoveries.text = "Discoveries %d / %d" % [GameState.discoveries.size(), GameState.total_discoveries]

	var problems: PackedStringArray = []
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
