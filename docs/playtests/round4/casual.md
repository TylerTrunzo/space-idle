# Playtest round 4: Casual persona, seed 2

Source: a subagent playtest of stage 1.6 (head 5763bad). The scratch files it mentions (notes, command log, saves, bug
saves) were in the session scratchpad (`r4-casual/`) and are not kept in the repo.

## Persona and run
- **Persona:** Casual, with 4 check-ins a day: morning, lunch (gap of about 5.5 h), evening (about 6 h), bed (about 4 h)
  and an overnight gap of about 8.5 h. Every gap used `away`.
- **Run:** seed 2, t = 0 to 504 h. That is 21 full days plus the day-22 morning summary: 85 check-ins and 84 aways.
- **Commands:** 14,640 in total, of which 13,500 were upgrades. The upgrades came from a "buy max" helper run at each
  check-in; it spends the money on hand on the cheapest speed and capacity levels first. The other 486 were game
  commands.
- **Replay:** a fresh replay of the command log ends at exactly the live state: t = 1,814,525 s, 264M credits,
  56 milestones, Orbital Station L12, Mass Driver L15.
- **End state:**
  - 7 bodies;
  - 2,940 crew housed, of whom 1,300+ are idle;
  - 1.35M credits/s, about 115B earned on day 21;
  - all 56 milestones done (the last, Trillionaire, at 491.5 h);
  - Station L13 about 12 h away.

## Timeline highlights
- **0 h:** the first contract asked for 1K copper ore and paid 7.5K, which covered the 5K first claim (Brine at 5.5 h).
  The day-1 hull-plate contract paid 48.7K, exactly 1 h of income. It felt fair.
- **15.5 h: worst early moment.** The habitat modules were on Kora, but the habitats had to be built on Brine. Both ships
  had already gone to Brine. Fixing it took a shipyard, a wait for one ship, then a module route: about 13 game minutes
  for a casual player.
- **Day 2, lunch:** habitat capacity was absurdly cheap. 64 levels for 200K raised housing from 140 to 460 crew.
  - From then on, crew never mattered again.
  - The `catalog` planned the whole station chain (magnets, docks, drones, reactor cores, 5 routes) without one failed
    build.
- **Day 2, evening: best moment.** The headline read "earned 42.8M, 43.1M to Orbital Station … Orbital Station reached
  level 1". By bed it was Station L2 and Mass Driver L1, with 5 projects done. 37 milestones on day 2; the round-3 casual
  took until day 11.8 to reach 39.
- **Days 2–4:**
  - Credit auto-pay swept all income into the megaprojects. The auto-pay reserve became the spending allowance.
  - The day the allowance went up, 19M of upgrades took income from 12.7K to 20.6K credits/s (+60%). Nothing in the game
    hinted at that.
- **Day 3:** Station L4 stalled on 469 reactor cores while Cinder held 1K of them. Auto-sell `keepAtLeast 1000`
  silently blocks auto-delivery.
- **Days 5–9:** a new chore replaced station deliveries: resizing routes as upgraded docks outgrew them. The summary's
  top warning was right, but it sat for 3 check-ins.
- **Day 10: biggest "aha".** Every ship carries 10/s, so the routes had 10× the ships they needed; the rate setting was
  the cap. Nothing in the CLI shows this. Raising the rates took each dock from about 0.5 to 3.5 segments/s.
- **Days 11–14:** every away summary led with "Station Dock on Dusk Cairn 0%: not enough Hull Plate, 45M/h, ongoing
  1d 16h". It was false (bug 1), and 2 days went into "fixing" a route that was fine.
- **Days 14–21:** each check-in was about a minute: read the summary, deliver 1–2 contracts worth 1.3–3B each, buy max,
  leave. Next goals read "in 5d" and "in 6d 5h". The depot fix (a hidden rule, below) gave the last real jump: 1.08M to
  1.26M credits/s.

## Round-3 problems

