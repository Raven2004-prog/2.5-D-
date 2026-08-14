extends CanvasLayer
class_name GameUI

signal dialogue_finished(dialogue_id: String)
signal dialogue_choice(dialogue_id: String, choice_id: String)
signal folio_closed
signal pause_requested
signal resume_requested
signal title_requested
signal setting_changed(key: String, value: Variant)

const AshTheme := preload("res://scripts/ui_theme.gd")
const PortraitScene := preload("res://scripts/portrait.gd")
const FOLIO_MAP_PATH := "res://assets/ashen/ui/greyfen_folio_map.png"
const UI_ORNAMENT_PATH := "res://assets/ashen/ui/ashen_ui_ornament_atlas.png"
const VISUAL_QUALITY_IDS := ["high", "medium", "low"]

var dialogue_open := false
var folio_open := false

var _root: Control
var _objective_label: Label
var _chapter_label: Label
var _clock_label: Label
var _thread_label: RichTextLabel
var _prompt_panel: PanelContainer
var _condition_panel: PanelContainer
var _prompt_label: Label
var _health_bar: ProgressBar
var _stamina_bar: ProgressBar
var _notification_panel: PanelContainer
var _notification_label: Label
var _save_label: Label

var _dialogue_panel: PanelContainer
var _dialogue_ornament: TextureRect
var _dialogue_portrait: CharacterPortrait
var _speaker_label: Label
var _role_label: Label
var _dialogue_text: RichTextLabel
var _continue_label: Label
var _choice_box: VBoxContainer
var _dialogue_id := ""
var _pages := PackedStringArray()
var _page_index := 0

var _folio_panel: PanelContainer
var _folio_title: Label
var _folio_content: RichTextLabel
var _pause_panel: PanelContainer
var _pause_motion: CheckBox
var _pause_flash: CheckBox
var _pause_audio: CheckBox
var _pause_quality: OptionButton
var _pause_dof: CheckBox
var _pause_weather: HSlider
var _pause_weather_value: Label
var _notification_tween: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_build_ui()


func _unhandled_input(event: InputEvent) -> void:
	if _pause_panel and _pause_panel.visible and event.is_action_pressed("ui_cancel"):
		hide_pause()
		resume_requested.emit()
		get_viewport().set_input_as_handled()
	elif dialogue_open and (event.is_action_pressed("interact") or event.is_action_pressed("ui_accept")):
		if _choice_box.visible:
			return
		advance_dialogue()
		get_viewport().set_input_as_handled()
	elif folio_open and (event.is_action_pressed("folio") or event.is_action_pressed("ui_cancel")):
		hide_folio()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and not dialogue_open:
		pause_requested.emit()
		get_viewport().set_input_as_handled()


func set_objective(title: String, detail: String = "") -> void:
	_objective_label.text = title if detail.is_empty() else "%s\n%s" % [title, detail]
	_objective_label.queue_redraw()


func set_chapter(kicker: String, title: String) -> void:
	_chapter_label.text = "%s  ·  %s" % [kicker.to_upper(), title.to_upper()]


func set_clock(time_text: String, line_text: String) -> void:
	_clock_label.text = "%s\n%s" % [time_text, line_text]


func set_condition(health: float, maximum_health: float, stamina: float, maximum_stamina: float) -> void:
	_health_bar.max_value = maximum_health
	_health_bar.value = health
	_stamina_bar.max_value = maximum_stamina
	_stamina_bar.value = stamina


func set_health(health: float, maximum: float) -> void:
	_health_bar.max_value = maximum
	_health_bar.value = health


func set_stamina(stamina: float, maximum: float) -> void:
	_stamina_bar.max_value = maximum
	_stamina_bar.value = stamina


func set_threads(retained: Dictionary, present: Dictionary, resolved: Dictionary) -> void:
	var lines := PackedStringArray(["[color=#e7ad55][b]THE THREE FOUNDATIONS[/b][/color]"])
	for item in [["powder", "Powder beneath the granary"], ["signal", "Counterfeit horn cadence"], ["gate", "Jammed water gate"]]:
		var id: String = item[0]
		var marker := "◆" if resolved.get(id, false) else ("◇" if present.get(id, false) else ("↺" if retained.get(id, false) else "·"))
		var color := "#79b4ad" if resolved.get(id, false) else ("#e4c37a" if present.get(id, false) else ("#8fbfc3" if retained.get(id, false) else "#748089"))
		lines.append("[color=%s]%s %s[/color]" % [color, marker, item[1]])
	_thread_label.text = "\n".join(lines)


