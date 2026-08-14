extends Node3D
class_name AshenGreyfenGameWorld3D

## Playable Ashen Diorama world. This is the compatibility seam between the
## complete four-pass narrative and the new metre-scale 3D simulation.

signal autosave_requested(data: Dictionary)
signal story_completed(state: AshGameState)
signal return_to_title_requested

const HostScript := preload("res://scripts/ashen_3d/world_host_3d.gd")
const PlayerScript := preload("res://scripts/ashen_3d/player_actor_3d.gd")
const CameraScript := preload("res://scripts/ashen_3d/camera_rig_3d.gd")
const WeatherScript := preload("res://scripts/ashen_3d/weather_3d.gd")
const SoundscapeScript := preload("res://scripts/ashen_3d/soundscape_3d.gd")
const DirectorScript := preload("res://scripts/ashen_3d/story_director_adapter_3d.gd")
const EnemyScript := preload("res://scripts/ashen_3d/enemy_agent_3d.gd")
const BillboardScript := preload("res://scripts/ashen_3d/billboard_actor_3d.gd")
const InteractableScript := preload("res://scripts/ashen_3d/interactable_3d.gd")
const CollisionLayers := preload("res://scripts/ashen_3d/collision_layers_3d.gd")

const NPC_ANCHORS := {
	&"mara": &"mara_keep",
	&"tamsin": &"tamsin",
	&"lysa": &"lysa",
	&"nessa": &"nessa_clinic",
	&"brann": &"brann",
	&"kesh": &"kesh",
	&"piri": &"piri_signal",
	&"tomas": &"tomas",
}

const NPC_LABELS := {
	&"mara": "Mara",
	&"tamsin": "Tamsin",
	&"lysa": "Lysa",
	&"nessa": "Nessa",
	&"brann": "Brann",
	&"kesh": "Kesh",
	&"piri": "Piri",
	&"tomas": "Tomas",
}

const HOTSPOT_ANCHORS := {
	&"powder": &"granary_powder",
	&"signal": &"signal_horn",
	&"gate": &"water_gate_wheel",
	&"tunnel": &"tunnel_tracks",
}

const HOTSPOT_PROMPTS := {
	&"powder": "INSPECT THE DISTURBED FLOORBOARDS",
	&"signal": "COMPARE THE HORN ASSEMBLY",
	&"gate": "INSPECT THE JAMMED GEARS",
	&"tunnel": "TRACE THE DRAINAGE PRINTS",
}

const AGENT_CONFIGS := [
	{
		"id": &"west_road_observer",
		"name": "West-road observer",
		"route": [&"west_patrol_a", &"west_patrol_b", &"west_gate_entry"],
	},
	{
		"id": &"granary_watch",
		"name": "Granary watch",
		"route": [&"granary_watch_a", &"granary_watch_b", &"stage_granary"],
	},
	{
		"id": &"tunnel_buyer",
		"name": "Tunnel buyer",
		"route": [&"water_patrol_a", &"tunnel_tracks", &"water_patrol_b"],
	},
	{
		"id": &"signal_runner",
		"name": "Signal runner",
		"route": [&"piri_signal", &"signal_horn", &"stage_reach_mara"],
	},
]

const WARD_LIGHT_ANCHORS := [
	&"west_gate_entry", &"mara_keep", &"brann", &"nessa_clinic",
	&"stage_granary", &"water_gate_wheel",
]

# Blender's glTF empty importer treats `_wheel` as a node-type suffix in the
# current diorama revision, so this one authored anchor arrives shortened.
const IMPORTED_LANDMARK_ALIASES := {
	&"water_gate_wheel": &"water_gate",
}

var game_state: AshGameState
var ui: GameUI
var world_host: AshenWorldHost3D
var player: AshenPlayerActor3D
var camera_rig: AshenCameraRig3D
var weather: AshenWeather3D
var soundscape: AshenSoundscape3D
var story_director: AshenStoryDirectorAdapter3D

var npc_targets: Dictionary = {}
var hotspot_targets: Dictionary = {}
var agents: Array[AshenEnemyAgent3D] = []

