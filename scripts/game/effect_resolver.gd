## EffectResolver
## Listens for ability_triggered signals and executes the actual game effects.
## Handles targeting, damage calculation, status application, and economy.
## This is where you add new effect types as you implement more card abilities.
class_name EffectResolver
extends Node

var game_state: GameState


func _ready() -> void:
	EventBus.ability_triggered.connect(_on_ability_triggered)
	EventBus.deploy_triggered.connect(_on_deploy_triggered)
	EventBus.timer_expired.connect(_on_timer_expired)


func setup(gs: GameState) -> void:
	game_state = gs


# ── Signal Handlers ──────────────────────────────────────────────────────────

func _on_ability_triggered(card: CardInstance, effect: CardEffect) -> void:
	print("[DEBUG] _on_ability_triggered: %s effect=%s trigger=%s" % [card.data.name, effect.type, effect.trigger])
	EventBus.message_shown.emit("ABILITY: %s %s/%s" % [card.data.name, effect.type, effect.trigger])
	if not _check_costs(card, effect):
		print("[DEBUG] cost check failed")
		EventBus.message_shown.emit("COST FAIL")
		return

	match effect.type:
		"damage":
			_resolve_damage(card, effect)
		"boost":
			_resolve_boost(card, effect)
		"heal":
			_resolve_heal(card, effect)
		"profit":
			_resolve_profit(card, effect)
		"income":
			_resolve_income(card, effect)
		"draw":
			_resolve_draw(card, effect)
		"apply_status":
			_resolve_apply_status(card, effect)
		"destroy":
			_resolve_destroy(card, effect)
		"banish":
			_resolve_banish(card, effect)
		"spy":
			_resolve_spy(card, effect)
		"devour":
			_resolve_devour(card, effect)
		"seize":
			_resolve_seize(card, effect)
		"block":
			_resolve_block(card, effect)
		"complex":
			_resolve_complex(card, effect)
		_:
			push_warning("[EffectResolver] Unknown effect type: %s" % effect.type)


func _on_deploy_triggered(_card: CardInstance) -> void:
	# Deploy effects are handled through ability_triggered
	pass


func _on_timer_expired(_card: CardInstance) -> void:
	# Timer expiry effects are handled through ability_triggered
	pass


# ── Cost Checking ────────────────────────────────────────────────────────────

func _check_costs(card: CardInstance, effect: CardEffect) -> bool:
	var player: PlayerState = _get_controller(card)
	if not player:
		return false
	
	# Tribute: optional cost
	if effect.trigger == "tribute" and effect.tribute_cost > 0:
		if player.sellary < effect.tribute_cost:
			return false  # Can't afford — skip ability
		player.spend_sellary(effect.tribute_cost)
	
	# Upkeep: mandatory cost
	if effect.trigger == "upkeep" and effect.upkeep_cost > 0:
		if not player.spend_sellary(effect.upkeep_cost):
			return false  # Can't afford — ability doesn't trigger
	
	# Hoard: threshold check (doesn't spend)
	if effect.trigger == "hoard" and effect.hoard_threshold > 0:
		if player.sellary < effect.hoard_threshold:
			return false
	
	# Order: charge check
	if effect.trigger == "order":
		var charge_cost: int = effect.charges if effect.charges > 0 else 1
		if not card.use_charge(charge_cost):
			return false
	
	# Pay: explicit sellary cost
	if effect.trigger == "passive":
		pass  # TODO: handle Pay keyword separately
	
	return true


# ── Effect Resolvers ─────────────────────────────────────────────────────────

func _resolve_damage(source: CardInstance, effect: CardEffect) -> void:
	var targets: Array = _get_valid_damage_targets(source)
	print("[DEBUG] _resolve_damage: targets=%d needs_target=%s" % [targets.size(), effect.needs_target()])
	if targets.is_empty():
		return

	if effect.needs_target():
		EventBus.target_requested.emit(targets, func(target: CardInstance) -> void:
			_apply_damage(source, target, effect.value)
		)
	else:
		# No target needed (e.g. area) — hit all valid targets
		for target in targets:
			_apply_damage(source, target, effect.value)


