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
`deliverContract`, `discardContract`);
`factionId` defaults to the player. A successful game command
replies with `spent` and `gained` (credits and `body/resource` amounts that
changed), `createdId` for a new building, route, ship move or project, and for
`build`, `claimBody`, `survey`, `expandSlots`, `startMegaprojectStage`, `demolish`,
`createRoute`, `updateRoute`, `moveShips`, `deliverContract` and
`discardContract` a `message` such as
`"Started claiming Brine for 5K credits; done in 30m"`. Claims, extra build
slots and megaproject stages are projects: they are paid for at once and take
effect when their timer runs out (a claim of a body, a second slot on one, or
a second stage of a megaproject, already under way fails with
`projectInProgress`). `{"cmd":"startMegaprojectStage","megaprojectId":
"orbital_station","bodyId":"kora"}` pays the next level's cost from the body's
stock and credits; each completed stage raises the megaproject's level, a
permanent bonus.

A new building takes free crew up to its base crew slots (fewer if fewer are
free; the reply says `"Built Shipyard on Kora (b9) with 2 of 2 crew"`);
`"autoCrew":false` on `build` leaves it empty.

Routes move one resource between two of the player's bodies in one system,
using cargo ships from the source body's stock. `createRoute` takes an optional
`"stopAtDestination":"500"`: the route pauses while the destination holds 500,
counting its cargo still in flight, so it never overshoots, and resumes once the
destination uses some up. `{"cmd":"updateRoute","routeId":"r4",
"ratePerSecond":"2","cargoShips":3,"stopAtDestination":"800"}` changes any of
the three and keeps the rest (more ships are taken from the source body, fewer go
back to it); `"removeStopAtDestination":true` takes the stop level off.
`{"cmd":"moveShips","fromBodyId":"kora","toBodyId":"brine","count":2}` sends
cargo ships to another body as a shipment with the normal travel time, the way
to get ships to a body before opening a route from it. A route takes its share
of the source's stock before auto-sell sells there, so a rule with `keepAtLeast`
0 sells only what the route leaves.

Some bodies are hidden until surveyed. A hidden body is not in `state` or
`costs`, and every command but `survey` treats it as `unknownBody`.
`{"cmd":"survey","bodyId":"tessaly","sourceBodyId":"kora"}` pays
`costs.survey` (survey drones from the source body, plus credits) and starts a
survey project of a few hours; it runs beside claims and other surveys.
When it ends the body shows up and can be claimed. Ids of hidden bodies are
in `content/galaxy.json` (`"hidden": true`); an unknown id fails with
`unknownBody`, a surveyed one with `alreadySurveyed`.

The Veyra Exchange posts up to 3 contracts on the player's board. They never
expire. `{"cmd":"deliverContract","contractId":"c12","bodyId":"kora",
"amount":"500"}` delivers up to `amount` of the contract's resource from the
body's stock (clamped to what is held and to what the contract still wants;
deliveries add up), and pays the reward once the last unit is in.
`{"cmd":"discardContract","contractId":"c12"}` takes a contract off the board
with no penalty. Either way the freed slot refills 4 h later, banked after any
refills already waiting, so a board emptied before a long absence is full
again on return. An unknown contract fails with `unknownContract`. Meta
commands:

- `{"cmd":"advance","seconds":N}` run the simulation for N seconds, no cap
- `{"cmd":"away","seconds":N}` simulate the player being away for N seconds
  (offline catch-up, capped at the offline limit: 12 h plus the player's
  megaproject bonuses, at most 48 h) and print the away summary:
  seconds away and simulated, credits and stock gained, units wasted to
  storage caps, milestones reached and the top bottlenecks, those losing the
  most credits an hour first; one that was there before the absence says
  `"ongoing": "ongoing since 12.0h"` (game hours); and the projects that
  completed (`projectsCompleted`: `kind`, `targetId`, `name`)