| Round-3 problem | Verdict | Evidence |
|---|---|---|
| The game flattening | **Better early, same late** | **Growth:** day 7→14 ×5.5 (150K→830K credits/s); day 14→21 only ×1.6 (830K→1.35M; target ≥ 2×).<br>**Flat stretches:** day 7 (146–154K), days 11–12, days 14–16 (790–930K), days 17–20 (1.07–1.33M).<br>**Last new things:** last new body day 4; last new building type day 2; last milestone day 21 (all 56 done).<br>**Contracts-only days:** 9, 12, 15, 18, 19 and 20 (6 of 21; round 3 had 10).<br>**Megaproject gaps:** Station L12 (day 17) to L13 (day 22) and MD L14 (day 16) to L15 (day 21) are 5 days each; target ≤ 3. |
| Station deliveries as a chore | **Fixed** | Nothing delivered to a megaproject by hand in 21 days.<br>**New friction:** credit auto-pay sweeps everything above the reserve and starves upgrades; goods are overproduced unseen (27K reactor cores, wasted segments); `keepAtLeast` silently blocks auto-delivery; route resizing replaced the hauling. |
| Contracts pay for no effort | **Better (honest), still effortless** | First contract 7.5K (exactly the claim); day 1 48.7K (1 h of income); day 2 801K for 1K circuits (the 20-minute floor); late 1.7B (about 21 minutes).<br>**Share:** about 7–10% of earnings.<br>**Effort:** always already in stock; the auto-sell hold does the work. Harmless, not worth a check-in on their own. Fiddly sometimes: stock split across bodies; one hull-plate order sat 8 plates short for 1.5 days. |
| Silent crew crash and housing flicker | **Fixed (never happened)** | Every summary shows housing before and after; no shortage or flicker. New problem: crew is irrelevant after day 2 (habitat capacity too cheap, 1,300+ idle). |
| Hidden logistics rules | **Better, new hidden ones** | **Better:** `stopTarget`/`stopSharedWith`; auto-sell shows `localUse`, `contractHold`, `megaprojectHold`; "cut to cap" messages.<br>**Still hidden:** (a) per-ship capacity of 10/s; (b) stock plus cargo in flight never passes the destination's cap, so a route delivers at most cap ÷ trip time (Cinder 97.7K ÷ 2 m ≈ 814 plates/s) whatever its rate, and the bottleneck only says "not enough Hull Plate"; (c) `keepAtLeast` blocks auto-delivery. |
| Requirements revealed one failure at a time | **Fixed** | `catalog` shows the habitat module and the depot's 50 steel up front; build replies give the full recipe. Left over: where an input must be (modules on Kora). |
| The report's credits/sec | **Fixed (accurate), new confusion** | Matches away earnings (day 21: 1.33M/s vs 28.5B in 21,480 s). But before/after drops sharply when a Mass Driver level starts taking goods (9.02K→6.52K, 34.4K→22.6K, 1.32M→950K); it looks like a loss and is not flagged as redirected output. |

## Day by day

| Day | Credits/s (first → last) | Bodies | Station | Mass Driver | What was new |
|---|---|---|---|---|---|
| 1 | 0 → 185 | 2 | 0 | – | Brine claimed, circuit chain, 5 habitats (crew 20→100), Millionaire |
| 2 | 216 → 3.43K | 5 | 0→2 | 0→1 | 3 claims, station chain, Station L1/L2, MD opens and L1, 2 surveys |
| 3 | 4.23K → 9.02K | 6 | 3→4 | 2→5 | Dusk Cairn claimed, 4 MD levels |
| 4 | 11.1K → 34.4K | 7 | 5 | 6→7 | Tessaly claimed (last body), Billionaire |
| 5 | 22.6K → 90K | 7 | 6→7 | 8 | Sky Bazaar milestone |
| 6 | 108K → 146K | 7 | 8 | 9→10 | Crown of Lights milestone |
| 7 | 147K → 153K | 7 | 8 | 10 | Thirty Billion only; first day with no project finished |
| 8 | 121K → 183K | 7 | 9 | 11 | 1B allowance, slots now 819M, segment auto-sell |
| 9 | 193K → 318K | 7 | 9 | 11 | Only contracts (and route fixes) |
| 10 | 309K → 455K | 7 | 10 | 12 | City Above; the route-rate "aha" |
| 11 | 462K → 532K | 7 | 10 | 12 | Hundred Billion only |
| 12 | 537K → 593K | 7 | 10 | 12 | Only contracts |
| 13 | 539K → 823K | 7 | 11 | 13 | Both levels came in overnight |
| 14 | 792K → 877K | 7 | 11 | 13 | Three Hundred Billion only |
| 15 | 866K → 894K | 7 | 11 | 13 | Only contracts |
| 16 | 606K → 929K | 7 | 11 | 14 | MD L14 |
| 17 | 902K → 1.07M | 7 | 12 | 14 | Station L12 |
| 18 | 1.08M → 1.26M | 7 | 12 | 14 | Only contracts; depot fix +17% |
| 19 | 1.24M → 1.30M | 7 | 12 | 14 | Only contracts |
| 20 | 1.30M → 1.33M | 7 | 12 | 14 | Only contracts |
| 21 | 950K → 1.35M | 7 | 12 | 15 | MD L15, Trillionaire (56/56) |

- **Pacing:** a milestone or project on 15 of 21 days: 7/7 in week 1, 5/7 in week 2, 3/7 in week 3 (misses ≥ 5/7).
- **Against the casual bot (seed 2, 504 h):** the bot has Station L4, MD L6, 6 bodies and 90.6M earned on day 21, and
  19/21 days with a milestone or project. This player's station opened on day 2 against the bot's day 5 and the target
  of days 4–6, and the game ran about 1,000× ahead, because "buy max" spends hundreds of cheap upgrades per check-in,
  which the bot's 15-command limit forbids. Stage 2's buy-max button will make real casual players look like this run,
  not like the bot.

