extends CharacterBody3D
class_name AshenEnemyAgent3D

signal state_changed(agent: AshenEnemyAgent3D, new_state: int)
signal surrendered(agent: AshenEnemyAgent3D)

enum State { PATROL, NOTICE, INVESTIGATE, CHASE, STRIKE, SEARCH, RETURN, STUNNED, SURRENDERED }

const COLLIDER_RADIUS := 0.32
const COLLIDER_HEIGHT := 1.68
const EYE_HEIGHT := 1.48
const TARGET_TORSO_HEIGHT := 0.92

@export var stable_agent_id: StringName = &"choir_agent"
@export var display_name := "Choir agent"
@export var patrol_speed := 2.05
@export var chase_speed := 3.65
@export var vision_range := 10.5
@export_range(10.0, 85.0, 0.5) var vision_half_angle_degrees := 48.0
@export var attack_range := 1.18
@export var attack_damage := 18.0
@export var patrol_landmark_ids: Array[StringName] = []

var target: AshenPlayerActor3D
var landmark_registry: AshenLandmarkRegistry3D
var state := State.PATROL
var suspicion := 0.0
var resolve := 100.0
var facing := Vector3.RIGHT
var last_known_position := Vector3.ZERO

var _fallback_patrol_points := PackedVector3Array()
var _patrol_index := 0
var _lost_time := 0.0
var _search_time := 0.0
var _attack_cooldown := 0.0
var _stun_time := 0.0
var _strike_windup := 0.0
var _safe_velocity := Vector3.ZERO
var _safe_velocity_age := INF
var _navigation_agent: NavigationAgent3D


func _ready() -> void:
	if state == State.SURRENDERED:
		collision_layer = 0
		collision_mask = AshenCollisionLayers3D.WORLD_SOLID
	else:
		AshenCollisionLayers3D.configure_enemy(self)
	up_direction = Vector3.UP
	floor_stop_on_slope = true
	floor_constant_speed = true
	floor_snap_length = 0.18
	floor_max_angle = deg_to_rad(25.0)
	safe_margin = 0.02
	_ensure_collision_shape()
	_ensure_navigation_agent()


func configure(
		new_target: AshenPlayerActor3D,
		registry: AshenLandmarkRegistry3D,
		route_ids: Array[StringName],
		agent_id: StringName,
		name_text: String = "Choir agent"
	) -> void:
	target = new_target
	landmark_registry = registry
	patrol_landmark_ids = route_ids.duplicate()
	stable_agent_id = agent_id
	display_name = name_text
	_patrol_index = 0
	if has_patrol_position(0):
		_set_spawn_position(get_patrol_position(0))


func configure_fallback_points(
		new_target: AshenPlayerActor3D,
		points: PackedVector3Array,
		agent_id: StringName,
		name_text: String = "Choir agent"
	) -> void:
	target = new_target
	landmark_registry = null
	patrol_landmark_ids.clear()
	_fallback_patrol_points = points
	stable_agent_id = agent_id
	display_name = name_text
	_patrol_index = 0
	if not points.is_empty():
		_set_spawn_position(points[0])


