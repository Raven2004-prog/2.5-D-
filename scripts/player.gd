extends CharacterBody2D
class_name PlayerActor

signal health_changed(value: float, maximum: float)
signal stamina_changed(value: float, maximum: float)
signal interact_requested
signal focus_changed(active: bool)
signal defeated(cause: String)
signal shove_emitted(origin: Vector2, direction: Vector2)

const WALK_SPEED := 150.0
const SPRINT_SPEED := 226.0
const DODGE_SPEED := 370.0
const MAX_HEALTH := 100.0
const MAX_STAMINA := 100.0

var controls_enabled := true
var health := MAX_HEALTH
var stamina := MAX_STAMINA
var facing := Vector2.DOWN
var focus_active := false
var noise_level := 34.0

var _dodge_time := 0.0
var _dodge_cooldown := 0.0
var _shove_cooldown := 0.0
var _hurt_flash := 0.0
var _shove_flash := 0.0
var _invulnerable_time := 0.0
var _step_phase := 0.0


func _ready() -> void:
	collision_layer = 2
	collision_mask = 1 | 4
	if not get_node_or_null("CollisionShape2D"):
		var collision := CollisionShape2D.new()
		var shape := CapsuleShape2D.new()
		shape.radius = 11.0
		shape.height = 30.0
		collision.shape = shape
		collision.position = Vector2(0.0, 5.0)
		collision.name = "CollisionShape2D"
		add_child(collision)
	queue_redraw()


func _physics_process(delta: float) -> void:
	_dodge_time = maxf(0.0, _dodge_time - delta)
	_dodge_cooldown = maxf(0.0, _dodge_cooldown - delta)
	_shove_cooldown = maxf(0.0, _shove_cooldown - delta)
	_invulnerable_time = maxf(0.0, _invulnerable_time - delta)
	_hurt_flash = maxf(0.0, _hurt_flash - delta * 4.0)
	_shove_flash = maxf(0.0, _shove_flash - delta * 5.0)

	if not controls_enabled:
		velocity = velocity.move_toward(Vector2.ZERO, 850.0 * delta)
		move_and_slide()
		queue_redraw()
		return

	if Input.is_action_just_pressed("interact"):
		interact_requested.emit()
	if Input.is_action_just_pressed("focus"):
		focus_active = not focus_active
		focus_changed.emit(focus_active)
		queue_redraw()
	if Input.is_action_just_pressed("shove"):
		_try_shove()

	var input_vector := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_vector.length_squared() > 0.01:
		facing = input_vector.normalized()

	if Input.is_action_just_pressed("dodge") and _dodge_cooldown <= 0.0 and stamina >= 24.0:
		_dodge_time = 0.19
		_dodge_cooldown = 0.62
		_invulnerable_time = 0.27
		stamina -= 24.0
		stamina_changed.emit(stamina, MAX_STAMINA)

	if _dodge_time > 0.0:
		velocity = facing * DODGE_SPEED
		noise_level = 205.0
	else:
		var sprinting := Input.is_action_pressed("sprint") and input_vector.length_squared() > 0.01 and stamina > 1.0
		var speed := SPRINT_SPEED if sprinting else WALK_SPEED
		velocity = input_vector * speed
		if sprinting:
			stamina = maxf(0.0, stamina - 27.0 * delta)
			noise_level = 176.0
		else:
			stamina = minf(MAX_STAMINA, stamina + 20.0 * delta)
			noise_level = 78.0 if input_vector.length_squared() > 0.01 else 26.0
		stamina_changed.emit(stamina, MAX_STAMINA)

	move_and_slide()
	if velocity.length_squared() > 25.0:
		_step_phase += delta * velocity.length() * 0.045
	queue_redraw()


func _try_shove() -> void:
	if _shove_cooldown > 0.0 or stamina < 14.0:
		return
	_shove_cooldown = 0.48
	_shove_flash = 1.0
	stamina = maxf(0.0, stamina - 14.0)
	stamina_changed.emit(stamina, MAX_STAMINA)
	shove_emitted.emit(global_position, facing)
	queue_redraw()


