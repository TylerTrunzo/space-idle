# Playtest round 5, tester #10: Completionist (seed 10)

Repro files for the bugs below are in `docs/playtests/round5/repro/p10/`.

## Persona and run
- **Seed and length:** seed 10, 0 to 724.8 h (day 30.2). I then ran a fork past the cap, to day 60, only to date the two credit milestones I could not reach.
- **Check-ins:** about 150, at 4.8 h intervals, using `away`.
- **What I played by hand and what I scripted:**
  - The first 2.5 days were by hand: every claim, every new building type, and the surveys.
  - After that a script played each check-in. It delivers contracts, adds auto-sell on full stores, doubles rates on limited routes, spreads cargo ships, pays megaproject credits once it can cover a whole level, expands one slot per body, builds from a plan per body, fills empty crew slots, and taps buy-max.
- **Why I scripted:** from day 4 a check-in held no decisions.
- **Reference:** I also ran the balanced bot on seed 10 for 720 h.

## Checklist: everything in content/

| Item | Reached at | How | Notes |
|---|---|---|---|
| 7/7 bodies | Brine 0.9 h, Hollow Reach 10.6 h, Cinder 11.1 h, Vastmere 19.2 h, Tessaly 36 h, Dusk Cairn 65.4 h | claims (5K, 40K, 320K, 2.56M, 20.5M, 164M credits plus kits) | "Whole System" fires at 5 bodies while 2 hidden bodies remain. The two dearest claims earn no milestone. |
| 2/2 surveys | 28.8 h | both run at once from Vastmere (3 drones each) | |
| 26/26 building types | 25.0 h (the last were fertilizer plant and farm) | built from content order | Milestones stop at "Every Tool Lit" (20 types), reached at about 19.5 h. Types 21–26 earn nothing. The count is of types you own now, not types ever built. |
| 27/27 goods made | about 25 h (fertilizer last) | | Nothing in game shows this list: `state` has no lifetime-produced view. |
| Building and goods milestones (first steel, circuits, module, kit, magnets, core, drone, segment, types 12/20, crew 40/90) | 0.1 h to 24 h | normal growth | |
| Flow milestones (wire 20 and 150, steel 20, plate 5, wafer 10, food 20, segment 0.03) | 24 h to 57.6 h | normal growth | Food 20/s needed farms on Tessaly. |
| Clean Running and Nothing Lost | 2.5 h and 57.6 h | waste-free stretches | Easy. The clock reset once on reactor-core overflow. |
| Contracts 1 / 5 / 10 / 14 | 0.5 h / 33.6 h / day 9.0 / day 17.6 | see below | Hardest and least fun. In 30 days, 21 orders were completed and 34 discarded. |
| Station 1 / 2 / 3 / 4 / 6 / 8 / 10 / 12 / 15 | 33.6 h / 48 h / 52.8 h / 62.4 h / 91 h / 134 h / 158 h / day 13 / day 26.8 | near-ready goods, credits by hand | Level 16 at day 30. |
| Mass Driver 1 / 3 / 5 / 10 / 15 | 43 h / 62 h / 77 h / day 7 / day 25 | the same | Level 17 at day 30. |
| Credit milestones 10K to 1T | 0.5 h to day 15.6 | | |
| 3T | day 22.6 (518 h) | | The balanced bot on seed 10 got there at 432 h. |
| 10T | **not reached by day 30** (7.0T earned); fork: day 35.6 | | The bot also misses it on seed 10. |
| 30T | **not reached by day 30**; fork: day 60 | | The bot also misses it. It is out of reach in 30 days for anyone I saw. |

**Result:** 61 of 63 milestones by day 30. Everything that is not a credit total was done by day 26.8. The 30-day cap puts 10T and 30T out of reach on this seed.

