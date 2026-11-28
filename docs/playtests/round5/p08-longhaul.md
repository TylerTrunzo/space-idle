# Playtest round 5, tester #8: Long haul (seed 8)

## Persona and run
- **Seed 8.** Engine at deab2b1, run with an AOT build of `game_sim` (`dart compile exe` output in my scratch dir). No repo file was changed.
- **Game time:** 45 full game days (t = 0 to 1080 h), at 3 check-ins a day, about 8 h apart. That is about 135 check-ins. Day 1 had a long first session (about 1.3 h of active play) plus two short check-ins. Days 2–3 were played by hand. From t = 56 h, 128 check-ins ran through my routine script.
- **Routine (`checkin.py`, once per check-in):**
  - `away` to the next 8 h mark;
  - fill contracts I could fill from stock, and discard any contract that blocked a megaproject or had been open more than a day;
  - add auto-sell where a store was full;
  - double a route's rate and ships when a `routeLimited` bottleneck named rate or ships;
  - spread cargo ships out from the shipyard body;
  - from day 21, put free crew into empty slots (buy-max won't; see Bugs);
  - set the auto-pay reserve to 2 h of income;
  - tap `buyUpgrades` once with everything I held.
- **Builder pass (`daily.py`, once a day):** expand a slot on every body when it costs under 3% of a day's income, and fill free slots from a per-body wish list I chose.
- **By hand:** I stepped in on days 1–5, 11, 21, 25, 30 and 34–35, plus repro and experiment work.
- **Files** (all under `/tmp/claude-0/-home-user-space-idle/7963d8b4-7ef1-5bbc-9bff-b2b24979e3ee/scratchpad/r5/p08-longhaul/`):
  - saves every 5 days: `saves/day05.json` to `saves/day45.json`, plus `saves/day02_end.json`, `saves/day21_empty_slots.json` and `saves/repro_contract_discard_t856.json`;
  - logs: `logs/checkins.csv`, `logs/run.log`, `logs/checkins.txt`;
  - scripts: `sim.py`, `checkin.py`, `daily.py`, `days.py`, `exp/buymax_exp.py`, `exp/mp_exp.py`.

Wanting to automate is itself a finding. 96 route-rate raises over 61 check-ins were the bulk of what I did between day 5 and day 45.

## Timeline highlights
- **0–1.3 h:** Kora wire, wafer and circuit chain. First contract (370 steel for 7.5K) paid for Hollow Reach. Buy-max put 20 capacity levels into a fresh Protein Vat: 21 crew in one vat.
- **8–17 h:** First habitat, kit chain, claims on Cinder and Vastmere. Day 1 ends at 1.7K/s with 21 milestones.
- **24–32 h:** Magnet, dock, drone and reactor chain. Station level 1 and level 2 on day 2. Surveys found Tessaly and Dusk Cairn.
- **40–48 h:** Station level 3, Mass Driver level 2. Dusk Cairn claimed.
- **83 h (day 4):** Tessaly claimed. All 7 bodies owned, nothing left to survey or claim.
- **Day 8:** "Name on the Board" (10 contracts). That was the last non-credit, non-megaproject milestone I would ever get.
- **Day 11, best moment:** moved 600 cargo ships off Hollow Reach and built a Depot. Income went from 350K/s to 449K/s in one visit, because the route limits finally said what bound them.
- **Day 19:** Trillionaire. **Day 21:** found 7 new buildings that had sat at 0 crew for days while 140–280 crew were free.
- **Day 22:** station level 15 ("Harbor of Stars"). After this, station levels came 5, 7 and 11 days apart.
- **Day 25:** demolished crew-sponge buildings and put Depots on Cinder. Magnets unblocked (+5%).
- **Day 26:** 3T. **Day 39:** 10T. **Day 45:** station level 18. 30T is about 3 weeks away.

## Day-by-day table
Credits/sec is the average over the last 8 h of the day, taken from the away summary. Levels and bodies are at the end of the day.

| Day | cr/s | Bodies | Station | MD | What was new | Mood |
|---|---|---|---|---|---|---|
| 1 | 1.7K | 4 | 0 | 0 | First contract, claims, habitat, kits | 5 |
| 2 | 4.6K | 5 | 3 | 3 | Station L1–3, Mass Driver opens, surveys | 5 |
| 3 | 11.5K | 6 | 4 | 5 | Dusk Cairn, Billionaire | 4 |
| 4 | 34K | 7 | 5 | 6 | Tessaly (last body), 3B | 4 |
| 5 | 67K | 7 | 7 | 8 | Tessaly built, Sky Bazaar | 4 |
| 6 | 97K | 7 | 8 | 9 | 10B, Crown of Lights | 3 |
| 7 | 109K | 7 | 8 | 10 | Sustained Fire | 3 |
| 8 | 175K | 7 | 9 | 10 | 30B, 10 contracts | 3 |
| 9 | 288K | 7 | 10 | 11 | City Above | 3 |
| 10 | 330K | 7 | 10 | 11 | nothing | 2 |
| 11 | 569K | 7 | 11 | 12 | Ships + Depot fix (+28%), 100B | 4 |
| 12 | 754K | 7 | 11 | 13 | MD 13 | 3 |
| 13 | 886K | 7 | 12 | 13 | Orbital Commons | 3 |
| 14 | 1.01M | 7 | 12 | 13 | 300B | 3 |
| 15 | 1.31M | 7 | 12 | 14 | MD 14 | 3 |
| 16 | 1.64M | 7 | 13 | 14 | Station 13 | 3 |
| 17 | 1.77M | 7 | 13 | 15 | Freight Without Wings | 3 |
| 18 | 2.07M | 7 | 13 | 15 | nothing | 2 |
| 19 | 2.41M | 7 | 14 | 15 | Trillionaire | 3 |
| 20 | 2.53M | 7 | 14 | 15 | nothing | 2 |
| 21 | 2.84M | 7 | 14 | 16 | Empty-slot bug found | 3 |
| 22 | 3.15M | 7 | 15 | 16 | Harbor of Stars | 3 |
| 23 | 3.81M | 7 | 15 | 16 | nothing | 2 |
| 24 | 4.12M | 7 | 15 | 16 | nothing | 2 |
| 25 | 4.20M | 7 | 15 | 16 | Depot/crew-sponge fix | 3 |
| 26 | 4.76M | 7 | 15 | 17 | 3T | 3 |
| 27 | 4.67M | 7 | 16 | 17 | Station 16 | 2 |
| 28 | 5.52M | 7 | 16 | 17 | nothing | 2 |
| 29 | 5.57M | 7 | 16 | 17 | nothing | 2 |
| 30 | 5.61M | 7 | 16 | 17 | nothing (ran experiments) | 2 |
| 31 | 5.73M | 7 | 16 | 17 | nothing | 1 |
| 32 | 6.10M | 7 | 16 | 18 | MD 18 | 2 |
| 33 | 6.16M | 7 | 16 | 18 | nothing | 1 |
| 34 | 6.60M | 7 | 17 | 18 | Station 17 | 2 |
| 35–38 | 7.17–7.42M | 7 | 17 | 18 | nothing | 1 |
| 39 | 7.46M | 7 | 17 | 18 | 10T | 2 |
| 40 | 7.64M | 7 | 17 | 18 | nothing | 1 |
| 41 | 8.03M | 7 | 17 | 19 | MD 19 | 2 |
| 42–44 | 8.2–9.0M | 7 | 17 | 19 | nothing | 1 |
| 45 | 10.2M | 7 | 18 | 19 | Station 18 | 2 |

How fast income grew:

| Stretch | Growth | Per day |
|---|---|---|
| Day 7 → 14 | ×9.3 | |
| Day 14 → 21 | ×2.8 | |
| Day 21 → 30 | ×2.0 | |
| Day 30 → 45 | ×1.8 | about 4% |
| Day 35 → 40 | +6.6% | about 1.3% |

## Fun, length, coming back
**Fun.** Days 1–3 were excellent. Every visit had a claim, a new chain, a habitat or a level. Route limits naming their binding cause turned logistics into a real puzzle. Moving ships and adding Depots gave my two best fixes (+28% and +5%). After day 6, a check-in was the same every time: read the summary, raise one or two route rates, tap buy-max. The only real decision left was the daily build choice, and from day 22 even that was gone, because slots cost tens of billions. Buy-max makes upgrades a non-decision. Its crew-first rule actively hurts (see Bugs).

**Length.** Content runs out early:

| What | When it ran out |
|---|---|
| Bodies (all 7 claimed) | day 4 |
| Surveys | day 2 |
| All building types | about day 5 |
| Non-credit, non-megaproject milestones | day 8; contracts_14 was never reached |

That left only the credit milestones and megaproject levels:

| Milestone | Day |
|---|---|
| 1T | 19 |
| 3T | 26 |
| 10T | 39 |
| 30T | not reached; about day 65 at this rate |

| Megaproject levels | Days apart |
|---|---|
| Station 15 → 16 → 17 → 18 | 5, 7, 11 |
| Mass Driver 16 → 17 → 18 → 19 | 5, 6, 9 |

From day 27, only 5 of 19 days had any event. The numbers never stop growing, so nothing "runs out" mathematically. But it feels hollow: the growth is a few percent a day, and nothing new is built.

**Coming back.** On days 1–5 I wanted to see what finished overnight. On day 30 the only pull was "MD 18 in about 2 days" and "10T in 9 days". On day 45 it was "MD 20 in about 6.5 days" and "30T in about 3 weeks". Those aren't enough. What would bring me back is something new to build or reach.

## The three pleasures, late game
- **Numbers growing.** They keep growing and the formatting stays clean: K/M/B/T with 3 significant figures, "1d 6h counted (cap)", "10.5B Copper Wire". Nothing reached "Qa" in 45 days. But ×1.8 over 15 days doesn't feel like growth at these magnitudes. The headline "net +63.9B" is always just the reserve in the late game, so it carries no information.
- **Slow building.** It became pure waiting after day 22. Both megaprojects are credit sinks.
  - From the day-34 state (`saves/day35_start.json`), 5 days of play under four credit splits:

    | Split | Income after 5 days | vs equal split |
    |---|---|---|
    | No megaprojects at all | 8.85M/s | +18% (and +10% earned) |
    | Equal 1:1 (what I played) | 7.48M/s | — |
    | Mass Driver only | 7.83M/s | +5% |
    | Station only | 7.08M/s | −5% |

  - Neither the equal split nor station-only finished a level in those 5 days. Late levels lose to plain upgrades.
- **Optimization.** Route limits and Depots are the real puzzle and the best part of the late game. Crew is anti-optimization. Day-45 examples:

  | Body | Building | Crew | Output |
  |---|---|---|---|
  | Vastmere | b476 Reactor Works | 83 | 0.92 cores/s |
  | Vastmere | b338 Reactor Works | 10 | 933 cores/s |
  | Cinder | b350 RE mine | 74 | 192/s |
  | Cinder | b191 RE mine | 19 | 37.4K/s |

## Performance
Wall time for `away` on the AOT exe, scaling with about 180 buildings and 25 routes:

| What | Wall time |
|---|---|
| 8 h away, day 1 | 0.02 s |
| 8 h away, days 10–45 | 0.15–0.40 s |
| 12 h away, day 30 | 0.33 s |
| 12 h away, day 45 | 0.38 s |
| 72 h away, day 45 (30 h counted, capped) | 0.81 s |
| `dart run` (JIT, startup included), 12 h, day 30 | 0.93 s |

No concern.

## Best and worst moments
**Best:**
- Day 2: returned to station levels 1 and 2 done with nothing hauled.
- Day 11: the ships and Depot fix. "Steel into Hollow Reach is limited by Hollow Reach's storage (1.24K/s); a Depot raises it" told me exactly what to do.
- The away summary's "ongoing for 6d 8h, and worse than before" lines.

**Worst:**
- Day 21: 7 new buildings at 0 crew for 2–3 days while free crew grew. Nothing warned me except a "has no crew" line with no credit loss attached, ranked below small route issues.
- Days 26–41: buy-max spent about 40B a tap on 20–27 capacity levels at 1–2B each, while speed levels at 100–450M sat unbought.
- Days 35–38: four check-ins in a row with nothing at all.

## Where I'd quit, and why
- **Without my script, about day 10–12.** Each visit was a chore of raising route rates, with nothing new to build.
- **With the script, about day 28–30.** No new goals, levels 7–11 days apart, and 1–4% growth a day.

## Earlier testers' findings
- **Buy-max turns new buildings into crew sponges: confirmed, and worse late.**
  - New buildings get 20–80 crew. Buy-max bought capacity in 125 of 128 routine check-ins.
  - It never fills empty slots.
  - Tapping buy-max in budgets of 600M or less (so the crew-first levels never fit) beat one full tap by +11% income and +8% earned over 3 days, from the day-29 state (`exp/buymax_exp.py`).
- **Contracts ask for goods megaprojects need: confirmed.**
  - Of roughly 85 orders posted from day 3, about 75 asked for segments, drones, reactor cores or magnets.
  - Late orders were 10–12M units, sized to total storage, and paid the 30-minute income floor: 4.3M magnets (worth 193M) for 4.48B.
  - About 10 contracts were completed in total, none after day 8.
- **Content runs out by about day 5: confirmed** (see Length).

## Round-4 problems I met
1. **Megaproject payback: same up to day 21, worse after.** Gaps of 5, 7 and 11 days, and the experiment above.
2. **Mass Driver worthless: fixed.** At level 19 it multiplies tier 1–2 sales by ×2.53, and it beat station-only.
3. **Pacing bot vs a buy-max player: still far ahead of target.** I reached station level 1 on day 2 against a target of days 3–5, and all bodies by day 4.
4. **Away summary: better.** Bottlenecks are grouped, durations shown, and the diversion and contract-block warnings work. Still missing: idle crew is never reported (578 free on day 28), and empty-slot lines carry no credit loss.
5. **Route throughput hidden: fixed.** It became the main lever.
6. **Contracts not a decision: still not one.** Early ones were fine. Late ones are unfillable, they pay the floor, and they hold goods (Bug 3).
7. **Auto-feed / auto-pay: better.** The reserve works, but saving for a 164M claim on day 4 meant setting the reserve high by hand.
8. **Crew irrelevant: changed, not fixed.** Housing outran jobs (200–578 free crew on days 26–31), and buy-max dumps crew where it adds the least.
9. **Old bugs:** none of round 4's seen.

## Bugs
1. **Buy-max never fills empty crew slots.**
   - Load `saves/day21_empty_slots.json`. Run `{"cmd":"away","seconds":28800}` then `{"cmd":"buyUpgrades","budget":"5e9"}`, three times over.
   - Free crew goes 5 → 50 → 87, while 7 buildings stay at 0 crew: b371 and b383 (Station Docks), b373, b375, b377, b379, b381.
   - Buy-max keeps buying capacity on other buildings instead.
2. **The stop message blames the budget when credits are short.**
   - On the same save, run `buyUpgrades` with budget `2e8`, then again with budget `2e9`.
   - The second reply says "Bought no upgrades: the cheapest costs 9.26M credits, more than the budget allows", but the 2e9 budget wasn't the limit: what I held was.
3. **A discarded contract dumps its hold and crashes the market.**
   - Load `saves/repro_contract_discard_t856.json`. Run `away 28800`; `report` reads 7.21M/s.
   - Then `{"cmd":"discardContract","contractId":"c496"}` and `advance 60`. All 3.62M held segments sell within that minute and `report` reads 4.18M/s.
   - The next 8 h earn 171B against 208B without the discard (−18%).
   - This happened at every one of my discards late in the game.
4. **"Has no crew" and "understaffed" bottlenecks carry `lostCreditsPerHour: null`.** So they rank below 3M/h route issues and hid for days.

## Top 5 changes
1. **Buy-max by value, not "crew first"** (now, S). Fill empty slots first, then buy whichever level gives the most output per credit. That is +11% from my test, ends the crew sponges, and makes crew a real ratio lever (numbers, optimization).
2. **New frontier around days 7–14** (stage 3/5, L). Explorer ships to a second system, new deposits, the next tier of goods. Bodies are gone by day 4 and there is nothing new to build after day 6 (slow building). It's also the natural home for cargo hauler designs and pirates on long routes.
3. **Late megaproject value** (now, S–M). Ease cost growth past about level 15 (×1.6–1.8), or tie the bonus to production, so a level pays back within 3–5 days. Show the payback and the level ETA. At the moment, skipping megaprojects wins (slow building, numbers).
4. **"Keep supplied" routes** (stage 3, M). Routes that size their ships and rate to demand, with Depots suggested. My script raised route rates 96 times; that's the best puzzle turned into a chore (optimization). It fits the planned ship-design hauler routes.
5. **Late contracts sized by income minutes** (now, S). Cap the hold at about 1 h of production, release it gradually on discard, and add faction buyers with real choices in stage 3. Contracts would become a decision again, and stop causing silent income dips (optimization, numbers).
