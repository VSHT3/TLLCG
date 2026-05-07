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
	EventBus.damage_dealt.connect(_on_damage_dealt)


func setup(gs: GameState) -> void:
	game_state = gs


# ── Signal Handlers ──────────────────────────────────────────────────────────

func _on_ability_triggered(card: CardInstance, effect: CardEffect) -> void:
	EventBus.message_shown.emit("ABILITY: %s %s/%s" % [card.data.name, effect.type, effect.trigger])
	if not _check_costs(card, effect):
		return
	if effect.counter_delta != 0:
		card.change_counter(effect.counter_delta)

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
		"gain_charge":
			_resolve_gain_charge(card, effect)
		"complex":
			_resolve_complex(card, effect)
		"cleanse":
			_resolve_cleanse(card, effect)
		"discard":
			_resolve_discard(card, effect)
		_:
			push_warning("[EffectResolver] Unknown effect type: %s" % effect.type)


func _on_deploy_triggered(_card: CardInstance) -> void:
	# Deploy effects are handled through ability_triggered
	pass


func _on_timer_expired(_card: CardInstance) -> void:
	# Timer expiry effects are handled through ability_triggered
	pass


func _on_damage_dealt(target: CardInstance, amount: int, source: CardInstance) -> void:
	if amount <= 0 or not game_state:
		return
	_apply_masovystit_redirect(target, amount, source)


# ── Cost Checking ────────────────────────────────────────────────────────────

func _check_costs(card: CardInstance, effect: CardEffect) -> bool:
	var player: PlayerState = _get_controller(card)
	if not player:
		return false

	var use_key := "%s:%s:%s" % [effect.type, effect.trigger, effect.raw_text]
	if effect.max_uses_per_turn > 0:
		var uses: int = card.effect_uses_this_turn.get(use_key, 0)
		if uses >= effect.max_uses_per_turn:
			return false
	
	# Tribute: optional cost
	if effect.trigger == "tribute" and effect.tribute_cost > 0:
		if player.sellary < effect.tribute_cost:
			return false  # Can't afford — skip ability
		player.spend_sellary(effect.tribute_cost)
	
	# Upkeep: mandatory cost attached to any trigger.
	if effect.upkeep_cost > 0:
		if not player.spend_sellary(effect.upkeep_cost):
			return false  # Can't afford — ability doesn't trigger
	
	# Hoard: threshold check (doesn't spend)
	if effect.trigger == "hoard" and effect.hoard_threshold > 0:
		if player.sellary < effect.hoard_threshold:
			return false
	
	# Order: charge check
	if effect.trigger == "order":
		var charge_cost: int = effect.charges
		if charge_cost == 0 and card.max_charges > 0:
			charge_cost = 1
		if charge_cost > 0 and not card.use_charge(charge_cost):
			return false
	
	# Pay: explicit sellary cost
	if effect.trigger == "pay" and effect.pay_cost > 0:
		if not player.spend_sellary(effect.pay_cost):
			return false
	
	if effect.max_uses_per_turn > 0:
		card.effect_uses_this_turn[use_key] = card.effect_uses_this_turn.get(use_key, 0) + 1
	
	return true


# ── Effect Resolvers ─────────────────────────────────────────────────────────

func _resolve_damage(source: CardInstance, effect: CardEffect) -> void:
	var targets: Array = _get_effect_targets(source, effect)
	if targets.is_empty():
		return

	if effect.needs_target():
		EventBus.target_requested.emit(targets, func(target: CardInstance) -> void:
			_apply_damage_to_effect_targets(source, target, effect)
		)
	else:
		for target in targets:
			_apply_damage(source, target, effect.value)


func _apply_damage(source: CardInstance, target: CardInstance, base_damage: int) -> void:
	if target.data.type == "Artifact":
		return
	var damage: int = base_damage
	if source.has_status("Crit"):
		damage *= 2

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
		if target.data.type == "Unit":
			for eff in source.data.effects:
				if eff.trigger == "deathblow":
					EventBus.deathblow_triggered.emit(source, target)
					EventBus.ability_triggered.emit(source, eff)


func _resolve_boost(source: CardInstance, effect: CardEffect) -> void:
	var targets: Array = _get_effect_targets(source, effect)
	if targets.is_empty():
		return
	if effect.needs_target():
		EventBus.target_requested.emit(targets, func(target: CardInstance) -> void:
			_apply_boost_to_effect_targets(target, effect)
		)
	else:
		for target in targets:
			target.apply_boost(effect.value)
			EventBus.boost_applied.emit(target, effect.value)


func _resolve_heal(source: CardInstance, effect: CardEffect) -> void:
	var targets: Array = _get_effect_targets(source, effect)
	if targets.is_empty():
		return
	if effect.needs_target():
		EventBus.target_requested.emit(targets, func(target: CardInstance) -> void:
			_apply_heal_to_effect_targets(target, effect)
		)
	else:
		for target in targets:
			var amount: int = target.missing_health() if effect.value <= 0 else effect.value
			target.apply_heal(amount)
			EventBus.heal_applied.emit(target, amount)


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
	var targets: Array = _get_effect_targets(source, effect)
	if targets.is_empty():
		return
	if effect.needs_target():
		EventBus.target_requested.emit(targets, func(target: CardInstance) -> void:
			_apply_status_to_target(target, effect)
		)
	else:
		for target in targets:
			_apply_status_to_target(target, effect)


