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
level 1 (you have level 0)").

`{"cmd":"setMegaprojectAuto","megaprojectId":"orbital_station",
"goods":"nearReady","credits":true,"creditWeight":1}` feeds a megaproject on
its own every game minute. `goods` says when each owned body hands over what
the stage still needs above what it keeps (local use, its auto-sell rule's
`keepAtLeast`, open contract needs): `"off"` (the default) never, `"always"`
every minute, and `"nearReady"` only once the stage is near ready, until it
is paid for. A stage is near ready when the credits it still owes are no more
than the credits above the reserve plus 12 hours (`nearReadyHorizonSeconds`
in the rules) of what credit auto-pay gives it, or, with `credits` off, no
more than the credits you hold; until then its goods sell as usual (`state`
shows `goodsFedNow`). `true` and `false`, from older scripts, mean
`"always"` and `"off"`. With `credits` (default false) it takes a share of the
credits above the faction's one auto-pay reserve, set with
`{"cmd":"setAutoPayReserve","credits":"5e6"}` (0 until set). The credits
above the reserve are split among the megaprojects taking credits that still
owe some, in proportion to `creditWeight` (0 to 10, default 1; another value
fails with `invalidAmount`), a share one cannot use going to the others. At
weight 0 a megaproject takes credits only when none of the others owing has a
weight. No goods and no credits clears it. It may be set while the
megaproject is locked. Between minutes auto-sell holds back what a fed stage
still needs, up to the storage cap, and what a body holds of it above the cap
goes in at once, so deliveries are the same for any step size.

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
nothing there can use what arrives. Several routes with stop levels into
one store share one target (the highest of their levels, plus what the
destination uses during the trip of the farthest of them) and its room, the
nearest sending first and the others topping it up. Timed by the farthest
trip, the store is never starved, whichever route sends; while a nearer one
does, it can hold up to the destination's use over the difference between
the longest and shortest trips above the stop level (never past the cap). A
farther route can then send little while not paused. A level
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
expire. Each asks for a good the player's buildings make now from steady
supply (a good made at a trickle, or only from a stockpile nothing refills,
gets none), as much as sells for 10 to 30 minutes of income at today's price
(the larger of auto-sale income and the value of steady net production), at
most a day of what they make of it and what the player's bodies store
together (only goods whose largest such order is worth 10 minutes of income
are asked for, or, when none is, the three worth most), and pays 3× that sale value,
between 30 minutes and 1 hour of income and never below 1.5× the sale value,
at least 500 credits, in whole credits; the first contract ever posted has
no cap and pays at least 7,500 (see `content/README.md`). `{"cmd":"deliverContract","contractId":"c12","bodyId":"kora",
"amount":"500"}` delivers up to `amount` of the contract's resource from the
body's stock (clamped to what is held and to what the contract still wants;
deliveries add up), and pays the reward once the last unit is in. Leave out
`bodyId` (`{"cmd":"deliverContract","contractId":"c12","amount":"1e9"}`) to
deliver from every body you own in one command, the one holding the most
first (ties by body id): the reply lists what each gave ("Delivered 3K Steel
(2K from Kora, 1K from Brine) to contract c12 …", and `spent` by body), and
it fails only when no body you own holds a whole unit. The bots deliver this
way, one command per contract.
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
  `headline` such as `"Away 4d 2h; 12h counted (cap); +1.2M credits"`
  (built here from the summary's typed fields; when credits went into
  megaprojects on their own it says what was earned and where it went:
  `"Away 1h; earned 2.67B credits, 2.11B to Mass Driver, net +560M"`; the
  net is in whole credits, and under one either way reads `+0`),
  seconds away and simulated, the cap (`capSeconds`) and whether the absence
  passed it (`capped`), credits gained, earned (`creditsEarned`: sales and
  contract rewards) and paid in on their own (`creditsPaidIn`), stock
  gained, units wasted to
  storage caps (`totalWasted`) and their worth in credits (`wastedValue`),
  crew before and after (`housingBefore`, `housingAfter`: `base`,
  `supported`, `assigned`; when fewer are housed than assigned the headline
  adds `"; Crew short: 41 housed for 67 assigned"`), credits a second before
  and after (`creditsPerSecBefore`, `creditsPerSecAfter`), milestones
  reached and the top 3 bottlenecks, by cause (one entry for every
  building held back the same way on a body, with `count` and
  `buildingIds`: `"17 Station Docks on Cinder are running at 40%: not
  enough Hull Plate"`, its loss the sum of theirs), what the storage cap
  cut while away counted as `storageFull` entries (its worth an hour over
  the time simulated) even when no store is full on return, and the
  megaproject kinds (below): a crew shortage that costs credits
  first, then those losing the most credits an hour; one that was there
  before the absence gives `since` (the game time it began),
  `worseThanBefore` (its loss grew by more than a quarter) and how long it
  has held, `"ongoing": "for 3h 10m, and worse than before"`; one
  `nextGoal`: the milestone the current rates reach soonest, or a
  megaproject's next stage when that comes sooner (a stage still owed
  credits is left out once you have set its auto-delivery with credit
  auto-pay off and paid it none by hand since it opened; one whose
  auto-delivery you never set still counts; its ETA shares stock
  and income out as auto-delivery does: credits above the auto-pay reserve
  split by weight among the megaprojects taking them, goods to those fed
  goods in content order, so a stage paid by hand waits for them, and a
  near-ready stage's goods only once its feeding would start) (`kind`,
  `id`, `name`,
  `level` for a stage, `etaSeconds`, null when not in reach, and a
  `message` such as `"Next: First Foundry (Make 30 Steel), 12 of 30, in 1m
  30s"`, progress rounded down and what is still needed rounded up); the
  projects that
  completed (`projectsCompleted`: `kind`, `targetId`, `name`, `level` for a
  megaproject stage, and a `message` such as `"Orbital Station reached level
  3"`, which the headline also ends with), stages that started while away
  included; and the contracts posted while away (`contractsPosted`: `id`,
  `resourceId`, `resource`, `quantity`, `reward`)