func sync_settings(settings: Dictionary) -> void:
	if _pause_quality:
		_select_quality(_pause_quality, str(settings.get("visual_quality", "high")))
	if _pause_motion:
		_pause_motion.set_pressed_no_signal(bool(settings.get("reduce_motion", false)))
	if _pause_flash:
		_pause_flash.set_pressed_no_signal(bool(settings.get("reduce_flash", false)))
	if _pause_dof:
		_pause_dof.set_pressed_no_signal(bool(settings.get("depth_of_field", true)))
	if _pause_weather:
		var density := clampf(float(settings.get("weather_density", 1.0)), 0.25, 1.35)
		_pause_weather.set_value_no_signal(density)
		_update_weather_label(density)
	if _pause_audio:
		_pause_audio.set_pressed_no_signal(bool(settings.get("master_audio", true)))


func show_prompt(text: String) -> void:
	_prompt_label.text = text
	_prompt_panel.visible = not text.is_empty()


func notify(text: String, tint: Color = Color("e7ad55"), seconds: float = 2.8) -> void:
	_notification_label.text = text
	_notification_label.add_theme_color_override("font_color", tint)
	_notification_panel.modulate = Color.WHITE
	_notification_panel.visible = true
	if _notification_tween and _notification_tween.is_valid():
		_notification_tween.kill()
	_notification_tween = create_tween()
	_notification_tween.tween_interval(seconds)
	_notification_tween.tween_property(_notification_panel, "modulate:a", 0.0, 0.35)
	_notification_tween.tween_callback(_notification_panel.hide)


func show_saved() -> void:
	_save_label.visible = true
	_save_label.modulate.a = 1.0
	var tween := create_tween()
	tween.tween_interval(0.9)
	tween.tween_property(_save_label, "modulate:a", 0.0, 0.4)
	tween.tween_callback(_save_label.hide)


func show_dialogue(id: String, data: Dictionary, choices: Array = []) -> void:
	_dialogue_id = id
	_pages = data.get("pages", PackedStringArray(["..."]))
	_page_index = 0
	dialogue_open = true
	_dialogue_panel.visible = true
	if _dialogue_ornament:
		_dialogue_ornament.visible = true
	_condition_panel.visible = false
	_prompt_panel.visible = false
	_speaker_label.text = str(data.get("speaker", ""))
	_role_label.text = str(data.get("role", ""))
	_dialogue_portrait.set_character(str(data.get("portrait", str(data.get("speaker", "narrator")).to_lower())))
	_clear_choices()
	if not choices.is_empty():
		_choice_box.set_meta("pending_choices", choices)
	else:
		_choice_box.remove_meta("pending_choices")
	_render_page()


func advance_dialogue() -> void:
	if not dialogue_open:
		return
	if _page_index < _pages.size() - 1:
		_page_index += 1
		_render_page()
		return
	if _choice_box.has_meta("pending_choices"):
		_build_choices(_choice_box.get_meta("pending_choices") as Array)
		_choice_box.remove_meta("pending_choices")
		return
	var completed_id := _dialogue_id
	hide_dialogue()
	dialogue_finished.emit(completed_id)


func hide_dialogue() -> void:
	dialogue_open = false
	_dialogue_panel.visible = false
	if _dialogue_ornament:
		_dialogue_ornament.visible = false
	_condition_panel.visible = true
	_dialogue_id = ""
	_pages = PackedStringArray()
	_clear_choices()


func show_folio(retained_entries: Array, present_entries: Array, people_entries: Array, scars: int) -> void:
	folio_open = true
	_folio_panel.visible = true
	_condition_panel.visible = false
	_prompt_panel.visible = false
	var text := PackedStringArray()
	text.append("[color=#e7ad55][font_size=22][b]MEMORY FOLIO[/b][/font_size][/color]")
	text.append("[color=#9db9bc]Facts written in rain-blue survive only in Evan. Present-line evidence is amber.[/color]\n")
	text.append("[color=#79b4ad][b]ECHOES — RETAINED[/b][/color]")
	if retained_entries.is_empty():
		text.append("[color=#748089]Nothing has returned with you yet.[/color]")
	else:
		for entry in retained_entries:
			text.append("[color=#b9d5d3]◆ %s[/color]" % str(entry))
	text.append("\n[color=#e4b45e][b]THIS LINE — PHYSICAL / SHARED[/b][/color]")
	if present_entries.is_empty():
		text.append("[color=#8f887a]No present-line proof recorded.[/color]")
	else:
		for entry in present_entries:
			text.append("[color=#e7dec9]◇ %s[/color]" % str(entry))
	text.append("\n[color=#d2a26a][b]PEOPLE — WHAT THEY CHOSE[/b][/color]")
	if people_entries.is_empty():
		text.append("[color=#8f887a]Trust has to exist in this line.[/color]")
	else:
		for entry in people_entries:
			text.append("• %s" % str(entry))
	text.append("\n[color=#b96b65]Soul scars: %d[/color]" % scars)
	_folio_content.text = "\n".join(text)
	_folio_content.scroll_to_line(0)


