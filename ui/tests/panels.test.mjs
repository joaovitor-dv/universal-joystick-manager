// Every controller panel renders: assets load, nothing overflows, no JavaScript errors,
// and the colored face buttons of the Joy-Con diagrams sit on the drawn circles.
import { openPage, reporter, sleep } from './lib.mjs';

const page = await openPage(process.argv[2]);
const t = reporter('panels');
const { ev, click } = page;

const cards = await ev(`[...document.querySelectorAll('.card[data-controller]')].map(c => [c.dataset.controller, c.dataset.player || ''])`);
t.ok('the prototype retains 10 slots and a separate Joy-Con pair diagram for review', cards.length === 11, String(cards.length));
const initialRoster = await ev(`(() => ({
  connected:[...document.querySelectorAll('.card[data-player]')].filter(c => !c.hidden).map(c => c.dataset.player),
  disconnectedVisible:[...document.querySelectorAll('.card[data-player]')].filter(c => c.querySelector('.status').textContent === 'Not connected' && !c.hidden).length,
  pairHidden:document.querySelector('.card[data-controller="joyconpair"]').hidden,
  columns:getComputedStyle(document.querySelector('.cards')).gridTemplateColumns.split(' ').length,
  count:document.querySelector('#device-count').textContent
}))()`);
t.ok('only connected controllers appear in the two-column roster',
  JSON.stringify(initialRoster.connected) === JSON.stringify(['1','2','3']) && initialRoster.disconnectedVisible === 0 &&
  initialRoster.pairHidden && initialRoster.columns === 2 && initialRoster.count === 'Connected: 3 / 10', JSON.stringify(initialRoster));
const officialNames = await ev(`[...document.querySelectorAll('.card[data-player] h3')].map(el => el.textContent)`);
t.ok('cards use model names rather than color nicknames or series-as-product names',
  officialNames[0] === 'Nintendo Switch Pro Controller' && officialNames[2] === 'DUALSHOCK 3 Wireless Controller' &&
  officialNames[7] === 'Xbox Wireless Controller (Series X|S)' && officialNames[8] === 'Joy-Con (L)' && officialNames[9] === 'Joy-Con (R)',
  JSON.stringify(officialNames));
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

await click('.card[data-controller="joyconl"]'); await sleep(500);
const joyconL = await ev(`(() => {
  const buttons = [...document.querySelectorAll('#controller-diagram [data-joycon-shoulder]')];
  const rail = [...document.querySelectorAll('.keys[data-controller="joyconl"] .key--rail img')];
  return { labels:buttons.map(button => button.dataset.joyconShoulder),
    boxes:buttons.map(button => { const b = button.getBBox(); return {left:b.x,right:b.x+b.width}; }),
    railCount:rail.length, railTransforms:rail.map(icon => getComputedStyle(icon).transform) };
})()`);
t.ok('Joy-Con L has four distinct shoulder and rail miniatures',
  JSON.stringify(joyconL.labels) === JSON.stringify(['L','SL','SR','ZL']) &&
  joyconL.boxes.every((box,index) => index === 0 || joyconL.boxes[index-1].right < box.left),
  JSON.stringify(joyconL));
