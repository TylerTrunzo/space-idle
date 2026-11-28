# Playtest round 5, tester #5: First two hours (seed 5)

## Persona and run
- **Persona:** brand-new player. I read only the setup and command list (docs/playtesting.md) before playing. I learned everything else from the game's output, then read the round-4 findings and the bot summary afterwards.
- **Run:** seed 5, engine at deab2b1 (stage1-economy-engine). I covered 0 to 49.5 h of game time.
  - The first 6 h were played minute by minute, in sessions of 2–30 min with `advance` steps of 1–10 min.
  - After that I checked in every 1–2 h, with one 8 h overnight `away`.
  - That makes about 30 play sessions and 26 `away` returns.
- **Commands:** about 460 in total, including 15 buy-max taps, 22 contract deliveries and 24 manual crew reassignments.
- **What I automated:**
  - a wrapper that loads the save, runs the commands and saves again;
  - two output summarizers;
  - from 36 h on, a helper that delivers each open contract's exact remaining amount. I wrote it because I was typing the same partial deliveries every check-in. That urge is itself a finding (see contracts below).
- **Where the files are:** everything is in `/tmp/claude-0/-home-user-space-idle/7963d8b4-7ef1-5bbc-9bff-b2b24979e3ee/scratchpad/r5/p05-first-hours/`.
  - The full command log is `all_cmds.jsonl` and the full output log is `log.jsonl`.
  - Saves: `save_t3h_before_buymax.json`, `save_t4h.json`, `save_t6h.json`, `save_t8h.json`, `save_t10h.json`, `save_t12h.json`, `save_t18h.json`, `save_t20h_night.json`, `save_t34h.json` and `final_t49h.json`.
  - Bug repro files are in `repro/`.

## Timeline highlights
- **0:00.** `state` is a wall of JSON with no goal and no hint. The catalog lists 28 buildings, but it shows no sale prices, and the market lists only goods you already hold. I set auto-sell on steel and copper ore.
- **0:02.** A contract appeared without any message: 240 steel for 7.5K credits, when I had 250. It was the first hook. But steel quietly stopped selling. I only found out why in the auto-sell text: "keeps 240 (… + 240 for open contracts)".
- **0:03.** I built a second iron mine and a second smelter. A second smelter alone would have starved, because one mine makes exactly what one smelter uses.
- **0:12.** I delivered the contract (after one error, below) and claimed Brine with the reward. On Kora I built the whole circuit chain: wire mill, silicon mine, wafer fab and circuit fab.
- **0:17.** My first buy-max (1.5K) bought capacity and speed on the mines. The result was 0.96 iron ore a second that nothing used or sold, and no bottleneck flagged it.
- **0:18.** Kora's 12 slots were full.
- **1:03.** I came back from 45 min away to +25.6K credits and "Brine claimed". This was the moment I first wanted to come back.
- **1:05.** No crew was free. A habitat needs about 4 crew of water, oxygen and food buildings before it houses anyone. I had to pull crew off 4 buildings by hand.
- **1:14.** I built the first habitat and supported crew went from 20 to 40. This was the first "aha".
- **3:05.** I came back to +120K, 18 habitat modules piled up and 10 outpost kits. I claimed Hollow Reach.
  - I put auto-sell on the spare habitat modules, and their price crashed from 320 to 14.9 (saturation 0.05), with no warning.
- **3:07.** A 40K buy-max took income from 23 to 48 credits a second. This was the second "aha": buy-max now mattered.
- **4:07.** No cargo ship was free to carry habitat modules to Hollow Reach. I removed a route, moved the ship it returned and made a new route.
- **4:16.** Two habitats took crew to 80. A 150K buy-max then put 18 crew on ice melters, which made a water surplus of 11.9 a second. I put auto-sell on the water and income went from 72 to 109 a second.
- **8:00.** I claimed Cinder with plate presses, then got a 13K hull plate contract worth 838K. My stores could hold only 11.2K of it, so it needed a second delivery.
- **12:40.** I claimed Vastmere and set up the station chain: helium-3, reactor works, drone works and 2 station docks. I turned on auto-feed. The station reached level 1 at 17.6 h and the Mass Driver level 1 at about 20 h.
- **20–28 h (night).** While I was away: +49.6M earned, Mass Driver level 2, and Tessaly surveyed. I also came back to 114K of goods wasted on Vastmere, from routes overflowing into full stores.
- **28–49 h.** Three huge contracts, each needing 5–11 partial deliveries; Tessaly claimed for 20.5M; four more habitats taking supported crew from 245 to 413; then saving for Dusk Cairn (164M). There was "nothing left to survey" by 31 h. I claimed Dusk Cairn at 49.5 h.

## Day-by-day table

