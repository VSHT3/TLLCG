// Core data types — 1:1 port of scripts/resources/card_data.gd + card_effect.gd.
// CardData/CardEffect are immutable plain objects loaded from data/cards.json.
// Runtime state lives in CardInstance (cardInstance.ts).

export type CardType = "Unit" | "Spell" | "Artifact" | "Hero" | "Unknown";

export type Zone = "deck" | "hand" | "board" | "graveyard" | "banished";

export type EffectType =
	| "damage"
	| "boost"
	| "heal"
	| "profit"
	| "income"
	| "draw"
	| "apply_status"
	| "destroy"
	| "banish"
	| "spy"
	| "devour"
	| "seize"
	| "block"
	| "gain_charge"
	| "cleanse"
	| "discard"
	| "complex";

export type EffectTrigger =
	| "passive"
	| "deploy"
	| "last_word"
	| "deathblow"
	| "turn_start"
	| "turn_end"
	| "timer"
	| "upkeep"
	| "tribute"
	| "order"
	| "pay"
	| "hoard"
	| "spot_67";

export type TargetScope = "self" | "ally" | "enemy" | "any";
export type TargetKind = "card" | "unit" | "hero" | "artifact" | "non_hero" | "non_unit";

export interface CardEffect {
	type: EffectType;
	trigger: EffectTrigger;
	value: number;
	stacks: number;
	timerValue: number;
	upkeepCost: number;
	tributeCost: number;
	hoardThreshold: number;
	payCost: number;
	initialCharges: number;
	charges: number;
	maxCharges: number;
	counterDelta: number;
	counterThreshold: number;
	maxUsesPerTurn: number;
	status: string;
	permanentStatus: boolean;
	targetScope: TargetScope;
	targetKind: TargetKind;
	area: boolean;
	requiresTarget: boolean;
	rawText: string;
}

export interface CardData {
	id: string;
	name: string;
	type: CardType;
	rarity: string;
	factions: string[];
	categories: string[];
	basePower: number;
	hasAbility: boolean;
	abilityText: string;
	artworkPath: string;
	effects: CardEffect[];
	/** Complex card has working code (mirrors "implemented" in cards.json). */
	implemented?: boolean;
}

export interface BoardPosition {
	row: number;
	col: number;
}

// ── CardData/CardEffect helpers (card_data.gd / card_effect.gd methods) ──────
// Trivial GDScript methods (is_faction, is_spell, is_artifact, is_boardable)
// are inlined at callsites: card.factions.includes(f), card.type === "Spell", …

/** Token cards carry permanent Cursed (domain rule, checked in cleanse/diminish/isCursed). */
export function isToken(card: CardData): boolean {
	return card.categories.includes("Token");
}

const TARGETED_EFFECT_TYPES: Record<string, true> = {
	damage: true,
	boost: true,
	heal: true,
	apply_status: true,
	destroy: true,
	banish: true,
	devour: true,
	cleanse: true,
	discard: true,
};

export function effectNeedsTarget(effect: CardEffect): boolean {
	if (!effect.requiresTarget) return false;
	if (effect.targetScope === "self") return false;
	return TARGETED_EFFECT_TYPES[effect.type] === true;
}

export function effectHasCost(effect: CardEffect): boolean {
	return effect.upkeepCost > 0 || effect.tributeCost > 0 || effect.payCost > 0;
}

// ── Card database contract (scripts/autoloads/card_database.gd) ──────────────
// Implemented by cardDatabase.ts; state layer consumes only this surface.

export interface CardDatabaseApi {
	getCard(id: string): CardData | null;
	getHero(faction: string): CardData | null;
	/** Non-hero deck cards of a faction (deck filter: hasAbility only, applied by caller). */
	getCardsByFaction(faction: string): CardData[];
	getNeutralCards(): CardData[];
}
