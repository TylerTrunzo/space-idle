# Playtest round 5, tester #11: Speedrunner (seed 11)

Repro files for the bugs below are in `docs/playtests/round5/repro/p11/`.

## Persona and run
- **Setup:** seed 11, branch stage1-economy-engine. I compiled the simulator to a native binary in my scratch directory and changed no repo file.
- **Coverage:** about 26 game hours to Orbital Station level 5 on the best route. I then carried one save on to the 1T milestone, which it reached at about 362 h (day 15).
- **Check-ins:** I automated them. Python loops acted every 2 game minutes while awake, which is effectively continuous play. Wanting a planner bot is itself a finding: no human would do this loop by hand.
- **Nights:** the final route includes a 7 h `away` night. The 1T run used hourly check-ins while awake and an 8 h `away` each night.
- **Forks:** about 25 runs from saved states, comparing who buys upgrades (my own heuristic or buy-max) and when to switch from upgrading to paying.

## Times against the bots (seed 11, 240 h bot runs)

| | Station L1 | L3 | L5 | 1T earned |
|---|---|---|---|---|
| Casual bot | 96 h | 102 h | 114 h | not reached in 240 h |
| Balanced bot | 72 h | 84 h | 90 h | not reached in 240 h (seed 1: 270 h) |
| Me, route A (pay first) | **9.8 h** | 17.3 h | 30.6 h | |
| Me, route B (buy-max first, then pay; best) | 13.8 h | ~19.2 h | **26.3 h**, or 26.1 h with a 7 h night | 362 h |

A speedrunner is 7–10× faster than the casual targets up to station level 5. By 1T the lead is gone: I reached it at about day 15, against 270–324 h for the seed-1 bots. Level 5 has no milestone (station_4 is followed by station_6), so my own goal never celebrates.

## Fastest route found: build order
1. **0 h:** build a 2nd smelter and auto-sell copper ore and steel. Spend every credit on cheap copies of iron mines and smelters, which beats capacity levels this early. The first contract (370 steel for 7.5K) is filled at **0.19 h**. The order is sized from your income, so a poor start gets a smaller first order.
2. **0.19 h:** claim **Cinder** (5K). Build a plate press and a wire mill. Demolish the extra mines and smelters, replacing them with one capacity level each. Then a silicon mine, wafer fab and circuit fab, and auto-sell everything.
3. **0.7 h:** on Cinder, a sulfur mine and a propellant mixer (the cheapest fuel). On Kora, one outpost kit assembler. Move 1 cargo ship to Cinder and route fuel to Kora. The route must start on the source body, so the ship has to be moved first.
4. **2.45 h:** with 10 kits and 40K, claim **Hollow Reach**. Build a Module Works for an hour (12 modules), then demolish it. Build a shipyard.
5. **3.5 h:** on Hollow Reach, an ice drill, ice melter, electrolyzer, protein vat, nickel mine and a habitat, with modules routed in. Crew goes from 20 to 40.
6. **3.6 h:** an extra Kora slot. On Cinder, a rare-earth mine and Magnet Works. Send shipyard ships to Hollow Reach (nickel to Cinder) and to Cinder (magnets to Kora).
7. **From 3.6 h:** tap **buy-max with 90% of credits** every few minutes. It buys habitat capacity and crew-fill, taking crew from 55 to 176 by 8 h. My own value-based buyer never did this, and that is the main difference between routes A and B.
8. **4.9 h:** with 15 kits and 320K, claim **Vastmere**. Build 2 more habitats on Hollow Reach and a 2nd Kora slot. Demolish the kit assembler and shipyard. Build a station dock, drone works and reactor works on Kora, and set station goods to "always".
9. **6.5 h:** a helium-3 skimmer and helium-3 route. Auto-sell segments, drones and cores; the megaproject hold protects what the station needs.
10. **Until 14 h:** keep 90% going to buy-max and 10% to the station; L1 completes at 13.8 h. Fill every contract for a good the station does not need: magnet orders pay about 30× sale value, already known. Discard any contract for station goods.
11. **14 h:** stop upgrading and pay every credit into the station. L2 at 16.5 h, L3 ~19.2 h, L4 ~22.2 h, L5 26.1–26.3 h. Going to bed at 19 h with credit auto-pay on (reserve 0) cost nothing.