var _player_billboard: AshenBillboardActor3D
var _agent_billboards: Dictionary = {}
var _defense_volume: Area3D
var _nearest_interactable: AshenInteractable3D
var _rescue_in_progress := false
var _was_in_defense_volume := true
var _ward_lights: Array[OmniLight3D] = []
var _last_loop_index := -1


func configure(state: AshGameState) -> void:
	game_state = state


func _ready() -> void:
	if game_state == null:
		game_state = AshGameState.new()
	_build_spatial_world()
	_build_story_director()
	_apply_visual_settings()
	_last_loop_index = int(game_state.retained.get("loop_index", 0))
	set_process(true)
	set_physics_process(true)
	set_process_unhandled_input(true)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	var interface_blocks_play := (
		ui != null
		and (ui.dialogue_open or ui.folio_open)
	) or get_tree().paused or _rescue_in_progress
	player.controls_enabled = not interface_blocks_play
	if game_state and str(game_state.current_line.get("stage", "")) == "finale_defense":
		_tick_finale_3d(delta)


func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		return
	if is_instance_valid(_player_billboard):
		_player_billboard.set_facing(player.facing)
	for agent in agents:
		var visual := _agent_billboards.get(agent.stable_agent_id) as AshenBillboardActor3D
		if is_instance_valid(visual):
			visual.set_facing(agent.facing)
	_refresh_interactable_availability()
	_update_interaction_candidate()
	var loop_index := int(game_state.retained.get("loop_index", 0))
	if loop_index != _last_loop_index:
		_last_loop_index = loop_index
		weather.set_return_intensity(loop_index)
		_apply_pass_grade(loop_index)


func _unhandled_input(event: InputEvent) -> void:
	if ui == null or story_director == null:
		return
	if event.is_action_pressed("folio") and not ui.dialogue_open and not ui.folio_open:
		story_director.open_folio()
		get_viewport().set_input_as_handled()


func snapshot_data() -> Dictionary:
	_capture_spatial_state()
	return story_director.snapshot_data() if is_instance_valid(story_director) else game_state.to_save_data()


func _build_spatial_world() -> void:
	world_host = HostScript.new()
	world_host.name = "WorldHost3D"
	add_child(world_host)

	player = PlayerScript.new()
	player.name = "Evan3D"
	add_child(player)
	player.interact_requested.connect(_on_player_interact_requested)
	player.shove_emitted.connect(_on_player_shove)
	player.health_changed.connect(_on_player_health_changed)
	player.stamina_changed.connect(_on_player_stamina_changed)
	player.defeated.connect(_on_player_defeated)

	_player_billboard = BillboardScript.new()
	_player_billboard.name = "EvanPixelBillboard"
	_player_billboard.configure(BillboardScript.AtlasKind.EVAN, &"", 1.72)
	player.add_child(_player_billboard)

	camera_rig = CameraScript.new()
	camera_rig.name = "AshenCameraRig3D"
	add_child(camera_rig)
	camera_rig.set_target(player, false)
	player.set_movement_reference(camera_rig.get_camera())

	weather = WeatherScript.new()
	weather.name = "AshenStorm"
	add_child(weather)
	weather.set_target(player)
	weather.set_lightning_light(world_host.directional_light)

	soundscape = SoundscapeScript.new()
	soundscape.name = "AshenSoundscape"
	add_child(soundscape)
	soundscape.set_target(player)
	soundscape.bind_weather_source(weather)

	_build_interactables()
	_build_defense_volume()
	_build_agents()
	_build_ward_lights()
	_place_player_from_checkpoint(game_state.get_spatial_checkpoint(), true)


func _build_story_director() -> void:
	story_director = DirectorScript.new()
	story_director.name = "StoryDirector"
	story_director.configure(game_state)
	story_director.director_ready.connect(_on_director_ready)
	story_director.autosave_requested.connect(_on_director_autosave)
	story_director.story_completed.connect(_on_story_completed)
	story_director.return_to_title_requested.connect(_on_return_to_title)
	story_director.stage_changed.connect(_on_stage_changed)
	story_director.anchor_changed.connect(_on_anchor_changed)
	add_child(story_director)
	if story_director.ui:
		_on_director_ready(story_director.ui)


