# TLLCG — Think Look Like Card Game (Godot 4 Project)

A data-driven card game built with Godot 4.3, featuring 194 cards across 4 factions + neutral pool, with a custom ability system, economy, and board layout.

## Quick Start

```bash
# 1. Clone or copy this folder into your Godot projects
# 2. Run the YAML-to-JSON converter to generate fresh data:
python tools/yaml_to_json.py /path/to/TLLCG ./data

# 3. Open in Godot 4.3+ (just open the project.godot file)
# 4. The game auto-loads card data on startup via the CardDatabase autoload
```

## Project Structure

```
tllcg_godot/
├── project.godot              # Godot project config (autoloads, display settings)
│
├── data/                      # Generated JSON data (from YAML converter)
│   ├── cards.json             # 194 card definitions with parsed abilities
│   ├── keywords.json          # 27 keyword definitions (Deploy, Banish, etc.)
│   ├── statuses.json          # 10 status effect definitions
│   ├── categories.json        # Card categories (Token, etc.)
│   ├── factions.json          # 5 factions with card lists
│   └── rules.json             # Game constants (HP, sellary, row sizes)
│
├── scripts/
│   ├── autoloads/             # Singleton managers (auto-loaded by Godot)
│   │   ├── card_database.gd   # Loads & serves all card/keyword/status data
│   │   ├── game_constants.gd  # Game rules as typed variables + enums
│   │   └── event_bus.gd       # Global signal hub for decoupled events
│   │
│   ├── resources/             # Data classes (no game logic)
│   │   ├── card_data.gd       # CardData — immutable card definition
│   │   ├── card_effect.gd     # CardEffect — single parsed ability effect
│   │   └── card_instance.gd   # CardInstance — mutable runtime card state
│   │
│   ├── game/                  # Core game logic (no UI dependency)
│   │   ├── game_state.gd      # Central state: players, decks, turn flow
│   │   ├── player_state.gd    # Per-player state: hand, board, economy
│   │   ├── board_manager.gd   # Board layout helpers, adjacency, activation order
│   │   └── effect_resolver.gd # Listens for ability events, resolves effects
│   │
│   ├── ui/                    # Visual/interactive components
│   │   ├── card_visual.gd     # Card rendering, hover, drag-and-drop
│   │   ├── hand_manager.gd    # Hand layout (fan effect, card interaction)
│   │   └── board_visual.gd    # Board rendering (slots, highlights)
│   │
│   ├── main/
│   │   └── main.gd            # Game scene controller, wires everything together
│   │
│   ├── network/
│   │   └── network_manager.gd # Multiplayer stub (ENet-ready)
│   │
│   └── utils/
│       └── logger.gd          # Debug logging utility
│
├── scenes/                    # Godot .tscn scene files (create in editor)
│   ├── main/                  # Main game scene
│   ├── card/                  # Card visual scene template
│   ├── board/                 # Board layout scenes
│   ├── ui/                    # HUD, menus, popups
│   └── menus/                 # Title screen, faction select, settings
│
├── assets/
│   ├── artworks/              # Card artwork images (copy from TLLCG/Artworks/)
│   ├── fonts/                 # Custom fonts
│   ├── themes/                # Godot theme resources
│   └── audio/                 # SFX and music
│       ├── sfx/
│       └── music/
│
└── tools/
    └── yaml_to_json.py        # Converts TLLCG repo markdown → JSON
```

## Architecture Overview

### Data Flow
```
TLLCG repo (.md files)
    │
    ▼ yaml_to_json.py
JSON data files (data/*.json)
    │
    ▼ CardDatabase autoload
CardData resources (in memory)
    │
    ▼ GameState.setup_game()
CardInstance objects (mutable runtime state)
    │
    ├──▶ EffectResolver (handles ability logic)
    ├──▶ BoardManager (spatial queries)
    └──▶ UI (CardVisual, HandManager, BoardVisual)
```

### Key Design Decisions

1. **Data-driven cards**: All 194 cards are defined in JSON. No card has hardcoded GDScript. The effect resolver dispatches based on parsed effect types.

2. **Separation of data and state**: `CardData` is immutable (the definition). `CardInstance` holds mutable runtime state (current power, statuses, zone, position).

3. **Event bus architecture**: All game events flow through `EventBus` signals. This decouples game logic from UI — you can swap UI completely without touching game code.

