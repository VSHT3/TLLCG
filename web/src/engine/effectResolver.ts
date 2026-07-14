// Port of scripts/game/effect_resolver.gd — executes card effects.
// Callback-based target_requested/choice_requested became awaited
// InteractionHandler calls; everything else is 1:1 with the GDScript.

import type { CardEffect, TargetKind, TargetScope } from "./types";
import { effectNeedsTarget } from "./types";
import { CardInstance } from "./cardInstance";
import type { PlayerState } from "./playerState";
import type { GameState } from "./gameState";
import type { AbilityResolver } from "./abilityResolver";
import { effectivePayCost } from "./effectCosts";
import { getAdjacentCards, getCardAt } from "./boardManager";
import { Constants } from "./constants";
import { shuffle } from "./rng";

export class EffectResolver implements AbilityResolver {
	private game: GameState;
	private lastAbilityByPlayer = new Map<number, { card: CardInstance; effect: CardEffect }>();
	private replayingAbility = false;

	constructor(game: GameState) {
		this.game = game;
		game.events.on("turn_started", ({ playerId }) => this.lastAbilityByPlayer.delete(playerId));
	}

	private get events() {
		return this.game.events;
	}

	private message(text: string): void {
		this.events.emit("message_shown", { text });
	}

	// ── Dispatch (GDScript _on_ability_triggered) ──────────────────────────────

	async resolveAbility(card: CardInstance, effect: CardEffect): Promise<void> {
		this.message(`ABILITY: ${card.data.name} ${effect.type}/${effect.trigger}`);
		const shouldRecord = this.shouldRecordLastAbility(card, effect);

		if (card.data.id === "endest_pearl_incident") {
			await this.complexEndestPearlIncident(card);
			if (shouldRecord) this.recordLastAbility(card, effect);
			return;
		}
		if (card.data.id === "hnusny_domaci_produkt") {
			if (!this.checkCosts(card, effect)) return;
			await this.complexHnusnyDomaciProdukt(card, effect);
			if (shouldRecord) this.recordLastAbility(card, effect);
			return;
		}
		if (card.data.id === "velky_jazykovy_model" && effect.trigger === "turn_end" && effect.type === "banish") {
			if (card.counter <= 0) this.banishEffectTarget(card);
			return;
		}
		if (!this.checkCosts(card, effect)) return;
		if (effect.counterDelta !== 0) card.changeCounter(effect.counterDelta);

		await this.resolveByType(card, effect);
		if (shouldRecord) this.recordLastAbility(card, effect);
	}

	private async resolveByType(card: CardInstance, effect: CardEffect): Promise<void> {
		switch (effect.type) {
			case "damage":
				return this.resolveDamage(card, effect);
			case "boost":
				return this.resolveBoost(card, effect);
			case "heal":
				return this.resolveHeal(card, effect);
			case "profit":
			case "income":
				return this.resolveProfit(card, effect);
			case "draw":
				return this.resolveDraw(card, effect);
			case "apply_status":
				return this.resolveApplyStatus(card, effect);
			case "destroy":
				return this.resolveDestroy(card, effect);
			case "banish":
				return this.resolveBanish(card, effect);
			case "spy":
				return this.resolveSpy(card);
			case "devour":
				return this.resolveDevour(card);
			case "seize":
				return this.resolveSeize(card, effect);
			case "block":
				card.block = effect.value;
				return;
			case "gain_charge":
				card.gainCharge(effect.value > 0 ? effect.value : 1);
				this.message(`${card.data.name} gained charge (${card.charges}).`);
				return;
			case "complex":
				return this.resolveComplex(card, effect);
			case "cleanse":
				return this.resolveCleanse(card, effect);
			case "discard":
				return this.resolveDiscard(card, effect);
			default:
				this.message(`[EffectResolver] Unknown effect type: ${effect.type}`);
		}
	}

	/** Masovystit redirect hook — awaited after every damage_dealt, before kill checks. */
	async onDamageDealt(target: CardInstance, amount: number, source: CardInstance | null): Promise<void> {
		if (amount <= 0) return;
		await this.applyMasovystitRedirect(target, amount, source);
	}

	// ── Cost Checking ──────────────────────────────────────────────────────────

	private checkCosts(card: CardInstance, effect: CardEffect): boolean {
		const player = this.getController(card);
		if (!player) return false;

		const useKey = `${effect.type}:${effect.trigger}:${effect.rawText}`;
		if (effect.maxUsesPerTurn > 0) {
			if ((card.effectUsesThisTurn.get(useKey) ?? 0) >= effect.maxUsesPerTurn) return false;
		}

		// Tribute: optional cost (choice already made by GameState)
		if (effect.trigger === "tribute" && effect.tributeCost > 0) {
			if (player.sellary < effect.tributeCost) return false;
			player.spendSellary(effect.tributeCost);
		}

		// Upkeep: mandatory cost attached to any trigger
		if (effect.upkeepCost > 0) {
			if (!player.spendSellary(effect.upkeepCost)) return false;
		}

		// Hoard: threshold check (doesn't spend)
		if (effect.trigger === "hoard" && effect.hoardThreshold > 0) {
			if (player.sellary < effect.hoardThreshold) return false;
		}

		// Order: charge check
		if (effect.trigger === "order") {
			let chargeCost = effect.charges;
			if (chargeCost === 0 && card.maxCharges > 0) chargeCost = 1;
			if (chargeCost > 0 && !card.useCharge(chargeCost)) return false;
		}

		// Pay: explicit sellary cost
		if (effect.trigger === "pay" && effect.payCost > 0) {
			if (!player.spendSellary(effectivePayCost(card, effect, player))) return false;
		}

		if (effect.maxUsesPerTurn > 0) {
			card.effectUsesThisTurn.set(useKey, (card.effectUsesThisTurn.get(useKey) ?? 0) + 1);
		}
		return true;
	}

	private shouldRecordLastAbility(card: CardInstance, effect: CardEffect): boolean {
		if (this.replayingAbility) return false;
		if (card.data.id === "velky_jazykovy_model") return false;
		const player = this.getController(card);
		if (!player || player.playerId !== this.game.getCurrentPlayer().playerId) return false;
		return effect.trigger !== "pay" || effect.type !== "complex";
	}

	private recordLastAbility(card: CardInstance, effect: CardEffect): void {
		const player = this.getController(card);
		if (player) this.lastAbilityByPlayer.set(player.playerId, { card, effect });
	}

	// ── Simple Effect Resolvers ────────────────────────────────────────────────

	private async requestTarget(source: CardInstance, effect: CardEffect | null, targets: CardInstance[], prompt = "Choose a target"): Promise<CardInstance | null> {
		return this.game.interaction.requestTarget({ source, effect, validTargets: targets, prompt });
	}

	private async resolveDamage(source: CardInstance, effect: CardEffect): Promise<void> {
		const targets = this.getEffectTargets(source, effect);
		if (targets.length === 0) return;
		if (effectNeedsTarget(effect)) {
			const target = await this.requestTarget(source, effect, targets);
			if (!target) return;
			for (const affected of this.expandAreaTargets(target, effect)) {
				await this.applyDamage(source, affected, effect.value);
			}
		} else {
			for (const target of targets) {
				await this.applyDamage(source, target, effect.value);
			}
		}
	}