func hide_folio() -> void:
	folio_open = false
	_folio_panel.visible = false
	_condition_panel.visible = true
	folio_closed.emit()


func show_pause() -> void:
	_pause_panel.visible = true
	_condition_panel.visible = false
	_prompt_panel.visible = false
	var resume_button := _pause_panel.get_node("PauseBox/Resume") as Button
	resume_button.grab_focus()


func hide_pause() -> void:
	_pause_panel.visible = false
	_condition_panel.visible = true


func _render_page() -> void:
	_dialogue_text.text = _pages[_page_index] if _page_index < _pages.size() else "..."
	_continue_label.text = "E  CONTINUE" if _page_index < _pages.size() - 1 or not _choice_box.has_meta("pending_choices") else "E  CHOOSE"


func _build_choices(choices: Array) -> void:
	_clear_choices()
	_choice_box.visible = true
	for choice_value in choices:
		var choice: Dictionary = choice_value
		var button := Button.new()
		button.text = str(choice.get("text", "Choose"))
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 42
		button.pressed.connect(_select_choice.bind(str(choice.get("id", "choice"))))
		_choice_box.add_child(button)
	if _choice_box.get_child_count() > 0:
		(_choice_box.get_child(0) as Button).grab_focus()
	_continue_label.text = "CHOOSE WHAT EVAN SAYS"


func _select_choice(choice_id: String) -> void:
	var completed_id := _dialogue_id
	hide_dialogue()
	dialogue_choice.emit(completed_id, choice_id)


