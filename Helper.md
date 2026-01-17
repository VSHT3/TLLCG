---
cssclasses:
  - big-latex
---


# RNG
## Coinflip
![[coin-flip.mp3]]


```dataviewjs
// CONFIG
const totalDuration = 2500;          // ms for progress bar
const barLength     = 20;            // characters
const spinnerChars  = ["/", "-", "\\", "-"];
const audioPath     = "coin-flip.mp3"; // vault path or URL

function easeOutQuad(t) {
  return 1 - (1 - t) * (1 - t);
}

// ROOT
const root = dv.el("div", "", {
  attr: { style: "font-family: monospace; white-space: pre;" }
});

// BUTTONS WRAPPER
const controls = dv.el("div", "", {
  attr: { style: "margin-bottom: 0.5rem;" }
});
root.appendChild(controls);

const flipBtn  = dv.el("button", "Flip coin");
const resetBtn = dv.el("button", "Reset");
flipBtn.style.marginRight = "0.5rem";
controls.appendChild(flipBtn);
controls.appendChild(resetBtn);

// OUTPUT LINES
const barLine     = dv.el("div", "");
const spinnerLine = dv.el("div", "");
const resultLine  = dv.el("div", "");
root.appendChild(barLine);
root.appendChild(spinnerLine);
root.appendChild(resultLine);

// STATE
let progressTimer = null;
let spinnerTimer  = null;

// HELPERS
function hideControls() {
  controls.style.display = "none";
}

function showControls() {
  controls.style.display = "block";
}

function stopTimers() {
  if (progressTimer !== null) {
    clearInterval(progressTimer);
    progressTimer = null;
  }
  if (spinnerTimer !== null) {
    clearInterval(spinnerTimer);
    spinnerTimer = null;
  }
}

function renderColoredBar(progress) {
  const eased = easeOutQuad(progress);
  const filledCount = Math.round(eased * barLength);
  const emptyCount  = barLength - filledCount;

  const filled = "=".repeat(filledCount);
  const empty  = " ".repeat(emptyCount);

  let color;
  if (eased < 0.33)      color = "#4caf50";
  else if (eased < 0.66) color = "#ffc107";
  else                   color = "#f44336";

  if (eased >= 1) {
    // Whole bar red including closing bracket
    barLine.innerHTML =
      `<span style="color:#f44336;">[${"=".repeat(barLength)}]</span> 100%`;
  } else {
    const html =
      `<span style="color:${color};">[${filled}</span>` +
      `${empty ? `<span style="color:#888;">${empty}</span>` : ""}` +
      `] ${Math.round(eased * 100)}%`;
    barLine.innerHTML = html;
  }
}

function startSpinner() {
  let idx = 0;
  spinnerLine.textContent = spinnerChars[idx];
  spinnerTimer = setInterval(() => {
    idx = (idx + 1) % spinnerChars.length;
    spinnerLine.textContent = spinnerChars[idx];
  }, 120);
}

function stopSpinner() {
  if (spinnerTimer !== null) {
    clearInterval(spinnerTimer);
    spinnerTimer = null;
  }
  spinnerLine.textContent = "";
}

function playSound() {
  try {
    const audio = new Audio(audioPath);
    audio.play();
  } catch (e) {
    console.error("Audio play failed:", e);
  }
}

function resetView() {
  stopTimers();
  barLine.textContent     = "";
  spinnerLine.textContent = "";
  resultLine.textContent  = "";
  showControls();
}

// EVENTS
flipBtn.addEventListener("click", (e) => {
  e.preventDefault();
  stopTimers();
  resetView();
  hideControls();       // hide buttons during flip
  playSound();

  const start = Date.now();
  startSpinner();

  progressTimer = setInterval(() => {
    const elapsed  = Date.now() - start;
    const progress = Math.min(elapsed / totalDuration, 1);

    renderColoredBar(progress);

    if (progress >= 1) {
      clearInterval(progressTimer);
      progressTimer = null;
      stopSpinner();

      const result = Math.random() < 0.5 ? "Heads" : "Tails";
      resultLine.textContent = `Result: ${result}`;
      showControls();   // show buttons again after result
    }
  }, 60);
});

resetBtn.addEventListener("click", (e) => {
  e.preventDefault();
  resetView();
});

```

### Dice
`dice: d20|render`




___
```dataviewjs
// CONFIG
const TAG = "Card";
const RARITY_FIELD = "Card Rarity";
const FACTION_FIELD = "Card Faction";
const TARGET_FACTION = "Neutral";
const STORAGE_KEY = "obsidian-card-draw-v5";

const HELPER_FILE_NAME = "Helper";      // note name, e.g. "Helper"
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
resetBtn.textContent = "Reset deck";
resetBtn.addEventListener("click", () => {
  clearState();
  state = {};
  deck = buildDeck(state);
  info.textContent = `Cards remaining in deck: ${deck.length}`;
});
btnRow.appendChild(resetBtn);

```


#### Last Draw
