# Stage 1.5: 30-day balance baselines

Generated with `dart run game_sim:game_sim bot --bot <casual|balanced|greedy> --hours 720 --seed <n> --format md`.
The full seed-1 reports are `stage1_5-30day-casual.md`, `stage1_5-30day-balanced.md` and
`stage1_5-30day-greedy.md`: milestone timeline, income by day, the Days table (new things per day,
bodies, station level, contracts completed, contract rewards paid, earnings and the share of sales by
tier, with both pacing lines) and the timeline of claims, surveys, extra slots, station stages and
contracts. Seeds only change which contracts are posted.

## Pacing targets (Global Constraints, stage 1.5)

| Target | Seed 1 | Seed 2 | Seed 3 | Met |
|---|---|---|---|---|
| Casual: something new on 5 of every 7 days, days 1-21 | 21/21 days, worst week 7 | 20/21, worst 6 | 21/21, worst 7 | yes |
| Casual, contracts left out: a milestone or project on 5 of every 7 days | 16/21, worst week 4 | 14/21, worst 3 | 14/21, worst 4 | **no** (not a target; see below) |
| Casual: Orbital Station level 1 in days 4-6 | 132 h (day 6) | 126 h (day 6) | 126 h (day 6) | yes |
| Casual: level 3 in days 14-21 | 348 h (day 15) | 318 h (day 14) | 336 h (day 15) | yes |
| Casual: nothing runs out before day 21 | L4 day 23, 1.7B/day at day 30, credits 7.6B-9.3B left | same shape | same shape | yes |
| Balanced: 5 bodies at about day 2-3 | 54 h | 54 h | 54 h | yes |
| Balanced: level 3 sooner than casual | 96 h | 96 h | 96 h | yes |
| Balanced: levels continue past day 30 | L7 on day 15, none after | L7 on day 15 | L7 on day 14 | **no** |
| Balanced day 14: tier 0-1 at most 35% of sales | 26% | 24% | 24% | yes |
| Balanced day 14: no resource above 30% of sales | hull plate 38%, circuit 34% | similar | similar | **no** |

Earned in the tables now counts contract rewards beside market sales ("Contracts paid"); tier and
resource shares are of market sales only. Contracts are a large part of what the optimizer earns: about
4.5B of its 22B on day 14.

The gaps:

- **Without contracts, casual days are quieter.** The new second pacing line counts only milestones and
  completed projects. On 14-16 of the first 21 days the casual bot sees one, and some weeks have only
  3-4 such days; contracts fill the rest. The target counts contracts, so it holds, but the stretches
  between station levels (days 10-14 and 16-21) rest on the contracts board.
- **Station levels stop for the optimizer.** Level 8 costs 3^7 = 2,187 times level 1: 437K station
  segments. The balanced bot delivers about 24K segments a day, a rate that stops growing once its
  magnet supply (rare earths and nickel, mined and shipped) is spread over docks, drone works and
  reactor works, so level 8 is two to three weeks away at day 30. A player who keeps building mines
  and docks gets there; the bot does not scale its raw mining for the station.
- **One resource above 30% on day 14.** The station takes every magnet-based good (segments,
  drones, reactor cores) the optimizer makes, through deliveries from any body. What is left to sell is
  hull plates, circuits and the tier 1 goods, each at its market's cap, so hull plates and circuits earn
  about 36% each. With only those markets saturated, the 30% and 35% targets cannot both hold. Meeting
  both needs another export the station does not consume. `balance_targets_test` checks 40% for now.

## Stage 1.5 final fix wave: before and after

Deliveries to the station now go on while a stage runs (they pay for the next level, which starts as
the running one completes). Casual bot, before (e5357d0) and after:

| Seed | Station L1 | L2 | L3 | Something new, days 1-21 (worst week) | Milestone or project, days 1-21 (worst week) |
|---|---|---|---|---|---|
| 1 before | 132 h | 234 h | 342 h | 20/21 (6) | 16/21 (4) |
| 1 after | 132 h | 204 h | 348 h | 21/21 (7) | 16/21 (4) |
| 2 before | 126 h | 222 h | 318 h | 21/21 (7) | 14/21 (3) |
| 2 after | 126 h | 228 h | 318 h | 20/21 (6) | 14/21 (3) |
| 3 before | 126 h | 198 h | 348 h | 21/21 (7) | 15/21 (4) |
| 3 after | 126 h | 198 h | 336 h | 21/21 (7) | 14/21 (4) |

