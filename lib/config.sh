# shellcheck shell=bash
# lib/config.sh - config loading for erambox
#
# Maintainer: Cognis Digital
# License: COCL 1.0
#
# Parses an env-style config file into the associative array CFG. Lines look
# like KEY=value. Blank lines and lines starting with '#' are ignored.
# Inline values may be quoted with single or double quotes. We do NOT source
# the file (no code execution) -- it is parsed line by line.

declare -gA CFG

# Recognized keys (with defaults applied where sensible). Anything else in the
# file is preserved but flagged as unknown by validate.
ERAMBOX_KNOWN_KEYS=(
  ERAMBOX_PROFILE
  APP_NAME
  APP_IMAGE
  APP_PORT
  APP_INTERNAL_PORT
  APP_SECRET_KEY
  DB_IMAGE
  DB_NAME
  DB_USER
  DB_PASSWORD
  DB_PORT
  PROXY_IMAGE
  PROXY_HTTP_PORT
  PROXY_HTTPS_PORT
  TLS_ENABLED
  TLS_CERT_PATH
  TLS_KEY_PATH
  PUBLIC_HOSTNAME
  HEALTH_PATH
)

# config_strip_quotes VALUE -- remove one matching pair of surrounding quotes.
config_strip_quotes() {
  local v="$1"
  if [ "${#v}" -ge 2 ]; then
    local first="${v:0:1}" last="${v: -1}"
    if { [ "$first" = '"' ] && [ "$last" = '"' ]; } || \
       { [ "$first" = "'" ] && [ "$last" = "'" ]; }; then
      v="${v:1:${#v}-2}"
    fi
  fi
  printf '%s' "$v"
}

# config_load FILE -- populate CFG from FILE. Dies if the file is missing.
config_load() {
  local file="$1"
  [ -n "$file" ] || die "no config file given (use --config <file>)"
  [ -f "$file" ] || die "config file not found: $file"

  CFG=()
  local line key val lineno=0
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    # strip a trailing CR (Windows-authored files)
    line="${line%$'\r'}"
    # skip blanks and comments
    case "$(trim "$line")" in
      ''|'#'*) continue ;;
    esac
    # allow an optional leading "export "
    line="${line#export }"
    if [[ "$line" != *=* ]]; then
      warn "config line $lineno ignored (no '='): $line"
      continue
    fi
    key="${line%%=*}"
    val="${line#*=}"
    key="$(trim "$key")"
    val="$(trim "$val")"
    # Strip a trailing inline comment ( <space># ... ) only when the value is
    # NOT quoted. Quoted values keep '#' literally.
    case "$val" in
      \"*\"|\'*\') : ;;  # fully quoted: leave intact, quotes removed below
      *)
        # remove from the first " #" or tab-# onward
        if [[ "$val" == *" #"* ]]; then
          val="${val%%" #"*}"
          val="$(trim "$val")"
        fi
        if [[ "$val" == *$'\t#'* ]]; then
          val="${val%%$'\t#'*}"
          val="$(trim "$val")"
        fi
        ;;
    esac
    val="$(config_strip_quotes "$val")"
    if [[ ! "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      warn "config line $lineno ignored (invalid key): $key"
      continue
    fi
    CFG["$key"]="$val"
  done < "$file"
}

# config_get KEY [DEFAULT] -- echo CFG[KEY] or DEFAULT.
config_get() {
  local key="$1" def="${2-}"
  if [ -n "${CFG[$key]+set}" ]; then
    printf '%s' "${CFG[$key]}"
  else
    printf '%s' "$def"
  fi
}

# config_apply_defaults -- fill in defaults for optional keys.
config_apply_defaults() {
  : "${CFG[ERAMBOX_PROFILE]:=dev}"
  : "${CFG[APP_NAME]:=grcapp}"
  : "${CFG[APP_IMAGE]:=grc/webapp:latest}"
  : "${CFG[APP_INTERNAL_PORT]:=8080}"
  : "${CFG[DB_IMAGE]:=postgres:16-alpine}"
  : "${CFG[DB_NAME]:=grc}"
  : "${CFG[DB_USER]:=grc}"
  : "${CFG[PROXY_IMAGE]:=nginx:1.27-alpine}"
  : "${CFG[HEALTH_PATH]:=/health}"
  : "${CFG[PUBLIC_HOSTNAME]:=localhost}"
}

# config_effective_profile FALLBACK -- resolve profile from CFG or fallback.
config_effective_profile() {
  local fallback="${1:-dev}"
  local p
  p="$(config_get ERAMBOX_PROFILE "$fallback")"
  printf '%s' "$p"
}