extends Node

const TitleScene := preload("res://scripts/title_screen.gd")
const WorldScene := preload("res://scripts/game_world.gd")
const StateScene := preload("res://scripts/game_state.gd")
const AshTheme := preload("res://scripts/ui_theme.gd")

var title_screen: TitleScreen
var game_world: GreyfenGameWorld
var state: AshGameState
var modal_layer: CanvasLayer
var _state_is_persistable := false


func _ready() -> void:
	AudioManager.start_ambience()
	_prime_title_state_from_save()
	_show_title()


func _prime_title_state_from_save() -> void:
	if not SaveSystem.can_continue():
		return
	var data: Dictionary = SaveSystem.continue_game()
	if data.is_empty():
		return
	var saved_state := StateScene.new()
	if saved_state.load_save_data(data):
		state = saved_state
		_state_is_persistable = true


func _show_title() -> void:
	get_tree().paused = false
	_clear_content()
	SaveSystem.set_autosave_enabled(false)
	title_screen = TitleScene.new()
	title_screen.continue_available = SaveSystem.can_continue()
	if state:
		title_screen.reduce_motion = bool(state.settings.get("reduce_motion", false))
		AudioManager.set_master_enabled(bool(state.settings.get("master_audio", true)))
	title_screen.new_game_requested.connect(_start_new_game)
	title_screen.continue_requested.connect(_continue_game)
	title_screen.settings_requested.connect(_show_settings)
	title_screen.credits_requested.connect(_show_memory_of_greyfen)
	title_screen.quit_requested.connect(_quit_game)
	add_child(title_screen)


func _start_new_game() -> void:
	if SaveSystem.can_continue():
		AudioManager.play_ui("focus")
		var panel := _make_modal("BEGIN A NEW ACCOUNT?", "This will replace the current journey after a safe reset. The existing save is left untouched until you confirm.")
		var box := panel.get_meta("content") as VBoxContainer
		var confirm := Button.new()
		confirm.text = "START NEW GAME — REPLACE SAVE"
		confirm.theme_type_variation = "AshPrimaryButton"
		confirm.custom_minimum_size.y = 48
		confirm.pressed.connect(_begin_new_game)
		box.add_child(confirm)
		var keep := Button.new()
		keep.text = "KEEP CURRENT JOURNEY"
		keep.custom_minimum_size.y = 48
		keep.pressed.connect(_close_modal)
		box.add_child(keep)
		keep.grab_focus.call_deferred()
		return
	_begin_new_game()


func _begin_new_game() -> void:
	AudioManager.play_ui("confirm")
	var carried_settings: Dictionary = state.settings.duplicate(true) if state else {}
	if not SaveSystem.reset_save():
		_show_message("SAVE COULD NOT BE CLEARED", "The existing journey is still intact. Greyfen will not start a new account until that file can be safely replaced.")
		return
	state = StateScene.new()
	if not carried_settings.is_empty():
		state.settings.merge(carried_settings, true)
	_state_is_persistable = false
	_start_world()


func _continue_game() -> void:
	AudioManager.play_ui("confirm")
	var selected_settings: Dictionary = state.settings.duplicate(true) if state else {}
	var data: Dictionary = SaveSystem.continue_game()
	if data.is_empty():
		_show_message("THE THREAD IS BROKEN", "The remembered journey could not be opened. A new game remains safe to begin.")
		return
	var loaded_state := StateScene.new()
	if not loaded_state.load_save_data(data):
		_show_message("THE MEMORY DOES NOT FIT", "This save belongs to an incompatible story version. It has not been overwritten.")
		return
	if not selected_settings.is_empty():
		loaded_state.settings.merge(selected_settings, true)
	state = loaded_state
	_state_is_persistable = true
	_start_world()


func _start_world() -> void:
	_clear_content()
	AudioManager.set_master_enabled(bool(state.settings.get("master_audio", true)))
	game_world = WorldScene.new()
	game_world.configure(state)
	game_world.autosave_requested.connect(_save_snapshot)
	game_world.story_completed.connect(_show_ending)
	game_world.return_to_title_requested.connect(_show_title)
	add_child(game_world)
	SaveSystem.configure_autosave(_current_snapshot, 45.0, true)


