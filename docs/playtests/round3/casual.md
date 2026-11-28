# Playtest round 3: Casual persona, seed 1

Source: a subagent playtest. The scratch files it mentions (notes, command log, saves, bug saves) were in the session
scratchpad (`r3-casual/`) and are not kept in the repo.

## Persona and run
- **Persona:** Casual, checking in 4 times a day (morning, lunch, evening, bed). Gaps were about 5.5 h, 6 h and 4 h in
  the day and about 9 h overnight, all taken with `away`.
- **Run:** seed 1, t = 0 to 508 h (21 full game days, plus the day-22 morning summary). 85 check-ins, 5,044 commands.
  A fresh replay ends at the same 378M credits and 40 milestones as the live run.
- **End state:** all 7 bodies owned, Orbital Station level 7, 505 crew supported, 12.9K cr/s, 40 of 42 milestones.

## Timeline highlights
- **0 h:** a contract for 10 hull plates paid 6.04K at minute 1, more than an hour of income. Claimed Hollow Reach in the
  first 6 minutes.
- **5–15 h:** building requirements showed up only by failing, one at a time:
  - the kit assembler needed fuel;
  - the fuel refinery needed hydrogen;
  - the habitat needed a module.

  Crew was stuck at 20 until the first habitat on Brine at 15.5 h (crew went to 40).
- **Day 2:** claim costs went 5K, 40K, 320K, 2.56M (×8 each). Cinder's rare earths gate every advanced good: magnets,
  then drones, reactor cores and segments.
- **Day 3:** ran two surveys at once (3 h each). They revealed Tessaly and Dusk Cairn. Finding hidden bodies was a
  highlight.
- **Day 4, lunch: worst moment.** The player's own electrolyzer upgrades starved Brine's farm of water. Supported crew
  fell from 80 to 41 while 67 were assigned, so every building ran at 61%. The away summary did not mention it. Fixing
  it took about 40 commands.
- **Day 4, bed: best "aha".** Every upgrade cost between 50 and 2K credits while the player held 1.3M. About 530
  upgrades for roughly 800K tripled income from 37 to 110 cr/s. Nothing had said so.
- **Station levels:** L1 day 4, L2 day 5, L3 day 7, L4 day 9, L5 day 11, L6 day 13, L7 day 18.
- **Day 7, bed:** the iron route to Vastmere showed as "paused" forever while Vastmere sat empty. The cause is a hidden
  rule: cargo in flight counts toward the route's stop level.
- **Day 11.8:** Billionaire. It was the last milestone until Ten Billion at 508 h.
- **Days 14–21:** check-ins shrank to "deliver contracts, pour credits into the station, leave", about a minute each. L8
  costs 10.9B, about two weeks away.

## Round-2 problems

| Problem | Verdict | Evidence |
|---|---|---|
| Content running out | **Better** | **Better:** new things came regularly through day 13: surveys plus 2 hidden bodies (Tessaly claimed day 6, Dusk Cairn day 10), 7 station levels, 39 milestones by day 11.8.<br>**Still there:** the last new place was on day 10 and the last milestone before 10B on day 11.8. Days 14–17 and 19–21 had only contracts. Next level (L8) needs 10.9B at about 0.8B a day. |
| Crew dominating | **Better, still strong** | **Still strong:** 11 capacity buys (about 10K) gave +40% (22 to 31 cr/s, day 2). 30 buys gave +44% (393 to 565, day 6).<br>**Better:** crew is now gated by habitats, which need claims, slots and life support. That made real decisions. Speed upgrades were just as strong (×3 on day 4). |
| Market floor wall | **Mostly fixed** | **Fixed:** tier 2–3 goods hold their price at tens sold per second (plates 28.8 at 0.96 saturation, segments 994, drones 479).<br>**Remaining:** raw goods sit at the floor (iron 0.05) and nobody cares. The wall now is income going flat: 6.6K to 12.9K cr/s from day 13 to day 21, because the station soaks up all the output. |
| Nothing taking time | **Fixed** | Many timers ran at once and each check-in found something finished: claims 30 m to 3 h; surveys 3 h; slots 1 h; station levels 2–5 h. Satisfying through day 13. Twice a station level sat unstarted overnight because it was a few million credits short at departure. |
| Hidden rules and silent failures | **Better, not fixed** | **Better:** errors are good ("Mine can't mine Helium-3 … Mine mines …", "already getting an extra slot").<br>**Still hidden:** inputs still appear one failure at a time (drone works needed magnets, then circuits, then fuel), and: "0 free crew" while over-assigned, even right after freeing crew; a capacity upgrade doesn't add crew; a depot needs 50 steel on that body; auto-sell ate goods a contract needed; route stop level vs cargo in flight, and stop above the destination's storage cap (bugs 3 and 4); a slowly draining oxygen stock showed as net "0"; no list of the milestones left. |
| Weak away summary | **Better, with one serious hole** | **Good:** the headline names the station level; the list of finished projects (7 lines at once felt great); contracts posted; "ongoing since"; credits lost per hour; the cap is shown.<br>**The hole:** the day-4 crew crash was missing from the top bottlenecks (bug 2).<br>**Other gaps:** the same top warning led every summary for 9+ days; "ongoing" hid that a building got much worse (86% to 0%); waste is totalled in units, not credits; no next goal and no "you can now afford"; the station bonus is never described. |