func _physics_process(delta: float) -> void:
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	_strike_windup = maxf(0.0, _strike_windup - delta)
	_safe_velocity_age += delta

	if state == State.SURRENDERED:
		_stop_horizontal_motion()
		_apply_gravity(delta)
		move_and_slide()
		return

	if state == State.STUNNED:
		_stun_time -= delta
		_set_horizontal_velocity(_horizontal_velocity().move_toward(Vector3.ZERO, 12.5 * delta))
		_apply_gravity(delta)
		move_and_slide()
		if _stun_time <= 0.0:
			_search_time = 2.8
			_set_state(State.SEARCH)
		return

	if not is_instance_valid(target) or not target.controls_enabled:
		_stop_horizontal_motion()
		_apply_gravity(delta)
		move_and_slide()
		return

	var can_see := can_see_target()
	var distance := horizontal_distance_to(target.global_position)
	var can_hear := distance <= target.get_noise_radius()
	_update_perception(delta, can_see, can_hear)

	var desired_velocity := Vector3.ZERO
	match state:
		State.PATROL:
			desired_velocity = _follow_patrol(patrol_speed)
		State.NOTICE:
			if not can_see:
				_set_state(State.INVESTIGATE)
		State.INVESTIGATE:
			desired_velocity = _navigation_velocity_to(last_known_position, patrol_speed * 1.08)
			if horizontal_distance_to(last_known_position) < 0.5:
				_search_time = 3.1
				_set_state(State.SEARCH)
		State.CHASE:
			desired_velocity = _navigation_velocity_to(target.global_position, chase_speed)
			if distance <= attack_range and can_see:
				_set_state(State.STRIKE)
			elif not can_see:
				_lost_time += delta
				if _lost_time >= 2.0:
					_search_time = 4.0
					_set_state(State.SEARCH)
		State.STRIKE:
			face_toward(target.global_position)
			if distance > attack_range * 1.35 or not can_see:
				_set_state(State.CHASE)
			elif _strike_windup <= 0.0 and _attack_cooldown <= 0.0:
				_attack_cooldown = 1.0
				target.take_damage(attack_damage, display_name)
		State.SEARCH:
			_search_time -= delta
			var sweep_direction := facing.rotated(Vector3.UP, sin(_search_time * 2.4) * 0.9)
			desired_velocity = _navigation_velocity_to(last_known_position + sweep_direction * 1.8, patrol_speed * 0.65)
			if can_see:
				_set_state(State.CHASE)
			elif _search_time <= 0.0:
				_set_state(State.RETURN)
		State.RETURN:
			if not has_patrol_position(_patrol_index):
				_set_state(State.PATROL)
			else:
				var return_point: Vector3 = get_patrol_position(_patrol_index)
				desired_velocity = _navigation_velocity_to(return_point, patrol_speed)
				if horizontal_distance_to(return_point) < 0.45:
					_set_state(State.PATROL)

	if desired_velocity.length_squared() > 0.001:
		face_toward(global_position + desired_velocity)
	_set_horizontal_velocity(desired_velocity)
	_apply_gravity(delta)
	move_and_slide()


func can_see_target() -> bool:
	if not is_instance_valid(target):
		return false
	var offset := target.global_position - global_position
	offset.y = 0.0
	if offset.length_squared() <= 0.0001 or offset.length() > vision_range:
		return false
	var horizontal_facing := facing
	horizontal_facing.y = 0.0
	if horizontal_facing.length_squared() <= 0.0001:
		horizontal_facing = Vector3.FORWARD
	if horizontal_facing.normalized().dot(offset.normalized()) < cos(deg_to_rad(vision_half_angle_degrees)):
		return false
	return has_clear_line_to(target.global_position + Vector3.UP * TARGET_TORSO_HEIGHT, target)


func has_clear_line_to(destination: Vector3, expected_target: CollisionObject3D = null) -> bool:
	if not is_inside_tree():
		return false
	var origin := global_position + Vector3.UP * EYE_HEIGHT
	var query := PhysicsRayQueryParameters3D.create(origin, destination, AshenCollisionLayers3D.VISION_RAY_MASK)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or (expected_target != null and hit.get("collider") == expected_target)


func receive_shove(origin: Vector3, direction: Vector3) -> bool:
	var shove_direction := direction
	shove_direction.y = 0.0
	if shove_direction.length_squared() <= 0.0001 or state == State.SURRENDERED:
		return false
	shove_direction = shove_direction.normalized()
	var offset := global_position - origin
	offset.y = 0.0
	if offset.length() > 1.35:
		return false
	if offset.length_squared() > 0.001 and shove_direction.dot(offset.normalized()) < cos(0.72):
		return false
	if is_inside_tree():
		var destination := global_position + Vector3.UP * TARGET_TORSO_HEIGHT
		var query := PhysicsRayQueryParameters3D.create(origin, destination, AshenCollisionLayers3D.SHOVE_OCCLUSION_MASK)
		query.exclude = [get_rid()]
		if not get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			return false

	resolve -= 36.0
	_set_horizontal_velocity(shove_direction * 4.8)
	if resolve <= 0.0:
		_set_state(State.SURRENDERED)
		collision_layer = 0
		collision_mask = AshenCollisionLayers3D.WORLD_SOLID
		if is_instance_valid(_navigation_agent):
			_navigation_agent.avoidance_enabled = false
		surrendered.emit(self)
	else:
		_stun_time = 0.72
		_set_state(State.STUNNED)
	return true


func face_toward(point: Vector3) -> void:
	var direction := point - global_position
	direction.y = 0.0
	if direction.length_squared() > 0.0001:
		facing = direction.normalized()


func horizontal_distance_to(point: Vector3) -> float:
	var offset := point - global_position
	offset.y = 0.0
	return offset.length()


