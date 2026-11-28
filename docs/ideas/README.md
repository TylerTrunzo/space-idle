# Ideas for stage 3 and later

*Brainstorm with the owner, 2026-11-28. These are ideas, not spec. Nothing here changes the design spec or the
stage branches until the owner promotes it.*

Read for this brainstorm: spec §1, §2, §6, §7, §8, §11, §13 and the round 4 playtest findings
(`docs/playtests/2026-11-27-round4-findings.md` on the stage branches). §6 and §7 were read after the first draft;
the ideas fit them with no real conflicts (see each file's "Fit with the spec" notes).

Legend:
- **[Owner]**: the owner's own words or decision in the brainstorm.
- **[Claude, owner liked]**: Claude's proposal, which the owner approved in the conversation.
- **[Claude's call]**: a detail Claude filled in that wasn't discussed. The owner can override it.
- **[Check]**: needs checking against unread spec sections, or a later decision.

## The big picture **[Owner]**

A day-15 check-in is catching up on a galaxy that kept moving without you: diplomacy news, whether your ships were
attacked, how other factions expanded, then your own production. News should **open things up**, not just be read.
Factions **remember** what you did.

## Files

| File | Area |
|---|---|
| [01-galaxy-news-and-openings.md](01-galaxy-news-and-openings.md) | The away digest as galaxy news; news that creates openings |
| [02-factions-and-diplomacy.md](02-factions-and-diplomacy.md) | Faction memory, personalities, relation stages |
| [03-settings-difficulty-hardcore.md](03-settings-difficulty-hardcore.md) | War toggle, difficulty presets and sliders, hardcore mode |
| [04-ships-fuel-convoys.md](04-ships-fuel-convoys.md) | Ship design feedback, fuel, convoys, hybrids, pirates |
| [05-exploration.md](05-exploration.md) | What explorers find: leads, debris, blueprints, intel, deposits |
| [06-war.md](06-war.md) | The war check-in, war standing, war-weariness, changes to §8 |

## Suggested stage placement **[Claude's call]**

Builds on spec §11 and §13.4.

- **Stage 3, factions and diplomacy:**
  - galaxy news digest and openings (01);
  - faction memory, personalities and relation stages (02);
  - war toggle and difficulty presets (03), needed once factions can turn hostile;
  - fuel as a produced good, per-trip burn and tanks (04), arriving with §13.4's ship designs;
  - trade convoys with haulers, tankers and escorts (04), for §13.4's simple pirates;
  - faction buyers through openings, which round 4 deferred to stage 3 (E6, "market wall").
- **Stage 4, war:**
  - the war panel, standing meter, war-weariness and fleet trails (06);
  - scanner-limited enemy visibility (06);
  - siege supply and tanker raids (04, 06);
  - home blockade and the comeback openings (03);
  - hardcore mode (03), which only means something once war exists.
- **Stage 5, content:**
  - exploration finds: leads, derelicts, blueprints, intel, rare deposits (05);
  - factions racing you to finds (05).
  - **Dependency:** stage 4's scanner and intel ideas assume some exploration basics. Either pull a minimal
    explorer into stage 4 or keep intel to scanner range until stage 5.

## How these help round 4's problems **[Claude's call]**

- **Late-game flattening (days 8–12):** news openings, faction buyers and war demand give mid and late game new
  decisions and new markets.
- **Contracts are never a decision:** openings become timed, situational deals with real trade-offs (prices vs
  relations).
- **Saturated tier 0–1 markets:** fuel is a new steady sink. Wartime demand for armor and weapons adds another.
- **Hidden route throughput:** the convoy and design preview shows capacity, speed, fuel and raid risk before you
  commit.

## Open items **[Check]**

- **Hardcore versus the offline cap (owner to decide).** §6.7 fast-forwards at most 12 h (up to 48 h with
  upgrades). In hardcore, does the rest of the galaxy keep acting past that cap while your production stops? That
  would be very harsh; the other option is that the whole world pauses at the cap, yours and theirs alike. See 03.
- Hardcore mode needs a line in §2's anti-goals when promoted: "except in opt-in hardcore mode."
- Settings must be stored per world (not per player) for later shared galaxies (spec §5.4).