func _build_interactables() -> void:
	for npc_id: StringName in NPC_ANCHORS:
		var target := InteractableScript.new()
		target.name = "NPC_%s" % npc_id
		target.configure(npc_id, InteractableScript.Kind.NPC, str(NPC_LABELS[npc_id]), "TALK TO %s" % str(NPC_LABELS[npc_id]).to_upper())
		var marker := _resolve_landmark(NPC_ANCHORS[npc_id])
		if marker:
			target.global_transform = marker.global_transform
		add_child(target)
		var visual := BillboardScript.new()
		visual.name = "PortraitBillboard"
		visual.configure(BillboardScript.AtlasKind.NPC, npc_id, 1.68)
		target.add_child(visual)
		npc_targets[npc_id] = target

	for hotspot_id: StringName in HOTSPOT_ANCHORS:
		var target := InteractableScript.new()
		target.name = "Hotspot_%s" % hotspot_id
		target.configure(hotspot_id, InteractableScript.Kind.HOTSPOT, str(hotspot_id).capitalize(), HOTSPOT_PROMPTS[hotspot_id])
		var marker := _resolve_landmark(HOTSPOT_ANCHORS[hotspot_id])
		if marker:
			target.global_transform = marker.global_transform
		add_child(target)
		hotspot_targets[hotspot_id] = target


func _build_agents() -> void:
	var saved_states: Dictionary = game_state.current_line.get("agent_states", {})
	for config: Dictionary in AGENT_CONFIGS:
		var agent := EnemyScript.new()
		agent.name = "Agent_%s" % config["id"]
		add_child(agent)
		var route: Array[StringName] = []
		for route_id: Variant in config["route"]:
			route.append(StringName(route_id))
		agent.configure(player, world_host.landmark_registry, route, config["id"], config["name"])
		agent.surrendered.connect(_on_agent_surrendered)
		var saved := _saved_agent_state(saved_states, config["id"])
		if not saved.is_empty() and not bool(saved.get("legacy_transform_2d", false)):
			agent.restore_save_state(saved)
		agents.append(agent)
		var visual := BillboardScript.new()
		visual.name = "ChoirAgentBillboard"
		visual.configure(BillboardScript.AtlasKind.CHOIR_AGENT, &"", 1.73)
		agent.add_child(visual)
		_agent_billboards[config["id"]] = visual


func _build_defense_volume() -> void:
	_defense_volume = Area3D.new()
	_defense_volume.name = "GranaryDefenseVolume"
	CollisionLayers.configure_traversal_trigger(_defense_volume)
	var marker := _resolve_landmark(&"granary_defense")
	if marker:
		_defense_volume.global_transform = marker.global_transform
	var shape_node := CollisionShape3D.new()
	shape_node.name = "AuthoredDefenseBoundary"
	var box := BoxShape3D.new()
	box.size = Vector3(22.0, 3.0, 16.0)
	shape_node.shape = box
	shape_node.position = Vector3.UP * 1.0
	_defense_volume.add_child(shape_node)
	add_child(_defense_volume)


func _build_ward_lights() -> void:
	for anchor_id: StringName in WARD_LIGHT_ANCHORS:
		var marker := _resolve_landmark(anchor_id)
		if marker == null:
			continue
		var light := OmniLight3D.new()
		light.name = "WardLight_%s" % anchor_id
		light.light_color = Color("f2aa52")
		light.light_energy = 2.2
		light.omni_range = 8.5
		light.omni_attenuation = 1.35
		light.shadow_enabled = true
		light.position = marker.global_position + Vector3.UP * 2.35
		add_child(light)
		_ward_lights.append(light)
		if is_instance_valid(soundscape):
			soundscape.register_ward_landmark(anchor_id, marker.global_position + Vector3.UP * 1.35)


func _on_director_ready(ready_ui: GameUI) -> void:
	if ui == ready_ui:
		return
	ui = ready_ui
	ui.setting_changed.connect(_on_bool_setting_changed)
	ui.set_condition(player.health, AshenPlayerActor3D.MAX_HEALTH, player.stamina, AshenPlayerActor3D.MAX_STAMINA)
	_refresh_interactable_availability()


