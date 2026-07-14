// Seam between GameState (turn flow, triggers) and EffectResolver (effect execution).
// GDScript wired these via EventBus.ability_triggered + a listening resolver node;
// here GameState awaits the resolver directly so async targeting stays causal.
// GameState still emits ability_triggered on the EventBus as a notification.

import type { CardEffect } from "./types";
import type { CardInstance } from "./cardInstance";

export interface AbilityResolver {
	resolveAbility(source: CardInstance, effect: CardEffect): Promise<void>;
	/**
	 * Awaited after every damage_dealt emission, BEFORE the kill check —
	 * mirrors the Godot sync bus listener (masovystit redirect can heal the
	 * target back and thereby prevent the death).
	 */
	onDamageDealt?(target: CardInstance, amount: number, source: CardInstance | null): Promise<void>;
}

/** No-op resolver for state-layer tests. */
export const NULL_RESOLVER: AbilityResolver = {
	async resolveAbility(): Promise<void> {},
};
