# Stage 1.6: Tuning from playtest round 3 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix what playtest round 3 found before the app is built.
- **Flattening:** the game flattens around day 9 for optimizers and day 13 for casuals.
- **Station chore:** station deliveries become manual hauling.
- **Contracts:** they pay for no effort.
- **Crew crash:** it happens silently.
- **Logistics:** some rules stay hidden.

**Source:**
- `docs/playtests/2026-11-27-round3-findings.md`: problems §2, decisions D1–D8 in §3, pacing targets §4.
- Persona reports in `docs/playtests/round3/`.

**Architecture:**
- Same engine rules as stage 1.5: state + commands + tick, validate before mutating, deterministic, data-driven content.
- New state fields must be:
  - serialized;
  - copied by `copy()`;
  - integrity-checked;
  - tolerated when absent (saves are still disposable pre-release; `saveVersion` stays 1).

**Global constraints:**
- `.superpowers/sdd/2026-11-26-stage1_5-depth-endgame/global-constraints.md` applies unchanged. That includes no English
  in `game_core` outcomes, and player messages built from typed outcomes in `game_sim`.
- The stage 1.5 regression probes must keep passing:
  - save/load at every check-in;
  - the command fuzzer;
  - catch-up vs 1 s stepping.
- Extend the fuzzer to cover every new command.

## Review focus
1. Auto-delivery and auto-pay never spend what the player reserved. They never take a body's local demand buffer or
   contract needs, and offline catch-up gives the same result as live stepping.
2. Contract rewards stay within the bounds in §4 on every bot and seed, and the first contract is still the hook.
3. Stop-level and auto-sell changes give step-size invariance: 1 s vs 60 s within 2%.
4. A crew shortage always ranks in the away summary when it costs credits.
5. Pacing targets in findings §4 are met on seeds 1–3, or each miss is explained with numbers.

---

### Task 1: Logistics honesty, CLI catalog, small fixes

**Files:** `game_core` logistics, market (auto-sell), flow_report, apply_* parts, survey, contracts (board display),
outcome; `game_sim` script_runner; docs.

- **Stop levels:**
  - A route's stop level counts only the destination's stock, not cargo in flight.
  - `CreateRouteCommand` and `UpdateRouteCommand` clamp the stop level to the destination's storage cap. The outcome
    reports that it was clamped and to what value.
  - Tests:
    - the casual bug-3 shape (rate × travel > stop) keeps the destination supplied;
    - a stop above the cap is clamped.
- **Whole units:**
  - Contract and megaproject deliveries move whole units only (floor). Costs and quantities are whole.
  - `stillNeeded` and `remaining` never show a fraction.
  - Test: deliver the shown remaining amount after earlier fractional stock, and the cost is complete.
- **Auto-sell buffer:** it shows in `state` per rule as "keeps N (keepAtLeast M + local use)".
- **Honest `FlowReport.creditsPerSec`:**
  - It is the steady-state sale revenue from net production. Stock drawn down by consumers or sold from the buffer does
    not count.
  - Acceptance: from a mid-game balanced-bot state, it is within 10% of credits earned per second over the next 2.5 h
    away.
  - Add a separate `stockSalesPerSec` if the app needs it.
- **New bottleneck kind `noSales`:** when nothing sells, production is positive and no auto-sell rule exists, the
  bottleneck says "Nothing is being sold: turn on auto-sell or sell goods".
- **CLI meta command `{"cmd":"catalog"}`:**
  - It lists every building def: cost, crew slots, level-1 inputs and outputs per second, and the owned bodies that can
    host it now (deposit present, slot free).
  - The `build` reply lists the building's full inputs.
  - An `unknownDef` build lists names and costs.