func _save_snapshot(data: Dictionary) -> void:
	var saved := SaveSystem.autosave(data)
	_state_is_persistable = saved or _state_is_persistable
	if game_world and is_instance_valid(game_world) and game_world.ui:
		if saved:
			game_world.ui.show_saved()
		else:
			game_world.ui.notify("Progress could not be written. Your current session is still running.", Color("d17a64"), 4.0)


func _current_snapshot() -> Dictionary:
	if game_world and is_instance_valid(game_world):
		return game_world.snapshot_data()
	if state:
		return state.to_save_data()
	return {}


func _show_settings() -> void:
	AudioManager.play_ui("focus")
	var panel := _make_modal("SETTINGS", "Make Greyfen comfortable to read and watch.")
	var box := panel.get_meta("content") as VBoxContainer
	var reduce_motion := CheckBox.new()
	reduce_motion.text = "Reduce camera and interface motion"
	reduce_motion.button_pressed = bool(state.settings.get("reduce_motion", false)) if state else false
	reduce_motion.toggled.connect(_setting_toggled.bind("reduce_motion"))
	box.add_child(reduce_motion)
	var reduce_flash := CheckBox.new()
	reduce_flash.text = "Reduce Return and lightning flashes"
	reduce_flash.button_pressed = bool(state.settings.get("reduce_flash", false)) if state else false
	reduce_flash.toggled.connect(_setting_toggled.bind("reduce_flash"))
	box.add_child(reduce_flash)
	var sound := CheckBox.new()
	sound.text = "Procedural ambience and interface sound"
	sound.button_pressed = bool(state.settings.get("master_audio", AudioManager.master_enabled)) if state else AudioManager.master_enabled
	sound.toggled.connect(_sound_toggled)
	box.add_child(sound)
	var note := Label.new()
	note.text = "All dialogue is captioned. Gameplay uses no color-only objective states."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.theme_type_variation = "AshBody"
	box.add_child(note)
	_add_close_button(box)


func _setting_toggled(enabled: bool, key: String) -> void:
	if state == null:
		state = StateScene.new()
	state.settings[key] = enabled
	if title_screen and key == "reduce_motion":
		title_screen.reduce_motion = enabled
	AudioManager.play_ui("confirm")
	_persist_title_preferences()


func _sound_toggled(enabled: bool) -> void:
	if state == null:
		state = StateScene.new()
	state.settings["master_audio"] = enabled
	AudioManager.set_master_enabled(enabled)
	if enabled:
		AudioManager.play_ui("confirm")
	_persist_title_preferences()


func _persist_title_preferences() -> void:
	if _state_is_persistable and state and SaveSystem.can_continue():
		SaveSystem.autosave(state.to_save_data())


func _show_memory_of_greyfen() -> void:
	AudioManager.play_ui("focus")
	var panel := _make_modal("MEMORY OF GREYFEN", "Story notes, authorship, and scope")
	var box := panel.get_meta("content") as VBoxContainer
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.custom_minimum_size = Vector2(560, 280)
	text.text = "[color=#e7ad55][b]ASH WITNESS: THE SAME RAIN[/b][/color]\n\nA complete compact adaptation of Arc 1, ‘Ash at Greyfen,’ from the Evara planning bible. The wider novel remains protected beyond this opening story.\n\n[color=#79b4ad][b]ORIGINAL PRODUCTION[/b][/color]\nGame design, code-native characters, UI, fortress art, VFX, procedural ambience, icon, and implementation were created for this project. The painterly title artwork was generated specifically for Greyfen with the built-in image-generation tool.\n\n[color=#d9b870][b]CONTENT NOTE[/b][/color]\nThe story discusses death, panic, prejudice, coercion, and self-destructive choices without graphic imagery. Its central answer is collaborative courage."
	box.add_child(text)
	_add_close_button(box)


func _show_message(heading: String, body: String) -> void:
	var panel := _make_modal(heading, body)
	var box := panel.get_meta("content") as VBoxContainer
	_add_close_button(box)


