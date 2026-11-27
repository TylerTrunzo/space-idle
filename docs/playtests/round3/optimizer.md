# Playtest round 3: Optimizer, seed 2, 14 game days

Source: a subagent playtest. The scratch files it mentions (command log, timeline, saves, repros) were in the session
scratchpad (`r3-optimizer/`) and are not kept in the repo.

## Persona and run
- **Persona:** Optimizer. Checked in 7 times a day, every 2.5 h, with a 9 h night. Tested upgrade payback on throwaway
  save copies before buying, and compared numbers with `bot --bot balanced --seed 2 --hours 336`.
- **Run:** seed 2, t = 0 to 336 h, 101 `away` check-ins and 14,654 commands.
- **How it was played:** every decision by hand through day 4. From day 4 a helper script repeated the routine each
  check-in:
  - deliver a contract when stock was there, or hold the good back from auto-sell until it was;
  - deliver to the station from every body;
  - pay credits to the station;
  - spend the rest on upgrade rounds weighted by measured payback;
  - build docks or depots in new slots.

**Answer to the known risk:** for a skilled player the flattening is real, and it comes much earlier than day 9–12 in
time.
- **Income:** growth ended around day 3–4. It went from 100K/s on day 3 to 395K/s on day 14, and was completely flat
  (3.50–3.55B every 2.5 h) from day 10. By day 12, 5B of upgrades raised income by 0–7K/s, so they never pay back.
- **Station:** it did not stop at level 7. It reached level 10 on day 11, then stalled: level 11 needs 295B, about 5 more
  days.
- **Milestones:** the last reachable one, 100B, came on day 7. Nothing new happened after that. 1T would take about day
  30.
- **Compared with the bot on day 14:** the player earns 40B a day and the bot 23B, only 1.75× ahead. Both hit the same
  market-depth ceiling. The difference is mainly station level: 10 for the player, 6 for the bot.

## Timeline highlights
- **0:07:** the first contract (10 hull plates for 9.73K, about 1 h of income) paid for the first claim (Brine).
- **0:47:** first habitats; crew 20 → 60.
- **10 h:** surveyed Dusk Cairn and Tessaly at the same time. A contract for 100 drones paid 1.27M.
- **15.9 h:** station level 1 started. A 550K round of speed upgrades crossed the speed-level-25 doubling, and income
  went from 441 to 1.27K cr/s. The best "numbers go up" moment.
- **Day 2:** station levels 2–4 within 15 h. Tessaly habitats raised crew support to 790, and crew stopped mattering
  from here on.
- **Day 3:** plates sank to 60% of their price, then 26%. Switching investment to water, food, fertilizer and oxygen
  raised income by 20% for 20M; the best optimization puzzle of the run. Levels 5 and 6. Vastmere claimed, so all 7
  bodies were owned by 66 h.
- **Day 4:** found that depots multiply storage (×5 with capacity levels). Building docks in every new slot. Level 7.
  The chore of delivering tens of millions of plates began.
- **Day 7:** 100B milestone; level 9.
- **Day 9:** extra slots now cost 18.6B each (×2.5 per slot), which ended expansion.
- **Days 10–14:** level 10 on day 11. Income flat at about 390K/s; the only events were contracts. 7.05B banked at the
  end.

## Round-2 problems

