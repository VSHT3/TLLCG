## EventBus (Autoload)
## Global signal hub for decoupled communication between game systems.
## Anything can emit signals here; anything can listen.
## Access via: EventBus.card_played.connect(_on_card_played)
extends Node

# ── Game Flow ────────────────────────────────────────────────────────────────

signal game_started(player_ids: Array)
signal game_ended(winner_id: int)
signal turn_started(player_id: int, turn_number: int)
signal turn_ended(player_id: int)
signal phase_changed(phase: int, player_id: int)

# ── Card Actions ─────────────────────────────────────────────────────────────

signal card_played(card: CardInstance, player_id: int)
signal card_drawn(card: CardInstance, player_id: int, source: String)
signal card_discarded(card: CardInstance, player_id: int)
signal card_destroyed(card: CardInstance, source: CardInstance)
signal card_banished(card: CardInstance)
signal card_moved(card: CardInstance, from_zone: String, to_zone: String)

# ── Combat / Effects ─────────────────────────────────────────────────────────

signal damage_dealt(target: CardInstance, amount: int, source: CardInstance)
signal heal_applied(target: CardInstance, amount: int)
signal boost_applied(target: CardInstance, amount: int)
signal status_applied(target: CardInstance, status_name: String, stacks: int)
signal status_removed(target: CardInstance, status_name: String)
signal status_triggered(target: CardInstance, status_name: String)

# ── Economy ──────────────────────────────────────────────────────────────────

signal sellary_gained(player_id: int, amount: int)
signal sellary_spent(player_id: int, amount: int)
signal sellary_seized(from_id: int, to_id: int, amount: int)

# ── Board ────────────────────────────────────────────────────────────────────

signal card_placed_on_board(card: CardInstance, row: int, col: int)
signal card_removed_from_board(card: CardInstance)

# ── Abilities ────────────────────────────────────────────────────────────────

signal ability_triggered(card: CardInstance, effect: CardEffect)
signal deploy_triggered(card: CardInstance)
signal last_word_triggered(card: CardInstance)
signal deathblow_triggered(card: CardInstance, killed: CardInstance)
signal timer_expired(card: CardInstance)

# ── UI ───────────────────────────────────────────────────────────────────────

signal card_selected(card: CardInstance)
signal card_hovered(card: CardInstance)
signal card_detail_requested(card_visual: CardVisual)
signal target_requested(valid_targets: Array, callback: Callable)
signal target_selected(target: CardInstance)
signal target_cancelled()
signal message_shown(text: String)