4. **Effect resolver pattern**: Abilities are parsed into `CardEffect` objects with a `type` and `trigger`. The `EffectResolver` listens for `ability_triggered` signals and dispatches to the right handler. Adding a new effect = adding a new match case.

## Card Data Format (JSON)

Each card in `cards.json`:
```json
{
  "id": "neural_network",
  "name": "Neural Network",
  "type": "Unit",
  "rarity": "Common",
  "factions": ["A.I. Gods"],
  "categories": ["Token", "A.I."],
  "power": 3,
  "has_ability": true,
  "ability_text": "Timer 5 —> Profit 3.",
  "artwork": "neural network.png",
  "effects": [
    {
      "type": "profit",
      "value": 3,
      "trigger": "timer",
      "timer_value": 5
    }
  ]
}
```

### Effect Types
| Type | Description | Fields |
|------|-------------|--------|
| `damage` | Deal damage to target | `value` |
| `boost` | Increase power | `value` |
| `heal` | Heal up to base power | `value` |
| `profit` | Gain sellary | `value` |
| `income` | Profit at turn start | `value` |
| `draw` | Draw cards | `value` |
| `apply_status` | Apply status effect | `status`, `stacks` |
| `destroy` | Destroy target | — |
| `banish` | Remove from game | — |
| `spy` | Place on opponent's board | — |
| `devour` | Eat ally, gain its power | — |
| `seize` | Steal sellary | `value` |
| `block` | Reduce incoming damage | `value` |
| `complex` | Unparsed (needs manual impl) | `raw_text` |

### Trigger Types
| Trigger | When It Fires |
|---------|---------------|
| `passive` | Always active / on play |
| `deploy` | When card enters the board |
| `last_word` | When card is destroyed |
| `deathblow` | When this card kills a unit |
| `turn_start` | At start of owner's turn |
| `turn_end` | At end of owner's turn |
| `timer` | When timer reaches 0 |
| `upkeep` | Turn start if cost paid |
| `tribute` | On play if cost paid (optional) |
| `order` | When charges are spent |
| `hoard` | When sellary >= threshold |
| `spot_67` | When 6 and 7 are adjacent |

## Step-by-Step Implementation Guide

### Phase 1: Foundation (Current — DONE)
- [x] YAML-to-JSON converter
- [x] JSON data schema
- [x] Godot project structure
- [x] CardData / CardEffect / CardInstance resources
- [x] CardDatabase autoload
- [x] GameConstants autoload
- [x] EventBus autoload
- [x] GameState with turn flow
- [x] PlayerState with zones & economy
- [x] BoardManager with adjacency
- [x] EffectResolver with dispatch
- [x] Network manager stub

### Phase 2: Scene Building (YOUR NEXT STEP)
Create these scenes in the Godot editor:

#### 1. Card Scene (`scenes/card/card_visual.tscn`)
```
CardVisual (Control) — script: card_visual.gd
├── CardFrame (NinePatchRect) — card border/background
├── CardArt (TextureRect) — artwork
├── NameLabel (Label) — card name
├── PowerLabel (Label) — power number
├── TypeLabel (Label) — Unit/Spell/Artifact
├── AbilityLabel (RichTextLabel) — ability text
└── CostLabel (Label) — sellary cost info
```
- Size: ~100x140 (thumbnail) or ~200x280 (full view)
- Use `mouse_filter = PASS` for input
- Connect `mouse_entered` and `mouse_exited` signals

#### 2. Main Game Scene (`scenes/main/main.tscn`)
```
Main (Node2D) — script: main.gd
├── Background (TextureRect)
├── GameBoard (Node2D)
│   ├── Player1Board (BoardVisual) — top half
│   └── Player0Board (BoardVisual) — bottom half
├── UI (CanvasLayer)
│   ├── HandP0 (HandManager) — bottom of screen
│   ├── HandP1 (HandManager) — top of screen (hidden in local play)
│   └── HUD (Control)
│       ├── TurnLabel (Label)
│       ├── PhaseLabel (Label)
│       ├── SellaryP0 (Label)
│       ├── SellaryP1 (Label)
│       ├── HeroHPP0 (Label)
│       ├── HeroHPP1 (Label)
│       └── EndPhaseButton (Button)
└── EffectResolver (Node) — script: effect_resolver.gd
```

