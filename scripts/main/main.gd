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
@onready var message_label: Label = $UI/HUD/MessageLabel
@onready var end_turn_button: Button = $UI/HUD/EndTurnButton
@onready var neutral_deck_panel: Panel = $UI/NeutralDeckPanel
@onready var faction_deck_panel_p0: Panel = $UI/FactionDeckPanelP0
@onready var faction_deck_panel_p1: Panel = $UI/FactionDeckPanelP1
@onready var neutral_deck_label: Label = $UI/NeutralDeckPanel/NeutralDeckLabel
@onready var faction_deck_label_p0: Label = $UI/FactionDeckPanelP0/FactionDeckLabel
@onready var faction_deck_label_p1: Label = $UI/FactionDeckPanelP1/FactionDeckLabel
@onready var graveyard_panel_p0: Panel = $UI/GraveyardPanelP0
@onready var graveyard_panel_p1: Panel = $UI/GraveyardPanelP1
@onready var graveyard_label_p0: Label = $UI/GraveyardPanelP0/GraveyardLabelP0
@onready var graveyard_label_p1: Label = $UI/GraveyardPanelP1/GraveyardLabelP1
@onready var hero_container_p0: Control = $UI/HUD/HeroP0
@onready var hero_container_p1: Control = $UI/HUD/HeroP1
var hero_visual_p0: CardVisual = null
var hero_visual_p1: CardVisual = null
var hero_bar_fill_p0: ColorRect = null
var hero_bar_fill_p1: ColorRect = null
var hero_bar_label_p0: Label = null
var hero_bar_label_p1: Label = null
@onready var effect_resolver: EffectResolver = $EffectResolver
@onready var card_detail_popup: PanelContainer = $UI/CardDetailPopup
@onready var detail_name: Label = $UI/CardDetailPopup/VBox/DetailName
@onready var detail_meta: Label = $UI/CardDetailPopup/VBox/DetailMeta
@onready var detail_power: Label = $UI/CardDetailPopup/VBox/DetailPower
@onready var detail_ability: RichTextLabel = $UI/CardDetailPopup/VBox/DetailAbility
@onready var detail_activate_button: Button = $UI/CardDetailPopup/VBox/ActivateButton
@onready var detail_close_button: Button = $UI/CardDetailPopup/VBox/CloseButton

const MENU_SCENE := "res://scenes/menus/main_menu.tscn"
const CardTestRunnerScript := preload("res://scripts/game/card_test_runner.gd")
const SettingsPanelScript := preload("res://scripts/ui/settings_panel.gd")

# ── Game State ───────────────────────────────────────────────────────────────

var game_state: GameState = null
var pending_unit_card: CardInstance = null
var pending_drag_card: CardInstance = null
var pending_target_callback: Callable = Callable()
var pending_valid_targets: Array = []
var _detail_card_visual: CardVisual = null
var _detail_card_instance: CardInstance = null
var choice_panel: PanelContainer = null
var choice_title: Label = null
var choice_options: VBoxContainer = null
var action_log_panel: PanelContainer = null
var action_log_text: RichTextLabel = null
var action_log_lines: Array[String] = []
var debug_panel: PanelContainer = null
var debug_card_id: LineEdit = null
var debug_player_select: OptionButton = null
var debug_zone_select: OptionButton = null
var debug_row_spin: SpinBox = null
var debug_col_spin: SpinBox = null
var debug_power_spin: SpinBox = null
var debug_counter_spin: SpinBox = null
var debug_timer_spin: SpinBox = null
var debug_charges_spin: SpinBox = null
var zone_panel: PanelContainer = null
var zone_title: Label = null
var zone_list: VBoxContainer = null
var zone_close_button: Button = null
var game_over_panel: PanelContainer = null
var game_over_title: Label = null
var game_over_summary: Label = null
var _graveyard_sequence := 0
var event_panel: PanelContainer = null
var event_title_label: Label = null
var event_detail_label: Label = null
var event_queue: Array[Dictionary] = []
var event_showing := false
var event_hold_timer_active := false
var popup_hold_until_ms := 0
var status_panel_top: PanelContainer = null
var status_panel_bottom: PanelContainer = null
var turn_banner_panel: PanelContainer = null
var turn_banner_player_label: Label = null
var turn_banner_phase_label: Label = null
var turn_banner_meta_label: Label = null
var top_name_label: Label = null
var top_sellary_label: Label = null
var top_hp_label: Label = null
var bottom_name_label: Label = null
var bottom_sellary_label: Label = null
var bottom_hp_label: Label = null
var ability_panel: PanelContainer = null
var ability_title_label: Label = null
var ability_items: VBoxContainer = null
var ai_enabled := false
var ai_running := false
var ai_toggle_button: Button = null
var sound_toggle_button: Button = null
var settings_panel = null
var debug_toggle_button: Button = null
var _last_turn_banner_key := ""


# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	AudioManager.set_music_context(AudioManager.MUSIC_CONTEXT_GAMEPLAY)
	_build_table_backdrop()
	_build_menu_button()
	_build_turn_banner()
	_build_status_panels()
	_build_action_log()
	_build_event_panel()
	_build_ability_panel()
	_build_debug_panel()
	_build_settings_panel()
	_build_zone_panel()
	_build_game_over_panel()
	_build_choice_panel()
	_apply_ui_theme()
	_apply_settings()
	SettingsManager.settings_changed.connect(_on_setting_changed)
	_connect_signals()
	_start_new_game(GameConstants.pending_faction_choices)


func _start_new_game(factions: Array[String]) -> void:
	game_state = GameState.new()
	effect_resolver.setup(game_state)
	game_state.setup_game(factions, GameConstants.first_player_id)
	
	# Setup visuals
	if board_p0:
		board_p0.setup(game_state.players[0])
	if board_p1:
		board_p1.setup(game_state.players[1])
	if hand_p0:
		hand_p0.setup(game_state.players[0])
		hand_p0.can_play_func = _can_play_card
	if hand_p1:
		hand_p1.setup(game_state.players[1])
		hand_p1.can_play_func = _can_play_card
	
	# Instantiate hero visuals from card scene
	var card_scene: PackedScene = hand_p0.card_visual_scene if hand_p0 else null
	if card_scene:
		if hero_container_p0 and game_state.players[0].hero:
			hero_visual_p0 = _setup_hero_visual(card_scene, hero_container_p0, game_state.players[0].hero)
			hero_visual_p0.clicked.connect(_on_hero_clicked)
			_build_hero_hp_bar(hero_container_p0, 0)
		if hero_container_p1 and game_state.players[1].hero:
			hero_visual_p1 = _setup_hero_visual(card_scene, hero_container_p1, game_state.players[1].hero)
			hero_visual_p1.clicked.connect(_on_hero_clicked)
			_build_hero_hp_bar(hero_container_p1, 1)

	# Start first turn
	game_state.start_turn()
	_refresh_all()
	if bool(SettingsManager.get_value("board_intro_enabled", true)):
		call_deferred("_play_match_intro")


func _setup_hero_visual(card_scene: PackedScene, container: Control, hero: CardInstance) -> CardVisual:
	container.clip_contents = true
	container.custom_minimum_size = Vector2(180, 100)
	var visual: CardVisual = card_scene.instantiate()
	container.add_child(visual)
	visual.setup(hero)
	visual.show_power_chip = false
	visual.set_card_dimensions(Vector2(180, 82))
	visual.refresh_display()
	visual.mouse_filter = Control.MOUSE_FILTER_STOP
	return visual


func _connect_signals() -> void:
	EventBus.turn_started.connect(_on_turn_started)
	EventBus.turn_ended.connect(_on_turn_ended)
	EventBus.phase_changed.connect(_on_phase_changed)
	EventBus.target_requested.connect(_on_target_requested)
	EventBus.card_played.connect(_on_card_played)
	EventBus.card_selected.connect(_on_card_selected)
	EventBus.card_drawn.connect(_on_card_drawn)
	EventBus.card_discarded.connect(_on_card_discarded)
	EventBus.card_destroyed.connect(_on_card_destroyed)
	EventBus.card_banished.connect(_on_card_banished)
	EventBus.card_placed_on_board.connect(_on_card_placed_on_board)
	EventBus.card_removed_from_board.connect(_on_card_removed_from_board)
	EventBus.sellary_gained.connect(_on_sellary_changed)
	EventBus.sellary_spent.connect(_on_sellary_changed)
	EventBus.sellary_seized.connect(_on_sellary_seized)
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.heal_applied.connect(_on_heal_applied)
	EventBus.boost_applied.connect(_on_boost_applied)
	EventBus.status_applied.connect(_on_status_applied)
	EventBus.status_triggered.connect(_on_status_triggered)
	EventBus.ability_triggered.connect(_on_ability_triggered)
	EventBus.deploy_triggered.connect(_on_deploy_triggered)
	EventBus.last_word_triggered.connect(_on_last_word_triggered)
	EventBus.deathblow_triggered.connect(_on_deathblow_triggered)
	EventBus.timer_expired.connect(_on_timer_expired)
	EventBus.game_ended.connect(_on_game_ended)
	EventBus.message_shown.connect(_on_message)
	EventBus.card_detail_requested.connect(show_card_detail)
	EventBus.choice_requested.connect(_on_choice_requested)
	EventBus.ability_panel_requested.connect(_on_ability_panel_requested)
	if detail_activate_button:
		detail_activate_button.pressed.connect(_on_detail_activate_pressed)
	if detail_close_button:
		detail_close_button.pressed.connect(_close_card_detail)
	
	if end_turn_button:
		end_turn_button.pressed.connect(_on_end_turn_pressed)
	if neutral_deck_panel:
		neutral_deck_panel.mouse_filter = Control.MOUSE_FILTER_STOP
		neutral_deck_panel.gui_input.connect(_on_neutral_deck_input)
	if faction_deck_panel_p0:
		faction_deck_panel_p0.mouse_filter = Control.MOUSE_FILTER_STOP
		faction_deck_panel_p0.gui_input.connect(_on_faction_deck_input.bind(0))
	if faction_deck_panel_p1:
		faction_deck_panel_p1.mouse_filter = Control.MOUSE_FILTER_STOP
		faction_deck_panel_p1.gui_input.connect(_on_faction_deck_input.bind(1))
	if graveyard_panel_p0:
		graveyard_panel_p0.mouse_filter = Control.MOUSE_FILTER_STOP
		graveyard_panel_p0.gui_input.connect(_on_graveyard_input.bind(0))
	if graveyard_panel_p1:
		graveyard_panel_p1.mouse_filter = Control.MOUSE_FILTER_STOP
		graveyard_panel_p1.gui_input.connect(_on_graveyard_input.bind(1))
	if board_p0:
		board_p0.row_selected.connect(_on_board_row_selected.bind(0))
		board_p0.target_card_clicked.connect(_on_target_card_clicked)
		board_p0.inspect_card_clicked.connect(_on_board_inspect_card_clicked)
		board_p0.ability_card_clicked.connect(_on_board_ability_card_clicked)
	if board_p1:
		board_p1.row_selected.connect(_on_board_row_selected.bind(1))
		board_p1.target_card_clicked.connect(_on_target_card_clicked)
		board_p1.inspect_card_clicked.connect(_on_board_inspect_card_clicked)
		board_p1.ability_card_clicked.connect(_on_board_ability_card_clicked)
	if hand_p0:
		hand_p0.card_drag_started.connect(_on_hand_card_drag_started)
		hand_p0.card_dropped.connect(_on_hand_card_dropped)
		hand_p0.card_right_clicked.connect(_on_hand_card_right_clicked)
	if hand_p1:
		hand_p1.card_drag_started.connect(_on_hand_card_drag_started)
		hand_p1.card_dropped.connect(_on_hand_card_dropped)
		hand_p1.card_right_clicked.connect(_on_hand_card_right_clicked)


# ── Signal Handlers ──────────────────────────────────────────────────────────

func _on_turn_started(player_id: int, turn_num: int) -> void:
	if turn_label:
		turn_label.text = "Turn %d, %s" % [turn_num, "You" if player_id == 0 else "Opponent"]
	_refresh_all()


func _on_turn_ended(_player_id: int) -> void:
	_refresh_all()


func _on_phase_changed(phase: int, _player_id: int) -> void:
	if phase_label:
		phase_label.text = GameConstants.PHASE_NAMES.get(phase, "Unknown")
		_pulse_label(phase_label, Color(0.45, 0.72, 1.0))
	if phase != GameConstants.TurnPhase.PLAY_CARDS:
		_clear_pending_unit()
	_clear_target_mode()
	_update_active_hand_visibility()
	_update_deck_labels()
	if hand_p0:
		hand_p0.refresh_draggable()
	if hand_p1:
		hand_p1.refresh_draggable()
	if end_turn_button:
		end_turn_button.disabled = (phase != GameConstants.TurnPhase.PLAY_CARDS)
	if phase == GameConstants.TurnPhase.PLAY_CARDS:
		_maybe_run_ai_turn()


