// Port of scripts/autoloads/game_constants.gd (autoload singleton → module object).
// Defaults match GDScript; loadRules() overrides from data/rules.json.

export enum TurnPhase {
	SELLARY,
	START_OF_TURN,
	PLAY_CARDS,
	DISCARD_CARDS,
	DRAW_CARDS,
	END_OF_TURN,
	STATUS_TRIGGER,
	STATUS_DIMINISH,
}

export const PHASE_NAMES: Record<TurnPhase, string> = {
	[TurnPhase.SELLARY]: "Sellary",
	[TurnPhase.START_OF_TURN]: "Start of Turn",
	[TurnPhase.PLAY_CARDS]: "Play Cards",
	[TurnPhase.DISCARD_CARDS]: "Discard Cards",
	[TurnPhase.DRAW_CARDS]: "Draw Cards",
	[TurnPhase.END_OF_TURN]: "End of Turn",
	[TurnPhase.STATUS_TRIGGER]: "Status Trigger",
	[TurnPhase.STATUS_DIMINISH]: "Status Diminish",
};

export const ROW_MELEE = 0;
export const ROW_RANGED = 1;
export const ROW_ARTILLERY = 2;

export interface RulesJson {
	hero_base_hp?: number;
	base_sellary_per_turn?: number;
	max_cards_per_turn?: number;
	max_hand_size?: number;
	neutral_draw_base_cost?: number;
	neutral_draw_extra_cost?: number;
	faction_draw_base_cost?: number;
	faction_draw_extra_cost?: number;
	row_capacities?: number[];
}

export const Constants = {
	HERO_BASE_HP: 30,
	BASE_SELLARY: 5,
	MAX_CARDS_PER_TURN: 2,
	MAX_HAND_SIZE: 10,
	NEUTRAL_DRAW_BASE_COST: 3,
	NEUTRAL_DRAW_EXTRA_COST: 1,
	FACTION_DRAW_BASE_COST: 4,
	FACTION_DRAW_EXTRA_COST: 1,
	ROW_CAPACITIES: [5, 5, 3] as number[],
	ROW_NAMES: ["melee", "ranged", "artillery"] as string[],
	get TOTAL_BOARD_SLOTS(): number {
		return this.ROW_CAPACITIES.reduce((a, b) => a + b, 0);
	},
};

export function loadRules(rules: RulesJson): void {
	Constants.HERO_BASE_HP = rules.hero_base_hp ?? Constants.HERO_BASE_HP;
	Constants.BASE_SELLARY = rules.base_sellary_per_turn ?? Constants.BASE_SELLARY;
	Constants.MAX_CARDS_PER_TURN = rules.max_cards_per_turn ?? Constants.MAX_CARDS_PER_TURN;
	Constants.MAX_HAND_SIZE = rules.max_hand_size ?? Constants.MAX_HAND_SIZE;
	Constants.NEUTRAL_DRAW_BASE_COST = rules.neutral_draw_base_cost ?? Constants.NEUTRAL_DRAW_BASE_COST;
	Constants.NEUTRAL_DRAW_EXTRA_COST = rules.neutral_draw_extra_cost ?? Constants.NEUTRAL_DRAW_EXTRA_COST;
	Constants.FACTION_DRAW_BASE_COST = rules.faction_draw_base_cost ?? Constants.FACTION_DRAW_BASE_COST;
	Constants.FACTION_DRAW_EXTRA_COST = rules.faction_draw_extra_cost ?? Constants.FACTION_DRAW_EXTRA_COST;
	if (rules.row_capacities) {
		Constants.ROW_CAPACITIES = rules.row_capacities.map((c) => Math.trunc(c));
	}
}
