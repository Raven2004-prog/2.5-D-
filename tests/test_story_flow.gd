extends SceneTree
## Full Arc 1 story-state regression.
##
## The first dialogue is completed through the real GameUI signal path. If that
## path is broken, the test records the integration failure and uses an explicit
## test-only dispatch fallback so every later story gate is still audited.

var failures: Array[String] = []
var _finished_ids: Array[String] = []
var _completed_state: AshGameState


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if condition:
		print("  [ok] %s" % message)
	else:
		failures.append(message)
		push_error("[story-flow] %s" % message)


func _run() -> void:
	print("[story-flow] Arc 1 arrival-to-ending regression")
	var state := AshGameState.new()
	var audio_manager := root.get_node_or_null("AudioManager")
	if audio_manager:
		audio_manager.set_master_enabled(false)
	var world := GreyfenGameWorld.new()
	world.configure(state)
	root.add_child(world)
	await process_frame
	await process_frame
	await process_frame

	# Keep this story-state regression deterministic while retaining the real
	# actors, UI, hotspots, signals, and finale state transitions.
	world.player.set_physics_process(false)
	for agent in world.agents:
		agent.set_physics_process(false)
	world.story_completed.connect(_on_story_completed)
	world.ui.dialogue_finished.connect(_capture_finished_id)

	_check(world._stage() == "arrival", "new game begins at arrival")
	_check(world.ui.dialogue_open and world.ui._dialogue_id == "intro_earth", "opening Earth memory is presented")
	_check(not (world.npcs["mara"] as NpcActor).available and (world.npcs["lysa"] as NpcActor).available, "the untranslated opening exposes only the fleeing courier as an interaction")

	# Real player-facing page advancement. This must emit the ID that was open.
	_drive_plain_dialogue_to_end(world.ui)
	var opening_dispatch_ok := (
		_finished_ids.size() == 1
		and _finished_ids[0] == "intro_earth"
		and world.ui.dialogue_open
		and world.ui._dialogue_id == "arrival"
	)
	_check(
		opening_dispatch_ok,
		"opening dialogue emits its active story ID before closing (received '%s')" % (
			_finished_ids[0] if not _finished_ids.is_empty() else "<no signal>"
		)
	)
	var empty_id_guard_ok := (
		_finished_ids.is_empty()
		or _finished_ids[0] != ""
		or not world._pending_return.is_empty()
	)
	_check(
		empty_id_guard_ok,
		"ordinary dialogue completion cannot be mistaken for a pending Return"
	)
	if not opening_dispatch_ok:
		# Continue the audit without changing gameplay code.
		world._on_dialogue_finished("intro_earth")
		await process_frame

	await _complete_story(world, "arrival")
	_check(bool(state.retained.get("g0_formed", false)), "arrival forms G-0")

	# Lysa's token and Mara's first hearing.
	_check((world.npcs["lysa"] as NpcActor).display_name == "Fleeing courier", "Lysa's name is not exposed before the first accommodation scene")
	await _talk_to(world, "lysa", "lysa_token")
	await _complete_story(world, "lysa_token")
	_check(world._stage() == "reach_mara", "Lysa's token advances the objective to Mara")
	_check(state.has_item("token") and state.knows("token"), "token is physical evidence and retained knowledge")
	_check((world.npcs["mara"] as NpcActor).available and not (world.npcs["lysa"] as NpcActor).available, "the token stage directs interaction to the unnamed warden")
	await _talk_to(world, "mara", "mara_arrest")
	await _complete_story(world, "mara_arrest")
	_check((world.npcs["lysa"] as NpcActor).display_name == "Lysa" and state.knows("lysa_name"), "Mara names Lysa in-scene before the UI uses her name")
	_check(world.ui.dialogue_open and world.ui._dialogue_id == "nessa_treatment", "Mara's custody scene reaches Nessa's treatment")
	await _complete_story(world, "nessa_treatment")
	_check(world.ui.dialogue_open and world.ui._dialogue_id == "tamsin_interrogation", "Nessa's treatment reaches Tamsin's interrogation")
	await _complete_story(world, "tamsin_interrogation")
	_check(world._stage() == "baseline_find_granary", "Mara sends Evan toward the granary")

	# First catastrophe and Return.
	await _inspect(world, "powder", "powder_discovery")
	_check(state.has_physical_evidence("powder") and state.knows("powder"), "first line records the granary powder")
	await _check_reload_dialogue(state.to_save_data(), "baseline_find_granary", "powder_discovery")
	await _complete_story(world, "powder_discovery")
	_check(world.ui._dialogue_id == "catastrophe_one", "powder discovery triggers the first authored catastrophe")
	await _check_reload_dialogue(state.to_save_data(), "baseline_find_granary", "catastrophe_one")
	await _complete_story(world, "catastrophe_one")
	await _wait_for_return_intro(world, "return_one")
	_check(int(state.retained.get("death_count", 0)) == 1, "first Return records one authored death")
	_check(int(state.retained.get("soul_scars", 0)) == 1, "first Return records one soul scar")
	_check(not state.has_item("token") and not state.has_physical_evidence("powder"), "first Return resets token and physical proof")
	_check(state.knows("powder") and state.knows("return_rule"), "first Return retains learned facts")
	await _complete_story(world, "return_one")

	# Brann's prediction, the stopped powder fuse, and second catastrophe.
	await _talk_to(world, "brann", "brann_prediction")
	await _complete_story(world, "brann_prediction")
	_check(world._stage() == "one_fuse", "Brann's verified prediction opens the powder intervention")
	_check(state.has_flag("brann_prediction") and state.npc_has_tag("brann", "listened_to_prediction"), "Brann's present-line hearing is recorded")
	await _inspect(world, "powder", "powder_discovery")
	await _check_reload_dialogue(state.to_save_data(), "one_fuse", "powder_discovery")
	await _complete_story(world, "powder_discovery")
	_check(world._stage() == "one_fuse_report", "stopping one fuse requires a report to Mara")
	await _talk_to(world, "mara", "catastrophe_two")
	await _complete_story(world, "catastrophe_two")
	await _wait_for_return_intro(world, "return_two")
	_check(int(state.retained.get("death_count", 0)) == 2, "second Return records Corvin's authored killing")
	_check(not state.has_flag("brann_prediction"), "second Return clears Brann's erased-line trust state")
	_check(state.knows("powder"), "second Return preserves threat knowledge")
	await _complete_story(world, "return_two")

	# Third pass: reconstruct all three foundations in the same physical line.
	await _inspect_and_finish(world, "powder", "powder_discovery")
	_check(world._stage() == "return_two", "one foundation cannot advance the third pass")
	await _inspect_and_finish(world, "signal", "signal_discovery")
	_check(world._stage() == "return_two", "two foundations cannot advance the third pass")
	await _inspect(world, "gate", "gate_discovery")
	await _check_reload_dialogue(state.to_save_data(), "return_two", "gate_discovery")
	await _complete_story(world, "gate_discovery")
	_check(state.all_foundations_present(), "third pass holds powder, signal, and gate proof together")
	_check(world._stage() == "wrong_hero_report", "three foundations unlock Mara's complete-plan report")

	# The wrong-hero choice must dispatch into its authored consequence.
	await _talk_to(world, "mara", "third_plan")
	await _choose(world, "third_plan", "assign_ghost_route")
	var third_plan_dispatch_ok := world.ui.dialogue_open and world.ui._dialogue_id == "wrong_hero"
	_check(
		third_plan_dispatch_ok,
		"the third-pass plan choice reaches its authored wrong-hero consequence"
	)
	if not third_plan_dispatch_ok:
		world._show_story("wrong_hero")
		await process_frame
	await _complete_story(world, "wrong_hero")
	_check(world.ui._dialogue_id == "catastrophe_three", "wrong-hero report reaches the third authored catastrophe")
	await _complete_story(world, "catastrophe_three")
	await _wait_for_return_intro(world, "return_three")
	_check(int(state.retained.get("death_count", 0)) == 3, "third Return records the deliberate secondary-collapse death")
	_check(int(state.retained.get("loop_index", 0)) == 3, "surviving line is pass four")
	_check(state.present_foundation_count() == 0 and state.contribution_count() == 0, "third Return clears erased proof and consent")
	_check(state.knows("powder") and state.knows("signal") and state.knows("gate"), "all three threat facts remain remembered")
	await _complete_story(world, "return_three")

	# Fourth line: rebuild examinable proof, including Lysa's tunnel route.
	await _inspect_and_finish(world, "powder", "powder_discovery")
	await _inspect_and_finish(world, "signal", "signal_discovery")
	await _inspect_and_finish(world, "gate", "gate_discovery")
	await _inspect_without_dialogue(world, "tunnel")
	_check(state.all_foundations_present(), "surviving line re-establishes all three physical foundations")
	_check(state.has_physical_evidence("tunnel") and state.knows("tunnel"), "surviving line traces the tunnel buyer for Lysa")
	_check(world._stage() == "return_three", "evidence alone does not skip ally consent")

	# Five allies independently accept their contributions before Mara.
	for contribution in [
		["nessa", "nessa_contribution"],
		["piri", "piri_contribution"],
		["brann", "brann_contribution"],
		["kesh", "kesh_contribution"],
		["lysa", "lysa_contribution"],
	]:
		await _talk_to(world, contribution[0], contribution[1])
		await _complete_story(world, contribution[1])
		_check(state.has_contribution(contribution[0]), "%s's independent contribution is recorded" % str(contribution[0]).capitalize())
		_check(state.npc_has_tag(contribution[0], "accepted_risk"), "%s's accepted risk exists in this line" % str(contribution[0]).capitalize())
	_check(state.contribution_count() == 5, "five ally contributions are ready before Mara")
	_check(world._first_five_ready() and world._stage() == "mara_ready", "five allies and three foundations unlock Mara's disclosure")

	# Consent-positive Mara choice and the Ash Witness Compact.
	await _talk_to(world, "mara", "mara_disclosure")
	await _choose(world, "mara_disclosure", "separate_fact")
	_check(state.npc_has_tag("mara", "accepted_disclosure"), "Mara accepts fact-separated disclosure")
	_check(world.ui.dialogue_open and world.ui._dialogue_id == "transfer_order", "consent-positive choice exposes the transfer order")
	await _complete_story(world, "transfer_order")
	_check(world.ui.dialogue_open and world.ui._dialogue_id == "ash_compact", "transfer order leads into the Ash Witness Compact")
	await _complete_story(world, "ash_compact")
	_check(world.ui.dialogue_open and world.ui._dialogue_id == "evan_compact", "Mara's surety leaves Evan an explicit choice")
	await _choose(world, "evan_compact", "ask_time")
	_check(world._stage() == "compact_offer" and not state.has_contribution("mara"), "Evan can step away without the game silently accepting for him")
	await _talk_to(world, "mara", "evan_compact")
	await _choose(world, "evan_compact", "accept_witness")
	_check(state.has_contribution("mara") and state.all_contributions_ready(), "Mara's Compact completes all six contributions")
	_check(state.has_flag("evan_accepted_compact") and world._stage() == "finale_to_tomas", "Evan's free acceptance advances to Tomas beneath the granary")
	_check(state.knows("ash_witness"), "Ash Witness terms are retained")

	# Non-coercive Tomas surrender and coordinated finale.
	await _talk_to(world, "tomas", "tomas_surrender")
	await _choose(world, "tomas_surrender", "offer_exit")
	_check(state.has_flag("tomas_surrendered") and state.npc_has_tag("tomas", "surrendered_without_violence"), "Tomas surrenders without coercion")
	_check(world._stage() == "finale_to_tomas" and world.ui._dialogue_id == "tomas_accepts", "Tomas's offered exit presents his explicit acceptance")
	await _check_reload_dialogue(state.to_save_data(), "finale_to_tomas", "tomas_accepts")
	await _complete_story(world, "tomas_accepts")
	_check(world._stage() == "finale_defense", "Tomas's completed acceptance begins the final defense")
	_check(world._finale_remaining > 37.9, "finale starts with the full defense window")
	_check(float(state.current_line.get("finale_time", 0.0)) > 37.9 and state.has_flag("executed_powder"), "the first finale checkpoint includes its timer and Tomas's powder action")
	var defense_time := world._finale_remaining
	world.player.global_position = world.world_map.get_landmark("anchor")
	world._process(2.0)
	_check(is_equal_approx(world._finale_remaining, defense_time), "leaving the granary line cannot win the defense by hiding elsewhere")
	world.player.global_position = world.world_map.get_landmark("granary") + Vector2(0, 80)
	var chasing := 0
	for agent in world.agents:
		if agent.state == EnemyAgent.State.CHASE:
			chasing += 1
	_check(chasing == world.agents.size(), "all surviving agents activate for the finale")
	var pressured_agent: EnemyAgent = world.agents[0]
	pressured_agent.global_position = world.player.global_position + Vector2(20, 0)
	pressured_agent.receive_shove(world.player.global_position, Vector2.RIGHT)
	pressured_agent.receive_shove(world.player.global_position, Vector2.RIGHT)
	pressured_agent.receive_shove(world.player.global_position, Vector2.RIGHT)
	_check(pressured_agent.state == EnemyAgent.State.SURRENDERED, "non-lethal pressure can remove one finale attacker")

	for delta in [7.1, 6.1, 7.1, 7.1, 6.1]:
		world._process(delta)
	_check(world._finale_events.has("piri"), "Piri's true cadence fires during the finale")
	_check(world._finale_events.has("brann"), "Brann's public refusal fires during the finale")
	_check(world._finale_events.has("nessa"), "Nessa's clinic evacuation fires during the finale")
	_check(world._finale_events.has("kesh"), "Kesh's Refuge Row shelter action fires during the finale")
	_check(world._finale_events.has("lysa"), "Lysa's tunnel exposure fires during the finale")
	_check(world._finale_events.has("mara"), "Mara's water-gate action fires during the finale")
	_check(state.has_flag("executed_powder") and state.has_flag("executed_signal") and state.has_flag("executed_gate"), "the HUD resolves each foundation only after the matching action occurs")
	await _check_reload_finale(state.to_save_data(), world._finale_events.size(), 1)
	world._process(5.0)
	await process_frame
	_check(world._stage() == "finale_resolved", "surviving the finale resolves Greyfen's attack")
	_check(world.ui.dialogue_open and world.ui._dialogue_id == "corvin_lens", "finale resolution reaches Corvin's soul-lens scene")
	await _check_reload_dialogue(state.to_save_data(), "finale_resolved", "corvin_lens")
	var surrendered_agents := 0
	for agent in world.agents:
		if agent.state == EnemyAgent.State.SURRENDERED:
			surrendered_agents += 1
	_check(surrendered_agents == world.agents.size(), "finale resolves every attacker non-lethally")

	# Corvin, tribunal, G-1, ending, and completion signal.
	await _complete_story(world, "corvin_lens")
	_check(world._stage() == "tribunal" and world.ui._dialogue_id == "tribunal", "Corvin scene advances to the tribunal")
	await _check_reload_dialogue(state.to_save_data(), "tribunal", "tribunal")
	await _complete_story(world, "tribunal")
	_check(bool(state.retained.get("g1_formed", false)), "tribunal forms G-1")
	_check(world._stage() == "complete" and world.ui._dialogue_id == "ending", "tribunal advances to the Lysford ending")
	await _complete_story(world, "ending")
	_check(_completed_state == state, "ending emits story_completed with the final state")
	_check(int(state.retained.get("death_count", 0)) == 3 and int(state.retained.get("soul_scars", 0)) == 3, "ending carries exactly three authored Returns and scars")
	_check(state.all_foundations_present() and state.all_contributions_ready(), "ending preserves the surviving line's proof and six choices")
	_check(state.has_flag("tomas_surrendered") and state.knows("ash_witness"), "ending preserves Tomas's surrender and Compact knowledge")

	var restored := AshGameState.new()
	_check(restored.load_save_data(state.to_save_data()), "completed Arc 1 state survives save encoding")
	_check(bool(restored.retained.get("g1_formed", false)) and restored.current_line.get("stage") == "complete", "completed save restores G-1 and ending stage")

	# Custom SceneTree tests quit more abruptly than the normal title-return path;
	# release procedural playback explicitly so engine leak diagnostics stay useful.
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
	_completed_state = null
	restored = null
	state = null
	world = null
	call_deferred("_finish")


