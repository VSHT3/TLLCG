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
@onready var hero_container_p0: Control = $UI/HUD/HeroP0
@onready var hero_container_p1: Control = $UI/HUD/HeroP1
var hero_visual_p0: CardVisual = null
var hero_visual_p1: CardVisual = null
@onready var effect_resolver: EffectResolver = $EffectResolver
@onready var card_detail_popup: PanelContainer = $UI/CardDetailPopup
@onready var detail_name: Label = $UI/CardDetailPopup/VBox/DetailName
@onready var detail_meta: Label = $UI/CardDetailPopup/VBox/DetailMeta
@onready var detail_power: Label = $UI/CardDetailPopup/VBox/DetailPower
@onready var detail_ability: RichTextLabel = $UI/CardDetailPopup/VBox/DetailAbility
@onready var detail_close_button: Button = $UI/CardDetailPopup/VBox/CloseButton

# ── Game State ───────────────────────────────────────────────────────────────

var game_state: GameState = null
var pending_unit_card: CardInstance = null
var pending_drag_card: CardInstance = null
var pending_target_callback: Callable = Callable()
var _detail_card_visual: CardVisual = null


# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
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
			hero_visual_p0 = card_scene.instantiate()
			hero_container_p0.add_child(hero_visual_p0)
			hero_visual_p0.setup(game_state.players[0].hero)
			hero_visual_p0.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hero_visual_p0.clicked.connect(_on_hero_clicked)
		if hero_container_p1 and game_state.players[1].hero:
			hero_visual_p1 = card_scene.instantiate()
			hero_container_p1.add_child(hero_visual_p1)
			hero_visual_p1.setup(game_state.players[1].hero)
			hero_visual_p1.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hero_visual_p1.clicked.connect(_on_hero_clicked)

	# Start first turn
	game_state.start_turn()
	_refresh_all()


func _connect_signals() -> void:
	EventBus.turn_started.connect(_on_turn_started)
	EventBus.turn_ended.connect(_on_turn_ended)
	EventBus.phase_changed.connect(_on_phase_changed)
	EventBus.target_requested.connect(_on_target_requested)
	EventBus.card_played.connect(_on_card_played)
	EventBus.card_selected.connect(_on_card_selected)
	EventBus.card_drawn.connect(_on_card_drawn)
	EventBus.card_destroyed.connect(_on_card_destroyed)
	EventBus.sellary_gained.connect(_on_sellary_changed)
	EventBus.sellary_spent.connect(_on_sellary_changed)
	EventBus.damage_dealt.connect(_on_damage_dealt)
	EventBus.game_ended.connect(_on_game_ended)
	EventBus.message_shown.connect(_on_message)
	EventBus.card_detail_requested.connect(show_card_detail)
	if detail_close_button:
		detail_close_button.pressed.connect(_close_card_detail)
	
	if end_turn_button:
		end_turn_button.pressed.connect(_on_end_turn_pressed)
	if neutral_deck_panel:
		neutral_deck_panel.gui_input.connect(_on_neutral_deck_input)
	if faction_deck_panel_p0:
		faction_deck_panel_p0.gui_input.connect(_on_faction_deck_input.bind(0))
	if faction_deck_panel_p1:
		faction_deck_panel_p1.gui_input.connect(_on_faction_deck_input.bind(1))
	if board_p0:
		board_p0.row_selected.connect(_on_board_row_selected.bind(0))
		board_p0.target_card_clicked.connect(_on_target_card_clicked)
	if board_p1:
		board_p1.row_selected.connect(_on_board_row_selected.bind(1))
		board_p1.target_card_clicked.connect(_on_target_card_clicked)
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
		turn_label.text = "Turn %d — Player %d" % [turn_num, player_id + 1]
	_refresh_all()


func _on_turn_ended(_player_id: int) -> void:
	_refresh_all()


func _on_phase_changed(phase: int, _player_id: int) -> void:
	if phase_label:
		phase_label.text = GameConstants.PHASE_NAMES.get(phase, "Unknown")
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
	print("[Main] Card played: %s" % card.data.name)


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
	if message_label:
		message_label.text = text


func _on_end_turn_pressed() -> void:
	if not game_state or game_state.game_over:
		return
	if game_state.current_phase != GameConstants.TurnPhase.PLAY_CARDS:
		return
	_clear_pending_unit()
	_clear_hand_selection()
	game_state.end_turn()
	_refresh_all()


# ── Targeting ────────────────────────────────────────────────────────────────

func _on_target_requested(valid_targets: Array, callback: Callable) -> void:
	pending_target_callback = callback
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
			hv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	EventBus.message_shown.emit("Select a target.")