## Day by day

| Day | cr/s (first → last) | Bodies | Station level | What was new |
|---|---|---|---|---|
| 1 | 1.7 → 16 | 3 | 0 | 2 claims, first contracts, first habitat (crew 40), 11 milestones |
| 2 | 12 → 37 | 4 | 0 | Vastmere claimed, slots, Millionaire |
| 3 | 35 → 16 | 5 | 0 | Cinder claimed, magnet/drone chain, 2 surveys reveal 2 bodies |
| 4 | 26 → 108 | 5 | **1** | Crew crash, L1, upgrade spree (×3 income) |
| 5 | 132 → 183 | 5 | **2** | L2 (Spine Complete) |
| 6 | 101 → 565 | 6 | 2 | Tessaly claimed, crew 130 |
| 7 | 554 → 639 | 6 | **3** | L3, Hundred Million, route stall found |
| 8 | 877 → 1.24K | 6 | 3 | Only contracts |
| 9 | 1.24K → 1.71K | 6 (+1 being claimed) | **4** | L4, Dusk Cairn claim started, 7 slots at once |
| 10 | 1.69K → 3.58K | 7 | 4 | Dusk Cairn (no milestone), depots (store ×4) |
| 11 | 3.58K → 4.78K | 7 | **5** | L5, Billionaire |
| 12 | 4.99K → 6.6K | 7 | 5 | Habitats (crew 345); otherwise contracts |
| 13 | 6.6K → 6.6K | 7 | **6** | L6 |
| 14 | 6.7K → 10.2K | 7 | 6 | Only contracts (plus slot filling) |
| 15 | ~10.2K | 7 | 6 | Only contracts |
| 16 | ~10.3K | 7 | 6 | Only contracts |
| 17 | ~10K | 7 | 6 | Only contracts |
| 18 | 10.5K → 9.6K | 7 | **7** | L7 |
| 19 | ~9.7K | 7 | 7 | Only contracts |
| 20 | ~10K | 7 | 7 | Only contracts |
| 21 | 12.9K | 7 | 7 | Only contracts (Ten Billion arrived on the day-22 morning) |

## Pacing, slow building, contracts, numbers, clarity
- **Station levels as events:**
  - Days 4–13 had a level every 1–2 days. The headline line "Orbital Station reached level N" felt like an event.
  - Around day 15 nothing happened: a 5-day gap between L6 and L7.
  - Each level costs ×3 while income grew about ×1.5 per level, so the gaps keep widening.
  - Levels 5–7 gave no milestone, and the bonus is invisible. The only visible bonus was the offline cap
    (12 → 14 → 17 → 18 h), which never mattered with a longest gap of 9 h.
- **Contracts-only days (10 of 21): a chore.**
  - Early on, contracts are too rewarding. On day 1 they paid 94K against 61K from 6 h of production. One contract for
    10 outpost kits paid 1.26M.
  - Late, they are about 20–60 minutes of income. Many ask for 5K of food, oxygen, water or ammonia, which competes
    with habitats, so they were nibbled at over 10+ visits.
  - Big partial orders clog the board, so no new contracts arrive until they are finished or discarded.
