class_name AnimalRig
extends Node3D
## Wraps an imported animal model: finds its AnimationPlayer, fixes loop flags, cross-fades clips and
## keeps the body pitched to the slope it is standing on. The parent body faces -Z (Godot forward).

const LOOPING := ["Idle", "Idle2", "Idle3", "Walk", "Run", "Gallop", "Eat"]

var anim: AnimationPlayer
var model: Node3D
var current := ""
var _pitch := 0.0
var _roll := 0.0
var _meshes: Array[MeshInstance3D] = []
var lift := 0.0                   ## extra height offset set by the owner (e.g. a crouch)
var _ground_y := 0.0
var _scale := 1.0
var _strides: Dictionary = {}

static var _stride_table: Dictionary = {}
static var _stride_loaded := false


func setup(model_path: String, model_scale: float, aliases: Dictionary = {}, faces_plus_z := true) -> bool:
	var ps: PackedScene = load(model_path)
	if ps == null:
		push_error("Animal model missing: %s" % model_path)
		return false
	model = ps.instantiate()
	model.scale = Vector3.ONE * model_scale
	if faces_plus_z:
		model.rotation.y = PI   # most source models look down +Z
	_scale = model_scale
	_strides = stride_table().get(model_path, {})
	add_child(model)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		push_error("No AnimationPlayer in %s" % model_path)
		return false
	anim = players[0]
	anim.playback_default_blend_time = 0.25
	for clip in anim.get_animation_list():
		var a := anim.get_animation(clip)
		a.loop_mode = Animation.LOOP_LINEAR if clip in LOOPING else Animation.LOOP_NONE
	# aliases let species with different clip names share one vocabulary (e.g. Run -> Gallop)
	var lib := anim.get_animation_library("")
	for alias: String in aliases:
		if not anim.has_animation(alias) and anim.has_animation(aliases[alias]):
			lib.add_animation(alias, anim.get_animation(aliases[alias]))
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		mi.extra_cull_margin = 2.0
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_meshes.append(mi)
		for s in mi.mesh.get_surface_count():
			var mat := mi.mesh.surface_get_material(s) as BaseMaterial3D
			if mat != null:
				mat.roughness = 0.82
				mat.metallic = 0.0
				mat.metallic_specular = 0.25
				mat.rim_enabled = true
				mat.rim = 0.18
				mat.rim_tint = 0.6
				mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return true


## Measured ground speed (m/s per unit of model scale, at playback rate 1) of the feet in each
## locomotion clip, written by the test scene with WS_STRIDES=1. Used to stop feet sliding.
static func stride_table() -> Dictionary:
	if not _stride_loaded:
		_stride_loaded = true
		var f := FileAccess.open("res://animations/strides.json", FileAccess.READ)
		if f != null:
			var d: Variant = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_stride_table = d
	return _stride_table


## Playback rate at which the feet of `clip` travel over the ground at `speed`, so they grip instead
## of skating. Limited to `max_cps` step cycles per second (beyond that legs just blur); `fallback`
## is returned when the clip has not been measured.
func stride_rate(clip: String, speed: float, min_cps := 0.3, max_cps := 3.4, fallback := 1.0) -> float:
	var key := clip
	if not _strides.has(key):
		return fallback
	var per_rate: float = float(_strides[key]) * _scale
	if per_rate < 0.01:
		return fallback
	var len := length(clip)
	return clampf(speed / per_rate, min_cps * len, max_cps * len)


func has(clip: String) -> bool:
	return anim != null and anim.has_animation(clip)


func length(clip: String) -> float:
	return anim.get_animation(clip).length if has(clip) else 1.0


## Cross-fade to a clip (no-op if it is already playing, unless `restart`).
func play(clip: String, speed := 1.0, blend := 0.25, restart := false) -> void:
	if anim == null or not anim.has_animation(clip):
		return
	if current != clip or restart:
		current = clip
		if restart:
			anim.stop()
		anim.play(clip, blend, speed)
	else:
		anim.speed_scale = 1.0
		# adjust the speed of the running clip without restarting it
		anim.play(clip, -1.0, speed)


func set_paused(p: bool) -> void:
	if anim == null:
		return
	if p and anim.is_playing():
		anim.pause()
	elif not p and not anim.is_playing() and current != "" and anim.get_animation(current).loop_mode != Animation.LOOP_NONE:
		anim.play(current)


## Lean the body to the terrain. `forward` is the horizontal facing direction.
func align_to_ground(normal: Vector3, forward: Vector3, delta: float, amount := 0.75) -> void:
	var right := forward.cross(Vector3.UP)
	# facing uphill the normal leans back toward us (normal.dot(forward) < 0) and the nose must rise
	var target_pitch := asin(clampf(-normal.dot(forward), -0.6, 0.6)) * amount
	var target_roll := asin(clampf(normal.dot(right), -0.6, 0.6)) * amount * 0.6
	var k := minf(delta * 7.0, 1.0)
	_pitch = lerpf(_pitch, target_pitch, k)
	_roll = lerpf(_roll, target_roll, k)
	rotation.x = _pitch
	rotation.z = -_roll
	position.y = lift


## Plant the animal on uneven ground: sample the terrain under the fore and hind feet, pitch the body
## along that line and raise or lower it so both ends touch, instead of floating or sinking in.
func fit_to_ground(world: WorldData, pos: Vector3, forward: Vector3, half_length: float, delta: float, grounded := true) -> void:
	var hf := world.height_at(pos.x + forward.x * half_length, pos.z + forward.z * half_length)
	var hb := world.height_at(pos.x - forward.x * half_length, pos.z - forward.z * half_length)
	var normal := world.normal_at(pos.x, pos.z)
	var right := forward.cross(Vector3.UP)
	var k := minf(delta * 8.0, 1.0)
	var target_pitch := 0.0
	var target_roll := 0.0
	var target_y := 0.0
	if grounded and minf(hf, hb) > WorldData.WATER_LEVEL - 0.6:
		target_pitch = clampf(atan2(hf - hb, half_length * 2.0), -0.85, 0.85)
		target_roll = asin(clampf(normal.dot(right), -0.6, 0.6)) * 0.45
		target_y = clampf((hf + hb) * 0.5 - pos.y, -0.35, 0.2)
	_pitch = lerpf(_pitch, target_pitch, k)
	_roll = lerpf(_roll, target_roll, k)
	_ground_y = lerpf(_ground_y, target_y, k)
	rotation.x = _pitch
	rotation.z = -_roll
	position.y = _ground_y + lift


func set_shadow(enabled: bool) -> void:
	for m in _meshes:
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if enabled else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
