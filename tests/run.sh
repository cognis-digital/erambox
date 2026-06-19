#!/usr/bin/env bash
#
# tests/run.sh -- self-contained test suite for erambox (Cognis Digital).
# Plain bash, no Docker, no network. Exits non-zero on any failure.
#
# License: COCL 1.0
set -uo pipefail

TESTS_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
ROOT_DIR="$(cd -P "$TESTS_DIR/.." >/dev/null 2>&1 && pwd)"
ERAMBOX="$ROOT_DIR/erambox.sh"

PASS=0
FAIL=0
WORK="$(mktemp -d 2>/dev/null || mktemp -d -t erambox)"
trap 'rm -rf "$WORK"' EXIT

ok()   { PASS=$((PASS+1)); printf 'ok   - %s\n' "$1"; }
nok()  { FAIL=$((FAIL+1)); printf 'FAIL - %s\n' "$1"; }

# assert_contains FILE PATTERN MSG  -- grep -F (literal) unless 4th arg "regex"
assert_contains() {
  local file="$1" pat="$2" msg="$3" mode="${4:-fixed}"
  local flag="-F"
  [ "$mode" = "regex" ] && flag="-E"
  if grep -q $flag -- "$pat" "$file" 2>/dev/null; then
    ok "$msg"
  else
    nok "$msg (pattern not found: $pat in $file)"
  fi
}

assert_not_contains() {
  local file="$1" pat="$2" msg="$3"
  if grep -qF -- "$pat" "$file" 2>/dev/null; then
    nok "$msg (unexpected pattern present: $pat)"
  else
    ok "$msg"
  fi
}

# run erambox, capture exit code
run_eb() {
  bash "$ERAMBOX" "$@" >"$WORK/_out" 2>"$WORK/_err"
  return $?
}

# ==========================================================================
# 1. --help works and is non-empty
# ==========================================================================
if run_eb --help && grep -q 'erambox' "$WORK/_out"; then
  ok "--help prints usage"
else
  nok "--help prints usage"
fi

# ==========================================================================
# 2. validate passes on the dev example
# ==========================================================================
if run_eb validate --config "$ROOT_DIR/examples/grc.env"; then
  ok "validate passes on examples/grc.env (dev)"
else
  nok "validate passes on examples/grc.env (dev)"
fi

# ==========================================================================
# 3. validate passes on the prod example
# ==========================================================================
if run_eb validate --config "$ROOT_DIR/examples/grc-prod.env"; then
  ok "validate passes on examples/grc-prod.env (prod)"
else
  nok "validate passes on examples/grc-prod.env (prod)"
fi

# ==========================================================================
# 4. validate FAILS on missing required var
# ==========================================================================
cat > "$WORK/missing.env" <<'EOF'
ERAMBOX_PROFILE=dev
APP_NAME=x
APP_IMAGE=grc/webapp:latest
# APP_PORT intentionally omitted
DB_IMAGE=postgres:16-alpine
DB_NAME=grc
DB_USER=grc
DB_PASSWORD=grc-dev-password
PROXY_IMAGE=nginx:1.27-alpine
PROXY_HTTP_PORT=8000
EOF
if run_eb validate --config "$WORK/missing.env"; then
  nok "validate fails on missing APP_PORT"
else
  ok "validate fails (non-zero) on missing APP_PORT"
fi

# ==========================================================================
# 5. validate FAILS on port conflict
# ==========================================================================
cat > "$WORK/conflict.env" <<'EOF'
ERAMBOX_PROFILE=dev
APP_NAME=x
APP_IMAGE=grc/webapp:latest
APP_PORT=8000
APP_INTERNAL_PORT=8080
DB_IMAGE=postgres:16-alpine
DB_NAME=grc
DB_USER=grc
DB_PASSWORD=grc-dev-password
PROXY_IMAGE=nginx:1.27-alpine
PROXY_HTTP_PORT=8000
EOF
if run_eb validate --config "$WORK/conflict.env"; then
  nok "validate fails on port conflict"
else
  if grep -q 'port conflict' "$WORK/_err"; then
    ok "validate fails (non-zero) on port conflict"
  else
    nok "validate fails on port conflict (wrong reason)"
  fi
fi

# ==========================================================================
# 6. validate FAILS on prod without TLS
# ==========================================================================
cat > "$WORK/prod-notls.env" <<'EOF'
ERAMBOX_PROFILE=prod
APP_NAME=x
APP_IMAGE=grc/webapp:1.0
APP_PORT=8080
APP_INTERNAL_PORT=8080
APP_SECRET_KEY=some-long-secret
DB_IMAGE=postgres:16-alpine
DB_NAME=grc
DB_USER=grc
DB_PASSWORD=Str0ng-Prod-Passw0rd
PROXY_IMAGE=nginx:1.27-alpine
PROXY_HTTP_PORT=80
PUBLIC_HOSTNAME=grc.example.com
TLS_ENABLED=false
EOF
if run_eb validate --config "$WORK/prod-notls.env"; then
  nok "validate fails on prod-without-TLS"
