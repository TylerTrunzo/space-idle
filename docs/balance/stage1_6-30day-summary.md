# Stage 1.6: 30-day balance baselines

Generated with `dart run game_sim:game_sim bot --bot <casual|balanced|greedy> --hours 720 --seed 1 --format md`.
The full seed-1 reports are `stage1_6-30day-casual.md`, `stage1_6-30day-balanced.md` and
`stage1_6-30day-greedy.md`. The stage 1.5 files (`stage1_5-30day-*.md`) are kept for comparison.
The seed 2 and 3 numbers below come from 21-day runs of the same bots (a 30-day run is the same as a
21-day one up to day 21).

"Before" is the start of stage 1.6 task 5 (commit e365fd7): stage 1.6 tasks 1-4 done, the bots
delivering to megaprojects by hand. "After" is task 5's content and bots (commit e95f318). The
seed-1 reports, and the first section below, are from after the stage 1.6 final fix wave; the
sections after it describe task 5.

## After the final fix wave

What moved the numbers:

- **Engine.** Credits auto-paid to megaprojects go in after the minute's sales, and stages due by
  the minute complete before the next is paid for (both for step-size invariance). Together they
  move when the bots' stages start by up to a minute, which the optimizer's tightly timed play
  amplifies: reverting just these two brings its seed-1 day 7 back from 29.2B to 40.2B.
- **Contracts** scale their `maxQuantity` by Orbital Station levels only (the Mass Driver sets
  `scalesContracts` false).
- **Bots** pay a stage's credits by hand when they can and keep their hour-of-income reserve (the
  auto reserve only otherwise), and grow a shared good (hull plate) counting what the station still
  lacks of it first.
- **Report.** An event seen at a day's end counts in that day, as the Days table does.

Pacing targets (findings §4), seeds 1 / 2 / 3, task 5 then the fix wave:

| Target | Task 5 | Fix wave | Met |
|---|---|---|---|
| Casual: a milestone or project on 5 of every 7 days, days 1-21 (worst 7 days) | 6 / 5 / 6 | 6 / 5 / 6 (20, 18, 20 of 21 days) | yes |
| Casual: Orbital Station level 1 in days 4-6 | day 6 / 5 / 6 | day 6 / 5 / 6 | yes |
| Casual: Mass Driver level 1 around days 6-8 | day 6 / 8 / 7 | day 6 / 8 / 7 | yes |
| Casual: no gap above 3 days between levels of one megaproject, through day 21 | station 4 / 4 / 4; Mass Driver 4 / 5 / 4 | station 4 / 4 / 5; Mass Driver 4 / 4 / 3 | **no** (accepted) |
| Casual: no gap above 3 days between levels of either megaproject, through day 21 | 2 / 4 / 2 | 2 / 3 / 3 | yes |
| Casual: income on day 21 at least 2× day 14 | 2.61× / 2.56× / 2.67× | 3.66× / 2.90× / 2.93× | yes |
| Balanced: income +20% from day 7 to day 14 | +71% / +59% / +32% | +52% / +109% / +69% | yes |
| Balanced: income +10% from day 14 to day 21 | +30% / +19% / +49% | +40% / +36% / +45% | yes |
| Contracts at most 15% of earnings on days 1, 7 and 14, every bot | highest 14.3% (casual s1 day 1) | highest 14.3% (casual s1 day 1) | yes |

Contract rewards as a share of earnings, days 1 / 7 / 14:

| Bot | s1 | s2 | s3 |
|---|---|---|---|
| casual | 14.3 / 3.3 / 4.1% | 9.3 / 2.9 / 5.1% | 7.6 / 4.0 / 5.1% |
| balanced | 0.2 / 10.0 / 9.3% | 0.9 / 11.8 / 9.3% | 0.9 / 9.0 / 8.7% |
| greedy | 10.9 / 7.7 / 7.4% | 10.8 / 7.7 / 7.4% | 10.1 / 7.7 / 7.4% |


On the days not checked the balanced bot still passes 15% now and then: 16.7% on day 20 (seed 1)
and 15.0% on day 16 (seed 3), when a single large order lands. A 50-minute reward cap (was 1 h)
changed nothing on seed 1 and cost seed 2 its day 14 to day 21 growth (+7%), so the cap stays.

