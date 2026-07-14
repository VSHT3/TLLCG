// Port of scripts/game/game_state.gd — central state manager and turn flow.
// Deviation from GDScript (deliberate): ability resolution is awaited via the
// injected AbilityResolver instead of fire-and-forget ability_triggered signals;
// the signal is still emitted as a notification before resolution.

import { Constants, TurnPhase } from "./constants";
import type { CardData, CardDatabaseApi, CardEffect, EffectTrigger } from "./types";
import { CardInstance } from "./cardInstance";
import { PlayerState } from "./playerState";
import type { EventBus } from "./events";
import type { Rng } from "./rng";
import { shuffle } from "./rng";
import type { InteractionHandler } from "./interaction";
import type { AbilityResolver } from "./abilityResolver";
import { NULL_RESOLVER } from "./abilityResolver";
import { effectivePayCost } from "./effectCosts";
import { getAdjacentCards } from "./boardManager";

export class GameState {
	players: PlayerState[] = [];
	neutralDeck: CardInstance[] = [];
	currentPlayerIdx = 0;
	turnNumber = 0;
	currentPhase: TurnPhase = TurnPhase.SELLARY;
	gameOver = false;
	winnerId = -1;
	lastSpellPlayed: CardData | null = null;

	resolver: AbilityResolver = NULL_RESOLVER;

	readonly db: CardDatabaseApi;
	readonly events: EventBus;
	readonly rng: Rng;
	readonly interaction: InteractionHandler;

	constructor(db: CardDatabaseApi, events: EventBus, rng: Rng, interaction: InteractionHandler) {
		this.db = db;
		this.events = events;
		this.rng = rng;
		this.interaction = interaction;
	}

	// ── Setup ──────────────────────────────────────────────────────────────────

	setupGame(factionChoices: string[], firstPlayerId = 0): void {
		this.buildNeutralDeck();

		for (let i = 0; i < factionChoices.length; i++) {
			this.players.push(PlayerState.create(i, factionChoices[i]!, this.db, this.events, this.rng));
		}

		// Rulebook: initial draw in reverse order of first pick
		for (let i = 0; i < this.players.length; i++) {
			const idx = (firstPlayerId + 1 + i) % this.players.length;
			this.drawNeutralCardsFree(idx, 5);
			this.drawFactionCardsFree(idx, 3);
		}

		this.turnNumber = 1;
		this.currentPlayerIdx = firstPlayerId;
		this.events.emit("game_started", { playerIds: this.players.map((p) => p.playerId) });
	}

	private buildNeutralDeck(): void {
		for (const cardData of this.db.getNeutralCards()) {
			if (cardData.type === "Hero") continue;
			if (!cardData.hasAbility) continue;
			this.neutralDeck.push(CardInstance.create(cardData, -1));
		}
		shuffle(this.neutralDeck, this.rng);
	}

	// ── Turn Flow ──────────────────────────────────────────────────────────────

	getCurrentPlayer(): PlayerState {
		return this.players[this.currentPlayerIdx]!;
	}

	async startTurn(): Promise<void> {
		const player = this.getCurrentPlayer();
		player.resetTurnState();
		this.events.emit("turn_started", { playerId: player.playerId, turnNumber: this.turnNumber });

		this.setPhase(TurnPhase.SELLARY);
		const sellaryGain = Math.max(player.baseSellary + player.baseSellaryModifierNextTurn, 0);
		player.baseSellaryModifierNextTurn = 0;
		player.gainSellary(sellaryGain);

		this.setPhase(TurnPhase.START_OF_TURN);
		await this.triggerStartOfTurn(player);

		// Interactive phase — player acts freely until endTurn()
		this.setPhase(TurnPhase.PLAY_CARDS);
	}

	/** Player pressed End Turn: hand limit, end-of-turn triggers, statuses, advance. */
	async endTurn(): Promise<void> {
		const player = this.getCurrentPlayer();

		for (const card of player.enforceHandLimit()) {
			this.events.emit("card_discarded", { card, playerId: player.playerId });
		}

		this.setPhase(TurnPhase.END_OF_TURN);
		if (player.suppressEndTurnNextTurn) {
			player.suppressEndTurnNextTurn = false;
			this.events.emit("message_shown", { text: "End-of-turn abilities suppressed." });
		} else {
			await this.triggerEndOfTurn(player);
		}

		this.setPhase(TurnPhase.STATUS_TRIGGER);
		await this.triggerStatuses(player);

		this.setPhase(TurnPhase.STATUS_DIMINISH);
		for (const card of player.getAllBoardUnits()) {
			card.diminishStatuses();
		}

		this.events.emit("turn_ended", { playerId: player.playerId });

		if (this.checkGameOver()) return;

		await this.advanceTurn();
	}

