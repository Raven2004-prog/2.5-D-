extends SceneTree
## Headless contract for the story-preserving 3D adapter. Run with:
## Godot --headless --path <project> --script res://tests/test_story_adapter_3d.gd

const StateScript := preload("res://scripts/game_state.gd")
const AdapterScript := preload("res://scripts/ashen_3d/story_director_adapter_3d.gd")

var _failures := 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("[story-adapter-3d] hidden narrative director checks")
	await _test_hidden_director_keeps_ui_live()
	await _test_same_stage_autosave_protects_3d_state()
	await _test_authored_return_moves_to_semantic_anchor()
	await _test_choice_and_manual_finale_tick()
	await _test_completion_and_title_relays()
	if _failures == 0:
		print("[story-adapter-3d] PASS")
		quit(0)
	else:
		printerr("[story-adapter-3d] FAIL: %d assertion(s)" % _failures)
		quit(1)


func _test_hidden_director_keeps_ui_live() -> void:
	var state := StateScript.new()
	var adapter := _spawn_adapter(state)
	await _settle_adapter()

	_expect(adapter.director != null and adapter.ui != null, "adapter constructs the existing narrative world and GameUI")
	_expect(adapter.director.name == "HiddenNarrativeDirector", "legacy world is explicitly identified as a hidden director")
	_expect(not adapter.director.is_processing(), "legacy director does not run its frame loop")
	_expect(not adapter.director.is_physics_processing(), "legacy director does not run physics")
	_expect(not adapter.director.is_processing_unhandled_input(), "legacy world cannot intercept 3D input")
	_expect(adapter.ui.is_processing_unhandled_input(), "GameUI keeps its dialogue and pause input handler")
	_expect(adapter.ui._root.visible, "GameUI remains visible")
	_expect(adapter.ui.dialogue_open and adapter.ui._dialogue_id == "intro_earth", "deferred opening story behavior is preserved")
	_expect(not adapter.interact_npc("lysa"), "world interaction cannot bypass an open dialogue")

	_expect(not adapter.director.world_map.visible, "old map drawing is hidden")
	_expect(not adapter.director.player.visible, "old player drawing is hidden")
	_expect(not adapter.director.player.is_physics_processing(), "old player body cannot simulate")
	_expect(adapter.director.player.collision_layer == 0 and adapter.director.player.collision_mask == 0, "old player collider is isolated")
	_expect(not adapter.director.player.controls_enabled, "old player input is disabled")
	_expect(not adapter.director.camera.enabled, "old Camera2D is disabled")
	_expect(not adapter.director.rain.visible and not adapter.director.rain.is_processing(), "old rain overlay is hidden and stopped")

	var actors_are_sandboxed := true
	for agent in adapter.director.agents:
		actors_are_sandboxed = actors_are_sandboxed and not agent.visible
		actors_are_sandboxed = actors_are_sandboxed and not agent.is_physics_processing()
		actors_are_sandboxed = actors_are_sandboxed and agent.collision_layer == 0 and agent.collision_mask == 0
	for npc_value in adapter.director.npcs.values():
		var npc := npc_value as NpcActor
		actors_are_sandboxed = actors_are_sandboxed and not npc.visible and not npc.is_processing()
	for hotspot_value in adapter.director.hotspots.values():
		var hotspot := hotspot_value as EvidenceHotspot
		actors_are_sandboxed = actors_are_sandboxed and not hotspot.visible and not hotspot.is_processing()
	_expect(actors_are_sandboxed, "every legacy actor and hotspot is hidden and non-processing")

	await _finish_dialogue(adapter, "intro_earth")
	_expect(adapter.ui.dialogue_open and adapter.ui._dialogue_id == "arrival", "legacy dialogue chaining remains active")
	await _finish_dialogue(adapter, "arrival")
	_expect(not adapter.ui.dialogue_open and bool(state.retained.get("g0_formed", false)), "opening completes through the real internal handler")

	adapter.queue_free()
	await process_frame


