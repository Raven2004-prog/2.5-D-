extends Node3D
class_name AshenSoundscape3D

## Original, deterministic soundscape for the Ashen Diorama world.
##
## Every sound is synthesized into an AudioStreamWAV at runtime.  The ambience
## loops are phase-periodic (rather than cross-faded samples), so there is no
## asset import step and no audible seam.  This node deliberately does not use
## AudioManager: it can be mounted beside the legacy story adapter without
## changing the existing mix or save contract.

signal one_shot_triggered(cue_id: StringName, intensity: float)
signal lightning_thunder_scheduled(delay_seconds: float, safe_intensity: float)
signal landmark_emitter_added(landmark_id: StringName)

const MIX_RATE := 22050
const PCM_MAX := 32767.0
const LOOP_IDS: Array[StringName] = [&"rain", &"fen_wind", &"ward_hum"]
const ONE_SHOT_IDS: Array[StringName] = [&"thunder", &"return", &"finale"]
const QUALITY_PROFILES := {
	"low": {"rain": 0.48, "wind": 0.16, "ward": 0.28, "emitters": 4, "range": 19.0},
	"medium": {"rain": 0.56, "wind": 0.22, "ward": 0.34, "emitters": 8, "range": 24.0},
	"high": {"rain": 0.63, "wind": 0.28, "ward": 0.40, "emitters": 12, "range": 30.0},
	"ultra": {"rain": 0.68, "wind": 0.32, "ward": 0.44, "emitters": 20, "range": 36.0},
}
const NORMAL_LIGHTNING_INTERVAL := 7.5
const GENTLE_LIGHTNING_INTERVAL := 12.0
const NORMAL_THUNDER_PEAK := 0.82
const GENTLE_THUNDER_PEAK := 0.52

var target: Node3D
var quality := "high"
var master_enabled := true
var master_gain := 1.0
var weather_density := 1.0
var reduced_stimulation := false

var _loop_streams: Dictionary = {}
var _one_shot_streams: Dictionary = {}
var _rain_player: AudioStreamPlayer
var _wind_player: AudioStreamPlayer
var _ward_bed_player: AudioStreamPlayer
var _one_shot_player: AudioStreamPlayer
var _landmark_emitters: Dictionary = {}
var _weather_source: Node
var _lightning_rng := RandomNumberGenerator.new()
var _lightning_cooldown_remaining := 0.0
var _pending_thunder_delay := -1.0
var _pending_thunder_intensity := 0.0
var _started := false


func _ready() -> void:
	_lightning_rng.seed = 0x415348454E534F55
	_build_stream_library()
	_build_players()
	apply_quality(quality)
	_started = true
	_sync_loop_playback()


func _process(delta: float) -> void:
	var safe_delta := maxf(delta, 0.0)
	_lightning_cooldown_remaining = maxf(0.0, _lightning_cooldown_remaining - safe_delta)
	if _pending_thunder_delay < 0.0:
		return
	_pending_thunder_delay -= safe_delta
	if _pending_thunder_delay <= 0.0:
		var intensity := _pending_thunder_intensity
		_pending_thunder_delay = -1.0
		_pending_thunder_intensity = 0.0
		_play_one_shot(&"thunder", intensity)


func _exit_tree() -> void:
	unbind_weather_source()
	stop()
	_landmark_emitters.clear()
	_loop_streams.clear()
	_one_shot_streams.clear()
	_pending_thunder_delay = -1.0
	_pending_thunder_intensity = 0.0
	_started = false


func set_target(new_target: Node3D) -> void:
	target = new_target


func get_target() -> Node3D:
	return target


func apply_settings(settings: Dictionary) -> void:
	var requested_master := settings.get("master_audio", settings.get("audio_enabled", true))
	var requested_gain := settings.get("master_volume", settings.get("audio_volume", 1.0))
	weather_density = clampf(float(settings.get("weather_density", settings.get("rain_intensity", 1.0))), 0.0, 1.35)
	reduced_stimulation = bool(settings.get("reduce_flash", settings.get("reduced_stimulation", false)))
	set_master_gain(float(requested_gain))
	apply_quality(str(settings.get("visual_quality", settings.get("quality", quality))))
	set_master_enabled(bool(requested_master))


func apply_quality(value: String) -> bool:
	if not QUALITY_PROFILES.has(value):
		return false
	quality = value
	_apply_mix_profile()
	_sync_loop_playback()
	return true


