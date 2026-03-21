#!/usr/bin/env python3
"""
TLLCG YAML-to-JSON Converter
=============================
Parses all card .md files (YAML frontmatter + Ability section) and system .md files
from the TLLCG repository into clean JSON data files ready for Godot import.

Usage:
    python yaml_to_json.py <repo_path> <output_dir>

Example:
    python yaml_to_json.py /path/to/TLLCG ./data

Output:
    data/cards.json       - All card definitions
    data/keywords.json    - All keyword definitions
    data/statuses.json    - All status definitions
    data/categories.json  - All category definitions
    data/factions.json    - Faction metadata
    data/rules.json       - Game rules/constants
"""

import json
import os
import re
import sys
from pathlib import Path


# ── Helpers ──────────────────────────────────────────────────────────────────

def parse_yaml_frontmatter(content: str) -> tuple[dict, str]:
    """Extract YAML frontmatter and body from a markdown file.
    Returns (frontmatter_dict, body_text).
    """
    if not content.startswith("---"):
        return {}, content

    # Find the closing ---
    end_idx = content.find("---", 3)
    if end_idx == -1:
        return {}, content

    yaml_block = content[3:end_idx].strip()
    body = content[end_idx + 3:].strip()

    # Parse YAML manually (avoids pyyaml dependency — works for our flat/list structure)
    data = {}
    current_key = None
    current_list = None

    for line in yaml_block.split("\n"):
        stripped = line.strip()
        if not stripped:
            continue

        # List item under a key
        if stripped.startswith("- ") and current_key is not None:
            value = stripped[2:].strip()
            if current_list is None:
                current_list = []
            current_list.append(value)
            data[current_key] = current_list
            continue

        # Key: value pair
        if ":" in stripped:
            # Save previous list if any
            if current_key and current_list is not None:
                data[current_key] = current_list

            colon_idx = stripped.index(":")
            key = stripped[:colon_idx].strip()
            value = stripped[colon_idx + 1:].strip()

            current_key = key
            current_list = None

            if value:
                # Inline value (not a list)
                # Handle booleans
                if value.lower() == "true":
                    data[key] = True
                elif value.lower() == "false":
                    data[key] = False
                # Handle numbers
                elif value.isdigit():
                    data[key] = int(value)
                else:
                    try:
                        data[key] = float(value)
                    except ValueError:
                        data[key] = value
            # else: value will come as list items or remain empty

    return data, body


def clean_ability_text(text: str) -> str:
    """Strip Obsidian wiki-links, image embeds, and flavor text from ability text."""
    # Remove image embeds: ![[...]]
    text = re.sub(r'!\[\[.*?\]\]', '', text)
    # Convert Obsidian wiki-links to plain text: [[Page#^anchor|display]] -> display
    text = re.sub(r'\[\[[^\]]*?\|([^\]]+?)\]\]', r'\1', text)
    # Convert remaining wiki-links: [[Page]] -> Page
    text = re.sub(r'\[\[([^\]]+?)\]\]', r'\1', text)
    # Remove italic flavor text lines (lines starting and ending with *)
    lines = []
    for line in text.split("\n"):
        stripped = line.strip()
        if stripped.startswith("*") and len(stripped) > 2:
            # Check if entire line is italic (flavor text)
            if stripped.endswith("*") or stripped.endswith("*."):
                continue
            # Also catch multi-line italic blocks
            if stripped.count("*") <= 2:  # Single italic block likely flavor
                continue
        lines.append(line)
    text = "\n".join(lines)
    # Clean up whitespace
    text = re.sub(r'\n{3,}', '\n\n', text)
    return text.strip()


def extract_ability(body: str) -> str:
    """Extract the ability text from the markdown body (after ## Ability or # Ability heading)."""
    # Find ability section
    match = re.search(r'^#{1,2}\s*Ability\s*$', body, re.MULTILINE)
    if not match:
        return ""

    ability_text = body[match.end():]

    # Cut off at the next heading if any
    next_heading = re.search(r'^#{1,2}\s+\S', ability_text, re.MULTILINE)
    if next_heading:
        ability_text = ability_text[:next_heading.start()]

    return clean_ability_text(ability_text)


