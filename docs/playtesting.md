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
| `{"cmd":"state"}` | Game time, credits, crew (base, supported, assigned, free, and overAssigned: crew assigned beyond what housing supports), milestones reached, every body in the system (type, deposits and their richness, owner, build slots used/total, storage cap, and stock for the bodies you own), your routes with their ids, stop level and whether they are paused, and the market price and saturation of every good you hold. Stock of components and above (tier 2+: circuits, cargo ships, outpost kits, ...) shows whole units; the part-made unit is kept |
| `{"cmd":"report"}` | Steady per-second production, use, net flow and waste per body, credits per second (what selling one second's net output earns, not a stockpile being sold down), each building's run fraction, effective fraction (run fraction × crew / base slots × crew efficiency), crew and actual inputs and outputs, and the bottlenecks, worst first |
| `{"cmd":"costs"}` | Next upgrade cost of every track of every building, the next claim cost (or "no bodies left to claim"), and the next extra build slot on each body you own |
| `{"cmd":"advance","seconds":600}` | Let time pass (no offline cap here) |
| `{"cmd":"away","seconds":28800}` | Pretend you closed the game for 8 hours: runs offline catch-up (capped at 12 h) and shows the away summary, with credits and stock gained, units wasted to storage caps, milestones reached and the top bottlenecks, those costing the most credits an hour first, each marked "ongoing since Xh" if it was already there when you left |
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
wasted). Each bottleneck also has `firstSeenAt` (game time since when it has
held without a break) and `lostCreditsPerHour` (what a full store or a starved
building costs an hour at current prices; null for the other kinds).

### Game commands (act)

`factionId` defaults to you. Amounts that can grow large (`ratePerSecond`,
`amount`, `keepAtLeast`) are strings, such as `"0.5"` or `"1e3"`. Crew and ship
counts are plain integers.

| Line | What it does |
|---|---|
| `{"cmd":"build","bodyId":"kora","defId":"mine","depositResourceId":"silicon"}` | Build; extractors name the deposit they mine. The new building takes free crew up to its base slots (add `"autoCrew":false` to leave it empty). The reply has the new `createdId` and says how much crew it took |
| `{"cmd":"assignCrew","buildingId":"b4","crew":1}` | Set a building's crew (an absolute count) |
| `{"cmd":"upgrade","buildingId":"b1","track":"speed"}` | Buy one level of `speed`, `efficiency` or `capacity` |
| `{"cmd":"setAutoSell","bodyId":"kora","resourceId":"steel","keepAtLeast":"100"}` | Sell everything above 100 automatically; `null` removes the rule |
| `{"cmd":"sell","bodyId":"kora","resourceId":"steel","amount":"50"}` | Sell once |
| `{"cmd":"createRoute","fromBodyId":"kora","toBodyId":"brine","resourceId":"circuit","ratePerSecond":"0.2","cargoShips":1,"stopAtDestination":"500"}` | Ship goods between your bodies; the cargo ships come from the source body's stock. `stopAtDestination` is optional: the route pauses while Brine holds 500 (cargo in flight counts), so it never overfills |
| `{"cmd":"updateRoute","routeId":"r1","ratePerSecond":"1","cargoShips":2,"stopAtDestination":"800"}` | Change a route's rate, ships or stop level (name any of them; the rest stay). `"removeStopAtDestination":true` takes the stop level off |
| `{"cmd":"moveShips","fromBodyId":"kora","toBodyId":"brine","count":2}` | Send cargo ships to another of your bodies in the system; they land after the normal travel time |
| `{"cmd":"removeRoute","routeId":"r1"}` | Close a route; its ships return to the source |
| `{"cmd":"claimBody","bodyId":"brine","sourceBodyId":"kora"}` | Claim an unowned body; after the first claim it also takes outpost kits from the source body |
| `{"cmd":"demolish","buildingId":"b4"}` | Remove a building for half its credit cost back |
| `{"cmd":"expandSlots","bodyId":"kora"}` | Buy one more build slot on a body you own; each one costs more (see `costs`) |

A successful command reply lists what it `spent` and `gained` (credits, and
`body/resource` amounts). `claimBody`, `demolish`, `createRoute`,
`updateRoute` and `moveShips` also say in a `message` what was claimed,
refunded, created, changed or sent, with ids. A
`depositMissing` error lists the deposits the body has.

Things worth knowing:

- Upgrade tracks: `speed` makes more per second (inputs and outputs alike),
  `efficiency` cuts the inputs per output, `capacity` adds a crew slot and
  some storage on the body. On a habitat, `capacity` adds a quarter more
  housing per level instead.
- Habitats need no crew. They house crew as long as they get food, water and
  oxygen. Food comes from a hydroponic farm (water and fertilizer, from
  ammonia) or a protein vat (water and hydrogen, which an electrolyzer also
  makes).
- Auto-sell never sells what the buildings on that body need for the next
  tick, or the next 10 seconds if the tick is shorter (route cargo lands in
  lots about 10 s apart), so it is safe on an input with `keepAtLeast` 0. A
  route out of a body takes its share before auto-sell sells the rest.
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
the market income of each day with each resource's share, dead zones (check-ins
where the bot found nothing to do), resources never produced or never used, the
final stock and credits, and the worst bottleneck at each check-in.
`docs/balance/stage1-baseline.md` holds the 168 h baselines; use them to compare your
experience against the bots', and rerun them after any content change.

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