	private setPhase(phase: TurnPhase): void {
		this.currentPhase = phase;
		this.events.emit("phase_changed", { phase, playerId: this.getCurrentPlayer().playerId });
	}

	private async advanceTurn(): Promise<void> {
		this.currentPlayerIdx = (this.currentPlayerIdx + 1) % this.players.length;
		if (this.currentPlayerIdx === 0) this.turnNumber++;
		await this.startTurn();
	}

	// ── Card Playing ───────────────────────────────────────────────────────────

	canPlayCard(player: PlayerState): boolean {
		if (this.currentPhase !== TurnPhase.PLAY_CARDS) return false;
		return player.cardsPlayedThisTurn < Constants.MAX_CARDS_PER_TURN + player.extraCardPlays;
	}

	/** Play a card from hand. row/col required for Units and Artifacts. */
	async playCard(player: PlayerState, card: CardInstance, rowIdx = -1, colIdx = -1): Promise<boolean> {
		if (!this.canPlayCard(player)) return false;
		if (!player.hand.includes(card)) return false;
		if (card.data.type === "Unit" || card.data.type === "Artifact") {
			if (rowIdx < 0 || colIdx < 0) return false;
			if (rowIdx >= Constants.ROW_CAPACITIES.length) return false;
			if (!player.isBoardFull() && player.isSlotOccupied(rowIdx, colIdx)) return false;
		}

		if (!player.removeFromHand(card)) return false;
		player.cardsPlayedThisTurn++;

		switch (card.data.type) {
			case "Unit": {
				if (player.isBoardFull()) {
					card.moveToZone("graveyard");
					player.graveyard.push(card);
					this.events.emit("card_discarded", { card, playerId: player.playerId });
					return true;
				}
				if (!player.placeOnBoard(card, rowIdx, colIdx)) return false;
				this.events.emit("card_placed_on_board", { card, row: rowIdx, col: colIdx });
				await this.triggerDeploy(card);
				await this.triggerTribute(card);
				await this.triggerCardEffects(card, "passive");
				break;
			}
			case "Spell": {
				// Spells resolve immediately then go to graveyard
				await this.resolveSpell(card);
				this.lastSpellPlayed = card.data;
				if (card.zone !== "deck" && card.zone !== "banished") {
					card.moveToZone("graveyard");
					player.graveyard.push(card);
				}
				break;
			}
			case "Artifact": {
				if (rowIdx < 0 || colIdx < 0) return false;
				if (!player.placeOnBoard(card, rowIdx, colIdx)) return false;
				this.events.emit("card_placed_on_board", { card, row: rowIdx, col: colIdx });
				await this.triggerDeploy(card);
				await this.triggerTribute(card);
				await this.triggerCardEffects(card, "passive");
				break;
			}
		}

		this.events.emit("card_played", { card, playerId: player.playerId });
		await this.triggerHoard(player);
		await this.triggerSpot67All();
		return true;
	}

	// ── Drawing ────────────────────────────────────────────────────────────────

	async drawNeutral(player: PlayerState): Promise<CardInstance | null> {
		if (!player.spendSellary(player.getNeutralDrawCost())) return null;
		const card = this.neutralDeck.shift();
		if (!card) return null;
		card.ownerId = player.playerId;
		card.controllerId = player.playerId;
		player.addToHand(card);
		player.neutralDrawsThisTurn++;
		this.events.emit("card_drawn", { card, playerId: player.playerId, source: "neutral" });
		await this.triggerSpot67All();
		return card;
	}

	async drawFaction(player: PlayerState): Promise<CardInstance | null> {
		if (!player.spendSellary(player.getFactionDrawCost())) return null;
		const card = player.drawFactionCard();
		if (card) {
			player.factionDrawsThisTurn++;
			this.events.emit("card_drawn", { card, playerId: player.playerId, source: "faction" });
			await this.triggerSpot67All();
		}
		return card;
	}

	/** Free draw for initial setup. */
	private drawNeutralCardsFree(playerIdx: number, count: number): void {
		const player = this.players[playerIdx]!;
		for (let i = 0; i < count; i++) {
			const card = this.neutralDeck.shift();
			if (!card) break;
			card.ownerId = player.playerId;
			card.controllerId = player.playerId;
			player.addToHand(card);
		}
	}

