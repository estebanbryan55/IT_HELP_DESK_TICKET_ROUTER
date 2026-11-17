// Runs a Postman v2.1 collection without installing Newman.
// Supports the subset of the pm.* API used by the Week 15 collection:
// pm.test, pm.expect (eql/equal/include/exist/above/oneOf), pm.response.*,
// pm.collectionVariables.get/set and pre-request scripts.
//
//   node tools/run-collection.mjs postman/Week15_IA6_HelpDesk.postman_collection.json \
//        --base http://127.0.0.1:8000/api/v1 --out evidence/run.json
import { readFileSync, writeFileSync } from 'node:fs';

const args = process.argv.slice(2);
const file = args[0];
const opt = (name, def) => {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : def;
};
const collection = JSON.parse(readFileSync(file, 'utf8'));
const vars = new Map((collection.variable ?? []).map((v) => [v.key, v.value]));
vars.set('baseUrl', opt('--base', vars.get('baseUrl')));
const label = opt('--label', 'run');
const outFile = opt('--out', null);

// Evidence must never contain bearer tokens, even lab ones.
const redact = (s) => s.replace(/"token":"[^"]*"/g, '"token":"[REDACTED]"');

const subst = (s) => (s ?? '').replace(/\{\{(\w+)\}\}/g, (_, k) => vars.get(k) ?? '');

function expect(actual) {
  const fail = (msg) => { throw new Error(msg); };
  const show = (v) => JSON.stringify(v);
  const api = {
    eql: (v) => JSON.stringify(actual) === JSON.stringify(v) || fail(`expected ${show(actual)} to eql ${show(v)}`),
    equal: (v) => actual === v || fail(`expected ${show(actual)} to equal ${show(v)}`),
    include: (v) => (actual ?? '').includes(v) || fail(`expected value to include ${show(v)}`),
    exist: () => (actual !== undefined && actual !== null) || fail('expected value to exist'),
    above: (n) => actual > n || fail(`expected ${actual} to be above ${n}`),
    oneOf: (list) => list.includes(actual) || fail(`expected ${show(actual)} to be one of ${show(list)}`),
  };
  const neg = {
    include: (v) => !(actual ?? '').includes(v) || fail(`expected value not to include ${show(v)}`),
    exist: () => (actual === undefined || actual === null) || fail(`expected no value, got ${show(actual)}`),
    equal: (v) => actual !== v || fail(`expected value not to equal ${show(v)}`),
  };
  return { to: { ...api, be: { ...api, ok: api.exist }, not: { ...neg, be: neg } } };
}

function makePm(response, tests) {
  let parsed;
  const res = response && {
    code: response.status,
    text: () => response.body,
    json: () => (parsed ??= JSON.parse(response.body)),
    headers: { get: (h) => response.headers.get(h) ?? undefined },
    responseTime: response.ms,
  };
  if (res) {
    res.to = { have: {
      status: (n) => { if (res.code !== n) throw new Error(`expected status ${n}, got ${res.code}`); },
      header: (h) => { if (!response.headers.has(h)) throw new Error(`expected header ${h}`); },
    } };
  }
  return {
    response: res,
    expect,
    test: (name, fn) => {
      try { fn(); tests.push({ name, pass: true }); } catch (e) { tests.push({ name, pass: false, error: e.message }); }
    },
    collectionVariables: { get: (k) => vars.get(k), set: (k, v) => vars.set(k, String(v)) },
    environment: { get: (k) => vars.get(k), set: (k, v) => vars.set(k, String(v)) },
  };
}

function runScript(item, type, pm) {
  const ev = (item.event ?? []).find((e) => e.listen === type);
  if (!ev) return;
  const code = Array.isArray(ev.script.exec) ? ev.script.exec.join('\n') : ev.script.exec;
  new Function('pm', code)(pm);
}

function* walk(items, path = []) {
  for (const it of items) {
    if (it.item) yield* walk(it.item, [...path, it.name]);
    else yield { ...it, folder: path.join(' / ') };
  }
}

const results = [];
const started = new Date();
for (const item of walk(collection.item)) {
  const tests = [];
  runScript(item, 'prerequest', makePm(null, tests));
  const r = item.request;
  const url = subst(typeof r.url === 'string' ? r.url : r.url.raw);
  const headers = Object.fromEntries((r.header ?? []).filter((h) => !h.disabled).map((h) => [h.key, subst(h.value)]));
  const body = r.body?.raw !== undefined ? subst(r.body.raw) : undefined;

  const t0 = performance.now();
  let response;
  try {
    const res = await fetch(url, { method: r.method, headers, body, signal: AbortSignal.timeout(15000) });
    response = { status: res.status, headers: res.headers, body: await res.text(), ms: Math.round(performance.now() - t0) };
  } catch (e) {
    response = { status: 0, headers: new Headers(), body: String(e.cause?.code ?? e.message), ms: Math.round(performance.now() - t0) };
  }
  runScript(item, 'test', makePm(response, tests));

  const pass = tests.length > 0 && tests.every((t) => t.pass);
  results.push({
    folder: item.folder, name: item.name, method: r.method, url: url.replace(vars.get('baseUrl'), ''),
    status: response.status, ms: response.ms, correlationId: response.headers.get('x-correlation-id'),
    pass, tests, responseExcerpt: redact(response.body).slice(0, 300),
  });
  const mark = pass ? 'PASS' : 'FAIL';
  console.log(`${mark}  ${String(response.status).padEnd(3)}  ${String(response.ms).padStart(4)}ms  ${item.name}`);
  for (const t of tests.filter((x) => !x.pass)) console.log(`        - ${t.name}: ${t.error}`);
}

const passed = results.filter((r) => r.pass).length;
console.log(`\n${label}: ${passed}/${results.length} requests passed, ${results.length - passed} failed  (${started.toISOString()})`);
if (outFile) {
  writeFileSync(outFile, JSON.stringify({ label, started: started.toISOString(), baseUrl: vars.get('baseUrl'), passed, total: results.length, results }, null, 2));
}
process.exitCode = passed === results.length ? 0 : 1;