The casual bot rarely has a stage's next level paid for before the running one ends, so the station
pace barely moves; the balanced bot reaches level 3 at 96 h on every seed (was 96-108 h) and level 7 on
days 14-15 (was 12-16).

## Day by day, seed 1

| Day | Casual new | Casual station | Casual contracts | Balanced new | Balanced station | Balanced contracts | Greedy new | Greedy station | Greedy contracts |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | 10 | 0 | 1 | 17 | 0 | 1 | 3 | 0 | 0 |
| 2 | 6 | 0 | 3 | 21 | 0 | 8 | 9 | 0 | 6 |
| 3 | 6 | 0 | 4 | 29 | 0 | 13 | 4 | 0 | 9 |
| 4 | 7 | 0 | 6 | 28 | 3 | 19 | 3 | 0 | 11 |
| 5 | 12 | 0 | 8 | 18 | 4 | 25 | 3 | 0 | 13 |
| 6 | 7 | 1 | 10 | 13 | 5 | 31 | 5 | 0 | 15 |
| 7 | 2 | 1 | 12 | 6 | 5 | 37 | 4 | 0 | 18 |
| 8 | 5 | 1 | 14 | 10 | 6 | 43 | 2 | 0 | 20 |
| 9 | 5 | 2 | 17 | 9 | 6 | 49 | 4 | 0 | 24 |
| 10 | 4 | 2 | 20 | 8 | 6 | 55 | 2 | 0 | 26 |
| 11 | 5 | 2 | 23 | 9 | 6 | 61 | 2 | 0 | 28 |
| 12 | 2 | 2 | 25 | 7 | 6 | 67 | 3 | 0 | 31 |
| 13 | 4 | 2 | 28 | 9 | 6 | 73 | 3 | 0 | 34 |
| 14 | 6 | 2 | 33 | 6 | 6 | 79 | 3 | 0 | 37 |
| 15 | 5 | 3 | 36 | 8 | 7 | 85 | 1 | 0 | 38 |
| 16 | 3 | 3 | 39 | 7 | 7 | 91 | 4 | 0 | 42 |
| 17 | 7 | 3 | 44 | 7 | 7 | 97 | 1 | 0 | 43 |
| 18 | 3 | 3 | 47 | 7 | 7 | 103 | 2 | 0 | 45 |
| 19 | 5 | 3 | 52 | 9 | 7 | 109 | 4 | 0 | 47 |
| 20 | 5 | 3 | 56 | 6 | 7 | 115 | 2 | 0 | 49 |
| 21 | 6 | 3 | 61 | 7 | 7 | 121 | 4 | 0 | 52 |
| 22 | 5 | 3 | 65 | 6 | 7 | 127 | 3 | 0 | 53 |
| 23 | 8 | 4 | 71 | 8 | 7 | 133 | 2 | 0 | 55 |
| 24 | 5 | 4 | 76 | 9 | 7 | 139 | 3 | 0 | 58 |
| 25 | 5 | 4 | 81 | 7 | 7 | 145 | 1 | 0 | 59 |
| 26 | 6 | 4 | 87 | 6 | 7 | 151 | 4 | 0 | 62 |
| 27 | 5 | 4 | 92 | 6 | 7 | 157 | 4 | 0 | 64 |
| 28 | 7 | 4 | 99 | 6 | 7 | 163 | 2 | 0 | 66 |
| 29 | 5 | 4 | 104 | 6 | 7 | 169 | 2 | 0 | 68 |
| 30 | 5 | 4 | 109 | 7 | 7 | 175 | 5 | 0 | 71 |

Earned is market sales plus contract rewards; the tier shares are of market sales only.

| Bot | Day | Earned | Contracts paid | Tier 0-1 | Tier 2 | Tier 3 |
|---|---:|---:|---:|---:|---:|---:|
| casual | 7 | 5.88M | 726K | 51% | 46% | 3% |
| casual | 14 | 41M | 8.92M | 53% | 47% | 1% |
| casual | 30 | 1.68B | 211M | 23% | 77% | 0% |
| balanced | 7 | 19.6B | 4.54B | 25% | 73% | 2% |
| balanced | 14 | 22.4B | 4.67B | 26% | 73% | 2% |
| balanced | 30 | 27B | 6B | 25% | 74% | 1% |
| greedy | 7 | 4.02M | 237K | 100% | 0% | 0% |
| greedy | 14 | 4.68M | 269K | 100% | 0% | 0% |
| greedy | 30 | 86M | 4.81M | 100% | 0% | 0% |

The greedy bot is a floor: it buys the cheapest thing each decision, never builds the kit chain, and so
never claims a third body; its "new things" are contracts and two early milestones.
