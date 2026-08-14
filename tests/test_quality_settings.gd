extends SceneTree
## Headless contract for title/pause display settings and persistence. Run with:
## Godot --headless --path <project> --script res://tests/test_quality_settings.gd

const MainScript := preload("res://scripts/main.gd")
const TEST_SAVE_PATH := "user://ash_at_greyfen_quality_settings_test.json"

var _failures := 0
var _original_save_path := ""
var _save_system: Variant
var _audio_manager: Variant


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("[quality-settings] title, pause, persistence, and legacy-world checks")
	_save_system = root.get_node_or_null("SaveSystem")
	_audio_manager = root.get_node_or_null("AudioManager")
	if _save_system == null or _audio_manager == null:
		printerr("[quality-settings] FAIL: project save/audio services are unavailable")
		quit(1)
		return
	_original_save_path = _save_system.save_path
	_save_system.save_path = TEST_SAVE_PATH
	_save_system.set_autosave_enabled(false)
	_save_system.reset_save(TEST_SAVE_PATH)

	await _test_pause_controls_and_variant_signal()
	await _test_legacy_world_accepts_display_values()
	await _test_title_controls_persist_and_merge()
	_cleanup_autoloads()
	# Uncapped headless frames can finish before the Dummy audio driver completes
	# a mix tick; allow stopped title/UI playbacks to release deterministically.
	await create_timer(0.12, true, false, true).timeout
	_save_system.reset_save(TEST_SAVE_PATH)
	_save_system.save_path = _original_save_path

	if _failures == 0:
		print("[quality-settings] PASS")
		quit(0)
	else:
		printerr("[quality-settings] FAIL: %d assertion(s)" % _failures)
		quit(1)


func _test_pause_controls_and_variant_signal() -> void:
	var ui := GameUI.new()
	ui.name = "QualitySettingsUI"
	root.add_child(ui)
	await process_frame
	await process_frame

	var quality := ui._pause_quality as OptionButton
	var dof := ui._pause_dof as CheckBox
	var weather := ui._pause_weather as HSlider
	_expect(quality != null and dof != null and weather != null, "pause exposes quality, depth of field, and weather controls")
	if quality != null:
		_expect(quality.item_count == 3, "pause quality selector has exactly High, Medium, and Low")
		_expect(_quality_ids(quality) == ["high", "medium", "low"], "pause quality values use stable save IDs")
	_expect(ui._pause_panel.size.y <= 648.0 and ui._pause_panel.custom_minimum_size.y <= 648.0, "pause panel stays within the 648px viewport")
	_expect(ui._root.find_child("GreyfenFolioMap", true, false) != null, "folio map artwork remains mounted")
	_expect(ui._root.find_child("AshenDialogueOrnament", true, false) != null, "dialogue ornament artwork remains mounted")

	var changes: Array[Dictionary] = []
	ui.setting_changed.connect(
		func(key: String, value: Variant) -> void: changes.append({"key": key, "value": value})
	)
	if quality != null:
		quality.select(1)
		quality.item_selected.emit(1)
	if dof != null:
		dof.toggled.emit(false)
	if weather != null:
		weather.value = 0.65
	_expect(_change_value(changes, "visual_quality") == "medium", "pause emits visual quality as a String")
	_expect(_change_value(changes, "depth_of_field") == false, "pause emits depth of field as a bool")
	var density_value: Variant = _change_value(changes, "weather_density")
	_expect(typeof(density_value) == TYPE_FLOAT and is_equal_approx(float(density_value), 0.65), "pause emits weather density as a float")

	var count_before_sync := changes.size()
	ui.sync_settings({
		"visual_quality": "low",
		"depth_of_field": false,
		"weather_density": 1.25,
		"reduce_motion": true,
		"reduce_flash": true,
		"master_audio": false,
	})
	_expect(str(quality.get_item_metadata(quality.selected)) == "low", "pause sync selects the saved quality without emitting")
	_expect(not dof.button_pressed and is_equal_approx(weather.value, 1.25), "pause sync restores DOF and density")
	_expect(ui._pause_weather_value.text == "125%", "pause gives weather density a readable percentage")
	_expect(changes.size() == count_before_sync, "settings synchronization never feeds changes back into persistence")

	ui.queue_free()
	await process_frame
	await process_frame


func _test_legacy_world_accepts_display_values() -> void:
	var state := AshGameState.new()
	state.current_line["stage"] = "return_three"
	state.current_line["spatial_checkpoint"] = state.checkpoint_for_stage("return_three")
	var world := GreyfenGameWorld.new()
	world.configure(state)
	root.add_child(world)
	await process_frame
	await process_frame
	await process_frame

	world._on_setting_changed("visual_quality", "medium")
	world._on_setting_changed("depth_of_field", false)
	world._on_setting_changed("weather_density", 0.55)
	world._on_setting_changed("future_visual_palette", "rainbound_amber")
	_expect(state.settings.get("visual_quality") == "medium", "legacy world stores a string quality value without a bool cast")
	_expect(state.settings.get("depth_of_field") == false, "legacy world stores the 3D-only DOF preference")
	_expect(is_equal_approx(float(state.settings.get("weather_density")), 0.55), "legacy world stores numeric weather density")
	_expect(state.settings.get("future_visual_palette") == "rainbound_amber", "legacy world safely preserves unknown future visual settings")
	_expect(is_equal_approx(world.rain.intensity, 0.55), "legacy rain previews the shared weather density")
	_expect(str(world.ui._pause_quality.get_item_metadata(world.ui._pause_quality.selected)) == "medium", "world resynchronizes the pause quality selector")
	_expect(not world.ui._pause_dof.button_pressed and is_equal_approx(world.ui._pause_weather.value, 0.55), "world resynchronizes non-boolean display values")

	world.queue_free()
	await process_frame
	await process_frame