func _on_director_autosave(_snapshot: Dictionary) -> void:
	autosave_requested.emit(snapshot_data())


func _on_story_completed(_state: AshGameState) -> void:
	_capture_spatial_state()
	story_completed.emit(game_state)


func _on_return_to_title() -> void:
	_capture_spatial_state()
	return_to_title_requested.emit()


func _on_stage_changed(stage: String, checkpoint: Dictionary) -> void:
	_refresh_interactable_availability()
	if stage == "finale_defense":
		weather.set_finale_active(true)
		if is_instance_valid(soundscape):
			soundscape.play_finale_cue(0.86)
		for agent in agents:
			if agent.state != AshenEnemyAgent3D.State.SURRENDERED:
				agent.last_known_position = player.global_position
				agent.suspicion = 1.0
				agent.state = AshenEnemyAgent3D.State.CHASE
	elif stage == "finale_resolved":
		weather.set_finale_active(false)
		for agent in agents:
			agent.state = AshenEnemyAgent3D.State.SURRENDERED
			agent.velocity = Vector3.ZERO
	elif stage.begins_with("return_"):
		if is_instance_valid(soundscape):
			var return_intensity := 0.72 + minf(float(game_state.retained.get("soul_scars", 0)) * 0.08, 0.24)
			soundscape.play_return_cue(return_intensity)
		for agent in agents:
			agent.reset_agent()
	if not checkpoint.is_empty():
		_place_player_from_checkpoint(checkpoint, true)


func _on_anchor_changed(zone_id: String, anchor_id: String, position: Vector3, facing: String) -> void:
	var checkpoint := {
		"zone_id": zone_id,
		"anchor_id": anchor_id,
		"position": [position.x, position.y, position.z],
		"facing": facing,
	}
	_place_player_from_checkpoint(checkpoint, true)


func _on_player_interact_requested() -> void:
	if ui == null or ui.dialogue_open or ui.folio_open or _nearest_interactable == null:
		return
	if _nearest_interactable.kind == AshenInteractable3D.Kind.NPC:
		story_director.interact_npc(str(_nearest_interactable.interaction_id))
	else:
		story_director.interact_hotspot(str(_nearest_interactable.interaction_id))
	_refresh_interactable_availability()


func _on_player_shove(origin: Vector3, direction: Vector3) -> void:
	var contacted := false
	for agent in agents:
		if agent.receive_shove(origin, direction):
			contacted = true
	if contacted and ui:
		ui.notify("Non-lethal opening—move before they recover.", Color("d7b56e"), 1.2)
	_capture_agent_states()


func _on_agent_surrendered(_agent: AshenEnemyAgent3D) -> void:
	if ui:
		ui.notify("An agent drops their weapon and withdraws.", Color("85c2b2"), 2.0)
	_capture_agent_states()
	autosave_requested.emit(snapshot_data())


func _on_player_health_changed(value: float, maximum: float) -> void:
	if story_director:
		story_director.set_player_condition(value, maximum, player.stamina, AshenPlayerActor3D.MAX_STAMINA)


func _on_player_stamina_changed(value: float, maximum: float) -> void:
	if story_director:
		story_director.set_player_condition(player.health, AshenPlayerActor3D.MAX_HEALTH, value, maximum)


func _on_player_defeated(_cause: String) -> void:
	if _rescue_in_progress:
		return
	_rescue_in_progress = true
	player.controls_enabled = false
	var stage := str(game_state.current_line.get("stage", "arrival"))
	var text := "Nessa's orderlies pull Evan from the road. This is injury, not a Return."
	if stage in ["arrival", "reach_mara", "baseline_find_granary"]:
		text = "A Greyfen patrol hauls the shoeless stranger clear. This is injury, not a Return."
	elif stage == "finale_defense":
		text = "Tamsin drags Evan behind the granary wall. This is injury, not a Return."
	if ui:
		ui.notify(text, Color("d17a64"), 3.5)
	await get_tree().create_timer(1.1).timeout
	var checkpoint := game_state.checkpoint_for_stage(stage)
	_place_player_from_checkpoint(checkpoint, false)
	player.reset_body(player.global_position, int(game_state.retained.get("soul_scars", 0)))
	if stage == "finale_defense":
		var remaining := minf(45.0, float(game_state.current_line.get("finale_time", 38.0)) + 6.0)
		game_state.current_line["finale_time"] = remaining
		if story_director.director:
			story_director.director._finale_remaining = remaining
		if ui:
			ui.notify("The rescue costs the operation six breaths.", Color("d17a64"), 2.8)
	_rescue_in_progress = false
	autosave_requested.emit(snapshot_data())


