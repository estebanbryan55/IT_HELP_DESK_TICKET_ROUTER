// Generates postman/Week15_IA6_HelpDesk.postman_collection.json.
// Each request id (TC-...) matches a row in docs/traceability-matrix.md.
//   node tools/build-collection.mjs
import { mkdirSync, writeFileSync } from 'node:fs';

const PASSWORD = 'Demo-Pass-2026!'; // seeded lab-only demo password (see DatabaseSeeder)
const json = { key: 'Content-Type', value: 'application/json' };
const accept = { key: 'Accept', value: 'application/json' };
const bearer = (v) => ({ key: 'Authorization', value: `Bearer {{${v}}}` });

const req = (id, title, method, path, { auth, body, headers = [], test, pre } = {}) => ({
  name: `${id} ${title}`,
  request: {
    method,
    header: [accept, ...(body !== undefined ? [json] : []), ...(auth ? [bearer(auth)] : []), ...headers],
    url: { raw: `{{baseUrl}}${path}` },
    ...(body !== undefined ? { body: { mode: 'raw', raw: typeof body === 'string' ? body : JSON.stringify(body) } } : {}),
  },
  event: [
    ...(pre ? [{ listen: 'prerequest', script: { type: 'text/javascript', exec: pre.trim().split('\n') } }] : []),
    { listen: 'test', script: { type: 'text/javascript', exec: test.trim().split('\n') } },
  ],
});

const status = (n) => `pm.test('status is ${n}', () => pm.response.to.have.status(${n}));`;
const login = (id, who, email, varName) => req(id, `Login as ${who}`, 'POST', '/auth/login', {
  body: { email, password: PASSWORD },
  test: `${status(200)}
pm.test('bearer token issued with expiry', () => pm.expect(pm.response.json().expires_at).to.exist());
pm.collectionVariables.set('${varName}', pm.response.json().token);`,
});

const ticket = {
  category: 'network', priority: 'high', subject: 'Week 15 test: Wi-Fi drops in Lab 3',
  description: 'Controlled test ticket created by the Week 15 Postman collection.', contact_number: '0917 555 0199',
};