## Slow building, numbers, clarity
- **Timers:** on days 2–6 claims, surveys (3 h) and station/MD stages (2–4.5 h) felt like anticipation, with several
  finishing per summary. After about day 8 a level waits days for credits and the timer is irrelevant: waiting, not
  anticipation.
- **Auto-delivery:** removed the chore, but also hid the goods side. Overproduction and waste went unnoticed.
- **Numbers:** they grow (2.2 → 1.35M credits/s), but after day 14 only about 7% a day. Walls: slots double per buy
  (819M by day 8, for a dock making 0.37 segments/s); late upgrades cost about 100M+ each and each buy-max bought only
  12–40; megaproject credit costs grow ×2.3 (MD) and ×2.5 (Station) per level.
- **Next-goal line:** right and useful. Late it reads "in 5d" or "in 6d 5h": honest but deflating.
- **Bottleneck list:** one row per building with the same cause (17 identical dock rows) floods it.

## Best and worst moments
- **Best:** the day-2 headlines naming Station L1, then L2 plus MD L1, plus 2 survey reveals; +60% from one upgrade
  spree; the route-rate and depot "ahas". That is the production-line optimization the owner loves, but found by
  testing, not from the output.
- **Worst:** modules on the wrong body plus ships sent away on day 1; two days chasing a false "0% for 1d 16h" warning;
  days 18–20 with nothing finishing, 1,300 idle crew, and buy-max adding about 1%.

## Where I'd quit, and why
Around day 12, certainly by day 19. Check-ins shrank to a minute of "deliver contract, buy max, leave". The summary kept
leading with a warning that couldn't be fixed (it was false). From day 18 nothing finished for 3 days, the next goals
were 5–6 days away, and every milestone but one was done.

## Bugs
1. **False 0% input bottlenecks after a step shorter than 60 s.** From the saved state, `away 14335` then `report`: all
   15 Dusk Cairn docks show 0% "input:hull_plate", and the away summary's top bottleneck is "0% … 17.9M/h, ongoing for
   1d 16h". With 14340 s none show; credits earned 7.684B vs 7.686B, so nothing was lost. `advance 55` + report gives 0%;
   another 5 s gives 100%. Real absences are rarely multiples of 60 s.
2. **The away summary's top 3 hides bigger problems behind per-building duplicates.** `wastedValue` 1.29B, yet
   `topBottlenecks` is 3 identical "Station Dock on Cinder 0%" rows at 60.9M/h, while storage-full rows for Vastmere
   (93.8M/h) and Tessaly (110M/h) outrank them and never appear.
3. **Auto-delivery silently skips goods held by `keepAtLeast`.** Station L4 needs 469 cores, Cinder holds 1K under
   `keepAtLeast 1000`; the summary said "in 1h 55m", then "you can start it now", but nothing says why auto-delivery
   isn't doing it.
4. **Delivery progress rounds away the last unit:** "(30K of 30K)" and "(50K of 50K)" while 1 unit is owed and the
   contract stays open.
5. **Headline float noise:** "net +0.59", "net -0.3", "net -0.69", "net +0.05" credits.
6. **Report cosmetic:** depots report `runFraction` 0 and `effectiveFraction` 0, habitats 1.0.
7. **Minor:** buildings built in the same moment as new habitats get "0 of N crew"; crew appears a tick later.

## Top 5 changes
1. **Retune pacing against a "buy max" casual bot** (now, M). Real-casual pacing is about 1,000× the bot's: Station L1
   on day 2 against days 4–6, all 56 milestones by day 21. Stage 2 ships buy-max, so the targets are met by the wrong
   player model.
2. **Make route throughput visible and honest** (now, S–M). Show each route's real limit: min(rate, ships × 10/s,
   destination cap ÷ trip time), and name it in the bottleneck ("Hull Plate into Cinder is capped by Cinder's storage
   at 814/s; a depot raises it"). The two biggest gains of the run came from rules the output hides.
3. **Fix the partial-tick false bottlenecks and group bottlenecks by cause** (now, S). One line such as "17 docks on
   Cinder short of Hull Plate, 1.1B/h", and let waste and other causes reach the top 3.
4. **Fill days 14–21 with things to reach** (stage 5, M–L). Milestones beyond Trillionaire and between 300B and 1T;
   soften the ×2.3/×2.5 credit growth or add a goods-only third megaproject; let late slots or claims grow output again.
5. **Auto-pay as a share of income, and reprice habitat capacity** (stage 2 UI and now/content, S). Sweeping everything
   above a reserve starved upgrades that paid back in about 20 minutes. 64 habitat levels for 200K gave +320 crew; make
   crew cost something again.
