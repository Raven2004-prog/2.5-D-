extends Node
class_name AshenStoryDirectorAdapter3D

## Runs the shipped four-pass story as a headless narrative service for the
## 2.5D world. GreyfenGameWorld remains the single source of truth for story
## transitions and GameUI dialogue, but none of its 2D simulation is allowed to
## render, process input, run physics, tick the finale, or author 3D save data.

signal director_ready(ui: GameUI)
signal autosave_requested(data: Dictionary)
signal story_completed(state: AshGameState)
signal return_to_title_requested
signal stage_changed(stage: String, checkpoint: Dictionary)
signal anchor_changed(zone_id: String, anchor_id: String, position: Vector3, facing: String)

const LegacyWorldScript := preload("res://scripts/game_world.gd")

var game_state: AshGameState
var director: GreyfenGameWorld
var ui: GameUI

var _authoritative_checkpoint: Dictionary = {}
var _authoritative_agent_states: Dictionary = {}
var _last_stage := ""
var _last_loop_index := -1
var _last_announced_checkpoint: Dictionary = {}
var _handling_legacy_snapshot := false
var _announced_ready := false


func configure(state: AshGameState) -> void:
	game_state = state
	if is_inside_tree() and director == null:
		_build_director()


func _ready() -> void:
	if game_state == null:
		game_state = AshGameState.new()
	_build_director()


func _process(_delta: float) -> void:
	if director == null or _handling_legacy_snapshot:
		return
	_poll_authoritative_3d_state()


func _build_director() -> void:
	if director != null:
		return
	_capture_authoritative_fields()
	_last_stage = get_stage()
	_last_loop_index = int(game_state.retained.get("loop_index", 0))

	director = LegacyWorldScript.new()
	director.name = "HiddenNarrativeDirector"
	director.configure(game_state)
	director.autosave_requested.connect(_on_legacy_autosave)
	director.story_completed.connect(_on_legacy_story_completed)
	director.return_to_title_requested.connect(_on_legacy_return_to_title)
	add_child(director)
	ui = director.ui
	_disable_legacy_world()
	call_deferred("_announce_director_ready")


func _announce_director_ready() -> void:
	if director == null or ui == null:
		return
	# GreyfenGameWorld begins its current stage through a deferred call. Calling
	# it here only if that call has not run protects unusual test/embed ordering.
	if not director._started:
		director._begin_current_stage()
	_reconcile_after_legacy_action()
	if not _announced_ready:
		_announced_ready = true
		director_ready.emit(ui)
	stage_changed.emit(get_stage(), get_spatial_checkpoint())
	_emit_anchor_if_changed(true)


func _disable_legacy_world() -> void:
	# Do not set PROCESS_MODE_DISABLED on the director: process-mode inheritance
	# would also silence GameUI. Disable callbacks individually instead.
	director.set_process(false)
	director.set_physics_process(false)
	director.set_process_input(false)
	director.set_process_unhandled_input(false)
	director.set_process_shortcut_input(false)

	for node in _descendants_of(director):
		if node == ui or (ui != null and ui.is_ancestor_of(node)):
			continue
		node.set_process(false)
		node.set_physics_process(false)
		node.set_process_input(false)
		node.set_process_unhandled_input(false)
		node.set_process_shortcut_input(false)
		if node is CanvasItem:
			(node as CanvasItem).hide()
		if node is CollisionObject2D:
			var collision_object := node as CollisionObject2D
			collision_object.collision_layer = 0
			collision_object.collision_mask = 0
		if node is Camera2D:
			(node as Camera2D).enabled = false

	if director.player:
		director.player.controls_enabled = false
	if director.camera:
		director.camera.enabled = false
	if director.rain:
		director.rain.hide()
		director.rain.set_process(false)


func _descendants_of(root: Node) -> Array[Node]:
	var result: Array[Node] = []
	var pending: Array[Node] = []
	for child in root.get_children():
		pending.append(child)
	while not pending.is_empty():
		var node: Node = pending.pop_back() as Node
		result.append(node)
		for child in node.get_children():
			pending.append(child)
	return result


