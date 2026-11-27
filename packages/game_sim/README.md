# game_sim

Headless CLI for the space idle engine. Reads one JSON object per line from
`--script` or stdin and writes one JSON line per input line to stdout.

```
dart run game_sim:game_sim [--content content] [--seed 1] [--load save.json] [--script file.jsonl]
dart run game_sim:game_sim check --content content   # exit 1 if content is invalid
dart run game_sim:game_sim bot --bot balanced|casual|greedy --hours 168 --seed 1 [--format json|md]
```

Game commands use the `Command.toJson` format (`build`, `demolish`, `assignCrew`,
`upgrade`, `createRoute`, `updateRoute`, `moveShips`, `removeRoute`, `sell`,
`setAutoSell`, `claimBody`, `survey`, `expandSlots`, `startMegaprojectStage`,
`deliverToMegaproject`, `setMegaprojectAuto`, `deliverContract`,
`discardContract`);
`factionId` defaults to the player. A successful game command
replies with `spent` and `gained` (credits and `body/resource` amounts it took
and gave), `createdId` for a new building, route, ship move or project, and for
`build`, `claimBody`, `survey`, `expandSlots`, `startMegaprojectStage`,
`deliverToMegaproject`, `demolish`,
`createRoute`, `updateRoute`, `moveShips`, `deliverContract` and
`discardContract` a `message` such as
`"Started claiming Brine for 5K credits (no kits needed); done in 30m"` (only
the first claim needs no outpost kits). Claims, extra build
slots and megaproject stages are projects: they are paid for at once and take
effect when their timer runs out (a claim of a body or a second slot on one
already under way fails with `projectInProgress`). A command on a body whose
claim is still under way fails with `stillClaiming`: "Brine is still being
claimed (25m left)". The reply is built from the engine's typed command
outcome (`CommandOk.outcome`), not by comparing states. A megaproject stage is paid for in deliveries that add
up: `{"cmd":"deliverToMegaproject","megaprojectId":"orbital_station",
"bodyId":"kora","amounts":{"hull_plate":"120","credits":"5e5"}}` hands over up
to those amounts from the body's stock (credits from the faction), each clamped
to what the next level still needs and to what is held, from any owned body at
any time, so a level may cost more than one body can store. The delivery that
completes the last entry starts the stage's timer (the reply has its
`createdId` and says "level 2 started, done in 2h"; otherwise it says what is
still needed). While a stage runs, deliveries pay for the level after it; once
that is paid in full it waits and starts the moment the running stage
completes, its timer running from then ("level 3 starts when level 2 is done,
in 25m"), offline too, and more deliveries fail with `projectInProgress` until
it starts. `state.megaprojects` shows `delivered` and `stillNeeded` while
a level is part-paid. `{"cmd":"startMegaprojectStage","megaprojectId":
"orbital_station","bodyId":"kora"}` delivers everything still needed from one
body at once ("Started Orbital Station level 1 on Kora for …", or "Paid for …
level 3 … it starts when level 2 is done" while a stage runs), or fails with
`cannotAfford`. Each completed stage raises the megaproject's level, a
permanent bonus. A megaproject with `requiresMegaproject` refuses deliveries
with `megaprojectLocked` until it opens ("Mass Driver opens at Orbital Station
level 2 (you have level 1)").

`{"cmd":"setMegaprojectAuto","megaprojectId":"orbital_station","goods":true,
"creditReserve":"5e6"}` feeds a megaproject on its own every game minute:
with `goods`, each owned body hands over what the stage still needs above
what it keeps (local use, its auto-sell rule's `keepAtLeast`, open contract
needs); with `creditReserve`, the credits above it (leave it out for no
credits). `"goods":false` without a reserve clears it. It may be set while
the megaproject is locked. Between minutes auto-sell holds back what a fed
megaproject still needs, so deliveries are the same for any step size.

A new building takes free crew up to its base crew slots (fewer if fewer are
free; the reply says `"Built Shipyard on Kora (b9) with 2 of 2 crew. At full
crew it uses 0.0333 Steel and 0.0133 Circuit a second and makes 0.00333
Cargo Ship a second"`, the recipe also as `inputsPerSec` and
`outputsPerSec`); `"autoCrew":false` on `build` leaves it empty. Deliveries to
contracts and megaprojects move whole units: amounts are rounded down, below
1 is refused, and what is still owed is whole.

Routes move one resource between two of the player's bodies in one system,
using cargo ships from the source body's stock. `createRoute` takes an optional
`"stopAtDestination":"500"`, the stock the destination keeps: the route
pauses while the destination would hold 500 once all the cargo in flight to
it of that resource (on any route), less what its buildings use at full
supply during the trip, has landed, and resumes once the destination uses
some up. So a long trip keeps enough in flight that the destination never
runs dry and settles near its level, and 60 s steps move what 1 s steps do.
The store plus the cargo on its way never pass the storage cap, even when
nothing there can use what arrives, and several routes into one store share
its room in route order. A level
above the destination's storage cap is cut to the cap; the reply ends "The
stop level was cut to Brine's storage cap: stock above it is wasted". Moved
ships and landed cargo can be used at the arrival time a reply gave. `{"cmd":"updateRoute","routeId":"r4",
"ratePerSecond":"2","cargoShips":3,"stopAtDestination":"800"}` changes any of
the three and keeps the rest (more ships are taken from the source body, fewer go
back to it); `"removeStopAtDestination":true` takes the stop level off.
`{"cmd":"moveShips","fromBodyId":"kora","toBodyId":"brine","count":2}` sends
cargo ships to another body as a shipment with the normal travel time, the way
to get ships to a body before opening a route from it. A route takes its share
of the source's stock before auto-sell sells there, so a rule with `keepAtLeast`
0 sells only what the route leaves.

Some bodies are hidden until surveyed. A hidden body is not in `state` or
`costs`, and every command but `survey` treats it as `unknownBody`. `state`
counts them as `unsurveyedSignals` (`systemId`, `name`, `count`) in each system
where the player owns a body, leaving out any under survey; a survey project in
`state` names its target "an unsurveyed body" and gives no `targetId`.
`{"cmd":"survey","sourceBodyId":"kora"}` pays `costs.survey` (survey drones
from the source body, plus credits) and starts a survey project of a few hours
on the next signal in the source body's system (in content order, skipping one
already under survey); it runs beside claims and other surveys. When it ends
the body shows up and can be claimed. With none left it fails with
`alreadySurveyed`, and with every one already under survey with
`projectInProgress`. A `bodyId` names the body instead (ids of hidden bodies
are in `content/galaxy.json`, `"hidden": true`); an unknown id fails with
`unknownBody`, one in another system with `routeInvalid` (checked first), a
surveyed one with `alreadySurveyed`.

The Veyra Exchange posts up to 3 contracts on the player's board. They never
expire. Each asks for 1–3 h of what the player's buildings make of a good
now from steady supply (a good made at a trickle, or only from a stockpile
nothing refills, gets none) and pays 3× its base price, between 10 minutes
and 1 hour of income (the larger of auto-sale income and the value of steady
net production), at least 500 credits; the first contract ever posted has
no cap and pays at least 7,500 (see `content/README.md`). `{"cmd":"deliverContract","contractId":"c12","bodyId":"kora",
"amount":"500"}` delivers up to `amount` of the contract's resource from the
body's stock (clamped to what is held and to what the contract still wants;
deliveries add up), and pays the reward once the last unit is in.
`{"cmd":"discardContract","contractId":"c12"}` takes a contract off the board
with no penalty. Either way the freed slot refills 4 h later, banked after any
refills already waiting, so a board emptied before a long absence is full
again on return; the reply says when the next contract arrives, the soonest
refill. An unknown contract fails with `unknownContract`. Meta
commands:

- `{"cmd":"advance","seconds":N}` run the simulation for N seconds, no cap
- `{"cmd":"away","seconds":N}` simulate the player being away for N seconds
  (offline catch-up, capped at the offline limit: 12 h plus the player's
  megaproject bonuses, at most 48 h) and print the away summary: a one-line
  `headline` such as `"Away 4d 2h; 12h counted (cap); +1.2M credits"`,
  seconds away and simulated, the cap (`capSeconds`) and whether the absence
  passed it (`capped`), credits and stock gained, units wasted to
  storage caps (`totalWasted`) and their worth in credits (`wastedValue`),
  crew before and after (`housingBefore`, `housingAfter`: `base`,
  `supported`, `assigned`; when fewer are housed than assigned the headline
  adds `"; Crew short: 41 housed for 67 assigned"`), credits a second before
  and after (`creditsPerSecBefore`, `creditsPerSecAfter`), milestones
  reached and the top bottlenecks: a crew shortage that costs credits
  first, then those losing the most credits an hour; one that was there
  before the absence gives `since` (the game time it began),
  `worseThanBefore` (its loss grew by more than a quarter) and how long it
  has held, `"ongoing": "for 3h 10m, and worse than before"`; one
  `nextGoal`: the milestone the current rates reach soonest, or a
  megaproject's next stage when that comes sooner (`kind`, `id`, `name`,
  `level` for a stage, `etaSeconds`, null when not in reach, and a
  `message` such as `"Next: First Foundry (Make 30 Steel), 12 of 30, in 1m
  30s"`); the projects that
  completed (`projectsCompleted`: `kind`, `targetId`, `name`, `level` for a
  megaproject stage, and a `message` such as `"Orbital Station reached level
  3"`, which the headline also ends with), stages that started while away
  included; and the contracts posted while away (`contractsPosted`: `id`,
  `resourceId`, `resource`, `quantity`, `reward`)