func _apply_damage(source: CardInstance, target: CardInstance, base_damage: int) -> void:
	if target.data.type == "Artifact":
		return
	var damage: int = base_damage

	if source.has_status("Perplexed") and randf() < 0.5:
		var player: PlayerState = _get_controller(source)
		if player and player.hero:
			target = player.hero

	if source.has_status("Drunk"):
		var miss_chance: float = source.get_status_stacks("Drunk") * 0.25
		if randf() < miss_chance:
			if "Abeer Dawood Salman" in source.data.factions:
				var crit_chance: float = source.get_status_stacks("Drunk") * 0.25
				if randf() < crit_chance:
					damage *= 2
					EventBus.message_shown.emit("%s crits! (Abeer Drunk)" % source.data.name)
				else:
					EventBus.message_shown.emit("%s missed (Drunk)!" % source.data.name)
					return
			else:
				EventBus.message_shown.emit("%s missed (Drunk)!" % source.data.name)
				return

	var actual_damage: int = target.apply_damage(damage)
	EventBus.damage_dealt.emit(target, actual_damage, source)

	if target.current_power <= 0:
		var owner: PlayerState = _find_card_owner(target)
		if owner:
			game_state._destroy_card(target, owner)
		for eff in source.data.effects:
			if eff.trigger == "deathblow":
				EventBus.deathblow_triggered.emit(source, target)
				EventBus.ability_triggered.emit(source, eff)


func _resolve_boost(source: CardInstance, effect: CardEffect) -> void:
	# Default: boost self. Targeting handled by complex abilities.
	source.apply_boost(effect.value)
	EventBus.boost_applied.emit(source, effect.value)


func _resolve_heal(source: CardInstance, effect: CardEffect) -> void:
	# Spells heal the casting player's hero; units/artifacts heal self
	var target: CardInstance = source
	if source.data.type == "Spell":
		var player: PlayerState = _get_controller(source)
		if player and player.hero:
			target = player.hero
	target.apply_heal(effect.value)
	EventBus.heal_applied.emit(target, effect.value)


func _resolve_profit(source: CardInstance, effect: CardEffect) -> void:
	var player: PlayerState = _get_controller(source)
	if player:
		var amount: int = effect.value
		# Check Economic Fury status (doubles profit)
		if source.has_status("Economic Fury") or (player.hero and player.hero.has_status("Economic Fury")):
			amount *= 2
		player.gain_sellary(amount)


func _resolve_income(source: CardInstance, effect: CardEffect) -> void:
	# Income is just Profit at start of turn
	_resolve_profit(source, effect)


func _resolve_draw(source: CardInstance, effect: CardEffect) -> void:
	var player: PlayerState = _get_controller(source)
	if not player:
		return
	# EGGxited: draw 3 copies of Egg specifically
	if source.data.id == "eggxited":
		var egg_data: CardData = CardDatabase.get_card("egg")
		if egg_data:
			for i in range(effect.value):
				var egg: CardInstance = CardInstance.create(egg_data, player.player_id)
				player.add_to_hand(egg)
				EventBus.card_drawn.emit(egg, player.player_id, "ability")
		return
	# Draw from neutral deck (free draws from abilities)
	for i in range(effect.value):
		if game_state.neutral_deck.is_empty():
			break
		var card: CardInstance = game_state.neutral_deck.pop_front() as CardInstance
		card.owner_id = player.player_id
		card.controller_id = player.player_id
		player.add_to_hand(card)
		EventBus.card_drawn.emit(card, player.player_id, "ability")


func _resolve_apply_status(source: CardInstance, effect: CardEffect) -> void:
	var targets: Array = _get_all_board_units_except(source)
	if targets.is_empty():
		return
	EventBus.target_requested.emit(targets, func(target: CardInstance) -> void:
		target.apply_status(effect.status, effect.stacks if effect.stacks > 0 else 1)
		EventBus.status_applied.emit(target, effect.status, effect.stacks)
	)


func _resolve_destroy(source: CardInstance, _effect: CardEffect) -> void:
	var targets: Array = _get_valid_damage_targets(source)
	if targets.is_empty():
		return
	EventBus.target_requested.emit(targets, func(target: CardInstance) -> void:
		var owner: PlayerState = _find_card_owner(target)
		if owner:
			game_state._destroy_card(target, owner)
	)


