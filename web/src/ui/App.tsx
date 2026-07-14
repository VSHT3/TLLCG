import { useCallback, useMemo, useRef, useState } from "react";
import { GameState } from "@engine/gameState";
import { EffectResolver } from "@engine/effectResolver";
import { EventBus } from "@engine/events";
import { createRng } from "@engine/rng";
import { Constants, TurnPhase, PHASE_NAMES } from "@engine/constants";
import type { CardInstance } from "@engine/cardInstance";
import type { PlayerState } from "@engine/playerState";
import { createDefaultDatabase } from "../data";
import { UiInteractionHandler, type PendingInteraction } from "./uiInteraction";

const db = createDefaultDatabase();
const ROW_NAMES = ["Melee", "Ranged", "Artillery"];

interface Session {
	game: GameState;
	events: EventBus;
}

export function App() {
	const [session, setSession] = useState<Session | null>(null);
	const [, setVersion] = useState(0);
	const [pending, setPending] = useState<PendingInteraction | null>(null);
	const [messages, setMessages] = useState<string[]>([]);
	const busyRef = useRef(false);

	const rerender = useCallback(() => setVersion((v) => v + 1), []);

	const startGame = useCallback(
		(factionA: string, factionB: string, firstPlayer: number, seed: number) => {
			const events = new EventBus();
			const interaction = new UiInteractionHandler(setPending);
			const game = new GameState(db, events, createRng(seed), interaction);
			game.resolver = new EffectResolver(game);
			events.on("message_shown", ({ text }) => {
				setMessages((prev) => [...prev.slice(-99), text]);
			});
			events.onAny(rerender);
			game.setupGame([factionA, factionB], firstPlayer);
			setSession({ game, events });
			void game.startTurn();
		},
		[rerender],
	);

	/** Serialize engine actions — one at a time, re-render after. */
	const act = useCallback(
		async (action: () => Promise<unknown>) => {
			if (busyRef.current) return;
			busyRef.current = true;
			try {
				await action();
			} finally {
				busyRef.current = false;
				rerender();
			}
		},
		[rerender],
	);

	if (!session) return <SetupScreen onStart={startGame} />;
	return <GameScreen game={session.game} pending={pending} messages={messages} act={act} />;
}

function SetupScreen({ onStart }: { onStart: (a: string, b: string, first: number, seed: number) => void }) {
	const factions = useMemo(() => db.getPlayableFactions(), []);
	const [factionA, setFactionA] = useState(factions[0] ?? "");
	const [factionB, setFactionB] = useState(factions[1] ?? "");
	const [first, setFirst] = useState(0);

	return (
		<div className="setup">
			<h1>TLLCG</h1>
			<div className="setup-row">
				<label>
					Player 1
					<select value={factionA} onChange={(e) => setFactionA(e.target.value)}>
						{factions.map((f) => (
							<option key={f}>{f}</option>
						))}
					</select>
				</label>
				<label>
					Player 2
					<select value={factionB} onChange={(e) => setFactionB(e.target.value)}>
						{factions.map((f) => (
							<option key={f}>{f}</option>
						))}
					</select>
				</label>
				<label>
					First player
					<select value={first} onChange={(e) => setFirst(Number(e.target.value))}>
						<option value={0}>Player 1</option>
						<option value={1}>Player 2</option>
					</select>
				</label>
			</div>
			<button className="primary" onClick={() => onStart(factionA, factionB, first, Date.now() >>> 0)}>
				Start game
			</button>
		</div>
	);
}

interface GameScreenProps {
	game: GameState;
	pending: PendingInteraction | null;
	messages: string[];
	act: (action: () => Promise<unknown>) => Promise<void>;
}

