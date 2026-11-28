# Playtest round 4: findings and decisions

Two subagent personas played the stage 1.6 economy (head 5763bad):
- **Casual:** 4 check-ins a day, 21 days, seed 2 ([casual.md](round4/casual.md)). Used a "buy max" helper each
  check-in, as the stage 2 app's buy-max button will let every player do.
- **Optimizer:** 7 a day, 14 days, seed 1 ([optimizer.md](round4/optimizer.md)).

## 1. What stage 1.6 fixed

| Round-3 problem | Casual | Optimizer |
|---|---|---|
| The game flattens | Better early, same late | Better, not fixed |
| Station deliveries as a chore | Fixed | Fixed |
| Contracts pay for no effort | Honest rewards, still effortless | Share fine, still effortless |
| Silent crew crash, flicker | Fixed (never happened) | Not reached |
| Hidden logistics rules | Better, new hidden ones | Better |
| Requirements one failure at a time | Fixed | Fixed |
| `report` credits/sec | Accurate, new confusion | Better |

Best moments in both: returning to several station and Mass Driver levels finished overnight with no hauling; day-1
and day-2 upgrade sprees; the catalog planning whole chains; new buildings restarting the cheap end of the upgrade
curve.

## 2. What is still wrong, ranked

1. **Megaproject levels stop paying back.** Station levels cost ×2.5 credits for ×1.25 depth (+7–16% income): payback
   35 h at L8, 200 h at L12, over 1,000 h at L14. Each level reopens a short window of upgrades, then nothing for days.
   Optimizer flat from day 10, casual growing only about 7% a day after day 14; both would quit around days 8–12.
2. **The Mass Driver's bonus is nearly worthless:** +0.4–1% income per level, because tier 0–1 markets are saturated and
   tier 2 makers bind. The even credit split hands it half the credits anyway.
3. **The pacing bot models the wrong player.** A buy-max casual runs about 1,000× ahead of the casual bot (station L1 on
   day 2 vs target days 4–6; all 56 milestones by day 21). Stage 2 ships buy-max.
4. **The away summary misleads:**
   - false 0% input bottlenecks after any step that isn't a whole game minute (two days spent "fixing" a fine route);
   - per-building duplicates fill the top 3 and hide bigger causes (17 identical dock rows; 1.29B waste unseen);
   - a megaproject diverting a top export (income 1.65M → 1.01M/s) is not flagged;
   - `keepAtLeast` silently blocks auto-delivery;
   - the next goal names a megaproject the player chose not to fund.
5. **Hidden route throughput:** each ship carries 10/s, and a route can't deliver faster than destination cap ÷ trip time.
   The two biggest gains of the casual run came from discovering these.
6. **Contracts are never a decision:** nearly every reward sits at the 20-minute income floor for goods already in stock
   (24K copper ore for 2.08B; 24 cargo ships for 6.29B).
7. **Goods auto-delivery feeds stages whose credits are days away**, starving sales; credit auto-pay sweeps everything
   above the reserve and starves upgrades that would pay back in minutes.
8. **Crew is irrelevant after day 2:** habitat capacity is far too cheap (64 levels for 200K: +320 crew).
9. **Bugs:**
   - a project completes one tick after its finish time ("still being claimed (0s left)");
   - delivery progress rounds away the last unit ("30K of 30K" while 1 is owed);
   - float noise in the headline ("net +0.59 credits");
   - depots report runFraction 0;
   - buildings built with new habitats show "0 of N crew" for a tick;
   - `report` overstates credits/sec by up to about 20% right after a big upgrade spree.

## 3. Decisions (controller, under the owner's "make executive choices")

- **E1. Megaproject value.** Retune so each station level costs about 1–2 days of income and pays back in 1–3 days
  through day 21 for the optimizer: lower credit growth (toward ×1.8–2.0) and/or raise the depth factor. Add milestones
  past 1T (3T, 10T, 30T) and station/MD levels 12, 15, 20.
- **E2. The Mass Driver speeds up what binds:** production speed for tier 1–2 makers (plate press, circuit fab, magnet
  works, refineries), chosen and measured on saved mid-game states (target ≥ +3% income per level mid-game).
- **E3. Auto-pay and auto-feed get two simple controls:**
  - a per-megaproject credit **share weight** (default equal) instead of a forced even split;
  - goods feeding mode **"when near ready"** (default): goods feed a stage once its remaining credits are covered or
    will be within 12 h at its auto-pay rate; "always" stays available.
- **E4. Away summary honesty:**
  - bottleneck input checks use the same fraction over a partial-minute step as over a full one (no false 0%);
  - bottlenecks are grouped by cause (body + resource + kind) with summed credits lost, and waste and storage-full
    compete for the top 3;
  - a new typed `megaprojectDiversion` bottleneck when auto-delivery takes a share of a good's sales, with credits/hour;
  - a typed reason when a keep rule blocks auto-delivery;
  - the next goal skips megaprojects with no auto-pay and no player funding, and considers the next milestone.
- **E5. Route throughput visible:** `state` shows each route's effective limit (rate, ships × capacity, destination
  room ÷ trip) and which one binds; a route-limited bottleneck names it.
- **E6. Contracts become a decision:** quantity sized so its sale value is worth about 10–30 minutes of income (capped
  by total storage across bodies), reward a multiple of sale value; the flat income floor drops to about 5 minutes.
  Bundles and faction buyers wait for stage 3.
- **E7. Buy-max as a game command:** `BuyUpgradesCommand(factionId, budget)` buys the best-value upgrades cheapest
  first, the same command the app's button will send. The casual bot uses it once per check-in. Pacing targets move to
  this bot.
- **E8. Crew matters a little longer:** habitat capacity costs grow faster (content), checked against both bots.
- **E9. The bugs in §2.9.**
- **Deferred:**
  - market wall content (tier 4 recipes, faction buyers, regional demand): stages 3 and 5;
  - research: stage 3;
  - market saturation and payback UI: stage 2 (already planned).

## 4. Pacing targets for stage 1.7 (seeds 1–3)

- **Buy-max casual bot:**
  - station L1 on days 3–5;
  - a milestone or project on ≥ 5 of every 7 days through day 21;
  - no gap > 3 days with neither megaproject levelling through day 21;
  - income at day 21 ≥ 1.5× day 14.
- **Balanced bot:** income +20% from day 7 to day 14 and +10% from day 14 to day 21; a station level at least every
  3 days through day 21.
- **Contracts:** ≤ 15% of earnings on days 1, 7 and 14 for every bot; no reward above 1 h of income (first excepted).
- **Mass Driver:** a level raises balanced income by ≥ 3% on days 5–14.
