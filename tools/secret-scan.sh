#!/usr/bin/env bash
# Week 15 secret and hardening-configuration scan.
#   bash tools/secret-scan.sh > evidence/09-secret-and-config-scan.txt
set -u
cd "$(dirname "$0")/.."
EXCLUDE=(--exclude-dir=vendor --exclude-dir=node_modules --exclude-dir=build --exclude-dir=.dart_tool
         --exclude-dir=storage --exclude-dir=screenshots --exclude=.env --exclude='*.sqlite' --exclude='*.lock'
         --exclude='01b-baseline-phpunit-raw.txt')
ENV=backend/.env

echo "# Week 15 secret and configuration scan $(date -Iseconds)"
echo "# Scope: week15/ (backend, frontend, tools, postman, docs, evidence), excluding vendor/, build/, .dart_tool/,"
echo "# storage/, the git-ignored backend/.env, database/*.sqlite, lock files"
echo

echo "## 1. Real APP_KEY / HMAC secrets from backend/.env found anywhere else?"
hits=0
for v in $(grep -E '^(APP_KEY|INTEGRATION_HMAC_KEYS)=' "$ENV" | cut -d= -f2- | tr ',' '\n' | sed 's/^[^:]*://; s/^base64://'); do
  [ ${#v} -lt 16 ] && continue
  n=$(grep -rl "${EXCLUDE[@]}" -F "$v" . 2>/dev/null | wc -l)
  hits=$((hits + n))
done
echo "files containing them: $hits"
echo

echo "## 2. Pattern scan (64-hex keys, base64 app keys, private keys, Sanctum bearer tokens)"
grep -rnE "${EXCLUDE[@]}" '(base64:[A-Za-z0-9+/]{40,}={0,2}|\b[0-9a-f]{64}\b|BEGIN [A-Z ]*PRIVATE KEY|\b[0-9]+\|[A-Za-z0-9]{40}\b|hdr_[0-9]+\|[A-Za-z0-9]{20,})' . \
  | grep -v 'request_hash' || echo "no matches"
echo "(Expected hits: only the deliberately fake 'hdr_1|forged...' token used by test TC-AUTH-07.)"
echo

echo "## 3. backend/.env is git-ignored"
grep -n '^\.env$' backend/.gitignore
echo

echo "## 4. Hardened settings (DEF-09: debug must be off; HTTPS required outside local)"
echo "backend/.env:         $(grep -E '^APP_DEBUG=' "$ENV")   $(grep -E '^APP_ENV=' "$ENV")   $(grep -E '^REQUIRE_HTTPS=' "$ENV") (local lab only)"
echo "backend/.env.example: $(grep -E '^APP_DEBUG=' backend/.env.example)   $(grep -E '^REQUIRE_HTTPS=' backend/.env.example)"
echo

echo "## 5. .env.example secret slots are empty"
grep -nE '^(APP_KEY|INTEGRATION_HMAC_KEYS|GATEWAY_KEY_ID)=' backend/.env.example
echo

echo "## 6. Flutter source contains no credentials or keys"
grep -rniE '(password|secret|api[_-]?key|token)\s*[:=]\s*["'"'"'][^"'"'"']{6,}' frontend/lib || echo "no matches"
echo

echo "## 7. Evidence files contain no bearer tokens (Postman runs are redacted)"
grep -c 'REDACTED' evidence/02-baseline-postman-run.json evidence/05-regression-postman-run.json
