# CLAUDE.md

Guidance for Claude Code working in this repo.

## Commands

```bash
# Headless startup check (verifies autoloads, scene, no crash)
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/vsht/tllcg --quit

# System tests
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/vsht/tllcg scenes/tools/system_tests.tscn

# Card data audit
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/vsht/tllcg --script res://scripts/tools/run_card_audit.gd

# Regenerate JSON data from Obsidian vault
python tools/yaml_to_json.py ./TLLCG ./data

# Open in editor
/Applications/Godot.app/Contents/MacOS/Godot --path /Users/vsht/tllcg
```

Run system tests + card audit before handing off rules/card parser changes.

---

## System wiring diagram

```
┌─────────────────────────────────────────────────────────────────┐
│  DATA PIPELINE                                                  │
│  TLLCG/*.md (Obsidian vault)                                    │
│       │  tools/yaml_to_json.py                                  │
│       ▼                                                         │
│  data/*.json  ──►  CardDatabase (autoload)                      │
│                        get_card(id) → CardData                  │
│                        get_cards_by_faction(name)               │
│                        resolve_ability_text(raw)                │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  GAME LOGIC  (scripts/game/)                                    │
│                                                                 │
│  GameState                                                      │
│  ├─ players: PlayerState[]                                      │
│  │    ├─ hero: CardInstance                                     │
│  │    ├─ hand / board[3][] / faction_deck / graveyard          │
│  │    ├─ sellary, extra_card_plays                             │
│  │    └─ adjacency API (see below)                             │
│  ├─ neutral_deck: CardInstance[]                                │
│  └─ turn flow:                                                  │
│       setup_game() → start_turn() → end_play_phase()           │
│       → end_discard_phase() → end_draw_phase() → _advance_turn │
│                                                                 │
│  EffectResolver  (Node, child of Main scene)                    │
│  ├─ setup(game_state)                                           │
│  ├─ listens: EventBus.ability_triggered                         │
│  ├─ _check_costs() → upkeep/tribute/hoard/order gating         │
│  ├─ _resolve_*()  one per effect type (damage/boost/heal/…)    │
│  ├─ _resolve_complex() → match source.data.id → _complex_*()   │
│  └─ shared helpers:                                             │
│       _get_controller(card) → PlayerState                       │
│       _get_enemy_player(source) → PlayerState                   │
│       _get_enemy_hero(player) → CardInstance                    │
│       _controls_card_id(player, id) → bool                     │
│       _find_card_owner(card) → PlayerState                      │
│       _get_valid_damage_targets(source) → Array                 │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  EVENT BUS  (autoload — full signal list)                       │
│                                                                 │
│  Game flow:   game_started, game_ended                          │
│               turn_started, turn_ended, phase_changed           │
│  Cards:       card_played, card_drawn, card_discarded           │
│               card_destroyed, card_banished, card_moved         │
│               card_placed_on_board, card_removed_from_board     │
│  Combat:      damage_dealt, heal_applied, boost_applied         │
│               status_applied, status_removed, status_triggered  │
│  Economy:     sellary_gained, sellary_spent, sellary_seized     │
│  Abilities:   ability_triggered(card, effect)  ← EffectResolver │
│               deploy_triggered, last_word_triggered             │
│               deathblow_triggered, timer_expired                │
│  Targeting:   target_requested(valid_targets, callback)         │
│               target_selected, target_cancelled                 │
│  UI:          card_selected, card_hovered                       │
│               card_detail_requested(card_visual)                │
│               message_shown(text)                               │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  UI LAYER  (scripts/ui/ + scripts/main/)                        │
│                                                                 │
│  MainMenu (scene: scenes/menus/main_menu.tscn)                  │
│  ├─ dice roll → faction pick (reverse order) → summary          │
│  └─ sets GameConstants.pending_faction_choices + first_player_id│
│                                                                 │
│  Main (scene: scenes/main/main.tscn)                            │
│  ├─ reads GameConstants.pending_faction_choices on _ready       │
│  ├─ wires all EventBus signals → refresh/HUD/targeting handlers │
│  ├─ card placement flow:                                        │
│  │    right-click hand card → _on_card_selected                 │
│  │    drag Unit/Artifact → _prepare_unit_placement              │
│  │    drop on slot → play_card(player, card, row, col)          │
│  │    Spell → play_card instantly (no board placement)          │
│  └─ targeting flow:                                             │
│       target_requested → boards.enter_target_mode(targets)      │
│       click card/hero → callback(target) → _clear_target_mode  │
│                                                                 │
│  BoardVisual  — 3 rows × 5/5/3 Panel slots                      │
│  ├─ refresh() — places CardVisuals by board_position.col        │
│  ├─ enter_target_mode / exit_target_mode                        │
│  └─ signals: row_selected(row,col), target_card_clicked(card)  │
│                                                                 │
│  HandManager  — HBoxContainer of CardVisuals                    │
│  ├─ can_play_func: Callable — injected by Main                  │
│  └─ refresh_draggable() — dims/enables per can_play_func        │
│                                                                 │
│  CardVisual  — single card Control node                         │
│  ├─ setup(CardInstance), refresh_display()                      │
│  ├─ set_draggable(bool), set_detail_highlighted(bool)           │
│  └─ signals: clicked, right_clicked, drag_started, drag_ended  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Turn flow

```
SELLARY → START_OF_TURN (income/upkeep triggers)
→ PLAY_CARDS (interactive, up to MAX_CARDS_PER_TURN + extra_card_plays)
→ DISCARD_CARDS (interactive) → DRAW_CARDS (interactive)
→ END_OF_TURN (turn_end triggers, timers)
→ STATUS_TRIGGER (Poison/Burn/Wither damage)
→ STATUS_DIMINISH → _advance_turn → next player's start_turn()
```

Win condition: `_check_game_over()` after each turn — fires `game_ended` when ≤1 hero alive.

---

## Data / resource types

| Type | File | Role |
|---|---|---|
| `CardData` | `scripts/resources/card_data.gd` | Immutable definition. `id`, `name`, `type`, `base_power`, `effects[]`, `factions[]`, `has_ability`, `ability_text` |
| `CardEffect` | `scripts/resources/card_effect.gd` | One parsed effect. `type`, `trigger`, `value`, `status`, `stacks`, `upkeep_cost`, `tribute_cost`, `hoard_threshold`, `charges`, `raw_text` |
| `CardInstance` | `scripts/resources/card_instance.gd` | Mutable runtime state. `current_power`, `statuses{}`, `zone`, `board_position{row,col}`, `owner_id`, `controller_id`, `block`, `charges` |
| `CardRuleDefaults` | `scripts/game/card_rule_defaults.gd` | Special runtime defaults and timer tick rules that must apply to every instance of a card |
| `EffectCosts` | `scripts/game/effect_costs.gd` | Shared cost rules used by both UI/payability checks and `EffectResolver` spending |

Effect `type` values: `damage / boost / heal / profit / income / draw / apply_status / destroy / banish / spy / devour / seize / block / complex`

Effect `trigger` values: `deploy / last_word / deathblow / turn_start / turn_end / timer / upkeep / tribute / order / hoard / passive`

---

## Card data format & deck filtering

- Source of truth: `TLLCG/*.md` → `tools/yaml_to_json.py` → `data/cards.json`
- **TLLCG/ is separate nested git repo** — don't track files here
- Decks only include `has_ability == true` cards (neutral + faction)
- `"implemented": true` in `cards.json` marks complex cards with working code

**Currently implemented complex cards (38):**
`accountant_pro_max`, `biblography`, `breakthru`, `carry_on`, `catch_up`, `claws_the_production`, `damina`, `dawood`, `discard_this_card`, `everything_here_here`, `fukacia_pracicka`, `hhmds`, `individual_sailor`, `knight`, `mikrofo_novy_pokles`, `miss_spell`, `mr_rural`, `my_country_called_me`, `masovystit`, `negromancy_premium`, `negromancy`, `obratnost_ruk`, `opakovacia_dedinka`, `premium_account`, `scrolling_papers`, `sellers_sailors`, `sir_vant`, `sir_veillance`, `sir_vival`, `s_ibal`, `tax_er`, `the_lion_does_not_care`, `the_prophet`, `the_why_axes`, `trembling_lips`, `velke_jazykove_monstrum`, `nak_mitchrbat`, `sibal_so_sledovanim_lucov`

**Complex cards TODO:** `mr_hornier` still needs clarified manual system mapping. Check `cards.json` where `effects[].type == "complex"` and `implemented` absent after importing new card data.

---

## Adding a new complex card

1. Fix effects in `data/cards.json` if converter missed them (set correct `trigger` + `type`)
2. Add `"implemented": true` to card entry
3. Add match arm in `EffectResolver._resolve_complex()`:
   ```gdscript
   "your_card_id":
       _complex_your_card(source)
   ```
4. Write `_complex_your_card(source: CardInstance)` using existing helpers:
   - `_get_controller(source)` → owning PlayerState
   - `_get_enemy_player(source)` / `_get_enemy_hero(player)`
   - `_controls_card_id(player, id)` → synergy checks
   - `player.get_right_neighbor(card)` / `get_left_neighbor` / `get_row_neighbors`
   - `player.is_alone_in_row(card)` / `get_cards_in_row(card)`
   - `_apply_damage(source, target, amount)` — respects Block, Artifacts immune, kills + triggers deathblow
   - `EventBus.boost_applied / heal_applied / damage_dealt` — emit after mutations for UI refresh

---

## Slot system

Board uses fixed slots (5/5/3). `board[row][]` is **unordered array** — `CardInstance.board_position.col` is authoritative slot index. Never use array index as col. Never reindex cols on removal.

Key methods: `place_on_board(card, row, col)`, `is_slot_occupied(row, col)`, `find_free_col(row)`, `find_card_position(card) → {row, col}`.

---

## PlayerState adjacency API

All methods use `board_position.col`, not array index:

| Method | Returns |
|---|---|
| `find_card_position(card)` | `{row, col}` or `{}` |
| `is_alone_in_row(card)` | `bool` |
| `get_right_neighbor(card)` | nearest card at higher col, or `null` |
| `get_left_neighbor(card)` | nearest card at lower col, or `null` |
| `get_row_neighbors(card)` | `[left?, right?]` — up to 2 |
| `get_cards_in_row(card)` | all other cards in same row |

---

## Targeting flow

```
EffectResolver._resolve_damage/destroy/banish/… :
    EventBus.target_requested.emit(valid_targets, callback_lambda)
        │
        ▼
    Main._on_target_requested():
        stores callback in pending_target_callback
        board_p0/p1.enter_target_mode(valid_targets)  → orange highlight
        hero visuals → MOUSE_FILTER_STOP + orange tint
        │
        ▼  (player clicks a card or hero)
    _on_target_card_clicked(target) / _on_hero_clicked(cv):
        _clear_target_mode()
        pending_target_callback.call(target)  → resolves effect
```

---

## Draggability gating

`HandManager.can_play_func: Callable` injected by Main (`_can_play_card`). Cards with `can_play_func → false` get `MOUSE_FILTER_IGNORE` + alpha 0.5. `_on_phase_changed` calls `refresh_draggable()` — critical because `turn_started` fires before phase reaches `PLAY_CARDS`.

`extra_card_plays` on PlayerState reset each turn; Carry On / HHMDS increment it; `can_play_card()` checks `cards_played_this_turn >= MAX_CARDS_PER_TURN + extra_card_plays`.

---

## TODO / what to work on next

### P0 — bugs / missing wiring (breaks existing cards)

- **Passive spells with `apply_status` / `destroy`** — targetable passive spells route through `target_requested` and pass headless startup, but still need manual in-editor gameplay verification with several examples.

### P1 — complex/system follow-up

- **Manual gameplay audit** — all current complex cards have resolver paths, but several newer systems use pragmatic UI prompts instead of bespoke panels: slot choice, graveyard choice, opponent-hand reveal, and board swap.
- **Regeneration safety** — if `tools/yaml_to_json.py` is rerun from source markdown, re-check `data/cards.json` for cards whose effects needed manual split triggers (`damina`, `trembling_lips`, `premium_account`, `mr_rural`, `velke_jazykove_monstrum`).

### P2 — UX / visual polish

- **Card artwork** — `CardArt` TextureRect exists but `visible = false`. Load from `card_data.artwork_path` in `refresh_display()` when file exists at `res://assets/cards/<path>`.
- **Status icons on cards** — `_update_status_visuals()` only tints modulate; no icons. Add small icon overlays per active status.
- **Power change animations** — flash red on damage, green on boost (currently instant).
- **Hand layout** — flat HBox; could fan cards (angle + overlap) for better feel.
- **`message_shown` log** — single label overwrites; scrolling log better for debugging.
- **Hero card visuals** — hero containers exist in HUD but small (150×72); deserve larger display with HP bar.

### P3 — systems not yet started

- **AI opponent** — single-player mode. Even "play random card each turn" enables solo testing.
- **Deck builder** — factions hardcoded; no card selection.
- **Win/lose screen** — `game_ended` fires but no scene transition, just label.
- **Sound** — no audio.

---

## Coding conventions

- Tabs for indentation
- `snake_case` vars/functions, `PascalCase` class names
- Typed vars preferred (`var x: int`)
- Static typing in function signatures where practical
- No comments unless WHY non-obvious
- Always run headless check after changes
