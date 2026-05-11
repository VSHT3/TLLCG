extends Node

signal track_changed(label: String)

const MIX_RATE := 44100
const GAMEPLAY_MUSIC_DIR := "res://assets/audio/music/gameplay"
const MUSIC_CONTEXT_MENU := "menu"
const MUSIC_CONTEXT_GAMEPLAY := "gameplay"
const SPECTRUM_ANALYZER_NAME := "TLLCGMusicSpectrum"

var enabled := true
var sfx_volume := 1.0
var music_volume := 0.42
var music_enabled := true
var music_context := MUSIC_CONTEXT_MENU
var _music_running := false
var _generated_player: AudioStreamPlayer = null
var _music_playback: AudioStreamGeneratorPlayback = null
var _music_phase_a := 0.0
var _music_phase_b := 0.0
var _music_phase_c := 0.0
var _music_time := 0.0
var _track_player: AudioStreamPlayer = null
var _gameplay_tracks: Array[AudioStream] = []
var _gameplay_queue: Array[AudioStream] = []
var _last_track: AudioStream = null
var _current_track_label := ""
var _last_spectrum_peak := 0.0
var _spectrum_effect_idx := -1
var _spectrum_instance = null


func _ready() -> void:
	if SettingsManager:
		enabled = bool(SettingsManager.get_value("sound_enabled", enabled))
		music_enabled = bool(SettingsManager.get_value("music_enabled", music_enabled))
		music_volume = float(SettingsManager.get_value("music_volume", music_volume))
		sfx_volume = float(SettingsManager.get_value("sfx_volume", sfx_volume))
		SettingsManager.settings_changed.connect(_on_setting_changed)
	EventBus.card_played.connect(func(_card: CardInstance, _player_id: int) -> void:
		play_card()
	)
	EventBus.card_drawn.connect(func(_card: CardInstance, _player_id: int, _source: String) -> void:
		play_draw()
	)
	EventBus.damage_dealt.connect(func(_target: CardInstance, amount: int, _source: CardInstance) -> void:
		if amount > 0:
			play_damage()
	)
	EventBus.boost_applied.connect(func(_target: CardInstance, _amount: int) -> void:
		play_boost()
	)
	EventBus.status_applied.connect(func(_target: CardInstance, _status_name: String, _stacks: int) -> void:
		play_status()
	)
	EventBus.ability_triggered.connect(func(_card: CardInstance, _effect: CardEffect) -> void:
		play_ability()
	)
	EventBus.game_ended.connect(func(_winner_id: int) -> void:
		play_game_over()
	)
	if _audio_runtime_allowed():
		_ensure_spectrum_analyzer()
		start_music()


func set_music_context(context: String) -> void:
	if context != MUSIC_CONTEXT_MENU and context != MUSIC_CONTEXT_GAMEPLAY:
		context = MUSIC_CONTEXT_MENU
	if music_context == context and _music_running:
		track_changed.emit(current_track_label())
		return
	music_context = context
	if enabled and music_enabled:
		stop_music()
		start_music()
	else:
		track_changed.emit(current_track_label())


func play_card() -> void:
	_play_tone(220.0, 0.045, 0.035)
	_play_tone(440.0, 0.06, 0.052, 0.025)


func play_draw() -> void:
	_play_tone(520.0, 0.035, 0.026)
	_play_tone(780.0, 0.045, 0.024, 0.024)


func play_damage() -> void:
	_play_tone(95.0, 0.09, 0.075)
	_play_tone(144.0, 0.06, 0.05, 0.02)


func play_boost() -> void:
	_play_tone(392.0, 0.045, 0.035)
	_play_tone(659.0, 0.06, 0.035, 0.032)


func play_status() -> void:
	_play_tone(196.0, 0.075, 0.038)
	_play_tone(294.0, 0.075, 0.03, 0.018)


func play_ability() -> void:
	_play_tone(330.0, 0.045, 0.026)
	_play_tone(990.0, 0.035, 0.022, 0.025)


func play_game_over() -> void:
	_play_tone(330.0, 0.10, 0.055)
	_play_tone(440.0, 0.12, 0.05, 0.09)
	_play_tone(660.0, 0.16, 0.045, 0.2)


func play_ui() -> void:
	_play_tone(760.0, 0.035, 0.035)


func set_enabled(value: bool) -> void:
	enabled = value
	if SettingsManager:
		SettingsManager.set_value("sound_enabled", enabled)
	if enabled:
		start_music()
	else:
		stop_music()


