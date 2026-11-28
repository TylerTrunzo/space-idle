# Playtest round 2: findings and recommendations

*Stage 1 (economy engine only). Seven AI playtesters, 2026-11-26. Written for the owner.*

Terms: a **tier** is a step in a chain (ore is tier 0, steel 1, circuits 2, reactor cores and station
segments 3). **Auto-sell** sells a good automatically. A **bottleneck** is a building slowed by a
shortage. **cr/s** = credits per second.

---

## 1. Summary

**What works.** The first 1–2 days are fun for every kind of player: claiming a body, the early
crew-and-habitat puzzle, a three-body chain coming online, and the first "while you were away" payout.
The engine is fast (a 12-hour catch-up takes 0.3 s) and big numbers display correctly.

**Three biggest problems.**
1. **Content runs out.** 5 bodies and 19 milestones: an optimizer finishes by day 2–4, a casual player by
   day 10–12. Then nothing new happens.
2. **The economy collapses to one lever, then none.** Adding crew beats every upgrade 5–10×; later,
   income is bulk cheap goods at the market's minimum price. Decisions end around day 5.
3. **The game hides its rules and failures:** no building list, requirements revealed only by failing,
   silent crew crashes, the same warnings for days.

**Three biggest opportunities.**
1. **Repeatable megaprojects and more places to claim** to use up tier-3 goods and idle billions.
2. **Things that take time, plus a goal strip,** so every 2–5 minute visit finds something finished
   and a next goal.
3. **Supply routes, contracts and trade deals** to turn logistics chores into ratio puzzles.

---

## 2. What players loved

| What | Who |
|---|---|
| The first away payout (+36K to +60K after the first nap) | Casual, Completionist, Optimizer, Returner, Designer |
| Claiming a body: "I saved for this"; each opens a new resource and problem | All but Long-haul (6) |
| The early crew-and-habitat puzzle (20 crew; housing jumps 20 → 100) | Designer, Completionist, Returner, Optimizer, Long-haul |
| A multi-step chain coming online, especially across bodies ("most fun part") | Casual, Optimizer, Designer, Long-haul, New player |
| Days 0–7 growth: income ×14 in a week, a next step every visit | Long-haul, Designer, Optimizer, Completionist |
| Upgrade "doublings" every 25 levels; chain-wide upgrade rounds | Returner, Optimizer, Long-haul |
| Accidental jackpots (unsold overnight stock, four milestones in one away) | Casual, Returner, Completionist |
| A respectful away flow with generous offline gains | Long-haul, Optimizer, Returner |

---

## 3. Where players quit

| When | Why | Personas |
|---|---|---|
| **First 5 min** | A wall of numbers: no goal, no building list, 0 cr/s because nothing sells until you set it up. Estimated 2 in 10 leave. | 1 (New player) |
| **30 min – 4 h** | Crew full (19/20), home body full (12 slots), next claim needs 65K plus 2 unexplained outpost kits; upgrades give +3% for 300. The fix (circuits) was found at hour 4 by guessing. | 1 (New player: "the real quit point") |
| **Day 1–2** | Engaged players have claimed everything and done 15 of 19 milestones by hour 30. Struggling ones sit at 14–18 cr/s with 995K and nothing to buy. | 3 (Designer, Optimizer, New player) |
| **Day 3–5** | All bodies owned, or the next claim a week away; only "buy the cheapest upgrade" remains. A once-a-day player stayed at 2 bodies because the kit path was hidden. | 4 (Casual, Completionist, Optimizer, Returner) |
| **Day 9–14** | Last milestone (1B credits) reached; income plateaus; "next claim 143M" points at nothing. | 4 (Casual, Completionist, Long-haul, Designer) |
| **Day 60+** | A 12-command session raises income 0.9%; 307B banked with no use. | 2 (Long-haul, Completionist) |

Silent crew crashes (4.6) caused extra dips for 4 personas between hour 1 and day 8.

---

## 4. Core problems, ranked

Ranked by harm to fun, game length and players coming back.

