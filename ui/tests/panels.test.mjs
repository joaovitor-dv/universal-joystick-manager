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

const assetFailures = page.failed.filter(f => !/favicon\.ico/.test(f));
t.ok('no asset request failed', assetFailures.length === 0, assetFailures.join(' | '));
const failures = t.finish(); page.close(); process.exit(failures ? 1 : 0);
