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
var last_spell_played: CardData = null


# ── Setup ────────────────────────────────────────────────────────────────────

func setup_game(faction_choices: Array[String], first_player_id: int = 0) -> void:
	"""Initialize the game. faction_choices[i] = faction for player i. first_player_id goes first."""
	_build_neutral_deck()

	for i in range(faction_choices.size()):
		var ps: PlayerState = PlayerState.create(i, faction_choices[i])
		players.append(ps)

	# Rulebook: initial draw in reverse order of first pick
	var draw_order: Array[int] = []
	for i in range(players.size()):
		draw_order.append((first_player_id + 1 + i) % players.size())
	for i in draw_order:
		_draw_neutral_cards(i, 5)
		_draw_faction_cards(i, 3)

	turn_number = 1
	current_player_idx = first_player_id
	EventBus.game_started.emit(_get_player_ids())


func _build_neutral_deck() -> void:
	var neutral_cards: Array[CardData] = CardDatabase.get_neutral_cards()
	for card_data in neutral_cards:
		if card_data.type == "Hero":
			continue
		if not card_data.has_ability:
			continue
		var inst: CardInstance = CardInstance.create(card_data, -1)
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

	_set_phase(GameConstants.TurnPhase.SELLARY)
	var sellary_gain: int = maxi(player.base_sellary + player.base_sellary_modifier_next_turn, 0)
	player.base_sellary_modifier_next_turn = 0
	player.gain_sellary(sellary_gain)

	_set_phase(GameConstants.TurnPhase.START_OF_TURN)
	_trigger_start_of_turn(player)

	# Interactive phase — player acts freely until end_turn()
	_set_phase(GameConstants.TurnPhase.PLAY_CARDS)


func end_turn() -> void:
	"""Player pressed End Turn. Enforce hand limit, then resolve end-of-turn."""
	var player: PlayerState = get_current_player()

	# Enforce hand limit before end-of-turn triggers
	var discarded: Array[CardInstance] = player.enforce_hand_limit()
	for card in discarded:
		EventBus.card_discarded.emit(card, player.player_id)

	_set_phase(GameConstants.TurnPhase.END_OF_TURN)
	if player.suppress_end_turn_next_turn:
		player.suppress_end_turn_next_turn = false
		EventBus.message_shown.emit("End-of-turn abilities suppressed.")
	else:
		_trigger_end_of_turn(player)

	_set_phase(GameConstants.TurnPhase.STATUS_TRIGGER)
	_trigger_statuses(player)

	_set_phase(GameConstants.TurnPhase.STATUS_DIMINISH)
	_diminish_statuses(player)

	EventBus.turn_ended.emit(player.player_id)

	if _check_game_over():
		return

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
	if current_phase != GameConstants.TurnPhase.PLAY_CARDS:
		return false
	var limit: int = GameConstants.MAX_CARDS_PER_TURN + player.extra_card_plays
	return player.cards_played_this_turn < limit


func play_card(player: PlayerState, card: CardInstance, row_idx: int = -1, col_idx: int = -1) -> bool:
	"""Play a card from hand. row_idx + col_idx needed for Units. Returns success."""
	if not can_play_card(player, card):
		return false
	if not (card in player.hand):
		return false
	if card.data.type == "Unit" or card.data.type == "Artifact":
		if row_idx < 0 or col_idx < 0:
			return false
		if row_idx >= GameConstants.ROW_CAPACITIES.size():
			return false
		if not player.is_board_full() and player.is_slot_occupied(row_idx, col_idx):
			return false
	
	# Remove from hand
	if not player.remove_from_hand(card):
		return false
	
	player.cards_played_this_turn += 1
	
	match card.data.type:
		"Unit":
			if player.is_board_full():
				card.move_to_zone("graveyard")
				player.graveyard.append(card)
				EventBus.card_discarded.emit(card, player.player_id)
				return true
			if not player.place_on_board(card, row_idx, col_idx):
				return false
			EventBus.card_placed_on_board.emit(card, row_idx, col_idx)
			_trigger_deploy(card)
			_trigger_tribute(card)
			_trigger_passive(card)
		
		"Spell":
			# Spells resolve immediately then go to graveyard
			_resolve_spell(card, player)
			last_spell_played = card.data
			if card.zone != "deck" and card.zone != "banished":
				card.move_to_zone("graveyard")
				player.graveyard.append(card)
		
		"Artifact":
			if row_idx < 0 or col_idx < 0:
				return false
			if not player.place_on_board(card, row_idx, col_idx):
				return false
			EventBus.card_placed_on_board.emit(card, row_idx, col_idx)
			_trigger_deploy(card)
			_trigger_tribute(card)
			_trigger_passive(card)
	
	EventBus.card_played.emit(card, player.player_id)
	_trigger_hoard(player)
	_trigger_spot_67_all()
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
	_trigger_spot_67_all()
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
		_trigger_spot_67_all()
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
	if _trigger_card_effects(card, "deploy"):
		EventBus.deploy_triggered.emit(card)