- `{"cmd":"report"}` per-second flows and bottlenecks; while a megaproject
  is fed on its own, `autoDeliveredPerSec` (per megaproject, credits and
  goods a second) and `autoDeliveredValuePerSec`, apart from
  `creditsPerSec`, which leaves out what goes to megaprojects
- `{"cmd":"state"}` time, credits, crew, reached milestones, the level of
  every megaproject (`megaprojects`: `id`, `name`, `level`, `bonuses` and
  `nextLevel` such as `"level 3: storage +30%, housing +15%, offline cap +3h,
  market depth ×1.73"`, `locked` such as `"opens at Orbital Station level 2
  (now 1)"` while it is, and `auto` with `goods`, `creditReserve` and a `text`
  when it is fed on its own), the contracts
  board (`contracts`: `id`, `issuer`, `resourceId`, `resource` name,
  `quantity`, `delivered`, `reward` in credits) and when its empty slots
  refill (`contractRefills`: `at` and `timeLeft`; a refill already due, which
  waits for something a contract can ask for, is counted in `contractsDue`
  instead), the unsurveyed signals of
  each system the player has a body in (`unsurveyedSignals`), every body
  (type, deposits, owner, slots, storage cap, and stock if owned), the
  player's routes (`stopAtDestination`, null for none, `paused`, true while
  the destination would hold that much once its cargo in flight, less what
  it uses during the trip, lands, `inFlight` and `travelTime`), its
  auto-sell rules (`autoSell`: `bodyId`, `resourceId`, `keepAtLeast`,
  `localUse`, `contractHold` (what open contracts still need, less what
  bodies with no rule for the good hold, held on the body with a rule on the
  good that holds the most of it, up to its storage cap), `keeps`, and a `text` such as `"keeps 7.8K (keepAtLeast 30 +
  7.77K local use)"`, with `" + 200 for open contracts"` when it holds
  some and `" + 20K for megaprojects"` (`megaprojectHold`) for what a fed
  megaproject still needs), its running projects soonest first (`kind`, `targetId`
  but for a survey of a hidden body,
  `name`, `startedAt`, `finishAt`, `secondsLeft` and `timeLeft` such as
  `"1h 30m"`), and price and saturation of the goods the player holds