def sanitize_id(name: str) -> str:
    """Convert a card name to a safe snake_case ID."""
    # Replace special chars
    s = name.lower()
    s = s.replace(".", "_").replace("'", "").replace("'", "")
    s = s.replace("á", "a").replace("č", "c").replace("é", "e").replace("í", "i")
    s = s.replace("ó", "o").replace("ú", "u").replace("ý", "y").replace("ž", "z")
    s = s.replace("š", "s").replace("ň", "n").replace("ť", "t").replace("ď", "d")
    s = s.replace("ľ", "l").replace("ř", "r").replace("ô", "o").replace("ä", "a")
    s = re.sub(r'[^a-z0-9]+', '_', s)
    s = s.strip('_')
    return s


# ── Card Parser ──────────────────────────────────────────────────────────────

def parse_card_file(filepath: Path) -> dict:
    """Parse a single card .md file into a structured dict."""
    content = filepath.read_text(encoding="utf-8")
    frontmatter, body = parse_yaml_frontmatter(content)

    card_name = filepath.stem  # Filename without .md

    # Extract frontmatter fields with normalization
    card_type_raw = frontmatter.get("Card Type", [])
    if isinstance(card_type_raw, list):
        card_type = card_type_raw[0] if card_type_raw else "Unknown"
    else:
        card_type = str(card_type_raw) if card_type_raw else "Unknown"

    rarity_raw = frontmatter.get("Card Rarity", [])
    if isinstance(rarity_raw, list):
        rarity = rarity_raw[0] if rarity_raw else "Unknown"
    else:
        rarity = str(rarity_raw) if rarity_raw else "Unknown"

    faction_raw = frontmatter.get("Card Faction", [])
    if isinstance(faction_raw, str):
        faction_raw = [faction_raw]
    elif not isinstance(faction_raw, list):
        faction_raw = []

    category_raw = frontmatter.get("Card Category", [])
    if isinstance(category_raw, str):
        category_raw = [category_raw] if category_raw else []
    elif not isinstance(category_raw, list):
        category_raw = []
    # Filter empty strings
    category_raw = [c for c in category_raw if c]

    power = frontmatter.get("Card Power")
    if power is not None:
        try:
            power = int(power)
        except (ValueError, TypeError):
            power = 0
    else:
        power = 0 if card_type in ("Unit", "Hero") else None

    has_ability = frontmatter.get("Ability", False)
    ability_text = extract_ability(body) if has_ability else ""

    # Artwork path
    artwork = frontmatter.get("feature", "")
    if artwork:
        # Strip "Artworks/" prefix for Godot-relative path
        artwork = artwork.replace("Artworks/", "")

    card = {
        "id": sanitize_id(card_name),
        "name": card_name,
        "type": card_type,
        "rarity": rarity,
        "factions": [f for f in faction_raw if f],
        "categories": category_raw,
        "power": power,
        "has_ability": has_ability,
        "ability_text": ability_text,
        "artwork": artwork,
    }

    # Parse ability into structured effects (best-effort)
    if ability_text:
        card["effects"] = parse_ability_effects(ability_text, card_name)

    return card


# ── Ability Effect Parser ────────────────────────────────────────────────────

