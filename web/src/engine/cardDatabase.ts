// Port of scripts/autoloads/card_database.gd — JSON → CardData loading,
// including the pay-effect synthesis from ability text.
// Deviation: resolveAbilityText outputs plain text (no BBCode) — wiki links and
// ** markers are stripped; the web UI styles text itself.

import { Constants, type RulesJson } from "./constants";
import type { CardData, CardDatabaseApi, CardEffect, CardType, EffectType } from "./types";

export interface CardJson {
	id?: string;
	name?: string;
	type?: string;
	rarity?: string;
	factions?: string[];
	categories?: string[];
	power?: number | null;
	has_ability?: boolean;
	ability_text?: string;
	artwork?: string;
	implemented?: boolean;
	effects?: EffectJson[];
}

export interface EffectJson {
	type?: string;
	trigger?: string;
	value?: number;
	status?: string;
	stacks?: number;
	timer_value?: number;
	upkeep_cost?: number;
	tribute_cost?: number;
	hoard_threshold?: number;
	pay_cost?: number;
	initial_charges?: number;
	charges?: number;
	max_charges?: number;
	counter_delta?: number;
	counter_threshold?: number;
	max_uses_per_turn?: number;
	permanent_status?: boolean;
	target_scope?: string;
	target_kind?: string;
	area?: boolean;
	requires_target?: boolean;
	raw_text?: string;
}

export interface FactionJson {
	id?: string;
	name?: string;
	hero?: string | null;
	card_ids?: string[];
}

export interface DatabasePayload {
	cards: CardJson[];
	factions?: FactionJson[];
	statuses?: { id?: string; [k: string]: unknown }[];
	keywords?: { id?: string; [k: string]: unknown }[];
	categories?: { id?: string; [k: string]: unknown }[];
	rules?: RulesJson;
}

export class CardDatabase implements CardDatabaseApi {
	readonly cards = new Map<string, CardData>();
	readonly factions = new Map<string, FactionJson>();
	readonly statuses = new Map<string, Record<string, unknown>>();
	readonly keywords = new Map<string, Record<string, unknown>>();
	readonly categories = new Map<string, Record<string, unknown>>();
	readonly rules: RulesJson;

	constructor(payload: DatabasePayload) {
		this.rules = payload.rules ?? {};
		for (const entry of payload.factions ?? []) {
			if (entry.id) this.factions.set(entry.id, entry);
		}
		for (const entry of payload.statuses ?? []) {
			if (typeof entry.id === "string") this.statuses.set(entry.id, entry);
		}
		for (const entry of payload.keywords ?? []) {
			if (typeof entry.id === "string") this.keywords.set(entry.id, entry);
		}
		for (const entry of payload.categories ?? []) {
			if (typeof entry.id === "string") this.categories.set(entry.id, entry);
		}
		this.loadCards(payload.cards);
	}

	// ── Public API ─────────────────────────────────────────────────────────────

	getCard(cardId: string): CardData | null {
		return this.cards.get(cardId) ?? null;
	}

	getCardsByType(cardType: string): CardData[] {
		return [...this.cards.values()].filter((c) => c.type === cardType);
	}

	getCardsByFaction(factionName: string): CardData[] {
		return [...this.cards.values()].filter((c) => c.factions.includes(factionName));
	}

	getNeutralCards(): CardData[] {
		return this.getCardsByFaction("Neutral");
	}

	getHero(factionName: string): CardData | null {
		for (const card of this.cards.values()) {
			if (card.type === "Hero" && card.factions.includes(factionName)) return card;
		}
		return null;
	}

	getPlayableFactions(): string[] {
		const result: string[] = [];
		for (const f of this.factions.values()) {
			if (f.hero != null && f.name) result.push(f.name);
		}
		return result;
	}

	searchCards(query: string): CardData[] {
		const q = query.toLowerCase();
		return [...this.cards.values()].filter((c) => c.name.toLowerCase().includes(q));
	}

