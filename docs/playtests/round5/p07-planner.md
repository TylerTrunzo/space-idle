# Playtest round 5, tester #7: Contract and megaproject planner (seed 7)

Repro saves for the bugs below are in `docs/playtests/round5/repro/p07/`.

## Persona and run
- **Seed and length:** seed 7, game time 0 h to 174.5 h (day 7.3). I stopped there because my questions were answered.
- **Check-ins:** about 36 on the main line, at 5 a day (4.8 h `away` each). The first 29 h I played by hand.
- **What I automated:**
  - helper scripts that wrap each check-in: away, then state, report and costs, then deliver contracts, pay megaprojects, and run buy-max;
  - about 25 forked runs from five saved states, each one day long with 4–5 scripted check-ins, to measure the megaproject settings against each other.
- **Adopted forks:** the main line took the winning fork at 29→48 h, 48→72 h, 72→96 h and 125→150 h.
- **Wanting to automate is a finding in itself.** By day 4 every check-in was the same five commands.

## Timeline highlights
- **0 h:** the first contract asked for 1K Copper Ore for 7.5K. I took my Wire Mill's crew off to fill it faster. That was a real small decision, and a nice hook.
- **9–17 h:**
  - a steel order of 3.2K was bigger than my 1.8K store, so it took two deliveries;
  - the circuit (138K) and hull (135K) orders paid about 3× sale value, which felt fair.
- **17 h:** the first habitats raised crew from 20 to 80. Buy-max then put 28 crew into two nickel mines selling at 0.17, and 16 into ice drills.
- **24 h:** a magnet order (7.4K for 621K) would have taken every magnet for 7 h while the station chain needed them. I discarded it. That was the first real contract decision.
- **24 h:** I turned on station auto-pay (goods near-ready, credits on, reserve 0). It swept every credit.
- **29 h: the biggest finding of the run.** Forks from the same state:
  - keeping auto-pay on: 384 credits/s at 48 h;
  - spending everything on buy-max for two check-ins, then auto-pay: **6.19K/s**, and station level 1 still came at the same time (~43 h).
  - The game's ETA ("station in 9h 38m") gave no hint of this.
- **28.9 h:** my own `keepAtLeast 1000` on drones and cores (meant to stop them selling) blocked station delivery. `keepBlocksDelivery` caught it.
- **48 h:**
  - a station-segment order (1.9K for 5.7M) held 1.3K segments the station needed. I worked out by hand that the docks would remake them before the station's 86M credits came in, so I delivered it. It was a good decision, but only with math the game doesn't show.
  - Mass Driver goods (5K hull, 20K wire, 10K water, 2K wafers) all arrived within 5 game minutes. The goods mode didn't matter.
- **72 h:** contract rewards were now minutes of income (a 13M order against 300M/h).
- **96 h:** 2 station docks were at speed level 45 and running at 0%, because a circuit route was set to 0.6/s. One `updateRoute` took segments from 0.08 to 7.2 a second.
- **106–125 h:**
  - a reactor-core order (34K for 458M) held 3.84K cores the station needed, while my Reactor Works starved on a 0.1/s route. I discarded it.
  - Orders of 130K–220K units took 4–5 check-ins each, because each delivery is capped by the 26.8K store.
- **150–174 h:**
  - station level 12 costs 41B credits plus 410K segments, about a day of income, as round 4 targeted (E1);
  - income grew about 16% a day;
  - every check-in was identical.

## Day by day
| Day | Credits/s (end) | Bodies | Station | Mass Driver | What was new | Mood |
|---|---|---|---|---|---|---|
| 0 | 221 | 5 | 0 | – | chains, claims, habitats, first contracts | 4 |
| 1 | 6.19K | 5 | 2 (L3 under way) | 0 | the auto-pay trap found by forking | 3 |
| 2 | 84.8K | 5 | 3 | 1 | Mass Driver opens; goods trivial; numbers explode | 4 |
| 3 | 163K | 5 | 4 | 6 | megaprojects cheap now; route rate fix ×90 | 4 |
| 4 | 345K | 5 | 7 | 10 | contract holds against the station; route whack-a-mole | 3 |
| 5 | 538K | 5 | 10 | 11 | weights matter (−17% for the wrong one) | 3 |
| 6 | 624K | 5 | 11 (L12 paid) | 11 | nothing; station levels now cost ~1 day | 2 |
| 7.3 | 650K | 5 | 11 | 11 | – | 2 |