## How much forking helped
- **Overall:** from 30.6 h (route A) to 26.3 h, about 14% faster.
- **The only lever that mattered was when to switch from upgrading to paying:**
  - from 14 h: switching at 14 / 16 / 18 h gave 26.3 / 26.5 / 26.5 h;
  - from 9.9 h: switching at 14 / 16 / 18 / 20 h gave 32.4 / 29.1 / 28.5 / 28.4 h.
- **Cleverer payment rules lost:**
  - "just in time" (pay so the next level starts as the running one ends) left the station idle and was slower: level 4 only at 27.6 h, versus 22.2 h on route B;
  - "pay once a level costs under P hours of income" gave 27.8–33.1 h;
  - putting all credits into the L1 goods chain first gave L5 at 28.6–37.3 h.
- **After L1 on route B, the stage timers bind:** L1 to L5 took 12.5 h, against an 11.5 h minimum for the L2–L5 timers. The last 10 h of the speedrun are spent waiting.

## Persona findings
- **One dominant opening.** Every good run claims Cinder (cheap fuel), then Hollow Reach (nickel and life support), then Vastmere (helium-3), and skips Brine. Fuel for kits, then rare earths, nickel and helium-3 is a forced chain. Order alternatives are not viable: Vastmere first needs a 3000-credit refinery and 4 crew for the same fuel. The route-planning in the first 6 hours (kits, ships, crew, slots) was the best part of the run: tense and fun.
- **After about 7 h the speedrun stops being a puzzle.** It becomes "tap buy-max, then at about 14 h stop and pay". That is a single knob, worth about ±2 h, with no on-screen hint of where it lies.
- **Buy-max is weak early but wins later.**
  - At 7–8 h, my targeted buying had 4.4K credits/s against buy-max's 1.8K/s.
  - Buy-max early puts its levels into crew sponges, such as a helium-3 skimmer with 26 crew and a reactor with 13 (known).
  - By 14 h, buy-max was ahead at 18.5K/s against 6.5K/s, because it is the only thing that buys habitat capacity and so crew. A value-minded player cannot see that lever: habitats have no output, and nothing says "+N crew for X credits".
- **Easy trap: capacity on multi-slot buildings.** Ten capacity levels on a 3-slot dock cost me 2.2M for +7.7% each, at six times the price of a speed level. Only the static upgradeNote warns about this.
- **Per-building costs push you to build copies.** Costs rise ×1.17 a level, so payback climbs past 4 h around level 40–50. The answer is copies on 50K slots, but nothing suggests it (known).
- **Plain buy-max plateaus.** Without feeding megaprojects, income stalled at about 0.24M credits/s from day 7, earning about 7B a night: numbers stop growing. Feeding both megaprojects (station weight 2, Mass Driver weight 1, reserve one hour of income) reached 1T at 362 h. The station's market depth is the real growth engine, and the game never says so.
- **The lead evaporates.** Being about 88 h ahead at L5 became behind the seed-1 bots by 1T. Doubling level costs pull everyone together, so a speedrunner has no reason to go past the early sprint.

## Day-by-day (best route, then the 1T continuation)

| Day | Credits/s | Bodies | Station level | Mass Driver level | What was new | Mood (1–5) |
|---|---|---|---|---|---|---|
| 1 (0–24 h) | 0.5K → 2.6K (8 h) → 18.5K (14 h) → 22K | 4 | 0 → 4 | 0 | 3 claims, habitats, the whole chain, L1–L4 | 5 to 7 h, then 3 |
| 2 | ~23K → 60K | 4 | 5 → 6 | 1 → 5 | L5 at 26 h; after that only levels and credit milestones | 2 |
| 3–6 | ~0.1M → 0.4M | 4 | 6 → 10 | 5 → 10 | Station-segment contracts of 140K–210K units | 2 |
| 7–15 | → ~1.5M | 4 | 10 → 13 | 10 → 14 | 1T at 362 h | 1–2 |

