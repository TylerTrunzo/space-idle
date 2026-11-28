# Playtest round 5, tester #3: Snacker (seed 3)

## Persona and run
- **Seed:** 3, engine eea9d07. HEAD is 52a5e5c, which only adds a docs file.
- **Game time:** 0 to 240 h (10 game days).
- **Check-ins:** 80 sessions, 8 a day. Gaps were 2 / 2 / 1.5 / 2 / 2.5 / 2.5 / 2.5 h, then a 9 h night. Each session was `away`, one decision, then `advance 120`.
- **Automation:** one Python helper ran each session (actions, advance 120, away gap, state) and printed a "phone screen" (headline, next goal, top 3 bottlenecks, credits). From day 7 a batch runner played sessions whose only decision was buy-max or "look and close". I still read every summary. I wanted to automate the "nothing to do" sessions from about day 6, and that is a finding in itself.
- **Files:** everything is in `/tmp/claude-0/-home-user-space-idle/7963d8b4-7ef1-5bbc-9bff-b2b24979e3ee/scratchpad/r5/p03-snacker/`.
  - `replay.jsonl` replays the whole run from a new game with `--seed 3`. I checked it: it ends at 240 h, station 10, Mass Driver 12, 51 milestones.
  - `all.jsonl` is the same with a session tag before each block.
  - `cur.json` is the end state; `save_D10S3_start.json` is the state at 220 h.
- **Honesty about "one decision":** I bent the rule on days 3–5. The habitat chain and the station chain cannot be built one tap per session. D5S6 alone was 7 commands: 2 demolishes, 3 builds, 2 routes.

## Timeline highlights
- **0 h:** nothing sells until you set auto-sell. The first decision is invisible unless you read the docs.
- **2 h:** I tried to deliver the first contract. The CLI refused it because `amount` is required, so that session's decision was lost.
- **5.5 h, first buy-max:** 37K bought 75 levels and income went from 1.64 to 29/s. This is the best hook in the game.
- **10 h, second buy-max:** 32 to 264/s. Contracts paid 476K for 4.4K copper ore that sells for about 220 credits. Free money, not a decision.
- **15 h to 128 h:** the contract board froze. It held three day-1 contracts worth about 475K each, with `contractRefills: []`, for 4.5 days. Income meanwhile rose from 264/s to 86K/s.
- **31 h:** I built a wire mill, then tapped buy-max: 265 to 2.53K/s. The real loop is "build a new building type, then tap buy-max: ×3 to ×10". Nothing in the output ever suggests building.
- **36 h:** circuits, wafers and silicon were wasted. The summary said "storage full" with lost/h figures, and auto-selling them was an obvious one-tap fix.
- **53 h:** I cut the plate press from 6 crew to 2 to staff new buildings. Income fell 26.5K to 16.7K/s and nothing told me why.
- **72–74 h:** I built one habitat. Buy-max then bought 15 habitat capacity levels (housing 40 to 115) and sank 95 crew into Brine's ice and food buildings. That wasted 177M/h of goods by the summary's figure; auto-selling them gained only about 27M/h.
- **96 h:** I tapped buy-max before bed on a new body with no auto-sell rules. I woke to "wasted value 1.37B" against 1.22B earned.
- **106–111 h:** built the magnet chain, reactor works, drone works and a station dock, then turned on station auto-feed. For the first time the next goal named the station: "level 1 still needs 51 Station Segment; in 1h 42m".
- **120 h, best moment:** "Orbital Station reached level 3", with levels 1, 2 and 3 all done overnight and nothing hauled by hand. 40K to 58K/s.
- **125–132 h:** auto-pay swept credits to 0.14. Buy-max said "Bought no upgrades: the cheapest costs 26.3M" with no word about auto-pay. I set a 400M reserve by hand.
- **150–230 h:** each session was "look, close". Buy-max bought 2 to 5 levels for 400M. Contracts asked for station segments, survey drones and reactor cores, so I had to discard them three times.
- **178 h:** I noticed the plate press still at 2 of 7 crew, with 115 crew free. Restoring it took income from 250K to 240K... correction: from 181K to 240K/s (+33%), the biggest single lever since day 5. The game never flagged it.
- **240 h:** 314K/s, station 10 (level 11 needs 205K segments at 0.8/s, about 3 days), Mass Driver 12, 51 milestones.