	private drawFactionCardsFree(playerIdx: number, count: number): void {
		const player = this.players[playerIdx]!;
		for (let i = 0; i < count; i++) {
			player.drawFactionCard();
		}
	}

	// ── Ability Triggers ───────────────────────────────────────────────────────

	private async triggerDeploy(card: CardInstance): Promise<void> {
		if (await this.triggerCardEffects(card, "deploy")) {
			this.events.emit("deploy_triggered", { card });
		}
	}

	private async triggerTribute(card: CardInstance): Promise<void> {
		const player = this.getCardController(card);
		if (!player) return;
		for (const effect of card.data.effects) {
			if (effect.trigger !== "tribute") continue;
			if (effect.tributeCost > 0) {
				if (player.sellary < effect.tributeCost) continue;
				const accepted = await this.interaction.requestChoice(
					`Tribute ${effect.tributeCost} for ${card.data.name}?`,
					[
						{ label: "Pay", value: true },
						{ label: "Skip", value: false },
					],
				);
				if (accepted) await this.emitTriggeredEffect(card, effect);
			} else {
				await this.emitTriggeredEffect(card, effect);
			}
		}
	}

	async resolveSpell(card: CardInstance): Promise<void> {
		for (const effect of card.data.effects) {
			await this.emitTriggeredEffect(card, effect);
		}
	}

	private async triggerStartOfTurn(player: PlayerState): Promise<void> {
		await this.triggerPlayerEffects(player, ["turn_start", "upkeep"]);
		await this.triggerHoard(player);
		await this.triggerSpot67All();
	}

	private async triggerEndOfTurn(player: PlayerState): Promise<void> {
		for (const card of player.getAllBoardUnits()) {
			await this.triggerCardEffects(card, "turn_end");
			if (card.tickTimer()) {
				this.events.emit("timer_expired", { card });
				await this.triggerCardEffects(card, "timer");
			}
		}
		await this.triggerHoard(player);
		await this.triggerSpot67All();
	}

	private async triggerPlayerEffects(player: PlayerState, triggers: EffectTrigger[]): Promise<void> {
		for (const card of [...player.getAllBoardUnits()]) {
			for (const trigger of triggers) {
				await this.triggerCardEffects(card, trigger);
			}
		}
	}

	private async triggerCardEffects(card: CardInstance, trigger: EffectTrigger): Promise<boolean> {
		let emitted = false;
		for (const effect of card.data.effects) {
			if (effect.trigger === trigger) {
				await this.emitTriggeredEffect(card, effect);
				emitted = true;
			}
		}
		return emitted;
	}

	private async emitTriggeredEffect(card: CardInstance, effect: CardEffect): Promise<void> {
		this.events.emit("ability_triggered", { card, effect });
		await this.resolver.resolveAbility(card, effect);
	}

	getCardController(card: CardInstance): PlayerState | null {
		return this.players.find((p) => p.playerId === card.controllerId) ?? null;
	}

	private async triggerHoard(player: PlayerState): Promise<void> {
		for (const card of [...player.getAllBoardUnits()]) {
			await this.triggerCardEffects(card, "hoard");
		}
	}

	private async triggerSpot67All(): Promise<void> {
		for (const player of this.players) {
			if (this.playerSpots67(player)) {
				for (const card of [...player.getAllBoardUnits()]) {
					await this.triggerCardEffects(card, "spot_67");
				}
			}
		}
	}

	private playerSpots67(player: PlayerState): boolean {
		for (const card of player.getAllBoardUnits()) {
			if (card.data.id === "67") return true;
			if (cardRepresentsNumber(card, "6")) {
				const pos = player.findCardPosition(card);
				if (!pos) continue;
				for (const adjacent of getAdjacentCards(player, pos.row, pos.col)) {
					if (cardRepresentsNumber(adjacent, "7")) return true;
				}
			}
		}
		return false;
	}

	// ── Board Activations ──────────────────────────────────────────────────────

	/** Activate a board card's Order effects for the current player. */
	async activateOrder(card: CardInstance): Promise<boolean> {
		if (this.currentPhase !== TurnPhase.PLAY_CARDS || card.activatedThisTurn) return false;
		const player = this.getCurrentPlayer();
		if (card.controllerId !== player.playerId || !player.getAllBoardUnits().includes(card)) return false;
		if (!this.cardHasPayableTrigger(card, "order", player)) return false;
		const triggered = await this.triggerCardEffects(card, "order");
		if (triggered) {
			card.activatedThisTurn = true;
			await this.triggerHoard(player);
			await this.triggerSpot67All();
		}
		return triggered;
	}

