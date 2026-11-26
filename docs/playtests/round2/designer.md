# Design review: Space Idle, stage 1 economy (Game designer persona)

## Persona and run
- **Persona:** senior designer of idle, incremental and management games.
- **Hand play:** seed 61, about 252 game hours (10.5 days), 45 check-ins. I played the first 30 h fully by hand: about 12 sessions covering crew allocation, the first claim, habitats, routes and the Cinder→Vastmere→Kora reactor and station chain. From 30 h to 102 h I hand-fixed bottlenecks at each visit, then spent with a "buy the cheapest speed level" helper, standing in for a "buy max" button. At 102 h and 108 h I did two hand-made crew boosts.
- **Bots:** balanced, casual and greedy, 336 h (14 days) each, seed 61.
- **Seed does nothing yet.** The seed 61 bot runs give the same milestones and the same income per day as the seed 1 baselines (balanced day 1 is 7.71M in both). The galaxy is fixed in content, so every game is the same game.
- **Files:** everything is in `/tmp/claude-0/-home-user/7963d8b4-7ef1-5bbc-9bff-b2b24979e3ee/scratchpad/pt2-designer/`: the bot reports `bot_*.md`, the full command log `my_game.jsonl`, the saves, and the repros.

---

## 1. What the game is today

### Pacing and numbers (my hand run)
Credits per second are taken from the away gains.

| Game time | Credits/s | Bodies owned | Milestones and events |
|---|---:|---:|---|
| 0.1 h | 2 → 7 | 1 | Capacity + crew doubles a building for 60 cr |
| 6 h | ~10 | 1 → 2 | 10K; claimed Brine; 4 habitats: crew 20 → 100 (best moment) |
| 12 h | ~105 | 4 | Outpost Ready, Millionaire; 715 habitat modules, 718 cargo ships and 346 kits piled up in one nap |
| 24 h | ~260 | 5 | 10M, Whole System (the whole system was claimed on day 1) |
| 30 h | ~250 | 5 | Fusion Heart, Orbital Foundations: 15 of 19 milestones done |
| 84–102 h | 1.5K → 1.75K | 5 | Nothing new. Spending 90% on speed each visit gives about +4% |
| 108 h | 4.7K | 5 | 2.6M spent on habitat capacity and crew made income 2.7× (100M) |
| 132 h | 14K | 5 | 300M |
| 186 h | 35K | 5 | Billionaire (the last milestone in the game) |
| 252 h | 62K | 5 | Nothing new for about 5 days; the same 3 bottleneck lines at every visit |

### Bots over 14 days

| Bot | Last new (non-credit) milestone | Last milestone | Income on day 7 | Income on day 14 | Shape |
|---|---|---|---:|---:|---|
| Balanced | 60 h | 1B at 198 h | 2.05B | 6.13B | Flattens on days 8–12 (2.7B → 3.5B) |
| Casual | 150 h | 100M at 288 h | 9.6M | 25.5M | One milestone in days 7–14 |
| Greedy | none | 3M at 102 h | 1.43M | 1.53M | Exactly flat from day 8; never claims; 24 of 27 resources unused |

### Diagnosis
1. **Content runs out on day 1–2 for an engaged player, and on day 6 for a casual one.** After that the only goals are credit thresholds, and after 1B there is nothing at all. Credits are the only thing that accumulates, so there are no new decisions.
2. **Crew is the dominant lever, and it is underpriced.**
   - At 102 h, 2.6M credits of habitat capacity plus building capacity tripled income. The previous visit's 35M of speed levels gave about +4%.
   - At 252 h, a mine's capacity level 21 costs 6.5K and its speed level 66 costs 124M.
   - Habitat capacity adds housing with no extra food, water or oxygen, so crew is almost free.
   - The efficiency track was never worth touching: it still costs 100 at 1.5B credits.
   - Together, this collapses "ratios and optimization" into "add housing, multiply crew". The spec's anti-goal is a shallow economy; this is the main threat to it.
3. **Nothing ever finishes.** There are no construction, research or travel timers longer than a minute (claims, builds and upgrades are instant). Spec §6.7 says each check-in should usually have something finished to act on. Today the only thing waiting for you is a bigger credit number.
4. **Tier-2 goods are made in floods.** One 6 h nap produced hundreds of kits, modules and ships, while claims cost 2–4 kits. The kit gate is meaningless and cargo ships are effectively unlimited, which undercuts the "slow building" pleasure.
5. **Logistics is a chore, not a puzzle.**
   - To start a route from a body you must first ship cargo ships to it.
   - A route pushes a fixed rate whatever the destination needs, so goods are wasted at full storage (45M units in one of my away periods).
   - There is no way to edit a route, only remove and recreate it.
