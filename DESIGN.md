# Design

## Style

Restrained tactical tabletop UI. Dark neutral table surface, cool steel panels, warm amber for primary actions, green for legal placement, orange for targeting, red for damage, and blue for resource/phase information. Use color as state language, not decoration.

## Color

- Background: deep blue-black table tones, never pure black.
- Panels: cool desaturated slate with subtle borders.
- Primary action: warm amber with strong hover/focus contrast.
- Legal placement: muted green fill with bright green border.
- Targeting/attention: orange-gold highlight.
- Damage/error: softened red.
- Boost/heal/success: green.
- Resource/info: clear blue.

## Typography

Use Godot default/system UI fonts with compact hierarchy. Labels should favor short game terms over prose. Hero/resource/phase readouts need stronger size and weight than debug and log text. Card names must fit within their card frame without overlap.

## Layout

The board is centered in a wide table band with player 1 mirrored at the top and player 0 mirrored at the bottom. Hands and hero areas must not overlap board rows, deck/graveyard panels, or debug overlays. Repeated elements should use fixed dimensions so hover, long names, counters, and status indicators cannot shift the table.

## Components

- Card frame: fixed-size compact card with rarity border, type/power chips, status/state badges, and no generated artwork.
- Hero panel: larger than normal utility panels, with HP bar and readable player/resource labels.
- Board slot: fixed slot with clear empty, legal, occupied, and targetable states.
- Action log: compact, scrollable, newest action visible.
- Debug sandbox: available but subordinate, hidden by default.

## Motion

Use short 120-180 ms feedback for damage, boost, heal, targeting, and phase changes. Prefer scale, opacity, and color modulation. Avoid long choreography, layout movement, or effects that obscure the board.
