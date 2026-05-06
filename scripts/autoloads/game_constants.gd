## GameConstants (Autoload)
## Central place for all game constants loaded from rules.json.
## Access via: GameConstants.HERO_BASE_HP
extends Node

# ── Core Rules ───────────────────────────────────────────────────────────────

var HERO_BASE_HP: int = 30
var BASE_SELLARY: int = 5
var MAX_CARDS_PER_TURN: int = 2
var MAX_HAND_SIZE: int = 10
var NEUTRAL_DRAW_BASE_COST: int = 3
var NEUTRAL_DRAW_EXTRA_COST: int = 1
var FACTION_DRAW_BASE_COST: int = 4
var FACTION_DRAW_EXTRA_COST: int = 1

# ── Board Layout ─────────────────────────────────────────────────────────────

var ROW_CAPACITIES: Array[int] = [5, 5, 3]
var ROW_NAMES: Array[String] = ["melee", "ranged", "artillery"]
var TOTAL_BOARD_SLOTS: int = 13  # 5 + 5 + 3

# ── Turn Phases ──────────────────────────────────────────────────────────────

enum TurnPhase {
	SELLARY,
	START_OF_TURN,
	PLAY_CARDS,
	DISCARD_CARDS,
	DRAW_CARDS,
	END_OF_TURN,
	STATUS_TRIGGER,
	STATUS_DIMINISH,
}

var PHASE_NAMES: Dictionary = {
	TurnPhase.SELLARY: "Sellary",
	TurnPhase.START_OF_TURN: "Start of Turn",
	TurnPhase.PLAY_CARDS: "Play Cards",
	TurnPhase.DISCARD_CARDS: "Discard Cards",
	TurnPhase.DRAW_CARDS: "Draw Cards",
	TurnPhase.END_OF_TURN: "End of Turn",
	TurnPhase.STATUS_TRIGGER: "Status Trigger",
	TurnPhase.STATUS_DIMINISH: "Status Diminish",
}

# ── Card Types ───────────────────────────────────────────────────────────────

enum CardType { UNIT, SPELL, ARTIFACT, HERO }

# ── Zones ────────────────────────────────────────────────────────────────────

enum Zone { DECK, HAND, BOARD, GRAVEYARD, BANISHED }

# ── Activation Order ─────────────────────────────────────────────────────────

## Cards activate from melee row to artillery, left to right.
const ACTIVATION_ORDER := "melee_to_artillery_left_to_right"

# ── Match Setup (set by MainMenu before scene switch) ────────────────────────

## Faction names chosen by each player. Index = player_id.
var pending_faction_choices: Array[String] = ["Sir Can", "A.I. Gods"]
## Player who won the dice roll and goes first.
var first_player_id: int = 0

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	# Override from rules.json if available
	var rules: Dictionary = CardDatabase.rules
	if rules.is_empty():
		return
	HERO_BASE_HP = rules.get("hero_base_hp", HERO_BASE_HP)
	BASE_SELLARY = rules.get("base_sellary_per_turn", BASE_SELLARY)
	MAX_CARDS_PER_TURN = rules.get("max_cards_per_turn", MAX_CARDS_PER_TURN)
	MAX_HAND_SIZE = rules.get("max_hand_size", MAX_HAND_SIZE)
	NEUTRAL_DRAW_BASE_COST = rules.get("neutral_draw_base_cost", NEUTRAL_DRAW_BASE_COST)
	NEUTRAL_DRAW_EXTRA_COST = rules.get("neutral_draw_extra_cost", NEUTRAL_DRAW_EXTRA_COST)
	FACTION_DRAW_BASE_COST = rules.get("faction_draw_base_cost", FACTION_DRAW_BASE_COST)
	FACTION_DRAW_EXTRA_COST = rules.get("faction_draw_extra_cost", FACTION_DRAW_EXTRA_COST)
	var caps = rules.get("row_capacities", [5, 5, 3])
	ROW_CAPACITIES = []
	for c in caps:
		ROW_CAPACITIES.append(int(c))
	TOTAL_BOARD_SLOTS = 0
	for c in ROW_CAPACITIES:
		TOTAL_BOARD_SLOTS += c
	print("[GameConstants] Loaded rules — HP:%d Sellary:%d Board:%s" % [
		HERO_BASE_HP, BASE_SELLARY, str(ROW_CAPACITIES)
	])
