## CardInstance
## Runtime state of a single card in play. Wraps a CardData definition
## and tracks mutable game state (current power, statuses, position, etc.).
class_name CardInstance
extends RefCounted

# ── Identity ─────────────────────────────────────────────────────────────────

## The immutable card definition.
var data: CardData

## Unique instance ID (for tracking across zones).
var instance_id: int = -1

## Counter for generating unique IDs.
static var _next_id: int = 0

# ── Mutable State ────────────────────────────────────────────────────────────

## Current power (can change from boost/damage/etc.).
var current_power: int = 0

## Status effects: status_name -> stack count.
var statuses: Dictionary = {}
var permanent_statuses: Dictionary = {}
var damaged_this_turn: bool = false

## Generic scratch state for reusable ability systems.
var ability_state: Dictionary = {}
var effect_uses_this_turn: Dictionary = {}

## Timer value (counts down each turn).
var timer: int = 0

## Charge counter (for Order abilities).
var charges: int = 0
var max_charges: int = 0

## Generic counter (for Counter keyword).
var counter: int = 0

## Block value.
var block: int = 0

## Which zone this card is in.
var zone: String = "deck"  # deck, hand, board, graveyard, banished

## Board position: {row: int, col: int} or empty.
var board_position: Dictionary = {}

## Owner player index.
var owner_id: int = -1

## Controller player index (may differ from owner due to Spy/Control).
var controller_id: int = -1

## Whether the card has been activated this turn.
var activated_this_turn: bool = false


# ── Constructor ──────────────────────────────────────────────────────────────

static func create(card_data: CardData, owner: int) -> CardInstance:
	var inst := CardInstance.new()
	inst.data = card_data
	inst.instance_id = _next_id
	_next_id += 1
	inst.current_power = card_data.base_power
	inst.owner_id = owner
	inst.controller_id = owner
	inst.zone = "deck"
	
	# Initialize timer/charges from effects
	for effect in card_data.effects:
		if effect.timer_value > 0:
			inst.timer = effect.timer_value
		if effect.initial_charges > 0:
			inst.charges = max(inst.charges, effect.initial_charges)
		if effect.max_charges > 0:
			inst.max_charges = max(inst.max_charges, effect.max_charges)
		if effect.counter_threshold > 0 and inst.counter == 0:
			inst.counter = effect.counter_threshold
	
	return inst


# ── State Queries ────────────────────────────────────────────────────────────

func is_alive() -> bool:
	return current_power > 0 and zone == "board"


func is_on_board() -> bool:
	return zone == "board"


func is_in_hand() -> bool:
	return zone == "hand"


func get_status_stacks(status_name: String) -> int:
	return statuses.get(_normalize_status_name(status_name), 0)


func has_status(status_name: String) -> bool:
	return get_status_stacks(status_name) > 0


func is_invisible() -> bool:
	return has_status("Invisible")


func is_cursed() -> bool:
	return has_status("Cursed") or data.is_token()


# ── State Mutations ──────────────────────────────────────────────────────────

func apply_damage(amount: int) -> int:
	"""Apply damage, returns actual damage dealt (after Block)."""
	var blocked: int = mini(amount, block)
	var actual: int = amount - blocked
	current_power = maxi(current_power - actual, 0)
	if actual > 0:
		damaged_this_turn = true
	return actual


func apply_direct_damage(amount: int) -> int:
	"""Apply damage that bypasses Block, such as status damage."""
	var actual: int = maxi(amount, 0)
	current_power = maxi(current_power - actual, 0)
	if actual > 0:
		damaged_this_turn = true
	return actual


func apply_boost(amount: int) -> void:
	current_power += amount


func apply_heal(amount: int) -> void:
	"""Heal up to base power."""
	current_power = mini(current_power + amount, data.base_power)


func missing_health() -> int:
	return maxi(data.base_power - current_power, 0)


func apply_status(status_name: String, stacks: int = 1, permanent: bool = false) -> void:
	var normalized := _normalize_status_name(status_name)
	if normalized in statuses:
		statuses[normalized] += stacks
	else:
		statuses[normalized] = stacks
	if permanent:
		permanent_statuses[normalized] = true


func remove_status(status_name: String) -> void:
	var normalized := _normalize_status_name(status_name)
	statuses.erase(normalized)
	permanent_statuses.erase(normalized)


func cleanse() -> void:
	"""Remove all non-permanent statuses."""
	var to_remove: Array = []
	for s in statuses:
		# Tokens have permanent Cursed — don't cleanse it
		if s == "Cursed" and data.is_token():
			continue
		if permanent_statuses.get(s, false):
			continue
		to_remove.append(s)
	for s in to_remove:
		statuses.erase(s)


func diminish_statuses() -> void:
	"""Reduce all stackable statuses by 1 at end of turn."""
	var to_remove: Array = []
	for status_name in statuses:
		# Permanent statuses don't diminish
		if status_name == "Cursed" and data.is_token():
			continue
		if permanent_statuses.get(status_name, false):
			continue
		# Drunk diminishes every 4 turns (handled separately)
		if status_name == "Drunk":
			continue
		statuses[status_name] -= 1
		if statuses[status_name] <= 0:
			to_remove.append(status_name)
	for s in to_remove:
		statuses.erase(s)


func tick_timer() -> bool:
	"""Reduce timer by 1. Returns true if timer just reached 0."""
	if timer > 0:
		timer -= 1
		return timer == 0
	return false


func use_charge(amount: int = 1) -> bool:
	"""Use charges for Order ability. Returns true if enough charges."""
	if charges >= amount:
		charges -= amount
		return true
	return false


func gain_charge(amount: int = 1) -> void:
	if max_charges > 0:
		charges = mini(charges + amount, max_charges)
	else:
		charges += amount


func change_counter(delta: int) -> void:
	counter = maxi(counter + delta, 0)


func move_to_zone(new_zone: String) -> void:
	zone = new_zone
	if new_zone != "board":
		board_position = {}


func place_on_board(row: int, col: int) -> void:
	zone = "board"
	board_position = {"row": row, "col": col}


func reset_turn_state() -> void:
	activated_this_turn = false
	damaged_this_turn = false
	effect_uses_this_turn.clear()


func _normalize_status_name(status_name: String) -> String:
	var key := status_name.strip_edges().to_lower().replace("_", " ")
	match key:
		"economic fury", "cancerous":
			return "Economic Fury"
		"cursed":
			return "Cursed"
		"crit":
			return "Crit"
		"vulnerable":
			return "Vulnerable"
		"perplexed":
			return "Perplexed"
		"invisible":
			return "Invisible"
		"drunk":
			return "Drunk"
		"defender":
			return "Defender"
		"protector":
			return "Protector"
		"poison":
			return "Poison"
		"burn":
			return "Burn"
		"wither":
			return "Wither"
		_:
			return status_name.capitalize()
