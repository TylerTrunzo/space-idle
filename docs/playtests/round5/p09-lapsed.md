# Playtest round 5, tester #9: Lapsed and returning (seed 9)

The saves from just before and just after the gap, and the repro for bug 1, are in `docs/playtests/round5/repro/p09/`.

## Persona and run
- **Seed:** 9.
- **Before the gap:** 29 check-ins, day 0 to day 6.77, each about 6 h apart.
- **The gap:** one `away` of 864,000 s (10 days). Only 22 h of it was counted (the cap).
- **After the gap:** a 26-minute return session, then 28 more check-ins, to day 14.68 of game time. That makes 58 check-ins in all.
- **Automation:** a helper script (`ci.py`) ran the routine at each check-in:
  - auto-sell on new goods, but not on goods that a route brings in;
  - fill any contract the stock could cover;
  - discard contracts for megaproject goods that I couldn't fill;
  - raise route rates when a bottleneck said "raise its rate";
  - buy-max with the credits above the reserve;
  - `away` for the rest of the 6 h.
- **By hand:** every build, claim, crew move and route setup. The first 30 minutes back were played entirely by hand.
- **Wanting to automate the routine is itself a finding:** after day 4 the check-ins were the same five clicks.

## Timeline highlights
- **0.0–0.5 d:** built the circuit chain on Kora and claimed Brine. Income went from 1.65 to 92/s. Great opening.
- **1.0–1.5 d:** buy-max put 23 and 21 crew into an electrolyzer and a fuel refinery (a known issue). I moved them by hand twice before the new buildings got crew.
- **2.27 d:** Orbital Station level 1, then Mass Driver levels 1 and 2. By 2.5 d the station was at level 3.
- **3.0 d:** the board started asking for 38K–430K station segments and survey drones, and these orders held the station's goods. From then on I discarded one or two contracts at every check-in.
- **4–6.8 d:** flat. Buy-max bought 3–7 levels a check-in, and each check-in banked a net +160M while 3–3.7B went to the megaprojects. Station level 10 and Mass Driver level 12. Mood 2–3.
- **6.77 d:** I left with:
  - three open contracts, one of them a magnet order 195K of 340K delivered;
  - a keep rule of 20K circuits on Kora and a keep rule of 500 survey drones on Hollow Reach;
  - Orbital Station level 11 about 1 h from done.
- **The gap:** "Away 10d; 22h counted (cap); earned 30B credits, 13.4B to Orbital Station and 16.5B to Mass Driver, net +140M; Orbital Station reached level 11". The game clock moved on only 22 h (day 7.69).
- **Return session:**
  - cleaned up the board;
  - +581M from the magnet contract, which auto-pay swept within a minute;
  - one station dock (20K credits) and six extra slots.
- **9.19 d:** two habitats (1.7K habitat modules were sitting unused on Kora) raised supported crew from 578 to 849. 340 crew then sat idle for three check-ins, and nothing pointed at them.
- **10.94 d:** 8 new buildings, 599 buy-max levels and 330 crew put to work gave +0.4% income at the time and about 2.5% over the next three check-ins: their output feeds goods the station takes, or saturated markets.
- **11.9–14.7 d:**
  - Mass Driver level 14, the 300B milestone and Orbital Station level 13;
  - income grew about 2% a day;
  - Mass Driver level 15 asks for 92.9B credits plus 82M hull plate and 328M copper wire, about 3 days out.

## Day-by-day

