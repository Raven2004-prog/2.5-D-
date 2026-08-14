extends Node3D
class_name AshenInteractable3D

## Landmark-owned interaction target for the 2.5D world. NPC targets own a small
## grounded body and navigation obstacle; evidence targets are non-blocking. Every
## target owns an Area3D, while the world applies facing and obstruction priority.

enum Kind { NPC, HOTSPOT }

const INTERACTION_RADIUS := 2.15
const NPC_RADIUS := 0.30
const NPC_HEIGHT := 1.62

var interaction_id: StringName = &""
var label := ""
var prompt := "INTERACT"
var kind: int = Kind.HOTSPOT
var available := true

var interaction_area: Area3D
var grounded_body: StaticBody3D
var navigation_obstacle: NavigationObstacle3D
var glint: MeshInstance3D


func configure(id: StringName, target_kind: int, label_text: String, prompt_text: String) -> void:
	interaction_id = id
	kind = clampi(target_kind, Kind.NPC, Kind.HOTSPOT)
	label = label_text
	prompt = prompt_text
	if is_inside_tree():
		_build_nodes()


func _ready() -> void:
	_build_nodes()


func set_available(value: bool) -> void:
	available = value
	if is_instance_valid(interaction_area):
		# Availability is refreshed every frame from the story director. Avoid
		# needlessly re-registering an unchanged Area3D with the physics server,
		# which can invalidate its overlap cache for the current frame.
		if interaction_area.monitoring != value:
			interaction_area.monitoring = value
		if interaction_area.monitorable != value:
			interaction_area.monitorable = value
	if is_instance_valid(glint):
		glint.visible = value


func is_player_inside(player: AshenPlayerActor3D) -> bool:
	if not available or not is_instance_valid(player) or not is_instance_valid(interaction_area):
		return false
	var area_shape := interaction_area.get_node_or_null("InteractionRadius") as CollisionShape3D
	var player_shape := player.get_node_or_null("GroundCollider") as CollisionShape3D
	if (
		is_instance_valid(area_shape)
		and not area_shape.disabled
		and area_shape.shape is SphereShape3D
		and is_instance_valid(player_shape)
		and not player_shape.disabled
		and player_shape.shape is CapsuleShape3D
	):
		# Area3D.overlaps_body() is frame-cached and can be one physics step stale
		# after a checkpoint/scene teleport. Test the same authored shapes directly
		# so prompts are deterministic without replacing the real Area3D contract.
		return _sphere_overlaps_player_capsule(
			area_shape,
			area_shape.shape as SphereShape3D,
			player_shape,
			player_shape.shape as CapsuleShape3D
		)
	return interaction_area.overlaps_body(player)


func _sphere_overlaps_player_capsule(
		sphere_node: CollisionShape3D,
		sphere: SphereShape3D,
		capsule_node: CollisionShape3D,
		capsule: CapsuleShape3D
	) -> bool:
	var capsule_half_segment := maxf(capsule.height * 0.5 - capsule.radius, 0.0)
	var capsule_start_world := capsule_node.global_transform * (Vector3.DOWN * capsule_half_segment)
	var capsule_end_world := capsule_node.global_transform * (Vector3.UP * capsule_half_segment)
	var sphere_inverse := sphere_node.global_transform.affine_inverse()
	var capsule_start_local := sphere_inverse * capsule_start_world
	var capsule_end_local := sphere_inverse * capsule_end_world

	var sphere_scale := sphere_node.global_basis.get_scale().abs()
	var capsule_scale := capsule_node.global_basis.get_scale().abs()
	var minimum_sphere_scale := maxf(minf(sphere_scale.x, minf(sphere_scale.y, sphere_scale.z)), 0.0001)
	var maximum_capsule_scale := maxf(capsule_scale.x, maxf(capsule_scale.y, capsule_scale.z))
	var combined_radius := sphere.radius + capsule.radius * maximum_capsule_scale / minimum_sphere_scale
	return _point_segment_distance_squared(Vector3.ZERO, capsule_start_local, capsule_end_local) <= combined_radius * combined_radius