- `{"cmd":"report"}` per-second flows and bottlenecks (by cause, as in
  `away`); while a megaproject
  is fed on its own, `autoDeliveredPerSec` (per megaproject, credits and
  goods a second) and `autoDeliveredValuePerSec`, apart from
  `creditsPerSec`, which leaves out what goes to megaprojects
- `{"cmd":"state"}` time, credits, crew, reached milestones, the level of
  every megaproject (`megaprojects`: `id`, `name`, `level`, `bonuses` and
  `nextLevel` such as `"level 3: storage +30%, housing +15%, offline cap +3h,
  market depth ×1.95"`, `locked` such as `"opens at Orbital Station level 1
  (now 0)"` while it is, and `auto` with `goods`, `credits` and a `text`
  when it is fed on its own; `autoPayReserve` beside `credits`), the contracts
  board (`contracts`: `id`, `issuer`, `resourceId`, `resource` name,
  `quantity`, `delivered` (its display rounded down, so it never reads as
  the whole while a unit is owed), `reward` in credits) and when its empty
  slots
  refill (`contractRefills`: `at` and `timeLeft`; a refill already due, which
  waits for something a contract can ask for, is counted in `contractsDue`
  instead), the unsurveyed signals of
  each system the player has a body in (`unsurveyedSignals`), every body
  (type, deposits, owner, slots, storage cap, and stock if owned), the
  player's routes (`stopAtDestination`, null for none; for a route with
  one, `stopTarget`, the stock the destination keeps with its cargo in
  flight, shared by every stop-level route into it and timed by the
  farthest, and `stopSharedWith`, the ids of those other routes; `paused`,
  true while the destination and its cargo in flight hold that target;
  `throughput`, the most it could carry a second, sustained (a capacity
  ceiling, not what it carries now: a paused route into a full store that
  nothing draws from can show a nonzero ceiling while carrying nothing),
  and `limitedBy`, what holds it there: `rate`, `ships` (ships × 10 a
  second each), `destinationRoom` (a stop-level route keeps its
  destination's stock and cargo on the way within the stop target, here
  the storage cap, so it carries at most (that target − the other routes'
  cargo in flight there) ÷ the trip; the destination's own stock does not
  count: a route 2 minutes from a store whose target is 97.7K carries at
  most 814 a second, whatever the rate), `stopLevel` (the same, with a
  stop-level target below the cap) or `sourceStock` (what the source makes beyond its own use, cargo
  arriving there and its stock over a minute, less what routes ahead of it
  take); `inFlight` and `travelTime`), its
  auto-sell rules (`autoSell`: `bodyId`, `resourceId`, `keepAtLeast`,
  `localUse`, `contractHold` (what open contracts still need, less what
  bodies with no rule for the good hold, held on the bodies with a rule on
  the good: first what they hold, so none of it sells, then room for the
  rest, the one that holds the most first, each up to its storage cap),
  `keeps`, and a `text` such as `"keeps 7.8K (keepAtLeast 30 +
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
A delivery to a contract that leaves it open says how far it is, rounding
what is in down and what is owed up: `"Delivered 577 Nickel from Dusk Cairn
to contract c205 (49.9K of 50K, 1 still owed)"`. A building put up with
`autoCrew` that got fewer crew than its base slots (as one does alongside
new habitats, which house no one until they first run) takes free crew
after the next tick's production; crew that frees up later is yours to
assign.
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
`effectiveFraction` (run fraction × crew / base slots × crew efficiency),
both null for a building that runs no recipe (a depot), and
actual `inputs` and `outputs`. The rates are steady-state rates: cargo on
routes counts as arriving at the rate it is sent, and a building cargo
feeds runs at no more than the share a full 60 s step of its store's
average supply gives it (what is there and on its way, spread over the
trip), so a report a few seconds before a lot lands reads as one a few
seconds after: no false 0% just before, no false 100% just after.
`creditsPerSec` is what
auto-sell earns a second in steady play, the lower of two estimates: every
building held to the inputs it can get without drawing stock down (cargo
sent round a cycle of routes counts only as far as the cycle's own production
feeds it, and habitats draw what they draw now), and what
a short run of play (5 min, then 10 min measured) earns. Goods made from a
stock nothing refills, and stock above an auto-sell keep, do not count, and
what auto-sell holds back for open contracts is left out (it fills once and
then sells). The steady sales are valued at the prices the market settles
at over the next 2.5 h (five recovery times), not today's, so right after a
large upgrade spree it does not read high while prices catch up, and both
estimates count megaproject stages under way that finish within the short
run as done. So it matches what hours away earn (within 1% from day-7 bot
states; within 1% on the round-4 optimizer's state at 26.5 h, right after a
578M upgrade spree, where it used to read 21% high). `state` also gives the player's crew totals (`base`, `supported`,
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
sold: turn on auto-sell or sell goods"; `bodyId` and `buildingId` are null),
`megaprojectDiversion` (auto-delivery hands `megaprojectId` a tenth or more
of what would otherwise sell of `resourceId`, `shareOfSales`: "Orbital
Station takes 40% of the Hull Plate that would sell: 1.2M credits an hour
not earned"), or `keepBlocksDelivery` (a fed megaproject still owes
`resourceId`, and `bodyId`'s auto-sell `keepAtLeast` holds back
`heldByKeep` of it from auto-delivery: "Orbital Station still needs Reactor
Core, but Cinder keeps 469 of it back for its auto-sell keepAtLeast 1K"),
or `routeLimited` (an `input` shortage whose store's routes carry less than
its buildings use, where the route that carries most, `routeId`, is held
back by something other than what its source has: `binding` is `rate`,
`ships`, `destinationRoom` or `stopLevel`, and `routePerSec` the most it
carries a second, as `state` shows it: "17 Station Docks on Cinder are
running as low as 39%: Hull Plate into Cinder is limited by Cinder's storage
(814/s); a Depot raises it"; it is tracked and grouped as the `input`
shortage it is, and its `lostCreditsPerHour` is the input's).
`report` and `away` list them by cause: buildings on one body held back the
same way are one entry with `count`, `buildingIds` (and `buildingId` null
when there are several) and their losses summed.
Each also gives `firstSeenAt`, the game time since which it has held without
a break, and `lostCreditsPerHour`, an estimate at current prices of what it
costs (the wasted units for `storageFull`; for `input` the output the
starved building does not make, gross of the inputs it would use, as for
`routeLimited`; the net
production left unsold for `noSales`; for `crewShortage` what full staffing
would add to net production, more output less the extra inputs it draws,
leaving out output a full store with nothing selling it would waste; for
`megaprojectDiversion` what the goods taken would sell for at current
prices; null for the other kinds).

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
- `balanced` fixes the worst bottlenecks (a building short of an input only
  below 70% of full rate: a bot heuristic, see
  `BalancedBot.defaultInputWorthFixingBelow`), claims bodies, auto-sells
  surplus,
  works toward the next milestone (and housing when crew runs out), and
  spends the rest on the best return.
- `casual` plays like `balanced` but issues at most 15 commands per check-in
  (auto-sell rules aside), a stand-in for a player with a few minutes.

The bots build with `autoCrew` on, so a new building takes its crew at once;
they assign what crew is left (from new housing) themselves. Timed things come
first in a check-in (surveys, claims, contracts, megaproject deliveries), so
their timers run while the player is away.

- **Megaprojects.** Once a megaproject opens, each bot feeds it on its own
  (`setMegaprojectAuto`): goods from every body once a stage is near ready
  (`"goods":"nearReady"`), credits at the default weight 1. Once credits are all the
  stage being paid for still lacks, the bot pays them by hand when it can
  and still keep a reserve of an hour of income; otherwise they go in on
  their own above the shared auto-pay reserve of that hour (one for every
  megaproject, set before any credits go in), and stop at the next decision after the
  stage is paid (credits paid in earlier, or left flowing into the next
  stage, sit idle in a stage still short of goods). The bots deliver by
  hand only what auto-delivery does not cover. Stages go on being paid for
  while one runs, the next starting as the running one ends; the engine's
  auto-sell holds back what a fed stage still lacks. When at today's
  surplus a good a stage lacks would take more than a day to come (after
  what megaprojects before it in content order still lack of it, since
  auto-delivery feeds those first), the balanced and casual bots grow its
  supply, once per megaproject per decision: they feed a maker held back
  by its inputs (or grow those in turn, going on to the next maker when
  that leads nowhere), else build another maker.
- **Surveys** take only drones beyond what that stage still lacks.
- **Contracts** come before the station: the engine's auto-sell holds a
  contract's goods back, and the bots deliver once a body holds enough to
  finish it (or its store is nearly full), and discard a contract on a
  resource they neither make nor hold.
- **Routes.** A route feeding buildings carries twice their demand and stops at
  what the destination keeps for them (`stopAtDestination`), so it keeps up as
  they grow without filling the store; the surplus is sold at the source. A
  route too small is grown with `updateRoute` (more rate, more ships), and
  cargo ships go where a route needs them with `moveShips`. Build-part routes
  stop at the parts needed.
- **Starved makers.** When every maker of a good the bot is working toward
  stands idle for an input, it routes the input in, grows the route, sends
  ships, or feeds the input's own makers in turn.

`docs/balance/stage1_6-30day-*.md` hold the 30-day baselines of all three bots (seed 1, and a
summary of the pacing targets on seeds 1 to 3); the stage 1.5 ones are kept for comparison. Rerun
them after changing `content/*.json` and compare.

