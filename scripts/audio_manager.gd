extends Node
## Small, dependency-free procedural sound palette.
##
## UI tones and a restrained fen ambience are synthesized into AudioStreamWAV
## resources at startup. Nothing is loaded from external audio files.

const MIX_RATE := 22050

var master_enabled := true
var ui_volume := 0.72
var ambience_volume := 0.28

var _ui_player: AudioStreamPlayer
var _ambience_player: AudioStreamPlayer
var _ui_streams: Dictionary = {}
var _ambience_stream: AudioStreamWAV


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_players()
	_build_streams()


func play_ui(cue: StringName = &"confirm", pitch_offset: float = 0.0) -> void:
	if not master_enabled or _ui_player == null:
		return
	var stream: AudioStreamWAV = _ui_streams.get(cue)
	if stream == null:
		stream = _ui_streams.get(&"focus")
	if stream == null:
		return
	_ui_player.stream = stream
	_ui_player.pitch_scale = clampf(1.0 + pitch_offset, 0.75, 1.25)
	_ui_player.volume_db = _linear_to_safe_db(ui_volume)
	_ui_player.play()


func start_ambience(restart: bool = false) -> void:
	if not master_enabled or _ambience_player == null or _ambience_stream == null:
		return
	if _ambience_player.playing and not restart:
		return
	_ambience_player.stream = _ambience_stream
	_ambience_player.volume_db = _linear_to_safe_db(ambience_volume)
	_ambience_player.play()


func stop_ambience() -> void:
	if _ambience_player != null:
		_ambience_player.stop()


func set_master_enabled(enabled: bool) -> void:
	master_enabled = enabled
	if not enabled:
		if _ui_player != null:
			_ui_player.stop()
		stop_ambience()
	else:
		start_ambience()


func set_ui_volume(linear_volume: float) -> void:
	ui_volume = clampf(linear_volume, 0.0, 1.0)
	if _ui_player != null:
		_ui_player.volume_db = _linear_to_safe_db(ui_volume)


func set_ambience_volume(linear_volume: float) -> void:
	ambience_volume = clampf(linear_volume, 0.0, 1.0)
	if _ambience_player != null:
		_ambience_player.volume_db = _linear_to_safe_db(ambience_volume)


func has_cue(cue: StringName) -> bool:
	return _ui_streams.has(cue)


func get_ui_cue_names() -> Array[StringName]:
	var names: Array[StringName] = []
	for cue: StringName in _ui_streams.keys():
		names.append(cue)
	names.sort()
	return names


func _build_players() -> void:
	_ui_player = AudioStreamPlayer.new()
	_ui_player.name = "ProceduralUI"
	_ui_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_ui_player)

	_ambience_player = AudioStreamPlayer.new()
	_ambience_player.name = "ProceduralAmbience"
	_ambience_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_ambience_player)


func _build_streams() -> void:
	_ui_streams = {
		&"focus": _make_tone(520.0, 0.070, 0.16, 0.18),
		&"confirm": _make_tone(690.0, 0.125, 0.20, 0.25),
		&"cancel": _make_tone(310.0, 0.150, 0.18, 0.12),
		&"warning": _make_tone(185.0, 0.230, 0.22, 0.34),
	}
	_ambience_stream = _make_fen_ambience(4.0)


func _make_tone(
		frequency: float,
		duration_seconds: float,
		amplitude: float,
		overtone_mix: float
	) -> AudioStreamWAV:
	var sample_count := maxi(int(MIX_RATE * duration_seconds), 8)
	var samples := PackedFloat32Array()
	samples.resize(sample_count)
	for index in range(sample_count):
		var time := float(index) / MIX_RATE
		var attack := clampf(time / 0.008, 0.0, 1.0)
		var release := clampf((duration_seconds - time) / 0.045, 0.0, 1.0)
		var envelope := minf(attack, release)
		var phase := TAU * frequency * time
		var body := sin(phase) + sin(phase * 2.01) * overtone_mix
		samples[index] = body * amplitude * envelope / (1.0 + overtone_mix)
	return _samples_to_wav(samples, false)


func _make_fen_ambience(duration_seconds: float) -> AudioStreamWAV:
	var sample_count := maxi(int(MIX_RATE * duration_seconds), 8)
	var samples := PackedFloat32Array()
	samples.resize(sample_count)
	var random := RandomNumberGenerator.new()
	random.seed = 0x4752455946454E
	var filtered_noise := 0.0
	for index in range(sample_count):
		var time := float(index) / MIX_RATE
		var loop_phase := time / duration_seconds
		filtered_noise = lerpf(filtered_noise, random.randf_range(-1.0, 1.0), 0.012)
		var loop_envelope := pow(sin(PI * loop_phase), 2.0)
		var low_air := sin(TAU * 43.0 * time) * 0.038
		var distant_hum := sin(TAU * 71.5 * time + sin(TAU * 0.25 * time) * 0.8) * 0.020
		var fen_noise := filtered_noise * 0.026 * loop_envelope
		samples[index] = (low_air + distant_hum + fen_noise) * 0.74
	return _samples_to_wav(samples, true)


func _samples_to_wav(samples: PackedFloat32Array, looped: bool) -> AudioStreamWAV:
	var pcm := PackedByteArray()
	pcm.resize(samples.size() * 2)
	for index in range(samples.size()):
		var signed_sample := clampi(int(round(samples[index] * 32767.0)), -32768, 32767)
		var unsigned_sample := signed_sample if signed_sample >= 0 else signed_sample + 65536
		pcm[index * 2] = unsigned_sample & 0xff
		pcm[index * 2 + 1] = (unsigned_sample >> 8) & 0xff

	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.data = pcm
	if looped:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	return stream


func _linear_to_safe_db(value: float) -> float:
	return -80.0 if value <= 0.0001 else linear_to_db(value)