| Day | Credits/sec | Bodies | Station level | Mass Driver level | What was new | Mood (1–5) |
|---|---|---|---|---|---|---|
| 1 (0–24 h) | 0 → 9.5 (0.2 h) → 48 (3 h) → 230 (6.4 h) → 1.1K (10 h) → 1.74K (20 h) | 1 → 5 (Brine 1 h, Hollow Reach 4 h, Cinder 8 h, Vastmere 12.4 h) | 1 (17.6 h) | 1 (about 20 h) | Contracts, claims, circuits, habitats, kits, magnets, station chain, first survey | 5 for the first 6 h, then 4 |
| 2 (24–49.5 h) | 1.83K → 2.56K → 3.04K → 3.69K | 5 → 6 (Tessaly 33.7 h), Dusk Cairn being claimed at 49.5 h | 2 (about 37 h) | 3 (about 37 h) | Tessaly habitats, huge contracts, Dusk Cairn wall (164M, about 14 h of income) | 3 |

## Fun, length, coming back
**Fun.** The first 6 hours are genuinely good: every check-in had something new to build, and the numbers grew about 10× every 2–3 hours. Some decisions felt real:
- which body to claim;
- whether to sacrifice smelters to staff a habitat chain;
- feeding the station versus saving for a claim.

Others were fake:
- **Buy-max:** there's nothing to decide, and it often makes things worse. It piled crew onto melters, a nickel mine (29 a second when 0.4 was used) and new vats, and those raw goods then sold at crashed prices (water ice 0.05, iron 0.13).
- **Contracts:** always worth delivering, at 3× sale value, so they never posed a choice.

From about 30 h on, the routine was the same at each check-in: deliver partial contracts, read the same bottleneck lines, wait.

**Length.** New goals arrived steadily through day 1 (5 bodies, both megaprojects open). On day 2 things thinned:
- the last survey signal was gone at 31 h;
- the only claim left cost 164M, about 14 h of income;
- megaproject levels double in cost each time, and their bonuses are hard to feel.

My persona's horizon ends here. I'd still come back on day 3, to build up Dusk Cairn and Tessaly, but the flat stretch starts around 36 h.

**Coming back.** Things that pulled me back:
- returning to a finished claim;
- the overnight run, with two megaproject levels and a newly surveyed body;
- each new body restarting cheap upgrades.

What would make me quit:
- contract chores;
- a next-goal line that keeps pointing at the megaproject I had deliberately stopped funding;
- buy-max quietly wrecking my ratios.

## Best and worst moments
**Best:**
1. 1:14, first habitat: crew doubled and everything sped up.
2. 0:12, a 7.5K contract paid when I held 250 credits, which funded my first claim.
3. 3:07, buy-max doubled income.
4. Waking to "Mass Driver reached level 2" and "Tessaly surveyed".
5. Route bottleneck lines that name the fix, such as "Steel into Cinder is limited by route r54's 2 Cargo Ships (20/s); assign more ships".

**Worst:**
1. The crew wall at 1:05, with no hint how to get past it.
2. Hand-shuffling cargo ships to move habitat modules.
3. Habitat modules dumped from 320 to 14.9 by auto-sell.
4. Contracts like 91K magnets (8.4M) and 120K circuits (8.3M). Each is bigger than my stores hold, so it took 10+ manual partial deliveries over a day.
5. The last-unit problem ("1 still owed"), twice.

## Where I'd quit, and why
Around 40–48 h. Every check-in was "deliver contract parts, read the same three bottlenecks, wait for 164M". There was nothing left to survey and no new building type to try. The next-goal line kept saying "Orbital Station level 3 still needs 64.1M credits; you can start it now" while I was saving for a claim it never mentions.