func _trigger_tribute(card: CardInstance) -> void:
	var player := _get_card_controller(card)
	if not player:
		return
	for effect in card.data.effects:
		if effect.trigger != "tribute":
			continue
		var tribute_effect: CardEffect = effect
		if tribute_effect.tribute_cost > 0:
			if player.sellary < tribute_effect.tribute_cost:
				continue
			EventBus.choice_requested.emit("Tribute %d for %s?" % [tribute_effect.tribute_cost, card.data.name], [
				{"label": "Pay", "value": true},
				{"label": "Skip", "value": false},
			], func(accepted: bool) -> void:
				if accepted:
					_emit_triggered_effect(card, tribute_effect)
			)
		else:
			_emit_triggered_effect(card, tribute_effect)


func _trigger_passive(card: CardInstance) -> void:
	_trigger_card_effects(card, "passive")


func _resolve_spell(card: CardInstance, _player: PlayerState) -> void:
	"""Resolve all effects of a spell card."""
	for effect in card.data.effects:
		_emit_triggered_effect(card, effect)


func _trigger_start_of_turn(player: PlayerState) -> void:
	"""Trigger all start-of-turn abilities (activation order: melee->artillery, L->R)."""
	_trigger_player_effects(player, ["turn_start", "upkeep"])
	_trigger_hoard(player)
	_trigger_spot_67_all()


func _trigger_end_of_turn(player: PlayerState) -> void:
	"""Trigger end-of-turn abilities and tick timers."""
	for card in player.get_all_board_units():
		_trigger_card_effects(card, "turn_end")
		# Tick timers
		if card.tick_timer():
			EventBus.timer_expired.emit(card)
			_trigger_card_effects(card, "timer")
	_trigger_hoard(player)
	_trigger_spot_67_all()


func _trigger_player_effects(player: PlayerState, triggers: Array[String]) -> void:
	for card in player.get_all_board_units().duplicate():
		for trigger in triggers:
			_trigger_card_effects(card, trigger)


func _trigger_card_effects(card: CardInstance, trigger: String) -> bool:
	var emitted := false
	for effect in card.data.effects:
		if effect.trigger == trigger:
			_emit_triggered_effect(card, effect)
			emitted = true
	return emitted


func _emit_triggered_effect(card: CardInstance, effect: CardEffect) -> void:
	EventBus.ability_triggered.emit(card, effect)


func _get_card_controller(card: CardInstance) -> PlayerState:
	for player in players:
		if player.player_id == card.controller_id:
			return player
	return null


func _trigger_hoard(player: PlayerState) -> void:
	for card in player.get_all_board_units().duplicate():
		_trigger_card_effects(card, "hoard")


func _trigger_spot_67_all() -> void:
	for player in players:
		if _player_spots_67(player):
			for card in player.get_all_board_units().duplicate():
				_trigger_card_effects(card, "spot_67")


func _player_spots_67(player: PlayerState) -> bool:
	for card in player.get_all_board_units():
		if card.data.id == "67":
			return true
		if _card_represents_number(card, "6"):
			var pos: Dictionary = player.find_card_position(card)
			if pos.is_empty():
				continue
			for adjacent in BoardManager.get_adjacent_cards(player, pos["row"], pos["col"]):
				if _card_represents_number(adjacent, "7"):
					return true
	return false


func _card_represents_number(card: CardInstance, number_text: String) -> bool:
	return card.data.id == number_text or card.data.name.strip_edges() == number_text


func activate_order(card: CardInstance) -> bool:
	"""Activate a board card's Order effects for the current player."""
	if current_phase != GameConstants.TurnPhase.PLAY_CARDS or card.activated_this_turn:
		return false
	var player := get_current_player()
	if card.controller_id != player.player_id or not (card in player.get_all_board_units()):
		return false
	if not _card_has_payable_trigger(card, "order", player):
		return false
	var triggered := _trigger_card_effects(card, "order")
	if triggered:
		card.activated_this_turn = true
		_trigger_hoard(player)
		_trigger_spot_67_all()
	return triggered


func activate_pay(card: CardInstance) -> bool:
	"""Activate a board card's Pay effects for the current player."""
	if current_phase != GameConstants.TurnPhase.PLAY_CARDS:
		return false
	var player := get_current_player()
	if card.controller_id != player.player_id or not (card in player.get_all_board_units()):
		return false
	if not _card_has_payable_trigger(card, "pay", player):
		return false
	var triggered := _trigger_card_effects(card, "pay")
	if triggered:
		_trigger_hoard(player)
		_trigger_spot_67_all()
	return triggered


func _card_has_payable_trigger(card: CardInstance, trigger: String, player: PlayerState) -> bool:
	for effect in card.data.effects:
		if effect.trigger != trigger:
			continue
		if effect.pay_cost > 0 and player.sellary < effect.pay_cost:
			continue
		if effect.upkeep_cost > 0 and player.sellary < effect.upkeep_cost:
			continue
		if trigger == "order":
			var charge_cost: int = effect.charges
			if charge_cost == 0 and card.max_charges > 0:
				charge_cost = 1
			if charge_cost > 0 and card.charges < charge_cost:
				continue
		return true
	return false


