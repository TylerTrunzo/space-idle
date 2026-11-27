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
  with its spare credits (at most the auto-pay reserve while a megaproject takes credits on its own).
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

| Target | Before | After | Met after |
|---|---|---|---|
| Casual: station level 1 on days 3-5 | day 6 / 7 / 6 (132, 162, 138 h) | day 4 / 5 / 4 (90, 102, 90 h) | yes |
| Casual: a milestone or project on ≥ 5 of every 7 days (worst week) | 6 / 7 / 6 | 6 / 7 / 6 | yes |
| Casual: no gap > 3 days with neither megaproject levelling, through day 21 (longest gap from station level 1) | 2 / 2 / 3 | 2 / 3 / 3 | yes |
| Casual: day 21 ≥ 1.5× day 14 | 2.31× / 2.36× / 4.35× | 1.97× / **1.38×** / 2.19× | **no on seed 2** |
| Balanced: +20% from day 7 to day 14 | 2.59× / 2.51× / 2.63× | 3.16× / 3.01× / 3.09× | yes |
| Balanced: +10% from day 14 to day 21 | 1.11× / 1.11× / 1.08× | 1.49× / 1.51× / 1.71× | yes |
| Balanced: a station level at least every 3 days through day 21 (longest gap) | 12 / 13 / 10 | **4 / 4** / 3 | **no on seeds 1-2** |
| Contracts ≤ 15% of earnings on days 1 / 7 / 14, casual | 12.7-0.0-9.3 / 6.3-0.0-7.9 / 6.0-9.6-3.1% | 0.1-0.9-0.0 / 0.7-1.6-2.5 / 0.8-0.3-0.0% | yes |
| Same, balanced | 0.0-0.0-0.0 / 1.5-4.3-6.2 / 1.4-1.5-4.6% | 0.0-0.1-3.8 / 1.3-0.0-3.7 / 1.4-1.1-1.8% | yes |
| Same, greedy | 12.3-11.2-10.6 / 9.9-12.8-12.0 / 9.0-9.5-10.7% | unchanged | yes |
| No reward above 1 h of income, first excepted (largest, in hours of the report's credits a second when posted): casual | 3.81 / 4.21 / 7.51 | 1.04 / 1.78 / 1.37 | no (see below) |
| Same, balanced | 1.01 / 1.02 / 0.79 | 1.01 / 1.02 / 0.79 | about |
| Same, greedy | 0.94 / 1.03 / 1.02 | unchanged | about |
| Mass Driver: a level raises balanced income ≥ 3% on days 5-14 | +4.5-5.0% | +4.84-5.00% (days 5, 7, 10, 14) | yes |

The contract reward cap is 1 h of the reward's income basis, the larger of credits a second and the
value of what is made beyond what is used; the measure above uses credits a second alone, so a
reward a little over 1 h of it is within the cap.

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

## Crew (E8)

Free crew as a share of crew supported, averaged over check-ins:

| Bot | Days 1-4 before | Days 4-21 before | Days 1-4 after | Days 4-21 after |
|---|---|---|---|---|
| Old casual (before) / buy-max casual (after) | 14-17% | 0-1% | 51-52% | 25% |
| Buy-max casual on the base content | 84% | 73-76% | | |
| Balanced | 7-10% | 3-5% | 13-16% | 3% |

Habitat capacity ×2.5 a level cut the buy-max casual's idle crew from 84% to about half; the
balanced bot keeps crew tight as before.

## Later days

Seed 1 balanced: income 484B on day 21, 610-698B on days 24-30; station 16 → 17 and Mass Driver
17 → 18 between day 21 and 30. Casual seed 1: 346B on day 21. Both still level past day 30.
