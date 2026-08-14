extends CharacterBody3D
class_name AshenPlayerActor3D

signal health_changed(value: float, maximum: float)
signal stamina_changed(value: float, maximum: float)
signal interact_requested
signal focus_changed(active: bool)
signal defeated(cause: String)
signal shove_emitted(origin: Vector3, direction: Vector3)

const WALK_SPEED := 3.8
const SPRINT_SPEED := 5.6
const DODGE_SPEED := 8.5
const GROUND_ACCELERATION := 24.0
const GROUND_DECELERATION := 32.0
const MAX_HEALTH := 100.0
const MAX_STAMINA := 100.0
const COLLIDER_RADIUS := 0.32
const COLLIDER_HEIGHT := 1.68
const COLLIDER_CENTER_HEIGHT := COLLIDER_HEIGHT * 0.5
const SHOVE_ORIGIN_HEIGHT := 0.9

var controls_enabled := true
var health := MAX_HEALTH
var stamina := MAX_STAMINA
var facing := Vector3.BACK
var focus_active := false
var noise_level := 0.8
var movement_reference: Node3D

var _dodge_time := 0.0
var _dodge_cooldown := 0.0
var _shove_cooldown := 0.0
var _invulnerable_time := 0.0


func _ready() -> void:
	AshenCollisionLayers3D.configure_player(self)
	up_direction = Vector3.UP
	floor_stop_on_slope = true
	floor_constant_speed = true
	floor_snap_length = 0.18
	floor_max_angle = deg_to_rad(25.0)
	safe_margin = 0.02
	_ensure_collision_shape()
	health_changed.emit(health, MAX_HEALTH)
	stamina_changed.emit(stamina, MAX_STAMINA)


func _physics_process(delta: float) -> void:
	_dodge_time = maxf(0.0, _dodge_time - delta)
	_dodge_cooldown = maxf(0.0, _dodge_cooldown - delta)
	_shove_cooldown = maxf(0.0, _shove_cooldown - delta)
	_invulnerable_time = maxf(0.0, _invulnerable_time - delta)

	if not controls_enabled:
		_set_horizontal_velocity(_horizontal_velocity().move_toward(Vector3.ZERO, GROUND_DECELERATION * delta))
		_apply_gravity(delta)
		move_and_slide()
		return

	if Input.is_action_just_pressed("interact"):
		interact_requested.emit()
	if Input.is_action_just_pressed("focus"):
		focus_active = not focus_active
		focus_changed.emit(focus_active)
	if Input.is_action_just_pressed("shove"):
		_try_shove()

	var input_axis := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var move_direction := get_world_move_direction(input_axis)
	if move_direction.length_squared() > 0.001:
		facing = move_direction

	if Input.is_action_just_pressed("dodge") and _dodge_cooldown <= 0.0 and stamina >= 24.0:
		_dodge_time = 0.19
		_dodge_cooldown = 0.62
		_invulnerable_time = 0.27
		_set_stamina(stamina - 24.0)

	if _dodge_time > 0.0:
		_set_horizontal_velocity(facing * DODGE_SPEED)
		noise_level = 5.2
	else:
		var sprinting := Input.is_action_pressed("sprint") and move_direction.length_squared() > 0.001 and stamina > 1.0
		var speed := SPRINT_SPEED if sprinting else WALK_SPEED
		var desired_velocity := move_direction * speed
		var acceleration := GROUND_ACCELERATION if desired_velocity.length_squared() > 0.001 else GROUND_DECELERATION
		_set_horizontal_velocity(_horizontal_velocity().move_toward(desired_velocity, acceleration * delta))
		if sprinting:
			_set_stamina(stamina - 27.0 * delta)
			noise_level = 4.4
		else:
			_set_stamina(stamina + 20.0 * delta)
			noise_level = 2.0 if move_direction.length_squared() > 0.001 else 0.65

	_apply_gravity(delta)
	move_and_slide()


func set_movement_reference(reference: Node3D) -> void:
	movement_reference = reference


func get_world_move_direction(input_axis: Vector2) -> Vector3:
	if input_axis.length_squared() <= 0.001:
		return Vector3.ZERO
	if is_instance_valid(movement_reference):
		var reference_forward := -movement_reference.global_basis.z
		var reference_right := movement_reference.global_basis.x
		reference_forward.y = 0.0
		reference_right.y = 0.0
		if reference_forward.length_squared() > 0.001 and reference_right.length_squared() > 0.001:
			return (reference_right.normalized() * input_axis.x + reference_forward.normalized() * -input_axis.y).normalized()
	return Vector3(input_axis.x, 0.0, input_axis.y).normalized()


func take_damage(amount: float, source_name: String = "an agent") -> void:
	if _invulnerable_time > 0.0 or health <= 0.0:
		return
	health = maxf(0.0, health - maxf(amount, 0.0))
	_invulnerable_time = 0.48
	health_changed.emit(health, MAX_HEALTH)
	if health <= 0.0:
		controls_enabled = false
		defeated.emit("Cornered by %s" % source_name)


func heal(amount: float) -> void:
	health = minf(MAX_HEALTH, health + maxf(amount, 0.0))
	health_changed.emit(health, MAX_HEALTH)


func reset_body(at_position: Vector3, scar_count: int = 0) -> void:
	global_position = at_position
	velocity = Vector3.ZERO
	controls_enabled = true
	health = MAX_HEALTH - minf(24.0, float(maxi(scar_count, 0)) * 4.0)
	stamina = MAX_STAMINA
	_dodge_time = 0.0
	_dodge_cooldown = 0.0
	_shove_cooldown = 0.0
	_invulnerable_time = 1.0
	focus_active = false
	health_changed.emit(health, MAX_HEALTH)
	stamina_changed.emit(stamina, MAX_STAMINA)
	focus_changed.emit(false)


func get_noise_radius() -> float:
	return noise_level


func get_shove_origin() -> Vector3:
	return global_position + Vector3.UP * SHOVE_ORIGIN_HEIGHT


func _try_shove() -> void:
	if _shove_cooldown > 0.0 or stamina < 14.0:
		return
	_shove_cooldown = 0.48
	_set_stamina(stamina - 14.0)
	shove_emitted.emit(get_shove_origin(), facing)


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
	collision.position = Vector3.UP * COLLIDER_CENTER_HEIGHT


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


func _set_stamina(value: float) -> void:
	var next_value := clampf(value, 0.0, MAX_STAMINA)
	if is_equal_approx(next_value, stamina):
		return
	stamina = next_value
	stamina_changed.emit(stamina, MAX_STAMINA)