## Day by day
| Day | credits/sec (end) | Bodies | Station | Mass Driver | What was new | Mood |
|---|---|---|---|---|---|---|
| 1 | 264 | 1 | 0 | 0 | auto-sell, contracts, buy-max 1.6 → 264 | 4 |
| 2 | 7.25K | 2 (Brine empty) | 0 | 0 | wire mill, circuit line, ×10 buy-max | 4 |
| 3 | 21.9K | 2 | 0 | 0 | plate press, modules, shipyard, Brine life support, first habitat | 3 |
| 4 | 37.8K | 3 | 0 | 0 | housing 115, fuel, outpost kits, Cinder; 1.37B wasted overnight | 2.5 |
| 5 | 58.3K | 5 | 3 | 0 | magnets, cores, drones, docks; station 1–3 overnight | 5 (morning) |
| 6 | 137K | 5 | 7 | 7 | Mass Driver, auto-pay, reserve | 3.5 |
| 7 | 168K | 5 | 9 | 9 | second dock, contract discards | 3 |
| 8 | 250K | 5 (+2 surveyed) | 9 | 10 | surveys, extra slots, crew fix +33% | 3.5 |
| 9 | 286K | 6 | 10 | 11 | Dusk Cairn claimed (nothing to do with it) | 2.5 |
| 10 | 314K | 6 | 10 | 12 | nothing | 2 |

## What I did each session, and how long a real person would take to work it out
- **Day 1:**
  - Auto-sell steel and copper ore. About 5 minutes; only the docs say nothing sells.
  - Deliver a contract (CLI error). Then deliver it (1–2 minutes; the away summary never says a contract is ready).
  - Buy-max (instant). Auto-sell iron ore (instant: the waste row says so).
  - Buy-max. Deliver 3 contracts (1 minute). Build a wire mill (5+ minutes: you have to know chains and read the catalog).
- **Day 2:**
  - Move a crew member (about 3 minutes: "Wire Mill has no crew", but no hint where crew comes from). Claim Brine (curiosity).
  - Auto-sell copper wire (instant). Buy-max.
  - Free mine crew and build a silicon, wafer and circuit line (10+ minutes). Buy-max.
  - Auto-sell 3 wasted goods (instant). Buy-max.
- **Day 3:** plate press, buy-max, module works and shipyard, ice drill and melter, electrolyzer and protein vat, habitat-module route, habitat. All of these needed the catalog and the content rules: 5–15 minutes each, and the whole housing loop took me about 30 minutes to plan.
- **Day 4:**
  - Buy-max. Auto-sell all of Brine (instant).
  - Fuel refinery and kit assembler (10 minutes). Move ships (the route failed with a clear "Needs 1 Cargo Ship on Brine").
  - Fuel route. Claim Cinder (1 minute: the claim cost names the kits). Two Cinder mines. Buy-max at night (a mistake).
- **Day 5:**
  - Auto-sell the waste (instant). Claim the two remaining bodies.
  - Three habitats. Nickel mine and magnet works.
  - Rare-earth route and He-3 skimmer. Docks, reactor works, drone works and routes (20+ minutes).
  - Station auto-feed (5 minutes: you must know the command exists). Buy-max.
- **Day 6:** Mass Driver auto-feed, buy-max, auto-sell the waste, auto-sell He-3, clear stale contracts, buy-max (bought nothing), set a reserve (10+ minutes to work out why buy-max bought nothing), buy-max.
- **Day 7:** second dock (5 minutes), buy-max, look, buy-max, look, buy-max, discard 3 contracts (2 minutes: the "holds … the station needs" row gives the clue), buy-max.
- **Day 8:** look, buy-max, survey (5 minutes; signals appear only in `state`), a typo session, restore plate press crew (30+ minutes; I found it by accident in the raw report), buy-max, expand a slot, build a dock.
- **Day 9:** discard contracts, claim Dusk Cairn, dock, buy-max, look, buy-max, discard, buy-max.
- **Day 10:** look, buy-max, discard, buy-max, a failed build (wrong building type; the error says why), buy-max, look, buy-max.

## Fun, length, coming back
**Fun.** Days 1–2 are excellent for a snacker. One tap of buy-max multiplies income 3–10×, the numbers jump, and the waste rows give one-tap fixes. Day 5 morning was the peak: the station gained three levels overnight. From day 6 the sessions are empty. Credits sit at the reserve, buy-max buys 2–5 levels per tap, and the "one decision" is usually "close the app" or "discard contracts that hoard station goods". Building the station chain (days 3–5) was work, not play: 25 or more taps across 10 sessions, mostly crew shuffles and routes, with income flat at about 22K–40K/s for two days.

**Length.** New content dried up from about day 5, as already known. After that only megaproject levels and credit milestones were left. Surveys (day 8) were a nice surprise but gave two more ice/ore bodies I had no use for. Station level 11 is about 3 days of segments away at day 10, so the next "big" moment is far off. My horizon as a snacker is about day 7–10.

