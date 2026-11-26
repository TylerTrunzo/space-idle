# game_sim

Headless CLI for the space idle engine. Reads one JSON object per line from
`--script` or stdin and writes one JSON line per input line to stdout.

```
dart run game_sim:game_sim [--content content] [--seed 1] [--load save.json] [--script file.jsonl]
dart run game_sim:game_sim check --content content   # exit 1 if content is invalid
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