def parse_ability_effects(text: str, card_name: str = "") -> list[dict]:
    """
    Best-effort parse of ability text into structured effect objects.
    This doesn't cover every edge case — the Godot effect resolver
    will use these as hints combined with the raw text fallback.
    """
    effects = []
    text_lower = text.lower()

    # Detect triggers
    trigger = "passive"
    if "deploy" in text_lower:
        trigger = "deploy"
    elif "last word" in text_lower:
        trigger = "last_word"
    elif "deathblow" in text_lower:
        trigger = "deathblow"
    elif "at the start of your turn" in text_lower:
        trigger = "turn_start"
    elif "at the end of your turn" in text_lower:
        trigger = "turn_end"
    elif re.search(r'timer\s+\d+', text_lower):
        trigger = "timer"
    elif "upkeep" in text_lower:
        trigger = "upkeep"
    elif "tribute" in text_lower:
        trigger = "tribute"
    elif re.search(r'order\b', text_lower):
        trigger = "order"
    elif re.search(r'hoard\s+\d+', text_lower):
        trigger = "hoard"
    elif "spot valid 67" in text_lower:
        trigger = "spot_67"

    # Detect effect types
    # Damage
    dmg_match = re.search(r'deal\s+(\d+)\s+damage', text_lower)
    if dmg_match:
        effects.append({
            "type": "damage",
            "value": int(dmg_match.group(1)),
            "trigger": trigger,
        })

    # Boost
    boost_match = re.search(r'boost\s+(\d+)', text_lower)
    if boost_match:
        effects.append({
            "type": "boost",
            "value": int(boost_match.group(1)),
            "trigger": trigger,
        })

    # Heal
    heal_match = re.search(r'heal\s+(\d+)', text_lower)
    if heal_match:
        effects.append({
            "type": "heal",
            "value": int(heal_match.group(1)),
            "trigger": trigger,
        })

    # Profit
    profit_match = re.search(r'profit\s+(\d+)', text_lower)
    if profit_match:
        effects.append({
            "type": "profit",
            "value": int(profit_match.group(1)),
            "trigger": trigger,
        })

    # Income
    income_match = re.search(r'income\s+(\d+)', text_lower)
    if income_match:
        effects.append({
            "type": "income",
            "value": int(income_match.group(1)),
            "trigger": "turn_start",
        })

    # Draw
    draw_match = re.search(r'draw\s+(?:up to\s+)?(\d+)', text_lower)
    if draw_match:
        effects.append({
            "type": "draw",
            "value": int(draw_match.group(1)),
            "trigger": trigger,
        })

    # Apply status
    status_pattern = r'apply\s+(cursed|vulnerable|perplexed|invisible|cancerous|economic fury|drunk|defender|protector|poison|burn|wither)(?:\s+(\d+))?'
    for m in re.finditer(status_pattern, text_lower):
        effects.append({
            "type": "apply_status",
            "status": m.group(1),
            "stacks": int(m.group(2)) if m.group(2) else 1,
            "trigger": trigger,
        })

    # Destroy
    if "destroy" in text_lower and not dmg_match:
        effects.append({
            "type": "destroy",
            "trigger": trigger,
        })

    # Banish
    if "banish" in text_lower:
        effects.append({
            "type": "banish",
            "trigger": trigger,
        })

    # Spy
    if "spy" in text_lower:
        effects.append({
            "type": "spy",
            "trigger": trigger,
        })

    # Devour
    if "devour" in text_lower:
        effects.append({
            "type": "devour",
            "trigger": trigger,
        })

    # Seize
    seize_match = re.search(r'seize\s+(\d+)', text_lower)
    if seize_match:
        effects.append({
            "type": "seize",
            "value": int(seize_match.group(1)),
            "trigger": trigger,
        })

    # Timer
    timer_match = re.search(r'timer\s+(\d+)', text_lower)
    if timer_match:
        # Add timer metadata to all effects
        for eff in effects:
            if eff["trigger"] == "timer":
                eff["timer_value"] = int(timer_match.group(1))

    # Upkeep cost
    upkeep_match = re.search(r'upkeep\s+(\d+)', text_lower)
    if upkeep_match:
        for eff in effects:
            if eff["trigger"] == "upkeep":
                eff["upkeep_cost"] = int(upkeep_match.group(1))

    # Tribute cost
    trib_match = re.search(r'tribute\s+(\d+)', text_lower)
    if trib_match:
        for eff in effects:
            if eff["trigger"] == "tribute":
                eff["tribute_cost"] = int(trib_match.group(1))

    # Hoard threshold
    hoard_match = re.search(r'hoard\s+(\d+)', text_lower)
    if hoard_match:
        for eff in effects:
            if eff["trigger"] == "hoard":
                eff["hoard_threshold"] = int(hoard_match.group(1))

    # Block
    block_match = re.search(r'block\s+(\d+)', text_lower)
    if block_match:
        effects.append({
            "type": "block",
            "value": int(block_match.group(1)),
            "trigger": "passive",
        })

    # Charge
    charge_match = re.search(r'charge\s+(\d+)', text_lower)
    if charge_match:
        for eff in effects:
            if eff.get("trigger") == "order":
                eff["charges"] = int(charge_match.group(1))

    # If nothing was parsed, mark as complex/manual
    if not effects:
        effects.append({
            "type": "complex",
            "trigger": trigger,
            "raw_text": text,
        })

    return effects