func take_damage(amount: float, source_name: String = "an agent") -> void:
	if _invulnerable_time > 0.0 or health <= 0.0:
		return
	health = maxf(0.0, health - amount)
	_hurt_flash = 1.0
	_invulnerable_time = 0.48
	health_changed.emit(health, MAX_HEALTH)
	queue_redraw()
	if health <= 0.0:
		controls_enabled = false
		defeated.emit("Cornered by %s" % source_name)


func heal(amount: float) -> void:
	health = minf(MAX_HEALTH, health + amount)
	health_changed.emit(health, MAX_HEALTH)
	queue_redraw()


func reset_body(at_position: Vector2, scar_count: int = 0) -> void:
	global_position = at_position
	velocity = Vector2.ZERO
	controls_enabled = true
	var scar_penalty := minf(24.0, float(scar_count) * 4.0)
	health = MAX_HEALTH - scar_penalty
	stamina = MAX_STAMINA
	_dodge_time = 0.0
	_invulnerable_time = 1.0
	focus_active = false
	health_changed.emit(health, MAX_HEALTH)
	stamina_changed.emit(stamina, MAX_STAMINA)
	focus_changed.emit(false)
	queue_redraw()


func get_noise_radius() -> float:
	return noise_level


func _draw() -> void:
	var bob := sin(_step_phase) * 1.4 if velocity.length_squared() > 25.0 else 0.0
	var shadow_alpha := 0.28 if _dodge_time <= 0.0 else 0.14
	draw_set_transform(Vector2(0.0, bob))
	_draw_ellipse_shape(Vector2(0.0, 16.0), Vector2(17.0, 7.0), Color(0.02, 0.03, 0.035, shadow_alpha))

	var body_color := Color("d9e1df") if _hurt_flash <= 0.0 else Color("ffd4c8")
	var shirt := Color("23394b")
	var trousers := Color("646b70")
	var skin := Color("d4b69b")
	var hair := Color("14181c")
	var side := Vector2(-facing.y, facing.x)
	var stride := sin(_step_phase) * 3.0
	draw_line(Vector2(-4.0, 8.0) + side * stride, Vector2(-5.0, 17.0), trousers, 5.0, true)
	draw_line(Vector2(4.0, 8.0) - side * stride, Vector2(5.0, 17.0), trousers, 5.0, true)
	draw_colored_polygon(PackedVector2Array([Vector2(-10, -7), Vector2(9, -7), Vector2(11, 9), Vector2(-9, 9)]), shirt)
	draw_line(Vector2(-8, -2), Vector2(-14, 7) + side * 2.0, skin, 4.0, true)
	draw_line(Vector2(8, -2), Vector2(14, 6) - side * 2.0, skin, 4.0, true)
	draw_circle(Vector2(0, -14), 8.5, skin)
	draw_arc(Vector2(0, -16), 8.2, PI, TAU, 12, hair, 5.0, true)
	draw_circle(Vector2(3, -13) + facing * 2.0, 1.0, body_color)

	# The ordinary cracked phone is the only blue-white light on Evan.
	draw_circle(Vector2(13, 5), 4.0, Color(0.35, 0.75, 0.92, 0.14))
	draw_rect(Rect2(Vector2(11.2, 2.0), Vector2(3.6, 6.2)), Color("91d3e8"), true)
	if focus_active:
		draw_arc(Vector2.ZERO, 24.0, 0.0, TAU, 40, Color(0.42, 0.83, 0.84, 0.72), 1.4, true)
		draw_arc(Vector2.ZERO, 29.0, -PI * 0.2, PI * 0.55, 18, Color(0.91, 0.68, 0.29, 0.46), 1.0, true)
	if _shove_flash > 0.0:
		var start := facing.angle() - 0.65
		var end := facing.angle() + 0.65
		draw_arc(facing * 18.0, 27.0 + (1.0 - _shove_flash) * 8.0, start, end, 18, Color(0.94, 0.73, 0.38, _shove_flash), 3.0, true)


func _draw_ellipse_shape(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for index in range(24):
		var angle := TAU * float(index) / 24.0
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_colored_polygon(points, color)
