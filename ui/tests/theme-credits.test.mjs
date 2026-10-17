// Help menu and Credits & Info page; the dark-only theme configurator, its jokes, presets and persistence.
import { openPage, reporter, sleep } from './lib.mjs';

const page = await openPage(process.argv[2]);
const t = reporter('theme-credits');
const { ev, click, text, hidden, escape, menu } = page;
const setVal = (sel, v) => ev(`(() => { const e = document.querySelector(${JSON.stringify(sel)}); e.value = ${JSON.stringify(v)}; e.dispatchEvent(new Event('input', {bubbles:true})); e.dispatchEvent(new Event('change', {bubbles:true})); return e.value; })()`);
const msg = () => text('#theme-msg');

// --- Help menu and Credits & Info
t.ok('Help menu starts closed', await hidden('.menu[data-menu=help] .menu-pop'));
await click('.menu[data-menu=help] .menu-label');
t.ok('Help menu opens', !(await hidden('.menu[data-menu=help] .menu-pop')));
t.ok('Help has Credits & Info and 3 links', (await ev(`document.querySelectorAll('.menu[data-menu=help] .menu-pop [role=menuitem]').length`)) === 4);
await click('#header-help');
t.ok('the header Help button toggles the same menu', await hidden('.menu[data-menu=help] .menu-pop'));
await menu('help', 'credits');
t.ok('Credits page opens and the controllers are hidden', !(await hidden('#credits-page')) && (await hidden('main')));
t.ok('the menu closes after choosing', await hidden('.menu[data-menu=help] .menu-pop'));
t.ok('credits show the empty volunteer testers state', (await text('#testers-list')).includes('Be the first'));
await escape();
t.ok('Esc returns to the controllers', (await hidden('#credits-page')) && !(await hidden('main')));

// --- theme dialog and light-mode attempts
await menu('view', 'theme');
t.ok('Theme dialog opens', !(await hidden('#theme-modal')));
const startBg = await ev(`window.UJMTheme.current().bg`);
await setVal('#c-bg', '#ffffff');
t.ok('a white background is refused with the first joke', (await msg()) === 'Do you hate your sight?', await msg());
t.ok('the background did not change', (await ev(`window.UJMTheme.current().bg`)) === startBg);
t.ok('the picker went back to the valid color', (await ev(`document.querySelector('#c-bg').value`)) === startBg);
await sleep(1000); await setVal('#t-bg', '#f5f5f5');
t.ok('typing a light hex gets the second joke', (await msg()) === "What's wrong with you? Daywalker.", await msg());
const second = await msg();
await sleep(1000); await setVal('#c-bg', '#cccccc');
t.ok('a third attempt gets another joke', (await msg()) !== second);
await sleep(1000); await setVal('#c-bg', '#ddd'); await sleep(1000); await setVal('#c-bg', '#eeeeee');
t.ok('the fifth attempt says to touch some grass', (await msg()).includes('touch some grass'));
await setVal('#c-accent', '#101010');
t.ok('a too-dim accent is refused', (await msg()).includes('so dim'));
await setVal('#c-text', '#202020');
t.ok('dark text is refused', (await msg()).includes('Denied'));
await setVal('#t-accent', 'banana');
t.ok('garbage input is refused', (await msg()).includes('not a color'));
t.ok('none of the refusals changed the theme', (await ev(`document.querySelector('#ujm-theme-override').textContent.length`)) === 0);

// --- presets, persistence and reset
await click('.preset[data-id=midnight]');
const css = await ev(`document.querySelector('#ujm-theme-override').textContent`);
t.ok('the Midnight preset generates the recolored stylesheet', css.length > 5000, String(css.length));
t.ok('semantic colors are kept (red B button)', css.includes('#f3424d') || css.includes('#ee535d'));
t.ok('the --panel variable changed', (await ev(`getComputedStyle(document.documentElement).getPropertyValue('--panel').trim()`)) !== '#080d09');
await click('#theme-close');
await page.send('Page.reload'); await sleep(1800);
t.ok('the theme survives a reload', (await ev(`window.UJMTheme.current().accent`)) === '#7aa2ff');
await menu('view', 'theme'); await click('#theme-reset');
t.ok('reset restores the default and clears the recolored stylesheet', (await ev(`document.querySelector('#ujm-theme-override').textContent.length`)) === 0);
await click('#theme-close');

// --- disconnected examples remain available as diagram previews, not roster entries
await menu('tools', 'diagram-preview');
await ev(`document.querySelector('#preview-model').value = 'xbox360'`);
await click('#preview-show');
t.ok('the diagram gallery shows Xbox 360 without exposing a disconnected roster card',
  (await text('#selected-name')) === 'Xbox 360 Wireless Controller — diagram preview' && (await hidden('.card[data-controller=xbox360]')));
t.ok('there is no tab strip', (await ev(`document.querySelectorAll('[role=tab]').length`)) === 0);
t.ok('no JavaScript errors', page.errors.length === 0, page.errors.join(' | '));
const failures = t.finish(); page.close(); process.exit(failures ? 1 : 0);
