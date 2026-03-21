## BoardManager
## Manages the physical board layout: two sides (one per player),
## each with 3 rows (melee 5, ranged 5, artillery 3).
## Handles adjacency calculations for Area effects.
class_name BoardManager
extends Node

# ── Board Structure ──────────────────────────────────────────────────────────
# Each player has their own 3-row board.
# The "board" is mirrored: Player 0's melee faces Player 1's melee.
#
# Layout (top = P1 artillery, bottom = P0 artillery):
#   P1 Artillery:  [  ][  ][  ]
#   P1 Ranged:     [  ][  ][  ][  ][  ]
#   P1 Melee:      [  ][  ][  ][  ][  ]
#   ─────────── BATTLEFIELD LINE ───────────
#   P0 Melee:      [  ][  ][  ][  ][  ]
#   P0 Ranged:     [  ][  ][  ][  ][  ]
#   P0 Artillery:  [  ][  ][  ][  ][  ]

const ROW_MELEE := 0
const ROW_RANGED := 1
const ROW_ARTILLERY := 2


# ── Adjacency ────────────────────────────────────────────────────────────────

## Get cards adjacent to a position (same player's board).
## Includes up/down, left/right, and diagonals per the Area keyword.
static func get_adjacent_cards(player: PlayerState, row: int, col: int) -> Array[CardInstance]:
	var adjacent: Array[CardInstance] = []
	
	# All 8 directions
	var directions: Array[Vector2i] = [
		Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(-1, 1),
		Vector2i(0, -1),                    Vector2i(0, 1),
		Vector2i(1, -1),  Vector2i(1, 0),  Vector2i(1, 1),
	]
	
	for dir: Vector2i in directions:
		var r: int = row + dir.x
		var c: int = col + dir.y
		if r < 0 or r >= player.board.size():
			continue
		if c < 0 or c >= player.board[r].size():
			continue
		adjacent.append(player.board[r][c])
	
	return adjacent


## Get all cards in the same row.
static func get_row_cards(player: PlayerState, row: int) -> Array[CardInstance]:
	var result: Array[CardInstance] = []
	if row >= 0 and row < player.board.size():
		for card in player.board[row]:
			result.append(card)
	return result


## Get the card at a specific position. Returns null if empty.
static func get_card_at(player: PlayerState, row: int, col: int) -> CardInstance:
	if row < 0 or row >= player.board.size():
		return null
	if col < 0 or col >= player.board[row].size():
		return null
	return player.board[row][col]


## Check if a position has a Defender or Protector that must be attacked first.
static func has_taunt_in_front(player: PlayerState, target: CardInstance) -> bool:
	"""Check if there's a Defender/Protector blocking attacks to this target."""
	var pos: Dictionary = player.find_card_position(target)
	if pos.is_empty():
		return false
	
	# Defender: must be attacked before other units in same row
	for card in get_row_cards(player, pos["row"]):
		if card != target and card.has_status("Defender"):
			return true
	
	# Protector: must be attacked before the hero
	if target == player.hero:
		for card in player.get_all_board_units():
			if card.has_status("Protector"):
				return true
	
	return false


# ── Activation Order ─────────────────────────────────────────────────────────

## Get all board cards in activation order: melee->artillery, left->right.
static func get_activation_order(player: PlayerState) -> Array[CardInstance]:
	var result: Array[CardInstance] = []
	for row_idx in range(player.board.size()):
		for card in player.board[row_idx]:
			result.append(card)
	return result


# ── Placement Helpers ────────────────────────────────────────────────────────

## Find the first available row for placing a unit.
static func find_available_row(player: PlayerState) -> int:
	"""Returns first non-full row index, or -1 if board is full."""
	for i in range(player.board.size()):
		if not player.is_row_full(i):
			return i
	return -1


## Get valid rows where a card can be placed.
static func get_valid_placement_rows(player: PlayerState) -> Array[int]:
	var result: Array[int] = []
	for i in range(player.board.size()):
		if not player.is_row_full(i):
			result.append(i)
	return result