func _test_same_stage_autosave_protects_3d_state() -> void:
	var state := StateScript.new()
	state.current_line["stage"] = "return_two"
	state.current_line["spatial_checkpoint"] = state.checkpoint_for_stage("return_two")
	var adapter := _spawn_adapter(state)
	var autosaves: Array[Dictionary] = []
	adapter.autosave_requested.connect(func(data: Dictionary) -> void: autosaves.append(data.duplicate(true)))
	await _settle_adapter()
	await _finish_dialogue(adapter, "return_two")

	var authoritative_agents := {
		"granary_watch": {
			"agent_id": "granary_watch",
			"state": 2,
			"resolve": 71.0,
			"suspicion": 0.75,
			"patrol_index": 1,
			"position": [11.0, 0.0, -4.0],
			"last_known": [8.0, 0.0, -1.0],
			"facing": [1.0, 0.0, 0.0],
		},
	}
	_expect(
		adapter.set_spatial_checkpoint("signal_ward", "tower_lower_landing", Vector3(12.5, 1.0, -7.25), "west"),
		"adapter accepts an authored 3D checkpoint"
	)
	adapter.set_agent_states(authoritative_agents)
	var expected_checkpoint := adapter.get_spatial_checkpoint()

	_expect(adapter.interact_hotspot("powder"), "3D hotspot ID delegates to existing evidence logic")
	_expect(state.has_physical_evidence("powder"), "delegated hotspot records present-line evidence")
	_expect(adapter.ui.dialogue_open and adapter.ui._dialogue_id == "powder_discovery", "delegated hotspot presents the existing dialogue")
	_expect(not autosaves.is_empty(), "legacy story autosave is relayed")
	_expect(state.current_line.get("spatial_checkpoint") == expected_checkpoint, "legacy autosave cannot overwrite the 3D checkpoint")
	_expect(state.current_line.get("agent_states") == authoritative_agents, "legacy dummy agents cannot overwrite 3D agent state")
	if not autosaves.is_empty():
		var safe_line: Dictionary = autosaves.back().get("current_line", {})
		_expect(safe_line.get("spatial_checkpoint") == expected_checkpoint, "relayed snapshot contains the authoritative 3D checkpoint")
		_expect(safe_line.get("agent_states") == authoritative_agents, "relayed snapshot contains only authoritative 3D agents")

	var snapshot := adapter.snapshot_data()
	_expect(snapshot.get("schema_version") == 2, "adapter snapshots use save schema V2")
	_expect(snapshot["current_line"].get("agent_states") == authoritative_agents, "adapter never calls the unsafe legacy snapshot path")

	adapter.queue_free()
	await process_frame


func _test_authored_return_moves_to_semantic_anchor() -> void:
	var state := StateScript.new()
	state.current_line["stage"] = "baseline_find_granary"
	state.current_line["spatial_checkpoint"] = state.checkpoint_for_stage("baseline_find_granary")
	var adapter := _spawn_adapter(state)
	var stage_events: Array[String] = []
	var anchor_events: Array[Dictionary] = []
	adapter.stage_changed.connect(func(stage: String, _checkpoint: Dictionary) -> void: stage_events.append(stage))
	adapter.anchor_changed.connect(func(zone_id: String, anchor_id: String, position: Vector3, facing: String) -> void:
		anchor_events.append({"zone_id": zone_id, "anchor_id": anchor_id, "position": position, "facing": facing})
	)
	await _settle_adapter()

	adapter.set_agent_states({
		"signal_runner": {
			"agent_id": "signal_runner", "state": 1, "resolve": 55.0,
			"suspicion": 0.2, "patrol_index": 0,
			"position": [2.0, 0.0, 3.0], "last_known": [2.0, 0.0, 3.0], "facing": [0.0, 0.0, 1.0],
		},
	})
	adapter.set_spatial_checkpoint("refuge_row", "granary_investigation", Vector3(3.0, 0.0, 6.0), "north")
	_expect(adapter.interact_hotspot("powder"), "baseline powder interaction delegates successfully")
	await _finish_dialogue(adapter, "powder_discovery")
	_expect(adapter.ui.dialogue_open and adapter.ui._dialogue_id == "catastrophe_one", "first authored catastrophe is still chained")
	await _finish_dialogue(adapter, "catastrophe_one")
	await create_timer(0.85).timeout
	await process_frame

	_expect(adapter.get_stage() == "return_one", "authored Return reaches pass two through the adapter")
	_expect(int(state.retained.get("death_count", 0)) == 1 and int(state.retained.get("soul_scars", 0)) == 1, "Return preserves death and soul-scar behavior")
	var checkpoint := adapter.get_spatial_checkpoint()
	_expect(checkpoint.get("zone_id") == "fen_road" and checkpoint.get("anchor_id") == "west_gate_inside", "new line moves to its approved semantic anchor")
	_expect(checkpoint.get("position") == [0.0, 0.0, 0.0], "Return does not reuse the prior 3D position")
	_expect(adapter.get_agent_states().is_empty(), "new authored line clears prior-line 3D agent state")
	_expect(stage_events.has("return_one"), "stage changes are exposed to the 3D world")
	var saw_return_anchor := false
	for event in anchor_events:
		if event.get("zone_id") == "fen_road" and event.get("anchor_id") == "west_gate_inside":
			saw_return_anchor = true
	_expect(saw_return_anchor, "anchor changes are exposed to the 3D world")

	var legacy_still_sandboxed := not adapter.director.player.controls_enabled
	legacy_still_sandboxed = legacy_still_sandboxed and adapter.director.player.collision_layer == 0
	for agent in adapter.director.agents:
		legacy_still_sandboxed = legacy_still_sandboxed and agent.collision_layer == 0 and not agent.is_physics_processing()
	_expect(legacy_still_sandboxed, "legacy reset routines cannot re-enable hidden physics after a Return")

	adapter.queue_free()
	await process_frame


