class_name AshUITheme
extends RefCounted

## Programmatic theme shared by menus, dialogue, the Memory Folio, and HUD panels.
## Keeping the palette here makes later art passes consistent without coupling UI
## scenes to a particular font or imported theme resource.

const ASH_BLACK := Color("#0b0f13")
const ASH_CHARCOAL := Color("#151b21")
const RAIN_BLUE := Color("#314553")
const RAIN_BLUE_LIGHT := Color("#607988")
const FEN_TEAL := Color("#456f6c")
const BRONZE := Color("#b8793f")
const AMBER := Color("#e7ad55")
const AMBER_BRIGHT := Color("#ffd17a")
const PARCHMENT := Color("#e7dec9")
const PARCHMENT_MUTED := Color("#b9b2a2")
const DANGER_RED := Color("#9b4944")
const INK := Color("#17191b")


static func create_theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 18

	_configure_labels(result)
	_configure_buttons(result)
	_configure_panels(result)
	_configure_inputs(result)
	_configure_misc(result)

	return result


static func palette() -> Dictionary:
	return {
		&"ash_black": ASH_BLACK,
		&"ash_charcoal": ASH_CHARCOAL,
		&"rain_blue": RAIN_BLUE,
		&"rain_blue_light": RAIN_BLUE_LIGHT,
		&"fen_teal": FEN_TEAL,
		&"bronze": BRONZE,
		&"amber": AMBER,
		&"amber_bright": AMBER_BRIGHT,
		&"parchment": PARCHMENT,
		&"parchment_muted": PARCHMENT_MUTED,
		&"danger_red": DANGER_RED,
		&"ink": INK,
	}


static func _configure_labels(target: Theme) -> void:
	target.set_color(&"font_color", &"Label", PARCHMENT)
	target.set_color(&"font_shadow_color", &"Label", Color(ASH_BLACK, 0.86))
	target.set_constant(&"shadow_offset_x", &"Label", 1)
	target.set_constant(&"shadow_offset_y", &"Label", 2)

	_register_variation(target, &"AshKicker", &"Label")
	target.set_color(&"font_color", &"AshKicker", AMBER)
	target.set_font_size(&"font_size", &"AshKicker", 14)
	target.set_constant(&"outline_size", &"AshKicker", 3)
	target.set_color(&"font_outline_color", &"AshKicker", Color(ASH_BLACK, 0.78))

	_register_variation(target, &"AshTitle", &"Label")
	target.set_color(&"font_color", &"AshTitle", PARCHMENT)
	target.set_font_size(&"font_size", &"AshTitle", 64)
	target.set_constant(&"outline_size", &"AshTitle", 7)
	target.set_color(&"font_outline_color", &"AshTitle", Color(ASH_BLACK, 0.92))
	target.set_constant(&"shadow_offset_x", &"AshTitle", 3)
	target.set_constant(&"shadow_offset_y", &"AshTitle", 5)
	target.set_color(&"font_shadow_color", &"AshTitle", Color(ASH_BLACK, 0.82))

	_register_variation(target, &"AshSubtitle", &"Label")
	target.set_color(&"font_color", &"AshSubtitle", AMBER_BRIGHT)
	target.set_font_size(&"font_size", &"AshSubtitle", 24)
	target.set_constant(&"outline_size", &"AshSubtitle", 4)
	target.set_color(&"font_outline_color", &"AshSubtitle", Color(ASH_BLACK, 0.85))

	_register_variation(target, &"AshBody", &"Label")
	target.set_color(&"font_color", &"AshBody", PARCHMENT_MUTED)
	target.set_font_size(&"font_size", &"AshBody", 17)

	_register_variation(target, &"AshHint", &"Label")
	target.set_color(&"font_color", &"AshHint", Color(PARCHMENT_MUTED, 0.82))
	target.set_font_size(&"font_size", &"AshHint", 13)

	target.set_color(&"default_color", &"RichTextLabel", PARCHMENT)
	target.set_color(&"font_shadow_color", &"RichTextLabel", Color(ASH_BLACK, 0.72))
	target.set_color(&"font_selected_color", &"RichTextLabel", ASH_BLACK)
	target.set_color(&"selection_color", &"RichTextLabel", AMBER)
	target.set_font_size(&"normal_font_size", &"RichTextLabel", 18)


