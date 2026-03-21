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
var neutral_draws_this_turn: int = 0
var faction_draws_this_turn: int = 0


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
		if card_data.type != "Hero":
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
	return get_row_count(row_idx) >= GameConstants.ROW_CAPACITIES[row_idx]


func is_board_full() -> bool:
	for i in range(board.size()):
		if not is_row_full(i):
			return false
	return true


func find_card_position(card: CardInstance) -> Dictionary:
	"""Returns {row, col} or empty dict if not found."""
	for row_idx in range(board.size()):
		for col_idx in range(board[row_idx].size()):
			if board[row_idx][col_idx] == card:
				return {"row": row_idx, "col": col_idx}
	return {}


# ── Board Mutations ──────────────────────────────────────────────────────────

func place_on_board(card: CardInstance, row_idx: int) -> bool:
	"""Place a card on a specific row. Returns false if row is full."""
	if is_row_full(row_idx):
		return false
	var col: int = board[row_idx].size()
	board[row_idx].append(card)
	card.place_on_board(row_idx, col)
	card.controller_id = player_id
	return true


func remove_from_board(card: CardInstance) -> bool:
	"""Remove a card from the board. Returns false if not found."""
	for row_idx in range(board.size()):
		var idx: int = board[row_idx].find(card)
		if idx != -1:
			board[row_idx].remove_at(idx)
			# Reindex remaining cards in this row
			for i in range(idx, board[row_idx].size()):
				board[row_idx][i].board_position = {"row": row_idx, "col": i}
			return true
	return false


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


# ── Economy ──────────────────────────────────────────────────────────────────

func gain_sellary(amount: int) -> void:
	sellary += amount
	EventBus.sellary_gained.emit(player_id, amount)


func spend_sellary(amount: int) -> bool:
	"""Spend sellary. Returns false if insufficient funds."""
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
	neutral_draws_this_turn = 0
	faction_draws_this_turn = 0
	for row in board:
		for card in row:
			card.reset_turn_state()
