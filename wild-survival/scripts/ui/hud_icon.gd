class_name HudIcon
extends Control
## Small vector icons drawn in code (no image files): heart, water drop, leaf, lightning bolt and
## one for every ability. Crisp at any resolution and tinted with `color`.

var kind := "heart"
var color := Color.WHITE:
	set(v):
		color = v
		queue_redraw()
var dim := false:
	set(v):
		dim = v
		queue_redraw()


static func make(p_kind: String, p_color: Color, px := 30.0) -> HudIcon:
	var i := HudIcon.new()
	i.kind = p_kind
	i.color = p_color
	i.custom_minimum_size = Vector2(px, px)
	i.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	i.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return i


func _pts(raw: Array) -> PackedVector2Array:
	# points given in a 0..1 box, scaled to the control
	var out := PackedVector2Array()
	var s := minf(size.x, size.y)
	var off := (size - Vector2(s, s)) * 0.5
	for p: Vector2 in raw:
		out.append(off + p * s)
	return out


func _poly(raw: Array, c: Color) -> void:
	var pts := _pts(raw)
	draw_colored_polygon(pts, c)
	pts.append(pts[0])
	draw_polyline(pts, Color(0, 0, 0, 0.55), 1.5, true)


func _line(raw: Array, c: Color, w := 0.09) -> void:
	draw_polyline(_pts(raw), c, maxf(w * minf(size.x, size.y), 1.5), true)


func _circle(center: Vector2, r: float, c: Color) -> void:
	var s := minf(size.x, size.y)
	draw_circle((size - Vector2(s, s)) * 0.5 + center * s, r * s, c)