func set_master_enabled(enabled: bool) -> void:
	master_enabled = enabled
	if not master_enabled:
		_pending_thunder_delay = -1.0
		_pending_thunder_intensity = 0.0
	_sync_loop_playback()
	if not master_enabled and is_instance_valid(_one_shot_player):
		_one_shot_player.stop()


func set_master_gain(value: float) -> void:
	master_gain = clampf(value, 0.0, 1.0)
	_apply_mix_profile()
	_sync_loop_playback()


func set_weather_density(value: float) -> void:
	weather_density = clampf(value, 0.0, 1.35)
	_apply_mix_profile()
	_sync_loop_playback()


func set_reduced_stimulation(enabled: bool) -> void:
	reduced_stimulation = enabled


func start() -> void:
	set_master_enabled(true)


func stop() -> void:
	for player: AudioStreamPlayer in [_rain_player, _wind_player, _ward_bed_player, _one_shot_player]:
		if is_instance_valid(player):
			player.stop()
	for raw_emitter: Variant in _landmark_emitters.values():
		var emitter := raw_emitter as AudioStreamPlayer3D
		if is_instance_valid(emitter):
			emitter.stop()


func bind_weather_source(source: Node) -> bool:
	unbind_weather_source()
	if not is_instance_valid(source) or not source.has_signal("lightning_flashed"):
		return false
	_weather_source = source
	var callback := Callable(self, "_on_weather_lightning_flashed")
	if not _weather_source.is_connected("lightning_flashed", callback):
		_weather_source.connect("lightning_flashed", callback)
	return true


func unbind_weather_source() -> void:
	if is_instance_valid(_weather_source):
		var callback := Callable(self, "_on_weather_lightning_flashed")
		if _weather_source.is_connected("lightning_flashed", callback):
			_weather_source.disconnect("lightning_flashed", callback)
	_weather_source = null


func request_lightning(intensity: float = 1.0, distance_metres: float = 135.0) -> bool:
	if not master_enabled or master_gain <= 0.0:
		return false
	if _pending_thunder_delay >= 0.0 or _lightning_cooldown_remaining > 0.0:
		return false
	var peak := GENTLE_THUNDER_PEAK if reduced_stimulation else NORMAL_THUNDER_PEAK
	var safe_intensity := clampf(intensity, 0.18, peak)
	var travel_time := clampf(maxf(distance_metres, 18.0) / 343.0, 0.08, 3.2)
	var deterministic_air_delay := _lightning_rng.randf_range(0.055, 0.19)
	_pending_thunder_delay = clampf(travel_time + deterministic_air_delay, 0.18, 3.35)
	_pending_thunder_intensity = safe_intensity
	_lightning_cooldown_remaining = get_lightning_min_interval()
	lightning_thunder_scheduled.emit(_pending_thunder_delay, safe_intensity)
	return true


func get_lightning_min_interval() -> float:
	return GENTLE_LIGHTNING_INTERVAL if reduced_stimulation else NORMAL_LIGHTNING_INTERVAL


func get_pending_thunder_delay() -> float:
	return _pending_thunder_delay


func get_lightning_cooldown_remaining() -> float:
	return _lightning_cooldown_remaining


func play_cue(cue_id: StringName, intensity: float = 1.0) -> bool:
	if not ONE_SHOT_IDS.has(cue_id):
		return false
	if cue_id == &"thunder":
		return request_lightning(intensity)
	return _play_one_shot(cue_id, intensity)


func play_return_cue(intensity: float = 1.0) -> bool:
	return _play_one_shot(&"return", intensity)


func play_finale_cue(intensity: float = 1.0) -> bool:
	return _play_one_shot(&"finale", intensity)


func register_ward_landmark(landmark_id: StringName, world_position: Vector3) -> AudioStreamPlayer3D:
	if landmark_id == &"":
		return null
	if _landmark_emitters.has(landmark_id):
		var existing := _landmark_emitters[landmark_id] as AudioStreamPlayer3D
		if is_instance_valid(existing):
			existing.global_position = world_position
			return existing
	var profile: Dictionary = QUALITY_PROFILES[quality]
	if _landmark_emitters.size() >= int(profile["emitters"]):
		return null
	var emitter := AudioStreamPlayer3D.new()
	emitter.name = "Ward_%s" % str(landmark_id).validate_node_name()
	emitter.stream = get_loop_stream(&"ward_hum")
	emitter.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
	emitter.unit_size = 3.8
	emitter.max_distance = float(profile["range"])
	emitter.panning_strength = 0.72
	add_child(emitter)
	emitter.global_position = world_position
	_landmark_emitters[landmark_id] = emitter
	_apply_emitter_mix(emitter)
	if master_enabled and master_gain > 0.0:
		emitter.play()
	landmark_emitter_added.emit(landmark_id)
	return emitter