func _resolve_destroy(source: CardInstance, effect: CardEffect) -> void:
	var targets: Array = _get_effect_targets(source, effect)
	if targets.is_empty():
		return
	if effect.needs_target():
		EventBus.target_requested.emit(targets, func(target: CardInstance) -> void:
			_destroy_effect_target(target)
		)
	else:
		for target in targets:
			_destroy_effect_target(target)


func _resolve_banish(source: CardInstance, effect: CardEffect) -> void:
	var targets: Array = _get_effect_targets(source, effect)
	if targets.is_empty():
		return
	if effect.needs_target():
		EventBus.target_requested.emit(targets, func(target: CardInstance) -> void:
			_banish_effect_target(target)
		)
	else:
		for target in targets:
			_banish_effect_target(target)


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
			EventBus.card_removed_from_board.emit(source)
			source.controller_id = p.player_id
			var placed := false
			for row_idx in range(p.board.size()):
				var free_col: int = p.find_free_col(row_idx)
				if free_col >= 0:
					placed = p.place_on_board(source, row_idx, free_col)
					if placed:
						EventBus.card_placed_on_board.emit(source, row_idx, free_col)
					break
			if not placed:
				source.move_to_zone("graveyard")
				player.graveyard.append(source)
				EventBus.card_discarded.emit(source, player.player_id)
			break


func _resolve_devour(source: CardInstance, _effect: CardEffect) -> void:
	var player: PlayerState = _get_controller(source)
	if not player:
		return
	var allies: Array = []
	for card in player.get_all_board_units():
		if card != source and card.data.type == "Unit":
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
	var targets: Array[PlayerState] = []
	for p in game_state.players:
		match effect.target_scope:
			"self", "ally":
				if p.player_id == player.player_id:
					targets.append(p)
			"any":
				targets.append(p)
			_:
				if p.player_id != player.player_id:
					targets.append(p)
	if targets.is_empty():
		return
	if targets.size() == 1:
		_apply_seize(player, targets[0], effect.value)
		return
	var options: Array = []
	for target_player in targets:
		var who := "You" if target_player.player_id == player.player_id else "Opponent"
		options.append({"label": who, "detail": "%d sellary available." % target_player.sellary, "value": target_player})
	EventBus.choice_requested.emit("Seize from", options, func(target_player: PlayerState) -> void:
		_apply_seize(player, target_player, effect.value)
	)


func _resolve_block(source: CardInstance, effect: CardEffect) -> void:
	source.block = effect.value


func _resolve_gain_charge(source: CardInstance, effect: CardEffect) -> void:
	source.gain_charge(effect.value if effect.value > 0 else 1)
	EventBus.message_shown.emit("%s gained charge (%d)." % [source.data.name, source.charges])


func _apply_seize(to_player: PlayerState, from_player: PlayerState, value: int) -> void:
	var amount: int = mini(value, from_player.sellary)
	from_player.sellary -= amount
	to_player.gain_sellary(amount)
	EventBus.sellary_seized.emit(from_player.player_id, to_player.player_id, amount)


func _apply_damage_to_effect_targets(source: CardInstance, target: CardInstance, effect: CardEffect) -> void:
	for affected in _expand_area_targets(target, effect):
		_apply_damage(source, affected, effect.value)


func _apply_boost_to_effect_targets(target: CardInstance, effect: CardEffect) -> void:
	for affected in _expand_area_targets(target, effect):
		affected.apply_boost(effect.value)
		EventBus.boost_applied.emit(affected, effect.value)


func _apply_heal_to_effect_targets(target: CardInstance, effect: CardEffect) -> void:
	for affected in _expand_area_targets(target, effect):
		var amount: int = affected.missing_health() if effect.value <= 0 else effect.value
		affected.apply_heal(amount)
		EventBus.heal_applied.emit(affected, amount)


func _apply_status_to_target(target: CardInstance, effect: CardEffect) -> void:
	var stacks: int = effect.stacks if effect.stacks > 0 else 1
	for affected in _expand_area_targets(target, effect):
		affected.apply_status(effect.status, stacks, effect.permanent_status)
		EventBus.status_applied.emit(affected, effect.status, stacks)


func _destroy_effect_target(target: CardInstance) -> void:
	var owner: PlayerState = _find_card_owner(target)
	if owner:
		game_state._destroy_card(target, owner)


func _banish_effect_target(target: CardInstance) -> void:
	var owner: PlayerState = _find_card_owner(target)
	if not owner:
		owner = _find_card_owner_or_zone_owner(target)
	if owner:
		_remove_card_from_owner_zones(owner, target)
		target.move_to_zone("banished")
		owner.banished.append(target)
		EventBus.card_banished.emit(target)


func _cleanse_effect_target(target: CardInstance) -> void:
	target.cleanse()
	EventBus.message_shown.emit("Cleanse: %s cleansed" % target.data.name)


func _move_card_to_graveyard(owner: PlayerState, card: CardInstance) -> void:
	_remove_card_from_owner_zones(owner, card)
	card.move_to_zone("graveyard")
	owner.graveyard.append(card)
	EventBus.card_discarded.emit(card, owner.player_id)