func _test_choice_and_manual_finale_tick() -> void:
	var state := StateScript.new()
	state.current_line["stage"] = "finale_to_tomas"
	state.current_line["spatial_checkpoint"] = state.checkpoint_for_stage("finale_to_tomas")
	var adapter := _spawn_adapter(state)
	await _settle_adapter()

	var authoritative_agents := {
		"tunnel_buyer": {
			"agent_id": "tunnel_buyer", "state": 1, "resolve": 48.0,
			"suspicion": 0.4, "patrol_index": 2,
			"position": [17.0, 0.0, 9.0], "last_known": [15.0, 0.0, 9.0], "facing": [-1.0, 0.0, 0.0],
		},
	}
	adapter.set_agent_states(authoritative_agents)
	_expect(adapter.interact_npc("tomas"), "3D NPC ID delegates to Tomas's existing interaction")
	_expect(adapter.ui._dialogue_id == "tomas_surrender", "Tomas's non-coercive choice dialogue opens")
	await _reveal_choices(adapter)
	_expect(adapter.choose_dialogue("offer_exit"), "choice selection reaches the existing handler")
	_expect(state.has_flag("tomas_surrendered"), "Tomas's voluntary surrender remains recorded")
	_expect(adapter.ui.dialogue_open and adapter.ui._dialogue_id == "tomas_accepts", "acceptance scene follows the choice")
	_expect(adapter.get_agent_states() == authoritative_agents, "choice-handler autosave cannot replace 3D agents")

	await _finish_dialogue(adapter, "tomas_accepts")
	_expect(adapter.get_stage() == "finale_defense", "acceptance begins the existing granary finale")
	_expect(is_equal_approx(float(state.current_line.get("finale_time", 0.0)), 38.0), "finale retains its authored duration")
	var time_before_idle := float(state.current_line.get("finale_time", 0.0))
	for _frame in range(4):
		await process_frame
	_expect(is_equal_approx(float(state.current_line.get("finale_time", 0.0)), time_before_idle), "hidden director never advances finale automatically")

	_expect(adapter.tick_finale(8.0), "3D gameplay can advance the finale explicitly while inside its defense volume")
	_expect(is_equal_approx(float(state.current_line.get("finale_time", 0.0)), 30.0), "manual finale tick advances authored time exactly once")
	_expect((state.current_line.get("finale_events", []) as Array).has("piri"), "manual finale tick fires authored contribution milestones")
	_expect(adapter.get_agent_states() == authoritative_agents, "finale milestone autosave preserves 3D agent state")
	_expect(adapter.get_spatial_checkpoint().get("anchor_id") == "granary_defense", "finale stage exposes the granary defense anchor")

	adapter.ui.show_dialogue("adapter_pause_probe", {"speaker": "Narrator", "pages": PackedStringArray(["Hold."])})
	_expect(not adapter.tick_finale(1.0), "dialogue pauses manual finale progression")
	adapter.ui.hide_dialogue()

	adapter.queue_free()
	await process_frame


func _test_completion_and_title_relays() -> void:
	var state := StateScript.new()
	state.current_line["stage"] = "complete"
	state.current_line["spatial_checkpoint"] = state.checkpoint_for_stage("complete")
	var adapter := AdapterScript.new()
	var completed_states: Array[AshGameState] = []
	var title_requests := [0]
	var autosave_count := [0]
	adapter.story_completed.connect(func(completed: AshGameState) -> void: completed_states.append(completed))
	adapter.return_to_title_requested.connect(func() -> void: title_requests[0] += 1)
	adapter.autosave_requested.connect(func(_data: Dictionary) -> void: autosave_count[0] += 1)
	adapter.configure(state)
	get_root().add_child(adapter)
	await _settle_adapter()

	_expect(adapter.ui.dialogue_open and adapter.ui._dialogue_id == "ending", "completed state resumes the existing ending")
	await _finish_dialogue(adapter, "ending")
	_expect(completed_states.size() == 1 and completed_states[0] == state, "story-completed signal relays the authoritative state")
	_expect(adapter.request_return_to_title(), "3D host can request return to title through the adapter")
	_expect(title_requests[0] == 1, "return-to-title signal is relayed exactly once")
	_expect(autosave_count[0] >= 1, "return to title relays a safe autosave first")

	adapter.queue_free()
	await process_frame


func _spawn_adapter(state: AshGameState) -> AshenStoryDirectorAdapter3D:
	var adapter := AdapterScript.new()
	adapter.configure(state)
	get_root().add_child(adapter)
	return adapter


func _settle_adapter() -> void:
	await process_frame
	await process_frame


func _finish_dialogue(adapter: AshenStoryDirectorAdapter3D, expected_id: String) -> void:
	for _step in range(32):
		if not adapter.ui.dialogue_open or adapter.ui._dialogue_id != expected_id:
			return
		adapter.advance_dialogue()
		await process_frame
	_expect(false, "dialogue '%s' closes within a bounded number of advances" % expected_id)


func _reveal_choices(adapter: AshenStoryDirectorAdapter3D) -> void:
	for _step in range(32):
		if adapter.ui._choice_box.visible:
			return
		if not adapter.ui.dialogue_open:
			break
		adapter.advance_dialogue()
		await process_frame
	_expect(false, "choice dialogue exposes its choices within a bounded number of advances")


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("  [ok] %s" % label)
	else:
		_failures += 1
		printerr("  [FAIL] %s" % label)
