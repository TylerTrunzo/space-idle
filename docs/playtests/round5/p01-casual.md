# Playtest round 5, tester #1: buy-max casual, seed 2

## Persona and run
- **Persona:** a casual who taps Buy max. Four check-ins a day, at 08:00, 13:30, 19:30 and 23:30 game time, so the gaps are 5.5, 6, 4 and 8.5 h. Every gap used `away`.
- **Run:** seed 2, engine at deab2b1. It covers t = 0 to 504 h (21 full days plus the day-22 morning summary): 84 check-ins and 84 `away` calls.
- **End state:**
  - 3.53M credits/s;
  - all 7 bodies;
  - Orbital Station L15, Mass Driver L16;
  - 57 of 63 milestones. Missing: 3T, 10T, 30T, 14 contracts, and the two zero-waste milestones.
- **Replay:** replaying the full command log gives the same final state (t = 1,814,400 s, 8B credits, same levels).
  - Command log: `/tmp/claude-0/-home-user-space-idle/7963d8b4-7ef1-5bbc-9bff-b2b24979e3ee/scratchpad/r5/p01-casual/log.jsonl`
  - Replay script: `/tmp/claude-0/-home-user-space-idle/7963d8b4-7ef1-5bbc-9bff-b2b24979e3ee/scratchpad/r5/p01-casual/repro/full_replay.jsonl`
  - Day-end saves: `/tmp/claude-0/-home-user-space-idle/7963d8b4-7ef1-5bbc-9bff-b2b24979e3ee/scratchpad/r5/p01-casual/saves_d*_end.json`
- **What I automated:**
  - `checkin.py`: taps Buy max with 99% of credits, plays 60 s, runs `report`, then goes `away` until the next slot.
  - `summ.py`: prints the away summary and a short state.
  - `auto.py`: discards every contract for station segments, survey drones, reactor cores or magnets.
  - Wanting to automate that discard is itself a finding (see contracts below).
- **Decisions:** about 400 game commands in total. That includes 84 Buy max taps, 89 contract discards, 75 builds, 36 auto-sell rules, 23 slot expansions, 20 route changes, 14 crew moves, 6 claims and 3 surveys.
  - Days 1–3 needed 8–15 decisions per check-in.
  - From day 6 on it was about 1–3.

## Timeline highlights
- **0–11.5 h:** the first contract (7.5K) paid for the Brine claim. The first Buy max (44.5K) took income from 2.2 to 14.4/s. But Buy max puts speed on mines that nothing consumes: by 11.5 h, 471K of goods had been wasted against 293K earned.
- **Day 1 night:** 5.17M earned and 3.11M wasted. Brine filled with food, water and fertilizer, which I fixed with seven auto-sell rules. I wanted an "auto-sell everything surplus" switch.
- **24 h, best early moment:** three habitats plus one 6M Buy max took income from 181 to 734/s.
  - The crew-first rule then put 29 crew into a fuel refinery whose fuel was all wasted. I had to take them off by hand.
  - Every new building after that started with 0 crew, because Buy max had used all the free crew.
- **Day 2:** claims, a shipyard, routes and the start of the station chain. Income went from 734 to 14.3K/s.
- **59.5 h:** "Orbital Station reached level 2" (L1 came at about 57 h, on day 3). At 63.5 h, station L3 and Mass Driver L1. At 72 h I came back to station L4–L5 and Mass Driver L2–L4 done overnight. This was the high point.
- **72 h:** auto-pay with reserve 0 had taken all my credits (0.96 left), so Buy max had nothing to spend. I set the reserve to 200M, later 1B, then 8B.
- **From 72 h on:** almost every contract asked for station segments, survey drones, reactor cores or magnets, the goods the megaprojects eat. The report said "Contract #c77 holds 4.14K Station Segments the Orbital Station needs", but the away summary never showed that line. Discarding became my most common decision (89 times).
- **101.5 h:** raising the reserve to 1B let one Buy max take income from 89K to 130K/s (+46%).
- **183.5 h:** I built a plate cluster on Hollow Reach. One tap bought 932 levels and income went from 362K to 426K, then 517K/s. New buildings make Buy max fun again.
- **Days 11–12:** income sat at 750K/s through four check-ins.
  - An A/B test from the same save: a 1B allowance gave 0% growth in a day; putting every credit into Buy max gave +50%.
  - I raised the reserve to 8B.
