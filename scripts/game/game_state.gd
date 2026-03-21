## GameState
## Central game state manager. Owns all player states and the neutral deck.
## Orchestrates turn flow and delegates to EffectResolver for abilities.
class_name GameState
extends RefCounted

# ── State ────────────────────────────────────────────────────────────────────

var players: Array[PlayerState] = []
var neutral_deck: Array[CardInstance] = []
var current_player_idx: int = 0
var turn_number: int = 0
var current_phase: int = GameConstants.TurnPhase.SELLARY
var game_over: bool = false
var winner_id: int = -1


# ── Setup ────────────────────────────────────────────────────────────────────

func setup_game(faction_choices: Array[String]) -> void:
	"""Initialize the game with chosen factions. faction_choices[i] = faction for player i."""
	# Build neutral deck
	_build_neutral_deck()
	
	# Create players
	for i in range(faction_choices.size()):
		var ps: PlayerState = PlayerState.create(i, faction_choices[i])
		players.append(ps)
	
	# Initial draw: 5 neutral + 3 faction per player (reverse order of first pick)
	for i in range(players.size() - 1, -1, -1):
		_draw_neutral_cards(i, 5)
		_draw_faction_cards(i, 3)
	
	turn_number = 1
	current_player_idx = 0
	EventBus.game_started.emit(_get_player_ids())


func _build_neutral_deck() -> void:
	var neutral_cards: Array[CardData] = CardDatabase.get_neutral_cards()
	for card_data in neutral_cards:
		if card_data.type == "Hero":
			continue  # Skip neutral heroes if any
		# Create one instance of each neutral card
		var inst: CardInstance = CardInstance.create(card_data, -1)  # -1 = no owner yet
		neutral_deck.append(inst)
	neutral_deck.shuffle()


func _get_player_ids() -> Array:
	var ids: Array[int] = []
	for p in players:
		ids.append(p.player_id)
	return ids


# ── Turn Flow ────────────────────────────────────────────────────────────────

func get_current_player() -> PlayerState:
	return players[current_player_idx]


func start_turn() -> void:
	var player: PlayerState = get_current_player()
	player.reset_turn_state()
	EventBus.turn_started.emit(player.player_id, turn_number)
	
	# Phase 1: Sellary
	_set_phase(GameConstants.TurnPhase.SELLARY)
	player.gain_sellary(player.base_sellary)
	
	# Phase 2: Start-of-turn abilities
	_set_phase(GameConstants.TurnPhase.START_OF_TURN)
	_trigger_start_of_turn(player)
	
	# Phase 3: Play cards (interactive — handled by UI)
	_set_phase(GameConstants.TurnPhase.PLAY_CARDS)


func end_play_phase() -> void:
	"""Called when player finishes playing cards. Continues to discard/draw."""
	_set_phase(GameConstants.TurnPhase.DISCARD_CARDS)
	# Discard phase is interactive — UI handles it
	# After discard, call end_discard_phase()


func end_discard_phase() -> void:
	_set_phase(GameConstants.TurnPhase.DRAW_CARDS)
	# Draw phase is interactive — UI handles it
	# After draw, call end_draw_phase()


func end_draw_phase() -> void:
	var player: PlayerState = get_current_player()
	
	# Phase 6: End-of-turn abilities
	_set_phase(GameConstants.TurnPhase.END_OF_TURN)
	_trigger_end_of_turn(player)
	
	# Phase 7: Status trigger
	_set_phase(GameConstants.TurnPhase.STATUS_TRIGGER)
	_trigger_statuses(player)
	
	# Phase 8: Status diminish
	_set_phase(GameConstants.TurnPhase.STATUS_DIMINISH)
	_diminish_statuses(player)
	
	# Enforce hand limit
	var discarded: Array[CardInstance] = player.enforce_hand_limit()
	for card in discarded:
		EventBus.card_discarded.emit(card, player.player_id)
	
	# End turn
	EventBus.turn_ended.emit(player.player_id)
	
	# Check win condition
	if _check_game_over():
		return
	
	# Next player
	_advance_turn()


