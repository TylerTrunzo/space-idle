# Google Play store listing (draft)

The limits listed are Google Play's: title ≤ 30 characters, short description ≤ 80, full description ≤ 4,000. Check
them in Play Console before submitting; Google changes them occasionally.

## Title

`Accrete: Idle Space Factory` (27 characters)

Play's metadata policy doesn't allow promotional or ranking words in the title, such as "free", "no ads", "best",
"#1" or "new", and doesn't allow emoji or all caps. Keep the "no ads" message in the descriptions.

## Short description (≤ 80)

Pick one:

- `Build production chains across planets. No resets, no ads, no purchases.` (72)
- `A deep space-industry idle game. Your empire grows for good. No ads, ever.` (74)
- `Mine, refine and ship across the stars. An idle empire that never resets.` (73)

## Full description

Sections marked **[v1-if-shipped]** cover factions and war. Remove them if those systems aren't in the release
build.

```
Build a space empire that never resets.

Accrete is an idle game about industry. Every planet holds only some
resources, so you mine what's there, refine it through tier after tier of
production, and ship it between worlds to build something bigger. Your empire
grows outward across the star map, over days and weeks, and it keeps working
while you're away.

THE FUN IS IN THE RATIOS
• Many raw resources, multi-tier refining, and planets with their own deposits
• Upgrade buildings, assign crew, and balance inputs against outputs
• Plan whole production chains before you build them
• Find the bottleneck: is it the refinery, the route, or the dock?
• Cargo routes, ships and storage, all yours to tune

GROWTH THAT LASTS
• No prestige, no reset: everything you build stays built
• Station megaprojects that level up over hours and days
• Big milestones give you a victory moment, and the game keeps going
• An away summary shows what your empire did while you were gone

MADE FOR SHORT CHECK-INS
• A few minutes is always enough to make progress
• Offline progress: production, deliveries and projects continue
• One tap buys the best-value upgrades when you're short on time
• No timers designed to pull you back, and no streaks to break

[v1-if-shipped]
FACTIONS, DIPLOMACY AND (OPTIONAL) WAR
• Computer-controlled factions to trade with, negotiate with, or fight
• Attack and defend planets with battles that resolve automatically
• War is optional: a peaceful player can reach every planet and item
• You'll never come back to find your empire destroyed overnight

FAIR BY DESIGN
• No ads
• No in-app purchases
• No premium currency
• Plays offline. No account needed.

Also playable in your web browser.
```

That's about 1,700 characters, so there's room to add a feature or two later.

## Claims check

Every listing claim has to be true in the build you submit. Recheck this table on release day.

| Claim | Source | Status |
|---|---|---|
| Many resources, multi-tier refining, planet-specific deposits | spec §2 goal | Economy is built (stage 1); verify in the app build |
| Plan chains before building | round 4: "the catalog planning whole chains" | In the engine; confirm the app has a catalog screen |
| Routes, ships, storage | round 4 §2.5, stage2-app's latest commit ("routes") | In the app branch |
| Station megaprojects over hours and days | round 4 §1 | True |
| Milestones with a victory moment; play continues | spec §2 | Confirm the app shows the victory moment |
| Away summary | round 4 §2.4 | Exists; round 4 found it **misleading**, so fix E4 before advertising it |
| One-tap buy best upgrades | round 4 E7 | Planned for stage 2; confirm |
| A few minutes is always enough | spec §2 (2–5 min target) | Pacing E1 must land; see stage 1.7 targets |
| No FOMO timers or streaks | spec anti-goals | Keep true |
| Factions, diplomacy, war; never destroyed overnight | spec §2, anti-goals | **Not built yet.** Keep `[v1-if-shipped]` out until it is |
| No ads, IAP, premium currency | spec non-goals | True |
| Offline, no account | spec non-goals (no accounts, servers, cloud saves) | True. Add "progress lives on this device" to the FAQ |
| Browser version | spec §2 | Link it from the listing once it's hosted |

## Listing settings

- **Category:** Games → Strategy (Simulation is the alternative; Strategy suits production chains and factions
  better). Tags: Idle, Strategy, Simulation, Sci-fi, Single player, Offline.
- **Target audience:** 13+ (or 18+). Don't include under-13s: that brings in the Families policy, which isn't worth
  it for a game with no monetization.
- **Content rating (IARC):** answer honestly. Abstract, auto-resolved battles with no gore usually rate Everyone or
  Everyone 10+. Rate again when war ships.
- **Data safety:** with no accounts, analytics, ads or network calls, the declaration can be "no data collected or
  shared". Check that no Flutter plugin or crash reporter collects data. Adding analytics later means updating the
  declaration.
- **Ads declaration:** "No, my app does not contain ads."
- **Privacy policy URL:** still required. A one-page "we collect nothing; saves stay on your device" policy, hosted on
  the game's site or GitHub Pages, is enough.
- **Contact email:** use a dedicated address for the game, not a personal inbox. Plan: an iCloud+ custom-domain address such as hello@brightworkgames.com.
