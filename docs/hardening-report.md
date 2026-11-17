# Week 15 Integration Testing and Hardening Report (IA6)

Project 16, IT Help Desk Ticket Router. Flutter Web client with a Laravel 13 API.
Evidence date: 17 November 2026. Prototype with fictional data only; **not production ready**.

## 1. Executive summary

The Week 14 build had a clean happy path and strong cryptographic controls, but it had not been tested against misuse, duplicates, or failing dependencies.

**Baseline (Week 14 code):**

| Suite | Passed | Total | Notes |
|---|---|---|---|
| PHPUnit | 57 | 72 | 13 failures and 2 errors, all in the new Week 15 tests |
| Live Postman | 37 | 49 | |

The live failure injection also showed that a database outage:

* returned a 500 containing the database file path and SQL;
* left no health signal;
* made the gateway client hang for 30 s and then crash.

**After the hardening sprint:**

| Suite | Passed | Total |
|---|---|---|
| PHPUnit | **72** (238 assertions) | 72 |
| Live Postman | **49** | 49 |
| Flutter | **17** | 17 |

The same outage now gives a generic 503 with a correlation id, the health check reports `degraded`, the UI recovers with "Try again", and the gateway gives up cleanly after 3 bounded attempts (11 s, exit code 1).

Ten defects were found and fixed (DEF-01..10). Four observations are recorded but not fixed, with reasons (OBS-01..04).

## 2. Scope and environment

* **In scope.** The complete bounded workflow: submit → route → work → resolve → confirm/close, plus reassignment and the signed email gateway.
* **Interfaces.** Flutter Web ↔ API, gateway ↔ API, API ↔ database.
* **Out of scope.** Load and performance (Week 16), UAT (Week 17), real TLS certificates, and production data.
* **Environment.**
  * Windows 10, PHP 8.4.14, Laravel 13 with Sanctum, PHPUnit 12.5.43.
  * Flutter 3.47.8 / Dart 3.13, Node 24.12 (test runner and screenshot driver), headless Edge.
  * The API on `127.0.0.1:8015` and the Flutter build on `localhost:5015`. Week 14 stays untouched on :8000.
* **Data.** Six seeded fictional accounts on the reserved `example.test` domain. The lab-only demo password is the one in `DatabaseSeeder`.

## 3. Test strategy (Topic 1)

| Layer | Tool | What it proves | Count |
|---|---|---|---|
| Unit / feature | PHPUnit, in-memory SQLite | Each rule, control, and error path in isolation; deterministic failure injection (DB down, gateway timeout) | 72 |
| Contract / integration | Postman v2.1 collection, run by `tools/run-collection.mjs` | The real HTTP contract over the network: status codes, headers, CORS preflight, rate limiting, token revocation | 49 |
| Client state | `flutter_test` with a simulated API | Every UI state, the retry behaviour, the idempotency key, and the 375 px layout | 17 |
| Failure injection | `tools/failure-injection.sh` | Real outage and timeout behaviour, before and after | 3 scenarios |
| Visual | `tools/capture-screens.mjs` (CDP + headless Edge) | What the user actually sees, including a live outage and recovery | 13 screens |

Every requirement is linked to its tests and evidence in `traceability-matrix.md`.

**Decision record ADR-W15-01, test runner.**

* Options considered: Newman (`npm i -g newman`), or a small Node runner that executes the same Postman collection.
* Chosen: the Node runner. It adds no global dependency, it works offline in the lab, and it keeps the collection importable into Postman unchanged.
* Consequence: it supports only the `pm.*` subset that the collection uses. New scripts must stay within that subset or switch to Newman.

## 4. Results

| Suite | Before | After | Files |
|---|---|---|---|
| PHPUnit | 57/72 (15 fail) | 72/72 | `evidence/01`, `04` |
| Live Postman | 37/49 (12 fail) | 49/49 | `evidence/02`, `05` (+ JSON) |
| Failure injection | unsafe 500 / 404 / 30 s crash | 503 safe / 200 recovery / 11 s bounded | `evidence/03`, `06` |
| Flutter | ST-03 fail (DEF-10) | 17/17 | `evidence/08b`, `08` |
| Secret/config scan | `APP_DEBUG=true` | clean | `evidence/09` |