func _set_phase(phase: int) -> void:
	current_phase = phase
	EventBus.phase_changed.emit(phase, get_current_player().player_id)


func _advance_turn() -> void:
	current_player_idx = (current_player_idx + 1) % players.size()
	if current_player_idx == 0:
		turn_number += 1
	start_turn()


# ── Card Playing ─────────────────────────────────────────────────────────────

func can_play_card(player: PlayerState, _card: CardInstance) -> bool:
	"""Check if a player can play a card from hand."""
	if player.cards_played_this_turn >= GameConstants.MAX_CARDS_PER_TURN:
		return false
	if current_phase != GameConstants.TurnPhase.PLAY_CARDS:
		return false
	return true


func play_card(player: PlayerState, card: CardInstance, row_idx: int = -1) -> bool:
	"""Play a card from hand. row_idx needed for Units. Returns success."""
	if not can_play_card(player, card):
		return false
	
	# Remove from hand
	if not player.remove_from_hand(card):
		return false
	
	player.cards_played_this_turn += 1
	
	match card.data.type:
		"Unit":
			if row_idx < 0:
				return false
			if player.is_board_full():
				# Goes to graveyard if board is full
				card.move_to_zone("graveyard")
				player.graveyard.append(card)
				EventBus.card_discarded.emit(card, player.player_id)
				return true
			if not player.place_on_board(card, row_idx):
				return false
			EventBus.card_placed_on_board.emit(card, row_idx, player.board[row_idx].size() - 1)
			# Trigger Deploy
			_trigger_deploy(card)
		
		"Spell":
			# Spells resolve immediately then go to graveyard
			_resolve_spell(card, player)
			card.move_to_zone("graveyard")
			player.graveyard.append(card)
		
		"Artifact":
			# Artifacts go to a special zone (we put them on board row 2 / artillery)
			if not player.place_on_board(card, 2):
				# If artillery row full, try other rows
				var placed: bool = false
				for r in range(GameConstants.ROW_CAPACITIES.size()):
					if player.place_on_board(card, r):
						placed = true
						break
				if not placed:
					card.move_to_zone("graveyard")
					player.graveyard.append(card)
					return true
			_trigger_deploy(card)
	
	EventBus.card_played.emit(card, player.player_id)
	return true


# ── Drawing ──────────────────────────────────────────────────────────────────

func draw_neutral(player: PlayerState) -> CardInstance:
	"""Draw a neutral card. Deducts sellary. Returns null if can't afford or deck empty."""
	var cost: int = player.get_neutral_draw_cost()
	if not player.spend_sellary(cost):
		return null
	if neutral_deck.is_empty():
		return null
	var card: CardInstance = neutral_deck.pop_front() as CardInstance
	card.owner_id = player.player_id
	card.controller_id = player.player_id
	player.add_to_hand(card)
	player.neutral_draws_this_turn += 1
	EventBus.card_drawn.emit(card, player.player_id, "neutral")
	return card


func draw_faction(player: PlayerState) -> CardInstance:
	"""Draw a faction card. Deducts sellary."""
	var cost: int = player.get_faction_draw_cost()
	if not player.spend_sellary(cost):
		return null
	var card: CardInstance = player.draw_faction_card()
	if card:
		player.faction_draws_this_turn += 1
		EventBus.card_drawn.emit(card, player.player_id, "faction")
	return card


func _draw_neutral_cards(player_idx: int, count: int) -> void:
	"""Free draw (for initial setup)."""
	var player: PlayerState = players[player_idx]
	for i in range(count):
		if neutral_deck.is_empty():
			break
		var card: CardInstance = neutral_deck.pop_front() as CardInstance
		card.owner_id = player.player_id
		card.controller_id = player.player_id
		player.add_to_hand(card)


func _draw_faction_cards(player_idx: int, count: int) -> void:
	"""Free draw (for initial setup)."""
	var player: PlayerState = players[player_idx]
	for i in range(count):
		player.draw_faction_card()


# ── Ability Triggers ─────────────────────────────────────────────────────────