func _remove_card_from_owner_zones(owner: PlayerState, card: CardInstance) -> void:
	if card in owner.get_all_board_units():
		owner.remove_from_board(card)
		EventBus.card_removed_from_board.emit(card)
	if card in owner.hand:
		owner.remove_from_hand(card)
	if card in owner.graveyard:
		owner.graveyard.erase(card)
	if card in owner.banished:
		owner.banished.erase(card)


func _expand_area_targets(target: CardInstance, effect: CardEffect) -> Array:
	var result: Array = [target]
	if not effect.area:
		return result
	var owner: PlayerState = _find_card_owner(target)
	if not owner:
		return result
	var pos: Dictionary = owner.find_card_position(target)
	if pos.is_empty():
		return result
	for adjacent in BoardManager.get_adjacent_cards(owner, pos["row"], pos["col"]):
		if not (adjacent in result):
			result.append(adjacent)
	return result


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
		"knight":
			_complex_knight(source)
		"tax_er":
			_complex_tax_er(source)
		"fukacia_pracicka":
			_complex_fukacia_pracicka(source)
		"everything_here_here":
			_complex_everything_here_here(source)
		"sibal_so_sledovanim_lucov":
			_complex_sibal_so_sledovanim_lucov(source)
		"the_lion_does_not_care":
			_complex_the_lion_does_not_care(source)
		"sir_vival":
			_complex_sir_vival(source, effect)
		"biblography":
			_complex_biblography(source, effect)
		"the_prophet":
			_complex_the_prophet(source, effect)
		"opakovacia_dedinka":
			_complex_opakovacia_dedinka(source)
		"breakthru":
			_complex_breakthru(source)
		"dawood":
			_complex_dawood(source)
		"discard_this_card":
			_complex_discard_this_card(source)
		"claws_the_production":
			_complex_claws_the_production(source)
		"my_country_called_me":
			_complex_my_country_called_me(source)
		"negromancy":
			_complex_negromancy(source, ["Common", "Rare"])
		"negromancy_premium":
			_complex_negromancy(source, ["Epic", "Legendary"])
		"sellers_sailors":
			_complex_sellers_sailors(source)
		"premium_account":
			_complex_premium_account(source, effect)
		"scrolling_papers":
			_complex_scrolling_papers(source)
		"damina":
			_complex_damina(source, effect)
		"trembling_lips":
			_complex_trembling_lips(source, effect)
		"miss_spell":
			_complex_miss_spell(source)
		"mikrofo_novy_pokles":
			_complex_mikrofo_novy_pokles(source)
		"the_why_axes":
			_complex_the_why_axes(source)
		"sir_veillance":
			_complex_sir_veillance(source)
		"obratnost_ruk":
			_complex_obratnost_ruk(source)
		"mr_rural":
			_complex_mr_rural(source, effect)
		"velke_jazykove_monstrum":
			_complex_velke_jazykove_monstrum(source, effect)
		"nak_mitchrbat":
			_complex_nak_mitchrbat(source)
		"masovystit":
			_complex_masovystit(source)
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


func _complex_knight(source: CardInstance) -> void:
	var player: PlayerState = _get_controller(source)
	if not player:
		return
	var enemy_hero: CardInstance = _get_enemy_hero(player)
	if enemy_hero:
		_apply_damage(source, enemy_hero, 1)


func _complex_tax_er(source: CardInstance) -> void:
	var player: PlayerState = _get_controller(source)
	if not player:
		return
	for p in game_state.players:
		if p.player_id == player.player_id:
			continue
		var unpaid: int = 0
		if p.sellary < 2:
			unpaid = 2 - p.sellary
			p.sellary = 0
		else:
			p.sellary -= 2
		if unpaid > 0 and p.hero:
			for i in range(unpaid):
				_apply_damage(source, p.hero, 1)
		EventBus.sellary_seized.emit(p.player_id, player.player_id, 2 - unpaid)
		EventBus.message_shown.emit("Tax 'er!: took %d, unpaid %d" % [2 - unpaid, unpaid])
		break


func _complex_fukacia_pracicka(source: CardInstance) -> void:
	var player: PlayerState = _get_controller(source)
	if not player:
		return
	var targets: Array = []
	for p in game_state.players:
		for card in p.get_all_board_units():
			if card.data.type != "Hero":
				targets.append(card)
	if targets.is_empty():
		return
	EventBus.target_requested.emit(targets, func(target: CardInstance) -> void:
		var heal_amount: int = target.data.base_power - target.current_power
		if heal_amount > 0:
			target.apply_heal(heal_amount)
			EventBus.heal_applied.emit(target, heal_amount)
		target.cleanse()
		EventBus.message_shown.emit("Fúkacia Prácička: healed %d + cleansed %s" % [heal_amount, target.data.name])
	)


func _complex_everything_here_here(source: CardInstance) -> void:
	var player: PlayerState = _get_controller(source)
	if not player:
		return
	if player.is_board_full():
		player.extra_card_plays += 3
		EventBus.message_shown.emit("Everything Here Here: +3 extra plays")


