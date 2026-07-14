import { describe, expect, it } from "vitest";
import { makeCard, makeEffect, makeGame, placeUnit } from "./helpers";

function setup(seed = 42) {
	const t = makeGame({ seed });
	t.game.setupGame(["Alpha", "Beta"], 0);
	return t;
}

describe("EffectResolver simple effects", () => {
	it("damage kills and triggers deathblow on the source", async () => {
		const { game, log, interaction, resolver } = setup();
		const attacker = placeUnit(
			game,
			0,
			makeCard({
				id: "attacker",
				effects: [
					makeEffect({ type: "damage", trigger: "deploy", value: 5, targetScope: "enemy", targetKind: "unit" }),
					makeEffect({ type: "profit", trigger: "deathblow", value: 3, requiresTarget: false }),
				],
			}),
			0,
			0,
		);
		const victim = placeUnit(game, 1, makeCard({ id: "victim", basePower: 2 }), 0, 0);
		interaction.targetPicks.push(() => victim);
		const before = game.players[0]!.sellary;
		await resolver.resolveAbility(attacker, attacker.data.effects[0]!);
		expect(victim.zone).toBe("graveyard");
		expect(log.some((l) => l.startsWith("deathblow_triggered"))).toBe(true);
		expect(game.players[0]!.sellary).toBe(before + 3);
	});

	it("damage ignores artifacts", async () => {
		const { game, resolver } = setup();
		const attacker = placeUnit(game, 0, makeCard({ id: "attacker" }), 0, 0);
		const artifact = placeUnit(game, 1, makeCard({ id: "art", type: "Artifact", basePower: 0 }), 0, 0);
		await resolver.applyDamage(attacker, artifact, 10);
		expect(artifact.zone).toBe("board");
	});

	it("crit doubles damage", async () => {
		const { game, resolver } = setup();
		const attacker = placeUnit(game, 0, makeCard({ id: "attacker" }), 0, 0);
		attacker.applyStatus("Crit", 1);
		const victim = placeUnit(game, 1, makeCard({ id: "victim", basePower: 10 }), 0, 0);
		await resolver.applyDamage(attacker, victim, 2);
		expect(victim.currentPower).toBe(6);
	});

	it("upkeep cost gates the effect", async () => {
		const { game, resolver } = setup();
		const p0 = game.players[0]!;
		p0.sellary = 1;
		const card = placeUnit(
			game,
			0,
			makeCard({ id: "upkeeper", effects: [makeEffect({ type: "profit", trigger: "turn_start", value: 5, upkeepCost: 2, requiresTarget: false })] }),
			0,
			0,
		);
		await resolver.resolveAbility(card, card.data.effects[0]!);
		expect(p0.sellary).toBe(1); // couldn't pay, no profit
		p0.sellary = 2;
		await resolver.resolveAbility(card, card.data.effects[0]!);
		expect(p0.sellary).toBe(5); // paid 2, gained 5
	});

	it("hoard threshold gates without spending", async () => {
		const { game, resolver } = setup();
		const p0 = game.players[0]!;
		const card = placeUnit(
			game,
			0,
			makeCard({ id: "hoarder", effects: [makeEffect({ type: "profit", trigger: "hoard", value: 1, hoardThreshold: 10, requiresTarget: false })] }),
			0,
			0,
		);
		p0.sellary = 9;
		await resolver.resolveAbility(card, card.data.effects[0]!);
		expect(p0.sellary).toBe(9);
		p0.sellary = 10;
		await resolver.resolveAbility(card, card.data.effects[0]!);
		expect(p0.sellary).toBe(11);
	});

	it("Economic Fury doubles profit", async () => {
		const { game, resolver } = setup();
		const p0 = game.players[0]!;
		const card = placeUnit(
			game,
			0,
			makeCard({ id: "earner", effects: [makeEffect({ type: "profit", trigger: "turn_start", value: 3, requiresTarget: false })] }),
			0,
			0,
		);
		card.applyStatus("Economic Fury", 1);
		p0.sellary = 0;
		await resolver.resolveAbility(card, card.data.effects[0]!);
		expect(p0.sellary).toBe(6);
	});

	it("invisible units are excluded from targeted effects", async () => {
		const { game, resolver } = setup();
		const attacker = placeUnit(
			game,
			0,
			makeCard({ id: "attacker", effects: [makeEffect({ type: "damage", trigger: "deploy", value: 1, targetScope: "enemy", targetKind: "unit" })] }),
			0,
			0,
		);
		const hidden = placeUnit(game, 1, makeCard({ id: "hidden" }), 0, 0);
		hidden.applyStatus("Invisible", 1);
		const targets = resolver.getEffectTargets(attacker, attacker.data.effects[0]!);
		expect(targets).toHaveLength(0);
	});

	it("Defender shields same-row cards from targeting", async () => {
		const { game, resolver } = setup();
		const attacker = placeUnit(
			game,
			0,
			makeCard({ id: "attacker", effects: [makeEffect({ type: "damage", trigger: "deploy", value: 1, targetScope: "enemy", targetKind: "unit" })] }),
			0,
			0,
		);
		const defender = placeUnit(game, 1, makeCard({ id: "defender" }), 0, 0);
		defender.applyStatus("Defender", 1);
		const squishy = placeUnit(game, 1, makeCard({ id: "squishy" }), 0, 1);
		const targets = resolver.getEffectTargets(attacker, attacker.data.effects[0]!);
		expect(targets).toContain(defender);
		expect(targets).not.toContain(squishy);
	});

	it("seize steals up to available sellary", async () => {
		const { game, resolver } = setup();
		const p0 = game.players[0]!;
		const p1 = game.players[1]!;
		p0.sellary = 0;
		p1.sellary = 2;
		const card = placeUnit(
			game,
			0,
			makeCard({ id: "seizer", effects: [makeEffect({ type: "seize", trigger: "deploy", value: 5, targetScope: "enemy", requiresTarget: false })] }),
			0,
			0,
		);
		await resolver.resolveAbility(card, card.data.effects[0]!);
		expect(p0.sellary).toBe(2);
		expect(p1.sellary).toBe(0);
	});

	it("masovystit redirects damage from the card behind it", async () => {
		const { game, db, resolver } = setup();
		db.cards.set("masovystit", makeCard({ id: "masovystit", name: "MasovyStit", basePower: 6 }));
		const shield = placeUnit(game, 1, makeCard({ id: "masovystit", basePower: 6 }), 0, 2);
		const behind = placeUnit(game, 1, makeCard({ id: "behind", basePower: 3 }), 1, 2);
		const attacker = placeUnit(game, 0, makeCard({ id: "attacker" }), 0, 0);
		await resolver.applyDamage(attacker, behind, 2);
		// behind takes 2, then healed back 2 by redirect; shield takes 4
		expect(behind.currentPower).toBe(3);
		expect(shield.currentPower).toBe(2);
	});
});

