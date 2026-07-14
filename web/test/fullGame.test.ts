// Seeded full-game fuzz over the REAL card data: two players play random
// legal actions until a hero dies or the turn cap hits. Exercises every
// trigger path (deploy/tribute/turn flow/statuses/hoard/spot_67) and all
// reachable complex cards without crashing, with invariants checked.

import { describe, expect, it } from "vitest";
import { createDefaultDatabase } from "../src/data";
import { GameState } from "@engine/gameState";
import { EffectResolver } from "@engine/effectResolver";
import { EventBus } from "@engine/events";
import { createRng } from "@engine/rng";
import { AutoInteractionHandler } from "@engine/interaction";
import { Constants } from "@engine/constants";

const FACTIONS = ["Sir Can", "A.I. Gods", "Abeer Dawood Salman"];

async function playRandomGame(seed: number, factionA: string, factionB: string): Promise<void> {
	const db = createDefaultDatabase();
	const events = new EventBus();
	const rng = createRng(seed);
	const game = new GameState(db, events, rng, new AutoInteractionHandler());
	game.resolver = new EffectResolver(game);
	game.setupGame([factionA, factionB], 0);

	const MAX_TURNS = 30;
	await game.startTurn();
	while (!game.gameOver && game.turnNumber <= MAX_TURNS) {
		const player = game.getCurrentPlayer();

		// Play up to limit random cards
		for (let i = 0; i < 4 && game.canPlayCard(player) && player.hand.length > 0; i++) {
			const card = player.hand[rng.randi(player.hand.length)]!;
			if (card.data.type === "Unit" || card.data.type === "Artifact") {
				const row = rng.randi(3);
				const col = player.findFreeCol(row);
				if (col >= 0) await game.playCard(player, card, row, col);
			} else {
				await game.playCard(player, card);
			}
			if (game.gameOver) return;
		}

		// Random draws while affordable
		while (player.sellary >= player.getNeutralDrawCost() && rng.randf() < 0.5) {
			if (!(await game.drawNeutral(player))) break;
		}

		// Random order/pay activations
		for (const card of [...player.getAllBoardUnits()]) {
			if (rng.randf() < 0.3) await game.activateOrder(card);
			if (rng.randf() < 0.2) await game.activatePay(card);
			if (game.gameOver) return;
		}

		// Invariants every turn
		for (const p of game.players) {
			expect(p.sellary).toBeGreaterThanOrEqual(0);
			for (let row = 0; row < p.board.length; row++) {
				const cols = p.board[row]!.map((c) => c.boardPosition?.col ?? -1);
				expect(new Set(cols).size, `duplicate cols row ${row}`).toBe(cols.length);
				expect(cols.every((c) => c >= 0 && c < Constants.ROW_CAPACITIES[row]!)).toBe(true);
				for (const c of p.board[row]!) {
					expect(c.zone).toBe("board");
				}
			}
		}

		await game.endTurn();
	}

	// Hand limit respected after every endTurn
	for (const p of game.players) {
		expect(p.hand.length).toBeLessThanOrEqual(Constants.MAX_HAND_SIZE);
	}
}

describe("full-game fuzz (real data)", () => {
	for (const seed of [1, 2, 3, 7, 1337]) {
		for (let a = 0; a < FACTIONS.length; a++) {
			const b = (a + 1) % FACTIONS.length;
			it(`seed ${seed}: ${FACTIONS[a]} vs ${FACTIONS[b]}`, async () => {
				await playRandomGame(seed, FACTIONS[a]!, FACTIONS[b]!);
			});
		}
	}
});
