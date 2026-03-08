---
cssclasses:
  - wide-note
---

```dataviewjs
function countByFaction(faction) {
  return dv.pages()
    .where(p => p["Card Faction"] == faction)
    .length;
}

function countByFactionWithoutAbility(faction) {
  return dv.pages()
    .where(p => p["Card Faction"] == faction)
    .where(p => !p.Ability)
    .length;
}

function countByFactionRarityType(faction, rarity, type) {
  return dv.pages()
    .where(p => p["Card Faction"] == faction)
    .where(p => p["Card Rarity"] == rarity)
    .where(p => p["Card Type"] == type)
    .length;
}

const factions = [
  "Neutral",
  "Abeer Dawood Salman",
  "Sir Can",
  "The Plague",
  "A.I. Gods"
];

const rarities = ["Common", "Rare", "Epic", "Legendary"];
const types = ["Unit", "Artifact", "Spell"];

// ---------- Table 1: Faction summary ----------
let summaryRows = [];

for (let f of factions) {
  const total = countByFaction(f);
  const noAbility = countByFactionWithoutAbility(f);

  const common = dv.pages()
    .where(p => p["Card Faction"] == f && p["Card Rarity"] == "Common").length;
  const rare = dv.pages()
    .where(p => p["Card Faction"] == f && p["Card Rarity"] == "Rare").length;
  const epic = dv.pages()
    .where(p => p["Card Faction"] == f && p["Card Rarity"] == "Epic").length;
  const legendary = dv.pages()
    .where(p => p["Card Faction"] == f && p["Card Rarity"] == "Legendary").length;

  const commonPlusRare = common + rare;
  const epicPlusLegendary = epic + legendary;

  summaryRows.push([
    f,
    total,
    noAbility,
    common,
    rare,
    epic,
    legendary,
    commonPlusRare,
    epicPlusLegendary
  ]);
}

dv.table(
  [
    "Faction",
    "Total",
    "Without Ability",
    "Common",
    "Rare",
    "Epic",
    "Legendary",
    "Common+Rare",
    "Epic+Legendary"
  ],
  summaryRows
);

// ---------- Table 2: Faction × Rarity × Type ----------
let detailRows = [];

for (let f of factions) {
  for (let r of rarities) {
    for (let t of types) {
      const count = countByFactionRarityType(f, r, t);
      if (count > 0) {
        detailRows.push([f, r, t, count]);
      }
    }
  }
}

dv.table(
  ["Faction", "Rarity", "Card Type", "Count"],
  detailRows
);

// ---------- Table 3: Overall totals per Card Type ----------
let typeTotalsRows = [];

for (let t of types) {
  const total = dv.pages()
    .where(p => p["Card Type"] == t)
    .length;
  typeTotalsRows.push([t, total]);
}

dv.table(
  ["Card Type", "Total Cards"],
  typeTotalsRows
);

// ---------- Table 4: Card Type × Faction totals ----------
let typeFactionRows = [];

for (let t of types) {
  for (let f of factions) {
    const count = dv.pages()
      .where(p => p["Card Type"] == t)
      .where(p => p["Card Faction"] == f)
      .length;

    if (count > 0) {
      typeFactionRows.push([t, f, count]);
    }
  }
}

dv.table(
  ["Card Type", "Faction", "Count"],
  typeFactionRows
);

```
