# Playtest round 3: New player, seed 3, first game day (0–24.1 h)

Source: a subagent playtest. The scratch files it mentions were in the session scratchpad
(`r3-newplayer/`) and are not kept in the repo.

## Persona and run
- **Persona:** a new player. Learned only from the simulator's output, docs/playtesting.md, content/README.md and spec
  sections 1–2. Did not read the content JSON or the source. Read the round-2 findings only after playing, to fill in
  the comparison table.
- **Seed 3**, 0 h to 24.1 h of game time, 8 sessions: an active first hour, then check-ins at 4.0, 7.1, 10.7, 14.4,
  17.7, 21.6 and 24.1 h, using `away` for the gaps.
- **End of day 1:**
  - 59 cr/s.
  - 4 bodies owned, with a 5th (Dusk Cairn) being claimed.
  - Orbital Station level 0: 40 drones and 100K credits delivered so far.
  - 21 of 42 milestones.
  - About 3.5M credits earned in total, about 414K of it from contracts.

## Timeline highlights
- **0:00** – 0 cr/s and `"bottlenecks":[]`. Nothing in the game said auto-sell had to be set; only the docs did. The
  building list turned up only after sending a fake building type (`"defId":"help"`).
- **0:01–0:09** – A contract asked for 10 hull plates for 6.04K, about 50 minutes of income. Built a plate press and
  delivered. It felt like a jackpot.
- **0:09** – Claimed Hollow Reach for 5K (30 min). Capacity upgrades turned out to double output; speed upgrades gave
  +10%.
- **0:27–0:55** – Learning what buildings need, one failure at a time:
  - Spent 2.5K on an Outpost Kit Assembler on Kora; it said "not enough Fuel".
  - At 20/20 crew, the habitat needed a module. The module works first said "not enough Hull Plate", then "not enough
    Circuit".
  - The first habitat at 0:55 took crew to 40.
  - Spent 8K, two-thirds of the bank, on Drone Works. It said "not enough Magnet", and 7 hours later "not enough Fuel".
    It sat idle until 7.6 h.
- **4.0 h** – 3 h away earned +148K. A contract paid 30.8K for 100 iron ore (market value about 100). Claimed Cinder
  (40K + 10 kits).
- **7.1 h** – Set up the magnet chain (nickel from Hollow Reach, rare earths on Cinder), ship moves and a fuel route.
  Drones started flowing. Started the first survey.
- **10.7 h** – **Best moment:** the survey revealed Tessaly, a richer ice moon. A contract paid 170K for 2 station
  segments (market value 2K). Built a Station Dock and claimed Tessaly (320K). Reactor Works then said it needs
  Helium-3, which no owned body had.
- **14.4 h** – The second survey found Dusk Cairn, with Helium-3 at 1.4 richness. That gave a clear goal. Two Tessaly
  habitats took crew to 105.
- **17.7 h** – Housing had quietly dropped from 105 to 91 while away, because Tessaly ran short of water. The away
  summary did not say so. A steel contract half-failed because the player's own auto-sell rule sold the steel being
  saved.
- **24.1 h** – A contract posted 100 station segments for 426K. Claimed Dusk Cairn (2.56M, 2 h). The next claim now
  costs 20.5M.

## Round-2 problems

| Problem | Verdict | Evidence (day 1, new player) |
|---|---|---|
| Content running out | **Better** (too early to call fully) | At 24 h: 21 of 42 milestones, station level 0. Vastmere and Brine were unclaimed (next claim 20.5M). In round 2 a designer owned the whole system on day 1. |
| Crew dominating | **Better, still dominant early** | Capacity on a 1-slot mine costs 300–900 and doubles output; speed costs 50–400 for +10%. About 40 capacity levels bought, few speed levels. The difference now is that crew needs real habitats, with water, food and oxygen chains and modules, so it is a puzzle rather than free. |
| Market floor wall | **Not reached** | Every good still sold at saturation 0.91–1.0 at 24 h. Contracts and the station now take tier-3 goods, so the early signs are good. |
| Nothing taking time | **Fixed** | Claims took 30 min, 1 h, 1.5 h and 2 h; extra slots 1 h; surveys 3 h. Every check-in found a finished project. Equipment no longer floods: about 73 modules and 98 kits in a day, against 715 in one nap in round 2. |
| Hidden rules and silent failures | **Better, not fixed** | Error messages are now excellent: `depositMissing` lists what a body has, `stillClaiming` gives the time left, `cannotAfford` names the body. Still hidden or silent: see the confusion list (items 3–6, 11–13). |
| Weak away summary | **Better** | The headline, completed projects, posted contracts and "ongoing since" marks all help. It is missing housing or crew changes (105 → 91 never appeared) and the change in cr/s. |