	/** Damage with Crit/Perplexed/Drunk rules; kills + deathblow. Artifacts immune. */
	async applyDamage(source: CardInstance, target: CardInstance, baseDamage: number): Promise<void> {
		if (target.data.type === "Artifact") return;
		let damage = baseDamage;
		if (source.hasStatus("Crit")) damage *= 2;

		if (source.hasStatus("Perplexed") && this.game.rng.randf() < 0.5) {
			const player = this.getController(source);
			if (player?.hero) target = player.hero;
		}

		if (source.hasStatus("Drunk")) {
			const missChance = source.getStatusStacks("Drunk") * 0.25;
			if (this.game.rng.randf() < missChance) {
				if (source.data.factions.includes("Abeer Dawood Salman")) {
					const critChance = source.getStatusStacks("Drunk") * 0.25;
					if (this.game.rng.randf() < critChance) {
						damage *= 2;
						this.message(`${source.data.name} crits! (Abeer Drunk)`);
					} else {
						this.message(`${source.data.name} missed (Drunk)!`);
						return;
					}
				} else {
					this.message(`${source.data.name} missed (Drunk)!`);
					return;
				}
			}
		}

		// Only a target that was actually alive can be killed by this hit —
		// re-hitting a corpse must not re-trigger destroy/deathblow (the Godot
		// original loops forever on mass-damage deathblow spells otherwise).
		const wasAlive = target.currentPower > 0;
		const actualDamage = target.applyDamage(damage);
		this.events.emit("damage_dealt", { target, amount: actualDamage, source });
		await this.onDamageDealt(target, actualDamage, source);

		if (wasAlive && target.currentPower <= 0) {
			const owner = this.findCardOwner(target);
			if (owner) await this.game.destroyCard(target, owner);
			if (target.data.type === "Unit") {
				for (const eff of source.data.effects) {
					if (eff.trigger === "deathblow") {
						this.events.emit("deathblow_triggered", { card: source, killed: target });
						this.events.emit("ability_triggered", { card: source, effect: eff });
						await this.resolveAbility(source, eff);
					}
				}
			}
		}
	}

	private async resolveBoost(source: CardInstance, effect: CardEffect): Promise<void> {
		const targets = this.getEffectTargets(source, effect);
		if (targets.length === 0) return;
		if (effectNeedsTarget(effect)) {
			const target = await this.requestTarget(source, effect, targets);
			if (!target) return;
			for (const affected of this.expandAreaTargets(target, effect)) {
				affected.applyBoost(effect.value);
				this.events.emit("boost_applied", { target: affected, amount: effect.value });
			}
		} else {
			for (const target of targets) {
				target.applyBoost(effect.value);
				this.events.emit("boost_applied", { target, amount: effect.value });
			}
		}
	}

	private async resolveHeal(source: CardInstance, effect: CardEffect): Promise<void> {
		const targets = this.getEffectTargets(source, effect);
		if (targets.length === 0) return;
		if (effectNeedsTarget(effect)) {
			const target = await this.requestTarget(source, effect, targets);
			if (!target) return;
			for (const affected of this.expandAreaTargets(target, effect)) {
				this.healCard(affected, effect.value);
			}
		} else {
			for (const target of targets) {
				this.healCard(target, effect.value);
			}
		}
	}

	private healCard(target: CardInstance, value: number): void {
		const amount = value <= 0 ? target.missingHealth() : value;
		target.applyHeal(amount);
		this.events.emit("heal_applied", { target, amount });
	}

	private async resolveProfit(source: CardInstance, effect: CardEffect): Promise<void> {
		const player = this.getController(source);
		if (!player) return;
		let amount = effect.value;
		// Economic Fury doubles profit
		if (source.hasStatus("Economic Fury") || (player.hero && player.hero.hasStatus("Economic Fury"))) {
			amount *= 2;
		}
		player.gainSellary(amount);
	}

	private async resolveDraw(source: CardInstance, effect: CardEffect): Promise<void> {
		const player = this.getController(source);
		if (!player) return;
		// EGGxited: draw copies of Egg specifically
		if (source.data.id === "eggxited") {
			const eggData = this.game.db.getCard("egg");
			if (eggData) {
				for (let i = 0; i < effect.value; i++) {
					const egg = CardInstance.create(eggData, player.playerId);
					player.addToHand(egg);
					this.events.emit("card_drawn", { card: egg, playerId: player.playerId, source: "neutral" });
				}
			}
			return;
		}
		// Free draws from abilities pull from the neutral deck
		for (let i = 0; i < effect.value; i++) {
			const card = this.game.neutralDeck.shift();
			if (!card) break;
			card.ownerId = player.playerId;
			card.controllerId = player.playerId;
			player.addToHand(card);
			this.events.emit("card_drawn", { card, playerId: player.playerId, source: "neutral" });
		}
	}

	private async resolveApplyStatus(source: CardInstance, effect: CardEffect): Promise<void> {
		const targets = this.getEffectTargets(source, effect);
		if (targets.length === 0) return;
		if (effectNeedsTarget(effect)) {
			const target = await this.requestTarget(source, effect, targets);
			if (!target) return;
			this.applyStatusToTarget(target, effect);
		} else {
			for (const target of targets) {
				this.applyStatusToTarget(target, effect);
			}
		}
	}

	private applyStatusToTarget(target: CardInstance, effect: CardEffect): void {
		const stacks = effect.stacks > 0 ? effect.stacks : 1;
		for (const affected of this.expandAreaTargets(target, effect)) {
			affected.applyStatus(effect.status, stacks, effect.permanentStatus);
			this.events.emit("status_applied", { target: affected, statusName: effect.status, stacks });
		}
	}

	private async resolveDestroy(source: CardInstance, effect: CardEffect): Promise<void> {
		const targets = this.getEffectTargets(source, effect);
		if (targets.length === 0) return;
		if (effectNeedsTarget(effect)) {
			const target = await this.requestTarget(source, effect, targets);
			if (!target) return;
			await this.destroyEffectTarget(target);
		} else {
			for (const target of targets) {
				await this.destroyEffectTarget(target);
			}
		}
	}

	private async resolveBanish(source: CardInstance, effect: CardEffect): Promise<void> {
		const targets = this.getEffectTargets(source, effect);
		if (targets.length === 0) return;
		if (effectNeedsTarget(effect)) {
			const target = await this.requestTarget(source, effect, targets);
			if (!target) return;
			this.banishEffectTarget(target);
		} else {
			for (const target of targets) {
				this.banishEffectTarget(target);
			}
		}
	}

	/** Place card on opponent's board. */
	private async resolveSpy(source: CardInstance): Promise<void> {
		const player = this.getController(source);
		if (!player) return;
		const opponent = this.game.players.find((p) => p.playerId !== player.playerId);
		if (!opponent) return;
		player.removeFromBoard(source);
		this.events.emit("card_removed_from_board", { card: source });
		source.controllerId = opponent.playerId;
		let placed = false;
		for (let rowIdx = 0; rowIdx < opponent.board.length; rowIdx++) {
			const freeCol = opponent.findFreeCol(rowIdx);
			if (freeCol >= 0) {
				placed = opponent.placeOnBoard(source, rowIdx, freeCol);
				if (placed) this.events.emit("card_placed_on_board", { card: source, row: rowIdx, col: freeCol });
				break;
			}
		}
		if (!placed) {
			source.moveToZone("graveyard");
			player.graveyard.push(source);
			this.events.emit("card_discarded", { card: source, playerId: player.playerId });
		}
	}

