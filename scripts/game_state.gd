extends RefCounted
class_name AshGameState

const SCHEMA_VERSION := 2
const CONTENT_VERSION := "greyfen-arc1-2.0"
const LEGACY_SCHEMA_VERSION := 1
const LEGACY_CONTENT_VERSION := "greyfen-arc1-1.0"

const FOUNDATION_IDS := ["powder", "signal", "gate"]
const CONTRIBUTION_IDS := ["nessa", "piri", "brann", "kesh", "lysa", "mara"]
const VISUAL_QUALITY_IDS := ["low", "medium", "high", "ultra"]
const FACING_IDS := [
	"north", "north_east", "east", "south_east",
	"south", "south_west", "west", "north_west",
]

## Display names belonged to the 2D prototype. The values are durable identity
## keys and must be used by the 2.5D world regardless of localized display text.
const LEGACY_AGENT_IDS := {
	"West-road observer": "west_road_observer",
	"Granary watch": "granary_watch",
	"Tunnel buyer": "tunnel_buyer",
	"Signal runner": "signal_runner",
	"west_road_observer": "west_road_observer",
	"granary_watch": "granary_watch",
	"tunnel_buyer": "tunnel_buyer",
	"signal_runner": "signal_runner",
}

## V1 used pixel coordinates in one large 2D canvas. Those coordinates cannot
## be scaled safely into the authored 3D spaces, so every story stage migrates
## to a deliberate, safe spawn anchor. Position is a local fallback offset; a
## valid anchor transform is authoritative when the world restores a save.
const STAGE_CHECKPOINTS := {
	"arrival": {"zone_id": "fen_road", "anchor_id": "evan_arrival", "position": [0.0, 0.0, 0.0], "facing": "north_east"},
	"reach_mara": {"zone_id": "keep_court", "anchor_id": "mara_ward", "position": [0.0, 0.0, 0.0], "facing": "north"},
	"baseline_find_granary": {"zone_id": "refuge_row", "anchor_id": "granary_approach", "position": [0.0, 0.0, 0.0], "facing": "east"},
	"return_one": {"zone_id": "fen_road", "anchor_id": "west_gate_inside", "position": [0.0, 0.0, 0.0], "facing": "east"},
	"one_fuse": {"zone_id": "refuge_row", "anchor_id": "granary_approach", "position": [0.0, 0.0, 0.0], "facing": "east"},
	"one_fuse_report": {"zone_id": "keep_court", "anchor_id": "mara_ward", "position": [0.0, 0.0, 0.0], "facing": "north"},
	"return_two": {"zone_id": "fen_road", "anchor_id": "west_gate_inside", "position": [0.0, 0.0, 0.0], "facing": "east"},
	"wrong_hero_report": {"zone_id": "keep_court", "anchor_id": "mara_ward", "position": [0.0, 0.0, 0.0], "facing": "north"},
	"return_three": {"zone_id": "fen_road", "anchor_id": "west_gate_inside", "position": [0.0, 0.0, 0.0], "facing": "east"},
	"mara_ready": {"zone_id": "keep_court", "anchor_id": "mara_ward", "position": [0.0, 0.0, 0.0], "facing": "north"},
	"compact_offer": {"zone_id": "keep_court", "anchor_id": "mara_ward", "position": [0.0, 0.0, 0.0], "facing": "north"},
	"finale_to_tomas": {"zone_id": "granary_undercroft", "anchor_id": "tomas_standoff", "position": [0.0, 0.0, 0.0], "facing": "north"},
	"finale_defense": {"zone_id": "refuge_row", "anchor_id": "granary_defense", "position": [0.0, 0.0, 0.0], "facing": "south"},
	"finale_resolved": {"zone_id": "refuge_row", "anchor_id": "granary_defense", "position": [0.0, 0.0, 0.0], "facing": "south"},
	"tribunal": {"zone_id": "keep_hall", "anchor_id": "tribunal_entry", "position": [0.0, 0.0, 0.0], "facing": "north"},
	"complete": {"zone_id": "keep_hall", "anchor_id": "tribunal_entry", "position": [0.0, 0.0, 0.0], "facing": "north"},
}

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
		"visual_quality": "high",
		"depth_of_field": true,
		"weather_density": 1.0,
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
		"spatial_checkpoint": checkpoint_for_stage(stage),
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


