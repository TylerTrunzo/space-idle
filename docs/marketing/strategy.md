# Accrete marketing strategy

*Brightwork Games, drafted 28 November 2026. Sources are listed at the end. Where a source is a vendor blog or a
single anecdote, the text says so.*

## 1. What we're optimizing for

Accrete is free, with no ads and no purchases, so a player brings in no money. That changes the usual maths:

- **Installs aren't the goal. Players who stay are.** The main measure in this plan is **cost per player still
  playing on day 7** ("cost per D7 player"), not cost per install.
- **Every paid dollar is spent, not invested.** Paid ads only make sense once a dollar buys players who stay and
  leave good reviews. Until then the free channels below give more for the money.
- **Ratings and Play's quality signals act like a multiplier.** They decide how often Play shows the game for free.

## 2. Retention comes before any ad spend

Ads multiply whatever retention the game already has. GameAnalytics' 2025 data puts the median mobile game at about
22% of players returning on day 1, just under 4% on day 7, and under 1% on day 30. The top 10% of games keep about
11–12% at day 7.

Round 4 of our own playtests found both personas would quit around days 8–12 (findings §2.1). Paying for installs
before that is fixed means paying for players to leave in week two, and some of them would say so in reviews.

**The gate for any paid spend** (all four must hold):

1. E1 (megaproject payback) has shipped and passed its stage 1.7 pacing targets.
2. Closed or open testers report no week-2 stall.
3. Play Console shows day-7 retention of **10% or more**, which is near the top 10% of all games. Idle games should
   beat the all-genre median because they're built for return visits.
4. The rating is **4.3 or higher** from at least 20 reviews, and Android vitals are below Play's thresholds (§3.2).

## 3. Free levers, in order of return

### 3.1 Store listing conversion (free, and it multiplies every other channel)

Every visitor to the Play page, from any source, either installs or leaves. Play Console's **store listing
experiments** let you A/B test the icon, screenshots and short description against the live listing at no cost.
Vendor studies (SplitMetrics, as reported by ASO blogs) put icon-test wins at roughly 8–24% more installs. Those
figures are vendor-reported and vary, so treat them as "worth testing", not a promise.

Plan, testing one element at a time:
1. Icon C (A orbit) against a variant with a lighter background, for 14 days at a 50/50 split.
2. First screenshot: the star map against the production view.
3. Short description: "no resets" first against "no ads" first.

### 3.2 Play's quality signals (free, and protects everything else)

Play may **reduce a game's visibility and show a warning on its listing** when, averaged over 28 days, the
user-perceived crash rate goes above 1.09% or the ANR (app not responding) rate goes above 0.47%. Single phone models
have their own limits. One bad week on cheap phones can cost free traffic for a month.

Ratings matter too. NP Digital's study of 49 companies found 4-star apps got about 83% of the downloads of 5-star
apps, and 4.5-star apps about 96%. Other sources claim bigger gaps but don't show their data.

**Requests for the builder** (not marketing changes, so the owner decides):
- Use Play's In-App Review prompt only after a good moment, such as a station level finishing or a milestone. Never
  after a loss or an error, and never more than Play allows.
- Check Android vitals weekly, especially per phone model, before and during any ad test.

### 3.3 Google Play pre-registration (free)

Before launch, the listing can take pre-registrations. Play notifies people at release, and on eligible devices
installs the game automatically. Google's own 2019 case study (Nexon) reported about 50% of pre-registrations
becoming installs. That's one older case; the only other public figure is a disputed developer anecdote. Use it
anyway: it costs nothing, and it gives every post and link a better call to action than "email us".

**Use it** once the store listing is final, and point the website, devlog and social links at it.

### 3.4 Community and devlog (time, not money)

- **Where:** r/incremental_games, r/idlegames and r/AndroidGaming on Reddit; Bluesky with #gamedev and #indiedev; an
  itch.io devlog; the web build on itch.io and galaxy.click.
