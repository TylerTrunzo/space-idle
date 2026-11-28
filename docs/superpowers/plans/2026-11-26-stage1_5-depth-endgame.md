# Stage 1.5: Depth and Endgame Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the stage-1 economy a long, goal-rich arc before the app is built. That means real-time projects, the Orbital Station megaproject, a relaxed contracts board, hidden bodies found by surveys, about 40 milestones, an economy rebalance, and route and crew fixes, all in `game_core`, with bots and balance re-tuned.

**Architecture:** One new engine concept, **projects**: timed work in `GameState.projects`, which `tick` completes. Claims, slot expansions, surveys and megaproject stages become projects. Megaprojects and contracts are data-driven (`content/megaprojects.json`, contract templates in `content/contracts.json`). Bonuses from megaproject levels are folded into existing formulas through one `EmpireBonuses` lookup. Everything stays deterministic: contracts are generated from the state's `Rng`.

**Tech Stack:** Dart 3.14 (`/opt/flutter/bin`), `package:test`; existing `game_core` and `game_sim`.

**Spec:** `docs/superpowers/specs/2026-11-26-space-idle-design.md`, §14 (owner decisions) plus §6, §6.6 and §6.7. Evidence and the recommendation list: `docs/playtests/2026-11-26-round2-findings.md`, §5(a) items a1–a12.

## Global Constraints
- Every Global Constraint of the stage-1 plan still holds: pure Dart core, determinism, validate-before-mutate, `BigNum` quantities, data-driven content, no prestige, original names.
- **Timers [Owner]:** claims, slot expansions, surveys and megaproject stages take real time, between 10 minutes and 6 hours each. They have no skip and no speed-up purchase. Ordinary builds and upgrades stay instant.
- **Megaprojects [Owner]:** each level is a permanent empire-wide bonus, and the next level costs about ×3. They never reset.
- **Contracts [Owner]:** 3 slots, no expiry. An empty slot refills after `contractRefillSeconds` (content, default 4 h) and refills bank, so missing a day costs nothing. There are no limited-time events.
- **Offline cap [spec 6.7]:** 12 h base, raised by Orbital Station levels to a maximum of 48 h. `OfflineSummary` states the cap plainly (`capped: bool`, `secondsAway`, `secondsSimulated`).
- **Saves:** pre-release saves are disposable, so `saveVersion` stays 1. Every new state field is serialized, copied, integrity-checked and tolerated when absent.
- **Pacing targets** (casual bot, 4 check-ins a day):
  - something new (a milestone, project completion, contract or body) on at least 5 of every 7 days for the first 21 days;
  - Orbital Station level 1 around day 4–6, level 3 around day 14–21;
  - nothing in the content runs out before day 21.
  - For the balanced (optimizer) bot: 5 bodies at about day 2–3 (timers now slow claims), with megaproject levels continuing past day 30.

## Review Focus
1. A project in flight across save/load and offline catch-up: it completes at exactly its `finishAt`, and its effects apply once. (Task 1 test.)
2. A contract that becomes impossible (its resource is no longer produced): it never blocks anything, and the player can discard it. (Task 3 test.)
3. Two projects competing for the same items or credits: costs are taken when a project starts, so nothing can double-spend. (Task 1 test.)
4. A survey revealing a body while a claim project targets another body: no interference. (Task 4 test.)
5. Huge megaproject levels (level 50): the costs and bonuses stay finite, and the bonuses have a cap where the spec implies one (offline cap 48 h). (Task 2 test.)

---

### Task 1: Projects (timed work), with claims and slot expansions as projects

**Files:** Create `packages/game_core/lib/src/sim/projects.dart`, `packages/game_core/test/sim/projects_test.dart`. Modify `game_state.dart` (add `List<ProjectState> projects`), `apply.dart` (Claim and ExpandSlots start projects), `engine.dart` (tick completes projects; `OfflineSummary.projectsCompleted`), `save_codec.dart` (integrity), `content.dart` and `rules.json` (durations).

