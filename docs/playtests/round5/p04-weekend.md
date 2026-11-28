# Playtest round 5, tester #4: Weekend player (seed 4)

## Persona and run
- **Seed and engine:** seed 4, branch `stage1-economy-engine` at 2c1e202.
- **Calendar:** 3 real weeks, about 502 h of wall time. Each week had a long Saturday, a long Sunday and one 15-minute midweek check (Wednesday, then Thursday, then Tuesday), plus a final arrival on day 22. That is 9 sessions and 10 away summaries.
- **Gaps:** I used `away` for every absence. They ran from 25 h to 100 h.
- **Game time:** only **162 h** of game time was counted, against 502 h of wall time (32%).
- **What I scripted:** buy-max every 15 minutes during the week-3 sessions, plus a compact printer for the JSON output. Wanting a script for that loop is itself a finding (below).
- **Container restart:** it hit at game time 15.7 h. I resumed from save `saves/0019.json` with nothing lost.
- **Files:** the tester's scratch folder `r5/p04-weekend/` (not kept in the repo). It holds the command log (`all.jsonl`), a save at the end of every session (`sunday1_end.json`, `wed1_end.json`, `sat2_end.json`, …, `tue3_end.json`), the casual bot run (`casual_bot_504h.md`) and the no-cap replay (`nocap.jsonl`, `nocap_out.jsonl`).

## Timeline highlights (wall day, game hours)
- **W1 Sat, 0–2.7 h:**
  - Auto-sell set, mines built, the first contract (1K copper ore for 7.5K) paid for the Hollow Reach claim.
  - At 20/20 crew I took crew off mines and built an all-Hollow-Reach life-support chain: ice drill, melter, electrolyzer, protein vat.
  - Plate press and module works went on Hollow Reach, with a steel route and a circuit route from Kora. The first habitat came at 2.7 h.
  - This was the best puzzle of the run.
- **W1 Sun, after a 25 h gap (12 h counted):**
  - 2.1M in the bank. The contracts (habitat modules, food, steel) were real choices, because modules also build habitats.
  - Built the fuel refinery, kit assembler and shipyard, and claimed Cinder: magnets, drone works, station dock.
  - Income went from 50/s to 1.65K/s. A 4.75 h session, eager the whole time.
- **W1 Wed, after a 73 h gap (12 h counted, 16% of the absence):** +71M. Claimed Vastmere for He-3, ran a survey, made partial contract deliveries, bought max. Done in 15 minutes.
- **W2 Sat, after a 62 h gap (12 h counted):**
  - The report showed mines making **1.62K/s iron ore against 216/s used**, sold at a price of about 0.00.
  - I took 37 crew off mines and income did not change. Nothing in the output points at this (see below).
  - Built He-3, reactor works and Tessaly, then delivered the Orbital Station's first level by hand. **Station level 1 started at 42 h** and finished 2 h later. Best moment of the run.
- **W2 Sun, after a 26 h gap (13 h counted):**
  - Station levels 2–4 and Mass Driver levels 1–4 had all completed while I was away. The headline listed 12 completed projects.
  - Claimed Brine and Dusk Cairn. Then **2 h of watching**: auto-pay swept every credit above the reserve into the megaprojects, and there was nothing left to build.
- **W2 Thu, after a 100 h gap (17 h counted):** "earned 3.75B … net +13.6M". Discarded the absurd contracts (69K drones, 60K segments). Nothing else to do.
- **W3 Sat and Sun:**
  - The content was used up: no bodies left to claim, nothing left to survey.
  - I raised the reserve to 100B (which pauses auto-pay) and ran buy-max every 15 minutes. Income went 76K → 143K/s on Saturday and 158K → 252K/s on Sunday.
  - Between buy-max taps I only raised route rates.
- **W3 Tue and day-22 arrival:** two 3–4 day gaps at a 21 h cap. Income reached 327K/s with the Orbital Station at level 10 and the Mass Driver at level 11.

