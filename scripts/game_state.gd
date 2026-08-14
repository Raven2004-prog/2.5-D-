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
	if int(data.get("schema_version", -1)) != SCHEMA_VERSION:
		return false
	if not data.has("retained") or not data.has("current_line"):
		return false
	retained = (data["retained"] as Dictionary).duplicate(true)
	current_line = (data["current_line"] as Dictionary).duplicate(true)
	settings = (data.get("settings", settings) as Dictionary).duplicate(true)
	return true


func checkpoint_summary() -> String:
	return "Pass %d · %d/3 foundations · %d/6 choices" % [
		int(retained.get("loop_index", 0)) + 1,
		present_foundation_count(),
		contribution_count(),
	]

