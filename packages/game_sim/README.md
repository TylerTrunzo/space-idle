# game_sim

Headless CLI for the space idle engine. Reads one JSON object per line from
`--script` or stdin and writes one JSON line per input line to stdout.

```
dart run game_sim:game_sim [--content content] [--seed 1] [--load save.json] [--script file.jsonl]
dart run game_sim:game_sim check --content content   # exit 1 if content is invalid
dart run game_sim:game_sim bot --bot balanced --hours 168 --seed 1 [--format json|md]
```

Game commands use the `Command.toJson` format (`build`, `demolish`, `assignCrew`,
`upgrade`, `createRoute`, `removeRoute`, `sell`, `setAutoSell`, `claimBody`);
`factionId` defaults to the player. Meta commands:

- `{"cmd":"advance","seconds":N}` run the simulation
- `{"cmd":"report"}` per-second flows and bottlenecks
- `{"cmd":"state"}` time, credits, owned bodies and their stock
- `{"cmd":"costs"}` upgrade costs of the player's buildings and the next claim cost
- `{"cmd":"save","path":"save.json"}` / `{"cmd":"load","path":"save.json"}`

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
actual `inputs` and `outputs`. `state` also gives the player's crew totals
(`base`, `supported`, `assigned`, `free`).

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

- `greedy` buys the cheapest affordable upgrade or building each decision.
- `balanced` fixes the worst bottlenecks, claims bodies, auto-sells surplus,
  works toward the next milestone (and housing when crew runs out), and
  spends the rest on the best return.

`docs/balance/stage1-baseline.md` is the balanced 168 h baseline; rerun it
after changing `content/*.json` and compare.