func _point_segment_distance_squared(point: Vector3, start: Vector3, end: Vector3) -> float:
	var segment := end - start
	var segment_length_squared := segment.length_squared()
	if segment_length_squared <= 0.000001:
		return point.distance_squared_to(start)
	var weight := clampf((point - start).dot(segment) / segment_length_squared, 0.0, 1.0)
	return point.distance_squared_to(start + segment * weight)


func interaction_point() -> Vector3:
	return global_position + Vector3.UP * (0.92 if kind == Kind.NPC else 0.36)


func _build_nodes() -> void:
	if not is_instance_valid(interaction_area):
		interaction_area = get_node_or_null("InteractionArea") as Area3D
	if interaction_area == null:
		interaction_area = Area3D.new()
		interaction_area.name = "InteractionArea"
		add_child(interaction_area)
	AshenCollisionLayers3D.configure_interactable(interaction_area)
	interaction_area.monitoring = available
	interaction_area.monitorable = available
	var area_shape := interaction_area.get_node_or_null("InteractionRadius") as CollisionShape3D
	if area_shape == null:
		area_shape = CollisionShape3D.new()
		area_shape.name = "InteractionRadius"
		interaction_area.add_child(area_shape)
	var sphere := area_shape.shape as SphereShape3D
	if sphere == null:
		sphere = SphereShape3D.new()
		area_shape.shape = sphere
	sphere.radius = INTERACTION_RADIUS
	area_shape.position = Vector3.UP * 0.72

	if kind == Kind.NPC:
		_build_npc_footprint()
		if is_instance_valid(glint):
			glint.queue_free()
	else:
		_build_hotspot_glint()
		if is_instance_valid(grounded_body):
			grounded_body.queue_free()
			grounded_body = null
		if is_instance_valid(navigation_obstacle):
			navigation_obstacle.queue_free()
			navigation_obstacle = null


func _build_npc_footprint() -> void:
	if not is_instance_valid(grounded_body):
		grounded_body = get_node_or_null("GroundedBody") as StaticBody3D
	if grounded_body == null:
		grounded_body = StaticBody3D.new()
		grounded_body.name = "GroundedBody"
		add_child(grounded_body)
	AshenCollisionLayers3D.configure_npc(grounded_body)
	var collision := grounded_body.get_node_or_null("Footprint") as CollisionShape3D
	if collision == null:
		collision = CollisionShape3D.new()
		collision.name = "Footprint"
		grounded_body.add_child(collision)
	var capsule := collision.shape as CapsuleShape3D
	if capsule == null:
		capsule = CapsuleShape3D.new()
		collision.shape = capsule
	capsule.radius = NPC_RADIUS
	capsule.height = NPC_HEIGHT
	collision.position = Vector3.UP * (NPC_HEIGHT * 0.5)

	if not is_instance_valid(navigation_obstacle):
		navigation_obstacle = get_node_or_null("NavigationObstacle3D") as NavigationObstacle3D
	if navigation_obstacle == null:
		navigation_obstacle = NavigationObstacle3D.new()
		navigation_obstacle.name = "NavigationObstacle3D"
		add_child(navigation_obstacle)
	navigation_obstacle.radius = NPC_RADIUS + 0.12
	navigation_obstacle.height = NPC_HEIGHT
	navigation_obstacle.avoidance_enabled = true
	navigation_obstacle.affect_navigation_mesh = true


func _build_hotspot_glint() -> void:
	if not is_instance_valid(glint):
		glint = get_node_or_null("EvidenceGlint") as MeshInstance3D
	if glint == null:
		glint = MeshInstance3D.new()
		glint.name = "EvidenceGlint"
		add_child(glint)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.28, 0.28)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_color = Color(0.61, 0.89, 0.91, 0.78)
	material.emission_enabled = true
	material.emission = Color(0.38, 0.82, 0.86)
	material.emission_energy_multiplier = 2.0
	quad.material = material
	glint.mesh = quad
	glint.position = Vector3.UP * 0.38
	glint.visible = available
