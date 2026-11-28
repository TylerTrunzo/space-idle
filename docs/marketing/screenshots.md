# Screenshots and store art plan

I haven't seen the app's UI. This plan follows the features named in spec §1–2 and playtest round 4. Adjust the shots
to the real screens once stage 2 is done.

## Play requirements (check the current Play Console help before uploading)

- **Phone screenshots:** 2–8 allowed. JPEG or 24-bit PNG with no transparency. Each side 320–3,840 px, and the long
  side no more than twice the short side. Aim for **8 shots at 1080×1920 (portrait)** or 1920×1080 if the game plays
  landscape. Google has favoured listings with at least 4 screenshots of at least 1,080 px when picking games to
  feature.
- **Feature graphic:** 1024×500, required. It shows at the top of the listing and behind the video.
- **App icon:** 512×512, 32-bit PNG.
- **Video (optional):** a YouTube link, 30–60 s. Fine to skip at launch.
- **Tablet shots:** optional, but cheap to add if the layout adapts.

## Rule: real screens only

Screenshots must show real gameplay. A caption strip and a frame are fine. Mocked-up UI, faked numbers, or showing
war before it ships is not. That rule is Play policy as well as the spec's.

## Shot list (in upload order)

The first 2–3 shots do most of the work, because they're all most people see in search results.

| # | Screen and state | Caption | Shows |
|---|---|---|---|
| 1 | Star map, mid-game: several colonised bodies with visible routes | **Build an empire that never resets** | Sense of place (anti-goal: "not a spreadsheet") |
| 2 | A planet's production view: tiered buildings, input/output rates | **Every planet has different deposits** | Depth: multi-tier refining |
| 3 | Catalog or chain planner: ore → plate → circuit | **Plan the whole chain** | The optimization pleasure |
| 4 | Away summary after a night: projects finished, credits earned | **Your empire works while you sleep** | Offline progress; round 4's favourite moment |
| 5 | Station megaproject screen, partway through a level | **Megaprojects that grow over days** | Slow building |
| 6 | A route with ships, cargo and its binding limit visible (fix E5) | **Find the bottleneck** | Logistics |
| 7 | Buy-max mid-spree, numbers ticking up | **A few minutes is always enough** | Short check-ins, numbers getting bigger |
| 8 | A milestone or victory moment | **No ads. No purchases. Just growth.** | Fairness, and the "it keeps going" ending |

When factions ship, swap #7 or #8 for a diplomacy screen captioned **"Trade, negotiate, or fight. War is optional."**

## How to get good game states without days of play

The headless `game_sim` can already drive the economy by seed and day (round 4 used seeds 1–3, days 1–21), and E2
mentions "saved mid-game states". Ask the builder for a debug-only way to load a sim save into the app, then capture:

- **Day 1–2 state** for shots 2, 3 and 7 (bright, readable, not cluttered)
- **Day 7–10 state** for shots 1, 5 and 6 (a full map, but before the late-game stall)
- **A save from just after an overnight jump** for shot 4

Use the same seed for every capture so the shots tell one consistent story. Capture at device scale 2 on a 1080-wide
phone viewport, then add captions in an image editor or a small script, not in the game.

Before capturing, make sure fixes from §2.9 are in so no shot shows a bug: "0 of N crew", "30K of 30K" while one
unit is still owed, or "+0.59 credits".

## Feature graphic (1024×500)

- Left two-thirds: a crop of the star map with routes glowing between planets; nothing important near the edges.
- Right third: the name in the logo font, and the tagline "Build an empire that never resets."
- Keep text large. It's shown small on phones and partly covered by the play button when there's a video.

## Icon concepts

1. A planet with a ring made of a conveyor or cargo route (says "space industry" at a glance)
2. A gear whose teeth are small planets
3. The letter mark (S for Starwright) as an orbit path with one bright cargo ship on it

Test the icon at 48 px next to other idle games' icons. Most use busy cartoon faces, so a clean icon with one idea
stands out.

## 30-second video (later)

0–5 s, an upgrade spree with numbers climbing → 5–12 s, zoom out to the star map with routes → 12–20 s, the chain
planner → 20–26 s, the away summary: "while you were away…" → 26–30 s, the name and "No ads. No purchases. No reset."