func _on_card_selected(card: CardInstance) -> void:
	if not game_state or game_state.game_over:
		return
	if game_state.current_phase != GameConstants.TurnPhase.PLAY_CARDS:
		return

	var player: PlayerState = game_state.get_current_player()
	if not (card in player.hand):
		return

	if not game_state.can_play_card(player, card):
		EventBus.message_shown.emit("Card limit reached (%d/%d)." % [
			player.cards_played_this_turn,
			GameConstants.MAX_CARDS_PER_TURN + player.extra_card_plays
		])
		return

	match card.data.type:
		"Unit", "Artifact":
			_prepare_unit_placement(player, card)
		"Spell":
			_clear_hand_selection()
			if not game_state.play_card(player, card):
				EventBus.message_shown.emit("Could not play %s." % card.data.name)
			_refresh_all()
		_:
			EventBus.message_shown.emit("%s cannot be played." % card.data.type)


func _prepare_unit_placement(player: PlayerState, card: CardInstance) -> void:
	var valid_rows: Array[int] = _get_valid_unit_rows(player)
	if valid_rows.is_empty():
		_clear_hand_selection()
		EventBus.message_shown.emit("No open board row for %s." % card.data.name)
		return
	pending_unit_card = card
	_highlight_active_board_rows(valid_rows)
	EventBus.message_shown.emit("Drag %s to a highlighted row." % card.data.name)


func _get_valid_unit_rows(player: PlayerState) -> Array[int]:
	var valid_rows: Array[int] = []
	for row_idx in range(GameConstants.ROW_CAPACITIES.size()):
		if not player.is_row_full(row_idx):
			valid_rows.append(row_idx)
	return valid_rows


func _on_board_row_selected(row_idx: int, col_idx: int, board_player_id: int) -> void:
	if not pending_unit_card or not game_state or game_state.game_over:
		return

	var player: PlayerState = game_state.get_current_player()
	if board_player_id != player.player_id:
		EventBus.message_shown.emit("Choose a row on the active player's board.")
		return
	if player.is_slot_occupied(row_idx, col_idx):
		EventBus.message_shown.emit("That slot is occupied.")
		return
	if not (pending_unit_card in player.hand):
		_clear_pending_unit()
		EventBus.message_shown.emit("Selected card is no longer playable.")
		return

	var card: CardInstance = pending_unit_card
	_clear_pending_unit()
	_clear_hand_selection()
	if not game_state.play_card(player, card, row_idx, col_idx):
		EventBus.message_shown.emit("Could not play %s." % card.data.name)
	_refresh_all()


func _on_hand_card_drag_started(card: CardInstance) -> void:
	if not game_state or game_state.game_over:
		return
	var player: PlayerState = game_state.get_current_player()
	if not (card in player.hand):
		return
	pending_drag_card = card
	_highlight_graveyard(player)
	if game_state.current_phase != GameConstants.TurnPhase.PLAY_CARDS:
		return
	if not game_state.can_play_card(player, card):
		return
	match card.data.type:
		"Unit", "Artifact":
			_prepare_unit_placement(player, card)
		"Spell":
			_clear_pending_unit()
			_clear_hand_selection()
			if not game_state.play_card(player, card):
				EventBus.message_shown.emit("Could not play %s." % card.data.name)
			pending_drag_card = null
			_clear_graveyard_highlight()
			_refresh_all()


func _on_hand_card_dropped(card: CardInstance, drop_position: Vector2) -> void:
	if not game_state or game_state.game_over:
		return
	pending_drag_card = null
	_clear_graveyard_highlight()
	var player: PlayerState = game_state.get_current_player()

	# Graveyard drop — works regardless of play limit
	if _is_over_graveyard(drop_position, player):
		if card in player.hand:
			_discard_card(player, card)
		_clear_pending_unit()
		_clear_hand_selection()
		return

	if card != pending_unit_card:
		_clear_pending_unit()
		_clear_hand_selection()
		_refresh_all()
		return

	var slot := _get_active_board_slot_at_position(drop_position)
	if slot.row < 0:
		_clear_pending_unit()
		_clear_hand_selection()
		EventBus.message_shown.emit("Drop %s on a highlighted slot." % card.data.name)
		_refresh_all()
		return
	if player.is_slot_occupied(slot.row, slot.col):
		_clear_pending_unit()
		_clear_hand_selection()
		EventBus.message_shown.emit("That slot is occupied.")
		_refresh_all()
		return
	_clear_pending_unit()
	_clear_hand_selection()
	if not game_state.play_card(player, card, slot.row, slot.col):
		EventBus.message_shown.emit("Could not play %s." % card.data.name)
	_refresh_all()


func _get_active_board_slot_at_position(pos: Vector2) -> Dictionary:
	var player: PlayerState = game_state.get_current_player()
	var board := board_p0 if player.player_id == 0 else board_p1
	if not board:
		return {"row": -1, "col": -1}
	return board.get_slot_at_global_position(pos)


func _highlight_active_board_rows(valid_rows: Array[int]) -> void:
	var player: PlayerState = game_state.get_current_player()
	if player.player_id == 0:
		if board_p0:
			board_p0.highlight_valid_rows(valid_rows)
		if board_p1:
			board_p1.clear_highlights()
	else:
		if board_p1:
			board_p1.highlight_valid_rows(valid_rows)
		if board_p0:
			board_p0.clear_highlights()


func _clear_pending_unit() -> void:
	pending_unit_card = null
	if board_p0:
		board_p0.clear_highlights()
	if board_p1:
		board_p1.clear_highlights()


func _clear_hand_selection() -> void:
	if hand_p0:
		hand_p0.clear_selection()
	if hand_p1:
		hand_p1.clear_selection()


func _on_card_played(card: CardInstance, _player_id: int) -> void:
	_log_action("Played: %s" % card.data.name)
	if card.zone == "graveyard":
		_mark_graveyard_recent(card)
	_queue_game_event("Played", card.data.name, _rarity_event_color(card.data.rarity), 0.75)


func _on_card_drawn(card: CardInstance, player_id: int, source: String) -> void:
	_log_action("%s drew %s (%s)" % ["You" if player_id == 0 else "Opponent", card.data.name, source])
	_refresh_all()


func _on_card_discarded(card: CardInstance, player_id: int) -> void:
	_mark_graveyard_recent(card)
	_log_action("%s discarded %s" % ["You" if player_id == 0 else "Opponent", card.data.name])
	_refresh_all()


func _on_card_destroyed(card: CardInstance, _source: CardInstance) -> void:
	if card.zone == "graveyard":
		_mark_graveyard_recent(card)
	_log_action("Destroyed: %s" % card.data.name)
	_queue_game_event("Destroyed", card.data.name, Color(0.95, 0.32, 0.24), 0.9)
	_refresh_all()


func _on_card_banished(card: CardInstance) -> void:
	_log_action("Banished: %s" % card.data.name)
	_queue_game_event("Banished", card.data.name, Color(0.72, 0.58, 1.0), 0.9)
	_refresh_all()


func _on_card_placed_on_board(card: CardInstance, row: int, col: int) -> void:
	_log_action("Board: %s at r%d c%d" % [card.data.name, row + 1, col + 1])
	_refresh_all()


func _on_card_removed_from_board(card: CardInstance) -> void:
	_log_action("Removed: %s" % card.data.name)


func _on_sellary_changed(_player_id: int, _amount: int) -> void:
	_refresh_hud()


func _on_sellary_seized(from_id: int, to_id: int, amount: int) -> void:
	_log_action("%s seized %d from %s" % [
		"You" if to_id == 0 else "Opponent",
		amount,
		"you" if from_id == 0 else "opponent",
	])
	_refresh_hud()


func _on_damage_dealt(target: CardInstance, amount: int, source: CardInstance) -> void:
	var src_name: String = source.data.name if source else "?"
	_log_action("%s dealt %d to %s" % [src_name, amount, target.data.name])
	if amount > 0:
		_queue_game_event("Damage %d" % amount, "%s -> %s" % [src_name, target.data.name], Color(0.95, 0.32, 0.24), 0.65)
	_mark_card_event(target, Color(0.95, 0.32, 0.24))
	_float_card_event(target, "-%d" % amount, Color(1.0, 0.38, 0.32))
	_refresh_all()


func _on_heal_applied(target: CardInstance, amount: int) -> void:
	_log_action("%s healed %d" % [target.data.name, amount])
	if amount > 0:
		_queue_game_event("Heal %d" % amount, target.data.name, Color(0.35, 0.95, 0.62), 0.65)
	_mark_card_event(target, Color(0.35, 0.95, 0.62))
	_float_card_event(target, "+%d" % amount, Color(0.48, 1.0, 0.58))
	_refresh_all()


func _on_boost_applied(target: CardInstance, amount: int) -> void:
	_log_action("%s boosted %d" % [target.data.name, amount])
	if amount > 0:
		_queue_game_event("Boost %d" % amount, target.data.name, Color(0.62, 0.9, 0.38), 0.65)
	_mark_card_event(target, Color(0.62, 0.9, 0.38))
	_float_card_event(target, "+%d" % amount, Color(0.64, 0.95, 0.36))
	_refresh_all()


func _on_status_applied(target: CardInstance, status_name: String, stacks: int) -> void:
	_log_action("%s gained %s %d" % [target.data.name, status_name, stacks])
	_queue_game_event("Status: %s" % status_name, "%s x%d" % [target.data.name, stacks], Color(0.52, 0.72, 1.0), 0.75)
	_mark_card_event(target, Color(0.52, 0.72, 1.0))
	_float_card_event(target, status_name, Color(0.62, 0.78, 1.0))
	_refresh_all()


func _on_status_triggered(target: CardInstance, status_name: String) -> void:
	_log_action("%s triggered on %s" % [status_name, target.data.name])
	_queue_game_event("%s Triggered" % status_name, target.data.name, Color(0.7, 0.95, 0.55), 0.75)
	_mark_card_event(target, Color(0.7, 0.95, 0.55))
	_refresh_all()


func _on_ability_triggered(card: CardInstance, effect: CardEffect) -> void:
	_log_action("%s: %s/%s" % [card.data.name, effect.trigger, effect.type])
	_queue_game_event(_trigger_event_title(effect.trigger), "%s - %s%s" % [
		card.data.name,
		effect.describe(),
		_effect_event_suffix(effect),
	], _event_color(effect.trigger), 1.0)
	_mark_card_event(card, _event_color(effect.trigger))


func _on_deploy_triggered(card: CardInstance) -> void:
	_log_action("Deploy: %s" % card.data.name)
	_mark_card_event(card, _event_color("deploy"))
	_refresh_all()


func _on_last_word_triggered(card: CardInstance) -> void:
	_log_action("Last Word: %s" % card.data.name)
	_queue_game_event("Last Word", card.data.name, Color(0.85, 0.46, 0.95), 0.95)
	_mark_card_event(card, Color(0.85, 0.46, 0.95))
	_refresh_all()


func _on_deathblow_triggered(card: CardInstance, killed: CardInstance) -> void:
	_log_action("Deathblow: %s destroyed %s" % [card.data.name, killed.data.name])
	_queue_game_event("Deathblow", "%s destroyed %s" % [card.data.name, killed.data.name], Color(0.95, 0.32, 0.24), 0.95)
	_mark_card_event(card, Color(0.95, 0.32, 0.24))
	_refresh_all()


func _on_timer_expired(card: CardInstance) -> void:
	_log_action("Timer expired: %s" % card.data.name)
	_queue_game_event("Timer Expired", card.data.name, Color(0.3, 0.78, 0.95), 0.95)
	_mark_card_event(card, Color(0.3, 0.78, 0.95))
	_refresh_all()


func _on_game_ended(winner_id: int) -> void:
	if phase_label:
		phase_label.text = "GAME OVER, %s wins!" % ("You" if winner_id == 0 else "Opponent")
	_log_action("Game over: %s wins" % ("You" if winner_id == 0 else "Opponent"))
	_show_game_over(winner_id)


func _on_message(text: String) -> void:
	print("[Game] %s" % text)
	_log_action(text)


func _pulse_label(label: Label, color: Color) -> void:
	if not label:
		return
	var tween := create_tween()
	label.modulate = color
	tween.tween_property(label, "modulate", Color.WHITE, 0.35)


func _on_end_turn_pressed() -> void:
	if not game_state or game_state.game_over:
		return
	if _is_interaction_locked():
		EventBus.message_shown.emit("Resolve the open prompt first.")
		return
	if game_state.current_phase != GameConstants.TurnPhase.PLAY_CARDS:
		return
	_clear_pending_unit()
	_clear_hand_selection()
	popup_hold_until_ms = Time.get_ticks_msec() + 350
	game_state.end_turn()
	_refresh_all()