	/** Strip Obsidian wiki links and ** markers → plain readable text. */
	resolveAbilityText(raw: string): string {
		return raw
			.replace(/\[\[[^\]]*\|([^\]]+)\]\]/g, "$1")
			.replace(/\[\[([^\]|]+)\]\]/g, "$1")
			.replace(/\*\*([^*]+)\*\*/g, "$1");
	}

	// ── Loading ────────────────────────────────────────────────────────────────

	private loadCards(cardArray: CardJson[]): void {
		const factionCardIndex = this.buildFactionCardIndex();
		for (const entry of cardArray) {
			const id = (entry.id ?? "").trim();
			if (id === "") continue;

			const type = normalizeCardType(entry);
			let basePower = entry.power ?? 0;
			if ((type === "Unit" || type === "Hero") && basePower <= 0) {
				basePower = type === "Hero" ? Constants.HERO_BASE_HP : 1;
			}

			const card: CardData = {
				id,
				name: entry.name ?? "",
				type,
				rarity: normalizeRarity(entry),
				factions: normalizeFactions(id, entry, factionCardIndex),
				categories: entry.categories ?? [],
				basePower,
				hasAbility: entry.has_ability ?? false,
				abilityText: entry.ability_text ?? "",
				artworkPath: entry.artwork ?? "",
				effects: (entry.effects ?? []).map(parseEffect),
				implemented: entry.implemented,
			};

			ensurePayEffectsFromText(card);

			if (card.abilityText.trim() === "" && card.effects.length === 0) {
				card.hasAbility = false;
			}

			this.cards.set(card.id, card);
		}
	}

	private buildFactionCardIndex(): Map<string, string[]> {
		const result = new Map<string, string[]>();
		for (const faction of this.factions.values()) {
			const name = faction.name ?? "";
			if (name === "") continue;
			for (const cardId of faction.card_ids ?? []) {
				if (cardId === "") continue;
				const list = result.get(cardId);
				if (list) {
					list.push(name);
				} else {
					result.set(cardId, [name]);
				}
			}
		}
		return result;
	}
}

// ── Parsing helpers ──────────────────────────────────────────────────────────

function parseEffect(eff: EffectJson): CardEffect {
	return {
		type: (eff.type ?? "complex") as CardEffect["type"],
		trigger: (eff.trigger ?? "passive") as CardEffect["trigger"],
		value: eff.value ?? 0,
		status: eff.status ?? "",
		stacks: eff.stacks ?? 0,
		timerValue: eff.timer_value ?? 0,
		upkeepCost: eff.upkeep_cost ?? 0,
		tributeCost: eff.tribute_cost ?? 0,
		hoardThreshold: eff.hoard_threshold ?? 0,
		payCost: eff.pay_cost ?? 0,
		initialCharges: eff.initial_charges ?? 0,
		charges: eff.charges ?? 0,
		maxCharges: eff.max_charges ?? 0,
		counterDelta: eff.counter_delta ?? 0,
		counterThreshold: eff.counter_threshold ?? 0,
		maxUsesPerTurn: eff.max_uses_per_turn ?? 0,
		permanentStatus: eff.permanent_status ?? false,
		targetScope: (eff.target_scope ?? "enemy") as CardEffect["targetScope"],
		targetKind: (eff.target_kind ?? "card") as CardEffect["targetKind"],
		area: eff.area ?? false,
		requiresTarget: eff.requires_target ?? true,
		rawText: eff.raw_text ?? "",
	};
}

function normalizeCardType(entry: CardJson): CardType {
	switch ((entry.type ?? "").trim().toLowerCase()) {
		case "unit":
			return "Unit";
		case "spell":
			return "Spell";
		case "artifact":
			return "Artifact";
		case "hero":
			return "Hero";
	}
	if (entry.power != null) return "Unit";
	if ((entry.has_ability ?? false) || (entry.ability_text ?? "").trim() !== "") return "Spell";
	if ((entry.id ?? "").trim() !== "" || (entry.name ?? "").trim() !== "") return "Spell";
	return "Unknown";
}

function normalizeRarity(entry: CardJson): string {
	switch ((entry.rarity ?? "").trim().toLowerCase()) {
		case "common":
			return "Common";
		case "rare":
			return "Rare";
		case "epic":
			return "Epic";
		case "legendary":
			return "Legendary";
		case "hero":
			return "Hero";
	}
	if (entry.type === "Hero") return "Hero";
	return "Common";
}

function normalizeFactions(cardId: string, entry: CardJson, factionCardIndex: Map<string, string[]>): string[] {
	const result: string[] = [];
	for (const faction of entry.factions ?? []) {
		const name = faction.trim();
		if (name !== "" && !result.includes(name)) result.push(name);
	}
	for (const faction of factionCardIndex.get(cardId) ?? []) {
		if (!result.includes(faction)) result.push(faction);
	}
	if (result.length === 0 && entry.type !== "Hero") result.push("Neutral");
	return result;
}

// ── Pay-effect synthesis from ability text ───────────────────────────────────

function ensurePayEffectsFromText(card: CardData): void {
	if (card.abilityText.trim() === "") return;
	if (card.effects.some((e) => e.trigger === "pay" && e.payCost > 0)) return;

	for (const rawLine of card.abilityText.split("\n")) {
		const line = rawLine.trim();
		if (line === "") continue;
		const payMatch = /\bpay\s+(\d+)/i.exec(line);
		if (!payMatch) continue;
		const cost = parseInt(payMatch[1]!, 10);
		const added = appendSimplePayEffects(card, line, cost);
		if (!added) {
			const effect = newPayEffect("complex", cost, line);
			effect.requiresTarget = false;
			card.effects.push(effect);
		}
	}
}

