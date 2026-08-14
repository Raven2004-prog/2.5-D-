extends RefCounted
class_name AshGameState

const SCHEMA_VERSION := 1
const CONTENT_VERSION := "greyfen-arc1-1.0"

const FOUNDATION_IDS := ["powder", "signal", "gate"]
const CONTRIBUTION_IDS := ["nessa", "piri", "brann", "kesh", "lysa", "mara"]

var retained: Dictionary = {}
var current_line: Dictionary = {}
var settings: Dictionary = {}


func _init() -> void:
	new_game()


func new_game() -> void:
	retained = {
		"loop_index": 0,
		"death_count": 0,
		"soul_scars": 0,
		"knowledge": ["phone"],
		"echo_log": [],
		"trauma_tags": [],
		"g0_formed": false,
		"g1_formed": false,
	}
	settings = {
		"reduce_motion": false,
		"reduce_flash": false,
		"master_audio": true,
		"high_contrast": false,
		"rain_intensity": 1.0,
		"text_scale": 1.0,
	}
	_reset_current_line("arrival")


func _reset_current_line(stage: String = "arrival") -> void:
	current_line = {
		"stage": stage,
		"physical_evidence": [],
		"inventory": [],
		"contributions": [],
		"npc_tags": {},
		"flags": [],
		"player_position": [180.0, 875.0],
		"finale_time": 0.0,
		"finale_events": [],
		"agent_states": {},
		"pending_story": "",
		"pending_choices": [],
		"pending_return": {},
	}


func remember(id: String, echo_text: String = "") -> bool:
	var knowledge: Array = retained["knowledge"]
	if knowledge.has(id):
		return false
	knowledge.append(id)
	if not echo_text.is_empty():
		var log: Array = retained["echo_log"]
		log.append(echo_text)
	return true


func knows(id: String) -> bool:
	return (retained.get("knowledge", []) as Array).has(id)


func add_physical_evidence(id: String) -> bool:
	var evidence: Array = current_line["physical_evidence"]
	if evidence.has(id):
		return false
	evidence.append(id)
	return true


func has_physical_evidence(id: String) -> bool:
	return (current_line.get("physical_evidence", []) as Array).has(id)


func add_inventory(id: String) -> bool:
	var inventory: Array = current_line["inventory"]
	if inventory.has(id):
		return false
	inventory.append(id)
	return true


func has_item(id: String) -> bool:
	return (current_line.get("inventory", []) as Array).has(id)


func add_flag(id: String) -> bool:
	var flags: Array = current_line["flags"]
	if flags.has(id):
		return false
	flags.append(id)
	return true


func has_flag(id: String) -> bool:
	return (current_line.get("flags", []) as Array).has(id)


func accept_contribution(id: String) -> bool:
	var contributions: Array = current_line["contributions"]
	if contributions.has(id):
		return false
	contributions.append(id)
	return true


func has_contribution(id: String) -> bool:
	return (current_line.get("contributions", []) as Array).has(id)


func foundation_count() -> int:
	var result := 0
	for id in FOUNDATION_IDS:
		if knows(id):
			result += 1
	return result


func present_foundation_count() -> int:
	var result := 0
	for id in FOUNDATION_IDS:
		if has_physical_evidence(id):
			result += 1
	return result


func contribution_count() -> int:
	return (current_line.get("contributions", []) as Array).size()


func all_foundations_present() -> bool:
	for id in FOUNDATION_IDS:
		if not has_physical_evidence(id):
			return false
	return true


func all_contributions_ready() -> bool:
	for id in CONTRIBUTION_IDS:
		if not has_contribution(id):
			return false
	return true


func set_npc_tag(npc_id: String, tag: String) -> void:
	var npc_tags: Dictionary = current_line["npc_tags"]
	var tags: Array = npc_tags.get(npc_id, [])
	if not tags.has(tag):
		tags.append(tag)
	npc_tags[npc_id] = tags


func npc_has_tag(npc_id: String, tag: String) -> bool:
	var npc_tags: Dictionary = current_line.get("npc_tags", {})
	return (npc_tags.get(npc_id, []) as Array).has(tag)


func record_authored_return(cause: String, gained_echo: String, trauma_tag: String, next_stage: String) -> void:
	retained["death_count"] = int(retained.get("death_count", 0)) + 1
	retained["soul_scars"] = int(retained.get("soul_scars", 0)) + 1
	retained["loop_index"] = int(retained.get("loop_index", 0)) + 1
	retained["g0_formed"] = true
	var log: Array = retained["echo_log"]
	log.append(gained_echo)
	var trauma: Array = retained["trauma_tags"]
	if not trauma.has(trauma_tag):
		trauma.append(trauma_tag)
	remember("return_rule")
	remember("soul_scar")
	remember("death_%d" % int(retained["death_count"]))
	_reset_current_line(next_stage)
	current_line["last_return_cause"] = cause


