#!/usr/bin/env bash
# Week 15 controlled failure injection (Git Bash / Linux).
#   bash tools/failure-injection.sh "label" > evidence/<file>.txt
#
# F1  Database unavailable: a second API instance on :8016 points at a
#     SQLite file that does not exist. Normal instance on :8015 is untouched.
# F2  Recovery: the same requests against the healthy instance on :8015.
# F3  Dependency timeout: gateway:send posts to a stub on :8017 that answers
#     after 35 s, so the HTTP client must time out and give up.
set -u
cd "$(dirname "$0")/../backend"
LABEL="${1:-run}"
SERVER_PHP="vendor/laravel/framework/src/Illuminate/Foundation/resources/server.php"

echo "=== Week 15 failure injection: $LABEL"
echo "Date: $(date -Iseconds)   PHP: $(php -r 'echo PHP_VERSION;')"
echo

stop_port() { # stop whatever listens on a port (Windows via PowerShell, else fuser)
  if command -v powershell >/dev/null; then
    powershell -NoProfile -Command "Get-NetTCPConnection -LocalPort $1 -State Listen -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id \$_.OwningProcess -Force }"
  else
    fuser -k "$1/tcp" >/dev/null 2>&1
  fi
}

show() { # method url [json]
  local out
  if [ -n "${3:-}" ]; then
    out=$(curl -s -i -X "$1" "$2" -H 'Accept: application/json' -H 'Content-Type: application/json' -d "$3")
  else
    out=$(curl -s -i -X "$1" "$2" -H 'Accept: application/json')
  fi
  echo "$out" | head -1
  echo "$out" | grep -i -E '^(x-correlation-id|retry-after):'
  # body only (everything after the blank line), flattened to one line
  echo "body: $(echo "$out" | tr -d '\r' | sed '1,/^$/d' | tr -s ' \n' ' ' | cut -c1-420)"
}

echo "--- F1 Database unavailable (instance :8016, DB_DATABASE=missing file)"
# Laravel's server.php must run with public/ as the working directory.
(cd public && DB_DATABASE="$OLDPWD/storage/does-not-exist/missing.sqlite" \
  php -S 127.0.0.1:8016 "../$SERVER_PHP" >/dev/null 2>&1) &
until curl -s -o /dev/null http://127.0.0.1:8016/up 2>/dev/null; do sleep 0.3; done
echo "> GET /api/v1/health"
show GET http://127.0.0.1:8016/api/v1/health
echo "> POST /api/v1/auth/login"
show POST http://127.0.0.1:8016/api/v1/auth/login '{"email":"student@example.test","password":"Demo-Pass-2026!"}'
stop_port 8016
echo

echo "--- F2 Recovery check on the healthy instance (:8015)"
echo "> GET /api/v1/health"
show GET http://127.0.0.1:8015/api/v1/health
echo "> POST /api/v1/auth/login"
out=$(curl -s -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:8015/api/v1/auth/login \
  -H 'Accept: application/json' -H 'Content-Type: application/json' \
  -d '{"email":"employee@example.test","password":"Demo-Pass-2026!"}')
echo "HTTP $out (token body omitted from evidence)"
echo

echo "--- F3 Gateway dependency timeout (stub on :8017 answers after 35 s)"
php -S 127.0.0.1:8017 ../tools/slow-upstream.php >/dev/null 2>&1 &
sleep 1
START=$(date +%s)
GATEWAY_URL=http://127.0.0.1:8017/api/v1/integrations/email-gateway/tickets php artisan gateway:send 2>&1 \
  | sed 's/\x1b\[[0-9;]*m//g' | grep -v '^\s*$' | head -12
echo "exit code: ${PIPESTATUS[0]}   elapsed: $(( $(date +%s) - START )) s"
stop_port 8017
echo
echo "=== end"