static func _configure_buttons(target: Theme) -> void:
	var normal := _flat_style(Color(ASH_CHARCOAL, 0.82), Color(RAIN_BLUE_LIGHT, 0.38), 1, 8, 17, 13)
	var hover := _flat_style(Color(RAIN_BLUE, 0.92), Color(AMBER, 0.66), 1, 8, 17, 13)
	var pressed := _flat_style(Color(FEN_TEAL, 0.94), AMBER, 1, 8, 17, 13)
	var disabled := _flat_style(Color(ASH_CHARCOAL, 0.48), Color(RAIN_BLUE, 0.22), 1, 8, 17, 13)
	var focus := _flat_style(Color.TRANSPARENT, AMBER_BRIGHT, 2, 8, 15, 11)

	target.set_stylebox(&"normal", &"Button", normal)
	target.set_stylebox(&"hover", &"Button", hover)
	target.set_stylebox(&"pressed", &"Button", pressed)
	target.set_stylebox(&"hover_pressed", &"Button", pressed)
	target.set_stylebox(&"disabled", &"Button", disabled)
	target.set_stylebox(&"focus", &"Button", focus)
	target.set_color(&"font_color", &"Button", PARCHMENT)
	target.set_color(&"font_hover_color", &"Button", AMBER_BRIGHT)
	target.set_color(&"font_pressed_color", &"Button", ASH_BLACK)
	target.set_color(&"font_focus_color", &"Button", AMBER_BRIGHT)
	target.set_color(&"font_disabled_color", &"Button", Color(PARCHMENT_MUTED, 0.42))
	target.set_font_size(&"font_size", &"Button", 18)
	target.set_constant(&"outline_size", &"Button", 3)
	target.set_color(&"font_outline_color", &"Button", Color(ASH_BLACK, 0.75))

	_register_variation(target, &"AshMenuButton", &"Button")
	target.set_font_size(&"font_size", &"AshMenuButton", 20)
	target.set_constant(&"h_separation", &"AshMenuButton", 12)

	_register_variation(target, &"AshPrimaryButton", &"Button")
	target.set_stylebox(
		&"normal",
		&"AshPrimaryButton",
		_flat_style(Color(BRONZE, 0.88), Color(AMBER_BRIGHT, 0.76), 1, 8, 17, 13)
	)
	target.set_stylebox(
		&"hover",
		&"AshPrimaryButton",
		_flat_style(Color(AMBER, 0.96), AMBER_BRIGHT, 1, 8, 17, 13)
	)
	target.set_stylebox(
		&"pressed",
		&"AshPrimaryButton",
		_flat_style(Color(AMBER_BRIGHT, 0.98), PARCHMENT, 1, 8, 17, 13)
	)
	target.set_color(&"font_color", &"AshPrimaryButton", ASH_BLACK)
	target.set_color(&"font_hover_color", &"AshPrimaryButton", ASH_BLACK)
	target.set_color(&"font_pressed_color", &"AshPrimaryButton", INK)
	target.set_color(&"font_focus_color", &"AshPrimaryButton", ASH_BLACK)
	target.set_font_size(&"font_size", &"AshPrimaryButton", 20)


static func _configure_panels(target: Theme) -> void:
	target.set_stylebox(
		&"panel",
		&"Panel",
		_flat_style(Color(ASH_CHARCOAL, 0.88), Color(RAIN_BLUE_LIGHT, 0.38), 1, 10, 20, 20)
	)
	target.set_stylebox(
		&"panel",
		&"PanelContainer",
		_flat_style(Color(ASH_CHARCOAL, 0.88), Color(RAIN_BLUE_LIGHT, 0.38), 1, 10, 20, 20)
	)

	_register_variation(target, &"AshGlassPanel", &"PanelContainer")
	target.set_stylebox(
		&"panel",
		&"AshGlassPanel",
		_flat_style(Color(ASH_BLACK, 0.69), Color(AMBER, 0.24), 1, 14, 24, 24)
	)

	_register_variation(target, &"AshParchmentPanel", &"PanelContainer")
	target.set_stylebox(
		&"panel",
		&"AshParchmentPanel",
		_flat_style(Color(PARCHMENT, 0.97), Color(BRONZE, 0.78), 1, 8, 22, 20)
	)