func _resolve_banish(source: CardInstance, _effect: CardEffect) -> void:
	var targets: Array = _get_valid_damage_targets(source)
	if targets.is_empty():
		return
	EventBus.target_requested.emit(targets, func(target: CardInstance) -> void:
		var owner: PlayerState = _find_card_owner(target)
		if owner:
			owner.remove_from_board(target)
			target.move_to_zone("banished")
			owner.banished.append(target)
			EventBus.card_banished.emit(target)
	)


func _resolve_spy(source: CardInstance, _effect: CardEffect) -> void:
	"""Place card on opponent's board."""
	var player: PlayerState = _get_controller(source)
	if not player:
		return
	# Find opponent
	for p in game_state.players:
		if p.player_id != player.player_id:
			# Move to opponent's board
			player.remove_from_board(source)
			source.controller_id = p.player_id
			for row_idx in range(p.board.size()):
				var free_col: int = p.find_free_col(row_idx)
				if free_col >= 0:
					p.place_on_board(source, row_idx, free_col)
					break
			break


func _resolve_devour(source: CardInstance, _effect: CardEffect) -> void:
	var player: PlayerState = _get_controller(source)
	if not player:
		return
	var allies: Array = []
	for card in player.get_all_board_units():
		if card != source:
			allies.append(card)
	if allies.is_empty():
		return
	EventBus.target_requested.emit(allies, func(target: CardInstance) -> void:
		var power: int = target.current_power
		game_state._destroy_card(target, player)
		source.apply_boost(power)
		EventBus.boost_applied.emit(source, power)
	)


func _resolve_seize(source: CardInstance, effect: CardEffect) -> void:
	"""Steal sellary from opponent."""
	var player: PlayerState = _get_controller(source)
	if not player:
		return
	for p in game_state.players:
		if p.player_id != player.player_id:
			var amount: int = mini(effect.value, p.sellary)
			p.sellary -= amount
			player.gain_sellary(amount)
			EventBus.sellary_seized.emit(p.player_id, player.player_id, amount)
			break


func _resolve_block(source: CardInstance, effect: CardEffect) -> void:
	source.block = effect.value


func _resolve_complex(source: CardInstance, effect: CardEffect) -> void:
	match source.data.id:
		"accountant_pro_max":
			_complex_accountant_pro_max(source)
		"carry_on":
			_complex_carry_on(source)
		"catch_up":
			_complex_catch_up(source)
		"hhmds":
			_complex_hhmds(source)
		"individual_sailor":
			_complex_individual_sailor(source)
		"sir_vant":
			_complex_sir_vant(source, effect)
		"s_ibal":
			_complex_sibal(source)
		_:
			push_warning("[EffectResolver] Unimplemented complex effect on %s: %s" % [source.data.name, effect.raw_text])


func _complex_accountant_pro_max(source: CardInstance) -> void:
	var player: PlayerState = _get_controller(source)
	if not player:
		return
	var gold: int = player.sellary
	var profit: int = 0
	var boost: int = 0
	if gold >= 8:
		profit = 4
		boost = 1
	elif gold >= 6:
		profit = 3
	elif gold >= 2:
		profit = 2
	if profit > 0:
		player.gain_sellary(profit)
		EventBus.message_shown.emit("Accountant Pro Max: profit %d" % profit)
	if boost > 0:
		source.apply_boost(boost)
		EventBus.boost_applied.emit(source, boost)


func _complex_carry_on(source: CardInstance) -> void:
	var player: PlayerState = _get_controller(source)
	if not player:
		return
	player.extra_card_plays += 2
	EventBus.message_shown.emit("Carry On: +2 card plays this turn")


func _complex_hhmds(source: CardInstance) -> void:
	var player: PlayerState = _get_controller(source)
	if not player:
		return
	player.extra_card_plays += 1
	EventBus.message_shown.emit("HHMDS: +1 card play this turn")


func _complex_catch_up(source: CardInstance) -> void:
	var player: PlayerState = _get_controller(source)
	if not player:
		return
	for p in game_state.players:
		if p.player_id != player.player_id:
			var diff: int = p.sellary - player.sellary
			if diff > 0:
				player.gain_sellary(diff)
				EventBus.message_shown.emit("Catch-up: gained %d sellary" % diff)
			elif diff < 0:
				player.spend_sellary(-diff)
				EventBus.message_shown.emit("Catch-up: lost %d sellary" % (-diff))
			break


