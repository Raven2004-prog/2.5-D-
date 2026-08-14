class_name TitleScreen
extends Control

signal new_game_requested
signal continue_requested
signal settings_requested
signal credits_requested
signal quit_requested

const AshTheme := preload("res://scripts/ui_theme.gd")
const TITLE_ART_PATH := "res://assets/art/greyfen_title.png"

const BACKGROUND_OVERSCAN := 18.0
const PARALLAX_DISTANCE := 8.0

const GRADIENT_SHADER := """
shader_type canvas_item;

uniform vec4 ash_color : source_color = vec4(0.043, 0.059, 0.075, 1.0);
uniform vec4 rain_color : source_color = vec4(0.192, 0.271, 0.325, 1.0);
uniform vec4 amber_color : source_color = vec4(0.722, 0.475, 0.247, 1.0);
uniform float panel_edge = 0.62;

void fragment() {
	vec2 uv = UV;
	float left_field = 1.0 - smoothstep(0.04, panel_edge, uv.x);
	float lower_field = smoothstep(0.45, 1.0, uv.y);
	float rain_field = smoothstep(0.0, 0.9, uv.x) * (1.0 - smoothstep(0.22, 0.78, uv.y));
	float horizon = exp(-pow((uv.y - 0.48) * 7.0, 2.0)) * smoothstep(0.44, 0.88, uv.x);
	vec3 tint = mix(ash_color.rgb, rain_color.rgb, rain_field * 0.24);
	tint = mix(tint, amber_color.rgb, horizon * 0.11);
	float alpha = clamp(0.10 + left_field * 0.76 + lower_field * 0.18, 0.0, 0.90);
	COLOR = vec4(tint, alpha);
}
"""

const VIGNETTE_SHADER := """
shader_type canvas_item;

uniform vec4 vignette_color : source_color = vec4(0.016, 0.022, 0.027, 1.0);

void fragment() {
	vec2 centered = (UV - vec2(0.5)) * vec2(1.18, 1.0);
	float edge = smoothstep(0.34, 0.78, length(centered));
	float top_bottom = smoothstep(0.52, 1.0, abs(UV.y - 0.5) * 2.0);
	float alpha = clamp(edge * 0.64 + top_bottom * 0.12, 0.0, 0.72);
	COLOR = vec4(vignette_color.rgb, alpha);
}
"""

@export var reduce_motion: bool = false:
	set(value):
		reduce_motion = value
		if is_node_ready():
			_apply_motion_preference()

@export var continue_available: bool = false:
	set(value):
		continue_available = value
		if is_node_ready():
			_refresh_continue_state()

var _background: TextureRect
var _gradient_material: ShaderMaterial
var _content_margin: MarginContainer
var _content_panel: PanelContainer
var _content_column: VBoxContainer
var _title_label: Label
var _subtitle_label: Label
var _body_label: Label
var _new_game_button: Button
var _continue_button: Button
var _buttons: Array[Button] = []
var _elapsed := 0.0
var _background_offset := Vector2.ZERO
var _entry_tween: Tween
var _ui_built := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	theme = AshTheme.create_theme()
	_build_interface()
	resized.connect(_update_responsive_layout)
	_update_responsive_layout()
	_refresh_continue_state()
	_apply_motion_preference()
	call_deferred("_focus_initial_button")


func set_continue_available(value: bool) -> void:
	continue_available = value


func set_reduce_motion(value: bool) -> void:
	reduce_motion = value


func _process(delta: float) -> void:
	if reduce_motion or not is_instance_valid(_background):
		return

	_elapsed += delta
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return

	var pointer := get_viewport().get_mouse_position() / viewport_size
	var pointer_offset := (pointer - Vector2(0.5, 0.5)) * -PARALLAX_DISTANCE
	var breathing_offset := Vector2(sin(_elapsed * 0.16), cos(_elapsed * 0.12)) * 1.6
	var target_offset := pointer_offset + breathing_offset
	_background_offset = _background_offset.lerp(target_offset, 1.0 - exp(-delta * 2.4))
	_apply_background_offset()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		quit_requested.emit()
		get_viewport().set_input_as_handled()