func _capture_finished_id(id: String) -> void:
	_finished_ids.append(id)


func _finish() -> void:
	if failures.is_empty():
		print("[story-flow] PASS")
		quit(0)
	else:
		print("[story-flow] FAIL (%d issue(s)); downstream gates were audited with test-only dialogue dispatch fallback" % failures.size())
		quit(1)


func _on_story_completed(state: AshGameState) -> void:
	_completed_state = state


func _check_reload_dialogue(data: Dictionary, expected_stage: String, expected_dialogue: String) -> void:
	var reloaded_state := AshGameState.new()
	_check(reloaded_state.load_save_data(data), "save at '%s' reloads into a valid state" % expected_stage)
	var reloaded_world := GreyfenGameWorld.new()
	reloaded_world.configure(reloaded_state)
	root.add_child(reloaded_world)
	await process_frame
	await process_frame
	await process_frame
	_check(reloaded_world._stage() == expected_stage and reloaded_world.ui.dialogue_open and reloaded_world.ui._dialogue_id == expected_dialogue, "Continue reopens '%s' instead of soft-locking" % expected_dialogue)
	if expected_dialogue.begins_with("catastrophe"):
		_check(not reloaded_world._pending_return.is_empty(), "Continue restores the authored Return attached to '%s'" % expected_dialogue)
	reloaded_world.queue_free()
	await process_frame
	await process_frame