func _tick_finale_3d(delta: float) -> void:
	if ui and (ui.dialogue_open or ui.folio_open) or _rescue_in_progress:
		return
	var inside := _is_player_inside_defense_volume()
	if inside != _was_in_defense_volume and ui:
		if inside:
			ui.notify("The granary line holds again.", Color("85c2b2"), 2.0)
		else:
			ui.notify("Return to the amber ward-lights before the attackers break the line.", Color("d17a64"), 3.4)
	_was_in_defense_volume = inside
	if inside:
		story_director.tick_finale(delta)


func _is_player_inside_defense_volume() -> bool:
	if not is_instance_valid(_defense_volume) or not is_instance_valid(player):
		return false
	var boundary := _defense_volume.get_node_or_null("AuthoredDefenseBoundary") as CollisionShape3D
	var player_shape := player.get_node_or_null("GroundCollider") as CollisionShape3D
	if (
		is_instance_valid(boundary)
		and not boundary.disabled
		and boundary.shape is BoxShape3D
		and is_instance_valid(player_shape)
		and not player_shape.disabled
		and player_shape.shape is CapsuleShape3D
	):
		# The authored box is authoritative. Area3D overlap lists are frame-cached,
		# so a teleport can otherwise report the previous side of the boundary for
		# one tick and incorrectly advance or pause the finale.
		return _box_overlaps_player_capsule(
			boundary,
			boundary.shape as BoxShape3D,
			player_shape,
			player_shape.shape as CapsuleShape3D
		)
	return _defense_volume.overlaps_body(player)


func _box_overlaps_player_capsule(
		box_node: CollisionShape3D,
		box: BoxShape3D,
		capsule_node: CollisionShape3D,
		capsule: CapsuleShape3D
	) -> bool:
	var capsule_half_segment := maxf(capsule.height * 0.5 - capsule.radius, 0.0)
	var capsule_start_world := capsule_node.global_transform * (Vector3.DOWN * capsule_half_segment)
	var capsule_end_world := capsule_node.global_transform * (Vector3.UP * capsule_half_segment)
	var box_inverse := box_node.global_transform.affine_inverse()
	var capsule_start_local := box_inverse * capsule_start_world
	var capsule_end_local := box_inverse * capsule_end_world

	var box_scale := box_node.global_basis.get_scale().abs()
	var capsule_scale := capsule_node.global_basis.get_scale().abs()
	var minimum_box_scale := maxf(minf(box_scale.x, minf(box_scale.y, box_scale.z)), 0.0001)
	var maximum_capsule_scale := maxf(capsule_scale.x, maxf(capsule_scale.y, capsule_scale.z))
	var local_capsule_radius := capsule.radius * maximum_capsule_scale / minimum_box_scale
	var half_extents := box.size * 0.5
	return _segment_box_distance_squared(capsule_start_local, capsule_end_local, half_extents) <= local_capsule_radius * local_capsule_radius


func _segment_box_distance_squared(start: Vector3, end: Vector3, half_extents: Vector3) -> float:
	# Distance-to-box along a segment is convex. A short fixed ternary search gives
	# deterministic capsule-vs-box containment even for rotated authored volumes.
	var lower := 0.0
	var upper := 1.0
	for _iteration in range(24):
		var first := lower + (upper - lower) / 3.0
		var second := upper - (upper - lower) / 3.0
		if _point_box_distance_squared(start.lerp(end, first), half_extents) <= _point_box_distance_squared(start.lerp(end, second), half_extents):
			upper = second
		else:
			lower = first
	var weight := (lower + upper) * 0.5
	return minf(
		_point_box_distance_squared(start.lerp(end, weight), half_extents),
		minf(_point_box_distance_squared(start, half_extents), _point_box_distance_squared(end, half_extents))
	)