### 4.1 Content runs out (very high)
**Evidence.** Optimizer: all 5 bodies by hour 15, all 19 milestones by day 4.4. Designer: whole system
claimed on day 1. Completionist: all 26 building types by day 4; "days 20–30 were nothing". Long-haul
bot: no new milestone for 111 days after day 9, and its 42 buildings never change after day 7. Six
reports flag the "next claim 143M" line shown when no body is left.
**Root cause.** Stage 1 is one system (5 bodies, 27 goods, 26 buildings, 19 milestones), about the first
1–2 weeks of the content plan, with nothing repeatable (the spec's megaprojects aren't built yet).

### 4.2 Players can't discover what exists or what it needs (very high on day 1)
**Evidence.** New player guessed about 50 building names, found circuits at hour 4, and built an
electrolyzer that needs water from nowhere. Casual read the data files to learn what to build. Returner's
once-a-day run stayed at 2 bodies for 21 real days because the kit path was hidden. Completionist found
the strongest upgrade (Capacity) on day 3. Also hidden: route travel time, auto-sell rules, prices of
goods you don't hold, the next slot price (50K → 125K surprised).
**Root cause.** Stage 1 is a text tool with no catalog or tutorial. The app will inherit the gaps
(requirements revealed only by failure) unless stage 2 designs them out.

### 4.3 Crew and capacity dominate (high; threatens the "shallow economy" anti-goal)
**Evidence.** Optimizer: one Capacity upgrade (60–90 credits) adds a crew slot worth +100% of base output,
a 2-minute payback, 5–10× better than Speed. Designer: 2.6M on capacity tripled income; the previous 35M
on Speed gave +4%; at hour 252 Capacity costs 6.5K vs Speed 124M. Long-haul: 60–62 of 104 upgrade tracks
give nothing; Efficiency hits its floor at level 28 but is still offered.
**Root cause.** Habitat capacity adds housing without extra food, water or oxygen, so crew is nearly
free; Capacity costs grow much slower than Speed; Efficiency has a hard floor.

### 4.4 The market floor makes the late game a volume game (high)
**Evidence.** Optimizer: from hour 30 nearly every tier 0–2 good sells at the floor (15% of base); a
station segment is worth 135 credits, and extra crew on tier-3 buildings is worth zero by day 14.
Completionist, day 27: hull plate 4.5 (base 30), 25–30% of output wasted. Hull plates are 30–50% of
income in every bot run. Long-haul: Speed costs ×1.25 per level for about ×1.1 gain, so best payback
goes from 3.5 h (day 7) to 25 days (day 120). Banks pile up: 995K at hour 24 (New player), 10–50 days of
income (Optimizer), 307B (Long-haul).
**Root cause.** The market is the only buyer, its floor never falls, and nothing else consumes tier-3
goods or credits.

### 4.5 Nothing takes time, and goods arrive in floods (high, against "slow building")
**Evidence.** Claims, builds and upgrades are instant; spec §6.7 promises "something finished" at each
check-in. One 6-hour nap made 715 habitat modules, 718 cargo ships and 346 kits, while a claim needs 2–4
kits (Designer). Long-haul found 12.1K idle ships and 8.9K kits.
**Root cause.** Pacing is done only by credit prices, which can't pace players whose day-7 income
ranges from ~25 cr/s (Casual) to ~382K cr/s (Optimizer).

### 4.6 Silent failure spirals (medium-high; quick to fix)
**Evidence.** Casual: two housing crashes (supported crew 70 → 20), ~30% of income lost for 2–3 visits,
no named cause. Optimizer: crew 60 → 46 when a fuel refinery took the habitats' oxygen; reactor works
idle 18 h because auto-sell sold its circuits. Completionist: crew collapse at hours 6–12. Long-haul: a
chain at 0% from day 7 to day 120.
**Root cause.** Fixed serving order (habitats not first), no warning for part-staffed buildings, no
priority control. Engine fixes I4, P4 and P5 cover the mechanics; the app must still explain them.

### 4.7 Logistics is a chore (medium)
**Evidence.** To start a route you first ship cargo ships to the source body as cargo (Returner,
Designer, Completionist). Routes push a fixed rate whatever the destination needs: 641 ships per body in
6 h (Casual), 45M units wasted in one away (Designer), a storage-full warning for 280 h (Optimizer).
Routes can't be edited. Auto-sell silently sells what a route should carry. One chain fix took 6
commands for +1.3% (Long-haul).
**Root cause.** Routes are "send X per second" and ships are stock, not a fleet.

