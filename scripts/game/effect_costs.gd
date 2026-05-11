class_name EffectCosts
extends RefCounted


static func effective_pay_cost(card: CardInstance, effect: CardEffect, player: PlayerState) -> int:
	if card.data.id == "velky_jazykovy_model" and effect.trigger == "pay":
		return maxi(0, effect.pay_cost - count_ai_gods_units(player))
	return effect.pay_cost


static func count_ai_gods_units(player: PlayerState) -> int:
	var count := 0
	for board_card in player.get_all_board_units():
		if board_card.data.type == "Unit" and "A.I. Gods" in board_card.data.factions:
			count += 1
	return count