## Megaproject settings measured (forks, one day each)
| From | Setting | Credits/s a day later | Levels |
|---|---|---|---|
| 29 h | auto-pay everything (reserve 0) | 384 | St 1 |
| 29 h | buy-max with all credits for 2 check-ins, then auto-pay | **6,190** | St 2 |
| 29 h | reserve 1.5M used as the buy-max budget | 1,640 | St 1 |
| 48 h | buy-max only | 79.6K | St 3, MD 0 |
| 48 h | Mass Driver L1 paid by hand (8M), buy-max the rest | **84.8K** | St 3, MD 1 |
| 48 h | auto-pay everything, equal weights | 8.5K | St 4, MD 5 |
| 72 h | buy-max only | 113K | – |
| 72 h | auto-pay everything (5.1B credits sat idle: the station was walled on segments) | 128K | St 4, MD 7 |
| 72 h | pay by hand, buy-max the rest | **163K** | St 4, MD 6 |
| 125 h | buy-max only | **543K** | St 8, MD 11 |
| 125 h | auto-pay, station weight 10 / MD 1 | 538K | St 10, MD 11 |
| 125 h | pay by hand, station first | 536K | St 10, MD 11 |
| 125 h | equal weights, or by hand with MD first | 506K | St 9, MD 12 |
| 125 h | MD weight 10 | 452K | St 8, MD 12 |
| 125 h | station goods "always" instead of near-ready | 527K | St 10 |

**What these show:**
- **Settings a sensible player ends up with:**
  - credit auto-pay OFF (or an enormous reserve) until about day 3;
  - then auto-pay ON, station weighted well above the Mass Driver;
  - goods near-ready;
  - an auto-pay reserve of about 1 h of income, which works as buy-max's wallet: auto-pay refills the reserve before paying projects, so buy-max at each check-in spends it.
- **The defaults are not this.** Auto-pay with reserve 0 and equal weights is the worst sensible choice on days 1–3. It cost 10–16× in income and gained nothing in station timing.
- **Weights are a real choice with a 17% swing on day 5.** The game shows nothing that points the right way. A Mass Driver level is ~4.8% on tier 1–2 sales. A station level now gives more, but which wins changes by day.
- **Goods modes are almost cosmetic:**
  - Mass Driver goods arrive in minutes;
  - near-ready vs always on the station is a 2% difference.
- **By hand vs auto-pay:**
  - by hand wins early, because it leaves credits for buy-max;
  - after day 4, auto-pay with a reserve is equal or better, because hand-pay can only queue one level ahead while stages take 4–6 h.

## Contracts
- **Days 0–2: real decisions.**
  - Pause a mill to fill an order faster.
  - Discard a magnet order that would starve the station.
  - Deliver a segment order after working out the regrowth.
  - Rewards were 3× sale value, a fair premium.
- **From day 3: income coupons.**
  - The 30-minute income floor dominates: day-6 orders paid **113×** sale value for magnets (210K magnets worth 9.8M paid 1.11B), 10.8× for drones and 5.1× for segments.
  - Every order pays about the same 25–35 minutes of income, whatever the good or size, so "pick contracts by value" is not a choice.
  - The only decision left is "does it hold goods my megaproject needs?", and the answer comes from off-screen arithmetic.
  - Contracts were about 6% of earnings per day.
- **Timing:** the board refilled steadily, but day 5+ orders (130K–220K) need 4–5 check-ins of store-capped deliveries. That was a chore. Already known: oversize orders, the "1 still owed" last unit, and holds that block near-ready feeding (I met all three).

## Fun, length, coming back
- **Fun:** Fun peaked when a fork showed a ×16 difference, and when one route fix took station segments from 0.08 to 7.2 a second (×90). Both were discoveries, but the game hid both. Contracts were fun only on days 0–2.
- **Length:** From day ~5 the only goals are megaproject levels, at about one a day. Every check-in is: deliver contracts, buy-max, leave. My planner horizon ran out on day 6.
- **Coming back:** I'd come back for a planner's view: "Station L12: credits 21 h, segments 12.8 h (binding), drones 1.1 h". I built that table by hand from `report`. A "what changes if I fund X instead" view would be the decision I came for.

## Best and worst moments
- **Best:**
  - the 29 h fork result;
  - the day-2 segment-order judgement call;
  - day-2 numbers going ×14.