### 4.8 The away summary tells no story (medium)
**Evidence.** A 4-day absence counts 12 h (~12.5% of production) and the summary doesn't say so: "reads
as lost 7 days" (Returner). The same top warning for 100+ h (Optimizer), 8 visits (New player), or days
7–120 (Long-haul); players stopped reading it. "Stock gained" is noise and can be negative; waste is in
units, not credits; milestones from active play are missing. No "you can now afford", no next goal
(all seven).
**Root cause.** It lists raw totals instead of "what happened, what to do next".

### 4.9 Credit milestones fight spending (medium; quick)
**Evidence.** Credit milestones check the current balance, so spending delays them: 100M came on day 10.4
and 300M/1B needed hoarding (Completionist). Stock milestones ("30 steel") never fire with auto-sell on
(Optimizer, Designer, Casual).
**Root cause.** Milestones measure what you hold, not what you earned or made. Fixes P7 and P9 switch to
lifetime totals.

### Engine bugs already being fixed
The engine list (`.superpowers/sdd/2026-11-26-stage1-economy-engine/balance-review-findings.md`) covers
the unreloadable save (P1, most serious), the wrong credits-per-second readout (P2, P8), the phantom
143M claim (P3), crew display (P4, P5), the stalled nickel route (P6), lifetime milestones (P7, P9),
repeating warnings (P10), duplicate auto-sell rules (I3) and habitats first (I4).
**Not yet on it:** the away summary hides the offline cap and omits milestones from active play; "stock
gained" shows decreases as gains; auto-sell "keep 200" kept 4.93K steel; the seed changes nothing; the
unknown-building error lists no valid names.

---

## 5. Recommendations

Effort: **S** hours to a day, **M** a few days, **L** a week or more. Pleasure: **N** numbers bigger,
**B** slow building, **O** optimization.

### (a) Stage 1 now: content and engine

| # | Change | Effort | Pleasure | Asked by |
|---|---|---|---|---|
| a1 | **First repeatable megaproject**: Orbital Station built from station segments, drones and reactor cores; each level a permanent bonus (+10% storage, +5% housing), next level ~×3 cost | M | N, B | Optimizer, Long-haul, Completionist, Designer, Returner |
| a2 | **Rebalance crew**: habitat capacity raises life-support use; Capacity costs on a curve like Speed | M | O | Optimizer, Designer, Completionist |
| a3 | **Market**: lower the floor (0.15 → ~0.03) or slow price recovery; deeper demand for high tiers | M | O, N | Optimizer, Completionist, Designer, Casual |
| a4 | **Upgrade curve**: cost growth ×1.25 → ~×1.15 or a doubling every 10 levels; fix the Efficiency floor; label tracks that do nothing | S | N, O | Long-haul, Casual, Returner, Optimizer |
| a5 | **Cut tier-2 floods**: scale claim kits (e.g. 25 × claim number), lower component volume | S | B | Designer, Casual, Completionist, Long-haul |
| a6 | **Two hidden Veyra bodies** revealed by survey drones (which today only sell) | M | B | Designer, Casual, Optimizer, Returner, Long-haul |
| a7 | **~40 milestones now, ~60 by stage 3**: production rates, chain completion, building counts, crew, "every type built", zero waste for 24 h, credits past 1B | M | N, O | Completionist, Designer, Long-haul, Casual |
| a8 | **Route fixes**: stop at N in the destination, routes served before auto-sell, move-ships command, edit a route | S–M | O | Six of seven |
| a9 | **Jobs for dead buildings** (hydrogen furnace, protein vat, propellant mixer, depot, fusion refinery) | S | O | Completionist, Optimizer, Casual |
| a10 | **Auto-crew new buildings** when crew is free, with a "leave empty" option | S | O | Returner, Designer, Completionist, New player, Casual |
| a11 | **Helpful errors**: list valid buildings; say how to make kits; first claim needs none | S | O | New player, Returner, Casual |
| a12 | **Honest offline cap**, and the spec's upgrade path 12 → 48 h (e.g. via megaproject levels) | S/M | N | Returner, Designer |

### (b) Stage 2 app: what it must show and teach

