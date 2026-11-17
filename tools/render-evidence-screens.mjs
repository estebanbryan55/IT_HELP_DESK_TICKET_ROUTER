// Turns the saved text evidence into terminal-style screenshots
// (evidence/screenshots/test-*.jpg) for the report.
//   node tools/render-evidence-screens.mjs
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { launch } from './cdp.mjs';

const ev = fileURLToPath(new URL('../evidence/', import.meta.url));
const shots = [
  ['01-baseline-phpunit-before-fixes.txt', 'test-01-phpunit-BEFORE-fixes.jpg', 'php artisan test --testdox   (Week 14 code + new Week 15 tests)'],
  ['04-phpunit-after-fixes.txt', 'test-02-phpunit-AFTER-fixes.jpg', 'vendor/bin/phpunit --testdox   (Week 15 code)'],
  ['02-baseline-postman-run.txt', 'test-03-postman-BEFORE-fixes.jpg', 'node tools/run-collection.mjs postman/Week15_IA6_HelpDesk.postman_collection.json'],
  ['05-regression-postman-run.txt', 'test-04-postman-AFTER-fixes.jpg', 'node tools/run-collection.mjs postman/Week15_IA6_HelpDesk.postman_collection.json'],
  ['03-baseline-failure-injection.txt', 'test-05-failure-injection-BEFORE.jpg', 'bash tools/failure-injection.sh'],
  ['06-failure-injection-after-fixes.txt', 'test-06-failure-injection-AFTER.jpg', 'bash tools/failure-injection.sh'],
  ['08-flutter-tests.txt', 'test-07-flutter-tests.jpg', 'flutter test --reporter expanded'],
  ['08b-flutter-DEF10-before-fix.txt', 'test-08-flutter-DEF10-before-fix.jpg', 'flutter test --plain-name "ST-03"   (before fix)'],
  ['09-secret-and-config-scan.txt', 'test-09-secret-and-config-scan.jpg', 'bash tools/secret-scan.sh'],
  ['07-protected-log-excerpt.txt', 'test-10-protected-log-excerpt.jpg', 'storage/logs/laravel.log (excerpt)'],
];

const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const colour = (line) => {
  if (/^\s*(PASS\b|\[x\]|✔)|All tests passed|requests passed, 0 failed|^OK \(/.test(line)) return 'ok';
  if (/^\s*(FAIL\b|\[ \]|✘|-> )|Some tests failed|ERRORS!|FAILURES!|Fatal|Exception|500 Internal|^\s+- /.test(line)) return 'bad';
  if (/^(=+|---|##|#|>)/.test(line)) return 'head';
  if (/503|Retry-After|degraded|unreachable after/.test(line)) return 'warn';
  return '';
};

const dir = mkdtempSync(join(tmpdir(), 'w15-render-'));
const page = await launch({ port: 9334 });
try {
  for (const [src, out, cmd] of shots) {
    const text = readFileSync(join(ev, src), 'utf8').replace(/\r/g, '');
    const lines = text.split('\n').map((l) => `<div class="${colour(l)}">${esc(l) || '&nbsp;'}</div>`).join('');
    const html = `<!doctype html><meta charset="utf-8"><style>
      body{margin:0;background:#0d1117;font:13px/1.45 Consolas,'Cascadia Mono',monospace;color:#c9d1d9}
      .bar{background:#161b22;padding:10px 16px;border-bottom:1px solid #30363d;color:#8b949e}
      .bar b{color:#e6edf3}.cmd{color:#7ee787}
      pre{margin:0;padding:12px 16px;white-space:pre-wrap;word-break:break-word}
      .ok{color:#3fb950}.bad{color:#f85149}.head{color:#79c0ff;font-weight:bold}.warn{color:#d29922}
    </style><div class="bar"><b>Week 15 evidence</b> · ${esc(src)}<br><span class="cmd">$ ${esc(cmd)}</span></div><pre>${lines}</pre>`;
    const file = join(dir, `${out}.html`);
    writeFileSync(file, html);
    await page.viewport(1200, 800);
    await page.goto(pathToFileURL(file).href, 800);
    const height = await page.eval('document.documentElement.scrollHeight');
    await page.viewport(1200, Math.min(Math.max(height, 300), 6000));
    await page.shot(join(ev, 'screenshots', out), 300);
  }
} finally {
  await page.close();
}
