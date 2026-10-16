// File menu (export/import of controller profiles and app settings, Exit), the simulated service
// button and the simulated Bluetooth shortcuts (pair, connect, disconnect).
import { openPage, reporter, sleep } from './lib.mjs';

const page = await openPage(process.argv[2]);
const t = reporter('file-service-bluetooth');
const { ev, click, text, hidden, escape, menu } = page;
const toast = () => text('#toast');
const importJson = async (kind, content) => {
  await menu('file', kind === 'controllers' ? 'import-controllers' : 'import-settings');
  await ev(`(() => { const i = document.querySelector('#import-file'); const dt = new DataTransfer(); dt.items.add(new File([${JSON.stringify(content)}], 'p.json', {type: 'application/json'})); i.files = dt.files; i.dispatchEvent(new Event('change', {bubbles: true})); })()`);
  await sleep(300);
};
const cardTitle = sel => ev(`document.querySelector(${JSON.stringify(sel + ' h3')}).textContent`);
// capture downloads instead of writing files
await ev(`(() => { window.__dl = []; window.__blobs = []; const co = URL.createObjectURL.bind(URL); URL.createObjectURL = b => { window.__blobs.push(b); return co(b); }; const oc = HTMLAnchorElement.prototype.click; HTMLAnchorElement.prototype.click = function () { if (this.download) { window.__dl.push(this.download); return; } return oc.call(this); }; })()`);

// --- File menu and controller profiles
const actions = await ev(`[...document.querySelectorAll('.menu[data-menu=file] [data-action]')].map(b => b.dataset.action).join(',')`);
t.ok('File has export/import of profiles and settings, and Exit', actions === 'export-controllers,import-controllers,export-settings,import-settings,exit', actions);
const prof = JSON.parse(await ev(`JSON.stringify(window.UJMTools.buildControllerProfiles())`));
t.ok('profiles: format, version and the simulated flag', prof.format === 'ujm-controller-profiles' && prof.version === 1 && prof.simulated === true);
t.ok('profiles: 10 controllers with unique ids, no combined pair', prof.controllers.length === 10 && new Set(prof.controllers.map(c => c.id)).size === 10);
await menu('file', 'export-controllers');
t.ok('export downloads ujm-controller-profiles-YYYYMMDD.json', /^ujm-controller-profiles-\d{8}\.json$/.test(await ev(`window.__dl[0]`)), await ev(`window.__dl[0]`));
t.ok('the downloaded file is valid JSON', JSON.parse(await ev(`window.__blobs[0].text()`)).controllers.length === 10);
await importJson('controllers', JSON.stringify({ format: 'ujm-controller-profiles', version: 1, controllers: [
  { id: 'pro-1', alias: 'Player One' }, { id: 'pro-2', alias: '\u0007  Spacey  ' }, { id: 'ghost-9', alias: 'Nobody' }, { id: 'ds4-5', alias: 42 }, { id: 'xbox360-6', alias: 'x'.repeat(80) }] }));
t.ok('import applies an alias to the card', (await cardTitle('.card[data-controller=pro][data-player="1"]')) === 'Player One');
t.ok('import strips control characters and trims', (await cardTitle('.card[data-controller=pro][data-player="2"]')) === 'Spacey');
t.ok('import cuts long aliases to 40 characters', (await cardTitle('.card[data-controller=xbox360]')).length === 40);
t.ok('the summary counts applied, unknown and invalid entries', /3 applied.*1 unknown.*1 invalid/.test(await toast()), await toast());
t.ok('a long alias without spaces does not overflow the list', (await ev(`[...document.querySelectorAll('main > section.panel .card')].filter(c => c.scrollWidth > c.clientWidth + 1).length`)) === 0);
await importJson('controllers', JSON.stringify({ format: 'ujm-controller-profiles', version: 1, controllers: [{ id: 'pro-1', alias: null }, { id: 'pro-2', alias: null }, { id: 'xbox360-6', alias: null }] }));
t.ok('alias null restores the original name', (await cardTitle('.card[data-controller=pro][data-player="1"]')) === 'Pro Controller — Blue');
await importJson('controllers', 'not json at all');
t.ok('invalid JSON is reported', (await toast()).includes('not valid JSON'), await toast());
await importJson('controllers', JSON.stringify({ format: 'something-else', version: 1 }));
t.ok('a wrong format is reported', (await toast()).includes('ujm-controller-profiles'), await toast());