| # | Change | Effort | Pleasure | Asked by |
|---|---|---|---|---|
| b1 | **Goal strip**, always visible, three bars: *now* (top bottleneck + fix, best upgrade), *today* (next milestone, active construction, contract), *long* (next region, megaproject level) | M | N, B | All 7 |
| b2 | **Build catalog**: cost, inputs, outputs, crew, which bodies can host it | S | O | New player, Casual |
| b3 | **Recipe help in context**: tap "needs copper wire" → its maker and a Build button | M | O | New player, Returner |
| b4 | **Upgrade previews**: "+10%, pays back in 8 min", sort by payback, buy ×10/max, whole-chain preview (single upgrades often show +0 when ten double output) | M | O, N | Optimizer, Long-haul, New player, Casual, Designer |
| b5 | **Crew panel**: demand vs housing, warning before a crash, credits per extra crew, "never starve this" priority | M | O | Optimizer, Completionist, Casual, Designer |
| b6 | **Chain view** with end-to-end ratios and waste in credits | M | O | Casual, Completionist, Optimizer |
| b7 | **Away summary 2.0**: "away 4 days, 12 h counted"; gain vs last visit; top earners; waste in credits; what finished; all new milestones; top 3 problems ranked by credits lost per hour with one-tap fixes; old ones folded into "ongoing"; "you can now afford…" | S–M | N | All 7 |
| b8 | **Prices for every good** and "worth per hour" | S | O | New player, Casual |
| b9 | **Show the next price** before slot and claim buys; confirm big spends | S | B | New player |
| b10 | **Show auto-sell rules, route status and travel time** | S | O | Long-haul, Optimizer, Returner, Completionist |

**Onboarding flow** (from the New player; each step is a goal in the strip):
1. **Minute 0:** name the three starting buildings. Goal "Sell some steel", auto-sell as a toggle,
   cr/s in large type.
2. **Minutes 1–5:** "Build a second smelter" (catalog, cost shown first), then "Assign crew" as a button.
   Upgrades show payback.
3. **Minutes 5–20:** "Reach 5K and claim a body", showing what each body can mine.
4. **Minutes 20–30:** celebrate the claim; "Build on your new body"; warn at 19/20 crew and say where
   crew comes from.
5. **30–60 min:** "Refined goods sell for more: try circuits", with the chain as a checklist tree.
6. **1–2 h:** introduce habitats *before* the crew wall, and the kit path before the 65K claim.
7. **First return:** gains, what's full or idle, one recommended action.
8. **Rest of day 1:** all three goal bars filled; when credits pile up, name the next real target.

### (c) Stage 3: factions, ships, pirates, contracts

| # | Change | Effort | Pleasure | Asked by |
|---|---|---|---|---|
| c1 | **Ship designs replace stock cargo ships**: fleet pool per system, route stats from the design, crew upkeep | L | O, B | Completionist, Designer, Optimizer, Long-haul |
| c2 | **Contracts board** (decision 4) | M | O | Designer, Casual |
| c3 | **Factions as buyers**: standing needs ("buys magnets at 1.6×"), trade deals as X/s-for-Y/s puzzles, peaceful planet cession via reputation | L | O, B | Designer, Optimizer |
| c4 | **Pirates as risk vs speed**: risk on the map before you commit, escorts reduce it, offline losses capped and listed | M | O | Designer, Casual |
| c5 | **Sinks for surplus**: modules, fuel and hulls consume tier 2–3 goods continuously | M | O, N | Long-haul, Optimizer |
| c6 | **Regional markets with slow, pre-announced demand shifts** | M | O | Designer |
| c7 | **Introduce one system at a time**, each solving a problem the player already has | S | — | Designer |

### (d) Stage 4: war (untested; guard-rails)

| # | Change | Effort | Pleasure | Asked by |
|---|---|---|---|---|
| d1 | **Warships consume production continuously**, a second buyer for tier 3 | M | O | Optimizer, Long-haul |
| d2 | **War never required** for economic progress | S | — | Optimizer, Long-haul |
| d3 | **Optional pirate-base hunts** for blueprints and rare samples | M | B | Designer |
| d4 | **Strict anti-devastation rules** (spec §8); every offline event in the summary | S | — | Designer, Long-haul |

### (e) Stage 5: galaxy, exploration, research, megaprojects