## Onboarding clarity: every confusion, with the output that caused it
1. **No goal at the start.** `state` has no hint or goal line, and `nextGoal` exists only in the away summary. The market shows only goods you hold, so I couldn't tell circuits (20) or hull plate (30) were worth more than steel (6) until I made them.
2. **The contract arrived without a message.** The `advance` reply was just `{"ok":true,"time":120.0}`. Income then dropped, and the only explanation was in the auto-sell rule: `"keeps 240 (keepAtLeast 0 + 0 local use + 240 for open contracts)"`.
3. **`amount` looks optional but isn't.** The docs present it like `bodyId`. Sending `{"cmd":"deliverContract","contractId":"c4"}` gave `"command field \"amount\" must be a string"`.
4. **Milestones appear without a message** in `state` ("First Foundry", "Handshake Deal"), with no event or announcement.
5. **Buy-max's surplus isn't flagged.** The report net showed `'iron_ore': '0.96'` after buy-max, but there was no bottleneck: unsold surplus isn't flagged unless nothing sells at all.
6. **The first next-goal line wasn't actionable:** "Next: Clean Running (Waste nothing for 2h), 3.76K of 7.2K, in 57m 21s". The figures are seconds, which it doesn't say, and the goal is passive.
7. **Nothing warns about the crew wall.** Crew went from 17 free to 0 within 20 min, and no line warned me. The habitat's crewless design means you need crew before you can get crew.
8. **Habitat modules on the wrong body:** `"Needs 1 Habitat Module on Hollow Reach (you have 0)"`. It doesn't say how to get one there, or that you have no free cargo ship.
9. **The price crash.** `habitat_module ('14.9', saturation 0.05)` came after one auto-sell rule, with no warning. Jargon never explained in output: "saturation", "market depth ×1.25", "(tiers 1-2)". No output maps goods to tiers.
10. **Tiny rates shown as 0.** Report outputs show `'habitat_module': '0'` and `'outpost_kit': '0'` (0.00333 a second), and route throughput shows `"display": "0"`.
11. **`effectiveFraction` reads 4.0 or 10.0 on upgraded buildings.** That isn't a fraction.
12. **A deliberate choice nags forever.** I zeroed Module Works' crew on purpose, and "Module Works on Brine has no crew" took a top-3 away slot for 1 day 12 h. There is no way to pause a building.
13. **`keepBlocksDelivery` spam.** Four lines like "Mass Driver still needs Water, but Tessaly keeps 200 of it back…" were all about keeps I set on purpose to buffer life support.

## Was the next-goal line right and helpful?
- **0–10 h:** right but not helpful. It named passive milestones (Clean Running, Millionaire, Ten Million) while the real next steps were a habitat, a claim or outpost kits.
- **12–30 h:** good. "Orbital Station level 1 still needs 3.76M credits and 37 Station Segment; in 56m" and "Mass Driver level 3 … you can start it now" were both clear and actionable.
- **36–49 h:** wrong for me. After I turned off credits for both megaprojects it still said "Mass Driver level 4 still needs 62.3M credits; in 2h 56m", then "Orbital Station level 3 … you can start it now" four check-ins in a row. It never named a claim (Tessaly 20.5M, Dusk Cairn 164M), which was my actual goal.

## The first-hour guide, compared with what I needed
The guide's order is: sell steel, build a second smelter, add crew, buy an upgrade, claim a body, build there, make circuits, build a habitat, make an outpost kit. What I actually needed:

- **Sell steel:** yes, but the first contract comes before anything else and decides the pace. It's the funding for the first claim, so add "deliver your first contract".
- **Second smelter:** it needs a second iron mine (or mine speed) too, or it starves.
- **Make circuits:** this belongs before the claim. Kora has copper and silicon, and circuits were my best early income.
- **Add crew:** at the start there are 17 free crew. The step is really "fill crew", and buy-max does it.
- **Build a habitat:** the wall comes at about 1 h. Move it earlier, and add "you need about 4 crew for its water, oxygen and food first".
- **Outpost kit:** right place. The kit claim at about 3 h felt good.

So the order I'd suggest: sell steel, deliver the contract, add a mine and a smelter, make circuits, claim, buy-max, build a life-support chain and a habitat, then kits.

## When buy-max started to matter
- **0:17 (1.5K):** a small gain and it made a surplus.
- **1:20 (8K):** 11 → 20.5 a second.
- **3:07 (40K):** 23 → 48, the turning point.
- **After 10 h:** capacity levels cost 30–50K each. 1M bought 35 levels and +270 a second; 5M late on day 2 bought +0.4K a second.

## Round-4 problems I met
- **Delivery progress rounds away the last unit: better, not fixed.**
  - It now says it, but the last unit is still owed: "Delivered 3.2K Circuit (2.9K from Kora, 303 from Brine) to contract c28 (3.19K of 3.2K, 1 still owed)".
  - Then `deliverContract … "amount":"1"` failed with "None of your bodies has a whole Circuit to deliver". It happened again on c78.
- **Away summary honesty: mostly fixed.**
  - Grouped rows work ("3 Plate Presses on Cinder …").
  - The diversion warning works: "Mass Driver takes 100% of the Hull Plate that would sell: 2.65M credits an hour not earned".
  - Keep-blocks warnings work, but are noisy.
  - I saw no false 0%.
  - The next goal still names a megaproject I chose not to fund (above).
