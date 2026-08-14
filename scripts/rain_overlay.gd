extends Control
class_name RainOverlay

var intensity := 1.0
var reduced_motion := false
var flash_amount := 0.0
var return_distortion := 0.0
var _elapsed := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 90
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += delta * (0.28 if reduced_motion else 1.0)
	flash_amount = maxf(0.0, flash_amount - delta * 1.8)
	return_distortion = maxf(0.0, return_distortion - delta * 0.42)
	queue_redraw()


func pulse_lightning(amount: float = 0.32) -> void:
	flash_amount = maxf(flash_amount, amount)


func begin_return(reduce_flash: bool = false) -> void:
	return_distortion = 0.52 if reduce_flash else 1.0
	flash_amount = 0.12 if reduce_flash else 0.55


func _draw() -> void:
	var viewport_size := size
	if viewport_size.x <= 1.0:
		viewport_size = get_viewport_rect().size
	# Screen-space rain keeps density stable while the camera moves.
	var drop_count := int(92.0 * intensity) if reduced_motion else int(155.0 * intensity)
	for index in range(drop_count):
		var speed := 420.0 + float((index * 31) % 210)
		var x := fmod(float(index * 89) + _elapsed * speed * 0.23, viewport_size.x + 120.0) - 60.0
		var y := fmod(float(index * 47) + _elapsed * speed, viewport_size.y + 80.0) - 40.0
		var length := 8.0 + float(index % 8) * 1.7
		var alpha := 0.09 + float(index % 5) * 0.018
		draw_line(Vector2(x, y), Vector2(x - length * 0.32, y + length), Color(0.68, 0.79, 0.82, alpha), 1.0, true)
	# Low fog and readable cinematic vignette.
	draw_rect(Rect2(0, viewport_size.y * 0.72, viewport_size.x, viewport_size.y * 0.28), Color(0.52, 0.65, 0.66, 0.035), true)
	var edge := 74.0
	draw_rect(Rect2(0, 0, edge, viewport_size.y), Color(0.015, 0.02, 0.025, 0.18), true)
	draw_rect(Rect2(viewport_size.x - edge, 0, edge, viewport_size.y), Color(0.015, 0.02, 0.025, 0.18), true)
	draw_rect(Rect2(0, 0, viewport_size.x, 46), Color(0.015, 0.02, 0.025, 0.12), true)
	draw_rect(Rect2(0, viewport_size.y - 58, viewport_size.x, 58), Color(0.015, 0.02, 0.025, 0.16), true)
	if return_distortion > 0.0:
		var bands := 9
		for band in range(bands):
			var band_y := viewport_size.y * float(band) / float(bands)
			var band_alpha := return_distortion * (0.025 + float(band % 3) * 0.018)
			draw_rect(Rect2(0, band_y, viewport_size.x, viewport_size.y / float(bands) * 0.6), Color(0.38, 0.75, 0.78, band_alpha), true)
	if flash_amount > 0.0:
		draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0.92, 0.82, 0.62, flash_amount), true)
