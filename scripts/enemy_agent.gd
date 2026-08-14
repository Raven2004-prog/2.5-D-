extends CharacterBody2D
class_name EnemyAgent

signal state_changed(agent: EnemyAgent, new_state: int)
signal surrendered(agent: EnemyAgent)

enum State { PATROL, NOTICE, INVESTIGATE, CHASE, STRIKE, SEARCH, RETURN, STUNNED, SURRENDERED }

@export var agent_name := "Choir agent"
@export var patrol_speed := 72.0
@export var chase_speed := 128.0
@export var vision_range := 230.0
@export var vision_half_angle := 0.86
@export var attack_damage := 18.0

var target: PlayerActor
var patrol_points := PackedVector2Array()
var state := State.PATROL
var suspicion := 0.0
var resolve := 100.0
var facing := Vector2.RIGHT
var last_known_position := Vector2.ZERO

var _patrol_index := 0
var _lost_time := 0.0
var _search_time := 0.0
var _attack_cooldown := 0.0
var _stun_time := 0.0
var _flash := 0.0


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	if not get_node_or_null("CollisionShape2D"):
		var collision := CollisionShape2D.new()
		var shape := CapsuleShape2D.new()
		shape.radius = 11.0
		shape.height = 30.0
		collision.shape = shape
		collision.position = Vector2(0, 5)
		collision.name = "CollisionShape2D"
		add_child(collision)
	queue_redraw()


func configure(new_target: PlayerActor, points: PackedVector2Array, name_text: String = "Choir agent") -> void:
	target = new_target
	patrol_points = points
	agent_name = name_text
	if patrol_points.size() > 0:
		global_position = patrol_points[0]
	queue_redraw()


func _physics_process(delta: float) -> void:
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	_flash = maxf(0.0, _flash - delta * 5.0)
	if state == State.SURRENDERED:
		velocity = Vector2.ZERO
		return
	if state == State.STUNNED:
		_stun_time -= delta
		velocity = velocity.move_toward(Vector2.ZERO, 560.0 * delta)
		move_and_slide()
		if _stun_time <= 0.0:
			_set_state(State.SEARCH)
			_search_time = 2.8
		queue_redraw()
		return
	if not is_instance_valid(target) or not target.controls_enabled:
		velocity = Vector2.ZERO
		return

	var can_see := _can_see_target()
	var distance := global_position.distance_to(target.global_position)
	var can_hear := distance <= target.get_noise_radius()
	if can_see:
		last_known_position = target.global_position
		_lost_time = 0.0
		suspicion = minf(1.0, suspicion + delta * (1.55 if state == State.NOTICE else 0.92))
		if suspicion >= 0.32 and state in [State.PATROL, State.RETURN]:
			_set_state(State.NOTICE)
		if suspicion >= 1.0 and state != State.CHASE and state != State.STRIKE:
			_set_state(State.CHASE)
	elif can_hear and state in [State.PATROL, State.RETURN]:
		last_known_position = target.global_position
		suspicion = maxf(suspicion, 0.42)
		_set_state(State.INVESTIGATE)
	elif state in [State.PATROL, State.NOTICE, State.RETURN]:
		suspicion = maxf(0.0, suspicion - delta * 0.38)

	match state:
		State.PATROL:
			_follow_patrol(delta)
		State.NOTICE:
			velocity = Vector2.ZERO
			if not can_see:
				_set_state(State.INVESTIGATE)
		State.INVESTIGATE:
			_move_toward(last_known_position, patrol_speed * 1.08)
			if global_position.distance_to(last_known_position) < 16.0:
				_search_time = 3.1
				_set_state(State.SEARCH)
		State.CHASE:
			_move_toward(target.global_position, chase_speed)
			if distance <= 34.0:
				_set_state(State.STRIKE)
			elif not can_see:
				_lost_time += delta
				if _lost_time >= 2.0:
					_search_time = 4.0
					_set_state(State.SEARCH)
		State.STRIKE:
			velocity = Vector2.ZERO
			facing = global_position.direction_to(target.global_position)
			if distance > 42.0:
				_set_state(State.CHASE)
			elif _attack_cooldown <= 0.0:
				_attack_cooldown = 1.0
				_flash = 1.0
				target.take_damage(attack_damage, agent_name)
		State.SEARCH:
			_search_time -= delta
			velocity = facing.rotated(sin(_search_time * 3.0) * 0.9) * 22.0
			if can_see:
				_set_state(State.CHASE)
			elif _search_time <= 0.0:
				_set_state(State.RETURN)
		State.RETURN:
			if patrol_points.is_empty():
				_set_state(State.PATROL)
			else:
				_move_toward(patrol_points[_patrol_index], patrol_speed)
				if global_position.distance_to(patrol_points[_patrol_index]) < 14.0:
					_set_state(State.PATROL)

	move_and_slide()
	queue_redraw()


