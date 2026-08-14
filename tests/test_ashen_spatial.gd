extends SceneTree

const CollisionLayers := preload("res://scripts/ashen_3d/collision_layers_3d.gd")
const LandmarkRegistry := preload("res://scripts/ashen_3d/landmark_registry_3d.gd")
const PlayerActor := preload("res://scripts/ashen_3d/player_actor_3d.gd")
const CameraRig := preload("res://scripts/ashen_3d/camera_rig_3d.gd")
const EnemyAgent := preload("res://scripts/ashen_3d/enemy_agent_3d.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error("[ashen-spatial] %s" % message)


func _run() -> void:
	_test_collision_contract()
	var registry: Variant = await _build_registry_fixture()
	var player: Variant = await _test_player_foundation()
	var camera_rig: Variant = await _test_camera_foundation(player)
	await _test_enemy_foundation(player, registry)

	camera_rig.queue_free()
	player.queue_free()
	registry.queue_free()
	await process_frame
	await process_frame
	if failures.is_empty():
		print("[ashen-spatial] PASS")
		quit(0)
	else:
		print("[ashen-spatial] FAIL (%d)" % failures.size())
		quit(1)


func _test_collision_contract() -> void:
	_check(CollisionLayers.WORLD_SOLID == 1, "WorldSolid is exactly physics layer 1.")
	_check(CollisionLayers.PLAYER == 2, "Player is exactly physics layer 2.")
	_check(CollisionLayers.ENEMY == 4, "Enemy is exactly physics layer 3.")
	_check(CollisionLayers.NPC == 8, "NPC is exactly physics layer 4.")
	_check(CollisionLayers.INTERACTABLE_AREA == 16, "InteractableArea is exactly physics layer 5.")
	_check(CollisionLayers.VISION_OCCLUDER == 32, "VisionOccluder is exactly physics layer 6.")
	_check(CollisionLayers.TRAVERSAL_TRIGGER == 64, "TraversalTrigger is exactly physics layer 7.")
	_check(CollisionLayers.TERRAIN_HAZARD == 128, "TerrainHazard is exactly physics layer 8.")
	_check(CollisionLayers.PARTICLE_COLLIDER == 256, "ParticleCollider is exactly physics layer 9.")
	_check(CollisionLayers.layer_name(9) == "ParticleCollider", "Physics layer 9 has the locked ParticleCollider name.")
	_check(CollisionLayers.PLAYER_BODY_MASK == CollisionLayers.WORLD_SOLID | CollisionLayers.ENEMY | CollisionLayers.NPC, "Player collides only with world, enemies, and NPC footprints.")
	_check(CollisionLayers.ENEMY_BODY_MASK == CollisionLayers.WORLD_SOLID | CollisionLayers.PLAYER, "Enemy collides with world and player, not other enemies.")
	_check((CollisionLayers.ENEMY_BODY_MASK & CollisionLayers.ENEMY) == 0, "Enemy bodies cannot form physical crowd deadlocks.")
	_check(CollisionLayers.INTERACTABLE_DETECTION_MASK == CollisionLayers.PLAYER, "Interactable areas detect only the player body.")


func _build_registry_fixture():
	var registry := LandmarkRegistry.new()
	registry.name = "LandmarkRegistry3D"
	var fen_zone := Node3D.new()
	fen_zone.name = "FenRoad"
	fen_zone.set_meta(&"zone_id", &"fen_road")
	registry.add_child(fen_zone)

	var arrival := Marker3D.new()
	arrival.name = "EvanArrival"
	arrival.position = Vector3(2.0, 0.0, 6.0)
	arrival.set_meta(&"landmark_id", &"fen_road/evan_arrival")
	fen_zone.add_child(arrival)

	var gate := Marker3D.new()
	gate.name = "WestGateInside"
	gate.position = Vector3(9.0, 0.0, 2.0)
	gate.set_meta(&"landmark_id", &"fen_road/west_gate_inside")
	fen_zone.add_child(gate)

	var refuge_zone := Node3D.new()
	refuge_zone.name = "RefugeRow"
	refuge_zone.set_meta(&"zone_id", &"refuge_row")
	registry.add_child(refuge_zone)
	var defense := Marker3D.new()
	defense.name = "GranaryDefense"
	defense.position = Vector3(32.0, 0.0, -14.0)
	defense.set_meta(&"landmark_id", &"refuge_row/granary_defense")
	refuge_zone.add_child(defense)

	registry.set_process(false)
	root.add_child(registry)
	await process_frame
	_check(registry.has_landmark(&"fen_road/evan_arrival"), "Registry discovers a slash-qualified semantic arrival anchor.")
	_check(registry.has_landmark(&"refuge_row/granary_defense"), "Registry discovers the V2 finale defense anchor.")
	_check(registry.get_zone_id(&"fen_road/west_gate_inside") == &"fen_road", "Landmarks inherit their owning zone ID.")
	_check(registry.get_landmark_position(&"fen_road/evan_arrival").is_equal_approx(Vector3(2.0, 0.0, 6.0)), "Registry resolves authored 3D positions.")
	_check(registry.find_closest_landmark(Vector3(8.5, 0.0, 2.0), &"fen_road") == &"fen_road/west_gate_inside", "Registry resolves the nearest anchor within a requested zone.")
	var duplicate := Marker3D.new()
	_check(not registry.register_landmark(&"fen_road/evan_arrival", duplicate, &"fen_road"), "Registry rejects duplicate semantic IDs instead of silently replacing anchors.")
	duplicate.free()
	return registry


func _test_player_foundation():
	var player := PlayerActor.new()
	player.name = "Evan3D"
	player.set_physics_process(false)
	root.add_child(player)
	await process_frame
	_check(player.collision_layer == CollisionLayers.PLAYER, "Player body uses the Player layer.")
	_check(player.collision_mask == CollisionLayers.PLAYER_BODY_MASK, "Player body uses the exact collision mask contract.")
	_check(is_equal_approx(player.safe_margin, 0.02), "Player uses a metre-scale collision margin.")
	_check(is_equal_approx(player.floor_snap_length, 0.18), "Player controller has stable slope/floor snapping.")
	_check(is_equal_approx(player.floor_max_angle, deg_to_rad(25.0)), "Player floor limit matches the locked 25-degree traversal slope.")
	var collision := player.get_node_or_null("GroundCollider") as CollisionShape3D
	_check(collision != null and collision.shape is CapsuleShape3D, "Player owns an explicit capsule collision proxy.")
	if collision and collision.shape is CapsuleShape3D:
		var capsule := collision.shape as CapsuleShape3D
		_check(is_equal_approx(capsule.radius, PlayerActor.COLLIDER_RADIUS), "Player capsule radius follows the spatial scale contract.")
		_check(is_equal_approx(collision.position.y, PlayerActor.COLLIDER_CENTER_HEIGHT), "Player collider is anchored from the character's feet.")
	_check(player.get_world_move_direction(Vector2(0.0, -1.0)).is_equal_approx(Vector3.FORWARD), "Default screen-up movement travels into the 3D scene.")
	player.reset_body(Vector3(4.0, 0.0, 5.0), 3)
	_check(player.global_position.is_equal_approx(Vector3(4.0, 0.0, 5.0)), "Player reset accepts a full 3D safe spawn.")
	_check(is_equal_approx(player.health, 88.0), "Existing soul-scar health semantics survive the 3D controller migration.")
	return player


func _test_camera_foundation(player):
	var camera_rig := CameraRig.new()
	camera_rig.name = "AshenCameraRig3D"
	camera_rig.set_target(player)
	camera_rig.set_process(false)
	root.add_child(camera_rig)
	await process_frame
	var camera := camera_rig.get_camera()
	_check(camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "HD-2D camera uses perspective projection.")
	_check(camera.fov >= CameraRig.MIN_FOV and camera.fov <= CameraRig.MAX_FOV, "Camera remains inside the fixed low-FOV range.")
	_check(is_equal_approx(camera.fov, 22.0), "Camera uses the locked 22-degree nominal field of view.")
	_check(is_equal_approx(camera_rig.yaw_degrees, 45.0), "Camera uses the locked 45-degree nominal yaw.")
	_check(is_equal_approx(camera_rig.camera_height, 26.25) and is_equal_approx(camera_rig.follow_distance, 35.0), "Camera uses the locked exploration-scale height/distance baseline.")
	_check(absf(camera_rig.get_nominal_pitch_degrees() - 36.0) <= 0.5, "Camera uses the locked nominal 36-degree pitch.")
	var actor_pixels := camera_rig.estimate_actor_pixel_height(1080.0, 1.72)
	_check(actor_pixels >= 100.0 and actor_pixels <= 120.0, "A 1.72 m actor projects to 100-120 pixels at 1080p (%.2f)." % actor_pixels)
	_check(camera.current, "The phase-one 3D camera makes itself current.")
	var forward := camera_rig.get_ground_forward()
	var right := camera_rig.get_ground_right()
	_check(absf(forward.dot(Vector3.UP)) < 0.001 and is_equal_approx(forward.length(), 1.0), "Camera exposes a normalized ground-plane forward vector.")
	_check(absf(forward.dot(right)) < 0.001 and is_equal_approx(right.length(), 1.0), "Camera ground basis is orthonormal.")
	player.set_movement_reference(camera)
	_check(player.get_world_move_direction(Vector2(0.0, -1.0)).dot(forward) > 0.999, "Camera-relative player input agrees with screen framing.")
	camera_rig.set_reduced_motion(true)
	player.global_position = Vector3(12.0, 0.0, -7.0)
	camera_rig._process(1.0 / 60.0)
	_check(camera_rig.global_position.is_equal_approx(player.global_position), "Reduced motion snaps follow movement without camera easing.")
	return camera_rig


func _test_enemy_foundation(player, registry) -> void:
	var enemy := EnemyAgent.new()
	enemy.name = "WestRoadObserver3D"
	enemy.configure(
		player,
		registry,
		[&"fen_road/evan_arrival", &"fen_road/west_gate_inside"],
		&"west_road_observer",
		"West-road observer"
	)
	enemy.set_physics_process(false)
	root.add_child(enemy)
	await process_frame
	_check(enemy.stable_agent_id == &"west_road_observer", "Enemy has a stable save identity independent of its display name.")
	_check(enemy.collision_layer == CollisionLayers.ENEMY, "Enemy body uses the Enemy layer.")
	_check(enemy.collision_mask == CollisionLayers.ENEMY_BODY_MASK, "Enemy body uses the exact world/player-only mask.")
	_check(is_equal_approx(enemy.floor_max_angle, deg_to_rad(25.0)), "Enemy floor limit matches the locked 25-degree navigation slope.")
	_check((enemy.collision_mask & CollisionLayers.ENEMY) == 0, "Enemy bodies rely on navigation avoidance rather than physical crowd collision.")
	_check(enemy.patrol_route_is_resolved(), "Enemy patrol resolves semantic registry anchors.")
	_check(enemy.get_patrol_position(1).is_equal_approx(registry.get_landmark_position(&"fen_road/west_gate_inside")), "Enemy patrol positions come from the landmark registry.")
	var navigation := enemy.get_navigation_agent()
	_check(navigation.avoidance_enabled, "NavigationAgent3D avoidance is active for a live enemy.")
	_check(not navigation.use_3d_avoidance, "Ground enemies use planar avoidance to prevent vertical drift.")
	_check(navigation.radius > EnemyAgent.COLLIDER_RADIUS, "Navigation clearance is wider than the physical capsule.")

	enemy.global_position = player.global_position + Vector3.RIGHT * 0.8
	var shove_origin: Vector3 = player.global_position + Vector3.UP * PlayerActor.SHOVE_ORIGIN_HEIGHT
	_check(enemy.receive_shove(shove_origin, Vector3.RIGHT), "3D shove reaches an unobstructed enemy in the forward cone.")
	enemy.receive_shove(shove_origin, Vector3.RIGHT)
	enemy.receive_shove(shove_origin, Vector3.RIGHT)
	_check(enemy.state == EnemyAgent.State.SURRENDERED, "Repeated non-lethal 3D pressure reaches surrendered state.")

	var saved := enemy.to_save_state()
	_check(saved.get("agent_id") == "west_road_observer", "Enemy save state serializes its stable agent ID.")
	_check(saved.get("position") is Array and saved["position"].size() == 3, "Enemy save state serializes a three-component position.")
	_check(saved.get("facing") is Array and saved["facing"].size() == 3, "Enemy save state serializes a three-component facing vector.")
	enemy.queue_free()
	await process_frame
