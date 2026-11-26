# Playtest round 2: Brand-new player, seed 51

## Persona and run
- I read only `docs/playtesting.md` and the `game_sim` README. I never read the content files or the spec. One attempt to list the content files was blocked by the permission classifier, so everything after that was guesswork, which is the point of this persona.
- Seed 51, game time covered: 0 to 24.0 h (86,430 s).
- Active play: about 2 h in 30–300 s steps with `state`/`report`/`costs` between them.
- Check-ins: about 14 `away` calls in total, 7,000–11,400 s each. Each had a few seconds of actions around it.
- Final state: 995K credits, 14 slots on Kora, 8 on Hollow Reach, 2 bodies owned.
- Scratch dir: `/tmp/claude-0/-home-user/7963d8b4-7ef1-5bbc-9bff-b2b24979e3ee/scratchpad/pt2-newplayer/`.
  - `script.jsonl` holds my commands. It misses some early lines, so treat it as approximate.
  - `cur.json` is the final save.
  - `run.sh` and `buy.py` are the helper scripts.

## Timeline highlights (game time, what I did, how it felt)
- **0:00** I called `state`. The screen has no building list, no goal, no hint, and `milestones` is empty. The market only lists iron ore. It is not obvious that nothing sells until I act (the guide says so). I only know what b1/b2/b3 are from `report`.
- **0:01** I tried `sell steel`, which paid about 6 each, and then set auto-sell. This was the first satisfying step.
- **0:02** I bought a mine speed upgrade for 50 credits. Output went from 0.40 to 0.44, a 10% gain. The ore mine only feeds the smelter, so the upgrade did almost nothing for credits. A new player cannot tell a good purchase from a wasted one.
- **0:03–0:15** I discovered that `build` needs a `defId`. The only defIds I knew were the ones in the guide text. `mine` needs `depositResourceId`, and its error is helpful because it lists the deposits. New buildings start with no crew, and the `noCrew` bottleneck message ("Smelter on Kora has no crew") is clear and good. I built mine + smelter pairs: 4 credits/s at 0:08, 6.4/s at 0:15.
- **0:20** I claimed Hollow Reach for 5K. It felt like a real event. The `First Claim` milestone appeared only later, on my next `state`.
- **0:27** I hit three walls at once:
  - Crew was at 19/20.
  - Kora was full at 12 slots.
  - The next claim costs 65K plus 2 outpost kits, and I don't know how to make kits.
  - A `habitat` build fails with "Needs 1 Habitat Module on Hollow Reach", and I don't know how to get one.
- **0:30–2:00** I bought 100–400 credit upgrades, 5–10% each. Income went from 9.6/s to 17/s over 1.5 h. It felt like treading water. The `storageFull` warnings for iron ore (wasted output) were my own doing: I upgraded mines faster than the smelters.
- **1:00** I got the `Ten Thousand Credits` milestone, a small joy.
- **2:00–4:00** I guessed `electrolyzer` correctly and built it for 400. It does nothing, because it needs Water and I know of no source. This was a pure beginner trap.
- **3:57** I spent 50K on an extra Kora slot, which felt good. About 1.5 h later I spent 125K on a second one. The price rise (50K to 125K, with 313K next) was not shown at the moment of purchase, and I regretted it.
- **4:00–4:20** Only by guessing defIds did I find `circuit_fab`, then `wire_mill`, then `wafer_fab`. This is when income finally moved: the circuit chain started and `creditsPerSec` read 54/s.
  - Crew (20, no habitat) blocked each step. I demolished and re-crewed mines to make room.
  - Wire and wafers piled up (760 and 453 units) until I set auto-sell on them.
- **8:00–10:00** I guessed `shipyard` and built it. Cargo ships sell for about 100 each, and a route works. The 2 outpost kits for the next claim still never appeared. I turned off my own copper mine by mistake and lost income for a check-in.
- **10:00–24:00** Income was flat at about 13.7–18/s (96K per 7,000 s) until a final bump to about 24/s. Credits piled up to 995K with nothing to spend them on. The slot cost is 313K, the claim is 65K but blocked by kits, and I know no other building.

## Fun
**Best moments:**
- First sale of steel, 6 credits each (0:01).
- The clear `noCrew` message, with the building named (0:03).
- First claim at 20 min.
- The "Ten Thousand Credits" milestone.
- Finding `wire_mill`, `wafer_fab` and `circuit_fab` by guessing, and seeing the chain work. This was the single biggest moment of the day, but it came 4 h in, by luck.
- Getting 100 credits for a cargo ship.