func _follow_patrol(_delta: float) -> void:
	if patrol_points.is_empty():
		velocity = Vector2.ZERO
		return
	var point := patrol_points[_patrol_index]
	_move_toward(point, patrol_speed)
	if global_position.distance_to(point) < 13.0:
		_patrol_index = (_patrol_index + 1) % patrol_points.size()


func _move_toward(point: Vector2, speed: float) -> void:
	var direction := global_position.direction_to(point)
	if direction.length_squared() > 0.01:
		facing = direction
	velocity = direction * speed


func _can_see_target() -> bool:
	if not is_instance_valid(target):
		return false
	var offset := target.global_position - global_position
	if offset.length() > vision_range:
		return false
	if facing.dot(offset.normalized()) < cos(vision_half_angle):
		return false
	var query := PhysicsRayQueryParameters2D.create(global_position, target.global_position, 1 | 2)
	query.exclude = [get_rid()]
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.get("collider") == target


func receive_shove(origin: Vector2, direction: Vector2) -> bool:
	if state == State.SURRENDERED or global_position.distance_to(origin) > 48.0:
		return false
	resolve -= 36.0
	velocity = direction.normalized() * 215.0
	_flash = 1.0
	if resolve <= 0.0:
		_set_state(State.SURRENDERED)
		collision_layer = 0
		collision_mask = 1
		surrendered.emit(self)
	else:
		_stun_time = 0.72
		_set_state(State.STUNNED)
	queue_redraw()
	return true


func reset_agent() -> void:
	resolve = 100.0
	suspicion = 0.0
	_lost_time = 0.0
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	_patrol_index = 0
	if patrol_points.size() > 0:
		global_position = patrol_points[0]
	_set_state(State.PATROL)
	queue_redraw()


func _set_state(next_state: int) -> void:
	if state == next_state:
		return
	state = next_state
	state_changed.emit(self, state)
	queue_redraw()


func _draw() -> void:
	_draw_ellipse_shape(Vector2(0, 14), Vector2(16, 6), Color(0.02, 0.02, 0.025, 0.34))
	var coat := Color("3b3038") if _flash <= 0.0 else Color("a96d67")
	if state == State.SURRENDERED:
		coat = Color("5c5a59")
	draw_colored_polygon(PackedVector2Array([Vector2(-11, -8), Vector2(10, -8), Vector2(12, 13), Vector2(-10, 13)]), coat)
	draw_circle(Vector2(0, -15), 8.0, Color("b9967c"))
	draw_arc(Vector2(0, -16), 8.0, PI, TAU, 12, Color("171419"), 4.0, true)
	draw_line(Vector2(-9, -3), Vector2(-14, 9), Color("8b784c"), 3.0, true)
	draw_line(Vector2(9, -3), Vector2(15, 9), Color("8b784c"), 3.0, true)
	if state == State.SURRENDERED:
		draw_line(Vector2(-12, -3), Vector2(-20, -15), Color("b9967c"), 3.0, true)
		draw_line(Vector2(12, -3), Vector2(20, -15), Color("b9967c"), 3.0, true)
	else:
		var cone_color := Color(0.86, 0.65, 0.31, 0.055)
		if state in [State.CHASE, State.STRIKE]:
			cone_color = Color(0.94, 0.22, 0.18, 0.12)
		var left := facing.rotated(-vision_half_angle) * minf(vision_range, 135.0)
		var right := facing.rotated(vision_half_angle) * minf(vision_range, 135.0)
		draw_colored_polygon(PackedVector2Array([Vector2.ZERO, left, right]), cone_color)
	if suspicion > 0.05 and state != State.SURRENDERED:
		draw_arc(Vector2(0, -35), 7.0, -PI * 0.5, -PI * 0.5 + TAU * suspicion, 20, Color("e8aa4b") if suspicion < 1.0 else Color("e7533f"), 2.2, true)


func _draw_ellipse_shape(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index in range(24):
		var angle := TAU * float(index) / 24.0
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_colored_polygon(points, color)
