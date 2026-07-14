import { describe, expect, it } from "vitest";
import { TurnPhase } from "@engine/constants";
import { makeCard, makeEffect, makeGame, placeUnit } from "./helpers";
import { CardInstance } from "@engine/cardInstance";

function setup(seed = 42) {
	const t = makeGame({ seed });
	t.game.setupGame(["Alpha", "Beta"], 0);
	return t;
}

describe("GameState turn flow", () => {
	it("setup deals 5 neutral + 3 faction per player (faction deck limited by pool)", () => {
		const { game } = setup();
		// FakeDb has only 2 faction cards per faction → hand = 5 + 2
		expect(game.players[0]!.hand.length).toBe(7);
		expect(game.players[1]!.hand.length).toBe(7);
		expect(game.turnNumber).toBe(1);
	});

	it("startTurn grants base sellary plus next-turn modifier, then clears it", async () => {
		const { game } = setup();
		const p0 = game.players[0]!;
		p0.baseSellaryModifierNextTurn = -2;
		await game.startTurn();
		expect(p0.sellary).toBe(3);
		expect(p0.baseSellaryModifierNextTurn).toBe(0);
		expect(game.currentPhase).toBe(TurnPhase.PLAY_CARDS);
	});

	it("play limit is MAX_CARDS_PER_TURN + extraCardPlays", async () => {
		const { game } = setup();
		const p0 = game.players[0]!;
		await game.startTurn();
		expect(game.canPlayCard(p0)).toBe(true);
		p0.cardsPlayedThisTurn = 2;
		expect(game.canPlayCard(p0)).toBe(false);
		p0.extraCardPlays = 1;
		expect(game.canPlayCard(p0)).toBe(true);
	});

	it("unit played onto full board goes to graveyard and still counts", async () => {
		const { game } = setup();
		const p0 = game.players[0]!;
		await game.startTurn();
		for (let row = 0; row < 3; row++) {
			const cap = row === 2 ? 3 : 5;
			for (let col = 0; col < cap; col++) {
				placeUnit(game, 0, makeCard({ id: `f${row}${col}` }), row, col);
			}
		}
		const inHand = p0.hand.find((c) => c.data.type === "Unit")!;
		const ok = await game.playCard(p0, inHand, 0, 0);
		expect(ok).toBe(true);
		expect(inHand.zone).toBe("graveyard");
		expect(p0.cardsPlayedThisTurn).toBe(1);
	});

	it("endTurn: poison cannot kill, burn can", async () => {
		const { game } = setup();
		await game.startTurn();
		const poisoned = placeUnit(game, 0, makeCard({ id: "poisoned", basePower: 2 }), 0, 0);
		poisoned.applyStatus("Poison", 5);
		const burned = placeUnit(game, 0, makeCard({ id: "burned", basePower: 2 }), 0, 1);
		burned.applyStatus("Burn", 3);
		await game.endTurn();
		expect(poisoned.currentPower).toBe(1);
		expect(poisoned.zone).toBe("board");
		expect(burned.zone).toBe("graveyard");
	});

	it("wither removes all stacks after triggering once", async () => {
		const { game } = setup();
		await game.startTurn();
		const withered = placeUnit(game, 0, makeCard({ id: "withered", basePower: 10 }), 0, 0);
		withered.applyStatus("Wither", 3);
		await game.endTurn();
		expect(withered.currentPower).toBe(7);
		expect(withered.hasStatus("Wither")).toBe(false);
	});

	it("suppressEndTurnNextTurn skips end-of-turn triggers once", async () => {
		const { game, log } = setup();
		await game.startTurn();
		placeUnit(
			game,
			0,
			makeCard({ id: "end_triggerer", effects: [makeEffect({ type: "profit", trigger: "turn_end", value: 2, requiresTarget: false })] }),
			0,
			0,
		);
		game.players[0]!.suppressEndTurnNextTurn = true;
		const before = game.players[0]!.sellary;
		await game.endTurn();
		expect(game.players[0]!.sellary).toBe(before);
		expect(log.some((l) => l.startsWith("message_shown") && l.includes("suppressed"))).toBe(true);
	});

	it("destroyed cursed card is banished, normal card goes to graveyard", async () => {
		const { game } = setup();
		const p0 = game.players[0]!;
		const normal = placeUnit(game, 0, makeCard({ id: "normal" }), 0, 0);
		const cursed = placeUnit(game, 0, makeCard({ id: "cursed_one" }), 0, 1);
		cursed.applyStatus("Cursed", 1, true);
		await game.destroyCard(normal, p0);
		await game.destroyCard(cursed, p0);
		expect(normal.zone).toBe("graveyard");
		expect(cursed.zone).toBe("banished");
		expect(p0.banished).toContain(cursed);
	});

	it("game ends when one hero stands", async () => {
		const { game, log } = setup();
		game.players[1]!.hero!.currentPower = 0;
		expect(game.checkGameOver()).toBe(true);
		expect(game.winnerId).toBe(0);
		expect(game.gameOver).toBe(true);
		expect(log.some((l) => l.startsWith("game_ended"))).toBe(true);
	});

	it("tribute asks Pay/Skip via interaction and resolves on Pay", async () => {
		const { game, interaction, log } = setup();
		const p0 = game.players[0]!;
		await game.startTurn();
		const tributeCard = CardInstance.create(
			makeCard({
				id: "tributer",
				effects: [makeEffect({ type: "profit", trigger: "tribute", tributeCost: 3, value: 5, requiresTarget: false })],
			}),
			0,
		);
		p0.hand.push(tributeCard);
		tributeCard.zone = "hand";
		interaction.choicePicks.push(true);
		const before = p0.sellary;
		await game.playCard(p0, tributeCard, 0, 0);
		// paid 3 (in checkCosts), gained 5
		expect(p0.sellary).toBe(before - 3 + 5);
		expect(log.some((l) => l.startsWith("ability_triggered"))).toBe(true);
	});

	it("order activation consumes charge and locks for the turn", async () => {
		const { game } = setup();
		await game.startTurn();
		const orderCard = placeUnit(
			game,
			0,
			makeCard({
				id: "orderer",
				effects: [makeEffect({ type: "profit", trigger: "order", value: 1, charges: 1, initialCharges: 2, maxCharges: 2, requiresTarget: false })],
			}),
			0,
			0,
		);
		expect(await game.activateOrder(orderCard)).toBe(true);
		expect(orderCard.charges).toBe(1);
		expect(orderCard.activatedThisTurn).toBe(true);
		expect(await game.activateOrder(orderCard)).toBe(false);
	});
});
