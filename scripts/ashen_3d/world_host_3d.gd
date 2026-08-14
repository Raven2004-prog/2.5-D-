extends Node3D
class_name AshenWorldHost3D

## Runtime host for the authored Greyfen GLB.
##
## The imported scene remains the single source of truth for visible geometry and
## collision proxies. Blender empties named `anchor__*` are mirrored as Marker3D
## nodes in the semantic registry so story/save code never depends on GLB paths.

signal world_built(valid: bool)
signal navigation_bake_completed(success: bool, mode: StringName)

const DIORAMA_PATH := "res://assets/ashen/environment/greyfen_diorama.glb"
const DioramaScene: PackedScene = preload(DIORAMA_PATH)
const RegistryScript := preload("res://scripts/ashen_3d/landmark_registry_3d.gd")
const CollisionLayers := preload("res://scripts/ashen_3d/collision_layers_3d.gd")

const PHYSICAL_ZONE_IDS := [
	&"fen_road",
	&"west_gate",
	&"keep_court",
	&"refuge_row",
	&"water_gate",
]

## Alias IDs and zones exactly match AshGameState.STAGE_CHECKPOINTS. The source
## IDs are authored Blender empty names with the `anchor__` prefix removed.
const CHECKPOINT_ALIAS_SOURCES := {
	&"evan_arrival": &"stage_arrival",
	&"mara_ward": &"stage_reach_mara",
	&"granary_approach": &"stage_granary",
	&"west_gate_inside": &"west_gate_entry",
	&"tomas_standoff": &"tomas",
	&"granary_defense": &"stage_finale",
	&"tribunal_entry": &"stage_tribunal",
}

const CHECKPOINT_ALIAS_ZONES := {
	&"evan_arrival": &"fen_road",
	&"mara_ward": &"keep_court",
	&"granary_approach": &"refuge_row",
	&"west_gate_inside": &"fen_road",
	&"tomas_standoff": &"granary_undercroft",
	&"granary_defense": &"refuge_row",
	&"tribunal_entry": &"keep_hall",
}

const FEN_ANCHORS := [
	&"arrival", &"split_ash", &"lysa", &"stage_arrival",
]
const WEST_GATE_ANCHORS := [
	&"west_gate_entry", &"brann", &"west_patrol_a", &"west_patrol_b", &"shortcut_barracks",
]
const KEEP_ANCHORS := [
	&"mara_keep", &"tamsin", &"piri_signal", &"signal_horn", &"stage_reach_mara",
	&"stage_return_two", &"stage_return_three", &"stage_tribunal",
]
const REFUGE_ANCHORS := [
	&"granary_powder", &"nessa_clinic", &"kesh", &"tomas", &"granary_watch_a",
	&"granary_watch_b", &"stage_granary", &"stage_finale", &"shortcut_granary", &"shortcut_refuge",
]
const WATER_ANCHORS := [
	&"water_gate_wheel", &"tunnel_tracks", &"water_patrol_a", &"water_patrol_b", &"shortcut_drain",
]

@export var bake_navigation_on_ready := true
@export var threaded_navigation_bake := true

var environment_root: Node3D
var landmark_registry: AshenLandmarkRegistry3D
var navigation_region: NavigationRegion3D
var world_environment: WorldEnvironment
var directional_light: DirectionalLight3D

var validation_errors: Array[String] = []
var validation_warnings: Array[String] = []
var navigation_mode: StringName = &"uninitialized"

var _raw_anchor_markers: Dictionary = {}
var _imported_collision_bodies: Array[StaticBody3D] = []
var _imported_collision_shape_count := 0
var _fallback_navigation_mesh: NavigationMesh
var _world_is_built := false


func _ready() -> void:
	build_world()
	if bake_navigation_on_ready:
		call_deferred("bake_navigation_now", threaded_navigation_bake)


func build_world() -> bool:
	if _world_is_built:
		return validation_errors.is_empty()
	_world_is_built = true
	validation_errors.clear()
	validation_warnings.clear()
	_build_lighting()
	_build_navigation_region()
	_load_diorama()
	_build_registry()
	if environment_root:
		_harvest_imported_anchors(environment_root)
		_validate_and_configure_collisions(environment_root)
	_create_checkpoint_aliases()
	_validate_checkpoint_aliases()
	_install_safe_navigation_fallback()
	var valid := validation_errors.is_empty()
	world_built.emit(valid)
	return valid


