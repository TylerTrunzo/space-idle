# Exploration

Builds on spec §13.2 (unsurveyed bodies; explorers find new systems).

## What the owner wants **[Owner]**

An explorer coming back is exciting when it brings:
- new leads on different planets;
- floating debris with random stuff in it;
- new intel;
- a new deposit of a resource;
- and so on.

## What explorers find **[Claude, owner liked]**

| Find | What it gives |
|---|---|
| Survey (§13.2) | A body's deposits and richness, before you claim it |
| New system (§13.2) | The galaxy grows |
| Lead | A faint signal pointing farther out. Following it takes another trip, sometimes a chain of a few, ending in something good: a wreck, a rich world, a lost station. **Leads never expire.** |
| Debris / derelict | Salvage: raw materials, credits, rare items |
| Blueprint (in salvage) | Module variants you can't get any other way (a lighter tank, a long-range scanner). Ties exploration to ship design (04). |
| Intel | A pirate base's location, a faction's fleet movements or planned expansion. Use it, or sell it to a faction for credits and goodwill (02). |
| Rare deposit | Resources not found in your home region |

- **Explorer design matters.** Scanner strength sets how much you find. Tank size sets how far you reach (04).
- **A standing order, "explore the frontier,"** keeps explorers working while you're away. It never becomes a chore.
- **Factions explore too.** Racing a faction to a rich find you both spotted becomes news, with an opening attached
  (01).
- **Each find shows up in the news digest** as an opening.

## Notes for the builder **[Claude's call]**

- Finds roll from the seeded RNG, so runs stay deterministic and `game_sim` can measure find rates.
- Lead chains are short (2–4 steps), and the end reward is shown as a rough tier ("faint", "strong signal") up
  front.
