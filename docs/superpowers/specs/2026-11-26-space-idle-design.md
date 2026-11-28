# Space Idle Game — Design

*Working title: "Space Idle" (final name TBD). Date: 2026-11-26.*

Legend: **[Owner]** = decided by the project owner. **[Claude's call]** = proposed by Claude, not yet
explicitly confirmed by the owner. The owner can override any [Claude's call]. Anything not marked is a
direct consequence of an [Owner] decision.

---

## 1. Intent and why

An idle / incremental management game set in space, for Android and the web first and iOS later. The
owner enjoys idle games in the style of Victorina Idle. The genre and mechanics are the reference;
nothing (name, art, text, specific content) is copied from it.

The three pleasures the game must deliver **[Owner]**:

1. **Numbers getting bigger.** Visible, satisfying growth that keeps going.
2. **Slow building.** An empire that grows outward over days and weeks.
3. **Production-line management and optimization.** Upgrading buildings, assigning workers, and
   balancing input/output ratios across chains.

On top of that, **[Owner]** wants factions, diplomacy, and the option of war (attacking and defending
planets).

**Success [Owner]:** the game is published on the Google Play Store. Making money is not a goal.

The owner steers design and playtests. Claude does all the building **[Owner]**.

## 2. Goals, non-goals, anti-goals

### Goals
- A deep, complex production economy: many raw resources, multi-tier refining, and planets that each
  have only some resources **[Owner]**.
- Computer-controlled factions with diplomacy and war, all in the first release **[Owner]**.
- Architecture that allows real players later **[Owner]**, in **both** forms **[Owner]**: small
  private worlds (a few friends in one galaxy) and large shared galaxies with many players. v1 ships
  single-player only, but the engine must be ready to run behind a server (see §5.4).
- **War is optional [Owner].** A peaceful player can reach every planet, resource, and item without
  ever fighting, through colonizing, trade, and diplomacy.
- **No forced ending [Owner].** The game never ends. Big milestones give a "victory" moment and play
  continues (§6.6).
- **Short check-ins [Owner]:** the owner plays idle games in a few short check-ins a day. The design
  target is that a 2–5 minute session is always worthwhile (§6.7).
- Runs on Android and in a web browser from one codebase; iOS buildable later **[Owner]**.
- A headless game engine that AI subagents can drive to playtest and balance the game **[Owner]**
  (they asked for subagent playtesting; the headless engine is how that works).
- Ready for the Play Store: stable, polished, compliant.

### Non-goals (v1)
- Monetization: no ads, no premium currency, nothing to buy that affects play **[Owner]** ("just getting it on the
  Play Store").
  - **Optional donations [Owner, 2026-11-28]:** a "Support the developer" section where players can donate if they
    want to. It is never required, unlocks nothing, gives no gameplay benefit, and is never pushed (no pop-ups,
    reminders or timers). It sits quietly in settings. Implementation notes (stage 6, store prep):
    - On Android, a tip to the developer inside the app goes through Google Play Billing (consumable "tip"
      products, for example three sizes). Linking out to an outside payment page from inside the Play build is
      likely against Play's payments policy; check the current policy before building it.
    - The web build can link to an outside donation page (for example Ko-fi or GitHub Sponsors), which the owner
      chooses.
    - It needs the owner's Play developer account with a payments (merchant) profile, which is an owner action.
    - A thank-you message only. No badge, currency or perk, so there's no pay-to-win and no pressure.
- Online multiplayer, accounts, servers, cloud saves.
- A prestige/reset system **[Owner]**: the empire grows for good.
- iOS release in v1. The code must stay iOS-compatible, but publishing needs a Mac with Xcode (or a
  rented cloud Mac), which is out of scope for now.
- Real-time tactical combat. Battles resolve automatically.

### Anti-goals (failure even if it technically works)
- **Coming back to devastation.** Returning after a night offline to find your empire lost to an AI
  attack you couldn't respond to.
- **A shallow economy.** If the best strategy is "upgrade whatever is cheapest," the optimization
  pleasure is gone. Decisions about crew, ratios, and routes must matter.
- **A spreadsheet with no sense of place.** The star map must make growth visible.
- **Copying a specific existing game's** name, art, characters, text, or exact content.
- **Pay-to-win pressure or dark patterns** (even though there's no monetization, avoid FOMO timers and
  punishing streaks).

## 3. Constraints
- **Tech: Flutter** (Dart) **[Owner]**, one codebase for Android, web, and iOS later.
- **Google Play:** the owner has **no developer account yet [Owner]**, so it will be a new personal
  account ($25 one-time, with identity verification that can take days). New personal accounts must run
  a **closed test with at least 12 opted-in testers for 14 consecutive days** before applying for
  production access. The owner needs to recruit around 12 Android testers; plan at least 2 weeks at the
  end for this.
- **Account timing [Claude's call]:** the owner creates the account during stage 2–3 so verification
  is done well before store prep. The final name and package ID (which can never change once uploaded
  to Play) are settled before the first Play upload. Until then the owner tests via sideloaded APKs and
  the web build.
- Must meet current Play requirements: target API level, Data safety form (the game collects no data),
  content rating questionnaire, privacy policy URL, store listing assets (icon, feature graphic,
  screenshots).
- **Fully offline, single-player.** No backend.
- Web build: Flutter web has a slower first load than a typical website. That's accepted.
- The owner isn't writing code, so all decisions must be explainable in plain language, and the build
  must be reproducible by Claude in future sessions (scripts, docs).

## 4. Approaches considered

| Approach | Trade-off | Outcome |
|---|---|---|
| **Flutter** | Strong at UI-heavy screens (panels, lists, numbers), one codebase for Android/iOS/web, standard Play Store tooling. Slower first web load. | **Chosen [Owner]** |
| Web game (TypeScript) wrapped with Capacitor | Best web load and easiest browser testing; less native feel on phones and dependence on the wrapper. | Rejected |
| Godot engine | Best for heavily animated scenes; clunky for menu-heavy management UIs, and web exports are larger and pickier. Most of this game is management screens. | Rejected |

Factions:

| Option | Trade-off | Outcome |
|---|---|---|
| **Computer-controlled factions** | Works offline, no servers, tunable fairness; AI can feel predictable. | **Chosen [Owner]**, with an architecture that allows real players later |
| Real players | Real rivalries, but needs servers/accounts/anti-cheat and creates offline-raid frustration. | Deferred |

Release scope:

| Option | Outcome |
|---|---|
| **Everything in v1** (production + factions + diplomacy + war) | **Chosen [Owner]** |
| Production + peaceful factions, war in an update | Rejected |
| Production only | Rejected |

Look (from the mockups at https://claude.ai/artifact/MKMcBotPhiq7XVcqNz5wd2):
- **Home screen = Star Map (option B) [Owner].**
- **Tapping a planet opens the Mission Control panel (option A) [Owner].**
- Option C (cozy illustrated) rejected.

## 5. Architecture **[Claude's call]**

Three parts in one repository (a Dart workspace / monorepo):

```
packages/game_core/   Pure Dart. No Flutter imports. All rules, state, content, simulation, AI.
packages/game_sim/    Pure Dart CLI. Drives game_core headlessly for tests and AI playtesting.
app/                  Flutter app (Android, web, iOS later). Renders state, sends commands.
content/              Data files (JSON) for resources, recipes, buildings, planets, factions, ships.
```

### 5.1 Engine principles
- **State + commands + tick.** The whole game is a serializable `GameState`. Every change goes through
  a `Command` (assign crew, upgrade building, create route, propose treaty, launch fleet, ...).
  `tick(state, dt)` advances time. The UI never mutates state directly.
- **Deterministic.** Same starting state, same seed, and same command sequence give identical
  results. All randomness goes through a seeded RNG stored in the state. This makes bugs reproducible,
  playtests replayable, and offline progress consistent.
- **Fixed simulation step** (e.g. 1 s game-time) with fast-forward that batches many steps. Offline
  progress and AI playtesting both use fast-forward. It must handle simulating 24 hours of game time
  in well under a second on a mid-range phone. Where per-second stepping is too slow, the builder may
  use analytic/steady-state stepping for stable production as long as results stay deterministic.
- **Faction slots.** The player and every AI faction are "factions" in the same state, acting through
  the same `Command` interface. A `FactionController` decides commands: `HumanController` (UI input),
  `AiController` (the faction personalities), and later `RemoteController` (multiplayer). AI factions
  play by the same rules as the player; no hidden cheating resources (difficulty tuned via AI
  personality and starting position, not cheats).
- **Data-driven content.** Resources, recipes, buildings, planets, ship classes, and faction
  personalities live in `content/` JSON and are validated at load time (every recipe input exists,
  every resource is producible somewhere, no unreachable items). Balancing means editing data, not
  code.
- **Big numbers.** Growth is a core pleasure, so numbers must not overflow. Use a mantissa/exponent
  number type in `game_core` for quantities and currency, with display formatting (`1.24K`, `3.5M`,
  `8.1e15` after the named suffixes run out; the exact cutoff is the builder's call).

### 5.2 Headless simulator (`game_sim`) for subagent playtesting **[Owner goal, Claude's design]**
- CLI that loads content and a save or new game, accepts commands as JSON lines on stdin (or a script
  file), fast-forwards time, and prints state summaries as JSON.
- Built-in reports: resource flows and bottlenecks, time to reach each milestone, idle "dead zones"
  (stretches with nothing worth doing), unused resources/recipes, faction relations over time, war
  outcomes.
- Scripted strategy bots (greedy, balanced, militarist, trader) for regression balance runs.
- Subagent playtesters are given the CLI plus a persona ("optimizer", "casual who checks in twice a
  day", "warmonger") and report findings in plain language.

### 5.3 Flutter app
- Renders `GameState` read-only and sends `Command`s. Runs the engine tick on a timer while open.
- State management, routing, and persistence libraries are the builder's call (the repo has Flutter
  convention skills available: Riverpod, Drift, and others).
- Save: autosave locally (on interval and on app pause), versioned save format with migrations, plus
  export/import of a save as a text string (a manual backup since there are no cloud saves).

### 5.4 Multiplayer readiness **[Owner: both private and large shared worlds later; approach is Claude's call]**
v1 has no servers, but `game_core` is built so a server can run it as the authority later:
- **Authority abstraction.** Something owns the world clock and the RNG and applies commands. In v1
  that's the phone (single-player). Later it's a Dart server running the same `game_core`.
- **Every command is validated in `game_core`** against the current state (can this faction afford
  it, own it, reach it). The UI's own checks are only for display. A server can then safely accept
  commands from untrusted clients.
- **Two time modes.** Single-player catches up by fast-forwarding on return. A shared world's server
  ticks continuously, and clients only receive state. Offline progress code goes through the authority
  abstraction so both modes work.
- **Per-faction views.** `game_core` can produce the slice of state a given faction may see (for fog
  of war or hidden info later, and to keep network payloads small).
- **Not in v1:** networking, accounts, server hosting, matchmaking, anti-cheat, and the offline-safety
  rules for human-vs-human war. Those are a later design. Note that large shared galaxies will need a
  hosted server with ongoing running costs.

## 6. Economy **[Owner: complex, many resources, planet-specific deposits; details are Claude's call]**

### 6.1 Planets and deposits
Each body has a type and 1–4 deposits from that type's pool. No body has everything. Example pools:

| Body type | Possible raw resources |
|---|---|
| Asteroid belt | Nickel, Iron, Platinum, Water ice |
| Rocky world | Iron, Copper, Silicon, Aluminium |
| Ice moon | Water ice, Ammonia, Methane |
| Gas giant (orbital skimmers) | Hydrogen, Helium-3, Methane |
| Volcanic world | Sulfur, Rare earths, Titanium |
| Ocean world | Water, Deuterium, Biomass |
| Exotic (late) | Void crystals, Dark matter, Antimatter traces |

Deposits have a richness level (affecting base extraction rate). Deposits do not run out in v1
(**[Claude's call]**: depletion would fight the "keeps growing" pleasure).

### 6.2 Product tiers
Five tiers, targeting **40–60 items** in v1. Most recipes need 2–3 inputs, usually from different
planets.

1. **Raw**: as above (about 20).
2. **Refined**: steel, aluminium plate, copper wire, silicon wafers, titanium ingots, fuel cells,
   plastics, coolant, ...
3. **Components**: circuits, hull plates, engines, reactor cores, sensors, habitat modules, ...
4. **Advanced**: AI cores, shield generators, weapon systems, warp drives, terraforming kits, ...
5. **Megaprojects**: orbital stations, colony ships, dreadnoughts, star gates, ...

The full item list and recipe graph is the builder's call, validated by the content checker and
balanced with `game_sim`.

### 6.3 Buildings
- Each building runs one recipe (extractors produce from a deposit with no inputs).
- **Crew [Owner]:** each building has crew slots. Output scales with assigned crew. Crew come from a
  finite pool that grows by building habitats (which consume food/water/air products, another chain).
- **Upgrades [Owner]:** each building has separate upgrade tracks, for example **Speed** (more
  throughput), **Efficiency** (fewer inputs per output), and **Capacity** (storage / crew slots).
  Efficiency changes ratios, so fixing one bottleneck can create another. That's intended.
- **Ratios [Owner]:** every building shows inputs/s and outputs/s. Every resource shows its net flow
  per planet and empire-wide. If inputs are short, a building runs at the fraction it can supply, and
  the UI flags the bottleneck and its cause.
- Storage per planet per resource, with caps; overflow is wasted (shown clearly).

### 6.4 Logistics **[Claude's call, owner said "good for now"]**
- Goods move between planets on **cargo routes** that the player creates (source, destination,
  resource, amount/s).
- Routes have limited capacity from assigned cargo ships (built from components) and a travel time.
  A route can be the bottleneck.
- Routes are drawn on the star map with moving ships.
- In war, enemy fleets can blockade or raid routes.

### 6.5 Currency
- **Credits**: earned by selling goods to a neutral market (prices drift with supply) and through
  faction trade. Spent on upgrades, buildings, and claiming planets.
- Upgrade costs scale exponentially and production multiplies through the tiers, so numbers grow
  large. Exact curves are the builder's call, tuned with `game_sim`.

### 6.6 Progression without prestige **[Owner: no reset; structure is Claude's call]**
- **Regions unlock in stages:** home system (belt, rocky world, moon) → outer system (gas giant,
  ice moons) → neighboring systems via warp drives → distant systems with exotic worlds. Each stage
  adds new resources and deeper chains.
- New planets are claimed by building colony ships/outposts (a production goal), or taken in war.
- **Research [Claude's call]:** a tech tree funded by a research product/points, unlocking recipes,
  building types, and upgrade tracks. It paces the unlocks. The builder may fold this into region
  unlocks if it adds too much scope.
- The galaxy size for v1 (about 6–10 star systems with 4–8 bodies each) is the builder's call,
  enough for weeks of play.
- **Every planet and item is reachable peacefully [Owner: war optional].** Conquest is a faster,
  riskier path to planets that also have a peaceful route (colonizing unclaimed worlds, buying/trading
  claims, diplomatic cession). No resource is conquest-only.
- **Endless late game [Owner: no forced ending; mechanics are Claude's call]:** upgrade tracks never
  cap, and **repeatable megaprojects** (each completion gives a permanent empire-wide bonus and costs
  more next time) keep numbers growing after the galaxy is claimed. **Milestone victories** (e.g.
  completing the first star gate, reaching an empire output threshold, forming a galactic alliance)
  show a celebration screen, then play continues.

### 6.7 Check-in rhythm and offline progress **[Owner: a few short check-ins a day; numbers are Claude's call]**
- On return, fast-forward the engine for the time away, capped at **12 h base, raised by upgrades up
  to 48 h**. So overnight is fully covered from the start and a weekend away is covered later.
- Upgrade, construction, and fleet-travel timers are mostly in the **minutes to a few hours** range,
  so each check-in usually has something finished to act on.
- Show a "while you were away" summary: production gains, faction events, any war events, and the top
  2–3 bottlenecks with a tap to jump to each one. That way a 2–5 minute session can always do a
  meaningful rebalance.
- `game_sim` balance bands assume a player who checks in about 4 times a day for a few minutes.

## 7. Factions and diplomacy **[Owner: AI factions with diplomacy; details are Claude's call]**

- **4–6 AI factions in v1**, each with a name, home system, color, and personality, for example a
  trader collective, a militarist dominion, an isolationist league, an expansionist empire. Names
  are original.
- AI factions run real economies on the same rules (§5.1). Their decisions can be simpler than a
  human's (heuristic planners), but they produce, trade, expand, and build fleets for real.
- **Relations:** each faction has a relation score and a tension score with every other faction
  (including other AIs, so AI-vs-AI wars and alliances can happen).
- **Diplomatic actions:** trade deal (exchange X/s of one resource for Y/s of another, for a
  duration), non-aggression pact, alliance (mutual defense), demand tribute, declare war, offer or
  accept peace.
- **Tension drivers:** border proximity, competing for the same planets, broken deals, military
  build-up near borders, personality.
- Factions start small and nearby; bigger ones are met as you expand.
- UI: a Factions tab with each faction's stance, active deals, relation/tension bars, and available
  actions (as in the mockup sketch in the conversation).

## 8. War **[Owner: attack and defend planets, in v1; details are Claude's call]**

- **War runs on the economy.** Ship classes (e.g. corvette, frigate, cruiser, dreadnought) and
  planetary defenses (shields, defense platforms, garrisons) are built from components. Going to war
  means shifting production.
- **Fleets** are assembled from ships, given orders (attack planet, defend planet, blockade route,
  escort), and travel along lanes over real time (minutes to hours).
- **Battles resolve automatically**, idle-style: attack vs. defense, shields, ship counts, with
  seeded randomness. A battle report explains why it went the way it did.
- **Sieges** take time. A planet's defenses are worn down before it can be captured. Capturing a
  planet transfers its buildings (damaged) and deposits.
- **War is optional [Owner].** Aggressive factions can still threaten you, but diplomacy (pacts,
  alliances, paying tribute, concessions) can always calm a threat down, at a cost. A player who never
  builds a warship can still progress fully, though they'll pay for peace with credits and trade
  concessions **[Claude's call]**.
- **Factions are never wiped out [Claude's call, follows from no forced ending].** Home worlds are
  protected for every faction, AI included, so factions can shrink but not disappear. Conquering the
  galaxy is not a win condition.
- **Anti-devastation rules** (from the anti-goal):
  - Your home world cannot be captured (same rule for AI factions).
  - Attacks give warning time (a fleet en route is visible with an ETA).
  - While you're offline, enemy sieges progress at a reduced rate, and AI factions won't start a new
    war against you while you're offline.
  - Defenses you set up (shields, platforms, standing defense orders) still fight while you're away.
- War ends with peace terms (planets, tribute, trade concessions).

## 9. Look and screens **[Owner: B home + A panels]**

Visual reference: the mockup page (link in §4).

- **Home = Star Map.** Your planets on orbits around a star, cargo ships moving along routes, enemy
  fleets as moving markers with ETAs, faction territory at the edges. Pinch/zoom out to the galaxy
  view as systems unlock. Top bar shows key resources and credits, ticking live.
- **Tap a planet → Mission Control panel** (bottom sheet, swipe up to full screen): that planet's
  buildings with crew pips and +/- buttons, inputs/s → outputs/s, upgrade buttons with costs,
  bottleneck warnings (amber), deficits (red), local storage, and routes in/out.
- **Bottom tabs [Claude's call]:** Map · Production (all buildings in one list, filterable, for fast
  rebalancing) · Crew · Fleet · Factions. Research lives where it fits best (builder's call).
- Visual style: dark space background. Mission Control panels use a monospace data font, thin
  borders, cyan for interactive elements, amber for warnings, red for deficits, green for surpluses.
  Planets and ships are vector/procedural art (no commissioned illustration needed).
- Must work in portrait on phones, and adapt to wider web/tablet screens (e.g. map and panel side by
  side).
- Accessibility basics: state conveyed by icon + text as well as color, readable text sizes, adequate
  tap targets.

## 10. Testing and playtesting
- `game_core`: unit tests for rules; determinism tests (same seed and commands give a byte-identical
  state); content validation tests; save-migration tests.
- `game_sim`: scripted balance regression runs (time-to-milestone stays within target bands).
- Subagent playtests at each stage milestone, with personas, producing written reports
  **[Owner]**.
- Flutter: widget tests for key panels; a smoke test that launches the app on web and Android.
- The owner playtests builds on their own Android phone (via APK / internal testing track) and on the
  web.

## 11. Build stages (one release, built in order) **[Claude's call]**

No deadline has been set. At the end of each stage, the build pauses for the owner to playtest and give
feedback (plus subagent playtests) before the next stage starts. If scope has to shrink, cut in this
order: research folded into region unlocks, then fewer ship classes, then fewer factions (minimum 4).
1. **Economy engine**: `game_core` with resources, recipes, buildings, crew, upgrades, storage,
   routes, credits, big numbers, save/load, `game_sim` CLI. Playtest the economy headlessly.
2. **Map and panels**: Flutter app with star map home, Mission Control panel, tabs, offline progress,
   autosave. Android + web builds.
3. **Factions and diplomacy**: AI factions with economies, relations, deals, pacts.
4. **War**: ships, fleets, defenses, battles, sieges, peace.
5. **Content and balance**: full 40–60 item economy, galaxy, research, tuning via `game_sim` and
   subagent playtests.
6. **Store prep**: icon, screenshots, listing text, privacy policy, Data safety, content rating,
   closed test (12 testers × 14 days), production release. Web deploy.

## 12. Left to the builder
- Exact items, recipes, numbers, cost curves, and galaxy layout (tuned via `game_sim`).
- Flutter libraries (state management, persistence, routing), project structure details, and the
  web hosting target.
- AI planner design, battle formula, and RNG details, within the determinism rule.
- Rendering technique for the star map (CustomPainter vs. a game library such as Flame).
- Whether research is a separate tree or folded into region unlocks.
- Final game name and package ID: proposed by the builder, decided by the owner before the first Play
  upload.

## 13. Ships, customization, and pirates **[Owner idea, 2026-11-26; details are Claude's call]**

The owner wants ship customization for moving between planets, pirate risk on routes, and several ship roles
(large cargo, small exploration, fighting). These build on the economy, logistics and war already planned.

### 13.1 Ship classes and modules
- Ships are **designs** made from a **hull** plus **modules**, and every part is a produced item. That way ship
  building is another production chain to optimize.
  - Hulls (size sets module slots, speed, upkeep): small, medium, large, capital.
  - Modules:
    - cargo hold (capacity)
    - engine (speed, shorter travel)
    - armor (survive raids)
    - weapons (attack/defense)
    - shields
    - scanner (exploration range, spots pirates earlier)
    - crew quarters (needed for larger hulls)
- The player saves designs (e.g. "Hauler Mk II: large hull, 4 holds, 1 engine, 1 armor"). A shipyard builds a design
  from its parts.
- Starting roles (presets the player can edit):
  - **Large cargo hauler:** high capacity, slow.
  - **Courier:** small and fast, low capacity, good for urgent goods.
  - **Explorer:** small, with scanners and long range. It surveys unknown bodies and systems: reveals deposits and
    richness, and finds new systems to unlock.
  - **Escort/fighter:** weapons and armor, protects routes, and later forms war fleets.
- Routes are assigned ships of a design instead of generic "cargo ships". Route capacity and travel time come from
  the assigned ships' stats.

### 13.2 Exploration
- Bodies and systems start **unsurveyed**: you see a body's type, but not its deposits or richness. Sending an
  explorer reveals them, which also fixes the playtest "first-claim trap" (you learn what a body offers before
  claiming it).
- Exploration is how the galaxy grows (spec 6.6): explorers find neighboring systems, which then unlock for claiming.

### 13.3 Pirates
- Pirates are a non-diplomatic threat that **raids cargo routes**, scaling with how far out and how valuable a route
  is. They are not a faction you negotiate with, though trade allies may share patrol coverage.
- Each shipment on a risky route has a raid chance from the seeded RNG, so it stays deterministic. Escorts, armor,
  scanners and route patrols lower that chance and the loss.
- A raid steals part of the cargo and may damage ships. It never destroys a whole route's fleet in one event.
- Anti-devastation (same spirit as 8): while offline, raid losses per hour are capped at a small share of shipped
  value, and the away summary lists raids clearly. Pirate risk is visible on the map (route shading) before you
  commit ships.
- Optional active play: hunt pirate bases with fighting ships for rewards (rare items, credits).

### 13.4 Where this lands in the build stages
- **Stage 3 (factions):** ship designs + hulls/modules + design-based routes (cargo haulers, couriers). Pirates on
  outer routes in a simple form (raid chance, escorts reduce it).
- **Stage 4 (war):** fighting ships use the same design system. Fleets are groups of designed ships, and pirate bases
  can be attacked.
- **Stage 5 (galaxy content):** explorers, unsurveyed bodies, and system discovery.

## 14. Decisions after playtest round 2 **[Owner, 2026-11-26]**

Source: docs/playtests/2026-11-26-round2-findings.md (7 AI playtesters). Every playtester enjoyed days 1–2, and then
the content ran out (day 2–4 for an optimizer, day 10–12 for a casual player).

- **Real-time timers on big things only [Owner].** Claims, extra building slots, megaproject stages, surveys and
  research take real time, mostly 1–6 h, never under 10 minutes, with no skip button. Ordinary buildings and upgrades
  stay instant. Several timers can run at once, and finished ones appear in the away summary.
- **Repeatable megaprojects as the endless spine, starting now [Owner].** The first is the Orbital Station. Each level
  consumes large deliveries of tier 2–3 goods plus a timer, and grants a permanent empire-wide bonus; the next level
  costs about ×3. More types come in later stages. No resets.
- **Small research tree from stage 3 [Owner].** Labs turn components into research points. Nodes take real time.
  It starts with about 8 nodes and grows to 40–50 by stage 5. Basic conveniences (auto-assign crew, buy ×10) are free,
  never locked behind research.
- **Relaxed contracts board [Owner].** 3 orders at a time with long or no expiry. Empty slots refill over time and
  bank up, so missing a day costs nothing. Orders start from a neutral exchange; factions with reputation post them
  from stage 3. There are no limited-time events.
- **Routes [Claude's call].** A "stop when the destination has N" cap now; "keep the destination stocked" supply
  routes from a shared ship pool arrive with ship designs (stage 3).
- **Galaxy [Claude's call].** The home system stays hand-made. Outer systems are generated from the game seed in
  stage 5.
- **Offline cap [spec 6.7].** It rises from 12 h to 48 h through megaproject levels. The away summary always says
  plainly how much of the absence was counted.