func resolve_checkpoint_anchor(zone_id: StringName, anchor_id: StringName) -> Marker3D:
	if not is_instance_valid(landmark_registry):
		return null
	var marker := landmark_registry.get_landmark(anchor_id)
	if marker == null or landmark_registry.get_zone_id(anchor_id) != zone_id:
		return null
	return marker


func infer_physical_zone_id(anchor_id: StringName, position: Vector3 = Vector3.ZERO) -> StringName:
	if anchor_id in FEN_ANCHORS:
		return &"fen_road"
	if anchor_id in WEST_GATE_ANCHORS:
		return &"west_gate"
	if anchor_id in KEEP_ANCHORS:
		return &"keep_court"
	if anchor_id in REFUGE_ANCHORS:
		return &"refuge_row"
	if anchor_id in WATER_ANCHORS:
		return &"water_gate"
	# Position fallback is deterministic for newly authored anchors and follows the
	# west-to-east geography of the source diorama.
	if position.x < -80.0:
		return &"fen_road"
	if position.x < -32.0:
		return &"west_gate"
	if position.x < 18.0:
		return &"keep_court"
	if position.x < 65.0:
		return &"refuge_row"
	return &"water_gate"


func get_raw_anchor_count() -> int:
	return _raw_anchor_markers.size()


func get_imported_collision_body_count() -> int:
	return _imported_collision_bodies.size()


func get_imported_collision_shape_count() -> int:
	return _imported_collision_shape_count


func get_imported_collision_bodies() -> Array[StaticBody3D]:
	return _imported_collision_bodies.duplicate()


func get_raw_anchor_ids_in_physical_zone(zone_id: StringName) -> Array[StringName]:
	var result: Array[StringName] = []
	for id: Variant in _raw_anchor_markers.keys():
		var marker := _raw_anchor_markers[id] as Marker3D
		if is_instance_valid(marker) and StringName(marker.get_meta(&"physical_zone_id", &"")) == zone_id:
			result.append(StringName(id))
	result.sort()
	return result


func get_checkpoint_clearance_failures(radius: float = 0.40, height: float = 1.70) -> Dictionary:
	var failures := {}
	if not is_inside_tree() or not is_instance_valid(landmark_registry):
		return failures
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = height
	for alias: StringName in CHECKPOINT_ALIAS_SOURCES:
		var marker := landmark_registry.get_landmark(alias)
		if marker == null:
			continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.transform = Transform3D(Basis.IDENTITY, marker.global_position + Vector3.UP * (height * 0.5))
		query.collision_mask = CollisionLayers.WORLD_SOLID
		query.collide_with_bodies = true
		query.collide_with_areas = false
		var blocker_names: Array[String] = []
		for hit: Dictionary in get_world_3d().direct_space_state.intersect_shape(query, 32):
			var collider: Variant = hit.get("collider")
			if collider is StaticBody3D and _imported_collision_bodies.has(collider):
				blocker_names.append(str((collider as StaticBody3D).name))
		if not blocker_names.is_empty():
			failures[alias] = blocker_names
	return failures


func bake_navigation_now(on_thread: bool = true) -> bool:
	if not is_inside_tree() or not is_instance_valid(navigation_region) or environment_root == null:
		validation_warnings.append("Navigation bake requested before the authored world was ready.")
		return false
	var runtime_mesh := _make_runtime_navigation_mesh()
	navigation_region.navigation_mesh = runtime_mesh
	navigation_mode = &"baking"
	if not navigation_region.bake_finished.is_connected(_on_navigation_bake_finished):
		navigation_region.bake_finished.connect(_on_navigation_bake_finished)
	navigation_region.bake_navigation_mesh(on_thread)
	return true


func _build_lighting() -> void:
	world_environment = WorldEnvironment.new()
	world_environment.name = "AshenWorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("071116")
	environment.background_energy_multiplier = 0.42
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("718b91")
	environment.ambient_light_energy = 0.52
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.fog_enabled = true
	environment.fog_light_color = Color("6d8588")
	environment.fog_light_energy = 0.45
	environment.fog_density = 0.0065
	environment.fog_height = 1.2
	environment.fog_height_density = 0.16
	world_environment.environment = environment
	add_child(world_environment)

	directional_light = DirectionalLight3D.new()
	directional_light.name = "StormDuskKey"
	directional_light.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	directional_light.light_color = Color("d5b27c")
	directional_light.light_energy = 1.08
	directional_light.shadow_enabled = true
	directional_light.directional_shadow_max_distance = 180.0
	add_child(directional_light)


