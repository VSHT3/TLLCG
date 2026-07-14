// Seeded RNG for deterministic tests and replayable games.
// GDScript used global shuffle()/randi(); the engine takes an injected Rng.

export interface Rng {
	/** Random int in [0, n). */
	randi(n: number): number;
	/** Random float in [0, 1). */
	randf(): number;
}

/** mulberry32 — small, fast, good enough for card shuffling. */
export function createRng(seed: number): Rng {
	let state = seed >>> 0;
	const randf = (): number => {
		state = (state + 0x6d2b79f5) >>> 0;
		let t = state;
		t = Math.imul(t ^ (t >>> 15), t | 1);
		t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
		return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
	};
	return {
		randf,
		randi: (n: number) => Math.floor(randf() * n),
	};
}

/** In-place Fisher–Yates shuffle. */
export function shuffle<T>(array: T[], rng: Rng): void {
	for (let i = array.length - 1; i > 0; i--) {
		const j = rng.randi(i + 1);
		const tmp = array[i]!;
		array[i] = array[j]!;
		array[j] = tmp;
	}
}