func _clear_choices() -> void:
	_choice_box.visible = false
	for child in _choice_box.get_children():
		child.queue_free()


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.theme = AshTheme.create_theme()
	add_child(_root)

	# Objective card.
	var objective_panel := PanelContainer.new()
	objective_panel.position = Vector2(24, 22)
	objective_panel.size = Vector2(390, 100)
	objective_panel.theme_type_variation = "AshGlassPanel"
	_root.add_child(objective_panel)
	var objective_box := VBoxContainer.new()
	objective_box.add_theme_constant_override("separation", 4)
	objective_panel.add_child(objective_box)
	_chapter_label = Label.new()
	_chapter_label.theme_type_variation = "AshKicker"
	_chapter_label.text = "CHAPTER 1  ·  THE BLINK"
	objective_box.add_child(_chapter_label)
	_objective_label = Label.new()
	_objective_label.text = "Find shelter from the rain."
	_objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective_label.add_theme_font_size_override("font_size", 17)
	objective_box.add_child(_objective_label)

	# Clock and threat foundation card.
	var status_panel := PanelContainer.new()
	status_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	status_panel.position = Vector2(-344, 22)
	status_panel.size = Vector2(320, 154)
	status_panel.theme_type_variation = "AshGlassPanel"
	_root.add_child(status_panel)
	var status_box := VBoxContainer.new()
	status_box.add_theme_constant_override("separation", 4)
	status_panel.add_child(status_box)
	_clock_label = Label.new()
	_clock_label.text = "4:20 PM\nTHE FIRST RAIN"
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clock_label.theme_type_variation = "AshKicker"
	status_box.add_child(_clock_label)
	_thread_label = RichTextLabel.new()
	_thread_label.bbcode_enabled = true
	_thread_label.fit_content = true
	_thread_label.scroll_active = false
	_thread_label.custom_minimum_size = Vector2(270, 84)
	_thread_label.text = "[color=#748089]Three hands move unseen.[/color]"
	status_box.add_child(_thread_label)

	# Condition bars.
	_condition_panel = PanelContainer.new()
	_condition_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_condition_panel.position = Vector2(24, -104)
	_condition_panel.size = Vector2(280, 78)
	_condition_panel.theme_type_variation = "AshGlassPanel"
	_root.add_child(_condition_panel)
	var condition_box := GridContainer.new()
	condition_box.columns = 2
	condition_box.add_theme_constant_override("h_separation", 8)
	condition_box.add_theme_constant_override("v_separation", 6)
	_condition_panel.add_child(condition_box)
	var health_label := Label.new()
	health_label.text = "BODY"
	health_label.theme_type_variation = "AshKicker"
	condition_box.add_child(health_label)
	_health_bar = _make_bar("BODY", Color("aa5b55"))
	condition_box.add_child(_health_bar)
	var stamina_label := Label.new()
	stamina_label.text = "BREATH"
	stamina_label.theme_type_variation = "AshKicker"
	condition_box.add_child(stamina_label)
	_stamina_bar = _make_bar("BREATH", Color("5c9996"))
	condition_box.add_child(_stamina_bar)
	set_condition(100, 100, 100, 100)

	_prompt_panel = PanelContainer.new()
	_prompt_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_prompt_panel.offset_left = 390
	_prompt_panel.offset_right = -390
	_prompt_panel.offset_top = -69
	_prompt_panel.offset_bottom = -23
	_prompt_panel.theme_type_variation = "AshGlassPanel"
	_root.add_child(_prompt_panel)
	_prompt_label = Label.new()
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_prompt_label.text = "E  INTERACT"
	_prompt_panel.add_child(_prompt_label)
	_prompt_panel.visible = false

	_save_label = Label.new()
	_save_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_save_label.position = Vector2(-152, -55)
	_save_label.size = Vector2(128, 28)
	_save_label.text = "◆  REMEMBERED"
	_save_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_save_label.theme_type_variation = "AshHint"
	_save_label.visible = false
	_root.add_child(_save_label)

	_notification_panel = PanelContainer.new()
	_notification_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_notification_panel.position = Vector2(-205, 182)
	_notification_panel.size = Vector2(410, 54)
	_notification_panel.theme_type_variation = "AshGlassPanel"
	_notification_panel.visible = false
	_root.add_child(_notification_panel)
	_notification_label = Label.new()
	_notification_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notification_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_notification_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notification_panel.add_child(_notification_label)

	_build_dialogue()
	_build_folio()
	_build_pause()


func _build_dialogue() -> void:
	_dialogue_panel = PanelContainer.new()
	_dialogue_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_dialogue_panel.offset_left = 40
	_dialogue_panel.offset_right = -40
	_dialogue_panel.offset_top = -246
	_dialogue_panel.offset_bottom = -24
	_dialogue_panel.theme_type_variation = "AshGlassPanel"
	_dialogue_panel.visible = false
	_root.add_child(_dialogue_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	_dialogue_panel.add_child(row)
	_dialogue_portrait = PortraitScene.new()
	_dialogue_portrait.custom_minimum_size = Vector2(150, 174)
	row.add_child(_dialogue_portrait)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 4)
	row.add_child(column)
	var speaker_row := HBoxContainer.new()
	column.add_child(speaker_row)
	_speaker_label = Label.new()
	_speaker_label.theme_type_variation = "AshSubtitle"
	_speaker_label.add_theme_font_size_override("font_size", 24)
	speaker_row.add_child(_speaker_label)
	_role_label = Label.new()
	_role_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_role_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_role_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_role_label.theme_type_variation = "AshHint"
	speaker_row.add_child(_role_label)
	_dialogue_text = RichTextLabel.new()
	_dialogue_text.bbcode_enabled = true
	_dialogue_text.fit_content = false
	_dialogue_text.scroll_active = false
	_dialogue_text.custom_minimum_size.y = 86
	_dialogue_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dialogue_text.add_theme_font_size_override("normal_font_size", 19)
	column.add_child(_dialogue_text)
	_choice_box = VBoxContainer.new()
	_choice_box.visible = false
	_choice_box.add_theme_constant_override("separation", 5)
	column.add_child(_choice_box)
	_continue_label = Label.new()
	_continue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_continue_label.theme_type_variation = "AshKicker"
	column.add_child(_continue_label)

	_dialogue_ornament = TextureRect.new()
	_dialogue_ornament.name = "AshenDialogueOrnament"
	_dialogue_ornament.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_dialogue_ornament.offset_left = 22
	_dialogue_ornament.offset_right = -22
	_dialogue_ornament.offset_top = -255
	_dialogue_ornament.offset_bottom = -15
	_dialogue_ornament.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_dialogue_ornament.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_dialogue_ornament.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_dialogue_ornament.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialogue_ornament.texture = _atlas_region(UI_ORNAMENT_PATH, Rect2(18, 15, 1500, 310))
	_dialogue_ornament.visible = false
	_root.add_child(_dialogue_ornament)


