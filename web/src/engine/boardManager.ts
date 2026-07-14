// Port of scripts/game/board_manager.gd — board layout + adjacency helpers.
// Rows: 0 melee (5), 1 ranged (5), 2 artillery (3). Boards are mirrored per player.

import { Constants } from "./constants";
import type { CardInstance } from "./cardInstance";
import type { PlayerState } from "./playerState";

const DIRECTIONS: readonly [number, number][] = [
	[-1, -1], [-1, 0], [-1, 1],
	[0, -1], [0, 1],
	[1, -1], [1, 0], [1, 1],
];

/** Cards adjacent to a position on the same player's board (8 directions). */
export function getAdjacentCards(player: PlayerState, row: number, col: number): CardInstance[] {
	const adjacent: CardInstance[] = [];
	for (const [dr, dc] of DIRECTIONS) {
		const r = row + dr;
		const c = col + dc;
		if (r < 0 || r >= player.board.length) continue;
		if (c < 0 || c >= (Constants.ROW_CAPACITIES[r] ?? 0)) continue;
		const card = getCardAt(player, r, c);
		if (card) adjacent.push(card);
	}
	return adjacent;
}

export function getRowCards(player: PlayerState, row: number): CardInstance[] {
	if (row < 0 || row >= player.board.length) return [];
	return [...player.board[row]!];
}

/** Card at a specific slot, or null. */
export function getCardAt(player: PlayerState, row: number, col: number): CardInstance | null {
	if (row < 0 || row >= player.board.length) return null;
	if (col < 0 || col >= (Constants.ROW_CAPACITIES[row] ?? 0)) return null;
	return player.board[row]!.find((card) => card.boardPosition?.col === col) ?? null;
}

/** Whether a Defender (same row) or Protector (hero) must be attacked first. */
export function hasTauntInFront(player: PlayerState, target: CardInstance): boolean {
	const pos = player.findCardPosition(target);
	if (pos) {
		for (const card of getRowCards(player, pos.row)) {
			if (card !== target && card.hasStatus("Defender")) return true;
		}
	}
	if (target === player.hero) {
		for (const card of player.getAllBoardUnits()) {
			if (card.hasStatus("Protector")) return true;
		}
	}
	return false;
}

/** All board cards in activation order: melee→artillery, left→right. */
export function getActivationOrder(player: PlayerState): CardInstance[] {
	return player.board.flat();
}

/** First non-full row index, or -1 if board full. */
export function findAvailableRow(player: PlayerState): number {
	for (let i = 0; i < player.board.length; i++) {
		if (!player.isRowFull(i)) return i;
	}
	return -1;
}

export function getValidPlacementRows(player: PlayerState): number[] {
	const result: number[] = [];
	for (let i = 0; i < player.board.length; i++) {
		if (!player.isRowFull(i)) result.push(i);
	}
	return result;
}