**Worst moments:**
- Not knowing what buildings exist. I blind-guessed about 50 names, and the unknownDef error offers no list. This is the main failure for a brand-new player.
- Walls with no explanation:
  - 65K claim cost plus 2 outpost kits.
  - Habitat needs a "Habitat Module".
  - Electrolyzer needs "Water".
  - Circuit fab needs "copper wire" and "silicon wafer".
  - Each is only discovered when a `report` bottleneck names an input, with no hint of where it comes from.
- Upgrades that give +10% for 50 credits, then +3% for 300 credits. They look cheap and feel useless.
- Hoarding 995K credits at 24 h with nothing meaningful to buy.

## Where I'd quit, and why
- **First 5 minutes:** about 2 in 10 new players would leave right after the `state` dump. It is a wall of JSON, with no goal, no building list, and credits/sec showing 0.
- **About 0:30:** crew cap, slots full and a 65K claim cost. A real player's reaction would be "I have 3 buildings of each kind and nothing to do." I would leave here if I had no way to look up recipes.
- **About 4 h:** this is the real quit point for most players. I only kept going because I guessed `wire_mill` and `circuit_fab`.
- **Day 1 evening (about 10–24 h):** flat 14–18 credits/s, nothing visible to buy. A player who has not found the chain would uninstall.

## Length and retention findings
- **Away summary:** it is accurate but flat. "Credits gained 96K, wasted 11.9K" tells you nothing about what you could do next. A summary that says "you could now afford X" would help.
- **Away summary clarity:** `topBottlenecks` in the summary kept showing a broken electrolyzer and idle smelters I never fixed. The same stale warnings 8 times in a row is nagging, not guidance.
- **Goals:** only two milestones appeared in 24 h. There is no short-, medium- or long-term goal on screen.
- **Hidden info:** claim costs and extra-slot costs appear only in `costs`. The cost of a new building is shown only after buying it (100, 150, 400, 600, 1K).
- **Retention pull:** a returning player needs a reason like "your cargo ship batch finished" or "prices recovered". Nothing in the output tells me I missed something.
- **Day-1 shape:** minutes 0–30 have strong growth, 30 min–4 h is a plateau, and after the chain is found there is a second plateau. A player who finds the chain early (1 h) would have a much better day.

## Pacing and numbers

| Game time | Credits/sec (realised) | Bodies | Milestones / events |
|---|---|---|---|
| 0:00 | 0 (nothing sells) | 1 | start, 250 credits |
| 0:03 | 1.2 | 1 | first sells + 1 upgrade |
| 0:15 | 6.4 | 1 | mine+smelter pairs, Kora slots full |
| 0:20 | 6.2 | 2 | claim Hollow Reach (5K) |
| 0:27 | 9.6 | 2 | crew cap 19/20, next claim 65K + 2 kits |
| 1:00 | 13 | 2 | 10K credits milestone |
| 2:00 | 17 | 2 | upgrades only; storage waste on iron |
| 4:00 | 16.5 | 2 | extra slot 50K, circuit chain found |
| 8:00 | 18.8 | 2 | shipyard found; 208K credits |
| 12:00 | about 14 | 2 | my crew mistake cost income |
| 17:30 | about 14 | 2 | 683K credits, flat |
| 24:00 | about 24 | 2 | 995K credits, nothing to buy |

- **Cliffs:**
  - 5K claim to 65K claim plus kits is a 13x jump.
  - Slot costs go 50K, then 125K, then 313K (2.5x each). Each slot buys little.
  - Crew is capped at 20 until a habitat, which needs a module nobody told me about.
- **Upgrade ROI:** the first speed upgrade gives +10%, and by level 4–5 each gives about +3% for 200–370 credits. In my 1–2 h spree, I spent about 6K on roughly 35 upgrades for +1 credit/s.
- **Report vs reality:** `creditsPerSec` in `report` read 29–54/s while real income was 17–24/s. I did not find the reason.

## Bugs and rough edges
- **`creditsPerSec` mismatch:** after building the circuit chain (at about 4:10), `report` showed 54.4/s, but the following away windows earned 17–19/s. Repro: play to about 4:10 with a wire_mill + wafer_fab + circuit_fab on Kora, then compare `report` against `away` (script in `script.jsonl`, save `cur.json`).
- **Market list:** `state` shows prices only for goods I hold. Steel, circuit and cargo ship prices never appeared before I held them, so you cannot judge what to make.
- **Error text:** `unknownDef` gives no list of valid defIds; `cannotAfford` for a claim names kits but not how to make them.
- **Silent price escalation:** `expandSlots` spent 125K with no confirmation or preview.
- **Away summary:** `milestonesReached` was empty in every away window, even though `First Claim` shows in `state`. It seems to only report milestones reached during the away period, so something I hit during active play never shows up.
- **Crew assignment:** `assignCrew` to a 2-slot building failed with "you have 0 free" and gave no hint of where to find crew (it is on other buildings).