- **Day 12, 269.5 h:** "Circuit into Cinder is limited by route r55's rate (50/s); raise its rate". Fixing it took income from 884K to 985K/s.
- **Days 14–21:** route whack-a-mole. Each fix moves the limit to the next route and adds 0–5%. The new docks, gas skimmer and reactor works I built did almost nothing (crew-sponge bug below).
- **Days 20–21:** nothing completed. Income went from 3.36M to 3.53M/s. The next goal read "Mass Driver level 17 … in 2d 9h".

## Day by day
"Credits/s" is the reading at the first and last check-in of the day. A level reached overnight is counted on the day it finished.

| Day | Credits/s | Bodies | Station | Mass Driver | What was new | Mood |
|---|---|---|---|---|---|---|
| 1 | 0 → 181 | 1→2 | 0 | – | Brine claimed, circuits, module route, first contracts | 4 |
| 2 | 181 → 14.3K | 2→4 | 0 | – | 4× income from habitats and Buy max, Cinder and Hollow Reach claimed, shipyard | 4 |
| 3 | 14.3K → 61.6K | 5 | 0→5 | 0→4 | Vastmere claimed; station L1–L5, Mass Driver opens, L1–L4 | 5 |
| 4 | 61.6K → 88.9K | 5→6 | 5→7 | 4→8 | Surveys, Tessaly; contract discards start | 4 |
| 5 | 88.9K → 180K | 7 | 7→8 | 8→9 | Dusk Cairn claimed, docks there; 1B allowance gives +46% | 4 |
| 6 | 180K → 247K | 7 | 8→9 | 9→10 | Tried one segment contract (4 check-ins to fill) | 3 |
| 7 | 247K → 340K | 7 | 9→10 | 10→11 | Route ship fix | 3 |
| 8 | 340K → 426K | 7 | 10 | 11→12 | Flat, then the Hollow Reach cluster (932 levels) | 3 |
| 9 | 426K → 641K | 7 | 10→11 | 12 | More docks, circuit fab, first extra habitat | 4 |
| 10 | 641K → 749K | 7 | 11→12 | 12→13 | Habitats (+155 crew each), depot | 3 |
| 11 | 749K → 884K | 7 | 12 | 13 | Flat 750K for a day; 8B allowance | 2 |
| 12 | 884K → 1.09M | 7 | 12 | 13 | Route fixes; 300B milestone | 3 |
| 13 | 1.09M → 1.40M | 7 | 12→13 | 13→14 | – | 3 |
| 14 | 1.40M → 1.72M | 7 | 13 | 14 | Vastmere reactor cluster | 3 |
| 15 | 1.72M → 1.98M | 7 | 13 | 14→15 | Route chores; Freight Without Wings | 2 |
| 16 | 1.98M → 2.66M | 7 | 13→14 | 15 | Slots and habitat; new buildings | 3 |
| 17 | 2.66M → 2.76M | 7 | 14 | 15 | Trillionaire; new buildings do nothing | 2 |
| 18 | 2.76M → 3.01M | 7 | 14 | 15→16 | Mass Driver L16 measured at +0.3% | 2 |
| 19 | 3.01M → 3.36M | 7 | 14→15 | 16 | Harbor of Stars | 2 |
| 20 | 3.36M → 3.32M | 7 | 15 | 16 | Nothing | 1 |
| 21 | 3.32M → 3.53M | 7 | 15 | 16 | Nothing | 1 |

**§4 targets in this run:**
- **Station L1 on days 3–5:** met, on day 3 at about 57 h.
- **A milestone or project on ≥ 5 of every 7 days:** met only just. Week 2 had 5/7 (days 11 and 14 empty) and week 3 had 5/7 (days 20 and 21 empty). Counting slot expansions as projects, every day had one.
- **No gap over 3 days without a megaproject level:** met. The longest was 2.2 days (240 → 293 h).
- **Day 21 ≥ 1.5× day 14:** met, at about 2.1× (about 3.4M against 1.6M credits/s).

## Fun, length, coming back
**Fun.** Days 1–5 are genuinely fun. Each check-in builds a new chain, claims a body, or comes back to one or two megaproject levels finished. Buy max gives the "numbers getting bigger" pleasure in bursts:
- 181 → 734/s;
- +46% on day 5;
- 932 levels for one new cluster on day 8.

The decisions that mattered were placing buildings, fixing routes and setting the buy-max allowance. Buy max itself is not a decision, and it wrecks ratios:
- early waste was larger than income;
- it put 29 crew into a refinery whose fuel was all wasted.

