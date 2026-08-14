extends Node3D
class_name AshenCameraRig3D

## Fixed-angle, low-FOV camera used by the HD-2D presentation.
## The player may use this rig as its movement reference so screen-up always moves
## into the scene. Reduced-motion mode snaps the rig instead of easing it.

const MIN_FOV := 18.0
const MAX_FOV := 32.0

@export var target_path: NodePath
@export_range(MIN_FOV, MAX_FOV, 0.5) var field_of_view := 22.0
@export_range(4.0, 24.0, 0.25) var follow_distance := 13.5
@export_range(3.0, 20.0, 0.25) var camera_height := 10.5
@export_range(-180.0, 180.0, 0.5) var yaw_degrees := 45.0
@export_range(0.0, 3.0, 0.05) var focus_height := 0.9
@export_range(0.0, 16.0, 0.25) var follow_sharpness := 7.0
@export_range(0.0, 4.0, 0.05) var look_ahead_distance := 1.15

var target: Node3D
var reduced_motion := false

var _camera: Camera3D
var _initialized := false


func _ready() -> void:
	if target == null and not target_path.is_empty():
		target = get_node_or_null(target_path) as Node3D
	_ensure_camera()
	if is_instance_valid(target):
		global_position = target.global_position
		_initialized = true
	_update_camera_transform()


func _process(delta: float) -> void:
	if not is_instance_valid(target):
		return
	var desired := target.global_position + _target_look_ahead()
	if not _initialized or reduced_motion or follow_sharpness <= 0.0:
		global_position = desired
		_initialized = true
	else:
		var weight := 1.0 - exp(-follow_sharpness * maxf(delta, 0.0))
		global_position = global_position.lerp(desired, weight)
	_update_camera_transform()


func set_target(new_target: Node3D, snap: bool = true) -> void:
	target = new_target
	if snap and is_instance_valid(target) and is_inside_tree():
		global_position = target.global_position
		_initialized = true
	elif snap:
		_initialized = false
	if is_inside_tree():
		_update_camera_transform()


func set_reduced_motion(enabled: bool) -> void:
	reduced_motion = enabled
	if enabled and is_instance_valid(target) and is_inside_tree():
		global_position = target.global_position
		_initialized = true
		_update_camera_transform()


func get_camera() -> Camera3D:
	_ensure_camera()
	return _camera


func get_ground_forward() -> Vector3:
	_ensure_camera()
	var forward := -_camera.global_basis.z
	forward.y = 0.0
	return forward.normalized() if forward.length_squared() > 0.0001 else Vector3.FORWARD


func get_ground_right() -> Vector3:
	var right := get_ground_forward().cross(Vector3.UP).normalized()
	return right if right.length_squared() > 0.0001 else Vector3.RIGHT


func snap_to_target() -> void:
	if not is_instance_valid(target) or not is_inside_tree():
		return
	global_position = target.global_position
	_initialized = true
	_update_camera_transform()


func _ensure_camera() -> void:
	if is_instance_valid(_camera):
		return
	_camera = get_node_or_null("Camera3D") as Camera3D
	if _camera == null:
		_camera = Camera3D.new()
		_camera.name = "Camera3D"
		add_child(_camera)
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.fov = clampf(field_of_view, MIN_FOV, MAX_FOV)
	_camera.near = 0.08
	_camera.far = 500.0
	_camera.current = true


func _target_look_ahead() -> Vector3:
	if reduced_motion or not target is CharacterBody3D:
		return Vector3.ZERO
	var body := target as CharacterBody3D
	var horizontal_velocity := Vector3(body.velocity.x, 0.0, body.velocity.z)
	if horizontal_velocity.length_squared() <= 0.01:
		return Vector3.ZERO
	return horizontal_velocity.normalized() * look_ahead_distance


func _update_camera_transform() -> void:
	_ensure_camera()
	_camera.fov = clampf(field_of_view, MIN_FOV, MAX_FOV)
	var yaw := deg_to_rad(yaw_degrees)
	var offset := Vector3(0.0, camera_height, follow_distance).rotated(Vector3.UP, yaw)
	_camera.global_position = global_position + offset
	var focus := global_position + Vector3.UP * focus_height
	if _camera.global_position.distance_squared_to(focus) > 0.0001:
		_camera.look_at(focus, Vector3.UP)
