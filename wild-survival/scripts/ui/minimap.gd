class_name Minimap
extends Control
## Minimap (top right) and full map (hold / toggle M). North is up; the arrow is the deer.
## Landmarks and rare plants appear only once the deer has discovered them: safe thickets and
## landmarks when visited, a rare plant when the deer has come close enough to notice it.

const VIEW_RADIUS := 120.0      ## metres shown from the centre to the edge of the minimap

var world: WorldData
var player: Player
var forage: Forage
var predators: PredatorManager
var texture: ImageTexture
var full := false:               ## true: draw the whole world, large
	set(v):
		full = v
		queue_redraw()
var _redraw := 0.0


func setup(p_world: WorldData, p_player: Player, p_forage: Forage, p_predators: PredatorManager, tex: ImageTexture) -> void:
	world = p_world
	player = p_player
	forage = p_forage
	predators = p_predators
	texture = tex
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true


func _process(delta: float) -> void:
	_redraw -= delta
	if _redraw <= 0.0 and is_visible_in_tree():
		_redraw = 0.05 if not full else 0.15
		queue_redraw()


## Everything currently allowed on the map: [{pos: Vector2 (world x,z), color, shape, name}]
func markers() -> Array:
	var out: Array = []
	if world == null:
		return out
	for g in world.groves:
		if GameState.discoveries.has(g["id"]):
			out.append({"pos": g["center"], "color": Color(0.2, 0.95, 0.3), "shape": "ring", "name": g["name"]})
	for p in world.pois:
		if GameState.discoveries.has(p["id"]):
			out.append({"pos": p["pos"], "color": Color(1.0, 0.95, 0.75), "shape": "diamond", "name": p["name"]})
	if forage != null:
		for it in forage.items:
			if it["seen"] and not it["eaten"]:
				var ip: Vector3 = it["pos"]
				out.append({"pos": Vector2(ip.x, ip.z), "color": WorldMap.PLANT_COLORS[it["kind"]], "shape": "dot", "name": it["name"]})
	# Keen Senses: the nearest hunter shows as a red mark
	if predators != null and GameState.has_ability("keen_senses"):
		var near := predators.nearest()
		if near != null and is_instance_valid(near) and near.player_distance < 90.0:
			out.append({"pos": near.pos2(), "color": Color(1.0, 0.15, 0.1), "shape": "cross", "name": near.display_name})
	return out


func _draw() -> void:
	if texture == null or player == null:
		return
	var s := minf(size.x, size.y)
	var rect := Rect2(Vector2.ZERO, Vector2(s, s))
	var here := Vector2(player.global_position.x, player.global_position.z)
	var centre := Vector2.ZERO if full else here
	var radius := WorldData.HALF if full else VIEW_RADIUS
	draw_rect(rect, Color(0.03, 0.05, 0.04, 1.0))
	# the part of the world picture that falls inside the view
	var tex_size := Vector2(texture.get_size())
	var uv0 := WorldMap.to_uv(centre.x - radius, centre.y - radius)
	var uv1 := WorldMap.to_uv(centre.x + radius, centre.y + radius)
	draw_texture_rect_region(texture, rect, Rect2(uv0 * tex_size, (uv1 - uv0) * tex_size))
	var scale_px := s / (radius * 2.0)
	var font := get_theme_default_font()
	for m in markers():
		var p: Vector2 = ((m["pos"] as Vector2) - centre) * scale_px + Vector2(s, s) * 0.5
		if not rect.grow(-3.0).has_point(p):
			continue
		var c: Color = m["color"]
		var r := 4.0 if not full else 5.0
		match String(m["shape"]):
			"ring":
				draw_circle(p, r + 2.5, Color(0, 0, 0, 0.7))
				draw_arc(p, r + 1.5, 0.0, TAU, 20, c, 2.0, true)
			"diamond":
				draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r - 3), p + Vector2(r + 3, 0), p + Vector2(0, r + 3), p + Vector2(-r - 3, 0)]), Color(0, 0, 0, 0.7))
				draw_colored_polygon(PackedVector2Array([p + Vector2(0, -r - 1), p + Vector2(r + 1, 0), p + Vector2(0, r + 1), p + Vector2(-r - 1, 0)]), c)
			"cross":
				draw_line(p + Vector2(-r - 1, -r - 1), p + Vector2(r + 1, r + 1), c, 3.0)
				draw_line(p + Vector2(-r - 1, r + 1), p + Vector2(r + 1, -r - 1), c, 3.0)
			_:
				draw_circle(p, r + 1.5, Color(0, 0, 0, 0.75))
				draw_circle(p, r, c)
		if full and font != null:
			draw_string_outline(font, p + Vector2(9, 5), m["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.85))
			draw_string(font, p + Vector2(9, 5), m["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.95))
	# the deer: an arrow pointing the way it faces
	var pp := (here - centre) * scale_px + Vector2(s, s) * 0.5
	var f := player.forward()
	var dir := Vector2(f.x, f.z).normalized()
	var side := Vector2(-dir.y, dir.x)
	var a := 9.0 if not full else 11.0
	var tri := PackedVector2Array([pp + dir * a, pp - dir * a * 0.7 + side * a * 0.65, pp - dir * a * 0.3, pp - dir * a * 0.7 - side * a * 0.65])
	draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[3], tri[0]]), Color(0, 0, 0, 0.9), 4.0, true)
	draw_colored_polygon(tri, Color(1.0, 1.0, 1.0))
	# frame and north mark
	draw_rect(rect, Color(0.55, 0.47, 0.28, 0.95), false, 2.0)
	if font != null:
		draw_string_outline(font, Vector2(s * 0.5 - 5.0, 16.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.9))
		draw_string(font, Vector2(s * 0.5 - 5.0, 16.0), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.92, 0.6))