**Coming back.** I came back for the overnight project completions and the early ×10 taps. I would quit over sessions where the most useful action is nothing, and a contract board that needs weeding. Snacking is neither rewarded nor punished late:
- **Days 0–2, buy-max only:** 8 sessions a day ended at 2.53K/s with 93.6M banked, 4 a day at 2.51K/s with 59.5M, and 1 a day at 48/s. Short sessions help a little over 4 a day and a lot over 1 a day.
- **Days 9–10:** my 6 sessions from 220 h to 240 h earned about 21.5B and ended at 314K/s. One 20 h away from the same save earned 21.2B and ended at 300K/s, with the same levels and milestones. The offline cap is 22 h at station 10, so frequent check-ins buy about 1–2% plus contract weeding.

## The three pleasures
- **Numbers growing:** yes, and spectacularly on days 1–2 (1.6 → 7.25K/s). From day 7 it is slow (168K → 314K over 3 days), with no tap that moves it.
- **Slow building:** overnight megaproject levels feel like anticipation done right. The 2 h claim and survey timers fit the snacker cadence well.
- **Optimization:** the levers that matter are invisible:
  - crew in capacity slots (+33% from one reassign on day 8);
  - which goods sell at all (ore prices hit 0.00–0.01);
  - dock speed versus capacity.
  The summary shows waste, not levers.

## Clarity
- The away summary is good at "you are wasting X: auto-sell it".
- It never says "build something new". That is the real ×10 action for days 1–3.
- The next goal is usually a passive milestone ("Nothing Lost in 22h", "Ten Billion"). It named the station only after I turned on auto-feed.
- Waste "lost/h" figures use list prices, so they overstate badly (detail under Bugs, item 2).
- **What I want on one screen:**
  1. income and its change since the last session;
  2. the one best action with its gain ("Plate Press has 5 empty crew slots: about +30%", "New: build a Wire Mill", "3 goods unsold: auto-sell all");
  3. the next megaproject level with what binds it ("Station 11: segments, 3 days at 0.8/s");
  4. a buy-max button that says what it will buy.
- **Noise at this cadence:**
  - the contracts board after day 1;
  - `megaprojectDiversion` rows of 1.68M/h against 1B/h income (always in the top 3 on days 8–10);
  - "2 buildings have no crew", where I left them empty on purpose;
  - "Nothing Lost" as the next goal.

## Best and worst moments
- **Best:**
  - Waking at 120 h to "Orbital Station reached level 3" (levels 1–3 overnight, no hauling).
  - The first buy-max taps (×18 and ×8).
  - The wire mill plus buy-max giving ×10 on day 2.
- **Worst:**
  - 96 h: "wasted value 1.37B" after a bedtime buy-max on a body with no sell rules.
  - 53 h: one crew reassign cut income 37% with no explanation.
  - 132 h: "Bought no upgrades" because auto-pay had swept everything.
  - Days 7–10: discarding station-goods contracts three times.

## Where I'd quit, and why
Around day 9–10. Income grew about 10% a day, every session was "look, nothing to do", buy-max did nothing visible, and the only regular chore was weeding contracts. The next goal was "Hundred Billion in 20h". I would have dropped to 1–2 opens a day by day 7. Given the cap, that loses nothing, which tells a snacker their habit doesn't matter.