- **Small fixes:**
  - a survey project's state no longer exposes the hidden target's id (show "an unsurveyed body");
  - `unsurveyedSignals` drops while a survey targets one of them;
  - the "ongoing since" wording becomes "for 3h 10m";
  - an empty board at t=0 shows no "0s" refill line; refills due now are posted at state creation;
  - a missing upgrade track returns `noSuchTrack` (or the nearest fitting error), not `unknownDef`;
  - "Needs 1 more crew (you have 0 free)" while over-assigned says how many are over-assigned;
  - re-review minors:
    - a named survey checks the system first;
    - the "highest level" message does not fire while the final stage is running;
    - trim or document the extra public exports;
  - ships are usable at the exact `arriveAt` the outcome reported (the edge-of-tick ordering).
- [ ] Tests for each behaviour change. Docs (README, `docs/playtesting.md`) updated. Commit per area.

### Task 2: Away summary and crew honesty

**Files:** `game_core` engine (OfflineSummary), flow_report, crew, production; `game_sim` script_runner.

- **`crewShortage` gets a `lostCreditsPerHour`:**
  - Value: the credits/hour that the affected buildings lose at their current fraction compared with full staffing.
  - It ranks first among the away summary's `topBottlenecks` whenever it is nonzero.
  - The headline names it: "Crew short: 41 housed for 67 assigned".
- **`OfflineSummary` additions:**
  - `housingBefore` and `housingAfter`;
  - `creditsPerSecBefore` and `creditsPerSecAfter`;
  - `wastedValue` (credits, at current prices);
  - per ongoing bottleneck, `worseThanBefore` (its lost credits/hour grew by > 25%) and `since` (game time);
  - `nextGoal`: from `milestoneProgress`, the reached-soonest milestone by current rate, or the megaproject remaining
    with its ETA, using typed data only.
- **Housing flicker (round-3 new-player bug 1):**
  - Find why supported housing alternates tick to tick when a habitat input hovers near zero.
  - Make habitat input satisfaction stable: habitats take their inputs before same-depth consumers (already the rule),
    and housing uses the same tick's fraction that `state` reports.
  - Tests:
    - `state` and `report` agree on housing in the same tick;
    - a 60 s and a 1 s run give housing within 2%.
- **Capacity upgrades fill crew:** a capacity upgrade on a building fills its new slot from free crew. The outcome
  reports the crew added.
- [ ] Tests: the casual bug-2 shape ranks `crewShortage` first and puts it in the headline; the new summary fields
  round-trip; the existing summary tests still pass.

### Task 3: Contracts rework

**Files:** `game_core` contracts, market (auto-sell keep), content (`contracts.json` schema + validator); tests.

- **Quantity:**
  - Based on the faction's *gross* production rate of the resource (sum of building outputs at current fractions)
    × `quantitySeconds`.
  - Clamped to `[minQuantity, maxQuantity × qtyScale]`, where `qtyScale = 1 + megaproject levels summed`, and capped by
    the largest storage cap.
  - A resource with gross rate below `minQuantity / quantitySeconds` is ineligible: no "2 drones" orders from
    near-zero flows.
- **Reward:**
  - `rewardMultiplier × basePrice × quantity` (multiplier 3).
  - Floor: `rewardIncomeSeconds` of income, retuned to 600.
  - Cap: `rewardCapIncomeSeconds` (new, 3600) of income.
- **The first contract** a faction ever gets is exempt from the cap (onboarding hook). Pin it with a test.
- **Life-support goods** (anything a habitat consumes) get weight 0.25 in template choice.
- **Auto-sell** never sells, on a body, the amount the faction's open contracts still need of that resource. That is
  capped by the body's storage, and goes to the body with the largest stock of it when several qualify.
- **Content validation:** `rewardCapIncomeSeconds ≥ rewardIncomeSeconds`.
- [ ] Tests:
  - the bug-1 shape gets no tiny order;
  - the reward stays within the floor and cap;
  - the first contract is exempt;
  - the life-support weight is applied (statistical over a seeded run);
  - auto-sell holds contract needs;
  - the board refill rules are unchanged.

### Task 4: Megaprojects: compounding bonuses, Mass Driver, auto-delivery