## Day-by-day table (wall days)
| Wall day | credits/sec (arrive → leave) | bodies | Station | MD | What was new | Mood |
|---|---|---|---|---|---|---|
| 1 Sat | 0 → 50 | 2 | 0 | 0 | first claim, life-support chain, first habitat | 4 |
| 2 Sun | 50 → 1.65K | 3 | 0 | 0 | fuel, kits, shipyard, Cinder magnets, drone works, dock | 5 |
| 5 Wed | 1.65K → 7.3K | 3 (+Vastmere claiming) | 0 | 0 | survey, big partial contracts | 4 |
| 8 Sat | 7.2K → 29K | 5 | 1 (L2 building) | 0 | the 37 wasted crew found, station level 1 | 5 |
| 9 Sun | 44K → 53K | 7 | 4→5 | 4→6 | last claims; then 2 h idle | 3 |
| 13 Thu | 68K | 7 | 7 | 7 | discarding contracts only | 3 |
| 15 Sat | 76K → 143K | 7 | 8 | 8 | buy-max with auto-pay paused | 3 |
| 16 Sun | 158K → 252K | 7 | 9 | 9 | depot, route rates | 3 |
| 19 Tue | 263K | 7 | 9 | 10 | nothing new | 2 |
| 22 Sat | 327K | 7 | 10 | 11 | "City Above" milestone | 2 |

## Persona findings

**1. Offline cap: fair in outcome, punishing on paper, and it never grows to fit a weekend.**

The absences counted 47%, 16%, 19%, 51%, 17%, 52%, 74%, 41% and 24% of their length. The cap starts at 12 h and the Orbital Station adds +1 h a level, so it was 22 h by level 10. The spec (§6.7, §14) promises up to 48 h, "so a weekend away is covered later". That needs station level 36, which ×2 costs make unreachable: level 11 alone costs about 10 B.

The surprise is that the cap cost me much less than the lost hours suggest. I replayed my exact command log with every `away` turned into `advance` (`nocap.jsonl`). It ended at **428K/s with the station at level 12 and the Mass Driver at level 14**, against my **327K/s, levels 10 and 11**: only +31%. Growth comes from the buy-max sprees in active sessions, and idle credits mostly go into megaproject levels whose cost doubles each time.

So the cap is fair. But a weekend player only sees "3d 1h; 12h counted (cap)" again and again, for three weeks.

Suggestion: grow the cap faster. For example +2–3 h a level, or a separate cheap "offline buffer" upgrade, so 48 h is reachable by about week 2. A second option: credit a small share of the uncounted time, say 10%, as a "while you slept" bonus.

**2. Wording respects absence, with two exceptions.**
- **What works:** there is no guilt or "you missed out" text anywhere. The headline is neutral and honest about the cap.
- **Bad `net` figures:** after 37 h away the headline read **"earned 4.87B credits … net -3.03M"**, and after 4 days it read "net +13.6M". Both read as "you lost money" or "nothing happened", when in fact 3–5B was earned and two megaprojects levelled.
  - Why it happens: auto-pay also swept a 3.03M contract reward I had banked above the reserve.
  - Suggestion: lead with what was earned and built, and drop or soften the net when it is near zero or negative.
- **Game clock:** on wall day 21 the game clock reads "d6 18:14". In the app a day counter that disagrees with the calendar would feel odd. Suggestion: show real time away, not game days.

**3. The away summary after 2–5 days is useful, not overwhelming.** It is 2–4.5 KB of JSON, with up to 12 "reached level N" lines and a long headline when both megaprojects levelled. Bottlenecks were 0–2 rows and always accurate. `keepBlocksDelivery` and `megaprojectDiversion` were clear, and I acted on them directly. No false 0% rows appeared.

**4. "What was I doing?" is the real gap.** The summary says what finished, but not what I was building toward.

On W1 Wed and W2 Sat the station was blocked only by 30 Reactor Cores: I had no He-3 and no Reactor Works. Yet `nextGoal` said "Next: Hundred Million … in 3h 11m". I had to rebuild the dependency chain in my head from `costs`.

Suggestion: a "blocked on" line, e.g. "Orbital Station needs Reactor Core; nothing makes it; Reactor Works needs Helium-3 (Vastmere)". It would serve every returning player, and a weekend player most.

**5. Long sessions: rich in week 1, thin from week 2.**
- **Week 1:** each weekend session had 3–4 h of real decisions: crew juggling, habitat logistics, routes, claims.
- **W2 Sunday:** about 40 minutes of work, then 2 h idle with credits pinned at the reserve.
- **Week 3:** the only lever left was "pause auto-pay, tap buy-max every 15 minutes, raise route rates". It gave +88% and +53% income per session, so it was worth doing, but it was so mechanical that I scripted it.
- **What a weekend player needs:** a project that takes a whole session to plan, such as a new body type, a new tier or a ratio redesign, not more of the same buttons.

**6. How far behind a daily player.** The casual bot on seed 4 at day 21 had:
- 269B a day (about 3.1M/s), the station at level 14 and the Mass Driver at 17;
- all 63 milestones.