- `{"cmd":"costs"}` upgrade costs of the player's buildings (a track that
  can no longer help, such as efficiency at its floor, shows `"maxed": true`
  and a `reason` instead of a cost, and `upgrade` refuses it; `upgradeNote`
  says that speed and capacity on a building share one price counter), the
  next claim
  cost (or `"no bodies left to claim"` once every body is owned), each
  owned body's next extra build slot, the survey cost and time, and each
  megaproject's next stage (`"locked: opens at …"` while locked; else
  `megaprojects`: `nextLevel`, `cost`,
  `stillNeeded` once part-paid, `timeTaken`, and a `note` while a stage
  runs). What cannot be started now says why instead of a cost: `"busy: an
  extra slot arrives in 25m"`, `"busy: every unsurveyed signal is being
  surveyed"`, `"busy: every body left is being claimed"`, `"busy: level 3 is
  paid for and starts when level 2 is done, in 1h"`, `"busy: level 50, its
  highest, is under way, done in 1h"`, or `"nothing left to survey"`
- `{"cmd":"catalog"}` every building type in content order: `cost`,
  `crewSlots`, `inputsPerSec` and `outputsPerSec` at its base level with full
  crew (an extractor's for each resource it mines at richness 1), `housing`
  or `storageBonus` when it adds some, and `canBuildOn`: the player's bodies
  with a free build slot that can take one now, an extractor's with the
  `deposits` it can mine there and their `outputPerSec`
- `{"cmd":"save","path":"save.json"}` / `{"cmd":"load","path":"save.json"}`

`advance` and `away` tick the engine the same way, in 60 s steps; within a
step every chain on a body runs through and landed cargo is used, so the step
length does not change what is earned. The only difference is that `away`
caps the time at the offline limit and summarizes it.

Replies are `{"ok":true,...}` or `{"ok":false,"error":"...","message":"..."}`.
A capacity upgrade on a crewed building fills its new slot from free crew:
the reply has `crewAdded` and a message such as `"Mine on Kora (b1) is at
capacity level 1; 1 free crew moved into its new slot (2 of 2 crew)"`, or
says the slot is empty when no crew is free.
Error messages are plain sentences with display names: an unknown building
type lists what the body can build with each one's cost (`"Mine (mine, 100
credits), Smelter (smelter, 150 credits), ..."`), an upgrade track the
building lacks is `noSuchTrack`, "Needs 1 more crew" says how many crew are
assigned beyond what housing supports when that is why none is free,
and a claim short of outpost kits says what makes them (`"An Outpost Kit
Assembler makes 1 Outpost Kit from 6 Hull Plate, 12 Fuel and 6 Circuit"`).
Numbers appear as `{"value":"2.41e6","display":"2.41M"}`.

