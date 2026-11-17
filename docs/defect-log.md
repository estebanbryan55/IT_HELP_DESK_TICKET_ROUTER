# Week 15 Defect Log

Environment:

* Windows 10 machine
* PHP 8.4.14
* Laravel 13 (from Week 14) with PHPUnit 12.5
* Flutter 3.47.8
* Node 24.12 (test runner only)
* SQLite lab database with seeded fictional users

Every defect was reproduced by a test before it was fixed. The same test was rerun after the fix (see `evidence/01` and `evidence/04` for PHPUnit, `02` and `05` for Postman, `03` and `06` for live failure injection, `08b` and `08` for Flutter).

Priority = likelihood × impact × exposure. **High** means the defect is reachable by any signed-in user or by any outage.

| ID | Title | Found by | Priority |
|---|---|---|---|
| DEF-01 | Ticket existence leaked through 403 (BOLA, enumeration) | TC-AZ-01/02/06, PHPUnit | High |
| DEF-02 | Double submit or retry creates duplicate tickets | TC-DUP-01/02, PHPUnit | High |
| DEF-03 | Wrong-state actions reported as permission errors | TC-STA-02/03 | Medium |
| DEF-04 | Database outage → 500 leaking file path and SQL; no health signal | Live FI F1, PHPUnit | High |
| DEF-05 | Unknown status filter silently returns an empty list | TC-VAL-06 | Low |
| DEF-06 | 405 response lists supported methods and the route path | TC-CON-01 | Low |
| DEF-07 | CORS preflight blocks the new Idempotency-Key header | TC-CON-07, PHPUnit | High (blocks DEF-02 fix in browsers) |
| DEF-08 | Gateway client waits 30 s, then crashes with a stack trace | Live FI F3, PHPUnit | Medium |
| DEF-09 | `APP_DEBUG=true` in the lab `.env` exposes exception detail | Live FI F1 baseline body | High |
| DEF-10 | Flutter "Try again"/"Refresh" throws in debug builds | Flutter ST-03 | Medium |

---

### DEF-01 Ticket existence leaked through 403

* **Reproduce.** Sign in as `employee@example.test`. Run `GET /api/v1/tickets/{id}` for the student's ticket.
* **Expected.** The same answer as for an id that does not exist.
* **Actual (before).** `403 You are not permitted…`. The answer for a missing id is `404 Resource not found.`, so a caller can tell which ids exist (OWASP API1:2023, BOLA). The same happened for agents probing other agents' tickets and on the transition and confirm routes.
* **Root cause.** `Gate::authorize('view')` throws `AccessDeniedHttpException`, which is rendered as 403.
* **Fix.** `TicketController::authorizeVisible()` returns 404 when the caller may not *view* the ticket. A ticket the caller can see but may not change still returns 403. The denial is logged as `ticket.access_denied` with the correlation id.
* **Contract change.** Two Week 14 tests expected 403. They were updated deliberately and are marked `Week 15 DEF-01`. The Flutter detail screen now shows "Ticket not found" with "Back to list" and no retry loop (ST-06).
* **Retest.** `test_def01_*` ×3, TC-AZ-01/02/06 now return 404. TC-AZ-03/04 still return 403.

### DEF-02 Duplicate tickets on double submit or retry

* **Reproduce.** POST the same ticket twice, for example after a timeout where the first request actually succeeded.
* **Actual (before).** Two tickets were created (TC-DUP-01 returned 201 with id 6 instead of id 3).
* **Fix.**
  * Optional `Idempotency-Key` header, validated as 8–64 characters of `[A-Za-z0-9_-]`.
  * Keys are scoped per requester. A database unique index on `(requester_id, idempotency_key)` settles races, and a unique-violation is converted into a replay.
  * The same key with the same payload hash returns the original ticket with `200` and `Idempotent-Replayed: true`.
  * The same key with a different payload returns `409`.
  * Flutter generates one cryptographically random key per form (`Random.secure`) and reuses it on every retry. The submit button is disabled while a request is in flight (ST-11).
* **Retest.** `test_def02_*` ×4, TC-DUP-01/02, Flutter ST-10 (timeout then retry sends the same key).

### DEF-03 Wrong-state actions reported as 403

* **Actual (before).** Confirming an unresolved ticket, or reassigning a closed one, returned `403 You are not permitted…`. The user cannot tell that the ticket simply changed state.
* **Root cause.** The policy mixed *who* may act with *the current state*.
* **Fix.** The policies now check only identity and role. The controller returns `409` with a reason ("Only a resolved ticket can be confirmed.", "A closed ticket cannot be reassigned."). The Flutter detail screen reloads the ticket after a 409, so the buttons match the real state (ui-07).
* **Retest.** `test_def03_*` ×2, TC-STA-02/03.

