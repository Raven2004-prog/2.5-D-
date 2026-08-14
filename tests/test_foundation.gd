extends SceneTree
## Headless foundation check. Run with:
## Godot --headless --path <project> --script res://tests/test_foundation.gd

const SaveSystemScript := preload("res://scripts/save_system.gd")
const AudioManagerScript := preload("res://scripts/audio_manager.gd")
const TEST_SAVE_PATH := "user://ash_at_greyfen_foundation_test.json"

var _failures := 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("[foundation] Ash at Greyfen headless checks")
	_test_project_boot_contract()
	_test_save_roundtrip()
	_test_procedural_audio_contract()
	if _failures == 0:
		print("[foundation] PASS")
		quit(0)
	else:
		printerr("[foundation] FAIL: %d assertion(s)" % _failures)
		quit(1)


func _test_project_boot_contract() -> void:
	_expect(ProjectSettings.get_setting("application/config/name") == "Ash at Greyfen", "project name loads")
	_expect(ProjectSettings.get_setting("display/window/size/viewport_width") == 1152, "viewport width is 1152")
	_expect(ProjectSettings.get_setting("display/window/size/viewport_height") == 648, "viewport height is 648")
	_expect(ProjectSettings.get_setting("rendering/renderer/rendering_method") == "gl_compatibility", "Compatibility renderer is active")
	_expect(FileAccess.file_exists("res://icon.svg"), "original icon is available")
	_expect(ProjectSettings.get_setting("autoload/SaveSystem") == "*res://scripts/save_system.gd", "SaveSystem autoload is registered")
	_expect(ProjectSettings.get_setting("autoload/AudioManager") == "*res://scripts/audio_manager.gd", "AudioManager autoload is registered")
	for action in [
		&"move_left", &"move_right", &"move_up", &"move_down", &"interact",
		&"shove", &"focus", &"dodge", &"sprint", &"pause"
	]:
		_expect(InputMap.has_action(action), "input action '%s' exists" % action)
		_expect(not InputMap.action_get_events(action).is_empty(), "input action '%s' has a binding" % action)
	_expect(InputMap.action_get_events(&"shove").size() == 2, "shove supports keyboard and mouse")
	_expect(_action_has_key(&"move_left", KEY_A) and _action_has_key(&"move_left", KEY_LEFT), "move left uses A / Left")
	_expect(_action_has_key(&"move_right", KEY_D) and _action_has_key(&"move_right", KEY_RIGHT), "move right uses D / Right")
	_expect(_action_has_key(&"move_up", KEY_W) and _action_has_key(&"move_up", KEY_UP), "move up uses W / Up")
	_expect(_action_has_key(&"move_down", KEY_S) and _action_has_key(&"move_down", KEY_DOWN), "move down uses S / Down")
	_expect(_action_has_key(&"interact", KEY_E), "interact uses E")
	_expect(_action_has_key(&"shove", KEY_F) and _action_has_mouse_button(&"shove", MOUSE_BUTTON_LEFT), "shove uses F / Mouse Left")
	_expect(_action_has_key(&"focus", KEY_Q), "focus uses Q")
	_expect(_action_has_key(&"dodge", KEY_SPACE), "dodge uses Space")
	_expect(_action_has_key(&"sprint", KEY_SHIFT), "sprint uses Shift")
	_expect(_action_has_key(&"pause", KEY_ESCAPE), "pause uses Escape")


func _test_save_roundtrip() -> void:
	var saves := SaveSystemScript.new()
	saves.save_path = TEST_SAVE_PATH
	saves.reset_save()
	var source_state := {
		"chapter": "arrival",
		"checkpoint": {"id": "greyfen_gate", "position": [128.5, 64.25]},
		"flags": {"met_mara": true, "ward_lit": false},
		"inventory": ["cracked_phone", "ash_key"],
		"play_seconds": 12.5,
	}
	_expect(saves.autosave(source_state), "autosave writes JSON state")
	_expect(saves.can_continue(), "continue becomes available")

	var raw_text := FileAccess.get_file_as_string(TEST_SAVE_PATH)
	var raw: Variant = JSON.parse_string(raw_text)
	_expect(raw is Dictionary, "save file contains a JSON object")
	if raw is Dictionary:
		_expect(raw.get("format") == "ash_at_greyfen_save", "save format tag is present")
		_expect(int(raw.get("version", -1)) == 1, "save version is current")

	var updated_state: Dictionary = source_state.duplicate(true)
	updated_state["play_seconds"] = 19.75
	updated_state["flags"]["ward_lit"] = true
	_expect(saves.autosave(updated_state), "autosave atomically replaces prior state")
	var restored: Dictionary = saves.continue_game()
	_expect(restored == updated_state, "latest save data survives a roundtrip")
	_expect(not FileAccess.file_exists(TEST_SAVE_PATH + ".bak"), "successful save leaves no backup artifact")
	_expect(saves.reset_save(), "reset removes save data")
	_expect(not saves.can_continue(), "continue is unavailable after reset")
	saves.free()


func _test_procedural_audio_contract() -> void:
	var audio := AudioManagerScript.new()
	get_root().add_child(audio)
	_expect(audio.has_cue(&"focus"), "procedural focus cue is built")
	_expect(audio.has_cue(&"confirm"), "procedural confirm cue is built")
	_expect(audio.has_cue(&"cancel"), "procedural cancel cue is built")
	_expect(audio.has_cue(&"warning"), "procedural warning cue is built")
	audio.free()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("  [ok] %s" % label)
	else:
		_failures += 1
		printerr("  [FAIL] %s" % label)


func _action_has_key(action: StringName, keycode: int) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key_event := event as InputEventKey
			if key_event.keycode == keycode or key_event.physical_keycode == keycode:
				return true
	return false


func _action_has_mouse_button(action: StringName, button: int) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == button:
			return true
	return false
