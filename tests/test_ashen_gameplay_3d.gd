extends SceneTree

const WorldScript := preload("res://scripts/ashen_3d/ashen_game_world_3d.gd")
const StateScript := preload("res://scripts/game_state.gd")
const CollisionLayers := preload("res://scripts/ashen_3d/collision_layers_3d.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("[ashen-gameplay-3d] %s" % message)


func _run() -> void:
	var audio := root.get_node_or_null("AudioManager")
	if audio:
		audio.set_master_enabled(false)
	var state := StateScript.new()
	var world := WorldScript.new()
	world.name = "AshenGameplay3DFixture"
	world.configure(state)
	root.add_child(world)
	await process_frame
	await process_frame
	await physics_frame

	_test_world_contract(world, state)
	await _test_live_interaction(world, state)
	_test_nonlethal_combat(world)
	_test_v2_snapshot(world)
	await _test_finale_volume(world, state)

	world.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("[ashen-gameplay-3d] PASS")
		quit(0)
	else:
		print("[ashen-gameplay-3d] FAIL (%d)" % failures.size())
		quit(1)


func _test_world_contract(world, state) -> void:
	print("[ashen-gameplay-3d] debug lights=%d player=%s arrival=%s" % [world._ward_lights.size(), world.player.global_position, world.world_host.landmark_registry.get_landmark_position(&"evan_arrival")])
	_check(world.world_host != null and world.world_host.validation_errors.is_empty(), "authored five-district host builds without validation errors")
	_check(world.player is CharacterBody3D, "Evan is a CharacterBody3D")
	_check(world.player.collision_layer == CollisionLayers.PLAYER, "Evan uses the locked Player layer")
	_check(world.camera_rig.get_camera().current and is_equal_approx(world.camera_rig.get_camera().fov, 22.0), "fixed cinematic camera is current at 22 degrees")
	_check(world.weather != null and world.weather._rain is GPUParticles3D, "layered 3D weather is active")
	_check(world.story_director != null and world.ui != null, "complete story director and CanvasLayer UI are live")
	_check(world.npc_targets.size() == 8 and world.hotspot_targets.size() == 4, "all named NPCs and evidence points have 3D Area interactions")
	_check(world.agents.size() == 4, "all four stable enemy agents exist in 3D")
	_check(world._defense_volume.collision_layer == CollisionLayers.TRAVERSAL_TRIGGER, "granary finale uses the authored traversal volume")
	_check(world._ward_lights.size() == 6, "six authored ward lights establish refuge landmarks")
	var arrival: Marker3D = world.world_host.landmark_registry.get_landmark(&"evan_arrival")
	_check(arrival != null and world.player.global_position.distance_to(arrival.global_position) < 0.2, "new game begins at the semantic arrival anchor")
	_check(state.get_spatial_checkpoint().get("anchor_id") == "evan_arrival", "new game retains the semantic V2 checkpoint")


func _test_live_interaction(world, state) -> void:
	await _finish_dialogue(world.story_director, "intro_earth")
	await _finish_dialogue(world.story_director, "arrival")
	var lysa := world.npc_targets[&"lysa"] as AshenInteractable3D
	world.player.global_position = lysa.global_position + Vector3(0.0, 0.08, 1.15)
	world.player.facing = Vector3.FORWARD
	await physics_frame
	await physics_frame
	world._update_interaction_candidate()
	print("[ashen-gameplay-3d] debug lysa available=%s overlap=%s player=%s lysa=%s nearest=%s" % [lysa.available, lysa.interaction_area.overlaps_body(world.player), world.player.global_position, lysa.global_position, world._nearest_interactable])
	_check(world._nearest_interactable == lysa, "Area3D, facing priority and clear-line query select Lysa")
	world._on_player_interact_requested()
	_check(world.ui.dialogue_open and world.ui._dialogue_id == "lysa_token", "3D NPC interaction enters the real four-pass story")
	_check(not state.has_item("token"), "dialogue consequence remains gated until its authored completion")
	await _finish_dialogue(world.story_director, "lysa_token")
	_check(state.has_item("token"), "authored token consequence survives the 3D adapter")


func _test_nonlethal_combat(world) -> void:
	var agent := world.agents[0] as AshenEnemyAgent3D
	agent.global_position = world.player.global_position + world.player.facing * 0.8
	agent.resolve = 30.0
	world._on_player_shove(world.player.get_shove_origin(), world.player.facing)
	print("[ashen-gameplay-3d] debug shove state=%s resolve=%s player=%s agent=%s" % [agent.state, agent.resolve, world.player.global_position, agent.global_position])
	_check(agent.state == AshenEnemyAgent3D.State.SURRENDERED, "forward unobstructed shove resolves an agent non-lethally")
	_check(agent.collision_layer == 0, "surrendered agents no longer crowd-block the player")


func _test_v2_snapshot(world) -> void:
	world.player.global_position += Vector3(2.4, 0.0, -1.7)
	var snapshot: Dictionary = world.snapshot_data()
	_check(snapshot.get("schema_version") == 2, "playable 3D snapshot uses schema V2")
	var line: Dictionary = snapshot.get("current_line", {})
	var checkpoint: Dictionary = line.get("spatial_checkpoint", {})
	_check((checkpoint.get("position", []) as Array).size() == 3, "snapshot persists a Vector3 player position")
	_check(not str(checkpoint.get("zone_id", "")).is_empty() and not str(checkpoint.get("anchor_id", "")).is_empty(), "snapshot persists semantic zone and anchor IDs")
	var agent_states: Dictionary = line.get("agent_states", {})
	_check(agent_states.size() == 4 and agent_states.has("west_road_observer"), "snapshot keys enemies by stable agent ID")
	_check(str((agent_states["west_road_observer"] as Dictionary).get("agent_id", "")) == "west_road_observer", "saved enemy payload embeds stable identity")


func _test_finale_volume(world, state) -> void:
	state.current_line["stage"] = "finale_defense"
	state.current_line["finale_time"] = 38.0
	world.story_director.director._finale_remaining = 38.0
	world.player.global_position = world._defense_volume.global_position + Vector3.UP * 0.1
	await physics_frame
	var before := float(state.current_line["finale_time"])
	print("[ashen-gameplay-3d] debug defense overlap=%s player=%s volume=%s stage=%s" % [world._defense_volume.overlaps_body(world.player), world.player.global_position, world._defense_volume.global_position, world.story_director.get_stage()])
	world._tick_finale_3d(1.0)
	_check(float(state.current_line["finale_time"]) < before, "finale clock advances inside the authored granary volume")
	world.player.global_position += Vector3(40.0, 0.0, 0.0)
	await physics_frame
	var held := float(state.current_line["finale_time"])
	world._tick_finale_3d(1.0)
	_check(is_equal_approx(float(state.current_line["finale_time"]), held), "leaving the visible defense volume pauses rather than silently failing the operation")


func _finish_dialogue(adapter: AshenStoryDirectorAdapter3D, expected_id: String) -> void:
	for _step in range(40):
		if not adapter.ui.dialogue_open or adapter.ui._dialogue_id != expected_id:
			return
		adapter.advance_dialogue()
		await process_frame
	_check(false, "dialogue '%s' completes within the test bound" % expected_id)