func checkpoint_for_stage(stage: String) -> Dictionary:
	var source: Dictionary = STAGE_CHECKPOINTS.get(stage, STAGE_CHECKPOINTS["arrival"])
	return source.duplicate(true)


func set_spatial_checkpoint(
		zone_id: String,
		anchor_id: String,
		position: Vector3,
		facing: String
	) -> bool:
	var checkpoint := {
		"zone_id": zone_id,
		"anchor_id": anchor_id,
		"position": [position.x, position.y, position.z],
		"facing": facing,
	}
	if not _spatial_checkpoint_is_valid(checkpoint):
		return false
	current_line["spatial_checkpoint"] = checkpoint
	return true


func get_spatial_checkpoint() -> Dictionary:
	var checkpoint: Variant = current_line.get("spatial_checkpoint", {})
	if checkpoint is Dictionary and _spatial_checkpoint_is_valid(checkpoint):
		return (checkpoint as Dictionary).duplicate(true)
	return checkpoint_for_stage(str(current_line.get("stage", "arrival")))


func to_save_data() -> Dictionary:
	var serialized_line := current_line.duplicate(true)
	var checkpoint: Variant = serialized_line.get("spatial_checkpoint", {})
	if not checkpoint is Dictionary or not _spatial_checkpoint_is_valid(checkpoint):
		serialized_line["spatial_checkpoint"] = checkpoint_for_stage(str(serialized_line.get("stage", "arrival")))
	var agent_states: Variant = serialized_line.get("agent_states", {})
	if agent_states is Dictionary:
		serialized_line["agent_states"] = _agent_states_with_stable_ids(agent_states)
	var serialized_settings := settings.duplicate(true)
	serialized_settings.merge(_default_v2_settings(), false)
	return {
		"schema_version": SCHEMA_VERSION,
		"content_version": CONTENT_VERSION,
		"retained": retained.duplicate(true),
		"current_line": serialized_line,
		"settings": serialized_settings,
	}


func load_save_data(data: Dictionary) -> bool:
	var schema_value: Variant = data.get("schema_version", -1)
	if not _is_finite_number(schema_value) or float(schema_value) != floorf(float(schema_value)):
		return false
	var schema_version := int(schema_value)
	var candidate := data.duplicate(true)
	if schema_version == LEGACY_SCHEMA_VERSION:
		candidate = _migrate_v1_save_data(candidate)
		if candidate.is_empty():
			return false
	elif schema_version == SCHEMA_VERSION:
		if str(candidate.get("content_version", "")) != CONTENT_VERSION:
			return false
	else:
		return false
	return _load_v2_save_data(candidate)


func _load_v2_save_data(data: Dictionary) -> bool:
	if int(data.get("schema_version", -1)) != SCHEMA_VERSION:
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
	if loaded_line.has("stage"):
		if not loaded_line["stage"] is String or not STAGE_CHECKPOINTS.has(loaded_line["stage"]):
			return false
	if loaded_line.has("pending_story") and not loaded_line["pending_story"] is String:
		return false
	if loaded_line.has("player_position") and not _is_number_pair(loaded_line["player_position"]):
		return false
	if not loaded_line.has("spatial_checkpoint") or not _spatial_checkpoint_is_valid(loaded_line["spatial_checkpoint"]):
		return false
	if not _boolean_fields_are_valid(loaded_settings, ["reduce_motion", "reduce_flash", "master_audio", "high_contrast", "depth_of_field"]):
		return false
	if not _numeric_fields_are_valid(loaded_settings, ["rain_intensity", "text_scale", "weather_density"]):
		return false
	if loaded_settings.has("visual_quality"):
		if not loaded_settings["visual_quality"] is String or not VISUAL_QUALITY_IDS.has(loaded_settings["visual_quality"]):
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
		var seen_agent_ids := {}
		for agent_data: Variant in (loaded_line["agent_states"] as Dictionary).values():
			if not agent_data is Dictionary:
				return false
			var agent_id: Variant = agent_data.get("agent_id", "")
			if not agent_id is String or not _stable_id_is_valid(agent_id) or seen_agent_ids.has(agent_id):
				return false
			seen_agent_ids[agent_id] = true
			if not _numeric_fields_are_valid(agent_data, ["state", "resolve", "suspicion", "patrol_index"]):
				return false
			for vector_key in ["position", "last_known", "facing"]:
				if agent_data.has(vector_key) and not _is_number_vector(agent_data[vector_key], [2, 3]):
					return false
			if agent_data.has("legacy_transform_2d") and not agent_data["legacy_transform_2d"] is bool:
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


