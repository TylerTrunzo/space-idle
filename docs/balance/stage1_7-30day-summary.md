# Stage 1.7: 30-day balance baselines

Generated with `dart run game_sim:game_sim bot --bot <casual|balanced|greedy> --hours 720 --seed 1 --format md`.
The full seed-1 reports are `stage1_7-30day-casual.md`, `stage1_7-30day-balanced.md` and
`stage1_7-30day-greedy.md`. The stage 1.6 and 1.5 files are kept for comparison. The seed 2 and 3
numbers below come from 21-day runs of the same bots (greedy: 14 days).

"Before" is the start of stage 1.7 task 4 (commit fbdea69): the old casual bot (the balanced plan on
15 commands a check-in, no buy-max), bots paying megaproject credits by hand, the stage 1.7 task 3
content. "After" is task 4's bots and content. The pacing targets are
`docs/playtests/2026-11-27-round4-findings.md` §4, which moved the casual targets to a casual bot
that taps buy-max each check-in.

## What changed

- **Buy-max casual.** The casual bot taps `buyUpgrades` once a check-in, as one of its 15 commands,
  with its spare credits (less what it saves for a goal, and at most the auto-pay reserve while a
  megaproject takes credits on its own). Buy-max fills free crew first with capacity on buildings
  whose crew slots are all filled.
  With the stage 1.7 task 3 content it earned 40-47B on day 7, against 4-6M for the old casual bot:
  round 4's "about 1,000× ahead" was, if anything, low.
- **Megaproject credits on their own.** Both bots now set credit auto-pay once every good a stage
  lacks is made or held, above a reserve of an hour of income (plus what they save for a goal). The
  balanced bot weights the Orbital Station 2 to the Mass Driver's 1. Idle credits at day 21 fell
  from 33-39B to 13-32B, on an economy three times the size.
- **Contracts.** The balanced and casual bots discard an order they cannot fill within about a day.
- **Content.** Both megaprojects cost ×2 a level (were ×2.5 and ×2.3) from 20M and 8M credits
  (were 5M and 2M). Habitat capacity costs ×2.5 a level (was ×1.2). New milestones: 3T, 10T and
  30T earned, station levels 12 and 15, Mass Driver levels 10 and 15 (levels 20 were tried and
  dropped: no baseline reaches them by day 30).

## Pacing targets, seeds 1 / 2 / 3

After task 4's fix round 1: buy-max fills free crew first (a capacity level on a building whose
crew slots are all filled comes before cost while crew is free), the casual bot's buy-max leaves
its goal saving at every check-in, and the controller's rulings (a station level at least every 4
days; rewards measured against the income basis the cap uses). Stage 1.5's "Orbital Station level 3
around day 14-21" belonged to the old casual bot; §4's targets for the buy-max casual supersede it
(it reaches level 3 on day 4-5).

