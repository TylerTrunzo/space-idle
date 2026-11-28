# Playtest round 5, tester #6: Logistics tinkerer (seed 6)

## Persona and run
- **Run:** seed 6, 0 to 332 h (day 13.8), 84 check-ins at 4 h intervals. The container restarted at 52.8 h and I resumed from my save.
- **How I played:**
  - Days 0 to 2.3 by hand, with about 3 to 8 minutes of game time per check-in.
  - After that a script, `auto.py`. Each check-in it delivers or discards contracts, adds missing auto-sell rules, pays megaproject credits once only credits are owed, applies the fix each `routeLimited` line suggests, and spends 60% of spare credits on speed for the makers of whatever is short.
  - I stepped in by hand at about 56 h, 68 h, 96 h, 164 h and 188 h.
  - Wanting that script at all is a finding: from day 3, routine logistics is the same 5 to 10 commands every visit.
- **End state:**
  - 7 bodies, 25 routes, 98 buildings, 59 milestones;
  - about 3,400 idle cargo ships on Kora;
  - Orbital Station level 14, Mass Driver level 16;
  - 2.85M credits a second.
- **Specialised bodies:**
  - Kora: factory (circuits, hull plates, docks, shipyard).
  - Hollow Reach: nickel, fuel and life support.
  - Cinder: magnets and drones.
  - Vastmere: reactor cores and docks.
  - Brine: food and crew, plus docks.
  - Dusk Cairn: reactor world (rare earths, nickel, helium-3, magnets, cores).
  - Tessaly: a remote dock world with 8 docks and 2 depots, fed by three routes.
