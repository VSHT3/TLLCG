extends Node

const MIX_RATE := 44100
const GAMEPLAY_MUSIC_DIR := "res://assets/audio/music/gameplay"
const MUSIC_CONTEXT_MENU := "menu"
const MUSIC_CONTEXT_GAMEPLAY := "gameplay"

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
		start_music()


func set_music_context(context: String) -> void:
	if context != MUSIC_CONTEXT_MENU and context != MUSIC_CONTEXT_GAMEPLAY:
		context = MUSIC_CONTEXT_MENU
	if music_context == context and _music_running:
		return
	music_context = context
	if enabled and music_enabled:
		stop_music()
		start_music()


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
	if music_context == MUSIC_CONTEXT_GAMEPLAY and _ensure_gameplay_player():
		_stop_generated_music()
		_play_next_gameplay_track()
		set_process(true)
		return
	if music_context == MUSIC_CONTEXT_GAMEPLAY:
		_music_running = false
		set_process(false)
		return
	_start_generated_music()


func stop_music() -> void:
	_music_running = false
	_stop_generated_music()
	if _track_player:
		_track_player.stop()
	set_process(false)


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
	if music_context != MUSIC_CONTEXT_GAMEPLAY:
		return
	if not _ensure_gameplay_player():
		return
	_music_running = true
	_stop_generated_music()
	_play_next_gameplay_track()


func current_track_label() -> String:
	if _track_player and _track_player.stream:
		var path := _track_player.stream.resource_path
		if path != "":
			return path.get_file().get_basename().replace("_", " ").capitalize()
	return "Generated Ambient"


func _on_setting_changed(key: String, value: Variant) -> void:
	match key:
		"sound_enabled":
			enabled = bool(value)
			if enabled:
				start_music()
			else:
				stop_music()
		"music_enabled":
			music_enabled = bool(value)
			if music_enabled and enabled:
				start_music()
			else:
				stop_music()
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


func _stop_generated_music() -> void:
	if _generated_player:
		_generated_player.stop()
	_music_playback = null


func _ensure_gameplay_player() -> bool:
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
			var stream := load(path)
			if not (stream is AudioStream) and AudioStreamMP3:
				stream = AudioStreamMP3.load_from_file(path)
			if stream is AudioStream:
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
	_track_player.stop()
	_track_player.stream = stream
	_track_player.volume_db = linear_to_db(maxf(music_volume * 0.58, 0.001))
	_track_player.play()


func _on_gameplay_track_finished() -> void:
	if _music_running and enabled and music_enabled and music_context == MUSIC_CONTEXT_GAMEPLAY:
		_play_next_gameplay_track()


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