## Top 10 ideas (ranked)
1. **Building catalog command** (stage 2 UI, S). A "Build" menu listing every building with cost, inputs, outputs, slots and crew. This directly serves production-line optimisation, and without it the player is blind. At minimum, list valid ids in `unknownDef`.
2. **First-hour guided goals** (stage 2 UI, M). A visible "next goal" that changes: sell steel, assign crew, build a second smelter, claim a body, find circuits. The goals teach the chain and give numbers a reason to grow. See the onboarding list below.
3. **Recipe discovery in context** (stage 2 UI, M). Clicking a bottleneck like "needs Copper Wire" should show which building makes it and a "build it" button. This solves the electrolyzer and circuit-fab dead ends.
4. **Show prices of all goods and "worth per hour"** (stage 2 UI, S). The player should see that a circuit is worth about 100x ore before building, which makes ratios and upgrades a decision.
5. **Upgrade previews** (stage 2 UI, S). Show "+10% output, payback 8 min" next to each upgrade and sort by payback. This makes upgrades a real optimisation choice instead of a coin flip.
6. **Make the second claim reachable** (stage 1 content, M). Either lower the 65K + 2 kits, or show the full kit recipe path as a goal. Slow building needs a visible next body.
7. **Better away summary** (stage 2 UI, M). "While you were away: 96K credits (+14%), 3 ships built, Kora iron full for 2 h. You can now afford: a slot (50K)." Stop repeating stale warnings. Highlight things you can act on.
8. **Crew/habitat early path** (stage 1 content, M). Crew at 20 is the first hard cap. Make the habitat a first-hour goal with a clear recipe, or raise base crew a little.
9. **Escalation warning on slot/claim purchases** (stage 2 UI, S). Show the next price when buying, and confirm large spends. Avoids the 125K regret.
10. **Mid-game sinks and long goals** (stage 3-5, L). With 995K credits and nothing to buy at 24 h, add real money sinks: more bodies, research, ships, and production tiers. Avoid padding or pay-to-skip. Prefer goals that deepen ratios (e.g., "run circuits at 90% efficiency on both bodies").

## What the stage 2 app should show or teach, moment by moment
- **Minute 0:**
  - Show the three starting buildings by name with a one-line description ("Iron mine: digs ore").
  - A single highlighted goal: "Sell some steel" with a button.
  - Explain that nothing sells until you sell it, and offer auto-sell as a toggle.
  - Show credits/sec in big type.
- **Minute 1–5:**
  - Goal: "Build a second smelter" and show the build menu. Show costs before buying.
  - After building, show "Assign crew" as a prompt, not a hidden step. The `noCrew` message is already good; make it a button.
  - Mark upgrades with their payback so the player knows speed on a mine feeding a full smelter does nothing.
- **Minute 5–20:**
  - Goal: "Reach 5K to claim a body." Show a progress bar, the choice of bodies and what each offers (deposits).
  - Show that Kora's slots are limited and what a slot costs.
- **Minute 20–30 (claim done):**
  - Congratulate and show the milestone immediately.
  - Goal: "Build on your new body." Explain deposits per body, and which mines can mine what (Water Ice needs a different building).
  - Warn when crew is almost out (19/20) and show where crew comes from.
- **30 min – 1 h:**
  - Introduce the second tier: "Refined goods sell for more. Try circuits." Show the full chain (copper -> wire, silicon -> wafer, then circuit) as a tree with checkmarks.
  - Teach the unit "run fraction" in plain words, and explain the storage-full warning.
- **1 – 2 h:**
  - Explain why more upgrades have diminishing returns and show the best-payback upgrade.
  - Show the 10K milestone and the next medium goal (habitat, shipyard, outpost kits).
  - Show the habitat requirement before the player hits it.
- **First away (1–2 h later):**
  - Summary with credits gained, what is full or idle, and a "recommended next action".
  - No repeated warnings for things the player has deliberately ignored.
- **Rest of day 1:**
  - A "goal ladder" with a short-term (next 10 min), medium-term (next body) and long-term (full chain on 3 bodies) goal visible together.
  - When credits pile up with no sink, say what the next real target is (outposts, routes) instead of leaving the player with 995K idle.
  - Do not use daily streaks or punishing timers.