func _trigger_deploy(card: CardInstance) -> void:
	for effect in card.data.effects:
		if effect.trigger == "deploy":
			EventBus.deploy_triggered.emit(card)
			EventBus.ability_triggered.emit(card, effect)


func _resolve_spell(card: CardInstance, _player: PlayerState) -> void:
	"""Resolve all effects of a spell card."""
	for effect in card.data.effects:
		EventBus.ability_triggered.emit(card, effect)


func _trigger_start_of_turn(player: PlayerState) -> void:
	"""Trigger all start-of-turn abilities (activation order: melee->artillery, L->R)."""
	for card in player.get_all_board_units():
		for effect in card.data.effects:
			if effect.trigger == "turn_start" or effect.trigger == "upkeep":
				EventBus.ability_triggered.emit(card, effect)
		# Income keyword
		for effect in card.data.effects:
			if effect.type == "income":
				player.gain_sellary(effect.value)


func _trigger_end_of_turn(player: PlayerState) -> void:
	"""Trigger end-of-turn abilities and tick timers."""
	for card in player.get_all_board_units():
		for effect in card.data.effects:
			if effect.trigger == "turn_end":
				EventBus.ability_triggered.emit(card, effect)
		# Tick timers
		if card.tick_timer():
			EventBus.timer_expired.emit(card)
			for effect in card.data.effects:
				if effect.trigger == "timer":
					EventBus.ability_triggered.emit(card, effect)


func _trigger_statuses(player: PlayerState) -> void:
	"""Process status effects at end of turn."""
	var units: Array[CardInstance] = player.get_all_board_units()
	for card in units:
		# Poison: 1 damage per stack, cannot kill
		if card.has_status("Poison"):
			var stacks: int = card.get_status_stacks("Poison")
			var dmg: int = mini(stacks, card.current_power - 1)
			if dmg > 0:
				card.apply_damage(dmg)
				EventBus.status_triggered.emit(card, "Poison")
		
		# Burn: 1 damage per stack, can kill
		if card.has_status("Burn"):
			var stacks: int = card.get_status_stacks("Burn")
			card.apply_damage(stacks)
			EventBus.status_triggered.emit(card, "Burn")
			if card.current_power <= 0:
				_destroy_card(card, player)
		
		# Wither: damage = stacks, remove all stacks, can kill
		if card.has_status("Wither"):
			var stacks: int = card.get_status_stacks("Wither")
			card.apply_damage(stacks)
			card.remove_status("Wither")
			EventBus.status_triggered.emit(card, "Wither")
			if card.current_power <= 0:
				_destroy_card(card, player)
		
		# Vulnerable: if damaged this turn, +1 damage per stack
		# (This is handled in the damage application, not here)


func _diminish_statuses(player: PlayerState) -> void:
	"""Reduce status stacks at end of turn."""
	for card in player.get_all_board_units():
		card.diminish_statuses()


# ── Destruction ──────────────────────────────────────────────────────────────

func _destroy_card(card: CardInstance, player: PlayerState) -> void:
	"""Handle card destruction: Last Word, Cursed check, graveyard/banish."""
	# Trigger Last Word
	for effect in card.data.effects:
		if effect.trigger == "last_word":
			EventBus.last_word_triggered.emit(card)
			EventBus.ability_triggered.emit(card, effect)
	
	player.remove_from_board(card)
	EventBus.card_removed_from_board.emit(card)
	
	if card.is_cursed():
		card.move_to_zone("banished")
		player.banished.append(card)
		EventBus.card_banished.emit(card)
	else:
		card.move_to_zone("graveyard")
		player.graveyard.append(card)
	
	EventBus.card_destroyed.emit(card, null)


# ── Win Condition ────────────────────────────────────────────────────────────

func _check_game_over() -> bool:
	"""Check if only one hero remains alive."""
	var alive_players: Array = []
	for p in players:
		if p.hero and p.hero.current_power > 0:
			alive_players.append(p.player_id)
	
	if alive_players.size() <= 1:
		game_over = true
		winner_id = alive_players[0] if alive_players.size() == 1 else -1
		EventBus.game_ended.emit(winner_id)
		return true
	return false