| # | Change | Effort | Pleasure | Asked by |
|---|---|---|---|---|
| e1 | **Research tree** (decision 3) | L | O, B | Optimizer, Designer, Long-haul |
| e2 | **Region unlocks gated by items, not credits** ("Warp Gate: 500 hull plates, 50 reactor cores") so casual and expert players arrive at similar times | L | B | Designer, Returner, Optimizer, Long-haul |
| e3 | **Procedural outer galaxy** with anomalies (decision 6) | L | B | Designer, Long-haul |
| e4 | **6–8 megaproject types** (Mass Driver, Dyson Swarm, Star Gate, Ring Habitat…), each fed by different chains | M | N, B | Designer, Optimizer, Long-haul |
| e5 | **Records and a Codex** of personal bests, items made, bodies surveyed | S–M | N, B | Designer |
| e6 | **Content target**: ~55–60 items, ~50 building types, ~8 systems / ~40 bodies, ~100 milestones, 40–50 research nodes, 5 factions. Home system lasts a casual player days 1–7, an optimizer days 1–3 | L | all | Designer |

---

## 6. Decisions for the owner

**1. Should things take real time to finish?**
A: keep everything instant. B: timers on big things only (claims, extra slots, megaproject stages,
research), 10 min to ~6 h; small builds and upgrades stay instant. C: timers on everything.
**Recommend B.** Every visit gets something finished, the day-1 sprint slows, and the casual/expert gap
narrows. Mostly 1–6 h, a few overnight ones, none under 10 minutes, no skip button.

**2. Repeatable megaprojects as the endless spine?**
A: rely on more content and rising upgrades. B: megaprojects built from big item deliveries, each level a
permanent bonus at ×2.5–4 cost, starting with the Orbital Station in stage 1.
**Recommend B, now.** It is already in spec §6.6, uses the idle tier-3 goods and banked billions, and
needs little engine work. Without it there is no reason to play past day 14.

**3. A separate research tree?**
A: fold research into region unlocks (the spec allows this). B: a small tree: Labs turn components into
research points; nodes take 30 min early to 8–12 h late; 40–50 nodes; unlocks recipes, upgrade tracks,
the offline cap and map range.
**Recommend B,** first 8 nodes with stage 3. It is the cheapest long-term goal generator and another chain
to balance. Keep basic comforts (auto-crew, buy ×10) free from the start.

**4. A contracts board?**
A: none. B: three open orders, first from a neutral exchange, later from factions; long or no expiry;
empty slots bank up to 3; each asks for a mid-chain good in a quantity that stretches your ratios;
rewards are reputation, blueprints, megaproject parts. C: short timed events.
**Recommend B.** A target for every visit and a use for chains beyond price. Reject C (a FOMO timer).

**5. Replace fixed-rate routes with supply routes?**
A: keep "send X per second" with a stop-at-N cap. B: "keep the destination stocked at X" or "send what it
uses", from a shared ship pool; fixed rate as an advanced option.
**Recommend B.** Six of seven testers hit route waste or chores. Optimization moves to ratios, capacity
and travel time instead of bookkeeping. Cap now (a8), full change with ship designs in stage 3.

**6. A procedural galaxy from the seed?**
A: hand-make every system. B: keep the home system hand-made (it is the tutorial); generate outer
systems, deposits and anomalies from the seed.
**Recommend B, in stage 5.** Today every game is identical. It adds replay value and reaches ~40 bodies
without hand-authoring each, but needs checks that every resource stays reachable peacefully.

**Not a new direction:** the offline cap upgrade path is already in the spec; implement it and be honest.
The Returner's one-time "welcome back" bonus: I recommend against it; generous offline gains already
respect the player.

---

## 7. Things to avoid

- **Login streaks, daily-reward calendars, "come back within N hours"** (all 7).
- **FOMO:** contracts expiring in hours, online-only events, energy/stamina (Designer, Optimizer).
- **Skip-timer buttons**, even free, or anything resembling pay-to-skip (Casual, Optimizer, Designer,
  Returner).
- **Hiding the offline cap** (Returner).
- **Punishing returns:** offline raids, decay, sinks that cost you for skipping a day (Long-haul,
  Optimizer, Designer).
- **A prestige reset:** "a bank that cannot buy anything is a content gap, not a reason to reset"
  (Long-haul, Designer).
