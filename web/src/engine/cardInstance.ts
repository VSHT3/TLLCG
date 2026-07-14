// Port of scripts/resources/card_instance.gd — mutable runtime state of a card.

import type { BoardPosition, CardData, Zone } from "./types";
import { isToken } from "./types";
import { applyInstanceDefaults, timerTickAmount } from "./cardRuleDefaults";

let nextInstanceId = 0;

const CANONICAL_STATUS: Record<string, string> = {
	"economic fury": "Economic Fury",
	cancerous: "Economic Fury",
	cursed: "Cursed",
	crit: "Crit",
	vulnerable: "Vulnerable",
	perplexed: "Perplexed",
	invisible: "Invisible",
	drunk: "Drunk",
	defender: "Defender",
	protector: "Protector",
	poison: "Poison",
	burn: "Burn",
	wither: "Wither",
};

function normalizeStatusName(statusName: string): string {
	const key = statusName.trim().toLowerCase().replaceAll("_", " ");
	const canonical = CANONICAL_STATUS[key];
	if (canonical) return canonical;
	// Godot String.capitalize(): capitalize each word
	return statusName
		.replaceAll("_", " ")
		.split(" ")
		.map((w) => (w.length > 0 ? w[0]!.toUpperCase() + w.slice(1) : w))
		.join(" ");
}

export class CardInstance {
	data: CardData;
	instanceId: number;

	currentPower = 0;
	statuses = new Map<string, number>();
	permanentStatuses = new Set<string>();
	damagedThisTurn = false;
	/** Generic scratch state for reusable ability systems. */
	abilityState: Record<string, unknown> = {};
	effectUsesThisTurn = new Map<string, number>();
	timer = 0;
	charges = 0;
	maxCharges = 0;
	counter = 0;
	block = 0;
	zone: Zone = "deck";
	boardPosition: BoardPosition | null = null;
	ownerId = -1;
	controllerId = -1;
	activatedThisTurn = false;

	private constructor(data: CardData) {
		this.data = data;
		this.instanceId = nextInstanceId++;
	}

	static create(cardData: CardData, owner: number): CardInstance {
		const inst = new CardInstance(cardData);
		inst.currentPower = cardData.basePower;
		inst.ownerId = owner;
		inst.controllerId = owner;

		for (const effect of cardData.effects) {
			if (effect.timerValue > 0) inst.timer = effect.timerValue;
			if (effect.initialCharges > 0) inst.charges = Math.max(inst.charges, effect.initialCharges);
			if (effect.maxCharges > 0) inst.maxCharges = Math.max(inst.maxCharges, effect.maxCharges);
			if (effect.counterThreshold > 0 && inst.counter === 0) inst.counter = effect.counterThreshold;
		}
		applyInstanceDefaults(inst);
		return inst;
	}

	// ── State Queries ──────────────────────────────────────────────────────────

	isAlive(): boolean {
		return this.currentPower > 0 && this.zone === "board";
	}

	getStatusStacks(statusName: string): number {
		return this.statuses.get(normalizeStatusName(statusName)) ?? 0;
	}

	hasStatus(statusName: string): boolean {
		return this.getStatusStacks(statusName) > 0;
	}

	isCursed(): boolean {
		return this.hasStatus("Cursed") || isToken(this.data);
	}

	// ── State Mutations ────────────────────────────────────────────────────────

	/** Apply damage; Block absorbs first. Returns actual damage dealt. */
	applyDamage(amount: number): number {
		const blocked = Math.min(amount, this.block);
		const actual = amount - blocked;
		this.currentPower = Math.max(this.currentPower - actual, 0);
		if (actual > 0) this.damagedThisTurn = true;
		return actual;
	}

	/** Damage that bypasses Block (status damage). */
	applyDirectDamage(amount: number): number {
		const actual = Math.max(amount, 0);
		this.currentPower = Math.max(this.currentPower - actual, 0);
		if (actual > 0) this.damagedThisTurn = true;
		return actual;
	}

	applyBoost(amount: number): void {
		this.currentPower += amount;
	}

	/** Heal up to base power. */
	applyHeal(amount: number): void {
		this.currentPower = Math.min(this.currentPower + amount, this.data.basePower);
	}

	missingHealth(): number {
		return Math.max(this.data.basePower - this.currentPower, 0);
	}

	applyStatus(statusName: string, stacks = 1, permanent = false): void {
		const normalized = normalizeStatusName(statusName);
		this.statuses.set(normalized, (this.statuses.get(normalized) ?? 0) + stacks);
		if (permanent) this.permanentStatuses.add(normalized);
	}

	removeStatus(statusName: string): void {
		const normalized = normalizeStatusName(statusName);
		this.statuses.delete(normalized);
		this.permanentStatuses.delete(normalized);
	}

	/** Remove all non-permanent statuses. Token Cursed never cleanses. */
	cleanse(): void {
		for (const s of [...this.statuses.keys()]) {
			if (s === "Cursed" && isToken(this.data)) continue;
			if (this.permanentStatuses.has(s)) continue;
			this.statuses.delete(s);
		}
	}

	/** Reduce all stackable statuses by 1 at end of turn. */
	diminishStatuses(): void {
		for (const [statusName, stacks] of [...this.statuses.entries()]) {
			if (statusName === "Cursed" && isToken(this.data)) continue;
			if (this.permanentStatuses.has(statusName)) continue;
			// Drunk diminishes every 4 turns (handled separately)
			if (statusName === "Drunk") continue;
			if (stacks - 1 <= 0) {
				this.statuses.delete(statusName);
			} else {
				this.statuses.set(statusName, stacks - 1);
			}
		}
	}

	/** Reduce timer. Returns true if timer just reached 0. */
	tickTimer(): boolean {
		if (this.timer > 0) {
			this.timer = Math.max(this.timer - timerTickAmount(this), 0);
			return this.timer === 0;
		}
		return false;
	}

	/** Use charges for Order ability. Returns true if enough charges. */
	useCharge(amount = 1): boolean {
		if (this.charges >= amount) {
			this.charges -= amount;
			return true;
		}
		return false;
	}

	gainCharge(amount = 1): void {
		if (this.maxCharges > 0) {
			this.charges = Math.min(this.charges + amount, this.maxCharges);
		} else {
			this.charges += amount;
		}
	}

	changeCounter(delta: number): void {
		this.counter = Math.max(this.counter + delta, 0);
	}

	moveToZone(newZone: Zone): void {
		this.zone = newZone;
		if (newZone !== "board") this.boardPosition = null;
	}

	placeOnBoard(row: number, col: number): void {
		this.zone = "board";
		this.boardPosition = { row, col };
	}

	resetTurnState(): void {
		this.activatedThisTurn = false;
		this.damagedThisTurn = false;
		this.effectUsesThisTurn.clear();
	}
}
