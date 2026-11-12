class_name ThirdPersonCamera
extends Node3D
## Smooth, collision-aware third-person camera. Yaw lives on this node, pitch on the inner pivot.

@export var target_height := 1.35
@export var min_distance := 1.2

var target: Node3D
var world: WorldData
var camera: Camera3D
var input_enabled := true
var shake := 0.0

var _pitch := -0.22
var _distance := 5.5
var _current_distance := 5.5
var _focus := Vector3.ZERO
var _fov_boost := 0.0
var _orbit := 0.0


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	camera = Camera3D.new()
	camera.near = 0.15
	camera.far = 1400.0
	camera.fov = float(Settings.get_value("graphics", "fov"))
	add_child(camera)
	camera.make_current()
	var listener := AudioListener3D.new()
	camera.add_child(listener)
	listener.make_current()
	_distance = float(Settings.get_value("controls", "camera_distance"))
	_current_distance = _distance


func snap_to_target() -> void:
	if target != null:
		_focus = target.global_position + Vector3(0.0, target_height, 0.0)
		_update_transform(1.0)


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		var motion := (event as InputEventMouseMotion).relative
		var sens := lerpf(0.0008, 0.0065, float(Settings.get_value("controls", "mouse_sensitivity")))
		rotation.y -= motion.x * sens
		var inv := -1.0 if bool(Settings.get_value("controls", "invert_y")) else 1.0
		_pitch = clampf(_pitch - motion.y * sens * inv, -1.25, 0.55)
	elif event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(_distance - 0.5, 2.5)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(_distance + 0.5, 10.0)


## Slow orbit used behind the main menu.
func orbit(delta: float, speed := 0.06) -> void:
	_orbit += delta
	rotation.y += delta * speed
	_pitch = -0.18 + sin(_orbit * 0.13) * 0.06


func _process(delta: float) -> void:
	if target == null:
		return
	var tp := target.get_global_transform_interpolated().origin if target.is_inside_tree() else target.global_position
	var want := tp + Vector3(0.0, target_height, 0.0)
	# follow tightly horizontally, a little softer vertically (hides stair-stepping on slopes)
	var k := minf(delta * 18.0, 1.0)
	_focus.x = lerpf(_focus.x, want.x, k)
	_focus.z = lerpf(_focus.z, want.z, k)
	_focus.y = lerpf(_focus.y, want.y, minf(delta * 9.0, 1.0))
	_update_transform(delta)


func _update_transform(delta: float) -> void:
	global_position = _focus
	var dir := Vector3(0.0, 0.0, 1.0).rotated(Vector3.RIGHT, _pitch).rotated(Vector3.UP, rotation.y)
	var desired := _distance
	# collision: pull the camera in front of trunks, rocks and terrain
	var space := get_world_3d().direct_space_state
	if space != null:
		var q := PhysicsRayQueryParameters3D.create(_focus, _focus + dir * (_distance + 0.4), 3)
		var hit := space.intersect_ray(q)
		if not hit.is_empty():
			desired = clampf(_focus.distance_to(hit["position"]) - 0.35, min_distance, _distance)
	if desired < _current_distance:
		_current_distance = lerpf(_current_distance, desired, minf(delta * 22.0, 1.0))
	else:
		_current_distance = lerpf(_current_distance, desired, minf(delta * 4.0, 1.0))
	var cam_pos := _focus + dir * _current_distance
	if world != null:
		cam_pos.y = maxf(cam_pos.y, world.height_at(cam_pos.x, cam_pos.z) + 0.35)
		cam_pos.y = maxf(cam_pos.y, WorldData.WATER_LEVEL + 0.25)
	if shake > 0.001:
		cam_pos += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * shake * 0.12
		shake = lerpf(shake, 0.0, minf(delta * 6.0, 1.0))
	camera.global_position = cam_pos
	camera.look_at(_focus + Vector3(0.0, 0.15, 0.0), Vector3.UP)
	var base_fov := float(Settings.get_value("graphics", "fov"))
	var boost := 0.0
	if target is Player and (target as Player).is_sprinting:
		boost = 9.0
	_fov_boost = lerpf(_fov_boost, boost, minf(delta * 3.0, 1.0))
	camera.fov = base_fov + _fov_boost
