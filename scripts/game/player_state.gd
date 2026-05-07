## PlayerState
## Tracks all runtime state for a single player: hero, hand, board, economy.
class_name PlayerState
extends RefCounted

# ── Identity ─────────────────────────────────────────────────────────────────

var player_id: int = -1
var faction_name: String = ""

# ── Hero ─────────────────────────────────────────────────────────────────────

var hero: CardInstance = null

# ── Zones ────────────────────────────────────────────────────────────────────

## Faction draw pile (shuffled).
var faction_deck: Array[CardInstance] = []
## Cards in hand.
var hand: Array[CardInstance] = []
## Cards on the board, organized by row: [[row0], [row1], [row2]].
var board: Array = [[], [], []]
## Graveyard (destroyed cards).
var graveyard: Array[CardInstance] = []
## Banished cards (removed from game).
var banished: Array[CardInstance] = []

# ── Economy ──────────────────────────────────────────────────────────────────

var sellary: int = 0
var base_sellary: int = 5
var cards_played_this_turn: int = 0
var extra_card_plays: int = 0
var neutral_draws_this_turn: int = 0
var faction_draws_this_turn: int = 0
var free_plays_turn: bool = false
var base_sellary_modifier_next_turn: int = 0
var suppress_end_turn_next_turn: bool = false


# ── Setup ────────────────────────────────────────────────────────────────────

static func create(id: int, faction: String) -> PlayerState:
	var ps := PlayerState.new()
	ps.player_id = id
	ps.faction_name = faction
	ps.base_sellary = GameConstants.BASE_SELLARY
	
	# Create hero
	var hero_data: CardData = CardDatabase.get_hero(faction)
	if hero_data:
		ps.hero = CardInstance.create(hero_data, id)
		ps.hero.zone = "board"
	
	# Build faction deck
	var faction_cards: Array[CardData] = CardDatabase.get_cards_by_faction(faction)
	for card_data in faction_cards:
		if card_data.type == "Hero":
			continue
		if not card_data.has_ability:
			continue
		var inst: CardInstance = CardInstance.create(card_data, id)
		ps.faction_deck.append(inst)
	ps.faction_deck.shuffle()
	
	return ps


# ── Board Queries ────────────────────────────────────────────────────────────

func get_all_board_units() -> Array[CardInstance]:
	"""Get all units on the board (flat list, activation order)."""
	var result: Array[CardInstance] = []
	for row in board:
		for card in row:
			result.append(card)
	return result


func get_board_unit_count() -> int:
	var count: int = 0
	for row in board:
		count += row.size()
	return count


func get_row_count(row_idx: int) -> int:
	if row_idx < 0 or row_idx >= board.size():
		return 0
	return board[row_idx].size()


func is_row_full(row_idx: int) -> bool:
	return find_free_col(row_idx) < 0


func is_board_full() -> bool:
	for i in range(board.size()):
		if not is_row_full(i):
			return false
	return true


func find_card_position(card: CardInstance) -> Dictionary:
	"""Returns {row, col} using the card's stored slot position, or empty dict if not found."""
	for row_idx in range(board.size()):
		if card in board[row_idx]:
			return {"row": row_idx, "col": card.board_position.get("col", -1)}
	return {}


# ── Adjacency Queries ────────────────────────────────────────────────────────
# All adjacency helpers operate on slot columns (board_position.col), not array indices.
# "Right" = higher col index. "Left" = lower col index.

func get_cards_in_row(card: CardInstance) -> Array[CardInstance]:
	"""All cards on the same row as the given card, excluding the card itself."""
	var pos: Dictionary = find_card_position(card)
	if pos.is_empty():
		return []
	var result: Array[CardInstance] = []
	for c in board[pos["row"]]:
		if c != card:
			result.append(c)
	return result


func is_alone_in_row(card: CardInstance) -> bool:
	"""True if no other card shares the same row."""
	var pos: Dictionary = find_card_position(card)
	if pos.is_empty():
		return false
	return board[pos["row"]].size() == 1


