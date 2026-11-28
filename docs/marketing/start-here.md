# Start here: how to begin marketing

This is the working plan. Claude is the marketing lead: it recommends, drafts, and builds the assets. The owner decides
and does anything that needs their own accounts, money, or name. Each step says who does what.

## The idea in one paragraph

You don't need ads, a budget, or a finished game to start. A small free game earns its audience by **showing up in a
few right places, being honest, and being easy to try**. The steps that take the longest in calendar time are
Google's: account verification, then a 14-day closed test with 12+ testers. So start those early. Everything else can
run alongside development.

## Step by step

### Step 1 — Decide the name and identity (this week, ~1 hour)
- **Owner:** pick the name (see `names.md`) and a public developer name. That can be your own name or a small studio
  name; a studio name keeps your personal name off the store.
- **Owner:** run the 5 checks in `names.md` (store search, trademark, domains, handles, the say-it-aloud test).
- **Claude:** once the name is chosen, update every doc and draft the logo and icon concepts.

### Step 2 — Claim the basics (this week, ~1–2 hours, ~$25–40)
- **Owner:**
  - make a dedicated email for the game;
  - register a Google Play developer account ($25 one-time). Identity verification can take days, so start now;
  - buy the domain (~$10–20 a year) if you want one;
  - reserve the same handle on Reddit, Bluesky, YouTube and itch.io.
- **Claude:** write the privacy policy page ("we collect nothing") and a one-page website or press kit to host on
  GitHub Pages or the domain.

### Step 3 — Start a devlog now, before the game is done (ongoing, ~1 post every 2 weeks)
- Why: when you launch, you want 20–100 people who already care. A devlog is how you get them with no budget.
- Hooks: **an idle game with no prestige reset**, **free with no ads or purchases**, and design posts built from
  playtest findings ("why station levels stopped paying back, and how we fixed it"). Per the owner's decision, posts
  don't mention AI (see `strategy.md` §6).
- **Claude:** drafts each post from the latest playtest findings and commits. **Owner:** reviews and posts it.
- Where: itch.io devlog (it can stay private until the web build exists), Bluesky or Mastodon with #gamedev
  #indiedev, and r/incremental_games only within its rules.

### Step 4 — Recruit closed testers (as soon as stage 2 makes the app playable)
- Google requires 12+ opted-in testers for 14 days in a row before you can publish (check the current rule).
- Aim for 20, because some drop out.
- **Claude:** writes the tester invite, a one-page "how to join the test" guide, and a 2-question feedback form.
- **Owner:** sends the invite to friends and family, devlog readers, and a Feedback Friday post with the web build.

### Step 5 — Fix the week-2 stall before any big push
- Playtests show players would quit around days 8–12 (round 4, E1). Testers will confirm or refute that.
- **Claude:** reads tester feedback alongside the playtest findings and says when it's safe to push for installs.

### Step 6 — Prepare the store page (when the app UI is stable)
- **Claude:**
  - finalises the listing text against what's actually built (the claims check in `store-listing.md`);
  - captures screenshots from sim saves;
  - builds the feature graphic and caption frames.
- **Owner:** uploads everything and fills in Play Console's forms (content rating, data safety, target audience).
  Claude can walk you through each form.

### Step 7 — Launch week
- **Claude:** drafts the launch posts (Reddit, Bluesky, itch.io, Discord) and reply templates for reviews.
- **Owner:** posts them over 2–3 days, not all at once, and replies to every comment in the first week.

### Step 8 — After launch
- Each update gets a short devlog post and a "what's new" note.
- Factions and war shipping is the second launch: new screenshots, a video, and posts again.
- **Claude:** reviews Play Console numbers (installs, day-7 and day-30 retention, review themes) with you monthly.

## What Claude can make for you

The name only needs settling before the first three:

- Icon and logo concepts (SVG)
- Feature graphic (1024×500)
- Screenshot caption frames
- Privacy policy page
- A website or press kit
- itch.io page copy
- Devlog posts
- Reddit and Bluesky launch posts
- Tester invite and feedback form
- Review reply templates
- A 30-second trailer storyboard
- Play Console form walkthroughs

## Decisions log

| Date | Decision | Status |
|---|---|---|
| 2026-11-28 | Marketing docs started; Claude acts as marketing lead | Done |
| 2026-11-28 | Game name: ~~Starwright~~ → **Accrete** (two other space games already use Starwright) | Chosen; web and USPTO checks clear (no live marks in classes 9/41/42); domain and handles still to check |
| 2026-11-28 | Public developer name: **Brightwork Games** (a studio name, not space-themed, so it can carry future games) | Chosen; USPTO clear (only live mark is a dental practice); domain and handles still to check |
| 2026-11-28 | First asset: icon and logo concepts | Done: `brand/`. Recommend concept C |
| 2026-11-28 | App icon direction: **C** (the name's letter drawn as an orbit), redrawn as an **A** for Accrete; A's ringed route goes on the feature graphic | Chosen; final polish and export to do |
| 2026-11-28 | Domain and email: buy the domain through iCloud+ or Cloudflare; studio email via iCloud+ Custom Email Domain; website on Cloudflare Pages | Owner to do |
| 2026-11-28 | Domain **brightworkgames.com** bought through iCloud+; **hello@brightworkgames.com** created | Done |
| 2026-11-28 | Website and privacy policy built (`site/`); social kit ready (`social/`) | Owner to publish on Cloudflare Pages and claim the handles |
| 2026-11-28 | Strategy written (`strategy.md`): no paid ads until the retention gate is met; then a $150–200 test of Google App campaigns in low-cost English-speaking markets, plus Reddit | Proposed |
| 2026-11-28 | AI involvement: keep a low profile. No AI in marketing, never deny it, answer honestly if asked, follow platform rules (`strategy.md` §6) | Decided by owner; owner to make the GitHub repository private |
| 2026-11-28 | Ad budget: one $150–200 test once the retention gate is met, then decide | Decided by owner |
| — | How much time per week the owner gives to marketing | **Open** |