### DEF-04 Unsafe and unobservable database outage

* **Reproduce.** Run `tools/failure-injection.sh` (F1 starts an API instance whose SQLite file does not exist).
* **Actual (before).** Login returned `500` with the full database path, SQL text, and cache key in the body. There was no health endpoint (404).
* **Fix.**
  * `App\Support\DependencyFailure` recognises lost or missing database connections. They are rendered as `503` with `Retry-After: 30`, a generic message, and `correlation_id`. Every other API 5xx also carries the correlation id, with a generic body when debug is off.
  * New `GET /api/v1/health` returns `{status, checks.database}`: 200 when the database is ok, 503 when it is degraded. It never includes error text.
  * Flutter maps 502/503/504 to a "temporarily unavailable (ref xxxxxxxx)" message with Try again (ST-04, ui-08).
* **Retest.** `test_def04_*` ×3, TC-HLT-01, live F1/F2 (`evidence/06`).

### DEF-05 Unknown status filter accepted

* `GET /tickets?status=bogus` returned `200 []`, which hid client bugs.
* Now the `status` (enum) and `page` (≥ 1) parameters are validated and an unknown value returns 422.

### DEF-06 405 response leaked routing details

* The 405 message said "The GET method is not supported for route api/v1/auth/login. Supported methods: POST."
* Now the API returns a generic `405 Method not allowed.`.

### DEF-07 CORS blocked the Idempotency-Key header

* After DEF-02, browsers would have failed the preflight, because `Idempotency-Key` was not in `allowed_headers`. Every Flutter Web ticket submission would then have failed with a network error, an interoperability defect that a server-only test would miss.
* Added `Idempotency-Key` to `allowed_headers`. Exposed `Idempotent-Replayed` and `Retry-After`.
* TC-CON-07 and `test_def07_*` check this.

### DEF-08 Unbounded gateway timeout

* **Actual (before).** Against a dependency that answers after 35 s, `gateway:send` waited the default 30 s and then died with an uncaught `ConnectionException` stack trace.
* **Fix.**
  * Each attempt connects within 2 s and times out after 3 s.
  * There are 3 attempts, 500 ms apart, retried only on connection errors or 5xx.
  * Retries cannot create duplicates, because the signed message's nonce makes a re-delivery a 409 replay.
  * After the last attempt, one line is printed ("unreachable after 3 attempts… kept for manual retry") and the command exits with code 1.
* **Retest.** Live F3 took 11 s and exited with code 1. `test_def08_*` covers a permanent timeout and one transient failure that is recovered.

### DEF-09 Debug mode on in the lab `.env`

* With `APP_DEBUG=true`, any exception returned internals (DEF-04 baseline body).
* Set `APP_DEBUG=false`. `.env.example` was already false. The secret and configuration scan now checks both files (§4).

### DEF-10 Flutter retry and refresh did nothing in debug builds

* `void _refresh() => setState(() => _future = _load());`: the arrow returns the Future from the `setState` callback, and Flutter asserts on that.
* "Try again" after a network error therefore threw instead of reloading. Release builds hide the assertion, which is why manual tests in Week 14 missed it. A page reload is not a workaround, because it signs the user out (the token is held only in memory).
* Fixed in the list and detail screens with block-bodied `_refresh()` / `_reload()`. ST-03 passes after the fix (`evidence/08b` shows the failure, `08` the pass).

---

## Not fixed (accepted or deferred)

| ID | Observation | Decision |
|---|---|---|
| OBS-01 | `TicketRouter::nextReference()` uses `max(id)+1`. Two simultaneous inserts on MySQL could compute the same reference and one would fail on the unique index (500). | Deferred. It cannot occur on single-writer SQLite. Before the MySQL deployment, derive the reference from the inserted id. Logged for Week 16 load testing. |
| OBS-02 | After a ticket is reopened, the previous resolution note is still shown (ui-07). The history shows the reopen. | Accepted for now (low impact). Clear or label it "previous resolution" in Week 17 UAT if users find it confusing. |
| OBS-03 | When the database is down, login rate limiting (cache store = database) also fails. Requests get 503, so this is safe, but no throttling is recorded during an outage. | Accepted. Move the cache to Redis in deployment (Week 16 environment comparison). |
| OBS-04 | `php artisan serve` is single-threaded. Median request time is about 0.5 s on the lab laptop. | Out of scope for Week 15. Measured properly in Week 16. |