func _migrate_v1_save_data(data: Dictionary) -> Dictionary:
	# Schema is intentionally inspected before content version so an otherwise
	# valid V1 save reaches this migration instead of the V2 rejection branch.
	if str(data.get("content_version", "")) != LEGACY_CONTENT_VERSION:
		return {}
	var legacy_retained: Variant = data.get("retained", null)
	var legacy_line: Variant = data.get("current_line", null)
	var legacy_settings: Variant = data.get("settings", {})
	if not legacy_retained is Dictionary or not legacy_line is Dictionary or not legacy_settings is Dictionary:
		return {}

	var migrated := data.duplicate(true)
	migrated["schema_version"] = SCHEMA_VERSION
	migrated["content_version"] = CONTENT_VERSION
	var migrated_line: Dictionary = legacy_line.duplicate(true)
	var stage: Variant = migrated_line.get("stage", "arrival")
	if not stage is String or not STAGE_CHECKPOINTS.has(stage):
		return {}
	migrated_line["spatial_checkpoint"] = checkpoint_for_stage(stage)
	var legacy_agents: Variant = migrated_line.get("agent_states", {})
	if legacy_agents is Dictionary:
		migrated_line["agent_states"] = _agent_states_with_stable_ids(legacy_agents, true)
	migrated["current_line"] = migrated_line
	var migrated_settings: Dictionary = legacy_settings.duplicate(true)
	migrated_settings.merge(_default_v2_settings(), false)
	migrated["settings"] = migrated_settings
	return migrated


func _default_v2_settings() -> Dictionary:
	return {
		"visual_quality": "high",
		"depth_of_field": true,
		"weather_density": 1.0,
	}


func _agent_states_with_stable_ids(source: Dictionary, migrated_from_v1: bool = false) -> Dictionary:
	var result := {}
	for key: Variant in source.keys():
		var value: Variant = source[key]
		if not value is Dictionary:
			result[key] = value
			continue
		var state: Dictionary = value.duplicate(true)
		var id_value: Variant = state.get("agent_id", "")
		var agent_id := str(id_value) if id_value is String and not str(id_value).is_empty() else _stable_agent_id(str(key))
		state["agent_id"] = agent_id
		if migrated_from_v1:
			for vector_key in ["position", "last_known", "facing"]:
				if state.has(vector_key) and _is_number_pair(state[vector_key]):
					state["legacy_transform_2d"] = true
					break
		result[key] = state
	return result


func _stable_agent_id(source: String) -> String:
	if LEGACY_AGENT_IDS.has(source):
		return str(LEGACY_AGENT_IDS[source])
	var slug := source.strip_edges().to_snake_case().replace("-", "_")
	return slug if _stable_id_is_valid(slug) else "legacy_agent"


func _stable_id_is_valid(value: String) -> bool:
	if value.is_empty():
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		if not (code == 95 or code >= 48 and code <= 57 or code >= 97 and code <= 122):
			return false
	return true


func _spatial_checkpoint_is_valid(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	for key in ["zone_id", "anchor_id"]:
		if not value.has(key) or not value[key] is String or str(value[key]).strip_edges().is_empty():
			return false
	if not value.has("position") or not _is_number_vector(value["position"], [3]):
		return false
	var facing: Variant = value.get("facing", "")
	return facing is String and FACING_IDS.has(facing)


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
	return _is_number_vector(value, [2])


func _is_number_vector(value: Variant, accepted_sizes: Array) -> bool:
	if not value is Array or not accepted_sizes.has(value.size()):
		return false
	for component: Variant in value:
		if not _is_finite_number(component):
			return false
	return true


func _is_finite_number(value: Variant) -> bool:
	var value_type := typeof(value)
	return value_type in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))


func checkpoint_summary() -> String:
	return "Pass %d · %d/3 foundations · %d/6 choices" % [
		int(retained.get("loop_index", 0)) + 1,
		present_foundation_count(),
		contribution_count(),
	]
