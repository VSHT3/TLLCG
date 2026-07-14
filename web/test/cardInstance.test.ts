import { describe, expect, it } from "vitest";
import { CardInstance } from "@engine/cardInstance";
import { makeCard, makeEffect } from "./helpers";

describe("CardInstance", () => {
	it("block absorbs damage before power", () => {
		const c = CardInstance.create(makeCard({ basePower: 5 }), 0);
		c.block = 3;
		const actual = c.applyDamage(4);
		expect(actual).toBe(1);
		expect(c.currentPower).toBe(4);
		expect(c.damagedThisTurn).toBe(true);
	});

	it("direct damage bypasses block", () => {
		const c = CardInstance.create(makeCard({ basePower: 5 }), 0);
		c.block = 10;
		expect(c.applyDirectDamage(2)).toBe(2);
		expect(c.currentPower).toBe(3);
	});

	it("heal caps at base power", () => {
		const c = CardInstance.create(makeCard({ basePower: 5 }), 0);
		c.applyDamage(3);
		c.applyHeal(10);
		expect(c.currentPower).toBe(5);
	});

	it("boost exceeds base power", () => {
		const c = CardInstance.create(makeCard({ basePower: 5 }), 0);
		c.applyBoost(4);
		expect(c.currentPower).toBe(9);
	});

	it("normalizes status names (cancerous → Economic Fury)", () => {
		const c = CardInstance.create(makeCard(), 0);
		c.applyStatus("cancerous", 2);
		expect(c.getStatusStacks("Economic Fury")).toBe(2);
		c.applyStatus("economic_fury", 1);
		expect(c.getStatusStacks("Economic Fury")).toBe(3);
	});

	it("diminish skips permanent, token Cursed, and Drunk", () => {
		const token = CardInstance.create(makeCard({ categories: ["Token"] }), 0);
		token.applyStatus("Cursed", 1);
		token.applyStatus("Poison", 2);
		token.applyStatus("Drunk", 3);
		token.applyStatus("Burn", 1, true);
		token.diminishStatuses();
		expect(token.getStatusStacks("Cursed")).toBe(1);
		expect(token.getStatusStacks("Poison")).toBe(1);
		expect(token.getStatusStacks("Drunk")).toBe(3);
		expect(token.getStatusStacks("Burn")).toBe(1);
		token.diminishStatuses();
		expect(token.hasStatus("Poison")).toBe(false);
	});

	it("cleanse keeps permanent statuses and token Cursed", () => {
		const token = CardInstance.create(makeCard({ categories: ["Token"] }), 0);
		token.applyStatus("Cursed", 1);
		token.applyStatus("Poison", 2);
		token.applyStatus("Crit", 1, true);
		token.cleanse();
		expect(token.hasStatus("Poison")).toBe(false);
		expect(token.hasStatus("Cursed")).toBe(true);
		expect(token.hasStatus("Crit")).toBe(true);
	});

	it("token is always cursed", () => {
		const token = CardInstance.create(makeCard({ categories: ["Token"] }), 0);
		expect(token.isCursed()).toBe(true);
	});

	it("initializes timer/charges/counter from effects", () => {
		const c = CardInstance.create(
			makeCard({
				effects: [makeEffect({ timerValue: 4, initialCharges: 2, maxCharges: 5, counterThreshold: 3 })],
			}),
			0,
		);
		expect(c.timer).toBe(4);
		expect(c.charges).toBe(2);
		expect(c.maxCharges).toBe(5);
		expect(c.counter).toBe(3);
	});

	it("gainCharge respects maxCharges", () => {
		const c = CardInstance.create(makeCard({ effects: [makeEffect({ maxCharges: 2 })] }), 0);
		c.gainCharge(5);
		expect(c.charges).toBe(2);
	});
});
