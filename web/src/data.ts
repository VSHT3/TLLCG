// Wires the real data/*.json (generated from the Obsidian vault) into a CardDatabase.

import cardsJson from "@data/cards.json";
import factionsJson from "@data/factions.json";
import statusesJson from "@data/statuses.json";
import keywordsJson from "@data/keywords.json";
import categoriesJson from "@data/categories.json";
import rulesJson from "@data/rules.json";
import { CardDatabase, type CardJson, type FactionJson } from "./engine/cardDatabase";
import { loadRules, type RulesJson } from "./engine/constants";

export function createDefaultDatabase(): CardDatabase {
	loadRules(rulesJson as RulesJson);
	return new CardDatabase({
		cards: cardsJson as CardJson[],
		factions: factionsJson as FactionJson[],
		statuses: statusesJson as { id?: string }[],
		keywords: keywordsJson as { id?: string }[],
		categories: categoriesJson as { id?: string }[],
		rules: rulesJson as RulesJson,
	});
}