func _complex_sibal_so_sledovanim_lucov(source: CardInstance) -> void:
	var player: PlayerState = _get_controller(source)
	if not player:
		return
	# Draw 3 faction
	var drawn: int = 0
	for i in range(3):
		var card: CardInstance = player.draw_faction_card()
		if card:
			EventBus.card_drawn.emit(card, player.player_id, "ability")
			drawn += 1
	# Shuffle 3 back
	var shuffled: int = 0
	while shuffled < 3 and not player.hand.is_empty():
		var card: CardInstance = player.hand[player.hand.size() - 1]
		player.remove_from_hand(card)
		card.move_to_zone("faction_deck")
		player.faction_deck.append(card)
		shuffled += 1
	player.faction_deck.shuffle()
	EventBus.message_shown.emit("Šibal so sledovaním lúčov: drew %d, shuffled %d back" % [drawn, shuffled])


func _complex_the_lion_does_not_care(source: CardInstance) -> void:
	var player: PlayerState = _get_controller(source)
	if not player:
		return
	player.free_plays_turn = true
	EventBus.message_shown.emit("The Lion Does Not Care: expenses negated this turn")


func _complex_sir_vival(source: CardInstance, effect: CardEffect) -> void:
	var player: PlayerState = _get_controller(source)
	if not player:
		# Try to find by owner when in graveyard
		for p in game_state.players:
			if p.player_id == source.owner_id:
				player = p
				break
	if not player:
		return

	if effect.trigger == "turn_start":
		if source.zone == "graveyard":
			var idx: int = player.graveyard.find(source)
			if idx >= 0:
				player.graveyard.remove_at(idx)
			var free_row: int = -1
			var free_col: int = -1
			for row_idx in range(player.board.size()):
				var col: int = player.find_free_col(row_idx)
				if col >= 0:
					free_row = row_idx
					free_col = col
					break
			if free_row >= 0:
				player.place_on_board(source, free_row, free_col)
				EventBus.card_placed_on_board.emit(source, free_row, free_col)
				EventBus.message_shown.emit("Sir Vival: returned from graveyard")

	elif effect.trigger == "turn_end":
		var right: CardInstance = player.get_right_neighbor(source)
		if right:
			right.apply_heal(1)
			EventBus.heal_applied.emit(right, 1)


func _complex_biblography(source: CardInstance, effect: CardEffect) -> void:
	if effect.trigger != "turn_end":
		return
	var player: PlayerState = _get_controller(source)
	if not player:
		return
	if not player.spend_sellary(2):
		EventBus.message_shown.emit("Biblography: can't afford upkeep 2")
		return
	var row_mates: Array[CardInstance] = player.get_cards_in_row(source)
	for card in row_mates:
		if card.data.type != "Artifact":
			card.apply_heal(1)
			EventBus.heal_applied.emit(card, 1)
	EventBus.message_shown.emit("Biblography: healed %d row units" % row_mates.size())


func _complex_the_prophet(source: CardInstance, effect: CardEffect) -> void:
	var player: PlayerState = _get_controller(source)
	if not player:
		return

	if effect.trigger == "upkeep":
		# Cost already deducted by _check_costs; nothing else to do
		return

	if effect.trigger == "turn_end":
		var has_sfp: bool = _controls_card_id(player, "self_fulfilling_prophecy")
		var hp: int = source.current_power
		if hp % 2 == 0:
			# Even health
			var enemy_hero: CardInstance = _get_enemy_hero(player)
			if has_sfp:
				# Damage enemy hero + boost self
				if enemy_hero:
					_apply_damage(source, enemy_hero, 1)
				source.apply_boost(1)
				EventBus.boost_applied.emit(source, 1)
			else:
				# Damage enemy hero + damage self
				if enemy_hero:
					_apply_damage(source, enemy_hero, 1)
				source.apply_damage(1)
				EventBus.damage_dealt.emit(source, 1, source)
				if source.current_power <= 0:
					game_state._destroy_card(source, player)
		else:
			# Odd health: boost self + adjacent units
			source.apply_boost(1)
			EventBus.boost_applied.emit(source, 1)
			for neighbor in player.get_row_neighbors(source):
				neighbor.apply_boost(1)
				EventBus.boost_applied.emit(neighbor, 1)


func _complex_opakovacia_dedinka(source: CardInstance) -> void:
	var player: PlayerState = _get_controller(source)
	if not player:
		return
	var last: CardData = game_state.last_spell_played
	if not last:
		EventBus.message_shown.emit("Opakovacia Dedinka: no spell to replay")
		return
	var inst: CardInstance = CardInstance.create(last, player.player_id)
	inst.zone = "hand"
	game_state._resolve_spell(inst, player)
	EventBus.message_shown.emit("Opakovacia Dedinka: replayed %s" % last.name)


func _complex_breakthru(source: CardInstance) -> void:
	var player: PlayerState = _get_controller(source)
	if not player:
		return
	var targets: Array = _get_enemy_board_cards(player)
	if targets.size() < 2:
		EventBus.message_shown.emit("Breakthru needs two enemy cards.")
		return
	EventBus.target_requested.emit(targets, func(first: CardInstance) -> void:
		var remaining: Array = targets.duplicate()
		remaining.erase(first)
		EventBus.target_requested.emit(remaining, func(second: CardInstance) -> void:
			var owner: PlayerState = _find_card_owner(first)
			if owner and owner == _find_card_owner(second) and owner.swap_board_positions(first, second):
				EventBus.message_shown.emit("Breakthru swapped %s and %s." % [first.data.name, second.data.name])
		)
	)


