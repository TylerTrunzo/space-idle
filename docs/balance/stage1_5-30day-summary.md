# Stage 1.5: 30-day balance baselines

Generated with `dart run game_sim:game_sim bot --bot <casual|balanced|greedy> --hours 720 --seed <n> --format md`.
The full seed-1 reports are `stage1_5-30day-casual.md`, `stage1_5-30day-balanced.md` and
`stage1_5-30day-greedy.md`: milestone timeline, income by day, the Days table (new things per day,
bodies, station level, contracts completed, income share by tier) and the timeline of claims, surveys,
extra slots, station stages and contracts. Seeds only change which contracts are posted.

## Pacing targets (Global Constraints, stage 1.5)

| Target | Seed 1 | Seed 2 | Seed 3 | Met |
|---|---|---|---|---|
| Casual: something new on 5 of every 7 days, days 1-21 | 20/21 days, worst week 6 | 21/21, worst 7 | 21/21, worst 7 | yes |
| Casual: Orbital Station level 1 in days 4-6 | 132 h (day 6) | 126 h (day 6) | 126 h (day 6) | yes |
| Casual: level 3 in days 14-21 | 342 h (day 15) | 318 h (day 14) | 348 h (day 15) | yes |
| Casual: nothing runs out before day 21 | L4 day 23, 1.0B/day at day 30, credits 10B-1T left | same shape | same shape | yes |
| Balanced: 5 bodies at about day 2-3 | 54 h | 54 h | 54 h | yes |
| Balanced: level 3 sooner than casual | 96 h | 102 h | 108 h | yes |
| Balanced: levels continue past day 30 | L7 on day 12, none after | L7 on day 15 | L7 on day 16 | **no** |
| Balanced day 14: tier 0-1 at most 35% of income | 24% | 24% | 24% | yes |
| Balanced day 14: no resource above 30% | hull plate 37%, circuit 36% | similar | similar | **no** |

The two gaps:

- **Station levels stop for the optimizer.** Level 8 costs 3^7 = 2,187 times level 1: 437K station
  segments. The balanced bot delivers about 24K segments a day, a rate that stops growing once its
  magnet supply (rare earths and nickel, mined and shipped) is spread over docks, drone works and
  reactor works, so level 8 is two to three weeks away at day 30. A player who keeps building mines
  and docks gets there; the bot does not scale its raw mining for the station.
- **One resource above 30% on day 14.** The station now takes every magnet-based good (segments,
  drones, reactor cores) the optimizer makes, through deliveries from any body. What is left to sell is
  hull plates, circuits and the tier 1 goods, each at its market's cap, so hull plates and circuits earn
  about 36% each. With only those markets saturated, the 30% and 35% targets cannot both hold: hull
  plates and circuits would need caps at most 0.75 times the tier 1 total for the first and at least
  0.93 times it for the second. Meeting both needs another export the station does not consume.
  Before deliveries accumulated, segments and magnets piled up past the station's storage wall and were
  sold, which kept day 14 under 30%. `balance_targets_test` checks 40% for now.

## Day by day, seed 1

| Day | Casual new | Casual station | Casual contracts | Balanced new | Balanced station | Balanced contracts | Greedy new | Greedy station | Greedy contracts |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 10 | 0 | 1 | 17 | 0 | 1 | 3 | 0 | 0 |
| 2 | 6 | 0 | 3 | 21 | 0 | 8 | 9 | 0 | 6 |
| 3 | 6 | 0 | 4 | 29 | 0 | 13 | 4 | 0 | 9 |
| 4 | 7 | 0 | 6 | 26 | 3 | 19 | 3 | 0 | 11 |
| 5 | 12 | 0 | 8 | 19 | 4 | 25 | 3 | 0 | 13 |
| 6 | 7 | 1 | 10 | 10 | 5 | 31 | 5 | 0 | 15 |
| 7 | 2 | 1 | 12 | 8 | 5 | 37 | 4 | 0 | 18 |
| 8 | 5 | 1 | 14 | 10 | 6 | 43 | 2 | 0 | 20 |
| 9 | 2 | 1 | 15 | 8 | 6 | 49 | 4 | 0 | 24 |
| 10 | 5 | 2 | 16 | 6 | 6 | 55 | 2 | 0 | 26 |
| 11 | 2 | 2 | 18 | 10 | 6 | 61 | 2 | 0 | 28 |
| 12 | 0 | 2 | 18 | 9 | 7 | 67 | 3 | 0 | 31 |
| 13 | 3 | 2 | 20 | 6 | 7 | 73 | 3 | 0 | 34 |
| 14 | 3 | 2 | 22 | 9 | 7 | 79 | 3 | 0 | 37 |
| 15 | 6 | 3 | 26 | 7 | 7 | 85 | 1 | 0 | 38 |
| 16 | 5 | 3 | 30 | 9 | 7 | 91 | 4 | 0 | 42 |
| 17 | 5 | 3 | 34 | 6 | 7 | 97 | 1 | 0 | 43 |
| 18 | 4 | 3 | 38 | 6 | 7 | 103 | 2 | 0 | 45 |
| 19 | 5 | 3 | 41 | 7 | 7 | 109 | 4 | 0 | 47 |
| 20 | 2 | 3 | 43 | 7 | 7 | 115 | 2 | 0 | 49 |
| 21 | 3 | 3 | 45 | 8 | 7 | 121 | 4 | 0 | 52 |
| 22 | 6 | 3 | 51 | 12 | 7 | 127 | 3 | 0 | 53 |
| 23 | 8 | 4 | 57 | 8 | 7 | 133 | 2 | 0 | 55 |
| 24 | 5 | 4 | 62 | 8 | 7 | 139 | 3 | 0 | 58 |
| 25 | 6 | 4 | 68 | 7 | 7 | 145 | 1 | 0 | 59 |
| 26 | 2 | 4 | 70 | 8 | 7 | 151 | 4 | 0 | 62 |
| 27 | 4 | 4 | 74 | 7 | 7 | 157 | 4 | 0 | 64 |
| 28 | 7 | 4 | 81 | 6 | 7 | 163 | 2 | 0 | 66 |
| 29 | 5 | 4 | 86 | 6 | 7 | 169 | 2 | 0 | 68 |
| 30 | 5 | 4 | 91 | 8 | 7 | 175 | 5 | 0 | 71 |

| Bot | Day | Earned | Tier 0-1 | Tier 2 | Tier 3 |
|---|---:|---:|---:|---:|---:|
| casual | 7 | 5.18M | 51% | 46% | 3% |
| casual | 14 | 35.9M | 58% | 42% | 1% |
| casual | 30 | 1.02B | 32% | 68% | 0% |
| balanced | 7 | 15B | 25% | 73% | 2% |
| balanced | 14 | 20.5B | 24% | 74% | 2% |
| balanced | 30 | 21.5B | 24% | 73% | 3% |
| greedy | 7 | 3.78M | 100% | 0% | 0% |
| greedy | 14 | 4.41M | 100% | 0% | 0% |
| greedy | 30 | 81.2M | 100% | 0% | 0% |

The greedy bot is a floor: it buys the cheapest thing each decision, never builds the kit chain, and so
never claims a third body; its "new things" are contracts and two early milestones.