**Interfaces:**
- `enum ProjectKind { claim, expandSlots, survey, megaprojectStage }`
- `ProjectState { String id, String factionId, ProjectKind kind, String targetId /* body id or megaproject id */, double startedAt, double finishAt, Map<String,Object?> data }`. Serialized and copied. Ids come from `newId('p')`.
- Rules (`RulesDef`): `claimSecondsBase` (default 1800), `claimSecondsPerOwned` (default 1800, so the n-th claim takes base + perOwned × (owned − 1), clamped to [600, 21600]), and `expandSlotsSeconds` (default 3600).
- **Commands:**
  - `ClaimBodyCommand` validates as today, pays as today, then creates a claim project. It fails `alreadyOwned` / `routeInvalid` / a new `CommandError.projectInProgress` if a claim on the same body is already running. The body becomes owned on completion.
  - `ExpandSlotsCommand` does the same, and a second expansion on the same body while one is running → `projectInProgress`.
- `void stepProjects(GameState s, Content c)`: completes every project with `finishAt <= s.time`, in `finishAt`-then-id order, and applies its effect. It runs in `tick` after `stepMarket` and before the milestone check. `catchUpOffline` reports completions in `OfflineSummary.projectsCompleted` (list of `{kind, targetId, name}`).
- `GameEngine.projectsFor(GameState, factionId)` returns the running projects sorted by `finishAt`, for UI and bots.
- [ ] **Failing tests:**
  - a claim completes after its duration, and not before;
  - the duration formula with clamping;
  - costs are taken at start, so a second claim can't double-spend;
  - a project survives save/load and `copy()`;
  - completion during `catchUpOffline` is listed;
  - a completed claim makes the body owned exactly once;
  - `projectInProgress` errors.
- [ ] Implement, pass, analyze clean, commit `feat(core): timed projects; claims and slot expansions take real time`.

### Task 2: Megaprojects: Orbital Station, bonuses, offline cap path

**Files:** Create `content/megaprojects.json`, `packages/game_core/lib/src/sim/megaprojects.dart`, test file. Modify content model/loader/validator, `apply.dart` (new command), `production.dart`, `crew.dart` and `engine.dart` (apply bonuses), `game_state.dart` (`FactionState.megaprojectLevels: Map<String,int>`).

**Interfaces:**
- `MegaprojectDef { id, name, String hostBodyType? /* or any owned body */, Map<String,BigNum> baseCost /* resources + optional credits */, double costGrowth /* 3.0 */, double stageSeconds /* per level; base 7200 */, double stageSecondsGrowth /* 1.15, capped at 21600 */, List<BonusDef> bonusesPerLevel }`
- `BonusDef { BonusKind kind, double amount }` where `enum BonusKind { storagePercent, housingPercent, offlineCapSeconds, outputPercent, marketDepthPercent }`.
- Orbital Station level bonuses: +10% storage, +5% housing, +3600 s offline cap (the cap is clamped at 172800 s = 48 h total).
- Its cost draws on tier 2–3 goods (station segments, survey drones, reactor cores, hull plates, habitat modules) so every chain matters. The builder tunes it.
- `StartMegaprojectStageCommand(factionId, megaprojectId, bodyId)`:
  - takes the level-N cost from that body's stock (plus credits);
  - starts a `megaprojectStage` project;
  - `projectInProgress` if a stage of this megaproject is already running.
- On completion, `megaprojectLevels[id]++`.
- `EmpireBonuses bonusesFor(GameState, Content, factionId)` returns the summed bonuses. It is used by `storageCap`, crew housing, `catchUpOffline`'s cap, and market depth.
- `megaprojectCost(Content, MegaprojectDef, int level)` is public, for UI and bots.
- [ ] **Failing tests:**
  - level costs grow ×3;
  - starting a stage takes items, fails without them, and leaves state unchanged on failure;
  - completion raises the level;
  - +10% storage shows in `storageCap`;
  - housing bonus;
  - offline cap: 12 h base, 13 h at level 1, clamped at 48 h at level 50 (Review Focus 5);
  - a level-50 cost is finite;
  - content validation of `megaprojects.json`.