func remove_landmark_emitter(landmark_id: StringName) -> bool:
	if not _landmark_emitters.has(landmark_id):
		return false
	var emitter := _landmark_emitters[landmark_id] as AudioStreamPlayer3D
	_landmark_emitters.erase(landmark_id)
	if is_instance_valid(emitter):
		emitter.stop()
		emitter.queue_free()
	return true


func get_landmark_emitter(landmark_id: StringName) -> AudioStreamPlayer3D:
	return _landmark_emitters.get(landmark_id) as AudioStreamPlayer3D


func get_landmark_emitter_count() -> int:
	return _landmark_emitters.size()


func get_max_landmark_emitters() -> int:
	var profile: Dictionary = QUALITY_PROFILES[quality]
	return int(profile["emitters"])


func get_loop_stream(cue_id: StringName) -> AudioStreamWAV:
	return _loop_streams.get(cue_id) as AudioStreamWAV


func get_one_shot_stream(cue_id: StringName) -> AudioStreamWAV:
	return _one_shot_streams.get(cue_id) as AudioStreamWAV


func get_loop_ids() -> Array[StringName]:
	return LOOP_IDS.duplicate()


func get_one_shot_ids() -> Array[StringName]:
	return ONE_SHOT_IDS.duplicate()


func get_layer_player(cue_id: StringName) -> AudioStreamPlayer:
	match cue_id:
		&"rain":
			return _rain_player
		&"fen_wind":
			return _wind_player
		&"ward_hum":
			return _ward_bed_player
	return null


func _on_weather_lightning_flashed(intensity: float) -> void:
	# Visual lightning is immediate; this delay models sound travel and avoids
	# synchronized flash/bang spikes.  Reduced-stimulation mode additionally
	# caps the peak and lengthens the minimum interval.
	request_lightning(intensity, 112.0)


func _build_stream_library() -> void:
	if not _loop_streams.is_empty():
		return
	_loop_streams[&"rain"] = _samples_to_wav(_synthesize_rain_loop(), true)
	_loop_streams[&"fen_wind"] = _samples_to_wav(_synthesize_fen_wind_loop(), true)
	_loop_streams[&"ward_hum"] = _samples_to_wav(_synthesize_ward_hum_loop(), true)
	_one_shot_streams[&"thunder"] = _samples_to_wav(_synthesize_thunder(), false)
	_one_shot_streams[&"return"] = _samples_to_wav(_synthesize_return_cue(), false)
	_one_shot_streams[&"finale"] = _samples_to_wav(_synthesize_finale_cue(), false)


func _build_players() -> void:
	_rain_player = _make_bed_player("RainBed", get_loop_stream(&"rain"))
	_wind_player = _make_bed_player("FenWindBed", get_loop_stream(&"fen_wind"))
	_ward_bed_player = _make_bed_player("WardResonanceBed", get_loop_stream(&"ward_hum"))
	_one_shot_player = AudioStreamPlayer.new()
	_one_shot_player.name = "StoryAndStormCues"
	_one_shot_player.max_polyphony = 4
	add_child(_one_shot_player)


func _make_bed_player(player_name: String, stream: AudioStreamWAV) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.stream = stream
	add_child(player)
	return player


func _apply_mix_profile() -> void:
	if not QUALITY_PROFILES.has(quality):
		return
	var profile: Dictionary = QUALITY_PROFILES[quality]
	if is_instance_valid(_rain_player):
		_rain_player.volume_db = _linear_to_safe_db(float(profile["rain"]) * weather_density * master_gain)
	if is_instance_valid(_wind_player):
		_wind_player.volume_db = _linear_to_safe_db(float(profile["wind"]) * lerpf(0.45, 1.0, minf(weather_density, 1.0)) * master_gain)
	if is_instance_valid(_ward_bed_player):
		_ward_bed_player.volume_db = _linear_to_safe_db(float(profile["ward"]) * 0.30 * master_gain)
	for raw_emitter: Variant in _landmark_emitters.values():
		var emitter := raw_emitter as AudioStreamPlayer3D
		if is_instance_valid(emitter):
			emitter.max_distance = float(profile["range"])
			_apply_emitter_mix(emitter)


func _apply_emitter_mix(emitter: AudioStreamPlayer3D) -> void:
	var profile: Dictionary = QUALITY_PROFILES[quality]
	emitter.volume_db = _linear_to_safe_db(float(profile["ward"]) * master_gain)