# ── Targeting ────────────────────────────────────────────────────────────────

func _on_target_requested(valid_targets: Array, callback: Callable) -> void:
	pending_target_callback = callback
	pending_valid_targets = valid_targets
	if board_p0:
		board_p0.enter_target_mode(valid_targets)
	if board_p1:
		board_p1.enter_target_mode(valid_targets)
	# Highlight hero visuals if they're valid targets
	for hv in [hero_visual_p0, hero_visual_p1]:
		if hv and hv.card_instance in valid_targets:
			hv.mouse_filter = Control.MOUSE_FILTER_STOP
			hv.modulate = Color(1.0, 0.6, 0.2)
		elif hv:
			hv.mouse_filter = Control.MOUSE_FILTER_STOP
	EventBus.message_shown.emit("Select a target.")


func _on_hero_clicked(cv: CardVisual) -> void:
	if pending_target_callback.is_valid():
		if not (cv.card_instance in pending_valid_targets):
			EventBus.message_shown.emit("That hero is not a valid target.")
			return
		var cb: Callable = pending_target_callback
		_clear_target_mode()
		cb.call(cv.card_instance)
		_refresh_all()
		return
	show_card_instance_detail(cv.card_instance)


func _on_target_card_clicked(target: CardInstance) -> void:
	if not pending_target_callback.is_valid():
		return
	var cb: Callable = pending_target_callback
	_clear_target_mode()
	cb.call(target)
	_refresh_all()


func _on_board_ability_card_clicked(card: CardInstance) -> void:
	if not game_state or game_state.game_over:
		return
	if game_state.current_phase != GameConstants.TurnPhase.PLAY_CARDS:
		return
	if game_state.activate_pay(card):
		EventBus.message_shown.emit("Activated Pay: %s." % card.data.name)
		_refresh_all()
	else:
		EventBus.message_shown.emit("%s has no payable Pay ability right now." % card.data.name)


func _on_board_inspect_card_clicked(card: CardInstance) -> void:
	show_card_instance_detail(card)


func _clear_target_mode() -> void:
	pending_target_callback = Callable()
	pending_valid_targets = []
	if board_p0:
		board_p0.exit_target_mode()
	if board_p1:
		board_p1.exit_target_mode()
	for hv in [hero_visual_p0, hero_visual_p1]:
		if hv:
			hv.mouse_filter = Control.MOUSE_FILTER_STOP
			hv.modulate = Color.WHITE


func _mark_card_event(card: CardInstance, color: Color) -> void:
	if not card:
		return
	card.ability_state["ui_flash_color"] = color
	if board_p0:
		board_p0.pulse_card(card, color)
	if board_p1:
		board_p1.pulse_card(card, color)
	if hero_visual_p0 and hero_visual_p0.card_instance == card:
		hero_visual_p0.pulse_event(color)
	if hero_visual_p1 and hero_visual_p1.card_instance == card:
		hero_visual_p1.pulse_event(color)


func _float_card_event(card: CardInstance, text: String, color: Color) -> void:
	if not card:
		return
	card.ability_state["ui_float_text"] = text
	card.ability_state["ui_float_color"] = color


func _event_color(trigger: String) -> Color:
	match trigger:
		"turn_end":
			return Color(0.95, 0.55, 0.22)
		"turn_start", "upkeep", "income":
			return Color(0.35, 0.78, 0.95)
		"deploy":
			return Color(0.45, 0.9, 0.5)
		"order", "pay", "tribute":
			return Color(0.95, 0.82, 0.25)
		"timer":
			return Color(0.4, 0.62, 1.0)
		"last_word", "deathblow":
			return Color(0.95, 0.35, 0.48)
		_:
			return Color(0.86, 0.72, 1.0)


func _trigger_event_title(trigger: String) -> String:
	match trigger:
		"deploy":
			return "Deploy"
		"passive":
			return "Passive"
		"order":
			return "Order"
		"pay":
			return "Pay"
		"tribute":
			return "Tribute"
		"hoard":
			return "Hoard"
		"upkeep":
			return "Upkeep"
		"turn_start":
			return "Start of Turn"
		"turn_end":
			return "End of Turn"
		"timer":
			return "Timer"
		"last_word":
			return "Last Word"
		"deathblow":
			return "Deathblow"
		"spot_67":
			return "Spot 67"
		"counter":
			return "Counter"
		_:
			return trigger.capitalize()


func _effect_event_suffix(effect: CardEffect) -> String:
	var parts: Array[String] = []
	if effect.tribute_cost > 0:
		parts.append("tribute %d" % effect.tribute_cost)
	if effect.pay_cost > 0:
		parts.append("pay %d" % effect.pay_cost)
	if effect.upkeep_cost > 0:
		parts.append("upkeep %d" % effect.upkeep_cost)
	if effect.hoard_threshold > 0:
		parts.append("hoard %d" % effect.hoard_threshold)
	if effect.charges > 0:
		parts.append("%d charge" % effect.charges)
	elif effect.trigger == "order" and effect.max_charges > 0:
		parts.append("1 charge")
	if effect.timer_value > 0:
		parts.append("timer %d" % effect.timer_value)
	if effect.counter_delta != 0:
		parts.append("counter %+d" % effect.counter_delta)
	if parts.is_empty():
		return ""
	return " (%s)" % ", ".join(parts)


func _rarity_event_color(rarity: String) -> Color:
	match rarity:
		"Rare":
			return Color(0.24, 0.56, 0.95)
		"Epic":
			return Color(0.62, 0.35, 0.9)
		"Legendary":
			return Color(0.95, 0.62, 0.18)
		"Hero":
			return Color(0.92, 0.28, 0.22)
		_:
			return Color(0.72, 0.76, 0.84)


func _build_menu_button() -> void:
	var ui := $UI
	var button := Button.new()
	button.name = "MenuButton"
	button.text = "X"
	button.tooltip_text = "Return to main menu"
	button.offset_left = 1848.0
	button.offset_top = 70.0
	button.offset_right = 1898.0
	button.offset_bottom = 108.0
	button.add_theme_font_size_override("font_size", 18)
	button.pressed.connect(func():
		get_tree().change_scene_to_file(MENU_SCENE)
	)
	ui.add_child(button)


func _build_settings_panel() -> void:
	settings_panel = SettingsPanelScript.new()
	settings_panel.name = "GameSettings"
	settings_panel.build(Vector2(1800, 70), true)
	settings_panel.debug_visibility_requested.connect(_set_debug_visible)
	$UI.add_child(settings_panel)


func _build_table_backdrop() -> void:
	var bg := ColorRect.new()
	bg.name = "TableBackdrop"
	bg.color = SettingsManager.color("background")
	bg.offset_left = -320.0
	bg.offset_top = -240.0
	bg.offset_right = 2560.0
	bg.offset_bottom = 1600.0
	bg.z_index = -100
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	move_child(bg, 0)

	var left_rail := Panel.new()
	left_rail.name = "LeftRail"
	left_rail.offset_left = 0.0
	left_rail.offset_top = -40.0
	left_rail.offset_right = 270.0
	left_rail.offset_bottom = 1240.0
	left_rail.z_index = -92
	left_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_rail.add_theme_stylebox_override("panel", _make_panel_style(SettingsManager.color("rail"), SettingsManager.color("border"), 1, 0))
	add_child(left_rail)
	move_child(left_rail, 1)

	var right_rail := Panel.new()
	right_rail.name = "RightRail"
	right_rail.offset_left = 1686.0
	right_rail.offset_top = -40.0
	right_rail.offset_right = 2240.0
	right_rail.offset_bottom = 1240.0
	right_rail.z_index = -92
	right_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_rail.add_theme_stylebox_override("panel", _make_panel_style(SettingsManager.color("rail"), SettingsManager.color("border"), 1, 0))
	add_child(right_rail)
	move_child(right_rail, 1)

	var board_band := Panel.new()
	board_band.name = "BoardBand"
	board_band.offset_left = 270.0
	board_band.offset_top = 176.0
	board_band.offset_right = 1686.0
	board_band.offset_bottom = 846.0
	board_band.z_index = -90
	board_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_band.add_theme_stylebox_override("panel", _make_panel_style(SettingsManager.color("panel_soft"), SettingsManager.color("border"), 1, 4))
	add_child(board_band)
	move_child(board_band, 1)

	for rect in [
		Rect2(286, 194, 1384, 294),
		Rect2(286, 532, 1384, 294),
	]:
		var lane := Panel.new()
		lane.name = "BoardLane"
		lane.offset_left = rect.position.x
		lane.offset_top = rect.position.y
		lane.offset_right = rect.position.x + rect.size.x
		lane.offset_bottom = rect.position.y + rect.size.y
		lane.z_index = -88
		lane.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lane.add_theme_stylebox_override("panel", _make_panel_style(SettingsManager.color("background"), SettingsManager.color("border"), 1, 4))
		add_child(lane)
		move_child(lane, 1)

	for y in [496.0, 508.0]:
		var line := ColorRect.new()
		line.name = "CenterTableLine"
		line.offset_left = 286.0
		line.offset_top = y
		line.offset_right = 1670.0
		line.offset_bottom = y + 1.0
		line.color = Color(0.32, 0.39, 0.52, 0.52)
		line.z_index = -80
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(line)
		move_child(line, 1)


func _apply_ui_theme() -> void:
	var table_bg := get_node_or_null("TableBackdrop") as ColorRect
	if table_bg:
		table_bg.color = SettingsManager.color("background")
	for rail_name in ["LeftRail", "RightRail"]:
		var rail := get_node_or_null(rail_name) as Panel
		if rail:
			rail.add_theme_stylebox_override("panel", _make_panel_style(SettingsManager.color("rail"), SettingsManager.color("border"), 1, 0))
	var board_band := get_node_or_null("BoardBand") as Panel
	if board_band:
		board_band.add_theme_stylebox_override("panel", _make_panel_style(SettingsManager.color("panel_soft"), SettingsManager.color("border"), 1, 4))
	for child in get_children():
		if child is Panel and child.name == "BoardLane":
			child.add_theme_stylebox_override("panel", _make_panel_style(SettingsManager.color("background"), SettingsManager.color("border"), 1, 4))
		elif child is ColorRect and child.name == "CenterTableLine":
			child.color = Color(SettingsManager.color("accent"), 0.42)
	_style_info_panel(neutral_deck_panel)
	_style_info_panel(faction_deck_panel_p0)
	_style_info_panel(faction_deck_panel_p1)
	_style_info_panel(graveyard_panel_p0)
	_style_info_panel(graveyard_panel_p1)
	_style_info_panel(card_detail_popup)
	_style_info_panel(action_log_panel)
	_style_info_panel(debug_panel)
	_style_info_panel(zone_panel)
	_style_info_panel(choice_panel)
	_style_info_panel(ability_panel)
	_style_info_panel(status_panel_top)
	_style_info_panel(status_panel_bottom)
	for button in [end_turn_button]:
		_style_button(button)
	for label in [turn_label, phase_label, sellary_label_p0, sellary_label_p1, hero_hp_p0, hero_hp_p1, message_label]:
		_style_label(label)
	for old_label in [sellary_label_p0, sellary_label_p1, hero_hp_p0, hero_hp_p1]:
		if old_label:
			old_label.visible = false
	if turn_label:
		turn_label.visible = false
		turn_label.offset_left = 24.0
		turn_label.offset_top = 18.0
		turn_label.offset_right = 232.0
		turn_label.offset_bottom = 44.0
	if phase_label:
		phase_label.visible = false
		phase_label.offset_left = 24.0
		phase_label.offset_top = 48.0
		phase_label.offset_right = 232.0
		phase_label.offset_bottom = 74.0
	if message_label:
		message_label.visible = false
		message_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if card_detail_popup:
		card_detail_popup.offset_left = -442.0
		card_detail_popup.offset_top = 124.0
		card_detail_popup.offset_right = -12.0
		card_detail_popup.offset_bottom = 424.0
	if graveyard_panel_p0:
		graveyard_panel_p0.offset_left = 70.0
		graveyard_panel_p0.offset_top = 746.0
		graveyard_panel_p0.offset_right = 250.0
		graveyard_panel_p0.offset_bottom = 826.0
		graveyard_panel_p0.add_theme_stylebox_override("panel", _make_panel_style(SettingsManager.color("panel_soft"), SettingsManager.color("border"), 1, 4))
	for panel in [neutral_deck_panel, faction_deck_panel_p0, faction_deck_panel_p1, graveyard_panel_p0]:
		_decorate_stack_panel(panel)
	if graveyard_panel_p1:
		graveyard_panel_p1.visible = false
	if hero_container_p0:
		hero_container_p0.offset_left = 70.0
		hero_container_p0.offset_top = 924.0
		hero_container_p0.offset_right = 250.0
		hero_container_p0.offset_bottom = 1024.0
	if hero_container_p1:
		hero_container_p1.offset_left = 70.0
		hero_container_p1.offset_top = 64.0
		hero_container_p1.offset_right = 250.0
		hero_container_p1.offset_bottom = 164.0
	if end_turn_button:
		end_turn_button.offset_left = 1696.0
		end_turn_button.offset_top = 562.0
		end_turn_button.offset_right = 1884.0
		end_turn_button.offset_bottom = 614.0
	_style_control_tree($UI)