func patrol_route_is_resolved() -> bool:
	if not patrol_landmark_ids.is_empty():
		if not is_instance_valid(landmark_registry):
			return false
		for id in patrol_landmark_ids:
			if not landmark_registry.has_landmark(id):
				return false
		return true
	return not _fallback_patrol_points.is_empty()


func has_patrol_position(index: int) -> bool:
	if not patrol_landmark_ids.is_empty():
		return (
			is_instance_valid(landmark_registry)
			and index >= 0
			and index < patrol_landmark_ids.size()
			and landmark_registry.has_landmark(patrol_landmark_ids[index])
		)
	return index >= 0 and index < _fallback_patrol_points.size()


func get_patrol_position(index: int) -> Vector3:
	if not patrol_landmark_ids.is_empty():
		if not has_patrol_position(index):
			return global_position if is_inside_tree() else position
		var landmark_id := patrol_landmark_ids[index]
		return landmark_registry.get_landmark_position(landmark_id)
	if index >= 0 and index < _fallback_patrol_points.size():
		return _fallback_patrol_points[index]
	return global_position if is_inside_tree() else position


func to_save_state() -> Dictionary:
	return {
		"agent_id": str(stable_agent_id),
		"state": state,
		"resolve": resolve,
		"suspicion": suspicion,
		"position": [global_position.x, global_position.y, global_position.z],
		"last_known": [last_known_position.x, last_known_position.y, last_known_position.z],
		"patrol_index": _patrol_index,
		"facing": [facing.x, facing.y, facing.z],
	}


func restore_save_state(data: Dictionary) -> void:
	resolve = clampf(float(data.get("resolve", 100.0)), 0.0, 100.0)
	suspicion = clampf(float(data.get("suspicion", 0.0)), 0.0, 1.0)
	state = clampi(int(data.get("state", State.PATROL)), State.PATROL, State.SURRENDERED)
	_patrol_index = clampi(int(data.get("patrol_index", 0)), 0, maxi(_patrol_count() - 1, 0))
	var saved_position := _array_to_vector3(data.get("position", []), global_position)
	var saved_last_known := _array_to_vector3(data.get("last_known", []), last_known_position)
	var saved_facing := _array_to_vector3(data.get("facing", []), facing)
	_set_spawn_position(saved_position)
	last_known_position = saved_last_known
	saved_facing.y = 0.0
	if saved_facing.length_squared() > 0.0001:
		facing = saved_facing.normalized()
	if state == State.SURRENDERED:
		collision_layer = 0
		collision_mask = AshenCollisionLayers3D.WORLD_SOLID
		if is_instance_valid(_navigation_agent):
			_navigation_agent.avoidance_enabled = false
	else:
		AshenCollisionLayers3D.configure_enemy(self)
		if is_instance_valid(_navigation_agent):
			_navigation_agent.avoidance_enabled = true


func reset_agent() -> void:
	resolve = 100.0
	suspicion = 0.0
	_lost_time = 0.0
	_search_time = 0.0
	_attack_cooldown = 0.0
	_strike_windup = 0.0
	_patrol_index = 0
	AshenCollisionLayers3D.configure_enemy(self)
	_ensure_navigation_agent()
	_navigation_agent.avoidance_enabled = true
	if has_patrol_position(0):
		_set_spawn_position(get_patrol_position(0))
	_set_state(State.PATROL)


func get_navigation_agent() -> NavigationAgent3D:
	_ensure_navigation_agent()
	return _navigation_agent


func _update_perception(delta: float, can_see: bool, can_hear: bool) -> void:
	if can_see:
		last_known_position = target.global_position
		_lost_time = 0.0
		suspicion = minf(1.0, suspicion + delta * (1.55 if state == State.NOTICE else 0.92))
		if suspicion >= 0.32 and state in [State.PATROL, State.RETURN]:
			_set_state(State.NOTICE)
		if suspicion >= 1.0 and state not in [State.CHASE, State.STRIKE]:
			_set_state(State.CHASE)
	elif can_hear and state not in [State.STRIKE, State.STUNNED, State.SURRENDERED]:
		last_known_position = target.global_position
		suspicion = maxf(suspicion, 0.42)
		if state == State.CHASE:
			_lost_time = 0.0
		elif state != State.INVESTIGATE:
			_set_state(State.INVESTIGATE)
	elif state in [State.PATROL, State.NOTICE, State.RETURN]:
		suspicion = maxf(0.0, suspicion - delta * 0.38)


