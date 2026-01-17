---
cssclasses:
  - triple-text
---

```dataviewjs
// CONFIG
const TAG = "Card";
const RARITY_FIELD = "Card Rarity";
const FACTION_FIELD = "Card Faction";
const TARGET_FACTION = "Sir Can";
const STORAGE_KEY = "obsidian-card-draw-v5";

const HELPER_FILE_NAME = "Sir Can Deck";      // note name, e.g. "Helper"
const LAST_DRAW_HEADING = "#### Last Draw";  // exact heading text to target

// --- Helpers: state ---
function loadState() {
  try {
    return JSON.parse(localStorage.getItem(STORAGE_KEY)) ?? {};
  } catch (e) {
    return {};
  }
}
function saveState(state) {
  localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
}
function clearState() {
  localStorage.removeItem(STORAGE_KEY);
}

// --- Helpers: metadata ---
function firstLower(value) {
  if (!value) return "";
  if (Array.isArray(value) && value.length > 0) return String(value[0]).toLowerCase();
  return String(value).toLowerCase();
}
function getRarity(page) {
  return firstLower(page[RARITY_FIELD]);
}
function getFaction(page) {
  return firstLower(page[FACTION_FIELD]);
}

// --- Build full card list (filtered) ---
function getAllCards() {
  return dv.pages()
    .where(p => (p.file.tags ?? []).some(t => t === TAG || t === `#${TAG}`))
    .where(p => getFaction(p) === TARGET_FACTION.toLowerCase())
    .where(p => getRarity(p) !== "hero");
}

// --- Build deck from cards + state ---
function buildDeck(state) {
  const cards = getAllCards();
  const deck = [];

  for (let page of cards) {
    const rarity = getRarity(page);
    const path = page.file.path;

    let copies = 1;
    if (rarity === "common" || rarity === "rare") copies = 2;

    let drawnCount = state[path] ?? 0;
    for (let i = drawnCount; i < copies; i++) {
      deck.push(page);
    }
  }

  // Shuffle deck (Fisher–Yates)
  for (let i = deck.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [deck[i], deck[j]] = [deck[j], deck[i]];
  }

  return deck;
}

// --- Helper: write last draw into Helper note under heading ---
async function writeLastDrawToHelper(linkText) {
  const files = app.vault.getMarkdownFiles();
  const helper = files.find(f => f.basename === HELPER_FILE_NAME);
  if (!helper) return;

  const content = await app.vault.read(helper);
  const lines = content.split("\n");

  const headingIndex = lines.findIndex(
    line => line.trim() === LAST_DRAW_HEADING
  );
  if (headingIndex === -1) {
    // If heading not found, append it at the end
    lines.push("", LAST_DRAW_HEADING, linkText);
  } else {
    // Replace everything after heading up to next heading with our single line
    let i = headingIndex + 1;
    while (i < lines.length && !lines[i].startsWith("#")) {
      i++;
    }
    const before = lines.slice(0, headingIndex + 1);
    const after = lines.slice(i);
    lines.length = 0;
    lines.push(...before, linkText, ...after);
  }

  await app.vault.modify(helper, lines.join("\n"));
}

// --- Helper: clear last draw under heading ---
async function clearLastDrawInHelper() {
  const files = app.vault.getMarkdownFiles();
  const helper = files.find(f => f.basename === HELPER_FILE_NAME);
  if (!helper) return;

  const content = await app.vault.read(helper);
  const lines = content.split("\n");

  const headingIndex = lines.findIndex(
    line => line.trim() === LAST_DRAW_HEADING
  );
  if (headingIndex === -1) {
    // Nothing to clear if heading doesn't exist
    return;
  }

  // Remove everything after heading up to next heading
  let i = headingIndex + 1;
  while (i < lines.length && !lines[i].startsWith("#")) {
    i++;
  }
  const before = lines.slice(0, headingIndex + 1);
  const after = lines.slice(i);
  const newLines = [...before, ...after];

  await app.vault.modify(helper, newLines.join("\n"));
}

// --- Initial state & deck ---
let state = loadState();
let deck = buildDeck(state);

// --- UI (simple, no visible result here) ---
const container = dv.el("div", "");

const info = document.createElement("div");
info.textContent = `Cards remaining in deck: ${deck.length}`;
container.appendChild(info);

const btnRow = document.createElement("div");
btnRow.style.marginTop = "0.5rem";
btnRow.style.display = "flex";
btnRow.style.gap = "0.5rem";
btnRow.style.flexWrap = "wrap";
container.appendChild(btnRow);

// --- Draw button ---
const drawBtn = document.createElement("button");
drawBtn.textContent = "Draw";
drawBtn.style.fontSize = "1.5em";      // bigger text
drawBtn.style.padding = "0.5em 1.2em"; // bigger click area
drawBtn.style.borderRadius = "0.4em";  // optional


drawBtn.textContent = "Draw";
drawBtn.addEventListener("click", async () => {
  if (deck.length === 0) {
    new Notice("No cards left to draw.");
    return;
  }

  const idx = Math.floor(Math.random() * deck.length);
  const card = deck[idx];

  const path = card.file.path;
  state[path] = (state[path] ?? 0) + 1;
  saveState(state);

  deck.splice(idx, 1);

  // Use file.name so link is [[Biblography]] instead of path
  const linkText = `[[${card.file.name}]]`;
  await writeLastDrawToHelper(linkText);

  info.textContent = `Cards remaining in deck: ${deck.length}`;
});
btnRow.appendChild(drawBtn);

// --- Reset + shuffle button ---
const resetBtn = document.createElement("button");
resetBtn.style.fontSize = "1.5em"; 
resetBtn.style.padding = "0.5em 1.2em";
resetBtn.style.borderRadius = "0.4em";

resetBtn.textContent = "Reset deck";
resetBtn.addEventListener("click", () => {
  clearState();
  state = {};
  deck = buildDeck(state);
  info.textContent = `Cards remaining in deck: ${deck.length}`;
});
btnRow.appendChild(resetBtn);

// --- Clear Last Draw button ---
const clearLastDrawBtn = document.createElement("button");
clearLastDrawBtn.style.fontSize = "1.5em"; 
clearLastDrawBtn.style.padding = "0.5em 1.2em";
clearLastDrawBtn.style.borderRadius = "0.4em";
clearLastDrawBtn.textContent = "Clear Last Drawd";
clearLastDrawBtn.addEventListener("click", async () => {
  await clearLastDrawInHelper();
  new Notice("Last Draw cleared.");
});
btnRow.appendChild(clearLastDrawBtn);
```


#### Last Draw