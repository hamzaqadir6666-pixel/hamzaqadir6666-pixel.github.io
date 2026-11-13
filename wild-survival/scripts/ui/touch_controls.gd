class_name TouchControls
extends Control
## On-screen controls for phones and tablets: a movement stick under the left thumb, action
## buttons under the right thumb, drag anywhere else to look around, pinch to zoom.
##
## Everything is driven by raw InputEventScreenTouch / InputEventScreenDrag events, tracked per
## finger, so several fingers work at the same time (move + look + a button). The widgets feed
## the same input actions the keyboard uses, so the rest of the game does not know the difference.

const STICK_RADIUS := 135.0
const STICK_KNOB := 58.0
const STICK_DEADZONE := 0.18
const LOOK_SPEED := 1.7           # touch drags are shorter than mouse moves, so they turn further
const BUTTON_ALPHA := 0.42

var camera: ThirdPersonCamera

## id -> {pos: Vector2, radius: float, label: String, action: String, mode: "hold" | "toggle" | "tap"}
var _buttons: Dictionary = {}
var _button_finger: Dictionary = {}     # button id -> finger index holding it
var _toggled: Dictionary = {}           # button id -> bool
var _stick_finger := -1
var _stick_base := Vector2.ZERO
var _stick_vec := Vector2.ZERO
var _look_fingers: Dictionary = {}      # finger index -> last position
var _pinch_dist := 0.0
var _font: Font
var _tap_release: Array[String] = []    # actions pressed for a single frame


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_font = ThemeDB.fallback_font
	Settings.changed.connect(_on_settings_changed)
	get_viewport().size_changed.connect(_layout)
	visibility_changed.connect(_on_visibility_changed)
	_layout()
	_refresh_enabled()


func _on_settings_changed(section: String, _key: String) -> void:
	if section == "controls":
		_refresh_enabled()


func _refresh_enabled() -> void:
	visible = Settings.touch_active()
	if not visible:
		release_all()


func _on_visibility_changed() -> void:
	if not is_visible_in_tree():
		release_all()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_EXIT_TREE:
		release_all()


func is_active() -> bool:
	return is_visible_in_tree() and Settings.touch_active()


## Button positions follow the screen size (wide phones get the same thumb reach).
func _layout() -> void:
	var s := get_viewport_rect().size
	_buttons = {
		"jump": {"pos": Vector2(s.x - 190.0, s.y - 185.0), "radius": 92.0, "label": "JUMP", "action": "jump", "mode": "tap"},
		"sprint": {"pos": Vector2(s.x - 405.0, s.y - 150.0), "radius": 76.0, "label": "RUN", "action": "sprint", "mode": "toggle"},
		"interact": {"pos": Vector2(s.x - 180.0, s.y - 400.0), "radius": 76.0, "label": "EAT", "action": "interact", "mode": "hold"},
		"sneak": {"pos": Vector2(s.x - 385.0, s.y - 335.0), "radius": 66.0, "label": "SNEAK", "action": "sneak", "mode": "toggle"},
		"pause": {"pos": Vector2(s.x - 78.0, 78.0), "radius": 46.0, "label": "II", "action": "pause", "mode": "tap"},
	}
	_stick_base = _stick_home()
	queue_redraw()


func _stick_home() -> Vector2:
	var s := get_viewport_rect().size
	return Vector2(250.0, s.y - 240.0)


func _stick_zone(p: Vector2) -> bool:
	var s := get_viewport_rect().size
	return p.x < s.x * 0.42 and p.y > s.y * 0.32


func _button_at(p: Vector2) -> String:
	for id: String in _buttons:
		var b: Dictionary = _buttons[id]
		if p.distance_to(b["pos"]) <= float(b["radius"]) * 1.15:
			return id
	return ""