Megaproject levels by day (Orbital Station / Mass Driver at the end of each day):

| Day | Casual s1 | Casual s2 | Casual s3 | Balanced s1 | Balanced s2 | Balanced s3 |
|---:|---:|---:|---:|---:|---:|---:|
| 1 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 |
| 2 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 |
| 3 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 |
| 4 | 0/0 | 0/0 | 0/0 | 3/4 | 2/5 | 4/5 |
| 5 | 0/0 | 1/0 | 0/0 | 5/9 | 5/9 | 8/9 |
| 6 | 1/1 | 1/0 | 1/0 | 6/11 | 7/11 | 8/11 |
| 7 | 1/1 | 1/0 | 1/1 | 6/11 | 8/12 | 8/12 |
| 8 | 2/1 | 2/1 | 2/1 | 6/12 | 8/12 | 9/13 |
| 9 | 2/2 | 2/2 | 2/2 | 6/13 | 9/13 | 9/13 |
| 10 | 2/3 | 2/2 | 2/2 | 6/13 | 9/13 | 9/13 |
| 11 | 2/4 | 3/2 | 3/2 | 6/13 | 9/13 | 10/14 |
| 12 | 3/4 | 3/3 | 3/3 | 6/13 | 10/14 | 10/14 |
| 13 | 3/5 | 3/4 | 3/4 | 7/14 | 10/14 | 10/14 |
| 14 | 4/5 | 3/4 | 3/4 | 8/14 | 10/14 | 10/14 |
| 15 | 4/5 | 4/5 | 3/5 | 8/14 | 10/14 | 10/14 |
| 16 | 4/6 | 4/5 | 4/5 | 8/14 | 10/14 | 10/15 |
| 17 | 4/6 | 4/5 | 4/5 | 8/14 | 10/15 | 11/15 |
| 18 | 5/6 | 5/5 | 4/6 | 8/14 | 11/15 | 11/15 |
| 19 | 5/6 | 5/6 | 4/6 | 8/14 | 11/15 | 11/15 |
| 20 | 5/7 | 5/6 | 4/6 | 9/15 | 11/15 | 11/15 |
| 21 | 5/7 | 5/6 | 5/6 | 9/15 | 11/15 | 11/15 |

Earned by day, seed 1:

| Bot | Day 7 | Day 14 | Day 21 | Day 30 |
|---|---:|---:|---:|---:|
| casual | 7.03M | 71.1M | 260M | 687M |
| balanced | 30.6B | 46.5B | 65.3B | 72.6B |
| greedy | 4.1M | 4.77M | 16.7M | 69.8M |

## What task 5 changed

- **Milestones (56, was 42).** Credits earned 30M, 3B, 30B and 300B; Orbital Station levels 4, 6, 8 and
  10; Mass Driver levels 1, 3 and 5; three rate milestones placed where the casual bot reaches them
  on days 11-18 (station segments 0.03/s, steel 20/s, copper wire 150/s). The values the plan named
  (1 segment/s, 1K steel/s, 500 plates/s) are reached by the optimizer on days 2-4 and never by the
  casual bot by day 21.
- **Extra build slots** cost ×2.0 each (was ×2.5).
- **Mass Driver.** Opens at Orbital Station level 1 (was 2). Costs 2M credits, 5K hull plate, 20K
  copper wire, 10K water and 2K silicon wafers, ×2.3 a level (was 4M credits, 20K steel, 5K plate,
  20K wire, 10K water, 2K food, ×2.5). Food went because habitats eat all a casual player makes;
  steel went because the plate presses that feed the station's hull plates take it all, so the Mass
  Driver waited on it for days. Its bonus is production speed ×1.15 a level for extractors and tier-1
  buildings; it no longer deepens tier 0-1 markets (see below).
- **Orbital Station.** Costs ×2.5 a level (was ×3) and deepens every market ×1.25 a level (was ×1.2).
- **Contracts** pay at least 20 minutes of income (was 10); the 1 h cap and the 3× base-price reward
  are unchanged.
- **Bots** feed every open megaproject on their own: goods from every body, and credits above a
  reserve of 1 h of income while credits are all the stage still lacks. They no longer deliver by
  hand what that covers, nor hold back contract or megaproject goods that the engine's auto-sell
  already holds. When a good a stage lacks would take more than a day to come at today's surplus,
  the balanced and casual bots grow its supply (once per megaproject per decision).

