# IT Help Desk Ticket Router — Project 16

PFEBSIT 002 Integrative Programming and Technologies 2 · Weeks 13–18 individual project
Flutter Web client + Laravel 13 / MySQL backend API · controlled, fictional data only.

**Current milestone: Week 13 — Automation Foundation (SA7).** Report: [docs/week13_report.md](docs/week13_report.md)

## What it does

Requesters submit IT problems. The backend categorises each ticket by keyword rules, sets its priority and SLA, and assigns it to the least-loaded available agent in the right team (or sends it to a supervisor for triage). Agents respond and resolve; requesters confirm or reopen. Automation:

- **Rule-based assignment** on submit (event-driven)
- **SLA aging alerts** — warning at 75 %, escalation at 100 % (scheduled scan, every 60 s)
- **Reassignment** when an agent is marked unavailable
- **Failed-notification recovery** — transactional outbox, bounded retry with backoff, dead-letter → supervisor manual review
- **Support summaries** — daily at 18:00 local, or on demand

## Folder layout

```
helpdesk_ticket_router/
  backend-laravel/             Laravel API (current backend) — see backend-laravel/README.md
    routes/api.php             API routes (same contract as docs/openapi.yaml)
    app/Services/              tickets, rules, outbox, retry, aging, summaries, job runner
    routes/console.php         scheduler + `php artisan helpdesk:job`
    database/                  MySQL migration and seed users
    gateway/mock_gateway.php   mock notification service (fault injection)
    tests/                     41 PHPUnit tests (MySQL test database)
  backend/                     original Dart (shelf) backend, kept for reference
    bin/server.dart            API server
    bin/mock_gateway.dart      mock notification service (fault injection)
    lib/src/                   api, tickets, rules, outbox, retry, automation, store, logger, config
    config/routing_rules.json  routing keywords -> team (editable without code changes)
    test/                      36 automated tests
    tool/run_evidence.dart     runs the Week 13 scenarios and writes evidence/
    .env.example               configuration template (no secrets)
  frontend/                    Flutter Web app (lib/src/screens, widgets, api_client) + 5 widget tests
  docs/
    week13_report.md           SA7 submission
    openapi.yaml               API contract
  evidence/
    week13_run.md / .json      scenario results with correlation ids
    app_structured.log         backend structured log from the evidence run
    mock_gateway.log           gateway log (injected faults, deliveries)
    screenshots/               desktop and phone-width screenshots
```

## Setup

Requirements: PHP 8.3+ with `pdo_mysql`, Composer, MySQL/MariaDB (XAMPP works), and the Flutter SDK (stable, web enabled).

```bash
cd backend-laravel
composer install
cp .env.example .env        # then change GATEWAY_API_KEY to any local value
php artisan key:generate
mysql -u root -e "CREATE DATABASE helpdesk CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
php artisan migrate --seed
```

```bash
cd frontend
flutter pub get
```

## Run (four terminals)

1. Mock notification gateway:
   ```bash
   cd backend-laravel && php -S 127.0.0.1:8091 gateway/mock_gateway.php
   ```
2. API server (http://127.0.0.1:8080):
   ```bash
   cd backend-laravel && php artisan serve --host=127.0.0.1 --port=8080
   ```
3. Scheduler (outbox dispatch, SLA aging scan, daily summary):
   ```bash
   cd backend-laravel && php artisan schedule:work
   ```
4. Flutter Web client:
   ```bash
   cd frontend && flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8080
   ```

Sign in by choosing a demo user: **Ana / Ben / Gio** (requesters — Gio's mailbox is deliberately invalid), **Carla, Noel, Dan, Eli, Faith** (agents), **Mara** (supervisor).
Week 13 uses a demo identity header (`X-Demo-User`); real authentication is added in Week 14.

To start with fresh data: `cd backend-laravel && php artisan migrate:fresh --seed`.

## Tests

```bash
mysql -u root -e "CREATE DATABASE helpdesk_test CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
```

```bash
cd backend-laravel && php artisan test
```

```bash
cd frontend && flutter test
```

Inject faults by hand (gateway must be running):

```bash
curl -X POST http://127.0.0.1:8091/admin/fault -H "Content-Type: application/json" -d "{\"failNext\": 2, \"status\": 503}"
```

## Configuration

All settings are in `backend-laravel/.env` (see `.env.example`): database connection, retry limits, outbox poll interval, SLA hours per priority, warning ratio, summary hour, allowed CORS origins. `.env`, `vendor/` and `storage/logs/` are git-ignored. The Flutter app only receives the API base URL; it never holds a secret.

## Known limitations (Week 13)

Demo identity only, plain HTTP on localhost, a single global write lock in MySQL, mock gateway, keyword routing. See section 9 of the report. Not production ready.