## Day-by-day table (one game day, so by check-in)

| Time | cr/s | Bodies | Station | What was new |
|---|---|---|---|---|
| 0–1 h (active) | 0 → 12.4 | 1 → 2 | 0 | 8 milestones, claim, first contract, first habitat |
| 4.0 h | 18 → 20.5 | 2 (+Cinder claiming) | 0 | Contract, claim, extra slot |
| 7.1 h | 22 | 3 | 0 | Cinder done, magnets and drones, first survey |
| 10.7 h | 24 → 32.5 | 3 (+Tessaly claiming) | 0 (first delivery) | Hidden body found, Station Dock, segment contract |
| 14.4 h | 32 → 40 | 4 | 0 | Second survey (Dusk Cairn), Millionaire, +40 crew |
| 17.7 h | 51 → 58 | 4 | 0 | **Contracts only**, plus repairing the crew drop |
| 21.6 h | 59 | 4 | 0 | **Contracts only** (5K copper ore) |
| 24.1 h | 59 | 4 (+Dusk Cairn claiming) | 0 | Claim, 426K segment contract, 3M milestone |

**Pacing.** Every visit had something to do. The two contracts-only visits still had a decision in them, but the
copper-ore one was a chore: turn off auto-sell, wait, come back.

**Slow building.** The survey timers were the best anticipation in the game: a 3-hour timer matches a check-in, and the
reveal is a surprise. The station felt like a distant list of numbers on day 1: 4.9M credits, plus Helium-3 that sits
behind a 2.56M claim.

**Contracts.** Fun, but far too rewarding early:
- 6K for 10 plates at minute 9;
- 30.8K for 100 iron ore;
- 170K for 2 segments.

Early on they outweigh production.

## Every confusing moment, with the exact output
1. **t=0:** `"creditsPerSec":{"display":"0"}` with `"bottlenecks":[]`. Nothing says "nothing sells; set auto-sell".
2. **t=0:** `"contracts":[]` next to `"contractRefills":[{"at":0.0,"timeLeft":"0s"},...]`. A refill is due in "0s",
   but the board is empty.
3. **No catalog.** Sending `"defId":"help"` was the only way to get `"There is no building type help. Kora can build:
   Mine (mine), Smelter (smelter), ..."`. The list has names only: no cost, crew or recipe.
4. **Costs show up only when you can't afford them:** `"Needs 250 credits (you have 249)"`. Drone Works' 8K cost was
   learned only after buying it.
5. **Recipes come one missing input at a time:**
   - Module Works: `"not enough Hull Plate"`, then `"not enough Circuit"`.
   - Drone Works: `"not enough Magnet"`, then `"not enough Fuel"`.
   - Magnet Works: `"not enough Nickel"`.
   - Kit Assembler: `"not enough Fuel"` (it also needs circuits and plates).
6. **Capacity upgrade:** `{"ok":true,"spent":{..."842"}}` and nothing changed. The report showed `crew 1 / 2` with no
   bottleneck. Crew is not assigned and nothing says so.
7. **A milestone name that does not match:** `"Ten Thousand Credits"` was reached while holding 1.68K. No milestone shows
   what comes next or how far along you are.
8. **An unexplained loss figure:** `"Protein Vat ... not enough Water", "lostCreditsPerHour":"3.24K"`. That is food
   never sold.
9. **Ship landing time is slightly off:** `"Sent 1 Cargo Ship ... it lands in 2m"`. Exactly 2 minutes later:
   `"Needs 1 Cargo Ship on Hollow Reach (you have 0)"`.
10. **Route travel time is not shown:** `"Created route r58: Habitat Module from Hollow Reach to Tessaly ... pausing
    while Tessaly holds 5"`. Then the state showed `'paused': True` while Tessaly held 0, because the cargo was in
    flight to another system and the trip is long.
11. **Housing fell silently:** `crew supported 105 → 91` across an away. The away `topBottlenecks` listed only
    `storageFull`. There is no `crewShortage` because assigned (80) stayed under supported.
12. **A contract competes with auto-sell:** after 13 minutes of saving steel, `"Delivered 100 Steel ... (282 of
    1.3K)"`. The keep-100 rule had sold the rest, and nothing warned about it.
13. **A nag that hides the real problem:** `"Reactor Works on Cinder has no crew"` was `"ongoing since 10.8h"` all day.
    The real block is Helium-3, and nothing says where Helium-3 is found.
