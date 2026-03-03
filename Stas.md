
```dataviewjs
function countByFaction(faction) {
  return dv.pages()
    .where(p => p["Card Faction"] == faction)
    .length;
}

function countByFactionWithoutAbility(faction) {
  return dv.pages()
    .where(p => p["Card Faction"] == faction)
    .where(p => !p.Ability)   // Ability is unchecked / false / missing
    .length;
}

const factions = [
  "Neutral",
  "Abeer Dawood Salman",
  "Sir Can",
  "The Plague",
  "A.I. Gods"
];

for (let f of factions) {
  const total = countByFaction(f);
  const noAbility = countByFactionWithoutAbility(f);
  dv.paragraph(`${f}: ${total} (without Ability: ${noAbility})`);
}
```