func _sync_loop_playback() -> void:
	if not _started:
		return
	var beds_enabled := master_enabled and master_gain > 0.0
	_set_player_active(_rain_player, beds_enabled and weather_density > 0.01)
	_set_player_active(_wind_player, beds_enabled and weather_density > 0.01)
	_set_player_active(_ward_bed_player, beds_enabled)
	for raw_emitter: Variant in _landmark_emitters.values():
		var emitter := raw_emitter as AudioStreamPlayer3D
		if not is_instance_valid(emitter):
			continue
		if beds_enabled and not emitter.playing:
			emitter.play()
		elif not beds_enabled and emitter.playing:
			emitter.stop()


func _set_player_active(player: AudioStreamPlayer, active: bool) -> void:
	if not is_instance_valid(player):
		return
	if active and not player.playing:
		player.play()
	elif not active and player.playing:
		player.stop()


func _play_one_shot(cue_id: StringName, intensity: float) -> bool:
	if not master_enabled or master_gain <= 0.0 or not is_instance_valid(_one_shot_player):
		return false
	var stream := get_one_shot_stream(cue_id)
	if stream == null:
		return false
	var safe_peak := GENTLE_THUNDER_PEAK if reduced_stimulation and cue_id == &"thunder" else 0.88
	var safe_intensity := clampf(intensity, 0.0, safe_peak)
	_one_shot_player.stream = stream
	_one_shot_player.volume_db = _linear_to_safe_db(maxf(safe_intensity * master_gain, 0.001))
	_one_shot_player.play()
	one_shot_triggered.emit(cue_id, safe_intensity)
	return true


func _samples_to_wav(samples: PackedFloat32Array, looped: bool) -> AudioStreamWAV:
	var pcm := PackedByteArray()
	pcm.resize(samples.size() * 2)
	for index in samples.size():
		var value := int(round(clampf(samples[index], -1.0, 1.0) * PCM_MAX))
		if value < 0:
			value += 65536
		pcm[index * 2] = value & 0xFF
		pcm[index * 2 + 1] = (value >> 8) & 0xFF
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = pcm
	if looped:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	else:
		stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return stream


