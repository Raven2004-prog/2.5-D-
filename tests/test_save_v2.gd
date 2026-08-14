extends SceneTree
## Save-schema V2 and V1 migration regression. Run with:
## Godot --headless --path <project> --script res://tests/test_save_v2.gd

const StateScript := preload("res://scripts/game_state.gd")
const SaveSystemScript := preload("res://scripts/save_system.gd")
const TEST_SAVE_PATH := "user://ash_at_greyfen_save_v2_test.json"

var _failures := 0


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("[save-v2] Ash at Greyfen migration checks")
	_test_new_game_contract()
	_test_all_stage_anchor_mappings()
	_test_v1_migration_preserves_story()
	_test_content_version_routing()
	_test_v2_validation_is_atomic()
	_test_save_envelope_remains_compatible()
	if _failures == 0:
		print("[save-v2] PASS")
		quit(0)
	else:
		printerr("[save-v2] FAIL: %d assertion(s)" % _failures)
		quit(1)


func _test_new_game_contract() -> void:
	var state := StateScript.new()
	var data := state.to_save_data()
	_expect(data.get("schema_version") == 2, "new saves use payload schema V2")
	_expect(data.get("content_version") == "greyfen-arc1-2.0", "new saves use the 2.5D content identity")
	var checkpoint: Dictionary = data["current_line"].get("spatial_checkpoint", {})
	_expect(checkpoint.get("zone_id") == "fen_road", "new game begins in the semantic fen-road zone")
	_expect(checkpoint.get("anchor_id") == "evan_arrival", "new game begins at the authored arrival anchor")
	_expect(checkpoint.get("position") == [0.0, 0.0, 0.0], "spatial checkpoint stores a finite XYZ fallback")
	_expect(checkpoint.get("facing") == "north_east", "spatial checkpoint stores semantic facing")
	_expect(state.settings.get("visual_quality") == "high", "visual quality defaults to high")
	_expect(state.settings.get("depth_of_field") == true, "depth of field defaults on")
	_expect(is_equal_approx(float(state.settings.get("weather_density")), 1.0), "weather density defaults to full")
	_expect(
		state.set_spatial_checkpoint("refuge_row", "granary_defense", Vector3(4.0, 0.25, -8.5), "south"),
		"runtime can record a valid 3D checkpoint"
	)
	var prior := state.get_spatial_checkpoint()
	_expect(
		not state.set_spatial_checkpoint("refuge_row", "granary_defense", Vector3.ZERO, "downstage"),
		"invalid facing cannot poison a checkpoint"
	)
	_expect(state.get_spatial_checkpoint() == prior, "a rejected checkpoint leaves the prior checkpoint intact")


func _test_all_stage_anchor_mappings() -> void:
	var state := StateScript.new()
	_expect(StateScript.STAGE_CHECKPOINTS.size() == 16, "all sixteen shipped story stages have migration anchors")
	for stage: String in StateScript.STAGE_CHECKPOINTS.keys():
		var checkpoint := state.checkpoint_for_stage(stage)
		_expect(not str(checkpoint.get("zone_id", "")).is_empty(), "stage '%s' has a zone" % stage)
		_expect(not str(checkpoint.get("anchor_id", "")).is_empty(), "stage '%s' has an anchor" % stage)
		var position: Variant = checkpoint.get("position", [])
		_expect(position is Array and position.size() == 3, "stage '%s' has an XYZ fallback" % stage)
		_expect(StateScript.FACING_IDS.has(checkpoint.get("facing", "")), "stage '%s' has an approved facing" % stage)
	var fallback := state.checkpoint_for_stage("corrupt_stage")
	_expect(fallback == state.checkpoint_for_stage("arrival"), "unknown runtime stage lookup falls back to safe arrival")


func _test_v1_migration_preserves_story() -> void:
	var legacy := _legacy_v1_fixture()
	var state := StateScript.new()
	_expect(state.load_save_data(legacy), "known V1 payload migrates before V2 content rejection")
	_expect(state.retained.get("loop_index") == 3, "migration preserves loop index")
	_expect(state.retained.get("knowledge") == ["phone", "powder", "signal", "gate"], "migration preserves retained knowledge")
	_expect(state.retained.get("echo_log") == ["first", "second", "third"], "migration preserves authored echoes")
	_expect(state.current_line.get("stage") == "finale_defense", "migration preserves the exact narrative stage")
	_expect(state.current_line.get("physical_evidence") == ["powder", "signal", "gate"], "migration preserves present-line evidence")
	_expect(state.current_line.get("contributions") == ["nessa", "piri", "brann", "kesh", "lysa", "mara"], "migration preserves voluntary contributions")
	_expect(state.current_line.get("pending_story") == "finale_warning", "migration preserves pending story transactions")
	_expect(state.current_line.get("narrative_extension") == {"witness": "Evan", "consent": true}, "migration preserves unknown narrative extension fields")
	_expect(state.current_line.get("player_position") == [1370.0, 680.0], "legacy coordinates are retained losslessly for diagnostics")

	var checkpoint: Dictionary = state.current_line.get("spatial_checkpoint", {})
	_expect(checkpoint.get("zone_id") == "refuge_row", "finale migration selects the approved refuge-row zone")
	_expect(checkpoint.get("anchor_id") == "granary_defense", "finale migration selects the safe granary anchor")
	_expect(checkpoint.get("position") == [0.0, 0.0, 0.0], "migration does not scale obsolete pixel coordinates into metres")
	_expect(checkpoint.get("position") != [1370.0, 0.0, 680.0], "legacy XY never masquerades as XYZ")

	var agents: Dictionary = state.current_line.get("agent_states", {})
	var observer: Dictionary = agents.get("West-road observer", {})
	var buyer: Dictionary = agents.get("Tunnel buyer", {})
	_expect(observer.get("agent_id") == "west_road_observer", "legacy observer receives a stable identity")
	_expect(buyer.get("agent_id") == "tunnel_buyer", "legacy tunnel buyer receives a stable identity")
	_expect(observer.get("legacy_transform_2d") == true, "legacy agent transforms are marked as 2D instead of scaled")
	_expect(observer.get("resolve") == 34.0 and observer.get("state") == 8, "migration preserves agent gameplay state")

	_expect(state.settings.get("reduce_motion") == true, "migration preserves accessibility settings")
	_expect(state.settings.get("master_audio") == false, "migration preserves audio preference")
	_expect(state.settings.get("rain_intensity") == 0.65, "migration preserves legacy rain preference")
	_expect(state.settings.get("personal_extension") == "preserved", "migration preserves unknown settings")
	_expect(state.settings.get("visual_quality") == "high", "migration adds a visual-quality default")
	_expect(state.settings.get("depth_of_field") == true, "migration adds the depth-of-field default")
	_expect(state.settings.get("weather_density") == 1.0, "migration adds the weather-density default")

	var rewritten := state.to_save_data()
	_expect(rewritten.get("schema_version") == 2, "the next save rewrites migrated state as V2")
	_expect(rewritten.get("content_version") == "greyfen-arc1-2.0", "the next save adopts current content identity")
	var roundtrip := StateScript.new()
	_expect(roundtrip.load_save_data(rewritten), "migrated V2 state survives a second load")
	_expect(roundtrip.current_line.get("finale_events") == ["piri", "brann"], "finale milestones survive migration and roundtrip")


func _test_content_version_routing() -> void:
	var unknown_v1 := _legacy_v1_fixture()
	unknown_v1["content_version"] = "greyfen-unknown-1.0"
	_expect(not StateScript.new().load_save_data(unknown_v1), "unknown V1 content is rejected after schema detection")
	var corrupt_stage := _legacy_v1_fixture()
	corrupt_stage["current_line"]["stage"] = "after_everything"
	_expect(not StateScript.new().load_save_data(corrupt_stage), "unknown V1 stage cannot create an unsafe or soft-locked migration")

	var mislabeled_v2 := StateScript.new().to_save_data()
	mislabeled_v2["content_version"] = "greyfen-arc1-1.0"
	_expect(not StateScript.new().load_save_data(mislabeled_v2), "V2 payload cannot claim the legacy content identity")

	var future := StateScript.new().to_save_data()
	future["schema_version"] = 3
	_expect(not StateScript.new().load_save_data(future), "future schemas are rejected without mutation")

	var fractional := StateScript.new().to_save_data()
	fractional["schema_version"] = 2.5
	_expect(not StateScript.new().load_save_data(fractional), "fractional schema versions are rejected")


