// Port of scripts/autoloads/event_bus.gd — typed event emitter.
// Signal names kept snake_case for 1:1 traceability with GDScript.
// UI-only signals (card_selected, card_hovered, card_detail_requested) stay UI-side.
// target_requested / choice_requested became InteractionHandler (interaction.ts):
// the engine awaits a Promise instead of passing a callback.

import type { CardEffect } from "./types";
import type { CardInstance } from "./cardInstance";
import type { TurnPhase } from "./constants";

export interface EngineEvents {
	// Game flow
	game_started: { playerIds: number[] };
	game_ended: { winnerId: number };
	turn_started: { playerId: number; turnNumber: number };
	turn_ended: { playerId: number };
	phase_changed: { phase: TurnPhase; playerId: number };

	// Card actions
	card_played: { card: CardInstance; playerId: number };
	card_drawn: { card: CardInstance; playerId: number; source: "neutral" | "faction" };
	card_discarded: { card: CardInstance; playerId: number };
	card_destroyed: { card: CardInstance; source: CardInstance | null };
	card_banished: { card: CardInstance };
	card_moved: { card: CardInstance; fromZone: string; toZone: string };

	// Combat / effects
	damage_dealt: { target: CardInstance; amount: number; source: CardInstance | null };
	heal_applied: { target: CardInstance; amount: number };
	boost_applied: { target: CardInstance; amount: number };
	status_applied: { target: CardInstance; statusName: string; stacks: number };
	status_removed: { target: CardInstance; statusName: string };
	status_triggered: { target: CardInstance; statusName: string };

	// Economy
	sellary_gained: { playerId: number; amount: number };
	sellary_spent: { playerId: number; amount: number };
	sellary_seized: { fromId: number; toId: number; amount: number };

	// Board
	card_placed_on_board: { card: CardInstance; row: number; col: number };
	card_removed_from_board: { card: CardInstance };

	// Abilities
	ability_triggered: { card: CardInstance; effect: CardEffect };
	deploy_triggered: { card: CardInstance };
	last_word_triggered: { card: CardInstance };
	deathblow_triggered: { card: CardInstance; killed: CardInstance };
	timer_expired: { card: CardInstance };

	// Messages
	message_shown: { text: string };
}

export type EventName = keyof EngineEvents;
export type EventHandler<E extends EventName> = (payload: EngineEvents[E]) => void;

export class EventBus {
	private handlers = new Map<EventName, Set<EventHandler<EventName>>>();

	on<E extends EventName>(event: E, handler: EventHandler<E>): () => void {
		let set = this.handlers.get(event);
		if (!set) {
			set = new Set();
			this.handlers.set(event, set);
		}
		set.add(handler as EventHandler<EventName>);
		return () => set.delete(handler as EventHandler<EventName>);
	}

	off<E extends EventName>(event: E, handler: EventHandler<E>): void {
		this.handlers.get(event)?.delete(handler as EventHandler<EventName>);
	}

	emit<E extends EventName>(event: E, payload: EngineEvents[E]): void {
		const set = this.handlers.get(event);
		if (set) {
			for (const handler of [...set]) {
				handler(payload);
			}
		}
		for (const handler of [...this.anyHandlers]) {
			handler(event, payload);
		}
	}

	/** Subscribe to every event — for logging / debugging / UI refresh. */
	onAny(handler: (event: EventName, payload: unknown) => void): () => void {
		this.anyHandlers.add(handler);
		return () => this.anyHandlers.delete(handler);
	}

	private anyHandlers = new Set<(event: EventName, payload: unknown) => void>();
}
