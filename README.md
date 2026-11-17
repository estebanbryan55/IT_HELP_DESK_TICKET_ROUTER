# IT Help Desk Ticket Router (Project 16)

PFEBSIT 002 Integrative Programming and Technologies 2, Weeks 13–18 individual project.
Current milestone: **Week 14: Secure Data Exchange and Encryption (SA8 and IA5)**.

| Layer | Technology |
|---|---|
| Web client | Flutter Web (Flutter 3.47, Dart 3.13) in `frontend/` |
| Backend API | **Laravel 13** (PHP 8.4) with Laravel Sanctum in `backend/` |
| Database | SQLite for the lab. MySQL/MariaDB is the deployment target. |

> Prototype for coursework. It uses fictional data only and is **not production ready**.

## Bounded workflow

A requester (student or employee) submits a ticket. Rule-based routing assigns it to the least-loaded active agent who specialises in that category. The agent starts work and resolves the ticket with a note. The requester then confirms the fix (closed) or rejects it (reopened). A supervisor sees everything and can reassign. An email gateway can also create tickets through an HMAC-signed endpoint.

## Week 14 security controls

| Control | Where |
|---|---|
| Bearer tokens (Sanctum), stored as SHA-256 hashes, 60-minute expiry, revoked on logout | `AuthController`, `config/sanctum.php` |
| Login rate limit (5/min per email+IP), generic error, timing-equalised check | `AppServiceProvider`, `AuthController` |
| Role + ownership authorisation | `app/Policies/TicketPolicy.php`, list scoping in `TicketController@index` |
| Server-side validation (authoritative) and data minimisation | `app/Http/Requests/*` |
| Field encryption at rest (AES-256-CBC + HMAC-SHA256, Laravel `Crypt`) for `contact_number` and `access_note`, with tamper detection | `app/Casts/ProtectedString.php` |
| Role-based masking of protected fields in responses | `app/Http/Resources/TicketResource.php` |
| HMAC-SHA256 signed gateway messages: key id, timestamp window, nonce replay check | `app/Http/Middleware/VerifyIntegrationSignature.php`, `app/Services/MessageSigner.php` |
| HTTPS required (403 on plain HTTP), HSTS, security headers, strict CORS | `RequireHttps`, `SecurityHeaders`, `config/cors.php` |
| Correlation IDs plus log redaction of secrets and protected fields | `AssignCorrelationId`, `app/Logging/RedactSensitiveData.php` |
| Append-only audit trail of state changes | `ticket_events` table, `TicketRouter::record()` |

## Run locally

Backend:

```bash
cd backend
composer install
cp .env.example .env
php artisan key:generate
```

In `.env`, set `REQUIRE_HTTPS=false` (local only) and give each of these a value:
`INTEGRATION_HMAC_KEYS=gw-2026a:<64 hex chars>`, `GATEWAY_KEY_ID=gw-2026a`, `GATEWAY_URL=http://127.0.0.1:8010/api/v1/integrations/email-gateway/tickets`.

```bash
php artisan migrate:fresh --seed
php artisan serve --port=8010
```

Frontend (in a second terminal):

```bash
cd frontend
flutter pub get
flutter run -d chrome --web-port 5000 --dart-define=API_BASE_URL=http://127.0.0.1:8010/api/v1
```

Demo accounts (password `Demo-Pass-2026!`, lab only): `student@example.test`, `employee@example.test`, `agent.network@example.test`, `agent.hardware@example.test`, `agent.accounts@example.test`, `supervisor@example.test`.

## Tests and evidence

```bash
cd backend && php artisan test
cd frontend && flutter test
cd backend && php artisan gateway:send --tamper
```

`gateway:send` also accepts `--expired`, `--replay`, and `--wrong-key`.

Saved results are in `evidence/week14/`:

| File | Content |
|---|---|
| `01-phpunit-testdox.txt` | 46 backend tests (auth, authorisation, encryption, HMAC, transport) |
| `02-gateway-simulator.txt` | Live signed-message runs: valid, tampered, expired, wrong key, replay |
| `03-api-adverse-cases.txt` | Live curl run: bad login, missing/forged/revoked token, IDOR, validation, ciphertext at rest, headers |
| `04-protected-log-excerpt.txt` | Log lines with correlation ids and rejection reasons, no secrets |
| `05-flutter-tests.txt` | Flutter widget and API-client tests |
| `06-secret-scan.txt` | Repository secret scan |
| `data-flow-diagram.png` | Trust boundaries and flows |
| `ui-*.jpg` | Flutter Web screens, including the 375 px layout and validation states |

## Deployment note (HTTPS)

TLS is terminated at a reverse proxy (Nginx or Caddy) in front of `php artisan serve` / PHP-FPM. Set `TRUSTED_PROXIES` to the proxy address so Laravel honours `X-Forwarded-Proto`. Keep `REQUIRE_HTTPS=true` and `APP_DEBUG=false`. Load secrets from the host's secret store, never from the repository.