## Pacing targets (findings §4), seeds 1-3

| Target | Before s1 / s2 / s3 | After s1 / s2 / s3 | Met after |
|---|---|---|---|
| Casual: a milestone or project on 5 of every 7 days, days 1-21 (worst 7 days) | 4 / 3 / 4 (16, 15, 16 of 21 days) | 6 / 5 / 6 (19, 19, 19 of 21 days) | yes |
| Casual: Orbital Station level 1 in days 4-6 | day 6 / 6 / 6 | day 6 / 5 / 6 | yes |
| Casual: Mass Driver level 1 around days 6-8 | day 20 / never / 21 | day 6 / 8 / 7 | yes |
| Casual: no gap above 3 days between levels of one megaproject, through day 21 | station 5 / 5 / 5, then nothing for the last 7 / 7 / 6 days; Mass Driver one level at most | station 4 / 4 / 4; Mass Driver 4 / 5 / 4 | **no** |
| Casual: no gap above 3 days between levels of either megaproject, through day 21 (counting the days after the last level) | 6 / 7 / 6 | 2 / 4 / 2 | s1 and s3 |
| Casual: income on day 21 at least 2× day 14 | 3.64× / 4.01× / 4.20× | 2.61× / 2.56× / 2.67× | yes |
| Balanced: income +20% from day 7 to day 14 | +61% / +76% / +49% | +71% / +59% / +32% | yes |
| Balanced: income +10% from day 14 to day 21 | +2% / +19% / +7% | +30% / +19% / +49% | yes |
| Contracts at most 15% of earnings on days 1, 7 and 14, every bot | highest 14.3% (casual s1 day 1) | highest 14.3% (casual s1 day 1) | yes |
| No contract reward above 1 h of income, the first excepted | enforced by the engine at posting | enforced by the engine at posting | yes |

Income is everything earned in the day: market sales plus contract rewards (the Days tables'
"Earned"). Goods auto-delivered to megaprojects are not income.

Contract rewards as a share of earnings, days 1 / 7 / 14:

| Bot | Before s1 | Before s2 | Before s3 | After s1 | After s2 | After s3 |
|---|---|---|---|---|---|---|
| casual | 14.3 / 0.0 / 1.4% | 9.0 / 2.4 / 2.0% | 7.6 / 4.6 / 1.0% | 14.3 / 3.4 / 5.0% | 9.3 / 2.9 / 4.7% | 7.6 / 4.4 / 3.4% |
| balanced | 0.2 / 5.9 / 5.8% | 0.5 / 4.3 / 5.7% | 0.5 / 5.5 / 5.8% | 0.2 / 6.6 / 8.3% | 0.9 / 10.6 / 7.1% | 0.9 / 10.7 / 9.1% |
| greedy | 10.7 / 4.0 / 3.9% | 10.2 / 4.0 / 3.9% | 10.0 / 4.0 / 3.9% | 10.9 / 7.7 / 7.4% | 10.8 / 7.7 / 7.4% | 10.1 / 7.7 / 7.4% |

Every reward a bot was offered, the first excepted, was at least 1.55× what selling the goods at
that check-in's prices would have paid (casual 2.06×, balanced 2.32×, greedy 1.55× at the lowest).

### The misses

- **One megaproject's levels more than 3 days apart (casual).** The station gets a level every 3-4
  days (levels on days 6, 8, 12, 15, 19 for seed 1), the Mass Driver every 1-5 days. A level every
  3 days for each would mean 7 station levels by day 21 where the casual bot gets 4-5; with costs ×2.5
  a level (the lowest the plan allows) that needs income to grow 2.5× every 3 days, and the casual
  bot's grows about 2.2× (×10 from day 7 to day 14, ×2.6 from day 14 to day 21). Counting both
  megaprojects together, a level comes at least every 2 days on seeds 1 and 3 and every 4 on seed 2
  (station on day 15, then nothing until day 19).