- **Does the away summary make me want to act?** Yes, when it shows a storage-full line in credits per hour (for example
  "Cinder full of Station Segment, 3.61M/h"). No when it repeats the same plate-press warning for 9 days, and not at all
  for crew problems.
- **Numbers:** income went 4 → 12.9K cr/s and lifetime credits passed 10B. Flat from day 13 to day 21. The cr/s readout
  drops when goods are kept for the station (10K → 5.5K on day 18), which punishes saving.
- **Clarity:** not possible to tell what to do next from the output alone without trial and error early on (sessions of
  7–12 minutes on days 1–4, too long for a casual). By the late game there was nothing left to decide.

## Bugs
1. **Contracts with tiny quantities and huge rewards.** Seen 5 times: "2 survey drones = 11.7M … 71.1M", against a market
   price of about 480 each. Drone works was making 0.08/s gross at the time. The quantity seems to come from a near-zero
   net flow rather than what is actually made.
2. **Away summary omits a crew shortage.** `topBottlenecks` listed only 3 `input` lines (Vastmere plate presses), while
   `report`'s first bottleneck was `crewShortage`: "support 41 of 67 assigned". Its `lostCreditsPerHour` is null, so it
   never ranks.
3. **Route pauses forever while the destination is empty.** Cargo in flight (rate × about 180 s of travel) exceeds the
   stop level. r61 stays `paused:true`, Vastmere iron stays 0, and `report` says the furnaces are at 0% ("not enough
   Iron Ore", 219K/h lost). Yet hull plates rise 0.93/s, so roughly 30% of the iron still lands. Removing the stop
   level fixes it.
4. **A stop level above the destination's storage cap wastes the cargo**, and the summary reports it as "output is being
   wasted". Example: a Kora → Dusk Cairn plate route with stop 8000 against Dusk's 2.24K cap; 213K units wasted over one
   night (day 12).
5. **Minor:** fractional station leftovers ("still needs 0.01 Hull Plate") after partial deliveries.
6. **Minor:** "Needs 1 more crew (you have 0 free)" appears while crew is over-assigned, even right after unassigning 4.

## Best and worst moments
- **Best:** the 6K contract at minute 1; the 2 surveys revealing new bodies; the day-9 summary listing L4 plus 6 slots
  finished at once; the 530-upgrade spree tripling income; depots taking Kora's storage from 10.6K to 42.8K.
- **Worst:** the hidden crew crash on day 4; chains revealed by failing three times in a row (drone works); a route that
  looked paused for good; days 14–17 and 19–21 with nothing to decide.

## Where I'd quit, and why
Around day 14–15, right after L6. No new bodies, no milestones in sight, and the next level 5 days out. Contracts were
small, and many fought life support. Every check-in was the same minute of "deliver and pay", while cr/s stayed flat.

## Top 5 changes
1. **Fix the away summary (now, S).** Always put crew or housing failures first and in the headline. Flag "worse than
   before" on ongoing problems. Add one next-goal line ("station needs 76M; you will have it in 40 m"). Show waste in
   credits.
2. **Station pacing (now: S for the first two items; stage 5: M).** An auto-pay option, so a level starts when credits
   arrive offline. Show each level's bonus. Add per-material sub-milestones. In stage 5, cut the ×3 gaps with more
   megaproject types.
3. **Contracts for the late game (now, S–M).** Base quantities on gross production (bug 1). Avoid life-support goods, or
   offer them as optional. Late, ask for station-scale lots of tier-3 goods with rewards worth a check-in.
4. **Route and requirement clarity (now, S–M).** Count only stock toward stop levels, or warn when rate × travel exceeds
   the stop. Cap the stop at the destination's storage. Show travel time and cargo in flight in `state`. Show a
   building's full input list in the build reply.
5. **Stage 2 UI tools (stage 2 UI, M–L).** Upgrade payback and buy-max (cheap upgrades tripled income unnoticed for 2
   days). A life-support forecast ("food runs out in 1 h 05 m") before leaving. A chain or ratio view. A list of the
   milestones left.