#### 3. Board Row Scene (`scenes/board/board_visual.tscn`)
- Uses `board_visual.gd` script
- VBoxContainer with 3 HBoxContainer rows
- Each row has N Panel slots (5, 5, 3)

### Phase 3: Card Interaction
1. **Drag-and-drop**: Cards from hand → board slots
2. **Targeting system**: Click a card, then click a target
   - `EventBus.target_requested` → highlight valid targets
   - `EventBus.target_selected` → resolve effect
3. **Context menu**: Right-click for card details
4. **Hover tooltip**: Show ability text and stats

### Phase 4: Visual Polish
1. **Card art**: Copy artworks from TLLCG repo to `assets/artworks/`
2. **Animations**: Tween-based card movement, damage numbers, status icons
3. **Particles**: Destruction effects, ability triggers
4. **Sound**: Card play SFX, damage SFX, turn transition

### Phase 5: AI Opponent
1. Basic AI: random valid moves
2. Heuristic AI: evaluate board state, prioritize threats
3. Consider: minimax or MCTS for deeper strategy

### Phase 6: Multiplayer
1. `NetworkManager` already has ENet scaffolding
2. Implement action serialization (play card → `{action: "play", card_id: "...", row: 0}`)
3. Server-authoritative: host validates all moves
4. Sync: replicate GameState changes via RPC

### Phase 7: Menus & Meta
1. Title screen with faction select
2. Deck builder (later, if custom decks)
3. Settings (audio, display, controls)
4. Match history

## Game Rules Reference

| Rule | Value |
|------|-------|
| Hero base HP | 30 |
| Base sellary/turn | 5 |
| Cards playable/turn | 2 |
| Max hand size | 10 |
| Neutral draw cost | 3 + 1/extra |
| Faction draw cost | 4 + 1/extra |
| Board rows | Melee (5), Ranged (5), Artillery (3) |
| Win condition | Last hero standing |

### Turn Phases
1. Gain sellary
2. Start-of-turn abilities trigger
3. Play up to 2 cards
4. Discard any cards
5. Draw cards (costs sellary)
6. End-of-turn abilities trigger
7. Statuses trigger
8. Statuses diminish

### Activation Order
Melee row → Ranged row → Artillery row, left to right within each row.

## Development Tips

### Re-generating card data
Whenever you add/edit cards in the TLLCG repo, re-run:
```bash
python tools/yaml_to_json.py /path/to/TLLCG ./data
```

### Adding a new effect type
1. Add the type string to `CardEffect.describe()` in `card_effect.gd`
2. Add a `_resolve_xxx()` method in `effect_resolver.gd`
3. Add a match case in `_on_ability_triggered()`
4. If the parser can detect it, add regex to `parse_ability_effects()` in `yaml_to_json.py`

### Adding a new keyword
1. Define it in `Systems/Keywords.md` in the TLLCG repo
2. Re-run the converter
3. If it has gameplay effect, implement in `effect_resolver.gd`

### Adding a new status
1. Define it in `Systems/Statuses.md`
2. Re-run the converter
3. Add trigger logic in `GameState._trigger_statuses()`
4. Add diminish logic in `CardInstance.diminish_statuses()`
5. Add visual indicator in `CardVisual._update_status_visuals()`

### Testing without UI
You can test game logic purely in code:
```gdscript
func _ready():
    var gs = GameState.new()
    gs.setup_game(["Sir Can", "A.I. Gods"])
    gs.start_turn()
    var p = gs.get_current_player()
    print("Hand: ", p.hand.size(), " cards")
    print("Sellary: ", p.sellary)
    # Play a card
    if p.hand.size() > 0:
        var card = p.hand[0]
        if card.data.type == "Unit":
            gs.play_card(p, card, 0)  # Row 0 (melee)
```

## Factions

| Faction | Hero | Cards | Theme |
|---------|------|-------|-------|
| A.I. Gods | A.I. God | 18 | Neural networks, data, tech |
| Abeer Dawood Salman | Abeer Dawood Salman | 21 | Pirates, alcohol, economics |
| Sir Can | Sir Can | 21 | Knights, cans, medieval |
| The Plague | The Plague | 14 | Disease, infection, decay |
| Neutral | — | 65 | Shared card pool |

## Credits

- Game design: TLLCG team
- Engine: Godot 4.3
- Project structure & tooling: Generated with Perplexity Computer