func _build_interface() -> void:
	if _ui_built:
		return
	_ui_built = true

	_background = TextureRect.new()
	_background.name = &"TitleArt"
	_background.texture = load(TITLE_ART_PATH) as Texture2D
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_background.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_background)

	var gradient_overlay := ColorRect.new()
	gradient_overlay.name = &"ResponsiveGradient"
	gradient_overlay.color = Color.WHITE
	gradient_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gradient_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_gradient_material = _shader_material(GRADIENT_SHADER)
	gradient_overlay.material = _gradient_material
	add_child(gradient_overlay)

	var vignette_overlay := ColorRect.new()
	vignette_overlay.name = &"Vignette"
	vignette_overlay.color = Color.WHITE
	vignette_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vignette_overlay.material = _shader_material(VIGNETTE_SHADER)
	add_child(vignette_overlay)

	_content_margin = MarginContainer.new()
	_content_margin.name = &"SafeArea"
	_content_margin.mouse_filter = Control.MOUSE_FILTER_PASS
	_content_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_content_margin)

	var horizontal_layout := HBoxContainer.new()
	horizontal_layout.name = &"HorizontalLayout"
	horizontal_layout.mouse_filter = Control.MOUSE_FILTER_PASS
	_content_margin.add_child(horizontal_layout)

	var vertical_center := CenterContainer.new()
	vertical_center.name = &"VerticalCenter"
	vertical_center.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	vertical_center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	horizontal_layout.add_child(vertical_center)

	_content_panel = PanelContainer.new()
	_content_panel.name = &"MenuPanel"
	_content_panel.theme_type_variation = &"AshGlassPanel"
	_content_panel.mouse_filter = Control.MOUSE_FILTER_PASS
	vertical_center.add_child(_content_panel)

	_content_column = VBoxContainer.new()
	_content_column.name = &"MenuColumn"
	_content_column.add_theme_constant_override(&"separation", 10)
	_content_panel.add_child(_content_column)

	var kicker := Label.new()
	kicker.name = &"Kicker"
	kicker.text = "A STORY OF GREYFEN"
	kicker.theme_type_variation = &"AshKicker"
	kicker.uppercase = true
	_content_column.add_child(kicker)

	_title_label = Label.new()
	_title_label.name = &"Title"
	_title_label.text = "ASH WITNESS"
	_title_label.theme_type_variation = &"AshTitle"
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content_column.add_child(_title_label)

	_subtitle_label = Label.new()
	_subtitle_label.name = &"Subtitle"
	_subtitle_label.text = "THE SAME RAIN"
	_subtitle_label.theme_type_variation = &"AshSubtitle"
	_subtitle_label.uppercase = true
	_content_column.add_child(_subtitle_label)

	var divider := HSeparator.new()
	divider.name = &"AmberDivider"
	divider.custom_minimum_size.y = 12.0
	_content_column.add_child(divider)

	_body_label = Label.new()
	_body_label.name = &"Promise"
	_body_label.text = "Knowledge survives. Trust must be earned again."
	_body_label.theme_type_variation = &"AshBody"
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content_column.add_child(_body_label)

	var menu_gap := Control.new()
	menu_gap.custom_minimum_size.y = 8.0
	menu_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_column.add_child(menu_gap)

	_new_game_button = _create_menu_button(&"NewGame", "NEW GAME", &"new_game_requested", true)
	_continue_button = _create_menu_button(&"Continue", "CONTINUE", &"continue_requested")
	var memory_button := _create_menu_button(
		&"MemoryOfGreyfen",
		"MEMORY OF GREYFEN",
		&"credits_requested"
	)
	memory_button.tooltip_text = "Credits and story notes"
	_create_menu_button(&"Settings", "SETTINGS", &"settings_requested")
	_create_menu_button(&"Quit", "QUIT", &"quit_requested")

	var footer_gap := Control.new()
	footer_gap.custom_minimum_size.y = 5.0
	footer_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content_column.add_child(footer_gap)

	var footer := Label.new()
	footer.name = &"Location"
	footer.text = "846 COVENANT AGE  /  ASH MARCH, CALDRIS"
	footer.theme_type_variation = &"AshHint"
	footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content_column.add_child(footer)

	var right_spacer := Control.new()
	right_spacer.name = &"ScenerySpace"
	right_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_layout.add_child(right_spacer)


func _create_menu_button(
	node_name: StringName,
	button_text: String,
	action_signal: StringName,
	primary := false
) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = button_text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.focus_mode = Control.FOCUS_ALL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.custom_minimum_size.y = 48.0
	button.theme_type_variation = &"AshPrimaryButton" if primary else &"AshMenuButton"
	button.pressed.connect(_emit_menu_signal.bind(action_signal))
	button.focus_entered.connect(_animate_button_focus.bind(button, true))
	button.focus_exited.connect(_animate_button_focus.bind(button, false))
	button.mouse_entered.connect(button.grab_focus)
	button.resized.connect(_center_button_pivot.bind(button))
	_content_column.add_child(button)
	_buttons.append(button)
	return button


func _emit_menu_signal(action_signal: StringName) -> void:
	emit_signal(action_signal)


