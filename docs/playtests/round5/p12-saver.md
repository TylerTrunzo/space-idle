# Playtest round 5, tester #12: Saver (seed 12)

Repro saves for the bugs below are in `docs/playtests/round5/repro/p12/`.

## Persona and run
- **Seed and span:** seed 12, 0 to 234 h (10 game days), 40 check-ins of about 6 h each, all using `away`.
- **How I played:** I bought only big things: buildings, claims, surveys, slots and megaproject levels. Each megaproject level was paid in one lump by hand, with credits auto-pay off and goods on `nearReady`. I allowed one big batch of upgrades (`buyUpgrades`) a day, at the first check-in.
- **What I scripted:** days 1 to 4 by hand. From 90 h, `auto.py` ran the routine check-ins: deliver contracts I could fill completely, claim or pay a megaproject when the whole credit cost fit the bank, and run the daily batch. Builds, routes and discards stayed manual. I scripted because a saver's check-in is "is the thing affordable yet?", which is arithmetic, not play.
- **Reference runs:**
  - the casual and balanced bots on seed 12 for 240 h;
  - a fork of my own run from day 6 that batched every check-in ("eager");
  - several 6–24 h what-if forks.

## Timeline highlights
- **0–6 h:** with 250 credits I built a wire mill and a mine. Then +49K came in, mostly from the first contracts. Contracts were about 70% of day-1 income, so saving felt natural.
- **6–19 h:** claims cost 5K, then 40K, then 320K. I claimed Hollow Reach, Cinder and Vastmere almost as soon as I could afford them. This was the best stretch: saving had a target and a payoff.
- **24 h:** crew hit the 20-person wall. I had three empty bodies and no crew to work them, so the first habitat and a new chain were needed.
- **30 h:** a fork test settled the saving question. With a 400K bank at 13 credits/sec:
  - saving gave 689K six hours later;
  - spending it all on upgrades gave 94/s and 2.01M.
  I took the first daily batch and income went from 13/s to 83/s.
- **36–42 h:** saving for Brine (2.56M). One check-in was dead. The next goal read "Three Million / Ten Million", never "Brine: affordable in 1.6 h".
- **62 h:** station level 1, **40 h ahead of the casual bot** (102 h). Mass Driver level 1 at about 70 h. Proudest moment of the run.
- **72 h:** with a 22.6M bank, a fork compared two options:
  - Mass Driver level 2 (16M): +0% income after 12 h, actually 619/s down to 555/s, because the next level's feed began;
  - spending 22M on upgrades: 4.17K/s, 6.7× more.
- **78–90 h:** I paid station levels 2 and 3, Mass Driver 2 and 3, and the Tessaly claim (20.5M). Surveys ran out at 84 h (Tessaly, then Dusk Cairn).
- **90 h:** I paid Mass Driver level 3. Holding the remaining 94M started goods feeding for level 4: "Mass Driver takes 100% of the Hull Plate that would sell". About 16% of income was diverted while I was actually saving for the station.
- **97 h:** Dusk Cairn claimed (164M). After that, nothing is left to claim or survey.
- **150–170 h:** I paid 1.28B for station level 7. Contract c130 (29K segments) then held its segments for about 12 h while segments overflowed storage on Cinder and Dusk Cairn. Low point.
- **200–234 h:** segments and routes were the wall, not credits. I built two more docks, raised routes and discarded three huge contracts. Each check-in's income paid one level, so saving stopped meaning anything.

