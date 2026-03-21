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

## Timer value (counts down each turn).
var timer: int = 0

## Charge counter (for Order abilities).
var charges: int = 0

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
		if effect.charges > 0:
			inst.charges = effect.charges
	
	return inst


# ── State Queries ────────────────────────────────────────────────────────────

func is_alive() -> bool:
	return current_power > 0 and zone == "board"


func is_on_board() -> bool:
	return zone == "board"


func is_in_hand() -> bool:
	return zone == "hand"


func get_status_stacks(status_name: String) -> int:
	return statuses.get(status_name, 0)


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
	return actual


func apply_boost(amount: int) -> void:
	current_power += amount


func apply_heal(amount: int) -> void:
	"""Heal up to base power."""
	current_power = mini(current_power + amount, data.base_power)


func apply_status(status_name: String, stacks: int = 1) -> void:
	if status_name in statuses:
		statuses[status_name] += stacks
	else:
		statuses[status_name] = stacks


func remove_status(status_name: String) -> void:
	statuses.erase(status_name)


func cleanse() -> void:
	"""Remove all non-permanent statuses."""
	var to_remove: Array = []
	for s in statuses:
		# Tokens have permanent Cursed — don't cleanse it
		if s == "Cursed" and data.is_token():
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


func move_to_zone(new_zone: String) -> void:
	zone = new_zone
	if new_zone != "board":
		board_position = {}


func place_on_board(row: int, col: int) -> void:
	zone = "board"
	board_position = {"row": row, "col": col}


func reset_turn_state() -> void:
	activated_this_turn = false
