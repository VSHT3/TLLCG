# Repository Guidelines

## Project Structure & Module Organization

This is a Godot 4 card game project. `project.godot` defines the app, main scene, display settings, and autoload singletons. Game scripts live under `scripts/`: `autoloads/` for global managers, `resources/` for data objects, `game/` for rules and turn flow, `ui/` for visual components, `main/` for scene wiring, `network/` for multiplayer stubs, and `utils/` for helpers. Generated card and rules data live in `data/*.json`. Godot scenes belong in `scenes/` by feature area (`main/`, `card/`, `board/`, `ui/`, `menus/`). Static media and theme resources belong in `assets/`. Conversion utilities live in `tools/`.

## Current State & Recent Work

The project now has a documented MVP plan in `ROADMAP.md`. Baseline launch scenes were added at `scenes/main/main.tscn` and `scenes/card/card_visual.tscn`; they match the node paths expected by `scripts/main/main.gd` and `scripts/ui/card_visual.gd`. The default match currently starts in `main.gd` with `["Sir Can", "A.I. Gods"]`, both present in `data/factions.json`. Godot is installed locally at `/Applications/Godot.app` and was verified as 4.6.1. A headless startup check loaded `CardDatabase` and `GameConstants` successfully. Basic placement wiring now lives in `scripts/main/main.gd`: active-hand Unit clicks set a pending card, Unit drags can be dropped on active-board rows, and `GameState.play_card()` places the card in the chosen row. Non-Units are intentionally inert for now so cards do not appear to disappear while the board loop is being stabilized. `CardVisual` is intentionally a simple name-only rectangle; do not reintroduce ability text in hand cards until the play loop is stable.

## Build, Test, and Development Commands

- `python3 tools/yaml_to_json.py /path/to/TLLCG ./data`: regenerate JSON card, faction, keyword, status, and rules data from the source markdown repository.
- `open -a Godot /Users/vsht/tllcg/project.godot`: open this project in the installed Godot app.
- `/Applications/Godot.app/Contents/MacOS/Godot --path /Users/vsht/tllcg`: run/open the project from the CLI.
- `/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/vsht/tllcg --quit-after 1`: smoke-test startup and autoload initialization.

## Coding Style & Naming Conventions

Use the existing GDScript style: tabs for indentation, typed variables and return types, `snake_case` for files, functions, variables, and card IDs, and `PascalCase` for `class_name` types such as `GameState` and `CardData`. Keep game logic independent from UI code; route cross-system notifications through `EventBus`. Python tools use standard library dependencies, 4-space indentation, and type hints where useful.

## Testing Guidelines

No automated test suite is currently committed. For rule or effect changes, add focused validation where practical and manually verify by running the project. For converter changes, regenerate `data/*.json` and inspect representative cards, factions, statuses, and rules for schema drift. Treat `CardDatabase` startup errors and Godot script warnings as blockers before opening a PR.

## Next Implementation Plan

Follow `ROADMAP.md` and keep the first playable scope narrow. Next steps are: verify click-to-play and row placement in the Godot editor, add draw/discard controls, add targeting for simple effects, and add simple manual smoke checks for turn advance, card play, and hero HP. Do not start with polish, online multiplayer, AI, deckbuilding, or full art/audio.

## Commit & Pull Request Guidelines

The current history is minimal and uses short imperative summaries, for example `godot TLLCG`. Keep new commit messages concise and action-oriented, such as `Add board slot validation` or `Fix card data parsing`. Pull requests should include a clear summary, testing or manual verification notes, linked issues when available, and screenshots or recordings for visual scene/UI changes. Mention regenerated data files explicitly when converter output changes.

## Security & Configuration Tips

Do not commit local editor clutter such as `.DS_Store`; it is now ignored in `.gitignore`. Keep `.godot/` cache changes out of reviews unless they are intentionally required. Avoid hardcoding absolute paths in code; pass source repository paths to `tools/yaml_to_json.py` from the command line.