function GameScreen({ game, pending, messages, act }: GameScreenProps) {
	const [selected, setSelected] = useState<CardInstance | null>(null);
	const current = game.getCurrentPlayer();
	const opponent = game.players.find((p) => p !== current)!;
	const targetSet = pending?.kind === "target" ? new Set(pending.request.validTargets) : null;

	const onHandCardClick = (card: CardInstance) => {
		if (pending) return;
		if (card.data.type === "Spell") {
			void act(() => game.playCard(current, card));
			setSelected(null);
		} else {
			setSelected(selected === card ? null : card);
		}
	};

	const onSlotClick = (player: PlayerState, row: number, col: number) => {
		if (pending || !selected || player !== current) return;
		const card = selected;
		setSelected(null);
		void act(() => game.playCard(current, card, row, col));
	};

	const onBoardCardClick = (card: CardInstance) => {
		if (pending?.kind === "target" && targetSet?.has(card)) {
			pending.resolve(card);
		}
	};

	return (
		<div className="game">
			<header className="hud">
				<span className="hud-turn">
					Turn {game.turnNumber} — {PHASE_NAMES[game.currentPhase]}
				</span>
				<span className="hud-player">
					{current.factionName} (P{current.playerId + 1}) to move
				</span>
				<span className="hud-sellary">Sellary: {current.sellary}</span>
				<span>
					Plays: {current.cardsPlayedThisTurn}/{Constants.MAX_CARDS_PER_TURN + current.extraCardPlays}
				</span>
				<button
					disabled={!!pending || current.sellary < current.getNeutralDrawCost()}
					onClick={() => void act(() => game.drawNeutral(current))}
				>
					Draw neutral ({current.getNeutralDrawCost()})
				</button>
				<button
					disabled={!!pending || current.sellary < current.getFactionDrawCost() || current.factionDeck.length === 0}
					onClick={() => void act(() => game.drawFaction(current))}
				>
					Draw faction ({current.getFactionDrawCost()})
				</button>
				<button
					className="primary"
					disabled={!!pending || game.currentPhase !== TurnPhase.PLAY_CARDS}
					onClick={() => {
						setSelected(null);
						void act(() => game.endTurn());
					}}
				>
					End turn
				</button>
			</header>

			{game.gameOver && (
				<div className="banner">
					{game.winnerId >= 0 ? `${game.players[game.winnerId]!.factionName} (P${game.winnerId + 1}) wins!` : "Draw!"}
				</div>
			)}

			<main className="battlefield">
				<PlayerSide
					player={opponent}
					mirrored
					targetSet={targetSet}
					onCardClick={onBoardCardClick}
					onSlotClick={onSlotClick}
					canAct={false}
					act={act}
					game={game}
				/>
				<div className="battle-line" />
				<PlayerSide
					player={current}
					mirrored={false}
					targetSet={targetSet}
					onCardClick={onBoardCardClick}
					onSlotClick={onSlotClick}
					canAct={!pending && !game.gameOver}
					act={act}
					game={game}
				/>
			</main>

			<Hand player={current} selected={selected} onCardClick={onHandCardClick} canPlay={game.canPlayCard(current)} />

			<aside className="log">
				{messages.slice(-14).map((m, i) => (
					<div key={i}>{m}</div>
				))}
			</aside>

			{pending?.kind === "target" && (
				<div className="target-bar">
					{pending.request.prompt}
					<button onClick={() => pending.resolve(null)}>Cancel</button>
				</div>
			)}
			{pending?.kind === "choice" && (
				<div className="modal-backdrop">
					<div className="modal">
						<h3>{pending.prompt}</h3>
						{pending.options.map((opt, i) => (
							<button key={i} onClick={() => pending.resolve(opt.value)}>
								<strong>{opt.label}</strong>
								{opt.description && <small>{opt.description}</small>}
							</button>
						))}
					</div>
				</div>
			)}
			{pending?.kind === "panel" && (
				<div className="modal-backdrop">
					<div className="modal">
						<h3>{pending.title}</h3>
						<ul>
							{pending.items.map((item, i) => (
								<li key={i}>{item}</li>
							))}
						</ul>
						<button className="primary" onClick={() => pending.resolve()}>
							OK
						</button>
					</div>
				</div>
			)}
		</div>
	);
}

interface PlayerSideProps {
	player: PlayerState;
	mirrored: boolean;
	targetSet: Set<CardInstance> | null;
	onCardClick: (card: CardInstance) => void;
	onSlotClick: (player: PlayerState, row: number, col: number) => void;
	canAct: boolean;
	act: (action: () => Promise<unknown>) => Promise<void>;
	game: GameState;
}