	private async resolveDevour(source: CardInstance): Promise<void> {
		const player = this.getController(source);
		if (!player) return;
		const allies = player.getAllBoardUnits().filter((c) => c !== source && c.data.type === "Unit");
		if (allies.length === 0) return;
		const target = await this.requestTarget(source, null, allies, "Devour an ally");
		if (!target) return;
		const power = target.currentPower;
		await this.game.destroyCard(target, player);
		source.applyBoost(power);
		this.events.emit("boost_applied", { target: source, amount: power });
	}

	/** Steal sellary from a player. */
	private async resolveSeize(source: CardInstance, effect: CardEffect): Promise<void> {
		const player = this.getController(source);
		if (!player) return;
		const targets: PlayerState[] = this.game.players.filter((p) => {
			switch (effect.targetScope) {
				case "self":
				case "ally":
					return p.playerId === player.playerId;
				case "any":
					return true;
				default:
					return p.playerId !== player.playerId;
			}
		});
		if (targets.length === 0) return;
		if (targets.length === 1) {
			this.applySeize(player, targets[0]!, effect.value);
			return;
		}
		const chosen = await this.game.interaction.requestChoice(
			"Seize from",
			targets.map((t) => ({
				label: t.playerId === player.playerId ? "You" : "Opponent",
				value: t,
			})),
		);
		this.applySeize(player, chosen, effect.value);
	}

	private applySeize(toPlayer: PlayerState, fromPlayer: PlayerState, value: number): void {
		const amount = Math.min(value, fromPlayer.sellary);
		fromPlayer.sellary -= amount;
		toPlayer.gainSellary(amount);
		this.events.emit("sellary_seized", { fromId: fromPlayer.playerId, toId: toPlayer.playerId, amount });
	}

	private async resolveCleanse(source: CardInstance, effect: CardEffect): Promise<void> {
		const targets = this.getEffectTargets(source, effect);
		if (targets.length === 0) return;
		if (effectNeedsTarget(effect)) {
			const target = await this.requestTarget(source, effect, targets);
			if (!target) return;
			this.cleanseEffectTarget(target);
		} else {
			for (const target of targets) {
				this.cleanseEffectTarget(target);
			}
		}
	}

	private cleanseEffectTarget(target: CardInstance): void {
		target.cleanse();
		this.message(`Cleanse: ${target.data.name} cleansed`);
	}

	private async resolveDiscard(source: CardInstance, effect: CardEffect): Promise<void> {
		const player = this.getController(source);
		if (!player) return;
		if (effect.targetScope === "self") {
			this.moveCardToGraveyard(player, source);
			return;
		}
		const playersToScan = this.game.players.filter((p) => {
			switch (effect.targetScope) {
				case "ally":
					return p.playerId === player.playerId;
				case "any":
					return true;
				default:
					return p.playerId !== player.playerId;
			}
		});
		const candidates = playersToScan.flatMap((p) => p.hand);
		if (candidates.length === 0) return;
		const target = await this.game.interaction.requestChoice(
			"Discard",
			candidates.map((card) => ({ label: `${card.data.name} (${card.data.rarity})`, value: card })),
		);
		const owner = this.findCardOwnerOrZoneOwner(target);
		if (owner) this.moveCardToGraveyard(owner, target);
	}

	// ── Shared Target/Zone Helpers ─────────────────────────────────────────────

	private async destroyEffectTarget(target: CardInstance): Promise<void> {
		const owner = this.findCardOwner(target);
		if (owner) await this.game.destroyCard(target, owner);
	}

	private banishEffectTarget(target: CardInstance): void {
		const owner = this.findCardOwner(target) ?? this.findCardOwnerOrZoneOwner(target);
		if (!owner) return;
		this.removeCardFromOwnerZones(owner, target);
		target.moveToZone("banished");
		owner.banished.push(target);
		this.events.emit("card_banished", { card: target });
	}

	private moveCardToGraveyard(owner: PlayerState, card: CardInstance): void {
		this.removeCardFromOwnerZones(owner, card);
		card.moveToZone("graveyard");
		owner.graveyard.push(card);
		this.events.emit("card_discarded", { card, playerId: owner.playerId });
	}

	private removeCardFromOwnerZones(owner: PlayerState, card: CardInstance): void {
		if (owner.getAllBoardUnits().includes(card)) {
			owner.removeFromBoard(card);
			this.events.emit("card_removed_from_board", { card });
		}
		if (owner.hand.includes(card)) owner.removeFromHand(card);
		const gIdx = owner.graveyard.indexOf(card);
		if (gIdx !== -1) owner.graveyard.splice(gIdx, 1);
		const bIdx = owner.banished.indexOf(card);
		if (bIdx !== -1) owner.banished.splice(bIdx, 1);
	}

	private expandAreaTargets(target: CardInstance, effect: CardEffect): CardInstance[] {
		const result = [target];
		if (!effect.area) return result;
		const owner = this.findCardOwner(target);
		if (!owner) return result;
		const pos = owner.findCardPosition(target);
		if (!pos) return result;
		for (const adjacent of getAdjacentCards(owner, pos.row, pos.col)) {
			if (!result.includes(adjacent)) result.push(adjacent);
		}
		return result;
	}

	// ── Player/Target Lookup Helpers ───────────────────────────────────────────

	getController(card: CardInstance): PlayerState | null {
		return this.game.players.find((p) => p.playerId === card.controllerId) ?? null;
	}

	findCardOwner(card: CardInstance): PlayerState | null {
		return this.game.players.find((p) => p.getAllBoardUnits().includes(card) || p.hero === card) ?? null;
	}

	findCardOwnerOrZoneOwner(card: CardInstance): PlayerState | null {
		return (
			this.findCardOwner(card) ??
			this.game.players.find(
				(p) => p.hand.includes(card) || p.graveyard.includes(card) || p.banished.includes(card) || p.playerId === card.ownerId,
			) ??
			null
		);
	}

	getEnemyPlayer(source: CardInstance): PlayerState | null {
		const player = this.getController(source);
		if (!player) return null;
		return this.game.players.find((p) => p.playerId !== player.playerId) ?? null;
	}

	getEnemyHero(player: PlayerState): CardInstance | null {
		const enemy = this.game.players.find((p) => p.playerId !== player.playerId);
		if (!enemy) return null;
		return enemy.hero && enemy.hero.currentPower > 0 ? enemy.hero : null;
	}

	controlsCardId(player: PlayerState, cardId: string): boolean {
		return player.getAllBoardUnits().some((c) => c.data.id === cardId);
	}

	getValidDamageTargets(source: CardInstance): CardInstance[] {
		const player = this.getController(source);
		if (!player) return [];
		const targets: CardInstance[] = [];
		for (const p of this.game.players) {
			if (p.playerId === player.playerId) continue;
			for (const card of p.getAllBoardUnits()) {
				if (!card.hasStatus("Invisible")) targets.push(card);
			}
			if (p.hero && p.hero.currentPower > 0) targets.push(p.hero);
		}
		return targets;
	}

	private getBoardCardsByFilter(scope: TargetScope, kind: TargetKind, sourcePlayer: PlayerState): CardInstance[] {
		const source = sourcePlayer.getAllBoardUnits()[0] ?? sourcePlayer.hero;
		if (!source) return [];
		return this.getEffectTargets(source, {
			...EMPTY_EFFECT,
			targetScope: scope,
			targetKind: kind,
			requiresTarget: true,
		});
	}