func _follow_patrol(speed: float) -> Vector3:
	if not has_patrol_position(_patrol_index):
		return Vector3.ZERO
	var point: Vector3 = get_patrol_position(_patrol_index)
	var desired := _navigation_velocity_to(point, speed)
	if horizontal_distance_to(point) < 0.42:
		_patrol_index = (_patrol_index + 1) % _patrol_count()
	return desired


func _navigation_velocity_to(destination: Vector3, speed: float) -> Vector3:
	_ensure_navigation_agent()
	if not _navigation_map_is_ready():
		return Vector3.ZERO
	if _navigation_agent.target_position.distance_squared_to(destination) > 0.04:
		_navigation_agent.target_position = destination
	if _navigation_agent.is_navigation_finished():
		_navigation_agent.velocity = Vector3.ZERO
		return Vector3.ZERO
	var next_position := _navigation_agent.get_next_path_position()
	var direction := next_position - global_position
	direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		return Vector3.ZERO
	var desired := direction.normalized() * speed
	_navigation_agent.velocity = desired
	if _safe_velocity_age <= 0.2 and _safe_velocity.length_squared() > 0.0001:
		return Vector3(_safe_velocity.x, 0.0, _safe_velocity.z).limit_length(speed)
	return desired


func _navigation_map_is_ready() -> bool:
	var map_rid := _navigation_agent.get_navigation_map()
	return map_rid.is_valid() and NavigationServer3D.map_get_iteration_id(map_rid) > 0


func _ensure_collision_shape() -> void:
	var collision := get_node_or_null("GroundCollider") as CollisionShape3D
	if collision == null:
		collision = CollisionShape3D.new()
		collision.name = "GroundCollider"
		add_child(collision)
	var capsule := collision.shape as CapsuleShape3D
	if capsule == null:
		capsule = CapsuleShape3D.new()
		collision.shape = capsule
	capsule.radius = COLLIDER_RADIUS
	capsule.height = COLLIDER_HEIGHT
	collision.position = Vector3.UP * (COLLIDER_HEIGHT * 0.5)


func _ensure_navigation_agent() -> void:
	if is_instance_valid(_navigation_agent):
		return
	_navigation_agent = get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if _navigation_agent == null:
		_navigation_agent = NavigationAgent3D.new()
		_navigation_agent.name = "NavigationAgent3D"
		add_child(_navigation_agent)
	_navigation_agent.path_desired_distance = 0.28
	_navigation_agent.target_desired_distance = 0.42
	_navigation_agent.radius = COLLIDER_RADIUS + 0.06
	_navigation_agent.height = COLLIDER_HEIGHT
	_navigation_agent.neighbor_distance = 4.5
	_navigation_agent.max_neighbors = 8
	_navigation_agent.time_horizon_agents = 1.0
	_navigation_agent.time_horizon_obstacles = 0.7
	_navigation_agent.avoidance_enabled = state != State.SURRENDERED
	_navigation_agent.use_3d_avoidance = false
	if not _navigation_agent.velocity_computed.is_connected(_on_navigation_velocity_computed):
		_navigation_agent.velocity_computed.connect(_on_navigation_velocity_computed)


func _on_navigation_velocity_computed(safe_velocity: Vector3) -> void:
	_safe_velocity = safe_velocity
	_safe_velocity.y = 0.0
	_safe_velocity_age = 0.0


func _set_state(next_state: int) -> void:
	if state == next_state:
		return
	state = next_state
	if state == State.STRIKE:
		_strike_windup = 0.32
	state_changed.emit(self, state)


func _patrol_count() -> int:
	return patrol_landmark_ids.size() if not patrol_landmark_ids.is_empty() else _fallback_patrol_points.size()


func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = 0.0
	else:
		var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
		velocity.y -= gravity * delta


func _horizontal_velocity() -> Vector3:
	return Vector3(velocity.x, 0.0, velocity.z)


func _set_horizontal_velocity(value: Vector3) -> void:
	velocity.x = value.x
	velocity.z = value.z


func _stop_horizontal_motion() -> void:
	_set_horizontal_velocity(Vector3.ZERO)
	if is_instance_valid(_navigation_agent):
		_navigation_agent.velocity = Vector3.ZERO


func _set_spawn_position(value: Vector3) -> void:
	if is_inside_tree():
		global_position = value
	else:
		position = value


func _array_to_vector3(value: Variant, fallback: Vector3) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback
