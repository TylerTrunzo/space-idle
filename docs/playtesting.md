# Playtesting the economy (stage 1)

This guide is for a subagent playtester. You play the headless simulator
(`game_sim`) in a persona, then write a short report in plain language. Stage 1
has only the economy: one star system, one faction (you), production chains,
crew and habitats, cargo routes, the market and claiming bodies. There are no AI
factions, no diplomacy and no war yet.

## Setup

From the repository root:

```
export PATH=/opt/flutter/bin:$PATH
dart pub get
dart run game_sim:game_sim check --content content   # {"ok":true} if content is valid
```

## Playing by hand

The simulator reads one JSON object per line from stdin (or `--script file.jsonl`)
and writes one JSON line back for each. Keep a script file of the lines you send so
that anyone can replay your game exactly:

```
dart run game_sim:game_sim --seed 1 --script my_game.jsonl
```

For an interactive session, pipe lines in, or run the command and type them.
Replies are `{"ok":true,...}` or `{"ok":false,"error":"...","message":"..."}`.
Numbers come back as `{"value":"2.41e6","display":"2.41M"}`.

### Meta commands (look and wait)

| Line | What it does |
|---|---|
| `{"cmd":"state"}` | Game time, credits, crew (base, supported, assigned, free, and overAssigned: crew assigned beyond what housing supports), milestones reached, every body in the system (type, deposits and their richness, owner, build slots used/total, storage cap, and stock for the bodies you own), your routes with their ids, stop level, whether they are paused, cargo in flight (`inFlight`) and travel time, every auto-sell rule with what it keeps back (`"keeps 7.8K (keepAtLeast 30 + 7.77K local use)"`, with `"+ 200 for open contracts"` on the body holding what open contracts still need, and `"+ 20K for megaprojects"` while a fed megaproject still needs the good), the contracts board and its future refills (a refill already due but waiting for something to ask for is counted in `contractsDue`, not shown as "0s"), and the market price and saturation of every good you hold. Stock of components and above (tier 2+: circuits, cargo ships, outpost kits, ...) shows whole units; the part-made unit is kept |
| `{"cmd":"catalog"}` | Every building type: its cost, crew slots, what it takes and makes a second at its base level with full crew (an extractor at richness 1), housing or storage it adds, and which of your bodies can take one now (`canBuildOn`: a free slot and, for an extractor, a deposit it mines, with the rate there) |
| `{"cmd":"report"}` | Steady per-second production, use, net flow and waste per body, credits per second (what auto-sell earns a second in steady play: goods made from a stock nothing refills, and stock above an auto-sell keep, do not count, nor what auto-sell holds back for open contracts, nor goods auto-delivery takes, and a short run of play confirms it; it matches what a few hours away earn), what auto-delivery hands each megaproject a second and its worth (`autoDeliveredPerSec`, `autoDeliveredValuePerSec`; income plus this to projects, not lost income), each building's run fraction, effective fraction (run fraction × crew / base slots × crew efficiency), crew and actual inputs and outputs, and the bottlenecks, worst first |
| `{"cmd":"costs"}` | Next upgrade cost of every track of every building, the next claim cost (or "no bodies left to claim"), the survey cost and time, the next extra build slot on each body you own, and each megaproject's next level (`cost`, plus `stillNeeded` once part of it is delivered). Anything you cannot start right now says why instead of a cost, such as `"busy: an extra slot arrives in 25m"` or `"busy: level 3 is paid for and starts when level 2 is done, in 1h"` |
| `{"cmd":"advance","seconds":600}` | Let time pass (no offline cap here) |
| `{"cmd":"away","seconds":28800}` | Pretend you closed the game for 8 hours: runs offline catch-up (capped at 12 h, more with Orbital Station levels) and shows the away summary: a one-line `headline` ("Away 4d 2h; 12h counted (cap); +1.2M credits"), the cap and whether you passed it (`capSeconds`, `capped`), credits and stock gained, units wasted to storage caps and their worth in credits (`wastedValue`), crew housed and assigned before and after (`housingBefore`, `housingAfter`; a shortage also goes in the headline: "Crew short: 41 housed for 67 assigned"), credits a second before and after, milestones reached and the top bottlenecks (a crew shortage that costs credits first, then those costing the most credits an hour), each marked `"ongoing": "for 3h 10m"` (how long it has held, with `since`, its start) if it was already there when you left, and ", and worse than before" (`worseThanBefore`) when its loss grew by more than a quarter, one `nextGoal` (the milestone your current rates reach soonest, or the next megaproject stage when that is sooner, with its ETA), the projects that completed with a line for each (`message`, such as "Brine claimed" or "Orbital Station reached level 3", and `level` for a megaproject stage; the headline names the level too), the contracts posted while you were away (`contractsPosted`), and what auto-delivery handed each megaproject (`autoDelivered`, with a `message` such as "Orbital Station got 5K Hull Plate and 2M credits") |
| `{"cmd":"save","path":"save.json"}` / `{"cmd":"load","path":"save.json"}` | Save or restore the game |

`advance` and `away` step the engine the same way (60 s ticks; every chain on a
body runs through within a tick and cargo that lands is used in the same tick),
so a long `advance` earns what many short ones do. `away` only adds the 12 h cap
and the summary.

A bottleneck in `report` has a `kind`: `input` (a building is short of
`resourceId`), `noCrew`, `understaffed` (a building has every input but fewer
crew than its base slots, such as "Circuit Fab on Kora is understaffed: 1 of
2 crew"), `crewShortage` (habitats and base crew support fewer
crew than you have assigned, so every crewed building slows down), or
`storageFull` (a body's store of `resourceId` is at its cap and output is being
wasted), or `noSales` ("Nothing is being sold: turn on auto-sell or sell goods":
you make goods that sell and have no auto-sell rule). Each bottleneck also has
`firstSeenAt` (game time since when it has held without a break) and
`lostCreditsPerHour` (what a full store or a starved building costs an hour at
current prices, for `noSales` what your net production would sell for, for
`crewShortage` the output your crewed buildings lose against full staffing;
null for the other kinds).

### Game commands (act)

`factionId` defaults to you. Amounts that can grow large (`ratePerSecond`,
`amount`, `keepAtLeast`) are strings, such as `"0.5"` or `"1e3"`. Crew and ship
counts are plain integers.

| Line | What it does |
|---|---|
| `{"cmd":"build","bodyId":"kora","defId":"mine","depositResourceId":"silicon"}` | Build; extractors name the deposit they mine. The new building takes free crew up to its base slots (add `"autoCrew":false` to leave it empty). The reply has the new `createdId`, says how much crew it took and gives its whole recipe a second (`"At full crew it uses 0.0333 Steel and 0.0133 Circuit a second and makes 0.00333 Cargo Ship a second"`, also as `inputsPerSec` and `outputsPerSec`) |
| `{"cmd":"assignCrew","buildingId":"b4","crew":1}` | Set a building's crew (an absolute count) |
| `{"cmd":"upgrade","buildingId":"b1","track":"speed"}` | Buy one level of `speed`, `efficiency` or `capacity`. A capacity level on a crewed building fills its new slot from free crew; the reply says so (`crewAdded`), or that the slot is empty when no crew is free |
| `{"cmd":"setAutoSell","bodyId":"kora","resourceId":"steel","keepAtLeast":"100"}` | Sell everything above 100 automatically; `null` removes the rule |
| `{"cmd":"sell","bodyId":"kora","resourceId":"steel","amount":"50"}` | Sell once |
| `{"cmd":"createRoute","fromBodyId":"kora","toBodyId":"brine","resourceId":"circuit","ratePerSecond":"0.2","cargoShips":1,"stopAtDestination":"500"}` | Ship goods between your bodies; the cargo ships come from the source body's stock. `stopAtDestination` is optional: the stock Brine keeps. The route pauses while Brine holds 500 once what is on its way (on any route), less what Brine's buildings use during the trip, has landed: a long trip keeps enough in flight that Brine never runs dry, and Brine settles near 500. Brine's stock plus the cargo on its way never pass its storage cap. A level above Brine's storage cap is cut to the cap, and the reply says so |
| `{"cmd":"updateRoute","routeId":"r1","ratePerSecond":"1","cargoShips":2,"stopAtDestination":"800"}` | Change a route's rate, ships or stop level (name any of them; the rest stay). `"removeStopAtDestination":true` takes the stop level off |
| `{"cmd":"moveShips","fromBodyId":"kora","toBodyId":"brine","count":2}` | Send cargo ships to another of your bodies in the system; they land after the normal travel time |
| `{"cmd":"removeRoute","routeId":"r1"}` | Close a route; its ships return to the source |
| `{"cmd":"claimBody","bodyId":"brine","sourceBodyId":"kora"}` | Claim an unowned body; after the first claim it also takes outpost kits from the source body |
| `{"cmd":"demolish","buildingId":"b4"}` | Remove a building for half its credit cost back |
| `{"cmd":"survey","sourceBodyId":"kora"}` | Survey the next unsurveyed signal in Kora's system (`state` shows `unsurveyedSignals`), paying credits and survey drones from Kora; the body shows up when the survey ends, a few hours later. Add `"bodyId"` to pick one by id |
| `{"cmd":"expandSlots","bodyId":"kora"}` | Buy one more build slot on a body you own; each one costs more (see `costs`) |
| `{"cmd":"deliverToMegaproject","megaprojectId":"orbital_station","bodyId":"kora","amounts":{"hull_plate":"120","credits":"5e5"}}` | Hand goods (from that body) and credits to the Orbital Station's next level; deliveries add up from any of your bodies, and the one that completes the level starts its timer. While a level is being built, deliveries pay for the level after it, which then starts by itself the moment the running one is done |
| `{"cmd":"startMegaprojectStage","megaprojectId":"orbital_station","bodyId":"kora"}` | Deliver everything the next level still needs from one body at once |
| `{"cmd":"setMegaprojectAuto","megaprojectId":"orbital_station","goods":true,"creditReserve":"5e6"}` | Feed a megaproject on its own every game minute: goods from every body above what each keeps (its own use, its auto-sell `keepAtLeast`, open contract needs), and credits above the reserve (leave `creditReserve` out for none). `"goods":false` with no reserve stops it. The Mass Driver opens at Orbital Station level 1 (`state.megaprojects` shows `locked` until then, and each megaproject's `bonuses` and `nextLevel`) |
| `{"cmd":"deliverContract","contractId":"c12","bodyId":"kora","amount":"500"}` / `{"cmd":"discardContract","contractId":"c12"}` | Work the contracts board (`state.contracts`): deliveries add up and the reward is paid with the last unit; a discard costs nothing. The reply says when the next contract arrives (the soonest refill) |

Deliveries to contracts and megaprojects move whole units (rounded down; less
than 1 is refused), and what is still owed is always whole, so delivering the
amount shown completes it.

A successful command reply lists what it `spent` and `gained` (credits, and
`body/resource` amounts). `build`, `claimBody`, `survey`, `expandSlots`,
`demolish`, `createRoute`, `updateRoute`, `moveShips`, the megaproject and
the contract commands also say in a `message` what they did, with ids (a
first claim's says it needed no kits). A command on a body whose claim is
still under way fails with `stillClaiming` and the time left ("Brine is
still being claimed (25m left)"). A `depositMissing` error lists the deposits the body has, an
unknown building type lists the buildings the body can take with each one's
cost, a claim short of outpost kits says which building makes them and from
what, an upgrade track the building lacks fails with `noSuchTrack`, and a crew
request while crew is over-assigned says by how much. Moved ships can be used
at the arrival time the reply gave.

Things worth knowing:

- Upgrade tracks: `speed` makes more per second (inputs and outputs alike),
  `efficiency` cuts the inputs per output, `capacity` adds a crew slot
  (filled from free crew, if any) and some storage on the body. On a
  habitat, `capacity` adds a quarter more housing per level instead.
- Habitats need no crew. They house crew as long as they get food, water and
  oxygen. Food comes from a hydroponic farm (water and fertilizer, from
  ammonia) or a protein vat (water and hydrogen, which an electrolyzer also
  makes). Habitats have first claim on their inputs, but a habitat short of
  one claims only the share of the others it can use, so the farm still gets
  the water it needs to make the food. Crew work at the share of their number
  the same tick's housing supports (9.5 housed for 10 crew is 95%), so
  housing does not swing from tick to tick and `state` and `report` agree.
- Auto-sell never sells what the buildings on that body need for the next
  tick, or the next 10 seconds if the tick is shorter (route cargo lands in
  lots about 10 s apart), so it is safe on an input with `keepAtLeast` 0;
  `state.autoSell` shows each rule's buffer. It also never sells what your
  open contracts still need, less what bodies with no rule for the good hold:
  that is held on the body with a rule on the good that holds the most of it,
  up to its storage cap. A route out of a body
  takes its share before auto-sell sells the rest.
- Contracts ask only for goods you make now from steady supply (a stockpile
  nothing refills does not count), about 1 h (bulk), 2 h (components) or 3 h
  (advanced goods) of what your buildings make that way, and pay 3× the base
  price, between 20 minutes and 1 hour of your income (the larger of what
  auto-sell earns and what your steady production is worth, so selling by
  hand counts too) and never less than 500 credits. The very first one has no
  cap and pays at least 7,500, enough for your first claim. Food, water and
  oxygen are asked for less often.
- The market pays less as you sell more of one good, but never pays less in
  total for selling more. Raw goods bottom out very low; refined goods and
  components hold their price better, so refining and diversifying pays.

Starting position: you own Kora with an iron mine (`b1`), a copper mine (`b2`) and
a smelter (`b3`), 250 credits and 40 iron ore. Nothing sells until you sell it or
set auto-sell. The other bodies in the system are Cinder, Hollow Reach, Vastmere and
Brine (ids `cinder`, `hollow_reach`, `vastmere`, `brine`); `state` shows what each
one has before you claim it. Building types, recipes and prices are in
`content/*.json`.

### Playing to a schedule

The game is balanced for a player who checks in about 4 times a day for a few
minutes (spec §6.7). To play like that, act for a few game minutes (advance in
small steps of 10 to 60 s while you act), then step away for the rest of the 6
hours: `{"cmd":"away","seconds":21420}` after 180 s of play. `away` works like
closing the game: it caps the time at 12 h, as the real game does, and shows the
summary you would see on coming back. `advance` has no cap, so do not skip more
than 12 h at once with it if you want the real-game experience.

Write down the game time (from `state`) whenever something notable happens.

## Bot runs

Bots play the same schedule automatically and print a balance report:

```
dart run game_sim:game_sim bot --bot balanced --hours 168 --seed 1 --format md
dart run game_sim:game_sim bot --bot casual --hours 168 --format md
dart run game_sim:game_sim bot --bot greedy --hours 24 --format json
```

- `greedy` buys the cheapest affordable upgrade, building, extra slot or claim
  each decision. It is a floor: it never plans a chain, and shows that "buy the
  cheapest thing" does not win.
- `balanced` fixes the worst bottlenecks, claims bodies, auto-sells surplus, works
  toward the next milestone (and housing when crew runs out), and spends the rest on
  the best return. It plays like an attentive optimizer.
- `casual` plays like `balanced` but with at most 15 commands per check-in
  (auto-sell rules aside): the casual persona's pace.

The report shows when each milestone was first seen (check-in index and hours),
the market income of each day with each resource's share, a Days table (new things
seen per day, bodies, megaproject levels, contracts completed, contract rewards paid,
earnings from sales and contracts, and the share of sales by tier) with two pacing
lines (days with anything new, and days with a milestone or project, contracts left
out), a timeline of completed projects and contracts, dead zones (check-ins
where the bot found nothing to do), resources never produced or never used, the
final stock and credits, and the worst bottleneck at each check-in.
`docs/balance/` holds the 30-day baselines (`stage1_5-30day-*.md`); use them to
compare your experience against the bots', and rerun them after any content change.

## Personas

Play one persona per session (spec §5.2). Stay in character: a casual player does
not read the JSON content files to plan ahead; an optimizer does.

- **Optimizer.** You want the fastest possible growth. Read the content files, work
  out ratios, plan chains, check `report` and `costs` often, and push for every
  milestone as early as you can. Look for dominant strategies, exploits, upgrades
  that are never worth buying, and anything that makes the numbers stop growing.
- **Casual, 4 times a day.** You check in about every 6 hours for 2 to 5 minutes of
  game time and want each visit to have something worth doing. Use `state` and
  `report` on arrival as a "while you were away" summary, fix the top one or two
  bottlenecks, buy what you can, and leave. Play at least 7 in-game days (28
  check-ins). Note visits where nothing was worth doing, and visits that needed more
  than a few minutes to sort out.
- **Warmonger.** War arrives in stage 4, so for now play an aggressive expander:
  claim bodies as early as possible and build toward what an army would need (hull
  plates, fuel, circuits, cargo ships). Report whether expanding fast is fun or
  punishing, what you would want to attack or defend, and anything in the economy
  that would make war pointless or mandatory later.

## Report template

Write the report in plain language, under about a page. Use game time (hours since
start) for anything that happened at a moment.

```
# Playtest report: <persona>, seed <n>, <hours played> h

## Summary
Two or three sentences: how it felt overall and the single biggest issue.

## What was fun
- ...

## What was boring
- ... (with game times: "12 h to 30 h: nothing to do but wait for credits")

## Stuck points
- <game time>: what you were trying to do, why you could not, how (or whether) you
  got unstuck.

## Numbers that felt off
- <thing>: what it is, what you expected, why. ("Speed level 30 on the iron mine
  costs more than a whole day of income but adds almost nothing.")

## Bugs
- What happened, what you expected, and the exact command lines to reproduce it,
  starting from a new game: the `--seed` and the script lines (or a save file
  path).

## Suggestions
- Optional: changes you would try first, in content (`content/*.json`) or rules.
```
