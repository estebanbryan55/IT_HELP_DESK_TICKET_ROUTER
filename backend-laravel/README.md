# Help Desk API — Laravel backend

Laravel 13 + MySQL implementation of the IT Help Desk Ticket Router API. It replaces the Dart (shelf) backend in `../backend`
and keeps the same contract (`../docs/openapi.yaml`), so the Flutter Web client works unchanged.

## Where things are

| Concern | File |
|---|---|
| Routes (same paths as the Dart server) | `routes/api.php` |
| Controllers, demo identity (`X-Demo-User`), JSON body parsing | `app/Http/Controllers/Api/` |
| Correlation id, CORS, access log middleware | `app/Http/Middleware/` |
| Error format `{"error": {code, message, details?, correlationId}}` | `bootstrap/app.php`, `app/Exceptions/ApiException.php` |
| Ticket workflow, routing, assignment | `app/Services/TicketService.php`, `app/Services/RoutingRules.php`, `config/routing_rules.json` |
| Transactional outbox, retry with backoff, dead letter | `app/Services/Outbox.php`, `app/Services/RetryPolicy.php`, `app/Services/HttpNotificationGateway.php` |
| SLA aging, reassignment, daily summary, job runs | `app/Services/AgingScanner.php`, `app/Services/SummaryService.php`, `app/Services/JobRunner.php` |
| Scheduler and `helpdesk:job` command | `routes/console.php` |
| Schema and seed users | `database/migrations/`, `database/seeders/DatabaseSeeder.php` |
| Settings (read from `.env`) | `config/helpdesk.php` |
| Mock notification gateway (fault injection) | `gateway/mock_gateway.php` |
| Structured JSON-lines log | `storage/logs/app.log` |

Every write runs in a MySQL transaction that first locks one row (`app_state.lock`), so the API and the scheduler never
change state at the same time, and a failed request rolls back completely.

## Setup

Requirements: PHP 8.3+ with `pdo_mysql`, Composer, and MySQL/MariaDB (XAMPP works).

```bash
composer install
cp .env.example .env
php artisan key:generate
```

Create the database (XAMPP: root with no password), then create the tables and seed users:

```bash
mysql -u root -e "CREATE DATABASE helpdesk CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
php artisan migrate --seed
```

Start over with fresh data at any time with `php artisan migrate:fresh --seed`.

## Run (three terminals, from this folder)

```bash
php -S 127.0.0.1:8091 gateway/mock_gateway.php
```

```bash
php artisan serve --host=127.0.0.1 --port=8080
```

```bash
php artisan schedule:work
```

The scheduler runs `outbox-dispatch` every 5 s, `aging-scan` every minute, and the daily summary check every minute
(it generates once a day after `SUMMARY_HOUR`). Submitting a ticket also starts a dispatch in the background
right away, so notifications don't wait for the next poll.

Run a job by hand:

```bash
php artisan helpdesk:job aging-scan
```

## Tests

Tests use a separate database, `helpdesk_test`, and a scripted fake gateway:

```bash
mysql -u root -e "CREATE DATABASE helpdesk_test CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"
php artisan test
```
