// Port of scripts/game/player_state.gd — all runtime state for one player.

import { Constants } from "./constants";
import type { CardDatabaseApi } from "./types";
import { CardInstance } from "./cardInstance";
import type { EventBus } from "./events";
import type { Rng } from "./rng";
import { shuffle } from "./rng";

export class PlayerState {
	playerId = -1;
	factionName = "";
	hero: CardInstance | null = null;

	factionDeck: CardInstance[] = [];
	hand: CardInstance[] = [];
	/** 3 rows; arrays are UNORDERED — boardPosition.col is the authoritative slot. */
	board: CardInstance[][] = [[], [], []];
	graveyard: CardInstance[] = [];
	banished: CardInstance[] = [];

	sellary = 0;
	baseSellary = 5;
	cardsPlayedThisTurn = 0;
	extraCardPlays = 0;
	neutralDrawsThisTurn = 0;
	factionDrawsThisTurn = 0;
	freePlaysTurn = false;
	baseSellaryModifierNextTurn = 0;
	suppressEndTurnNextTurn = false;

	private events: EventBus;
	private rng: Rng;

	constructor(events: EventBus, rng: Rng) {
		this.events = events;
		this.rng = rng;
	}

	static create(id: number, faction: string, db: CardDatabaseApi, events: EventBus, rng: Rng): PlayerState {
		const ps = new PlayerState(events, rng);
		ps.playerId = id;
		ps.factionName = faction;
		ps.baseSellary = Constants.BASE_SELLARY;

		const heroData = db.getHero(faction);
		if (heroData) {
			ps.hero = CardInstance.create(heroData, id);
			ps.hero.zone = "board";
		}

		for (const cardData of db.getCardsByFaction(faction)) {
			if (cardData.type === "Hero") continue;
			if (!cardData.hasAbility) continue;
			ps.factionDeck.push(CardInstance.create(cardData, id));
		}
		shuffle(ps.factionDeck, rng);
		return ps;
	}

	// ── Board Queries ──────────────────────────────────────────────────────────

	/** All board cards, flat, activation order (melee→artillery, insertion order per row). */
	getAllBoardUnits(): CardInstance[] {
		return this.board.flat();
	}

	getBoardUnitCount(): number {
		return this.board.reduce((n, row) => n + row.length, 0);
	}

	getRowCount(rowIdx: number): number {
		return this.board[rowIdx]?.length ?? 0;
	}

	isRowFull(rowIdx: number): boolean {
		return this.findFreeCol(rowIdx) < 0;
	}

	isBoardFull(): boolean {
		for (let i = 0; i < this.board.length; i++) {
			if (!this.isRowFull(i)) return false;
		}
		return true;
	}

	/** {row, col} from the card's stored slot, or null if not on this board. */
	findCardPosition(card: CardInstance): { row: number; col: number } | null {
		for (let rowIdx = 0; rowIdx < this.board.length; rowIdx++) {
			if (this.board[rowIdx]!.includes(card)) {
				return { row: rowIdx, col: card.boardPosition?.col ?? -1 };
			}
		}
		return null;
	}

	// ── Adjacency Queries (slot columns, not array indices) ────────────────────

	getCardsInRow(card: CardInstance): CardInstance[] {
		const pos = this.findCardPosition(card);
		if (!pos) return [];
		return this.board[pos.row]!.filter((c) => c !== card);
	}

	isAloneInRow(card: CardInstance): boolean {
		const pos = this.findCardPosition(card);
		if (!pos) return false;
		return this.board[pos.row]!.length === 1;
	}

	/** Nearest card at higher col in the same row, or null. */
	getRightNeighbor(card: CardInstance): CardInstance | null {
		return this.nearestInRow(card, +1);
	}

	/** Nearest card at lower col in the same row, or null. */
	getLeftNeighbor(card: CardInstance): CardInstance | null {
		return this.nearestInRow(card, -1);
	}

	private nearestInRow(card: CardInstance, direction: 1 | -1): CardInstance | null {
		const pos = this.findCardPosition(card);
		if (!pos) return null;
		let best: CardInstance | null = null;
		let bestDist = Infinity;
		for (const c of this.board[pos.row]!) {
			if (c === card) continue;
			const dist = ((c.boardPosition?.col ?? -1) - pos.col) * direction;
			if (dist > 0 && dist < bestDist) {
				bestDist = dist;
				best = c;
			}
		}
		return best;
	}

	/** Left and right immediate neighbors (up to 2). */
	getRowNeighbors(card: CardInstance): CardInstance[] {
		const result: CardInstance[] = [];
		const left = this.getLeftNeighbor(card);
		const right = this.getRightNeighbor(card);
		if (left) result.push(left);
		if (right) result.push(right);
		return result;
	}

	getAdjacentEmptySlots(card: CardInstance): { row: number; col: number }[] {
		const pos = this.findCardPosition(card);
		if (!pos) return [];
		const result: { row: number; col: number }[] = [];
		for (const [dr, dc] of ADJACENT_DIRECTIONS) {
			const row = pos.row + dr;
			const col = pos.col + dc;
			if (row < 0 || row >= this.board.length) continue;
			if (col < 0 || col >= (Constants.ROW_CAPACITIES[row] ?? 0)) continue;
			if (!this.isSlotOccupied(row, col)) result.push({ row, col });
		}
		return result;
	}

	// ── Board Mutations ────────────────────────────────────────────────────────

	/** First unoccupied col in row, or -1 if full. */
	findFreeCol(rowIdx: number): number {
		if (rowIdx < 0 || rowIdx >= this.board.length) return -1;
		for (let col = 0; col < (Constants.ROW_CAPACITIES[rowIdx] ?? 0); col++) {
			if (!this.isSlotOccupied(rowIdx, col)) return col;
		}
		return -1;
	}