- **Hidden route throughput: fixed.** `limitedBy` and the bottleneck text name the fix. But overflow on a full store is a new hidden rule (bug 2).
- **Contracts are never a decision: same.** The reward is about 3× sale value, so delivering is always right. It's now also a chore: 37K, 91K and 120K orders exceed storage and take 5–11 partial deliveries each.
- **Auto-pay sweeps everything above the reserve: same.** To save 20.5M and then 164M for claims, I had to turn credits off on both megaprojects. Weights help, but there is no "save for X" option.
- **Crew irrelevant after day 2: better.** Crew was the main constraint for my whole first day. On day 2 four habitats gave +84 crew at once and buy-max dumped them into cheap, low-value capacity.
- **The pacing bot models the wrong player: still true for an attentive new player.** I reached station level 1 at 17.6 h, against the casual bot's day 4–5 target.
- **Report overstates credits per second: a new case** (bug 1).

## Bugs
Repro files are in `/tmp/claude-0/-home-user-space-idle/7963d8b4-7ef1-5bbc-9bff-b2b24979e3ee/scratchpad/r5/p05-first-hours/repro/`.

1. **`report` overstates income while a contract holds goods.** It read 2.85 credits a second while I earned about 0.7 (271 → 484 credits over 300 s). This contradicts the docs, which say held goods don't count.
   - Repro: `gs --seed 5 --script repro/report_overstates.jsonl`.
2. **Routes without a stop level overflow a full destination and waste the goods.** `state` still claims full throughput (`r73 circuit 0.4 0.4 rate`) while Vastmere wastes `circuit 0.29/s, hull_plate 0.2/s`. That cost 114K overnight. The docs say stock plus in-flight cargo never passes the cap.
   - Repro: `--load repro/vastmere_hullplate_waste.json --script repro/route_overflow.jsonl`.
3. **Contract last unit:** delivering the full amount leaves 1 owed.
   - Repro: `--load repro/contract_offbyone_save.json --script repro/contract_offbyone.jsonl` gives "(3.19K of 3.2K, 1 still owed)".
   - Cause, as far as I can tell: Brine has no auto-sell rule for circuits, so its stock is subtracted from Kora's hold. Brine's buildings then use those circuits, so Kora keeps one short. The owed amount is also shown rounded (3.17K for 3,171).
4. **Rounding mismatch inside one message:** "Delivered 11.9K Magnet (11.9K from Cinder, 19 from Vastmere) to contract c65 (11.8K of 37K …)".
5. **Contracts sized beyond reachable storage.** c50 asked for 13K hull plate, but the bodies holding hull plate could store 11.2K. A 91K magnet order needed 11 deliveries, about one per 2 h check-in.
6. **Wrong auto-feed text.** The `setMegaprojectAuto … "credits":false` reply still says "once a stage is near ready (its credits due within 12h)". With credits off it's really "once you hold the credits".
7. **Small display issues:** rates under 0.005 show as "0"; `effectiveFraction` goes above 1; building ids skip numbers (b4, b7 were never seen; they went to projects), which is a little confusing.

## Top 5 changes (ranked by fun impact)
1. **A smarter buy-max** (stage: now, effort M).
   - Skip capacity and speed on buildings whose output is unsold, saturated or surplus.
   - Prefer the bottleneck building.
   - Show the payback in the reply.

   Why: buy-max is now the main lever, and it wrecks ratios and crashes raw prices. Making it chain-aware keeps the numbers climbing and makes the ratio puzzle visible instead of undone.
2. **Contracts that fit play** (stage: now, effort S–M).
   - Size orders to what the holding bodies can store and to about 6–12 h of that good's production.
   - Add an "auto-deliver" toggle.
   - Show the time to fill.

   Why: turns a chore into a background goal, and fixes the last-unit bug at its source.
3. **A next-goal line for the early game and for claims** (stage: now for the line, stage 2 for the UI; effort S).
   - In the first hours, follow the first-hour guide, including "build life support before crew runs out".
   - Include the next claim or extra slot when it's cheaper than the megaproject.
   - Skip megaprojects whose credits are off.
   - Show the line in `state`, not only in the away summary.

   Why: clarity, and a reason to come back at each stage.
4. **An event feed and warnings** (stage 2, effort S).
   - Announce "Contract posted", "Milestone reached" and "Stage started" in `advance` and `state`.
   - Warn when an auto-sell rule will crash a thin market (tier 2+), and show each good's tier and price in the catalog.
   - Add a pause toggle for buildings, so a deliberate choice doesn't nag.

   Why: the numbers growing need to be seen to feel good, and price crashes are hidden losses.
5. **Make logistics a real game, and give day 2 something new** (stage 3, effort L).
   - Cargo ships were my earliest scarce item: I removed routes to free them. Ship customization (cargo size) and pirates on long routes would turn routing into a real optimization layer.
   - Survey signals ran out at 31 h, so exploration should be the main day 2+ hook (more signals, nearby systems).
   - Until then (stage: now, effort S), give a short-term hook: a cheaper extra survey signal, or one more mid-cost claim between 20M and 164M.

   Why: slow building with anticipation, instead of waiting for credits.