func _build_folio() -> void:
	_folio_panel = PanelContainer.new()
	_folio_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_folio_panel.offset_left = 80
	_folio_panel.offset_right = -80
	_folio_panel.offset_top = 46
	_folio_panel.offset_bottom = -46
	_folio_panel.theme_type_variation = "AshGlassPanel"
	_folio_panel.visible = false
	_root.add_child(_folio_panel)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	_folio_panel.add_child(body)
	var map_column := VBoxContainer.new()
	map_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_column.size_flags_stretch_ratio = 1.42
	map_column.add_theme_constant_override("separation", 6)
	body.add_child(map_column)
	var map_kicker := Label.new()
	map_kicker.text = "GREYFEN  ·  THE ROUTES MEMORY KEEPS"
	map_kicker.theme_type_variation = "AshKicker"
	map_column.add_child(map_kicker)
	var map := TextureRect.new()
	map.name = "GreyfenFolioMap"
	map.texture = load(FOLIO_MAP_PATH) as Texture2D
	map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	map.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map.custom_minimum_size = Vector2(420, 260)
	map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_column.add_child(map)
	var map_hint := Label.new()
	map_hint.text = "WARD-AMBER: shelter  ·  ASH-WHITE: remembered anomaly"
	map_hint.theme_type_variation = "AshHint"
	map_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_column.add_child(map_hint)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_stretch_ratio = 0.82
	column.add_theme_constant_override("separation", 10)
	body.add_child(column)
	_folio_title = Label.new()
	_folio_title.text = "WHAT THE RAIN COULD NOT TAKE"
	_folio_title.theme_type_variation = "AshKicker"
	column.add_child(_folio_title)
	_folio_content = RichTextLabel.new()
	_folio_content.bbcode_enabled = true
	_folio_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_folio_content.add_theme_font_size_override("normal_font_size", 18)
	column.add_child(_folio_content)
	var close_hint := Label.new()
	close_hint.text = "TAB / ESC  CLOSE FOLIO"
	close_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	close_hint.theme_type_variation = "AshHint"
	column.add_child(close_hint)