From day 6 on, most check-ins were three steps: discard a megaproject-goods contract, tap Buy max (+1%), leave.

**Length.** There are walls on day 11 (flat until I discovered the reserve lever), days 14–15, and days 17–21.
- Bodies run out on day 5, surveys on day 4, new building types on day 3.
- After that the only new goals are megaproject levels, about every 2.5 days, and credit milestones. Milestones are almost all done by day 17, then nothing until 3T.
- New buildings should keep the game going, but after day 10 they don't (crew-sponge bug). My horizon: about day 17.

**Coming back.** What brought me back was overnight station and Mass Driver levels while they came every few check-ins (days 3–7), and the "raise its rate" lines once they named a real lever.
- Late, the next goal is "in 2d 9h". The away summary leads with "Cinder storage is full of Helium-3: 2K/h", a 0.0001% loss that sat there for 4 days. I have no reason to open the game before the level lands.

**The three pleasures:**
- **Numbers grow** (2.2 → 3.53M credits/s), but only in jumps when I did something other than Buy max.
- **Slow building** felt like anticipation on days 2–7 and like waiting after day 10.
- **Optimization** levers are now visible: route limits are named, and diversion and keep-rule warnings appear. But the only ratio puzzle a casual meets is "raise route rate X", repeated 20 times.

## Best and worst moments
**Best:**
- The day-3 and day-4 morning headlines ("Orbital Station reached level 5; Mass Driver reached level 4").
- 734/s after the first habitats.
- 932 levels in one tap on a new cluster.
- "limited by route r55's rate (50/s); raise its rate", which gave +12% for one command.

**Worst:**
- 89 contract discards.
- Day 11 at a flat 750K/s with no hint why. Auto-pay took about 90% of income, and Buy max on the 1B left gave +0.1%.
- Days 17–21: the buildings I added made nothing. The top of the summary was noise. Two days had nothing at all.

## Where I'd quit, and why
Around day 17–18. Check-ins had become "discard contract, tap Buy max (+1%), raise one route rate", with the next goal two days out. A real casual, without my A/B test, might have quit on day 11: income was flat for a day, and the only clue was "net +983M" in the headline.

## Round-4 problems I met
| Problem | Verdict | Evidence |
|---|---|---|
| 1. Megaproject levels stop paying back | **Better** | Levels every ≤ 2.2 days through day 21. Station L14 +7% (2.48 → 2.66M), L15 +11% (3.02 → 3.36M). |
| 2. Mass Driver bonus nearly worthless | **Same for this player, late** | Measured over 30-minute steps: L16 at 423.7 h took 3.00M → 3.01M (+0.3%). The tier 1–2 sale price did rise 5% (hull plate 17.1 → 18.0), so the fed megaprojects probably take the tier-2 goods it would boost. Repro below. |
| 3. Pacing bot models the wrong player | **Fixed** | Casual bot, seed 2: station L1 at 90 h (me about 57 h), L15 at 420 h (me 456 h), 380B on day 20 (me about 290B). Within about 1.3×. |
| 4. Away summary misleads | **Better, new noise** | No false 0%. Grouping works ("5 Station Docks on Dusk Cairn…"). The diversion, keep-rule and contract-hold kinds are reported. New problems: tiny waste rows hold the top 3 for days; `contractBlocksDelivery` has null credits lost, so it never reaches the top 3; "cps 1.24M → 2.48M" swings come from feeding starting, not real growth. |
| 5. Hidden route throughput | **Fixed** | Limits are named, with the fix: rate, "1 Cargo Ship (10/s); assign more ships", "Dusk Cairn's storage (59.5/s); a Depot raises it". New chore: 20 route edits, one limit after another. |
| 6. Contracts never a decision | **Worse for this persona** | Rewards are about 30–60 minutes of income, as designed. But 89 of 99 orders asked for goods a megaproject eats. The one I kept (180K segments for 532M) took 4 check-ins to fill at about 20K storage per body. |
| 7. Auto-feed and auto-pay starve upgrades | **Goods better, credits same** | Feeding goods near ready works. Credits: with a 1B reserve on day 11, 0% growth in a day, against +50% putting every credit into Buy max. On day 15 the 2-day A/B was 2.48M against 2.65M. |
| 8. Crew irrelevant after day 2 | **Changed** | Housing binds on days 6–10, but Buy max's crew-first rule wastes the crew (bug 1). |
| 9. Bugs | **Mostly fixed** | No float noise, no "0s left", no false 0%. The "0 of N crew" build message is still there (bug 4). |