6. **The market is the only demand.** Every chain exists only for its sale price. Hull plates are 30–50% of income in every bot, for the whole run.
7. **Clarity problems:**
   - The report's `creditsPerSec` overstates income (see Bugs).
   - Auto-sell keeps a hidden buffer: "keep 200" left 4.93K steel.
   - The away summary gives waste in units, not credits.
   - `costs` shows a next claim (143M + 5 kits) when no body is left to claim.
   - New buildings start with 0 crew even when 125 crew are free.
   - The same bottleneck lines repeat for days.

### Fun
- **Best:**
  - The early crew puzzle: 20 crew, who gets them?
  - The habitat moment: supported crew 20 → 100 → 260.
  - The first time a 3-body chain ran (Cinder magnets → Vastmere reactor cores → Kora station segments).
  - The growth curve in hours 0–30.
- **Worst:**
  - Shipping cargo ships so I could make routes, and recreating routes to change a rate.
  - A visit spent only saving for the 11M claim.
  - Clicking speed levels that do almost nothing.
  - Day 5+ visits where the summary is the same as last time.

---

## 2. Core loops at three time scales

| Scale | Today | Proposed: what the player does | Proposed: what the player wants |
|---|---|---|---|
| **Session (2–5 min)** | Read the summary, fix 1–2 bottlenecks, spend all credits on upgrades | 1) Collect what finished: buildings, research, expeditions, contract payouts. 2) Fix the top bottleneck, with one-tap fixes in the summary. 3) Rebalance crew and ratios, and buy upgrades (with buy ×10 or max). 4) Queue the next construction, research and delivery so something finishes while away. | "My empire runs better than when I arrived, and something is cooking." |
| **Day (3–5 sessions)** | Claims on day 1 only; then nothing | A construction or research step of several hours finishes; a faction contract is delivered; a new chain or body comes online about every 1–2 days early on, then every 2–4 days; a megaproject stage advances | "Today I unlocked or finished X." |
| **Weeks** | None | Open a new system through exploration and warp; meet a faction and build a relationship; finish a megaproject level (permanent bonus); design a new ship class; reach a galactic victory milestone | "My empire is visibly bigger on the map, and I have a long project I'm proud of." |

Guiding principle: **gate novelty by time and production, and reward skill with numbers.**
- The balanced bot earns 15–200× what the casual bot earns, so no credit-priced gate can pace both.
- Construction, research and travel timers, plus item-quantity gates, shrink that spread for unlocks.
- Optimizers still win on income, records and megaproject levels.

---

## 3. Goal structure: always show three horizons
A persistent **Goals strip** (stage 2 UI) with three slots, each with a progress bar:
- **Immediate (this session):** the top bottleneck with its fix, the best upgrade for its cost, or crew to assign.
- **Session / day (hours):** the active construction or research timer, the nearest contract, and the next milestone on the ladder with its progress ("Station segments 37 / 50").
- **Long term (days to weeks):** the next region unlock (for example "Survey Veyra's outer belt: 3 / 5 drones"), the current megaproject level, and the next victory milestone.

**Milestone ladder:**
- Show the next 3 milestones with progress, not a hidden list.
- Move from stock conditions to **lifetime-produced** conditions. Stock conditions are currently defeated by auto-sell (see Bugs).
- Go from 19 to about 60 in stage 1–3 content, and 100+ by stage 5.
- Mix the types: production, chain-quality ("all Kora buildings at 95% or better for 24 h"), expansion, collection and records.

---

## 4. Progression systems and how they lock into the chains
Every system below should **consume chain output** (a demand sink) and **unlock new chain shapes** (new decisions). Pure credit sinks do neither.

### Research / tech (stages 2–5; start small)
- **Points:** a Lab building turns components into research points. Tier 1 labs use circuits and wafers; later labs use AI cores and exotic matter. So research is another chain to balance, not a credit sink.
- **Pacing:** nodes take real time (30 min early, up to 8–12 h late), with 1 research slot at first and a 2nd and 3rd from research. This is the main "something finished" source.
- **What it unlocks:**
  - recipes and building types (the next tier);
  - upgrade tracks and caps (for example "Deep core drilling: +1 deposit throughput tier");
  - QoL automation that the player earns: buy ×10 or max, auto-assign crew to new buildings, supply routes, auto-sell presets;
  - the offline cap, 12 h → 48 h, as the spec suggests;
  - map scanner range.