func _point_box_distance_squared(point: Vector3, half_extents: Vector3) -> float:
	var outside := Vector3(
		maxf(absf(point.x) - half_extents.x, 0.0),
		maxf(absf(point.y) - half_extents.y, 0.0),
		maxf(absf(point.z) - half_extents.z, 0.0)
	)
	return outside.length_squared()


func _refresh_interactable_availability() -> void:
	if story_director == null or story_director.director == null:
		return
	for id: StringName in npc_targets:
		var target := npc_targets[id] as AshenInteractable3D
		var legacy_npc: Variant = story_director.director.npcs.get(str(id))
		target.set_available(legacy_npc is NpcActor and (legacy_npc as NpcActor).available)
	for id: StringName in hotspot_targets:
		var target := hotspot_targets[id] as AshenInteractable3D
		var legacy_hotspot: Variant = story_director.director.hotspots.get(str(id))
		target.set_available(legacy_hotspot is EvidenceHotspot and (legacy_hotspot as EvidenceHotspot).available)


func _update_interaction_candidate() -> void:
	if ui == null or ui.dialogue_open or ui.folio_open:
		_nearest_interactable = null
		if ui:
			ui.show_prompt("")
		return
	var best: AshenInteractable3D
	var best_score := INF
	var candidates: Array[AshenInteractable3D] = []
	for value: Variant in npc_targets.values():
		candidates.append(value as AshenInteractable3D)
	for value: Variant in hotspot_targets.values():
		candidates.append(value as AshenInteractable3D)
	for target in candidates:
		if target == null or not target.is_player_inside(player):
			continue
		var offset := target.global_position - player.global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance <= 0.001:
			continue
		var facing_score := player.facing.normalized().dot(offset.normalized())
		if facing_score < -0.12 or not _has_clear_interaction_line(target):
			continue
		var score := distance + (1.0 - facing_score) * 0.7
		if score < best_score:
			best = target
			best_score = score
	_nearest_interactable = best
	ui.show_prompt("E  %s" % best.prompt if best else "")