	getEffectTargets(source: CardInstance, effect: CardEffect): CardInstance[] {
		if (effect.targetScope === "self") return [source];

		const sourcePlayer = this.getController(source);
		if (!sourcePlayer) return [];

		const playersToScan = this.game.players.filter((p) => {
			switch (effect.targetScope) {
				case "ally":
					return p.playerId === sourcePlayer.playerId;
				case "any":
					return true;
				default:
					return p.playerId !== sourcePlayer.playerId;
			}
		});

		const targets: CardInstance[] = [];
		for (const player of playersToScan) {
			switch (effect.targetKind) {
				case "hero":
					if (player.hero && player.hero.currentPower > 0) targets.push(player.hero);
					break;
				case "artifact":
					targets.push(...player.getAllBoardUnits().filter((c) => c.data.type === "Artifact"));
					break;
				case "unit":
					targets.push(...player.getAllBoardUnits().filter((c) => c.data.type === "Unit"));
					break;
				case "non_hero":
					targets.push(...player.getAllBoardUnits());
					break;
				case "non_unit":
					targets.push(...player.getAllBoardUnits().filter((c) => c.data.type !== "Unit"));
					if (player.hero && player.hero.currentPower > 0) targets.push(player.hero);
					break;
				default:
					targets.push(...player.getAllBoardUnits());
					if (player.hero && player.hero.currentPower > 0) targets.push(player.hero);
			}
		}

		return targets.filter((target) => {
			if (target === source && effect.targetScope !== "self") return false;
			if (target.hasStatus("Invisible") && effectNeedsTarget(effect)) return false;
			if (this.isBlockedByProtectorOrDefender(target)) return false;
			return true;
		});
	}

	private isBlockedByProtectorOrDefender(target: CardInstance): boolean {
		const owner = this.findCardOwner(target);
		if (!owner) return false;
		if (target === owner.hero) {
			for (const card of owner.getAllBoardUnits()) {
				if (card.hasStatus("Protector")) return true;
			}
		}
		const pos = owner.findCardPosition(target);
		if (!pos) return false;
		for (const card of owner.board[pos.row]!) {
			if (card !== target && card.hasStatus("Defender") && !target.hasStatus("Defender")) return true;
		}
		return false;
	}

	// ── Masovystit Redirect ────────────────────────────────────────────────────

	private async applyMasovystitRedirect(target: CardInstance, amount: number, damageSource: CardInstance | null): Promise<void> {
		const owner = this.findCardOwner(target);
		if (!owner) return;
		const pos = owner.findCardPosition(target);
		if (!pos) return;
		const shieldRow = pos.row - 1;
		if (shieldRow < 0) return;
		const shield = getCardAt(owner, shieldRow, pos.col);
		if (!shield || shield.data.id !== "masovystit" || shield === target) return;
		target.currentPower += amount;
		this.events.emit("heal_applied", { target, amount });
		const actual = shield.applyDamage(amount * 2);
		this.events.emit("damage_dealt", { target: shield, amount: actual, source: damageSource });
		this.message(`MasovyStit redirected ${amount} damage.`);
		if (shield.currentPower <= 0) await this.game.destroyCard(shield, owner);
	}

	// ── Complex Card Implementations ───────────────────────────────────────────

	private async resolveComplex(source: CardInstance, effect: CardEffect): Promise<void> {
		const handler = COMPLEX_HANDLERS[source.data.id];
		if (!handler) {
			this.message(`[EffectResolver] Unimplemented complex effect on ${source.data.name}: ${effect.rawText}`);
			return;
		}
		await handler(this, source, effect);
	}

	async complexAccountantProMax(source: CardInstance): Promise<void> {
		const player = this.getController(source);
		if (!player) return;
		const gold = player.sellary;
		let profit = 0;
		let boost = 0;
		if (gold >= 8) {
			profit = 4;
			boost = 1;
		} else if (gold >= 6) {
			profit = 3;
		} else if (gold >= 2) {
			profit = 2;
		}
		if (profit > 0) {
			player.gainSellary(profit);
			this.message(`Accountant Pro Max: profit ${profit}`);
		}
		if (boost > 0) {
			source.applyBoost(boost);
			this.events.emit("boost_applied", { target: source, amount: boost });
		}
	}

	async complexCarryOn(source: CardInstance): Promise<void> {
		const player = this.getController(source);
		if (!player) return;
		player.extraCardPlays += 2;
		this.message("Carry On: +2 card plays this turn");
	}

	async complexHhmds(source: CardInstance): Promise<void> {
		const player = this.getController(source);
		if (!player) return;
		player.extraCardPlays += 1;
		this.message("HHMDS: +1 card play this turn");
	}

	async complexCatchUp(source: CardInstance): Promise<void> {
		const player = this.getController(source);
		if (!player) return;
		const other = this.game.players.find((p) => p.playerId !== player.playerId);
		if (!other) return;
		const diff = other.sellary - player.sellary;
		if (diff > 0) {
			player.gainSellary(diff);
			this.message(`Catch-up: gained ${diff} sellary`);
		} else if (diff < 0) {
			player.spendSellary(-diff);
			this.message(`Catch-up: lost ${-diff} sellary`);
		}
	}

	async complexIndividualSailor(source: CardInstance): Promise<void> {
		const player = this.getController(source);
		if (!player) return;
		if (player.isAloneInRow(source)) {
			const enemyHero = this.getEnemyHero(player);
			if (enemyHero) await this.applyDamage(source, enemyHero, 3);
			source.applyBoost(1);
			this.events.emit("boost_applied", { target: source, amount: 1 });
		} else {
			const right = player.getRightNeighbor(source);
			if (right) {
				right.applyBoost(1);
				this.events.emit("boost_applied", { target: right, amount: 1 });
			}
		}
	}

	async complexSirVant(source: CardInstance, effect: CardEffect): Promise<void> {
		const player = this.getController(source);
		if (!player) return;
		if (effect.trigger === "turn_end") {
			// Optional: pay 2 → heal hero by 1
			if (player.sellary >= 2 && player.hero) {
				player.spendSellary(2);
				player.hero.applyHeal(1);
				this.events.emit("heal_applied", { target: player.hero, amount: 1 });
				this.message("Sir Vant: paid 2, healed hero by 1");
			}
		} else if (effect.trigger === "last_word") {
			for (const card of player.getAllBoardUnits()) {
				if (card.data.factions.includes("Sir Can")) {
					card.applyHeal(2);
					this.events.emit("heal_applied", { target: card, amount: 2 });
					card.applyBoost(1);
					this.events.emit("boost_applied", { target: card, amount: 1 });
				}
			}
			this.message("Sir Vant last word: healed+boosted Sir Can units");
		}
	}

	async complexSibal(source: CardInstance): Promise<void> {
		const player = this.getController(source);
		if (!player) return;
		let shuffled = 0;
		while (shuffled < 2 && player.hand.length > 0) {
			const card = player.hand[player.hand.length - 1]!;
			player.removeFromHand(card);
			card.moveToZone("deck");
			player.factionDeck.push(card);
			shuffled++;
		}
		shuffle(player.factionDeck, this.game.rng);
		for (let i = 0; i < 2; i++) {
			const drawn = player.drawFactionCard();
			if (drawn) this.events.emit("card_drawn", { card: drawn, playerId: player.playerId, source: "faction" });
		}
		this.message(`Šibal: shuffled ${shuffled}, drew 2 faction`);
	}

	async complexKnight(source: CardInstance): Promise<void> {
		const player = this.getController(source);
		if (!player) return;
		const enemyHero = this.getEnemyHero(player);
		if (enemyHero) await this.applyDamage(source, enemyHero, 1);
	}