- **Size:** about 40–50 nodes in 5 bands, one per region. The spec allows folding research into region unlocks, but this is the system I would protect most: it is the cheapest long-term goal generator.

### Region unlocks (stages 3–5)
- Use the **orphaned survey drone**, which is the balanced bot's only unused item.
- Drones survey Veyra's hidden bodies (add 2: an outer ice moon and a Kuiper object). A warp-drive item plus a lane-beacon construction (hours) opens neighbor systems.
- Each region adds 2–4 raw resources that only exist there and one new tier, so old chains feed new ones. Old planets keep mattering because the new recipes need their outputs.
- Unlocks cost **items in quantity**, not credits ("Warp Gate Mk I: 500 hull plates, 50 reactor cores, 20 warp coils"), so casual and optimizer players arrive at similar times.

### Repeatable megaprojects (stage 1 content, small engine work; the endless spine)
- They are built in stages at a Megaproject Dock. Each stage is a large item delivery plus a timer.
- Each completion gives a **permanent empire bonus** and the next level costs about ×2.5–4.
- Examples:
  - **Orbital Station** (home): consumes the station segments that exist now. Each level adds +10% storage and +1 offline hour, or +5% crew housing.
  - **Mass Driver:** cuts route travel time.
  - **Dyson Swarm Segment:** an empire-wide production multiplier.
  - **Star Gate:** unlocks a lane, then later levels cut lane time.
  - **Ring Habitat:** a crew multiplier.
  - **Galactic Exchange:** raises market depth.
- Mix the inputs so that every chain feeds some megaproject. That fixes the problem that hull plates are the only point of the economy, and gives "numbers get bigger" its long tail without a reset.

### Ship design (spec §13; stage 3)
- Hulls and modules are produced items: about 8–10 new items, for example cargo hold, ion engine, armor plate, shield emitter, scanner array, crew quarters, weapon mount and a warp coil, plus 4 hull sizes.
- Ships are designs, and a route's capacity and travel time come from the assigned design.
- This replaces the generic cargo ship and fixes the flood: ships become a real production commitment with crew upkeep.
- Trade-offs must matter, so travel time must matter:
  - inter-system lanes take minutes to hours;
  - couriers suit urgent contract deliveries;
  - haulers suit bulk;
  - armor or escorts suit pirate lanes.
- **Avoid** perishable cargo and per-shipment micromanagement.

### Factions and diplomacy (stage 3)
- Factions are a **demand source**. Each has standing needs ("The Trader Collective buys magnets at 1.6×") and posts **contracts**.
- Reputation unlocks:
  - trade deals: a steady exchange of X/s for Y/s, which is a pure ratio puzzle the owner will love;
  - pacts;
  - **peaceful cession of planets**, the spec's war-optional route.
- Personalities shape what each faction asks for. A militarist wants hulls and fuel; an isolationist wants food and medical goods.

### Pirates (stages 3–4)
- They are a **risk-versus-throughput ratio decision**: the short lane through the Drift has a 6% raid chance, the long lane is safe.
- Risk shading on the map shows before you commit. Escorts, armor and scanners reduce it.
- Offline losses are capped as in §13.3, and raids are always listed in the away summary.
- Optional pirate-base hunts reward rare blueprints and exotic samples, never anything mandatory.

### Exploration (stage 5, with a first slice in stage 3)
- Bodies start unsurveyed. Explorer designs with range reveal deposits and richness, which also fixes the first-claim trap.
- **Anomalies** (seeded): a derelict holding a blueprint, a 2.0-richness deposit, a lost colony that joins for a habitat-module delivery. These are one-off pleasant surprises.
- **A procedural outer galaxy from the seed** makes the seed mean something and gives replay value. Keep Veyra handcrafted as the tutorial system.

---

## 5. Retention mechanics that respect the player
**Add:**
- **Away summary 2.0:**
  - a headline delta ("+1.35B, +8% vs your last visit, peak 62K/s");
  - things that completed;
  - events and raids;
  - waste **in credits**;
  - the top 3 bottlenecks with one-tap fixes;
  - the three goal bars.

  This makes every return feel rewarded even when nothing new unlocked.
- **A contracts board:**
  - 3 open orders from factions, or from a neutral "Veyra Exchange" in stage 1–2;
  - long expiry (48–72 h) or none, and a new one appears when one is filled;
  - unfilled slots bank up to 3, so missing a day costs nothing;
  - each order targets a mid-chain good in a quantity that stretches current ratios;
  - rewards are reputation, blueprints, and sometimes a megaproject part.
