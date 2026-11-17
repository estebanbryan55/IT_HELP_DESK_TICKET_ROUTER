// Week 15 UI evidence: drives the real Flutter Web build (http://localhost:5015)
// against the real Laravel API (:8015) in headless Edge and saves screenshots.
// It restarts the API itself to show a live database outage and recovery.
//
//   node tools/capture-screens.mjs          (API database freshly seeded first)
import { spawn, execSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { launch, sleep } from './cdp.mjs';

const backend = fileURLToPath(new URL('../backend/', import.meta.url));
const out = fileURLToPath(new URL('../evidence/screenshots/', import.meta.url));
const API = 'http://127.0.0.1:8015/api/v1';
const WEB = 'http://localhost:5015/';
const PASSWORD = 'Demo-Pass-2026!'; // seeded lab-only demo password

function stopPort(port) {
  try {
    execSync(`powershell -NoProfile -Command "Get-NetTCPConnection -LocalPort ${port} -State Listen -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }"`);
  } catch { /* nothing was listening */ }
  execSync('powershell -NoProfile -Command "Start-Sleep -Milliseconds 500"');
}

async function startApi({ outage = false } = {}) {
  stopPort(8015);
  const env = { ...process.env };
  if (outage) env.DB_DATABASE = `${backend}storage/does-not-exist/missing.sqlite`;
  spawn('php', ['-S', '127.0.0.1:8015', '../vendor/laravel/framework/src/Illuminate/Foundation/resources/server.php'],
    { cwd: `${backend}public`, env, stdio: 'ignore', detached: true }).unref();
  for (let i = 0; i < 50; i++) {
    try { await fetch('http://127.0.0.1:8015/up'); return; } catch { await sleep(200); }
  }
  throw new Error('API did not start');
}

async function api(method, path, token, body) {
  const res = await fetch(API + path, {
    method,
    headers: { Accept: 'application/json', 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  return res.json();
}
const tokenFor = async (email) => (await api('POST', '/auth/login', null, { email, password: PASSWORD })).token;

async function signIn(p, email, password = PASSWORD) {
  await p.enableSemantics();
  await p.fill('Email', email);
  await p.fill('Password', password);
  await p.click('Sign in', { exact: true });
  await sleep(2500);
}

await startApi();
const p = await launch({ width: 1366, height: 900 });
try {
  // ---- Desktop requester flow -------------------------------------------------
  await p.viewport(1366, 860);
  await p.goto(WEB, 7000);
  await p.shot(`${out}ui-01-login-desktop.jpg`);

  await signIn(p, 'student@example.test', 'wrong-password');
  await p.shot(`${out}ui-02-login-invalid-credentials.jpg`);

  await p.goto(WEB, 6000);
  await signIn(p, 'student@example.test');
  await p.shot(`${out}ui-03-requester-ticket-list.jpg`);

  await p.viewport(1366, 1000);
  await p.enableSemantics();
  await p.click('New ticket', { exact: true });
  await sleep(1500);
  await p.enableSemantics();
  await p.click('Submit ticket');
  await p.shot(`${out}ui-04-new-ticket-client-validation.jpg`);

  await p.click('Category');
  await sleep(800);
  await p.click('Network', { exact: true });
  await sleep(800);
  await p.fill('Subject', 'Week 15 demo: VPN disconnects in Lab 2');
  await p.fill('Description', 'The VPN client disconnects every ten minutes on the Lab 2 computers since Monday.');
  await p.fill('Contact number', '0917 555 0150');
  await p.click('Submit ticket');
  await sleep(1200);
  await p.shot(`${out}ui-05-ticket-submitted-snackbar.jpg`, 200);

  // ---- 409 conflict: the requester's screen is stale -----------------------------
  const agent = await tokenFor('agent.network@example.test');
  const list = await api('GET', '/tickets', agent);
  const id = list.data.find((t) => t.subject.startsWith('Week 15 demo')).id;
  await api('POST', `/tickets/${id}/transition`, agent, { status: 'in_progress' });
  await api('POST', `/tickets/${id}/transition`, agent, { status: 'resolved', note: 'Updated the VPN client profile.' });

  await sleep(4500); // let the snackbar close
  await p.enableSemantics();
  await p.click('Refresh');
  await sleep(1500);
  await p.click('Week 15 demo: VPN disconnects in Lab 2');
  await sleep(2000);
  await p.shot(`${out}ui-06-ticket-detail-resolved-awaiting-confirmation.jpg`);

  // Meanwhile the agent reopens it (the requester has not refreshed).
  await api('POST', `/tickets/${id}/transition`, agent, { status: 'in_progress', note: 'Reopened: one more check needed.' });
  await p.enableSemantics();
  await p.click('Confirm fixed');
  await sleep(1500);
  await p.shot(`${out}ui-07-conflict-409-stale-ticket-reloaded.jpg`, 200);

  // ---- Live dependency outage and recovery --------------------------------------
  await sleep(4500);
  await p.enableSemantics();
  await p.click('Back', { exact: true }).catch(() => p.clickAt(28, 28));
  await sleep(1500);
  await startApi({ outage: true });
  await p.enableSemantics();
  await p.click('Refresh');
  await sleep(2000);
  await p.shot(`${out}ui-08-service-unavailable-503.jpg`);

  stopPort(8015);
  await p.enableSemantics();
  await p.click('Try again');
  await sleep(3000);
  await p.shot(`${out}ui-09-network-unreachable.jpg`);

  await startApi();
  await p.enableSemantics();
  await p.click('Try again');
  await sleep(2000);
  await p.shot(`${out}ui-10-recovered-after-outage.jpg`);

  // ---- Supervisor view -------------------------------------------------------------
  await p.viewport(1366, 860);
  await p.goto(WEB, 6000);
  await signIn(p, 'supervisor@example.test');
  await p.shot(`${out}ui-11-supervisor-all-tickets.jpg`);

  // ---- Narrow (375 px) browser ---------------------------------------------------
  await p.viewport(375, 812, true);
  await p.goto(WEB, 6000);
  await signIn(p, 'employee@example.test');
  await p.shot(`${out}ui-12-narrow-375-ticket-list.jpg`);
  await p.enableSemantics();
  await p.click('New ticket', { exact: true });
  await sleep(1500);
  await p.enableSemantics();
  await p.fill('Subject', 'abc');
  await p.fill('Asset tag', 'bad tag!');
  await p.key('Tab');
  const submit = await p.find('Submit ticket');
  if (submit) await p.clickAt(submit.x, submit.y);
  await p.shot(`${out}ui-13-narrow-375-form-validation.jpg`);
} finally {
  await p.close();
}
console.log('done; API left running on :8015');
