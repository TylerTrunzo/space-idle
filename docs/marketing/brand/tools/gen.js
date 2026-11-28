// Generates Accrete icon concepts + outlined wordmarks as standalone SVGs.
const fs = require('fs');
const path = require('path');
const opentype = require('opentype.js');

const OUT = process.argv[2];
fs.mkdirSync(OUT, { recursive: true });

const C = {
  bg0: '#0A0F24', bg1: '#1A2352',
  amber: '#FFB547', amberHi: '#FFD58A',
  teal: '#4FD1C5', tealLo: '#2A8F98',
  pl0: '#2E3B8F', pl1: '#7D8CFF',
  star: '#E8ECFF', ink: '#0A0F24', paper: '#F5F3EE',
};

const bgDefs = `
  <radialGradient id="bg" cx="35%" cy="25%" r="90%">
    <stop offset="0" stop-color="${C.bg1}"/><stop offset="1" stop-color="${C.bg0}"/>
  </radialGradient>
  <radialGradient id="planet" cx="35%" cy="30%" r="75%">
    <stop offset="0" stop-color="${C.pl1}"/><stop offset="1" stop-color="${C.pl0}"/>
  </radialGradient>
  <radialGradient id="glow" r="50%">
    <stop offset="0" stop-color="${C.amberHi}" stop-opacity="1"/>
    <stop offset=".35" stop-color="${C.amber}" stop-opacity=".9"/>
    <stop offset="1" stop-color="${C.amber}" stop-opacity="0"/>
  </radialGradient>`;

const stars = (pts) => pts.map(([x, y, r, o]) =>
  `<circle cx="${x}" cy="${y}" r="${r}" fill="${C.star}" opacity="${o}"/>`).join('');

const wrap = (defs, body) => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">
<defs>${bgDefs}${defs}</defs>
<rect width="512" height="512" fill="url(#bg)"/>
${body}
</svg>
`;

// A — Ringed Route: a planet whose ring is a dashed cargo route with one pod on it.
const iconA = wrap(`
  <clipPath id="front"><rect x="0" y="256" width="512" height="256"/></clipPath>`, `
${stars([[78, 92, 3, .8], [430, 70, 2.5, .6], [452, 410, 3, .7], [62, 420, 2, .5], [380, 150, 1.8, .5]])}
<g transform="rotate(-18 256 256)">
  <ellipse cx="256" cy="256" rx="210" ry="64" fill="none" stroke="${C.amber}" stroke-opacity=".55"
    stroke-width="14" stroke-dasharray="34 18" stroke-linecap="round"/>
</g>
<circle cx="256" cy="256" r="122" fill="url(#planet)"/>
<path d="M170 300 Q256 330 342 296" fill="none" stroke="${C.teal}" stroke-opacity=".35" stroke-width="10" stroke-linecap="round"/>
<g transform="rotate(-18 256 256)" clip-path="url(#front)">
  <ellipse cx="256" cy="256" rx="210" ry="64" fill="none" stroke="${C.amber}"
    stroke-width="14" stroke-dasharray="34 18" stroke-linecap="round"/>
</g>
<g transform="rotate(-18 256 256) translate(402 296)">
  <circle r="40" fill="url(#glow)"/>
  <rect x="-17" y="-11" width="34" height="22" rx="6" fill="${C.amberHi}"/>
</g>`);

// B — Gear World: a planet set inside a gear, one moon on its orbit.
function gearPath(cx, cy, rOut, rIn, teeth) {
  const pts = [];
  const step = (Math.PI * 2) / teeth;
  for (let i = 0; i < teeth; i++) {
    const a = i * step - Math.PI / 2;
    const seq = [[rIn, -0.5], [rOut, -0.3], [rOut, 0.3], [rIn, 0.5]];
    for (const [r, f] of seq) {
      const t = a + f * step;
      pts.push([cx + r * Math.cos(t), cy + r * Math.sin(t)]);
    }
  }
  return 'M' + pts.map(([x, y]) => `${x.toFixed(1)} ${y.toFixed(1)}`).join(' L') + ' Z';
}
const iconB = wrap('', `
${stars([[70, 80, 3, .8], [448, 96, 2.5, .6], [440, 440, 3, .7], [80, 430, 2, .5]])}
<circle cx="256" cy="256" r="214" fill="none" stroke="${C.teal}" stroke-opacity=".35" stroke-width="4"/>
<path d="${gearPath(256, 256, 176, 146, 10)}" fill="${C.tealLo}"/>
<circle cx="256" cy="256" r="134" fill="${C.bg0}"/>
<circle cx="256" cy="256" r="118" fill="url(#planet)"/>
<path d="M156 286 Q256 318 356 282" fill="none" stroke="${C.teal}" stroke-opacity=".35" stroke-width="10" stroke-linecap="round"/>
<g transform="translate(${(256 + 214 * Math.cos(-0.75)).toFixed(1)} ${(256 + 214 * Math.sin(-0.75)).toFixed(1)})">
  <circle r="46" fill="url(#glow)"/><circle r="18" fill="${C.amberHi}"/>
