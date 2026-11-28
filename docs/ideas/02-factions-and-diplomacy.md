# Factions and diplomacy

**[Check]** Spec §7 (factions and diplomacy) was not read for this brainstorm. Reconcile before building.

## What the owner wants **[Owner]**

- Factions **remember** what you did. Example: if you sell armor to Halden during its war with Vey, Vey holds that
  against you.

## Memory and reactions **[Claude, owner liked]**

- **Each faction keeps a short, readable memory list,** for example "Sold armor to our enemy Halden (−12)" or "Ran
  our famine relief (+20)". You can always see why a faction feels the way it does.
- **Personalities decide what they care about.**
  - A militarist faction resents arms sales to its enemies.
  - A merchant faction mostly doesn't care who you trade with, but hates broken contracts.
  - The same act plays differently with different factions.
- **You see the reaction before you commit:** "Vey −10, Halden +15" on the deal itself. You can still make
  enemies, but only knowingly.
- **Grudges fade slowly unless renewed,** so a day-3 mistake isn't forever. Difficulty sets how slowly (03).

## Relation stages **[Claude, owner liked]**

| Stage | Effect |
|---|---|
| Friendly | Better prices, shared patrols, may defend you (see 03, hardcore) |
| Neutral | Normal trade |
| Cool | Worse prices |
| Hostile | Closed lanes, no deals |
| War | Only if the war toggle allows factions to declare war on you (03), or you declare it |

- **Each step down appears in the news first.** Nothing goes from friendly to war overnight.

## Notes for the builder **[Claude's call]**

- Memory entries are typed events with a weight and a decay rate, so the AI and the UI read the same list.
- AI-to-AI relations use the same system. That's what produces the news in 01.
- Intel (05) can be sold to a faction for credits and goodwill.
