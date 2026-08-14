extends SceneTree

const HostScript := preload("res://scripts/ashen_3d/world_host_3d.gd")
const StateScript := preload("res://scripts/game_state.gd")
const CollisionLayers := preload("res://scripts/ashen_3d/collision_layers_3d.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("[ashen-world-asset] %s" % message)


func _run() -> void:
	_check(ResourceLoader.exists(HostScript.DIORAMA_PATH, "PackedScene"), "Authored Greyfen GLB is imported as a PackedScene.")
	var host := HostScript.new()
	host.name = "AshenWorldAssetTest"
	host.bake_navigation_on_ready = false
	root.add_child(host)
	await process_frame
	await process_frame

	_test_build_contract(host)
	_test_checkpoint_aliases(host)
	_test_physical_zone_inference(host)
	_test_collision_import(host)
	_test_checkpoint_clearance(host)
	_test_lighting(host)
	await _test_navigation(host)

	host.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("[ashen-world-asset] PASS")
		quit(0)
	else:
		print("[ashen-world-asset] FAIL (%d)" % failures.size())
		quit(1)


func _test_build_contract(host) -> void:
	_check(host.environment_root != null and is_instance_valid(host.environment_root), "World host instantiates the authored Greyfen diorama.")
	_check(host.landmark_registry != null and is_instance_valid(host.landmark_registry), "World host owns a semantic LandmarkRegistry3D.")
	_check(host.navigation_region != null and is_instance_valid(host.navigation_region), "World host owns a NavigationRegion3D.")
	_check(host.validation_errors.is_empty(), "Authored world passes host validation: %s" % "; ".join(host.validation_errors))
	_check(host.get_raw_anchor_count() >= 30, "At least thirty authored anchor__* nodes survive GLB import and harvesting.")
	for id: StringName in host._raw_anchor_markers:
		var marker := host._raw_anchor_markers[id] as Marker3D
		_check(marker != null and marker.has_meta(&"landmark_id"), "Raw anchor '%s' is mirrored as Marker3D metadata." % id)
		_check(str(marker.get_meta(&"source_node_name", "")).begins_with("anchor_"), "Raw anchor '%s' records its imported Node3D source." % id)


func _test_checkpoint_aliases(host) -> void:
	var seen_aliases := {}
	for stage: String in StateScript.STAGE_CHECKPOINTS:
		var checkpoint: Dictionary = StateScript.STAGE_CHECKPOINTS[stage]
		var zone_id := StringName(checkpoint["zone_id"])
		var anchor_id := StringName(checkpoint["anchor_id"])
		var marker: Marker3D = host.resolve_checkpoint_anchor(zone_id, anchor_id)
		_check(marker != null, "Stage '%s' resolves checkpoint alias '%s/%s'." % [stage, zone_id, anchor_id])
		if marker:
			_check(marker.has_meta(&"source_anchor_id"), "Checkpoint alias '%s' preserves its authored source anchor." % anchor_id)
		seen_aliases[anchor_id] = true
	_check(seen_aliases.size() == 7, "All sixteen story stages collapse to exactly seven stable checkpoint aliases.")
	for alias: StringName in HostScript.CHECKPOINT_ALIAS_SOURCES:
		_check(seen_aliases.has(alias), "Host alias '%s' is used by AshGameState.STAGE_CHECKPOINTS." % alias)


func _test_physical_zone_inference(host) -> void:
	_check(HostScript.PHYSICAL_ZONE_IDS.size() == 5, "Imported anchor geography uses exactly five physical district IDs.")
	for zone_id: StringName in HostScript.PHYSICAL_ZONE_IDS:
		var ids: Array[StringName] = host.get_raw_anchor_ids_in_physical_zone(zone_id)
		_check(not ids.is_empty(), "Physical district '%s' owns at least one authored anchor." % zone_id)
	for alias: StringName in HostScript.CHECKPOINT_ALIAS_SOURCES:
		var marker: Marker3D = host.landmark_registry.get_landmark(alias)
		_check(marker != null and marker.has_meta(&"physical_zone_id"), "Checkpoint alias '%s' retains physical-district metadata beside its save zone." % alias)


func _test_collision_import(host) -> void:
	var bodies: Array[StaticBody3D] = host.get_imported_collision_bodies()
	_check(bodies.size() >= 30, "GLB importer creates at least thirty authored StaticBody3D proxies.")
	_check(host.get_imported_collision_shape_count() >= bodies.size(), "Every imported collision body owns an enabled shape.")
	for body in bodies:
		_check(body.collision_layer == CollisionLayers.WORLD_SOLID | CollisionLayers.VISION_OCCLUDER, "Collision proxy '%s' blocks bodies and sight on the exact layer contract." % body.name)
		_check(body.collision_mask == 0, "Static collision proxy '%s' does not perform unnecessary body queries." % body.name)


func _test_checkpoint_clearance(host) -> void:
	var clearance_failures: Dictionary = host.get_checkpoint_clearance_failures()
	_check(clearance_failures.is_empty(), "Stable checkpoint capsules do not overlap authored collision: %s" % clearance_failures)


func _test_lighting(host) -> void:
	_check(host.world_environment != null and host.world_environment.environment != null, "World host creates a WorldEnvironment.")
	if host.world_environment and host.world_environment.environment:
		_check(host.world_environment.environment.fog_enabled, "World environment enables restrained atmospheric fog.")
		_check(host.world_environment.environment.tonemap_mode == Environment.TONE_MAPPER_FILMIC, "World environment uses filmic tonemapping.")
	_check(host.directional_light != null and host.directional_light.shadow_enabled, "Storm-dusk DirectionalLight3D casts authored shadows.")


func _test_navigation(host) -> void:
	_check(host.navigation_mode == &"fallback_pads", "Host starts from conservative disconnected checkpoint pads before runtime baking.")
	_check(host.navigation_region.navigation_mesh != null, "NavigationRegion3D always has a safe authored fallback mesh.")
	if host.navigation_region.navigation_mesh:
		_check(host.navigation_region.navigation_mesh.get_polygon_count() == 7, "Safe fallback contains one isolated pad per stable checkpoint alias.")
	var requested: bool = host.bake_navigation_now(false)
	_check(requested, "World host accepts a synchronous runtime navigation bake request.")
	await process_frame
	await process_frame
	_check(host.navigation_mode in [&"runtime_baked", &"fallback_pads"], "Navigation bake completes or restores the conservative fallback.")
	_check(host.navigation_region.navigation_mesh != null and host.navigation_region.navigation_mesh.get_polygon_count() > 0, "NavigationRegion3D retains navigable polygons after bake handling.")
