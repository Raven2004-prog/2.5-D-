extends SceneTree
## Headless contract for the original procedural 3D soundscape. Run with:
## Godot --headless --path <project> --script res://tests/test_ashen_soundscape.gd

const SoundscapeScript := preload("res://scripts/ashen_3d/soundscape_3d.gd")

var _failures := 0
var _primary: AshenSoundscape3D
var _mirror: AshenSoundscape3D
var _target: Node3D
var _weather_probe: Node


func _initialize() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	print("[ashen-soundscape] deterministic synthesis and lifecycle checks")
	_primary = SoundscapeScript.new()
	_primary.name = "PrimarySoundscape"
	root.add_child(_primary)
	_mirror = SoundscapeScript.new()
	_mirror.name = "MirrorSoundscape"
	root.add_child(_mirror)
	await process_frame

	_test_stream_contract()
	_test_deterministic_library()
	await _test_settings_and_target()
	_test_accessible_lightning_timing()
	await _test_weather_binding_and_story_cues()
	await _test_positional_landmarks()
	await _test_clean_teardown()

	if _failures == 0:
		print("[ashen-soundscape] PASS")
		quit(0)
	else:
		printerr("[ashen-soundscape] FAIL: %d assertion(s)" % _failures)
		quit(1)


func _test_stream_contract() -> void:
	_expect(_primary.get_loop_ids() == [&"rain", &"fen_wind", &"ward_hum"], "all three authored ambience layers are present")
	_expect(_primary.get_one_shot_ids() == [&"thunder", &"return", &"finale"], "storm, Return, and finale cues are present")
	for cue_id: StringName in _primary.get_loop_ids():
		var stream := _primary.get_loop_stream(cue_id)
		_expect(stream != null, "%s loop resolves to an in-memory WAV" % cue_id)
		if stream == null:
			continue
		_expect(stream.format == AudioStreamWAV.FORMAT_16_BITS, "%s loop uses 16-bit PCM" % cue_id)
		_expect(stream.mix_rate == 22050, "%s loop uses the intended mix rate" % cue_id)
		_expect(not stream.stereo, "%s loop is mono for a stable spatial mix" % cue_id)
		_expect(stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "%s is explicitly forward-looped" % cue_id)
		_expect(stream.loop_begin == 0, "%s starts its loop at the first sample" % cue_id)
		_expect(stream.loop_end * 2 == stream.data.size(), "%s loop endpoint covers its complete PCM payload" % cue_id)
		_expect(stream.data.size() > 22050 * 2, "%s contains more than one second of authored audio" % cue_id)
	for cue_id: StringName in _primary.get_one_shot_ids():
		var stream := _primary.get_one_shot_stream(cue_id)
		_expect(stream != null, "%s cue resolves to an in-memory WAV" % cue_id)
		if stream == null:
			continue
		_expect(stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.mix_rate == 22050, "%s cue shares the safe PCM contract" % cue_id)
		_expect(stream.loop_mode == AudioStreamWAV.LOOP_DISABLED, "%s remains a true one-shot" % cue_id)
		_expect(stream.data.size() > 22050 * 2, "%s contains a substantial synthesized cue" % cue_id)


func _test_deterministic_library() -> void:
	for cue_id: StringName in _primary.get_loop_ids():
		var first := _primary.get_loop_stream(cue_id)
		var second := _mirror.get_loop_stream(cue_id)
		_expect(first.data == second.data, "%s synthesis is byte-for-byte deterministic" % cue_id)
	for cue_id: StringName in _primary.get_one_shot_ids():
		var first := _primary.get_one_shot_stream(cue_id)
		var second := _mirror.get_one_shot_stream(cue_id)
		_expect(first.data == second.data, "%s one-shot synthesis is byte-for-byte deterministic" % cue_id)
	_expect(
		_primary.get_loop_stream(&"rain").data != _primary.get_loop_stream(&"fen_wind").data,
		"rain and wind are independently authored layers"
	)
	_expect(
		_primary.get_one_shot_stream(&"return").data != _primary.get_one_shot_stream(&"finale").data,
		"Return and finale have distinct musical identities"
	)


