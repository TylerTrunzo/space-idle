# Content

The game's data, validated at load by `game_core` (`dart run game_sim:game_sim check`).

## Economy at a glance

- **Markets.** Raw (tier 0) and refined (tier 1) goods have shallow markets and floors near zero: they
  pay early, but bulk sales earn almost nothing. Components (tier 2) and advanced goods (tier 3) have
  deep markets, so late income comes from them and is spread over several goods, because each market
  pays less per unit the more of it is sold. Orbital Station levels deepen every market ×1.25 a level,
  compounding (×1.95 at level 3).
- **Upgrades.** Speed and capacity on a building share one counter: each speed or capacity upgrade
  makes the next one of either 17% pricier, so the order you buy them in hardly matters, and one more
  crew never pays back more than about 1.7× faster than a speed level (capacity's base is 6× speed's).
  Efficiency counts on its own (×1.2 a level) and stops at 25% of inputs, shown as maxed.
- **Crew.** A habitat's capacity levels raise its housing and its food, water and oxygen use alike
  (+25% each a level), so every crew costs the same upkeep.
- **Equipment.** Outpost kits, habitat modules and cargo ships are for use, not trade: markets one unit deep,
  and their makers have no speed or capacity track. Each maker makes a steady 36–72 every 6 h; more
  needs another building. Claims after the first cost 5 + 5 × (bodies owned − 1) kits.
