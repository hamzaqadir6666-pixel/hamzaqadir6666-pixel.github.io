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


func setup(model_path: String, model_scale: float, aliases: Dictionary = {}) -> bool:
	var ps: PackedScene = load(model_path)
	if ps == null:
		push_error("Animal model missing: %s" % model_path)
		return false
	model = ps.instantiate()
	model.scale = Vector3.ONE * model_scale
	model.rotation.y = PI   # source models look down +Z
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
	var target_pitch := asin(clampf(normal.dot(forward), -0.6, 0.6)) * -amount
	var target_roll := asin(clampf(normal.dot(right), -0.6, 0.6)) * amount * 0.6
	var k := minf(delta * 7.0, 1.0)
	_pitch = lerpf(_pitch, target_pitch, k)
	_roll = lerpf(_roll, target_roll, k)
	rotation.x = -_pitch
	rotation.z = -_roll


func set_shadow(enabled: bool) -> void:
	for m in _meshes:
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if enabled else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