| Target | Before | After | Met after |
|---|---|---|---|
| Casual: station level 1 on days 3-5 | day 6 / 7 / 6 (132, 162, 138 h) | day 4 / 5 / 4 (96, 108, 90 h) | yes |
| Casual: a milestone or project on ≥ 5 of every 7 days (worst week) | 6 / 7 / 6 | 6 / 6 / **4** | **no on seed 3** |
| Casual: no gap > 3 days with neither megaproject levelling, through day 21 (longest gap from station level 1) | 2 / 2 / 3 | 3 / 2 / **4** | **no on seed 3** |
| Casual: day 21 ≥ 1.5× day 14 | 2.31× / 2.36× / 4.35× | 2.27× / 1.82× / **1.38×** | **no on seed 3** |
| Balanced: +20% from day 7 to day 14 | 2.59× / 2.51× / 2.63× | 3.16× / 3.01× / 3.09× | yes |
| Balanced: +10% from day 14 to day 21 | 1.11× / 1.11× / 1.08× | 1.49× / 1.51× / 1.71× | yes |
| Balanced: a station level at least every 4 days through day 21 (longest run of days without one; §4 said 3, ruled 4) | 12 / 13 / 10 | 4 / 4 / 3 | yes |
| Contracts ≤ 15% of earnings on days 1 / 7 / 14, casual | 12.7-0.0-9.3 / 6.3-0.0-7.9 / 6.0-9.6-3.1% | 0.6-1.2-6.8 / 0.4-1.7-4.6 / 0.7-6.9-4.0% | yes |
| Same, balanced | 0.0-0.0-0.0 / 1.5-4.3-6.2 / 1.4-1.5-4.6% | 0.0-0.1-3.8 / 1.3-0.0-3.7 / 1.4-1.1-1.8% | yes |
| Same, greedy | 12.3-11.2-10.6 / 9.9-12.8-12.0 / 9.0-9.5-10.7% | unchanged | yes |
| No reward above 1 h of income, first excepted: largest reward in hours of the income basis (`incomeBasis`, the cap's), casual | (credits a second: 3.8 / 4.2 / 7.5) | 0.98 / 1.00 / 0.60 | yes |
| Same, balanced | | 0.99 / 1.0002 / 0.77 | yes (within 1%) |
| Same, greedy | | 0.92 / 1.0006 / 1.00 | yes (within 1%) |
| Mass Driver: a level raises balanced income ≥ 3% on days 5-14 | +4.5-5.0% | +4.84-5.00% (days 5, 7, 10, 14) | yes |

The reward is measured at the first decision after the order is posted, often after a catch-up, so
the basis has moved a little since the engine capped it: 1% is allowed. Before the fix round the
basis was not measured; the credits-a-second figures are given for reference.

**Known misses.** Casual seed 3 misses three targets after the fix round, where seed 2 missed the
day-21 ratio before it (1.38×, ruling 7). Which seed misses moves with small changes: with habitat
capacity at ×2 every seed passes, at ×1.5 seed 1 misses three (worst week 5, gap 4, 1.13×), at ×2.5
(shipped, ruling 4) seed 3. Nothing was tuned to pass.

## Megaproject levels (E1)

Balanced bot, station level reached, the day, and that level's credits in days of that day's
earnings (seed 1; seeds 2 and 3 are within a level and a day):

| Level | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 |
|---|---|---|---|---|---|---|---|---|
| Before: day, days of income | 8, 0.11 | 9, 0.19 | (seed 3: 11, 0.39) | never | | | | |
| After: day, days of income | 5, 0.13 | 5, 0.26 | 6, 0.28 | 7, 0.40 | 9, 0.49 | 11, 0.65 | 13, 1.20 | 17, 1.92 |

Before, credits were never the cost: the station's segments walled it at level 10-11 from day 8-9
to day 21 (and beyond). After, the levels reached on days 13-21 cost 1.2-1.9 days of income.

One more level, the bonus alone (its multiplier raised so the state's level gives what the next
would), on the balanced bot's states; payback is the next level's credits over the income it adds:

| State | Station gain, next level's cost, payback | Mass Driver gain, cost, payback |
|---|---|---|
| Before, day 7 (s1-s3) | +10.4-14.2%, 0.12-0.35 d, 0.9-3.4 d | +4.9-5.0%, 0.35-0.66 d, 7-14 d |
| Before, day 14 | +17.0-18.4%, 0.36-0.85 d, 2.0-5.0 d | +4.7-4.8%, 0.31-0.77 d, 6.5-16 d |
| After, day 7 | +8.5-9.2%, 0.68-0.71 d, 7.4-8.3 d | +5.0%, 0.28-0.56 d, 5.7-11 d |
| After, day 14 | +13.5-15.5%, 1.7-2.1 d, 11-15 d | +4.9-5.0%, 1.4-1.7 d, 28-34 d |
| After, day 21 | +15.4-18.6%, 2.4-2.9 d, 13-19 d | +4.8-5.0%, 1.9-2.3 d, 38-47 d |

A level costing 1-2 days of income cannot pay back in 1-3 days at a gain of 8-19%: E1 as written
asks for both. Raising the station's depth factor to ×1.5 a level made the targets for gaps pass and
the economy grow ×11-15 from day 7 to day 14 (up to 30T a day by day 21), with levels at 0.1-0.6 days of
income; it was not kept.

The controller accepted the steep costs (ruling 1): a station level pays back in 7-19 days of the
income it adds, and playtest round 5 judges whether levels still feel worth it.

**Sales concentration.** Hull plates are 44-51% of the balanced bot's day-14 sales on seeds 1-3
(38-41% before). `balance_targets_test` allows up to 55% for stage 1.7, a known concentration until
stage 3's market-wall content (ruling 2).

## Crew (E8)

Free crew as a share of crew supported, averaged over check-ins:

| Bot | Days 1-4 before | Days 4-21 before | Days 1-4 after | Days 4-21 after |
|---|---|---|---|---|
| Old casual (before) / buy-max casual (after) | 14-17% | 0-1% | 8-12% | 2% |
| Buy-max casual on the base content, cheapest first only | 84% | 73-76% | | |
| Buy-max casual, habitat ×2.5, cheapest first only (task 4 before the fix round) | | | 51-52% | 25% |
| Balanced | 7-10% | 3-5% | 13-16% | 3% |

Filling free crew with capacity first is what made crew bind for the buy-max casual: it now runs
short of crew from day 2, as the balanced bot always did.

## Later days

Seed 1 balanced: income 484B on day 21, 610-698B on days 24-30; station 16 → 17 and Mass Driver
17 → 18 between day 21 and 30. Casual seed 1: 405B on day 21, 663B on day 30; station 15 → 16 and
Mass Driver 17 → 18 between day 21 and 30. Both still level past day 30.