**Response time (live run).**

| Run | Median | p95 | Max |
|---|---|---|---|
| Before | 552 ms | 935 ms | 1286 ms |
| After | 521 ms | 925 ms | 968 ms |

The hardening did not add measurable latency. Absolute values reflect the single-threaded `php artisan serve` and are examined in Week 16.

## 5. Hardening backlog and what was implemented (Topic 4)

| Rank | Weakness | Likelihood | Impact | Action | Status |
|---|---|---|---|---|---|
| 1 | DEF-09 debug on → internals in responses | High (any error) | High | `APP_DEBUG=false`, scan check | Done |
| 2 | DEF-04 DB outage leaks and gives no health signal | Medium | High | 503 mapping, correlation id on 5xx, `/health` | Done |
| 3 | DEF-01 BOLA existence leak | High (any user) | Medium | 404 for invisible tickets | Done |
| 4 | DEF-02 + DEF-07 duplicate tickets | High (double click / retry) | Medium | Idempotency-Key end to end, CORS | Done |
| 5 | DEF-08 unbounded dependency wait | Medium | Medium | timeouts, bounded retry, clean failure | Done |
| 6 | DEF-10 UI retry broken | Medium | Medium | setState fix | Done |
| 7 | DEF-03 misleading 403 | Medium | Low | 409 + UI reload | Done |
| 8 | DEF-05 / DEF-06 contract leaks | Low | Low | validation, generic 405 | Done |
| 9 | OBS-01 reference race on MySQL | Low now | Medium later | id-derived reference | Deferred to the Week 16 MySQL test |
| 10 | OBS-03 rate limiter depends on the DB | Low | Medium | Redis cache store | Deferred to deployment |

**Decision record ADR-W15-02, 404 instead of 403 for invisible tickets.**

* Alternative: keep 403 and add random, non-sequential ids.
* Chosen: 404, because it is one rule in one place, needs no migration, and follows OWASP API1 guidance.
* Consequences:
  * Two Week 14 tests and the client message changed.
  * Support staff cannot tell "missing" from "not yours" from the response alone. They use the `ticket.access_denied` log entry and its correlation id.

**Decision record ADR-W15-03, server-side Idempotency-Key.**

* Alternative: only disable the button in Flutter.
* Rejected, because it does not cover a timeout followed by a retry, two tabs, or other clients.
* Chosen: an `Idempotency-Key` header, a payload hash, and a database unique index.
* Consequences: two new columns. Keys are kept with the ticket (no expiry yet).

## 6. Failure-condition findings (Topic 3)

| Scenario | Predicted (after fix) | Observed before | Observed after |
|---|---|---|---|
| F1 database missing: `/health` | 503 degraded | 404 (no endpoint) | 503 `{"status":"degraded"}` + Retry-After |
| F1 database missing: login | 503 generic + ref | 500 with DB path and SQL | 503 generic, `correlation_id` = header |
| F2 healthy instance after the outage | 200 | 404 / 200 | 200 / 200 |
| F3 gateway dependency answers after 35 s | ≤ 3 × 3 s, exit 1 | 30 s, uncaught exception | 11 s, one-line error, exit 1 |
| UI during the outage | safe message, retry works | n/a | ui-08 (503 + ref), ui-09 (unreachable), ui-10 (recovered) |

No data was corrupted in any scenario. The failed requests never reached a write.

## 7. Residual risk

* OBS-01..04 in `defect-log.md`.
* The Postman runner is not Newman (ADR-W15-01).
* Tests run on SQLite. The MySQL behaviour of the unique index and of concurrency is not yet verified.
* HTTPS is enforced in code and tested with PHPUnit. The lab runs over local HTTP with `REQUIRE_HTTPS=false`.
* Idempotency keys never expire.
* The lab demo password is shared. It is acceptable only on a local machine.

## 8. Next improvement

The most valuable next step is the Week 16 load test against MySQL. It will confirm OBS-01 under concurrency, measure the cost of the idempotency lookup, and verify that `/health` is fast enough for a load-balancer probe.