## Timeline highlights
- **0.5 h:** first contract, 7.5K, pays for the first claim. A great hook.
- **2.6 h:** first habitat. Crew goes from 20 to 40, and Twelve Trades fires.
- **10–11 h:** Hollow Reach and Cinder claimed. Magnets on Cinder starve until I build a shipyard: 2 starting ships is not enough.
- **19 h:** Vastmere claimed. I built 6 new types in one visit: the most fun check-in of the run.
- **25 h:** the 26th building type. **28.8 h:** both surveys done.
- **33.6 h:** station level 1. My own keep-1e9 rules had blocked it, and the `keepBlocksDelivery` message told me exactly why. Good.
- **43 h:** six milestones in one away summary. The best payoff of the run.
- **65.4 h (day 3.7): Dusk Cairn, the last new thing of any kind.** After this, the only events are credit totals, megaproject levels and contract completions.
- **Days 4–9:** a level or a milestone almost every day. Slot expansion and buildings feel like real growth (income ×40).
- **Days 9–23:** nine milestones in 14 days. Station level 13 and Mass Driver level 14 sat for 7 days because my buy-max habit kept the bank below each level's 131–164B price. Nothing in the game said so: the next goal was "Three Trillion … in 9d" for 35 check-ins in a row.
- **Day 23:** I stopped buy-max and saved. Five megaproject levels landed in 7 days, and income went from 3.7M to 7.2M a second. Station levels 14–16 each added 18–25%.

## Day by day (condensed)

| Day | Credits/s | Bodies | Station | Mass Driver | What was new | Mood (1–5) |
|---|---|---|---|---|---|---|
| 1 | 828 | 5 | 0 | 0 | 4 claims, 23 types, 24 milestones | 5 |
| 2 | 5.4K | 6 | 2 | 1 | last types, surveys, Tessaly, station level 1 | 5 |
| 3 | 22K | 7 | 4 | 4 | Dusk Cairn (the last new content) | 4 |
| 4–5 | 64–191K | 7 | 6–7 | 7–9 | levels only, slot expansion | 4 |
| 6–8 | 387–820K | 7 | 9–10 | 10–12 | levels, contracts_10 | 3 |
| 9–15 | 0.96–2.6M | 7 | 10–12 | 12–14 | 300B, station 12, 1T | 2 |
| 16–23 | 3.1–3.7M | 7 | 13 | 14 | contracts_14, 3T; flat otherwise | 1 |
| 24–30 | 4.6–7.2M | 7 | 14–16 | 15–17 | station 15, Mass Driver 15, then nothing | 2 |

## Persona questions
- **Is the checklist visible in game?** No.
  - `state.milestones` lists only what you have reached. Nothing lists what is left, or progress toward it.
  - `nextGoal` names one milestone, almost always a credit total (137 of about 150 lines). It never named a contract, megaproject or flow milestone while I paid credits by hand.
  - "Every good made" can't be seen at all.
  - `catalog` doesn't mark which types you have built.
  - A completionist has to diff `content/milestones.json` by hand. I wrote `missing.py` to do it, and wanting it is itself a finding.
- **When does the last new thing happen?** The last body was claimed at day 3.7, the last building type at day 2.04, the surveys finished at day 2.2, and the last good was first made at about day 2. After day 4 the checklist is only "bigger number" items. The last milestone inside 30 days was station 15 at day 26.8, followed by 3+ silent days.
- **Does collecting feel rewarding?**
  - Milestone names are lovely ("Freight Without Wings", "Harbor of Stars").
  - But a milestone is only a name. It carries no text, no reward and nothing it unlocks.
  - Station levels are the real reward: +18–25% income late, and they feel great.
  - Mass Driver levels add +5%. Late on that is invisible.
  - The pacing is front-loaded: 24 milestones on day 1, 12 on day 2, 8 on day 3, then about one every 2–3 days.
- **What is missing, impossible or pointless:**
  - **Outpost kits after the 7th claim.** Kits have no use once every body is claimed. The Kit Assembler kept eating hull plate, fuel and circuits: 4,230 kits sat on Brine at day 30, against about 100 ever needed. Nothing flags this.
  - **Survey drones after the two surveys.** They only feed the station.
  - **Reactor cores.** The station is their only consumer, so Dusk Cairn's store sat full from day 3 to day 30, and the waste reached 1.07B an hour. Buy-max kept upgrading the reactor works anyway (a known issue).
  - **Cargo ships.** 8.5K were made and more than 1,000 sat idle on Kora; the surplus sells at about 0.
  - **No milestone** for owning 6 or 7 bodies, for 26 types, or for completing every survey and claim.
  - **Contract milestones turn into a chore.** About 60% of orders asked for goods a megaproject needs (segments, drones, cores) or for impossible sizes (480K circuits, 290K hull plates, 1.1M drones). I only reached 14 completions by scripting partial deliveries of goods that were overflowing anyway.

