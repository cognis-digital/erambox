# shellcheck shell=bash
# lib/common.sh - shared helpers for erambox
#
# Maintainer: Cognis Digital
# License: COCL 1.0
#
# Sourced, not executed. No top-level side effects beyond defining functions.

# Colorless, prefix-tagged logging to stderr so stdout stays machine-parseable.
log()  { printf '[erambox] %s\n' "$*" >&2; }
warn() { printf '[erambox][warn] %s\n' "$*" >&2; }
err()  { printf '[erambox][error] %s\n' "$*" >&2; }

die() {
  err "$*"
  exit 1
}

# require_value FLAG VALUE -- ensure a flag that expects an argument got one.
require_value() {
  local flag="$1" val="${2-}"
  if [ -z "$val" ]; then
    die "option $flag requires a value"
  fi
}

# is_truthy VALUE -- normalize common boolean spellings.
is_truthy() {
  case "$(printf '%s' "${1-}" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|on|y) return 0 ;;
    *) return 1 ;;
  esac
}

# trim VALUE -- strip leading/trailing whitespace, echo result.
trim() {
  local s="$1"
  # remove leading whitespace
  s="${s#"${s%%[![:space:]]*}"}"
  # remove trailing whitespace
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# is_port VALUE -- true if VALUE is an integer in 1..65535.
is_port() {
  local v="${1-}"
  [[ "$v" =~ ^[0-9]+$ ]] || return 1
  [ "$v" -ge 1 ] && [ "$v" -le 65535 ]
}

# ensure_outdir DIR FORCE -- create DIR; if non-empty and not FORCE, fail.
ensure_outdir() {
  local dir="$1" force="$2"
  if [ -d "$dir" ] && [ -n "$(ls -A "$dir" 2>/dev/null)" ]; then
    if ! is_truthy "$force"; then
      die "output directory '$dir' is not empty (use --force to overwrite)"
    fi
  fi
  mkdir -p "$dir"
}