func _test_settings_and_target() -> void:
	_target = Node3D.new()
	_target.name = "ListenerTarget"
	root.add_child(_target)
	_primary.set_target(_target)
	_expect(_primary.get_target() == _target, "the 3D listener/player target is exposed")

	var rain := _primary.get_layer_player(&"rain")
	var wind := _primary.get_layer_player(&"fen_wind")
	var ward := _primary.get_layer_player(&"ward_hum")
	_expect(rain != null and wind != null and ward != null, "each ambience layer owns an inspectable player")
	_expect(rain.playing and wind.playing and ward.playing, "ambience begins as a layered sound bed")

	_primary.apply_settings({
		"master_audio": false,
		"master_volume": 0.65,
		"visual_quality": "low",
		"weather_density": 0.4,
		"reduce_flash": true,
	})
	_expect(not _primary.master_enabled, "master audio setting disables the procedural mix")
	_expect(is_equal_approx(_primary.master_gain, 0.65), "master gain setting is retained")
	_expect(_primary.quality == "low" and _primary.get_max_landmark_emitters() == 4, "quality setting applies the low-cost emitter budget")
	_expect(is_equal_approx(_primary.weather_density, 0.4), "weather density setting is retained")
	_expect(_primary.reduced_stimulation, "reduced-flash preference also protects sudden audio timing")
	_expect(not rain.playing and not wind.playing and not ward.playing, "master disable stops every looping bed")

	var quality_before := _primary.quality
	_expect(not _primary.apply_quality("cinematic-ish"), "unknown quality names are rejected")
	_expect(_primary.quality == quality_before, "a rejected quality name does not silently mutate settings")
	_primary.set_master_enabled(true)
	await process_frame
	_expect(rain.playing and wind.playing and ward.playing, "re-enabling master audio resumes the beds")
	_primary.set_weather_density(0.0)
	_expect(not rain.playing and not wind.playing and ward.playing, "zero weather density removes storm layers but preserves ward atmosphere")
	_primary.set_weather_density(1.0)
	_primary.apply_quality("high")


func _test_accessible_lightning_timing() -> void:
	_primary.set_master_enabled(true)
	_mirror.set_master_enabled(true)
	_primary.set_master_gain(1.0)
	_mirror.set_master_gain(1.0)
	_primary.set_reduced_stimulation(true)
	_mirror.set_reduced_stimulation(true)
	var scheduled: Array[Vector2] = []
	_primary.lightning_thunder_scheduled.connect(
		func(delay: float, intensity: float) -> void: scheduled.append(Vector2(delay, intensity))
	)
	var triggered: Array[StringName] = []
	_primary.one_shot_triggered.connect(
		func(cue_id: StringName, _intensity: float) -> void: triggered.append(cue_id)
	)
	_expect(_primary.request_lightning(2.4, 171.5), "first lightning event schedules a physically delayed rumble")
	_expect(_mirror.request_lightning(2.4, 171.5), "matching soundscape accepts the same first event")
	_expect(not scheduled.is_empty(), "lightning exposes its safe thunder schedule")
	if not scheduled.is_empty():
		_expect(scheduled[0].x >= 0.18 and scheduled[0].x <= 3.35, "thunder delay stays inside the bounded accessibility window")
		_expect(scheduled[0].y <= 0.52, "reduced-stimulation mode caps the thunder peak")
	_expect(
		is_equal_approx(_primary.get_pending_thunder_delay(), _mirror.get_pending_thunder_delay()),
		"lightning delay is deterministic for a matching event sequence"
	)
	_expect(_primary.get_lightning_min_interval() >= 12.0, "reduced-stimulation mode lengthens the lightning interval")
	_expect(not _primary.request_lightning(0.8, 30.0), "overlapping lightning cannot stack sudden thunder peaks")

	var delay := _primary.get_pending_thunder_delay()
	_primary._process(delay + 0.01)
	_expect(triggered.has(&"thunder"), "scheduled thunder becomes the authored thunder one-shot")
	_expect(_primary.get_pending_thunder_delay() < 0.0, "fired thunder clears its pending timer")
	_expect(not _primary.request_lightning(0.8, 80.0), "lightning remains gated during the cooldown")
	_primary._process(_primary.get_lightning_cooldown_remaining() + 0.01)
	_expect(_primary.request_lightning(0.8, 80.0), "lightning can schedule again after its safe interval")
	_primary.set_master_enabled(false)
	_expect(_primary.get_pending_thunder_delay() < 0.0, "master disable cancels pending thunder instead of surprising the player later")
	_expect(not _primary.request_lightning(0.8, 80.0), "disabled audio rejects new lightning cues")
	_primary.set_master_enabled(true)