// --- app settings
const settings = JSON.parse(await ev(`JSON.stringify(window.UJMTools.buildAppSettings())`));
t.ok('settings: format and theme', settings.format === 'ujm-app-settings' && /^#[0-9a-f]{6}$/.test(settings.theme.bg));
await importJson('settings', JSON.stringify({ format: 'ujm-app-settings', version: 1, theme: { bg: '#ffffff', accent: '#9cff88', text: '#e3f6e5' } }));
t.ok('importing a LIGHT theme is refused with a joke', (await toast()).startsWith('Do you hate your sight?'), await toast());
t.ok('...and the theme did not change', (await ev(`window.UJMTheme.current().bg`)) === settings.theme.bg);
await importJson('settings', JSON.stringify({ format: 'ujm-app-settings', version: 1, theme: { bg: '#070a12', accent: '#7aa2ff', text: '#e6ecff' } }));
t.ok('importing a dark theme applies it', (await ev(`window.UJMTheme.current().accent`)) === '#7aa2ff');
await ev(`window.UJMTheme.apply(${JSON.stringify(settings.theme)})`);

// --- service button (simulated)
t.ok('the service starts as running', (await ev(`window.UJMTools.serviceState()`)) === 'running');
t.ok('the status dot sits inside the service pill', await ev(`(() => { const p = document.querySelector('#svc-pill').getBoundingClientRect(), d = document.querySelector('#svc-pill .pill-dot').getBoundingClientRect(); return d.width > 0 && d.left >= p.left && d.right <= p.right && d.top >= p.top && d.bottom <= p.bottom; })()`));
await click('#btn-service');
t.ok('stopping asks for confirmation', !(await hidden('#confirm-modal')));
await click('#confirm-cancel');
t.ok('cancel keeps it running', (await ev(`window.UJMTools.serviceState()`)) === 'running');
await click('#btn-service'); await click('#confirm-ok'); await sleep(1100);
t.ok('the service is stopped and the banner is shown', (await ev(`window.UJMTools.serviceState()`)) === 'stopped' && !(await hidden('#svc-banner')));
t.ok('Pair, Connect and Disconnect are disabled and say why', await ev(`['pair','connect','disconnect'].every(a => { const b = document.querySelector('#toolbar [data-action=' + a + ']'); return b.disabled && b.title.includes('Start the service first'); })`));
await menu('controller', 'service-toggle'); await sleep(1300);
t.ok('the Controller menu starts it again', (await ev(`window.UJMTools.serviceState()`)) === 'running' && (await hidden('#svc-banner')));

// --- connect / disconnect
await click('.card[data-controller=xbox360]');
await click('#btn-connect'); await sleep(1000);
t.ok('Connect marks the selected controller Connected over Bluetooth', (await text('.card[data-controller=xbox360] .status')) === 'Connected' && (await text('.card[data-controller=xbox360] .muted')) === 'Microsoft · Bluetooth');
await click('#btn-disconnect'); await sleep(1000);
t.ok('Disconnect marks it Not connected', (await text('.card[data-controller=xbox360] .status')) === 'Not connected');
await click('.card[data-controller=pro][data-player="2"]');
t.ok('a USB controller has no Bluetooth actions', await ev(`document.querySelector('#btn-connect').disabled && document.querySelector('#btn-disconnect').disabled`));

// --- pairing
await click('#btn-pair');
t.ok('Pair opens the dialog', !(await hidden('#pair-modal')));
await click('#pair-scan'); await sleep(1600);
t.ok('the scan lists controllers with masked addresses only', (await ev(`document.querySelectorAll('#pair-list input').length`)) >= 3 && (await ev(`[...document.querySelectorAll('#pair-list .muted')].every(e => /XX:XX:XX\\)$/.test(e.textContent))`)));
await click('#pair-list input[name=pair-dev]');
const target = await text('#pair-list b');
await click('#pair-go'); await sleep(3400);
t.ok('the log shows the bluetoothctl steps and says it is simulated', /bluetoothctl pair[\s\S]*Pairing successful[\s\S]*Connection successful[\s\S]*Done \(simulated\)/.test(await text('#pair-log')));
t.ok('the paired controller is Connected', await ev(`[...document.querySelectorAll('.card[data-controller]')].some(c => c.querySelector('h3').textContent === ${JSON.stringify(target)} && c.querySelector('.status').textContent === 'Connected')`), target);
await escape();
t.ok('Esc closes the pairing dialog', await hidden('#pair-modal'));

// --- exit
await menu('file', 'exit');
t.ok('Exit asks first and says the service keeps running', !(await hidden('#confirm-modal')) && (await text('#confirm-text')).includes('service keeps running'));
await escape();
t.ok('Esc cancels the exit', (await hidden('#confirm-modal')) && (await hidden('#exit-screen')));
await menu('file', 'exit'); await click('#confirm-ok'); await sleep(200);
t.ok('confirming shows the exit screen', !(await hidden('#exit-screen')));
await click('#exit-reopen'); await sleep(1800);
t.ok('Reopen reloads the interface', await hidden('#exit-screen'));
t.ok('no JavaScript errors', page.errors.length === 0, page.errors.join(' | '));
const failures = t.finish(); page.close(); process.exit(failures ? 1 : 0);