## Fun, length, coming back
- **Fun:** the first 6 game hours are a great logistics puzzle. They need kits, ships, crew and slots in the right order, and every minute saved shows. After that the decisions are fake: buy-max, then pay.
- **Length:** for this persona the content ends at L5 (~1 day). The 1T chase is two weeks of tapping buy-max.
- **Coming back:** I would come back for a better route, if there were splits or par times. As it stands I would quit once I found the switch time.

## Best and worst moments
- **Best:** the Hollow Reach claim at 2.45 h. I juggled the last free crew between the electrolyzer and the vat to bring the first habitat online, and crew doubled.
- **Worst:** 22–26 h, watching L5's 3.5 h timer with nothing left to decide. Second worst: a night lost to a drone contract (bug 1).

## Where I'd quit, and why
At about 26 h, once L5 is in. The speedrun has no further target that rewards skill: 1T is reached at much the same time however well you played the first day.

## Round-4 problems met
- **Contract income is still the dominant early cash:** 10K magnets for 8.1M and 13K circuits for 21.6M (known, planner).
- **Crew is now a real constraint, which is better:** crew went from 20 to 40 to 176 through habitats and their capacity. With buy-max it still turns into crew sponges (known).

## Bugs
1. **A contract posted while the queued station level is fully paid takes the next level's goods, and the away summary then misreports it.**
   - Contract c53 asked for 43K survey drones and was posted at 16.0 h, while L3 was fully prepaid. It held the 320 drones L4 needed through a 7 h night.
   - The away summary's nextGoal said "Orbital Station level 4 still needs 320 Survey Drone; **you can start it now**". It cannot start: the drones are held by the contract, and the hold row has no credits-lost figure.
   - Cost: L5 at 29.57 h, against 26.07 h for the same route with the night at 19 h.
   - The "never ask for owed goods" guard misses goods the level after the queued one will need, and "you can start it now" is false. This is a sharper form of the known contract-hold issue.
   - Repro: `repro/p11/sl16_before_sleep.json`, then `setMegaprojectAuto` with credits true, `setAutoPayReserve 0`, `away 25200`. Steps are in `repro/p11/contract_hold_night.txt`.
2. **No `station_5` milestone** (levels 4 and 6 have one). Minor.
3. **Ship placement for routes:** `createRoute` from a freshly claimed body fails ("Needs 1 Cargo Ship on Cinder") because the route takes ships from the source body and the starting ships are on Kora. You must `moveShips` first, and the error doesn't suggest it. Close to the known ship-scarcity issue.

## Top 5 changes
1. **(now, S) Fix the contract guard and the false "start it now" message.** Don't ask for goods any fed megaproject will need at its next two levels, and say "held by contract #c53, discard it to start". A single contract cost a speedrunner 3.5 h overnight. This serves slow building: anticipation should not turn into a silent stall.
2. **(stage 2, S) An invest-or-pay planner line:** "pay now: L5 ETA X; keep upgrading 2 h: ETA Y". The run's only real decision is invisible today. This serves optimization.
3. **(now, M) Let surplus goods speed up a running stage.** I had 950 unsold segments piled up, and L2–L5 sit at the 11.5 h timer floor. Spending segments or credits to shorten a timer would make the timers a resource. This serves slow building and numbers growing.
4. **(stage 2, S) Show the crew lever.** For example "habitat capacity: +5 housing for 1.8K", and flag empty slots versus capacity-on-3-slot traps. Only buy-max found the lever that made route B 14% faster. This serves optimization and makes the levers visible.
5. **(stage 2, S; stage 3 for content) Splits or personal best times per milestone and station level.** Add a route-shaping choice: alternative kit or fuel recipes, or Dusk Cairn as a one-body magnet-and-helium-3 shortcut, unlocked by an early survey. Then openings differ and a speedrun has something to replay for, intrinsically and without streaks. This serves optimization and length.