- **Scratch files** (all in the tester's scratch folder `r5/p06-logistics/`, not kept in the repo):
  - every command I sent: `all.jsonl`;
  - the scripted check-ins: `timeline.txt`;
  - saves: `save_44h.json`, `save_52h_oversized.json`, `save_68h_contract_starve.json`, `save_96h_tessaly.json`, `save_164h_ships_starved.json`, `save_188h_wall.json`, `cur.json` (end).

## Timeline highlights
- **4 h:** buy-max put 37 crew into mines and none into the circuit fab. I put the crew back by hand. This was the first sign that "cheapest first" is wrong for a chain.
- **12 h:** I balanced the circuit fab, plate press and smelter by hand and income went 121 → 228/s. Pure ratio joy.
- **20 h:** Cinder magnet world. "Nickel into Cinder is limited by route r51's rate (3/s); raise its rate" named the right fix. Magnets went 2 → 17/s, and income went 764 → 2.2K/s.
- **24 to 28 h:** station chain spread over three bodies. Auto-delivery collected segments, drones and cores from every body with no hauling. Station level 1 at 28 h.
- **36 h:** I noticed every sold good was at about 99% of base price, so station depth bonuses were worth nothing to me. I paid the Mass Driver first.
- **44 h:** Dusk Cairn's reactor works were held back: "Circuit into Dusk Cairn is limited by Dusk Cairn's storage (2.5/s); a Depot raises it." Efficiency upgrades on the reactor works were the better fix (64% → 100% for 4M). The game never suggests that.
- **52 h:** I tried the obvious anti-whack-a-mole setup: every route at rate 1000, 10 ships, stop level at the storage cap. Income fell 8K → 5.3K/s. Routes from one source competed for its stock, and Brine's docks sat at 0% for 30+ minutes while Hollow Reach's 16.6K buffer filled. Stop levels of about 3× trip demand fixed it.
- **56 h:** after I spent on factory speed, raw supply bound. One spend on extractors took income 7K → 25K/s.
- **68 h:** docks on four bodies were starved. Delivering a contract without `bodyId` had pulled the hull plates out of the docks' route-fed buffers.
- **96 h:** Tessaly as a remote dock world. Hull plate inflow was capped by storage ÷ the 7-minute trip, even with two depots. Efficiency to its floor fixed it.
- **112 to 164 h:** the script obeyed "assign more ships" and doubled ships on a Hollow Reach route. That failed for 9 check-ins: "Needs 16 Cargo Ship on Hollow Reach (you have 10)", while Kora held 400+. The nickel shortage behind it cost up to 2.5B/h, about 70% of income. Moving ships fixed the ships limit, then storage bound instead.
- **188 h:** megaproject wall. With goods feeding near ready and credit auto-pay off, the Mass Driver's goods never fed, because I never held its full 32.8B. The next goal stopped naming it. Turning on credit auto-pay fixed it, after which auto-pay took nearly all income.
- **192 h:** I built 6 drone works, one on each body that had a slot, plus 4 fuel routes. Drones went 5 → 45/s for station level 12.
- **200 h and 324 h:** crew shortages (175 and 190 housed for 286). The new fuel routes drew down Hollow Reach's hydrogen, which its protein vat feeds the habitats with. The summary led with `crewShortage`, not the hydrogen root cause.
- **200 to 332 h:** levels every 1 to 3 days; the same two storage-room lines for 5+ days.

## Day by day
| Day | Credits/s at end | Bodies | Station level | Mass Driver level | What was new | Mood (1–5) |
|---|---|---|---|---|---|---|
| 1 | 2.2K | 5 | 0 | 0 | all bodies claimed, magnet world | 5 |
| 2 | 7.0K | 6 | 2 | 1 | docks on 4 bodies, Dusk Cairn | 5 |
| 3 | 49K | 6 | 5 | 6 | ratio cascade: factories, then raw | 4 |
| 4 | 230K | 7 | 6 | 9 | Tessaly remote dock world | 5 |
| 5 | 511K | 7 | 9 | 10 | ships-limited route (script stuck) | 3 |
| 6 | 823K | 7 | 10 | 11 | nothing new | 2 |
| 7 | 959K | 7 | 10 | 12 | flat | 2 |
| 8 | 1.09M | 7 | 11 | 12 | megaproject wall; drone works everywhere | 3 |
| 9 | 1.5M | 7 | 12 | 13 | crew shortage via hydrogen | 3 |
| 10 | 1.84M | 7 | 12 | 14 | nothing new | 2 |
| 11 | 2.25M | 7 | 13 | 14 | nothing new | 2 |
| 12 | 2.36M | 7 | 13 | 15 | net +0 for 6 check-ins (auto-pay takes everything) | 2 |
| 13 | 2.71M | 7 | 14 | 15 | nothing new | 2 |
| 14 | 2.85M | 7 | 14 | 16 | crew shortage again | 2 |

## Fun, length, coming back
- **Fun:** days 0 to 4 are a real logistics puzzle, and the best stretch of the game I've seen.
  - Each body gets a job. You route three inputs into an assembly world, a typed bottleneck names the route and what binds it, and you fix it.
  - When the fix lands, income jumps 2–4×. Ratio cascades (factories, then raw supply, then storage) are satisfying when they happen.
  - From about day 5, logistics turns into a chore: rate, then storage, then ships, then depot, on every body, every day.
- **Length:**
  - After Tessaly (day 4) there was nothing new to build: no new body types, goods or building types.
  - Days 6 to 14 were megaproject levels, which auto-pay handles on its own, and two storage-room lines that never went away.
  - Income still grew 3× from day 7 to day 14, but none of it was my doing.
- **Coming back:**
  - What pulls me back is a broken chain I know how to fix, so routing must stay a puzzle, not a list of chores.
  - What would make me quit: the top bottleneck reads the same for 5 days, and the only lever left is a depot that costs a slot, a 1 h timer and a steel route.

## Best and worst moments
- **Best:**
  - 20 h: the route-rate fix on the magnet route took income 764 → 2.2K/s.
  - 56 h: the raw-supply fix took income 7K → 25K/s.
  - 96 h: Tessaly, a remote 8-dock world running on three long routes.
  - Throughout: auto-delivery collecting station goods from 4 bodies with no hauling.
- **Worst:**
  - 52 h: oversized routes starving other routes out of the same source stock, with no priority control and nothing in the output saying why.
  - 164 h: 9 check-ins losing up to 70% of income to a "ships" limit whose fix (move ships to the source body) the line never mentions.
  - Building a depot means first making a steel route, then building the depot, then removing the route. I did that 5 times.

## Where I'd quit
Around day 6 or 7. By then each body is fully built. The binding limit is "storage ÷ trip" everywhere, and the only answer is depots, which a chore stands in front of. A logistics player gets no new problem shapes after Tessaly.

## Round-4 problems I met
- **Hidden route throughput (§2.5): much better.**
  - `state` shows `throughput` and `limitedBy` for each route, and `routeLimited` names the binding limit: rate, ships, storage or stop level.
  - Every message was correct.
  - The advice is incomplete: it never says "raise efficiency on the consumer", nor "move ships from Kora (you have 400)".
- **Away summary (§2.4): much better.**
  - Grouping and credits-lost figures work. The megaproject-diversion and keep-rule lines were right.
  - New problem: a heavily over-upgraded, starved building shows a phantom loss, gross of inputs that could never exist. "3 Magnet Works on Cinder at 2%: 2.8B/h" held the top 3 for 3+ days.
- **Auto-feed and auto-pay (§2.7): same as the known issue.**
  - With credits off, near-ready feeding never starts unless you hoard the full credits. With credits on, the reserve is the only spending money.

## Bugs and rough edges
Repro commands are against the seed-6 sim with `--content content` and `--load <save>`; the saves were in the tester's scratch folder.

1. **Delivering a contract from every body drains route-fed input buffers.**
   - Repro: load `save_68h_contract_starve.json`, run `{"cmd":"report"}`. Docks on Hollow Reach, Cinder, Brine and Vastmere show at 31–66%, "not enough Hull Plate". Each check-in before this save my script had delivered contracts with `amount` 1e12 and no `bodyId`.
   - The same happened at 24 h: a circuit contract took the circuits routed to the drone works on Cinder and the reactor works on Vastmere.
   - Expected: deliver-all skips stock that local buildings use, or at least stock that routes brought in.
2. **Contract hold counts stock on bodies with no auto-sell rule, so a body's own hold reads 0.**
   - Repro: at 36 h, contract c55 owed 781 circuits. Kora held 19 and nothing was held back there, because route buffers on Vastmere and Cinder counted toward the contract.
   - It matches the documented rule, but it reads as a bug: "781 still owed" for two check-ins.
3. **"Assign more ships" gives no hint when the source body has none.**
   - Repro: load `save_164h_ships_starved.json`, then `{"cmd":"updateRoute","routeId":"r51","cargoShips":32}`.
   - It fails with "Needs … on Hollow Reach (you have 10)" while Kora has hundreds. The line should say "move N ships from Kora".
4. **Phantom loss figure.**
   - Repro: load `save_188h_wall.json`, then `{"cmd":"report"}`. The Cinder Magnet Works line shows about 2.8B/h at 2% run. No source anywhere could supply the nickel they want, so the figure overstates what could be fixed.
5. **Oversized routes starve each other.**
   - Repro: load `save_52h_oversized.json`, then `{"cmd":"advance","seconds":1800}` and `{"cmd":"report"}`. Brine's docks sit at 0%, "not enough Hull Plate", while Kora makes 32/s.
   - There is no per-route priority or fair share, and no message saying a sibling route took the stock.
6. **Minor:** a route ships fractions of whole-unit goods (habitat module `inFlight` 0.3). `removeRoute` returning ships at once is already known.

## Ship customization and pirates (stage 3) — proposals
- **Cargo haulers fix the binding limit late in the game.** Late on, what binds is storage ÷ trip time, not ships or rate.
  - A large-hold hauler with its own cargo bay acts as a moving buffer: delivered cargo waits in the hold, not in the destination's store. That makes design matter.
  - Engine modules cut trip time, which raises storage-limited throughput directly.
  - Make the ship's stats the levers that matter. Today ships are free filler: I ended with about 3,400 idle on Kora.
- **Routes as "keep stocked" contracts on a shared fleet:**
  - The player sets "keep Tessaly at 2 minutes of hull plate use". The game sizes rate and stop level, and draws ships from a body-wide pool.
  - Ship designs set the cost and risk. That removes the whack-a-mole without removing choices.
- **Pirates scale with trip length and cargo value**, so the remote dock worlds (Tessaly 7 min, Dusk Cairn 8 min) become a real trade-off:
  - near and safe but slot-poor;
  - far and roomy but raided.
- **Escorts and armour as module slots** on the hauler (holds versus armour), plus a per-route "risk / expected loss per hour" shown beside the route's throughput.
- **Anti-devastation:** show the raid loss as one away-summary line with credits per hour, in the same format as the other bottleneck lines.

## Top 5 changes (ranked by fun)
1. **"Keep supplied" routes (now; Stage 2 for the UI), M effort.** The player names a destination and goods and a target in minutes of use; the engine sizes rate, ships (from any body) and stop level, and shares fairly between routes from one source. This keeps the ratio puzzle and removes the chore (I made 73 route updates by hand).
   - Pleasures: optimization without chores; slow building stays about building, not maintenance.
2. **A chain or ratio view (Stage 2; engine data now), S effort.**
   - Show made, used and spare for each good, empire-wide and per body, with "spare would run N more of X" or "short: add N levels or buildings of Y".
   - I had to write `emp.py` to see this. It is the tool that makes ratio puzzles readable, not just guessable.
   - Pleasures: optimization.
3. **Better bottleneck advice (now), S effort:**
   - for storage-limited routes, offer "efficiency on the consumers" alongside "a depot raises it";
   - for ships limits, "move ships from <body with idle ships>";
   - cap a starved building's loss at what the empire could actually supply.
   - Pleasures: clarity of the optimization levers.
4. **Depots that take their steel from any body (now), S effort.** Better, make storage room a body-level upgrade with no slot and no build goods: there is no fun in a temporary steel route. Depots are the late-game logistics lever and should be one tap.
   - Pleasures: slow building, without friction.
5. **New logistics problem shapes after day 4 (Stage 3), L effort:**
   - hauler designs that trade hold, speed and armour;
   - pirate risk on long routes;
   - remote bodies with larger slot counts or rarer deposits, to make distance a choice;
   - a stage-3 good whose recipe needs inputs from 4+ bodies.
   - Pleasures: new goals, so the game stays long.
