# TLLCG MVP Roadmap

## First Playable Goal

Build a local two-player card game loop that can start a match, draw cards, play cards to the board, resolve supported effects, advance turns, damage heroes, and declare a winner.

## MVP Scope

- Start a match with two hardcoded factions, then replace this with faction selection.
- Load card, faction, keyword, status, and rule data through `CardDatabase`.
- Display both boards, both hands, turn phase, sellary, and hero HP.
- Allow a player to play units to valid rows and resolve spells or artifacts through `GameState`.
- Advance through play, discard, draw, end-turn, status, and next-turn phases.
- Resolve all simple effect types in `EffectResolver`; log unsupported complex effects clearly.
- End the game when a hero reaches 0 HP.

## Out of Scope Until MVP Works

- Online multiplayer.
- AI opponent.
- Deckbuilding.
- Final card art, animation, sound, and menu polish.
- Full targeting UX for every complex card.

## Immediate Implementation Order

1. Create the missing Godot scenes referenced by `project.godot`. Done: `scenes/main/main.tscn` and `scenes/card/card_visual.tscn` exist.
2. Verify startup with a default two-faction match. Done: Godot 4.6.1 headless startup loads card data and rules.
3. Wire basic card click/play actions from hand to board. Started: clicking an active player's Unit now selects it, highlights valid rows, and clicking a row calls `GameState.play_card()`.
4. Add manual smoke checks for data loading, turn advance, card play, and win condition.

## Current Interaction Notes

- During `PLAY_CARDS`, drag a Unit from the active player's visible hand onto a highlighted board row.
- Clicking a Unit still selects it and highlights valid rows; non-Units are inert for now.
- Cards are intentionally simple name-only rectangles for now; artwork, power, type, and ability text are hidden.
- Spells resolve immediately through existing `GameState`/`EffectResolver` behavior.
- Targeting UI, discard choice, draw choice, and polished feedback are still pending.