const folders = [
  { name: '1 Health', item: [
    req('TC-HLT-01', 'Health check reports database ok', 'GET', '/health', { test: `${status(200)}
pm.test('database check ok', () => pm.expect(pm.response.json().checks.database).to.eql('ok'));` }),
  ] },
  { name: '2 Authentication', item: [
    login('TC-AUTH-01', 'student (requester)', 'student@example.test', 'studentToken'),
    login('TC-AUTH-02', 'employee (requester)', 'employee@example.test', 'employeeToken'),
    login('TC-AUTH-03a', 'network agent', 'agent.network@example.test', 'agentNetToken'),
    login('TC-AUTH-03b', 'hardware agent', 'agent.hardware@example.test', 'agentHwToken'),
    login('TC-AUTH-03c', 'supervisor', 'supervisor@example.test', 'supToken'),
    req('TC-AUTH-04', 'Wrong password gives generic 401', 'POST', '/auth/login', {
      body: { email: 'student@example.test', password: 'wrong-password' },
      test: `${status(401)}
pm.test('generic message', () => pm.expect(pm.response.json().message).to.eql('Invalid credentials.'));` }),
    req('TC-AUTH-05', 'Malformed email rejected', 'POST', '/auth/login', {
      body: { email: 'not-an-email', password: 'x' }, test: status(422) }),
    req('TC-AUTH-06', 'No token gives 401', 'GET', '/tickets', { test: status(401) }),
    req('TC-AUTH-07', 'Forged token gives 401', 'GET', '/tickets', {
      headers: [{ key: 'Authorization', value: 'Bearer hdr_1|forgedforgedforgedforged' }], test: status(401) }),
  ] },
  { name: '3 Functional workflow', item: [
    req('TC-FUN-01', 'Requester submits ticket (routed to network agent)', 'POST', '/tickets', {
      auth: 'studentToken', body: ticket, headers: [{ key: 'Idempotency-Key', value: '{{idemKey}}' }],
      pre: `pm.collectionVariables.set('idemKey', 'w15-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 10));`,
      test: `${status(201)}
const d = pm.response.json().data;
pm.test('auto-assigned', () => pm.expect(d.status).to.eql('assigned'));
pm.test('routed to network specialist', () => pm.expect(d.agent.name).to.eql('Nico Network'));
pm.test('protected field visible to owner', () => pm.expect(d.contact_number).to.eql('0917 555 0199'));
pm.collectionVariables.set('ticketId', d.id);
pm.collectionVariables.set('ticketRef', d.reference);` }),
    req('TC-FUN-02', 'Requester list contains the new ticket', 'GET', '/tickets', {
      auth: 'studentToken', test: `${status(200)}
pm.test('ticket listed', () => pm.expect(pm.response.text()).to.include(pm.collectionVariables.get('ticketRef')));` }),
    req('TC-FUN-03', 'Agent starts work', 'POST', '/tickets/{{ticketId}}/transition', {
      auth: 'agentNetToken', body: { status: 'in_progress' }, test: `${status(200)}
pm.test('in progress', () => pm.expect(pm.response.json().data.status).to.eql('in_progress'));` }),
    req('TC-FUN-04', 'Resolve without note is rejected', 'POST', '/tickets/{{ticketId}}/transition', {
      auth: 'agentNetToken', body: { status: 'resolved' }, test: `${status(422)}
pm.test('note error', () => pm.expect(pm.response.json().errors.note).to.exist());` }),
    req('TC-FUN-05', 'Agent resolves with note', 'POST', '/tickets/{{ticketId}}/transition', {
      auth: 'agentNetToken', body: { status: 'resolved', note: 'Rebooted the Lab 3 access point.' }, test: `${status(200)}
pm.test('resolved', () => pm.expect(pm.response.json().data.status).to.eql('resolved'));` }),
    req('TC-FUN-06', 'Requester confirms fix and ticket closes', 'POST', '/tickets/{{ticketId}}/confirm', {
      auth: 'studentToken', body: { accepted: true }, test: `${status(200)}
pm.test('closed', () => pm.expect(pm.response.json().data.status).to.eql('closed'));` }),
  ] },
  { name: '4 Invalid input and boundaries', item: [
    req('TC-VAL-01', 'Invalid category, short subject, bad phone', 'POST', '/tickets', {
      auth: 'studentToken', body: { category: 'printer-magic', subject: 'x', description: 'short', contact_number: '<script>' },
      test: `${status(422)}
const e = pm.response.json().errors;
pm.test('field errors returned', () => ['category', 'subject', 'description', 'contact_number'].forEach((f) => pm.expect(e[f]).to.exist()));` }),
    req('TC-VAL-02', 'Subject of 121 characters rejected (upper bound + 1)', 'POST', '/tickets', {
      auth: 'studentToken', body: { ...ticket, subject: 'S'.repeat(121) }, test: status(422) }),
    req('TC-VAL-03', 'Subject of exactly 120 characters accepted (upper bound)', 'POST', '/tickets', {
      auth: 'studentToken', body: { ...ticket, category: 'hardware', subject: 'B'.repeat(120) }, test: `${status(201)}
pm.collectionVariables.set('ticket2Id', pm.response.json().data.id);` }),
    req('TC-VAL-04', 'Malformed JSON body gives 422, not 500', 'POST', '/tickets', {
      auth: 'studentToken', body: '{"category": "network", "subject": ', test: status(422) }),
    req('TC-VAL-05', 'Client-supplied status/requester ignored (mass assignment)', 'POST', '/tickets', {
      auth: 'employeeToken', body: { ...ticket, category: 'account', status: 'closed', requester_id: 1, assigned_agent_id: 999 },
      test: `${status(201)}
const d = pm.response.json().data;
pm.test('status set by server', () => pm.expect(d.status).to.eql('assigned'));
pm.test('requester is the caller', () => pm.expect(d.requester.name).to.eql('Erin Employee'));` }),
    req('TC-VAL-06', 'Unknown status filter rejected', 'GET', '/tickets?status=bogus', {
      auth: 'supToken', test: `${status(422)}
pm.test('status field error', () => pm.expect(pm.response.json().errors.status).to.exist());` }),
  ] },
  { name: '5 Authorization', item: [
    req('TC-AZ-01', "Requester cannot read another requester's ticket (no existence leak)", 'GET', '/tickets/{{ticketId}}', {
      auth: 'employeeToken', test: `${status(404)}
pm.test('same body as unknown id', () => pm.expect(pm.response.json().message).to.eql('Resource not found.'));` }),
    req('TC-AZ-02', 'Agent cannot read a ticket assigned to another agent', 'GET', '/tickets/{{ticketId}}', {
      auth: 'agentHwToken', test: status(404) }),
    req('TC-AZ-03', 'Requester cannot change status of own ticket', 'POST', '/tickets/{{ticket2Id}}/transition', {
      auth: 'studentToken', body: { status: 'resolved', note: 'self-resolve attempt' }, test: status(403) }),
    req('TC-AZ-04', 'Requester cannot list agents', 'GET', '/agents', { auth: 'studentToken', test: status(403) }),
    req('TC-AZ-05', 'Unknown ticket id', 'GET', '/tickets/999999', { auth: 'supToken', test: `${status(404)}
pm.test('generic message', () => pm.expect(pm.response.json().message).to.eql('Resource not found.'));` }),
    req('TC-AZ-06', "Requester cannot confirm another requester's ticket", 'POST', '/tickets/{{ticketId}}/confirm', {
      auth: 'employeeToken', body: { accepted: true }, test: status(404) }),
    req('TC-AZ-07', 'Supervisor can read any ticket', 'GET', '/tickets/{{ticketId}}', { auth: 'supToken', test: status(200) }),
  ] },
  { name: '6 Duplicate and state conflicts', item: [
    req('TC-DUP-01', 'Same Idempotency-Key replays the original ticket', 'POST', '/tickets', {
      auth: 'studentToken', body: ticket, headers: [{ key: 'Idempotency-Key', value: '{{idemKey}}' }],
      test: `${status(200)}
pm.test('same ticket returned', () => pm.expect(String(pm.response.json().data.id)).to.eql(pm.collectionVariables.get('ticketId')));
pm.test('replay flagged', () => pm.expect(pm.response.headers.get('Idempotent-Replayed')).to.eql('true'));` }),
    req('TC-DUP-02', 'Same key with a different payload is refused', 'POST', '/tickets', {
      auth: 'studentToken', body: { ...ticket, subject: 'A different subject entirely' },
      headers: [{ key: 'Idempotency-Key', value: '{{idemKey}}' }], test: status(409) }),
    req('TC-STA-01', 'Closed ticket cannot be reopened by transition', 'POST', '/tickets/{{ticketId}}/transition', {
      auth: 'supToken', body: { status: 'in_progress' }, test: status(409) }),
    req('TC-STA-02', 'Confirming an unresolved ticket is a conflict, not a permission error', 'POST', '/tickets/{{ticket2Id}}/confirm', {
      auth: 'studentToken', body: { accepted: true }, test: status(409) }),
    req('TC-STA-03', 'Reassigning a closed ticket is a conflict', 'POST', '/tickets/{{ticketId}}/assign', {
      auth: 'supToken', body: { agent_id: 3 }, test: status(409) }),
  ] },
  { name: '7 Contract and interoperability', item: [
    req('TC-CON-01', 'Wrong HTTP method gives generic 405', 'GET', '/auth/login', { test: `${status(405)}
pm.test('no route details leaked', () => pm.expect(pm.response.text()).to.not.include('Supported methods'));` }),
    req('TC-CON-02', 'Client correlation id is echoed', 'GET', '/health', {
      headers: [{ key: 'X-Correlation-Id', value: 'week15-trace-0001' }], test: `${status(200)}
pm.test('echoed', () => pm.expect(pm.response.headers.get('X-Correlation-Id')).to.eql('week15-trace-0001'));` }),
    req('TC-CON-03', 'Security headers present', 'GET', '/tickets', { auth: 'studentToken', test: `${status(200)}
pm.test('nosniff', () => pm.expect(pm.response.headers.get('X-Content-Type-Options')).to.eql('nosniff'));
pm.test('CSP', () => pm.expect(pm.response.headers.get('Content-Security-Policy')).to.include("default-src 'none'"));
pm.test('no-store', () => pm.expect(pm.response.headers.get('Cache-Control')).to.include('no-store'));
pm.test('json', () => pm.expect(pm.response.headers.get('Content-Type')).to.include('application/json'));` }),
    req('TC-CON-04', 'CORS preflight from the Flutter origin allowed', 'OPTIONS', '/tickets', {
      headers: [{ key: 'Origin', value: 'http://localhost:5000' }, { key: 'Access-Control-Request-Method', value: 'POST' }],
      test: `pm.test('2xx', () => pm.expect(pm.response.code).to.be.oneOf([200, 204]));
pm.test('origin allowed', () => pm.expect(pm.response.headers.get('Access-Control-Allow-Origin')).to.eql('http://localhost:5000'));` }),
    req('TC-CON-05', 'CORS preflight from an unknown origin not allowed', 'OPTIONS', '/tickets', {
      headers: [{ key: 'Origin', value: 'https://evil.example' }, { key: 'Access-Control-Request-Method', value: 'POST' }],
      test: `pm.test('origin not allowed', () => pm.expect(pm.response.headers.get('Access-Control-Allow-Origin')).to.not.exist());` }),
    req('TC-CON-07', 'CORS preflight allows the Idempotency-Key header', 'OPTIONS', '/tickets', {
      headers: [{ key: 'Origin', value: 'http://localhost:5000' }, { key: 'Access-Control-Request-Method', value: 'POST' },
        { key: 'Access-Control-Request-Headers', value: 'authorization,content-type,idempotency-key' }],
      test: `pm.test('header allowed', () => pm.expect((pm.response.headers.get('Access-Control-Allow-Headers') || '').toLowerCase()).to.include('idempotency-key'));` }),
    req('TC-CON-06', 'Unsigned gateway message rejected', 'POST', '/integrations/email-gateway/tickets', {
      body: { requester_email: 'student@example.test', category: 'software', subject: 'Unsigned', description: 'No signature headers.' },
      test: status(401) }),
  ] },
  { name: '8 Rate limiting', item: [
    ...[1, 2, 3, 4, 5].map((n) => req(`TC-RL-0${n}`, `Failed login ${n}/5`, 'POST', '/auth/login', {
      body: { email: 'ratelimit@example.test', password: `wrong-${n}` }, test: status(401) })),
    req('TC-RL-06', 'Sixth failed login in a minute is throttled', 'POST', '/auth/login', {
      body: { email: 'ratelimit@example.test', password: 'wrong-6' }, test: `${status(429)}
pm.test('Retry-After sent', () => pm.expect(pm.response.headers.get('Retry-After')).to.exist());` }),
  ] },
  { name: '9 Sign out', item: [
    req('TC-AUTH-08', 'Logout revokes the token', 'POST', '/auth/logout', { auth: 'studentToken', test: status(200) }),
    req('TC-AUTH-09', 'Revoked token no longer works', 'GET', '/tickets', { auth: 'studentToken', test: status(401) }),
  ] },
];

const collection = {
  info: {
    name: 'Week 15 IA6 - IT Help Desk Ticket Router API',
    description: 'Project 16 integration test collection: normal, invalid, boundary, unauthorized, forbidden, not-found, duplicate, conflict, contract, and rate-limit cases. Controlled demo data only.',
    schema: 'https://schema.getpostman.com/json/collection/v2.1.0/collection.json',
  },
  variable: [{ key: 'baseUrl', value: 'http://127.0.0.1:8000/api/v1' }],
  item: folders,
};

mkdirSync(new URL('../postman/', import.meta.url), { recursive: true });
writeFileSync(new URL('../postman/Week15_IA6_HelpDesk.postman_collection.json', import.meta.url), JSON.stringify(collection, null, 2));
console.log(`Wrote ${folders.reduce((n, f) => n + f.item.length, 0)} requests`);