## Day by day
"Earned" counts sales only (the away summaries' earned figure), not contract rewards. The casual bot's figures are from its own report.

| Day | credits/sec at end | Bodies | Station | Mass Driver | What was new | Earned that day (casual bot) | Mood |
|---:|---:|---:|---:|---:|---|---:|---:|
| 1 | 8 | 4 | 0 | 0 | claims, contracts, kits | 0.5M (21M) | 3 |
| 2 | 90 | 5 | 0 | 0 | first habitat, first batch ×6, Brine | 6M (1.16B) | 3 |
| 3 | 619 | 5 | 1 | 1 | station chain, station level 1 | 50M (3.66B) | 4 |
| 4 | 4.5K | 6 | 3 | 3 | surveys, Tessaly | 376M (4.96B) | 4 |
| 5 | 10.2K | 7 | 4 | 5 | Dusk Cairn, the last body | 0.8B (12.1B) | 3 |
| 6 | 33.6K | 7 | 6 | 7 | levels only | 2.5B (31.5B) | 3 |
| 7 | 35.7K | 7 | 6 | 8 | paid level 7 stuck on a contract | 3.0B (56.7B) | 2 |
| 8 | 193K | 7 | 7 | 9 | batch ×3.5 | 11B (85B) | 3 |
| 9 | 233K | 7 | 9 | 10 | more docks, route fixes | 13B (108B) | 2 |
| 10 | 380K | 7 | 10 | 11 | levels only | 27B (123B) | 2 |

On day 10 the casual bot is at station 12 and Mass Driver 14. The balanced bot earned 242B that day and is at station 14 and Mass Driver 15.

## The saver's questions, answered

**1. Is saving ever the right call?**
Only for gateway buys:
- the claims, which opened new chains and life support;
- the first station level, which opened the Mass Driver;
- station docks once segments became the wall.

For anything priced in credits, upgrades won every time. At 30 h, 72 h and 90 h, batching beat saving by 3×, 6.7× and 2.4× within 6–24 h. Cheap levels growing ×1.17 each always beat a megaproject level. The Mass Driver's +5% sale price was worth almost nothing in the short term.

**2. Dead time.**
About 9 of 40 check-ins (23%) had nothing worth doing. The casual bot reports no dead check-ins. Of my "busy" check-ins, most were a single tap: pay one level. A saver's day is "wait, tap, wait".

**3. Does the game show what I'm saving for, and when I'll afford it? No.**
- `nextGoal` almost always named a credit milestone ("Ten Billion in 1d 20h") while my station level was about 4 h away.
- `costs` lists prices but never says "affordable in X".
- Claims and slots have no ETA anywhere.
- **New:** a megaproject stage drops out of `nextGoal` entirely if you pay whole levels in one lump (see Bugs).

**4. How far behind is the saver?**
- **Income, against the casual bot:** 40× behind on day 1, 190× on day 2, 13–19× on days 4–7, 4.5× on day 10.
- **Income, against the balanced bot:** about 9× on day 10.
- **Megaprojects, against the casual bot:** ahead on station levels until about day 5 (levels 1–4 at 62–113 h, against the bot's 102–108 h), then passed for good.
- **Against my eager fork (batching every check-in from day 6, same rules otherwise):**
  - day 10 income 547K/s against my 380K/s (+44%);
  - days 6–10 earnings about 105B against my 57B;
  - but only station level 8 against my 10. My manual docks and contract discards explain most of that gap.

The game punishes patience on income. It rewards it only with an early taste of megaproject levels.

**5. Do megaproject credit costs make saving meaningful?**
On days 2–4, yes:
- station level 1 at 20M was about 9 h of saving;
- Brine at 2.56M and Dusk Cairn at 164M felt like real goals.

From day 5 on, no. Each level's credits (×2 a level, up to 10.24B for station level 10) were about one check-in of income. The real walls were goods: 51K segments for station level 9, and 5.1M hull plates plus 20.5M copper wire for Mass Driver level 11. Credits stopped being the thing you save.

## Fun, length, coming back
- **Fun:** days 1–4 were genuinely good for a saver. A claim ladder (×8 each time), then the station chain, then the first station and Mass Driver levels ahead of the bot. After that the best decision was always "spend it", which turns the persona into a worse buy-max player.
- **Length:** claims ran out at 97 h and surveys at 84 h (known). After that came megaproject levels and route whack-a-mole. The goods walls (segments, hull plates) are long but passive.
- **Coming back:** what pulled me back was checking whether a level was affordable yet. The game never tells you, so I did the sums myself. Mood dropped to 2 on day 7, when a level I'd paid 1.28B for sat 12 h blocked by a contract.

## Best and worst moments
- **Best:**
  - claiming three bodies in 13 h;
  - station level 1 at 62 h, ahead of the bot;
  - the 30 h batch taking income ×6.
- **Worst:**
  - the paid station level 7 held up by contract c130 (on the known list, but it hurts a saver most);
  - holding a bank that silently started Mass Driver feeding;
  - repeated "Next: Ten Billion" while I was clearly saving for a station level.

## Where I'd quit
Around day 7. Saving is visibly wrong, the game never acknowledges my target, and the levels I save for stall on goods and contracts, not credits.

## Bugs and new findings (repro saves in `repro/p12/`)
1. **`nextGoal` never shows a megaproject stage to a lump-sum payer.**
   - **Repro:** `--seed 12 --load repro/p12/nextgoal-saver.json`, then `{"cmd":"away","seconds":600}`.
   - **Result:** "Next: Three Billion … in 2d 16h", although Mass Driver level 6 is affordable in about 2 h.
   - **Check:** deliver 1 credit by hand first (`deliverToMegaproject`, `credits:"1"`). The goal becomes "Mass Driver level 6 still needs 256M … in 1h 55m".
   - **Cause:** the "pays it none by hand" exclusion seems to look only at the current stage. A saver pays nothing toward a level until paying all of it, so the saver never sees one.
2. **With credits off, `nearReady` is keyed to whatever bank you hold.**
   - Holding credits for project A starts goods feeding for project B, diverting top exports: 1.84M/h of hull plates plus 441K/h of copper wire at 90 h; 161M/h at 204 h, about 26% of income.
   - **Repro:** `--load repro/p12/bank-triggers-md-feed.json`, then `{"cmd":"deliverToMegaproject","megaprojectId":"mass_driver","bodyId":"kora","amounts":{"credits":"3.2e7"}}`, then `report`. Expect the Mass Driver level-4 feed and the "takes 100% of the Hull Plate" warning.
   - In a 24 h fork the final cost was small (509M against 510M). It is a timing tax and a confusing message.
3. **The contract guard doesn't protect savers.**
   - "Never ask for a good a fed megaproject owes" doesn't help, because with credits off a stage isn't fed until you hold its credits.
   - Station-segment contracts were posted 6 times (c90, c92, c107, c115, c130, c147). Later they held the segments of levels already paid for.
   - **Repro:** `--load repro/p12/contract-holds-paid-station-L7.json`, then `report`. It shows "Contract #c130 holds 5.36K Station Segments the Orbital Station needs", while station level 7 is fully paid in credits.
   - The away line "Orbital Station level 7 still needs 5.36K Station Segment; you can start it now" was helpful, but it's on `nextGoal` only.
4. **While a saver saves, station segments overflow storage and are wasted** (12M + 6M/h on Cinder and Dusk Cairn). `nearReady` won't feed until the credits are in hand, and segments have no other use. Switching to `"always"` fixed it, but nothing hints at that.
5. **Known items I also met:**
   - `deliverContract` with no amount fails;
   - "1 still owed" on c43 lasted 2 days, because hull plates never accumulated while the Mass Driver was fed;
   - a crew-first buy-max spent 14M on 7 capacity levels;
   - ships pile up (421 on Kora);
   - route rate raises turned into whack-a-mole.

## Top 5 changes (ranked by fun impact)
1. **Buy orders ("buy when affordable"), now plus stage 2, M.** Queue a claim, slot, building or megaproject level and let it run offline the moment credits allow. The away summary then says "Station level 7 bought at 03:12". It turns dead check-ins into anticipation (slow building) and makes saving a plan rather than idling.
2. **A pinned "saving for" line with an ETA, now, S.** Pick a target and show "affordable in 3 h 10 m" in `nextGoal`, the away summary and `costs`. Also fix bug 1: include megaproject stages for lump-sum payers. This feeds the numbers-growing pleasure: you watch the bar fill.
3. **Earmarked credits, now, S.** Key `nearReady` (credits off) to the pinned target, or to credits set aside, not the raw bank. Then saving for A never diverts exports to B. Fixes bug 2 and the confusing diversion warning, and keeps the optimization levers readable.
4. **Contracts respect any auto-fed megaproject's next-level goods (in any goods mode), and expire, now, S.** Removes the worst saver moment: a paid level stuck behind a contract. Makes the levels the saver worked for actually land.
5. **Big buys that compound, stage 3 (ships, pirates) and stage 5, L.** Saving loses because a ×1.17 upgrade always beats a megaproject level. Make the big purchases change the production graph:
   - freighter hulls or convoy escorts that lift route limits;
   - a pirate-insurance stockpile;
   - station levels that unlock recipes or slots.
   Then "save for the freighter" is a real ratio decision, not a sink.
