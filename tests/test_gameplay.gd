extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("[gameplay] %s" % message)


func _run() -> void:
	var audio_manager := root.get_node_or_null("AudioManager")
	if audio_manager:
		audio_manager.set_master_enabled(false)
	var state := AshGameState.new()
	_check(state.retained["loop_index"] == 0, "A new game starts on the first pass.")
	_check(not state.knows("powder"), "The first pass does not begin with plot knowledge.")
	state.add_inventory("token")
	state.add_physical_evidence("powder")
	state.set_npc_tag("lysa", "trusted")
	state.remember("powder", "Powder under the granary.")
	state.record_authored_return("granary", "The granary fell.", "smoke", "return_one")
	_check(state.knows("powder"), "Retained knowledge survives a Return.")
	_check(not state.has_item("token"), "Physical inventory resets on a Return.")
	_check(not state.has_physical_evidence("powder"), "Physical evidence resets on a Return.")
	_check(not state.npc_has_tag("lysa", "trusted"), "NPC relationship state resets on a Return.")
	_check(state.retained["soul_scars"] == 1, "A true authored death adds one soul scar.")

	for foundation in AshGameState.FOUNDATION_IDS:
		state.remember(foundation)
		state.add_physical_evidence(foundation)
	_check(state.all_foundations_present(), "All three threat foundations can be proven in one line.")
	for contribution in AshGameState.CONTRIBUTION_IDS:
		state.accept_contribution(contribution)
	_check(state.all_contributions_ready(), "Final success recognizes all six independent contributions.")
	state.settings["master_audio"] = false

	var encoded := state.to_save_data()
	var restored := AshGameState.new()
	_check(restored.load_save_data(encoded), "Gameplay state accepts its current save schema.")
	_check(restored.all_contributions_ready(), "Contributions survive an ordinary save/load.")
	_check(restored.retained["soul_scars"] == 1, "Soul scars survive an ordinary save/load.")
	_check(not bool(restored.settings.get("master_audio", true)), "Audio preference survives an ordinary save/load.")
	for malformed_key in ["retained", "current_line", "settings"]:
		var malformed := encoded.duplicate(true)
		malformed[malformed_key] = []
		_check(not AshGameState.new().load_save_data(malformed), "Malformed '%s' save data is rejected without a cast error." % malformed_key)
	var wrong_content := encoded.duplicate(true)
	wrong_content["content_version"] = "future-incompatible-content"
	_check(not AshGameState.new().load_save_data(wrong_content), "Incompatible story content is rejected safely.")
	var malformed_schema := encoded.duplicate(true)
	malformed_schema["schema_version"] = []
	_check(not AshGameState.new().load_save_data(malformed_schema), "A non-numeric schema version is rejected safely.")
	var malformed_position := encoded.duplicate(true)
	malformed_position["current_line"]["player_position"] = [{}, 875.0]
	_check(not AshGameState.new().load_save_data(malformed_position), "A damaged player position is rejected before world construction.")
	var malformed_clock := encoded.duplicate(true)
	malformed_clock["current_line"]["finale_time"] = {}
	_check(not AshGameState.new().load_save_data(malformed_clock), "A damaged finale clock is rejected safely.")
	var malformed_agent := encoded.duplicate(true)
	malformed_agent["current_line"]["agent_states"] = {"Granary watch": {"resolve": []}}
	_check(not AshGameState.new().load_save_data(malformed_agent), "Damaged patrol scalar data is rejected safely.")
	var malformed_setting := encoded.duplicate(true)
	malformed_setting["settings"]["rain_intensity"] = []
	_check(not AshGameState.new().load_save_data(malformed_setting), "Damaged numeric settings are rejected safely.")

	# Instantiate the complete world, including map, lights, HUD, dialogue, actors,
	# and AI. This catches scene-tree and runtime API errors that parser checks miss.
	restored.current_line["stage"] = "return_three"
	var world := GreyfenGameWorld.new()
	world.configure(restored)
	root.add_child(world)
	await process_frame
	await process_frame
	await process_frame
	_check(world.player != null and is_instance_valid(world.player), "The player actor instantiates.")
	_check(world.npcs.size() == 8, "All eight named Greyfen NPC actors instantiate.")
	_check(world.hotspots.size() == 4, "All investigation hotspots instantiate.")
	_check(world.agents.size() == 4, "All four patrol agents instantiate.")
	_check(world.ui != null and world.rain != null, "HUD and rain presentation instantiate.")

	var test_agent: EnemyAgent = world.agents[0]
	var original_resolve := test_agent.resolve
	test_agent.global_position = world.player.global_position - Vector2(20, 0)
	_check(not test_agent.receive_shove(world.player.global_position, Vector2.RIGHT), "A shove cannot hit an agent behind Evan.")
	test_agent.global_position = world.player.global_position + Vector2(20, 0)
	_check(test_agent.receive_shove(world.player.global_position, Vector2.RIGHT), "A close non-lethal shove contacts an agent.")
	_check(test_agent.resolve < original_resolve, "A shove reduces resolve rather than lethal health.")
	test_agent.receive_shove(world.player.global_position, Vector2.RIGHT)
	test_agent.receive_shove(world.player.global_position, Vector2.RIGHT)
	_check(test_agent.state == EnemyAgent.State.SURRENDERED, "Repeated non-lethal pressure makes an agent surrender.")

	world._on_pause_requested()
	_check(paused and world.ui._pause_panel.visible, "Pause freezes the world and opens the in-game menu.")
	world._on_setting_changed("reduce_motion", true)
	_check(bool(restored.settings.get("reduce_motion", false)) and world.rain.reduced_motion and not world.camera.position_smoothing_enabled, "Pause-menu motion preference applies to rain and camera immediately.")
	world._resume_game()
	_check(not paused and not world.ui._pause_panel.visible, "Resume restores play and closes the in-game menu.")

	if audio_manager:
		audio_manager._ui_player.stop()
		audio_manager._ui_player.stream = null
		audio_manager._ambience_player.stop()
		audio_manager._ambience_player.stream = null
		audio_manager._ui_streams.clear()
		audio_manager._ambience_stream = null
	world.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("[gameplay] PASS")
		quit(0)
	else:
		print("[gameplay] FAIL (%d)" % failures.size())
		quit(1)