- **Contracts.** An order asks only for a good your buildings make now from steady supply (never
  from a stock nothing refills), at least `minQuantity / quantitySeconds` a second (1 h for bulk
  goods, 2 h for components, 3 h for advanced goods), so neither a trickle nor a stockpile gets one.
  It asks for as much as sells, at today's price, for 10 to 30 minutes of your income
  (`quantityIncomeSecondsMin` 600 and `quantityIncomeSecondsMax` 1800, rolled for each order), so
  filling it gives up real sales: a decision, not a formality. It never asks for more than a day
  of what you make of it (`quantityProductionSecondsMax` 86,400, gross: habitat modules and cargo
  ships, made a few dozen at a time, would otherwise be asked for in thousands), nor more than your
  bodies can store together (an order can be filled from several; auto-sell holds its goods back on
  the bodies with a rule for the good: first all they hold, so none of what is owed sells, then room
  for the rest, the fullest body first, each up to its cap), nor less than `minQuantity`.
  A good is asked for only if its largest possible order (the least of what your bodies store
  together and a day of what you make of it) sells today for at least `quantityIncomeSecondsMin` of
  your income, so an order is never for a good worth only seconds of play. When no good you make is
  worth that, as late in the game when markets are deep in saturation and storage holds minutes of
  income at most, the order is for one of the three goods whose largest order is worth most, and
  pays at least the reward floor.
  Templates may still set a `maxQuantity` (× 1 + your levels of the megaprojects with
  `scalesContracts`); the shipped ones do not, as it cut late orders to a sliver of income. It pays
  `rewardMultiplier` (3) times what its goods sell for at today's price, at least
  `rewardIncomeSeconds` (30 min; what a fallback order pays) and at most `rewardCapIncomeSeconds` (1 h) of your income when it
  is posted, both at least `minRewardCredits` (500), and never less than `minRewardMultiplier`
  (1.5) times the sale value, cap or not, in whole credits. Income here is the larger of what
  auto-sell earns a second and the value of what your buildings steadily make beyond what they use,
  at current prices, so it does not matter which goods you auto-sell or whether you sell by hand,
  and a stockpile does not raise it. The first contract you are ever offered has no cap and pays at
  least `firstContractMinReward` (7,500, which must cover the first claim's 5,000 credits): it is
  the hook. Habitat goods (food, water, oxygen) weigh `lifeSupportWeight` (0.25) in the draw, so
  orders seldom compete with crew upkeep. Auto-sell holds back what open contracts still need, less
  what bodies with no rule for the good hold. The loader checks that the quantity span's minimum is
  at most its maximum, the reward cap at least the floor, and `minRewardMultiplier` at most
  `rewardMultiplier`.
- **Orbital Station.** Each level's goods and credits are delivered bit by bit, from any body, so a
  level may cost far more than one body holds; its timer starts once the last of it is in.
- **Mass Driver.** Opens at Orbital Station level 1 (`requiresMegaproject`). It takes credits and bulk
  goods that otherwise saturate (hull plate, copper wire, water, silicon wafers), costs ×2.3 a level,
  and each level runs extractors and tier-1 buildings ×1.15 faster (inputs and outputs), compounding.
  It asks for no food (habitats eat all a young economy makes) and no steel (plate presses take it for
  the station's hull plates), and it does not deepen markets: deeper tier 0–1 markets made those goods
  most of an optimizer's sales. Tuned in stage 1.6 so a casual player opens it on days 6–8 and gets a
  level every 1–5 days through day 21 (the casual bot on seeds 1–3, `docs/balance/`; it opens on
  day 10 on seed 2).
- **Megaproject bonuses.** `bonusesPerLevel` kinds: `storagePercent`, `housingPercent`,
  `outputPercent` and `marketDepthPercent` add `amount` percent a level; `offlineCapSeconds` adds
  seconds; `marketDepthMultiplier` and `productionSpeedMultiplier` multiply by `amount^level`
  (`amount` at least 1), optionally only from `appliesToMinTier` and up to `appliesToMaxTier` (the
  tier of the good sold, or the highest tier a building makes; habitats and depots make nothing and
  are never sped up; the lowest tier must not pass the highest). A multiplier never passes
  ×1,000,000, so every level stays finite.
- **Auto-delivery.** A megaproject can be fed on its own (`setMegaprojectAuto`): every game minute
  each body hands over what the stage still needs above what it keeps (its buildings' use over the
  step, its auto-sell rule's `keepAtLeast`, and what open contracts still need), every minute with
  goods `always`, or with `nearReady` only once the stage's credits still owed are within
  `nearReadyHorizonSeconds` (rules, default 43,200) of what credit auto-pay gives it (with credits
  off, within the credits held), until that stage is paid; with `credits` on, the credits above
  your one auto-pay reserve go in after the minute's sales, split among the megaprojects taking
  them by `creditWeight` (0 to 10). Between minutes auto-sell
  holds those goods back, up to the storage cap; what a body holds of them above its cap goes in at
  once. Stages due by the minute complete first, so the next one starts at the same time at any
  step size.

## Building niches

Every building is the best choice somewhere.

| Building | Best choice when |
|---|---|
| Mine, Ice Drill, Gas Skimmer | The only way to get a body's deposits. |
| Smelter | Steel where there is no hydrogen; the cheapest steel to build. |
| Hydrogen Furnace | Iron ore is shipped in and hydrogen is local (a gas giant): twice the steel per ore, plus water for habitats on a body with no ice. |
| Wire Mill, Wafer Fab, Circuit Fab, Plate Press, Magnet Works | The only makers of their goods; circuits, plates and magnets are deep exports and inputs to everything above them. |
| Ice Melter | Water from ice: the cheapest water. |
| Electrolyzer | Oxygen (and hydrogen) from water: the only oxygen. |
| Fuel Refinery | The most fuel per crew, from the electrolysis chain on an icy body. |
| Fusion Refinery | The most fuel per slot (almost twice the refinery's), on a slot-short gas giant with helium-3; it competes with reactor works for that helium-3. |
| Propellant Mixer | Fuel on a volcanic world, from sulfur alone: kits can be assembled on Cinder; sulfur's only use. |
| Fertilizer Plant, Hydroponic Farm | The most food per crew where ammonia is. |
| Protein Vat | Food without ammonia: with an ice melter and electrolyzer, a body with only ice can feed its habitats. |
| Reactor Works | Reactor cores, a deep export and the station's core input. |
| Station Dock | Station segments from plates, magnets and circuits: the top export, and Orbital Station stages (reactor cores go to the station directly, so the dock never eats them). |
| Drone Works | Survey drones: a deep export, surveys, and Orbital Station stages. |
| Module Works | Habitat modules for habitats: a fixed 72 per 6 h. |
| Shipyard | Cargo ships for routes (each carries 10 a second): a fixed 72 per 6 h. |
| Outpost Kit Assembler | Kits for claims: a fixed 36 per 6 h. |
| Habitat | The only crew housing. |
| Depot | Stockpiling past the storage cap (+200% storage each, cheap capacity levels): goods held for a big contract or a long absence. |
