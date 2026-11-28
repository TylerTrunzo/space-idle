// Renders the link-preview image and social profile images from HTML, using the site's own fonts and assets.
// Usage: node social.js <site-dir> <social-out-dir>   (serves <site-dir> on a local port while rendering)
const http = require('http');
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const SITE = path.resolve(process.argv[2]);
const OUT = path.resolve(process.argv[3]);
fs.mkdirSync(OUT, { recursive: true });

const types = { '.svg': 'image/svg+xml', '.woff2': 'font/woff2', '.css': 'text/css', '.html': 'text/html' };
const server = http.createServer((req, res) => {
  const file = path.join(SITE, decodeURIComponent(req.url.split('?')[0]));
  if (!file.startsWith(SITE) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) { res.statusCode = 404; return res.end(); }
  res.setHeader('content-type', types[path.extname(file)] || 'application/octet-stream');
  fs.createReadStream(file).pipe(res);
});

const base = `
<link rel="stylesheet" href="/assets/site.css">
<style>
  html,body{margin:0;background:none}
  .frame{position:relative;overflow:hidden;background:
    radial-gradient(70% 90% at 20% 0%, #1f2858, transparent 60%),
    radial-gradient(60% 80% at 100% 20%, #1b2a55, transparent 55%), #0a0f24;
    color:#eef0fb;font-family:"Space Grotesk",system-ui,sans-serif;display:flex;align-items:center}
  .stars i{position:absolute;width:4px;height:4px;border-radius:50%;background:#e8ecff}
  .dot{display:inline-block;border-radius:50%;background:#ffb547;box-shadow:0 0 40px 10px rgba(255,181,71,.5)}
</style>`;

const stars = (w, h, n) => {
  let s = '', seed = 7;
  const r = () => (seed = (seed * 9301 + 49297) % 233280) / 233280;
  for (let i = 0; i < n; i++) s += `<i style="left:${(r() * w) | 0}px;top:${(r() * h) | 0}px;opacity:${(0.25 + r() * 0.6).toFixed(2)}"></i>`;
  return `<div class="stars">${s}</div>`;
};

const jobs = [
  {
    file: path.join(SITE, 'assets/og-accrete.png'), w: 1200, h: 630,
    html: `<div class="frame" style="width:1200px;height:630px;padding:0 90px;gap:70px">${stars(1200, 630, 40)}
      <img src="/assets/accrete-icon.svg" style="width:300px;height:300px;border-radius:66px;box-shadow:0 0 0 2px #2b3568,0 30px 80px rgba(0,0,0,.5);position:relative">
      <div style="position:relative">
        <img src="/assets/accrete-wordmark.svg" style="height:64px;display:block;margin-bottom:34px">
        <div style="font-size:54px;font-weight:700;line-height:1.1;margin-bottom:26px">Build an empire<br>that never resets.</div>
        <div style="font-size:26px;color:#a9b0d3">An idle space game · Android &amp; web</div>
      </div></div>`,
  },
  {
    file: path.join(OUT, 'avatar-800.png'), w: 800, h: 800,
    html: `<div class="frame" style="width:800px;height:800px;justify-content:center">${stars(800, 800, 18)}
      <div style="position:relative;font-size:520px;font-weight:700;line-height:1;letter-spacing:-.02em;margin-top:-30px">B</div>
      <span class="dot" style="position:absolute;width:92px;height:92px;left:548px;top:150px"></span></div>`,
  },
  {
    file: path.join(OUT, 'banner-1500x500.png'), w: 1500, h: 500,
    html: `<div class="frame" style="width:1500px;height:500px;padding:0 120px;justify-content:space-between">${stars(1500, 500, 36)}
      <div style="position:relative">
        <div style="display:flex;align-items:center;gap:26px;font-size:84px;font-weight:700;margin-bottom:18px">
          <span class="dot" style="width:40px;height:40px"></span>Brightwork Games</div>
        <div style="font-size:34px;color:#a9b0d3">Making Accrete, an idle space game for Android and the web.</div>
      </div>
      <img src="/assets/accrete-icon.svg" style="position:relative;width:240px;height:240px;border-radius:54px;box-shadow:0 0 0 2px #2b3568">
    </div>`,
  },
  {
    // YouTube shows only the centre 1546x423 on every device, so all text sits inside it.
    file: path.join(OUT, 'youtube-banner-2560x1440.png'), w: 2560, h: 1440,
    html: `<div class="frame" style="width:2560px;height:1440px;justify-content:center">${stars(2560, 1440, 90)}
      <div style="position:relative;width:1546px;height:423px;display:flex;align-items:center;justify-content:space-between;padding:0 40px;box-sizing:border-box">
        <div>
          <div style="display:flex;align-items:center;gap:24px;font-size:96px;font-weight:700;margin-bottom:14px">
            <span class="dot" style="width:44px;height:44px"></span>Brightwork Games</div>
          <div style="font-size:38px;color:#a9b0d3">Devlogs and trailers for Accrete, an idle space game.</div>
        </div>
        <img src="/assets/accrete-icon.svg" style="width:260px;height:260px;border-radius:58px;box-shadow:0 0 0 2px #2b3568">
      </div></div>`,
  },
];

(async () => {
  await new Promise((r) => server.listen(0, r));
  const port = server.address().port;
  const browser = await chromium.launch();
  for (const j of jobs) {
    const page = await browser.newPage({ viewport: { width: j.w, height: j.h }, deviceScaleFactor: 1 });
    await page.goto(`http://127.0.0.1:${port}/404.html`);
    await page.setContent(`<!doctype html><html><head><base href="http://127.0.0.1:${port}/">${base}</head><body>${j.html}</body></html>`);
    await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(150);
    await page.screenshot({ path: j.file, clip: { x: 0, y: 0, width: j.w, height: j.h } });
    await page.close();
    console.log('wrote', path.relative(process.cwd(), j.file));
  }
  await browser.close();
  server.close();
})();
