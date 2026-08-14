extends SceneTree

const HostScript := preload("res://scripts/ashen_3d/world_host_3d.gd")
const StateScript := preload("res://scripts/game_state.gd")
const CollisionLayers := preload("res://scripts/ashen_3d/collision_layers_3d.gd")

const EXPECTED_RUNTIME_ANCHORS := {
	&"arrival": Vector3(-111.0, 0.35, 18.0),
	&"mara_keep": Vector3(-4.0, 0.35, -5.0),
	&"stage_granary": Vector3(25.0, 0.35, 9.0),
	&"stage_finale": Vector3(34.0, 0.35, 18.0),
	&"water_gate_wheel": Vector3(91.0, 0.35, 27.0),
}

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
	_test_axis_contract(host)
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


func _test_axis_contract(host) -> void:
	for anchor_id: StringName in EXPECTED_RUNTIME_ANCHORS:
		var marker: Marker3D = host.landmark_registry.get_landmark(anchor_id)
		var expected: Vector3 = EXPECTED_RUNTIME_ANCHORS[anchor_id]
		_check(marker != null, "Axis sentinel anchor '%s' survives with its semantic ID." % anchor_id)
		if marker:
			_check(marker.global_position.distance_to(expected) < 0.06, "Axis sentinel '%s' is at Godot Y-up coordinate %s, got %s." % [anchor_id, expected, marker.global_position])

	var minimum := Vector3(INF, INF, INF)
	var maximum := Vector3(-INF, -INF, -INF)
	for id: StringName in host._raw_anchor_markers:
		var marker := host._raw_anchor_markers[id] as Marker3D
		if marker:
			minimum = minimum.min(marker.global_position)
			maximum = maximum.max(marker.global_position)
	var anchor_extent := maximum - minimum
	_check(anchor_extent.x > 200.0 and anchor_extent.z > 50.0, "Landmark geography spans the authored XZ traversal plane: %s." % anchor_extent)
	_check(minimum.y > 0.20 and maximum.y < 2.35, "Landmark elevation stays near ground on Godot Y instead of leaking district depth: %s to %s." % [minimum.y, maximum.y])

	for alias: StringName in HostScript.CHECKPOINT_ALIAS_SOURCES:
		var checkpoint: Marker3D = host.landmark_registry.get_landmark(alias)
		_check(checkpoint != null and absf(checkpoint.global_position.y - 0.35) < 0.06, "Checkpoint '%s' remains on the authored ground-height band." % alias)

	var ground_bounds := _largest_collision_footprint(host)
	_check(ground_bounds.size.x > 220.0 and ground_bounds.size.z > 120.0, "Broad ground collision spans XZ: %s." % ground_bounds)
	_check(ground_bounds.size.y < 0.75, "Broad ground collision is thin on Godot Y: %s." % ground_bounds)
	_check(absf(ground_bounds.get_center().x) < 0.1 and absf(ground_bounds.get_center().z) < 0.1, "Broad ground collision remains centred under Greyfen: %s." % ground_bounds.get_center())
	_check(ground_bounds.end.y < 0.05 and ground_bounds.position.y > -0.65, "Broad ground collision sits immediately below traversal height: %s." % ground_bounds)


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


func _largest_collision_footprint(host) -> AABB:
	var largest := AABB()
	var largest_area := -1.0
	for body: StaticBody3D in host.get_imported_collision_bodies():
		var shapes: Array[CollisionShape3D] = []
		_collect_collision_shapes(body, shapes)
		for shape_node in shapes:
			var bounds := _collision_shape_world_bounds(shape_node)
			var footprint := bounds.size.x * bounds.size.z
			if footprint > largest_area:
				largest_area = footprint
				largest = bounds
	return largest


func _collect_collision_shapes(node: Node, result: Array[CollisionShape3D]) -> void:
	if node is CollisionShape3D:
		var shape_node := node as CollisionShape3D
		if not shape_node.disabled and shape_node.shape != null:
			result.append(shape_node)
	for child in node.get_children():
		_collect_collision_shapes(child, result)


func _collision_shape_world_bounds(shape_node: CollisionShape3D) -> AABB:
	var debug_mesh := shape_node.shape.get_debug_mesh()
	if debug_mesh == null:
		return AABB()
	var local_bounds := debug_mesh.get_aabb()
	var minimum := Vector3(INF, INF, INF)
	var maximum := Vector3(-INF, -INF, -INF)
	for x_side in range(2):
		for y_side in range(2):
			for z_side in range(2):
				var local_point := local_bounds.position + Vector3(
					local_bounds.size.x * x_side,
					local_bounds.size.y * y_side,
					local_bounds.size.z * z_side
				)
				var world_point := shape_node.global_transform * local_point
				minimum = minimum.min(world_point)
				maximum = maximum.max(world_point)
	return AABB(minimum, maximum - minimum)