func _decorate_stack_panel(panel: Control) -> void:
	if not panel or panel.has_meta("stack_decorated"):
		return
	panel.set_meta("stack_decorated", true)
	for i in range(3):
		var card := Panel.new()
		card.name = "StackOffset%d" % i
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.show_behind_parent = true
		card.z_index = -3 + i
		card.anchor_right = 1.0
		card.anchor_bottom = 1.0
		card.offset_left = 5.0 + float(i) * 4.0
		card.offset_top = 5.0 - float(i) * 3.0
		card.offset_right = -7.0 + float(i) * 4.0
		card.offset_bottom = -7.0 - float(i) * 3.0
		card.add_theme_stylebox_override("panel", _make_panel_style(SettingsManager.color("panel_soft"), SettingsManager.color("border"), 1, 4))
		panel.add_child(card)
		panel.move_child(card, 0)


func _play_match_intro() -> void:
	if bool(SettingsManager.get_value("reduced_motion", false)):
		return
	if hand_p0:
		hand_p0.play_deal_intro(false)
	if hand_p1:
		hand_p1.play_deal_intro(true)
	for panel in [neutral_deck_panel, faction_deck_panel_p0, faction_deck_panel_p1]:
		if panel:
			panel.scale = Vector2(0.96, 0.96)
			var tween := create_tween()
			tween.tween_property(panel, "scale", Vector2.ONE, 0.18)


func _style_control_tree(node: Node) -> void:
	if node is Button:
		_style_button(node)
	for child in node.get_children():
		_style_control_tree(child)


func _style_info_panel(node: Control) -> void:
	if not node:
		return
	if node is Panel:
		node.add_theme_stylebox_override("panel", _make_panel_style(SettingsManager.color("panel"), SettingsManager.color("border"), 1, 6))
	elif node is PanelContainer:
		node.add_theme_stylebox_override("panel", _make_panel_style(SettingsManager.color("panel"), SettingsManager.color("border"), 1, 6))


func _style_label(label: Label) -> void:
	if not label:
		return
	label.add_theme_color_override("font_color", SettingsManager.color("text"))
	label.add_theme_font_size_override("font_size", 14)


func _style_button(button: Button) -> void:
	if not button:
		return
	button.add_theme_stylebox_override("normal", _make_panel_style(SettingsManager.color("panel_soft"), SettingsManager.color("border"), 1, 5))
	button.add_theme_stylebox_override("hover", _make_panel_style(SettingsManager.color("panel"), SettingsManager.color("accent"), 1, 5))
	button.add_theme_stylebox_override("pressed", _make_panel_style(SettingsManager.color("rail"), SettingsManager.color("accent"), 1, 5))
	button.add_theme_color_override("font_color", SettingsManager.color("text"))
	_wire_button_motion(button)


func _wire_button_motion(button: Button) -> void:
	if button.has_meta("motion_wired"):
		return
	button.set_meta("motion_wired", true)
	button.mouse_entered.connect(func() -> void:
		_tween_control_scale(button, Vector2(1.025, 1.025), 0.11)
	)
	button.mouse_exited.connect(func() -> void:
		_tween_control_scale(button, Vector2.ONE, 0.14)
	)
	button.button_down.connect(func() -> void:
		_tween_control_scale(button, Vector2(0.985, 0.985), 0.06)
	)
	button.button_up.connect(func() -> void:
		_tween_control_scale(button, Vector2(1.025, 1.025) if button.is_hovered() else Vector2.ONE, 0.12)
	)


func _tween_control_scale(control: Control, target: Vector2, duration: float) -> void:
	if not control:
		return
	control.pivot_offset = control.size * 0.5
	if bool(SettingsManager.get_value("reduced_motion", false)):
		control.scale = target
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", target, duration)


func _pulse_control(control: Control, color: Color = Color(1.0, 0.82, 0.38)) -> void:
	if not control or bool(SettingsManager.get_value("reduced_motion", false)):
		return
	control.pivot_offset = control.size * 0.5
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "scale", Vector2(1.035, 1.035), 0.08)
	tween.parallel().tween_property(control, "modulate", color, 0.08)
	tween.tween_property(control, "scale", Vector2.ONE, 0.16)
	tween.parallel().tween_property(control, "modulate", Color.WHITE, 0.16)


func _make_panel_style(bg: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.shadow_color = Color(0, 0, 0, 0.24)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 3)
	style.content_margin_left = 10
	style.content_margin_top = 8
	style.content_margin_right = 10
	style.content_margin_bottom = 8
	return style


func _hide_overlays(except: Control = null) -> void:
	for panel in [debug_panel, zone_panel, card_detail_popup, choice_panel, ability_panel]:
		if panel and panel != except:
			panel.visible = false
	if settings_panel and settings_panel.panel and settings_panel.panel != except:
		settings_panel.panel.visible = false
	if event_panel and except != event_panel:
		event_panel.visible = false
		event_showing = false
	if not (except == debug_panel or except == card_detail_popup):
		_set_debug_overlay_mode(false)


func _set_debug_overlay_mode(open: bool) -> void:
	for control in [turn_banner_panel, end_turn_button]:
		if control:
			control.visible = not open


func _set_debug_visible(open: bool) -> void:
	if debug_panel:
		if open:
			_hide_overlays(debug_panel)
		debug_panel.visible = open
		_set_debug_overlay_mode(open)
	SettingsManager.set_value("debug_enabled", open)


func _on_setting_changed(key: String, _value: Variant) -> void:
	match key:
		"theme":
			_apply_ui_theme()
		"action_log_enabled", "event_popups_enabled", "ability_popups_enabled", "debug_enabled":
			_apply_settings()


func _apply_settings() -> void:
	if action_log_panel:
		action_log_panel.visible = bool(SettingsManager.get_value("action_log_enabled", true))
	if event_panel and not bool(SettingsManager.get_value("event_popups_enabled", true)):
		event_panel.visible = false
		event_showing = false
		event_queue.clear()
	if ability_panel and not bool(SettingsManager.get_value("ability_popups_enabled", true)):
		ability_panel.visible = false
	if debug_panel:
		var show_debug := bool(SettingsManager.get_value("debug_enabled", false))
		debug_panel.visible = show_debug
		_set_debug_overlay_mode(show_debug)


func _build_turn_banner() -> void:
	var ui := $UI
	turn_banner_panel = PanelContainer.new()
	turn_banner_panel.name = "TurnBanner"
	turn_banner_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	turn_banner_panel.offset_left = 1696.0
	turn_banner_panel.offset_top = 452.0
	turn_banner_panel.offset_right = 1884.0
	turn_banner_panel.offset_bottom = 536.0
	turn_banner_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.06, 0.055, 0.045, 0.96), Color(0.7, 0.52, 0.22), 2, 7))
	ui.add_child(turn_banner_panel)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 1)
	turn_banner_panel.add_child(box)

	turn_banner_player_label = Label.new()
	turn_banner_player_label.text = "Player Turn"
	turn_banner_player_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_banner_player_label.add_theme_font_size_override("font_size", 17)
	turn_banner_player_label.add_theme_color_override("font_color", Color(0.96, 0.82, 0.42))
	box.add_child(turn_banner_player_label)

	turn_banner_phase_label = Label.new()
	turn_banner_phase_label.text = "Phase"
	turn_banner_phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_banner_phase_label.add_theme_font_size_override("font_size", 11)
	turn_banner_phase_label.add_theme_color_override("font_color", Color(0.88, 0.9, 0.94))
	box.add_child(turn_banner_phase_label)

	turn_banner_meta_label = Label.new()
	turn_banner_meta_label.text = "Turn 1"
	turn_banner_meta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	turn_banner_meta_label.add_theme_font_size_override("font_size", 10)
	turn_banner_meta_label.add_theme_color_override("font_color", Color(0.63, 0.68, 0.76))
	box.add_child(turn_banner_meta_label)


func _build_status_panels() -> void:
	var ui := $UI
	status_panel_top = _create_status_panel("BoardStatusPlayer2", Vector2(1668, 12), "P2")
	status_panel_bottom = _create_status_panel("BoardStatusPlayer1", Vector2(1668, 1016), "P1")
	ui.add_child(status_panel_top)
	ui.add_child(status_panel_bottom)


func _build_hero_hp_bar(container: Control, player_id: int) -> void:
	var back := ColorRect.new()
	back.name = "HeroHPBack"
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.offset_left = 0.0
	back.offset_top = 86.0
	back.offset_right = 180.0
	back.offset_bottom = 98.0
	back.color = Color(0.11, 0.035, 0.04, 0.94)
	container.add_child(back)

	var fill := ColorRect.new()
	fill.name = "HeroHPFill"
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill.offset_left = 1.0
	fill.offset_top = 87.0
	fill.offset_right = 179.0
	fill.offset_bottom = 97.0
	fill.color = Color(0.55, 0.88, 0.48, 0.96)
	container.add_child(fill)

	var label := Label.new()
	label.name = "HeroHPText"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.offset_left = 0.0
	label.offset_top = 82.0
	label.offset_right = 180.0
	label.offset_bottom = 100.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))
	container.add_child(label)

	if player_id == 0:
		hero_bar_fill_p0 = fill
		hero_bar_label_p0 = label
	else:
		hero_bar_fill_p1 = fill
		hero_bar_label_p1 = label


func _create_status_panel(panel_name: String, pos: Vector2, label_text: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = panel_name
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.offset_left = pos.x
	panel.offset_top = pos.y
	panel.offset_right = pos.x + 226.0
	panel.offset_bottom = pos.y + 46.0
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.055, 0.062, 0.074, 0.96), Color(0.26, 0.29, 0.34), 1, 7))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4)
	panel.add_child(row)

	var name := Label.new()
	name.text = label_text
	name.custom_minimum_size = Vector2(74, 30)
	name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name.add_theme_font_size_override("font_size", 12)
	name.add_theme_color_override("font_color", Color(0.84, 0.88, 0.95))
	row.add_child(name)

	var sellary := Label.new()
	sellary.text = "Sellary 0"
	sellary.custom_minimum_size = Vector2(58, 30)
	sellary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sellary.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sellary.add_theme_font_size_override("font_size", 14)
	sellary.add_theme_color_override("font_color", Color(0.95, 0.79, 0.32))
	row.add_child(sellary)

	var hp := Label.new()
	hp.text = "H0 C0"
	hp.custom_minimum_size = Vector2(76, 30)
	hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp.add_theme_font_size_override("font_size", 12)
	hp.add_theme_color_override("font_color", Color(0.68, 0.92, 0.78))
	row.add_child(hp)

	if label_text == "P2":
		top_name_label = name
		top_sellary_label = sellary
		top_hp_label = hp
	else:
		bottom_name_label = name
		bottom_sellary_label = sellary
		bottom_hp_label = hp
	return panel


func _build_event_panel() -> void:
	var ui := $UI
	event_panel = PanelContainer.new()
	event_panel.name = "GameEventBanner"
	event_panel.visible = false
	event_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	event_panel.offset_left = 610.0
	event_panel.offset_top = 472.0
	event_panel.offset_right = 1310.0
	event_panel.offset_bottom = 560.0
	event_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.055, 0.064, 0.085, 0.96), Color(0.95, 0.75, 0.28), 2, 8))
	ui.add_child(event_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	event_panel.add_child(box)

	event_title_label = Label.new()
	event_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	event_title_label.add_theme_font_size_override("font_size", 20)
	event_title_label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.35))
	box.add_child(event_title_label)

	event_detail_label = Label.new()
	event_detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	event_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	event_detail_label.add_theme_font_size_override("font_size", 14)
	event_detail_label.add_theme_color_override("font_color", Color(0.88, 0.91, 0.96))
	box.add_child(event_detail_label)


