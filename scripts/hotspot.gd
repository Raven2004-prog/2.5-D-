extends Node2D
class_name EvidenceHotspot

var hotspot_id := ""
var display_name := ""
var prompt_text := "Inspect"
var accent := Color("d8a04a")
var available := true
var discovered := false
var active := false
var _phase := 0.0


func configure(id: String, label_text: String, prompt: String, color: Color) -> void:
	hotspot_id = id
	display_name = label_text
	prompt_text = prompt
	accent = color
	queue_redraw()


func _process(delta: float) -> void:
	_phase = fmod(_phase + delta, TAU)
	if active or not discovered:
		queue_redraw()


func set_active(value: bool) -> void:
	active = value
	queue_redraw()


func set_discovered(value: bool) -> void:
	discovered = value
	queue_redraw()


func _draw() -> void:
	if not available:
		return
	var alpha := 0.7 if active else 0.3
	var radius := 18.0 + sin(_phase * 2.4) * 2.0
	if not discovered:
		draw_circle(Vector2.ZERO, radius + 8.0, Color(accent, 0.055))
		draw_arc(Vector2.ZERO, radius, 0, TAU, 32, Color(accent, alpha), 1.5, true)
	else:
		draw_arc(Vector2.ZERO, 14.0, -PI * 0.1, PI * 1.18, 22, Color(accent, alpha), 2.0, true)
		draw_line(Vector2(-6, 0), Vector2(-1, 5), Color(accent, alpha), 2.0, true)
		draw_line(Vector2(-1, 5), Vector2(7, -6), Color(accent, alpha), 2.0, true)
	if hotspot_id == "signal":
		for ring in range(3):
			draw_arc(Vector2(0, 4), 5.0 + ring * 5.0, -PI * 0.8, -PI * 0.2, 10, Color(accent, alpha), 1.5, true)
	elif hotspot_id == "powder":
		draw_rect(Rect2(-8, -7, 16, 14), Color(accent, alpha * 0.65), false, 2.0)
		draw_line(Vector2(-8, -7), Vector2(8, 7), Color(accent, alpha * 0.65), 1.0)
	elif hotspot_id == "gate":
		draw_circle(Vector2.ZERO, 8.0, Color(accent, alpha), false, 2.0)
		for spoke in range(6):
			var direction := Vector2.RIGHT.rotated(TAU * float(spoke) / 6.0)
			draw_line(direction * 3.0, direction * 11.0, Color(accent, alpha), 1.5)
	elif hotspot_id == "tunnel":
		draw_line(Vector2(-7, 6), Vector2(7, -6), Color(accent, alpha), 2.0)
		draw_circle(Vector2(-6, 7), 3.0, Color(accent, alpha))
		draw_circle(Vector2(7, -7), 3.0, Color(accent, alpha))

