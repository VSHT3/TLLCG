import type { CardData, CardDatabaseApi, CardEffect } from "@engine/types";
import { CardInstance } from "@engine/cardInstance";
import { EventBus } from "@engine/events";
import { createRng } from "@engine/rng";
import { GameState } from "@engine/gameState";
import { EffectResolver } from "@engine/effectResolver";
import { AutoInteractionHandler, type ChoiceOption, type InteractionHandler, type TargetRequest } from "@engine/interaction";

export function makeEffect(overrides: Partial<CardEffect> = {}): CardEffect {
	return {
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
		...overrides,
	};
}

export function makeCard(overrides: Partial<CardData> = {}): CardData {
	return {
		id: "test_card",
		name: "Test Card",
		type: "Unit",
		rarity: "Common",
		factions: ["Testers"],
		categories: [],
		basePower: 3,
		hasAbility: true,
		abilityText: "",
		artworkPath: "",
		effects: [],
		...overrides,
	};
}

/** Small fixed card pool: hero + vanilla units per faction, neutral filler. */
export class FakeDb implements CardDatabaseApi {
	cards = new Map<string, CardData>();

	constructor(extra: CardData[] = []) {
		const base: CardData[] = [
			makeCard({ id: "hero_a", name: "Hero A", type: "Hero", rarity: "Hero", factions: ["Alpha"], basePower: 30 }),
			makeCard({ id: "hero_b", name: "Hero B", type: "Hero", rarity: "Hero", factions: ["Beta"], basePower: 30 }),
			makeCard({ id: "grunt_a1", factions: ["Alpha"], name: "Grunt A1" }),
			makeCard({ id: "grunt_a2", factions: ["Alpha"], name: "Grunt A2" }),
			makeCard({ id: "grunt_b1", factions: ["Beta"], name: "Grunt B1" }),
			makeCard({ id: "grunt_b2", factions: ["Beta"], name: "Grunt B2" }),
			makeCard({ id: "n1", factions: ["Neutral"], name: "Neutral 1" }),
			makeCard({ id: "n2", factions: ["Neutral"], name: "Neutral 2" }),
			makeCard({ id: "n3", factions: ["Neutral"], name: "Neutral 3" }),
			makeCard({ id: "n4", factions: ["Neutral"], name: "Neutral 4" }),
			makeCard({ id: "n5", factions: ["Neutral"], name: "Neutral 5" }),
			makeCard({ id: "n6", factions: ["Neutral"], name: "Neutral 6" }),
			makeCard({ id: "n7", factions: ["Neutral"], name: "Neutral 7" }),
			makeCard({ id: "n8", factions: ["Neutral"], name: "Neutral 8" }),
			makeCard({ id: "n9", factions: ["Neutral"], name: "Neutral 9" }),
			makeCard({ id: "n10", factions: ["Neutral"], name: "Neutral 10" }),
			makeCard({ id: "n11", factions: ["Neutral"], name: "Neutral 11" }),
			makeCard({ id: "n12", factions: ["Neutral"], name: "Neutral 12" }),
		];
		for (const card of [...base, ...extra]) {
			this.cards.set(card.id, card);
		}
	}

	getCard(id: string): CardData | null {
		return this.cards.get(id) ?? null;
	}
	getHero(faction: string): CardData | null {
		return [...this.cards.values()].find((c) => c.type === "Hero" && c.factions.includes(faction)) ?? null;
	}
	getCardsByFaction(faction: string): CardData[] {
		return [...this.cards.values()].filter((c) => c.factions.includes(faction));
	}
	getNeutralCards(): CardData[] {
		return this.getCardsByFaction("Neutral");
	}
}

/** Interaction handler with scripted picks; falls back to first option. */
export class ScriptedInteraction extends AutoInteractionHandler {
	targetPicks: ((req: TargetRequest) => CardInstance | null)[] = [];
	choicePicks: unknown[] = [];

	override async requestTarget(request: TargetRequest): Promise<CardInstance | null> {
		const pick = this.targetPicks.shift();
		if (pick) return pick(request);
		return super.requestTarget(request);
	}

	override async requestChoice<T>(prompt: string, options: ChoiceOption<T>[]): Promise<T> {
		if (this.choicePicks.length > 0) {
			const wanted = this.choicePicks.shift();
			const found = options.find((o) => o.value === wanted || o.label === wanted);
			if (found) return found.value;
		}
		return super.requestChoice(prompt, options);
	}
}

export interface TestGame {
	game: GameState;
	resolver: EffectResolver;
	events: EventBus;
	interaction: ScriptedInteraction;
	db: FakeDb;
	log: string[];
}

export function makeGame(opts: { db?: FakeDb; seed?: number; interaction?: InteractionHandler } = {}): TestGame {
	const db = opts.db ?? new FakeDb();
	const events = new EventBus();
	const interaction = (opts.interaction as ScriptedInteraction) ?? new ScriptedInteraction();
	const game = new GameState(db, events, createRng(opts.seed ?? 42), interaction);
	game.resolver = new EffectResolver(game);
	const log: string[] = [];
	events.onAny((event, payload) => {
		log.push(`${event}:${JSON.stringify(payload, (k, v) => (k === "card" || k === "target" || k === "source" || k === "killed" ? (v?.data?.id ?? v) : k === "effect" ? v?.type : v))}`);
	});
	return { game, resolver: game.resolver as EffectResolver, events, interaction, db, log };
}

/** Put a unit straight onto a player's board (bypasses hand/cost). */
export function placeUnit(game: GameState, playerIdx: number, card: CardData, row = 0, col?: number): CardInstance {
	const player = game.players[playerIdx]!;
	const inst = CardInstance.create(card, player.playerId);
	const targetCol = col ?? player.findFreeCol(row);
	if (!player.placeOnBoard(inst, row, targetCol)) throw new Error(`slot ${row},${targetCol} occupied`);
	return inst;
}