func _build_ability_panel() -> void:
	var ui := $UI
	ability_panel = PanelContainer.new()
	ability_panel.name = "AbilityPanel"
	ability_panel.visible = false
	ability_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	ability_panel.offset_left = 620.0
	ability_panel.offset_top = 300.0
	ability_panel.offset_right = 1300.0
	ability_panel.offset_bottom = 760.0
	ability_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.064, 0.074, 0.098, 0.98), Color(0.5, 0.58, 0.75), 1, 8))
	ui.add_child(ability_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	ability_panel.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	box.add_child(header)

	ability_title_label = Label.new()
	ability_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ability_title_label.add_theme_font_size_override("font_size", 20)
	ability_title_label.add_theme_color_override("font_color", Color(0.95, 0.82, 0.38))
	header.add_child(ability_title_label)

	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(80, 34)
	close.pressed.connect(func() -> void:
		ability_panel.visible = false
	)
	header.add_child(close)
	_style_button(close)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(640, 372)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)

	ability_items = VBoxContainer.new()
	ability_items.add_theme_constant_override("separation", 8)
	scroll.add_child(ability_items)


func _on_ability_panel_requested(title: String, items: Array) -> void:
	if not bool(SettingsManager.get_value("ability_popups_enabled", true)):
		_log_action("%s: %d item(s)" % [title, items.size()])
		return
	_show_ability_panel(title, items)


func _show_ability_panel(title: String, items: Array) -> void:
	if not ability_panel or not ability_items:
		return
	_hide_overlays(ability_panel)
	ability_title_label.text = title
	for child in ability_items.get_children():
		child.queue_free()
	if items.is_empty():
		var empty := Label.new()
		empty.text = "No cards to show."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_color_override("font_color", Color(0.78, 0.82, 0.9))
		ability_items.add_child(empty)
	else:
		for item in items:
			ability_items.add_child(_ability_item_control(item))
	ability_panel.visible = true
	if bool(SettingsManager.get_value("reduced_motion", false)):
		ability_panel.modulate.a = 1.0
		ability_panel.scale = Vector2.ONE
		return
	ability_panel.modulate.a = 0.0
	ability_panel.scale = Vector2(0.985, 0.985)
	var tween := create_tween()
	tween.tween_property(ability_panel, "modulate:a", 1.0, 0.12)
	tween.parallel().tween_property(ability_panel, "scale", Vector2.ONE, 0.12)


func _ability_item_control(item) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 58)
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.085, 0.098, 0.13, 1.0), Color(0.26, 0.31, 0.42), 1, 6))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)

	var badge := ColorRect.new()
	badge.custom_minimum_size = Vector2(8, 42)
	badge.color = Color(0.55, 0.65, 0.88)
	row.add_child(badge)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 2)
	row.add_child(text_box)

	var title := Label.new()
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(0.91, 0.94, 0.98))
	text_box.add_child(title)

	var detail := Label.new()
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_font_size_override("font_size", 12)
	detail.add_theme_color_override("font_color", Color(0.68, 0.73, 0.82))
	text_box.add_child(detail)

	if item is CardInstance:
		var card: CardInstance = item
		title.text = card.data.name
		detail.text = "%s · %s · %s" % [card.data.type, card.data.rarity, ", ".join(card.data.factions)]
		badge.color = _rarity_event_color(card.data.rarity)
		panel.mouse_filter = Control.MOUSE_FILTER_STOP
		panel.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				show_card_instance_detail(card)
		)
	elif item is CardData:
		var data: CardData = item
		title.text = data.name
		detail.text = "%s · %s · %s" % [data.type, data.rarity, ", ".join(data.factions)]
		badge.color = _rarity_event_color(data.rarity)
	elif item is Dictionary:
		title.text = str(item.get("title", item.get("label", "Result")))
		detail.text = str(item.get("detail", item.get("description", "")))
		if item.has("color") and item["color"] is Color:
			badge.color = item["color"]
	else:
		title.text = str(item)
		detail.text = ""
	return panel


func _queue_game_event(title: String, detail: String, color: Color, duration: float = 0.85) -> void:
	if not event_panel or not bool(SettingsManager.get_value("event_popups_enabled", true)):
		return
	event_queue.append({
		"title": title,
		"detail": detail,
		"color": color,
		"duration": duration,
	})
	while event_queue.size() > 8:
		event_queue.pop_front()
	if not event_showing:
		_show_next_game_event()


func _show_next_game_event() -> void:
	if event_showing or event_queue.is_empty() or not event_panel:
		return
	var wait_ms := popup_hold_until_ms - Time.get_ticks_msec()
	if wait_ms > 0:
		if not event_hold_timer_active:
			event_hold_timer_active = true
			get_tree().create_timer(float(wait_ms) / 1000.0).timeout.connect(func() -> void:
				event_hold_timer_active = false
				_show_next_game_event()
			)
		return
	event_showing = true
	var event: Dictionary = event_queue.pop_front()
	var color: Color = event.get("color", Color(0.95, 0.82, 0.35))
	var duration: float = float(event.get("duration", 0.85))
	event_title_label.text = str(event.get("title", "Event"))
	event_title_label.add_theme_color_override("font_color", color)
	event_detail_label.text = str(event.get("detail", ""))
	var style := event_panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	if style:
		style.border_color = color
		event_panel.add_theme_stylebox_override("panel", style)
	event_panel.visible = true
	if bool(SettingsManager.get_value("reduced_motion", false)):
		event_panel.modulate.a = 1.0
		event_panel.scale = Vector2.ONE
		await get_tree().create_timer(duration * 0.6).timeout
		event_panel.visible = false
		event_showing = false
		_show_next_game_event()
		return
	event_panel.modulate.a = 0.0
	event_panel.scale = Vector2(0.985, 0.985)
	var tween := create_tween()
	tween.tween_property(event_panel, "modulate:a", 1.0, 0.08)
	tween.parallel().tween_property(event_panel, "scale", Vector2.ONE, 0.08)
	tween.tween_interval(duration)
	tween.tween_property(event_panel, "modulate:a", 0.0, 0.16)
	tween.tween_callback(func() -> void:
		event_panel.visible = false
		event_showing = false
		_show_next_game_event()
	)


func _build_game_over_panel() -> void:
	var ui := $UI
	game_over_panel = PanelContainer.new()
	game_over_panel.name = "GameOverPanel"
	game_over_panel.visible = false
	game_over_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	game_over_panel.set_anchors_preset(Control.PRESET_CENTER)
	game_over_panel.offset_left = -310.0
	game_over_panel.offset_top = -190.0
	game_over_panel.offset_right = 310.0
	game_over_panel.offset_bottom = 190.0
	game_over_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.07, 0.08, 0.11, 0.98), Color(0.85, 0.65, 0.25), 2, 8))
	ui.add_child(game_over_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	game_over_panel.add_child(box)

	game_over_title = Label.new()
	game_over_title.text = "Game Over"
	game_over_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_title.add_theme_font_size_override("font_size", 34)
	game_over_title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.38))
	box.add_child(game_over_title)

	game_over_summary = Label.new()
	game_over_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game_over_summary.add_theme_font_size_override("font_size", 17)
	box.add_child(game_over_summary)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)

	var rematch := Button.new()
	rematch.text = "Rematch"
	rematch.custom_minimum_size = Vector2(140, 42)
	rematch.pressed.connect(func():
		get_tree().change_scene_to_file("res://scenes/main/main.tscn")
	)
	buttons.add_child(rematch)

	var menu := Button.new()
	menu.text = "Main Menu"
	menu.custom_minimum_size = Vector2(140, 42)
	menu.pressed.connect(func():
		get_tree().change_scene_to_file(MENU_SCENE)
	)
	buttons.add_child(menu)

	_style_control_tree(game_over_panel)


func _show_game_over(winner_id: int) -> void:
	_hide_overlays()
	game_over_panel.visible = true
	var winner_text := "Draw" if winner_id < 0 else "%s wins" % ("You" if winner_id == 0 else "Opponent")
	game_over_title.text = winner_text
	var p0_hp := game_state.players[0].hero.current_power if game_state.players[0].hero else 0
	var p1_hp := game_state.players[1].hero.current_power if game_state.players[1].hero else 0
	game_over_summary.text = "Final hero health\nYou: %d\nOpponent: %d" % [p0_hp, p1_hp]
	game_over_panel.pivot_offset = game_over_panel.size * 0.5
	game_over_panel.scale = Vector2(0.96, 0.96)
	game_over_panel.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(game_over_panel, "scale", Vector2.ONE, 0.14)
	tween.parallel().tween_property(game_over_panel, "modulate:a", 1.0, 0.14)


# ── Debug Sandbox / Action Log ───────────────────────────────────────────────

func _build_action_log() -> void:
	var ui := $UI
	action_log_panel = PanelContainer.new()
	action_log_panel.name = "ActionLog"
	action_log_panel.offset_left = 8.0
	action_log_panel.offset_top = 168.0
	action_log_panel.offset_right = 252.0
	action_log_panel.offset_bottom = 318.0
	action_log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(action_log_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	action_log_panel.add_child(box)

	var title := Label.new()
	title.text = "Action Log"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 13)
	box.add_child(title)

	action_log_text = RichTextLabel.new()
	action_log_text.custom_minimum_size = Vector2(220, 118)
	action_log_text.fit_content = false
	action_log_text.scroll_active = true
	action_log_text.bbcode_enabled = false
	action_log_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(action_log_text)


func _build_debug_panel() -> void:
	var ui := $UI
	var toggle := Button.new()
	debug_toggle_button = toggle
	toggle.name = "DebugToggleButton"
	toggle.text = "Debug"
	toggle.visible = false
	toggle.offset_left = 1676.0
	toggle.offset_top = 70.0
	toggle.offset_right = 1832.0
	toggle.offset_bottom = 108.0
	toggle.pressed.connect(func():
		if debug_panel:
			_hide_overlays(debug_panel)
			debug_panel.visible = not debug_panel.visible
			_set_debug_overlay_mode(debug_panel.visible)
	)
	ui.add_child(toggle)

	debug_panel = PanelContainer.new()
	debug_panel.name = "DebugSandbox"
	debug_panel.visible = false
	debug_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	debug_panel.offset_left = 1478.0
	debug_panel.offset_top = 124.0
	debug_panel.offset_right = 1908.0
	debug_panel.offset_bottom = 752.0
	ui.add_child(debug_panel)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(410, 608)
	debug_panel.add_child(scroll)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)

	var title := Label.new()
	title.text = "Debug Sandbox"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	box.add_child(title)

	debug_card_id = LineEdit.new()
	debug_card_id.placeholder_text = "card id, empty uses detailed card"
	box.add_child(debug_card_id)

	var selectors := HBoxContainer.new()
	selectors.add_theme_constant_override("separation", 8)
	box.add_child(selectors)

	debug_player_select = OptionButton.new()
	debug_player_select.add_item("You", 0)
	debug_player_select.add_item("Opponent", 1)
	selectors.add_child(debug_player_select)

	debug_zone_select = OptionButton.new()
	debug_zone_select.add_item("Hand", 0)
	debug_zone_select.add_item("Board", 1)
	debug_zone_select.add_item("Graveyard", 2)
	selectors.add_child(debug_zone_select)

	var slot_row := HBoxContainer.new()
	slot_row.add_theme_constant_override("separation", 6)
	box.add_child(slot_row)
	slot_row.add_child(_debug_label("Row"))
	debug_row_spin = _debug_spin(0, 2, 0)
	slot_row.add_child(debug_row_spin)
	slot_row.add_child(_debug_label("Col"))
	debug_col_spin = _debug_spin(0, 4, 0)
	slot_row.add_child(debug_col_spin)

	var spawn_grid := GridContainer.new()
	spawn_grid.columns = 3
	spawn_grid.add_theme_constant_override("h_separation", 6)
	spawn_grid.add_theme_constant_override("v_separation", 6)
	box.add_child(spawn_grid)
	_debug_button(spawn_grid, "Spawn", _debug_spawn_selected_zone)
	_debug_button(spawn_grid, "+5 Sellary", _debug_add_sellary)
	_debug_button(spawn_grid, "Draw Egg", _debug_draw_egg)

	var state_title := Label.new()
	state_title.text = "Set State (-1 leaves unchanged)"
	state_title.add_theme_font_size_override("font_size", 12)
	box.add_child(state_title)

	var state_grid := GridContainer.new()
	state_grid.columns = 4
	state_grid.add_theme_constant_override("h_separation", 6)
	state_grid.add_theme_constant_override("v_separation", 6)
	box.add_child(state_grid)
	state_grid.add_child(_debug_label("Power"))
	debug_power_spin = _debug_spin(-1, 99, -1)
	state_grid.add_child(debug_power_spin)
	state_grid.add_child(_debug_label("Counter"))
	debug_counter_spin = _debug_spin(-1, 99, -1)
	state_grid.add_child(debug_counter_spin)
	state_grid.add_child(_debug_label("Timer"))
	debug_timer_spin = _debug_spin(-1, 99, -1)
	state_grid.add_child(debug_timer_spin)
	state_grid.add_child(_debug_label("Charges"))
	debug_charges_spin = _debug_spin(-1, 99, -1)
	state_grid.add_child(debug_charges_spin)
	_debug_button(box, "Apply State To Card", _debug_apply_state)

	var trigger_grid := GridContainer.new()
	trigger_grid.columns = 3
	trigger_grid.add_theme_constant_override("h_separation", 6)
	trigger_grid.add_theme_constant_override("v_separation", 6)
	box.add_child(trigger_grid)
	for trigger in ["deploy", "passive", "order", "pay", "turn_start", "turn_end", "timer"]:
		var trigger_name: String = str(trigger)
		_debug_button(trigger_grid, trigger_name.capitalize(), Callable(self, "_debug_run_trigger").bind(trigger_name))

	var turn_grid := GridContainer.new()
	turn_grid.columns = 2
	turn_grid.add_theme_constant_override("h_separation", 6)
	turn_grid.add_theme_constant_override("v_separation", 6)
	box.add_child(turn_grid)
	_debug_button(turn_grid, "Start Effects", _debug_force_start_effects)
	_debug_button(turn_grid, "End Effects", _debug_force_end_effects)
	_debug_button(turn_grid, "Refresh", _refresh_all)
	_debug_button(turn_grid, "Clear Log", _debug_clear_log)

	var win_grid := GridContainer.new()
	win_grid.columns = 3
	win_grid.add_theme_constant_override("h_separation", 6)
	win_grid.add_theme_constant_override("v_separation", 6)
	box.add_child(win_grid)
	_debug_button(win_grid, "Win You", Callable(self, "_debug_force_game_over").bind(0))
	_debug_button(win_grid, "Win Opp.", Callable(self, "_debug_force_game_over").bind(1))
	_debug_button(win_grid, "Draw", Callable(self, "_debug_force_game_over").bind(-1))

	var test_title := Label.new()
	test_title.text = "Automation"
	test_title.add_theme_font_size_override("font_size", 12)
	box.add_child(test_title)

	var automation_grid := GridContainer.new()
	automation_grid.columns = 2
	automation_grid.add_theme_constant_override("h_separation", 6)
	automation_grid.add_theme_constant_override("v_separation", 6)
	box.add_child(automation_grid)
	ai_toggle_button = _debug_button(automation_grid, "AI: Off", _debug_toggle_ai)
	_debug_button(automation_grid, "AI Step", _debug_ai_step)
	_debug_button(automation_grid, "Run Audit", _debug_run_card_audit)
	_debug_button(automation_grid, "Sound -", Callable(self, "_debug_adjust_sound").bind(-0.1))
	sound_toggle_button = _debug_button(automation_grid, "Sound: On", _debug_toggle_sound)
	_debug_button(automation_grid, "Sound +", Callable(self, "_debug_adjust_sound").bind(0.1))


