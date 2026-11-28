# Stage 1.7: 30-day balance baselines

Generated with `dart run game_sim:game_sim bot --bot <casual|balanced|greedy> --hours 720 --seed 1 --format md`.
The full seed-1 reports are `stage1_7-30day-casual.md`, `stage1_7-30day-balanced.md` and
`stage1_7-30day-greedy.md`. The stage 1.6 and 1.5 files are kept for comparison. The seed 2 and 3
numbers below come from 21-day runs of the same bots (greedy: 14 days).

"Before" is the start of stage 1.7 task 4 (commit fbdea69): the old casual bot (the balanced plan on
15 commands a check-in, no buy-max), bots paying megaproject credits by hand, the stage 1.7 task 3
content. "After" is task 4's bots and content, after its fix round and the controller's rulings.
The pacing targets are `docs/playtests/2026-11-27-round4-findings.md` §4, which moved the casual
targets to a casual bot that taps buy-max each check-in. Stage 1.5's "Orbital Station level 3
around day 14-21" belonged to the old casual bot; §4's targets supersede it (the buy-max casual
reaches level 3 on day 4-5).

## What changed

- **Buy-max casual.** The casual bot taps `buyUpgrades` once a check-in, as one of its 15 commands,
  with its spare credits: what it holds, less what it saves for its next goal, and at most the
  auto-pay reserve while a megaproject can take credits on its own. Buy-max fills free crew first:
  while crew is free, a capacity level on a building whose crew slots are all filled comes before
  cost. With the stage 1.7 task 3 content, cheapest first alone, it earned 40-47B on day 7 against
  4-6M for the old casual bot: round 4's "about 1,000× ahead" was, if anything, low.
- **Megaproject credits on their own.** Both bots set credit auto-pay once every good a stage lacks
  is made or held, above a reserve of an hour of income plus what they save for a goal. The balanced
  bot weights the Orbital Station 2 to the Mass Driver's 1. Idle credits at day 21 fell from 33-39B
  to 10-25B, on an economy three times the size.
- **Contracts.** The balanced and casual bots discard an order they cannot fill within about a day.
- **Content.** Both megaprojects cost ×2 a level (were ×2.5 and ×2.3) from 20M and 8M credits (were
  5M and 2M). Habitat capacity costs ×2 a level (was ×1.2). New milestones: 3T, 10T and 30T earned,
  station levels 12 and 15, Mass Driver levels 10 and 15 (levels 20 were tried and dropped: no
  baseline reaches them by day 30).

## Pacing targets, seeds 1 / 2 / 3

| Target | Before | After | Met |
|---|---|---|---|
| Casual: station level 1 on days 3-5 | day 6 / 7 / 6 (132, 162, 138 h) | day 4 / 4 / 5 (90, 90, 108 h) | yes |
| Casual: a milestone or project on ≥ 5 of every 7 days (worst week) | 6 / 7 / 6 | 7 / 7 / 7 | yes |
| Casual: no gap > 3 days with neither megaproject levelling, through day 21 (longest run of days without, from station level 1) | 2 / 2 / 3 | 3 / 3 / 3 | yes |
| Casual: day 21 ≥ 1.5× day 14 (three-day averages: days 19-21 over days 12-14) | 2.73× / 3.05× / 4.78× | 1.61× / 1.65× / 1.69× | yes |
| Balanced: +20% from day 7 to day 14 (three-day averages: days 12-14 over days 5-7) | 3.62× / 3.35× / 4.11× | 3.95× / 3.51× / 3.11× | yes |
| Balanced: +10% from day 14 to day 21 (three-day averages: days 19-21 over days 12-14) | 1.12× / 1.21× / 1.10× | 1.83× / 1.75× / 1.59× | yes |
| Balanced: a station level at least every 4 days through day 21 (longest run of days without one; §4 said 3, the controller ruled 4) | 12 / 13 / 10 | 4 / 3 / **5** | **no on seed 3** (known miss) |
| Contracts ≤ 15% of earnings on days 1 / 7 / 14, casual | 12.7-0.0-9.3 / 6.3-0.0-7.9 / 6.0-9.6-3.1% | 0.6-4.4-2.9 / 0.4-2.7-2.1 / 0.7-0.0-4.4% | yes |
| Same, balanced | 0.0-0.0-0.0 / 1.5-4.3-6.2 / 1.4-1.5-4.6% | 0.0-0.0-5.1 / 1.3-0.0-3.5 / 1.4-4.4-7.6% | yes |
| Same, greedy | 12.3-11.2-10.6 / 9.9-12.8-12.0 / 9.0-9.5-10.7% | unchanged | yes |
| No reward above 1 h of income, first excepted | | at posting, against the income basis the engine caps by: always (game_core `test/sim/contract_reward_cap_test.dart`, about 100 contracts on seeds 1-6 and four mid-game states) | yes |
| Mass Driver: a level raises balanced income ≥ 3% on days 5-14 | +4.5-5.0% | +4.86-5.00% (days 5, 7, 14) | yes |