**Files:** `game_core` megaprojects, content (`megaprojects.json` schema + validator), commands
(`SetMegaprojectAutoCommand`), state, engine tick order, outcome; `game_sim` script_runner, docs.

- **Bonus kinds:**
  - New `marketDepthMultiplier` and `productionSpeedMultiplier` kinds, compounding per level: `factor^level`, with an
    optional `appliesToMaxTier`.
  - The Orbital Station's `marketDepthPercent 25` becomes `marketDepthMultiplier 1.2`.
  - Each megaproject has a `bonusText`-free typed description: the app formats it. The CLI shows "level 3: storage +30%,
    market depth ×1.73, …".
- **Mass Driver content:**
  - Cost (base, growth ×2.5): credits, steel, hull plate, copper wire, water, food. Quantities are in the thousands to
    tens of thousands, tuned so the casual bot reaches L1 around days 6–8.
  - Bonus: `productionSpeedMultiplier 1.1` for tiers ≤ 1 and `marketDepthMultiplier 1.1` for tiers ≤ 1.
  - Unlock: `requiresMegaproject: {orbital_station: 2}`. This is a new optional field; the validator checks the
    reference.
- **Auto-delivery:**
  - `FactionState.megaprojectAuto: Map<String, {bool goods, BigNum? creditReserve}>`.
  - `SetMegaprojectAutoCommand(factionId, megaprojectId, goods, creditReserve?)`.
  - Every 60 game seconds, at a fixed boundary so that it is step-size invariant, the engine delivers what is still
    owed (current or queued level):
    - goods from each owned body above that body's keep, which is the local demand buffer plus open-contract needs;
    - with a credit reserve set, credits above that reserve.
  - It uses the same internal path as `DeliverToMegaprojectCommand`, so the integrity and queuing rules hold. Order in
    the tick: after production and logistics, before auto-sell.
  - `OfflineSummary` reports the amounts auto-delivered.
- [ ] Tests:
  - each bonus kind compounds and stays finite at level 1000;
  - the Mass Driver is locked before station level 2;
  - auto-delivery respects keeps and the credit reserve;
  - auto-delivery starts and queues stages;
  - catch-up vs 1 s stepping;
  - the fuzzer covers the new command;
  - save integrity for `megaprojectAuto`.

### Task 5: Milestones, slot growth, bots, pacing retune, baselines

**Files:** `content/milestones.json`, `content/rules.json`, `game_sim` bots and balance report, `docs/balance/`.

- **Milestones:**
  - credits 3B, 30B, 300B;
  - Orbital Station levels 4, 6, 8, 10;
  - Mass Driver levels 1, 3, 5;
  - 3 scaling rate milestones: segments 1/s, steel 1K/s, plates 500/s, or values the baselines show sit between days
    10 and 21.
  - Keep the milestone reachability test passing.
- **Slots:** `slotGrowth` 2.5 → 2.0.
- **Bots:**
  - enable auto-delivery with a reserve of 1 h of income;
  - work the Mass Driver;
  - stop hand-delivering where auto covers it;
  - the casual bot keeps its command budget.
- **Retune to findings §4.**
  - Content levers in order:
    1. Mass Driver costs;
    2. station `costGrowth` (3 → 2.5 allowed);
    3. contract multipliers;
    4. bonus factors.
  - Report every target on seeds 1–3, before and after.
- **Baselines:** regenerate `docs/balance/stage1_6-30day-{casual,balanced,greedy}.md` and the summary. Keep the stage 1.5
  files for comparison.
- [ ] `balance_targets_test` asserts:
  - contracts ≤ 15% of earnings at days 1, 7, 14;
  - casual milestone-or-project pacing ≥ 5/7;
  - balanced income growth from day 7 to day 14 ≥ 20%.

## After the plan (controller)
- A whole-branch review, then one fix wave.
- A short playtest: a casual 21-day and an optimizer 14-day run, checking the flattening and the contract feel.
- Then stage 2 (the app plan is already extended).
