# IT Help Desk Ticket Router — Project 16

PFEBSIT 002 Integrative Programming and Technologies 2 · Weeks 13–18 individual project
Flutter Web client + Dart (shelf) backend API · controlled, fictional data only.

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
  backend/
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

Requirements: Flutter SDK (stable, web enabled) — it includes Dart. Tested with Flutter 3.47.8 / Dart 3.13.7 on Windows 10.

```bash
cd backend
cp .env.example .env        # then change GATEWAY_API_KEY to any local value
dart pub get
```

```bash
cd frontend
flutter pub get
```

## Run (three terminals)

1. Mock notification gateway:
   ```bash
   cd backend && dart run bin/mock_gateway.dart
   ```
2. API server (http://127.0.0.1:8080):
   ```bash
   cd backend && dart run bin/server.dart
   ```
3. Flutter Web client:
   ```bash
   cd frontend && flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8080
   ```

Sign in by choosing a demo user: **Ana / Ben / Gio** (requesters — Gio's mailbox is deliberately invalid), **Carla, Noel, Dan, Eli, Faith** (agents), **Mara** (supervisor).
Week 13 uses a demo identity header (`X-Demo-User`); real authentication is added in Week 14.

To start with fresh data, stop the server and delete `backend/data/`.

## Tests and evidence

```bash
cd backend && dart test
```

```bash
cd frontend && flutter test
```

Regenerate the evidence (gateway and server running, fresh `backend/data/`):

```bash
cd backend && dart run tool/run_evidence.dart
```

Inject faults by hand (gateway must be running):

```bash
curl -X POST http://127.0.0.1:8091/admin/fault -H "Content-Type: application/json" -d "{\"failNext\": 2, \"status\": 503}"
```

## Configuration

All settings are in `backend/.env` (see `.env.example`): ports, retry limits, scheduler intervals, SLA hours per priority, warning ratio, summary hour, allowed CORS origins. `.env`, `data/` and `logs/` are git-ignored. The Flutter app only receives the API base URL; it never holds a secret.

## Known limitations (Week 13)

Demo identity only, plain HTTP on localhost, single-process JSON file store, mock gateway, keyword routing. See section 9 of the report. Not production ready.