**Income ratios on three-day averages** (controller ruling 4 on task 4). A day's earnings swing by
5-20% from the next with when a megaproject level lands (casual seed 1, days 12-21: 140, 171, 184,
199, 206, 214, 258, 265, 260, 270B), so the §4 ratios compare the mean of the three days ending on
each day named, with the bars unchanged. One day against one day, the casual bot read 1.47× / 1.46×
/ 1.61× after task 4's fix round 2, and seeds 1-2 missed 1.5×.

**Known miss.** The balanced bot on seed 3 goes 5 days without a station level (level 15 from day
16, still on day 21). Seed 1, which `balance_targets_test` plays, goes 4. Not tuned (ruling 3).

**The income basis swings.** A contract's reward is capped at 1 h of its income basis at posting:
the larger of credits a second and the sale value of what is made beyond what is used. The second
counts surplus goods, so it moves severalfold within hours as near-ready feeding starts and stops
taking them: on casual seed 1, a magnet order posted at 298 h saw a basis of 3.15M a second at
297.5 h and 5.02M right after posting, against 1.41-1.48M at the check-ins before and after (credits
a second about 1.45M). Its 9.18B reward was within the cap at posting, yet 1.7 h of the basis a
player reading it two hours later sees. Context for playtest round 5: a reward can look generous
against today's income.

## Megaproject levels (E1)

Balanced bot, station level reached, the day, and that level's credits in days of that day's
earnings (seed 1; seeds 2 and 3 are within a level and two days):

| Level | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 |
|---|---|---|---|---|---|---|---|---|
| Before: day, days of income | 8, 0.11 | 9, 0.19 | (seed 3: 11, 0.39) | never | | | | |
| After: day, days of income | 5, 0.13 | 5, 0.26 | 6, 0.30 | 7, 0.46 | 9, 0.60 | 11, 0.81 | 14, 1.06 | 17, 1.75 |

Before, credits were never the cost: the station's segments walled it at level 10-11 from day 8-9
to day 21 (and beyond). After, the levels reached on days 14-21 cost 1.0-1.8 days of income.

One more level, the bonus alone (its multiplier raised so the state's level gives what the next
would), on the balanced bot's states; payback is the next level's credits over the income it adds:

| State | Station gain, next level's cost, payback | Mass Driver gain, cost, payback |
|---|---|---|
| Before, day 7 (s1-s3) | +10.4-14.2%, 0.12-0.35 d, 0.9-3.4 d | +4.9-5.0%, 0.35-0.66 d, 7-14 d |
| Before, day 14 | +17.0-18.4%, 0.36-0.85 d, 2.0-5.0 d | +4.7-4.8%, 0.31-0.77 d, 6.5-16 d |
| After, day 7 | +6.1-8.3%, 0.70-0.82 d, 8-14 d | +4.9-5.0%, 0.33-0.56 d, 7-11 d |
| After, day 14 | +13.7-16.0%, 1.3-2.1 d, 8-15 d | +4.9-5.0%, 1.6-2.1 d, 33-41 d |
| After, day 21 | +15.4-16.7%, 2.7-3.4 d, 17-21 d | +4.9-5.0%, 2.2-2.7 d, 44-56 d |

A level costing 1-2 days of income cannot pay back in 1-3 days at a gain of 6-17%: E1 as written
asks for both. Raising the station's depth factor to ×1.5 a level made the gap targets pass and the
economy grow ×11-15 from day 7 to day 14 (up to 30T a day by day 21), with levels at 0.1-0.6 days of
income; it was not kept. The controller accepted the steep costs (ruling 1): a station level pays
back in 8-21 days of the income it adds, and playtest round 5 judges whether levels still feel worth
it.

**Sales concentration.** Hull plates are 46-52% of the balanced bot's day-14 sales on seeds 1-3
(38-41% before). `balance_targets_test` allows up to 55% for stage 1.7, a known concentration until
stage 3's market-wall content (ruling 2).

## Crew (E8)

Free crew as a share of crew supported, averaged over check-ins:

| Bot | Days 1-4 | Days 4-21 |
|---|---|---|
| Old casual (before) | 14-17% | 0-1% |
| Buy-max casual, cheapest first only, base content | 84% | 73-76% |
| Buy-max casual, cheapest first only, habitat ×2.5 | 51-52% | 25% |
| Buy-max casual, crew first, habitat ×2.5 | 8-12% | 2% |
| Buy-max casual, crew first (free crew read once a command), habitat ×2 | 9-15% | 2-6% |
| **Buy-max casual, crew first, habitat ×2 (shipped)** | **7-12%** | **2-5%** |
| Balanced, before | 7-10% | 3-5% |
| **Balanced (shipped)** | **13-16%** | **3-6%** |

Buy-max puts every free worker to use, so housing is what binds: crew stays a constraint
throughout, for the buy-max casual as for the balanced bot.

## Later days

Seed 1 balanced: income 496B on day 21, 687B on day 30; station 16 → 17 and Mass Driver 17 → 18
between day 21 and 30. Casual seed 1: 270B on day 21, 330B on day 30; its station stays at level 13 from day 13 to day
30, while the Mass Driver goes on (17 → 18 between day 21 and 30). The balanced bot still levels
both past day 30.