- `{"cmd":"report"}` per-second flows and bottlenecks
- `{"cmd":"state"}` time, credits, crew, reached milestones, the level of
  every megaproject (`megaprojects`: `id`, `name`, `level`), the contracts
  board (`contracts`: `id`, `issuer`, `resourceId`, `resource` name,
  `quantity`, `delivered`, `reward` in credits) and when its empty slots
  refill (`contractRefills`: `at` and `timeLeft`), every body
  (type, deposits, owner, slots, storage cap, and stock if owned), the
  player's routes (`stopAtDestination`, null for none, and `paused`, true
  while the destination plus the route's cargo in flight hold at least that
  much), its running projects soonest first (`kind`, `targetId`,
  `name`, `startedAt`, `finishAt`, `secondsLeft` and `timeLeft` such as
  `"1h 30m"`), and price and saturation of the goods the player holds
- `{"cmd":"costs"}` upgrade costs of the player's buildings (a track that
  can no longer help, such as efficiency at its floor, shows `"maxed": true`
  and a `reason` instead of a cost, and `upgrade` refuses it; `upgradeNote`
  says that speed and capacity on a building share one price counter), the
  next claim
  cost (or `"no bodies left to claim"` once every body is owned), each
  owned body's next extra build slot, and each megaproject's next stage
  (`megaprojects`: `nextLevel`, `cost`, `timeTaken`)
- `{"cmd":"save","path":"save.json"}` / `{"cmd":"load","path":"save.json"}`

`advance` and `away` tick the engine the same way, in 60 s steps; within a
step every chain on a body runs through and landed cargo is used, so the step
length does not change what is earned. The only difference is that `away`
caps the time at the offline limit and summarizes it.

Replies are `{"ok":true,...}` or `{"ok":false,"error":"...","message":"..."}`.
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
routes counts as arriving at the rate it is sent, and `creditsPerSec` is
what auto-selling one second's net production earns, not a stockpile being
sold down, so it matches what a stretch of `advance` earns while nothing
changes. `state` also gives the player's crew totals (`base`, `supported`,
`assigned`, `free`, which is never below 0, and `overAssigned`, the crew
assigned beyond what housing supports).

Bottlenecks in `report` carry a `kind`: `input` (short of `resourceId`),
`noCrew`, `understaffed` (every input supplied but fewer crew than its
base slots; the building's `limitReason` is `understaffed` too),
`crewShortage` (habitats and base crew support fewer crew than
are assigned, so every crewed building slows; `bodyId` and `buildingId` are
null), or `storageFull` (`resourceId` is at the body's storage cap and
output is being wasted; `buildingId` is null). Each also gives
`firstSeenAt`, the game time since which it has held without a break, and
`lostCreditsPerHour`, an estimate at current prices of what it costs (the
wasted units for `storageFull`, the output not made for `input`; null for
the other kinds).

## Bot runs

`bot` plays a new game with a scripted bot as a player who checks in 4 times
a day: each check-in the bot acts for 180 s of game time, deciding every
10 s, then the engine catches up offline to the next check-in. It prints a
balance report: when each milestone was first seen, dead zones (check-ins
with nothing to do), unused resources, final stock and credits, and the worst
bottleneck at each check-in. `--format md` gives Markdown; JSON is the default.

The report also gives the market income of each day with each resource's
share.

- `greedy` buys the cheapest affordable upgrade, building, extra slot or
  claim each decision.
- `balanced` fixes the worst bottlenecks, claims bodies, auto-sells surplus,
  works toward the next milestone (and housing when crew runs out), and
  spends the rest on the best return.
- `casual` plays like `balanced` but issues at most 15 commands per check-in
  (auto-sell rules aside), a stand-in for a player with a few minutes.

Every bot works the contracts board: it holds a contract's goods back from
auto-sell, delivers what a body holds beyond its own needs, and discards a
contract on a resource it neither makes nor holds.

`docs/balance/stage1-baseline.md` holds the 168 h baselines of all three
bots; rerun them after changing `content/*.json` and compare.

