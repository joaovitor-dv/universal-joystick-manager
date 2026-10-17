// Every controller panel renders: assets load, nothing overflows, no JavaScript errors,
// and the colored face buttons of the Joy-Con diagrams sit on the drawn circles.
import { openPage, reporter, sleep } from './lib.mjs';

const page = await openPage(process.argv[2]);
const t = reporter('panels');
const { ev, click } = page;

const cards = await ev(`[...document.querySelectorAll('.card[data-controller]')].map(c => [c.dataset.controller, c.dataset.player || ''])`);
t.ok('the list has 11 controller panels (10 controllers and the combined Joy-Cons)', cards.length === 11, String(cards.length));
for (const [ctrl, player] of cards) {
  const sel = player ? `.card[data-controller="${ctrl}"][data-player="${player}"]` : `.card[data-controller="${ctrl}"]`;
  const before = page.errors.length;
  await click(sel); await sleep(900);
  const info = await ev(`(() => {
    const diag = document.querySelector('#diagnostic-panel'), d = diag.getBoundingClientRect();
    const imgs = [...diag.querySelectorAll('img')];
    const broken = imgs.filter(i => !i.complete || i.naturalWidth === 0).map(i => i.getAttribute('src'));
    const overflow = [...diag.querySelectorAll('*')].filter(el => { const r = el.getBoundingClientRect(); return r.width > 0 && (r.right > d.right + 2 || r.left < d.left - 2); }).length;
    return { name: document.querySelector('#selected-name').textContent, images: imgs.length, broken, overflow, scrollX: document.documentElement.scrollWidth > window.innerWidth };
  })()`);
  const label = `${ctrl}${player ? '-' + player : ''} (${info.name})`;
  t.ok(`${label}: all ${info.images} images loaded`, info.broken.length === 0, info.broken.join(', '));
  t.ok(`${label}: nothing overflows the panel`, info.overflow === 0 && !info.scrollX);
  t.ok(`${label}: no JavaScript errors`, page.errors.length === before, page.errors.slice(before).join(' | '));
}

// The Xbox 360 XCF's lower backdrop must not return through a second image or
// label overlay. The single, cropped vector export includes its own colors/text.
await click('.card[data-controller="xbox360"]'); await sleep(500);
const xbox360 = await ev(`(() => {
  const art = document.querySelector('#controller-diagram .controller-art--xbox360');
  const image = art?.querySelector('img');
  if (!image || !image.complete || !image.naturalWidth) return {loaded:false};
  const canvas = document.createElement('canvas'); canvas.width = 1; canvas.height = 1;
  canvas.getContext('2d').drawImage(image, 0, 0, 1, 1, 0, 0, 1, 1);
  return {loaded:true, src:image.getAttribute('src'), images:art.querySelectorAll('img').length,
    overlays:art.querySelectorAll('svg, .diagram-face').length, filter:getComputedStyle(image).filter,
    cornerAlpha:canvas.getContext('2d').getImageData(0, 0, 1, 1).data[3]};
})()`);
t.ok('Xbox 360 uses only the new XCF-derived vector diagram', xbox360.loaded && xbox360.src === 'assets/controller-references/xbox-360-xcf-ui.svg' && xbox360.images === 1 && xbox360.overlays === 0, JSON.stringify(xbox360));
t.ok('Xbox 360 diagram has a transparent background and no color filter', xbox360.cornerAlpha === 0 && xbox360.filter === 'none', JSON.stringify(xbox360));

// Face overlays are percentages of the picture; on the Joy-Con diagrams the picture sits below a band
// for the shoulder miniatures, so the overlays must be rescaled. Expected deviation: about 0 px.
const faces = {
  joyconr: [['Y', 73.5, 46.5], ['X', 80.8, 63.3], ['B', 66.4, 63.3], ['A', 73.5, 79.5]],
  joyconpair: [['X', 83.3, 19.3], ['Y', 75.8, 26.6], ['A', 90.5, 26.6], ['B', 83.3, 33.7]]
};
for (const [type, list] of Object.entries(faces)) {
  await click(`.card[data-controller="${type}"]`); await sleep(700);
  const dev = await ev(`(() => {
    const art = document.querySelector('#diagnostic-panel .controller-art'), pic = art.querySelector('svg image') || art.querySelector('img');
    const r = pic.getBoundingClientRect();
    return ${JSON.stringify(list)}.map(([l, x, y]) => { const m = art.querySelector('.diagram-face--' + l.toLowerCase()); if (!m) return 999;
      const b = m.getBoundingClientRect(); return Math.hypot(b.left + b.width / 2 - (r.left + x / 100 * r.width), b.top + b.height / 2 - (r.top + y / 100 * r.height)); });
  })()`);
  t.ok(`${type}: colored A/B/X/Y sit on the drawn circles (max ${Math.max(...dev).toFixed(1)} px)`, Math.max(...dev) <= 2);
}