- [ ] Implement, pass, commit `feat(core): repeatable megaprojects with permanent bonuses; orbital station`.

### Task 3: Contracts board (neutral exchange)

**Files:** Create `content/contracts.json` (templates), `packages/game_core/lib/src/sim/contracts.dart`, test. Modify state (`FactionState.contracts: List<ContractState>`, `contractRefillAt: List<double>`), commands, engine tick, save codec.

**Interfaces:**
- `ContractTemplateDef { id, String issuer /* "Veyra Exchange" in stage 1.5 */, int minTier, int maxTier, double quantitySeconds /* a quantity of about this many seconds of the player's current production; default 14400 */, double rewardMultiplier /* reward = quantity × basePrice × this; default 2.5 */ }`
- `ContractState { id, templateId, String resourceId, BigNum quantity, BigNum delivered, BigNum rewardCredits, double postedAt }`
- **Generation** (`stepContracts`): whenever the faction has fewer than 3 contracts and `time >= contractRefillAt[0]`, generate one with `Rng` from the state.
  - It picks a resource of the template's tiers that the faction has produced (lifetimeProduced > 0), or a resource whose inputs it produces.
  - Quantity = max(minimum, current net production rate of that resource × quantitySeconds), rounded to 2 significant figures.
  - Refill timestamps bank: when a contract is filled or discarded, push `max(time, lastRefillAt) + contractRefillSeconds`.
  - At most 3 contracts, and at most 3 banked refills.
- **Commands:**
  - `DeliverContractCommand(factionId, contractId, bodyId, amount)`: takes stock from the body, partial delivery allowed, and pays the reward when complete.
  - `DiscardContractCommand(factionId, contractId)`: no penalty; it frees the slot onto the refill timer.
- **Milestone** condition type `contractsCompleted`.
- [ ] **Failing tests:**
  - 3 contracts appear after refills on a game with production;
  - generation is deterministic for the same seed and state;
  - partial and full delivery, and the reward is paid once;
  - discard has no penalty and the slot refills after 4 h;
  - refills bank while away (3 empty slots after 12 h away are all refilled on return);
  - a contract on a resource no longer produced can be discarded (Review Focus 2);
  - integrity checks for the new state.
- [ ] Implement, pass, commit `feat(core): relaxed contracts board from a neutral exchange`.

### Task 4: Hidden bodies and surveys

**Files:** Modify `content/galaxy.json` (2 hidden bodies: an outer ice moon and a far Kuiper-type rock with new deposits that make the tier-3 chains richer; add a `kuiper` body type if needed), the content model (`BodyDef.hidden: bool`), state (`BodyState.surveyed: bool`), commands (`SurveyCommand(factionId, bodyId, sourceBodyId)` costs survey drones from the source body plus credits, and starts a `survey` project of 2–4 h), `costs`/state output, tests.
- Hidden bodies can't be claimed, routed to or seen in `state` until surveyed (`unknownBody`). Visible-but-unsurveyed is not needed in stage 1.5; all 5 original bodies count as surveyed.
- [ ] **Failing tests:**
  - a hidden body is not claimable;
  - a survey reveals it on completion;
  - a survey and a claim run in parallel without interfering (Review Focus 4);
  - survey drones finally have a use (shipped content test: survey_drone is consumed by something).
- [ ] Implement, pass, commit `feat(core): survey drones reveal hidden bodies`.

### Task 5: Economy rebalance (content plus small rule changes)

From findings a2, a3, a4, a5, a9:
- **a2 crew:**
  - The habitat capacity upgrade also raises that habitat's life-support inputs proportionally (housing × (1 + 0.25L), inputs × (1 + 0.25L)).
  - Building capacity upgrade costs follow a curve comparable to speed. The builder tunes it so capacity is no longer 5–10× better than speed after hour 1.