- **The optimizer's Mass Driver.** Reached as the casual bot reaches it (level 1 on days 6-8), the
  Mass Driver costs the balanced bot next to nothing: its economy is about 6,000× the casual bot's
  on day 7 (40.5B against 6.5M a day on seed 1), which at ×2.3 a level is about 10 levels. It reaches level 12
  on day 7 and level 15 on day 16, then slows to the pace its income grows. A steeper cost growth
  would stretch the casual bot's gaps further. Its levels keep coming, more slowly, through day 30
  (level 16 on day 25).

### Why the Mass Driver no longer deepens markets

At ×1.15 a level for tier 0-1 markets, the optimizer's level 15 made those markets 8× deeper, and
tier 0-1 goods became 72% of its day-14 sales on seed 1 (the target, kept from stage 1.5, is at most
35%). Without it the balanced bot's day 14 to day 21 growth fell to 6% on seed 1, so the Orbital Station's depth
bonus went from ×1.2 to ×1.25 a level instead (it deepens every tier). After: tier 0-1 goods are
21-28% of the balanced bot's day-14 sales and no good is above 36%.

## Megaproject levels by day

Orbital Station / Mass Driver at the end of each day.

| Day | Casual s1 | Casual s2 | Casual s3 | Balanced s1 | Balanced s2 | Balanced s3 |
|---:|---:|---:|---:|---:|---:|---:|
| 1 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 |
| 2 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 |
| 3 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 | 0/0 |
| 4 | 0/0 | 0/0 | 0/0 | 3/4 | 2/5 | 6/4 |
| 5 | 0/0 | 1/0 | 0/0 | 7/8 | 7/9 | 8/8 |
| 6 | 1/1 | 1/0 | 1/0 | 8/11 | 8/11 | 9/11 |
| 7 | 1/1 | 1/0 | 1/1 | 8/12 | 8/12 | 9/12 |
| 8 | 2/1 | 2/1 | 1/1 | 8/13 | 8/13 | 10/13 |
| 9 | 2/2 | 2/2 | 2/2 | 9/13 | 9/13 | 10/13 |
| 10 | 2/3 | 2/2 | 2/3 | 9/13 | 9/13 | 10/14 |
| 11 | 2/3 | 3/2 | 2/3 | 9/14 | 9/14 | 10/14 |
| 12 | 3/4 | 3/3 | 2/4 | 10/14 | 9/14 | 10/14 |
| 13 | 3/4 | 3/4 | 3/4 | 10/14 | 9/14 | 10/14 |
| 14 | 3/5 | 3/4 | 3/4 | 10/14 | 9/14 | 10/14 |
| 15 | 4/5 | 4/5 | 3/5 | 10/14 | 9/15 | 10/15 |
| 16 | 4/5 | 4/5 | 3/5 | 10/15 | 9/15 | 11/15 |
| 17 | 4/6 | 4/5 | 4/5 | 11/15 | 9/15 | 11/15 |
| 18 | 4/6 | 4/5 | 4/5 | 11/15 | 9/15 | 11/15 |
| 19 | 5/6 | 5/5 | 4/6 | 11/15 | 9/15 | 11/15 |
| 20 | 5/6 | 5/6 | 4/6 | 11/15 | 9/15 | 11/15 |
| 21 | 5/7 | 5/6 | 4/6 | 11/15 | 9/15 | 11/15 |

Before task 5 the casual bot ended day 21 at station level 3 on every seed, with the Mass Driver at
level 1 (seeds 1 and 3) or 0 (seed 2), and the balanced bot at station level 7 with the Mass Driver
at 0 on every seed.

## Earned by day, seed 1

| Bot | Day 7 | Day 14 | Day 21 | Day 30 |
|---|---:|---:|---:|---:|
| casual | 6.53M | 67.6M | 176M | 738M |
| balanced | 40.5B | 69.4B | 90.1B | 119B |
| greedy | 4.1M | 4.77M | 16.7M | 69.8M |

The greedy bot is a floor: it buys the cheapest thing each decision, never builds the kit chain,
never claims a third body and never reaches the station.

`balance_targets_test` asserts the targets on seed 1 only, to keep the suite quick: contracts at
most 15% on days 1, 7 and 14 for all three bots, the casual bot's milestone-or-project weeks, its
Mass Driver by day 8 and both megaprojects rising each week, its day 21 income at least 2× day 14,
and the balanced bot's +20% from day 7 to day 14.
