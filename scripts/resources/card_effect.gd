## CardEffect
## A single parsed effect from a card's ability text.
## Used by the EffectResolver to execute abilities at runtime.
class_name CardEffect
extends Resource

# ── Effect Type ──────────────────────────────────────────────────────────────
# damage, boost, heal, profit, income, draw, apply_status, destroy, banish,
# spy, devour, seize, block, complex
@export var type: String = "complex"

# ── Trigger ──────────────────────────────────────────────────────────────────
# passive, deploy, last_word, deathblow, turn_start, turn_end, timer,
# upkeep, tribute, order, hoard, spot_67
@export var trigger: String = "passive"

# ── Numeric Values ───────────────────────────────────────────────────────────
@export var value: int = 0
@export var stacks: int = 0
@export var timer_value: int = 0
@export var upkeep_cost: int = 0
@export var tribute_cost: int = 0
@export var hoard_threshold: int = 0
@export var pay_cost: int = 0
@export var initial_charges: int = 0
@export var charges: int = 0
@export var max_charges: int = 0
@export var counter_delta: int = 0
@export var counter_threshold: int = 0
@export var max_uses_per_turn: int = 0

# ── Status Info ──────────────────────────────────────────────────────────────
@export var status: String = ""
@export var permanent_status: bool = false

# ── Targeting Info ───────────────────────────────────────────────────────────
@export var target_scope: String = "enemy"  # self, ally, enemy, any
@export var target_kind: String = "card"  # card, unit, hero, artifact, non_hero, non_unit
@export var area: bool = false
@export var requires_target: bool = true

# ── Fallback ─────────────────────────────────────────────────────────────────
# For "complex" effects that couldn't be fully parsed.
@export var raw_text: String = ""


## Whether this effect requires manual targeting by the player.
func needs_target() -> bool:
	if not requires_target:
		return false
	if target_scope == "self":
		return false
	return type in ["damage", "boost", "heal", "apply_status", "destroy", "banish", "devour", "cleanse", "discard"]


## Whether this effect has a sellary cost.
func has_cost() -> bool:
	return upkeep_cost > 0 or tribute_cost > 0 or pay_cost > 0


## Get human-readable description.
func describe() -> String:
	match type:
		"damage":
			return "Deal %d damage" % value
		"boost":
			return "Boost %d" % value
		"heal":
			return "Heal %d" % value
		"profit":
			return "Profit %d" % value
		"income":
			return "Income %d" % value
		"draw":
			return "Draw %d" % value
		"apply_status":
			return "Apply %s %d" % [status, stacks]
		"destroy":
			return "Destroy target"
		"banish":
			return "Banish target"
		"spy":
			return "Spy"
		"devour":
			return "Devour ally"
		"seize":
			return "Seize %d" % value
		"block":
			return "Block %d" % value
		"gain_charge":
			return "Gain %d charge" % value
		"cleanse":
			return "Cleanse"
		"discard":
			return "Discard"
		"complex":
			return raw_text if raw_text else "Complex effect"
		_:
			return type
