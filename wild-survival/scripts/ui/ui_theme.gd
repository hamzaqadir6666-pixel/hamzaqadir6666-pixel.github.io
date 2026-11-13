class_name UITheme
extends RefCounted
## Wilderness UI theme built in code (earth and leaf tones) plus small widget helpers.

const BG := Color(0.06, 0.09, 0.06, 0.88)
const PANEL := Color(0.09, 0.13, 0.09, 0.92)
const EDGE := Color(0.55, 0.47, 0.28, 0.9)
const TEXT := Color(0.93, 0.90, 0.80)
const MUTED := Color(0.70, 0.72, 0.62)
const ACCENT := Color(0.84, 0.69, 0.32)
const LEAF := Color(0.38, 0.62, 0.30)
const HEALTH := Color(0.78, 0.24, 0.20)
const STAMINA := Color(0.88, 0.74, 0.26)
const FOOD := Color(0.47, 0.70, 0.28)
const WATER := Color(0.28, 0.58, 0.82)

const THEME_PATH := "res://ui/wilderness_theme.tres"

static var _theme: Theme


static func box(color: Color, radius := 6, border := 0, border_color := EDGE, margin := 10.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border)
	s.border_color = border_color
	s.set_content_margin_all(margin)
	return s


static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	if ResourceLoader.exists(THEME_PATH):
		_theme = load(THEME_PATH)
		return _theme
	_theme = build_theme()
	return _theme


static func build_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 20
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.6))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 2)
	# buttons
	t.set_stylebox("normal", "Button", box(Color(0.13, 0.19, 0.12, 0.92), 6, 1, Color(0.42, 0.40, 0.25, 0.8), 12.0))
	t.set_stylebox("hover", "Button", box(Color(0.22, 0.32, 0.18, 0.96), 6, 2, ACCENT, 12.0))
	t.set_stylebox("pressed", "Button", box(Color(0.30, 0.26, 0.12, 0.96), 6, 2, ACCENT, 12.0))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), 6, 2, ACCENT, 12.0))
	t.set_stylebox("disabled", "Button", box(Color(0.1, 0.1, 0.1, 0.6), 6, 1, Color(0.3, 0.3, 0.3), 12.0))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color(1, 0.96, 0.82))
	t.set_color("font_pressed_color", "Button", ACCENT)
	t.set_font_size("font_size", "Button", 22)
	for cls: String in ["OptionButton", "CheckButton", "CheckBox"]:
		t.set_stylebox("normal", cls, box(Color(0.13, 0.19, 0.12, 0.92), 5, 1, Color(0.42, 0.40, 0.25, 0.8), 8.0))
		t.set_stylebox("hover", cls, box(Color(0.22, 0.32, 0.18, 0.96), 5, 1, ACCENT, 8.0))
		t.set_stylebox("pressed", cls, box(Color(0.18, 0.26, 0.15, 0.96), 5, 1, ACCENT, 8.0))
		t.set_color("font_color", cls, TEXT)
		t.set_font_size("font_size", cls, 18)
	t.set_stylebox("panel", "PanelContainer", box(PANEL, 10, 2, EDGE, 22.0))
	t.set_stylebox("panel", "PopupMenu", box(PANEL, 6, 1, EDGE, 6.0))
	t.set_stylebox("panel", "TabContainer", box(Color(0.07, 0.10, 0.07, 0.9), 6, 1, Color(0.42, 0.40, 0.25, 0.6), 16.0))
	t.set_stylebox("tab_selected", "TabContainer", box(Color(0.24, 0.33, 0.19), 5, 1, ACCENT, 10.0))
	t.set_stylebox("tab_unselected", "TabContainer", box(Color(0.10, 0.14, 0.10), 5, 0, EDGE, 10.0))
	t.set_stylebox("tab_hovered", "TabContainer", box(Color(0.17, 0.24, 0.15), 5, 0, EDGE, 10.0))
	t.set_color("font_selected_color", "TabContainer", Color(1, 0.96, 0.82))
	t.set_color("font_unselected_color", "TabContainer", MUTED)
	# sliders
	t.set_stylebox("slider", "HSlider", box(Color(0.04, 0.06, 0.04), 4, 0, EDGE, 4.0))
	t.set_stylebox("grabber_area", "HSlider", box(LEAF, 4, 0, EDGE, 4.0))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(ACCENT, 4, 0, EDGE, 4.0))
	# progress bars
	t.set_stylebox("background", "ProgressBar", box(Color(0.03, 0.04, 0.03, 0.75), 4, 1, Color(0, 0, 0, 0.7), 0.0))
	t.set_stylebox("fill", "ProgressBar", box(LEAF, 4, 0, EDGE, 0.0))
	return t


static func label(text: String, size := 20, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, on_press: Callable, min_width := 280.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 48.0)
	b.pressed.connect(func() -> void:
		AudioManager.click()
		on_press.call())
	b.mouse_entered.connect(AudioManager.hover)
	return b


static func bar(color: Color, min_size := Vector2(220.0, 16.0)) -> ProgressBar:
	var p := ProgressBar.new()
	p.custom_minimum_size = min_size
	p.show_percentage = false
	p.max_value = 100.0
	p.value = 100.0
	p.add_theme_stylebox_override("fill", box(color, 4, 0, EDGE, 0.0))
	return p