- **Rotating market demand:** a slow drift of regional multipliers over 2–4 days, shown in advance ("Demand rising: magnets"). It nudges re-optimization without punishing anyone who misses it.
- **Optimization achievements:** for example zero waste for 24 h, a 6-step chain at 100%, every building at 95% or better, a trade deal exactly balanced. These reward pleasure #3 directly.
- **Records and collections:** personal bests per good and per second; a Codex of items produced, bodies surveyed, anomalies found and ship designs. This is "numbers bigger" plus "slow building" as a visible trophy case.
- **Gentle opt-in notifications:** "Research done", "Construction finished", never "come back or lose X".
- **Timers sized to the rhythm:** most completions take 1–6 h so a 4-a-day player always finds something done. A few take 12–24 h as overnight payoffs, and the offline cap stays at 12 h or more.

**Avoid:**
- login streaks or daily-reward calendars;
- contracts that expire in hours;
- energy or stamina;
- "double offline earnings" style prompts;
- events you can only get by being online in a window;
- any raid or attack that resolves badly while offline (already an anti-goal);
- timers too short to return to (<10 min) that pull players back compulsively;
- notification nagging;
- prestige or resets (the owner has ruled these out);
- a premium-feeling "skip timer" button, even a free one, because it turns timers into friction.

---

## 6. Content length plan
Targets are for a casual player (4 visits a day) and an optimizer. Current home-system novelty lasts about 30 h for an optimizer and about 150 h for a casual player.

| Phase | Casual target | Optimizer target | Content needed |
|---|---|---|---|
| 1. Home, Veyra (stage 1–2 content) | days 1–7 | days 1–3 | 5 → 7 bodies (2 surveyed late); 27 → ~32 items; 25 → ~30 buildings; ~25 milestones; Orbital Station levels 1–3; research band 1 (8 nodes) |
| 2. Outer Veyra, ships, first contact (stage 3) | weeks 2–3 | days 4–9 | +8–10 module and hull items; +6 buildings (shipyard lines, labs); 1–2 factions; contracts; light pirates; research band 2 (10 nodes) |
| 3. Neighbor systems through warp (stages 3–4) | weeks 3–6 | days 10–21 | 2–3 systems, about 15 bodies; +8 advanced items (AI core, shield generator, warp coil, terraforming kit, weapons…); +8 buildings; 4–5 factions; diplomacy and war; research band 3 (10 nodes); megaprojects 2–3 |
| 4. Distant and exotic (stage 5) | weeks 6–10 | weeks 3–6 | 2–3 systems, about 12 bodies; exotic raws (void crystal, dark matter, antimatter) and +6 items; +6 buildings; anomalies; research band 4 (10 nodes) |
| 5. Endless (stage 5) | week 10+ | week 6+ | Repeatable megaprojects (6–8 types); galactic victory milestones; records |