func _debug_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(58, 28)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _debug_spin(min_value: float, max_value: float, value: float) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = 1
	spin.value = value
	spin.custom_minimum_size = Vector2(72, 34)
	return spin


func _debug_button(parent: Control, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 34)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _log_action(text: String) -> void:
	if text.strip_edges() == "":
		return
	action_log_lines.append(text)
	while action_log_lines.size() > 18:
		action_log_lines.pop_front()
	if action_log_text:
		action_log_text.text = "\n".join(action_log_lines)
		action_log_text.scroll_to_line(maxi(action_log_lines.size() - 1, 0))


func _debug_clear_log() -> void:
	action_log_lines.clear()
	if action_log_text:
		action_log_text.text = ""


func _debug_get_player() -> PlayerState:
	if not game_state or game_state.players.is_empty():
		return null
	var idx := debug_player_select.get_selected_id() if debug_player_select else 0
	idx = clampi(idx, 0, game_state.players.size() - 1)
	return game_state.players[idx]


func _debug_current_card_id() -> String:
	var card_id := debug_card_id.text.strip_edges() if debug_card_id else ""
	if card_id == "" and _detail_card_visual and is_instance_valid(_detail_card_visual) and _detail_card_visual.card_instance:
		card_id = _detail_card_visual.card_instance.data.id
	return card_id


func _debug_spawn_selected_zone() -> void:
	if not debug_zone_select:
		return
	match debug_zone_select.get_selected_id():
		0:
			_debug_spawn_card("hand")
		1:
			_debug_spawn_card("board")
		_:
			_debug_spawn_card("graveyard")


func _debug_spawn_card(zone: String) -> void:
	var player := _debug_get_player()
	var card_id := _debug_current_card_id()
	if not player or card_id == "":
		EventBus.message_shown.emit("Debug: choose a player and card id.")
		return
	var data := CardDatabase.get_card(card_id)
	if not data:
		EventBus.message_shown.emit("Debug: unknown card id %s." % card_id)
		return
	var card := CardInstance.create(data, player.player_id)
	match zone:
		"hand":
			player.add_to_hand(card)
			EventBus.card_drawn.emit(card, player.player_id, "debug")
		"graveyard":
			card.move_to_zone("graveyard")
			player.graveyard.append(card)
			EventBus.card_discarded.emit(card, player.player_id)
		"board":
			if not data.type in ["Unit", "Artifact"]:
				EventBus.message_shown.emit("Debug: only units/artifacts can spawn on board.")
				return
			var row_idx := int(debug_row_spin.value)
			var col_idx := int(debug_col_spin.value)
			if not player.place_on_board(card, row_idx, col_idx):
				EventBus.message_shown.emit("Debug: slot r%d c%d is unavailable." % [row_idx + 1, col_idx + 1])
				return
			EventBus.card_placed_on_board.emit(card, row_idx, col_idx)
			for effect in card.data.effects:
				if effect.trigger in ["deploy", "passive"]:
					EventBus.ability_triggered.emit(card, effect)
	EventBus.message_shown.emit("Debug spawned %s to %s." % [data.name, zone])
	_refresh_all()


func _debug_add_sellary() -> void:
	var player := _debug_get_player()
	if not player:
		return
	player.gain_sellary(5)
	EventBus.message_shown.emit("Debug: %s gained 5 sellary." % ["You" if player.player_id == 0 else "Opponent"])
	_refresh_all()


func _debug_draw_egg() -> void:
	var player := _debug_get_player()
	if not player:
		return
	var data := CardDatabase.get_card("egg")
	if not data:
		EventBus.message_shown.emit("Debug: Egg card missing.")
		return
	var card := CardInstance.create(data, player.player_id)
	player.add_to_hand(card)
	EventBus.card_drawn.emit(card, player.player_id, "debug")
	_refresh_all()


func _debug_find_card() -> CardInstance:
	var player := _debug_get_player()
	var card_id := _debug_current_card_id()
	if not player or card_id == "":
		return null
	if player.hero and player.hero.data.id == card_id:
		return player.hero
	for card in player.get_all_board_units():
		if card.data.id == card_id:
			return card
	for card in player.hand:
		if card.data.id == card_id:
			return card
	for card in player.graveyard:
		if card.data.id == card_id:
			return card
	return null


func _debug_apply_state() -> void:
	var card := _debug_find_card()
	if not card:
		EventBus.message_shown.emit("Debug: card not found.")
		return
	if debug_power_spin.value >= 0:
		card.current_power = int(debug_power_spin.value)
	if debug_counter_spin.value >= 0:
		card.counter = int(debug_counter_spin.value)
	if debug_timer_spin.value >= 0:
		card.timer = int(debug_timer_spin.value)
	if debug_charges_spin.value >= 0:
		card.charges = int(debug_charges_spin.value)
		card.max_charges = maxi(card.max_charges, card.charges)
	EventBus.message_shown.emit("Debug state applied to %s." % card.data.name)
	_refresh_all()


func _debug_run_trigger(trigger: String) -> void:
	var card := _debug_find_card()
	if not card:
		EventBus.message_shown.emit("Debug: card not found.")
		return
	var count := 0
	for effect in card.data.effects:
		if effect.trigger == trigger:
			EventBus.ability_triggered.emit(card, effect)
			count += 1
	if count == 0:
		EventBus.message_shown.emit("Debug: %s has no %s effects." % [card.data.name, trigger])
	else:
		EventBus.message_shown.emit("Debug ran %d %s effect(s) on %s." % [count, trigger, card.data.name])
	_refresh_all()


func _debug_force_start_effects() -> void:
	var player := _debug_get_player()
	if not player:
		return
	game_state._trigger_start_of_turn(player)
	EventBus.message_shown.emit("Debug: ran %s start effects." % ["your" if player.player_id == 0 else "opponent"])
	_refresh_all()


func _debug_force_end_effects() -> void:
	var player := _debug_get_player()
	if not player:
		return
	game_state._trigger_end_of_turn(player)
	EventBus.message_shown.emit("Debug: ran %s end effects." % ["your" if player.player_id == 0 else "opponent"])
	_refresh_all()


func _debug_force_game_over(winner_id: int) -> void:
	if not game_state:
		return
	game_state.force_game_over(winner_id)


func _debug_toggle_ai() -> void:
	ai_enabled = not ai_enabled
	if ai_toggle_button:
		ai_toggle_button.text = "AI: On" if ai_enabled else "AI: Off"
	EventBus.message_shown.emit("AI opponent %s." % ("enabled" if ai_enabled else "disabled"))
	if ai_enabled:
		_maybe_run_ai_turn()


func _debug_ai_step() -> void:
	if not game_state or game_state.game_over:
		return
	_run_ai_turn()


func _debug_toggle_sound() -> void:
	if AudioManager:
		AudioManager.toggle_enabled()
	_update_sound_button()


func _debug_adjust_sound(delta: float) -> void:
	if AudioManager:
		AudioManager.adjust_sfx_volume(delta)
	_update_sound_button()


func _update_sound_button() -> void:
	if not sound_toggle_button or not AudioManager:
		return
	var pct := int(round(AudioManager.sfx_volume * 100.0))
	sound_toggle_button.text = "Sound: %s %d%%" % ["On" if AudioManager.enabled else "Off", pct]


func _debug_run_card_audit() -> void:
	var runner: RefCounted = CardTestRunnerScript.new()
	var report: Dictionary = runner.run_all()
	var lines: PackedStringArray = report.get("lines", PackedStringArray())
	_show_text_report("Card Audit", lines)
	EventBus.message_shown.emit("Card audit: %d pass, %d warning, %d fail." % [
		report.get("passed", 0),
		report.get("warnings", 0),
		report.get("failed", 0),
	])


func _maybe_run_ai_turn() -> void:
	if not ai_enabled or ai_running or not game_state or game_state.game_over:
		return
	var player := game_state.get_current_player()
	if player and player.player_id == 1:
		call_deferred("_run_ai_turn")


func _run_ai_turn() -> void:
	if ai_running or not game_state or game_state.game_over:
		return
	var player := game_state.get_current_player()
	if not player:
		return
	ai_running = true
	_log_action("AI: planning opponent turn" if player.player_id == 1 else "AI: planning your turn")
	await _ai_try_draw(player)
	await _ai_play_cards(player)
	await _ai_activate_board(player)
	if game_state and not game_state.game_over and game_state.get_current_player() == player:
		game_state.end_turn()
		_log_action("AI: ended turn")
	_refresh_all()
	ai_running = false
	_maybe_run_ai_turn()


func _ai_try_draw(player: PlayerState) -> void:
	if player.hand.size() < 5 and player.sellary >= player.get_faction_draw_cost():
		if game_state.draw_faction(player):
			_refresh_all()
			await get_tree().create_timer(0.18).timeout
	if player.hand.size() < 6 and player.sellary >= player.get_neutral_draw_cost():
		if game_state.draw_neutral(player):
			_refresh_all()
			await get_tree().create_timer(0.18).timeout


func _ai_play_cards(player: PlayerState) -> void:
	var played_any := true
	while played_any and game_state and game_state.can_play_card(player, _ai_first_hand_card(player)):
		played_any = false
		for card in player.hand.duplicate():
			if not _ai_can_play_card_safely(player, card):
				continue
			var slot := _ai_find_slot(player) if card.data.type in ["Unit", "Artifact"] else {"row": -1, "col": -1}
			var ok := false
			if card.data.type in ["Unit", "Artifact"]:
				ok = game_state.play_card(player, card, int(slot["row"]), int(slot["col"]))
			elif card.data.type == "Spell":
				ok = game_state.play_card(player, card)
			if ok:
				played_any = true
				_refresh_all()
				await get_tree().create_timer(0.22).timeout
				break


func _ai_activate_board(player: PlayerState) -> void:
	for card in player.get_all_board_units().duplicate():
		if game_state.game_over:
			return
		if _ai_can_activate(card, "order") and game_state.activate_order(card):
			_refresh_all()
			await get_tree().create_timer(0.18).timeout
		if _ai_can_activate(card, "pay") and game_state.activate_pay(card):
			_refresh_all()
			await get_tree().create_timer(0.18).timeout


