# Ships, fuel, convoys

Builds on spec §13 (ship designs from a hull plus modules, every part a produced item).

## What the owner wants **[Owner]**

- The fun of ships is **customizing them, creating different ships, and seeing how they perform**.
- A **fuel** part of the game.
- **Convoys built for a job:**
  - fighters with smaller fuel tanks, and large tankers in the convoy to refuel them;
  - trade convoys of tankers, cargo ships and fighter escorts;
  - **hybrid ships** too.

## Seeing how designs perform **[Claude, owner liked]**

- **Each design gets a stat card plus a track record:** trips run, cargo moved, raids survived, ships lost. You
  learn over days whether a design was a good idea.
- **Preview before building:** drop a draft design onto a route and see "140/s, trip 6 min, raid risk 6%" before
  spending anything. This also covers round 4's hidden route throughput (E5).
- **Side-by-side comparison** of two designs, or one design before and after a change.
- **No single best ship:** slots are limited and mass slows you down, so every design gives something up.
- **Rivals field their own designs.** Scanners can read a pirate or faction ship, so you can design against it.

## Fuel **[Claude, owner liked]**

**[Check]** Fuel against spec §6 (economy) and §7, which weren't read. Not checked yet: that needs the owner's clear OK.

- **It's a produced good,** refined from gas or ice: a new chain to manage, and a steady sink for saturated tiers
  (round 4).
- **Each trip burns fuel by mass and engine.** A bigger engine is faster but thirstier.
- **Tank size sets range,** so explorers need big tanks or a fuel depot on the way.
- **In war, supply matters:** cut a fleet's fuel and it stalls (see 06).
- **Refueling is automatic.** Routes and convoys pull fuel from storage like any other input.
- **A ship that runs dry crawls home slowly.** It's never stranded, least of all offline.

## Convoys **[Claude, owner liked]**

A convoy is a saved group of designs assigned to a route, so you design at two levels: ships, then the mix.

```
Convoy "Outer Run"   (route Kessa → Orin)
 4× Hauler Mk II     cargo 4×120
 1× Tanker T1        fuel pool +900
 2× Escort F2        raid risk 11% → 4%
 ─────────────────────────────────
 speed 0.8 (slowest: Tanker)   range 14 jumps   fuel/trip 310
```

- **A convoy shares one fuel pool,** so tankers stretch the range of short-tank fighters. Fighters are light and
  quick, but they depend on support.
- **A convoy moves at its slowest ship's speed.** Every tanker or extra escort costs speed, which is where the
  trade-offs come from.
- **Hybrids,** like an armed freighter with cargo and guns, are worse per slot than specialists. They're good for
  small or early convoys that can't afford dedicated escorts.
- **War fleets use the same system,** so a strike group with tankers is a supply line the enemy can cut.

## Pirates **[Claude, owner liked; extends §13.3]**

- **Pirates go after tankers first.** Losing one sends the convoy crawling home: a real loss, never a stranded
  fleet.
- **Escorts in a convoy lower raid risk.** The preview shows the before and after.
- **Repeated hits lead to a pirate base bounty** (01). Pirate strength is a difficulty slider (03).