func get_stage() -> String:
	if game_state == null:
		return "arrival"
	return str(game_state.current_line.get("stage", "arrival"))


func get_spatial_checkpoint() -> Dictionary:
	if game_state == null:
		return {}
	if not _authoritative_checkpoint.is_empty():
		return _authoritative_checkpoint.duplicate(true)
	return game_state.get_spatial_checkpoint()


func get_agent_states() -> Dictionary:
	return _authoritative_agent_states.duplicate(true)


func set_spatial_checkpoint(
		zone_id: String,
		anchor_id: String,
		position: Vector3,
		facing: String
	) -> bool:
	if game_state == null or not game_state.set_spatial_checkpoint(zone_id, anchor_id, position, facing):
		return false
	_authoritative_checkpoint = game_state.get_spatial_checkpoint()
	_emit_anchor_if_changed(true)
	return true


func set_agent_states(states: Dictionary) -> void:
	_authoritative_agent_states = states.duplicate(true)
	if game_state:
		game_state.current_line["agent_states"] = _authoritative_agent_states.duplicate(true)


func capture_authoritative_3d_state() -> void:
	## Call after a 3D controller writes checkpoint or agent state directly.
	_capture_authoritative_fields()
	_emit_anchor_if_changed()


func snapshot_data() -> Dictionary:
	if game_state == null:
		return {}
	_restore_authoritative_fields()
	return game_state.to_save_data()


func interact_npc(id: String) -> bool:
	if not _can_begin_interaction() or not director.npcs.has(id):
		return false
	var npc: Variant = director.npcs[id]
	if not npc is NpcActor or not (npc as NpcActor).available:
		return false
	_capture_authoritative_fields()
	director._interact_npc(npc as NpcActor)
	_reconcile_after_legacy_action()
	return true


func interact_hotspot(id: String) -> bool:
	if not _can_begin_interaction() or not director.hotspots.has(id):
		return false
	var hotspot: Variant = director.hotspots[id]
	if not hotspot is EvidenceHotspot or not (hotspot as EvidenceHotspot).available:
		return false
	_capture_authoritative_fields()
	director._interact_hotspot(hotspot as EvidenceHotspot)
	_reconcile_after_legacy_action()
	return true


func advance_dialogue() -> bool:
	if ui == null or not ui.dialogue_open:
		return false
	_capture_authoritative_fields()
	ui.advance_dialogue()
	_reconcile_after_legacy_action()
	return true


func open_folio() -> bool:
	if not _can_begin_interaction():
		return false
	_capture_authoritative_fields()
	director._open_folio()
	_reconcile_after_legacy_action()
	return ui != null and ui.folio_open


func choose_dialogue(choice_id: String) -> bool:
	if ui == null or not ui.dialogue_open or ui._choice_box == null or not ui._choice_box.visible:
		return false
	_capture_authoritative_fields()
	ui._select_choice(choice_id)
	_reconcile_after_legacy_action()
	return true


func tick_finale(delta: float) -> bool:
	if director == null or get_stage() != "finale_defense" or delta <= 0.0:
		return false
	if ui and (ui.dialogue_open or ui.folio_open) or director._rescue_in_progress:
		return false
	_capture_authoritative_fields()
	# Calling this method means the 3D gameplay layer has already confirmed that
	# Evan is holding the defense volume. Keep the hidden 2D proxy inside its old
	# granary radius so only authored timer/event logic runs.
	if director.player and director.world_map:
		director.player.global_position = director.world_map.get_landmark("granary")
	var prior_time := float(game_state.current_line.get("finale_time", director._finale_remaining))
	var prior_stage := get_stage()
	director._tick_finale(delta)
	_reconcile_after_legacy_action()
	return get_stage() != prior_stage or not is_equal_approx(
		float(game_state.current_line.get("finale_time", director._finale_remaining)),
		prior_time
	)


func set_player_condition(health: float, maximum_health: float, stamina: float, maximum_stamina: float) -> void:
	if ui:
		ui.set_condition(health, maximum_health, stamina, maximum_stamina)


func show_interaction_prompt(text: String) -> void:
	if ui and not ui.dialogue_open and not ui.folio_open:
		ui.show_prompt(text)


