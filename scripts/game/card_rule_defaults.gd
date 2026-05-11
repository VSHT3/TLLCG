class_name CardRuleDefaults
extends RefCounted


static func apply_instance_defaults(card: CardInstance) -> void:
	match card.data.id:
		"hnusny_domaci_produkt":
			if card.timer == 0:
				card.timer = 3
		"velky_jazykovy_model":
			if card.counter == 0:
				card.counter = 2


static func timer_tick_amount(card: CardInstance) -> int:
	if card.data.id == "hnusny_domaci_produkt" and card.timer > 10:
		return 2
	return 1
