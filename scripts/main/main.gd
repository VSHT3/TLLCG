## Main
## Entry point scene. Manages game initialization, turn flow UI, and scene transitions.
extends Node2D

# ── Scene References ─────────────────────────────────────────────────────────

@onready var board_p0: BoardVisual = $GameBoard/Player0Board
@onready var board_p1: BoardVisual = $GameBoard/Player1Board
@onready var hand_p0: HandManager = $UI/HandP0
@onready var hand_p1: HandManager = $UI/HandP1
@onready var hud: Control = $UI/HUD
@onready var turn_label: Label = $UI/HUD/TurnLabel
@onready var phase_label: Label = $UI/HUD/PhaseLabel
@onready var sellary_label_p0: Label = $UI/HUD/SellaryP0
@onready var sellary_label_p1: Label = $UI/HUD/SellaryP1
@onready var hero_hp_p0: Label = $UI/HUD/HeroHPP0
@onready var hero_hp_p1: Label = $UI/HUD/HeroHPP1
@onready var end_phase_button: Button = $UI/HUD/EndPhaseButton
@onready var effect_resolver: EffectResolver = $EffectResolver

# ── Game State ───────────────────────────────────────────────────────────────

var game_state: GameState = null


# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	_connect_signals()
	_start_new_game(["Sir Can", "A.I. Gods"])  # Default matchup


func _start_new_game(factions: Array[String]) -> void:
	game_state = GameState.new()
	effect_resolver.setup(game_state)
	game_state.setup_game(factions)
	
	# Setup visuals
	if board_p0:
		board_p0.setup(game_state.players[0])
	if board_p1:
		board_p1.setup(game_state.players[1])
	if hand_p0:
		hand_p0.setup(game_state.players[0])
	if hand_p1:
		hand_p1.setup(game_state.players[1])
	
	# Start first turn
	game_state.start_turn()
	_refresh_all()


func _connect_signals() -> void:
	EventBus.turn_started.connect(_on_turn_started)
	EventBus.turn_ended.connect(_on_turn_ended)
	EventBus.phase_changed.connect(_on_phase_changed)
	EventBus.card_played.connect(_on_card_played)
	EventBus.card_drawn.connect(_on_card_drawn)
	EventBus.card_destroyed.connect(_on_card_destroyed)
	EventBus.sellary_gained.connect(_on_sellary_changed)
	EventBus.sellary_spent.connect(_on_sellary_changed)
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.game_ended.connect(_on_game_ended)
	EventBus.message_shown.connect(_on_message)
	
	if end_phase_button:
		end_phase_button.pressed.connect(_on_end_phase_pressed)


# ── Signal Handlers ──────────────────────────────────────────────────────────

func _on_turn_started(player_id: int, turn_num: int) -> void:
	if turn_label:
		turn_label.text = "Turn %d — Player %d" % [turn_num, player_id + 1]
	_refresh_all()


func _on_turn_ended(_player_id: int) -> void:
	_refresh_all()


func _on_phase_changed(phase: int, _player_id: int) -> void:
	if phase_label:
		phase_label.text = GameConstants.PHASE_NAMES.get(phase, "Unknown")
	
	# Update button text based on phase
	if end_phase_button:
		match phase:
			GameConstants.TurnPhase.PLAY_CARDS:
				end_phase_button.text = "Done Playing"
			GameConstants.TurnPhase.DISCARD_CARDS:
				end_phase_button.text = "Done Discarding"
			GameConstants.TurnPhase.DRAW_CARDS:
				end_phase_button.text = "Done Drawing"
			_:
				end_phase_button.text = "Continue"


func _on_card_played(card: CardInstance, _player_id: int) -> void:
	print("[Main] Card played: %s" % card.data.name)
	_refresh_all()


func _on_card_drawn(card: CardInstance, player_id: int, source: String) -> void:
	print("[Main] Player %d drew %s from %s" % [player_id, card.data.name, source])
	_refresh_all()


func _on_card_destroyed(card: CardInstance, _source: CardInstance) -> void:
	print("[Main] Card destroyed: %s" % card.data.name)
	_refresh_all()


func _on_sellary_changed(_player_id: int, _amount: int) -> void:
	_refresh_hud()


func _on_damage_dealt(target: CardInstance, amount: int, source: CardInstance) -> void:
	var src_name: String = source.data.name if source else "?"
	print("[Main] %s dealt %d damage to %s" % [src_name, amount, target.data.name])
	_refresh_all()


func _on_game_ended(winner_id: int) -> void:
	print("[Main] Game Over! Winner: Player %d" % (winner_id + 1))
	if phase_label:
		phase_label.text = "GAME OVER — Player %d wins!" % (winner_id + 1)


func _on_message(text: String) -> void:
	print("[Game] %s" % text)


func _on_end_phase_pressed() -> void:
	match game_state.current_phase:
		GameConstants.TurnPhase.PLAY_CARDS:
			game_state.end_play_phase()
		GameConstants.TurnPhase.DISCARD_CARDS:
			game_state.end_discard_phase()
		GameConstants.TurnPhase.DRAW_CARDS:
			game_state.end_draw_phase()


# ── Refresh ──────────────────────────────────────────────────────────────────

func _refresh_all() -> void:
	if board_p0:
		board_p0.refresh()
	if board_p1:
		board_p1.refresh()
	if hand_p0:
		hand_p0.refresh()
	if hand_p1:
		hand_p1.refresh()
	_refresh_hud()


func _refresh_hud() -> void:
	if game_state.players.size() < 2:
		return
	var p0: PlayerState = game_state.players[0]
	var p1: PlayerState = game_state.players[1]
	
	if sellary_label_p0:
		sellary_label_p0.text = "P1 Sellary: %d" % p0.sellary
	if sellary_label_p1:
		sellary_label_p1.text = "P2 Sellary: %d" % p1.sellary
	if hero_hp_p0 and p0.hero:
		hero_hp_p0.text = "P1 Hero: %d HP" % p0.hero.current_power
	if hero_hp_p1 and p1.hero:
		hero_hp_p1.text = "P2 Hero: %d HP" % p1.hero.current_power
