# Week 15 Evidence Index (IA6)

Run date: 17 November 2026.

* Environment: Windows 10, PHP 8.4.14, PHPUnit 12.5.43, Flutter 3.47.8, Node 24.12, headless Microsoft Edge.
* API at `http://127.0.0.1:8015`, web app at `http://localhost:5015`.
* Data: only the fictional seeded accounts. Bearer tokens are redacted from every file.

"Before" means the unmodified Week 14 code with the new Week 15 tests added. "After" means the Week 15 code.

## Test records

| File | What it shows |
|---|---|
| `01-baseline-phpunit-before-fixes.txt` | PHPUnit before the fixes: 72 tests, 15 failing (all new Week 15 tests). `01b-…-raw.txt` is the full output, including the debug stack traces that DEF-06/09 removed. |
| `02-baseline-postman-run.txt` / `.json` | Live collection before the fixes: 37/49 pass. Each failing assertion is listed. |
| `03-baseline-failure-injection.txt` | Before: the DB outage returns a 500 with the DB path and SQL, there is no `/health`, and the gateway hangs for 30 s and then crashes |
| `04-phpunit-after-fixes.txt` | PHPUnit after the fixes: 72/72 (238 assertions) |
| `05-regression-postman-run.txt` / `.json` | Live collection after the fixes: 49/49, with timings and correlation ids |
| `06-failure-injection-after-fixes.txt` | After: 503 generic with Retry-After and correlation id, health `degraded` then `ok`, gateway bounded to 11 s and exit 1 |
| `07-protected-log-excerpt.txt` | Server log lines matching the runs (access denials, idempotent replay, outage), with no secrets |
| `08-flutter-tests.txt` | 17/17 Flutter tests: 5 from Week 14 and 12 new state tests (ST-01..ST-12) |
| `08b-flutter-DEF10-before-fix.txt` | The failing ST-03 output that exposed DEF-10 |
| `09-secret-and-config-scan.txt` | No real secrets outside `.env`, `APP_DEBUG=false`, `.env` git-ignored |

Supporting documents are in `../docs/`: `traceability-matrix.md`, `defect-log.md`, `hardening-report.md`.

## Screenshots (`screenshots/`)

**Flutter Web, real browser, real API.**

| File | State |
|---|---|
| `ui-01-login-desktop.jpg` | Sign-in screen |
| `ui-02-login-invalid-credentials.jpg` | Wrong password: generic error, password cleared |
| `ui-03-requester-ticket-list.jpg` | Requester's own tickets |
| `ui-04-new-ticket-client-validation.jpg` | Client-side validation before any request |
| `ui-05-ticket-submitted-snackbar.jpg` | Ticket created (sent with an Idempotency-Key), list reloading |
| `ui-06-ticket-detail-resolved-awaiting-confirmation.jpg` | Resolved ticket with Confirm / Not fixed; protected field visible to its owner |
| `ui-07-conflict-409-stale-ticket-reloaded.jpg` | The agent reopened the ticket meanwhile: Confirm gives 409, the message is shown, the ticket reloads |
| `ui-08-service-unavailable-503.jpg` | Live database outage: safe message with reference id |
| `ui-09-network-unreachable.jpg` | API stopped: network error with Try again |
| `ui-10-recovered-after-outage.jpg` | API restored: Try again recovers without signing in again |
| `ui-11-supervisor-all-tickets.jpg` | Supervisor sees all tickets |
| `ui-12-narrow-375-ticket-list.jpg` | 375 px browser width |
| `ui-13-narrow-375-form-validation.jpg` | 375 px form: fields stack, validation messages |

**Test runs, rendered from the files above.**

| File | |
|---|---|
| `test-01-phpunit-BEFORE-fixes.jpg` / `test-02-phpunit-AFTER-fixes.jpg` | PHPUnit before and after |
| `test-03-postman-BEFORE-fixes.jpg` / `test-04-postman-AFTER-fixes.jpg` | Live API collection before and after |
| `test-05-failure-injection-BEFORE.jpg` / `test-06-failure-injection-AFTER.jpg` | Outage and timeout before and after |
| `test-07-flutter-tests.jpg` / `test-08-flutter-DEF10-before-fix.jpg` | Flutter tests, and the DEF-10 failure |
| `test-09-secret-and-config-scan.jpg` | Secret and configuration scan |
| `test-10-protected-log-excerpt.jpg` | Correlated log entries |
