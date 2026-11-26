# Playtest round 2: Long-haul analyst

## Persona and run

- **Seeds and bots.** Seeds 41 and 42 with the balanced, casual and greedy bots, each for 120 game days, on the 4-check-ins-a-day schedule. That is 480 check-ins per run.
- **Seeds are identical.** Seed 41 and seed 42 give exactly the same trajectory, because stage 1 has no randomness in play. I report one set of numbers.
- **How I made the saves.**
  - The `bot` subcommand cannot save states, so I wrote my own driver at `/tmp/claude-0/-home-user/7963d8b4-7ef1-5bbc-9bff-b2b24979e3ee/scratchpad/pt2-longhaul/driver.dart`. It copies `runBotSession` and saves at days 7, 14, 30, 60 and 120. I did not touch the repo.
  - Saves are in `.../pt2-longhaul/saves/`, as `<bot>_s41_d<N>.json`. Per-day growth is in `<bot>_s<seed>_growth.csv` in the same folder.
  - The balanced saves cannot be loaded (see Bugs). I clamped them, and the loadable copies are named `balancedfix_*`.
- **Hand sessions.** I loaded 13 states: balanced and casual at days 7, 14, 30, 60 and 120, plus greedy at days 7, 60 and 120. Each was a 30-minute game-time session, plus a timed 12 h `away`.
  - I read `state`, `report` and `costs`, and fixed the top bottleneck.
  - I spent credits by payback order and measured the credits/sec change.
  - Helper scripts are `view.py`, `roi.py`, `session.py` and `chain.py` in the scratch dir. `roi.py` measures each upgrade's marginal gain by loading the save, buying that one upgrade and reading `report`.
  - That measuring is analyst behaviour. A real player cannot see it, which is itself a finding.

## Timeline highlights

- **Day 1 to 3 (balanced).** Credits/sec goes 3.7K, 16.7K, 34.5K. All 5 bodies are owned by day 2 and 18 of 19 milestones are reached by day 7. This is the best stretch of the game.
- **Day 7 (balanced).** 564M credits, 42 buildings, every build slot used, and 625 crew. A 12 h `away` earns 1.14B and triggers Billionaire.
  - The best upgrade pays back in about 3.5 h.
  - The Vastmere magnet, reactor, drone and station chain sits at 0% for lack of rare earths. This is the first thing I fixed (below).
- **Day 9 (balanced).** The last milestone (1B credits) is reached. No new milestone appears for the next 111 days.
- **Day 14 to 30 (balanced).** Credits/sec goes 135K to 411K. The best upgrade payback has stretched to about 1 day, then 2.5 days.
- **Day 30 to 60.** Credits/sec goes 411K to 2.67M. This is the last strong stretch, and it includes a jump that matches the x2 speed milestones at levels 50 and 75.
- **Day 60 to 120.** Credits/sec goes 2.67M to 4.6M to 5.66M. The gain per 30 days falls from x1.7 to x1.23, and best payback is 13 to 25 days.
- **Day 120 hand session.** I spent 165B (54% of the 307B bank) on the best 7 upgrades. Credits/sec went from 5.66M to 5.71M, which is +0.9%.
- **Casual bot.** It converges to the same ceiling: 5.45M credits/sec at day 120, against 5.66M for balanced. Playing well early barely changes where you end up.
- **Greedy bot.** It is stuck at 1 to 2 bodies and 35 to 77 credits/sec for 120 days. That is the floor, and it confirms "buy the cheapest" does not win.

## Fun

**Best moments**

- **Days 0 to 7.** Credits/sec grows x14 in 7 days, and every check-in has a clear next step (claims, circuits, outpost kits, habitats).
- **Chain-wide upgrades (casual day 7).** I bought 10 speed levels on all 25 buildings. It cost about 2.1M, and credits/sec went from 3.77K to 8.49K, a payback of about 7 minutes. That is real production-line satisfaction, as is the first time fixing a starved building (Vastmere) unblocks four others at once.
  - It only pays off as a set. Buying 3 rounds across the chain did nothing (3.77K to 3.41K), and 6 rounds only reached 3.97K.
  - Single upgrades therefore show "+0" in `report`, which hides the payoff. A player has to find this by experiment.
- **Crew and capacity.** The crew-and-capacity loop (more crew slots, more habitats, more crew) is a real decision early on.

**Worst moments**

