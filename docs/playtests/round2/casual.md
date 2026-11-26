# Playtest round 2: Casual, seed 7 (14.4 game days, 56 check-ins)
(Saved by the controller from the playtester's reply, condensed by the playtester.)

## Timeline
- Day 0.0: 250 credits. Nothing sells until auto-sell is set. Set it on steel and copper ore, bought cheap upgrades.
- Day 0.25: 36K after the first 6h away; Ten Thousand Credits. Claimed Brine (5K), built a circuit chain on Kora. Peak joy.
- Day 0.5: The circuit fab ran at 50% (1 of 2 crew) with limitReason None. Income went 25→81/s once fixed.
- Day 0.75: 615 cargo ships and 1.2K hull plates sat idle; selling the ships gave 53K.
- Day 1.0: 176 kits made overnight and sold. Claimed Hollow Reach (65K + 2 kits). Next claim 845K, then 11M.
- Day 1.5: Claimed Vastmere (845K). Built habitats from 349 modules.
- Days 1.7–2.0: Housing crash 1. Supported crew 70→20, because the fuel refinery ate the habitats' oxygen.
- Days 2.2–6.7: Auto-upgrade era, 350K→600K per check-in. Boring.
- Days 7–8.7: Housing crash 2, same cause, took 2 check-ins to notice.
- Day 9.9: Claimed Cinder (11M), Whole System.
- Days 10–12.4: Tier-3 chain (magnets, reactor core, survey drone). Most fun part.
- Days 12.4–14.4: Flat at ~950K per check-in. Next claim 143M with no target. Station Dock needs ships at the wrong body. Stopped.

## Fun
- Best: first away summary; selling unsold overnight stock (accidental jackpot); "I saved for this" slot and claim prices;
  the tier-3 cross-body chain; shipping cargo ships as cargo (found by trying).
- Worst: two silent oxygen/housing crashes; days 2.2–6.7 with nothing to decide; ~15 of 56 visits with nothing worth doing;
  reading buildings.json to know what can be built.

## Where I'd quit
- Soft quit around day 3–4: no interesting purchase, next goal 7 days away.
- Hard quit around day 12–14: nothing left to unlock, a 143M claim with no target, income plateau.
- The housing crashes cost ~30% of income for 2–3 check-ins with no named cause.

## Length and retention
- The away summary's bottlenecks are its most useful part. Missing: per-resource earnings, "affordable now", what
  changed. stockGained is noise.
- There is no "next milestone" line. Return drivers: a milestone 1–2 visits away, a stockpile to sell, a visible blocker
  with a one-command fix, a new body or building.
- Meaningful decisions ran out around day 6.
- The casual bot reached 150M by 336h (~25M/day at day 14) vs my ~3.8M/day. Hull plates were 30–50% of the bot's income
  and nothing tells a casual player that.

## Pacing
| Day | Credits | Per 6h | Bodies | Events |
|---|---|---|---|---|
| 0.25 | 36K | 36K | 1→2 | 10K, Brine |
| 1.0 | 359K | 155K | 2→3 | Circuit Board, Outpost Ready |
| 1.5 | 814K | 225K | 4 | Room to Grow, Second Claim |
| 3.0 | 1.3M | 350K | 4 | Millionaire |
| 5.0 | 2.8M | 560K | 4 | Three Million |
| 7.0 | 7.5M | 480–600K | 4 | housing crash |
| 9.9 | 11M | 780K | 5 | Whole System |
| 12.4 | 9.5M | 906K | 5 | Eyes Outward |
| 14.0 | 16.9M | 950K | 5 | stalled |
- Growth is a staircase from new chains; upgrades add ~1.5% per check-in. Upgrades cost 60–600 and give little.
- Claims cost 5K/65K/845K/11M/143M; slots ×2.5 each.
- creditsPerSec counts stockpile draining as income (2.61K/s shown vs ~58/s real).
- Raw prices fall when sold; components hold their price.

## Bugs and clarity issues
1. Partial crew is invisible in the report (limitReason null). Repro: circuit_fab with 1 of 2 crew.
2. The oxygen/housing spiral is silent: a fuel_refinery plus habitat on Brine. The summary shows crewShortage but not why.
3. The unknownDef error doesn't list valid ids, and build never says what a building needs or makes.
4. Auto-sell keepAtLeast 0 blocks stock milestones.
5. Route overdelivery (641 ships per body in 6h; 1K circuits). Needs a stop-at-N cap.
6. Crew `free` goes negative (-17); there is no auto-unassign.
7. Claim cost shown as 11M, charged 10.985M.
8. After 5 bodies, a 143M claim shows with no target.

## Top ideas
1. Next-goal ladder (next 3 milestones with progress + "you can afford") — stage 1, M.
2. Visible, forgiving housing/crew; serve habitats first; explain shortages — stage 1, S–M.
3. Bulk upgrade / best affordable — stage 2, S.
4. Steeper upgrade curve with visible per-level benefit — stage 1, M.
5. Ratio and chain view — stage 2, M.
6. New tiers and places to claim after the home system; survey drones that matter — stage 3/5, L.
7. Logistics ergonomics: ships per body, stop-at-N routes, auto ship counts — stage 1, S–M.
8. Recipe variants and per-body specialties — stage 1 content, M.
9. Milestone rewards that change the game — stage 1, S.
10. Gentle return loop: contracts, pirates raiding stockpiles, ships that leave and return. No streaks, timers or pay-to-skip — stage 3+, M.
Avoid: punishing streaks, silent failure spirals, hidden systems, unbounded auto-delivery.
