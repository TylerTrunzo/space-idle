# Playtest round 2: Optimizer, seed 11, 14 days

## Persona and run
- Persona: Optimizer. I read the content files, computed rates, and built three helpers in my scratch dir, all of which only call the public sim commands.
  - A `what-if` tool that loads the save, applies a change, advances N seconds and compares credits.
  - A greedy upgrade tuner that ranks every upgrade by measured payback.
  - A crew what-if that tries +1 / -1 crew on every building.
- Seed 11, 336.0 game hours (14.0 days). All 19 milestones were reached by day 4.4 (105.9 h).
- Check-ins: about 100 (95 logged rows plus about 40 hands-on sessions in the first 6 hours). Awake gaps were 1 to 3 h and the night gap was 8 h, all taken with `away`. `advance` was used only for the first hour of hands-on play.
- Scratch dir: `/tmp/claude-0/-home-user/7963d8b4-7ef1-5bbc-9bff-b2b24979e3ee/scratchpad/pt2-optimizer/`. Replayable command log: `log.jsonl`. Timeline: `timeline.csv`. Day-14 save: `day14.json`.
- Caveat: from hour 18 onward most routine buying was done by my own tuner script, which spends about 90% of credits on the best-payback upgrades at each check-in. A human would not do that many buys, but would reach the same set over a few more check-ins. Early game (first 6 h), builds, claims, logistics and crew decisions were by hand.

## Timeline highlights
- 0.0-0.3 h: Built the 3 Kora chains (iron to steel to plate press, wire mill, silicon to wafer fab) and a circuit fab. Income was about 8 cr/s. I hit the 12-slot limit on Kora early.
- 0.1 h: **Key discovery.** One `capacity` upgrade (60-90 cr) adds a crew slot, and assigning that crew gives +100% of the building's base output. At level 0 it pays back in about 2 minutes. From then on, "crew" is the real currency.
- 0.33 h: Claimed Brine for 5K. At 0.5 h I demolished an iron pair to free a Kora slot for a shipyard, because ships can only come from a shipyard and every body was full. I built 9 ships by accident.
- 1.0 h: **Crew death spiral.** My tuner pushed crew above housing, the fuel refinery out-competed the habitats for hydrogen and oxygen, supported crew fell from 60 to 46, and income stalled. I recovered by hand.
- 1.7 h: Claimed Hollow Reach (65K plus 2 outpost kits). Habitats on a body with no life support need routed food, water and oxygen.
- 3.6 h: Cinder (845K plus 3 kits), then magnets and drones. 15.2 h: Vastmere (11M plus 4 kits), the last claimable body. The claim cost then jumped to a meaningless 143M.
- 15.7-48 h: Reactor works sat at 0% for about 18 h. I had autosold circuits at the floor price of about 3 cr, and the only warning was one bottleneck line among several others.
- 49.9 h: Fixed that; first stations and drones. Income went from 0.9K/s to 2.3K/s in a few hours.
- 105.9 h (day 4.4): Billionaire, the last milestone. From here the game has no goals other than the numbers themselves.
- Days 5-14: Income grew from 52K/s to 4.2M/s, roughly 2x every 1.5 days, slowing to 2x every 2 days after day 10. Late buys had paybacks of 1 to 10 days.

## Fun
**Best moments**
- The capacity-upgrade discovery at 0.1 h, and the first "buy 10 things at 100-200 s payback" rounds (0.8-1.5 h). Credits went from 2K to 65K in 10 minutes.
- The first away summary ("60.8K gained, Outpost Ready"), and each doubling at speed level 25 (the multiplier doubles there). A 3 h jump from 165M to 242M income was one of those.
- Seeing "Reactor works running at 0%" turn into stations at 900 cr each. The Vastmere claim and the magnet-to-drone-to-station chain felt like a real build-up.
- Fixing a bottleneck by hand (hydrogen for protein vat, steel for press/shipyard) and seeing `report` go to 100% everywhere.

**Worst moments**
- Crew death spiral: unexplained income collapse, with no way to set input priority. The tuner pushed crew above housing, and the fuel refinery (processed before habitats) starved them of O2/H2.
- Reactor works idle for 18 h: a silent economic bug caused by my own autosell, with no strong alert.
- Day 5 onward: no choices that matter. The loop is "wait, tuner, buy 15-20 upgrades, repeat".
- From about day 7, hand-picking buys was pointless because the numbers are huge and the choice does not matter.

## Where I'd quit, and why
- Day 4-5 (about 100 h) is where a human Optimizer quits or goes into maintenance mode. Reasons:
  1. All 19 milestones are done and all 5 bodies owned. The claim button now says "143M" with nothing to claim.
  2. Every build I tried was worth about zero (see below).
  3. The only remaining action is buying upgrades whose payback is on the order of a day.
  4. Credits stop having a use. The tuner spent 90% every time and still the stock was 10-50 days of play-time income.
- If I stayed, it would be for the number going up, not for decisions. After day 7 the thing to do is nothing.
- Casual or low-effort players may stay longer because the same wall hits later for them, but it is the same wall.

## Length and retention findings
- Two real phases:
  1. Days 0-1: dense decisions, about 10 meaningful actions per check-in.
  2. Days 5-14: autopilot. I could replace myself with the tuner and lose almost nothing.
- Meaningful goals visible at once: short-term (next upgrade), medium (next claim or milestone), long (nothing after Billionaire). There is no long-term goal visible after day 4.4.
- **What-if tests at day 8 and day 14:**
  - New buildings in new slots (shipyard, module works, circuit fab, second dock, and others) all measured about zero or negative gain. Raw slots are not scarce.
  - Pushing 10 or 20 levels of speed and capacity on all T3 buildings (docks, reactors, drones, magnets) gave less than 0.4% income gain at a cost of tens of millions.
  - Marginal crew value at day 14 was 0 on every T3 building and about 5000 cr/s per crew on fuel refinery, wire mill and ice melters. The mid-game T3 goals (stations, drones) are economically irrelevant late. Most income comes from selling huge volumes of cheap goods at the market floor.
- **The market floor drives this.** Sale price is `basePrice x saturation`, and the floor of 0.15 gives linear income past saturation. From about hour 30 almost every T0-T2 good sits at 0.15 or lower. So income is roughly `volume x 0.15 x basePrice` summed over goods, and the unit price multiplier of high tiers barely matters. A station is worth 135 cr at the floor.
- The "while you were away" summary is decent (credits gained, stock gained, milestones, top bottleneck). It lacks any story. It never says "your reactor works has been idle for 18 h" with weight, only the single worst bottleneck. The top bottleneck line stayed on the same message for over 100 h ("Vastmere storage is full of Circuit") and I stopped reading it. That is a cry-wolf problem.
- Return pull: early, "I can afford a thing I wanted" is a strong hook. After day 4, the hook is only "the number got bigger".

## Pacing and numbers

| Game day | Income cr/s (avg over the gap) | Credits | Bodies owned | Milestones | Notes |
|---:|---:|---:|---:|---:|---|
| 0.27 (6.5 h) | 266 | 2.1M | 4 | 10 | Cinder claimed at 3.6 h |
| 0.48 (11.5 h) | 334 | 7.0M | 4 | 11 | Plateau 5-15 h, low-tier markets saturating |
| 1.03 (24.7 h) | 734 | 16.7M | 5 | 14 | Vastmere claimed at 15.2 h |
| 2.03 (48.7 h) | 1.9K | 104M | 5 | 15 | 100M milestone at 48.7 h; stations and drones online at 49.9 h |
| 2.95 (70.9 h) | 5.8K | 284M | 5 | 17 | |
| 3.95 (94.9 h) | 15K | 673M | 5 | 18 | Speed-25 doubling |
| 5.04 (120.9 h) | 52K | 1.8B | 5 | 19 | All milestones done at 105.9 h |
| 6.00 (143.9 h) | 116K | 3.1B | 5 | 19 | |
| 7.91 (189.9 h) | 382K | 4.5B | 5 | 19 | |
| 10.16 (243.9 h) | 1.4M | 41B | 5 | 19 | |
| 12.08 (289.9 h) | 2.7M | 80B | 5 | 19 | |
| 14.00 (335.9 h) | 4.2M | 125B | 5 | 19 | Before tuner spend; 12.5B after |

- Credits in the table are shown as at the start of the check-in (before the tuner spent). The Billionaire milestone fired while the tuner was spending 90% each time, so it reflects the cash peak, not total earned.
- Vs bot: balanced bot on seed 11 reached 27M at 48 h. I had 104M at 48.7 h. My day-7 income was about 9x the baseline bot's.
- **Walls and cliffs:**
  - 0.8 to 1.5 h: crew supply was the wall (20 base crew). Fixed by habitats (module works, routes). Needs a long explanation: a new player will hit it and not know why.
  - 5 to 15 h: low-tier prices saturate (iron ore at 0.2 saturation by 12 h; plates at 0.18 by 38 h). Income stalls at about 300 cr/s while credits pile up to 7M.
  - 15 to 48 h: a fix needed was not obvious (reactor works idle). After the fix, income went 2.5x in 3 h.
  - Day 5 to 14: smooth exponential growth, no wall, but the doubling time grows from 1.5 days to 2 days. Upgrade levels are 70-90 on the main chains (cost 4-50B each). Cost growth is 1.25^n and a single capacity level adds 1 crew out of about 80, so late capacity levels return about 1.3% each.
- **Dominant strategy:** buy `capacity` first on cheap raw/T1 buildings and assign the new crew. A crew slot is worth about 1 cr/s everywhere in the first hours, and housing is cheap (about 75 cr per crew via habitats, about 200-400 via habitat capacity). This beats speed upgrades (about 10% per level) by 5-10x early.
- **Upgrades never worth buying:** habitat `efficiency` (the tuner bought it up to level 9 for 10K each with no benefit), efficiency on anything whose input is already at the floor price, and speed or capacity on T3 buildings after hour 50.

## Bugs
1. **Report cps/net are not rates.** `report` shows `creditsPerSec` of 7 to 20 at 0.05 h when real income is about 2 cr/s, and "net" values like `copper_ore -14.8` that are one 60 s auto-sell tick, not per-second values. At hour 15.7 `cps` read 5.4K against about 400 real. At day 14 it read 5.75M against 4.4M real. Repro: `{"cmd":"build","bodyId":"kora","defId":"wire_mill"}`, assign crew, `{"cmd":"advance","seconds":60}`, `{"cmd":"report"}`; seed 1 or 11. Replay from `log.jsonl` or load `before_cap.json`.
2. **Auto-sell hides milestones.** Stock-based milestones like `first_steel` (30 steel) and `first_station_segment`/`first_survey_drone` never fire while auto-sell is on with `keepAtLeast` 0. I got `first_steel` at 0.78 h only by accident, and the drone and station milestones only after I set `keepAtLeast` to 1 at 49.9 h.
3. **No input priority and a death-spiral.** Buildings are served in a fixed order, so a factory placed before habitats can starve them, which reduces crew, which slows food and water, which loses more crew. Repro: Brine with two electrolyzers feeding a refinery and one protein vat plus 3 habitats, then raise crew beyond housing (see 1.0-1.1 h in `log.jsonl`; save `before_cap.json` is the pre-cap state only, not this one). No in-game way to set priority.
4. **Route drains vs autosell and storage.** A route sends its full rate every tick regardless of the destination's need, and the stock piles up until the destination cap, then is wasted. I wasted 100M+ units/hour by day 11-14 (e.g. "Vastmere storage is full of Circuit" for 280 hours). Only a message, no suggested fix. Check `away` summary field `totalWasted` in `day14.json` state.
5. **Claim cost keeps showing** (143M) after the last body is owned. `{"cmd":"costs"}` on `day14.json`. Cosmetic, but it reads like a goal.
6. **Hidden travel time.** Route travel time is `60 x (1 + orbit difference)` s (4 min for Kora to Brine). Players are never told; my first module shipment looked lost for 4 min. Not in `state`.
7. **Slot ids share the counter with routes** (b/r numbers interleave), so "next building id" is unpredictable from `state`. Minor.

## Top 10 ideas (ranked)
1. **Rebalance the market floor and add real late-game sinks (stage-1 content, M).** The 0.15 floor makes volume of T0-T2 worth more than T3. Lower floor to ~0.03 or make saturation recover slowly, so unit price matters at scale. Serves "numbers get bigger" and the optimizer's love of ratios, because high-tier chains become worth tuning again.
2. **Repeatable megaprojects (stage 1 content, M).** Spec 6.6 already plans it: each completion gives a permanent empire-wide bonus and costs more next time (e.g. a "Station Ring" needing N station segments, plus drones). This directly fixes "credits have no use" and "T3 is irrelevant". Gives long, visible, spend-heavy goals.
3. **Input priority and "reserve" controls per building (stage 2 UI, S-M).** Let the player rank buildings or mark "never starve this" (habitats first). Removes the death-spiral and gives optimizers a real ratio tool. Also a route "only send what is above N in destination" option to stop waste.
4. **Crew allocation as the main optimization surface (stage 2, M).** Show "marginal credits per crew" per building (my crew what-if as a UI panel). Crew value is already the central lever and it is invisible. Add a suggestion line like "move 5 crew from Ice Drill to Fuel Refinery: +6K/s".
5. **A built-in "what-if" or preview for upgrades (stage 2, M).** I built one with save/load. A player-facing "payback in seconds" label per upgrade and a "buy bundle" suggestion makes optimization fun without a spreadsheet, and rewards exactly the Optimizer persona.
6. **Add more raw resources, T1/T2 recipes and alternative recipes (now, M).** Only 5 bodies and one system. Dead recipes exist (hydrogen furnace, fusion refinery, propellant mixer, depot) that never pay. Add recipes whose value depends on ratio puzzles, and make alternates better in some situations, so there is "a better configuration to find" late.
7. **Stage 3 ships, modules and pirates as production sinks (stage 3, L).** Warship and ship-module parts that consume T2/T3 goods continuously (fuel, magnets, plates, reactors). Gives T3 a reason to exist and a use for the cargo ships I overproduced. Avoid forcing combat for economy progress.
8. **New systems and bodies via drones and kits (stage 5, L).** Survey drones currently only sell. Make them reveal a neighbor system with new deposits (higher richness, exotic resources), claimed with outpost kits. It restarts the early-game ratio puzzle, which was the most fun part (hours 0-5).
9. **Make the away summary a report with causes (stage 2, S).** Rank issues by lost credits per hour, list idle buildings and starved inputs with "fix" shortcuts, and stop repeating the same line. Return-visit hook: "your reactor was idle for 4 h, fix: route circuits".
10. **A tech or research layer with real choices (stage 5 research, L).** Unlocks per-chain efficiency floors, storage and crew-slot caps, and cap breakers on the speed multiplier. Gives late credits a target and a choice among mutually-exclusive paths, which is the opposite of the "buy everything" wall.

**Avoid:** daily streak timers, forced sinks that punish skipping (e.g. decay), pay-to-skip, and any "must check in within N hours" pressure. Keep offline gains generous as they are.