	async complexTaxEr(source: CardInstance): Promise<void> {
		const player = this.getController(source);
		if (!player) return;
		const opponent = this.game.players.find((p) => p.playerId !== player.playerId);
		if (!opponent) return;
		let unpaid = 0;
		if (opponent.sellary < 2) {
			unpaid = 2 - opponent.sellary;
			opponent.sellary = 0;
		} else {
			opponent.sellary -= 2;
		}
		if (unpaid > 0 && opponent.hero) {
			for (let i = 0; i < unpaid; i++) {
				await this.applyDamage(source, opponent.hero, 1);
			}
		}
		this.events.emit("sellary_seized", { fromId: opponent.playerId, toId: player.playerId, amount: 2 - unpaid });
		this.message(`Tax 'er!: took ${2 - unpaid}, unpaid ${unpaid}`);
	}

	async complexFukaciaPracicka(source: CardInstance): Promise<void> {
		const player = this.getController(source);
		if (!player) return;
		const targets = this.game.players.flatMap((p) => p.getAllBoardUnits().filter((c) => c.data.type !== "Hero"));
		if (targets.length === 0) return;
		const target = await this.requestTarget(source, null, targets, "Heal + cleanse a unit");
		if (!target) return;
		const healAmount = target.data.basePower - target.currentPower;
		if (healAmount > 0) {
			target.applyHeal(healAmount);
			this.events.emit("heal_applied", { target, amount: healAmount });
		}
		target.cleanse();
		this.message(`Fúkacia Prácička: healed ${healAmount} + cleansed ${target.data.name}`);
	}

	async complexEverythingHereHere(source: CardInstance): Promise<void> {
		const player = this.getController(source);
		if (!player) return;
		if (player.isBoardFull()) {
			player.extraCardPlays += 3;
			this.message("Everything Here Here: +3 extra plays");
		}
	}

	async complexSibalSoSledovanimLucov(source: CardInstance): Promise<void> {
		const player = this.getController(source);
		if (!player) return;
		const revealed = player.factionDeck.slice(0, 3).map((c) => c.data.name);
		await this.game.interaction.requestChoice("Šibal so sledovaním lúčov", [
			{
				label: "Continue",
				description: `Next faction cards: ${revealed.length > 0 ? revealed.join(", ") : "none"}`,
				value: true,
			},
		]);
		let drawn = 0;
		for (let i = 0; i < 3; i++) {
			const card = player.drawFactionCard();
			if (card) {
				this.events.emit("card_drawn", { card, playerId: player.playerId, source: "faction" });
				drawn++;
			}
		}
		let shuffled = 0;
		while (shuffled < 3 && player.hand.length > 0) {
			const card = player.hand[player.hand.length - 1]!;
			player.removeFromHand(card);
			card.moveToZone("deck");
			player.factionDeck.push(card);
			shuffled++;
		}
		shuffle(player.factionDeck, this.game.rng);
		this.message(`Šibal so sledovaním lúčov: drew ${drawn}, shuffled ${shuffled} back`);
	}

	async complexEndestPearlIncident(source: CardInstance): Promise<void> {
		const player = this.getController(source);
		if (!player) return;
		const choice = await this.game.interaction.requestChoice("Endest Pearl Incident", [
			{ label: "Destroy an artifact", description: "Choose any artifact on the board.", value: "destroy_artifact" },
			{ label: "Damage all units", description: "Deal 2 damage to every unit.", value: "damage_units" },
			{ label: "Damage a hero", description: "Deal 7 damage to a chosen hero.", value: "damage_hero" },
		]);
		switch (choice) {
			case "destroy_artifact": {
				const targets = this.getBoardCardsByFilter("any", "artifact", player);
				if (targets.length === 0) {
					this.message("No artifact to destroy.");
					break;
				}
				const target = await this.requestTarget(source, null, targets, "Destroy an artifact");
				if (target) await this.destroyEffectTarget(target);
				break;
			}
			case "damage_units": {
				for (const target of this.getBoardCardsByFilter("any", "unit", player)) {
					await this.applyDamage(source, target, 2);
				}
				break;
			}
			case "damage_hero": {
				const heroes = this.getBoardCardsByFilter("any", "hero", player);
				if (heroes.length === 0) {
					this.message("No hero target.");
					break;
				}
				const target = await this.requestTarget(source, null, heroes, "Damage a hero");
				if (target) await this.applyDamage(source, target, 7);
				break;
			}
		}
		this.shuffleEndestBack(source);
	}

	private shuffleEndestBack(source: CardInstance): void {
		for (const player of this.game.players) {
			const gIdx = player.graveyard.indexOf(source);
			if (gIdx !== -1) player.graveyard.splice(gIdx, 1);
			if (player.hand.includes(source)) player.removeFromHand(source);
		}
		source.applyStatus("Cursed", 1, true);
		source.moveToZone("deck");
		source.ownerId = -1;
		source.controllerId = -1;
		this.game.neutralDeck.push(source);
		shuffle(this.game.neutralDeck, this.game.rng);
		this.message("Endest Pearl Incident gained Cursed and shuffled into neutral deck.");
	}

	async complexTheLionDoesNotCare(source: CardInstance): Promise<void> {
		const player = this.getController(source);
		if (!player) return;
		player.freePlaysTurn = true;
		this.message("The Lion Does Not Care: expenses negated this turn");
	}

	async complexSirVival(source: CardInstance, effect: CardEffect): Promise<void> {
		let player = this.getController(source);
		if (!player) {
			player = this.game.players.find((p) => p.playerId === source.ownerId) ?? null;
		}
		if (!player) return;

		if (effect.trigger === "turn_start") {
			if (source.zone === "graveyard") {
				const idx = player.graveyard.indexOf(source);
				if (idx >= 0) player.graveyard.splice(idx, 1);
				for (let rowIdx = 0; rowIdx < player.board.length; rowIdx++) {
					const col = player.findFreeCol(rowIdx);
					if (col >= 0) {
						player.placeOnBoard(source, rowIdx, col);
						this.events.emit("card_placed_on_board", { card: source, row: rowIdx, col });
						this.message("Sir Vival: returned from graveyard");
						break;
					}
				}
			}
		} else if (effect.trigger === "turn_end") {
			const right = player.getRightNeighbor(source);
			if (right) {
				right.applyHeal(1);
				this.events.emit("heal_applied", { target: right, amount: 1 });
			}
		}
	}

	async complexBiblography(source: CardInstance, effect: CardEffect): Promise<void> {
		if (effect.trigger !== "turn_end") return;
		const player = this.getController(source);
		if (!player) return;
		if (!player.spendSellary(2)) {
			this.message("Biblography: can't afford upkeep 2");
			return;
		}
		const rowMates = player.getCardsInRow(source);
		for (const card of rowMates) {
			if (card.data.type !== "Artifact") {
				card.applyHeal(1);
				this.events.emit("heal_applied", { target: card, amount: 1 });
			}
		}
		this.message(`Biblography: healed ${rowMates.length} row units`);
	}