## Bugs
All paths below are in `/tmp/claude-0/-home-user-space-idle/7963d8b4-7ef1-5bbc-9bff-b2b24979e3ee/scratchpad/r5/p01-casual/repro/`.

1. **Buy max turns new buildings into crew sponges (major).** While crew is free, the cheapest capacity level is always on the newest building. Speed and capacity share one price counter, so once those levels are bought the building's speed costs as much as everyone's, and Buy max never raises it.
   - **Repro:** load `crew_sponge_save_240h.json`, then run `crew_sponge.jsonl` (build a station dock on Dusk Cairn, `buyUpgrades 1e9`, report, costs).
   - **Result:** the new dock b176 gets 50 capacity levels for 977M and speed 0. It ends with 53 crew and makes 0.15 segments/s. The old dock b98 has 6 crew and speed 51, and makes 8.61/s.
   - **In my run:** by 413 h, docks b166/b176/b227 (45–66 crew, speed 2–7) and gas skimmer b233 (83 crew, speed 5) made about 0.1% of the output of their siblings.
2. **Contracts ask for goods the next megaproject level needs.** The exemption covers only what the current stage still owes.
   - **Repro:** load `../bug_c77_segment_contract_72h.json`, then run `c81.jsonl`.
   - **Result:** c81 (97K Station Segments) posts at 76.0 h, while the station is fed and L7 owes only credits. L8 then needs segments that c81 holds.
3. **The contract-hold warning never reaches the away summary.** `contractBlocksDelivery` has `lostCreditsPerHour` null.
   - **Evidence:** at the 72 h arrival the top 3 were Helium-3 and Nickel waste (615/h and 558/h). Meanwhile `report` (same save, `bug_c77_segment_contract_72h.json`) shows "Contract #c77 holds 4.14K Station Segments the Orbital Station needs".
4. **A building made in the same step as new habitats is reported with 0 crew.**
   - **Repro:** load `save_24h.json`, then run `zero_crew_msg.jsonl`.
   - **Result:** the reply says "Fuel Refinery … with 0 of 1 crew"; one tick later assigned goes 20 → 21. Harmless, but it reads as a failure.
5. **Mass Driver L16 adds +0.3%.**
   - **Repro:** load `pre_md16_419.5h.json`, then run `md16.jsonl`.
   - **Result:** `report` reads 3M before and after; hull plate's sale price goes 17.1 → 18.0.
6. **Minor issues:**
   - Building a depot fails off the home body ("Needs 50 Steel on Dusk Cairn"), so I needed a one-off steel route.
   - A food contract (c43) sat 67.5K/130K for 19 days, holding food.

## Top 5 changes
1. **Fix Buy max's crew-first rule** (now, S). Fill free crew only while that capacity level costs no more than a few speed levels elsewhere, and spread crew across buildings. Better still, don't let capacity raise the speed price. This brings back the late "new building, cheap curve, big jump" moments, which serve numbers and slow building.
2. **Contracts from surplus, never from megaproject goods** (now, S; faction buyers in stage 3). Exclude any good a fed megaproject uses at any level, and favour goods the player is wasting or selling at saturation. Then a contract is "turn my overflow into a bonus", a real optimization choice, instead of 89 discards.
3. **Show the auto-pay vs Buy max trade-off** (now plus stage 2, S–M). Make the reserve a share of income, and show "auto-pay took 90%; a Buy max of X would add Y%" next to the next megaproject level's payback. That turns a hidden trap (day 11's 0% growth) into a ratio decision the player can see.
4. **Self-sizing supply routes from a ship pool** (stage 3 with ship designs, M). Routes carry what the destination uses. Logistics choices move to hauler design, escorts and pirate risk on outer routes. That ends the 20-edit whack-a-mole and gives cargo, ships and pirates something meaningful to act on.
5. **New things to build after day 5** (stage 3 research and labs, stage 5 exploration; L). Bodies, surveys and building types all run out by day 5. Tessaly and its 10 slots never had a use. Research-unlocked tier-4 recipes, explorer surveys that find new systems, and body specialities give fresh buildings and fresh cheap upgrade curves. That is where all three pleasures returned in this run.

Also worth doing now (S): hide away-summary bottlenecks under about 0.1% of income. The Helium-3 waste row topped the summary for 4 days.