func _input(event: InputEvent) -> void:
	if not is_active():
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_finger_down(t.index, t.position)
		else:
			_finger_up(t.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_finger_move(d.index, d.position, d.relative)


func _finger_down(index: int, p: Vector2) -> void:
	var id := _button_at(p)
	if id != "":
		_press_button(id, index)
	elif _stick_finger < 0 and _stick_zone(p):
		_stick_finger = index
		# the stick appears under the thumb, kept fully on screen
		var s := get_viewport_rect().size
		_stick_base = Vector2(clampf(p.x, STICK_RADIUS + 20.0, s.x * 0.42), clampf(p.y, STICK_RADIUS + 20.0, s.y - STICK_RADIUS - 20.0))
		_set_stick(p)
	else:
		_look_fingers[index] = p
		_pinch_dist = _current_pinch()
	queue_redraw()


func _finger_move(index: int, p: Vector2, relative: Vector2) -> void:
	if index == _stick_finger:
		_set_stick(p)
		queue_redraw()
	elif _look_fingers.has(index):
		_look_fingers[index] = p
		if _look_fingers.size() >= 2:
			var dist := _current_pinch()
			if _pinch_dist > 1.0 and camera != null:
				camera.zoom_by((_pinch_dist - dist) * 0.012)
			_pinch_dist = dist
		elif camera != null:
			camera.add_look(relative * LOOK_SPEED)


func _finger_up(index: int) -> void:
	if index == _stick_finger:
		_stick_finger = -1
		_stick_base = _stick_home()
		_apply_stick(Vector2.ZERO)
		# letting go of the stick also ends a run
		if _toggled.get("sprint", false):
			_set_toggle("sprint", false)
	elif _look_fingers.has(index):
		_look_fingers.erase(index)
		_pinch_dist = _current_pinch()
	else:
		for id: String in _button_finger.keys():
			if _button_finger[id] == index:
				_button_finger.erase(id)
				if _buttons[id]["mode"] == "hold":
					Input.action_release(_buttons[id]["action"])
	queue_redraw()


func _current_pinch() -> float:
	if _look_fingers.size() < 2:
		return 0.0
	var pts := _look_fingers.values()
	return (pts[0] as Vector2).distance_to(pts[1])


func _press_button(id: String, index: int) -> void:
	var b: Dictionary = _buttons[id]
	_button_finger[id] = index
	match b["mode"]:
		"hold":
			Input.action_press(b["action"])
		"toggle":
			_set_toggle(id, not _toggled.get(id, false))
		"tap":
			if id == "pause":
				_send_action("pause")
			else:
				Input.action_press(b["action"])
				_tap_release.append(b["action"])


func _set_toggle(id: String, on: bool) -> void:
	_toggled[id] = on
	var action: String = _buttons[id]["action"]
	if on:
		Input.action_press(action)
		# running and sneaking exclude each other
		var other := "sneak" if id == "sprint" else "sprint"
		if _toggled.get(other, false):
			_set_toggle(other, false)
	else:
		Input.action_release(action)
	queue_redraw()


func _send_action(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)


func _set_stick(p: Vector2) -> void:
	var v := (p - _stick_base) / STICK_RADIUS
	if v.length() > 1.0:
		v = v.normalized()
	_apply_stick(v)


func _apply_stick(v: Vector2) -> void:
	_stick_vec = v
	var m := v if v.length() > STICK_DEADZONE else Vector2.ZERO
	_axis("move_right", "move_left", m.x)
	_axis("move_back", "move_forward", m.y)


func _axis(positive: String, negative: String, value: float) -> void:
	if value > 0.0:
		Input.action_press(positive, value)
		Input.action_release(negative)
	elif value < 0.0:
		Input.action_press(negative, -value)
		Input.action_release(positive)
	else:
		Input.action_release(positive)
		Input.action_release(negative)


func _physics_process(_delta: float) -> void:
	# taps (jump) stay pressed for one physics frame so the player script sees "just pressed"
	if not _tap_release.is_empty():
		for action in _tap_release:
			Input.action_release.call_deferred(action)
		_tap_release.clear()


## Lets go of every finger and every action this overlay is holding.
func release_all() -> void:
	if _stick_finger >= 0 or _stick_vec != Vector2.ZERO:
		_apply_stick(Vector2.ZERO)
	_stick_finger = -1
	_look_fingers.clear()
	_pinch_dist = 0.0
	for id: String in _buttons:
		var b: Dictionary = _buttons[id]
		if b["mode"] == "hold" and _button_finger.has(id):
			Input.action_release(b["action"])
		if _toggled.get(id, false):
			Input.action_release(b["action"])
	_button_finger.clear()
	_toggled.clear()
	_tap_release.clear()
	if is_inside_tree():
		_stick_base = _stick_home()
		queue_redraw()


func _draw() -> void:
	# movement stick
	var held := _stick_finger >= 0
	draw_circle(_stick_base, STICK_RADIUS, Color(0.04, 0.06, 0.04, 0.30 if held else 0.20))
	draw_arc(_stick_base, STICK_RADIUS, 0.0, TAU, 64, Color(0.9, 0.85, 0.65, 0.55 if held else 0.35), 3.0, true)
	var knob := _stick_base + _stick_vec * STICK_RADIUS
	draw_circle(knob, STICK_KNOB, Color(0.9, 0.85, 0.65, 0.62 if held else 0.38))
	# buttons
	for id: String in _buttons:
		var b: Dictionary = _buttons[id]
		var on: bool = _button_finger.has(id) or _toggled.get(id, false)
		var pos: Vector2 = b["pos"]
		var r: float = b["radius"]
		var fill := Color(0.86, 0.66, 0.22, 0.72) if on else Color(0.04, 0.06, 0.04, BUTTON_ALPHA)
		draw_circle(pos, r, fill)
		draw_arc(pos, r, 0.0, TAU, 48, Color(0.92, 0.87, 0.68, 0.85 if on else 0.55), 3.0, true)
		var label: String = b["label"]
		var fs := int(clampf(r * 0.42, 20.0, 34.0))
		var w := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs).x
		draw_string(_font, pos + Vector2(-w * 0.5, fs * 0.36), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(0.08, 0.07, 0.04, 0.95) if on else Color(0.96, 0.94, 0.86, 0.9))
