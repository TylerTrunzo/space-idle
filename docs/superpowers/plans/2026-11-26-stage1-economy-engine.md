# Stage 1: Economy Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A pure-Dart, deterministic, headless economy engine (`game_core`) plus a CLI (`game_sim`) that can run, script, bot-play, and report on the space idle game's production economy.

**Architecture:** Dart pub workspace. `packages/game_core` holds all rules: big-number type, seeded RNG, data-driven content loaded from JSON, a mutable serializable `GameState`, validated `Command`s, and `GameEngine.tick/advance`. `packages/game_sim` is a CLI that loads `content/*.json`, runs JSON-lines scripts or bots, and prints JSON reports. No Flutter in this stage.

**Tech Stack:** Dart 3.14 (from Flutter 3.50.1 at `/opt/flutter/bin`), `package:test`, `package:lints`, `package:args` (sim only). GitHub Actions for CI.

**Spec:** `docs/superpowers/specs/2026-11-26-space-idle-design.md` (sections 5.1, 5.2, 5.4, 6, 10, 11 stage 1).

## Global Constraints

- `game_core` must not import Flutter, `dart:io`, `dart:html`, or `dart:ffi`. It must compile for VM and web (JS). `dart:math` and `dart:convert` are fine.
- Determinism: identical starting state + seed + command sequence produces byte-identical `GameState.toJson()` output. All randomness goes through `Rng` stored in state. Iterate maps/lists in a stable order (insertion order of content or sorted ids), never `Set`/`Map` order from hashing of non-deterministic keys.
- Every command is validated inside `game_core` against current state and the acting faction (spec §5.4). Invalid commands return a `CommandResult` with an error and leave state unchanged.
- Quantities, rates, costs, and credits use `BigNum` (spec §5.1). Plain `double` is allowed for fractions/multipliers in `[0, 1e6]` (crew fraction, satisfaction, saturation, upgrade multipliers before they're applied).
- Content is data-driven from `content/*.json` at repo root and validated at load (spec §5.1).
- No prestige/reset. Deposits never deplete (spec §6.1). Offline cap base = 12 h = 43200 s (spec §6.7).
- Original names only. Nothing copied from any existing game.
- Run Dart via `/opt/flutter/bin/dart` (add `/opt/flutter/bin` to `PATH`).
- Commit after each task with the session's attribution trailer lines.
- Implementers may load the `flutter:seeded-determinism-and-golden-vectors`, `flutter:value-objects-money-and-units`, `flutter:dart3-idioms-and-coding-standards`, and `flutter:project-structure-and-packages` skills for style. Where they conflict with this plan, this plan wins.

## Review Focus

1. **Huge time jumps:** `advance(state, 30 days)` (offline catch-up after a long absence, capped) must finish quickly and not explode numbers through step artifacts. Covered by the Task 8 performance and step-invariance tests.
2. **Starvation cascades:** a building whose input stock is zero must produce nothing and must not drive any stock negative. No stock may ever go below zero after any tick. Covered by the Task 6 invariant test.
3. **Malformed saves/content:** loading a save with an unknown version, missing fields, or content ids that no longer exist must return a typed error, not crash. Covered by Task 4 and Task 3 tests.
4. **Commands referencing other factions' things:** assigning crew to, upgrading, or routing from a body owned by another faction must be rejected. Covered by Task 5 tests.
5. **Number formatting at boundaries:** 999.5, 999999, 1e36, 0, and negative values must format sensibly ("1K" not "1000K"). Covered by Task 1 tests.

---

## File Structure

```
pubspec.yaml                         workspace root (workspace: [packages/game_core, packages/game_sim])
analysis_options.yaml                include: package:lints/recommended.yaml (+ strict-casts, strict-raw-types)
.github/workflows/ci.yml             dart analyze + dart test for both packages
content/
  rules.json                         global tuning numbers
  resources.json                     items (all tiers)
  buildings.json                     building types and their recipes/upgrade costs
  body_types.json                    planet types: deposit pools, build slots
  galaxy.json                        stage-1 starting galaxy (systems, bodies, starting faction setup)
  milestones.json                    named progress milestones for reports
packages/game_core/
  lib/game_core.dart                 barrel export
  lib/src/num/big_num.dart           BigNum
  lib/src/num/format.dart            formatNumber
  lib/src/rng.dart                   Rng (32-bit, web-safe)
  lib/src/content/content.dart       Content + defs (ResourceDef, BuildingDef, BodyTypeDef, RulesDef, GalaxyDef, MilestoneDef)
  lib/src/content/content_loader.dart  Content.fromBundle + validation errors
  lib/src/state/game_state.dart      GameState, FactionState, BodyState, BuildingState, RouteState, Shipment, MarketState
  lib/src/state/save_codec.dart      SaveCodec (encode/decode/migrate)
  lib/src/commands/command.dart      sealed Command + subclasses, CommandResult, CommandError
  lib/src/commands/apply.dart        applyCommand
  lib/src/sim/production.dart        per-step production
  lib/src/sim/logistics.dart         routes and shipments
  lib/src/sim/market.dart            selling, saturation, auto-sell
  lib/src/sim/crew.dart              housing and crew efficiency
  lib/src/sim/engine.dart            GameEngine (newGame, apply, tick, advance, catchUpOffline)
  lib/src/report/flow_report.dart    FlowReport, BuildingStatus, Bottleneck
  test/...                           one test file per src file
packages/game_sim/
  bin/game_sim.dart                  CLI entry
  lib/src/content_files.dart         loadContentDir(path) -> Map bundle (dart:io allowed here)
  lib/src/script_runner.dart         JSON-lines command runner
  lib/src/bots/bot.dart              Bot interface + GreedyBot + BalancedBot
  lib/src/balance_report.dart        milestone timeline, dead zones, unused items
  test/...
docs/playtesting.md                  how subagent playtesters use game_sim
```

---

### Task 1: Workspace scaffold, BigNum, number formatting

**Files:**
- Create: `pubspec.yaml`, `analysis_options.yaml`, `packages/game_core/pubspec.yaml`, `packages/game_core/lib/game_core.dart`, `packages/game_core/lib/src/num/big_num.dart`, `packages/game_core/lib/src/num/format.dart`
- Test: `packages/game_core/test/num/big_num_test.dart`, `packages/game_core/test/num/format_test.dart`

**Interfaces:**
- Produces: `final class BigNum implements Comparable<BigNum>` with `const BigNum.zero()`, `BigNum.from(num v)`, `BigNum.parse(String s)`, getters `double mantissa` (0 or in `[1,10)`, signed), `int exponent`, `bool isZero`, `bool isNegative`; operators `+ - * /`, unary `-`, `< <= > >=`, `==`/`hashCode` (value equality after normalization); methods `BigNum mulDouble(double f)`, `BigNum powInt(int n)` (n ≥ 0), `BigNum min(BigNum o)`, `BigNum max(BigNum o)`, `double toDouble()` (returns `double.infinity` when exponent > 308), `String toJson()` (format `"<mantissa>e<exponent>"`, e.g. `"1.5e3"`, zero is `"0"`), `static BigNum fromJson(String)`. Also `formatNumber(BigNum v) -> String`.

- [ ] **Step 1: Scaffold the workspace.** Root `pubspec.yaml`: `name: space_idle_workspace`, `publish_to: none`, `environment: sdk: ^3.8.0`, `workspace: [packages/game_core]` (Task 9 adds game_sim). `packages/game_core/pubspec.yaml`: `name: game_core`, `resolution: workspace`, dev_dependencies `test`, `lints`. Run `dart pub get` at the root. Expected: "Got dependencies".

- [ ] **Step 2: Write failing tests**

```dart
// big_num_test.dart
test('normalizes', () { final b = BigNum.from(12345); expect(b.mantissa, closeTo(1.2345, 1e-12)); expect(b.exponent, 4); });
test('adds across exponents', () => expect((BigNum.parse('1e30') + BigNum.from(1)).toJson(), '1e30'));
test('adds similar', () => expect((BigNum.from(950) + BigNum.from(50)), BigNum.from(1000)));
test('subtract to zero', () => expect((BigNum.from(5) - BigNum.from(5)).isZero, isTrue));
test('multiply beyond double', () { final b = BigNum.parse('1e300') * BigNum.parse('1e300'); expect(b.exponent, 600); expect(b.toDouble(), double.infinity); });
test('divide', () => expect(BigNum.from(1) / BigNum.from(4), BigNum.from(0.25)));
test('powInt', () => expect(BigNum.from(1.15).powInt(100).toDouble(), closeTo(1174313.45, 1)));
test('compare', () { expect(BigNum.parse('1e40') > BigNum.parse('9e39'), isTrue); expect(BigNum.from(-1) < BigNum.zero(), isTrue); });
test('json round trip', () { for (final s in ['0', '1.5e3', '-2.25e-4', '7e1000']) { expect(BigNum.fromJson(BigNum.fromJson(s).toJson()), BigNum.fromJson(s)); } });
// format_test.dart
const cases = {0: '0', 3: '3', 3.14159: '3.14', 12.34: '12.3', 999: '999', 999.5: '1K', 1000: '1K', 1240: '1.24K', 12400: '12.4K', 124000: '124K', 999999: '1M', 2.41e6: '2.41M', 1e33: '1Dc', -1500: '-1.5K'};
test('formats', () { cases.forEach((v, s) => expect(formatNumber(BigNum.from(v)), s, reason: '$v')); });
test('scientific after Dc', () => expect(formatNumber(BigNum.parse('1.24e36')), '1.24e36'));
```

- [ ] **Step 3: Run tests to verify they fail.** Run: `cd packages/game_core && dart test test/num`. Expected: compile errors (BigNum undefined).

- [ ] **Step 4: Implement `BigNum` and `formatNumber`.** Store a normalized `double mantissa` and `int exponent`. Addition aligns to the larger exponent; if the exponent gap > 17, return the larger operand. `==` compares normalized mantissa (rounded to 12 significant digits) and exponent so `950+50 == 1000` holds. Formatting rules: |v| < 1000 → fixed decimals (2 if <10, 1 if <100, 0 otherwise), trailing zeros and dot trimmed; if rounding reaches 1000, carry into the next suffix. Suffixes in order `K M B T Qa Qi Sx Sp Oc No Dc` for 1e3…1e33 with 3 significant digits, trailing zeros trimmed, carry on rounding (999999 → "1M"). |v| ≥ 1e36 → `"<m with 2 decimals trimmed>e<exp>"`. Negatives get a leading `-`.

- [ ] **Step 5: Run tests.** `dart test test/num` → all pass. `dart analyze` → no issues.

- [ ] **Step 6: Commit** `feat(core): workspace scaffold, BigNum, number formatting`.

---

### Task 2: Seeded RNG (web-safe)

**Files:**
- Create: `packages/game_core/lib/src/rng.dart`
- Test: `packages/game_core/test/rng_test.dart`

**Interfaces:**
- Produces: `final class Rng { Rng(int seed); Rng.fromState(int state); int get state; int nextUint32(); double nextDouble(); /* [0,1) */ int nextInt(int maxExclusive); }`. `state` is a non-negative int < 2^32 and fully captures the generator.

- [ ] **Step 1: Write failing tests**

```dart
test('golden vector', () { final r = Rng(42); expect([for (var i = 0; i < 5; i++) r.nextUint32()], goldenSeed42); });
test('state round trip', () { final a = Rng(7)..nextUint32(); final b = Rng.fromState(a.state); expect(b.nextUint32(), a.nextUint32()); });
test('nextInt bounds', () { final r = Rng(1); for (var i = 0; i < 1000; i++) { final v = r.nextInt(6); expect(v, inInclusiveRange(0, 5)); } });
test('nextDouble range', () { final r = Rng(3); for (var i = 0; i < 1000; i++) { expect(r.nextDouble(), allOf(greaterThanOrEqualTo(0), lessThan(1))); } });
```

`goldenSeed42` is produced by running the implementation once on the VM, pasting the 5 values into the test, then confirming the same values on JS (Step 4).

- [ ] **Step 2: Run to verify failure.** `dart test test/rng_test.dart` → compile error.

- [ ] **Step 3: Implement Mulberry32** using only operations exact on both VM and JS: keep the state masked to 32 bits (`& 0xFFFFFFFF`), and implement 32-bit multiply as a `_imul(a, b)` helper that splits into 16-bit halves (`((ah * bl + al * bh) << 16) + al * bl` masked) so no intermediate exceeds 2^53. `nextDouble = nextUint32() / 4294967296`. `nextInt(n) = (nextDouble() * n).floor()`.

- [ ] **Step 4: Verify on VM and JS.** `dart test test/rng_test.dart` and `dart test -p node test/rng_test.dart` both pass with the same golden values. (Node is installed at `/opt/node22/bin`. If `-p node` cannot run in this environment, record that in the commit message and keep the VM test.)

- [ ] **Step 5: Commit** `feat(core): web-safe seeded Rng with golden vector`.

---

### Task 3: Content model, loader, validator, and stage-1 content

**Files:**
- Create: `packages/game_core/lib/src/content/content.dart`, `packages/game_core/lib/src/content/content_loader.dart`, `content/rules.json`, `content/resources.json`, `content/buildings.json`, `content/body_types.json`, `content/galaxy.json`, `content/milestones.json`
- Test: `packages/game_core/test/content/content_loader_test.dart`, `packages/game_core/test/content/shipped_content_test.dart`

**Interfaces:**
- Consumes: `BigNum` (Task 1).
- Produces (all immutable, ids are `String`, lists keep JSON order):
  - `ResourceDef { id, name, int tier /*0 raw..4 megaproject*/, BigNum basePrice, double marketDepth /*default 10000*/ }`
  - `enum BuildingKind { extractor, factory, habitat, warehouse }`
  - `BuildingDef { id, name, kind, double cycleSeconds, Map<String,double> inputs /*per cycle*/, Map<String,double> outputs /*per cycle; extractor: output keyed by deposit resource, multiplied by richness*/, List<String> extracts /*extractor only: resource ids it may mine*/, int crewSlots, int housing /*habitat only*/, double storageBonus /*warehouse: added per-resource cap*/, Map<String,BigNum> buildCost /*'credits' or resource id*/, Map<UpgradeTrack, UpgradeCostDef> upgrades }`
  - `enum UpgradeTrack { speed, efficiency, capacity }`; `UpgradeCostDef { BigNum baseCredits, double growth }`
  - `BodyTypeDef { id, name, List<String> depositPool, int buildSlots }`
  - `RulesDef { double speedPerLevel /*1.1*/, int speedMilestoneEvery /*25*/, double speedMilestoneMult /*2*/, double efficiencyPerLevel /*0.95*/, double efficiencyFloor /*0.25*/, int capacityCrewPerLevel /*1*/, double capacityStoragePerLevel /*0.2*/, double baseStorageCap /*1000*/, double offlineCapSeconds /*43200*/, double marketFloor /*0.2*/, double marketRecoverySeconds /*3600*/, BigNum claimBaseCredits, double claimGrowth, String outpostKitResource, double shipCapacityPerSecond, String cargoShipResource, double baseTravelSeconds /*same system*/ }`
  - `GalaxyDef { List<SystemDef> systems; List<StartingFactionDef> factions; }`, `SystemDef { id, name, List<BodyDef> bodies }`, `BodyDef { id, name, typeId, int orbit, List<DepositDef> deposits }`, `DepositDef { resourceId, double richness }`, `StartingFactionDef { id, name, bool isPlayer, String homeBodyId, BigNum credits, int baseCrew, List<StartingBuildingDef> buildings, Map<String,BigNum> stock }`, `StartingBuildingDef { defId, String? depositResourceId, int crew }`
  - `MilestoneDef { id, name, MilestoneCondition condition }` where condition is one of `{ "type": "stock", "resource", "amount" }`, `{ "type": "credits", "amount" }`, `{ "type": "bodiesOwned", "count" }`, `{ "type": "buildingCount", "defId", "count" }`.
  - `final class Content { RulesDef rules; Map<String,ResourceDef> resources; Map<String,BuildingDef> buildings; Map<String,BodyTypeDef> bodyTypes; GalaxyDef galaxy; List<MilestoneDef> milestones; static ContentResult fromBundle(Map<String, Object?> bundle); }` where `bundle` keys are the file stems (`rules`, `resources`, ...) and values are decoded JSON.
  - `sealed class ContentResult` → `ContentOk(Content)` | `ContentInvalid(List<String> errors)`.

- [ ] **Step 1: Write failing loader tests** using small inline bundles:
  - `valid minimal bundle loads` → `ContentOk`.
  - `unknown recipe input is reported` → errors contain `"buildings.smelter.inputs: unknown resource 'unobtainium'"`.
  - `resource with no producer is reported` → errors contain `"resources.x: nothing produces it"` (a resource is produced if an extractor lists it in `extracts` and some body has that deposit, or a building outputs it).
  - `unreachable deposit type` → body references unknown `typeId` → error.
  - `missing required field gives error not throw` → `resources` entry without `name` → `ContentInvalid`, no exception.
  - `deposit not in body type pool` → error.

- [ ] **Step 2: Run** `dart test test/content` → fails.

- [ ] **Step 3: Implement the defs and `Content.fromBundle`.** Parse defensively (type-check every field, collect all errors with a `path` prefix, never throw). Validation rules: all referenced ids exist; every resource is produced somewhere; every non-megaproject resource is consumed by some recipe or has `basePrice > 0` (sellable); deposits belong to the body type's pool; each starting faction's home body exists; milestone references exist.

- [ ] **Step 4: Write the stage-1 content files.** Requirements:
  - About 22 resources. Tier 0 raw (10): iron ore, copper ore, silicon, water ice, nickel, ammonia, hydrogen, helium-3, sulfur, rare earths. Tier 1 refined (about 7): steel, copper wire, silicon wafer, water, oxygen, fuel, fertilizer, food. Tier 2 components (about 5): circuit, hull plate, magnet, habitat module, cargo ship, outpost kit. Tune the exact list to the rules below.
  - At least one multi-output recipe (electrolysis: water → oxygen + hydrogen).
  - Habitat building consumes food + water + oxygen and provides `housing`.
  - `outpost kit` needs ingredients from at least 2 different bodies (e.g. hull plates from belt nickel + fuel from gas-giant hydrogen + circuits from the home world).
  - One home system with 5 bodies: home rocky world "Kora" (iron, copper, silicon), asteroid belt "Hollow Reach" (nickel, iron, water ice), ice moon "Brine" (water ice, ammonia), gas giant "Vastmere" (hydrogen, helium-3), volcanic "Cinder" (sulfur, rare earths). Only Kora is owned at start.
  - The player faction starts with credits, base crew 10, and an iron extractor + copper extractor + a smelter on Kora, so the first minutes have something to do.
  - Body types for asteroid, rocky, ice moon, gas giant, volcanic, with pools as in spec §6.1 (pools may list resources not yet in stage-1 content only if those resources exist, so keep pools to existing ids).
  - Milestones (about 8): first steel 100, credits 10K, credits 1M, own 2 bodies, own 4 bodies, first circuit 100, first habitat module, credits 1B.
  - `rules.json` uses the defaults shown in the `RulesDef` comments, plus `claimBaseCredits: "5e3"`, `claimGrowth: 4`, `shipCapacityPerSecond: 2`, `baseTravelSeconds: 120`.

- [ ] **Step 5: Shipped-content test.** `shipped_content_test.dart` reads `../../content/*.json` via `dart:io` (allowed in tests only), builds the bundle, and expects `ContentOk`. Also asserts the outpost-kit multi-body rule by walking the recipe graph back to raw resources and checking those raws come from deposits on ≥ 2 distinct bodies.

- [ ] **Step 6: Run** `dart test` → all pass. `dart analyze` clean.

- [ ] **Step 7: Commit** `feat(core): data-driven content model, validator, stage-1 content`.

---

### Task 4: Game state, new game, save codec

**Files:**
- Create: `packages/game_core/lib/src/state/game_state.dart`, `packages/game_core/lib/src/state/save_codec.dart`
- Test: `packages/game_core/test/state/game_state_test.dart`, `packages/game_core/test/state/save_codec_test.dart`

**Interfaces:**
- Consumes: `BigNum`, `Rng`, `Content` and defs.
- Produces (mutable classes, all with `Map<String,Object?> toJson()` and `fromJson`):
  - `GameState { int saveVersion /*=1*/; double time /*game seconds*/; int rngState; List<FactionState> factions; List<BodyState> bodies; List<RouteState> routes; List<Shipment> shipments; MarketState market; int nextId; String newId(String prefix) /*"$prefix${nextId++}"*/; FactionState faction(String id); BodyState body(String id); }`
  - `FactionState { id, name, bool isPlayer, BigNum credits, int baseCrew, List<AutoSellRule> autoSell, Set<String> reachedMilestones /*serialized sorted*/ }`
  - `BodyState { id, name, systemId, typeId, int orbit, List<DepositDef> deposits, String? ownerId, Map<String,BigNum> stock, List<BuildingState> buildings }`
  - `BuildingState { id, defId, String? depositResourceId, int crew, Map<UpgradeTrack,int> levels, /* transient, not serialized: */ double lastRunFraction, String? lastLimitReason }`
  - `RouteState { id, ownerId, fromBodyId, toBodyId, resourceId, BigNum ratePerSecond, int cargoShips }`
  - `Shipment { routeId, toBodyId, resourceId, BigNum amount, double arriveAt }`
  - `MarketState { Map<String,double> saturation /*resource id → [floor,1], default 1*/ }`
  - `AutoSellRule { bodyId, resourceId, BigNum keepAtLeast }`
  - `GameState newGameState(Content content, int seed)`: builds bodies from galaxy, factions from starting defs, assigns home bodies, creates starting buildings and stock.
  - `final class SaveCodec { static String encode(GameState s); static SaveResult decode(String text, Content content); }` with `SaveResult` = `SaveOk(GameState)` | `SaveError(SaveErrorKind kind, String message)`, `enum SaveErrorKind { notJson, unknownVersion, missingField, unknownContentId }`. Migrations: `const Map<int, Map<String,Object?> Function(Map<String,Object?>)> migrations` keyed by *from* version. v1 is current and has none. The test registers a fake v0→v1 via an overridable parameter.

- [ ] **Step 1: Write failing tests**
  - `new game owns only home body`: the player owns Kora, every other body's `ownerId == null`.
  - `new game has starting buildings and crew` matching `galaxy.json`.
  - `json round trip is identical`: `jsonEncode(fromJson(toJson(s)).toJson()) == jsonEncode(s.toJson())`.
  - `decode rejects garbage` → `SaveError(notJson)`; `{"saveVersion": 99}` → `unknownVersion`; a body with `typeId: "nope"` → `unknownContentId`; missing `bodies` → `missingField`.
  - `migration runs`: decode with `migrations: {0: (m) => {...m, 'saveVersion': 1, 'time': m['clock']}}` on a v0 map → `SaveOk` with `time` copied.
  - `newId is deterministic`: two new games with the same seed produce identical JSON.

- [ ] **Step 2: Run** → fails. **Step 3: Implement.** **Step 4: Run** `dart test` → pass.

- [ ] **Step 5: Commit** `feat(core): game state, new game setup, versioned save codec`.

---

### Task 5: Commands and validation

**Files:**
- Create: `packages/game_core/lib/src/commands/command.dart`, `packages/game_core/lib/src/commands/apply.dart`
- Test: `packages/game_core/test/commands/apply_test.dart`

**Interfaces:**
- Consumes: `GameState`, `Content`, `BigNum`.
- Produces:
  - `sealed class Command { String get factionId; Map<String,Object?> toJson(); static Command fromJson(Map<String,Object?> j); }` with `"cmd"` discriminator. Subclasses and JSON names:
    - `BuildCommand(factionId, bodyId, defId, {depositResourceId})` `"build"`
    - `DemolishCommand(factionId, buildingId)` `"demolish"` (refund 50% of credits build cost)
    - `AssignCrewCommand(factionId, buildingId, int crew)` `"assignCrew"` (absolute target count)
    - `UpgradeCommand(factionId, buildingId, UpgradeTrack track)` `"upgrade"`
    - `CreateRouteCommand(factionId, fromBodyId, toBodyId, resourceId, BigNum ratePerSecond, int cargoShips)` `"createRoute"` (consumes `cargoShips` × `cargo ship` resource from the from-body stock)
    - `RemoveRouteCommand(factionId, routeId)` `"removeRoute"` (returns ships to the from-body stock)
    - `SellCommand(factionId, bodyId, resourceId, BigNum amount)` `"sell"`
    - `SetAutoSellCommand(factionId, bodyId, resourceId, BigNum? keepAtLeast)` `"setAutoSell"` (null removes the rule)
    - `ClaimBodyCommand(factionId, bodyId, sourceBodyId)` `"claimBody"`
  - `sealed class CommandResult` → `CommandOk({String? createdId})` | `CommandFailed(CommandError error, String message)`.
  - `enum CommandError { unknownFaction, unknownBody, unknownBuilding, unknownDef, notOwner, noBuildSlot, depositMissing, cannotAfford, crewUnavailable, crewSlotsExceeded, invalidAmount, alreadyOwned, routeInvalid }`
  - `CommandResult applyCommand(GameState s, Content c, Command cmd)`
  - Helper used by UI/bots later: `Map<String,BigNum> upgradeCost(Content c, BuildingState b, UpgradeTrack t)` and `Map<String,BigNum> claimCost(GameState s, Content c, String factionId)`. Claim cost: credits = `claimBaseCredits × claimGrowth^(ownedCount-1)`; outpost kits = `ownedCount - 1` (so the first claim is credits only), taken from `sourceBodyId` stock, which must be owned by the faction.
  - Crew availability: `int availableCrew(GameState s, Content c, String factionId)` = `baseCrew + Σ habitat housing × habitat lastRunFraction (rounded down) − Σ assigned crew`. For validation, a new assignment needs `availableCrew ≥ delta`. Slots: `crewSlots + capacityCrewPerLevel × capacityLevel`.
  - Upgrade cost credits = `baseCredits × growth^level`.

- [ ] **Step 1: Write failing tests**, one per command for the happy path, plus:
  - `build fails without free slot` → `noBuildSlot`.
  - `extractor needs matching deposit` → `depositMissing`.
  - `cannot act on another faction's body`: add a second faction owning Brine; build on Brine as the player → `notOwner`; upgrade their building → `notOwner`.
  - `failed command leaves state unchanged`: `jsonEncode` before == after for every failure case above.
  - `crew over slots` → `crewSlotsExceeded`; `crew over pool` → `crewUnavailable`.
  - `claim first body costs credits only; second needs 1 outpost kit`.
  - `command json round trip` for every subclass.

- [ ] **Step 2: Run** → fails. **Step 3: Implement** (validate fully before mutating anything). **Step 4: Run** → pass.

- [ ] **Step 5: Commit** `feat(core): validated commands`.

---

### Task 6: Production, crew, and storage step

**Files:**
- Create: `packages/game_core/lib/src/sim/production.dart`, `packages/game_core/lib/src/sim/crew.dart`
- Test: `packages/game_core/test/sim/production_test.dart`

**Interfaces:**
- Consumes: state, content, `availableCrew` rules from Task 5.
- Produces: `void stepProduction(GameState s, Content c, double dt)`, `double speedMultiplier(RulesDef r, int level)` = `speedPerLevel^level × speedMilestoneMult^(level ~/ speedMilestoneEvery)`, `double efficiencyMultiplier(RulesDef r, int level)` = `max(efficiencyFloor, efficiencyPerLevel^level)`, `BigNum storageCap(GameState s, Content c, BodyState b)` = `baseStorageCap × (1 + Σ warehouse storageBonus) ` plus per-building capacity upgrades `(1 + capacityStoragePerLevel × capacityLevel)` folded multiplicatively (a body-wide cap applied per resource), `double crewEfficiency(GameState s, Content c, String factionId)` = `min(1, supportedCrew / assignedCrew)` (1 when nothing is assigned).

Algorithm per step (bodies in list order, buildings in list order):
1. For each building: `crewFrac = crew / slots × crewEfficiency(owner)`. Potential cycles this step `p = dt / cycleSeconds × speedMult × crewFrac`. For extractors, output = `outputs[deposit] × richness × p`; they have no inputs.
2. Input demand for building = `inputs × efficiencyMult × p`. Sum demand per resource per body. `satisfaction[r] = min(1, stock[r] / demand[r])`.
3. Building run fraction `f = min over its inputs of satisfaction` (1 if no inputs). Record `lastRunFraction = f` and `lastLimitReason`: `"noCrew"` if crew = 0, else `"input:<resId>"` for the limiting input if `f < 1`, else null.
4. Subtract consumed inputs (`demand × f`), then add outputs (`outputs × p × f`), clamping each stock to the storage cap. Track clamped overflow into a transient `Map<String,BigNum> wastedThisStep` on the body (not serialized).
5. Habitats run like factories. Their `lastRunFraction` feeds next step's supported crew (`housing × f`).

- [ ] **Step 1: Write failing tests** with small inline content:
  - `extractor produces rate × dt`: richness 1.5, output 2 per 10 s cycle, 2/2 crew, dt 10 → +3 ore.
  - `factory limited by input`: smelter needs 4 ore per cycle, 2 ore in stock → runs at 0.5, produces half, ore → 0, `lastLimitReason == 'input:iron_ore'`.
  - `two consumers share proportionally`.
  - `no stock goes negative` (invariant): random small content + random commands for 500 steps with seeded `Rng`. After every step, every stock ≥ 0.
  - `storage cap clamps and records waste`.
  - `speed milestone`: `speedMultiplier(rules, 25) == 1.1^25 × 2`.
  - `efficiency reduces inputs, floor respected`.
  - `crew efficiency drops when habitats starve`: base crew 2, habitat housing 10, 8 crew assigned. With life support present → 1.0. With food removed, after one step → `0.25`.
  - `zero crew produces nothing`.

- [ ] **Step 2: Run** → fails. **Step 3: Implement.** **Step 4: Run** → pass.

- [ ] **Step 5: Commit** `feat(core): production step with crew, efficiency, storage`.

---

### Task 7: Logistics and market

**Files:**
- Create: `packages/game_core/lib/src/sim/logistics.dart`, `packages/game_core/lib/src/sim/market.dart`
- Test: `packages/game_core/test/sim/logistics_test.dart`, `packages/game_core/test/sim/market_test.dart`

**Interfaces:**
- Produces: `void stepLogistics(GameState s, Content c, double dt)`, `double travelSeconds(GameState s, Content c, BodyState a, BodyState b)` = `baseTravelSeconds × (1 + |a.orbit − b.orbit|)` (same system only in stage 1; route across systems → `routeInvalid` in Task 5 validation), `BigNum routeCapacity(Content c, RouteState r)` = `cargoShips × shipCapacityPerSecond` per second, `SaleResult sell(GameState s, Content c, String factionId, String bodyId, String resourceId, BigNum amount)` returning `{BigNum sold, BigNum revenue}`, `void stepMarket(GameState s, Content c, double dt)` (recovery + auto-sell), `double price(GameState s, Content c, String resourceId)` = `basePrice × saturation`.
- Market rules: revenue = `amount × basePrice × saturationBefore`; then `saturation = max(marketFloor, saturation − amount/marketDepth)`; recovery per step `saturation = min(1, saturation + dt / marketRecoverySeconds)`. Auto-sell each step sells `stock − keepAtLeast` if positive.
- Logistics rules: each step, each route moves `min(rate, capacity) × dt`, limited by source stock, into a new `Shipment` arriving at `time + travelSeconds`. Shipments whose `arriveAt ≤ time` are delivered (clamped to the destination cap, overflow wasted) in creation order. If the destination body is no longer owned by the route owner, the shipment returns its goods to the source on arrival instead (simple, deterministic).
- `SellCommand` and `SetAutoSellCommand` in `apply.dart` call into `market.dart`.

- [ ] **Step 1: Write failing tests**
  - `route moves goods after travel time`: rate 1/s, 2 ships (cap 4/s), travel 240 s. After 10 s, 10 units in transit and 0 delivered. After 250 s, 10 delivered.
  - `route limited by capacity`: rate 10/s with 1 ship (2/s) → moves 2/s.
  - `route limited by source stock`.
  - `in-transit goods survive save round trip`.
  - `selling lowers price and recovers`: basePrice 10, depth 100; sell 50 → revenue 500, saturation 0.5; after 1800 s → 1.0.
  - `price floor`.
  - `auto-sell keeps minimum`.

- [ ] **Step 2: Run** → fails. **Step 3: Implement.** **Step 4: Run** → pass.

- [ ] **Step 5: Commit** `feat(core): cargo routes, shipments, market and auto-sell`.

---

### Task 8: Engine, fast-forward, offline catch-up, flow report

**Files:**
- Create: `packages/game_core/lib/src/sim/engine.dart`, `packages/game_core/lib/src/report/flow_report.dart`
- Modify: `packages/game_core/lib/game_core.dart` (export public API)
- Test: `packages/game_core/test/sim/engine_test.dart`, `packages/game_core/test/report/flow_report_test.dart`

**Interfaces:**
- Produces:
  - `final class GameEngine { GameEngine(this.content); final Content content; GameState newGame(int seed); CommandResult apply(GameState s, Command cmd); void tick(GameState s, double dt); void advance(GameState s, double seconds, {double maxStep = 60}); OfflineSummary catchUpOffline(GameState s, double secondsAway, {double? capSeconds}); }`
  - `tick` order: `stepProduction` → `stepLogistics` → `stepMarket` → milestone check (adds to `reachedMilestones`) → `time += dt`.
  - `advance` splits into steps of at most `maxStep`, the last step taking the remainder.
  - `OfflineSummary { double secondsSimulated; double secondsAway; Map<String,BigNum> stockGained /*empire-wide, player faction*/; BigNum creditsGained; List<String> milestonesReached; List<Bottleneck> topBottlenecks /*max 3*/ }`. Cap defaults to `rules.offlineCapSeconds`.
  - `FlowReport buildFlowReport(GameState s, Content c, String factionId)` → `FlowReport { List<BodyFlow> bodies; Map<String,BigNum> empireNet /*per second*/; List<Bottleneck> bottlenecks }`, `BodyFlow { bodyId, Map<String,BigNum> producedPerSec, Map<String,BigNum> consumedPerSec, Map<String,BigNum> netPerSec, Map<String,BigNum> wastedPerSec, List<BuildingStatus> buildings }`, `BuildingStatus { buildingId, defId, double runFraction, String? limitReason, int crew, int slots }`, `Bottleneck { bodyId, buildingId, String resourceId, double runFraction, String message /*plain English, e.g. "Smelter on Kora is running at 50%: not enough Iron Ore"*/ }`. Bottlenecks are sorted by lowest run fraction, then body/building order. The rates come from a dry-run step of 1 s on a deep copy (so the report never mutates state).

- [ ] **Step 1: Write failing tests**
  - `determinism`: two engines, same seed, same 50 scripted commands interleaved with `advance(…, 3600)` → identical `jsonEncode(toJson())`.
  - `step invariance`: `advance(s, 3600, maxStep: 1)` vs `maxStep: 60` → player credits and every stock within 2% relative of each other for the starting setup.
  - `offline cap`: `catchUpOffline(s, 100000)` simulates exactly 43200 s.
  - `performance`: `catchUpOffline(s, 86400, capSeconds: 86400)` on shipped content with every body owned and 40 buildings completes in < 1000 ms on the VM (use `Stopwatch`).
  - `30-day jump`: `advance(s, 30 * 86400)` finishes, stocks finite, no negative stock.
  - `flow report does not mutate state`, `bottleneck message names the building, body, and resource`.

- [ ] **Step 2: Run** → fails. **Step 3: Implement.** **Step 4: Run** `dart test` (whole package) → pass.

- [ ] **Step 5: Commit** `feat(core): engine, fast-forward, offline catch-up, flow report`.

---

### Task 9: game_sim CLI and script runner

**Files:**
- Create: `packages/game_sim/pubspec.yaml`, `packages/game_sim/bin/game_sim.dart`, `packages/game_sim/lib/src/content_files.dart`, `packages/game_sim/lib/src/script_runner.dart`
- Modify: root `pubspec.yaml` (add `packages/game_sim` to workspace)
- Test: `packages/game_sim/test/script_runner_test.dart`

**Interfaces:**
- Consumes: the whole `game_core` public API.
- Produces:
  - `Map<String,Object?> loadContentDir(String path)` reads every `*.json` into a bundle keyed by file stem.
  - `final class ScriptRunner { ScriptRunner(GameEngine engine, GameState state); Map<String,Object?> handle(Map<String,Object?> line); }`. Each line is a game command (same JSON as `Command.toJson`, with `factionId` defaulting to the player) or a meta command: `{"cmd":"advance","seconds":N}`, `{"cmd":"report"}` (flow report JSON with formatted numbers plus raw values), `{"cmd":"state"}` (summary: time, credits, owned bodies, stock per body), `{"cmd":"save","path":...}`, `{"cmd":"load","path":...}`, `{"cmd":"costs"}` (upgrade and claim costs for every player building). It returns `{"ok":true,...}` or `{"ok":false,"error":"...","message":"..."}`.
  - CLI: `dart run game_sim:game_sim [--content content] [--seed 1] [--load save.json] [--script file.jsonl]`. Reads JSON lines from `--script` or stdin and writes one JSON line per input line to stdout. `dart run game_sim:game_sim check --content content` validates content and prints errors (exit 1 on invalid).

- [ ] **Step 1: Write failing tests**: `advance then state shows more credits/stock`, `invalid command returns ok:false with error name`, `unknown cmd returns ok:false error 'unknownCommand'`, `save then load round trip` (temp dir), `malformed JSON line returns ok:false error 'badJson' and the runner continues`.
- [ ] **Step 2: Run** → fails. **Step 3: Implement.** **Step 4: Run** → pass. Also run manually: `echo '{"cmd":"advance","seconds":600}\n{"cmd":"report"}' | dart run game_sim:game_sim --content content` prints two JSON lines.
- [ ] **Step 5: Commit** `feat(sim): headless CLI with JSON-lines script runner`.

---

### Task 10: Bots, balance report, playtesting guide, CI

**Files:**
- Create: `packages/game_sim/lib/src/bots/bot.dart`, `packages/game_sim/lib/src/balance_report.dart`, `docs/playtesting.md`, `.github/workflows/ci.yml`
- Modify: `packages/game_sim/bin/game_sim.dart` (add `bot` subcommand)
- Test: `packages/game_sim/test/bot_test.dart`, `packages/game_sim/test/balance_report_test.dart`

**Interfaces:**
- Produces:
  - `abstract interface class Bot { String get name; List<Command> decide(GameEngine e, GameState s, String factionId); }` (the same shape as the future `FactionController` in spec §5.1). `GreedyBot`: buys the cheapest affordable upgrade or build each decision. `BalancedBot`: fixes the worst bottleneck first (assign crew → efficiency/speed upgrade on the starving supplier → build another supplier → route), then claims bodies when affordable, then auto-sells surplus.
  - `BalanceReport runBotSession(GameEngine e, Bot bot, {required int seed, required double hours, double checkInEverySeconds = 21600 /* 4×/day per spec §6.7 */, double activeSecondsPerCheckIn = 180})`. The bot acts during each check-in (deciding every 10 s of game time for `activeSecondsPerCheckIn`), then the engine `catchUpOffline`s to the next check-in.
  - `BalanceReport { List<MilestoneHit> milestones /*id, gameHours, checkInIndex*/; List<DeadZone> deadZones /*check-ins where the bot found nothing to do*/; List<String> unusedResources /*never produced or never consumed/sold*/; Map<String,String> finalStock /*formatted*/; String finalCredits; List<String> bottleneckLog }` with `toJson()` and `toMarkdown()`.
  - CLI: `dart run game_sim:game_sim bot --bot balanced --hours 168 --seed 1 [--format md|json]`.
- `docs/playtesting.md`: how a subagent playtester runs the sim (commands, meta commands, bot runs), the personas from spec §5.2 (optimizer, casual 4×/day, warmonger, noting war arrives in stage 4), and the report template: what was fun/boring, stuck points with game time, numbers that felt off, bugs with exact command lines to reproduce.
- CI: on push/PR, checkout, install Dart stable (`dart-lang/setup-dart@v1`), `dart pub get`, `dart analyze --fatal-infos`, `dart test` in each package.

- [ ] **Step 1: Write failing tests**: `greedy bot makes progress in 24h` (credits grow, ≥ 1 milestone), `balanced bot reaches 'own 2 bodies' within 72h` (balance target; if content can't meet it, tune `content/*.json`, not the test), `report lists dead zones`, `markdown report contains milestone table`.
- [ ] **Step 2: Run** → fails. **Step 3: Implement.** **Step 4: Run** all tests in both packages → pass. Run `dart run game_sim:game_sim bot --bot balanced --hours 168 --format md` and save the output to `docs/balance/stage1-baseline.md`.
- [ ] **Step 5: Commit** `feat(sim): bots, balance reports, playtest guide, CI`.

---

## After the plan (controller tasks, not implementer tasks)

- Run 2–3 subagent playtests (personas: optimizer, casual) using `docs/playtesting.md`. Collect findings and tune `content/*.json` or fix bugs.
- Push the branch, open a PR to `main`, and let CI run.
