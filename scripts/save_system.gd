extends Node
## Versioned, JSON-only persistence for Ash at Greyfen.
##
## Gameplay systems provide plain Dictionaries containing JSON-safe values. The
## manager wraps them in a versioned envelope and replaces saves atomically.

signal save_completed(path: String)
signal save_failed(path: String, message: String)
signal save_loaded(data: Dictionary)
signal save_reset(path: String)

const CURRENT_SAVE_VERSION := 1
const SAVE_FORMAT := "ash_at_greyfen_save"
const DEFAULT_SAVE_PATH := "user://ash_at_greyfen_save.json"

@export_range(5.0, 600.0, 1.0) var autosave_interval_seconds := 45.0

var save_path := DEFAULT_SAVE_PATH
var last_error := ""

var _autosave_enabled := false
var _autosave_elapsed := 0.0
var _snapshot_provider: Callable


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	if not _autosave_enabled or not _snapshot_provider.is_valid():
		return
	_autosave_elapsed += delta
	if _autosave_elapsed < autosave_interval_seconds:
		return
	_autosave_elapsed = 0.0
	var snapshot: Variant = _snapshot_provider.call()
	if snapshot is Dictionary:
		autosave(snapshot)
	else:
		_set_error(save_path, "Autosave provider must return a Dictionary.")


func configure_autosave(
		snapshot_provider: Callable,
		interval_seconds: float = 45.0,
		enabled: bool = true
	) -> void:
	_snapshot_provider = snapshot_provider
	autosave_interval_seconds = clampf(interval_seconds, 5.0, 600.0)
	_autosave_enabled = enabled
	_autosave_elapsed = 0.0


func set_autosave_enabled(enabled: bool) -> void:
	_autosave_enabled = enabled
	_autosave_elapsed = 0.0


func autosave(state: Dictionary = {}, path_override: String = "") -> bool:
	var snapshot := state
	if snapshot.is_empty() and _snapshot_provider.is_valid():
		var provided: Variant = _snapshot_provider.call()
		if not provided is Dictionary:
			_set_error(_resolve_path(path_override), "Autosave provider must return a Dictionary.")
			return false
		snapshot = provided
	return save_game(snapshot, path_override)


func save_game(state: Dictionary, path_override: String = "") -> bool:
	var resolved_path := _resolve_path(path_override)
	if not _is_safe_save_path(resolved_path):
		_set_error(resolved_path, "Save paths must use the user:// location.")
		return false

	var envelope := {
		"format": SAVE_FORMAT,
		"version": CURRENT_SAVE_VERSION,
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"data": state.duplicate(true),
	}
	var json_text := JSON.stringify(envelope, "\t")
	if json_text.is_empty():
		_set_error(resolved_path, "Could not encode save data as JSON.")
		return false
	if not _write_atomic(resolved_path, json_text):
		return false

	last_error = ""
	save_completed.emit(resolved_path)
	return true


func can_continue(path_override: String = "") -> bool:
	return has_save(path_override)


func has_save(path_override: String = "") -> bool:
	var resolved_path := _resolve_path(path_override)
	return _is_safe_save_path(resolved_path) and FileAccess.file_exists(resolved_path)


func continue_game(path_override: String = "") -> Dictionary:
	var resolved_path := _resolve_path(path_override)
	if not _is_safe_save_path(resolved_path):
		_set_error(resolved_path, "Save paths must use the user:// location.")
		return {}
	if not FileAccess.file_exists(resolved_path):
		_set_error(resolved_path, "No save file exists yet.")
		return {}

	var file := FileAccess.open(resolved_path, FileAccess.READ)
	if file == null:
		_set_error(resolved_path, "Could not open save file (error %s)." % FileAccess.get_open_error())
		return {}
	var json_text := file.get_as_text()
	file.close()

	var parser := JSON.new()
	var parse_error := parser.parse(json_text)
	if parse_error != OK:
		_set_error(
			resolved_path,
			"Save JSON error on line %d: %s" % [parser.get_error_line(), parser.get_error_message()]
		)
		return {}
	if not parser.data is Dictionary:
		_set_error(resolved_path, "Save root must be a JSON object.")
		return {}

	var envelope: Dictionary = parser.data
	if str(envelope.get("format", "")) != SAVE_FORMAT:
		_set_error(resolved_path, "Unrecognized save format.")
		return {}
	var version_value: Variant = envelope.get("version", -1)
	if not _is_finite_number(version_value):
		_set_error(resolved_path, "Save version must be a number.")
		return {}
	var version := float(version_value)
	if version != floorf(version):
		_set_error(resolved_path, "Save version must be a whole number.")
		return {}
	if version > CURRENT_SAVE_VERSION:
		_set_error(resolved_path, "Save was created by a newer game version.")
		return {}
	if version < 1:
		_set_error(resolved_path, "Save version is too old to migrate safely.")
		return {}
	var data: Variant = envelope.get("data", {})
	if not data is Dictionary:
		_set_error(resolved_path, "Save payload must be a JSON object.")
		return {}

	last_error = ""
	var restored: Dictionary = data
	save_loaded.emit(restored)
	return restored


func _is_finite_number(value: Variant) -> bool:
	var value_type := typeof(value)
	return value_type in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


func reset_save(path_override: String = "") -> bool:
	var resolved_path := _resolve_path(path_override)
	if not _is_safe_save_path(resolved_path):
		_set_error(resolved_path, "Save paths must use the user:// location.")
		return false

	var success := true
	for suffix: String in ["", ".tmp", ".bak"]:
		var candidate: String = resolved_path + suffix
		if FileAccess.file_exists(candidate):
			var remove_error := DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))
			if remove_error != OK:
				success = false
				_set_error(candidate, "Could not remove save data (error %s)." % remove_error)
	if success:
		last_error = ""
		save_reset.emit(resolved_path)
	return success


func _write_atomic(path: String, contents: String) -> bool:
	var absolute_path := ProjectSettings.globalize_path(path)
	var temp_path := absolute_path + ".tmp"
	var backup_path := absolute_path + ".bak"
	var directory := absolute_path.get_base_dir()
	var directory_error := DirAccess.make_dir_recursive_absolute(directory)
	if directory_error != OK:
		_set_error(path, "Could not prepare save directory (error %s)." % directory_error)
		return false

	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		_set_error(path, "Could not create temporary save (error %s)." % FileAccess.get_open_error())
		return false
	file.store_string(contents)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		DirAccess.remove_absolute(temp_path)
		_set_error(path, "Could not finish writing save data (error %s)." % write_error)
		return false

	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(backup_path)
	var had_previous := FileAccess.file_exists(absolute_path)
	if had_previous:
		var backup_error := DirAccess.rename_absolute(absolute_path, backup_path)
		if backup_error != OK:
			DirAccess.remove_absolute(temp_path)
			_set_error(path, "Could not rotate previous save (error %s)." % backup_error)
			return false

	var commit_error := DirAccess.rename_absolute(temp_path, absolute_path)
	if commit_error != OK:
		if had_previous and FileAccess.file_exists(backup_path):
			DirAccess.rename_absolute(backup_path, absolute_path)
		DirAccess.remove_absolute(temp_path)
		_set_error(path, "Could not commit save data (error %s)." % commit_error)
		return false
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(backup_path)
	return true


func _resolve_path(path_override: String) -> String:
	return save_path if path_override.is_empty() else path_override


func _is_safe_save_path(path: String) -> bool:
	return path.begins_with("user://") and not path.contains("..")


func _set_error(path: String, message: String) -> void:
	last_error = message
	push_warning("SaveSystem: %s" % message)
	save_failed.emit(path, message)
