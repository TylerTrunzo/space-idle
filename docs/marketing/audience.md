# Audience

Success is getting the game published on Play (spec §1); money isn't a goal. So the job here is to find players
who'll enjoy it, leave honest reviews, and give feedback, not to buy installs.

## Who it's for

**Primary: production-minded idle players.** They already play idle and incremental games in a few short check-ins
a day (like the owner), and they want depth: chains, ratios, bottlenecks. They're tired of prestige resets, ad walls
and premium currencies. Typically adults 20–45, playing on their phones between other things.
*What wins them:* "no reset", "every ratio matters", and a fair game.
*What loses them:* a stall in week 2, an economy where buying the cheapest upgrade is always right, and any whiff of
pay-to-win.

**Secondary: strategy and factory-game fans with little time.** People who like 4X or factory-building games but
can't spend whole evenings on them now.
*What wins them:* planets with different deposits, logistics, factions and diplomacy (once built).
*What loses them:* shallowness. Expect them to find the strategy that wins every time; round 4 shows the optimizer
does exactly that.

**Tertiary: browser incremental players.** A large, active community that plays in the browser and gives detailed
feedback. The web build is how to reach them, and they're the best early testers.

## How the playtest personas map to these groups

Round 4 played *casual* and *optimizer*. Round 2 also had *newplayer*, *returner*, *longhaul*, *completionist* and
*designer*. Casual and returner are the primary group, optimizer and designer are the secondary group, and
completionist and longhaul are the people who'd write week-3 reviews. The fact that round 4's optimizer flattened out
from day 10 is a warning about the secondary group.

## Where they are

| Place | Audience | How to show up |
|---|---|---|
| r/incremental_games | Primary + tertiary | Read the rules first. Self-promotion is limited; use the "Feedback Fridays" thread with the web build. |
| r/AndroidGaming, r/idlegames | Primary | Post at launch: what it is, "no ads / no purchases", and a link. Answer every comment. |
| itch.io (web build) | Tertiary | A free browser page, with a devlog that tells the playtest-driven balancing story. |
| galaxy.click and similar incremental-game sites | Tertiary | Submit the web build. |
| A small Discord server | Everyone who stays | One place for testers and bug reports. Keep it small. |
| Bluesky / Mastodon #gamedev | Other devs, word of mouth | Short devlog posts about design decisions and what playtests changed. |

## Launch plan with no budget

**Phase 0, now.** Pick the name, reserve the handles and domain, write the privacy policy, and set up the itch.io
page (it can stay private).

**Phase 1, closed testing (needed anyway).** New personal Play developer accounts must run a closed test with at
least 12 opted-in testers for 14 days in a row before they can publish to production. Check the current rule in
Play Console, since it has changed before. Recruit testers from friends, a Feedback Friday post with the web build,
and Discord. Ask two questions only: "When did you stop wanting to check in?" and "What confused you?" That checks
the playtest findings against real people.

**Phase 2, open beta or web.** Once E1 passes its stage 1.7 pacing targets, put the web build on itch.io and
galaxy.click and post a devlog.

**Phase 3, Play production launch.** Post on Reddit and Discord, using the listing from `store-listing.md`. Reply to
every early review. Each Play update is a chance for a devlog post ("Update: the Mass Driver finally matters").

**Phase 4, when factions and war ship.** That's the one big "new content" moment. Update the listing, screenshots
and video, and post again.

## Measuring success without analytics

The data safety plan is "no data collected", so measure only with what Play Console reports anyway:

- Installs and uninstalls, and whether people still have it after day 7 and day 30 (Play Console shows retained
  installers)
- Rating and review themes: keep a tally of "stalls", "confusing" and "love the chains"
- Crashes and ANRs from Play's Android vitals (no SDK needed)