static func _configure_inputs(target: Theme) -> void:
	var normal := _flat_style(Color(ASH_BLACK, 0.76), Color(RAIN_BLUE_LIGHT, 0.44), 1, 7, 12, 10)
	var focus := _flat_style(Color(ASH_BLACK, 0.9), AMBER, 2, 7, 11, 9)
	var read_only := _flat_style(Color(ASH_CHARCOAL, 0.58), Color(RAIN_BLUE, 0.3), 1, 7, 12, 10)

	for control_type: StringName in [&"LineEdit", &"TextEdit"]:
		target.set_stylebox(&"normal", control_type, normal)
		target.set_stylebox(&"focus", control_type, focus)
		target.set_stylebox(&"read_only", control_type, read_only)
		target.set_color(&"font_color", control_type, PARCHMENT)
		target.set_color(&"font_uneditable_color", control_type, PARCHMENT_MUTED)
		target.set_color(&"caret_color", control_type, AMBER_BRIGHT)
		target.set_color(&"selection_color", control_type, Color(FEN_TEAL, 0.78))
		target.set_font_size(&"font_size", control_type, 18)

	target.set_color(&"font_color", &"CheckBox", PARCHMENT)
	target.set_color(&"font_hover_color", &"CheckBox", AMBER_BRIGHT)
	target.set_color(&"font_pressed_color", &"CheckBox", AMBER_BRIGHT)
	target.set_color(&"font_focus_color", &"CheckBox", PARCHMENT)
	target.set_font_size(&"font_size", &"CheckBox", 17)

	target.set_color(&"font_color", &"OptionButton", PARCHMENT)
	target.set_color(&"font_hover_color", &"OptionButton", AMBER_BRIGHT)
	target.set_font_size(&"font_size", &"OptionButton", 17)


static func _configure_misc(target: Theme) -> void:
	var separator := StyleBoxLine.new()
	separator.color = Color(AMBER, 0.58)
	separator.thickness = 1
	separator.grow_begin = 2.0
	separator.grow_end = 2.0
	target.set_stylebox(&"separator", &"HSeparator", separator)

	target.set_color(&"grabber_area", &"HSlider", Color(RAIN_BLUE, 0.9))
	target.set_color(&"grabber_area_highlight", &"HSlider", Color(FEN_TEAL, 0.96))

	target.set_stylebox(
		&"panel",
		&"TooltipPanel",
		_flat_style(Color(ASH_BLACK, 0.96), Color(AMBER, 0.62), 1, 6, 10, 8)
	)
	target.set_color(&"font_color", &"TooltipLabel", PARCHMENT)
	target.set_font_size(&"font_size", &"TooltipLabel", 14)


static func _register_variation(target: Theme, variation: StringName, base_type: StringName) -> void:
	target.set_type_variation(variation, base_type)


static func _flat_style(
	background: Color,
	border: Color,
	border_width: int,
	corner_radius: int,
	horizontal_padding: int,
	vertical_padding: int
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.border_width_left = border_width
	style.border_width_top = border_width
	style.border_width_right = border_width
	style.border_width_bottom = border_width
	style.corner_radius_top_left = corner_radius
	style.corner_radius_top_right = corner_radius
	style.corner_radius_bottom_right = corner_radius
	style.corner_radius_bottom_left = corner_radius
	style.content_margin_left = float(horizontal_padding)
	style.content_margin_right = float(horizontal_padding)
	style.content_margin_top = float(vertical_padding)
	style.content_margin_bottom = float(vertical_padding)
	style.anti_aliasing = true
	return style
