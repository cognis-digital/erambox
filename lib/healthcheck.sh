# lib/healthcheck.sh - health probing for erambox
#
# Maintainer: Cognis Digital
# License: COCL 1.0
#
# Builds the list of health-probe targets from CFG and either lists them
# (--dry-run, no network) or probes them with curl/wget.

# health_targets PROFILE -- echo one "LABEL<TAB>URL" per line.
health_targets() {
  local profile="$1"
  local host health http_port https_port app_port
  host="$(config_get PUBLIC_HOSTNAME localhost)"
  health="$(config_get HEALTH_PATH /health)"
  http_port="$(config_get PROXY_HTTP_PORT "")"
  https_port="$(config_get PROXY_HTTPS_PORT "")"
  app_port="$(config_get APP_PORT "")"

  if [ "$profile" = "prod" ]; then
    # Prod reaches the app only through the TLS proxy.
    if [ -n "$https_port" ]; then
      printf 'proxy-https\thttps://%s:%s%s\n' "$host" "$https_port" "$health"
    fi
    if [ -n "$http_port" ]; then
      # http endpoint should redirect; still a useful liveness target.
      printf 'proxy-http\thttp://%s:%s%s\n' "$host" "$http_port" "$health"
    fi
  else
    # Dev publishes the app directly and the proxy over HTTP.
    if [ -n "$app_port" ]; then
      printf 'app-direct\thttp://%s:%s%s\n' "$host" "$app_port" "$health"
    fi
    if [ -n "$http_port" ]; then
      printf 'proxy-http\thttp://%s:%s%s\n' "$host" "$http_port" "$health"
    fi
  fi
}

# health_probe_one URL -- returns 0 if reachable/2xx-3xx, else 1.
health_probe_one() {
  local url="$1"
  if command -v curl >/dev/null 2>&1; then
    local code
    code="$(curl -ksS -o /dev/null -w '%{http_code}' --max-time 10 "$url" 2>/dev/null || echo 000)"
    case "$code" in
      2??|3??) return 0 ;;
      *) return 1 ;;
    esac
  elif command -v wget >/dev/null 2>&1; then
    wget -q --spider --timeout=10 --no-check-certificate "$url" >/dev/null 2>&1
    return $?
  else
    err "no curl or wget available to probe (use --dry-run)"
    return 2
  fi
}

# healthcheck_run PROFILE DRYRUN
healthcheck_run() {
  local profile="$1" dryrun="$2"
  local targets
  targets="$(health_targets "$profile")"

  if [ -z "$targets" ]; then
    err "no health targets resolved (check PROXY_HTTP_PORT / APP_PORT in config)"
    return 1
  fi

  if is_truthy "$dryrun"; then
    log "health targets (profile=$profile, dry-run, no network):"
    local label url
    while IFS=$'\t' read -r label url; do
      [ -n "$label" ] || continue
      printf '%s\t%s\n' "$label" "$url"
    done <<< "$targets"
    return 0
  fi

  local failures=0 label url
  while IFS=$'\t' read -r label url; do
    [ -n "$label" ] || continue
    if health_probe_one "$url"; then
      log "OK   $label  $url"
    else
      err "FAIL $label  $url"
      failures=$((failures + 1))
    fi
  done <<< "$targets"

  if [ "$failures" -gt 0 ]; then
    err "healthcheck: $failures target(s) failed"
    return 1
  fi
  log "healthcheck: all targets healthy"
  return 0
}

# cmd_healthcheck -- CLI entrypoint.
cmd_healthcheck() {
  local config="" profile="" dryrun="false"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --config)  require_value "$1" "${2-}"; config="$2"; shift 2 ;;
      --profile) require_value "$1" "${2-}"; profile="$2"; shift 2 ;;
      --dry-run) dryrun="true"; shift ;;
      --help|-h) usage; return 0 ;;
      *) die "healthcheck: unknown option '$1'" ;;
    esac
  done

  config_load "$config"
  config_apply_defaults
  [ -n "$profile" ] || profile="$(config_effective_profile dev)"

  healthcheck_run "$profile" "$dryrun"
}