func toggle_enabled() -> bool:
	enabled = not enabled
	if enabled:
		start_music()
		play_ui()
	else:
		stop_music()
	return enabled


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	if SettingsManager:
		SettingsManager.set_value("sfx_volume", sfx_volume)
	if enabled:
		play_ui()


func adjust_sfx_volume(delta: float) -> void:
	set_sfx_volume(sfx_volume + delta)


func start_music() -> void:
	if _music_running or not enabled or not music_enabled or not _audio_runtime_allowed():
		return
	_music_running = true
	if _ensure_gameplay_player():
		_stop_generated_music()
		_play_next_gameplay_track()
		set_process(true)
		return
	_start_generated_music()


func stop_music() -> void:
	_music_running = false
	_stop_generated_music()
	if _track_player:
		_track_player.stop()
	set_process(false)
	track_changed.emit(current_track_label())


func set_music_enabled(value: bool) -> void:
	music_enabled = value
	if SettingsManager:
		SettingsManager.set_value("music_enabled", music_enabled)
	if music_enabled and enabled:
		start_music()
	else:
		stop_music()


func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	if SettingsManager:
		SettingsManager.set_value("music_volume", music_volume)
	if _generated_player:
		_generated_player.volume_db = linear_to_db(maxf(music_volume * 0.62, 0.001))
	if _track_player:
		_track_player.volume_db = linear_to_db(maxf(music_volume * 0.58, 0.001))


func skip_gameplay_track() -> void:
	if not _ensure_gameplay_player():
		return
	_music_running = true
	_stop_generated_music()
	_play_next_gameplay_track()


func current_track_label() -> String:
	if not enabled or not music_enabled:
		return "Music off"
	if _current_track_label != "":
		return _current_track_label
	if _track_player and _track_player.stream:
		if _track_player.stream.has_meta("track_label"):
			return str(_track_player.stream.get_meta("track_label"))
		var path := _track_player.stream.resource_path
		if path != "":
			return path.get_file().get_basename().replace("_", " ").capitalize()
	return "Generated Ambient"


func jukebox_status() -> String:
	if not enabled:
		return "Sound off"
	if not music_enabled:
		return "Music off"
	if _track_player and _track_player.playing:
		return "Playing"
	if _generated_player and _generated_player.playing:
		return "Generated fallback"
	if _gameplay_tracks.is_empty():
		return "No MP3 tracks found"
	return "Stopped"


func get_spectrum_bands(count: int) -> Array[float]:
	var bands: Array[float] = []
	if count <= 0:
		return bands
	for _i in range(count):
		bands.append(0.0)
	if not enabled or not music_enabled or not _audio_runtime_allowed():
		return bands
	_ensure_spectrum_analyzer()
	if not _spectrum_instance:
		return bands
	var min_hz := 45.0
	var max_hz := 11000.0
	for i in range(count):
		var low := min_hz * pow(max_hz / min_hz, float(i) / float(count))
		var high := min_hz * pow(max_hz / min_hz, float(i + 1) / float(count))
		var magnitude: Vector2 = _spectrum_instance.get_magnitude_for_frequency_range(low, high)
		var energy := maxf(magnitude.x, magnitude.y)
		bands[i] = clampf(pow(energy * 42.0, 0.55), 0.0, 1.0)
		_last_spectrum_peak = maxf(_last_spectrum_peak, bands[i])
	return bands


func synthetic_music_bands(count: int) -> Array[float]:
	var bands: Array[float] = []
	var ticks := float(Time.get_ticks_msec()) / 1000.0
	var playing := enabled and music_enabled and ((_track_player and _track_player.playing) or (_generated_player and _generated_player.playing))
	for i in range(count):
		if not playing:
			bands.append(0.0)
			continue
		var a: float = 0.18 + abs(sin(ticks * (2.1 + float(i) * 0.17) + float(i) * 0.73)) * 0.55
		var beat: float = pow(maxf(0.0, sin(ticks * 3.2 + float(i) * 0.41)), 3.0) * 0.32
		bands.append(clampf(a + beat, 0.0, 1.0))
	return bands


