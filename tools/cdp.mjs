// Minimal Chrome DevTools Protocol driver for headless Edge/Chrome, used to
// capture Week 15 screenshots of the Flutter Web app without extra packages.
import { spawn } from 'node:child_process';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const BROWSERS = [
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  'C:/Program Files/Microsoft/Edge/Application/msedge.exe',
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
];

export const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

export async function launch({ port = 9333, width = 1366, height = 900 } = {}) {
  const { existsSync } = await import('node:fs');
  const exe = BROWSERS.find((p) => existsSync(p));
  if (!exe) throw new Error('No Edge/Chrome found');
  const profile = mkdtempSync(join(tmpdir(), 'w15-cdp-'));
  const proc = spawn(exe, ['--headless=new', `--remote-debugging-port=${port}`, `--user-data-dir=${profile}`,
    '--no-first-run', '--disable-extensions', `--window-size=${width},${height}`, 'about:blank'], { stdio: 'ignore' });

  let target;
  for (let i = 0; i < 50 && !target; i++) {
    await sleep(200);
    try {
      const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
      target = list.find((t) => t.type === 'page');
    } catch { /* not up yet */ }
  }
  if (!target) throw new Error('Browser did not start');

  const ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((r) => ws.addEventListener('open', r, { once: true }));
  let seq = 0;
  const pending = new Map();
  ws.addEventListener('message', (ev) => {
    const msg = JSON.parse(ev.data);
    if (msg.id && pending.has(msg.id)) {
      const { resolve, reject } = pending.get(msg.id);
      pending.delete(msg.id);
      msg.error ? reject(new Error(msg.error.message)) : resolve(msg.result);
    }
  });
  const send = (method, params = {}) => new Promise((resolve, reject) => {
    const id = ++seq;
    pending.set(id, { resolve, reject });
    ws.send(JSON.stringify({ id, method, params }));
  });

  await send('Page.enable');
  await send('Runtime.enable');

  const page = {
    send,
    async viewport(w, h, mobile = false) {
      await send('Emulation.setDeviceMetricsOverride', { width: w, height: h, deviceScaleFactor: 1, mobile });
      await sleep(600);
    },
    async goto(url, waitMs = 4000) {
      await send('Page.navigate', { url });
      await sleep(waitMs);
    },
    async eval(expr) {
      const r = await send('Runtime.evaluate', { expression: expr, returnByValue: true, awaitPromise: true });
      return r.result?.value;
    },
    /** Turn on Flutter's semantics tree so widgets can be located by their labels. */
    async enableSemantics() {
      await page.eval(`(() => { const p = document.querySelector('flt-semantics-placeholder'); if (p) p.click(); return !!p; })()`);
      await sleep(800);
    },
    /** Center of the smallest semantics node whose label/text contains `text` (index picks among matches). */
    async find(text, { index = 0, exact = false } = {}) {
      return page.eval(`(() => {
        const want = ${JSON.stringify(text)}, exact = ${exact};
        const nodes = [...document.querySelectorAll('flt-semantics, [role], input, textarea')];
        const hits = nodes.filter((n) => {
          const label = (n.getAttribute('aria-label') || n.textContent || '').trim();
          return exact ? label === want : label.includes(want);
        }).map((n) => ({ n, r: n.getBoundingClientRect() }))
          .filter(({ r }) => r.width > 0 && r.height > 0)
          .sort((a, b) => a.r.width * a.r.height - b.r.width * b.r.height);
        const h = hits[${index}];
        return h ? { x: h.r.x + h.r.width / 2, y: h.r.y + h.r.height / 2 } : null;
      })()`);
    },
    async clickAt(x, y) {
      for (const type of ['mouseMoved', 'mousePressed', 'mouseReleased']) {
        await send('Input.dispatchMouseEvent', { type, x, y, button: 'left', clickCount: 1 });
      }
      await sleep(500);
    },
    async click(text, opts = {}) {
      const pos = await page.find(text, opts);
      if (!pos) throw new Error(`Not found on screen: ${text}`);
      await page.clickAt(pos.x, pos.y);
    },
    async type(text) {
      await send('Input.insertText', { text });
      await sleep(250);
    },
    async key(key) {
      const codes = { Tab: 9, Enter: 13, Escape: 27 };
      await send('Input.dispatchKeyEvent', { type: 'keyDown', key, windowsVirtualKeyCode: codes[key] });
      await send('Input.dispatchKeyEvent', { type: 'keyUp', key, windowsVirtualKeyCode: codes[key] });
      await sleep(250);
    },
    async fill(label, text, opts) {
      await page.click(label, opts);
      await page.type(text);
    },
    async shot(file, wait = 700) {
      await sleep(wait);
      const { data } = await send('Page.captureScreenshot', { format: 'jpeg', quality: 88 });
      writeFileSync(file, Buffer.from(data, 'base64'));
      console.log('saved', file);
    },
    async close() {
      try { await send('Browser.close'); } catch { /* already closing */ }
      ws.close();
      proc.kill();
    },
  };
  return page;
}