func to_save_data() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"content_version": CONTENT_VERSION,
		"retained": retained.duplicate(true),
		"current_line": current_line.duplicate(true),
		"settings": settings.duplicate(true),
	}


func load_save_data(data: Dictionary) -> bool:
	var schema_value: Variant = data.get("schema_version", -1)
	if not _is_finite_number(schema_value) or float(schema_value) != float(SCHEMA_VERSION):
		return false
	if str(data.get("content_version", "")) != CONTENT_VERSION:
		return false
	if not data.has("retained") or not data.has("current_line"):
		return false
	var loaded_retained: Variant = data["retained"]
	var loaded_line: Variant = data["current_line"]
	var loaded_settings: Variant = data.get("settings", {})
	if not loaded_retained is Dictionary or not loaded_line is Dictionary or not loaded_settings is Dictionary:
		return false
	if not _arrays_are_valid(loaded_retained, ["knowledge", "echo_log", "trauma_tags"]):
		return false
	if not _arrays_are_valid(loaded_line, ["physical_evidence", "inventory", "contributions", "flags", "finale_events", "pending_choices"]):
		return false
	if not _numeric_fields_are_valid(loaded_retained, ["loop_index", "death_count", "soul_scars"]):
		return false
	if not _boolean_fields_are_valid(loaded_retained, ["g0_formed", "g1_formed"]):
		return false
	if not _numeric_fields_are_valid(loaded_line, ["finale_time"]):
		return false
	if loaded_line.has("stage") and not loaded_line["stage"] is String:
		return false
	if loaded_line.has("pending_story") and not loaded_line["pending_story"] is String:
		return false
	if loaded_line.has("player_position") and not _is_number_pair(loaded_line["player_position"]):
		return false
	if not _boolean_fields_are_valid(loaded_settings, ["reduce_motion", "reduce_flash", "master_audio", "high_contrast"]):
		return false
	if not _numeric_fields_are_valid(loaded_settings, ["rain_intensity", "text_scale"]):
		return false
	if loaded_line.has("npc_tags"):
		if not loaded_line["npc_tags"] is Dictionary:
			return false
		for tags: Variant in (loaded_line["npc_tags"] as Dictionary).values():
			if not tags is Array:
				return false
	if loaded_line.has("agent_states"):
		if not loaded_line["agent_states"] is Dictionary:
			return false
		for agent_data: Variant in (loaded_line["agent_states"] as Dictionary).values():
			if not agent_data is Dictionary:
				return false
			if not _numeric_fields_are_valid(agent_data, ["state", "resolve", "suspicion", "patrol_index"]):
				return false
			for vector_key in ["position", "last_known", "facing"]:
				if agent_data.has(vector_key) and not _is_number_pair(agent_data[vector_key]):
					return false
	if loaded_line.has("pending_return") and not loaded_line["pending_return"] is Dictionary:
		return false
	for choice: Variant in (loaded_line.get("pending_choices", []) as Array):
		if not choice is Dictionary:
			return false
	var pending_return: Dictionary = loaded_line.get("pending_return", {})
	if not pending_return.is_empty():
		for key in ["dialogue_id", "cause", "echo", "trauma", "next_stage"]:
			if not pending_return.has(key) or not pending_return[key] is String:
				return false

	var retained_defaults := retained.duplicate(true)
	retained_defaults.merge((loaded_retained as Dictionary).duplicate(true), true)
	retained = retained_defaults
	var line_defaults := current_line.duplicate(true)
	line_defaults.merge((loaded_line as Dictionary).duplicate(true), true)
	current_line = line_defaults
	var setting_defaults := settings.duplicate(true)
	setting_defaults.merge((loaded_settings as Dictionary).duplicate(true), true)
	settings = setting_defaults
	return true


func _arrays_are_valid(source: Dictionary, keys: Array[String]) -> bool:
	for key in keys:
		if source.has(key) and not source[key] is Array:
			return false
	return true


func _numeric_fields_are_valid(source: Dictionary, keys: Array[String]) -> bool:
	for key in keys:
		if source.has(key) and not _is_finite_number(source[key]):
			return false
	return true


func _boolean_fields_are_valid(source: Dictionary, keys: Array[String]) -> bool:
	for key in keys:
		if source.has(key) and not source[key] is bool:
			return false
	return true


func _is_number_pair(value: Variant) -> bool:
	if not value is Array or value.size() != 2:
		return false
	return _is_finite_number(value[0]) and _is_finite_number(value[1])


func _is_finite_number(value: Variant) -> bool:
	var value_type := typeof(value)
	return value_type in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


func checkpoint_summary() -> String:
	return "Pass %d · %d/3 foundations · %d/6 choices" % [
		int(retained.get("loop_index", 0)) + 1,
		present_foundation_count(),
		contribution_count(),
	]