func _ai_first_hand_card(player: PlayerState) -> CardInstance:
	return player.hand[0] if player and not player.hand.is_empty() else null


func _ai_can_play_card_safely(player: PlayerState, card: CardInstance) -> bool:
	if not card or not game_state.can_play_card(player, card):
		return false
	if card.data.type in ["Unit", "Artifact"] and _ai_find_slot(player).is_empty():
		return false
	if not card.data.type in ["Unit", "Artifact", "Spell"]:
		return false
	for effect in card.data.effects:
		if card.data.type == "Spell" or effect.trigger in ["deploy", "passive", "tribute"]:
			if _ai_effect_needs_manual_input(effect):
				return false
	return true


func _ai_can_activate(card: CardInstance, trigger: String) -> bool:
	for effect in card.data.effects:
		if effect.trigger == trigger and _ai_effect_needs_manual_input(effect):
			return false
	return true


func _ai_effect_needs_manual_input(effect: CardEffect) -> bool:
	if effect.trigger == "tribute":
		return true
	if effect.needs_target():
		return true
	if effect.type == "complex":
		return true
	return false


func _ai_find_slot(player: PlayerState) -> Dictionary:
	for row_idx in range(GameConstants.ROW_CAPACITIES.size()):
		for col_idx in range(GameConstants.ROW_CAPACITIES[row_idx]):
			if not player.is_slot_occupied(row_idx, col_idx):
				return {"row": row_idx, "col": col_idx}
	return {}


# ── Zone Viewer ──────────────────────────────────────────────────────────────

