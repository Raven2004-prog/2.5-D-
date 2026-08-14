extends Node3D
class_name AshenWeather3D

## Layered, camera-following storm presentation for the Ashen Diorama world.
## Particle counts change with visual quality, while timing and gameplay remain
## identical.  All materials/textures are generated in memory for portability.

signal lightning_flashed(intensity: float)

const QUALITY_PARTICLES := {
	"low": [3200, 26, 12],
	"medium": [7200, 46, 20],
	"high": [12500, 72, 30],
	"ultra": [18000, 96, 42],
}

var target: Node3D
var quality := "high"
var reduced_motion := false
var reduced_flash := false
var weather_density := 1.0

var _rain: GPUParticles3D
var _mist: GPUParticles3D
var _embers: GPUParticles3D
var _lightning: DirectionalLight3D
var _lightning_timer := 11.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 0xA51E7
	_build_rain()
	_build_mist()
	_build_embers()
	apply_quality(quality)


func _process(delta: float) -> void:
	if is_instance_valid(target):
		var target_position := target.global_position
		global_position.x = target_position.x
		global_position.z = target_position.z
	_lightning_timer -= delta
	if _lightning_timer <= 0.0:
		_lightning_timer = _rng.randf_range(9.0, 19.0)
		_flash_lightning()


func set_target(new_target: Node3D) -> void:
	target = new_target
	if is_instance_valid(target):
		global_position = Vector3(target.global_position.x, 0.0, target.global_position.z)


func set_lightning_light(light: DirectionalLight3D) -> void:
	_lightning = light


func apply_settings(settings: Dictionary) -> void:
	reduced_motion = bool(settings.get("reduce_motion", false))
	reduced_flash = bool(settings.get("reduce_flash", false))
	weather_density = clampf(float(settings.get("weather_density", settings.get("rain_intensity", 1.0))), 0.25, 1.35)
	apply_quality(str(settings.get("visual_quality", "high")))


func apply_quality(value: String) -> void:
	quality = value if QUALITY_PARTICLES.has(value) else "high"
	var counts: Array = QUALITY_PARTICLES[quality]
	if _rain:
		_rain.amount = maxi(800, int(float(counts[0]) * weather_density))
		_rain.visibility_aabb = AABB(Vector3(-22, -1, -17), Vector3(44, 24, 34))
	if _mist:
		_mist.amount = maxi(8, int(float(counts[1]) * weather_density))
		_mist.visible = quality != "low"
	if _embers:
		_embers.amount = int(counts[2])


func set_finale_active(active: bool) -> void:
	if _embers:
		_embers.emitting = active


func set_return_intensity(loop_index: int) -> void:
	var tint := Color("adcfd0").lerp(Color("d8eef0"), clampf(float(loop_index) / 3.0, 0.0, 1.0))
	if _rain and _rain.process_material is ParticleProcessMaterial:
		(_rain.process_material as ParticleProcessMaterial).color = tint


func _build_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.name = "LayeredRain"
	_rain.position = Vector3(0, 16, 0)
	_rain.local_coords = false
	_rain.lifetime = 1.15
	_rain.randomness = 0.32
	_rain.preprocess = 1.4
	_rain.interp_to_end = 0.08
	_rain.fixed_fps = 30
	add_child(_rain)

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(20, 1.2, 15)
	process.direction = Vector3(-0.08, -1.0, 0.03)
	process.spread = 4.0
	process.initial_velocity_min = 25.0
	process.initial_velocity_max = 34.0
	process.gravity = Vector3(-1.8, -12.0, 0.7)
	process.scale_min = 0.72
	process.scale_max = 1.28
	process.color = Color(0.58, 0.76, 0.79, 0.46)
	_rain.process_material = process

	var streak := QuadMesh.new()
	streak.size = Vector2(0.025, 0.92)
	streak.orientation = PlaneMesh.FACE_Z
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_color = Color(0.72, 0.86, 0.88, 0.58)
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = false
	streak.material = material
	_rain.draw_pass_1 = streak


func _build_mist() -> void:
	_mist = GPUParticles3D.new()
	_mist.name = "MarshMist"
	_mist.position = Vector3(0, 0.8, 0)
	_mist.local_coords = false
	_mist.lifetime = 9.0
	_mist.randomness = 0.7
	_mist.preprocess = 9.0
	_mist.fixed_fps = 20
	add_child(_mist)

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(34, 0.6, 28)
	process.direction = Vector3(1, 0.05, 0.2)
	process.spread = 28.0
	process.initial_velocity_min = 0.08
	process.initial_velocity_max = 0.34
	process.gravity = Vector3(0, 0.018, 0)
	process.scale_min = 4.0
	process.scale_max = 9.0
	process.color = Color(0.19, 0.31, 0.33, 0.13)
	_mist.process_material = process

	var mist_quad := QuadMesh.new()
	mist_quad.size = Vector2(1.8, 0.65)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_color = Color(0.42, 0.56, 0.57, 0.16)
	material.vertex_color_use_as_albedo = true
	material.albedo_texture = _soft_particle_texture()
	mist_quad.material = material
	_mist.draw_pass_1 = mist_quad


func _build_embers() -> void:
	_embers = GPUParticles3D.new()
	_embers.name = "FinaleEmbers"
	_embers.position = Vector3(34, 1.0, 18)
	_embers.local_coords = false
	_embers.lifetime = 3.6
	_embers.randomness = 0.55
	_embers.emitting = false
	add_child(_embers)

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(10, 1, 8)
	process.direction = Vector3(0.12, 1, -0.05)
	process.spread = 32.0
	process.initial_velocity_min = 0.5
	process.initial_velocity_max = 1.8
	process.gravity = Vector3(0.15, 0.22, 0)
	process.scale_min = 0.04
	process.scale_max = 0.11
	process.color = Color(1.0, 0.36, 0.08, 0.85)
	_embers.process_material = process

	var ember := QuadMesh.new()
	ember.size = Vector2(0.08, 0.08)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.albedo_color = Color(1.0, 0.25, 0.035, 0.9)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.16, 0.02)
	material.emission_energy_multiplier = 2.4
	ember.material = material
	_embers.draw_pass_1 = ember


func _flash_lightning() -> void:
	var intensity := 0.48 if reduced_flash else _rng.randf_range(1.4, 2.4)
	lightning_flashed.emit(intensity)
	if not is_instance_valid(_lightning):
		return
	var baseline := _lightning.light_energy
	var tween := create_tween()
	_lightning.light_energy = baseline + intensity
	tween.tween_property(_lightning, "light_energy", baseline, 0.09 if reduced_flash else 0.18)
	if not reduced_flash:
		tween.tween_interval(0.06)
		tween.tween_property(_lightning, "light_energy", baseline + intensity * 0.55, 0.025)
		tween.tween_property(_lightning, "light_energy", baseline, 0.13)


func _soft_particle_texture() -> Texture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 0))
	gradient.add_point(0.38, Color(1, 1, 1, 0.62))
	gradient.add_point(0.62, Color(1, 1, 1, 0.62))
	gradient.set_color(gradient.get_point_count() - 1, Color(1, 1, 1, 0))
	var texture := GradientTexture2D.new()
	texture.width = 96
	texture.height = 48
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture
