# Playtest round 4: Optimizer, seed 1, 14 game days

Source: a subagent playtest of stage 1.6 (head 5763bad). The scratch files it mentions (command log, check-in CSVs,
saves, repro, tools) were in the session scratchpad (`r4-optimizer/`) and are not kept in the repo.

## Persona and run
- **Persona:** Optimizer. 7 check-ins a day, every 2.5 h, with a 9 h night; every gap taken with `away`.
- **Run:** seed 1, t = 0 to 336 h, 98 `away` check-ins, about 8,200 logged commands. A replay of the command log from a
  new seed-1 game reproduces the final state exactly (3B credits, station L13, Mass Driver L15, 56 milestones).
- **How it was played:**
  - **Days 1–3 and the start of day 4 by hand.** Upgrades were bought with a greedy tool that tries each upgrade on a
    throwaway save copy and buys the best credits-per-second gain per credit (from 26 h it lets the market settle for
    30 minutes before measuring). From day 3 a second tool tests new buildings the same way.
  - **From 76.9 h a routine script:** deliver every open contract; build a Kora circuit fab or Dusk Cairn magnet works
    if a throwaway test says it pays back in under 20 h; buy a cheap extra slot; run the upgrade tool with a payback
    limit lowered over the run (33 h → 100 h → 72, 48, 24, 12 h); pay leftover credits into the station; `away`.
  - **Re-planned by hand at least daily:** habitat capacity at 79 h; credit auto-pay per megaproject toggled at 48, 63,
    72, 192 and 216 h; station goods auto-delivery off at 288 h; build tests at 192 h; Mass Driver value tests at 48 h
    and 96 h.
- **Against the balanced bot (seed 1, 336 h):**

| | Player | Bot |
|---|---|---|
| Day 14 earnings | about 162B | 87B |
| Station level | 13 | 11 |
| Mass Driver level | 15 | 14 |
| Milestones | 56/56 (Trillionaire at 271.5 h) | 55/56 |
| 300B milestone | 146.5 h | 264 h |

  About 1.9× ahead (round 3: 1.75×).

## Timeline highlights
- **0–2.5 h:** two cheap buildings. The first contract (1K iron ore for 7.5K) paid for the first claim, Brine.
- **2.5 h:** the first throwaway upgrade test: 54K of speed upgrades raised income from 6.5 to 33 cr/s. Speed upgrades
  dominate day 1: 33, 172, 1.18K, 4.3K, 12.6K cr/s.
- **5.0 h:** a 1K hull plate contract paid 90K, and auto-sell had held the plates for it on its own.
- **12.5 h:** the only contract that was a real decision: 24 outpost kits for 4.53M, needed for the next claim. Claimed
  first, delivered later.
- **15 h:** all station L1 goods in except reactor cores; auto-delivery and credit auto-pay on before the night.
- **24 h: best moment.** Back to station L1 and L2 and Mass Driver L1 and L2, all finished overnight with no hauling
  (+746M earned, 163M paid in on its own).
- **Day 2:** station L3–7, Mass Driver L3–8, Dusk Cairn and Tessaly claimed; all 7 bodies by 34 h; 195K/s at day end.
- **48 h, first experiment:** one speed level (+10%) on all 40 tier 0–1 buildings raised income only 1%, so the Mass
  Driver's credit auto-pay went off.
- **48–72 h:** station L8 raised income 10% for 7.6B. Throwaway build tests found new circuit fabs paying back in 4–6 h.
- **Day 4:** station L9 and L10 and the 100B milestone; 815K/s at day end.
- **111 h:** no upgrade paid back within 33 h; flat at 1.0M/s for a day.
- **144 h:** station L12 reopened upgrades: 6.6B of them raised income by 84K/s.
- **175 h on:** upgrades dried up again; station and Mass Driver became multi-day credit bars. Station L13 at 216.6 h,
  then L14 needs 733B; Mass Driver L11–15 on days 9–12, then L16 needs 534B; Trillionaire at 271.5 h was the last
  milestone.
- **Days 13–14:** 12 identical check-ins of 15.6B each, only contracts happening.

## Round-3 problems

| Round-3 problem | Verdict | Evidence |
|---|---|---|
| The game flattens | **Better, not fixed** | Day-end income: d4 815K, d7 1.28M, d10 1.64M, d14 1.73M. Day 7→14 +35% (round 3 about +20%). Growth comes only in steps right after a station level; between levels upgrades stop paying (nothing under 33 h payback from 111 h, nothing under 100 h from 175 h). Flat: 111–135 h, 180–210 h, 228–336 h except a +5% step at 288 h. Last new goals: station L13 day 10, MD L15 and Trillionaire day 12 (round 3: day 7). Cause: still the sum of market depths. On day 5, with depth ×9.3, tier 0–1 goods sold at 0–20% of price, plates 22%, circuits 45%, magnets 50%. Each station level costs ×2.5 and adds only +7–16% income; payback per level about 35–100 h at L8, 200 h at L12, over 1,000 h at L14. |
| Station deliveries as a chore | **Fixed** | Zero goods deliveries by hand all run; all 33 manual megaproject deliveries were credits. Auto-delivery fed 14 station and 15 Mass Driver levels. |
| Contracts paying for no effort | **Better on share, same on effort** | 7–11% of earnings on days 5–14 (bot 9–12%). Almost every reward sat at the 20-minute-of-income floor for goods lying around: 24K copper ore for 2.08B, 10K water ice for 258M, 9.2K silicon for 111M, 24 cargo ships for 6.29B (ships sell at 230 each). Worth the 10 seconds; never a decision. |
| Silent crew crash and housing flicker | **Not reached** | Crew never short after day 1. 10 habitat capacity levels each (about 60K) took housing from 237 to 382. End: 432 housed, 279 assigned. No flicker. Crew irrelevant from day 2. |
| Hidden logistics rules | **Better** | `state` shows `stopTarget` and in-flight cargo; stop levels above storage are cut with a clear message; the auto-sell buffer is visible; no silent route throttling all run. |
| Requirements revealed one failure at a time | **Fixed** | Full recipes in build replies; `catalog`. |
| The report's credits/sec | **Better** | Usually within about 5% of the next away. Right after a big upgrade spree it overstates, because prices take about 30 minutes to fall (87.2K shown, 72K/s earned). Its steady-state view counts what a just-paid megaproject's next stage will take, so income "drops" 676K → 569K the moment a level is paid: honest, but it looks like a loss. |

## Day by day

| Day | Credits/s (end) | Bodies | Station | Mass Driver | What was new (besides contracts) |
|---|---|---|---|---|---|
| 1 | 25.9K | 5 | 2 | 2 | About 37 milestones, 4 claims, survey, slots, station L1–2 and MD L1–2 overnight |
| 2 | 195K | 7 | 7 | 8 | Dusk Cairn, Tessaly, station 3–7, MD 3–8, 1B/3B/10B milestones |
| 3 | 465K | 7 | 8 | 9 | Station 8, MD 9, 30B, new circuit fabs and plate presses |
| 4 | 815K | 7 | 10 | 10 | MD 10, station 9 and 10, 100B |
| 5 | 940K | 7 | 11 | 10 | Station 11 only; upgrades stop paying |
| 6 | 1.07M | 7 | 12 | 10 | Station 12 at the end of the night |
| 7 | 1.28M | 7 | 12 | 10 | 300B; upgrades reopened |
| 8 | 1.41M | 7 | 12 | 10 | **Contracts only** |
| 9 | 1.41M | 7 | 12 | 12 | MD 11 and 12 |
| 10 | 1.64M | 7 | 13 | 13 | Station 13, MD 13 |
| 11 | 1.65M | 7 | 13 | 14 | MD 14 only |
| 12 | 1.65M | 7 | 13 | 15 | Trillionaire (last milestone), MD 15 |
| 13 | 1.73M | 7 | 13 | 15 | **Contracts only** |
| 14 | 1.73M | 7 | 13 | 15 | **Contracts only** |

Earned per day: about 0.8B, 12B, 35B, 61B, 82B, 91B, 115B, 128B, 130B, 149B, 152B, 151B, 162B, 162B. Bot: day 7 33B,
day 14 87B.

## Key questions
- **When does income stop growing?** Upgrade-driven growth ends on day 5 (111 h). After that, only steps after station
  L12 (day 6) and L13 (day 10); flat from day 10–11. Station L14 (733B plus 28M segments) and MD L16 (534B) are about
  4–6 days of all income.
- **Does auto-delivery remove the hauling chore?** Yes, completely. Two new costs:
  - it feeds goods to a stage whose credits are days away (turning station goods off at 288 h was worth +5%);
  - when MD L15 was paid, the delivery for L16 took 275M hull plates in one 2.5 h gap. Plates are about 35% of sales, so
    income fell 1.65M → 1.01M/s, with no flag explaining why.
- **Do the Mass Driver and compounding depth keep upgrades worth buying past day 9?**
  - **Mass Driver: no, nearly worthless to an optimizer from day 3.** +10% speed on all 40 tier 0–1 buildings gave +1%
    income at 48 h and +0.4% at 96 h. Tier 0–1 markets are saturated, and tier 2 makers (plate press, circuit fab,
    magnet works), which it doesn't speed up, are the real limit. A level costs 4–230B for about +0.5%: payback
    200–800 h.
  - **Station depth: only in short windows.** Each level reopened a few check-ins of upgrades, then nothing until the
    next level, days later.
  - **The even credit split** sent the near-worthless Mass Driver half the credits (5.86B each on the night of day 3).
- **Are contracts a decision?** No: one at 12.5 h, then free tips at the 20-minute floor.

## Slow building
- **Days 1–4: real anticipation.** Claims, surveys, slots and station stages overlapped; overnight auto-delivery
  finishing four levels felt great; paying ahead into the next level while one runs works well.
- **From day 5: waiting.** Stage timers are capped at 6 h, so a credit bar measured in days is the limit. The decisions
  auto-delivery leaves are crude: one reserve, an even split, an all-or-nothing goods toggle. Wanted: a priority between
  megaprojects, and "feed goods only when credits are within N hours".

## Numbers
- **Growth:** ×7.5 on day 2, ×2.4 day 3, ×1.75 day 4, then +15%, +14%, +20%, +10%, 0%, +16%, 0%, 0%, +5%, 0% a day.
- **Walls:** market depth (every good at 0–50% of price from day 5); upgrade prices (+17% a level, speed doubles every
  25 levels; late levels 25–70M for +10% of a saturated good); Kora extra slots at 819M by 96 h.
- **What kept things moving on days 3–4:** new buildings, each restarting the cheap end of the upgrade curve. By day 8
  every new-building test paid back in over 100 h or lost money.

## Clarity
- **Next-goal line:** good early and right about station ETAs. Late it said "Mass Driver level 11 still needs 4.18B
  credits; you can start it now" for several check-ins while the player had chosen not to fund it. It showed
  Trillionaire only when megaproject auto-pay was off.
- **Contract holds:** a circuit contract was not held on Kora because Brine (no auto-sell rule for circuits) held
  enough; the player had to work out to deliver from Brine.
- **Contracts larger than a body's storage:** a 9K reactor core contract took 4 check-ins (Vastmere stores 2.52K).
- **Nothing says upgrades have stopped paying back;** throwaway-save tools were needed to see it on day 5.

## Best and worst moments
- **Best:** four megaproject levels finished overnight at 24 h; the day-1 upgrade sprees (6.5 → 12.6K cr/s); new
  circuit fabs paying back in hours on day 3; station L12 reopening 6.6B of upgrades.
- **Worst:** days 8, 11, 13, 14 of identical check-ins; the Mass Driver worth +0.4% while the even split hands it half
  the credits; 2.08B for 24K copper ore, again and again.

## Where I'd quit, and why
Around day 8 (about 180 h): upgrades dried up, station L13 was 1.5 days of credits away, only contracts remained. Would
come back once for station L13 (day 10) and Trillionaire (day 12), and stop for good on day 11 when L14 shows 733B and
MD L16 534B.

## Bugs
1. **A project completes one tick after its finish time, so commands are refused with "0s left".** Seed 1: build an
   iron mine, advance 2520 s, deliver c5, advance 30 s, claim Brine ("done in 30m"), advance exactly 1800 s, build on
   Brine → `stillClaiming`, "Brine is still being claimed (0s left)". One more 60 s advance and the build works. Also
   seen on Dusk Cairn at 26.5 h.
2. **Auto-delivery quietly diverts the top export to a megaproject.** From the day-11 save, five `away 9000`: the fifth
   summary shows "cps 1.65M -> 1.01M" and "Mass Driver got … 275M Hull Plate", with no "worse than before" flag and no
   bottleneck naming the cause.
3. **`report` overstates credits/sec by up to about 20% right after a large upgrade spree**, because prices take about
   30 minutes to fall.
4. **Oddity:** contract c242 (24K food, posted about 219 h) paid 4.5B while neighbours paid 1.7–2.1B.

## Top 5 changes
1. **Make megaproject levels pay back in days, not weeks** (now, M). Each station level costs ×2.5 and gives ×1.25 depth
   (+7–16% income), so payback runs from 35 h at L8 to over 1,000 h at L14. Lower credit growth to about ×1.8 or raise
   the depth bonus so a level is always about 1–2 days of income; each level then reopens a wave of upgrades.
2. **Point the Mass Driver's bonus at what binds** (now, S–M): speed up tier 2 makers, or add tier 0–1 depth, instead
   of tier 0–1 production (+0.4–1% income per level). Add a per-megaproject priority or weight for credit auto-pay.
3. **Make contracts a decision** (now, S): ask for amounts worth at least 5–10 minutes of income, 2-good bundles, or
   goods you don't make yet; drop the flat 20-minute floor that pays 2B for 24K copper ore.
4. **Feed goods only to stages whose credits are within reach** (now, S): a "feed goods only when credits are within
   N h" option, and a warning when a megaproject takes a top export ("Mass Driver is taking 35% of your plate sales:
   −640K cr/s").
5. **Show the market wall and upgrade payback** (stage 2 UI, S; deep-market content in stage 3/5, L): each good's
   price, saturation and share of income, plus "best payback available now: 31 h". For content past the wall: tier 4
   recipes and faction buyers with changing demand.
