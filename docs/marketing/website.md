# Website: brightworkgames.com

The site is in [`site/`](site/). It's plain HTML and CSS with no build step, no cookies, no analytics and no
third-party requests (the fonts are served from the site).

| Page | Path |
|---|---|
| Studio home | `/` |
| Accrete | `/accrete/` |
| Accrete privacy policy (the URL for Play Console) | `/accrete/privacy/` |
| Website privacy | `/privacy/` |
| Not found | `404.html` |

## Before publishing

1. **The email has to exist.** Every contact link points to hello@brightworkgames.com, so create it in iCloud+ first.
2. **The privacy policy has to match the game.** It says Accrete has no accounts, ads, analytics or tracking, and that
   saves stay on the device. Before the Play release, check with the builder that the release build includes no
   analytics or crash-reporting library and sends nothing over the network. If anything changes, update the policy,
   its date, and Play's data safety form together.
3. **Leave Cloudflare Web Analytics off.** The site's privacy page says there are no analytics.

## Publishing on Cloudflare Pages (free, about 10 minutes)

1. Log in to Cloudflare (dash.cloudflare.com). If the domain was bought through iCloud, its DNS may already be at
   Cloudflare; Apple's purchase email says where it's managed.
2. Go to **Workers & Pages → Create → Pages → Upload assets**. Name the project `brightworkgames`.
3. Upload the **contents** of the `site` folder, or the zip Claude sent, so `index.html` is at the top level. You'll
   get a `brightworkgames.pages.dev` address. Open it and check the pages.
4. In the project, open **Custom domains → Set up a domain** and add `brightworkgames.com`, then `www.brightworkgames.com`.
5. **Don't touch the MX or TXT records** that iCloud added for email. Pages only adds its own records for the website.
   Deleting iCloud's records breaks the email address.
6. To update the site later, upload a new version in the same project (**Create deployment**).

## After publishing

- Put `https://brightworkgames.com/accrete/privacy/` in Play Console under **App content → Privacy policy**.
- Add the site link to every social profile (see `social/README.md`).
- Paste the Accrete page into a link-preview checker, or into a draft post, to confirm the preview image appears.