func get_right_neighbor(card: CardInstance) -> CardInstance:
	"""Nearest card to the right (next higher col) in the same row. Null if none."""
	var pos: Dictionary = find_card_position(card)
	if pos.is_empty():
		return null
	var col: int = pos["col"]
	var best: CardInstance = null
	var best_dist: int = 999
	for c in board[pos["row"]]:
		if c == card:
			continue
		var c_col: int = c.board_position.get("col", -1)
		var dist: int = c_col - col
		if dist > 0 and dist < best_dist:
			best_dist = dist
			best = c
	return best


func get_left_neighbor(card: CardInstance) -> CardInstance:
	"""Nearest card to the left (next lower col) in the same row. Null if none."""
	var pos: Dictionary = find_card_position(card)
	if pos.is_empty():
		return null
	var col: int = pos["col"]
	var best: CardInstance = null
	var best_dist: int = 999
	for c in board[pos["row"]]:
		if c == card:
			continue
		var c_col: int = c.board_position.get("col", -1)
		var dist: int = col - c_col
		if dist > 0 and dist < best_dist:
			best_dist = dist
			best = c
	return best


func get_row_neighbors(card: CardInstance) -> Array[CardInstance]:
	"""Left and right immediate neighbors in the same row (up to 2 results)."""
	var result: Array[CardInstance] = []
	var left: CardInstance = get_left_neighbor(card)
	var right: CardInstance = get_right_neighbor(card)
	if left:
		result.append(left)
	if right:
		result.append(right)
	return result


func get_adjacent_empty_slots(card: CardInstance) -> Array[Dictionary]:
	var pos: Dictionary = find_card_position(card)
	if pos.is_empty():
		return []
	var result: Array[Dictionary] = []
	var directions: Array[Vector2i] = [
		Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(-1, 1),
		Vector2i(0, -1),                    Vector2i(0, 1),
		Vector2i(1, -1),  Vector2i(1, 0),   Vector2i(1, 1),
	]
	for dir in directions:
		var row_idx: int = pos["row"] + dir.x
		var col_idx: int = pos["col"] + dir.y
		if row_idx < 0 or row_idx >= board.size():
			continue
		if col_idx < 0 or col_idx >= GameConstants.ROW_CAPACITIES[row_idx]:
			continue
		if not is_slot_occupied(row_idx, col_idx):
			result.append({"row": row_idx, "col": col_idx})
	return result


# ── Board Mutations ──────────────────────────────────────────────────────────

func find_free_col(row_idx: int) -> int:
	"""Return first unoccupied col in row, or -1 if full."""
	if row_idx < 0 or row_idx >= board.size():
		return -1
	for col in range(GameConstants.ROW_CAPACITIES[row_idx]):
		if not is_slot_occupied(row_idx, col):
			return col
	return -1


func is_slot_occupied(row_idx: int, col_idx: int) -> bool:
	if row_idx < 0 or row_idx >= board.size():
		return true
	for card in board[row_idx]:
		if card.board_position.get("col", -1) == col_idx:
			return true
	return false


func place_on_board(card: CardInstance, row_idx: int, col_idx: int) -> bool:
	"""Place card in a specific slot. Returns false if slot occupied or row full."""
	if row_idx < 0 or row_idx >= board.size():
		return false
	if col_idx < 0 or col_idx >= GameConstants.ROW_CAPACITIES[row_idx]:
		return false
	if is_slot_occupied(row_idx, col_idx):
		return false
	board[row_idx].append(card)
	card.place_on_board(row_idx, col_idx)
	card.controller_id = player_id
	return true


func remove_from_board(card: CardInstance) -> bool:
	"""Remove a card from the board. Returns false if not found."""
	for row_idx in range(board.size()):
		var idx: int = board[row_idx].find(card)
		if idx != -1:
			board[row_idx].remove_at(idx)
			return true
	return false


func place_in_first_free_slot(card: CardInstance) -> bool:
	for row_idx in range(board.size()):
		var col_idx: int = find_free_col(row_idx)
		if col_idx >= 0:
			return place_on_board(card, row_idx, col_idx)
	return false


