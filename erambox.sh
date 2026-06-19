#!/usr/bin/env bash
#
# erambox - deployment scaffolder + config-as-code for a generic
#           self-hosted GRC (Governance / Risk / Compliance) web stack.
#
# Maintainer: Cognis Digital
# License: COCL 1.0
#
# Clean-room original. Generates a reproducible docker-compose.yml plus
# app / db / proxy config files (dev vs prod profiles) from a small env
# config, validates that config, and probes health endpoints.
#
set -euo pipefail

# --------------------------------------------------------------------------
# Locate our own directory so lib/ resolves regardless of CWD / symlinks.
# --------------------------------------------------------------------------
ERAMBOX_SELF="${BASH_SOURCE[0]}"
while [ -h "$ERAMBOX_SELF" ]; do
  _dir="$(cd -P "$(dirname "$ERAMBOX_SELF")" >/dev/null 2>&1 && pwd)"
  ERAMBOX_SELF="$(readlink "$ERAMBOX_SELF")"
  [[ $ERAMBOX_SELF != /* ]] && ERAMBOX_SELF="$_dir/$ERAMBOX_SELF"
done
ERAMBOX_DIR="$(cd -P "$(dirname "$ERAMBOX_SELF")" >/dev/null 2>&1 && pwd)"
ERAMBOX_LIB="$ERAMBOX_DIR/lib"

# shellcheck source=lib/common.sh
. "$ERAMBOX_LIB/common.sh"
# shellcheck source=lib/config.sh
. "$ERAMBOX_LIB/config.sh"
# shellcheck source=lib/template.sh
. "$ERAMBOX_LIB/template.sh"
# shellcheck source=lib/validate.sh
. "$ERAMBOX_LIB/validate.sh"
# shellcheck source=lib/generate.sh
. "$ERAMBOX_LIB/generate.sh"
# shellcheck source=lib/healthcheck.sh
. "$ERAMBOX_LIB/healthcheck.sh"

usage() {
  cat <<'EOF'
erambox - generic self-hosted GRC stack scaffolder (Cognis Digital)

USAGE:
  erambox.sh <command> [options]

COMMANDS:
  generate     Render docker-compose.yml + app/db/proxy configs from a config
  validate     Check a config for required vars, port conflicts, prod TLS rules
  healthcheck  Probe (or list, with --dry-run) the stack's health endpoints
  help         Show this help

GENERATE:
  erambox.sh generate --config <file> --profile dev|prod --out <dir>
      --config <file>     Path to an env-style config (see examples/grc.env)
      --profile dev|prod  Deployment profile (default: dev)
      --out <dir>         Output directory for generated artifacts (default: ./out)
      --force             Overwrite an existing non-empty output directory

VALIDATE:
  erambox.sh validate --config <file> [--profile dev|prod]
      Exits non-zero if any error is found. --profile defaults to the
      config's ERAMBOX_PROFILE, else dev.

HEALTHCHECK:
  erambox.sh healthcheck --config <file> [--dry-run] [--profile dev|prod]
      --dry-run           Print the target URLs without making network calls

GLOBAL:
  --help, -h              Show this help

EXAMPLES:
  erambox.sh generate --config examples/grc.env --profile dev --out ./out
  erambox.sh validate --config examples/grc-prod.env
  erambox.sh healthcheck --config examples/grc.env --dry-run

License: COCL 1.0
EOF
}

main() {
  if [ "$#" -eq 0 ]; then
    usage
    return 2
  fi

  local cmd="$1"
  shift || true

  case "$cmd" in
    generate)    cmd_generate "$@" ;;
    validate)    cmd_validate "$@" ;;
    healthcheck) cmd_healthcheck "$@" ;;
    help|--help|-h) usage ;;
    *)
      err "unknown command: $cmd"
      usage
      return 2
      ;;
  esac
}

main "$@"