func _refresh_continue_state() -> void:
	if not is_instance_valid(_continue_button):
		return
	_continue_button.disabled = not continue_available
	_continue_button.tooltip_text = "Resume the latest memory" if continue_available else "No remembered journey yet"
	_refresh_focus_chain()


func _refresh_focus_chain() -> void:
	var focusable: Array[Button] = []
	for button: Button in _buttons:
		if button.visible and not button.disabled:
			focusable.append(button)

	if focusable.is_empty():
		return

	for index: int in focusable.size():
		var current := focusable[index]
		var previous := focusable[(index - 1 + focusable.size()) % focusable.size()]
		var next := focusable[(index + 1) % focusable.size()]
		current.focus_neighbor_top = current.get_path_to(previous)
		current.focus_neighbor_bottom = current.get_path_to(next)
		current.focus_previous = current.get_path_to(previous)
		current.focus_next = current.get_path_to(next)


func _focus_initial_button() -> void:
	if continue_available and is_instance_valid(_continue_button):
		_continue_button.grab_focus()
	elif is_instance_valid(_new_game_button):
		_new_game_button.grab_focus()


func _animate_button_focus(button: Button, focused: bool) -> void:
	if not is_instance_valid(button):
		return
	_center_button_pivot(button)

	if reduce_motion:
		button.scale = Vector2.ONE
		return

	var target_scale := Vector2(1.018, 1.018) if focused else Vector2.ONE
	var tween := button.create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", target_scale, 0.13)


func _center_button_pivot(button: Button) -> void:
	if is_instance_valid(button):
		button.pivot_offset = button.size * 0.5


func _update_responsive_layout() -> void:
	if not is_instance_valid(_content_margin):
		return

	var viewport_size := size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		viewport_size = get_viewport_rect().size

	var short_side := minf(viewport_size.x, viewport_size.y)
	var horizontal_margin := int(clampf(viewport_size.x * 0.052, 24.0, 86.0))
	var vertical_margin := int(clampf(viewport_size.y * 0.055, 22.0, 64.0))
	_content_margin.add_theme_constant_override(&"margin_left", horizontal_margin)
	_content_margin.add_theme_constant_override(&"margin_right", horizontal_margin)
	_content_margin.add_theme_constant_override(&"margin_top", vertical_margin)
	_content_margin.add_theme_constant_override(&"margin_bottom", vertical_margin)

	var narrow := viewport_size.x / maxf(viewport_size.y, 1.0) < 1.35
	var preferred_width := clampf(viewport_size.x * (0.76 if narrow else 0.37), 292.0, 475.0)
	_content_panel.custom_minimum_size.x = preferred_width

	_title_label.add_theme_font_size_override(&"font_size", int(clampf(short_side * 0.082, 40.0, 68.0)))
	_subtitle_label.add_theme_font_size_override(&"font_size", int(clampf(short_side * 0.032, 19.0, 26.0)))
	_body_label.add_theme_font_size_override(&"font_size", int(clampf(short_side * 0.022, 15.0, 18.0)))

	if is_instance_valid(_gradient_material):
		_gradient_material.set_shader_parameter(&"panel_edge", 0.86 if narrow else 0.62)

	_apply_background_offset()


func _apply_motion_preference() -> void:
	if is_instance_valid(_entry_tween):
		_entry_tween.kill()

	set_process(not reduce_motion)
	if reduce_motion:
		_background_offset = Vector2.ZERO
		_apply_background_offset()
		if is_instance_valid(_content_panel):
			_content_panel.modulate = Color.WHITE
			_content_panel.position = Vector2.ZERO
		for button: Button in _buttons:
			button.scale = Vector2.ONE
	else:
		_play_entry_motion()


func _play_entry_motion() -> void:
	if not is_instance_valid(_content_panel):
		return

	_content_panel.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_content_panel.position = Vector2(-16.0, 0.0)
	_entry_tween = create_tween()
	_entry_tween.set_parallel(true)
	_entry_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_entry_tween.tween_property(_content_panel, "modulate", Color.WHITE, 0.52)
	_entry_tween.tween_property(_content_panel, "position", Vector2.ZERO, 0.62)


func _apply_background_offset() -> void:
	if not is_instance_valid(_background):
		return

	var motion := Vector2.ZERO if reduce_motion else _background_offset
	_background.offset_left = -BACKGROUND_OVERSCAN + motion.x
	_background.offset_top = -BACKGROUND_OVERSCAN + motion.y
	_background.offset_right = BACKGROUND_OVERSCAN + motion.x
	_background.offset_bottom = BACKGROUND_OVERSCAN + motion.y


func _shader_material(shader_code: String) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = shader_code
	var material := ShaderMaterial.new()
	material.shader = shader
	return material