- **How:** be a member before being a marketer. Read each subreddit's self-promotion rules, and post where they
  allow it (for example r/incremental_games' Feedback Friday thread).
- **Rhythm:** a devlog post every two weeks, written from the latest playtest findings. Each one ends with the
  pre-registration or tester link.

### 3.5 YouTube creators (time, plus a small chance of a big win)

Chris Zukowski, an indie marketing consultant, suggests contacting 25–30 YouTubers who play your genre before paying
for anything. Reported reply rates for personal emails sit around 4–5%. One team estimated only about 30% of creators
who accepted a copy actually covered the game. So 30 well-chosen emails might produce one to three videos. That's
still the cheapest way to reach thousands of idle-game players at once.

- **Who:** channels with about 5,000–250,000 subscribers that have covered idle, incremental or factory games in
  the last three months.
- **When:** start at least six weeks before launch. Creators often wait to see how others cover a game.
- **What to send:** a short personal email naming one of their videos, the Play link (or a tester invite), the
  press kit, and one line on what's different: "no prestige reset, no ads, production chains across planets".

### 3.6 Press (time)

Mobile game sites cover few free indie games, so press is the least reliable channel. Send one launch email to a
short list of mobile game sites, with a press kit page on the website. These are the angles most likely to get read:

1. **A free game with no ads and no purchases.** That's rare enough on mobile to be a story.
2. **An idle game with no prestige reset.** It's a genre debate players already have.
3. **Playtested by AI personas.** It's new, but see §6 before using it.

## 4. Paid ads: where a small budget goes furthest

### 4.1 Which channels

| Rank | Channel | Why | Watch out for |
|---|---|---|---|
| 1 | **Google Ads App campaigns** (install-optimized, Android) | The only ad product built for Play installs. It reaches Play search, YouTube and Google's partner apps, and can count installs without adding any tracking code to the game. | Google recommends a daily budget of at least 50× your target cost per install, and a 7–14-day learning period. That rules out US-only targeting on a small budget. |
| 2 | **Reddit ads**, targeted at subreddits | Puts the game in front of exactly the right communities. Third-party estimates put gaming clicks at about $0.10–$1.50. | Optimizing for installs needs a tracking pixel, so measure with tagged links in Play Console instead. Reddit users dislike ads that look like ads, so write like a person posting. |
| — | Meta, TikTok, Unity/AppLovin ad networks | Skip for now. | They need lots of video ads to test, or an attribution SDK inside the game. An SDK would break the privacy policy's "no analytics" promise. |

Keep Google App campaigns **optimized for installs only**. Optimizing for in-game actions needs Firebase or a
similar SDK in the app, which would mean rewriting the privacy policy and Play's data safety form.

### 4.2 Pay for players where they're cheap

The game makes no money from anyone, so a player in Manila is worth exactly as much as one in Ohio. Third-party
estimates for casual Android installs (they vary widely, so treat them as rough):

| Market | Estimated cost per install |
|---|---|
| United States | $1.50–$3.50 (idle RPG: $2–$5) |
| UK, Canada, Australia | $1.00–$2.50 |
| Western Europe | $0.60–$1.50 |
| Southeast Asia, Latin America | $0.15–$0.60 |
| India | $0.08–$0.30 |

Accrete is in English, so test in markets where English is widely used and installs are cheap: the Philippines,
India, Nigeria, Kenya, South Africa and Malaysia.

What a player who stays costs works out as cost per install ÷ day-7 retention:

| Cost per install | Day-7 retention | Cost per D7 player |
|---|---|---|
| $0.30 | 10% | $3.00 |
| $0.30 | 4% (median game) | $7.50 |
| $2.50 (US) | 10% | $25.00 |

The retention gate matters as much as the market choice.

**Risk:** cheaper markets have more low-end phones, and those crash more. Watch Android vitals by phone model during
the test (§3.2). If crash or ANR rates rise, stop the campaign before it costs free visibility everywhere.

### 4.3 The first test: $150–200, once the gate in §2 is met

| | Google App campaign | Reddit |
|---|---|---|
| Budget | $15/day for 10 days ($150) | $5–10/day for 7 days (about $50) |
| Target | Installs; target cost per install $0.30 | Clicks to the Play listing, using a tagged link |
| Markets | The six above, in their own campaign | Worldwide; r/incremental_games, r/idlegames, r/AndroidGaming |
| Expected | Roughly 400–600 installs if cost per install lands at $0.25–0.40 | Depends on click-to-install rate; that's what we're testing |

**Rules during the test:** no budget or bid changes during the first 7 days (Google's learning period), and change
one thing at a time. Some guides say a change of more than 20% restarts learning; that figure isn't from Google, but
it's a sensible ceiling.

**After 14 days, read in Play Console:** installs per channel, day-1 and day-7 retained installers, rating trend,
and vitals. Then:
- **Cost per D7 player under $3:** scale the winning channel by about 20% a week, up to the monthly budget.
- **$3–6:** test new ad creative and the store listing before spending more.
- **Over $6, or rating or vitals slipping:** stop paid ads and fix the game or the listing first.

### 4.4 Budget tiers

| Tier | Monthly | What it buys |
|---|---|---|
| **Organic** (now until the gate) | $0 | Everything in §3 |
| **Test** (once, after the gate) | $150–200 | §4.3 |
| **Steady** (only if the test passes) | $300–500 | One winning channel at around $10–15/day, with creative refreshed monthly |

A paid "launch spike" isn't worth it for a game with no revenue. Steady, measured spend beats a burst.

Ready-to-use ad copy is in [ads.md](ads.md).

## 5. Timeline, tied to the game's stages, not dates

| When | Marketing work |
|---|---|
| **Now** | Handles, website, Play developer account, devlog #1. Build the creator list (30 channels). |
| **Stage 2 playable** | Closed test with about 20 testers. Store listing drafted. First store listing experiment once the listing is live. |
| **E1 shipped and stage 1.7 targets met** | Pre-registration open. Web build on itch.io. Creator emails start (six weeks before launch). Devlog every two weeks. |
| **Launch** | Reddit and Bluesky posts over 2–3 days. Press email. Reply to every review in the first two weeks. |
| **Launch + 2 weeks** | Check the gate (§2). If it passes, run the $150–200 test. |
| **Factions and war ship** | Treat it as a second launch: new screenshots, a trailer, a creator round, a devlog and a press email. |

## 6. PR risk: being built with AI

Accrete's design is steered by its owner and built by an AI coding assistant, with AI personas playtesting it. Some
players and communities are hostile to games made with AI. itch.io asks creators to label AI-generated content, and
some subreddits limit or ban AI-made posts. If people find this out from someone else, it'll look like hiding it.

**Recommendation:** say it first and say it plainly. Add a short "How Accrete is made" note to the website. Answer
truthfully when asked. Follow each platform's disclosure rules. The playtest angle is the honest version of the
story: an owner who designs and plays, and AI that builds and tests, with every balancing decision written down in
the repository.

**The owner decides this** before any devlog or creator email goes out.

## 7. What to measure

All of it is available in Play Console with no tracking added to the game:

| Measure | Where | Target |
|---|---|---|
| Store visitors → installs (conversion rate) | Statistics → store performance | Rising after each experiment |
| Day-1 and day-7 retained installers | Statistics / user acquisition | Day 7 ≥ 10% |
| Rating, and the themes in reviews | Ratings and reviews | ≥ 4.3. Keep a tally of "stalls", "confusing" and "love the chains" |
| Crash and ANR rates, overall and per phone model | Android vitals | Below 1.09% and 0.47% |
| Installs by source | Acquisition reports, using tagged links (UTM) | Find the best free channel |
| Cost per D7 player | Ads spend ÷ day-7 retained installers from that campaign | Under $3 |

## Sources

- GameAnalytics, *2026 Mobile & PC Gaming Benchmarks* (2025 retention data):
  https://www.gameanalytics.com/reports/2026-mobile-pc-gaming-benchmarks
- Google, *App campaigns best practices* (50× budget rule, learning period):
  https://business.google.com/us/accelerate/resources/articles/best-practices-guide-setting-up-your-app-campaigns/
  and https://support.google.com/google-ads/answer/6167156
- Android vitals thresholds and visibility effects: https://developer.android.com/games/optimize/vitals and
  https://android-developers.googleblog.com/2022/10/raising-bar-on-technical-quality-on-google-play.html
- Cost-per-install estimates (third-party, they vary): https://thesocialoutline.com/blog/cpi-benchmarks-mobile-gaming,
  https://gamegrowthadvisor.com/blog/2026-03-17-user-acquisition-cpi-benchmarks-2026/,
  https://www.appsflyer.com/blog/measurement-analytics/gaming-app-market-benchmarks-q3/
- Reddit ad costs (third-party estimates): https://adbacklog.com/blog/reddit-ads-benchmarks-per-industry-2026,
  https://benly.ai/learn/reddit-ads/reddit-ads-cost-benchmarks
- Store listing test results (vendor-reported): https://screencraftapp.com/blog/app-store-optimization-tips-data-guide
- Ratings and downloads (NP Digital, 49 companies): https://neilpatel.com/marketing-stats/app-downloads-vs-ratings/
- Pre-registration (Google/Nexon 2019 case study):
  https://android-developers.googleblog.com/2019/08/nexon-increases-day-60-retention-and.html
- Creator outreach (Zukowski Q&A; developer-reported rates):
  https://discussions.unity.com/t/unity-community-q-a-how-to-market-a-game-with-chris-zukowski/1593229?page=3,
  https://gamelaunchguide.com/blog/streamer-outreach-indie-games/,
  https://www.creatorscout.dev/guides/how-to-get-youtubers-to-play-your-indie-game