t.ok('Joy-Con L rail icons are upright in the horizontal layout',
  joyconL.railCount === 2 && joyconL.railTransforms.every(value => /^matrix\(0, -1, 1, 0,/.test(value)),
  JSON.stringify(joyconL.railTransforms));

await click('.card[data-controller="joyconr"]'); await sleep(500);
const joyconR = await ev(`(() => {
  const buttons = [...document.querySelectorAll('#controller-diagram [data-joycon-shoulder]')];
  const rail = [...document.querySelectorAll('.keys[data-controller="joyconr"] .key--rail img')];
  const faces = ['A','B','X','Y'].map(label => {
    const symbol = document.querySelector('.keys[data-controller="joyconr"] .key--nintendo-' + label.toLowerCase() + ' .key-symbol');
    const style = getComputedStyle(symbol);
    return {label, width:symbol.getBoundingClientRect().width, color:style.color, background:style.backgroundColor};
  });
  return {labels:buttons.map(button => button.dataset.joyconShoulder),
    boxes:buttons.map(button => { const b = button.getBBox(); return {left:b.x,right:b.x+b.width}; }),
    railCount:rail.length, railTransforms:rail.map(icon => getComputedStyle(icon).transform), faces};
})()`);
t.ok('Joy-Con R has four distinct shoulder and rail miniatures',
  JSON.stringify(joyconR.labels) === JSON.stringify(['R','SL','SR','ZR']) &&
  joyconR.boxes.every((box,index) => index === 0 || joyconR.boxes[index-1].right < box.left),
  JSON.stringify(joyconR));
t.ok('Joy-Con R rail icons are upright in the horizontal layout',
  joyconR.railCount === 2 && joyconR.railTransforms.every(value => /^matrix\(0, 1, -1, 0,/.test(value)),
  JSON.stringify(joyconR.railTransforms));
t.ok('Joy-Con R face buttons use visible SNES-color disks like the Pro Controller',
  joyconR.faces.length === 4 && joyconR.faces.every(face => face.width === 30 && face.color === 'rgb(255, 255, 255)' && face.background !== 'rgba(0, 0, 0, 0)'),
  JSON.stringify(joyconR.faces));

await click('.card[data-controller="joyconpair"]'); await sleep(500);
const joyconPairFaces = await ev(`(() => ['A','B','X','Y'].map(label => {
  const key = document.querySelector('.keys[data-controller="joyconpair"] .key--nintendo-' + label.toLowerCase());
  const symbol = key?.querySelector('.key-symbol');
  const frame = key?.getBoundingClientRect(), face = symbol?.getBoundingClientRect();
  const style = symbol && getComputedStyle(symbol);
  return {label, width:face?.width, height:face?.height, color:style?.color, background:style?.backgroundColor,
    topGap:frame && face ? face.top-frame.top : null, bottomGap:frame && face ? frame.bottom-face.bottom : null,
    leftGap:frame && face ? face.left-frame.left : null, rightGap:frame && face ? frame.right-face.right : null};
}))()`);
const joyconPairColors = {A:'rgb(226, 52, 65)', B:'rgb(237, 185, 41)', X:'rgb(40, 121, 223)', Y:'rgb(29, 174, 114)'};
t.ok('Combined Joy-Cons A/B/X/Y use centered, readable SNES-color disks',
  joyconPairFaces.length === 4 && joyconPairFaces.every(face =>
    face.width === 30 && face.height === 30 && face.color === 'rgb(255, 255, 255)' &&
    face.background === joyconPairColors[face.label] &&
    Math.abs(face.topGap-face.bottomGap) <= 0.5 && Math.abs(face.leftGap-face.rightGap) <= 0.5),
  JSON.stringify(joyconPairFaces));

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

await click('.card[data-controller="pro"][data-player="1"]');
await page.menu('tools', 'create-alias');
const aliasOpen = await ev(`!document.querySelector('#alias-modal').hidden && document.querySelector('#alias-device').textContent.includes('Nintendo Switch Pro Controller')`);
await ev(`document.querySelector('#alias-input').value = 'Living room controller'; document.querySelector('#alias-form').requestSubmit()`);
const aliasResult = await ev(`({name:document.querySelector('.card[data-player="1"] h3').textContent, selected:document.querySelector('#selected-name').textContent, exported:window.UJMTools.buildControllerProfiles().controllers[0].alias})`);
t.ok('Tools creates an alias for the selected connected controller without changing its official model',
  aliasOpen && aliasResult.name === 'Living room controller' && aliasResult.selected.includes('Living room controller') && aliasResult.exported === 'Living room controller', JSON.stringify(aliasResult));
await page.menu('tools', 'diagram-preview');
const previewOptions = await ev(`({open:!document.querySelector('#preview-modal').hidden, models:[...document.querySelector('#preview-model').options].map(o=>o.value)})`);
await ev(`document.querySelector('#preview-model').value = 'joyconpair'`);
await click('#preview-show');
const previewResult = await ev(`({selected:document.querySelector('#selected-name').textContent, active:document.querySelectorAll('.card.selected').length, status:document.querySelector('#diagnostic-panel > .row .status').textContent})`);
t.ok('Tools diagram gallery keeps disconnected models out of the live roster', previewOptions.open && previewOptions.models.includes('joyconpair') && previewResult.selected.includes('diagram preview') && previewResult.active === 0 && previewResult.status === 'Preview only', JSON.stringify({previewOptions,previewResult}));
await page.menu('tools', 'preview-ten');
const highSlots = await ev(`(() => [9,10].map(player => { const c=document.querySelector('.card[data-player="'+player+'"]'); return {player,visible:!c.hidden,mask:[...c.querySelectorAll('.led')].map(l=>l.classList.contains('on'))}; }))()`);
t.ok('ten-player preview shows the four-LED patterns 2+3+4 and 1+2+3+4',
  highSlots[0].visible && highSlots[1].visible &&
  JSON.stringify(highSlots[0].mask) === JSON.stringify([false,true,true,true]) &&
  JSON.stringify(highSlots[1].mask) === JSON.stringify([true,true,true,true]), JSON.stringify(highSlots));
const tenGrid = await ev(`({count:document.querySelector('#device-count').textContent, rows:getComputedStyle(document.querySelector('.cards')).gridTemplateRows.split(' ').length, preview:!document.querySelector('#roster-preview-note').hidden})`);
t.ok('the explicit layout preview uses two columns and five rows for ten simulated controllers', tenGrid.count === 'Connected: 10 / 10' && tenGrid.rows === 5 && tenGrid.preview, JSON.stringify(tenGrid));
await page.menu('tools', 'preview-ten');
const restored = await ev(`({count:document.querySelector('#device-count').textContent, hidden:document.querySelector('.card[data-player="9"]').hidden, preview:document.querySelector('#roster-preview-note').hidden})`);
t.ok('leaving the layout preview restores the original connected roster', restored.count === 'Connected: 3 / 10' && restored.hidden && restored.preview, JSON.stringify(restored));
await ev(`window.UJMTools.simulateConnection(1,false)`);
const disconnected = await ev(`({hidden:document.querySelector('.card[data-player="1"]').hidden, count:document.querySelector('#device-count').textContent, alias:document.querySelector('.card[data-player="1"] h3').textContent})`);
t.ok('disconnecting removes a card from the roster without losing its alias', disconnected.hidden && disconnected.count === 'Connected: 2 / 10' && disconnected.alias === 'Living room controller', JSON.stringify(disconnected));

const assetFailures = page.failed.filter(f => !/favicon\.ico/.test(f));
t.ok('no asset request failed', assetFailures.length === 0, assetFailures.join(' | '));
const failures = t.finish(); page.close(); process.exit(failures ? 1 : 0);
