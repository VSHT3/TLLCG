## CardData
## Immutable definition of a card — loaded from JSON, never mutated at runtime.
## For in-game state, see CardInstance.
class_name CardData
extends Resource

@export var id: String = ""
@export var name: String = ""
@export var type: String = "Unknown"  # Unit, Spell, Artifact, Hero
@export var rarity: String = "Unknown"  # Common, Rare, Epic, Legendary, Hero
@export var factions: Array = []  # ["Neutral"], ["Sir Can"], etc.
@export var categories: Array = []  # ["Token", "A.I."], etc.
@export var base_power: int = 0
@export var has_ability: bool = false
@export var ability_text: String = ""
@export var artwork_path: String = ""
@export var effects: Array = []  # Array of CardEffect


## Check if this card belongs to a given faction.
func is_faction(faction_name: String) -> bool:
	return faction_name in factions


## Check if this card has a specific category.
func has_category(category_name: String) -> bool:
	return category_name in categories


## Whether this is a Token (permanent Cursed).
func is_token() -> bool:
	return has_category("Token")


## Whether this card can be placed on the board (Unit or Hero).
func is_boardable() -> bool:
	return type == "Unit" or type == "Hero"


## Whether this card is a one-shot (Spell).
func is_spell() -> bool:
	return type == "Spell"


## Whether this card is a persistent non-unit (Artifact).
func is_artifact() -> bool:
	return type == "Artifact"
