extends Node

const MIX_RATE := 44100

var enabled := true
var sfx_volume := 1.0


func _ready() -> void:
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


func play_card() -> void:
	_play_tone(360.0, 0.055, 0.055)
	_play_tone(520.0, 0.05, 0.04, 0.035)


func play_draw() -> void:
	_play_tone(620.0, 0.04, 0.035)


func play_damage() -> void:
	_play_tone(130.0, 0.075, 0.07)


func play_boost() -> void:
	_play_tone(480.0, 0.04, 0.04)
	_play_tone(720.0, 0.055, 0.035, 0.035)


func play_status() -> void:
	_play_tone(260.0, 0.065, 0.045)


func play_ability() -> void:
	_play_tone(820.0, 0.035, 0.025)


func play_game_over() -> void:
	_play_tone(330.0, 0.10, 0.055)
	_play_tone(440.0, 0.12, 0.05, 0.09)
	_play_tone(660.0, 0.16, 0.045, 0.2)


func play_ui() -> void:
	_play_tone(760.0, 0.035, 0.035)


func set_enabled(value: bool) -> void:
	enabled = value


func toggle_enabled() -> bool:
	enabled = not enabled
	if enabled:
		play_ui()
	return enabled


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	if enabled:
		play_ui()


func adjust_sfx_volume(delta: float) -> void:
	set_sfx_volume(sfx_volume + delta)


func _play_tone(freq: float, duration: float, volume: float, delay: float = 0.0) -> void:
	if not enabled:
		return
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	var player := AudioStreamPlayer.new()
	var stream := AudioStreamGenerator.new()
	stream.mix_rate = MIX_RATE
	stream.buffer_length = maxf(duration + 0.04, 0.08)
	player.stream = stream
	player.volume_db = -8.0
	add_child(player)
	player.play()
	var playback := player.get_stream_playback() as AudioStreamGeneratorPlayback
	if not playback:
		player.queue_free()
		return
	var frames := int(duration * MIX_RATE)
	for i in range(frames):
		var t := float(i) / float(MIX_RATE)
		var envelope := 1.0 - (float(i) / maxf(float(frames), 1.0))
		var sample := sin(TAU * freq * t) * volume * sfx_volume * envelope
		playback.push_frame(Vector2(sample, sample))
	await get_tree().create_timer(duration + 0.05).timeout
	player.queue_free()