I had 327K/s, levels 10 and 11, and 52 of 63 milestones: about **9.5× behind, and roughly where the bot was on day 6**. Per game hour I kept pace. The gap is almost entirely the cap plus the bot's 4 buy-max taps a day.

With no competition in stage 1 it doesn't matter. It will matter once AI factions, prices or war compare empires (stages 3–4). Offline protection must hold there, and a ~10× gap must not decide fights.

**7. Overproduction is invisible.** Buy-max piled speed levels onto ore mines whose output sold for about 0. The report showed them at run 1.0 with no waste and no bottleneck. Only comparing `produced` with `consumed` revealed 37 idle-value crew. This is a sharper case of the known buy-max issue: a "selling at under 5% of list price" flag in the report would have found it at once.

## Round-4 problems I met
- **Away-summary honesty (§2.4):** fixed. There were no false 0% rows. Grouping works ("2 Magnet Works on Cinder…"). Diversion and keep-rule warnings fire and are actionable.
- **Hidden route throughput (§2.5):** better. `state` and the bottlenecks name the binding limit. It is still whack-a-mole: I raised rates on 8 separate occasions, and steel went 0.5 → 1,000/s (known).
- **Contracts as a decision (§2.6):** fixed early (habitat modules vs habitats was a genuine choice). Broken late: every order on days 8–21 asked for 48K–320K of a good the megaprojects needed, so I discarded 14 of them (known).
- **Crew (§2.8):** better. Crew was the main puzzle of my first weekend, and irrelevant from day 8 (13–77 free).
- **Megaproject value (§2.1):** for this persona the station's +1 h offline cap is the bonus I care most about, and it is the weakest one relative to 50–100 h gaps.

## Bugs
- **Float-noise bottleneck.**
  - **What happens:** `report` lists "Plate Press on Hollow Reach is running at 99%: not enough Steel" with runFraction 0.9999999999999996 and lostCreditsPerHour 9.99e-11, shown as "0".
  - **Repro:** load `docs/playtests/round5/repro/p04/bug_99pct_bottleneck.json` (seed 4) and run `{"cmd":"report"}`.
  - **Fix:** apply an epsilon before flagging.
- **Negative net headline after a profitable absence.**
  - **What happens:** "earned 4.87B credits, 3.25B to Orbital Station and 1.62B to Mass Driver, net -3.03M".
  - **Repro:** load `docs/playtests/round5/repro/p04/bug_net_negative_headline.json` and run `{"cmd":"away","seconds":132300}`.
  - It is arithmetically true: auto-pay swept credits banked above the reserve. As player-facing text it reads as a loss.
- **Minor: `deliverContract` without `amount`** fails with "command field "amount" must be a string". The docs don't say whether `amount` is optional; "deliver everything owed" would be the natural default.

## Top 5 changes (ranked by fun impact for players who can't check in daily)
1. **Make the offline cap reachable at 48 h.** Raise it by +2–3 h a station level, or add a cheap repeatable "offline buffer" track.
   - **Stage and effort:** now (content). Effort S.
   - **Why:** returning to big numbers is the weekend player's reward, and the spec promises it. It costs little balance: no cap at all was only +31% in my replay.
2. **A "blocked on / what you were building" line in the away summary and the next goal.** Walk the dependency chain of the next megaproject level or chosen goal and name the missing building or body.
   - **Stage and effort:** now (engine), shown in the stage 2 UI. Effort M.
   - **Why:** it fixes "what was I doing?" and points at slow building rather than credit milestones.
3. **Give long sessions a big plan to work on.** New building types or tiers, or a body-specialisation choice, late enough that week 2+ weekends have something to design.
   - **Stage and effort:** stage 3 (research, exploration of new systems, ship design). Effort L.
   - **Why:** an hour of planning a new chain is optimization fun; tapping buy-max every 15 minutes is not.
4. **Reframe the away headline.** Lead with earned and built ("earned 4.87B; Station and Mass Driver reached level 8"), and drop "net" when it is under about 1% of earnings or negative.
   - **Stage and effort:** now (engine text). Effort S.
   - **Why:** numbers going up should feel up.
5. **Flag overproduction and near-zero sale prices in the report and the away summary,** e.g. "Iron Ore sells at 0.00: 1.4K/s nobody uses; 5 crew could move", and let buy-max skip such buildings.
   - **Stage and effort:** now (engine). Effort M.
   - **Why:** it turns an invisible waste into a visible ratio puzzle (crew and ratios), and stops buy-max fuelling it.
