// Tiny headless-Chromium harness for the interface tests (no dependencies).
// Needs Node.js 22+ (global WebSocket and fetch) and Chromium/Chrome (CHROME=/path/to/browser).
import { spawn } from 'node:child_process';
import { mkdtempSync, readFileSync, existsSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

export const sleep = ms => new Promise(r => setTimeout(r, ms));

export async function openPage(url, { width = 1440, height = 1000 } = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'ujm-ui-'));
  const bin = process.env.CHROME || 'chromium';
  const args = ['--headless=new', '--disable-gpu', '--hide-scrollbars', '--no-first-run', '--no-default-browser-check',
    '--remote-debugging-port=0', `--user-data-dir=${dir}`];
  if (process.env.CI) args.push('--no-sandbox');
  const chrome = spawn(bin, [...args, 'about:blank'], { stdio: 'ignore' });
  chrome.on('error', e => { console.error(`could not start ${bin}: ${e.message}`); process.exit(2); });
  let port;
  for (let i = 0; i < 80 && !port; i++) {
    const f = join(dir, 'DevToolsActivePort');
    if (existsSync(f)) port = readFileSync(f, 'utf8').split('\n')[0]; else await sleep(250);
  }
  if (!port) throw new Error(`${bin} did not open a DevTools port`);
  let target;
  for (let i = 0; i < 40 && !target; i++) {
    try { target = (await (await fetch(`http://127.0.0.1:${port}/json`)).json()).find(t => t.type === 'page'); } catch { /* not ready */ }
    if (!target) await sleep(250);
  }
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => { ws.addEventListener('open', resolve); ws.addEventListener('error', reject); });

  let id = 0; const pending = new Map(); const errors = []; const failed = []; const urls = new Map(); const requested = new Set();
  ws.addEventListener('message', e => {
    const m = JSON.parse(e.data);
    if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
    if (m.method === 'Runtime.exceptionThrown') errors.push(m.params.exceptionDetails.text + ' ' + ((m.params.exceptionDetails.exception || {}).description || '').split('\n')[0]);
    if (m.method === 'Runtime.consoleAPICalled' && m.params.type === 'error') errors.push('console.error ' + m.params.args.map(a => a.value ?? a.description).join(' '));
    if (m.method === 'Network.requestWillBeSent') { urls.set(m.params.requestId, m.params.request.url); requested.add(m.params.request.url); }
    if (m.method === 'Network.responseReceived' && m.params.response.status >= 400) failed.push(m.params.response.status + ' ' + m.params.response.url);
    if (m.method === 'Network.loadingFailed') failed.push('failed ' + (urls.get(m.params.requestId) || '?') + ' ' + m.params.errorText);
  });
  const send = (method, params = {}) => new Promise(res => { const i = ++id; pending.set(i, res); ws.send(JSON.stringify({ id: i, method, params })); });
  const ev = async expr => {
    const r = await send('Runtime.evaluate', { expression: expr, returnByValue: true, awaitPromise: true });
    if (r.result && r.result.exceptionDetails) errors.push('evaluate: ' + r.result.exceptionDetails.text + ' in ' + expr.slice(0, 60));
    return r.result && r.result.result ? r.result.result.value : undefined;
  };
  await send('Page.enable'); await send('Runtime.enable'); await send('Network.enable');
  await send('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: 1, mobile: false });
  await send('Page.navigate', { url }); await sleep(1800);
  const close = () => { try { ws.close(); } catch { /* closed */ } chrome.kill('SIGKILL'); try { rmSync(dir, { recursive: true, force: true }); } catch { /* busy */ } };
  const helpers = {
    click: sel => ev(`document.querySelector(${JSON.stringify(sel)}).click()`),
    text: sel => ev(`document.querySelector(${JSON.stringify(sel)}).textContent`),
    hidden: sel => ev(`document.querySelector(${JSON.stringify(sel)}).hidden`),
    escape: () => ev(`document.dispatchEvent(new KeyboardEvent('keydown', {key: 'Escape'}))`),
    menu: async (m, action) => { await helpers.click(`.menu[data-menu=${m}] .menu-label`); await helpers.click(`[data-action=${action}]`); }
  };
  return { send, ev, errors, failed, requested, close, ...helpers };
}

export function reporter(name) {
  const results = [];
  return {
    ok(label, cond, extra = '') { results.push([!!cond, label, extra]); },
    finish() {
      for (const [c, l, x] of results) console.log(`${c ? 'ok  ' : 'FAIL'} ${l}${x ? '  [' + String(x).slice(0, 140) + ']' : ''}`);
      const failures = results.filter(r => !r[0]).length;
      console.log(`${name}: ${results.length - failures}/${results.length} passed`);
      return failures;
    }
  };
}
