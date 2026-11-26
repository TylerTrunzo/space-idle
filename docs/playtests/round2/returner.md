# Playtest round 2 report: On-and-off returner

## Persona and run
- **Run A, seed 21.**
  - Played 12 check-ins (about 2 game days), then went away 4 days.
  - Then 12 check-ins (60h to 108h), then away 7 days.
  - Then 12 check-ins (120h to 168h).
  - 36 check-ins in total. Game clock ended at 168h, but about 21 real days had passed.
  - Check-ins were 4 hours apart. Each had about 150 s of play with at most 12 to 15 commands, then `away`.
  - The `away` command is capped at 12 h. Each 4-day or 7-day absence advanced the game clock by only 12 h.
- **Run B, seed 22.**
  - One check-in per day, with 600 s of play and at most 25 commands, for 21 real days.
  - It ended at game time 255.5 h, about 10.6 game days. Every real day was capped to 12 h of simulated production plus about 10 min of play.
- I used helper scripts for the tactical routine on every check-in: assign crew; set auto-sell on every output; speed-upgrade the producer of the top input bottleneck; then buy the cheapest upgrades.
- I made the strategic calls by hand: claims, which chains to build, routes and parking crew.
- Scripts, logs and saves are in `/tmp/claude-0/-home-user/7963d8b4-7ef1-5bbc-9bff-b2b24979e3ee/scratchpad/pt2-returner/`.
  - Key saves: `A_t48h.save.json`, `A_t108h.save.json`, `A_end.save.json`, `B.save.json`.
  - Command logs: `A.log.jsonl`, `B.log.jsonl`.

## Timeline highlights (Run A)
- **0 h to 0.1 h:** Built a second smelter and a wire mill, set auto-sell, upgraded the mines. Income about 1 to 3 credits/s.
- **4 h:** First `away` gave +46K credits and "Ten Thousand Credits".
- **8 h:** Claimed Cinder for 5K, which needs no outpost kit. Nothing in the output hints at this.
- **12 h:** Could not claim Brine: kits need fuel, fuel needs Cinder sulfur, and the cargo ships were on Kora ("Needs 1 Cargo Ship on Cinder"). Fixed by routing a ship from Kora to Cinder as a cargo item; non-obvious.
- **16 h to 24 h:** Crew wall (20 of 20). Parked 7 workers to staff Brine; built a habitat, crew support went to 40, then 60.
- **24 h:** A habitat_module route drained 158 modules to Brine, not auto-sold; recovered about 23K by selling.
- **32 h:** Claimed Vastmere for 845K. Third claim needs 3 kits; auto-sell was selling kits down to 2.
- **48 h, then away 4 days:** Returned to +1.23M and "Three Million". Only 12 h simulated for 96 h away, and I was never told what the rest would have earned.
- **60 h to 108 h:** Slow growth (435K to 627K per 4 h), 5M+ idle credits; only sink was the 11M claim.
- **108 h, then away 7 days:** +1.9M, clock moved 12 h. Returned with 9.8M, just short of the 11M claim.
- **128 h:** Claimed Hollow Reach ("Whole System"). Built nickel mine, magnet works, rare-earth route. At 168 h: 7.8M credits, next claim 143M, no sixth body.

## Fun
### Best moments
- First `away` result (+46K) after 5 minutes of play.
- Claiming Cinder, Brine, Vastmere: each opened a new resource and problem.
- The crew and habitat puzzle at 16 h to 24 h.
- Fuel route filling Kora's store and the kit assembler starting.
- Run B: upgrade-only growth to 110/s over about 500 upgrades; the level-25 doubling works well.

### Worst moments
- New buildings are silently uncrewed; only a `noCrew` bottleneck signals it.
- `report` creditsPerSec is wrong (see Bugs).
- Spending is trivial: credits outrun every sink except the next claim from about 40 h (Run A) / day 3 (Run B). Upgrades cost hundreds to ~25K against 400K to 5M per away.
- Run B: every day was "buy 25 speed upgrades"; the 65K claim stayed locked because kits need a fuel route; ended at 37.6M with nothing to buy.
- Run A: about 10 of 36 check-ins had no decision.

## Where I'd quit, and why
- **Run B, real day 5 to 7 (game 60 to 85 h):** 2 bodies, ~20/s, claim shown affordable but fails with "needs 2 Outpost Kit"; path to kits not signposted.
- **Run A, about 100 h to 110 h:** long dead stretch before the 11M claim; upgrade costs irrelevant; after Hollow Reach the next claim is 143M with no body left.

## Length and retention findings
### The away summary
- Fine for a normal 4 h gap (+46K to +860K).
- Does not communicate the cap: raw `secondsAway` 345600 vs `secondsSimulated` 43200, no explicit message. Reads as "lost 7 days, got one day's payout": demoralizing.
- `stockGained` is mostly noise (buffer stocks, negatives like iron_ore -11).
- Milestones in the summary are the nicest part. No next goal offered.