else
  if grep -q 'TLS_ENABLED=true' "$WORK/_err"; then
    ok "validate fails (non-zero) on prod-without-TLS"
  else
    nok "validate fails on prod-without-TLS (wrong reason)"
  fi
fi

# ==========================================================================
# 7. generate (dev) emits compose with app+db+proxy services
# ==========================================================================
DEVOUT="$WORK/devout"
if run_eb generate --config "$ROOT_DIR/examples/grc.env" --profile dev --out "$DEVOUT"; then
  ok "generate dev succeeds"
else
  nok "generate dev succeeds"
fi
COMPOSE="$DEVOUT/docker-compose.yml"
if [ -f "$COMPOSE" ]; then
  ok "generate dev writes docker-compose.yml"
  assert_contains "$COMPOSE" "  app:"   "compose has app service"
  assert_contains "$COMPOSE" "  db:"    "compose has db service"
  assert_contains "$COMPOSE" "  proxy:" "compose has proxy service"
  assert_contains "$COMPOSE" "postgres:16-alpine" "compose has db image"
  assert_contains "$COMPOSE" "nginx:1.27-alpine"  "compose has proxy image"
  # dev publishes the app on the host
  assert_contains "$COMPOSE" '"8080:8080"' "dev compose publishes app port"
  # no {{ }} placeholders left unresolved
  assert_not_contains "$COMPOSE" '{{' "dev compose has no unresolved placeholders"
else
  nok "generate dev writes docker-compose.yml"
fi
# config files exist
for f in config/app.conf config/db-init.sql config/proxy.conf; do
  if [ -f "$DEVOUT/$f" ]; then ok "generate dev writes $f"; else nok "generate dev writes $f"; fi
done
# dev proxy is HTTP only (no ssl_certificate directive)
assert_not_contains "$DEVOUT/config/proxy.conf" "ssl_certificate" "dev proxy.conf has no TLS"

# ==========================================================================
# 8. generate (prod) adds TLS / proxy hardening
# ==========================================================================
PRODOUT="$WORK/prodout"
if run_eb generate --config "$ROOT_DIR/examples/grc-prod.env" --profile prod --out "$PRODOUT"; then
  ok "generate prod succeeds"
else
  nok "generate prod succeeds"
fi
PCOMPOSE="$PRODOUT/docker-compose.yml"
PPROXY="$PRODOUT/config/proxy.conf"
if [ -f "$PCOMPOSE" ]; then
  assert_contains "$PCOMPOSE" "  app:"   "prod compose has app service"
  assert_contains "$PCOMPOSE" "  db:"    "prod compose has db service"
  assert_contains "$PCOMPOSE" "  proxy:" "prod compose has proxy service"
  # prod publishes 443 on the proxy
  assert_contains "$PCOMPOSE" '"443:443"' "prod compose publishes HTTPS port"
  # prod mounts TLS material into the proxy
  assert_contains "$PCOMPOSE" "/etc/nginx/tls/cert.pem" "prod compose mounts TLS cert"
  # prod must NOT publish the app directly on the host
  assert_not_contains "$PCOMPOSE" '"8080:8080"' "prod compose does not publish app port"
  assert_not_contains "$PCOMPOSE" '{{' "prod compose has no unresolved placeholders"
else
  nok "generate prod writes docker-compose.yml"
fi
if [ -f "$PPROXY" ]; then
  assert_contains "$PPROXY" "ssl_certificate"            "prod proxy.conf enables TLS"
  assert_contains "$PPROXY" "Strict-Transport-Security"  "prod proxy.conf sets HSTS"
  assert_contains "$PPROXY" "listen 443"                 "prod proxy.conf listens on 443"
  assert_contains "$PPROXY" "return 301 https"           "prod proxy.conf redirects HTTP->HTTPS"
else
  nok "generate prod writes proxy.conf"
fi

# ==========================================================================
# 9. healthcheck --dry-run lists the right targets
# ==========================================================================
# dev: app-direct + proxy-http
if run_eb healthcheck --config "$ROOT_DIR/examples/grc.env" --dry-run; then
  ok "healthcheck dry-run (dev) succeeds"
else
  nok "healthcheck dry-run (dev) succeeds"
fi
assert_contains "$WORK/_out" "http://localhost:8080/health" "dev dry-run lists app-direct target"
assert_contains "$WORK/_out" "http://localhost:8000/health" "dev dry-run lists proxy-http target"

# prod: proxy-https
if run_eb healthcheck --config "$ROOT_DIR/examples/grc-prod.env" --dry-run; then
  ok "healthcheck dry-run (prod) succeeds"
else
  nok "healthcheck dry-run (prod) succeeds"
fi
assert_contains "$WORK/_out" "https://grc.example.com:443/health" "prod dry-run lists proxy-https target"
assert_not_contains "$WORK/_out" "http://grc.example.com:8080" "prod dry-run does not expose app directly"

# ==========================================================================
# 10. unknown command exits non-zero
# ==========================================================================
if run_eb bogus-command; then
  nok "unknown command exits non-zero"
else
  ok "unknown command exits non-zero"
fi

# ==========================================================================
# Summary
# ==========================================================================
echo "----------------------------------------"
echo "PASS=$PASS FAIL=$FAIL"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
exit 0
