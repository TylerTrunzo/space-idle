# Galaxy news and openings

## What the owner wants **[Owner]**

- A check-in shows what happened in the world: random diplomacy events, whether any of your ships were attacked, how
  other factions expanded, and your own production.
- The news should **open things up** for you, not only be something to read.

## The away digest becomes galaxy news **[Claude, owner liked]**

- **Factions act on each other, not only on you.** They claim planets, make and break deals, and feud with each
  other on their own, so there's news even if you do nothing.
- **The away summary grows into a digest,** sorted by how much each item touches you. Your production report stays
  last, as it is now.
- **The map shows what changed since your last visit:** borders that grew or shrank, and new things highlighted.
- **Attacks are reported honestly and capped** (spec §13.3 offline caps; hardcore aside, see 03).

```
While you were away (9h)
 ⚠ Pirates hit Kessa→Orin route twice: −4% of shipped ore
 🤝 Vey Combine and Halden signed a trade pact
 🚀 Halden claimed 2 bodies in the Lyra system (now bordering you)
 ⚔ Vey and the Drift Clans are at war
 📈 Your income +6% · 3 upgrades finished
```

**Fit with the spec:** §6.7's "while you were away" summary already lists production gains, faction events, war
events and the top bottlenecks. This grows it into a news digest; it doesn't replace it. Openings use §7's
diplomatic actions and §6.5's faction trade.

## Openings **[Claude, owner liked]**

Each news item can come with an opening: a choice you act on from the digest or the map.

| News | Opening |
|---|---|
| Two factions go to war | Both pay a premium for armor, weapons, fuel. Supply one side, both, or neither. Frontier planets may be abandoned and open to claim. |
| A pact is signed | A new trade lane between them. Shared patrols lower pirate risk on it. |
| A faction expands next to you | A new nearby buyer with its own demand list. |
| Repeated pirate hits | Escorts trace the pirates' base, unlocking a bounty (ties to §13.3 pirate hunting). |
| A faction has a famine or crisis | It pays well for food or parts, or sells off a planet. |
| An explorer find | See 05. |

- **Openings last a day or two,** spanning several check-ins. Missing one costs nothing, and another always comes
  along. That keeps them away from the FOMO timers the §2 anti-goals rule out.
- **Each opening shows its diplomatic cost up front** ("Vey −10, Halden +15"; see 02).

## Notes for the builder **[Claude's call]**

- Openings are generated from the seeded RNG and world state, so `game_sim` can replay and balance them.
- Openings replace and extend round 4's contracts (E6): contracts with a reason, a buyer, and a relation trade-off.
- Round 4's away summary fixes (E4: grouped causes, honest bottlenecks) apply to the news digest too. Group repeats
  ("Pirates hit Kessa→Orin twice"), never 17 identical rows.