func _synthesize_rain_loop() -> PackedFloat32Array:
	var duration := 4.0
	var count := int(duration * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5241494E415348
	var cycles := PackedInt32Array()
	var phases := PackedFloat32Array()
	var amplitudes := PackedFloat32Array()
	for harmonic in 28:
		cycles.append(31 + harmonic * 7 + rng.randi_range(0, 5))
		phases.append(rng.randf_range(0.0, TAU))
		amplitudes.append(rng.randf_range(0.35, 1.0) / sqrt(float(harmonic + 2)))
	var drops: Array[Vector3] = []
	for drop_index in 18:
		drops.append(Vector3(rng.randf(), rng.randf_range(0.35, 0.9), rng.randf_range(520.0, 1280.0)))
	for index in count:
		var phase := float(index) / float(count)
		var wash := 0.0
		for harmonic in cycles.size():
			wash += sin(TAU * float(cycles[harmonic]) * phase + phases[harmonic]) * amplitudes[harmonic]
		wash *= 0.095
		var roof_body := sin(TAU * 13.0 * phase + 0.8) * 0.055 + sin(TAU * 23.0 * phase + 2.1) * 0.035
		var droplets := 0.0
		for drop: Vector3 in drops:
			var distance := absf(phase - drop.x)
			distance = minf(distance, 1.0 - distance)
			if distance < 0.011:
				var seconds := distance * duration
				droplets += sin(TAU * drop.z * seconds) * exp(-seconds * 155.0) * drop.y
		samples[index] = clampf((wash + roof_body + droplets * 0.13) * 0.72, -0.78, 0.78)
	return samples


func _synthesize_fen_wind_loop() -> PackedFloat32Array:
	var duration := 6.0
	var count := int(duration * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x46454E57494E44
	var phases := PackedFloat32Array()
	for phase_index in 14:
		phases.append(rng.randf_range(0.0, TAU))
	for index in count:
		var phase := float(index) / float(count)
		var slow_breath := 0.42 + 0.22 * sin(TAU * 2.0 * phase + 0.3) + 0.12 * sin(TAU * 5.0 * phase + 2.0)
		var air := 0.0
		for harmonic in 14:
			var cycles := 7 + harmonic * 3
			air += sin(TAU * float(cycles) * phase + phases[harmonic]) / float(harmonic + 2)
		var reed_whistle := sin(TAU * 71.0 * phase + 1.2 + sin(TAU * 3.0 * phase) * 0.8)
		var fen_drone := sin(TAU * 3.0 * phase + 2.4) + 0.55 * sin(TAU * 4.0 * phase + 0.7)
		samples[index] = clampf((air * slow_breath * 0.22 + reed_whistle * 0.025 + fen_drone * 0.045) * 0.76, -0.64, 0.64)
	return samples


func _synthesize_ward_hum_loop() -> PackedFloat32Array:
	var duration := 4.0
	var count := int(duration * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	# All frequencies are integer cycles across four seconds, preserving phase
	# at the loop boundary while suggesting a weathered, glassy ward resonance.
	for index in count:
		var phase := float(index) / float(count)
		var pulse := 0.78 + 0.16 * sin(TAU * 2.0 * phase + 0.4)
		var root := sin(TAU * 176.0 * phase + 0.2)
		var fifth := sin(TAU * 264.0 * phase + 1.1)
		var glass := sin(TAU * 421.0 * phase + sin(TAU * 3.0 * phase) * 0.35)
		var sub := sin(TAU * 88.0 * phase + 2.2)
		samples[index] = (root * 0.18 + fifth * 0.10 + glass * 0.045 + sub * 0.08) * pulse
	return samples


func _synthesize_thunder() -> PackedFloat32Array:
	var duration := 3.8
	var count := int(duration * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5448554E444552
	var filtered_noise := 0.0
	for index in count:
		var time := float(index) / float(MIX_RATE)
		var attack := clampf(time / 0.045, 0.0, 1.0)
		var decay := exp(-time * 0.83)
		var raw_noise := rng.randf_range(-1.0, 1.0)
		filtered_noise = lerpf(filtered_noise, raw_noise, 0.035 + 0.055 * exp(-time * 2.0))
		var rumble := sin(TAU * (42.0 * time - 1.4 * time * time)) * 0.34
		rumble += sin(TAU * (61.0 * time - 2.2 * time * time) + 0.8) * 0.19
		var crack := raw_noise * exp(-time * 10.0) * 0.20
		var tail_swell := 0.70 + 0.30 * sin(TAU * 0.78 * time + 1.1)
		samples[index] = clampf((filtered_noise * 1.55 + rumble + crack) * attack * decay * tail_swell, -0.88, 0.88)
	return samples


func _synthesize_return_cue() -> PackedFloat32Array:
	var duration := 2.4
	var count := int(duration * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x52455455524E
	var shimmer := 0.0
	for index in count:
		var time := float(index) / float(MIX_RATE)
		var t := time / duration
		var envelope := pow(sin(PI * clampf(t, 0.0, 1.0)), 0.55)
		var pitch := 118.0 + 92.0 * t + 24.0 * sin(PI * t)
		var tone := sin(TAU * pitch * time + 1.8 * t * t)
		tone += sin(TAU * pitch * 1.498 * time + 0.7) * 0.48
		var raw := rng.randf_range(-1.0, 1.0)
		shimmer = lerpf(shimmer, raw, 0.14)
		var backwards_breath := shimmer * pow(t, 2.2) * 0.28
		samples[index] = clampf((tone * 0.28 + backwards_breath) * envelope, -0.72, 0.72)
	return samples


func _synthesize_finale_cue() -> PackedFloat32Array:
	var duration := 2.8
	var count := int(duration * MIX_RATE)
	var samples := PackedFloat32Array()
	samples.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x46494E414C45
	var low_noise := 0.0
	for index in count:
		var time := float(index) / float(MIX_RATE)
		var t := time / duration
		var attack := clampf(time / 0.11, 0.0, 1.0)
		var release := pow(maxf(1.0 - t, 0.0), 0.72)
		var chord := sin(TAU * 82.0 * time) * 0.26
		chord += sin(TAU * 123.0 * time + 0.35) * 0.18
		chord += sin(TAU * 164.0 * time + 1.1) * 0.13
		chord += sin(TAU * 246.0 * time + 0.5) * 0.07
		var raw := rng.randf_range(-1.0, 1.0)
		low_noise = lerpf(low_noise, raw, 0.022)
		var impact := (low_noise * 0.42 + sin(TAU * 49.0 * time) * 0.18) * exp(-time * 2.3)
		var ember := sin(TAU * (380.0 + 110.0 * t) * time) * 0.035 * sin(PI * t)
		samples[index] = clampf((chord + impact + ember) * attack * release, -0.82, 0.82)
	return samples


func _linear_to_safe_db(value: float) -> float:
	if value <= 0.0001:
		return -80.0
	return clampf(linear_to_db(value), -80.0, -0.5)