function PlayerSide({ player, mirrored, targetSet, onCardClick, onSlotClick, canAct, act, game }: PlayerSideProps) {
	const rowOrder = mirrored ? [2, 1, 0] : [0, 1, 2];
	const hero = player.hero;
	return (
		<section className={`side ${mirrored ? "side-top" : "side-bottom"}`}>
			<div className="side-meta">
				<div
					className={`hero ${targetSet?.has(hero!) ? "targetable" : ""}`}
					onClick={() => hero && onCardClick(hero)}
				>
					<strong>{hero?.data.name ?? "—"}</strong>
					<span className="hero-hp">{hero?.currentPower ?? 0} HP</span>
				</div>
				<div className="side-stats">
					P{player.playerId + 1} · {player.factionName} · hand {player.hand.length} · deck {player.factionDeck.length} ·
					grave {player.graveyard.length} · {player.sellary}$
				</div>
			</div>
			{rowOrder.map((row) => (
				<div className="row" key={row}>
					<span className="row-label">{ROW_NAMES[row]}</span>
					{Array.from({ length: Constants.ROW_CAPACITIES[row]! }, (_, col) => {
						const card = player.board[row]!.find((c) => c.boardPosition?.col === col) ?? null;
						return (
							<div
								key={col}
								className={`slot ${card ? "occupied" : "empty"}`}
								onClick={() => (card ? onCardClick(card) : onSlotClick(player, row, col))}
							>
								{card && (
									<BoardCard
										card={card}
										targetable={targetSet?.has(card) ?? false}
										canAct={canAct && card.controllerId === player.playerId}
										act={act}
										game={game}
									/>
								)}
							</div>
						);
					})}
				</div>
			))}
		</section>
	);
}

interface BoardCardProps {
	card: CardInstance;
	targetable: boolean;
	canAct: boolean;
	act: (action: () => Promise<unknown>) => Promise<void>;
	game: GameState;
}

function BoardCard({ card, targetable, canAct, act, game }: BoardCardProps) {
	const statuses = [...card.statuses.entries()].map(([name, stacks]) => `${name} ${stacks}`).join(", ");
	const hasOrder = card.data.effects.some((e) => e.trigger === "order");
	const hasPay = card.data.effects.some((e) => e.trigger === "pay");
	return (
		<div className={`card board-card type-${card.data.type.toLowerCase()} ${targetable ? "targetable" : ""}`} title={db.resolveAbilityText(card.data.abilityText)}>
			<span className="card-name">{card.data.name}</span>
			{card.data.type !== "Artifact" && <span className="card-power">{card.currentPower}</span>}
			{card.block > 0 && <span className="card-block">🛡{card.block}</span>}
			{card.charges > 0 && <span className="card-charges">⚡{card.charges}</span>}
			{card.timer > 0 && <span className="card-timer">⏳{card.timer}</span>}
			{statuses && <span className="card-statuses">{statuses}</span>}
			{canAct && hasOrder && (
				<button className="mini" onClick={(e) => { e.stopPropagation(); void act(() => game.activateOrder(card)); }}>
					Order
				</button>
			)}
			{canAct && hasPay && (
				<button className="mini" onClick={(e) => { e.stopPropagation(); void act(() => game.activatePay(card)); }}>
					Pay
				</button>
			)}
		</div>
	);
}

interface HandProps {
	player: PlayerState;
	selected: CardInstance | null;
	onCardClick: (card: CardInstance) => void;
	canPlay: boolean;
}

function Hand({ player, selected, onCardClick, canPlay }: HandProps) {
	return (
		<footer className="hand">
			{player.hand.map((card) => (
				<div
					key={card.instanceId}
					className={`card hand-card type-${card.data.type.toLowerCase()} ${selected === card ? "selected" : ""} ${canPlay ? "" : "disabled"}`}
					onClick={() => canPlay && onCardClick(card)}
					title={db.resolveAbilityText(card.data.abilityText)}
				>
					<span className="card-name">{card.data.name}</span>
					<span className="card-type">{card.data.type}</span>
					{card.data.type !== "Spell" && card.data.type !== "Artifact" && (
						<span className="card-power">{card.currentPower}</span>
					)}
					<span className="card-text">{db.resolveAbilityText(card.data.abilityText)}</span>
				</div>
			))}
			{player.hand.length === 0 && <em>Hand empty</em>}
		</footer>
	);
}