	/** Activate a board card's Pay effects for the current player. */
	async activatePay(card: CardInstance): Promise<boolean> {
		if (this.currentPhase !== TurnPhase.PLAY_CARDS) return false;
		const player = this.getCurrentPlayer();
		if (card.controllerId !== player.playerId || !player.getAllBoardUnits().includes(card)) return false;
		if (!this.cardHasPayableTrigger(card, "pay", player)) return false;
		const triggered = await this.triggerCardEffects(card, "pay");
		if (triggered) {
			await this.triggerHoard(player);
			await this.triggerSpot67All();
		}
		return triggered;
	}

	private cardHasPayableTrigger(card: CardInstance, trigger: EffectTrigger, player: PlayerState): boolean {
		for (const effect of card.data.effects) {
			if (effect.trigger !== trigger) continue;
			const payCost = effectivePayCost(card, effect, player);
			if (payCost > 0 && player.sellary < payCost) continue;
			if (effect.upkeepCost > 0 && player.sellary < effect.upkeepCost) continue;
			if (trigger === "order") {
				let chargeCost = effect.charges;
				if (chargeCost === 0 && card.maxCharges > 0) chargeCost = 1;
				if (chargeCost > 0 && card.charges < chargeCost) continue;
			}
			return true;
		}
		return false;
	}

	// ── Spawning / Replaying ───────────────────────────────────────────────────

	async spawnCardForPlayer(
		player: PlayerState,
		cardId: string,
		anchor: CardInstance | null = null,
		cursed = false,
	): Promise<CardInstance | null> {
		const cardData = this.db.getCard(cardId);
		if (!cardData) return null;
		const inst = CardInstance.create(cardData, player.playerId);
		if (cursed) inst.applyStatus("Cursed", 1, true);
		const placed = anchor ? player.placeAdjacentTo(inst, anchor) : player.placeInFirstFreeSlot(inst);
		if (!placed) {
			inst.moveToZone("graveyard");
			player.graveyard.push(inst);
			this.events.emit("card_discarded", { card: inst, playerId: player.playerId });
			return inst;
		}
		this.events.emit("card_placed_on_board", {
			card: inst,
			row: inst.boardPosition?.row ?? -1,
			col: inst.boardPosition?.col ?? -1,
		});
		await this.triggerDeploy(inst);
		await this.triggerCardEffects(inst, "passive");
		return inst;
	}

	async playSpecificFromDeckOrGraveyard(
		player: PlayerState,
		cardId: string,
		anchor: CardInstance | null = null,
		cursed = false,
	): Promise<CardInstance | null> {
		const card = player.takeFromFactionDeck(cardId) ?? player.takeFromGraveyard(cardId);
		if (!card) return null;
		if (cursed) card.applyStatus("Cursed", 1, true);
		const placed = anchor ? player.placeAdjacentTo(card, anchor) : player.placeInFirstFreeSlot(card);
		if (!placed) {
			card.moveToZone("graveyard");
			player.graveyard.push(card);
			return card;
		}
		this.events.emit("card_placed_on_board", {
			card,
			row: card.boardPosition?.row ?? -1,
			col: card.boardPosition?.col ?? -1,
		});
		await this.triggerDeploy(card);
		await this.triggerCardEffects(card, "passive");
		return card;
	}

	async replayFromGraveyard(player: PlayerState, card: CardInstance, cursed = false): Promise<boolean> {
		const idx = player.graveyard.indexOf(card);
		if (idx === -1) return false;
		player.graveyard.splice(idx, 1);
		if (cursed) card.applyStatus("Cursed", 1, true);
		if (card.data.type === "Unit" || card.data.type === "Artifact") {
			if (!player.placeInFirstFreeSlot(card)) {
				player.graveyard.push(card);
				return false;
			}
			this.events.emit("card_placed_on_board", {
				card,
				row: card.boardPosition?.row ?? -1,
				col: card.boardPosition?.col ?? -1,
			});
			await this.triggerDeploy(card);
			await this.triggerCardEffects(card, "passive");
		} else if (card.data.type === "Spell") {
			await this.resolveSpell(card);
			card.moveToZone("graveyard");
			player.graveyard.push(card);
		}
		return true;
	}

	// ── Statuses ───────────────────────────────────────────────────────────────

