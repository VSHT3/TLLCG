// Bridges the engine's awaited InteractionHandler to React: each request parks
// a Promise.withResolvers() and publishes the pending request for the UI to
// render; clicking a target/option resolves it.

import type { CardInstance } from "@engine/cardInstance";
import type { ChoiceOption, InteractionHandler, TargetRequest } from "@engine/interaction";

export interface PendingTarget {
	kind: "target";
	request: TargetRequest;
	resolve: (target: CardInstance | null) => void;
}

export interface PendingChoice {
	kind: "choice";
	prompt: string;
	options: ChoiceOption<unknown>[];
	resolve: (value: unknown) => void;
}

export interface PendingPanel {
	kind: "panel";
	title: string;
	items: string[];
	resolve: () => void;
}

export type PendingInteraction = PendingTarget | PendingChoice | PendingPanel;

export class UiInteractionHandler implements InteractionHandler {
	private publish: (pending: PendingInteraction | null) => void;

	constructor(publish: (pending: PendingInteraction | null) => void) {
		this.publish = publish;
	}

	requestTarget(request: TargetRequest): Promise<CardInstance | null> {
		const { promise, resolve } = Promise.withResolvers<CardInstance | null>();
		this.publish({
			kind: "target",
			request,
			resolve: (target) => {
				this.publish(null);
				resolve(target);
			},
		});
		return promise;
	}

	requestChoice<T>(prompt: string, options: ChoiceOption<T>[]): Promise<T> {
		const { promise, resolve } = Promise.withResolvers<T>();
		this.publish({
			kind: "choice",
			prompt,
			options: options as ChoiceOption<unknown>[],
			resolve: (value) => {
				this.publish(null);
				resolve(value as T);
			},
		});
		return promise;
	}

	showPanel(title: string, items: string[]): Promise<void> {
		const { promise, resolve } = Promise.withResolvers<void>();
		this.publish({
			kind: "panel",
			title,
			items,
			resolve: () => {
				this.publish(null);
				resolve();
			},
		});
		return promise;
	}
}