func _test_v2_validation_is_atomic() -> void:
	var state := StateScript.new()
	state.remember("powder", "Powder under the boards.")
	var before := state.to_save_data()

	var bad_position := before.duplicate(true)
	bad_position["current_line"]["spatial_checkpoint"]["position"] = [1.0, 2.0]
	_expect(not state.load_save_data(bad_position), "V2 rejects a non-XYZ checkpoint")
	_expect(state.to_save_data() == before, "failed checkpoint validation does not partially mutate state")

	var bad_facing := before.duplicate(true)
	bad_facing["current_line"]["spatial_checkpoint"]["facing"] = "toward_camera"
	_expect(not state.load_save_data(bad_facing), "V2 rejects an unknown facing token")
	_expect(state.to_save_data() == before, "failed facing validation remains atomic")

	var bad_quality := before.duplicate(true)
	bad_quality["settings"]["visual_quality"] = "cinematic_plus"
	_expect(not state.load_save_data(bad_quality), "V2 rejects unsupported visual-quality IDs")

	var duplicate_agents := before.duplicate(true)
	duplicate_agents["current_line"]["agent_states"] = {
		"first": {"agent_id": "granary_watch", "state": 0},
		"localized label": {"agent_id": "granary_watch", "state": 2},
	}
	_expect(not state.load_save_data(duplicate_agents), "duplicate stable agent identities are rejected")

	var id_keyed := before.duplicate(true)
	id_keyed["current_line"]["agent_states"] = {
		"signal_runner": {
			"agent_id": "signal_runner",
			"state": 2,
			"resolve": 80.0,
			"suspicion": 0.5,
			"patrol_index": 1,
			"position": [4.0, 0.0, -2.0],
			"last_known": [3.0, 0.0, -2.0],
			"facing": [1.0, 0.0, 0.0],
		},
	}
	_expect(state.load_save_data(id_keyed), "V2 accepts canonical ID-keyed 3D agent state")


func _test_save_envelope_remains_compatible() -> void:
	var saves := SaveSystemScript.new()
	saves.save_path = TEST_SAVE_PATH
	saves.reset_save()
	var legacy := _legacy_v1_fixture()
	_expect(saves.save_game(legacy), "atomic envelope can still store a V1 payload")
	var loaded_legacy := saves.continue_game()
	_expect(loaded_legacy.get("schema_version") == 1, "save envelope returns legacy payload for state-level migration")
	var migrated := StateScript.new()
	_expect(migrated.load_save_data(loaded_legacy), "legacy envelope payload migrates successfully")
	_expect(saves.save_game(migrated.to_save_data()), "atomic envelope replaces legacy payload with V2")
	_expect(not FileAccess.file_exists(TEST_SAVE_PATH + ".bak"), "successful migration save leaves no stale backup")
	var loaded_v2 := saves.continue_game()
	_expect(loaded_v2.get("schema_version") == 2, "replacement envelope contains V2 payload")
	_expect(saves.reset_save(), "migration test save cleans up safely")
	saves.free()


func _legacy_v1_fixture() -> Dictionary:
	return {
		"schema_version": 1,
		"content_version": "greyfen-arc1-1.0",
		"retained": {
			"loop_index": 3,
			"death_count": 3,
			"soul_scars": 3,
			"knowledge": ["phone", "powder", "signal", "gate"],
			"echo_log": ["first", "second", "third"],
			"trauma_tags": ["smoke", "river", "isolation"],
			"g0_formed": true,
			"g1_formed": false,
		},
		"current_line": {
			"stage": "finale_defense",
			"physical_evidence": ["powder", "signal", "gate"],
			"inventory": ["lysa_token"],
			"contributions": ["nessa", "piri", "brann", "kesh", "lysa", "mara"],
			"npc_tags": {"mara": ["accepted_risk"], "lysa": ["named_route"]},
			"flags": ["evan_accepted_compact", "tomas_surrendered", "executed_powder"],
			"player_position": [1370.0, 680.0],
			"finale_time": 19.25,
			"finale_events": ["piri", "brann"],
			"agent_states": {
				"West-road observer": {
					"state": 8,
					"resolve": 34.0,
					"suspicion": 0.0,
					"position": [640.0, 710.0],
					"last_known": [1370.0, 680.0],
					"patrol_index": 2,
					"facing": [1.0, 0.0],
				},
				"Tunnel buyer": {
					"state": 2,
					"resolve": 73.0,
					"suspicion": 1.0,
					"position": [1100.0, 910.0],
					"last_known": [1370.0, 680.0],
					"patrol_index": 1,
					"facing": [0.0, -1.0],
				},
			},
			"pending_story": "finale_warning",
			"pending_choices": [{"id": "hold", "label": "Hold the line"}],
			"pending_return": {},
			"narrative_extension": {"witness": "Evan", "consent": true},
		},
		"settings": {
			"reduce_motion": true,
			"reduce_flash": true,
			"master_audio": false,
			"high_contrast": true,
			"rain_intensity": 0.65,
			"text_scale": 1.2,
			"personal_extension": "preserved",
		},
	}


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("  [ok] %s" % label)
	else:
		_failures += 1
		printerr("  [FAIL] %s" % label)