func spawn_card_for_player(player: PlayerState, card_id: String, anchor: CardInstance = null, cursed: bool = false) -> CardInstance:
	var card_data: CardData = CardDatabase.get_card(card_id)
	if not card_data:
		return null
	var inst := CardInstance.create(card_data, player.player_id)
	if cursed:
		inst.apply_status("Cursed", 1, true)
	var placed := false
	if anchor:
		placed = player.place_adjacent_to(inst, anchor)
	else:
		placed = player.place_in_first_free_slot(inst)
	if not placed:
		inst.move_to_zone("graveyard")
		player.graveyard.append(inst)
		EventBus.card_discarded.emit(inst, player.player_id)
		return inst
	EventBus.card_placed_on_board.emit(inst, inst.board_position.get("row", -1), inst.board_position.get("col", -1))
	_trigger_deploy(inst)
	_trigger_passive(inst)
	return inst


func play_specific_from_deck_or_graveyard(player: PlayerState, card_id: String, anchor: CardInstance = null, cursed: bool = false) -> CardInstance:
	var card: CardInstance = player.take_from_faction_deck(card_id)
	if not card:
		card = player.take_from_graveyard(card_id)
	if not card:
		return null
	if cursed:
		card.apply_status("Cursed", 1, true)
	var placed := false
	if anchor:
		placed = player.place_adjacent_to(card, anchor)
	else:
		placed = player.place_in_first_free_slot(card)
	if not placed:
		card.move_to_zone("graveyard")
		player.graveyard.append(card)
		return card
	EventBus.card_placed_on_board.emit(card, card.board_position.get("row", -1), card.board_position.get("col", -1))
	_trigger_deploy(card)
	_trigger_passive(card)
	return card


func replay_from_graveyard(player: PlayerState, card: CardInstance, cursed: bool = false) -> bool:
	if not (card in player.graveyard):
		return false
	player.graveyard.erase(card)
	if cursed:
		card.apply_status("Cursed", 1, true)
	if card.data.type in ["Unit", "Artifact"]:
		if not player.place_in_first_free_slot(card):
			player.graveyard.append(card)
			return false
		EventBus.card_placed_on_board.emit(card, card.board_position.get("row", -1), card.board_position.get("col", -1))
		_trigger_deploy(card)
		_trigger_passive(card)
	elif card.data.type == "Spell":
		_resolve_spell(card, player)
		card.move_to_zone("graveyard")
		player.graveyard.append(card)
	return true


func _trigger_statuses(player: PlayerState) -> void:
	"""Process status effects at end of turn."""
	var units: Array[CardInstance] = player.get_all_board_units()
	for card in units:
		if card.data.type == "Artifact":
			continue
		# Poison: 1 damage per stack, cannot kill
		if card.has_status("Poison"):
			var stacks: int = card.get_status_stacks("Poison")
			var dmg: int = mini(stacks, card.current_power - 1)
			if dmg > 0:
				card.apply_direct_damage(dmg)
				EventBus.damage_dealt.emit(card, dmg, null)
				EventBus.status_triggered.emit(card, "Poison")
		
		# Burn: 1 damage per stack, can kill
		if card.has_status("Burn"):
			var stacks: int = card.get_status_stacks("Burn")
			card.apply_direct_damage(stacks)
			EventBus.damage_dealt.emit(card, stacks, null)
			EventBus.status_triggered.emit(card, "Burn")
			if card.current_power <= 0:
				_destroy_card(card, player)
		
		# Wither: damage = stacks, remove all stacks, can kill
		if card.has_status("Wither"):
			var stacks: int = card.get_status_stacks("Wither")
			card.apply_direct_damage(stacks)
			EventBus.damage_dealt.emit(card, stacks, null)
			card.remove_status("Wither")
			EventBus.status_triggered.emit(card, "Wither")
			if card.current_power <= 0:
				_destroy_card(card, player)
		
		# Vulnerable: if damaged this turn, damage self by 1 per stack.
		if card.has_status("Vulnerable") and card.damaged_this_turn:
			var stacks: int = card.get_status_stacks("Vulnerable")
			card.apply_direct_damage(stacks)
			EventBus.damage_dealt.emit(card, stacks, null)
			EventBus.status_triggered.emit(card, "Vulnerable")
			if card.current_power <= 0:
				_destroy_card(card, player)


func _diminish_statuses(player: PlayerState) -> void:
	"""Reduce status stacks at end of turn."""
	for card in player.get_all_board_units():
		card.diminish_statuses()


# ── Destruction ──────────────────────────────────────────────────────────────

func _destroy_card(card: CardInstance, player: PlayerState) -> void:
	"""Handle card destruction: Last Word, Cursed check, graveyard/banish."""
	if card.data.type in ["Unit", "Hero"]:
		card.current_power = 0
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


func force_game_over(forced_winner_id: int) -> void:
	game_over = true
	winner_id = forced_winner_id
	EventBus.game_ended.emit(winner_id)