## Fun, length, coming back
- **Fun:** days 1–3 are excellent for a collector. Each visit adds a body, a new building type or a new chain, and the slow claims (30 min to 3 h) build real anticipation. From day 4, every decision except "pay the megaproject" was automatable, and I automated it.
- **Length:** the checklist runs out on day 3.7. What is left is credit totals and megaproject levels. These are paced fine to day 13, then one event every 2–5 days. 10T and 30T sit at day 36 and day 60 for my play, and the bot misses both on seed 10.
- **Coming back:** station levels (+20% income) were the only thing I looked forward to after day 10. With nothing new to collect and the next-goal line repeating "3T in 9d", I had no intrinsic reason to open the game twice a day.

## Best and worst moments
- **Best:**
  - building 6 new types in one Vastmere visit (19 h);
  - the 43 h away summary with 6 milestones;
  - station level 14 lifting income by a quarter.
- **Worst:**
  - days 16–23: 35 identical check-ins with only "3T in 9d";
  - discarding a megaproject-goods contract every visit;
  - finding 4,230 useless outpost kits.

## Where I'd quit
About day 9. Nothing was left to collect except numbers, and contracts had become a discard ritual. A completionist would come back only to tick 1T, 3T and the level 15s, and 10T and 30T are past a 30-day horizon.

## Round-4 problems met
Nothing changed beyond the known list. My experience matched the known entries for buy-max as a crew sponge, contracts asking for megaproject goods or oversized amounts, the "1 still owed" last unit, a depot needing a steel route, and route-rate whack-a-mole.

## Bugs and new issues
1. **Milestones reached during `advance` (or any non-`away` command) are silent.** The reply is only `{"ok":true,"time":400}`; you have to diff `state.milestones` to notice. Repro, seed 10: `setAutoSell kora steel 0`, then `advance 400`, then `state` shows First Foundry. File: `repro/p10/silent_milestone.jsonl`. Eleven of my early milestones were never announced. (The app shows a banner for these; the gap is in the simulator's output.)
2. **`createRoute` accepts `cargo_ship` as the cargo.** A ship ferries ships: `{"cmd":"createRoute","fromBodyId":"kora","toBodyId":"cinder","resourceId":"cargo_ship","ratePerSecond":"0.01","cargoShips":1}` succeeds. That was my slip; I meant `moveShips`. It is harmless but confusing; it should be refused or point to `moveShips`.
3. **Equipment goods keep being made after their use is gone,** and nothing flags it: kits after the last claim, drones after the last survey. Save: `repro/p10/day30_end_kits_idle.json` (Brine holds 4.23K outpost kits).
4. **Milestone naming and coverage:**
   - "Whole System" fires at 5 bodies of 7.
   - The two most expensive claims, Tessaly (20.5M) and Dusk Cairn (164M), have no milestone.
   - Building types top out at 20 of 26.
5. **No progress view of the checklist:** there is no list of unreached milestones, no lifetime-produced list, and no built-types list.

## Top 5 changes (ranked by fun impact)
1. **A collection screen** (now in the engine, then stage 2): every milestone with progress (`milestoneProgress` already exists), goods ever made, building types built, bodies and surveys. Effort S. It turns the front-loaded content into a visible goal list and makes "numbers getting bigger" legible.
2. **More to collect after day 4** (stage 3; L):
   - more hidden bodies through repeatable exploration surveys;
   - outpost kits and survey drones that stay useful (outposts, salvage, pirate bases);
   - milestones for 6/7 bodies and for all 26 types.

   Exploration and ship customization fit best here: they give kits, drones and cargo ships a purpose.
3. **Milestones that give something** (now; M): a small permanent perk or unlock and a line of flavor text on each. Slow building gets a payoff beyond the name.
4. **A next goal that names what blocks you** (now; S): "Mass Driver level 15 needs 131B and you spend half your bank each visit; save for 2 days to afford it". Say the same for contract milestones. That would have saved my 7 flat days; the mechanics already exist.
5. **Contract milestones that track something a player controls** (now; S/M): count orders filled from surplus, or cap order size at what a body can hold in a day. Alternatively, drop contracts_14 so it doesn't push players to script partial deliveries. Optimization should be about ratios, not discard rituals.
