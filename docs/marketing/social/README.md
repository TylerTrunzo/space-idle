# Social handles kit

Claude can't create these accounts: each signup needs the owner's email or phone, a verification code and usually a
CAPTCHA. Everything else is ready here, so each one takes a couple of minutes.

Use **hello@brightworkgames.com** to sign up, once it exists in iCloud+. Save each password in iCloud Keychain or
another password manager, and turn on two-factor sign-in wherever it's offered.

## Same on every platform

- **Name:** Brightwork Games
- **Handle:** `BrightworkGames`. If it's taken, use `BrightworkGamesHQ`, then `brightwork_games`. Use the same one
  everywhere if you can.
- **Link:** https://brightworkgames.com
- **Profile picture:** `avatar-800.png` (the B with an amber dot; it still works when a site crops it to a circle)
- **Bio** (138 characters, fits everywhere):

  > Small game studio. We're making Accrete, an idle space game about production chains, for Android and the web. No
  > ads, no purchases.

## Do these four now

| Platform | Handle | Notes |
|---|---|---|
| **Bluesky** | `brightworkgames.com` (your domain) | Sign up with any handle, then go to Settings → Account → Handle → "I have my own domain". It gives you one DNS record to add wherever brightworkgames.com's DNS is managed. A domain handle proves the account is really yours. Banner: `banner-1500x500.png`. |
| **Reddit** | `u/BrightworkGames` | Reddit usernames can never be changed, so check the spelling. Use it as a normal member of r/incremental_games and r/AndroidGaming before ever posting about the game. |
| **itch.io** | `brightworkgames` → brightworkgames.itch.io | This is where the web build and devlog will live. Make the account now; the game page can stay unpublished. |
| **YouTube** | `@BrightworkGames` | Create the channel under the same Google account as Play Console. Banner: `youtube-banner-2560x1440.png` (its text sits in the area YouTube shows on every device). |

## Reserve only (claim the name, post nothing yet)

X (`@BrightworkGames`, banner `banner-1500x500.png`), Instagram, Threads (uses the Instagram account) and TikTok.
Reserving takes a minute each and stops someone else taking the name. There's no need to keep them active.

**Discord:** wait until there are testers. A server doesn't reserve a name, and an empty one looks abandoned.

## First post (Bluesky, once the website is live)

> Hi, we're Brightwork Games. We're making Accrete, an idle space game about building production chains across
> planets. Nothing you build is ever reset, and there are no ads or purchases. It's in development for Android and
> the web, and we're looking for testers: brightworkgames.com/accrete

## Regenerating the images

`node ../brand/tools/social.js ../site .` from this folder. It also rebuilds the site's link-preview image,
`site/assets/og-accrete.png`.
