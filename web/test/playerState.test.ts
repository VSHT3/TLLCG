import { describe, expect, it } from "vitest";
import { CardInstance } from "@engine/cardInstance";
import { PlayerState } from "@engine/playerState";
import { EventBus } from "@engine/events";
import { createRng } from "@engine/rng";
import { FakeDb, makeCard } from "./helpers";

function makePlayer(): PlayerState {
	return PlayerState.create(0, "Alpha", new FakeDb(), new EventBus(), createRng(7));
}

function unit(id: string): CardInstance {
	return CardInstance.create(makeCard({ id, name: id }), 0);
}

describe("PlayerState board slots", () => {
	it("col stays authoritative after removal — no reindexing", () => {
		const p = makePlayer();
		const a = unit("a");
		const b = unit("b");
		const c = unit("c");
		p.placeOnBoard(a, 0, 0);
		p.placeOnBoard(b, 0, 2);
		p.placeOnBoard(c, 0, 4);
		p.removeFromBoard(a);
		expect(b.boardPosition).toEqual({ row: 0, col: 2 });
		expect(p.isSlotOccupied(0, 0)).toBe(false);
		expect(p.findFreeCol(0)).toBe(0);
	});

	it("adjacency: nearest by col, not array order", () => {
		const p = makePlayer();
		const left = unit("left");
		const mid = unit("mid");
		const right = unit("right");
		// Insert out of order
		p.placeOnBoard(right, 0, 4);
		p.placeOnBoard(left, 0, 0);
		p.placeOnBoard(mid, 0, 2);
		expect(p.getLeftNeighbor(mid)).toBe(left);
		expect(p.getRightNeighbor(mid)).toBe(right);
		expect(p.getRowNeighbors(mid)).toEqual([left, right]);
		expect(p.isAloneInRow(mid)).toBe(false);
	});

	it("row capacities are 5/5/3", () => {
		const p = makePlayer();
		for (let col = 0; col < 3; col++) {
			expect(p.placeOnBoard(unit(`art${col}`), 2, col)).toBe(true);
		}
		expect(p.placeOnBoard(unit("overflow"), 2, 3)).toBe(false);
		expect(p.isRowFull(2)).toBe(true);
	});

	it("swapBoardPositions swaps slots across rows", () => {
		const p = makePlayer();
		const a = unit("a");
		const b = unit("b");
		p.placeOnBoard(a, 0, 1);
		p.placeOnBoard(b, 1, 3);
		expect(p.swapBoardPositions(a, b)).toBe(true);
		expect(a.boardPosition).toEqual({ row: 1, col: 3 });
		expect(b.boardPosition).toEqual({ row: 0, col: 1 });
		expect(p.findCardPosition(a)).toEqual({ row: 1, col: 3 });
	});

	it("enforceHandLimit discards randomly down to 10", () => {
		const p = makePlayer();
		for (let i = 0; i < 13; i++) {
			p.addToHand(unit(`h${i}`));
		}
		const discarded = p.enforceHandLimit();
		expect(discarded).toHaveLength(3);
		expect(p.hand).toHaveLength(10);
		expect(p.graveyard).toHaveLength(3);
		for (const card of discarded) {
			expect(card.zone).toBe("graveyard");
		}
	});

	it("spendSellary is free during freePlaysTurn", () => {
		const p = makePlayer();
		p.sellary = 1;
		p.freePlaysTurn = true;
		expect(p.spendSellary(99)).toBe(true);
		expect(p.sellary).toBe(1);
	});

	it("draw costs escalate per draw", () => {
		const p = makePlayer();
		expect(p.getNeutralDrawCost()).toBe(3);
		p.neutralDrawsThisTurn = 2;
		expect(p.getNeutralDrawCost()).toBe(5);
		expect(p.getFactionDrawCost()).toBe(4);
		p.factionDrawsThisTurn = 1;
		expect(p.getFactionDrawCost()).toBe(5);
	});

	it("create builds hero and ability-only faction deck", () => {
		const p = makePlayer();
		expect(p.hero?.data.id).toBe("hero_a");
		expect(p.hero?.zone).toBe("board");
		expect(p.factionDeck.every((c) => c.data.hasAbility && c.data.type !== "Hero")).toBe(true);
		expect(p.factionDeck).toHaveLength(2);
	});
});
