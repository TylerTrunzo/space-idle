# Playtest round 3: findings and decisions

Three subagent personas played the stage 1.5 economy:
- **Casual:** 4 check-ins a day, 21 days, seed 1 ([casual.md](round3/casual.md)).
- **Optimizer:** 7 a day, 14 days, seed 2 ([optimizer.md](round3/optimizer.md)).
- **New player:** day 1, seed 3 ([newplayer.md](round3/newplayer.md)).

## 1. What stage 1.5 fixed

| Round-2 problem | Casual | Optimizer | New player |
|---|---|---|---|
| Nothing takes time | Fixed | Fixed early, fades after day 5 | Fixed |
| Content runs out | Better (last new thing day 13) | Better, not fixed (flat from day 9) | Better |
| Crew dominates | Better, still strong | Fixed, now irrelevant late | Better |
| Market floor wall | Mostly fixed | Same wall, new shape (sum of market depths) | Not reached |
| Hidden rules / silent failures | Better, not fixed | Better | Better, not fixed |
| Weak away summary | Better, one serious hole | Mostly fixed | Better |

Best moments in all three: survey reveals, the first contract paying for the first claim, station levels 1–6 as
events, upgrade sprees tripling income, depots multiplying storage, many timers finishing at once.

## 2. What is still wrong, ranked

1. **The game flattens:**
   - Casual: income is flat from day 13, there are 10 contracts-only days out of 21, and they would quit around days
     14–15.
   - Optimizer: income is flat from day 9, and they would quit around day 9.
   - Causes:
     - Income is capped by the sum of market depths.
     - Each station level costs ×3 while the station's market bonus adds only +25%.
     - Slot prices grow ×2.5.
     - No milestones sit between Billionaire and Ten Billion (casual), or after 100B (optimizer).
2. **Station deliveries become a chore late.** Optimizers haul millions of plates by hand. Casuals miss a level
   overnight because they were a few million credits short.
3. **Contracts pay for no effort:**
   - Early, they pay 10–300× market value: 6K at minute 1, 170K for 2 segments.
   - Late, the income floor pays billions for goods lying around.
   - Tiny quantities come from near-zero net flows ("2 drones = 71M").
   - Life-support goods compete with habitats.
   - The quantity cap of 5,000 per order makes late orders trivial.
4. **Silent crew crash.** A housing drop never ranks in the away summary (`lostCreditsPerHour` is null), and housing
   flickers tick to tick.
5. **Hidden logistics rules:**
   - Route stop levels count cargo in flight, which silently throttles a route.
   - A stop level above the destination's storage cap wastes the cargo.
   - Auto-sell's hidden buffer and its fight with contracts.
   - Fractional leftovers in deliveries.
6. **Requirements revealed one failure at a time.** There is no building catalog in the CLI. The full input list
   appears only by failing (the stage 2 catalog fixes this in the app).
7. **The `report` credits-per-second is 2× off,** and drops when you keep goods for the station.
8. **Small items:**
   - a survey project leaks its hidden target's id;
   - "ongoing since 60.5h" reads like a duration;
   - capacity upgrades don't fill crew;
   - "0 free crew" while over-assigned;
   - the empty board shows a "0s" refill;
   - `unknownDef` is returned for a missing upgrade track.

## 3. Decisions (controller, under the owner's "make executive choices")

- **D1. Market depth becomes a lever.**
  - The Orbital Station's depth bonus compounds (×1.2 per level instead of +25% added).
  - Each level's bonus is described in content and shown.
- **D2. A second repeatable megaproject, the Mass Driver.**
  - It is fed by bulk tier 0–2 goods (steel, hull plate, copper wire, water, food), so saturated goods have a purpose.
  - Its bonus is production speed for extractors and tier-1 buildings, compounding per level.
  - It is unlocked by station level 2.
  - The owner's decision to add repeatable megaprojects now already covers this.
- **D3. Auto-delivery to megaprojects.**
  - A per-megaproject toggle feeds it from every owned body each minute.
  - Each body keeps its local demand buffer and the amounts still owed to contracts.
  - An optional credit auto-pay keeps a reserve the player sets.
- **D4. Contracts are reworked:**
  - Quantity is based on gross production over 1–3 h, scaled by tier and capped by storage.
  - The reward is 3× market value at base price, with a floor of 10 minutes of income and a cap of 1 h of income.
  - The very first contract stays generous (onboarding hook).
  - Life-support goods are weighted down.
- **D5. Logistics honesty:**
  - Stop levels count destination stock only.
  - Stop levels are clamped to the destination's storage cap, with a message.
  - Deliveries move whole units.
  - Auto-sell never sells what an open contract still needs, and its buffer shows in `state`.
- **D6. Away summary.**
  - Crew and housing shortages get a credits-lost value, rank first and appear in the headline.
  - Housing before and after is shown.
  - Ongoing problems that got worse are flagged.
  - Waste is shown in credits.
  - One next-goal line is added.
  - Fix the housing flicker.
- **D7. More mid and late milestones:**
  - credits 3B, 30B and 300B;
  - station levels 4, 6, 8 and 10;
  - Mass Driver levels 1, 3 and 5;
  - scaling rate milestones.
  - Slot growth goes from ×2.5 to ×2.0.
- **D8. A CLI `catalog` meta command:** cost, crew, recipe per second and owned hosts for every building. Build replies
  list the full inputs. A `noSales` bottleneck appears when nothing sells.
- **Deferred:**
  - crew mattering late: stage 3 ships need crews;
  - research: stage 3;
  - new systems: stage 5;
  - claim growth stays ×8: casual players had all 7 bodies by day 10, and hidden bodies spread claims out;
  - stage 2 UI items (payback, buy-max, life-support forecast, milestones list): already in the stage 2 plan.

## 4. Pacing targets for the tuning wave (bots, seeds 1–3)

- **Casual:**
  - a milestone or project (not contracts) on ≥ 5 of every 7 days through day 21;
  - no station or Mass Driver gap > 3 days through day 21;
  - income at day 21 ≥ 2× income at day 14.
- **Balanced (optimizer):** income grows ≥ 20% from day 7 to day 14, and ≥ 10% from day 14 to day 21.
- **Contracts:**
  - ≤ 15% of earnings on days 1, 7 and 14 for every bot;
  - no reward above 1 h of income (the first contract excepted).
- **Station pacing:** casual station L1 stays within days 4–6.