# ── System File Parsers ──────────────────────────────────────────────────────

def parse_keywords(filepath: Path) -> list[dict]:
    """Parse Keywords.md into structured keyword definitions."""
    content = filepath.read_text(encoding="utf-8")
    keywords = []

    # Split on bold headers: **Keyword**
    pattern = r'\*\*(.+?)\*\*\s*\n(.*?)(?=\n\*\*|\n#|\Z)'
    for match in re.finditer(pattern, content, re.DOTALL):
        name = match.group(1).strip()
        description = match.group(2).strip()

        # Remove anchor tags ^xxx
        description = re.sub(r'\^[a-z0-9]+', '', description).strip()
        # Clean wiki-links
        description = re.sub(r'\[\[[^\]]*?\|([^\]]+?)\]\]', r'\1', description)
        description = re.sub(r'\[\[([^\]]+?)\]\]', r'\1', description)

        # Extract X parameter if present
        has_value = "$X$" in match.group(2) or "$x$" in match.group(2)
        description = description.replace("$X$", "X").replace("$x$", "X")
        description = description.replace("**X**", "X").replace("**$X$**", "X")

        # Check for {status} parameter
        has_status_param = "{status}" in description

        keywords.append({
            "id": sanitize_id(name),
            "name": name,
            "description": description,
            "has_value": has_value,
            "has_status_param": has_status_param,
        })

    return keywords


def parse_statuses(filepath: Path) -> list[dict]:
    """Parse Statuses.md into structured status definitions."""
    content = filepath.read_text(encoding="utf-8")

    # Remove YAML frontmatter if present
    if content.startswith("---"):
        end_idx = content.find("---", 3)
        if end_idx != -1:
            content = content[end_idx + 3:]

    statuses = []
    pattern = r'\*\*(.+?)\*\*\s*\n(.*?)(?=\n\*\*|\Z)'
    for match in re.finditer(pattern, content, re.DOTALL):
        name = match.group(1).strip()
        description = match.group(2).strip()

        # Remove anchor tags
        description = re.sub(r'\^[a-z0-9]+', '', description).strip()
        # Clean wiki-links
        description = re.sub(r'\[\[[^\]]*?\|([^\]]+?)\]\]', r'\1', description)
        description = re.sub(r'\[\[([^\]]+?)\]\]', r'\1', description)
        # Clean LaTeX fractions
        description = re.sub(r'\$\\frac\{(\d+)\}\{(\d+)\}\$', r'\1/\2', description)

        # Determine if stackable and diminish behavior
        stackable = "stack" in description.lower() or "per stack" in description.lower()
        diminishes = "dissepates" in description.lower() or "dissapates" in description.lower() or "diminish" in description.lower()
        damages = "damage self" in description.lower() or "damage" in description.lower()

        statuses.append({
            "id": sanitize_id(name),
            "name": name,
            "description": description,
            "stackable": stackable,
            "diminishes": diminishes,
            "damages_self": damages,
        })

    return statuses


def parse_categories(filepath: Path) -> list[dict]:
    """Parse Categories.md into structured category definitions."""
    content = filepath.read_text(encoding="utf-8")

    # Remove YAML frontmatter
    if content.startswith("---"):
        end_idx = content.find("---", 3)
        if end_idx != -1:
            content = content[end_idx + 3:]

    categories = []
    pattern = r'###?\s*\*\*(.+?)\*\*\s*\n(.*?)(?=\n###?\s*\*\*|\Z)'
    for match in re.finditer(pattern, content, re.DOTALL):
        name = match.group(1).strip()
        description = match.group(2).strip()
        description = re.sub(r'\[\[[^\]]*?\|([^\]]+?)\]\]', r'\1', description)
        description = re.sub(r'\[\[([^\]]+?)\]\]', r'\1', description)

        categories.append({
            "id": sanitize_id(name),
            "name": name,
            "description": description,
        })

    return categories


# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <repo_path> <output_dir>")
        sys.exit(1)

    repo_path = Path(sys.argv[1])
    output_dir = Path(sys.argv[2])
    output_dir.mkdir(parents=True, exist_ok=True)

    cards_dir = repo_path / "Cards"
    systems_dir = repo_path / "Systems"

    # ── Parse all cards ──
    print(f"Parsing cards from {cards_dir}...")
    cards = []
    errors = []
    for md_file in sorted(cards_dir.glob("*.md")):
        try:
            card = parse_card_file(md_file)
            cards.append(card)
        except Exception as e:
            errors.append(f"  ERROR parsing {md_file.name}: {e}")

    print(f"  Parsed {len(cards)} cards ({len(errors)} errors)")
    for err in errors:
        print(err)

    # ── Parse systems ──
    print("Parsing system files...")
    keywords = parse_keywords(systems_dir / "Keywords.md")
    print(f"  {len(keywords)} keywords")

    statuses = parse_statuses(systems_dir / "Statuses.md")
    print(f"  {len(statuses)} statuses")

    categories = parse_categories(systems_dir / "Categories.md")
    print(f"  {len(categories)} categories")

    # ── Derive factions ──
    faction_set = set()
    for card in cards:
        for f in card["factions"]:
            if f:
                faction_set.add(f)

    factions = []
    for f_name in sorted(faction_set):
        f_cards = [c for c in cards if f_name in c["factions"]]
        heroes = [c for c in f_cards if c["type"] == "Hero"]
        factions.append({
            "id": sanitize_id(f_name),
            "name": f_name,
            "hero": heroes[0]["name"] if heroes else None,
            "card_count": len(f_cards),
            "card_ids": [c["id"] for c in f_cards],
        })

    # ── Game rules/constants ──
    rules = {
        "hero_base_hp": 30,
        "base_sellary_per_turn": 5,
        "max_cards_per_turn": 2,
        "max_hand_size": 10,
        "neutral_draw_base_cost": 3,
        "neutral_draw_extra_cost": 1,
        "faction_draw_base_cost": 4,
        "faction_draw_extra_cost": 1,
        "row_capacities": [5, 5, 3],
        "row_names": ["melee", "ranged", "artillery"],
        "turn_phases": [
            "sellary",
            "start_of_turn_abilities",
            "play_cards",
            "discard_cards",
            "draw_cards",
            "end_of_turn_abilities",
            "status_trigger",
            "status_diminish",
        ],
        "activation_order": "melee_to_artillery_left_to_right",
    }

    # ── Write outputs ──
    def write_json(data, filename):
        path = output_dir / filename
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
        print(f"  Wrote {path} ({len(json.dumps(data))} bytes)")

    print("\nWriting JSON files...")
    write_json(cards, "cards.json")
    write_json(keywords, "keywords.json")
    write_json(statuses, "statuses.json")
    write_json(categories, "categories.json")
    write_json(factions, "factions.json")
    write_json(rules, "rules.json")

    # ── Summary ──
    print(f"\n{'='*60}")
    print(f"TLLCG Data Export Summary")
    print(f"{'='*60}")
    print(f"  Cards:      {len(cards)}")
    type_counts = {}
    for c in cards:
        t = c["type"]
        type_counts[t] = type_counts.get(t, 0) + 1
    for t, count in sorted(type_counts.items()):
        print(f"    {t}: {count}")
    print(f"  Keywords:   {len(keywords)}")
    print(f"  Statuses:   {len(statuses)}")
    print(f"  Categories: {len(categories)}")
    print(f"  Factions:   {len(factions)}")
    for f in factions:
        print(f"    {f['name']}: {f['card_count']} cards (hero: {f['hero']})")
    ability_count = sum(1 for c in cards if c["has_ability"] and c.get("ability_text"))
    print(f"  Cards with abilities: {ability_count}")
    no_ability = [c["name"] for c in cards if c["has_ability"] and not c.get("ability_text")]
    if no_ability:
        print(f"  Cards marked has_ability but no text: {len(no_ability)}")
    print(f"{'='*60}")


if __name__ == "__main__":
    main()