| Day | Credits/s | Bodies | Station lvl | Mass Driver lvl | What was new | Mood |
|---|---|---|---|---|---|---|
| 0 | 1.65 → 92 | 2 | 0 | 0 | circuits, Brine, module works | 5 |
| 1 | 611 → 18K | 4 | 0 | 0 | habitats, kits, Cinder and Hollow Reach, magnets | 4 |
| 2 | 30K → 85K | 7 | 0 → 4 | 0 → 4 | station opens, surveys, Tessaly, Dusk Cairn | 5 |
| 3 | 106K → 170K | 7 | 4 → 7 | 6 → 9 | contracts for megaproject goods (I discarded them) | 4 |
| 4 | 188K → 245K | 7 | 8 → 9 | 9 → 10 | nothing left to claim or survey | 3 |
| 5 | 247K → 299K | 7 | 9 → 10 | 10 → 11 | — | 3 |
| 6 (6.77) | 326K → 359K | 7 | 10 | 11 → 12 | — | 2 |
| *10-day gap* | shows 223K (real 392K) | 7 | 11 | 12 | 22 h counted | 3 |
| 8 | 398K → 451K | 7 | 11 | 13 | — | 3 |
| 9 | 455K → 490K | 7 | 12 | 13 | +270 crew from 2 habitats | 3 |
| 10 | 496K → 501K | 7 | 12 | 13 | 340 crew idle, no hint | 2 |
| 11 | 502K → 515K | 7 | 12 | 13 | build spree: +2.5% | 2 |
| 12 | 548K → 559K | 7 | 12 | 14 | 300B milestone | 2 |
| 13–14.7 | 577K → 641K | 7 | 13 | 14 | — | 2 |

## First 30 minutes back, minute by minute
- **m0:** the headline. "Away 10d; 22h counted" is honest. "net +140M" says 10 days were worth less than one normal 6 h check-in (+160M). This felt like being punished for leaving, even though 30B was really earned.
- **m1:** `state`. The board held the same three contracts as 10 days ago. Nothing gave their age, and no new contract had been posted. I remembered my goal only because the station's `stillNeeded` was there. Nothing said "you were building toward X".
- **m2:** `report` showed 223K/s against 361K before I left, with no bottleneck at all. My first thought was that something had decayed while I was gone. Nothing had: the figure is wrong (see Bugs).
- **m3:** `costs` and nextGoal: "Mass Driver level 13 still needs 9.27B credits and 20.5M Hull Plate and 82M Copper Wire and 41M Water and 8.2M Silicon Wafer; in 23h 3m". It was accurate, but it read as a shopping list, not a goal.
- **m4:**
  - `deliverContract c136` with no amount failed (a known issue).
  - Retrying with the amount worked: 144K magnets from two bodies and +581M. That was the one good moment.
  - At the next game minute auto-pay swept the 581M (credits 212M → 206M).
- **m5:** discarded the two 10-day-old orders for station segments and drones (270K and 230K).
  - Side effect: the dump of the freed holds on Hollow Reach switched both megaprojects to goods feeding at once, about a day early. This is the "one-minute spike" the docs describe, and nothing on screen says it happened.
  - I measured it: it cost about 1% of 12 h of income, so it is harmless.
- **m6:** `report` now showed 7 "takes 100% of …" rows, plus "Orbital Station still needs Survey Drone, but Hollow Reach keeps 500 of it back". That was the game reminding me of my old keep rule. Useful.
- **m7:** removed the keep rule.
- **m8:** buy-max with 200M bought 7 levels.
- **m9–10:**
  - 21 free crew, which arrived with the station's housing bonus.
  - Built a station dock for 20K, against 11M for one upgrade level. New buildings are absurdly cheap next to upgrades, but slots and crew limit them.
  - Raised the circuit route and bought 6 extra slots.
- **m11–18:** waited. A second buy-max bought 75 levels, 73 of them on the new dock (16 capacity, taking all the free crew).
- **m19–26:** nothing left to do. I closed the game.

**Verdict:** back on track in about 10 minutes, but there was little fun to get back to. The cleanup was the session. The first "number goes up" moment came at the next check-in: 398K/s and 6.8B earned.

## Fun, length, coming back
- **Fun:** days 0–3 are excellent: every check-in unlocked a chain, a body or a station level. After day 4 a check-in is "discard 1–2 absurd contracts, buy 3–15 levels, leave". The only meaningful decisions after the gap were spending a pile of idle crew and modules, and the game never pointed me to either.
- **Length:** content ran out by day 3.5, before the gap: no bodies left, nothing to survey, every building type built. The gap changed nothing. Megaproject levels keep coming, each 1–2 days apart.
- **Coming back:**
  - Nothing decayed: routes, caps, rules and megaproject progress were all intact. Orbital Station level 11 completed while I was away, which was a nice "welcome back".
  - But the return showed a frozen board, a false income drop and a net that looked like nothing. A real lapsed player would likely read those as "the game stalled without me" and not come back a second time.
  - Being 9 days "behind" doesn't matter in a single-player game. What matters is that the return gives nothing new to do.

