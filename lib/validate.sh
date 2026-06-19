# lib/validate.sh - config validation for erambox
#
# Maintainer: Cognis Digital
# License: COCL 1.0
#
# Validates a loaded CFG for a given profile. Accumulates errors and returns
# non-zero if any are found.

# Required keys regardless of profile.
ERAMBOX_REQUIRED_BASE=(
  APP_NAME
  APP_IMAGE
  APP_PORT
  DB_IMAGE
  DB_NAME
  DB_USER
  DB_PASSWORD
  PROXY_IMAGE
  PROXY_HTTP_PORT
)

# validate_run PROFILE -- returns 0 if valid, 1 otherwise. Prints findings.
validate_run() {
  local profile="$1"
  local errors=0
  local key

  if [ "$profile" != "dev" ] && [ "$profile" != "prod" ]; then
    err "invalid profile '$profile' (expected dev or prod)"
    errors=$((errors + 1))
  fi

  # --- required base vars -------------------------------------------------
  for key in "${ERAMBOX_REQUIRED_BASE[@]}"; do
    if [ -z "$(config_get "$key" "")" ]; then
      err "missing required config var: $key"
      errors=$((errors + 1))
    fi
  done

  # --- port sanity --------------------------------------------------------
  local app_port db_port proxy_http proxy_https
  app_port="$(config_get APP_PORT "")"
  db_port="$(config_get DB_PORT "")"
  proxy_http="$(config_get PROXY_HTTP_PORT "")"
  proxy_https="$(config_get PROXY_HTTPS_PORT "")"

  local p
  for p in "APP_PORT:$app_port" "PROXY_HTTP_PORT:$proxy_http"; do
    local pname="${p%%:*}" pval="${p#*:}"
    if [ -n "$pval" ] && ! is_port "$pval"; then
      err "$pname is not a valid TCP port: $pval"
      errors=$((errors + 1))
    fi
  done
  if [ -n "$db_port" ] && ! is_port "$db_port"; then
    err "DB_PORT is not a valid TCP port: $db_port"
    errors=$((errors + 1))
  fi
  if [ -n "$proxy_https" ] && ! is_port "$proxy_https"; then
    err "PROXY_HTTPS_PORT is not a valid TCP port: $proxy_https"
    errors=$((errors + 1))
  fi

  # --- host-published port conflicts -------------------------------------
  # Collect only the ports actually published on the host and look for dupes.
  declare -A seen=()
  local entry name val
  for entry in \
      "APP_PORT:$app_port" \
      "DB_PORT:$db_port" \
      "PROXY_HTTP_PORT:$proxy_http" \
      "PROXY_HTTPS_PORT:$proxy_https"; do
    name="${entry%%:*}"
    val="${entry#*:}"
    [ -n "$val" ] || continue
    is_port "$val" || continue
    if [ -n "${seen[$val]+set}" ]; then
      err "port conflict on $val: ${seen[$val]} and $name both publish it"
      errors=$((errors + 1))
    else
      seen[$val]="$name"
    fi
  done

  # --- prod-specific hardening rules -------------------------------------
  if [ "$profile" = "prod" ]; then
    if ! is_truthy "$(config_get TLS_ENABLED "")"; then
      err "prod profile requires TLS_ENABLED=true"
      errors=$((errors + 1))
    else
      if [ -z "$(config_get TLS_CERT_PATH "")" ]; then
        err "prod profile with TLS requires TLS_CERT_PATH"
        errors=$((errors + 1))
      fi
      if [ -z "$(config_get TLS_KEY_PATH "")" ]; then
        err "prod profile with TLS requires TLS_KEY_PATH"
        errors=$((errors + 1))
      fi
      if [ -z "$(config_get PROXY_HTTPS_PORT "")" ]; then
        err "prod profile with TLS requires PROXY_HTTPS_PORT"
        errors=$((errors + 1))
      fi
    fi
    if [ -z "$(config_get APP_SECRET_KEY "")" ]; then
      err "prod profile requires APP_SECRET_KEY"
      errors=$((errors + 1))
    fi
    local host
    host="$(config_get PUBLIC_HOSTNAME "")"
    if [ -z "$host" ] || [ "$host" = "localhost" ]; then
      err "prod profile requires a non-localhost PUBLIC_HOSTNAME"
      errors=$((errors + 1))
    fi
    # weak-default password guard for prod
    case "$(config_get DB_PASSWORD "")" in
      ''|grc|password|changeme|postgres)
        err "prod profile requires a strong, non-default DB_PASSWORD"
        errors=$((errors + 1))
        ;;
    esac
  fi

  # --- unknown-key warnings (non-fatal) ----------------------------------
  local k known
  for k in "${!CFG[@]}"; do
    known=0
    for key in "${ERAMBOX_KNOWN_KEYS[@]}"; do
      [ "$k" = "$key" ] && { known=1; break; }
    done
    [ "$known" -eq 0 ] && warn "unknown config key (ignored by generator): $k"
  done

  if [ "$errors" -gt 0 ]; then
    err "validation failed with $errors error(s)"
    return 1
  fi
  log "validation passed for profile '$profile'"
  return 0
}

# cmd_validate -- CLI entrypoint.
cmd_validate() {
  local config="" profile=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --config)  require_value "$1" "${2-}"; config="$2"; shift 2 ;;
      --profile) require_value "$1" "${2-}"; profile="$2"; shift 2 ;;
      --help|-h) usage; return 0 ;;
      *) die "validate: unknown option '$1'" ;;
    esac
  done

  config_load "$config"
  config_apply_defaults
  [ -n "$profile" ] || profile="$(config_effective_profile dev)"

  validate_run "$profile"
}