func _has_clear_interaction_line(target: AshenInteractable3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(
		player.global_position + Vector3.UP * 0.92,
		target.interaction_point(),
		CollisionLayers.WORLD_SOLID | CollisionLayers.VISION_OCCLUDER
	)
	query.exclude = [player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _capture_spatial_state() -> void:
	if not is_instance_valid(player) or not is_instance_valid(world_host) or story_director == null:
		return
	var registry := world_host.landmark_registry
	var closest_id := registry.find_closest_landmark(player.global_position)
	var zone_id := registry.get_zone_id(closest_id)
	if zone_id == &"":
		zone_id = world_host.infer_physical_zone_id(closest_id, player.global_position)
	game_state.set_spatial_checkpoint(str(zone_id), str(closest_id), player.global_position, _facing_to_id(player.facing))
	_capture_agent_states()
	story_director.capture_authoritative_3d_state()


func _capture_agent_states() -> void:
	var result := {}
	for agent in agents:
		result[str(agent.stable_agent_id)] = agent.to_save_state()
	game_state.current_line["agent_states"] = result
	if story_director:
		story_director.set_agent_states(result)


func _place_player_from_checkpoint(checkpoint: Dictionary, snap_camera: bool) -> void:
	if not is_instance_valid(player) or not is_instance_valid(world_host):
		return
	var anchor_id := StringName(str(checkpoint.get("anchor_id", "evan_arrival")))
	var marker := _resolve_landmark(anchor_id)
	var destination := marker.global_position if marker else Vector3.ZERO
	var saved: Variant = checkpoint.get("position", [])
	if saved is Array and saved.size() == 3:
		var candidate := Vector3(float(saved[0]), float(saved[1]), float(saved[2]))
		# Zero is the deliberate V1-migration sentinel. Non-zero V2 positions are
		# restored only inside the authored world bounds.
		if candidate.length_squared() > 0.01 and absf(candidate.x) < 220.0 and absf(candidate.z) < 180.0:
			destination = candidate
	player.global_position = destination + Vector3.UP * 0.06
	player.velocity = Vector3.ZERO
	player.facing = _id_to_facing(str(checkpoint.get("facing", "south")))
	if snap_camera and is_instance_valid(camera_rig):
		camera_rig.snap_to_target()


func _resolve_landmark(anchor_id: StringName) -> Marker3D:
	if not is_instance_valid(world_host) or not is_instance_valid(world_host.landmark_registry):
		return null
	var marker := world_host.landmark_registry.get_landmark(anchor_id)
	if marker == null and IMPORTED_LANDMARK_ALIASES.has(anchor_id):
		marker = world_host.landmark_registry.get_landmark(IMPORTED_LANDMARK_ALIASES[anchor_id])
	return marker


func _saved_agent_state(states: Dictionary, id: StringName) -> Dictionary:
	if states.get(str(id)) is Dictionary:
		return (states[str(id)] as Dictionary).duplicate(true)
	for value: Variant in states.values():
		if value is Dictionary and str((value as Dictionary).get("agent_id", "")) == str(id):
			return (value as Dictionary).duplicate(true)
	return {}


func _on_bool_setting_changed(key: String, enabled: bool) -> void:
	game_state.settings[key] = enabled
	_apply_visual_settings()


func _apply_visual_settings() -> void:
	if not is_instance_valid(camera_rig) or not is_instance_valid(weather) or not is_instance_valid(world_host):
		return
	camera_rig.set_reduced_motion(bool(game_state.settings.get("reduce_motion", false)))
	weather.apply_settings(game_state.settings)
	if is_instance_valid(soundscape):
		soundscape.apply_settings(game_state.settings)
	var quality := str(game_state.settings.get("visual_quality", "high"))
	var shadow_count := 6 if quality in ["high", "ultra"] else (3 if quality == "medium" else 1)
	for index in range(_ward_lights.size()):
		_ward_lights[index].shadow_enabled = index < shadow_count
		_ward_lights[index].visible = quality != "low" or index == 0
	world_host.directional_light.shadow_enabled = true
	var environment := world_host.world_environment.environment
	environment.volumetric_fog_enabled = quality in ["high", "ultra"]
	environment.volumetric_fog_density = 0.025
	var attributes := CameraAttributesPractical.new()
	var dof_enabled := bool(game_state.settings.get("depth_of_field", true)) and quality in ["high", "ultra"]
	attributes.dof_blur_far_enabled = dof_enabled
	attributes.dof_blur_far_distance = 34.0
	attributes.dof_blur_far_transition = 18.0
	attributes.dof_blur_amount = 0.08
	camera_rig.get_camera().attributes = attributes
	_apply_pass_grade(int(game_state.retained.get("loop_index", 0)))


func _apply_pass_grade(loop_index: int) -> void:
	if not is_instance_valid(world_host) or world_host.world_environment.environment == null:
		return
	var environment := world_host.world_environment.environment
	var grades := [
		[Color("071116"), Color("718b91"), 0.52],
		[Color("06141a"), Color("6d9298"), 0.55],
		[Color("110f14"), Color("829097"), 0.58],
		[Color("0b1216"), Color("8da3a1"), 0.62],
	]
	var grade: Array = grades[clampi(loop_index, 0, grades.size() - 1)]
	environment.background_color = grade[0]
	environment.ambient_light_color = grade[1]
	environment.ambient_light_energy = grade[2]


func _facing_to_id(direction: Vector3) -> String:
	var index := AshenBillboardActor3D.direction_index_from_vector(direction)
	return AshGameState.FACING_IDS[index]


func _id_to_facing(id: String) -> Vector3:
	var index := AshGameState.FACING_IDS.find(id)
	if index < 0:
		index = AshenBillboardActor3D.Direction8.SOUTH
	var angle := float(index) * PI * 0.25
	return Vector3(sin(angle), 0.0, -cos(angle)).normalized()
