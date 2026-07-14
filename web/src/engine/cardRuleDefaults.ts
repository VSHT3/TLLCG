// Port of scripts/game/card_rule_defaults.gd — per-card rule overrides.

import type { CardInstance } from "./cardInstance";

export function applyInstanceDefaults(card: CardInstance): void {
	switch (card.data.id) {
		case "hnusny_domaci_produkt":
			if (card.timer === 0) card.timer = 3;
			break;
		case "velky_jazykovy_model":
			if (card.counter === 0) card.counter = 2;
			break;
	}
}

export function timerTickAmount(card: CardInstance): number {
	if (card.data.id === "hnusny_domaci_produkt" && card.timer > 10) return 2;
	return 1;
}