## Best and worst moments
- **Best:**
  - 2.27 d: station level 1 with no hauling;
  - the return delivery of 144K magnets from two bodies for 581M;
  - the keep-rule reminder;
  - finding 1.7K forgotten habitat modules (+270 crew).
- **Worst:**
  - the "net +140M" after 10 days;
  - the phantom 38% income drop on return;
  - the same three contracts sitting on the board as when I left;
  - 340 idle crew for three check-ins with no line about it.

## Where I'd quit
On the second return after a lapse. The first one taught me that leaving costs nothing and coming back offers nothing: same board, same buy-max tap, the next level two days away. As a lapsed player I'd quit around day 10–11.

## Bugs
1. **The return income figure reads 38% low, with no reason given (new).**
   - **What happens:** right after the gap, `away.creditsPerSecAfter` and `report.creditsPerSec` both say 223K/s, against 361K before I left, and `topBottlenecks` is empty. The real rate is higher than before.
   - **Cause:** `report.autoDeliveredPerSec.mass_driver` counts hull plate, copper wire, wafers and water as being fed, while `state.megaprojects[mass_driver].auto.goodsFedNow` is `false`. The engine only starts feeding them about 1.5 h later.
   - **Repro:** `--seed 9 --load docs/playtests/round5/repro/p09/post-gap.json --script docs/playtests/round5/repro/p09/return-income-drop.jsonl`. It gives report 223K, both `goodsFedNow` false, then `away` 3600 earns 1.41B (392K/s, above the 361K before the gap), and Mass Driver gets credits only.
   - **Not only after gaps:** scanning my saves, report and state also disagree at c015, c017, c019 and c025.
   - **Effect for a returner:** "my income fell while I was away" is the worst first impression possible.
2. **The away summary after a 10-day gap shows no stale state (lapsed angle on a known issue).**
   - `contractsPosted` is `[]`, `contractRefills` is `[]`, and contracts carry no posted or age field.
   - Pre-gap `report` had a contract-hold bottleneck (c129 holding 52.8K segments the station needs). After the gap it was gone from `topBottlenecks` and from `report`, because the next stage wasn't near ready yet.
   - A returner gets no prompt to clear 10-day-old orders.
3. **Things I met that are already known:** the crew sponge, the frozen board, `deliverContract` without `amount`, auto-pay sweeping the contract reward, and the misleading net in the headline.
4. **A minor one I did not check further:** the bottleneck says "raise route r47's rate (1/s → 10/s)" while the real limit was ships (one ship carries 10/s, and Cinder made 8.7K/s).

## Top 5 changes (for the lapsed and returning player)
1. **Welcome-back briefing when the gap is over the cap** (now for the data, stage 2 for the UI; S–M). It would:
   - lead with what got done: "30B earned; 29.9B into megaprojects; Orbital Station level 11 done; Mass Driver level 13 is 57% paid";
   - not lead with "net +140M";
   - remind you what you were working toward;
   - list stale things: contracts over 2 days old, keep rules holding goods, idle crew and unused modules;
   - suggest 2–3 actions.

   It turns the bigger numbers you missed into a satisfying recap, and gets you back to optimizing within a minute.
2. **Fix the return income figure** (now; S). Make `report` and `creditsPerSecAfter` use the engine's actual feeding state. If they must forecast, label it ("Mass Driver starts taking goods in 1h 30m: −38%"). A falling number on return looks like punishment.
3. **Contract expiry and a fresh board during long absences** (now; S). Orders over N hours old lapse quietly, and new ones are posted on return. Without it there are no decisions on return, and the board stays frozen (a known issue); a returner is hit hardest.
4. **Flag idle crew and unused habitat modules** (now; S). For example "340 crew are free: build or raise capacity", or "1.7K Habitat Modules on Kora: build habitats". These were my two biggest finds after the gap, and nothing on screen pointed to either. They serve both ratio optimization and slow building.
5. **Something that happens while you're away** (stage 3; M–L). Exploration probes or survey ships that keep working offline and come back with a new signal or body. A pirate or trade event log for the absence. A new problem to solve on return is an intrinsic reason to come back, with no streaks needed. It extends length past day 4 and gives the returner a "what's new" moment.