### Is the cap fair?
- 12 h covers overnight. It fails the multi-day returner: 4 days away earns ~12.5% of production, 7 days ~7%; a once-a-day player gets half of every day.
- A 4-day absence forfeits about 9M credits at 28/s active income.
- Spec §6.7 says the cap rises to 48 h through upgrades; no such upgrade exists in stage 1.
- No catch-up, bonus or "welcome back".

### Picking up the thread
- Numbers survive, but no "where I left off" or next-goal pointer; I had to run `state` and `costs` to find the next claim.

### Once-a-day progression (Run B)
- Income 13/s to 110/s over 21 real days from upgrades alone, but meaning plateaus.

### Goals visible at once
- Short: upgrade costs. Medium: next claim, behind a hidden requirement. Long: credit/stock milestones. Nothing connects them.

### Content gaps
- After the 5th body there is no sink at all.

## Pacing and numbers
Real income = credits gained in an `away` / its seconds.

| Run / game time | Credits/s (real) | `report` creditsPerSec | Bodies | Notes |
|---|---|---|---|---|
| A, 4 h | 3.3 | 24.8 | 1 | 10K credits |
| A, 8 h | 9.5 | 498 | 2 | 179K |
| A, 12 h | 11 | 289 | 2 | 329K |
| A, 24 h | 15 | 152 | 3 | crew wall at 20 |
| A, 48 h | 28 | 681 | 4 | 1.79M; Millionaire |
| A, 60 h (after 4 d away) | 28 | 1.36K | 4 | Three Million; 3.0M |
| A, 108 h | 44 | 963 | 4 | 7.9M |
| A, 120 h (after 7 d away) | 44 | 1.9K | 4 | 9.8M; Ten Million |
| A, 168 h | 60 | 1.01K | 5 | Whole System; 7.8M; 12 milestones |
| B, day 3 (~24 h) | 13 | n/a | 2 | Millionaire |
| B, day 7 (~73 h) | 21 | n/a | 2 | Three Million |
| B, day 14 (~158 h) | 49 | n/a | 2 | Ten Million |
| B, day 21 (~255 h) | 110 | 1.17K | 2 | 37.6M, stuck |

- Walls: crew cap of 20; Kora slots (50K, 125K, 313K, 781K, 1.95M); kit supply chain; claims 5K, 65K, 845K, 11M, then 143M with nothing to claim.
- Growth roughly linear in A (slots and crew); B's upgrade-only growth stays exponential.

## Bugs
1. **`creditsPerSec` in `report` is wrong by 7x to 20x+.** Repro: load `A_t48h.save.json`, `report` (681), then `advance` 600: credits rise ~28/s. At start 24.8 vs real 3.3.
2. **Away summary does not state the cap.** Repro: load `A_t48h.save.json`, `{"cmd":"away","seconds":345600}`. `stockGained` has negatives/noise.
3. **No auto-crew on build.** `build` a smelter on Kora, then `report` shows `noCrew`.
4. **Route drains modules.** habitat_module route Kora to Brine at 0.05/s shipped everything; Brine reached 158.
5. **Cargo ships stuck at wrong body.** `createRoute` fuel Cinder to Kora fails "Needs 1 Cargo Ship on Cinder"; only fix is routing `cargo_ship` as cargo.
6. **Auto-sell eats kits.** `keepAtLeast` 2 on `outpost_kit` sold kits needed for the 3-kit claim; found only via the claim error.

## Top 10 ideas
1. Fix `creditsPerSec` and show net credits/s plus a "next goal" bar. (S, stage 1)
2. Honest, rewarding away summary: lead with "away 4 days, earned 12 h", next affordable goal, top bottleneck, main goods only. (S, stage 1/2)
3. Raise the offline cap via a scarce building/upgrade (12 to 24 to 36 to 48 h). (M, stage 1 content)
4. Midgame credit sinks that deepen production lines: warehouse tiers, refit/efficiency megaprojects, costs scaled to income. (M, stage 1 content)
5. Make kits discoverable: `costs`/`state` explain claim needs and missing link; say first claim needs no kits. (S, stage 1/2)
6. Auto-assign crew on build, with a park toggle; show crew demand vs supply. (S, stage 1/2)
7. First-class ships and routes: move-ship command, stop-at-target, route status. (M, stage 1/2/3)
8. Pinned short/medium/long goals, with chain milestones (first reactor core, station segment). (M, stage 2 UI)
9. One-time labelled catch-up after long absences (e.g. 25% of forfeited time); no streaks. (S/M, stage 1/2)
10. Sixth/seventh body or next region/research branch so the 143M claim leads somewhere. (L, stage 5)

Avoid: streaks and daily rewards that punish missed days; selling cap increases for real money; hiding the cap.
