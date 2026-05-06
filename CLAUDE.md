# CLAUDE.md

Guidance for Claude Code working in this repo.

## Commands

```bash
# Open project in Godot editor
godot --path /Users/vsht/tllcg

# Headless startup check (verifies autoloads, scene, no crash)
godot --headless --path /Users/vsht/tllcg

# Regenerate JSON data from Obsidian vault
python tools/yaml_to_json.py ./TLLCG ./data

# Regenerate single card test (pipe output, check for errors)
python tools/yaml_to_json.py ./TLLCG ./data 2>&1 | head -50
```

No test suite. Manual verify in Godot editor.

## Architecture

**Data pipeline:** `TLLCG/*.md` (Obsidian vault) → `tools/yaml_to_json.py` → `data/*.json` → `CardDatabase` autoload → all scripts.

**TLLCG/ = separate Git repo** (nested). Source of truth for card design. Edit there, re-run converter, reload Godot.

### Autoloads (global singletons, always available)

- **CardDatabase** — reads all JSON on startup; `get_card(id)`, `get_cards_by_faction(name)`, `search_cards(query)`
- **GameConstants** — typed constants from `rules.json`; `TurnPhase` enum, `Zone` enum, `CardType` enum, `ROW_CAPACITIES = [5, 5, 3]`
- **EventBus** — all game events as signals; UI listens passively, game logic emits; decouples UI from logic

### Data / state split

- `CardData` (resource) — immutable card definition (base_power, effects[], factions[], categories[])
- `CardEffect` (resource) — one parsed ability (type, trigger, value, status, raw_text fallback)
- `CardInstance` — mutable runtime state (current_power, statuses{}, zone, board_position, owner_id, controller_id)

### Game logic layer (`scripts/game/`)

- **GameState** — owns `players[]` and `neutral_deck`; orchestrates full turn flow; `setup_game()`, `play_card()`, `draw_neutral()`, `draw_faction()`
- **PlayerState** — per-player: hero, hand, board\[3\]\[\], faction_deck, sellary economy; `place_on_board()`, `enforce_hand_limit()`
- **BoardManager** — static helpers: adjacency, taunt detection, activation order, valid placement rows
- **EffectResolver** — listens to `EventBus.ability_triggered`; dispatches to `_resolve_damage/boost/heal/profit/seize/spy/…`; many effects TODO stubs (apply_status, destroy, banish, devour)

### UI layer (`scripts/ui/`)

- **CardVisual** — single card; drag threshold 8px, hover scale 4%; `setup(CardInstance)`, `refresh_display()`
- **HandManager** — fan layout (5° curve); rebuilds on `refresh()`; emits `card_drag_started/card_dropped` to Main
- **BoardVisual** — builds 3 HBoxContainers programmatically (5/5/3 slots); `highlight_valid_rows()`, `get_row_at_global_position()`

### Main scene wiring (`scripts/main/main.gd`)

Connects everything: instantiates GameState, wires 13+ EventBus signals, handles card placement workflow (click/drag → highlight rows → confirm → `play_card()` → `_refresh_all()`). Hardcoded default factions: `["Sir Can", "A.I. Gods"]`.

## Turn flow

```
gain_sellary → START_OF_TURN (income triggers) → PLAY_CARDS (interactive)
→ DISCARD_CARDS → DRAW_CARDS → END_OF_TURN (timer/turn_end triggers)
→ STATUS_TRIGGER (Poison/Burn/Wither damage) → STATUS_DIMINISH → next player
```

Win: `_check_game_over()` fires when ≤1 hero alive.

## Card data format

Effects in `cards.json`:
- `type`: damage / boost / heal / profit / income / draw / apply_status / destroy / banish / spy / devour / seize / block / complex
- `trigger`: deploy / last_word / deathblow / turn_start / turn_end / timer / upkeep / tribute / order / hoard / spot_67 / passive

`raw_text` = fallback for unparsed effects; `EffectResolver` logs warning for `complex` type.

## Coding conventions

- Tabs for indentation
- `snake_case` vars/functions, `PascalCase` class names
- Typed vars preferred (`var x: int`)
- Static typing in function signatures where practical

## Current implementation status

**Complete:** data loading, game state, turn flow, card placement (units/spells/artifacts), basic ability triggers (damage, profit, income, boost, heal, spy, seize), targeting UI (deploy/damage/destroy/banish/apply_status/devour), drag-drop UI, EventBus wiring, draw/discard phase UI, slot-precise board placement, card draggability gating, spell play from hand.

**Complex cards implemented** (`"implemented": true` in `cards.json`): Accountant Pro Max (hoard tiers), Carry On (+2 plays), Catch-up (match opponent sellary), Individual Sailor (boost right / alone→damage hero), Sir Vant (pay 2→heal hero; last word→Sir Can heal+boost), Šibal (shuffle 2 + draw 2 faction).

**Complex cards implemented** — add new ones in `EffectResolver._resolve_complex` as a match on `source.data.id`. Set `"implemented": true` in `cards.json` to track. Decks only draw `has_ability=true` cards (neutral + faction).

**Incomplete (TODO):** full card visual (art hidden), remaining `complex` effects (30+ cards unimplemented).

**Out of scope for MVP:** multiplayer (NetworkManager stub), AI opponent, deck building, menus.

## Slot system notes

Board uses fixed slots (5/5/3). `board[][]` stores cards by array order but `CardInstance.board_position.col` holds the actual slot index. `BoardVisual.refresh()` uses `board_position.col` to place visuals — not array index. `PlayerState.is_slot_occupied(row, col)` checks by stored col. `find_free_col(row)` returns first empty slot (used by artifact auto-place + spy). Never reindex cols on removal.

## Draggability gating

`HandManager.can_play_func` is a `Callable` injected by Main (`_can_play_card`). Called per card in `refresh()` and `refresh_draggable()`. Cards dim (alpha 0.5) + `MOUSE_FILTER_IGNORE` when not playable. `_on_phase_changed` calls `refresh_draggable()` on both hands — critical because `turn_started` fires before phase reaches `PLAY_CARDS`.