	async complexTheProphet(source: CardInstance, effect: CardEffect): Promise<void> {
		const player = this.getController(source);
		if (!player) return;
		if (effect.trigger === "upkeep") return; // cost already deducted by checkCosts

		if (effect.trigger === "turn_end") {
			const hasSfp = this.controlsCardId(player, "self_fulfilling_prophecy");
			const hp = source.currentPower;
			if (hp % 2 === 0) {
				const enemyHero = this.getEnemyHero(player);
				if (hasSfp) {
					if (enemyHero) await this.applyDamage(source, enemyHero, 1);
					source.applyBoost(1);
					this.events.emit("boost_applied", { target: source, amount: 1 });
				} else {
					if (enemyHero) await this.applyDamage(source, enemyHero, 1);
					source.applyDamage(1);
					this.events.emit("damage_dealt", { target: source, amount: 1, source });
					if (source.currentPower <= 0) await this.game.destroyCard(source, player);
				}
			} else {
				source.applyBoost(1);
				this.events.emit("boost_applied", { target: source, amount: 1 });
				for (const neighbor of player.getRowNeighbors(source)) {
					neighbor.applyBoost(1);
					this.events.emit("boost_applied", { target: neighbor, amount: 1 });
				}
			}
		}
	}

	async complexOpakovaciaDedinka(source: CardInstance): Promise<void> {
		const player = this.getController(source);
		if (!player) return;
		const last = this.game.lastSpellPlayed;
		// Self-replay guard: replaying opakovacia_dedinka itself recurses forever
		// (latent bug in the Godot original, surfaced by the fuzz suite).
		if (!last || last.id === source.data.id) {
			this.message("Opakovacia Dedinka: no spell to replay");
			return;
		}
		const inst = CardInstance.create(last, player.playerId);
		inst.zone = "hand";
		await this.game.resolveSpell(inst);
		this.message(`Opakovacia Dedinka: replayed ${last.name}`);
	}

	async complexBreakthru(source: CardInstance): Promise<void> {
		const player = this.getController(source);
		if (!player) return;
		const targets = this.game.players
			.filter((p) => p.playerId !== player.playerId)
			.flatMap((p) => p.getAllBoardUnits());
		if (targets.length < 2) {
			this.message("Breakthru needs two enemy cards.");
			return;
		}
		const first = await this.requestTarget(source, null, targets, "Swap: first card");
		if (!first) return;
		const second = await this.requestTarget(source, null, targets.filter((t) => t !== first), "Swap: second card");
		if (!second) return;
		const owner = this.findCardOwner(first);
		if (owner && owner === this.findCardOwner(second) && owner.swapBoardPositions(first, second)) {
			this.message(`Breakthru swapped ${first.data.name} and ${second.data.name}.`);
		}
	}

	async complexDawood(source: CardInstance): Promise<void> {
		const player = this.getController(source);
		if (!player) return;
		const choice = await this.game.interaction.requestChoice("Dawood", [
			{ label: "Boost a non-hero unit", description: "+2 power to a chosen unit.", value: "boost" },
			{ label: "Damage a non-hero unit", description: "Deal 1 damage to a chosen unit.", value: "damage" },
		]);
		const targets = this.getBoardCardsByFilter("any", "unit", player);
		if (targets.length === 0) {
			this.message("No unit target.");
			return;
		}
		const target = await this.requestTarget(source, null, targets, "Dawood target");
		if (!target) return;
		if (choice === "boost") {
			target.applyBoost(2);
			this.events.emit("boost_applied", { target, amount: 2 });
		} else {
			await this.applyDamage(source, target, 1);
		}
	}

	async complexDiscardThisCard(source: CardInstance): Promise<void> {
		const opponent = this.getEnemyPlayer(source);
		if (!opponent || opponent.hand.length === 0) {
			this.message("Opponent has no hand to discard.");
			return;
		}
		shuffle(opponent.hand, this.game.rng);
		const card = opponent.hand.shift()!;
		card.moveToZone("graveyard");
		opponent.graveyard.push(card);
		this.events.emit("card_discarded", { card, playerId: opponent.playerId });
		this.message(`Discarded ${card.data.name} from opponent.`);
	}

	async complexClawsTheProduction(source: CardInstance): Promise<void> {
		const opponent = this.getEnemyPlayer(source);
		if (!opponent) return;
		opponent.baseSellaryModifierNextTurn -= 2;
		this.message("Opponent loses 2 base sellary next turn.");
	}

	async complexMyCountryCalledMe(source: CardInstance): Promise<void> {
		const opponent = this.getEnemyPlayer(source);
		if (!opponent) return;
		opponent.suppressEndTurnNextTurn = true;
		this.message("Opponent's next end-of-turn abilities are suppressed.");
	}

	async complexNegromancy(source: CardInstance, rarities: string[]): Promise<void> {
		const player = this.getController(source);
		if (!player) return;
		const candidates = player.getGraveyardCardsByRarity(rarities);
		if (candidates.length === 0) {
			this.message("No graveyard card of matching rarity.");
			return;
		}
		const card = await this.game.interaction.requestChoice(
			"Replay from graveyard",
			candidates.map((c) => ({ label: `${c.data.name} (${c.data.rarity} ${c.data.type})`, value: c })),
		);
		if (await this.game.replayFromGraveyard(player, card, true)) {
			this.message(`Replayed ${card.data.name} with Cursed.`);
		}
	}

	async complexSellersSailors(source: CardInstance): Promise<void> {
		const player = this.getController(source);
		if (!player) return;
		for (const cardId of ["the_parrot", "the_ship", "the_captain", "the_mate"]) {
			await this.game.spawnCardForPlayer(player, cardId);
		}
		this.message("Summoned The Crew.");
	}

	async complexPremiumAccount(source: CardInstance, effect: CardEffect): Promise<void> {
		const player = this.getController(source);
		if (!player) return;
		if (effect.trigger === "tribute") {
			for (let i = 0; i < 2; i++) {
				await this.game.spawnCardForPlayer(player, "neural_network", source);
			}
			this.message("Premium Account spawned Neural Networks.");
		} else {
			const count = player
				.getAllBoardUnits()
				.filter((c) => c.data.categories.includes("A.I.") || c.data.factions.includes("A.I. Gods")).length;
			player.gainSellary(count);
			this.message(`Premium Account profit ${count}.`);
		}
	}

	async complexScrollingPapers(source: CardInstance): Promise<void> {
		const player = this.getController(source);
		if (!player) return;
		const deckName = await this.game.interaction.requestChoice("Look through top 3", [
			{ label: "Neutral deck", description: "Reveal the next 3 shared cards.", value: "neutral" },
			{ label: "Faction deck", description: "Reveal the next 3 cards from your faction deck.", value: "faction" },
		]);
		const cards = deckName === "neutral" ? this.game.neutralDeck : player.factionDeck;
		const names = cards.slice(0, 3).map((c) => c.data.name);
		const title = deckName[0]!.toUpperCase() + deckName.slice(1);
		await this.game.interaction.showPanel(`${title} top cards`, names);
		this.message(`${title} top: ${names.join(", ")}`);
	}

	async complexDamina(source: CardInstance, effect: CardEffect): Promise<void> {
		const player = this.getController(source);
		if (!player) return;
		switch (effect.trigger) {
			case "deploy":
				if (this.controlsCardId(player, "trembling_lips")) {
					source.applyBoost(1);
					this.events.emit("boost_applied", { target: source, amount: 1 });
				} else if (await this.game.playSpecificFromDeckOrGraveyard(player, "trembling_lips", source)) {
					this.message("Damina played Trembling Lips.");
				}
				break;
			case "turn_start":
				this.message(`Damina counter: ${source.counter}.`);
				break;
			case "order": {
				if (source.counter > 0) {
					if (effect.charges > 0) source.gainCharge(effect.charges);
					this.message("Damina counter is not 0.");
					return;
				}
				const targets = this.getBoardCardsByFilter("any", "hero", player);
				const target = await this.requestTarget(source, effect, targets, "Damina: damage a hero");
				if (target) await this.applyDamage(source, target, 5);
				break;
			}
		}
	}

