import { describe, expect, it } from "vitest";
import { createDefaultDatabase } from "../src/data";
import { Constants } from "@engine/constants";

const db = createDefaultDatabase();

describe("CardDatabase with real data", () => {
	it("loads all cards", () => {
		expect(db.cards.size).toBeGreaterThanOrEqual(190);
	});

	it("getCard('67') is the Epic neutral artifact with spot_67 draw", () => {
		const card = db.getCard("67")!;
		expect(card.type).toBe("Artifact");
		expect(card.rarity).toBe("Epic");
		expect(card.factions).toContain("Neutral");
		const effect = card.effects.find((e) => e.trigger === "spot_67")!;
		expect(effect.type).toBe("draw");
		expect(effect.value).toBe(4);
	});

	it("every playable faction has a Hero card", () => {
		const factions = db.getPlayableFactions();
		expect(factions.length).toBeGreaterThan(0);
		for (const faction of factions) {
			const hero = db.getHero(faction);
			expect(hero, `hero for ${faction}`).not.toBeNull();
			expect(hero!.type).toBe("Hero");
			expect(hero!.basePower).toBeGreaterThan(0);
		}
	});

	it("neutral cards are all Neutral faction", () => {
		const neutrals = db.getNeutralCards();
		expect(neutrals.length).toBeGreaterThan(0);
		expect(neutrals.every((c) => c.factions.includes("Neutral"))).toBe(true);
	});

	it("effect fields default sanely (no NaN/undefined)", () => {
		for (const card of db.cards.values()) {
			expect(card.basePower, card.id).not.toBeNaN();
			for (const e of card.effects) {
				expect(e.value, card.id).not.toBeNaN();
				expect(typeof e.trigger).toBe("string");
				expect(typeof e.targetScope).toBe("string");
				expect(typeof e.requiresTarget).toBe("boolean");
			}
		}
	});

	it("heroes without explicit power default to HERO_BASE_HP", () => {
		const heroes = db.getCardsByType("Hero");
		expect(heroes.length).toBeGreaterThan(0);
		for (const hero of heroes) {
			expect(hero.basePower).toBeGreaterThanOrEqual(1);
		}
		expect(Constants.HERO_BASE_HP).toBe(30);
	});

	it("resolveAbilityText strips wiki links and bold markers", () => {
		expect(db.resolveAbilityText("[[Keywords#^deploy|Deploy]]: gain **2** sellary [[Statuses]]")).toBe(
			"Deploy: gain 2 sellary Statuses",
		);
	});

	it("rules.json overrode Constants", () => {
		expect(Constants.BASE_SELLARY).toBe(5);
		expect(Constants.ROW_CAPACITIES).toEqual([5, 5, 3]);
	});
});