func _on_hero_clicked(cv: CardVisual) -> void:
	if not pending_target_callback.is_valid():
		return
	if cv.modulate != Color(1.0, 0.6, 0.2):
		return
	var cb: Callable = pending_target_callback
	_clear_target_mode()
	cb.call(cv.card_instance)
	_refresh_all()


func _on_target_card_clicked(target: CardInstance) -> void:
	if not pending_target_callback.is_valid():
		return
	var cb: Callable = pending_target_callback
	_clear_target_mode()
	cb.call(target)
	_refresh_all()


func _clear_target_mode() -> void:
	pending_target_callback = Callable()
	if board_p0:
		board_p0.exit_target_mode()
	if board_p1:
		board_p1.exit_target_mode()
	for hv in [hero_visual_p0, hero_visual_p1]:
		if hv:
			hv.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hv.modulate = Color.WHITE


# ── Draw / Discard ───────────────────────────────────────────────────────────

func _discard_card(player: PlayerState, card: CardInstance) -> void:
	player.remove_from_hand(card)
	card.move_to_zone("graveyard")
	player.graveyard.append(card)
	EventBus.card_discarded.emit(card, player.player_id)
	EventBus.message_shown.emit("Discarded %s." % card.data.name)
	_refresh_all()


func _is_over_graveyard(pos: Vector2, player: PlayerState) -> bool:
	var panel: Panel = graveyard_panel_p0 if player.player_id == 0 else graveyard_panel_p1
	if not panel:
		return false
	var rect: Rect2 = Rect2(panel.global_position, panel.size)
	return rect.has_point(pos)


func _highlight_graveyard(player: PlayerState) -> void:
	var panel: Panel = graveyard_panel_p0 if player.player_id == 0 else graveyard_panel_p1
	if panel:
		panel.modulate = Color(1.0, 0.4, 0.4)


func _clear_graveyard_highlight() -> void:
	if graveyard_panel_p0:
		graveyard_panel_p0.modulate = Color.WHITE
	if graveyard_panel_p1:
		graveyard_panel_p1.modulate = Color.WHITE


func _on_hand_card_right_clicked(_card: CardInstance) -> void:
	pass  # Right-click opens detail popup via card_detail_requested (handled in card_visual.gd)


func _on_neutral_deck_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	if not (event as InputEventMouseButton).pressed:
		return
	if not game_state or game_state.game_over:
		return
	if game_state.current_phase != GameConstants.TurnPhase.PLAY_CARDS:
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
	if game_state.current_phase != GameConstants.TurnPhase.PLAY_CARDS:
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
		faction_deck_label_p0.text = "Faction\n(%d cards)\nCost: %d" % [p0.faction_deck.size(), p0.get_faction_draw_cost()]
	if faction_deck_label_p1:
		var p1: PlayerState = game_state.players[1]
		faction_deck_label_p1.text = "Faction\n(%d cards)\nCost: %d" % [p1.faction_deck.size(), p1.get_faction_draw_cost()]


# ── Refresh ──────────────────────────────────────────────────────────────────

func _can_play_card(card: CardInstance) -> bool:
	if not game_state or game_state.game_over:
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
	_refresh_hud()


func _update_active_hand_visibility() -> void:
	if not game_state or game_state.players.size() < 2:
		return
	var active_id: int = game_state.get_current_player().player_id
	if hand_p0:
		hand_p0.visible = active_id == 0
	if hand_p1:
		hand_p1.visible = active_id == 1


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


# ── Card Detail Popup ────────────────────────────────────────────────────────

func show_card_detail(cv: CardVisual) -> void:
	if not card_detail_popup or not cv.card_instance:
		return

	# Clear previous highlight without triggering popup_hide cleanup
	if _detail_card_visual and is_instance_valid(_detail_card_visual):
		_detail_card_visual.set_detail_highlighted(false)
	_detail_card_visual = cv
	cv.set_detail_highlighted(true)

	var inst: CardInstance = cv.card_instance
	var data: CardData = inst.data

	detail_name.text = data.name
	detail_meta.text = "%s · %s · %s" % [data.type, data.rarity, ", ".join(data.factions)]

	if data.type in ["Unit", "Hero"]:
		detail_power.visible = true
		detail_power.text = "Power: %d / %d" % [inst.current_power, data.base_power]
	else:
		detail_power.visible = false

	if data.has_ability and data.ability_text != "":
		detail_ability.visible = true
		detail_ability.text = CardDatabase.resolve_ability_text(data.ability_text)
	else:
		detail_ability.visible = false
		detail_ability.text = ""

	card_detail_popup.visible = true


func _close_card_detail() -> void:
	if _detail_card_visual and is_instance_valid(_detail_card_visual):
		_detail_card_visual.set_detail_highlighted(false)
	_detail_card_visual = null
	card_detail_popup.visible = false