func _on_setting_changed(key: String, value: Variant) -> void:
	match key:
		"sound_enabled":
			enabled = bool(value)
			if enabled:
				start_music()
			else:
				stop_music()
			track_changed.emit(current_track_label())
		"music_enabled":
			music_enabled = bool(value)
			if music_enabled and enabled:
				start_music()
			else:
				stop_music()
			track_changed.emit(current_track_label())
		"music_volume":
			music_volume = clampf(float(value), 0.0, 1.0)
			if _generated_player:
				_generated_player.volume_db = linear_to_db(maxf(music_volume * 0.62, 0.001))
			if _track_player:
				_track_player.volume_db = linear_to_db(maxf(music_volume * 0.58, 0.001))
		"sfx_volume":
			sfx_volume = clampf(float(value), 0.0, 1.0)


func _process(_delta: float) -> void:
	if not _music_running or not enabled or not music_enabled or not _audio_runtime_allowed():
		stop_music()
		return
	if music_context == MUSIC_CONTEXT_GAMEPLAY and _track_player and _track_player.playing:
		return
	if music_context == MUSIC_CONTEXT_GAMEPLAY and _ensure_gameplay_player():
		_play_next_gameplay_track()
		return
	if not _music_playback and _generated_player:
		_music_playback = _generated_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if _music_playback:
		_fill_music_buffer()


func _start_generated_music() -> void:
	_ensure_spectrum_analyzer()
	if not _generated_player:
		_generated_player = AudioStreamPlayer.new()
		var stream := AudioStreamGenerator.new()
		stream.mix_rate = MIX_RATE
		stream.buffer_length = 0.35
		_generated_player.stream = stream
		add_child(_generated_player)
	_generated_player.volume_db = linear_to_db(maxf(music_volume * 0.62, 0.001))
	_generated_player.play()
	_music_playback = _generated_player.get_stream_playback() as AudioStreamGeneratorPlayback
	set_process(true)
	track_changed.emit(current_track_label())


func _stop_generated_music() -> void:
	if _generated_player:
		_generated_player.stop()
	_music_playback = null


func _ensure_gameplay_player() -> bool:
	_ensure_spectrum_analyzer()
	if _gameplay_tracks.is_empty():
		_load_gameplay_tracks()
	if _gameplay_tracks.is_empty():
		return false
	if not _track_player:
		_track_player = AudioStreamPlayer.new()
		_track_player.finished.connect(_on_gameplay_track_finished)
		add_child(_track_player)
	_track_player.volume_db = linear_to_db(maxf(music_volume * 0.58, 0.001))
	return true


func _load_gameplay_tracks() -> void:
	_gameplay_tracks.clear()
	var dir := DirAccess.open(GAMEPLAY_MUSIC_DIR)
	if not dir:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.get_extension().to_lower() == "mp3":
			var path := "%s/%s" % [GAMEPLAY_MUSIC_DIR, file_name]
			var stream := AudioStreamMP3.load_from_file(ProjectSettings.globalize_path(path))
			if stream is AudioStream:
				stream.set_meta("track_label", _format_track_label(path))
				_gameplay_tracks.append(stream)
		file_name = dir.get_next()
	dir.list_dir_end()
	_gameplay_tracks.shuffle()


func _play_next_gameplay_track() -> void:
	if not _track_player or _gameplay_tracks.is_empty():
		_music_running = false
		return
	if _gameplay_queue.is_empty():
		_gameplay_queue = _gameplay_tracks.duplicate()
		_gameplay_queue.shuffle()
		if _gameplay_queue.size() > 1 and _gameplay_queue[0] == _last_track:
			var first: AudioStream = _gameplay_queue.pop_front()
			_gameplay_queue.append(first)
	var stream: AudioStream = _gameplay_queue.pop_front()
	if _gameplay_tracks.size() > 1:
		var guard := 0
		while stream == _last_track and guard < _gameplay_queue.size():
			_gameplay_queue.append(stream)
			stream = _gameplay_queue.pop_front()
			guard += 1
	_last_track = stream
	_current_track_label = _stream_track_label(stream)
	_track_player.stop()
	_track_player.stream = stream
	_track_player.volume_db = linear_to_db(maxf(music_volume * 0.58, 0.001))
	_track_player.play()
	track_changed.emit(current_track_label())


func _on_gameplay_track_finished() -> void:
	if _music_running and enabled and music_enabled and music_context == MUSIC_CONTEXT_GAMEPLAY:
		_play_next_gameplay_track()