- **Silent failure spirals, hidden systems, unbounded auto-delivery** (Casual, Completionist, Optimizer).
- **Credit-only gates for new places**, given the ~15,000× income spread at day 7 (Designer).
- **Pure credit sinks** that consume no goods (Designer).
- **Micromanagement:** per-shipment choices, perishable cargo, timers under 10 minutes, nagging
  notifications (Designer).
- **Ships, factions and pirates all at once** (Designer). **Padding** goals (New player).

---

## 8. Appendix

### 8.1 Per-persona summaries
Raw reports are in the playtest scratch folder, which may be cleared later.

**Casual, 4 visits/day, 14 days** ([report](round2/casual.md)).
Peak joy in the first 6 h. Two silent housing crashes cost ~30% of income. Days 2–7 "boring"; the tier-3
chain on days 10–12 was the best part, then a plateau. Soft quit day 3–4, hard quit day 12–14; 15 of 56
visits had nothing to do.

**Optimizer, 14 days** ([report](round2/optimizer.md)).
Found at minute 6 that Capacity + crew doubles a building for 60 credits. All bodies by hour 15, all
milestones by day 4.4, 4.2M cr/s by day 14, but from day 5 a script could replace the player. Showed the
market floor makes tier 3 nearly worthless. Quit day 4–5.

**Returner** ([report](round2/returner.md)).
4-day and 7-day absences each counted only 12 h, never stated. The once-a-day run stayed at 2 bodies for
21 real days (hidden kit path), ending with 37.6M and nothing to buy.

**Completionist, 30 days** ([report](round2/completionist.md)).
Everything built and claimed by day 4; last milestone day 12.4 only by hoarding; days 20–30 empty. Found
the stalled nickel route and 25–30% waste at the market floor.

**Long-haul, bots to 120 days** ([report](round2/longhaul.md)).
Week 1 is best; best payback then stretches from 3.5 h to 25 days. Good and lazy bots end at nearly the
same income by day 120. Found the unreloadable save and that the seed does nothing.

**New player, day 1** ([report](round2/newplayer.md)).
Never saw a building list; hit three walls at minute 27; found circuits at hour 4; ended at 24 cr/s with
995K and nothing to buy. Wrote the onboarding flow in 5(b).

**Senior designer** ([report](round2/designer.md)).
Claimed the whole system on day 1. Diagnosed crew dominance, instant everything, floods and chore
logistics; proposed the goal strip, timers, megaprojects, research, contracts, supply routes and the
content plan. Principle: "gate novelty by time and production, reward skill with numbers."

### 8.2 Pacing across personas
Real income (cr/s, from credits actually earned) · bodies owned. A dash means the run didn't reach that day.

| Persona | Day 1 | Day 3 | Day 7 | Day 14 |
|---|---|---|---|---|
| New player | ~24 · 2 | — | — | — |
| Casual (human) | ~7 · 3 | ~16 · 4 | ~25 · 4 | ~44 · 5 |
| Returner A (game days) | 15 · 3 | ~30 · 4 | 60 · 5 | — |
| Returner B (real days, 12 h counted each) | — | 13 · 2 | 21 · 2 | 49 · 2 |
| Completionist | ~15 · 3 | ~60 · 4 | ~780 · 5 | ~7.4K (d12.4) → 41K (d15.4) · 5 |
| Designer (hand) | ~260 · 5 | ~1.5K · 5 | ~25K · 5 | — (62K at d10.5) |
| Optimizer | 734 · 5 | 5.8K · 5 | ~382K (d7.9) · 5 | 4.2M · 5 |
| Casual bot | — | — | ~110 · 5 | ~295 · 5 |
| Balanced bot | ~90 · 2 | — | ~24K · 5 | ~71K · 5 |
| Greedy bot | — | — | ~17 · 1 | ~18 · 2 |

- Bot rows use the Designer's daily-income figures. The Long-haul report used the game's own cr/s
  readout, which overstates income (bug P2; its casual-bot day-14 figure is ~25× too high), though its
  trends hold.
- Human income at day 7 spans ~25 to ~382K cr/s, about 15,000×; credit prices alone can't pace both ends.
- Milestones on day 1: Optimizer 14 of 19, Completionist 6, New player 2.
