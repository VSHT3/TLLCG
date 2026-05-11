## CardTestRunner
## Lightweight automated card-data audit for the debug sandbox.
class_name CardTestRunner
extends RefCounted

const VALID_TYPES := ["Unit", "Spell", "Artifact", "Hero"]
const VALID_RARITIES := ["Common", "Rare", "Epic", "Legendary", "Hero"]
const VALID_EFFECT_TYPES := [
	"damage", "boost", "heal", "profit", "income", "draw", "apply_status",
	"destroy", "banish", "spy", "devour", "seize", "block", "gain_charge",
	"cleanse", "discard", "complex"
]
const VALID_TRIGGERS := [
	"passive", "deploy", "last_word", "deathblow", "turn_start", "turn_end",
	"timer", "upkeep", "tribute", "order", "hoard", "pay", "counter", "spot_67"
]
const VALID_TARGET_SCOPES := ["self", "ally", "enemy", "any"]
const VALID_TARGET_KINDS := ["card", "unit", "hero", "artifact", "non_hero", "non_unit"]
const IMPLEMENTED_COMPLEX_IDS := [
	"accountant_pro_max", "carry_on", "catch_up", "hhmds", "individual_sailor",
	"sir_vant", "s_ibal", "knight", "tax_er", "fukacia_pracicka",
	"everything_here_here", "sibal_so_sledovanim_lucov", "the_lion_does_not_care",
	"sir_vival", "biblography", "the_prophet", "opakovacia_dedinka",
	"breakthru", "dawood", "discard_this_card", "claws_the_production",
	"my_country_called_me", "negromancy", "negromancy_premium", "sellers_sailors",
	"premium_account", "scrolling_papers", "damina", "trembling_lips",
	"miss_spell", "mikrofo_novy_pokles", "the_why_axes", "sir_veillance",
	"obratnost_ruk", "mr_rural", "velke_jazykove_monstrum", "nak_mitchrbat",
	"masovystit", "hnusny_domaci_produkt", "sir_plus", "velky_jazykovy_model"
]


func run_all() -> Dictionary:
	var result := {
		"passed": 0,
		"warnings": 0,
		"failed": 0,
		"lines": PackedStringArray(),
	}
	_add_line(result, "Card audit started.")
	_audit_cards(result)
	_add_line(result, "Audit complete: %d pass, %d warning, %d fail." % [
		result["passed"],
		result["warnings"],
		result["failed"],
	])
	return result


func _audit_cards(result: Dictionary) -> void:
	var database := _database()
	if not database:
		_check(result, false, "CardDatabase", "autoload is unavailable")
		return
	var cards_dict: Dictionary = database.get("cards")
	var cards: Array = cards_dict.values()
	cards.sort_custom(func(a: CardData, b: CardData) -> bool:
		return a.id < b.id
	)
	for card in cards:
		_audit_card(card, result)


func _audit_card(card: CardData, result: Dictionary) -> void:
	var context := "%s (%s)" % [card.name, card.id]
	_check(result, card.id.strip_edges() != "", context, "missing id")
	_check(result, card.name.strip_edges() != "", context, "missing name")
	_check(result, card.type in VALID_TYPES, context, "invalid type: %s" % card.type)
	_check(result, card.rarity in VALID_RARITIES, context, "invalid rarity: %s" % card.rarity)
	_check(result, not card.factions.is_empty(), context, "missing faction")
	if card.type in ["Unit", "Hero"]:
		_check(result, card.base_power > 0, context, "board card has no power")
	if card.has_ability and card.effects.is_empty():
		_warn(result, context, "has ability text but no structured effects")
	if not card.has_ability and not card.effects.is_empty():
		_warn(result, context, "has structured effects but has_ability is false")
	var inst := CardInstance.create(card, 0)
	_check(result, inst != null and inst.data == card, context, "CardInstance creation failed")
	for effect in card.effects:
		_audit_effect(card, effect, result)


func _audit_effect(card: CardData, effect: CardEffect, result: Dictionary) -> void:
	var context := "%s (%s) %s/%s" % [card.name, card.id, effect.trigger, effect.type]
	_check(result, effect.type in VALID_EFFECT_TYPES, context, "unknown effect type")
	_check(result, effect.trigger in VALID_TRIGGERS, context, "unknown trigger")
	_check(result, effect.target_scope in VALID_TARGET_SCOPES, context, "unknown target scope: %s" % effect.target_scope)
	_check(result, effect.target_kind in VALID_TARGET_KINDS, context, "unknown target kind: %s" % effect.target_kind)
	if effect.trigger == "timer":
		_check(result, effect.timer_value > 0 or effect.raw_text.to_lower().contains("timer"), context, "timer trigger without timer value")
	if effect.trigger == "hoard":
		_check(result, effect.hoard_threshold > 0, context, "hoard trigger without threshold")
	if effect.trigger == "tribute":
		_check(result, effect.tribute_cost > 0, context, "tribute trigger without cost")
	if effect.trigger == "pay":
		_check(result, effect.pay_cost > 0 or _has_paid_pay_sibling(card, effect), context, "pay trigger without cost")
	if effect.type == "apply_status":
		_check(result, _is_known_status(effect.status), context, "unknown status: %s" % effect.status)
	if effect.type in ["damage", "boost", "profit", "income", "draw", "block", "gain_charge"] and effect.value <= 0:
		_warn(result, context, "numeric effect has no positive value")
	if effect.type == "complex" and not (card.id in IMPLEMENTED_COMPLEX_IDS):
		_warn(result, context, "complex fallback still needs manual system mapping")


func _is_known_status(status_name: String) -> bool:
	if status_name.strip_edges() == "":
		return false
	var database := _database()
	if not database:
		return false
	var statuses: Dictionary = database.get("statuses")
	var normalized := status_name.strip_edges().to_lower().replace(" ", "_")
	if statuses.has(normalized):
		return true
	for entry in statuses.values():
		if str(entry.get("name", "")).to_lower() == status_name.strip_edges().to_lower():
			return true
	return status_name in ["Economic Fury", "Miss Spell", "Protector", "Crit"]


func _has_paid_pay_sibling(card: CardData, effect: CardEffect) -> bool:
	if effect.raw_text.strip_edges() == "":
		return false
	for sibling in card.effects:
		if sibling == effect:
			continue
		if sibling.trigger == "pay" and sibling.pay_cost > 0 and sibling.raw_text == effect.raw_text:
			return true
	return false


func _database() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if not tree or not tree.root:
		return null
	return tree.root.get_node_or_null("CardDatabase")


func _check(result: Dictionary, condition: bool, context: String, message: String) -> void:
	if condition:
		result["passed"] += 1
	else:
		result["failed"] += 1
		_add_line(result, "FAIL  %s: %s" % [context, message])


func _warn(result: Dictionary, context: String, message: String) -> void:
	result["warnings"] += 1
	_add_line(result, "WARN  %s: %s" % [context, message])


func _add_line(result: Dictionary, text: String) -> void:
	var lines: PackedStringArray = result["lines"]
	lines.append(text)
	result["lines"] = lines