func _show_ending(completed_state: AshGameState) -> void:
	state = completed_state
	var ending_saved := SaveSystem.autosave(state.to_save_data())
	_state_is_persistable = ending_saved or _state_is_persistable
	SaveSystem.set_autosave_enabled(false)
	_clear_content()

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = AshTheme.create_theme()
	add_child(root)
	var art := TextureRect.new()
	art.texture = load("res://assets/art/greyfen_title.png")
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(art)
	var veil := ColorRect.new()
	veil.color = Color(0.025, 0.035, 0.043, 0.74)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(veil)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "AshGlassPanel"
	panel.custom_minimum_size = Vector2(650, 470)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	var kicker := Label.new()
	kicker.text = "GREYFEN HOLDS"
	kicker.theme_type_variation = "AshKicker"
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(kicker)
	var heading := Label.new()
	heading.text = "ONE SURVIVING ACCOUNT"
	heading.theme_type_variation = "AshTitle"
	heading.add_theme_font_size_override("font_size", 48)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(heading)
	var body := Label.new()
	body.text = "The powder never lights. The true horn carries. Refuge Row shelters inside a wall built to exclude it.\n\nMara stakes her crown claim on Evan and Kesh's testimony. Evan signs—not because he is fearless, but because seven people chose the risk together.\n\nAt dawn, the road to Lysford opens."
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.theme_type_variation = "AshBody"
	box.add_child(body)
	var stat := Label.new()
	stat.text = "%d Returns remembered  ·  %d soul scars carried  ·  one surviving line chosen" % [int(state.retained.get("death_count", 0)), int(state.retained.get("soul_scars", 0))]
	stat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stat.theme_type_variation = "AshSubtitle"
	stat.add_theme_font_size_override("font_size", 18)
	if not ending_saved:
		stat.text += "\nProgress could not be written; leave this screen open until storage is available."
		stat.add_theme_color_override("font_color", Color("d17a64"))
	box.add_child(stat)
	var again := Button.new()
	again.text = "RETURN TO THE TITLE"
	again.theme_type_variation = "AshPrimaryButton"
	again.custom_minimum_size.y = 50
	again.pressed.connect(_show_title)
	box.add_child(again)
	again.grab_focus.call_deferred()


func _make_modal(heading_text: String, body_text: String) -> PanelContainer:
	_close_modal()
	if title_screen:
		title_screen.set_process_unhandled_input(false)
	modal_layer = CanvasLayer.new()
	modal_layer.layer = 100
	add_child(modal_layer)
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.015, 0.02, 0.88)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.theme = AshTheme.create_theme()
	modal_layer.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.theme = AshTheme.create_theme()
	modal_layer.add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = "AshGlassPanel"
	panel.custom_minimum_size = Vector2(640, 390)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	var kicker := Label.new()
	kicker.text = "ASH WITNESS"
	kicker.theme_type_variation = "AshKicker"
	box.add_child(kicker)
	var heading := Label.new()
	heading.text = heading_text
	heading.theme_type_variation = "AshSubtitle"
	heading.add_theme_font_size_override("font_size", 32)
	box.add_child(heading)
	if not body_text.is_empty():
		var body := Label.new()
		body.text = body_text
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.theme_type_variation = "AshBody"
		box.add_child(body)
	panel.set_meta("content", box)
	return panel


func _add_close_button(box: VBoxContainer) -> void:
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	var close := Button.new()
	close.text = "BACK"
	close.theme_type_variation = "AshPrimaryButton"
	close.custom_minimum_size.y = 48
	close.pressed.connect(_close_modal)
	box.add_child(close)
	close.grab_focus.call_deferred()


func _close_modal() -> void:
	if modal_layer and is_instance_valid(modal_layer):
		modal_layer.queue_free()
	modal_layer = null
	if title_screen:
		title_screen.set_process_unhandled_input(true)
		title_screen.call_deferred("_focus_initial_button")


func _clear_content() -> void:
	_close_modal()
	for child in get_children():
		child.queue_free()
	title_screen = null
	game_world = null


func _quit_game() -> void:
	AudioManager.play_ui("cancel")
	get_tree().quit()