func _check_reload_finale(data: Dictionary, expected_event_count: int, expected_surrendered: int) -> void:
	var reloaded_state := AshGameState.new()
	_check(reloaded_state.load_save_data(data), "mid-finale checkpoint reloads into a valid state")
	var reloaded_world := GreyfenGameWorld.new()
	reloaded_world.configure(reloaded_state)
	root.add_child(reloaded_world)
	await process_frame
	await process_frame
	await process_frame
	_check(reloaded_world._stage() == "finale_defense" and reloaded_world._finale_events.size() == expected_event_count, "Continue preserves fired finale milestones without replaying them")
	_check(is_equal_approx(reloaded_world._finale_remaining, float(reloaded_state.current_line.get("finale_time", 0.0))), "Continue restores the saved finale clock")
	var surrendered := 0
	for agent in reloaded_world.agents:
		if agent.state == EnemyAgent.State.SURRENDERED:
			surrendered += 1
	_check(surrendered == expected_surrendered, "Continue preserves non-lethal finale surrenders")
	reloaded_world.queue_free()
	await process_frame
	await process_frame


func _drive_plain_dialogue_to_end(ui: GameUI) -> void:
	var guard := 0
	var starting_id := ui._dialogue_id
	while ui.dialogue_open and ui._dialogue_id == starting_id and guard < 24:
		ui.advance_dialogue()
		guard += 1
	_check(guard < 24 and (not ui.dialogue_open or ui._dialogue_id != starting_id), "plain dialogue closes within a bounded number of advances")


