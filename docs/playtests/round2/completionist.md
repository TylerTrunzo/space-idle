# Playtest report: Completionist, seed 31, 30 game days

(Full report as sent via SubagentHandback.)

## Persona and run
- Seed 31, ~30 game days, ~150 check-ins at ~5 a day. Days 1-4 by hand; middle compressed with helper script ci.py; last days 27.3-29.7 hand-driven but nearly idle.
- Scratch dir: /tmp/claude-0/-home-user/7963d8b4-7ef1-5bbc-9bff-b2b24979e3ee/scratchpad/pt2-completionist/ (log.jsonl replay, table.txt, day12_all_milestones.json, day27.json).
- All 26 building types built, all 5 bodies owned, all 19 milestones by day 12.4.

## Timeline highlights
- 0 h: first wire mill took income from 1.8 to 9 credits/s. New buildings start with no crew (only a noCrew bottleneck hint).
- 6 h: 95K credits; claimed Brine (5K); built habitat -> crew 20 to 40.
- 6.2-12 h: crew-collapse spiral (habitats starved of shared water/oxygen; assigned crew exceeded supported; could not assign to fix).
- 12 h: 276 unsold outpost kits found (no autosell).
- 29.5 h (day 1.2): claimed Vastmere (845K + 3 kits).
- Day 3.2: found Capacity track (60 credits doubles a mine via crew slot), unexplained anywhere.
- Day 4.0: claimed Cinder (11M + 4 kits), 5th and last body.
- Day 4.3: four milestones in one away; 16/19 by day 5.
- Day 12.4: last milestone (Billionaire) reached only by hoarding; then flat plateau to day 30.

## Fun
Best: first away summary, first habitat, kit->claim loop, finding Capacity, multi-milestone away.
Worst: crew assignment after each build, cargo-ship logistics (ships are stock hauled by routes; stale routes drain ships), crew-collapse spiral, stalled Cinder magnet supply, spreadsheet-style upgrade buying from day 12.

## Where I'd quit
Day 4.3-5 (everything claimed/built, milestones gone); definitely by day 12.4 (last milestone). Days 20-30 were nothing. costs still shows a pointless 143M claim.

## Length and retention
- Content lasts ~4-5 days; credit milestones (100M/300M/1B) check current balance, so spending on upgrades blocks them (100M only at day 10.4; 300M/1B needed hoarding).
- Away summary lacks crew-collapse warning, next goal, short/medium/long-term goals.
- Pointless items: hydrogen furnace, protein vat, propellant mixer/sulfur, depot, survey drones (feed nothing), shipyard chore.
- Missing milestone types: production rate, chain completion, building counts, crew/habitat, upgrade levels, every-type-built, further segments/drones.

## Pacing (credits/s approx, bodies, milestones)
| Day | Credits/s | Bodies | Milestones |
|---:|---:|---:|---:|
| 0.25 | 4.5 | 2 | 1 |
| 1.0 | ~15 | 3 | 6 |
| 1.7 | ~25 | 4 | 8 |
| 3.2 | ~60 | 4 | 9 |
| 4.0 | ~100 | 5 | 12 |
| 5.1 | ~195 | 5 | 16 |
| 7.1 | ~780 | 5 | 16 |
| 10.0 | ~4,900 | 5 | 16 |
| 11.4 | ~7,400 | 5 | 18 |
| 12.4 | ~7,400 | 5 | 19 |
| 15.4 | ~41,000 | 5 | 19 |
| 20 | ~78,000 | 5 | 19 |
| 24.9 | ~124,000 | 5 | 19 |
| 27.3 | ~145,000 | 5 | 19 |
| 29.7 | ~180,000 | 5 | 19 |

Wall is the market: at day 27 raws at 0.01, steel 0.9 (base 6), hull plate 4.5 (base 30), saturation 0.15; storage full with 38-54K unsold; 25-30% waste. Capacity upgrades (~5-8K at lvl 20) vastly beat Speed (~250-300M at lvl 60-70). Habitat capacity reached 2.8B/level by day 27.9 (crew wall).

## Bugs
1. Nickel route r47 (hollow->cinder) stalled with 38.8K nickel at Hollow, Cinder 0; magnet works starved, starving reactor/drone works (save day27.json).
2. costs shows claim cost 143M + 5 kits with all bodies owned (day12_all_milestones.json).
3. removeRoute/ship handling: stale ship routes silently drain ships.
4. Autosell on a resource that a route also ships sells it first, no warning.
5. No warning that shared water/oxygen starve habitats and collapse crew.
6. assignCrew fails with negative free crew; recovery obscure.
7. Credit milestones use current balance, not lifetime earned.

## Top 10 ideas
1. Lifetime-earnings milestones + more milestone types (S, now).
2. Make market depth/floors not a wall; give late goods real value (M, now).
3. More bodies/tiers/megaprojects with escalating cost and permanent bonus (L, now).
4. Surface crew and Capacity clearly; auto-assign crew (S, stage 2 UI).
5. Crew-collapse warning / habitat dashboard / input priority (S, stage 2 UI).
6. Cargo ships as a fleet pool, not hauled stock (M, stage 3).
7. Production-line planning view with ratios (M, stage 2 UI).
8. Give redundant buildings distinct roles (S, now).
9. Away summary ends with next goals short/medium/long (S, now).
10. Storage/waste as a decision (S, now).
Avoid: streak rewards, forced timers, cash-out walls.