func _build_pause() -> void:
	_pause_panel = PanelContainer.new()
	_pause_panel.name = "PausePanel"
	_pause_panel.set_anchors_preset(Control.PRESET_CENTER)
	_pause_panel.position = Vector2(-280, -305)
	_pause_panel.size = Vector2(560, 610)
	_pause_panel.custom_minimum_size = Vector2(560, 610)
	_pause_panel.theme_type_variation = "AshGlassPanel"
	_pause_panel.visible = false
	_root.add_child(_pause_panel)
	var box := VBoxContainer.new()
	box.name = "PauseBox"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	_pause_panel.add_child(box)
	var kicker := Label.new()
	kicker.text = "THE RAIN WAITS"
	kicker.theme_type_variation = "AshKicker"
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(kicker)
	var heading := Label.new()
	heading.text = "PAUSED"
	heading.theme_type_variation = "AshTitle"
	heading.add_theme_font_size_override("font_size", 38)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(heading)
	var controls := Label.new()
	controls.text = "WASD / ARROWS  Move  ·  SHIFT  Sprint  ·  SPACE  Dodge\nE  Interact  ·  F  Shove  ·  Q  Focus  ·  TAB  Folio"
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls.theme_type_variation = "AshBody"
	controls.add_theme_font_size_override("font_size", 15)
	box.add_child(controls)
	var settings_heading := Label.new()
	settings_heading.text = "DISPLAY, COMFORT & SOUND"
	settings_heading.theme_type_variation = "AshKicker"
	settings_heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(settings_heading)
	var quality_row := _make_pause_setting_row("VISUAL QUALITY")
	_pause_quality = _make_quality_selector()
	_pause_quality.name = "VisualQuality"
	_pause_quality.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pause_quality.item_selected.connect(_pause_quality_selected)
	quality_row.add_child(_pause_quality)
	box.add_child(quality_row)
	_pause_motion = _make_pause_toggle("Reduce rain and camera motion", "reduce_motion")
	_pause_motion.name = "ReduceMotion"
	box.add_child(_pause_motion)
	_pause_flash = _make_pause_toggle("Reduce Return and lightning flashes", "reduce_flash")
	_pause_flash.name = "ReduceFlash"
	box.add_child(_pause_flash)
	_pause_dof = _make_pause_toggle("Depth of field", "depth_of_field")
	_pause_dof.name = "DepthOfField"
	box.add_child(_pause_dof)
	var weather_row := _make_pause_setting_row("WEATHER DENSITY")
	_pause_weather = HSlider.new()
	_pause_weather.name = "WeatherDensity"
	_pause_weather.min_value = 0.25
	_pause_weather.max_value = 1.35
	_pause_weather.step = 0.05
	_pause_weather.value = 1.0
	_pause_weather.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pause_weather.custom_minimum_size.x = 175
	_pause_weather.value_changed.connect(_pause_weather_changed)
	weather_row.add_child(_pause_weather)
	_pause_weather_value = Label.new()
	_pause_weather_value.name = "WeatherDensityValue"
	_pause_weather_value.custom_minimum_size.x = 48
	_pause_weather_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_pause_weather_value.theme_type_variation = "AshHint"
	weather_row.add_child(_pause_weather_value)
	_update_weather_label(_pause_weather.value)
	box.add_child(weather_row)
	_pause_audio = _make_pause_toggle("Procedural ambience and interface sound", "master_audio")
	_pause_audio.name = "MasterAudio"
	box.add_child(_pause_audio)
	var resume := Button.new()
	resume.name = "Resume"
	resume.text = "RESUME"
	resume.theme_type_variation = "AshPrimaryButton"
	resume.custom_minimum_size.y = 42
	resume.pressed.connect(_pause_resume)
	box.add_child(resume)
	var title := Button.new()
	title.name = "Title"
	title.text = "SAVE & RETURN TO TITLE"
	title.custom_minimum_size.y = 42
	title.pressed.connect(_pause_title)
	box.add_child(title)
	var hint := Label.new()
	hint.text = "Progress also saves after every Return and major choice."
	hint.theme_type_variation = "AshHint"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)


func _pause_resume() -> void:
	hide_pause()
	resume_requested.emit()


func _pause_title() -> void:
	hide_pause()
	title_requested.emit()


func _make_pause_toggle(label_text: String, key: String) -> CheckBox:
	var toggle := CheckBox.new()
	toggle.text = label_text
	toggle.toggled.connect(_pause_setting_toggled.bind(key))
	return toggle


func _pause_setting_toggled(enabled: bool, key: String) -> void:
	setting_changed.emit(key, enabled)


func _make_pause_setting_row(label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 166
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.theme_type_variation = "AshKicker"
	row.add_child(label)
	return row


func _make_quality_selector() -> OptionButton:
	var selector := OptionButton.new()
	for quality_id: String in VISUAL_QUALITY_IDS:
		selector.add_item(quality_id.to_upper())
		selector.set_item_metadata(selector.item_count - 1, quality_id)
	return selector


func _select_quality(selector: OptionButton, quality_id: String) -> void:
	var safe_id := quality_id if VISUAL_QUALITY_IDS.has(quality_id) else "high"
	for index in selector.item_count:
		if str(selector.get_item_metadata(index)) == safe_id:
			selector.select(index)
			return


func _pause_quality_selected(index: int) -> void:
	if not _pause_quality or index < 0 or index >= _pause_quality.item_count:
		return
	setting_changed.emit("visual_quality", str(_pause_quality.get_item_metadata(index)))


func _pause_weather_changed(value: float) -> void:
	var density := clampf(value, 0.25, 1.35)
	_update_weather_label(density)
	setting_changed.emit("weather_density", density)


func _update_weather_label(value: float) -> void:
	if _pause_weather_value:
		_pause_weather_value.text = "%d%%" % int(round(value * 100.0))


func _make_bar(label_text: String, fill_color: Color) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(188, 18)
	bar.show_percentage = true
	bar.tooltip_text = label_text
	var background := StyleBoxFlat.new()
	background.bg_color = Color("11171b")
	background.set_corner_radius_all(5)
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_color
	fill.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("background", background)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


func _atlas_region(path: String, region: Rect2) -> AtlasTexture:
	if not ResourceLoader.exists(path):
		return null
	var atlas := load(path) as Texture2D
	if atlas == null:
		return null
	var texture := AtlasTexture.new()
	texture.atlas = atlas
	texture.region = region
	return texture