| Problem | Verdict | Evidence |
|---|---|---|
| Content running out | **Better, not fixed** | All 7 bodies by day 3 (66 h). 41 of 42 milestones by day 7. Slots and docks kept the player busy until day 9. Days 12–14 had only contracts and deliveries. |
| Crew dominating | **Fixed, but crew is now irrelevant** | Speed beats capacity per credit from the 2nd crew on, as designed. Life-support chains are cheap to speed up, so 600–700 crew sat idle from day 2 to the end. Housing and life support are no longer a decision. |
| Market floor wall | **Same wall, new shape** | Raw goods sell at 0.00, steel at 0.09 (1%), plates at 7.1 (24%), circuits at 33%. Income is capped by the sum of market depths; each station level adds only 25% depth while costing 3×. From day 8, upgrades buy nothing. Spreading investment across many tier-1 markets was a good puzzle on days 3–4, then it ran out too. |
| Nothing taking time | **Fixed early, fades late** | Claims (30 m–3 h), surveys (3 h), slots (1 h) and station stages (2–7 h) made days 1–5 feel like real anticipation. After day 5 the timers were never the limit; the credit cost of a station level was (31 h, then about 6 days). |
| Hidden rules and silent failures | **Better** | Errors are clear: kit recipe on a failed claim, "already at its best efficiency", "no Hull Plate on Kora to deliver". New problems are under Bugs: route stop-level throttling, the auto-sell buffer, fractional leftovers, a misleading cr/s in `report`. Route travel time is still not shown in `state`. |
| Weak away summary | **Mostly fixed** | The headline now gives credits and the project that finished, the cap is shown, and posted contracts are listed. Still missing: a next goal. The top bottleneck stayed the same for 8 days ("Magnet Works on Cinder 26–69% nickel", "ongoing since 60.5h", which reads like a duration). |

## Day by day

| Day | Credits/s (end) | Bodies | Station level | What was new |
|---|---|---|---|---|
| 1 | 1.25K | 5 | 1 | About 19 milestones, 4 claims, 2 surveys, 3 slots, level 1 |
| 2 | 23.5K | 6 | 4 | Levels 2, 3, 4, Tessaly, milestones |
| 3 | ~100K | 7 | 6 | Levels 5 and 6, Vastmere, 1B milestone, market diversification |
| 4 | ~170K | 7 | 7 | Level 7, 23 slots, depots |
| 5 | ~250K | 7 | 8 | Level 8, 18 slots |
| 6 | ~290K | 7 | 8 | 4 slots and contracts (no milestone or station level) |
| 7 | ~330K | 7 | 9 | 100B milestone, level 9 |
| 8 | ~350K | 7 | 9 | 1 slot, contracts |
| 9 | ~360K | 7 | 9 | 1 slot, contracts; slots reach 18.6B |
| 10 | ~385K | 7 | 9 | Level 10 paid (timer running), contracts |
| 11 | ~389K | 7 | 10 | Level 10 complete |
| 12 | 389K | 7 | 10 | Contracts only |
| 13 | 395K | 7 | 10 | Contracts only |
| 14 | 395K | 7 | 10 | Contracts only |

Earned per day (market plus contracts): day 1 about 46M, day 3 8.7B, day 5 30B, day 7 37B, day 10 40B, day 14 40B.

**Is a contracts-only day fun?** No. From day 8 contracts were automatic: "you have 100 drones lying around, take
2.9B". There was no decision in them.

## Slow building
- **Days 1–5: satisfying.** Several timers ran at once (4–7 slots plus a station stage). Paying toward the next level
  while one ran felt good.
- **Day 6 on: just waiting.** The station became a credit bar measured in days, and slot prices outgrew income.

## Contracts
- **Share of income:** about 20% of earnings (85B of about 409B), roughly 6 a day. The same share as the bot.
- **Far too generous for the effort:**
  - 10 habitat modules paid 167M, and later 1.01B.
  - 5K iron ore paid 177M while iron ore's market price was 0.00.
  - 100 drones (about 45K at market) paid 2–3B.
- **Cause:** the reward floor is income-seconds (1–2 h of income), while quantities are capped by `maxQuantity` (100,
  1,000 and 5,000). Late in the game each one is a free tip, not a decision.
- **Verdict:** the overall amount is fine; the effort per reward is far too low.

## Best and worst moments
- **Best:**
  - Crossing speed level 25 tripled income overnight.
  - Finding the market ceiling and spreading into water, food, fertilizer and oxygen.
  - Depot storage multiplying.
  - Station levels 1–6 in 3 days, overlapping deliveries with running stages.
  - The first contract paying for the first claim.
- **Worst:**
  - Delivering 1.09M, then 9.8M, then 29.5M hull plates with only 20–170K of storage per body. That took dozens of
    deliver/advance cycles per level; it had to be scripted.
  - Day 10–14 upgrades returning nothing.
  - A route stop level silently starving Cinder's Magnet Works for days.
  - "Still needs 0.31 Station Segment" after delivering exactly the amount shown.