Examples:

```
{"cmd":"advance","seconds":600}
{"cmd":"build","bodyId":"kora","defId":"smelter"}
{"cmd":"report"}
```

`report` gives per-second rates for each owned body, the player's
`creditsPerSec`, and for each building its `runFraction` (input supply),
`effectiveFraction` (run fraction × crew / base slots × crew efficiency) and
actual `inputs` and `outputs`. The rates are steady-state rates: cargo on
routes counts as arriving at the rate it is sent. `creditsPerSec` is what
auto-sell earns a second in steady play, the lower of two estimates: every
building held to the inputs it can get without drawing stock down (cargo
sent round a cycle of routes counts only as far as the cycle's own production
feeds it, and habitats draw what they draw now), and what
a short run of play (5 min, then 10 min measured) earns. Goods made from a
stock nothing refills, and stock above an auto-sell keep, do not count, and
what auto-sell holds back for open contracts is left out (it fills once and
then sells), so it matches what hours away earn (within 1% from day-7 bot states). `state` also gives the player's crew totals (`base`, `supported`,
`assigned`, `free`, which is never below 0, and `overAssigned`, the crew
assigned beyond what housing supports).

Bottlenecks in `report` carry a `kind`: `input` (short of `resourceId`),
`noCrew`, `understaffed` (every input supplied but fewer crew than its
base slots; the building's `limitReason` is `understaffed` too),
`crewShortage` (habitats and base crew support fewer crew than
are assigned, so every crewed building slows; `bodyId` and `buildingId` are
null), `storageFull` (`resourceId` is at the body's storage cap and
output is being wasted; `buildingId` is null), or `noSales` (goods with a
price are made and no owned body has an auto-sell rule: "Nothing is being
sold: turn on auto-sell or sell goods"; `bodyId` and `buildingId` are null).
Each also gives `firstSeenAt`, the game time since which it has held without
a break, and `lostCreditsPerHour`, an estimate at current prices of what it
costs (the wasted units for `storageFull`, the output not made for `input`,
the net production left unsold for `noSales`, the output crewed buildings
lose against full staffing for `crewShortage`; null for the other kinds).

## Bot runs

`bot` plays a new game with a scripted bot as a player who checks in 4 times
a day: each check-in the bot acts for 180 s of game time, deciding every
10 s, then the engine catches up offline to the next check-in. It prints a
balance report: when each milestone was first seen, dead zones (check-ins
with nothing to do), unused resources, final stock and credits, and the worst
bottleneck at each check-in. `--format md` gives Markdown; JSON is the default.

The report also gives the market income of each day with each resource's
share, a Days table (new things seen each day: milestones, completed claims,
surveys, extra slots and megaproject stages, and completed contracts; bodies
owned, megaproject levels and contracts completed at the day's end; contract
rewards paid that day; Earned, market sales plus contract rewards; and each
tier's share of the day's market sales), two pacing lines ("days with
something new", and "days with a milestone or project", which leaves
contracts out), and a Timeline of every completed project and contract.

- `greedy` buys the cheapest affordable upgrade, building, extra slot or
  claim each decision.
- `balanced` fixes the worst bottlenecks, claims bodies, auto-sells surplus,
  works toward the next milestone (and housing when crew runs out), and
  spends the rest on the best return.
- `casual` plays like `balanced` but issues at most 15 commands per check-in
  (auto-sell rules aside), a stand-in for a player with a few minutes.

The bots build with `autoCrew` on, so a new building takes its crew at once;
they assign what crew is left (from new housing) themselves. Timed things come
first in a check-in (surveys, claims, contracts, megaproject deliveries), so
their timers run while the player is away.

- **Megaprojects.** Each bot delivers a stage's goods from every body that
  holds more than it keeps for its own use, then the credits once every good
  is in, which starts the timer. They go on delivering while a stage runs,
  paying for the level after it, which then starts as the running one ends.
  Auto-sell holds back what the stage being paid for still lacks.
- **Surveys** take only drones beyond what that stage still lacks.
- **Contracts** come before the station: the bots hold a contract's goods back
  from auto-sell, deliver once a body holds enough to finish it (or its store
  is nearly full), and discard a contract on a resource they neither make nor
  hold.
- **Routes.** A route feeding buildings carries twice their demand and stops at
  what the destination keeps for them (`stopAtDestination`), so it keeps up as
  they grow without filling the store; the surplus is sold at the source. A
  route too small is grown with `updateRoute` (more rate, more ships), and
  cargo ships go where a route needs them with `moveShips`. Build-part routes
  stop at the parts needed.
- **Starved makers.** When every maker of a good the bot is working toward
  stands idle for an input, it routes the input in, grows the route, sends
  ships, or feeds the input's own makers in turn.

`docs/balance/stage1_5-30day-*.md` hold the 30-day baselines of all three bots (seed 1, and a
seed 2 and 3 summary); rerun them after changing `content/*.json` and compare.

