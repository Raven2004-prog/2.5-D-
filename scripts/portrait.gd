extends Control
class_name CharacterPortrait

var character_id := "evan"
var accent := Color("d8a04a")
var _phase := 0.0

const COLORS := {
	"evan": [Color("263b4c"), Color("d1af92"), Color("171b20"), Color("79c7d0")],
	"mara": [Color("59636a"), Color("c29b7e"), Color("4a352e"), Color("d59b4a")],
	"lysa": [Color("5c4f66"), Color("caa583"), Color("3a2625"), Color("c47a56")],
	"nessa": [Color("456260"), Color("b98d72"), Color("252b2c"), Color("87b8a2")],
	"brann": [Color("5a5148"), Color("b58c6d"), Color("3a332e"), Color("c3a15e")],
	"kesh": [Color("514b60"), Color("956756"), Color("2b252f"), Color("d97045")],
	"piri": [Color("4b5c68"), Color("aa806c"), Color("31282c"), Color("dfa750")],
	"tamsin": [Color("36454c"), Color("b98f74"), Color("242729"), Color("8faab1")],
	"tomas": [Color("675b4a"), Color("c09b79"), Color("43352d"), Color("c7834d")],
	"corvin": [Color("3f2738"), Color("c2a18b"), Color("18131a"), Color("a84b55")],
	"narrator": [Color("303b42"), Color("a7b6b5"), Color("182024"), Color("c9904f")],
}


func _ready() -> void:
	custom_minimum_size = Vector2(118, 118)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func _process(delta: float) -> void:
	_phase += delta
	queue_redraw()


func set_character(id: String) -> void:
	character_id = id.to_lower()
	var palette: Array = COLORS.get(character_id, COLORS["narrator"])
	accent = palette[3]
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2(3, 3), size - Vector2(6, 6))
	draw_style_box(_panel_style(), rect)
	var palette: Array = COLORS.get(character_id, COLORS["narrator"])
	var clothing: Color = palette[0]
	var skin: Color = palette[1]
	var hair: Color = palette[2]
	var local_accent: Color = palette[3]
	var center := Vector2(size.x * 0.5, size.y * 0.54)
	# Rain-lit arch behind the bust.
	draw_circle(center + Vector2(0, 4), minf(size.x, size.y) * 0.36, Color(local_accent, 0.065))
	draw_arc(center + Vector2(0, 4), minf(size.x, size.y) * 0.36, PI, TAU, 34, Color(local_accent, 0.34), 1.5, true)
	# Shoulders, neck, face, and hair are deliberately graphic rather than photoreal.
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(-45, 43), center + Vector2(-33, 14), center + Vector2(-12, 3),
		center + Vector2(12, 3), center + Vector2(34, 14), center + Vector2(47, 43)
	]), clothing)
	draw_rect(Rect2(center + Vector2(-8, -1), Vector2(16, 19)), skin.darkened(0.06), true)
	_draw_ellipse_shape(center + Vector2(0, -23), Vector2(22, 29), skin)
	draw_colored_polygon(PackedVector2Array([
		center + Vector2(-22, -25), center + Vector2(-17, -48), center + Vector2(2, -55),
		center + Vector2(22, -43), center + Vector2(20, -18), center + Vector2(12, -38),
		center + Vector2(-13, -40)
	]), hair)
	if character_id == "mara":
		draw_line(center + Vector2(-20, -32), center + Vector2(-30, 12), hair, 7.0, true)
		draw_line(center + Vector2(20, -32), center + Vector2(28, 12), hair, 7.0, true)
	elif character_id == "kesh":
		draw_colored_polygon(PackedVector2Array([center + Vector2(-13, -46), center + Vector2(-27, -65), center + Vector2(-5, -50)]), local_accent.darkened(0.35))
		draw_colored_polygon(PackedVector2Array([center + Vector2(13, -46), center + Vector2(27, -65), center + Vector2(5, -50)]), local_accent.darkened(0.35))
	elif character_id == "corvin":
		draw_arc(center + Vector2(0, -18), 12, 0.08, PI - 0.08, 16, Color("6f2731"), 2.0, true)
	# Eyes and a small changing rain reflection keep portraits alive without animation assets.
	draw_line(center + Vector2(-12, -22), center + Vector2(-4, -22), hair.lightened(0.12), 2.0)
	draw_line(center + Vector2(4, -22), center + Vector2(12, -22), hair.lightened(0.12), 2.0)
	draw_line(Vector2(14 + fmod(_phase * 11.0, maxf(1.0, size.x - 28.0)), 10), Vector2(8 + fmod(_phase * 11.0, maxf(1.0, size.x - 28.0)), 23), Color(0.7, 0.8, 0.83, 0.15), 1.0)


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("111820")
	style.border_color = Color(accent, 0.64)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	return style


func _draw_ellipse_shape(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index in range(32):
		var angle := TAU * float(index) / 32.0
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_colored_polygon(points, color)
