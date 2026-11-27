# Content

The game's data, validated at load by `game_core` (`dart run game_sim:game_sim check`).

## Economy at a glance

- **Markets.** Raw (tier 0) and refined (tier 1) goods have shallow markets and floors near zero: they
  pay early, but bulk sales earn almost nothing. Components (tier 2) and advanced goods (tier 3) have
  deep markets, so late income comes from them and is spread over several goods, because each market
  pays less per unit the more of it is sold. Orbital Station levels deepen every market by 25%.
- **Upgrades.** Speed and capacity on a building share one counter: each speed or capacity upgrade
  makes the next one of either 17% pricier, so the order you buy them in hardly matters, and one more
  crew never pays back more than about 1.7× faster than a speed level (capacity's base is 6× speed's).
  Efficiency counts on its own (×1.2 a level) and stops at 25% of inputs, shown as maxed.
- **Crew.** A habitat's capacity levels raise its housing and its food, water and oxygen use alike
  (+25% each a level), so every crew costs the same upkeep.
- **Equipment.** Outpost kits, habitat modules and cargo ships are for use, not trade: markets one unit deep,
  and their makers have no speed or capacity track. Each maker makes a steady 36–72 every 6 h; more
  needs another building. Claims after the first cost 5 + 5 × (bodies owned − 1) kits.
- **Contracts.** An order asks only for a good your buildings make now, at least `minQuantity /
  quantitySeconds` a second, so a trickle never gets one. It asks for `quantitySeconds` of what you make
  of it, gross of what your own buildings use (1 h of bulk goods, 2 h of components, 3 h of advanced
  goods), but never more than one of your bodies can store, nor the template's `maxQuantity` (5,000,
  1,000 and 100) × (1 + your megaproject levels summed). It pays 3× the base price per unit, at least
  `rewardIncomeSeconds` (10 min) and at most `rewardCapIncomeSeconds` (1 h) of your income when it is
  posted. The first contract you are ever offered has no cap: it is the hook. Habitat goods (food,
  water, oxygen) are drawn a quarter as often, so orders seldom compete with crew upkeep. Auto-sell
  holds back what open contracts still need (on the body with the most of it).
- **Orbital Station.** Each level's goods and credits are delivered bit by bit, from any body, so a
  level may cost far more than one body holds; its timer starts once the last of it is in.

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
