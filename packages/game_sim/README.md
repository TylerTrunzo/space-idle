# game_sim

Headless CLI for the space idle engine. Reads one JSON object per line from
`--script` or stdin and writes one JSON line per input line to stdout.

```
dart run game_sim:game_sim [--content content] [--seed 1] [--load save.json] [--script file.jsonl]
dart run game_sim:game_sim check --content content   # exit 1 if content is invalid
dart run game_sim:game_sim bot --bot balanced|casual|greedy --hours 168 --seed 1 [--format json|md]
```

Game commands use the `Command.toJson` format (`build`, `demolish`, `assignCrew`,
`upgrade`, `createRoute`, `removeRoute`, `sell`, `setAutoSell`, `claimBody`,
`expandSlots`); `factionId` defaults to the player. A successful game command
replies with `spent` and `gained` (credits and `body/resource` amounts that
changed), `createdId` for a new building or route, and for `claimBody`,
`demolish` and `createRoute` a `message` such as `"Claimed Brine for 5K
credits"`. Meta commands:

- `{"cmd":"advance","seconds":N}` run the simulation for N seconds, no cap
- `{"cmd":"away","seconds":N}` simulate the player being away for N seconds
  (offline catch-up, capped at the offline limit) and print the away summary:
  seconds away and simulated, credits and stock gained, units wasted to
  storage caps, milestones reached and the top bottlenecks
- `{"cmd":"report"}` per-second flows and bottlenecks
- `{"cmd":"state"}` time, credits, crew, reached milestones, every body
  (type, deposits, owner, slots, storage cap, and stock if owned), the
  player's routes, and price and saturation of the goods the player holds
- `{"cmd":"costs"}` upgrade costs of the player's buildings, the next claim
  cost and each owned body's next extra build slot
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
`assigned`, `free`).

Bottlenecks in `report` carry a `kind`: `input` (short of `resourceId`),
`noCrew`, `crewShortage` (habitats and base crew support fewer crew than
are assigned, so every crewed building slows; `bodyId` and `buildingId` are
null), or `storageFull` (`resourceId` is at the body's storage cap and
output is being wasted; `buildingId` is null).

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

`docs/balance/stage1-baseline.md` holds the 168 h baselines of all three
bots; rerun them after changing `content/*.json` and compare.