	isSlotOccupied(rowIdx: number, colIdx: number): boolean {
		if (rowIdx < 0 || rowIdx >= this.board.length) return true;
		return this.board[rowIdx]!.some((card) => card.boardPosition?.col === colIdx);
	}

	placeOnBoard(card: CardInstance, rowIdx: number, colIdx: number): boolean {
		if (rowIdx < 0 || rowIdx >= this.board.length) return false;
		if (colIdx < 0 || colIdx >= (Constants.ROW_CAPACITIES[rowIdx] ?? 0)) return false;
		if (this.isSlotOccupied(rowIdx, colIdx)) return false;
		this.board[rowIdx]!.push(card);
		card.placeOnBoard(rowIdx, colIdx);
		card.controllerId = this.playerId;
		return true;
	}

	removeFromBoard(card: CardInstance): boolean {
		for (const row of this.board) {
			const idx = row.indexOf(card);
			if (idx !== -1) {
				row.splice(idx, 1);
				return true;
			}
		}
		return false;
	}

	placeInFirstFreeSlot(card: CardInstance): boolean {
		for (let rowIdx = 0; rowIdx < this.board.length; rowIdx++) {
			const colIdx = this.findFreeCol(rowIdx);
			if (colIdx >= 0) return this.placeOnBoard(card, rowIdx, colIdx);
		}
		return false;
	}

	placeAdjacentTo(card: CardInstance, anchor: CardInstance): boolean {
		for (const slot of this.getAdjacentEmptySlots(anchor)) {
			if (this.placeOnBoard(card, slot.row, slot.col)) return true;
		}
		return this.placeInFirstFreeSlot(card);
	}

	swapBoardPositions(a: CardInstance, b: CardInstance): boolean {
		const posA = this.findCardPosition(a);
		const posB = this.findCardPosition(b);
		if (!posA || !posB) return false;
		a.boardPosition = { row: posB.row, col: posB.col };
		b.boardPosition = { row: posA.row, col: posA.col };
		const rowA = this.board[posA.row]!;
		const rowB = this.board[posB.row]!;
		rowA.splice(rowA.indexOf(a), 1);
		rowB.splice(rowB.indexOf(b), 1);
		rowA.push(b);
		rowB.push(a);
		return true;
	}

	// ── Hand Operations ────────────────────────────────────────────────────────

	addToHand(card: CardInstance): void {
		card.moveToZone("hand");
		this.hand.push(card);
	}

	removeFromHand(card: CardInstance): boolean {
		const idx = this.hand.indexOf(card);
		if (idx !== -1) {
			this.hand.splice(idx, 1);
			return true;
		}
		return false;
	}

	/** Discard random cards until hand is at max size. Returns discarded cards. */
	enforceHandLimit(): CardInstance[] {
		const discarded: CardInstance[] = [];
		while (this.hand.length > Constants.MAX_HAND_SIZE) {
			const idx = this.rng.randi(this.hand.length);
			const card = this.hand[idx]!;
			this.hand.splice(idx, 1);
			card.moveToZone("graveyard");
			this.graveyard.push(card);
			discarded.push(card);
		}
		return discarded;
	}

	// ── Deck Operations ────────────────────────────────────────────────────────

	drawFactionCard(): CardInstance | null {
		const card = this.factionDeck.shift();
		if (!card) return null;
		this.addToHand(card);
		return card;
	}

	takeFromFactionDeck(cardId: string): CardInstance | null {
		const idx = this.factionDeck.findIndex((c) => c.data.id === cardId);
		if (idx === -1) return null;
		return this.factionDeck.splice(idx, 1)[0]!;
	}

	takeFromGraveyard(cardId = ""): CardInstance | null {
		const idx = this.graveyard.findIndex((c) => cardId === "" || c.data.id === cardId);
		if (idx === -1) return null;
		return this.graveyard.splice(idx, 1)[0]!;
	}

	getGraveyardCardsByRarity(rarities: string[]): CardInstance[] {
		return this.graveyard.filter((c) => rarities.includes(c.data.rarity));
	}

	// ── Economy ────────────────────────────────────────────────────────────────

	gainSellary(amount: number): void {
		this.sellary += amount;
		this.events.emit("sellary_gained", { playerId: this.playerId, amount });
	}

	/** Spend sellary. Returns false if insufficient funds. */
	spendSellary(amount: number): boolean {
		if (this.freePlaysTurn) return true;
		if (this.sellary < amount) return false;
		this.sellary -= amount;
		this.events.emit("sellary_spent", { playerId: this.playerId, amount });
		return true;
	}

	getNeutralDrawCost(): number {
		return Constants.NEUTRAL_DRAW_BASE_COST + this.neutralDrawsThisTurn * Constants.NEUTRAL_DRAW_EXTRA_COST;
	}

	getFactionDrawCost(): number {
		return Constants.FACTION_DRAW_BASE_COST + this.factionDrawsThisTurn * Constants.FACTION_DRAW_EXTRA_COST;
	}

	// ── Turn Reset ─────────────────────────────────────────────────────────────

	resetTurnState(): void {
		this.cardsPlayedThisTurn = 0;
		this.extraCardPlays = 0;
		this.neutralDrawsThisTurn = 0;
		this.factionDrawsThisTurn = 0;
		this.freePlaysTurn = false;
		for (const row of this.board) {
			for (const card of row) {
				card.resetTurnState();
			}
		}
	}
}

const ADJACENT_DIRECTIONS: readonly [number, number][] = [
	[-1, -1], [-1, 0], [-1, 1],
	[0, -1], [0, 1],
	[1, -1], [1, 0], [1, 1],
];
