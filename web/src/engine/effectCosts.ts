// Port of scripts/game/effect_costs.gd.

import type { CardEffect } from "./types";
import type { CardInstance } from "./cardInstance";
import type { PlayerState } from "./playerState";

export function effectivePayCost(card: CardInstance, effect: CardEffect, player: PlayerState): number {
	if (card.data.id === "velky_jazykovy_model" && effect.trigger === "pay") {
		return Math.max(0, effect.payCost - countAiGodsUnits(player));
	}
	return effect.payCost;
}

export function countAiGodsUnits(player: PlayerState): number {
	let count = 0;
	for (const boardCard of player.getAllBoardUnits()) {
		if (boardCard.data.type === "Unit" && boardCard.data.factions.includes("A.I. Gods")) {
			count++;
		}
	}
	return count;
}