func place_adjacent_to(card: CardInstance, anchor: CardInstance) -> bool:
	for slot in get_adjacent_empty_slots(anchor):
		if place_on_board(card, slot["row"], slot["col"]):
			return true
	return place_in_first_free_slot(card)


func swap_board_positions(a: CardInstance, b: CardInstance) -> bool:
	var pos_a: Dictionary = find_card_position(a)
	var pos_b: Dictionary = find_card_position(b)
	if pos_a.is_empty() or pos_b.is_empty():
		return false
	a.board_position = {"row": pos_b["row"], "col": pos_b["col"]}
	b.board_position = {"row": pos_a["row"], "col": pos_a["col"]}
	var row_a: Array = board[pos_a["row"]]
	var row_b: Array = board[pos_b["row"]]
	row_a.erase(a)
	row_b.erase(b)
	row_a.append(b)
	row_b.append(a)
	return true


# ── Hand Operations ──────────────────────────────────────────────────────────

func add_to_hand(card: CardInstance) -> void:
	card.move_to_zone("hand")
	hand.append(card)


func remove_from_hand(card: CardInstance) -> bool:
	var idx: int = hand.find(card)
	if idx != -1:
		hand.remove_at(idx)
		return true
	return false


func enforce_hand_limit() -> Array[CardInstance]:
	"""Discard random cards until hand is at max size. Returns discarded cards."""
	var discarded: Array[CardInstance] = []
	while hand.size() > GameConstants.MAX_HAND_SIZE:
		var rng_idx := randi() % hand.size()
		var card: CardInstance = hand[rng_idx]
		hand.remove_at(rng_idx)
		card.move_to_zone("graveyard")
		graveyard.append(card)
		discarded.append(card)
	return discarded


# ── Deck Operations ──────────────────────────────────────────────────────────

func draw_faction_card() -> CardInstance:
	"""Draw from faction deck. Returns null if empty."""
	if faction_deck.is_empty():
		return null
	var card: CardInstance = faction_deck.pop_front() as CardInstance
	add_to_hand(card)
	return card


func take_from_faction_deck(card_id: String) -> CardInstance:
	for i in range(faction_deck.size()):
		var card: CardInstance = faction_deck[i]
		if card.data.id == card_id:
			faction_deck.remove_at(i)
			return card
	return null


func take_from_graveyard(card_id: String = "") -> CardInstance:
	for i in range(graveyard.size()):
		var card: CardInstance = graveyard[i]
		if card_id == "" or card.data.id == card_id:
			graveyard.remove_at(i)
			return card
	return null


func get_graveyard_cards_by_rarity(rarities: Array[String]) -> Array[CardInstance]:
	var result: Array[CardInstance] = []
	for card in graveyard:
		if card.data.rarity in rarities:
			result.append(card)
	return result


# ── Economy ──────────────────────────────────────────────────────────────────

func gain_sellary(amount: int) -> void:
	sellary += amount
	EventBus.sellary_gained.emit(player_id, amount)


func spend_sellary(amount: int) -> bool:
	"""Spend sellary. Returns false if insufficient funds."""
	if free_plays_turn:
		return true
	if sellary < amount:
		return false
	sellary -= amount
	EventBus.sellary_spent.emit(player_id, amount)
	return true


func get_neutral_draw_cost() -> int:
	return GameConstants.NEUTRAL_DRAW_BASE_COST + (neutral_draws_this_turn * GameConstants.NEUTRAL_DRAW_EXTRA_COST)


func get_faction_draw_cost() -> int:
	return GameConstants.FACTION_DRAW_BASE_COST + (faction_draws_this_turn * GameConstants.FACTION_DRAW_EXTRA_COST)


# ── Turn Reset ───────────────────────────────────────────────────────────────

func reset_turn_state() -> void:
	cards_played_this_turn = 0
	extra_card_plays = 0
	neutral_draws_this_turn = 0
	faction_draws_this_turn = 0
	free_plays_turn = false
	for row in board:
		for card in row:
			card.reset_turn_state()