func _complete_story(world: GreyfenGameWorld, id: String) -> void:
	_check(world.ui.dialogue_open, "dialogue '%s' is open" % id)
	_check(world.ui._dialogue_id == id, "dialogue '%s' is the active story beat" % id)
	_check(not StoryContent.get_dialogue(id).is_empty(), "dialogue '%s' has authored content" % id)
	world.ui.hide_dialogue()
	world._on_dialogue_finished(id)
	await process_frame


func _talk_to(world: GreyfenGameWorld, npc_id: String, expected_dialogue: String) -> void:
	_check(world.npcs.has(npc_id), "NPC '%s' exists" % npc_id)
	world.nearest_interactable = world.npcs[npc_id]
	world._interact()
	await process_frame
	_check(world.ui.dialogue_open and world.ui._dialogue_id == expected_dialogue, "talking to %s opens '%s'" % [npc_id, expected_dialogue])


func _inspect(world: GreyfenGameWorld, hotspot_id: String, expected_dialogue: String) -> void:
	_check(world.hotspots.has(hotspot_id), "hotspot '%s' exists" % hotspot_id)
	_check((world.hotspots[hotspot_id] as EvidenceHotspot).available, "hotspot '%s' is available at this stage" % hotspot_id)
	world.nearest_interactable = world.hotspots[hotspot_id]
	world._interact()
	await process_frame
	_check(world.ui.dialogue_open and world.ui._dialogue_id == expected_dialogue, "inspecting %s opens '%s'" % [hotspot_id, expected_dialogue])