- **Chores with no decision (day 30 and later).** Every check-in is "buy whatever the cheapest speed level is". At day 120 the 37 best-looking upgrades are 1% gains costing 1.9e11 each.
- **Fixing the Vastmere chain at day 7.** It took 6 commands: remove the auto-sell on Cinder rare earths, ship cargo ships to Cinder, create the route, advance 200 s, and so on. The payoff was +0.7K credits/sec on 52.8K, which is nothing.
- **The away summary.** At day 120 it reads "245B gained, 0 stock, 0 waste, 0 milestones, same 3 bottlenecks". Compared with day 7 ("1.14B, Billionaire reached, 720 outpost kits made") it is dull.
- **Pointless output.** Late-game production piles up with no use: 12.1K idle cargo ships and 8.9K outpost kits (the balanced bot's save at day 7). Outpost kits have nothing to claim.

## Where I would quit, and why

- **Casual-schedule player.** At about day 14 to 21, once credits/sec stops doubling per check-in. That is about 3 weeks of real play.
- **Optimizer.** At about day 9 to 10. All 5 bodies are owned, all 19 milestones are done, and the factory is fully built. There is no new building, body or recipe to reach for.
- **Anyone, hard.** Day 60 to 90. A day-120 hand session is 12 commands that move credits/sec by +0.9%.
  - There is nothing to build: the 42 buildings never change after day 7 (balanced) or day 30 (casual). A second chain is useless because a new building at level 0 is about 1e-5 of a level-97 one.
  - The 307B in the bank has no use.
- **Effort versus reward.** The best payback is about 3.5 h at day 7 and about 25 days at day 120, so per-effort reward collapses by about 170x.

## Length and retention findings

- **The finite content runs out in under 2 weeks.** One system, 5 bodies, 19 milestones (the last at 1B credits), 26 buildings and 27 goods. Days 14 to 120 have no content, only the same speed upgrades with a rising price.
- **Short, medium and long goals.**
  - Short goals exist only in days 0 to 7.
  - By day 30 there are zero visible goals: no next milestone, no next claim, nothing locked.
  - `costs` still lists a "next claim: 143M credits and 5 outpost kits" at day 120, with no body left to claim. It is a goal that cannot be completed.
- **The away summary has no hook once chains are stable.** There is no "since you left" list of events beyond credits. The top bottlenecks are the same three Vastmere messages from day 7 to day 120, because the bot never fixes them. Nothing says "come back to spend this".
- **Income that cannot be spent.** The balanced bot holds 307B at day 120 and the casual bot 112B, because nothing is worth buying. That removes the reason to check in.
- **Catch-up cost is fine.** A 12 h `away` costs 0.3 s on the desktop VM (0.57 to 0.9 s of process time including startup), and a 30-day `advance` 7.5 s. Even a 48 h cap would be fine.

## Pacing and numbers

Credits/sec is from `report`, taken at each day. The bank column is the stock of credits that day (the bot spends, so it is not cumulative).

| Day | Balanced credits/sec | Balanced bank | Casual credits/sec | Casual bank | Greedy credits/sec | Balanced / casual / greedy bodies | Balanced milestones | Best upgrade payback, balanced |
|---:|---:|---:|---:|---:|---:|---|---:|---:|
| 1 | 3.72K | 5.2M | 486 | 527K | 31 | 2 / 2 / 1 | | |
| 2 | 16.7K | 27M | 732 | 2.1M | 33 | 5 / 2 / 1 | | |
| 3 | 34.5K | 70M | 643 | 3.3M | 34 | 5 / 4 / 1 | | |
| 5 | 48.4K | 259M | 2.7K | 2.5M | 35 | 5 / 5 / 1 | | |
| 7 | 52.8K | 564M | 3.8K | 18.8M | 36 | 5 / 5 / 1 | 18 | 3.5 h |
| 10 | 73.2K | 839M | 5.2K | 62M | 34 | 5 / 5 / 2 | 19 (day 9) | |
| 14 | 135K | 1.6B | 7.8K | 150M | 34 | 5 / 5 / 2 | 19 | 13 h |
| 21 | 189K | 2.8B | 13.4K | 516M | 41 | | | |
| 30 | 411K | 12.6B | 20.4K | 1.7B | 39 | 5 / 5 / 2 | 19 | 3 d |
| 45 | 1.37M | 26B | 61K | 0.9B | 47 | | | |
| 60 | 2.67M | 56B | 156K | 5.0B | 55 | 5 / 5 / 2 | 19 | 13 d |
| 90 | 4.6M | 113B | 2.73M | 59B | 70 | | | |
| 120 | 5.66M | 307B | 5.45M | 112B | 78 | 5 / 5 / 2 | 19 | 25 d |

- **Cost versus gain.** A speed upgrade costs x1.25 per level and gains about x1.1 per level (about x1.13 with the x2 every 25 levels). Cost wins, so growth is at best logarithmic in total spend. This matches the numbers: per-30-day growth is x6.5, then x1.7, then x1.23, and heads toward a flat line.
- **Spending a bank does not help.** The day-120 balanced hand session spent 165B for +0.9%. Day 60 spent 33B for +0.4%.
- **Dead upgrade tracks.**
  - Efficiency stops at level 28 on every refined chain (`0.95^28` is about 0.24, at the 0.25 floor). I only saw this because the levels sit at 28 in `costs`. The track is still offered.
  - Of 104 upgrade tracks on the balanced factory, 60 to 62 give zero gain at any day. That includes all 17 mine-capacity tracks (no free crew or no deficit), plus circuit-fab, magnet-works and habitat tracks. `costs` lists them as normal options.
- **Structural ceiling.** The factory has 42 buildings with no sink beyond selling at the market floor, and no later content.
- **BigNum.** Formatting is correct from 0 to 1e5000:
  - Suffixes run `K, M, B, T, Qa, Sx, ... Dc`, then scientific notation from 1e36.
  - `999999` shows "1M", and 0.0004 shows "0".
  - Setting credits to 1e5000 and advancing worked, with no overflow or NaN.
  - Nothing in the late game gets near the limits (307B).
- **Performance is fine.** The 120-day bot runs took 60 s (balanced) and 330 s (casual) of CPU. The casual bot's time is its own decision code, not the engine.

## Bugs

1. **Balanced saves cannot be loaded.**
   - **Symptom:** `game_sim: cannot load ...: body cinder: negative stock of cargo_ship`.
   - **Cause:** the engine writes a stock of `-2.220446049250313e-16` (float noise). The save validator rejects any negative value. A real player's save from the same play would be unrecoverable.
   - **Repro:** `.../pt2-longhaul/saves/balanced_s41_d7.json` (fails at every day: 7, 14, 30, 60, 120). Or re-run `driver.dart balanced 41 7 <dir>`, then `dart run game_sim:game_sim --content content --load <dir>/balanced_s41_d7.json --script st.jsonl`.
   - **Likely fix:** clamp tiny negatives to 0 in the engine or tolerate them on load.
   - The casual and greedy saves loaded fine.
2. **Seed has no effect.** `--seed 41` and `--seed 42` produce identical trajectories. Only the rng state field in the save differs, so seeds do not test anything yet.
3. **`away` shows a stock decrease as a gain.** `casual_s41_d7` away reports `stockGained.water_ice = -155`. It should be labelled as consumed.
4. **`costs` shows a next claim (143M and 5 outpost kits) when no unowned body remains.** Day 7 onwards in every save.
5. **A route moves goods at its full rate with no limit on what it drains.** A `createRoute ... "ratePerSecond":"40"` for cargo ships emptied Kora's 12K ships into Cinder (cap 14.6K) and then wasted output. This is a trap, not a crash. `state` does not show auto-sell rules at all, so a player cannot see why Cinder's rare earths vanish. The rules are only visible in the save.
6. **Away summary shows stale top bottlenecks.** Three bottlenecks that have been at 0% since day 7 are listed unchanged through day 120. They are not actionable (fixing them adds +1%).

## Top 10 ideas

1. **Repeatable megaprojects (stage-1 content, size M).** A "Station tier N" project that consumes tier 3 goods (station segments, drones, reactor cores), costs x1.5 per tier and grants a permanent empire-wide multiplier. This gives the 300B bank a use, and gives the starved Vastmere chain a reason to exist. It serves numbers and optimization.
2. **Efficiency that keeps scaling (now, size S).** Remove or raise the 0.25 floor, or switch to a bonus type that continues, or add a new track after level 28. Right now 28 levels exhaust it and then 60% of all tracks are dead. This keeps ratio optimization alive.
3. **New bodies and a second system (stage 1.5 or 5, size L).** All 5 bodies fall by day 2. Add more bodies at x13 claim cost each (the claim cost formula already exists), including exotic ones (void crystals). This drives slow building.
4. **Research or tier-5 unlocks (stage 5, size L).** Gate new recipes (AI cores, shield generators, warp drives) behind research points, so the factory has new things to build after day 14. Late recipes should give a bigger value-add than today's 1.7 to 2x.
5. **Soften the per-level cost wall (now, size S).** Reduce cost growth from 1.25 to about 1.15 per level, or raise the gain (for example 1.1 to 1.15) so payback stays under about 3 days. Alternatively show the wall as a smooth diminishing return and add a multiplier milestone every 10 levels, not 25. Lets the bank buy something.
6. **A real away summary (stage 2 UI, size M).** List what happened (items produced, which chains were idle, stock near cap, "a milestone is N hours away"), a suggested "do this next" with the estimated gain, and time-to-next-goal. Today day 120 says nothing useful.
7. **What-if preview for upgrades (stage 2 UI, size M).** Show the effect on credits/sec of the next 1, 5 and 10 levels on a chain, and the bottleneck it moves to. This turns production-line optimization into an informed choice. Currently single upgrades read as +0 even when buying ten is a 2x win.
8. **Make the factory scale with breadth (now or stage 3, size M).** A new building should matter late. Options: a "blueprint" that copies the best level to a new building at a discount, shared upgrades per building type, or upgrades that cost less when many buildings of a type exist. This stops a day-120 building being worth 1e-5 of the old ones, and gives the bank a use.
9. **Medium-term goals always visible (stage 2 UI, size S).** Show next milestone, next claim and next speed-doubling level for each building, plus a timer ("46 min"). After day 9, add milestones at 10B, 100B, 1T, and one per chain at (for example) production-rate thresholds, so something is always about to happen.
10. **Use for surplus goods (stage 3, size M).** Cargo ships, outpost kits and habitat modules pile up (12K, 8.9K and 12K). Ship classes, pirates and war would consume them, so keep that in mind when sizing stage 3. For now, add a sink such as "colony ships" as a megaproject input.

**Avoid:** daily-login streaks, FOMO timers, and punishing "welcome back" events. The current away flow is already respectful and should stay that way. Do not add a prestige reset: a bank that cannot buy anything is a content gap, not a reason to reset.
