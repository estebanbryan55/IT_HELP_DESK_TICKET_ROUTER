# IT Help Desk Ticket Router (Project 16)

PFEBSIT 002 Integrative Programming and Technologies 2, Weeks 13–18 individual project.
Current milestone: **Week 15: Integration Testing and Security Hardening (IA6)**.

| Layer | Technology |
|---|---|
| Web client | Flutter Web (Flutter 3.47, Dart 3.13) in `frontend/` |
| Backend API | **Laravel 13** (PHP 8.4) with Laravel Sanctum in `backend/` |
| Database | SQLite for the lab. MySQL/MariaDB is the deployment target. |

> Prototype for coursework. It uses fictional data only and is **not production ready**.

Week 15 starts from the Week 14 code (`../week14`, unchanged). It adds tests at every layer, reproduces the weaknesses they found, fixes them, and reruns everything as regression evidence.

## What changed in Week 15

| Defect | Fix | Where |
|---|---|---|
| DEF-01 403 revealed that another user's ticket exists (BOLA) | 404 for tickets the caller cannot view | `TicketController::authorizeVisible()` |
| DEF-02 double submit / retry created duplicate tickets | `Idempotency-Key` header + payload hash + unique index; Flutter sends one key per form | `TicketController@store`, migration `2026_11_17_*`, `new_ticket_screen.dart` |
| DEF-03 wrong-state actions answered 403 | 409 with a reason; UI reloads the ticket | `TicketController`, `TicketPolicy`, `ticket_detail_screen.dart` |
| DEF-04 DB outage → 500 leaking path and SQL, no health signal | 503 + Retry-After + `correlation_id`; `GET /api/v1/health` | `bootstrap/app.php`, `App\Support\DependencyFailure`, `HealthController` |
| DEF-05 unknown `?status=` returned an empty list | 422 | `TicketController@index` |
| DEF-06 405 listed routes and methods | generic 405 | `bootstrap/app.php` |
| DEF-07 CORS blocked `Idempotency-Key` | header allowed and exposed | `config/cors.php` |
| DEF-08 gateway client waited 30 s, then crashed | 3 s timeout, 3 bounded retries, clean exit 1 | `SendGatewayMessage` |
| DEF-09 `APP_DEBUG=true` in the lab `.env` | `false`, checked by the scan | `.env`, `tools/secret-scan.sh` |
| DEF-10 Flutter "Try again"/"Refresh" threw in debug builds | block-bodied `setState` | `ticket_list_screen.dart`, `ticket_detail_screen.dart` |

Details are in `docs/defect-log.md`, `docs/traceability-matrix.md`, and `docs/hardening-report.md`.

## Results

| Suite | Before (Week 14 code) | After |
|---|---|---|
| PHPUnit (backend) | 57/72 | **72/72** (238 assertions) |
| Postman collection, live API | 37/49 | **49/49** |
| Flutter tests | ST-03 failing | **17/17** |
| Database outage | 500 + internals | 503 safe, health `degraded`, UI recovers |
| Gateway timeout | 30 s, stack trace | 11 s, 3 attempts, exit 1 |

## Run locally

Double-click `RUN.bat`. It starts the API on **:8015** and the web app on **:5015**, so Week 14 on :8000/:5000 can keep running.

Or run it manually:

```bash
cd backend
composer install
cp .env.example .env
php artisan key:generate
```

In `.env`, set `REQUIRE_HTTPS=false` (local only), `FRONTEND_ORIGINS=http://localhost:5000,http://localhost:5015`, `INTEGRATION_HMAC_KEYS=gw-2026a:<64 hex chars>`, `GATEWAY_KEY_ID=gw-2026a`, and `GATEWAY_URL=http://127.0.0.1:8015/api/v1/integrations/email-gateway/tickets`.

```bash
php artisan migrate:fresh --seed
php artisan serve --port=8015
```

Then, in a second terminal:

```bash
cd frontend
flutter pub get
flutter run -d chrome --web-port 5015 --dart-define=API_BASE_URL=http://127.0.0.1:8015/api/v1
```

Demo accounts (password `Demo-Pass-2026!`, lab only): `student@example.test`, `employee@example.test`, `agent.network@example.test`, `agent.hardware@example.test`, `agent.accounts@example.test`, `supervisor@example.test`.

## Reproduce the Week 15 evidence

```bash
cd backend && php artisan test                     # 72 backend tests
cd frontend && flutter test                        # 17 Flutter tests
node tools/build-collection.mjs                    # regenerate the Postman collection
node tools/run-collection.mjs postman/Week15_IA6_HelpDesk.postman_collection.json --base http://127.0.0.1:8015/api/v1
bash tools/failure-injection.sh "my run"           # DB outage, recovery, gateway timeout (API must be on :8015)
bash tools/secret-scan.sh                          # secrets and hardened settings
```

The Postman collection can also be imported into Postman directly. Run the collection from a freshly seeded database (`php artisan migrate:fresh --seed`), and wait one minute between runs because of the login rate limit.

UI screenshots: build the web app with `flutter build web --dart-define=API_BASE_URL=http://127.0.0.1:8015/api/v1`, then run `node tools/serve-web.mjs 5015` and `node tools/capture-screens.mjs`. This needs Microsoft Edge or Chrome.

## Evidence

See `evidence/README.md` for the full index. Screenshots are in `evidence/screenshots/`. The Word report is `evidence/Week15_Project16_IT_Help_Desk_Ticket_Router_Report.docx`.