func request_return_to_title() -> bool:
	if director == null:
		return false
	_capture_authoritative_fields()
	director._return_to_title()
	_reconcile_after_legacy_action()
	return true


func _can_begin_interaction() -> bool:
	return director != null and ui != null and not ui.dialogue_open and not ui.folio_open


func _capture_authoritative_fields() -> void:
	if game_state == null:
		return
	var checkpoint: Variant = game_state.current_line.get("spatial_checkpoint", {})
	if checkpoint is Dictionary and not (checkpoint as Dictionary).is_empty():
		_authoritative_checkpoint = (checkpoint as Dictionary).duplicate(true)
	var agents: Variant = game_state.current_line.get("agent_states", {})
	if agents is Dictionary:
		_authoritative_agent_states = (agents as Dictionary).duplicate(true)


func _restore_authoritative_fields() -> void:
	if game_state == null:
		return
	if _authoritative_checkpoint.is_empty():
		_authoritative_checkpoint = game_state.checkpoint_for_stage(get_stage())
	game_state.current_line["spatial_checkpoint"] = _authoritative_checkpoint.duplicate(true)
	game_state.current_line["agent_states"] = _authoritative_agent_states.duplicate(true)


func _on_legacy_autosave(_unsafe_legacy_snapshot: Dictionary) -> void:
	_handling_legacy_snapshot = true
	_reconcile_after_legacy_action()
	var safe_snapshot := game_state.to_save_data()
	_handling_legacy_snapshot = false
	autosave_requested.emit(safe_snapshot)


func _on_legacy_story_completed(_legacy_state: AshGameState) -> void:
	_reconcile_after_legacy_action()
	story_completed.emit(game_state)


func _on_legacy_return_to_title() -> void:
	_reconcile_after_legacy_action()
	return_to_title_requested.emit()


func _reconcile_after_legacy_action() -> void:
	if game_state == null:
		return
	var stage := get_stage()
	var loop_index := int(game_state.retained.get("loop_index", 0))
	var stage_did_change := stage != _last_stage
	var line_did_change := loop_index != _last_loop_index
	if line_did_change:
		_authoritative_agent_states = {}
	if stage_did_change:
		_authoritative_checkpoint = game_state.checkpoint_for_stage(stage)
	_last_stage = stage
	_last_loop_index = loop_index
	_restore_authoritative_fields()
	if director:
		_disable_legacy_world()
	if stage_did_change:
		stage_changed.emit(stage, _authoritative_checkpoint.duplicate(true))
		_emit_anchor_if_changed(true)


func _poll_authoritative_3d_state() -> void:
	var stage := get_stage()
	var loop_index := int(game_state.retained.get("loop_index", 0))
	if stage != _last_stage or loop_index != _last_loop_index:
		_reconcile_after_legacy_action()
		return
	var checkpoint: Variant = game_state.current_line.get("spatial_checkpoint", {})
	if checkpoint is Dictionary and checkpoint != _authoritative_checkpoint:
		_authoritative_checkpoint = (checkpoint as Dictionary).duplicate(true)
		_emit_anchor_if_changed()
	var agents: Variant = game_state.current_line.get("agent_states", {})
	if agents is Dictionary and agents != _authoritative_agent_states:
		_authoritative_agent_states = (agents as Dictionary).duplicate(true)


func _emit_anchor_if_changed(force: bool = false) -> void:
	if _authoritative_checkpoint.is_empty():
		return
	if not force and _authoritative_checkpoint == _last_announced_checkpoint:
		return
	_last_announced_checkpoint = _authoritative_checkpoint.duplicate(true)
	var position_data: Array = _authoritative_checkpoint.get("position", [0.0, 0.0, 0.0])
	var position := Vector3.ZERO
	if position_data.size() == 3:
		position = Vector3(float(position_data[0]), float(position_data[1]), float(position_data[2]))
	anchor_changed.emit(
		str(_authoritative_checkpoint.get("zone_id", "")),
		str(_authoritative_checkpoint.get("anchor_id", "")),
		position,
		str(_authoritative_checkpoint.get("facing", "south"))
	)