func _inspect_and_finish(world: GreyfenGameWorld, hotspot_id: String, dialogue_id: String) -> void:
	await _inspect(world, hotspot_id, dialogue_id)
	await _complete_story(world, dialogue_id)


func _inspect_without_dialogue(world: GreyfenGameWorld, hotspot_id: String) -> void:
	_check((world.hotspots[hotspot_id] as EvidenceHotspot).available, "hotspot '%s' is available at this stage" % hotspot_id)
	world.nearest_interactable = world.hotspots[hotspot_id]
	world._interact()
	await process_frame
	_check(not world.ui.dialogue_open, "inspecting %s resolves without an extra dialogue" % hotspot_id)


func _choose(world: GreyfenGameWorld, dialogue_id: String, choice_id: String) -> void:
	_check(world.ui.dialogue_open and world.ui._dialogue_id == dialogue_id, "choice dialogue '%s' is active" % dialogue_id)
	var guard := 0
	while world.ui._page_index < world.ui._pages.size() - 1 and guard < 24:
		world.ui.advance_dialogue()
		guard += 1
	world.ui.advance_dialogue() # Reveal the pending choice buttons.
	_check(world.ui.dialogue_open, "choice dialogue '%s' waits for an explicit answer" % dialogue_id)
	world.ui._select_choice(choice_id)
	await process_frame


func _wait_for_return_intro(world: GreyfenGameWorld, expected_stage: String) -> void:
	_check(world._stage() == expected_stage, "authored death resets immediately to '%s'" % expected_stage)
	await create_timer(0.78).timeout
	await process_frame
	_check(world.ui.dialogue_open and world.ui._dialogue_id == expected_stage, "Return presents '%s' introduction" % expected_stage)