func _draw() -> void:
	var c := color if not dim else Color(color.r, color.g, color.b, 0.28)
	var dark := Color(0.04, 0.05, 0.04, 0.9 if not dim else 0.3)
	match kind:
		"heart":
			var pts := []
			for i in 40:
				var t := TAU * i / 40.0
				var x := 16.0 * pow(sin(t), 3.0)
				var y := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
				pts.append(Vector2(0.5 + x / 36.0, 0.47 - y / 36.0))
			_poly(pts, c)
			_circle(Vector2(0.34, 0.33), 0.06, Color(1, 1, 1, 0.45 if not dim else 0.1))
		"drop":
			var pts2 := [Vector2(0.5, 0.04)]
			for i in 25:
				var t2 := -0.25 * PI + (1.5 * PI) * i / 24.0
				pts2.append(Vector2(0.5 + cos(t2) * 0.3, 0.64 + sin(t2) * 0.3))
			_poly(pts2, c)
			_circle(Vector2(0.4, 0.62), 0.07, Color(1, 1, 1, 0.45 if not dim else 0.1))
		"leaf":
			var pts3 := []
			for i in 13:
				var t3 := float(i) / 12.0
				pts3.append(Vector2(0.14 + t3 * 0.74, 0.86 - t3 * 0.74) + Vector2(-0.7, -0.7) * sin(t3 * PI) * 0.2)
			for i in 13:
				var t4 := 1.0 - float(i) / 12.0
				pts3.append(Vector2(0.14 + t4 * 0.74, 0.86 - t4 * 0.74) + Vector2(0.7, 0.7) * sin(t4 * PI) * 0.2)
			_poly(pts3, c)
			_line([Vector2(0.08, 0.92), Vector2(0.8, 0.2)], dark, 0.05)
		"bolt":
			_poly([Vector2(0.6, 0.03), Vector2(0.2, 0.55), Vector2(0.46, 0.55), Vector2(0.36, 0.97), Vector2(0.82, 0.4), Vector2(0.54, 0.4)], c)
		"swift":
			for k in 3:
				var x0 := 0.12 + 0.24 * k
				_line([Vector2(x0, 0.2), Vector2(x0 + 0.26, 0.5), Vector2(x0, 0.8)], c, 0.11)
		"night_vision":
			var eye := []
			for i in 13:
				eye.append(Vector2(0.06 + 0.88 * i / 12.0, 0.5 - sin(PI * i / 12.0) * 0.27))
			for i in 13:
				eye.append(Vector2(0.94 - 0.88 * i / 12.0, 0.5 + sin(PI * i / 12.0) * 0.27))
			_poly(eye, c)
			_circle(Vector2(0.5, 0.5), 0.15, dark)
			_circle(Vector2(0.45, 0.45), 0.05, Color(1, 1, 1, 0.8 if not dim else 0.2))
		"iron_hide":
			_poly([Vector2(0.5, 0.05), Vector2(0.88, 0.18), Vector2(0.84, 0.6), Vector2(0.5, 0.95), Vector2(0.16, 0.6), Vector2(0.12, 0.18)], c)
			_line([Vector2(0.5, 0.25), Vector2(0.5, 0.72)], dark, 0.08)
			_line([Vector2(0.3, 0.45), Vector2(0.7, 0.45)], dark, 0.08)
		"deep_lungs":
			_poly([Vector2(0.6, 0.03), Vector2(0.2, 0.55), Vector2(0.46, 0.55), Vector2(0.36, 0.97), Vector2(0.82, 0.4), Vector2(0.54, 0.4)], c)
			_line([Vector2(0.78, 0.7), Vector2(0.78, 0.96)], c, 0.09)
			_line([Vector2(0.65, 0.83), Vector2(0.91, 0.83)], c, 0.09)
		"silent_step":
			# a feather
			var f := []
			for i in 11:
				var t5 := float(i) / 10.0
				f.append(Vector2(0.2 + t5 * 0.62, 0.8 - t5 * 0.62) + Vector2(-0.7, -0.7) * sin(t5 * PI) * 0.13)
			for i in 11:
				var t6 := 1.0 - float(i) / 10.0
				f.append(Vector2(0.2 + t6 * 0.62, 0.8 - t6 * 0.62) + Vector2(0.7, 0.7) * sin(t6 * PI) * 0.13)
			_poly(f, c)
			_line([Vector2(0.08, 0.92), Vector2(0.8, 0.2)], dark, 0.04)
		"keen_senses":
			_circle(Vector2(0.5, 0.78), 0.1, c)
			for k in 3:
				var arc := []
				var rr := 0.26 + 0.2 * k
				for i in 9:
					var a := -PI * 0.78 + PI * 0.56 * i / 8.0
					arc.append(Vector2(0.5 + cos(a) * rr, 0.78 + sin(a) * rr))
				_line(arc, c, 0.08)
		"high_leap":
			_poly([Vector2(0.5, 0.04), Vector2(0.9, 0.48), Vector2(0.64, 0.48), Vector2(0.64, 0.95), Vector2(0.36, 0.95), Vector2(0.36, 0.48), Vector2(0.1, 0.48)], c)
		"otter_blood":
			for k in 3:
				var w := []
				for i in 13:
					w.append(Vector2(0.06 + 0.88 * i / 12.0, 0.26 + 0.24 * k + sin(TAU * i / 6.0) * 0.07))
				_line(w, c, 0.1)
		"paw":
			_circle(Vector2(0.5, 0.64), 0.2, c)
			for p: Vector2 in [Vector2(0.22, 0.4), Vector2(0.4, 0.22), Vector2(0.62, 0.22), Vector2(0.8, 0.4)]:
				_circle(p, 0.1, c)
		"flower":
			for k in 5:
				var a2 := TAU * k / 5.0 - PI * 0.5
				_circle(Vector2(0.5 + cos(a2) * 0.25, 0.5 + sin(a2) * 0.25), 0.17, c)
			_circle(Vector2(0.5, 0.5), 0.12, Color(1.0, 0.9, 0.4, 1.0 if not dim else 0.3))
		"clock":
			_circle(Vector2(0.5, 0.5), 0.42, c)
			_circle(Vector2(0.5, 0.5), 0.33, dark)
			_line([Vector2(0.5, 0.26), Vector2(0.5, 0.5), Vector2(0.68, 0.6)], c, 0.08)
		"cloud", "rain", "storm":
			_circle(Vector2(0.34, 0.42), 0.18, c)
			_circle(Vector2(0.55, 0.32), 0.22, c)
			_circle(Vector2(0.72, 0.44), 0.16, c)
			draw_rect(Rect2(_pts([Vector2(0.3, 0.4)])[0], Vector2(0.44, 0.2) * minf(size.x, size.y)), c)
			if kind != "cloud":
				for k in 3:
					_line([Vector2(0.34 + 0.18 * k, 0.68), Vector2(0.26 + 0.18 * k, 0.94)], Color(0.55, 0.78, 1.0), 0.07)
			if kind == "storm":
				_line([Vector2(0.58, 0.55), Vector2(0.46, 0.76), Vector2(0.6, 0.76), Vector2(0.5, 0.98)], Color(1.0, 0.9, 0.3), 0.08)
		"sun":
			_circle(Vector2(0.5, 0.5), 0.22, c)
			for k in 8:
				var a3 := TAU * k / 8.0
				_line([Vector2(0.5 + cos(a3) * 0.32, 0.5 + sin(a3) * 0.32), Vector2(0.5 + cos(a3) * 0.46, 0.5 + sin(a3) * 0.46)], c, 0.07)
		_:
			_circle(Vector2(0.5, 0.5), 0.4, c)