	private async triggerStatuses(player: PlayerState): Promise<void> {
		for (const card of player.getAllBoardUnits()) {
			if (card.data.type === "Artifact") continue;

			// Poison: 1 damage per stack, cannot kill
			if (card.hasStatus("Poison")) {
				const dmg = Math.min(card.getStatusStacks("Poison"), card.currentPower - 1);
				if (dmg > 0) {
					card.applyDirectDamage(dmg);
					this.events.emit("damage_dealt", { target: card, amount: dmg, source: null });
					await this.resolver.onDamageDealt?.(card, dmg, null);
					this.events.emit("status_triggered", { target: card, statusName: "Poison" });
				}
			}

			// Burn: 1 damage per stack, can kill
			if (card.hasStatus("Burn")) {
				const stacks = card.getStatusStacks("Burn");
				card.applyDirectDamage(stacks);
				this.events.emit("damage_dealt", { target: card, amount: stacks, source: null });
				await this.resolver.onDamageDealt?.(card, stacks, null);
				this.events.emit("status_triggered", { target: card, statusName: "Burn" });
				if (card.currentPower <= 0) await this.destroyCard(card, player);
			}

			// Wither: damage = stacks, remove all stacks, can kill
			if (card.hasStatus("Wither")) {
				const stacks = card.getStatusStacks("Wither");
				card.applyDirectDamage(stacks);
				this.events.emit("damage_dealt", { target: card, amount: stacks, source: null });
				await this.resolver.onDamageDealt?.(card, stacks, null);
				card.removeStatus("Wither");
				this.events.emit("status_triggered", { target: card, statusName: "Wither" });
				if (card.currentPower <= 0) await this.destroyCard(card, player);
			}

			// Vulnerable: if damaged this turn, self-damage per stack
			if (card.hasStatus("Vulnerable") && card.damagedThisTurn) {
				const stacks = card.getStatusStacks("Vulnerable");
				card.applyDirectDamage(stacks);
				this.events.emit("damage_dealt", { target: card, amount: stacks, source: null });
				await this.resolver.onDamageDealt?.(card, stacks, null);
				this.events.emit("status_triggered", { target: card, statusName: "Vulnerable" });
				if (card.currentPower <= 0) await this.destroyCard(card, player);
			}
		}
	}

	// ── Destruction ────────────────────────────────────────────────────────────

	private destroying = new Set<CardInstance>();

	/**
	 * Card destruction: Last Word, Cursed check, graveyard/banish.
	 * Idempotent AND re-entrancy-safe: a card already destroyed or currently
	 * mid-destruction is skipped — the Godot original lacked this guard and
	 * hung forever when a card's last_word damage re-killed the card itself
	 * (dr_glass_cannon_chasuble's self-targeting last_word).
	 */
	async destroyCard(card: CardInstance, player: PlayerState): Promise<void> {
		if (card.zone === "graveyard" || card.zone === "banished") return;
		if (this.destroying.has(card)) return;
		this.destroying.add(card);
		try {
			await this.destroyCardInner(card, player);
		} finally {
			this.destroying.delete(card);
		}
	}

	private async destroyCardInner(card: CardInstance, player: PlayerState): Promise<void> {
		if (card.data.type === "Unit" || card.data.type === "Hero") {
			card.currentPower = 0;
		}
		for (const effect of card.data.effects) {
			if (effect.trigger === "last_word") {
				this.events.emit("last_word_triggered", { card });
				await this.emitTriggeredEffect(card, effect);
			}
		}

		// Remove from EVERY board — spy/steal cards can sit on a board whose
		// owner differs from the passed player.
		for (const p of this.players) {
			p.removeFromBoard(card);
		}
		this.events.emit("card_removed_from_board", { card });

		if (card.isCursed()) {
			card.moveToZone("banished");
			player.banished.push(card);
			this.events.emit("card_banished", { card });
		} else {
			card.moveToZone("graveyard");
			player.graveyard.push(card);
		}

		this.events.emit("card_destroyed", { card, source: null });
	}

	// ── Win Condition ──────────────────────────────────────────────────────────

	checkGameOver(): boolean {
		const alive = this.players.filter((p) => p.hero && p.hero.currentPower > 0);
		if (alive.length <= 1) {
			this.gameOver = true;
			this.winnerId = alive.length === 1 ? alive[0]!.playerId : -1;
			this.events.emit("game_ended", { winnerId: this.winnerId });
			return true;
		}
		return false;
	}

	forceGameOver(forcedWinnerId: number): void {
		this.gameOver = true;
		this.winnerId = forcedWinnerId;
		this.events.emit("game_ended", { winnerId: forcedWinnerId });
	}
}

function cardRepresentsNumber(card: CardInstance, numberText: string): boolean {
	return card.data.id === numberText || card.data.name.trim() === numberText;
}
