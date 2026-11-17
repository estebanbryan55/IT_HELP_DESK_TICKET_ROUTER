# Week 15 Requirements-to-Test Traceability Matrix

Project 16, IT Help Desk Ticket Router. IA6 Integration Testing and Hardening.

Test layers:

* **PHPUnit**: Laravel feature and unit tests, in-memory SQLite, `backend/tests/`.
* **Postman**: the live API collection `postman/Week15_IA6_HelpDesk.postman_collection.json`, run with `tools/run-collection.mjs` against `php artisan serve`.
* **Flutter**: widget and state tests in `frontend/test/`, run against a simulated API.
* **Live FI**: live failure injection, `tools/failure-injection.sh`.
* **UI**: real browser screenshots, `tools/capture-screens.mjs`.

"Before" is the unmodified Week 14 code. "After" is the Week 15 code.

| Req | Requirement / control | Type | Tests (id → where) | Expected result | Before | After | Evidence |
|---|---|---|---|---|---|---|---|
| R1 | Requester submits a ticket; rule-based routing assigns a specialist | Functional | TC-FUN-01, TC-FUN-02 (Postman); `test_requester_creates_ticket_and_it_is_routed_to_specialised_agent` | 201, status `assigned`, network agent | Pass | Pass | 02, 05 |
| R2 | Agent works → resolves (note required) → requester confirms → closed | Functional | TC-FUN-03..06; `test_full_workflow_assign_resolve_confirm_close` | 200 at each step; 422 without note | Pass | Pass | 02, 05, ui-06 |
| R3 | Server-side validation is authoritative | Invalid input | TC-VAL-01, TC-VAL-04; `test_invalid_input_is_rejected_with_field_errors`, `test_malformed_json_is_a_validation_error_not_a_server_error` | 422 with field errors, never 500 | Pass | Pass | 05 |
| R4 | Field limits: subject 5–120, description 10–2000 | Boundary | TC-VAL-02, TC-VAL-03; `test_subject_boundaries_5_and_120_accepted_4_and_121_rejected`, `test_description_boundaries_10_and_2000`, `test_whitespace_only_subject_is_treated_as_missing` | min and max accepted; min−1 and max+1 rejected | Pass | Pass | 04, 05 |
| R5 | Client cannot set server-owned fields (mass assignment) | Security | TC-VAL-05; `test_client_cannot_set_server_owned_fields` | status/requester/source set by server | Pass | Pass | 04, 05 |
| R6 | Unknown list filter is rejected | Invalid input | TC-VAL-06; `test_def05_unknown_status_filter_is_rejected` | 422 | **Fail** (200, empty list) | Pass | DEF-05 |
| R7 | Authentication: bearer token required, forged and revoked tokens refused, generic login error | Authentication | TC-AUTH-01..09; `AuthenticationTest` (10 tests) | 401, `Invalid credentials.` | Pass | Pass | 05 |
| R8 | Login brute-force limit | Security | TC-RL-01..06; `test_login_is_rate_limited_after_five_attempts` | 6th attempt → 429 + Retry-After | Pass | Pass | 05 |
| R9 | Object-level authorisation: other users' tickets are not exposed, and their existence is not revealed | Authorization | TC-AZ-01, TC-AZ-02, TC-AZ-06; `test_def01_*` (3 tests); updated Week 14 tests | 404, same body as an unknown id | **Fail** (403 reveals the ticket exists) | Pass | DEF-01 |
| R10 | Function-level authorisation (role) | Authorization | TC-AZ-03, TC-AZ-04, TC-AZ-07; `test_requester_cannot_change_status_or_assign` | 403 for a visible ticket and a wrong role | Pass | Pass | 05 |
| R11 | Duplicate submission (double click or retry) creates one ticket | Reliability | TC-DUP-01, TC-DUP-02; `test_def02_*` (4 tests); Flutter ST-10, ST-11 | 200 replay + `Idempotent-Replayed`; 409 on payload mismatch | **Fail** (second ticket created) | Pass | DEF-02 |
| R12 | Wrong-state actions are conflicts, not permission errors | Contract | TC-STA-01..03; `test_def03_*`; `test_invalid_status_transition_is_refused`; UI ui-07 | 409 with reason; UI reloads | **Fail** (403) | Pass | DEF-03, ui-07 |
| R13 | Database outage fails safely: 503, Retry-After, correlation id, no internals | Reliability / Security | Live FI F1; `test_def04_database_outage_returns_safe_503`; Flutter ST-04; UI ui-08 | 503 generic body | **Fail** (500 leaking DB path and SQL) | Pass | DEF-04, 03 vs 06 |
| R14 | Health/readiness signal reports the dependency | Reliability | TC-HLT-01, TC-CON-02; Live FI F1/F2; `test_def04_health_*` | 200 ok / 503 degraded | **Fail** (no endpoint) | Pass | DEF-04 |
| R15 | Recovery after the outage without re-login | Reliability | Live FI F2; Flutter ST-03; UI ui-09 → ui-10 | Try again recovers | **Fail** in debug build (DEF-10) | Pass | DEF-10, ui-10 |
| R16 | Dependency timeout is bounded (gateway → API) | Reliability | Live FI F3; `test_def08_*` (2 tests) | ≤ 3 attempts × 3 s, non-zero exit, no stack trace | **Fail** (30 s wait, then crash) | Pass (11 s, exit 1) | DEF-08 |
| R17 | Error responses do not leak routes, methods, or stack traces | Security | TC-CON-01; `test_def06_method_not_allowed_is_generic`; scan §4 | generic 405; APP_DEBUG=false | **Fail** | Pass | DEF-06, DEF-09 |
| R18 | Browser interoperability: CORS allows only the Flutter origin and the needed headers | Interoperability | TC-CON-04, TC-CON-05, TC-CON-07; `test_def07_*` | allowed for localhost:5000/5015 only; Idempotency-Key allowed | **Fail** (Idempotency-Key blocked) | Pass | DEF-07 |
| R19 | Correlation id on every response; malformed ids replaced | Observability | TC-CON-02; `test_every_api_response_carries_a_correlation_id`; log excerpt | header present and echoed | Pass | Pass | 07 |
| R20 | Security headers on API responses | Security | TC-CON-03; `TransportSecurityTest` | nosniff, CSP, no-store, JSON | Pass | Pass | 05 |
| R21 | Signed email-gateway messages only (Week 14 control kept) | Security / Interop | TC-CON-06; `IntegrationSignatureTest` (tamper, expiry, replay, wrong key) | 401 / 409 | Pass | Pass | 04 |
| R22 | Protected fields encrypted at rest and masked by role (Week 14 control kept) | Security | `ProtectedDataTest`; ui-06 | ciphertext in DB, masked for others | Pass | Pass | 04 |
| R23 | Flutter UI states: loading, success, empty, validation, 401, 404, network, 503, timeout | UI state | Flutter ST-01..ST-11 | correct message, no raw server text | ST-03 **Fail** (DEF-10) | Pass | 08, 08b |
| R24 | Responsive layout at 375 px | Usability | Flutter ST-12; ui-12, ui-13 | fields stack, no overflow | Pass | Pass | 08, ui-12/13 |
| R25 | No secrets or tokens in source, config examples, or evidence | Security | `tools/secret-scan.sh` | 0 real secrets | n/a | Pass | 09 |

Exit criteria for Week 15:

* All 72 PHPUnit tests pass.
* All 49 live Postman requests pass.
* All 17 Flutter tests pass.
* Every DEF-xx has a test that failed before its fix and passes after it.

All four criteria were met on 17 November 2026.