function appendSimplePayEffects(card: CardData, line: string, cost: number): boolean {
	const lower = line.toLowerCase();
	let added = false;

	if (lower.includes("destroy self")) {
		const effect = newPayEffect("destroy", cost, line);
		effect.targetScope = "self";
		effect.requiresTarget = false;
		card.effects.push(effect);
		added = true;
	} else if (lower.includes("destroy")) {
		card.effects.push(newPayEffect("destroy", cost, line));
		added = true;
	}

	if (lower.includes("banish self")) {
		const effect = newPayEffect("banish", cost, line);
		effect.targetScope = "self";
		effect.requiresTarget = false;
		card.effects.push(effect);
		added = true;
	} else if (lower.includes("banish")) {
		card.effects.push(newPayEffect("banish", cost, line));
		added = true;
	}

	const boostValue = firstNumberAfter(lower, "boost");
	if (boostValue > 0) {
		const effect = newPayEffect("boost", cost, line);
		effect.value = boostValue;
		effect.targetScope = lower.includes("self") ? "self" : "ally";
		effect.targetKind = "unit";
		effect.requiresTarget = !lower.includes("self");
		card.effects.push(effect);
		added = true;
	}

	if (lower.includes("heal")) {
		const effect = newPayEffect("heal", cost, line);
		effect.value = firstNumberAfter(lower, "heal");
		effect.targetScope = effect.value <= 0 || lower.includes("self") ? "self" : "ally";
		effect.targetKind = lower.includes("hero") ? "hero" : "unit";
		effect.requiresTarget = !(effect.targetScope === "self" || lower.includes("your hero"));
		card.effects.push(effect);
		added = true;
	}

	const timerValue = firstNumberAfter(lower, "timer");
	if (timerValue > 0 && (lower.includes("increase timer") || lower.includes("timer by"))) {
		const effect = newPayEffect("complex", cost, line);
		effect.value = timerValue;
		effect.targetScope = "self";
		effect.requiresTarget = false;
		card.effects.push(effect);
		added = true;
	}

	const damageValue = firstDamageValue(lower);
	if (damageValue > 0) {
		const effect = newPayEffect("damage", cost, line);
		effect.value = damageValue;
		effect.targetScope = lower.includes("a hero") || lower.includes("hero") ? "any" : "enemy";
		effect.targetKind = lower.includes("hero") ? "hero" : "unit";
		effect.requiresTarget = true;
		card.effects.push(effect);
		added = true;
	}

	const drawValue = firstNumberAfter(lower, "draw");
	if (drawValue > 0) {
		const effect = newPayEffect("draw", cost, line);
		effect.value = drawValue;
		effect.targetScope = "self";
		effect.requiresTarget = false;
		card.effects.push(effect);
		added = true;
	}

	for (const statusName of ["invisible", "vulnerable", "cursed", "crit", "poison", "burn", "wither"]) {
		if (lower.includes(statusName)) {
			const effect = newPayEffect("apply_status", cost, line);
			effect.status = statusName[0]!.toUpperCase() + statusName.slice(1);
			effect.stacks = 1;
			effect.targetScope = lower.includes("self") ? "self" : "enemy";
			effect.targetKind = "card";
			effect.requiresTarget = !lower.includes("self");
			card.effects.push(effect);
			added = true;
		}
	}

	if (added) chargePayLineOnce(card, line, cost);
	return added;
}

/** Only the first effect synthesized from a pay line carries the cost. */
function chargePayLineOnce(card: CardData, rawText: string, cost: number): void {
	let charged = false;
	for (const effect of card.effects) {
		if (effect.trigger !== "pay" || effect.rawText !== rawText) continue;
		if (charged) {
			effect.payCost = 0;
		} else {
			effect.payCost = cost;
			charged = true;
		}
	}
}

function newPayEffect(effectType: EffectType, cost: number, rawText: string): CardEffect {
	return {
		type: effectType,
		trigger: "pay",
		value: 0,
		status: "",
		stacks: 0,
		timerValue: 0,
		upkeepCost: 0,
		tributeCost: 0,
		hoardThreshold: 0,
		payCost: cost,
		initialCharges: 0,
		charges: 0,
		maxCharges: 0,
		counterDelta: 0,
		counterThreshold: 0,
		maxUsesPerTurn: 0,
		permanentStatus: false,
		targetScope: "enemy",
		targetKind: "card",
		area: false,
		requiresTarget: true,
		rawText,
	};
}

function firstNumberAfter(text: string, word: string): number {
	let match = new RegExp(`${word}\\s+(\\d+)`).exec(text);
	if (match) return parseInt(match[1]!, 10);
	match = new RegExp(`${word}\\s+[^0-9]*(\\d+)`).exec(text);
	return match ? parseInt(match[1]!, 10) : 0;
}

function firstDamageValue(text: string): number {
	const match = /(?:deal\s+)?(\d+)\s+damage|damage\s+[^0-9]*(\d+)/.exec(text);
	if (!match) return 0;
	return parseInt(match[1] ?? match[2] ?? "0", 10);
}