func _ensure_spectrum_analyzer() -> void:
	if not _audio_runtime_allowed():
		return
	var bus_idx := AudioServer.get_bus_index("Master")
	if bus_idx < 0:
		return
	if _spectrum_effect_idx >= 0:
		_spectrum_instance = AudioServer.get_bus_effect_instance(bus_idx, _spectrum_effect_idx)
		return
	for i in range(AudioServer.get_bus_effect_count(bus_idx)):
		var effect := AudioServer.get_bus_effect(bus_idx, i)
		if effect and effect.resource_name == SPECTRUM_ANALYZER_NAME:
			_spectrum_effect_idx = i
			_spectrum_instance = AudioServer.get_bus_effect_instance(bus_idx, i)
			return
	var analyzer := AudioEffectSpectrumAnalyzer.new()
	analyzer.resource_name = SPECTRUM_ANALYZER_NAME
	analyzer.buffer_length = 0.12
	AudioServer.add_bus_effect(bus_idx, analyzer)
	_spectrum_effect_idx = AudioServer.get_bus_effect_count(bus_idx) - 1
	_spectrum_instance = AudioServer.get_bus_effect_instance(bus_idx, _spectrum_effect_idx)


func _stream_track_label(stream: AudioStream) -> String:
	if stream and stream.has_meta("track_label"):
		return str(stream.get_meta("track_label"))
	if stream and stream.resource_path != "":
		return _format_track_label(stream.resource_path)
	return "Unknown Track"


func _format_track_label(path: String) -> String:
	return path.get_file().get_basename().replace("_", " ").capitalize()


func _fill_music_buffer() -> void:
	var available := _music_playback.get_frames_available()
	if available <= 0:
		return
	var roots: Array[float] = [55.0, 65.41, 49.0, 73.42]
	var chord_index := int(floor(_music_time / 5.8)) % roots.size()
	var root: float = roots[chord_index]
	var fifth: float = root * 1.5
	var upper: float = root * 4.0
	for _i in range(available):
		var wobble := 1.0 + sin(TAU * 0.04 * _music_time) * 0.006
		_music_phase_a = fmod(_music_phase_a + (root * wobble / MIX_RATE), 1.0)
		_music_phase_b = fmod(_music_phase_b + (fifth / MIX_RATE), 1.0)
		_music_phase_c = fmod(_music_phase_c + (upper / MIX_RATE), 1.0)
		var pulse := 0.65 + 0.35 * sin(TAU * 0.22 * _music_time)
		var sample := sin(TAU * _music_phase_a) * 0.055
		sample += sin(TAU * _music_phase_b) * 0.025
		sample += sin(TAU * _music_phase_c) * 0.012 * pulse
		sample *= music_volume
		_music_playback.push_frame(Vector2(sample, sample))
		_music_time += 1.0 / MIX_RATE


func _play_tone(freq: float, duration: float, volume: float, delay: float = 0.0) -> void:
	if not enabled or not _audio_runtime_allowed():
		return
	await _emit_tone(freq, duration, volume * sfx_volume, delay, -8.0)


func _play_music_tone(freq: float, duration: float, volume: float, delay: float = 0.0) -> void:
	if not enabled or not music_enabled or not _audio_runtime_allowed():
		return
	await _emit_tone(freq, duration, volume * music_volume, delay, -16.0)


func _audio_runtime_allowed() -> bool:
	return DisplayServer.get_name() != "headless"


func _emit_tone(freq: float, duration: float, volume: float, delay: float = 0.0, output_db: float = -8.0) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if not enabled:
		return
	var player := AudioStreamPlayer.new()
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = MIX_RATE
	stream.buffer_length = maxf(duration + 0.04, 0.08)
	player.stream = stream
	player.volume_db = output_db
	add_child(player)
	player.play()
	var playback := player.get_stream_playback() as AudioStreamGeneratorPlayback
	if not playback:
		player.queue_free()
		return
	var frames := int(duration * MIX_RATE)
	for i in range(frames):
		var t := float(i) / float(MIX_RATE)
		var p := float(i) / maxf(float(frames), 1.0)
		var attack := clampf(p / 0.08, 0.0, 1.0)
		var release := clampf((1.0 - p) / 0.16, 0.0, 1.0)
		var envelope := minf(attack, release)
		var sample := sin(TAU * freq * t) * volume * envelope
		sample += sin(TAU * freq * 2.0 * t) * volume * 0.14 * envelope
		playback.push_frame(Vector2(sample, sample))
	await get_tree().create_timer(duration + 0.05).timeout
	player.queue_free()