describe("EffectResolver complex cards", () => {
	it("carry_on grants +2 plays, hhmds +1", async () => {
		const { game, resolver } = setup();
		const p0 = game.players[0]!;
		const carry = placeUnit(game, 0, makeCard({ id: "carry_on", effects: [makeEffect({ type: "complex", trigger: "deploy", requiresTarget: false })] }), 0, 0);
		await resolver.resolveAbility(carry, carry.data.effects[0]!);
		expect(p0.extraCardPlays).toBe(2);
		const hh = placeUnit(game, 0, makeCard({ id: "hhmds", effects: [makeEffect({ type: "complex", trigger: "deploy", requiresTarget: false })] }), 0, 1);
		await resolver.resolveAbility(hh, hh.data.effects[0]!);
		expect(p0.extraCardPlays).toBe(3);
	});

	it("catch_up equalizes sellary", async () => {
		const { game, resolver } = setup();
		const p0 = game.players[0]!;
		const p1 = game.players[1]!;
		p0.sellary = 2;
		p1.sellary = 9;
		const card = placeUnit(game, 0, makeCard({ id: "catch_up", effects: [makeEffect({ type: "complex", trigger: "deploy", requiresTarget: false })] }), 0, 0);
		await resolver.resolveAbility(card, card.data.effects[0]!);
		expect(p0.sellary).toBe(9);
	});

	it("accountant_pro_max tiers by gold", async () => {
		const { game, resolver } = setup();
		const p0 = game.players[0]!;
		p0.sellary = 8;
		const card = placeUnit(game, 0, makeCard({ id: "accountant_pro_max", basePower: 2, effects: [makeEffect({ type: "complex", trigger: "turn_start", requiresTarget: false })] }), 0, 0);
		await resolver.resolveAbility(card, card.data.effects[0]!);
		expect(p0.sellary).toBe(12);
		expect(card.currentPower).toBe(3);
	});

	it("individual_sailor: alone hits enemy hero for 3 and boosts self", async () => {
		const { game, resolver } = setup();
		const card = placeUnit(game, 0, makeCard({ id: "individual_sailor", basePower: 2, effects: [makeEffect({ type: "complex", trigger: "turn_end", requiresTarget: false })] }), 0, 0);
		const enemyHero = game.players[1]!.hero!;
		const hp = enemyHero.currentPower;
		await resolver.resolveAbility(card, card.data.effects[0]!);
		expect(enemyHero.currentPower).toBe(hp - 3);
		expect(card.currentPower).toBe(3);
	});

	it("tax_er takes 2 or damages hero for unpaid", async () => {
		const { game, resolver } = setup();
		const p1 = game.players[1]!;
		p1.sellary = 1;
		const hp = p1.hero!.currentPower;
		const card = placeUnit(game, 0, makeCard({ id: "tax_er", effects: [makeEffect({ type: "complex", trigger: "turn_start", requiresTarget: false })] }), 0, 0);
		await resolver.resolveAbility(card, card.data.effects[0]!);
		expect(p1.sellary).toBe(0);
		expect(p1.hero!.currentPower).toBe(hp - 1);
	});

	it("claws_the_production reduces opponent's next income", async () => {
		const { game, resolver } = setup();
		const card = placeUnit(game, 0, makeCard({ id: "claws_the_production", type: "Spell", effects: [makeEffect({ type: "complex", trigger: "passive", requiresTarget: false })] }), 0, 0);
		await resolver.resolveAbility(card, card.data.effects[0]!);
		expect(game.players[1]!.baseSellaryModifierNextTurn).toBe(-2);
	});

	it("velky_jazykovy_model repeats last ability and banishes at 0 counter", async () => {
		const { game, resolver } = setup();
		const p0 = game.players[0]!;
		const earner = placeUnit(game, 0, makeCard({ id: "earner", effects: [makeEffect({ type: "profit", trigger: "order", value: 2, requiresTarget: false })] }), 0, 0);
		const vjm = placeUnit(
			game,
			0,
			makeCard({ id: "velky_jazykovy_model", effects: [makeEffect({ type: "complex", trigger: "pay", payCost: 0, requiresTarget: false, counterThreshold: 1 })] }),
			0,
			1,
		);
		p0.sellary = 0;
		await resolver.resolveAbility(earner, earner.data.effects[0]!);
		expect(p0.sellary).toBe(2);
		await resolver.resolveAbility(vjm, vjm.data.effects[0]!);
		expect(p0.sellary).toBe(4); // repeated profit
		expect(vjm.zone).toBe("banished"); // counter hit 0
	});
});