func _build_zone_panel() -> void:
	var ui := $UI
	zone_panel = PanelContainer.new()
	zone_panel.name = "ZoneViewer"
	zone_panel.visible = false
	zone_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	zone_panel.offset_left = 520.0
	zone_panel.offset_top = 150.0
	zone_panel.offset_right = 1400.0
	zone_panel.offset_bottom = 900.0
	ui.add_child(zone_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	zone_panel.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	box.add_child(header)

	zone_title = Label.new()
	zone_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zone_title.add_theme_font_size_override("font_size", 15)
	header.add_child(zone_title)

	zone_close_button = Button.new()
	zone_close_button.text = "Close"
	zone_close_button.custom_minimum_size = Vector2(70, 30)
	zone_close_button.pressed.connect(func():
		zone_panel.visible = false
	)
	header.add_child(zone_close_button)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(850, 688)
	box.add_child(scroll)

	zone_list = VBoxContainer.new()
	zone_list.add_theme_constant_override("separation", 4)
	scroll.add_child(zone_list)


func _show_card_zone(title: String, cards: Array) -> void:
	if not zone_panel or not zone_list:
		return
	_hide_overlays(zone_panel)
	zone_title.text = title
	for child in zone_list.get_children():
		child.queue_free()
	if cards.is_empty():
		var empty := Label.new()
		empty.text = "Empty"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		zone_list.add_child(empty)
	else:
		for i in range(cards.size()):
			var card: CardInstance = cards[i]
			var button := Button.new()
			button.text = "%02d  %s  [%s]" % [i + 1, card.data.name, card.data.rarity]
			button.alignment = HORIZONTAL_ALIGNMENT_LEFT
			button.custom_minimum_size = Vector2(0, 30)
			button.pressed.connect(Callable(self, "show_card_instance_detail").bind(card))
			zone_list.add_child(button)
	zone_panel.visible = true


func _show_card_zone_randomized(title: String, cards: Array) -> void:
	var preview := cards.duplicate()
	preview.shuffle()
	_show_card_zone("%s (randomized preview)" % title, preview)


func _shared_graveyard_cards() -> Array:
	var cards: Array = []
	if not game_state:
		return cards
	for player in game_state.players:
		for card in player.graveyard:
			if card is CardInstance:
				_ensure_graveyard_sequence(card)
				cards.append(card)
	cards.sort_custom(func(a: CardInstance, b: CardInstance) -> bool:
		return int(a.ability_state.get("ui_grave_seq", 0)) > int(b.ability_state.get("ui_grave_seq", 0))
	)
	return cards


func _mark_graveyard_recent(card: CardInstance) -> void:
	if not card:
		return
	_graveyard_sequence += 1
	card.ability_state["ui_grave_seq"] = _graveyard_sequence


func _ensure_graveyard_sequence(card: CardInstance) -> void:
	if not card or card.ability_state.has("ui_grave_seq"):
		return
	_graveyard_sequence += 1
	card.ability_state["ui_grave_seq"] = _graveyard_sequence


func _show_text_report(title: String, lines: PackedStringArray) -> void:
	if not zone_panel or not zone_list:
		return
	_hide_overlays(zone_panel)
	zone_title.text = title
	for child in zone_list.get_children():
		child.queue_free()
	if lines.is_empty():
		var empty := Label.new()
		empty.text = "No report lines."
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.custom_minimum_size = Vector2(820, 28)
		zone_list.add_child(empty)
	else:
		var report := RichTextLabel.new()
		report.custom_minimum_size = Vector2(820, 650)
		report.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		report.size_flags_vertical = Control.SIZE_EXPAND_FILL
		report.bbcode_enabled = true
		report.fit_content = false
		report.scroll_active = true
		report.add_theme_font_size_override("normal_font_size", 13)
		var formatted: Array[String] = []
		for line in lines:
			var escaped := str(line).replace("[", "\\[").replace("]", "\\]")
			if line.begins_with("FAIL"):
				formatted.append("[color=#ff746b]%s[/color]" % escaped)
			elif line.begins_with("WARN"):
				formatted.append("[color=#ffd45a]%s[/color]" % escaped)
			else:
				formatted.append("[color=#dbe4f2]%s[/color]" % escaped)
		report.text = "\n".join(formatted)
		zone_list.add_child(report)
	zone_panel.visible = true


# ── Choices ─────────────────────────────────────────────────────────────────

func _build_choice_panel() -> void:
	var ui := $UI
	choice_panel = PanelContainer.new()
	choice_panel.name = "ChoicePanel"
	choice_panel.visible = false
	choice_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	choice_panel.offset_left = 650.0
	choice_panel.offset_top = 326.0
	choice_panel.offset_right = 1270.0
	choice_panel.offset_bottom = 752.0
	choice_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.064, 0.074, 0.098, 0.98), Color(0.95, 0.75, 0.28), 1, 8))
	ui.add_child(choice_panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	choice_panel.add_child(box)

	choice_title = Label.new()
	choice_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	choice_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	choice_title.add_theme_font_size_override("font_size", 20)
	choice_title.add_theme_color_override("font_color", Color(0.95, 0.82, 0.38))
	box.add_child(choice_title)

	choice_options = VBoxContainer.new()
	choice_options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice_options.add_theme_constant_override("separation", 8)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(580, 318)
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(choice_options)
	box.add_child(scroll)


func _on_choice_requested(prompt: String, options: Array, callback: Callable) -> void:
	if not choice_panel or not choice_options:
		return
	var wait_ms := popup_hold_until_ms - Time.get_ticks_msec()
	if wait_ms > 0:
		await get_tree().create_timer(float(wait_ms) / 1000.0).timeout
	_hide_overlays(choice_panel)
	for child in choice_options.get_children():
		child.queue_free()
	choice_title.text = prompt
	for option in options:
		var label: String = ""
		var value = option
		var detail := ""
		if option is Dictionary:
			label = str(option.get("label", option.get("name", "Option")))
			value = option.get("value", option)
			detail = str(option.get("detail", option.get("description", "")))
		else:
			label = str(option)
		var button := _ability_choice_button(label, detail)
		button.pressed.connect(func():
			choice_panel.visible = false
			callback.call(value)
			_refresh_all()
		)
		choice_options.add_child(button)
	choice_panel.visible = true
	_refresh_all()


func _ability_choice_button(title: String, detail: String = "") -> Button:
	var button := Button.new()
	button.text = title if detail == "" else "%s\n%s" % [title, detail]
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(560, 54 if detail != "" else 42)
	button.add_theme_font_size_override("font_size", 14)
	_style_button(button)
	return button


# ── Draw / Discard ───────────────────────────────────────────────────────────

func _discard_card(player: PlayerState, card: CardInstance) -> void:
	player.remove_from_hand(card)
	card.move_to_zone("graveyard")
	player.graveyard.append(card)
	EventBus.card_discarded.emit(card, player.player_id)
	EventBus.message_shown.emit("Discarded %s." % card.data.name)
	_refresh_all()


func _is_over_graveyard(pos: Vector2, _player: PlayerState) -> bool:
	var panel: Panel = graveyard_panel_p0
	if not panel:
		return false
	var rect: Rect2 = Rect2(panel.global_position, panel.size)
	return rect.has_point(pos)


func _highlight_graveyard(_player: PlayerState) -> void:
	if graveyard_panel_p0:
		graveyard_panel_p0.add_theme_stylebox_override("panel", _make_panel_style(Color(0.18, 0.075, 0.07, 0.96), Color(0.96, 0.36, 0.28), 2, 4))


func _clear_graveyard_highlight() -> void:
	if graveyard_panel_p0:
		graveyard_panel_p0.modulate = Color.WHITE
		graveyard_panel_p0.add_theme_stylebox_override("panel", _make_panel_style(Color(0.05, 0.055, 0.066, 0.82), Color(0.18, 0.2, 0.24), 1, 4))
	if graveyard_panel_p1:
		graveyard_panel_p1.modulate = Color.WHITE


func _on_hand_card_right_clicked(_card: CardInstance) -> void:
	show_card_instance_detail(_card)


func _on_neutral_deck_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	if not (event as InputEventMouseButton).pressed:
		return
	if not game_state or game_state.game_over:
		return
	if _is_interaction_locked():
		EventBus.message_shown.emit("Resolve the open prompt first.")
		return
	if (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		_show_card_zone_randomized("Neutral Deck", game_state.neutral_deck)
		return
	if (event as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
		return
	if game_state.current_phase != GameConstants.TurnPhase.PLAY_CARDS:
		_show_card_zone_randomized("Neutral Deck", game_state.neutral_deck)
		return
	var player: PlayerState = game_state.get_current_player()
	var cost: int = player.get_neutral_draw_cost()
	var card: CardInstance = game_state.draw_neutral(player)
	if not card:
		if player.sellary < cost:
			EventBus.message_shown.emit("Need %d sellary to draw neutral (have %d)." % [cost, player.sellary])
		else:
			EventBus.message_shown.emit("Neutral deck is empty.")
	_update_deck_labels()
	_refresh_all()


func _on_faction_deck_input(event: InputEvent, player_id: int) -> void:
	if not event is InputEventMouseButton:
		return
	if not (event as InputEventMouseButton).pressed:
		return
	if not game_state or game_state.game_over:
		return
	if _is_interaction_locked():
		EventBus.message_shown.emit("Resolve the open prompt first.")
		return
	if (event as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT:
		_show_card_zone_randomized("Player %d Faction Deck" % (player_id + 1), game_state.players[player_id].faction_deck)
		return
	if (event as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
		return
	if game_state.current_phase != GameConstants.TurnPhase.PLAY_CARDS:
		_show_card_zone_randomized("Player %d Faction Deck" % (player_id + 1), game_state.players[player_id].faction_deck)
		return
	var player: PlayerState = game_state.get_current_player()
	if player.player_id != player_id:
		EventBus.message_shown.emit("Not your faction deck.")
		return
	var cost: int = player.get_faction_draw_cost()
	var card: CardInstance = game_state.draw_faction(player)
	if not card:
		if player.sellary < cost:
			EventBus.message_shown.emit("Need %d sellary to draw faction (have %d)." % [cost, player.sellary])
		else:
			EventBus.message_shown.emit("Faction deck is empty.")
		_update_deck_labels()
	_refresh_all()


func _on_graveyard_input(event: InputEvent, _player_id: int) -> void:
	if not event is InputEventMouseButton:
		return
	if not (event as InputEventMouseButton).pressed:
		return
	if (event as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
		return
	if not game_state:
		return
	_show_card_zone("Shared Graveyard, newest first", _shared_graveyard_cards())


func _update_deck_labels() -> void:
	if not game_state:
		return
	var player: PlayerState = game_state.get_current_player()
	var nc: int = player.get_neutral_draw_cost()
	var fc: int = player.get_faction_draw_cost()
	if neutral_deck_label:
		neutral_deck_label.text = "Neutral\n(%d cards)\nCost: %d" % [game_state.neutral_deck.size(), nc]
	if faction_deck_label_p0:
		var p0: PlayerState = game_state.players[0]
		faction_deck_label_p0.text = "P1 Faction\n%d cards\nCost %d" % [p0.faction_deck.size(), p0.get_faction_draw_cost()]
	if faction_deck_label_p1:
		var p1: PlayerState = game_state.players[1]
		faction_deck_label_p1.text = "P2 Faction\n%d cards\nCost %d" % [p1.faction_deck.size(), p1.get_faction_draw_cost()]


func _update_graveyard_labels() -> void:
	if not game_state or game_state.players.size() < 2:
		return
	var total := game_state.players[0].graveyard.size() + game_state.players[1].graveyard.size()
	if graveyard_label_p0:
		graveyard_label_p0.text = "Shared Grave\n%d cards" % total
	if graveyard_label_p1:
		graveyard_label_p1.text = "Shared Grave\n%d cards" % total


# ── Refresh ──────────────────────────────────────────────────────────────────

func _can_play_card(card: CardInstance) -> bool:
	if not game_state or game_state.game_over:
		return false
	if _is_interaction_locked():
		return false
	var current: PlayerState = game_state.get_current_player()
	# card must belong to the active player and be playable
	var owner: PlayerState = null
	for p in game_state.players:
		if card in p.hand:
			owner = p
			break
	if not owner or owner.player_id != current.player_id:
		return false
	return game_state.can_play_card(current, card) and card.data.type in ["Unit", "Spell", "Artifact"]


func _is_interaction_locked() -> bool:
	if pending_target_callback.is_valid():
		return true
	if choice_panel and choice_panel.visible:
		return true
	if ability_panel and ability_panel.visible:
		return true
	return false


func _refresh_all() -> void:
	# Board refresh frees all CardVisual nodes — clear stale detail ref
	if _detail_card_visual and not is_instance_valid(_detail_card_visual):
		_detail_card_visual = null
	if board_p0:
		board_p0.refresh()
	if board_p1:
		board_p1.refresh()
	if hand_p0:
		hand_p0.refresh()
	if hand_p1:
		hand_p1.refresh()
	if hero_visual_p0:
		hero_visual_p0.refresh_display()
	if hero_visual_p1:
		hero_visual_p1.refresh_display()
	_update_active_hand_visibility()
	_update_deck_labels()
	_update_graveyard_labels()
	_refresh_hud()


func _update_active_hand_visibility() -> void:
	if not game_state or game_state.players.size() < 2:
		return
	var active_id: int = game_state.get_current_player().player_id
	if hand_p0:
		hand_p0.visible = true
	if hand_p1:
		hand_p1.visible = true
	if graveyard_panel_p0:
		graveyard_panel_p0.visible = true
	if graveyard_panel_p1:
		graveyard_panel_p1.visible = false


func _refresh_hud() -> void:
	if game_state.players.size() < 2:
		return
	var p0: PlayerState = game_state.players[0]
	var p1: PlayerState = game_state.players[1]
	var active_id: int = game_state.get_current_player().player_id
	var phase_text: String = GameConstants.PHASE_NAMES.get(game_state.current_phase, "Unknown")
	
	if sellary_label_p0:
		sellary_label_p0.text = "Sellary: %d" % p0.sellary
	if sellary_label_p1:
		sellary_label_p1.text = "Sellary: %d" % p1.sellary
	if hero_hp_p0 and p0.hero:
		hero_hp_p0.text = "Hero: %d" % p0.hero.current_power
	if hero_hp_p1 and p1.hero:
		hero_hp_p1.text = "Hero: %d" % p1.hero.current_power
	if turn_banner_player_label:
		turn_banner_player_label.text = "PLAYER %d ACTIVE" % (active_id + 1)
		turn_banner_player_label.add_theme_color_override("font_color", Color(0.96, 0.82, 0.42) if active_id == 0 else Color(0.86, 0.62, 0.52))
	if turn_banner_phase_label:
		turn_banner_phase_label.text = phase_text
	if turn_banner_meta_label:
		turn_banner_meta_label.text = "Turn %d | Cards played %d/%d" % [
			game_state.turn_number,
			game_state.get_current_player().cards_played_this_turn,
			GameConstants.MAX_CARDS_PER_TURN + game_state.get_current_player().extra_card_plays,
		]
	_style_turn_banner(active_id)
	var banner_key := "%d:%d:%d" % [active_id, game_state.current_phase, game_state.turn_number]
	if banner_key != _last_turn_banner_key:
		_last_turn_banner_key = banner_key
		_pulse_control(turn_banner_panel, SettingsManager.color("accent"))
	if bottom_name_label:
		bottom_name_label.text = "P1 ACTIVE" if active_id == 0 else "P1"
	if bottom_sellary_label:
		bottom_sellary_label.text = "$%d" % p0.sellary
	if bottom_hp_label and p0.hero:
		bottom_hp_label.text = "H%d C%d" % [
			p0.hero.current_power,
			p0.hand.size(),
		]
	if top_name_label:
		top_name_label.text = "P2 ACTIVE" if active_id == 1 else "P2"
	if top_sellary_label:
		top_sellary_label.text = "$%d" % p1.sellary
	if top_hp_label and p1.hero:
		top_hp_label.text = "H%d C%d" % [
			p1.hero.current_power,
			p1.hand.size(),
		]
	_refresh_hero_bar(0, p0)
	_refresh_hero_bar(1, p1)
	_style_status_panel(status_panel_bottom, active_id == 0)
	_style_status_panel(status_panel_top, active_id == 1)
	if end_turn_button:
		end_turn_button.disabled = game_state.current_phase != GameConstants.TurnPhase.PLAY_CARDS or _is_interaction_locked()


func _refresh_hero_bar(player_id: int, player: PlayerState) -> void:
	if not player or not player.hero:
		return
	var fill := hero_bar_fill_p0 if player_id == 0 else hero_bar_fill_p1
	var label := hero_bar_label_p0 if player_id == 0 else hero_bar_label_p1
	var max_hp: float = maxf(float(player.hero.data.base_power), 1.0)
	var pct: float = clampf(float(player.hero.current_power) / max_hp, 0.0, 1.0)
	if fill:
		var target_right := 1.0 + 178.0 * pct
		if pct <= 0.3:
			fill.color = Color(0.92, 0.28, 0.22, 0.96)
		elif pct <= 0.6:
			fill.color = Color(0.95, 0.68, 0.25, 0.96)
		else:
			fill.color = Color(0.46, 0.86, 0.48, 0.96)
		var previous_pct: float = float(fill.get_meta("last_pct", pct))
		fill.set_meta("last_pct", pct)
		if bool(SettingsManager.get_value("reduced_motion", false)) or absf(previous_pct - pct) < 0.001:
			fill.offset_right = target_right
		else:
			var tween := create_tween()
			tween.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
			tween.tween_property(fill, "offset_right", target_right, 0.18)
			_pulse_control(label, fill.color)
	if label:
		label.text = "HP %d/%d" % [player.hero.current_power, int(max_hp)]


func _style_status_panel(panel: PanelContainer, active: bool) -> void:
	if not panel:
		return
	var bg := SettingsManager.color("panel") if active else SettingsManager.color("panel_soft")
	var border := SettingsManager.color("accent") if active else SettingsManager.color("border")
	panel.add_theme_stylebox_override("panel", _make_panel_style(bg, border, 2 if active else 1, 7))
	var was_active := bool(panel.get_meta("active_state", active))
	panel.set_meta("active_state", active)
	if active and not was_active:
		_pulse_control(panel, SettingsManager.color("accent"))


func _style_turn_banner(active_id: int) -> void:
	if not turn_banner_panel:
		return
	var border := Color(0.96, 0.74, 0.28) if active_id == 0 else Color(0.78, 0.42, 0.34)
	var bg := SettingsManager.color("panel")
	border = SettingsManager.color("accent") if active_id == 0 else SettingsManager.color("border").lightened(0.18)
	turn_banner_panel.add_theme_stylebox_override("panel", _make_panel_style(bg, border, 1, 5))


# ── Card Detail Popup ────────────────────────────────────────────────────────

func show_card_detail(cv: CardVisual) -> void:
	if not card_detail_popup or not cv.card_instance:
		return

	# Clear previous highlight without triggering popup_hide cleanup
	if _detail_card_visual and is_instance_valid(_detail_card_visual):
		_detail_card_visual.set_detail_highlighted(false)
	_detail_card_visual = cv
	_detail_card_instance = cv.card_instance
	cv.set_detail_highlighted(true)
	show_card_instance_detail(cv.card_instance)


func show_card_instance_detail(inst: CardInstance) -> void:
	if not card_detail_popup or not inst:
		return
	_hide_overlays(card_detail_popup)
	_detail_card_instance = inst
	var data: CardData = inst.data

	detail_name.text = data.name
	detail_meta.text = "%s · %s · %s" % [data.type, data.rarity, ", ".join(data.factions)]

	detail_power.visible = true
	detail_power.text = _format_detail_state(inst)

	if data.has_ability and data.ability_text != "":
		detail_ability.visible = true
		detail_ability.text = "%s\n\n%s" % [_format_effect_summary(inst), CardDatabase.resolve_ability_text(data.ability_text)]
	else:
		var summary := _format_effect_summary(inst)
		detail_ability.visible = summary != ""
		detail_ability.text = summary

	_update_detail_activate_button(inst)
	card_detail_popup.visible = true
	_set_debug_overlay_mode(true)


func _update_detail_activate_button(inst: CardInstance) -> void:
	if not detail_activate_button:
		return
	detail_activate_button.visible = false
	detail_activate_button.disabled = true
	if not game_state or game_state.game_over:
		return
	if game_state.current_phase != GameConstants.TurnPhase.PLAY_CARDS:
		return
	var player := game_state.get_current_player()
	if inst.controller_id != player.player_id or not (inst in player.get_all_board_units()):
		return
	var pay_cost := _first_trigger_sellary_cost(inst, "pay")
	if pay_cost >= 0:
		detail_activate_button.text = "Activate Pay%s" % (" (%d)" % pay_cost if pay_cost > 0 else "")
		detail_activate_button.visible = true
		detail_activate_button.disabled = pay_cost > player.sellary
		return
	if _has_trigger(inst, "order"):
		detail_activate_button.text = "Activate Order"
		detail_activate_button.visible = true
		detail_activate_button.disabled = false


func _first_trigger_sellary_cost(inst: CardInstance, trigger: String) -> int:
	for effect in inst.data.effects:
		if effect.trigger == trigger:
			return effect.pay_cost
	return -1


func _has_trigger(inst: CardInstance, trigger: String) -> bool:
	for effect in inst.data.effects:
		if effect.trigger == trigger:
			return true
	return false


func _on_detail_activate_pressed() -> void:
	var inst := _detail_card_instance
	if not inst or not game_state or game_state.game_over:
		return
	if game_state.activate_pay(inst):
		EventBus.message_shown.emit("Activated Pay: %s." % inst.data.name)
	elif game_state.activate_order(inst):
		EventBus.message_shown.emit("Activated Order: %s." % inst.data.name)
	else:
		EventBus.message_shown.emit("%s has no activatable ability right now." % inst.data.name)
	_refresh_all()
	if card_detail_popup and card_detail_popup.visible and inst:
		show_card_instance_detail(inst)


func _format_detail_state(inst: CardInstance) -> String:
	var parts: Array[String] = []
	if inst.data.type in ["Unit", "Hero"]:
		parts.append("Power %d/%d" % [inst.current_power, inst.data.base_power])
	if inst.timer > 0:
		parts.append("Timer %d" % inst.timer)
	if inst.counter > 0:
		parts.append("Counter %d" % inst.counter)
	if inst.max_charges > 0 or inst.charges > 0:
		parts.append("Charges %d/%d" % [inst.charges, inst.max_charges])
	if inst.block > 0:
		parts.append("Block %d" % inst.block)
	if not inst.statuses.is_empty():
		var statuses: Array[String] = []
		var keys: Array = inst.statuses.keys()
		keys.sort()
		for status_name in keys:
			var label := "%s %d" % [status_name, inst.statuses[status_name]]
			if inst.permanent_statuses.get(status_name, false):
				label += " permanent"
			statuses.append(label)
		parts.append("Statuses: %s" % ", ".join(statuses))
	return "\n".join(parts) if not parts.is_empty() else "No live state"


func _format_effect_summary(inst: CardInstance) -> String:
	if inst.data.effects.is_empty():
		return ""
	var lines: Array[String] = ["Events:"]
	for effect in inst.data.effects:
		lines.append("- %s: %s" % [effect.trigger, effect.describe()])
	return "\n".join(lines)


func _close_card_detail() -> void:
	if _detail_card_visual and is_instance_valid(_detail_card_visual):
		_detail_card_visual.set_detail_highlighted(false)
	_detail_card_visual = null
	_detail_card_instance = null
	card_detail_popup.visible = false
	_set_debug_overlay_mode(false)
