# Factions and diplomacy

## Fit with spec §7

§7 already has 4–6 factions with personalities (trader collective, militarist dominion, isolationist league,
expansionist empire), real AI economies, a **relation** and a **tension** score between every pair of factions
(AIs included), the diplomatic actions (trade deal, non-aggression pact, alliance, tribute, war, peace), tension
drivers (borders, competing claims, broken deals, build-ups, personality) and a Factions tab. The ideas below add to
it; nothing replaces it. **[Claude's call]** on how they join up:

- **The memory list explains the scores.** Each entry moves relation, tension or both, so the Factions tab can show
  *why* the bars are where they are.
- **Relation stages are bands of §7's relation score.** Tension is what pushes a faction down the stages toward war.
- **Personality examples below use §7's four types.** "Merchant" means the trader collective.
- **§7's alliance (mutual defense)** is the ally who defends you in hardcore (03).
- **§6.6's peaceful routes to planets** (buying claims, diplomatic cession) are what the "sells off a planet"
  opening (01) uses.

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