// Perspective diagrams must expose four distinct, separated shoulder/trigger shapes,
// and the filtered source linework must be mapped to a visible cool-white rather than shell black.
const shoulders = {
  pro: ['ZL','L','R','ZR'], dualsense: ['L2','L1','R1','R2'], ds4: ['L2','L1','R1','R2'],
  xboxone: ['LT','LB','RB','RT'], xboxseries: ['LT','LB','RB','RT']
};
for (const [type, expected] of Object.entries(shoulders)) {
  await click(`.card[data-controller="${type}"]`); await sleep(500);
  const found = await ev(`(() => {
    const art = document.querySelector('#controller-diagram .controller-art');
    const shapes = [...art.querySelectorAll('[data-shoulder-control]')].map(el => { const r = el.getBBox(); return {label:el.dataset.shoulderControl, x:r.x, y:r.y, right:r.x+r.width, bottom:r.y+r.height}; });
    const matrix = art.querySelector('#controller-outline feColorMatrix');
    const values = matrix?.getAttribute('values').trim().split(/\\s+/).map(Number) || [];
    return {labels:shapes.map(s=>s.label), shapes, light:values.length===20 && values[4]>.8 && values[9]>.8 && values[14]>.8};
  })()`);
  const separated = found.shapes.length === 4 && found.shapes.every((a,i) => found.shapes.slice(i+1).every(b => a.right <= b.x + .1 || b.right <= a.x + .1 || a.bottom <= b.y + .1 || b.bottom <= a.y + .1));
  t.ok(`${type}: exactly four separately outlined L/R shoulder and trigger buttons`, JSON.stringify(found.labels) === JSON.stringify(expected) && separated, JSON.stringify(found));
  t.ok(`${type}: controller detail lines render in a light palette`, found.light, JSON.stringify(found));
}

await click('.card[data-controller="xboxseries"]'); await sleep(500);
const seriesShare = await ev(`(() => {
  const art = document.querySelector('#controller-diagram svg');
  const share = art?.querySelector('[data-share-control="xbox-series"]');
  const transform = share?.getAttribute('transform') || '';
  const coords = transform.startsWith('translate(') ? transform.slice(10, -1).split(' ').map(Number) : [];
  return { count: art?.querySelectorAll('[data-share-control]').length || 0,
    x: coords[0] ?? null, y: coords[1] ?? null,
    transparent: share?.getAttribute('fill') === 'none' };
})()`);
t.ok('Xbox Series Share sits on the center bridge above the sticks', seriesShare.count === 1 && seriesShare.x === 500 && seriesShare.y >= 370 && seriesShare.y <= 430 && seriesShare.transparent, JSON.stringify(seriesShare));

await click('.card[data-controller="ds4"]'); await sleep(500);
const ds4System = await ev(`(() => ['SHARE', 'OPTIONS'].map(label => {
  const tile = [...document.querySelectorAll('.keys[data-controller="ds4"] .key')].find(el => el.getAttribute('aria-label') === label);
  const frame = tile?.getBoundingClientRect();
  const img = tile?.querySelector('img');
  const bounds = img?.getBoundingClientRect();
  return { label, frameWidth:frame?.width, frameHeight:frame?.height,
    iconWidth:bounds?.width, iconHeight:bounds?.height,
    topGap:frame && bounds ? bounds.top-frame.top : null,
    bottomGap:frame && bounds ? frame.bottom-bounds.bottom : null,
    loaded:!!img?.complete && img.naturalWidth > 0 };
}))()`);
t.ok('DualShock 4 Share/Options use legible icons centered in standard 42×38 frames', ds4System.every(s => s.loaded && s.frameWidth === 42 && s.frameHeight === 38 && s.iconWidth === 34 && s.iconHeight === 24 && Math.abs(s.topGap-s.bottomGap) <= 0.5), JSON.stringify(ds4System));

const assetFailures = page.failed.filter(f => !/favicon\.ico/.test(f));
t.ok('no asset request failed', assetFailures.length === 0, assetFailures.join(' | '));
const failures = t.finish(); page.close(); process.exit(failures ? 1 : 0);
