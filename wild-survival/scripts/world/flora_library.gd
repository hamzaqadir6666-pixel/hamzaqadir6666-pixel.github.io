class_name FloraLibrary
extends RefCounted
## Loads the converted environment models (see resources/flora_manifest.json), extracts their meshes
## and assigns wind-animated foliage materials. Shared by all vegetation systems.

const MANIFEST := "res://resources/flora_manifest.json"
const FOLIAGE_SHADER := preload("res://shaders/foliage.gdshader")

class Entry:
	var name: String
	var category: String
	var mesh: Mesh
	var size: Vector3          ## bounding size (metres at scale 1)
	var half_width: float
	var height: float
	var hull: PackedVector3Array

var entries: Dictionary = {}            ## name -> Entry
var by_category: Dictionary = {}        ## category -> Array[Entry]
var push_materials: Array[ShaderMaterial] = []   ## materials that react to the player
var wind_materials: Array[ShaderMaterial] = []

## Per-category sway tuning: [sway_start_height, sway_height_scale, flutter, push_radius, backlight]
const SWAY := {
	"trees": [2.5, 0.022, 0.05, 0.0, 0.5],
	"palms": [3.0, 0.045, 0.07, 0.0, 0.5],
	"dead": [3.0, 0.01, 0.01, 0.0, 0.1],
	"bushes": [0.25, 0.10, 0.06, 1.5, 0.45],
	"food": [0.25, 0.08, 0.05, 1.2, 0.45],
	"plants": [0.1, 0.16, 0.05, 1.0, 0.5],
	"grass": [0.0, 0.30, 0.03, 1.1, 0.55],
	"water_plants": [0.1, 0.22, 0.03, 1.0, 0.5],
}


func load_all() -> void:
	var f := FileAccess.open(MANIFEST, FileAccess.READ)
	if f == null:
		push_error("Flora manifest missing")
		return
	var manifest: Dictionary = JSON.parse_string(f.get_as_text())
	for category: String in manifest:
		by_category[category] = []
		for item: Dictionary in manifest[category]:
			var e := _load_entry(item, category)
			if e != null:
				entries[e.name] = e
				by_category[category].append(e)


func _load_entry(item: Dictionary, category: String) -> Entry:
	var path: String = item["path"]
	if not ResourceLoader.exists(path):
		push_warning("Flora model missing: %s" % path)
		return null
	var scene: PackedScene = load(path)
	var inst := scene.instantiate()
	var mi: MeshInstance3D = null
	if inst is MeshInstance3D:
		mi = inst
	else:
		var found := inst.find_children("*", "MeshInstance3D", true, false)
		if not found.is_empty():
			mi = found[0]
	if mi == null or mi.mesh == null:
		inst.free()
		return null
	var e := Entry.new()
	e.name = item["name"]
	e.category = category
	e.mesh = mi.mesh
	var mn: Array = item["min"]
	var mx: Array = item["max"]
	e.size = Vector3(mx[0] - mn[0], mx[1], mx[2] - mn[2])
	e.half_width = maxf(e.size.x, e.size.z) * 0.5
	e.height = mx[1]
	_setup_materials(e)
	if category == "rocks" or category == "cliffs" or category == "logs":
		var shape := e.mesh.create_convex_shape(true, false)
		if shape != null:
			e.hull = shape.points
	inst.free()
	return e


func _setup_materials(e: Entry) -> void:
	var sway: Array = SWAY.get(e.category, [0.0, 0.0, 0.0, 0.0, 0.0])
	for s in e.mesh.get_surface_count():
		var src := e.mesh.surface_get_material(s) as BaseMaterial3D
		if src == null:
			continue
		var is_foliage := src.resource_name.begins_with("foliage") or src.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
		if is_foliage and SWAY.has(e.category):
			var m := ShaderMaterial.new()
			m.shader = FOLIAGE_SHADER
			m.set_shader_parameter("albedo_tex", src.albedo_texture)
			m.set_shader_parameter("alpha_cutoff", 0.38)
			m.set_shader_parameter("sway_start_height", sway[0])
			m.set_shader_parameter("sway_height_scale", sway[1])
			m.set_shader_parameter("flutter", sway[2])
			m.set_shader_parameter("push_radius", sway[3])
			m.set_shader_parameter("backlight", sway[4])
			m.set_shader_parameter("tint", Color(0.92, 1.0, 0.88) if e.category != "food" else Color.WHITE)
			e.mesh.surface_set_material(s, m)
			wind_materials.append(m)
			if sway[3] > 0.0:
				push_materials.append(m)
		else:
			# bark / rock: opaque PBR
			src.roughness = 0.92
			src.metallic = 0.0
			src.metallic_specular = 0.25
			src.cull_mode = BaseMaterial3D.CULL_BACK if not is_foliage else BaseMaterial3D.CULL_DISABLED
			if is_foliage:
				src.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				src.alpha_scissor_threshold = 0.4
			src.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC


func category(cat: String) -> Array:
	return by_category.get(cat, [])


func find_prefix(prefix: String) -> Array:
	var out: Array = []
	for n: String in entries:
		if n.begins_with(prefix):
			out.append(entries[n])
	return out


func set_player_position(p: Vector3) -> void:
	for m in push_materials:
		m.set_shader_parameter("player_pos", p)


func set_wind(strength: float, dir: Vector2) -> void:
	for m in wind_materials:
		m.set_shader_parameter("wind_strength", strength)
		m.set_shader_parameter("wind_dir", dir)