func _complex_dawood(source: CardInstance) -> void:
	var player: PlayerState = _get_controller(source)
	if not player:
		return
	EventBus.choice_requested.emit("Dawood", [
		{"label": "Boost a non-hero unit", "detail": "+2 power to a chosen unit.", "value": "boost"},
		{"label": "Damage a non-hero unit", "detail": "Deal 1 damage to a chosen unit.", "value": "damage"},
	], func(choice: String) -> void:
		var targets: Array = _get_board_cards_by_filter("any", "unit", player)
		if targets.is_empty():
			EventBus.message_shown.emit("No unit target.")
			return
		EventBus.target_requested.emit(targets, func(target: CardInstance) -> void:
			if choice == "boost":
				target.apply_boost(2)
				EventBus.boost_applied.emit(target, 2)
			else:
				_apply_damage(source, target, 1)
		)
	)


func _complex_discard_this_card(source: CardInstance) -> void:
	var opponent: PlayerState = _get_enemy_player(source)
	if not opponent or opponent.hand.is_empty():
		EventBus.message_shown.emit("Opponent has no hand to discard.")
		return
	opponent.hand.shuffle()
	var card: CardInstance = opponent.hand.pop_front()
	card.move_to_zone("graveyard")
	opponent.graveyard.append(card)
	EventBus.card_discarded.emit(card, opponent.player_id)
	EventBus.message_shown.emit("Discarded %s from opponent." % card.data.name)


func _complex_claws_the_production(source: CardInstance) -> void:
	var opponent: PlayerState = _get_enemy_player(source)
	if not opponent:
		return
	opponent.base_sellary_modifier_next_turn -= 2
	EventBus.message_shown.emit("Opponent loses 2 base sellary next turn.")


func _complex_my_country_called_me(source: CardInstance) -> void:
	var opponent: PlayerState = _get_enemy_player(source)
	if not opponent:
		return
	opponent.suppress_end_turn_next_turn = true
	EventBus.message_shown.emit("Opponent's next end-of-turn abilities are suppressed.")


func _complex_negromancy(source: CardInstance, rarities: Array[String]) -> void:
	var player: PlayerState = _get_controller(source)
	if not player:
		return
	var candidates: Array[CardInstance] = player.get_graveyard_cards_by_rarity(rarities)
	if candidates.is_empty():
		EventBus.message_shown.emit("No graveyard card of matching rarity.")
		return
	var options: Array = []
	for card in candidates:
		options.append({"label": "%s (%s %s)" % [card.data.name, card.data.rarity, card.data.type], "value": card})
	EventBus.choice_requested.emit("Replay from graveyard", options, func(card: CardInstance) -> void:
		if game_state.replay_from_graveyard(player, card, true):
			EventBus.message_shown.emit("Replayed %s with Cursed." % card.data.name)
	)


func _complex_sellers_sailors(source: CardInstance) -> void:
	var player: PlayerState = _get_controller(source)
	if not player:
		return
	for card_id in ["the_parrot", "the_ship", "the_captain", "the_mate"]:
		game_state.spawn_card_for_player(player, card_id)
	EventBus.message_shown.emit("Summoned The Crew.")


func _complex_premium_account(source: CardInstance, effect: CardEffect) -> void:
	var player: PlayerState = _get_controller(source)
	if not player:
		return
	if effect.trigger == "tribute":
		for i in range(2):
			game_state.spawn_card_for_player(player, "neural_network", source)
		EventBus.message_shown.emit("Premium Account spawned Neural Networks.")
	else:
		var count: int = 0
		for card in player.get_all_board_units():
			if "A.I." in card.data.categories or "A.I. Gods" in card.data.factions:
				count += 1
		player.gain_sellary(count)
		EventBus.message_shown.emit("Premium Account profit %d." % count)


func _complex_scrolling_papers(source: CardInstance) -> void:
	var player: PlayerState = _get_controller(source)
	if not player:
		return
	EventBus.choice_requested.emit("Look through top 3", [
		{"label": "Neutral deck", "detail": "Reveal the next 3 shared cards.", "value": "neutral"},
		{"label": "Faction deck", "detail": "Reveal the next 3 cards from your faction deck.", "value": "faction"},
	], func(deck_name: String) -> void:
		var cards: Array = game_state.neutral_deck if deck_name == "neutral" else player.faction_deck
		var names: Array[String] = []
		var revealed: Array = []
		for i in range(mini(3, cards.size())):
			names.append(cards[i].data.name)
			revealed.append(cards[i])
		EventBus.ability_panel_requested.emit("%s top cards" % deck_name.capitalize(), revealed)
		EventBus.message_shown.emit("%s top: %s" % [deck_name.capitalize(), ", ".join(names)])
	)


