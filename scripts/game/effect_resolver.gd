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
	"""Main dispatch — resolve a single effect."""
	# Check costs first
	if not _check_costs(card, effect):
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
	"""Deal damage to a target. Requires target selection."""
	# TODO: Integrate with UI targeting system
	# For now, emit target request and wait for callback
	var targets: Array = _get_valid_damage_targets(source)
	if targets.is_empty():
		return
	
	# Placeholder: apply to first valid target (replace with UI targeting)
	var target: CardInstance = targets[0]
	var damage: int = effect.value
	
	# Check Perplexed (50% chance to hit own hero)
	if source.has_status("Perplexed"):
		if randf() < 0.5:
			var player: PlayerState = _get_controller(source)
			if player and player.hero:
				target = player.hero
	
	# Check Drunk (miss chance)
	if source.has_status("Drunk"):
		var miss_chance: float = source.get_status_stacks("Drunk") * 0.25
		if randf() < miss_chance:
			EventBus.message_shown.emit("%s missed (Drunk)!" % source.data.name)
			# Check Abeer faction crit instead
			if "Abeer Dawood Salman" in source.data.factions:
				var crit_chance: float = source.get_status_stacks("Drunk") * 0.25
				if randf() < crit_chance:
					damage *= 2
					EventBus.message_shown.emit("%s crits! (Abeer Drunk)" % source.data.name)
				else:
					return  # Miss
			else:
				return  # Miss
	
	var actual_damage: int = target.apply_damage(damage)
	EventBus.damage_dealt.emit(target, actual_damage, source)
	
	# Check Vulnerable — extra damage at end of turn (handled in status trigger)
	
	# Check if killed
	if target.current_power <= 0:
		var owner: PlayerState = _find_card_owner(target)
		if owner:
			game_state._destroy_card(target, owner)
		# Deathblow trigger
		for eff in source.data.effects:
			if eff.trigger == "deathblow":
				EventBus.deathblow_triggered.emit(source, target)
				EventBus.ability_triggered.emit(source, eff)


func _resolve_boost(source: CardInstance, effect: CardEffect) -> void:
	# Default: boost self. Targeting handled by complex abilities.
	source.apply_boost(effect.value)
	EventBus.boost_applied.emit(source, effect.value)


func _resolve_heal(source: CardInstance, effect: CardEffect) -> void:
	source.apply_heal(effect.value)
	EventBus.heal_applied.emit(source, effect.value)


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
	# Draw from neutral deck (free draws from abilities)
	for i in range(effect.value):
		if game_state.neutral_deck.is_empty():
			break
		var card: CardInstance = game_state.neutral_deck.pop_front() as CardInstance
		card.owner_id = player.player_id
		card.controller_id = player.player_id
		player.add_to_hand(card)
		EventBus.card_drawn.emit(card, player.player_id, "ability")


func _resolve_apply_status(_source: CardInstance, effect: CardEffect) -> void:
	"""Apply a status to a target. Requires target selection."""
	# TODO: Integrate with UI targeting
	# Placeholder
	EventBus.message_shown.emit("Apply %s %d — select target" % [effect.status, effect.stacks])


func _resolve_destroy(_source: CardInstance, _effect: CardEffect) -> void:
	"""Destroy a target. Requires target selection."""
	# TODO: Integrate with UI targeting
	EventBus.message_shown.emit("Destroy — select target")


func _resolve_banish(_source: CardInstance, _effect: CardEffect) -> void:
	"""Banish a target (remove from game, no Last Word)."""
	# TODO: Integrate with UI targeting
	EventBus.message_shown.emit("Banish — select target")


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
			# Place on opponent's melee row if possible
			for row_idx in range(p.board.size()):
				if p.place_on_board(source, row_idx):
					break
			break


func _resolve_devour(source: CardInstance, _effect: CardEffect) -> void:
	"""Destroy an allied unit, boost self by its power."""
	# TODO: Integrate with UI targeting for ally selection
	EventBus.message_shown.emit("%s — select ally to Devour" % source.data.name)


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
	"""Fallback for effects that need custom implementation."""
	push_warning("[EffectResolver] Complex effect on %s: %s" % [source.data.name, effect.raw_text])


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


func _get_valid_damage_targets(source: CardInstance) -> Array:
	"""Get all valid targets for a damage effect."""
	var targets: Array = []
	var player: PlayerState = _get_controller(source)
	if not player:
		return targets
	
	for p in game_state.players:
		if p.player_id == player.player_id:
			continue  # Skip own units
		# Add opponent's board units (excluding invisible)
		for card in p.get_all_board_units():
			if not card.is_invisible():
				targets.append(card)
		# If no units, hero becomes valid target
		if p.get_board_unit_count() == 0 and p.hero:
			targets.append(p.hero)
	
	return targets