	async complexTremblingLips(source: CardInstance, effect: CardEffect): Promise<void> {
		const player = this.getController(source);
		if (!player) return;
		switch (effect.trigger) {
			case "deploy":
				if (this.controlsCardId(player, "damina")) {
					source.applyBoost(1);
					this.events.emit("boost_applied", { target: source, amount: 1 });
				} else if (await this.game.playSpecificFromDeckOrGraveyard(player, "damina", source)) {
					this.message("Trembling Lips played Damina.");
				}
				break;
			case "turn_start": {
				if (source.timer % 2 !== 0) return;
				const pos = player.findCardPosition(source);
				if (!pos) return;
				for (const p of this.game.players) {
					for (const card of p.board[pos.row]!) {
						card.applyStatus("Invisible", 1);
						this.events.emit("status_applied", { target: card, statusName: "Invisible", stacks: 1 });
					}
				}
				break;
			}
		}
	}

	async complexMissSpell(source: CardInstance): Promise<void> {
		const player = this.getController(source);
		if (!player) return;
		const target = this.getEnemyHero(player);
		if (!target) return;
		target.applyStatus("Miss Spell", 1);
		this.events.emit("status_applied", { target, statusName: "Miss Spell", stacks: 1 });
		this.message("Miss Spell applied to enemy hero.");
	}

	async complexMikrofoNovyPokles(source: CardInstance): Promise<void> {
		const player = this.getController(source);
		if (!player) return;
		if (player.cardsPlayedThisTurn > 1) {
			this.message("Mikrofonovy Pokles must be your first action.");
			return;
		}
		const amount = player.sellary;
		if (amount <= 0) {
			this.message("No sellary to spend.");
			return;
		}
		player.spendSellary(amount);
		const targets = this.getBoardCardsByFilter("any", "unit", player);
		if (targets.length === 0) {
			this.message("No unit target.");
			return;
		}
		const target = await this.requestTarget(source, null, targets, "Damage a unit");
		if (target) await this.applyDamage(source, target, amount);
	}

	async complexTheWhyAxes(source: CardInstance): Promise<void> {
		const rowIdx = await this.game.interaction.requestChoice("Choose row", [
			{ label: "Melee", description: "Front row, 5 slots.", value: 0 },
			{ label: "Ranged", description: "Middle row, 5 slots.", value: 1 },
			{ label: "Artillery", description: "Back row, 3 slots.", value: 2 },
		]);
		const cards = this.game.players.flatMap((p) => p.board[rowIdx]!.filter((c) => c.data.type === "Unit"));
		if (cards.length === 0) {
			this.message("No units on that row.");
			return;
		}
		const total = cards.reduce((n, c) => n + c.currentPower, 0);
		const average = Math.trunc(total / cards.length);
		for (const card of cards) {
			card.currentPower = average;
		}
		this.message(`The Why Axes set row power to ${average}.`);
	}

	async complexSirVeillance(source: CardInstance): Promise<void> {
		const opponent = this.getEnemyPlayer(source);
		if (!opponent) return;
		if (opponent.hand.length === 0) {
			this.message("Opponent hand is empty.");
			return;
		}
		const names = opponent.hand.map((c) => `${c.data.name} (${c.data.rarity})`);
		this.message(`Opponent hand: ${names.join(", ")}`);
	}

	async complexObratnostRuk(source: CardInstance): Promise<void> {
		const player = this.getController(source);
		if (!player) return;
		let bestPlayer: PlayerState | null = null;
		let bestScore = -1;
		const rolls: string[] = [];
		for (const participant of this.game.players) {
			const d20 = () => this.game.rng.randi(20) + 1;
			const score = participant.playerId === player.playerId ? Math.max(d20(), d20()) : d20();
			rolls.push(`${participant.playerId === player.playerId ? "You" : "Opponent"}=${score}`);
			if (score > bestScore) {
				bestScore = score;
				bestPlayer = participant;
			}
		}
		if (!bestPlayer) return;
		for (const participant of this.game.players) {
			if (participant.playerId === bestPlayer.playerId) continue;
			const amount = Math.min(4, participant.sellary);
			participant.sellary -= amount;
			bestPlayer.gainSellary(amount);
			this.events.emit("sellary_seized", { fromId: participant.playerId, toId: bestPlayer.playerId, amount });
		}
		this.message(`Obratnost Ruk: ${rolls.join(", ")}. ${bestPlayer.playerId === player.playerId ? "You" : "Opponent"} seized 4.`);
	}

	async complexMrRural(source: CardInstance, effect: CardEffect): Promise<void> {
		const player = this.getController(source);
		if (!player) return;
		switch (effect.trigger) {
			case "turn_start":
			case "upkeep": {
				const eggCount = player.hand.filter((c) => c.data.id === "egg").length;
				if (eggCount <= 0) {
					this.message("Mr. Rural: no eggs in hand.");
					return;
				}
				const targets = this.getBoardCardsByFilter("enemy", "non_unit", player);
				if (targets.length === 0) {
					this.message("Mr. Rural: no non-unit target.");
					return;
				}
				const target = await this.requestTarget(source, effect, targets, "Mr. Rural target");
				if (target) await this.applyDamage(source, target, eggCount);
				break;
			}
			case "pay":
				for (const participant of this.game.players) {
					this.createCardInHand(participant, "egg");
				}
				this.message("Both players drew an Egg.");
				break;
		}
	}

	async complexHnusnyDomaciProdukt(source: CardInstance, effect: CardEffect): Promise<void> {
		const player = this.getController(source);
		if (!player) return;
		switch (effect.trigger) {
			case "turn_start": {
				if (effect.type !== "profit") return;
				const amount = source.timer > 10 ? 2 : 1;
				player.gainSellary(amount);
				this.message(`Hnusny Domaci Produkt: profit ${amount}.`);
				break;
			}
			case "pay": {
				const increase = effect.value > 0 ? effect.value : 3;
				source.timer += increase;
				this.message(`Hnusny Domaci Produkt: timer +${increase}.`);
				break;
			}
			case "timer":
				if (effect.type !== "destroy") return;
				await this.destroyEffectTarget(source);
				break;
		}
	}

	async complexVelkyJazykovyModel(source: CardInstance, effect: CardEffect): Promise<void> {
		if (effect.trigger !== "pay") return;
		const player = this.getController(source);
		if (!player) return;
		const last = this.lastAbilityByPlayer.get(player.playerId);
		if (!last || !this.canRepeatLastAbility(last.card)) {
			this.message("Velky Jazykovy Model: no valid ability to repeat.");
			return;
		}
		this.replayingAbility = true;
		await this.resolveByType(last.card, last.effect);
		this.replayingAbility = false;
		source.changeCounter(-1);
		this.message(`Velky Jazykovy Model repeated ${last.card.data.name}.`);
		if (source.counter <= 0) this.banishEffectTarget(source);
	}

	private canRepeatLastAbility(card: CardInstance): boolean {
		if (card.data.id === "velky_jazykovy_model") return false;
		if (!this.findCardOwnerOrZoneOwner(card)) return false;
		if (card.zone === "banished") return false;
		if (card.zone === "graveyard" && card.data.type !== "Spell") return false;
		return true;
	}