func _build_navigation_region() -> void:
	navigation_region = NavigationRegion3D.new()
	navigation_region.name = "GreyfenNavigationRegion3D"
	navigation_region.navigation_layers = 1
	navigation_region.use_edge_connections = true
	add_child(navigation_region)
	var navigation_map := navigation_region.get_navigation_map()
	if navigation_map.is_valid():
		NavigationServer3D.map_set_cell_size(navigation_map, 0.20)
		NavigationServer3D.map_set_cell_height(navigation_map, 0.10)


func _load_diorama() -> void:
	var imported := DioramaScene.instantiate()
	if not imported is Node3D:
		validation_errors.append("The Greyfen diorama root is not a Node3D.")
		if imported:
			imported.queue_free()
		return
	environment_root = imported as Node3D
	environment_root.name = "GreyfenDiorama"
	navigation_region.add_child(environment_root)


func _build_registry() -> void:
	landmark_registry = RegistryScript.new()
	landmark_registry.name = "LandmarkRegistry3D"
	landmark_registry.auto_discover_on_ready = false
	add_child(landmark_registry)


func _harvest_imported_anchors(node: Node) -> void:
	if node is Node3D:
		var source := node as Node3D
		var anchor_id := _anchor_id_from_node_name(source.name)
		if anchor_id != &"":
			if _raw_anchor_markers.has(anchor_id):
				var existing_marker := _raw_anchor_markers[anchor_id] as Marker3D
				if existing_marker.global_position.is_equal_approx(source.global_position):
					# Node-type suffix import may create a wrapper and child with the
					# same semantic empty name (notably `_wheel`). Coincident nodes
					# remain one authored anchor rather than a false duplicate.
					validation_warnings.append("Collapsed coincident imported anchor '%s'." % anchor_id)
				else:
					validation_errors.append(
						"Duplicate imported anchor '%s' from '%s' and '%s'." % [
							anchor_id,
							existing_marker.get_meta(&"source_node_name", "unknown"),
							source.name,
						]
					)
			else:
				var marker := _create_registry_marker(anchor_id, source.global_transform)
				var physical_zone := infer_physical_zone_id(anchor_id, source.global_position)
				marker.set_meta(&"physical_zone_id", physical_zone)
				marker.set_meta(&"source_node_name", source.name)
				landmark_registry.register_landmark(anchor_id, marker, physical_zone)
				_raw_anchor_markers[anchor_id] = marker
	for child in node.get_children():
		_harvest_imported_anchors(child)


func _anchor_id_from_node_name(node_name: StringName) -> StringName:
	var text := str(node_name)
	if text.begins_with("anchor__"):
		return StringName(text.trim_prefix("anchor__").strip_edges())
	# Some glTF naming revisions collapse repeated underscores. Accept that import
	# spelling without changing the semantic ID produced for the registry.
	if text.begins_with("anchor_"):
		return StringName(text.trim_prefix("anchor_").strip_edges())
	return &""


func _create_registry_marker(id: StringName, source_transform: Transform3D) -> Marker3D:
	var marker := Marker3D.new()
	marker.name = "Anchor__%s" % id
	landmark_registry.add_child(marker)
	marker.global_transform = source_transform
	return marker


func _create_checkpoint_aliases() -> void:
	for alias: StringName in CHECKPOINT_ALIAS_SOURCES:
		var source_id: StringName = CHECKPOINT_ALIAS_SOURCES[alias]
		var source_marker := _raw_anchor_markers.get(source_id) as Marker3D
		if not is_instance_valid(source_marker):
			validation_errors.append("Checkpoint alias '%s' has no imported source anchor '%s'." % [alias, source_id])
			continue
		var alias_marker := _create_registry_marker(alias, source_marker.global_transform)
		var checkpoint_zone: StringName = CHECKPOINT_ALIAS_ZONES[alias]
		alias_marker.set_meta(&"source_anchor_id", source_id)
		alias_marker.set_meta(&"physical_zone_id", source_marker.get_meta(&"physical_zone_id", &""))
		if not landmark_registry.register_landmark(alias, alias_marker, checkpoint_zone):
			validation_errors.append(landmark_registry.last_error)