func _test_weather_binding_and_story_cues() -> void:
	_weather_probe = Node.new()
	_weather_probe.name = "WeatherProbe"
	_weather_probe.add_user_signal("lightning_flashed", [{"name": "intensity", "type": TYPE_FLOAT}])
	root.add_child(_weather_probe)
	_expect(_primary.bind_weather_source(_weather_probe), "weather lightning can be bound without a dependency on its concrete script")
	_primary._process(_primary.get_lightning_cooldown_remaining() + 0.01)
	_weather_probe.emit_signal("lightning_flashed", 1.7)
	_expect(_primary.get_pending_thunder_delay() >= 0.18, "a weather flash schedules sound after visual light travel separation")
	_primary.set_master_enabled(false)
	_primary.set_master_enabled(true)

	var story_cues: Array[StringName] = []
	_primary.one_shot_triggered.connect(
		func(cue_id: StringName, _intensity: float) -> void: story_cues.append(cue_id)
	)
	_expect(_primary.play_return_cue(0.9), "Return transition plays its synthesized cue")
	_expect(_primary.play_finale_cue(0.9), "finale transition plays its synthesized cue")
	_expect(story_cues.has(&"return") and story_cues.has(&"finale"), "story cue signals identify both authored events")
	_expect(not _primary.play_cue(&"downloaded_ambience"), "unknown or external cues cannot enter the library")
	_primary.unbind_weather_source()
	_expect(not _primary.bind_weather_source(Node.new()), "nodes without a lightning signal are safely rejected")
	await process_frame


func _test_positional_landmarks() -> void:
	_primary.apply_quality("low")
	var first_position := Vector3(14.0, 2.25, -9.0)
	var emitter := _primary.register_ward_landmark(&"signal_ward/tower", first_position)
	_expect(emitter != null, "a ward landmark creates a positional 3D emitter")
	if emitter != null:
		_expect(emitter.stream == _primary.get_loop_stream(&"ward_hum"), "landmark reuses the deterministic ward loop")
		_expect(emitter.playing, "an enabled landmark begins emitting")
		_expect(emitter.global_position.is_equal_approx(first_position), "landmark emitter uses authored world coordinates")
		_expect(emitter.max_distance > 0.0, "landmark hum has bounded spatial falloff")
		var moved := _primary.register_ward_landmark(&"signal_ward/tower", Vector3(15.0, 2.25, -8.0))
		_expect(moved == emitter and _primary.get_landmark_emitter_count() == 1, "re-registering a stable landmark ID updates instead of duplicating")

	for index in range(1, _primary.get_max_landmark_emitters()):
		_primary.register_ward_landmark(StringName("test_ward/%d" % index), Vector3(float(index), 0.5, 0.0))
	_expect(_primary.get_landmark_emitter_count() == 4, "low quality enforces its positional emitter budget")
	_expect(_primary.register_ward_landmark(&"test_ward/overflow", Vector3.ZERO) == null, "landmark overflow fails safely")
	var old_range := emitter.max_distance if emitter != null else 0.0
	_primary.apply_quality("ultra")
	if emitter != null:
		_expect(emitter.max_distance > old_range, "quality upgrade expands landmark acoustic range without rebuilding audio")
	_expect(_primary.remove_landmark_emitter(&"test_ward/1"), "a landmark emitter can be removed cleanly")
	_expect(not _primary.remove_landmark_emitter(&"test_ward/missing"), "removing an unknown landmark is harmless")
	await process_frame


func _test_clean_teardown() -> void:
	var soundscape_ref: WeakRef = weakref(_primary)
	var rain_ref: WeakRef = weakref(_primary.get_layer_player(&"rain"))
	var emitter_ref: WeakRef = weakref(_primary.get_landmark_emitter(&"signal_ward/tower"))
	var mirror_ref: WeakRef = weakref(_mirror)
	_primary.queue_free()
	_mirror.queue_free()
	_target.queue_free()
	_weather_probe.queue_free()
	await process_frame
	await process_frame
	_expect(soundscape_ref.get_ref() == null and mirror_ref.get_ref() == null, "soundscape services leave the tree cleanly")
	_expect(rain_ref.get_ref() == null, "owned ambience players are released with the service")
	_expect(emitter_ref.get_ref() == null, "owned positional emitters are released with the service")


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	printerr("  assertion failed: %s" % message)