## Round-4 problems I met
- **Megaproject levels stop paying back (§2.1): better.**
  - Station 1–3 on day 5 (about 112–120 h, matching the casual bot's 108 h). Station 10 on day 9; Mass Driver 12 on day 10.
  - Levels landed every 1–2 sessions on days 5–7, then every 1–2 days.
  - Station 11 is walled by 205K segments, which are made by docks where buy-max buys capacity rather than speed (dock speed level 18 against level 70+ elsewhere).
- **Mass Driver worth (§2.2): better.** Level 12 gives sale price ×1.71 on tiers 1–2. Income steps of +5–15% coincided with its levels (D6S3: 69.5K to 81.5K/s with Mass Driver 2 and station 5). I could not isolate it exactly.
- **The away summary misleads (§2.4): mostly fixed, two gaps.**
  - Grouping works ("2 buildings on Kora have no crew"). No false 0% seen.
  - The diversion rows exist but are tiny and permanent.
  - Next goal: passive milestones, and it ignores megaprojects until auto-feed is on (already known).
  - New gap: list-price waste figures (Bugs, item 2).
- **Hidden route throughput (§2.5): not really met.** Route replies were clear; the "Needs 1 Cargo Ship on Brine" error tells you what to do.
- **Contracts are never a decision (§2.6): worse for a snacker.**
  - Day 1: pure free money (476K for ore worth about 220 at sale price, because the 30-minute-of-income floor sets the reward).
  - Days 1–5: stale and frozen.
  - Days 6–10: almost every order asks for station or Mass Driver goods and hoards them, so discarding is a chore.
- **Auto-pay sweep (§2.7): same.** I needed a manual reserve, and buy-max's reply doesn't explain it.
- **Crew irrelevant after day 2 (§2.8): better.** Crew was the gate on days 2–4, and housing grew 20 → 585, mostly through buy-max buying habitat capacity. Empty capacity slots are invisible, though (Bugs, item 3).

## Bugs
All of these replay from `replay.jsonl` with `--seed 3`.
1. **The contract board freezes with stale contracts (not in the known list).**
   - Contracts c9, c10 and c11 were posted at 15–26 h with rewards of about 475K, fixed at the 264/s income of the time.
   - They sat on the board until I cleared them at 128 h, while income reached 86K/s. No expiry, no refill (`state.contractRefills: []`), and nothing new was posted.
   - Check: `state` at any point from about 30 h to 127 h.
   - Expected: contracts expire or rescale, or the board refills anyway.
2. **Waste "lost/h" overstates by 6–18× (new, as far as I can tell).**
   - D4S1 (74 h): five Brine "storage full" rows totalled about 177M/h. Auto-selling all five raised income by 7.5K/s, about 27M/h.
   - D5S1 (96 h): about 153M/h shown, about 8.6M/h gained.
   - Cause: the figures price wasted output at today's unsaturated list price. They should use the price selling it would actually settle at.
3. **Empty capacity slots are never flagged (new).**
   - The plate press (b16) sat at 2 of 7 crew from 51.5 h to 178 h, with up to 129 crew free. No bottleneck, because `understaffed` compares only against base slots.
   - Restoring the crew: income 181K to 240K/s.
   - Repro: load `cur.json` after removing crew from a building that has capacity levels; `report` shows nothing.
4. **Buy-max's reply hides why it bought nothing.** At 130 h with credits at 0.23 (auto-pay sweep), the reply was "Bought no upgrades: the cheapest costs 26.3M credits". It should say that auto-pay took the credits and point to the reserve.
5. **The next-goal ETA ignores contract holds.** D7S6 (156 h): "Orbital Station level 9 still needs … 51.2K Station Segment; in 4h 57m", while contract c66 held 45.2K segments. The contract-hold row exists (already known); the ETA is the new part.
6. **New goods with no sell rule aren't flagged until storage fills.** Circuits at D2S5 showed no `noSales` row, which only fires when nothing sells at all.
7. **Minor:**
   - `deliverContract` with no `amount` fails ("command field amount must be a string"), though "deliver the amount shown" suggests a full delivery is the default.
   - Buy-max put 28 efficiency levels on Module Works and Shipyard, whose output was about 0.003/s and unsold, at 54 h.

## Top 5 changes
1. **A "best next action" line in the away summary, ranked by income gain.**
   - Stage: now (engine computes it), and stage 2 (one card in the app).
   - Effort: M.
   - Candidates: "build a new building type you can make", "fill N empty crew slots", "auto-sell N unsold goods", "a dock speed level gives +X segments a day".
   - Why: the ×10 actions on days 1–3 and the +33% crew fix were invisible. This turns optimization from reading the content files into a visible lever, and keeps the numbers jumping.
2. **"Sell surplus" on by default for new goods, or one auto-sell-all toggle per body.**
   - Stage: now. Effort: S.
   - Why: about a third of my early sessions went on setting sell rules, and forgetting one cost a whole night (1.37B wasted). This removes chores and protects the overnight build-up.
3. **Contracts that expire and refresh, and never ask for goods a fed megaproject needs.** Also a one-tap "deliver all ready".
   - Stage: now. Effort: S–M.
   - Why: today the board is first free money, then frozen, then a hoarding chore. Fresh, sized orders would give a snacker one real choice a day ("sell or take 2×?").
4. **Buy-max judged by value, not price.**
   - Stage: now. Effort: M.
   - Split the speed and capacity counters, skip output that is unsold or wasted, and value megaproject-bound output by how much sooner the next level lands.
   - Report how much income it added, and say when auto-pay emptied the wallet.
   - Why: late game, the one button a snacker has does nothing. Making it build toward the next station level would restore "tap and the number grows". Part of this is already known; the snacker angle is a dead button.
5. **A logistics helper: "supply this building" sets up routes and ships, and a chain blueprint ("build the station line").**
   - Stage: 2 for the UI; stage 3, where cargo ships, ship customization and pirates make routes worth defending and decorating.
   - Effort: L.
   - Why: the station chain took 25+ taps across 10 sessions and about two flat days. Making it a satisfying slow build rather than a chore protects the best moment of the run, the overnight station levels.