func _complex_damina(source: CardInstance, effect: CardEffect) -> void:
	var player: PlayerState = _get_controller(source)
	if not player:
		return
	match effect.trigger:
		"deploy":
			if _controls_card_id(player, "trembling_lips"):
				source.apply_boost(1)
				EventBus.boost_applied.emit(source, 1)
			elif game_state.play_specific_from_deck_or_graveyard(player, "trembling_lips", source):
				EventBus.message_shown.emit("Damina played Trembling Lips.")
		"turn_start":
			EventBus.message_shown.emit("Damina counter: %d." % source.counter)
		"order":
			if source.counter > 0:
				if effect.charges > 0:
					source.gain_charge(effect.charges)
				EventBus.message_shown.emit("Damina counter is not 0.")
				return
			var targets: Array = _get_board_cards_by_filter("any", "hero", player)
			EventBus.target_requested.emit(targets, func(target: CardInstance) -> void:
				_apply_damage(source, target, 5)
			)


func _complex_trembling_lips(source: CardInstance, effect: CardEffect) -> void:
	var player: PlayerState = _get_controller(source)
	if not player:
		return
	match effect.trigger:
		"deploy":
			if _controls_card_id(player, "damina"):
				source.apply_boost(1)
				EventBus.boost_applied.emit(source, 1)
			elif game_state.play_specific_from_deck_or_graveyard(player, "damina", source):
				EventBus.message_shown.emit("Trembling Lips played Damina.")
		"turn_start":
			if source.timer % 2 != 0:
				return
			var pos: Dictionary = player.find_card_position(source)
			if pos.is_empty():
				return
			for card in player.board[pos["row"]]:
				card.apply_status("Invisible", 1)
				EventBus.status_applied.emit(card, "Invisible", 1)
			for opponent in game_state.players:
				if opponent.player_id == player.player_id:
					continue
				for card in opponent.board[pos["row"]]:
					card.apply_status("Invisible", 1)
					EventBus.status_applied.emit(card, "Invisible", 1)


func _complex_miss_spell(source: CardInstance) -> void:
	var player: PlayerState = _get_controller(source)
	if not player:
		return
	var target := _get_enemy_hero(player)
	if not target:
		return
	target.apply_status("Miss Spell", 1)
	EventBus.status_applied.emit(target, "Miss Spell", 1)
	EventBus.message_shown.emit("Miss Spell applied to enemy hero.")


func _complex_mikrofo_novy_pokles(source: CardInstance) -> void:
	var player: PlayerState = _get_controller(source)
	if not player:
		return
	if player.cards_played_this_turn > 1:
		EventBus.message_shown.emit("Mikrofonovy Pokles must be your first action.")
		return
	var amount: int = player.sellary
	if amount <= 0:
		EventBus.message_shown.emit("No sellary to spend.")
		return
	player.spend_sellary(amount)
	var targets: Array = _get_board_cards_by_filter("any", "unit", player)
	if targets.is_empty():
		EventBus.message_shown.emit("No unit target.")
		return
	EventBus.target_requested.emit(targets, func(target: CardInstance) -> void:
		_apply_damage(source, target, amount)
	)


func _complex_the_why_axes(source: CardInstance) -> void:
	EventBus.choice_requested.emit("Choose row", [
		{"label": "Melee", "detail": "Front row, 5 slots.", "value": 0},
		{"label": "Ranged", "detail": "Middle row, 5 slots.", "value": 1},
		{"label": "Artillery", "detail": "Back row, 3 slots.", "value": 2},
	], func(row_idx: int) -> void:
		var cards: Array[CardInstance] = []
		for player in game_state.players:
			for card in player.board[row_idx]:
				if card.data.type == "Unit":
					cards.append(card)
		if cards.is_empty():
			EventBus.message_shown.emit("No units on that row.")
			return
		var total := 0
		for card in cards:
			total += card.current_power
		var average: int = total / cards.size()
		for card in cards:
			card.current_power = average
		EventBus.message_shown.emit("The Why Axes set row power to %d." % average)
	)


func _complex_sir_veillance(source: CardInstance) -> void:
	var opponent: PlayerState = _get_enemy_player(source)
	if not opponent:
		return
	if opponent.hand.is_empty():
		EventBus.message_shown.emit("Opponent hand is empty.")
		return
	var names: Array[String] = []
	for card in opponent.hand:
		names.append("%s (%s)" % [card.data.name, card.data.rarity])
	EventBus.message_shown.emit("Opponent hand: %s" % ", ".join(names))


func _complex_obratnost_ruk(source: CardInstance) -> void:
	var player: PlayerState = _get_controller(source)
	if not player:
		return
	var best_player: PlayerState = null
	var best_score := -1
	var rolls: Array[String] = []
	for participant in game_state.players:
		var score: int
		if participant.player_id == player.player_id:
			score = maxi(randi_range(1, 20), randi_range(1, 20))
		else:
			score = randi_range(1, 20)
		rolls.append("%s=%d" % ["You" if participant.player_id == player.player_id else "Opponent", score])
		if score > best_score:
			best_score = score
			best_player = participant
	if not best_player:
		return
	for participant in game_state.players:
		if participant.player_id == best_player.player_id:
			continue
		var amount: int = mini(4, participant.sellary)
		participant.sellary -= amount
		best_player.gain_sellary(amount)
		EventBus.sellary_seized.emit(participant.player_id, best_player.player_id, amount)
	EventBus.message_shown.emit("Obratnost Ruk: %s. %s seized 4." % [
		", ".join(rolls),
		"You" if best_player.player_id == player.player_id else "Opponent",
	])