func _test_title_controls_persist_and_merge() -> void:
	var disk_state := AshGameState.new()
	disk_state.settings["visual_quality"] = "high"
	disk_state.settings["depth_of_field"] = true
	disk_state.settings["weather_density"] = 1.0
	_expect(_save_system.save_game(disk_state.to_save_data()), "test journey is available for preference persistence")

	var main: Variant = MainScript.new()
	root.add_child(main)
	await process_frame
	await process_frame
	_expect(main.state != null and main._state_is_persistable, "title restores the available journey before editing preferences")
	main._show_settings()
	await process_frame
	var settings_panel := main.modal_layer.find_child("SettingsPanel", true, false) as PanelContainer
	var quality := settings_panel.find_child("VisualQuality", true, false) as OptionButton
	var dof := settings_panel.find_child("DepthOfField", true, false) as CheckBox
	var weather := settings_panel.find_child("WeatherDensity", true, false) as HSlider
	_expect(settings_panel != null and quality != null and dof != null and weather != null, "title Settings exposes all three visual controls")
	if settings_panel != null:
		_expect(settings_panel.size.y <= 648.0 and settings_panel.custom_minimum_size.y <= 648.0, "title Settings panel stays within the 648px viewport")
	if quality != null:
		_expect(_quality_ids(quality) == ["high", "medium", "low"], "title quality selector matches pause IDs")
		quality.select(1)
		quality.item_selected.emit(1)
	if dof != null:
		dof.toggled.emit(false)
	if weather != null:
		weather.value = 0.70
	_expect(main.state.settings.get("visual_quality") == "medium", "title selector routes its string value into live settings")
	_expect(main.state.settings.get("depth_of_field") == false, "title DOF toggle routes its bool value into live settings")
	_expect(is_equal_approx(float(main.state.settings.get("weather_density")), 0.70), "title weather slider routes its numeric value into live settings")

	var persisted_data: Dictionary = _save_system.continue_game()
	var persisted := AshGameState.new()
	_expect(persisted.load_save_data(persisted_data), "title preference autosave remains schema-valid")
	_expect(persisted.settings.get("visual_quality") == "medium", "title quality selection persists immediately")
	_expect(persisted.settings.get("depth_of_field") == false, "title DOF selection persists immediately")
	_expect(is_equal_approx(float(persisted.settings.get("weather_density")), 0.70), "title weather density persists immediately")

	# Recreate an older on-disk selection while keeping the live title choices.
	# Continue must merge the live choices after loading that journey.
	disk_state.settings["visual_quality"] = "high"
	disk_state.settings["depth_of_field"] = true
	disk_state.settings["weather_density"] = 1.0
	_expect(_save_system.save_game(disk_state.to_save_data()), "older on-disk preferences are staged for Continue merge")
	main._state_is_persistable = false
	main._continue_game()
	_expect(main.state.settings.get("visual_quality") == "medium", "Continue keeps the quality selected on the title screen")
	_expect(main.state.settings.get("depth_of_field") == false, "Continue keeps the title DOF selection")
	_expect(is_equal_approx(float(main.state.settings.get("weather_density")), 0.70), "Continue keeps the title weather selection")
	_expect(not _audio_manager._ambience_player.playing, "legacy title ambience stops when gameplay begins")
	_expect(_audio_manager.master_enabled and _audio_manager._ui_player != null, "stopping title ambience preserves the UI cue player")

	main._show_title()
	_expect(_audio_manager._ambience_player.playing, "returning to title restarts its restrained ambience")
	main.queue_free()
	await process_frame
	await process_frame


func _quality_ids(selector: OptionButton) -> Array[String]:
	var ids: Array[String] = []
	for index in selector.item_count:
		ids.append(str(selector.get_item_metadata(index)))
	return ids


func _change_value(changes: Array[Dictionary], key: String) -> Variant:
	for index in range(changes.size() - 1, -1, -1):
		if str(changes[index].get("key", "")) == key:
			return changes[index].get("value")
	return null


func _cleanup_autoloads() -> void:
	_save_system.set_autosave_enabled(false)
	_audio_manager.stop_ambience()
	if _audio_manager._ui_player:
		_audio_manager._ui_player.stop()
		_audio_manager._ui_player.stream = null
	if _audio_manager._ambience_player:
		_audio_manager._ambience_player.stop()
		_audio_manager._ambience_player.stream = null
	_audio_manager._ui_streams.clear()
	_audio_manager._ambience_stream = null


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	printerr("  assertion failed: %s" % message)