14. **The station lists `reactor_core` as a cost** without saying which building makes it or what that building needs.
15. **Claim costs grow ×8 per claim without explanation:** 5K → 40K → 320K → 2.56M → 20.5M. It shows only in `costs`.
16. **Slow outputs read as zero:** `outputs {'outpost_kit': '0'}` and `{'habitat_module': '0'}`. They look broken.
17. **The survey project leaks its target:** `'targetId': 'tessaly', 'name': 'an unsurveyed body'` gives away the hidden
    body's id. The signal count also stays at 2 while the survey runs.
18. **No warning when crewing an idle building:** `assignCrew` on Reactor Works, which has no Helium-3, replies
    `{"ok":true}`.

## Best and worst moments
- **Best:**
  - The survey reveals at 10.7 h and 14.4 h: a richer moon, then the Helium-3 body.
  - The 170K segment contract.
  - Crew jumping from 65 to 105 when the Tessaly habitats came online.
- **Worst:** 0:27–0:55. At 20/20 crew, with Kora full, each building gave its inputs one failure at a time. 8K went on
  Drone Works, which then sat idle for 7 hours.

## Where I'd quit, and why
- **Around 0:40–1:00 (quit risk).** The whack-a-mole of dependencies cost most of the bank, and nothing pointed at a next
  step. The contract windfall kept the player in.
- **At 24 h (second risk).** The station needs 4.9M credits, plus a Helium-3 chain behind a 2.56M claim, and the next
  claim after that is 20.5M. Without Dusk Cairn's 2-hour timer and the 426K contract, the thread would be lost.

## Bugs
1. **`state` and `report` disagree on housing by one tick.** Load the save from t=63600 (seed 3) and send `state`,
   `report`, `advance 60`, `state`, `report`:
   - At t=63600, `state` says `supported 91`, but the report shows the Tessaly habitats b59 and b60 at runFraction 1.0
     with no habitat bottleneck.
   - At t=63660, `state` says `supported 105`, but the report shows them at 0.67 with `"Habitat on Tessaly is running
     at 67%: not enough Food"`.
   - Water on Tessaly also swings between −0.07 and +0.07 from tick to tick. Housing seems to flicker every tick, which
     is probably why the away summary never shows it.
2. **The empty contract board shows a refill "0s" away** at t=0 (`contractRefills[0].timeLeft "0s"` with
   `contracts []`). Cosmetic.
3. **A survey project's `targetId` reveals the hidden body's id** before the survey finishes. Seen in `state.projects`
   after `{"cmd":"survey","sourceBodyId":"kora"}` at t=27660.
4. **The error code is wrong for a missing upgrade track:** `{"cmd":"upgrade","buildingId":"b1","track":"efficiency"}`
   returns `"error":"unknownDef"`. The message, "Mine has no efficiency upgrade", is fine. Cosmetic.
5. **Ships are not usable at the time `moveShips` gives:** after "lands in 2m", a route created exactly 2 minutes later
   fails with "you have 0". Minor, at the edge of a tick.

## Top 5 changes
1. **A next-step goal strip built from the game state** – stage 2 UI, M.
   - Examples: "Nothing sells yet: set auto-sell", "Drone Works needs Magnets → Magnet Works (Nickel + Rare Earths);
     Nickel is on Hollow Reach", "Next milestone: 3 of 5 contracts".
   - Why: it keeps a new player in the optimization loop instead of guessing; this round, guessing cost 8K.
2. **A building catalog command and a pre-build preview** – now (S), then a stage 2 UI panel.
   - What it shows: cost, crew slots, the full recipe per second, and which owned or known body has each input (for
     example, Helium-3 → Vastmere, Dusk Cairn).
   - Why: ratio planning is the third pleasure, and you can't plan a ratio you can't see.
3. **Make crew and housing changes loud** – now, S.
   - Capacity upgrades should fill free crew automatically, like `autoCrew` on build, or the reply should say "slot 2
     is empty".
   - The away summary should add "Housing 105 → 91: Tessaly habitats short of water".
   - Fix the state/report tick mismatch (bug 1).
   - Why: a silent crash undoes both the slow-building and the numbers-growing pleasures.
4. **Tune early contract rewards, and warn when auto-sell fights a contract** – now, S.
   - Rewards ran 10–300× market value early (6K at minute 9; 30.8K for 100 ore; 170K for 2 segments), so contracts
     outweigh production in the first hours.
   - Lower the income floor for the first day, and warn "auto-sell is selling Steel that contract c63 needs".
   - Why: numbers should grow from the production line, with contracts as seasoning.
5. **Show the path to the station, and soften the ×8 claim escalation** – stage 5 galaxy/megaprojects, M.
   - Name each station input's chain and where its raw goods are found.
   - Show route travel time in `createRoute`.
   - Consider ×4–5 per claim: 20.5M for the 6th body at 59 cr/s is about 4 days with no new body.
   - Why: slow building needs a visible next body or level, not a wall.