	async complexVelkeJazykoveMonstrum(source: CardInstance, effect: CardEffect): Promise<void> {
		switch (effect.trigger) {
			case "deploy":
				source.abilityState["monster_slots"] = [];
				await this.chooseMonsterSlots(source);
				break;
			case "turn_end": {
				const slots = (source.abilityState["monster_slots"] ?? []) as MonsterSlot[];
				if (slots.length === 0) {
					this.message("Jazykove Monstrum has no chosen slots.");
					return;
				}
				const rollIdx = this.game.rng.randi(Math.min(3, slots.length - 1) + 1);
				const slot = slots[rollIdx]!;
				const player = this.game.players.find((p) => p.playerId === slot.playerId);
				if (!player) return;
				const target = getCardAt(player, slot.row, slot.col);
				if (!target || target.data.type !== "Unit") {
					this.message("Jazykove Monstrum rolled an empty slot.");
					return;
				}
				target.applyStatus("Poison", 1);
				this.events.emit("status_applied", { target, statusName: "Poison", stacks: 1 });
				await this.applyDamage(source, target, 1);
				break;
			}
		}
	}

	private async chooseMonsterSlots(source: CardInstance): Promise<void> {
		const selected = (source.abilityState["monster_slots"] ?? []) as MonsterSlot[];
		while (selected.length < 4) {
			const options: { label: string; description: string; value: MonsterSlot }[] = [];
			for (const player of this.game.players) {
				for (let rowIdx = 0; rowIdx < Constants.ROW_CAPACITIES.length; rowIdx++) {
					for (let colIdx = 0; colIdx < Constants.ROW_CAPACITIES[rowIdx]!; colIdx++) {
						const slot: MonsterSlot = { playerId: player.playerId, row: rowIdx, col: colIdx };
						if (selected.some((s) => s.playerId === slot.playerId && s.row === slot.row && s.col === slot.col)) continue;
						options.push({
							label: `${player.playerId === source.controllerId ? "Your" : "Opponent"} ${ROW_LABELS[rowIdx] ?? "Artillery"} ${colIdx + 1}`,
							description: "Mark this slot for the monster effect.",
							value: slot,
						});
					}
				}
			}
			const slot = await this.game.interaction.requestChoice(`Choose slot ${selected.length + 1}/4`, options);
			selected.push(slot);
			source.abilityState["monster_slots"] = selected;
		}
		this.message("Jazykove Monstrum marked 4 slots.");
	}

	async complexNakMitchrbat(source: CardInstance): Promise<void> {
		const player = this.getController(source);
		if (!player) return;
		const cards = player.getAllBoardUnits();
		if (cards.length < 2) {
			this.message("Need two own cards to rearrange.");
			return;
		}
		const first = await this.requestTarget(source, null, cards, "Swap: first card");
		if (!first) return;
		const second = await this.requestTarget(source, null, cards.filter((c) => c !== first), "Swap: second card");
		if (!second) return;
		if (player.swapBoardPositions(first, second)) {
			this.message(`Swapped ${first.data.name} and ${second.data.name}.`);
		}
	}

	createCardInHand(player: PlayerState, cardId: string): CardInstance | null {
		const data = this.game.db.getCard(cardId);
		if (!data) return null;
		const card = CardInstance.create(data, player.playerId);
		card.zone = "hand";
		player.addToHand(card);
		this.events.emit("card_drawn", { card, playerId: player.playerId, source: "neutral" });
		return card;
	}
}

interface MonsterSlot {
	playerId: number;
	row: number;
	col: number;
}

const ROW_LABELS: Record<number, string> = { 0: "Melee", 1: "Ranged", 2: "Artillery" };

const EMPTY_EFFECT: CardEffect = {
	type: "complex",
	trigger: "passive",
	value: 0,
	status: "",
	stacks: 0,
	timerValue: 0,
	upkeepCost: 0,
	tributeCost: 0,
	hoardThreshold: 0,
	payCost: 0,
	initialCharges: 0,
	charges: 0,
	maxCharges: 0,
	counterDelta: 0,
	counterThreshold: 0,
	maxUsesPerTurn: 0,
	permanentStatus: false,
	targetScope: "enemy",
	targetKind: "card",
	area: false,
	requiresTarget: true,
	rawText: "",
};

type ComplexHandler = (resolver: EffectResolver, source: CardInstance, effect: CardEffect) => Promise<void>;

const COMPLEX_HANDLERS: Record<string, ComplexHandler> = {
	accountant_pro_max: (r, s) => r.complexAccountantProMax(s),
	carry_on: (r, s) => r.complexCarryOn(s),
	catch_up: (r, s) => r.complexCatchUp(s),
	hhmds: (r, s) => r.complexHhmds(s),
	individual_sailor: (r, s) => r.complexIndividualSailor(s),
	sir_vant: (r, s, e) => r.complexSirVant(s, e),
	s_ibal: (r, s) => r.complexSibal(s),
	knight: (r, s) => r.complexKnight(s),
	tax_er: (r, s) => r.complexTaxEr(s),
	fukacia_pracicka: (r, s) => r.complexFukaciaPracicka(s),
	everything_here_here: (r, s) => r.complexEverythingHereHere(s),
	sibal_so_sledovanim_lucov: (r, s) => r.complexSibalSoSledovanimLucov(s),
	endest_pearl_incident: (r, s) => r.complexEndestPearlIncident(s),
	the_lion_does_not_care: (r, s) => r.complexTheLionDoesNotCare(s),
	sir_vival: (r, s, e) => r.complexSirVival(s, e),
	biblography: (r, s, e) => r.complexBiblography(s, e),
	the_prophet: (r, s, e) => r.complexTheProphet(s, e),
	opakovacia_dedinka: (r, s) => r.complexOpakovaciaDedinka(s),
	breakthru: (r, s) => r.complexBreakthru(s),
	dawood: (r, s) => r.complexDawood(s),
	discard_this_card: (r, s) => r.complexDiscardThisCard(s),
	claws_the_production: (r, s) => r.complexClawsTheProduction(s),
	my_country_called_me: (r, s) => r.complexMyCountryCalledMe(s),
	negromancy: (r, s) => r.complexNegromancy(s, ["Common", "Rare"]),
	negromancy_premium: (r, s) => r.complexNegromancy(s, ["Epic", "Legendary"]),
	sellers_sailors: (r, s) => r.complexSellersSailors(s),
	premium_account: (r, s, e) => r.complexPremiumAccount(s, e),
	scrolling_papers: (r, s) => r.complexScrollingPapers(s),
	damina: (r, s, e) => r.complexDamina(s, e),
	trembling_lips: (r, s, e) => r.complexTremblingLips(s, e),
	miss_spell: (r, s) => r.complexMissSpell(s),
	mikrofo_novy_pokles: (r, s) => r.complexMikrofoNovyPokles(s),
	the_why_axes: (r, s) => r.complexTheWhyAxes(s),
	sir_veillance: (r, s) => r.complexSirVeillance(s),
	obratnost_ruk: (r, s) => r.complexObratnostRuk(s),
	mr_rural: (r, s, e) => r.complexMrRural(s, e),
	velky_jazykovy_model: (r, s, e) => r.complexVelkyJazykovyModel(s, e),
	velke_jazykove_monstrum: (r, s, e) => r.complexVelkeJazykoveMonstrum(s, e),
	nak_mitchrbat: (r, s) => r.complexNakMitchrbat(s),
	masovystit: async () => {}, // redirect handled in onDamageDealt
};