- **Totals:** about 55–60 items (inside the spec's 40–60 band), about 50 building types, about 8 systems and 40 bodies, about 100 milestones and achievements, 40–50 research nodes, 5 factions and 6–8 megaprojects.
- **Number curve target:** a new order of magnitude in income about every 12–24 h in week 1, then about 1–2 per week. Each region adds a step multiplier through higher-tier prices and megaproject bonuses, so growth never stalls flat the way greedy does on days 8–14 or balanced does on days 8–12.

---

## 7. Risks: where players quit
1. **Day 1–2, optimizer:** the whole system is claimed by 30 h, 15 of 19 milestones are done, and nothing new appears. This is the biggest cliff in the game today.
2. **Days 3–7, casual:** logistics chores (ship the ships, recreate routes) and a 100M milestone a week away.
3. **Day 5+:**
   - The same bottleneck text at every visit.
   - The best action is always "buy speed" or "add crew", so there is no decision.
   - That is the "spreadsheet without a sense of place" anti-goal.
4. **Abundance:** hundreds of components after a nap kill the feeling of slow building.
5. **A lost save:** the negative-stock bug below would end a real player's game on reload.
6. **Later stages:** complexity overload when ships, factions and pirates all arrive at once. Introduce them one at a time, with each one solving a problem the player already has. Ship-design UI on a phone is another risk. Any perceived offline loss to pirates or war would break trust.
7. **The optimizer/casual gap:** content tuned for one bores or blocks the other. Time and item gates (section 2) are the mitigation.

---

## 8. Top 15 changes, in priority order

| # | Change | Stage | Effort | Pleasure served |
|---|---|---|---|---|
| 1 | Fix the unloadable save: clamp tiny negative float stock to zero when saving or loading (see Bugs) | now | S | All (trust) |
| 2 | Milestones count lifetime production, not stock; show a visible ladder of the next 3 with progress; grow to ~60 milestones including optimization achievements | now, then stage 2 UI | S–M | Numbers, optimization |
| 3 | Economy rebalance: habitat capacity raises life-support draw (or needs modules), crew has upkeep, capacity costs follow a curve comparable to speed, efficiency matters through raw-throughput limits per deposit, claim kits scale (for example 25 × n) and tier-2 volume is tuned down; break the hull-plate monopoly | now | M | Optimization (the core one) |
| 4 | Construction timers for buildings, claims, slots and megaproject stages (minutes to hours), with a build queue that research expands | stage 1 engine, stage 2 UI | M | Slow building, check-in payoff |
| 5 | Repeatable megaprojects, starting with an Orbital Station that consumes station segments and drones; permanent bonuses; each level costs about ×3 | stage 1 content, small engine change | M | Numbers, slow building |
| 6 | Supply routes ("keep the destination stocked at X" or "ship what the destination uses"), a shared ship pool per system, editable routes; no more shipping ships to make routes | stage 1–2 | M | Optimization (removes chores) |
| 7 | Away summary 2.0: delta vs the last visit, waste in credits, completions, one-tap fixes, three goal bars | stage 2 | S–M | Numbers, retention |
| 8 | Bulk-buy and automation QoL (×10/max, auto-crew new buildings, auto-sell presets), unlocked through research | stage 2 | S–M | Numbers (keeps visits to 2–5 min) |
| 9 | Research tree: labs consume components; real-time nodes; unlocks recipes, tracks, QoL and offline cap up to 48 h | stage 2 (band 1), up to stage 5 | L | Optimization, slow building |
| 10 | Contracts board (3 orders, long or no expiry, banked slots), first from a neutral exchange, then from factions with reputation | stage 2–3 | M | Optimization (ratio targets), retention |
| 11 | Ship design: hulls and modules as produced items; route stats come from designs | stage 3 | L | Optimization, slow building |
| 12 | Rotating regional market demand and more than one market; where to sell becomes a route decision | stage 3 | M | Optimization |
| 13 | Region unlock through survey drones, then warp items: hidden Veyra bodies first, then neighbor systems, gated by item quantities | stage 3 slice, stage 5 full | L | Slow building |
| 14 | Pirates on outer lanes: visible risk, escorts and armor, capped offline loss, optional base hunts that drop blueprints | stage 3–4 | M | Optimization (risk vs throughput) |
| 15 | Seeded procedural outer galaxy with anomalies and a Codex collection; Veyra stays handmade | stage 5 | L | Slow building, replay |

---

## Bugs and clarity defects
All files are in `/tmp/claude-0/-home-user/7963d8b4-7ef1-5bbc-9bff-b2b24979e3ee/scratchpad/pt2-designer/`.

1. **Critical: a save that cannot be loaded.**
   - Float error left Cinder's magnet stock at -1.6e-11. `save` wrote it, and `load` then fails with "body cinder: negative stock of magnet".
   - Files: `save_BUG_negative_magnet_t144h.json` (my save, which fails to load) and `replay_bug.jsonl` (the replay script).
   - Repro: run `dart run game_sim:game_sim --seed 61 --content ../../content --script replay_bug.jsonl` from a new game. It ends with a save to `replay_save.json`, which then fails to `--load` the same way (here magnet is -1.1e-10).
   - Likely setup: a magnet route out of Cinder, auto-sell of magnet (keep 500) and Magnet Works all on the same body.
2. **Auto-sell defeats stock milestones.**
   - With auto-sell keep 0, station segments never reach a stock of 1, so "Orbital Foundations" never fires. "First Foundry" fired 6 h late for the same reason.
   - Repro: load `save_t108960_autosell_milestone.json`; no milestone in 6 h. Set `{"cmd":"setAutoSell","bodyId":"kora","resourceId":"station_segment","keepAtLeast":null}` and it fires within 240 s.
3. **The report overstates `creditsPerSec`.**
   - Its 1 s sample sells the auto-sell buffer that is kept for 60 s steps.
   - Repro: `repro_report_cps.jsonl`, seed 61. The report says 15.9/s; the next 600 s actually earn 0.45/s.
   - In my game the report said 138/s while I was earning about 9/s.
4. **Smaller clarity issues:**
   - Auto-sell "keep 200" silently kept 4.93K steel.
   - `costs` lists a next claim when no body is left to claim.
   - The away summary's `totalWasted` is in units and `stockGained` can be negative, both unexplained.
   - New buildings start with 0 crew.
   - Buildings and routes share one id counter (r17 after b16).
   - There is no command to edit a route.
