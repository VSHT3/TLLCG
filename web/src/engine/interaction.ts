// Player interaction contract — replaces GDScript's callback-based
// EventBus.target_requested / choice_requested signals with Promises.
// The engine awaits these; the UI implements them with real input,
// tests implement them with scripted picks (see test/helpers.ts).

import type { CardEffect } from "./types";
import type { CardInstance } from "./cardInstance";

export interface TargetRequest {
	source: CardInstance;
	effect: CardEffect | null;
	validTargets: CardInstance[];
	prompt: string;
}

export interface ChoiceOption<T = unknown> {
	label: string;
	/** Optional detail line (GDScript "detail"). */
	description?: string;
	value: T;
}

export interface InteractionHandler {
	/** Pick one of validTargets. Resolve null to cancel (GDScript target_cancelled). */
	requestTarget(request: TargetRequest): Promise<CardInstance | null>;
	/** Pick one option (GDScript choice_requested). Must resolve to one option's value. */
	requestChoice<T>(prompt: string, options: ChoiceOption<T>[]): Promise<T>;
	/** Show an informational panel (GDScript ability_panel_requested), e.g. deck peek. */
	showPanel(title: string, items: string[]): Promise<void>;
}

/** Auto-picks the first target/option — for tests and AI-less flows. */
export class AutoInteractionHandler implements InteractionHandler {
	async requestTarget(request: TargetRequest): Promise<CardInstance | null> {
		return request.validTargets[0] ?? null;
	}
	async requestChoice<T>(_prompt: string, options: ChoiceOption<T>[]): Promise<T> {
		if (options.length === 0) throw new Error("requestChoice with no options");
		return options[0]!.value;
	}
	async showPanel(_title: string, _items: string[]): Promise<void> {}
}
