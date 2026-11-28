// Renders a contact sheet of the icon concepts at Play sizes, plus lockups, to PNG.
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const DIR = process.argv[2];
const OUT = process.argv[3];
const uri = (f) => 'data:image/svg+xml;base64,' + fs.readFileSync(path.join(DIR, f)).toString('base64');
const icons = [
  ['A · Ringed Route', 'icon-a-ringed-route.svg'],
  ['B · Gear World', 'icon-b-gear-world.svg'],
  ['C · A Orbit (chosen)', 'icon-c-a-orbit.svg'],
];
const wmL = uri('wordmark-light-on-dark.svg');
const wmD = uri('wordmark-dark-on-light.svg');

const row = ([label, f]) => `
<section>
  <h2>${label}</h2>
  <div class="sizes">
    <img src="${uri(f)}" style="width:256px;height:256px;border-radius:20%">
    <img src="${uri(f)}" style="width:96px;height:96px;border-radius:20%">
    <img src="${uri(f)}" style="width:48px;height:48px;border-radius:20%">
    <img src="${uri(f)}" style="width:48px;height:48px;border-radius:50%">
  </div>
  <div class="lock dark"><img src="${uri(f)}" class="li"><img src="${wmL}" class="wm"></div>
  <div class="lock light"><img src="${uri(f)}" class="li"><img src="${wmD}" class="wm"></div>
</section>`;

const html = `<!doctype html><html><head><style>
body{margin:0;padding:40px;background:#E9E7E1;font:600 22px system-ui,sans-serif;color:#0A0F24;width:1400px}
h1{margin:0 0 8px;font-size:34px} p{margin:0 0 28px;font-weight:400;font-size:18px}
section{background:#fff;border-radius:20px;padding:24px 28px;margin-bottom:24px}
h2{margin:0 0 16px;font-size:24px}
.sizes{display:flex;gap:28px;align-items:end;margin-bottom:18px}
.lock{display:inline-flex;align-items:center;gap:18px;padding:18px 26px;border-radius:14px;margin-right:18px}
.dark{background:#0A0F24}.light{background:#F5F3EE;border:1px solid #ddd}
.li{width:72px;height:72px;border-radius:20%}.wm{height:40px}
</style></head><body>
<h1>Accrete: icon and logo concepts</h1>
<p>Each row shows 256 px, 96 px and 48 px with a rounded mask, 48 px with a circle mask, then a horizontal lockup on dark and on light.</p>
${icons.map(row).join('')}
</body></html>`;

(async () => {
  const b = await chromium.launch();
  const p = await b.newPage({ viewport: { width: 1480, height: 800 }, deviceScaleFactor: 1 });
  await p.setContent(html);
  await p.screenshot({ path: OUT, fullPage: true });
  await b.close();
})();