- **a3 market:** retune the per-resource floors and depth so late income comes from high tiers, not from dumping low tiers at the floor. Target at day 14 (balanced bot): tier 0–1 goods ≤ 35% of income, and no single resource > 30%.
- **a4 upgrades:**
  - Cost growth about ×1.15–1.18, or a speed doubling every 10 levels.
  - The efficiency floor stays, but `costs` marks a track at its cap as `maxed: true` and the command fails `invalidAmount` ("already at its best").
  - A track that can't help (efficiency on a building with no inputs, or capacity on a building with 0 base slots) is also marked.
- **a5 floods:** claim kits = 5 × (owned − 1) + 5 for later claims (tune). Lower component output so a 6 h nap makes tens, not hundreds, of kits, modules and ships.
- **a9 dead buildings:** give the hydrogen furnace, protein vat, propellant mixer, depot and fusion refinery each a clear niche. For example: a recipe that is better on a body lacking the usual input; the depot also halving waste; fusion fuel feeding megaproject or reactor costs. Every building must be the best choice in some situation; document which.
- [ ] Update content and rule code with tests; the shipped-content tests assert the market and income targets via a bot run where practical.
- [ ] Commit `balance: crew, market, upgrade curve, component volume, building niches`.

### Task 6: About 40 milestones and new condition types

- New condition types:
  - `productionRate` (empire net per second of a resource ≥ X)
  - `buildingTypesBuilt` (count of distinct defs owned ≥ N)
  - `crewTotal` (supported ≥ N)
  - `megaprojectLevel`
  - `contractsCompleted`
  - `zeroWasteFor` (seconds without empire waste ≥ N; track `wasteFreeSince` in state)
  - `lifetimeCredits` thresholds past 1B (10B, 100B, 1T)
  - `bodiesSurveyed`
- About 40 milestones total, spread across 21+ days for the casual bot (Global Constraints pacing). Each has a short, original, flavorful name.
- [ ] Tests per condition type, plus a shipped-content test that there are ≥ 38 milestones and every one is reachable in principle. Commit `feat(core): forty milestones with new condition types`.

### Task 7: Routes, crew and messaging quality of life

From a8, a10, a11, a12 plus the open bugfix-wave concern:
- **Routes:**
  - `CreateRouteCommand`/`UpdateRouteCommand` gain `BigNum? stopAtDestination` (the route pauses while the destination holds ≥ N).
  - New `UpdateRouteCommand(factionId, routeId, {ratePerSecond, cargoShips, stopAtDestination})` and `MoveShipsCommand(factionId, fromBodyId, toBodyId, int count)`, which ships cargo ships as an instant-start shipment with normal travel time.
  - Routes are served before auto-sell takes their resource on the source body.
- **Crew:** a newly built building is auto-assigned crew up to its base slots if free crew exists (`BuildCommand.autoCrew`, default true; false leaves it empty).
- **Auto-sell keep horizon:** keep local demand for `max(dt, rules.shipmentMergeSeconds)`, so live 1 s play doesn't sell route-fed inputs (bugfix-wave concern 1).
- **Errors:**
  - `unknownDef` on build lists the valid building names for that body;
  - `cannotAfford` for a claim's kits names the kit and its recipe inputs;
  - the first claim's reply notes "no kits needed".
- **Offline:** `OfflineSummary.capped`, `capSeconds`, and a one-line `headline` ("Away 4d 2h; 12h counted (cap). +1.2M credits").
- [ ] Tests for each; commit per group.

### Task 8: Bots, balance targets, baselines, quick playtest

- Bots learn projects (start claims early, plan around timers), megaproject stages, contracts (deliver when stock allows, discard impossible ones), surveys, `stopAtDestination`, and auto-crew.
- Tune content to the Global Constraints pacing targets. Run casual and balanced for 30 days.
- Regenerate `docs/balance/` baselines (30-day runs) and include the milestone timeline, the new-thing-per-day count, and income share by tier.
- Commit `feat(sim): bots for projects, megaprojects, contracts; 30-day baselines`.

## After the plan (controller)
- A whole-branch review of the stage-1.5 range, then a fix wave.
- A quick 3-persona playtest (casual 21 days, optimizer 14 days, new player day 1) against the pacing targets.
- Then stage 2 (the app plan is already written; extend it with the goal strip, projects, megaprojects and contracts UI before starting).