</g>`);

// C — A Orbit: the A monogram drawn as an orbit arch, its crossbar a tilted orbit with a cargo ship;
// a small world accreting at the apex.
const iconC = wrap(`
  <linearGradient id="sg" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0" stop-color="${C.teal}"/><stop offset="1" stop-color="${C.amber}"/>
  </linearGradient>
  <clipPath id="frontC"><rect x="0" y="300" width="512" height="212"/></clipPath>`, `
${stars([[80, 88, 3, .8], [440, 110, 2, .6], [436, 440, 3, .7], [72, 430, 2.5, .5], [120, 220, 1.8, .5]])}
<g transform="rotate(-14 256 300)">
  <ellipse cx="256" cy="300" rx="150" ry="40" fill="none" stroke="${C.amber}" stroke-opacity=".45" stroke-width="17"/>
</g>
<path d="M146 416 C 176 290, 208 178, 256 132 C 304 178, 336 290, 366 416"
  fill="none" stroke="url(#sg)" stroke-width="48" stroke-linecap="round" stroke-linejoin="round"/>
<g transform="rotate(-14 256 300)" clip-path="url(#frontC)">
  <ellipse cx="256" cy="300" rx="150" ry="40" fill="none" stroke="${C.amber}" stroke-width="17"/>
</g>
<circle cx="256" cy="120" r="40" fill="url(#planet)"/>
<g transform="rotate(-14 256 300) translate(392 316)"><circle r="46" fill="url(#glow)"/><circle r="17" fill="${C.amberHi}"/></g>`);

fs.writeFileSync(path.join(OUT, 'icon-a-ringed-route.svg'), iconA);
fs.writeFileSync(path.join(OUT, 'icon-b-gear-world.svg'), iconB);
fs.writeFileSync(path.join(OUT, 'icon-c-a-orbit.svg'), iconC);

// Wordmark, outlined to paths so it renders identically everywhere.
const font = opentype.parse(fs.readFileSync(require.resolve('@fontsource/space-grotesk/files/space-grotesk-latin-700-normal.woff')).buffer);
const n = (v) => (Math.round(v * 10) / 10).toString();
function cmds(list) {
  return list.map((c) => {
    if (c.type === 'M' || c.type === 'L') return c.type + n(c.x) + ' ' + n(c.y);
    if (c.type === 'Q') return 'Q' + [c.x1, c.y1, c.x, c.y].map(n).join(' ');
    if (c.type === 'C') return 'C' + [c.x1, c.y1, c.x2, c.y2, c.x, c.y].map(n).join(' ');
    return 'Z';
  }).join('');
}
function wordPath(text, size, tracking) {
  let x = 0; const parts = [];
  for (const ch of text) {
    const g = font.charToGlyph(ch);
    parts.push(cmds(g.getPath(x, size * 0.8, size).commands));
    x += (g.advanceWidth / font.unitsPerEm) * size + tracking;
  }
  return { d: parts.join(''), w: x - tracking };
}
const wm = wordPath('ACCRETE', 96, 10);
for (const [name, fill] of [['wordmark-dark-on-light', C.ink], ['wordmark-light-on-dark', C.paper]]) {
  fs.writeFileSync(path.join(OUT, `${name}.svg`),
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${Math.ceil(wm.w)} 96" width="${Math.ceil(wm.w)}" height="96"><path d="${wm.d}" fill="${fill}"/></svg>\n`);
}
fs.writeFileSync(path.join(OUT, 'wordmark-meta.json'), JSON.stringify({ width: Math.ceil(wm.w), height: 96 }));
console.log('ok', Math.ceil(wm.w));