func _validate_checkpoint_aliases() -> void:
	for alias: StringName in CHECKPOINT_ALIAS_SOURCES:
		if not landmark_registry.has_landmark(alias):
			validation_errors.append("Required checkpoint alias '%s' is absent." % alias)
			continue
		var expected_zone: StringName = CHECKPOINT_ALIAS_ZONES[alias]
		if landmark_registry.get_zone_id(alias) != expected_zone:
			validation_errors.append("Checkpoint alias '%s' is not assigned to '%s'." % [alias, expected_zone])
	if _raw_anchor_markers.is_empty():
		validation_errors.append("The imported diorama contains no harvestable anchor__* nodes.")


func _validate_and_configure_collisions(node: Node) -> void:
	_imported_collision_bodies.clear()
	_imported_collision_shape_count = 0
	_collect_collision_bodies(node)
	if _imported_collision_bodies.is_empty():
		validation_errors.append("The imported diorama contains no StaticBody3D collision proxies.")


func _collect_collision_bodies(node: Node) -> void:
	if node is StaticBody3D:
		var body := node as StaticBody3D
		body.collision_layer = CollisionLayers.WORLD_SOLID | CollisionLayers.VISION_OCCLUDER
		body.collision_mask = 0
		_imported_collision_bodies.append(body)
		var body_shape_count := _count_valid_collision_shapes(body)
		_imported_collision_shape_count += body_shape_count
		if body_shape_count == 0:
			validation_errors.append("Imported collision body '%s' has no enabled CollisionShape3D." % body.name)
	for child in node.get_children():
		_collect_collision_bodies(child)


func _count_valid_collision_shapes(node: Node) -> int:
	var count := 0
	for child in node.get_children():
		if child is CollisionShape3D:
			var shape_node := child as CollisionShape3D
			if not shape_node.disabled and shape_node.shape != null:
				count += 1
		else:
			count += _count_valid_collision_shapes(child)
	return count


func _make_runtime_navigation_mesh() -> NavigationMesh:
	var navigation_mesh := NavigationMesh.new()
	navigation_mesh.agent_height = 1.70
	navigation_mesh.agent_radius = 0.40
	navigation_mesh.agent_max_climb = 0.20
	navigation_mesh.agent_max_slope = 25.0
	navigation_mesh.cell_size = 0.20
	navigation_mesh.cell_height = 0.10
	navigation_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	navigation_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	return navigation_mesh


func _install_safe_navigation_fallback() -> void:
	_fallback_navigation_mesh = _make_runtime_navigation_mesh()
	var vertices := PackedVector3Array()
	var polygons: Array[PackedInt32Array] = []
	var half_extent := 0.72
	for alias: StringName in CHECKPOINT_ALIAS_SOURCES:
		var marker := landmark_registry.get_landmark(alias)
		if marker == null:
			continue
		var center := navigation_region.to_local(marker.global_position)
		var first := vertices.size()
		vertices.append(center + Vector3(-half_extent, 0.0, -half_extent))
		vertices.append(center + Vector3(-half_extent, 0.0, half_extent))
		vertices.append(center + Vector3(half_extent, 0.0, half_extent))
		vertices.append(center + Vector3(half_extent, 0.0, -half_extent))
		polygons.append(PackedInt32Array([first, first + 1, first + 2, first + 3]))
	_fallback_navigation_mesh.vertices = vertices
	for polygon in polygons:
		_fallback_navigation_mesh.add_polygon(polygon)
	navigation_region.navigation_mesh = _fallback_navigation_mesh
	navigation_mode = &"fallback_pads"
	if _fallback_navigation_mesh.get_polygon_count() == 0:
		validation_errors.append("Safe navigation fallback could not create any checkpoint pads.")


func _on_navigation_bake_finished() -> void:
	var baked_mesh := navigation_region.navigation_mesh
	var success := baked_mesh != null and baked_mesh.get_polygon_count() > 0
	if success:
		navigation_mode = &"runtime_baked"
	else:
		navigation_region.navigation_mesh = _fallback_navigation_mesh
		navigation_mode = &"fallback_pads"
		validation_warnings.append("Runtime navigation bake produced no polygons; restored safe checkpoint pads.")
	navigation_bake_completed.emit(success, navigation_mode)