func _complex_mr_rural(source: CardInstance, effect: CardEffect) -> void:
	var player: PlayerState = _get_controller(source)
	if not player:
		return
	match effect.trigger:
		"turn_start", "upkeep":
			var egg_count := 0
			for card in player.hand:
				if card.data.id == "egg":
					egg_count += 1
			if egg_count <= 0:
				EventBus.message_shown.emit("Mr. Rural: no eggs in hand.")
				return
			var targets: Array = _get_board_cards_by_filter("enemy", "non_unit", player)
			if targets.is_empty():
				EventBus.message_shown.emit("Mr. Rural: no non-unit target.")
				return
			EventBus.target_requested.emit(targets, func(target: CardInstance) -> void:
				_apply_damage(source, target, egg_count)
			)
		"pay":
			for participant in game_state.players:
				_create_card_in_hand(participant, "egg")
			EventBus.message_shown.emit("Both players drew an Egg.")


func _complex_velke_jazykove_monstrum(source: CardInstance, effect: CardEffect) -> void:
	match effect.trigger:
		"deploy":
			source.ability_state["monster_slots"] = []
			_choose_monster_slot(source)
		"turn_end":
			var slots: Array = source.ability_state.get("monster_slots", [])
			if slots.is_empty():
				EventBus.message_shown.emit("Jazykove Monstrum has no chosen slots.")
				return
			var roll_idx: int = randi_range(0, mini(3, slots.size() - 1))
			var slot: Dictionary = slots[roll_idx]
			var player := _get_player_by_id(slot.get("player_id", -1))
			if not player:
				return
			var target := BoardManager.get_card_at(player, slot.get("row", -1), slot.get("col", -1))
			if not target or target.data.type != "Unit":
				EventBus.message_shown.emit("Jazykove Monstrum rolled an empty slot.")
				return
			target.apply_status("Poison", 1)
			EventBus.status_applied.emit(target, "Poison", 1)
			_apply_damage(source, target, 1)


func _complex_nak_mitchrbat(source: CardInstance) -> void:
	var player: PlayerState = _get_controller(source)
	if not player:
		return
	var cards: Array = player.get_all_board_units()
	if cards.size() < 2:
		EventBus.message_shown.emit("Need two own cards to rearrange.")
		return
	EventBus.target_requested.emit(cards, func(first: CardInstance) -> void:
		var remaining: Array = cards.duplicate()
		remaining.erase(first)
		EventBus.target_requested.emit(remaining, func(second: CardInstance) -> void:
			if player.swap_board_positions(first, second):
				EventBus.message_shown.emit("Swapped %s and %s." % [first.data.name, second.data.name])
		)
	)


func _complex_masovystit(_source: CardInstance) -> void:
	# The actual redirect is handled by _on_damage_dealt so it can react globally.
	pass


func _resolve_cleanse(source: CardInstance, _effect: CardEffect) -> void:
	var targets: Array = _get_effect_targets(source, _effect)
	if targets.is_empty():
		return
	if _effect.needs_target():
		EventBus.target_requested.emit(targets, func(target: CardInstance) -> void:
			_cleanse_effect_target(target)
		)
	else:
		for target in targets:
			_cleanse_effect_target(target)


func _resolve_discard(source: CardInstance, effect: CardEffect) -> void:
	var player: PlayerState = _get_controller(source)
	if not player:
		return
	if effect.target_scope == "self":
		_move_card_to_graveyard(player, source)
		return
	var players_to_scan: Array[PlayerState] = []
	match effect.target_scope:
		"ally":
			players_to_scan.append(player)
		"any":
			for p in game_state.players:
				players_to_scan.append(p)
		_:
			for p in game_state.players:
				if p.player_id != player.player_id:
					players_to_scan.append(p)
	var candidates: Array[CardInstance] = []
	for p in players_to_scan:
		for card in p.hand:
			candidates.append(card)
	if candidates.is_empty():
		return
	var options: Array = []
	for card in candidates:
		options.append({"label": "%s (%s)" % [card.data.name, card.data.rarity], "value": card})
	EventBus.choice_requested.emit("Discard", options, func(target: CardInstance) -> void:
		var owner := _find_card_owner_or_zone_owner(target)
		if owner:
			_move_card_to_graveyard(owner, target)
	)


# ── Helpers ──────────────────────────────────────────────────────────────────

func _choose_monster_slot(source: CardInstance) -> void:
	var selected: Array = source.ability_state.get("monster_slots", [])
	if selected.size() >= 4:
		EventBus.message_shown.emit("Jazykove Monstrum marked 4 slots.")
		return

	var options: Array = []
	for player in game_state.players:
		for row_idx in range(GameConstants.ROW_CAPACITIES.size()):
			for col_idx in range(GameConstants.ROW_CAPACITIES[row_idx]):
				var slot := {"player_id": player.player_id, "row": row_idx, "col": col_idx}
				if _slot_is_selected(selected, slot):
					continue
				options.append({
					"label": "%s %s %d" % ["Your" if player.player_id == source.controller_id else "Opponent", _row_name(row_idx), col_idx + 1],
					"detail": "Mark this slot for the monster effect.",
					"value": slot,
				})

	EventBus.choice_requested.emit("Choose slot %d/4" % [selected.size() + 1], options, func(slot: Dictionary) -> void:
		selected.append(slot)
		source.ability_state["monster_slots"] = selected
		_choose_monster_slot(source)
	)