- **Worst:**
  - discovering that the sensible-looking default (auto-pay everything) had cost me 94% of my growth, with nothing on screen saying so;
  - a dock at speed level 45 running at 0% for two days.

## Where I'd quit
Around day 6–7. Every check-in was the same five commands. Contracts were flat income coupons. The only open question was weights, and I could only answer it by forking the save, which a player can't do.

## Round-4 problems I met
- **E1, megaproject value:**
  - **better late:** station level 12 costs about a day of income;
  - **worse early:** on days 1–2 levels are ruinous against buy-max, whose payback is 1–2 h;
  - on days 3–4 they are cheap (minutes of income).
- **E2, Mass Driver:**
  - **fixed:** a level gives +4.8–6.5%;
  - but its goods are trivial, and weighting it up loses to the station by day 5.
- **E5, auto-pay and next goal:**
  - weights and `megaprojectDiversion` work, and `keepBlocksDelivery` caught my keep trap;
  - still, the reserve is the only buy-max lever (already known);
  - and nextGoal named "Thirty Billion" when credits were on with a 1Qa reserve.
- **E6, contracts:**
  - **better on days 0–2;**
  - **same as round 4 from day 3:** the reward floor makes them effortless coupons.

## Bugs
1. **Near-ready feeds goods when auto-pay can give the stage nothing.**
   - Setup: station on near-ready with credits on, reserve 1e15, holding 2M of the 86M owed.
   - Result: `goodsFedNow: true`, and segments go to the station at 0.077/s instead of selling.
   - Repro: `printf '{"cmd":"state"}\n' | dart run game_sim:game_sim --seed 7 --content content --load docs/playtests/round5/repro/p07/nearready_reserve.json`
   - Look at `megaprojects[0].auto.goodsFedNow`.
2. **Buy-max's crew-fill rule overpays.** (A variant of the known crew sponge, with a figure.)
   - Result: 5.43M of a 5.5M budget went on 12 capacity levels at 481–500K each, mostly on mines whose raw ore sold for 0.01–0.6. The cheapest level was 80K.
   - Repro: load `docs/playtests/round5/repro/p07/buymax_crewfill_48h.json`, then send `{"cmd":"buyUpgrades","budget":"5.5e6"}`.
3. **Contract reward description vs reality (a design or doc mismatch).** The brief says "about 3× sale value", but day-6 orders paid 5–113×, because of the 30-minute income floor.
4. **The natural hoarding move blocks megaprojects (a UX trap).** A high `keepAtLeast` on megaproject goods blocks delivery. Keep 0 is the safe value, since megaproject holds are automatic, but nothing tells you that. The warning does fire.

## Top 5 changes
1. **A megaproject schedule view, in two parts.** Effort M. Serves slow building as anticipation, and optimization made visible.
   - Per stage: ETA for each input with the binding one marked, e.g. "L12: credits 21 h, segments 12.8 h ← binding", plus the next 2–3 levels.
   - "Income a day from now" under each funding choice: this level, buy-max, or the other megaproject.
   - Stage: now (engine numbers), then stage 2 (UI).
2. **Make auto-pay a share, not a sweep.** Effort S/M. Turns a trap into a lever.
   - Options: "auto-pay X% of income" or "auto-pay at most N levels ahead", with the reserve renamed "buy-max wallet".
   - The default should be credits off until the player turns it on, or a 50% share. Reserve 0 with equal weights cost me 16× on day 1.
   - Stage: now.
3. **Contract rewards scale with the good's value and difficulty again.** Effort S. Makes contracts a real choice again.
   - Drop the 30-minute floor after the first few days, or make it 30 minutes of *that good's* production value.
   - Size orders to storage, or allow "deliver whenever in stock" auto-delivery.
   - Add a "costs your Station X hours" line when an order holds megaproject goods.
   - Stage: now.
4. **Tell the player when a megaproject level is worse than upgrades.** Effort S. Serves the big-numbers pleasure.
   - Example: "Mass Driver L12 pays back in 34 h; upgrades in 3 h."
   - Show a weight suggestion, or the payback of each project's next level.
   - Stage: now (engine), then stage 2.
5. **Flag a starved, upgraded building chain as a hidden fortune.** Effort S. Serves optimization.
   - Example: "Station Docks at speed 45 run 0%: one route rate change = ×90 segments."
   - The report has the data. The away summary should lead with this, not with credit milestones.
   - Stage: now. In stage 3, cargo ships and logistics captains could own this, and pirates raiding a route would make route capacity a real decision.