func _complex_individual_sailor(source: CardInstance) -> void:
	var player: PlayerState = _get_controller(source)
	if not player:
		return

	if player.is_alone_in_row(source):
		# Condition met: damage enemy hero by 3, boost self by 1
		var enemy_hero: CardInstance = _get_enemy_hero(player)
		if enemy_hero:
			_apply_damage(source, enemy_hero, 3)
		source.apply_boost(1)
		EventBus.boost_applied.emit(source, 1)
	else:
		# Default: boost nearest right neighbor by 1
		var right: CardInstance = player.get_right_neighbor(source)
		if right:
			right.apply_boost(1)
			EventBus.boost_applied.emit(right, 1)


func _complex_sir_vant(source: CardInstance, effect: CardEffect) -> void:
	var player: PlayerState = _get_controller(source)
	if not player:
		return
	if effect.trigger == "turn_end":
		# Optional: pay 2 → heal hero by 1
		if player.sellary >= 2 and player.hero:
			player.spend_sellary(2)
			player.hero.apply_heal(1)
			EventBus.heal_applied.emit(player.hero, 1)
			EventBus.message_shown.emit("Sir Vant: paid 2, healed hero by 1")
	elif effect.trigger == "last_word":
		# Heal+boost all Sir Can units by 2/1
		for p in game_state.players:
			if p.player_id == player.player_id:
				for card in p.get_all_board_units():
					if "Sir Can" in card.data.factions:
						card.apply_heal(2)
						EventBus.heal_applied.emit(card, 2)
						card.apply_boost(1)
						EventBus.boost_applied.emit(card, 1)
		EventBus.message_shown.emit("Sir Vant last word: healed+boosted Sir Can units")


func _complex_sibal(source: CardInstance) -> void:
	var player: PlayerState = _get_controller(source)
	if not player:
		return
	# Shuffle 2 from hand into faction deck
	var shuffled: int = 0
	while shuffled < 2 and not player.hand.is_empty():
		# Pick last card in hand (avoids re-sorting)
		var card: CardInstance = player.hand[player.hand.size() - 1]
		player.remove_from_hand(card)
		card.move_to_zone("faction_deck")
		player.faction_deck.append(card)
		shuffled += 1
	player.faction_deck.shuffle()
	# Draw 2 faction
	for i in range(2):
		var drawn: CardInstance = player.draw_faction_card()
		if drawn:
			EventBus.card_drawn.emit(drawn, player.player_id, "ability")
	EventBus.message_shown.emit("Šibal: shuffled %d, drew 2 faction" % shuffled)


# ── Helpers ──────────────────────────────────────────────────────────────────

func _get_controller(card: CardInstance) -> PlayerState:
	for p in game_state.players:
		if p.player_id == card.controller_id:
			return p
	return null


func _find_card_owner(card: CardInstance) -> PlayerState:
	for p in game_state.players:
		if card in p.get_all_board_units():
			return p
		if p.hero == card:
			return p
	return null


func _get_all_board_units_except(source: CardInstance) -> Array:
	var result: Array = []
	for p in game_state.players:
		for card in p.get_all_board_units():
			if card != source:
				result.append(card)
	return result


func _get_enemy_player(source: CardInstance) -> PlayerState:
	"""Returns the first opponent of the card's controller."""
	var player: PlayerState = _get_controller(source)
	if not player:
		return null
	for p in game_state.players:
		if p.player_id != player.player_id:
			return p
	return null


func _get_enemy_hero(player: PlayerState) -> CardInstance:
	"""Returns the enemy hero if alive."""
	for p in game_state.players:
		if p.player_id != player.player_id:
			return p.hero if p.hero and p.hero.current_power > 0 else null
	return null


func _controls_card_id(player: PlayerState, card_id: String) -> bool:
	"""True if the player has a card with the given ID on their board."""
	for card in player.get_all_board_units():
		if card.data.id == card_id:
			return true
	return false


func _get_valid_damage_targets(source: CardInstance) -> Array:
	var targets: Array = []
	var player: PlayerState = _get_controller(source)
	if not player:
		return targets

	for p in game_state.players:
		if p.player_id == player.player_id:
			continue
		for card in p.get_all_board_units():
			if not card.is_invisible():
				targets.append(card)
		if p.hero and p.hero.current_power > 0:
			targets.append(p.hero)

	return targets