## Where I'd quit, and why
**Around day 9.** Income was flat, slots cost 18.6B, upgrades had stopped paying, and level 11 was days of waiting. The
only activity left was the plate-delivery chore. Might come back once for level 10 on day 11.

**What I'd still want to do at that point:** re-plan production against new demand, and find a use for the saturated
goods (steel, plates, tier-1). A fresh, cheap upgrade ladder, which only new bodies or new recipes give. Logistics that
run themselves.

**Content that would keep an optimizer engaged without padding:**
- Factions or regional buyers with shifting demand for specific goods.
- A second megaproject fed by tier-1 and tier-2 goods (for example a Mass Driver needing steel, water and food).
- Tier-4 recipes that turn segments and cores into deep-market goods.
- Research nodes that raise market depth, lower the 25% efficiency floor, or add storage.
- Continuous sinks (ship modules, station upkeep).
- A next-system unlock gated by items.
- Rate milestones that keep scaling (1K segments a second, 24 h with zero waste at scale).

## Bugs
1. **Fractional deliveries of components and above.** `state` shows whole units, but delivery takes fractions, and
   "still needs" is rounded.
   - Delivering "342" segments left 0.31 needed.
   - Delivering "5100" plates, as shown by "5.1K", left 3.22 needed.
   - *Repro:* deliver exactly the displayed `stillNeeded` for `station_segment` after earlier fractional deliveries
     (deliveries at about 15.9 h and 24.3 h).
2. **Route stop level counts cargo in flight, which silently caps a route at stop ÷ travel time.**
   - Route r47 showed `paused:true` while Cinder held 0 nickel. Magnet Works ran at 16–69% for days, and no bottleneck
     message names the route.
   - *Repro:* r47, stop 300, 180 s travel; r155, stop 60K, 540 s travel.
3. **`report` creditsPerSec is not steady-state.**
   - It shows 680–744K cr/s while each 2.5 h away earns 3.55B (395K/s), because presses drain stock.
   - It was also stale right after an auto-sell change at 0.12 h (9.6 shown, 11.5 actual).
4. **Auto-sell keeps keepAtLeast plus one 60 s step of local demand.** "Keep 30 steel" held 7.8K, and the rule is shown
   nowhere.
5. **A keep level at or above the storage cap wastes output instead of selling it,** with no warning when the rule is
   set.
6. **Wording:** "ongoing since 0.1h" reads like a duration, but it is a game-time timestamp.

## Top 5 changes
1. **Make the market ceiling a lever, not a wall** [now, M].
   - Give each market a visible revenue cap and a saturation readout.
   - Give multiplicative depth gains: a station bonus that compounds, or a research node.
   - Add a second buyer for tier-2 and tier-3 goods.
   - *Why:* it keeps numbers and optimization alive past day 8.
2. **Auto-delivery to megaprojects, plus a second megaproject fed by saturated tier-1 and tier-2 goods** [now, M].
   - A "feed continuously from all bodies" toggle or route.
   - *Why:* it kills the plate chore and gives dead goods a purpose (slow building, numbers).
3. **Contracts** [now, S].
   - Scale quantity with income or station level.
   - Tie the reward to about 3–5× market value with a lower income floor.
   - Add multi-good orders.
   - *Why:* contracts become a real ratio decision (optimization).
4. **Research tree with timers** [3 factions/ships/research, L].
   - Tier-4 recipes, ship-module sinks, a lower efficiency floor, more storage, routes that show throughput.
   - *Why:* fresh upgrade ladders (optimization, slow building).
5. **Next-system unlock gated by an item megaproject** [5 galaxy/megaprojects, L].
   - New bodies and deposits bring cheap upgrade ladders back.
   - Retune slot growth from ×2.5 to about ×1.8.
   - *Why:* slow building and numbers going up past day 9.

Smaller fixes for now (S):
- Show route travel time and throughput, and warn when the stop level is below demand × travel time.
- Deliver components and above only in whole units.
- Make `report` credits per second honest.
- Show the auto-sell buffer.
- Make habitats and crew matter again, for example with crew-only recipes or upkeep that scales.