func _slot_is_selected(selected: Array, slot: Dictionary) -> bool:
	for item in selected:
		if item.get("player_id") == slot.get("player_id") and item.get("row") == slot.get("row") and item.get("col") == slot.get("col"):
			return true
	return false


func _row_name(row_idx: int) -> String:
	match row_idx:
		0:
			return "Melee"
		1:
			return "Ranged"
		_:
			return "Artillery"


func _create_card_in_hand(player: PlayerState, card_id: String) -> CardInstance:
	var data: CardData = CardDatabase.get_card(card_id)
	if not data:
		return null
	var card := CardInstance.create(data, player.player_id)
	card.zone = "hand"
	player.add_to_hand(card)
	EventBus.card_drawn.emit(card, player.player_id, "created")
	return card


func _apply_masovystit_redirect(target: CardInstance, amount: int, damage_source: CardInstance) -> void:
	var owner: PlayerState = _find_card_owner(target)
	if not owner:
		return
	var pos: Dictionary = owner.find_card_position(target)
	if pos.is_empty():
		return
	var shield_row: int = pos["row"] - 1
	if shield_row < 0:
		return
	var shield := BoardManager.get_card_at(owner, shield_row, pos["col"])
	if not shield or shield.data.id != "masovystit" or shield == target:
		return
	target.current_power += amount
	EventBus.heal_applied.emit(target, amount)
	var redirected_damage := amount * 2
	var actual := shield.apply_damage(redirected_damage)
	EventBus.damage_dealt.emit(shield, actual, damage_source)
	EventBus.message_shown.emit("MasovyStit redirected %d damage." % amount)
	if shield.current_power <= 0:
		game_state._destroy_card(shield, owner)


func _get_player_by_id(player_id: int) -> PlayerState:
	for player in game_state.players:
		if player.player_id == player_id:
			return player
	return null

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


func _find_card_owner_or_zone_owner(card: CardInstance) -> PlayerState:
	var owner := _find_card_owner(card)
	if owner:
		return owner
	for p in game_state.players:
		if card in p.hand or card in p.graveyard or card in p.banished:
			return p
		if p.player_id == card.owner_id:
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


func _get_enemy_board_cards(player: PlayerState) -> Array:
	var result: Array = []
	for p in game_state.players:
		if p.player_id == player.player_id:
			continue
		for card in p.get_all_board_units():
			result.append(card)
	return result


func _get_board_cards_by_filter(scope: String, kind: String, source_player: PlayerState) -> Array:
	var effect := CardEffect.new()
	effect.target_scope = scope
	effect.target_kind = kind
	effect.requires_target = true
	var source := source_player.hero
	if source_player.get_all_board_units().size() > 0:
		source = source_player.get_all_board_units()[0]
	if not source:
		return []
	return _get_effect_targets(source, effect)


func _controls_card_id(player: PlayerState, card_id: String) -> bool:
	"""True if the player has a card with the given ID on their board."""
	for card in player.get_all_board_units():
		if card.data.id == card_id:
			return true
	return false


func _get_effect_targets(source: CardInstance, effect: CardEffect) -> Array:
	if effect.target_scope == "self":
		return [source]

	var source_player: PlayerState = _get_controller(source)
	if not source_player:
		return []

	var players_to_scan: Array[PlayerState] = []
	match effect.target_scope:
		"ally":
			players_to_scan.append(source_player)
		"any":
			for p in game_state.players:
				players_to_scan.append(p)
		_:
			for p in game_state.players:
				if p.player_id != source_player.player_id:
					players_to_scan.append(p)

	var targets: Array = []
	for player in players_to_scan:
		match effect.target_kind:
			"hero":
				if player.hero and player.hero.current_power > 0:
					targets.append(player.hero)
			"artifact":
				for card in player.get_all_board_units():
					if card.data.type == "Artifact":
						targets.append(card)
			"unit":
				for card in player.get_all_board_units():
					if card.data.type == "Unit":
						targets.append(card)
			"non_hero":
				for card in player.get_all_board_units():
					targets.append(card)
			"non_unit":
				for card in player.get_all_board_units():
					if card.data.type != "Unit":
						targets.append(card)
				if player.hero and player.hero.current_power > 0:
					targets.append(player.hero)
			_:
				for card in player.get_all_board_units():
					targets.append(card)
				if player.hero and player.hero.current_power > 0:
					targets.append(player.hero)

	var filtered: Array = []
	for target in targets:
		if target == source and effect.target_scope != "self":
			continue
		if target.is_invisible() and effect.needs_target():
			continue
		if _is_blocked_by_protector_or_defender(target):
			continue
		filtered.append(target)
	return filtered


func _is_blocked_by_protector_or_defender(target: CardInstance) -> bool:
	var owner: PlayerState = _find_card_owner(target)
	if not owner:
		return false
	if target == owner.hero:
		for card in owner.get_all_board_units():
			if card.has_status("Protector"):
				return true
	var pos: Dictionary = owner.find_card_position(target)
	if pos.is_empty():
		return false
	for card in owner.board[pos["row"]]:
		if card != target and card.has_status("Defender") and not target.has_status("Defender"):
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
