extends Node2D
class_name NpcActor

var npc_id := ""
var display_name := ""
var role := ""
var body_color := Color("6f7f86")
var accent_color := Color("d69a45")
var is_daevar := false
var available := true
var contribution_ready := false
var highlighted := false
var facing := Vector2.DOWN
var _pulse := 0.0
var _label: Label


func configure(id: String, name_text: String, role_text: String, color: Color, accent: Color, daevar: bool = false) -> void:
	npc_id = id
	display_name = name_text
	role = role_text
	body_color = color
	accent_color = accent
	is_daevar = daevar
	if is_inside_tree():
		_build_label()
	queue_redraw()


func _ready() -> void:
	_build_label()
	queue_redraw()


func _process(delta: float) -> void:
	_pulse = fmod(_pulse + delta, TAU)
	if highlighted or contribution_ready:
		queue_redraw()


func _build_label() -> void:
	if _label:
		_label.queue_free()
	_label = Label.new()
	_label.name = "Nameplate"
	_label.text = display_name
	_label.position = Vector2(-70, -48)
	_label.size = Vector2(140, 22)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color("eef2ee"))
	_label.add_theme_color_override("font_shadow_color", Color(0.02, 0.03, 0.04, 0.92))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 2)
	_label.visible = not display_name.is_empty()
	add_child(_label)


func set_highlighted(value: bool) -> void:
	highlighted = value
	queue_redraw()


func set_contribution_ready(value: bool) -> void:
	contribution_ready = value
	queue_redraw()


func _draw() -> void:
	# Soft ground shadow and compact, readable top-down silhouette.
	_draw_ellipse_shape(Vector2(0, 14), Vector2(16, 6), Color(0.02, 0.025, 0.03, 0.3))
	draw_colored_polygon(PackedVector2Array([Vector2(-11, -7), Vector2(10, -7), Vector2(12, 12), Vector2(-11, 12)]), body_color)
	draw_line(Vector2(-5, 9), Vector2(-6, 18), body_color.darkened(0.25), 5.0, true)
	draw_line(Vector2(5, 9), Vector2(6, 18), body_color.darkened(0.25), 5.0, true)
	draw_circle(Vector2(0, -15), 8.5, Color("c7a98b") if not is_daevar else Color("9a6b58"))
	draw_arc(Vector2(0, -16), 8.2, PI, TAU, 12, body_color.darkened(0.5), 4.0, true)
	draw_line(Vector2(-10, -5), Vector2(-15, 7), accent_color, 3.0, true)
	if is_daevar:
		draw_colored_polygon(PackedVector2Array([Vector2(-6, -21), Vector2(-12, -31), Vector2(-2, -23)]), accent_color.darkened(0.3))
		draw_colored_polygon(PackedVector2Array([Vector2(6, -21), Vector2(12, -31), Vector2(2, -23)]), accent_color.darkened(0.3))
	if contribution_ready:
		draw_circle(Vector2(0, -38), 8.0 + sin(_pulse * 2.0), Color(accent_color, 0.18))
		draw_arc(Vector2(0, -38), 6.0, -PI * 0.1, PI * 1.15, 16, accent_color, 2.2, true)
		draw_line(Vector2(-3, -38), Vector2(-0.5, -35), accent_color, 2.0, true)
		draw_line(Vector2(-0.5, -35), Vector2(4.5, -42), accent_color, 2.0, true)
	elif highlighted:
		draw_arc(Vector2.ZERO, 26.0 + sin(_pulse * 3.0) * 2.0, 0.0, TAU, 36, Color(accent_color, 0.72), 1.5, true)


func _draw_ellipse_shape(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index in range(24):
		var angle := TAU * float(index) / 24.0
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_colored_polygon(points, color)
