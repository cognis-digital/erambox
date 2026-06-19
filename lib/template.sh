# lib/template.sh - pure-bash templating for erambox
#
# Maintainer: Cognis Digital
# License: COCL 1.0
#
# No envsubst / sed dependency. Substitutes {{KEY}} placeholders using a
# provided associative array of values. Unknown placeholders are left as-is
# but reported via stderr so template authors notice typos.

# tpl_render TEMPLATE_TEXT ASSOC_ARRAY_NAME
#   Echos the rendered template. Values are taken from the named associative
#   array. Placeholders use the {{KEY}} form.
tpl_render() {
  local text="$1"
  local -n _vals="$2"   # nameref to caller's associative array
  local out="" rest="$text"
  local before token key

  while [[ "$rest" == *'{{'* ]]; do
    before="${rest%%'{{'*}"
    out+="$before"
    rest="${rest#*'{{'}"
    if [[ "$rest" != *'}}'* ]]; then
      # unterminated placeholder; emit literally and stop scanning
      out+='{{'
      break
    fi
    token="${rest%%'}}'*}"
    rest="${rest#*'}}'}"
    key="$(trim "$token")"
    if [ -n "${_vals[$key]+set}" ]; then
      out+="${_vals[$key]}"
    else
      warn "template placeholder {{$key}} has no value; left literal"
      out+="{{$key}}"
    fi
  done
  out+="$rest"
  printf '%s' "$out"
}

# tpl_render_file TEMPLATE_TEXT ASSOC_ARRAY_NAME DEST_PATH
#   Render and write to DEST_PATH (parent dirs created).
tpl_render_file() {
  local text="$1" arr="$2" dest="$3"
  mkdir -p "$(dirname "$dest")"
  tpl_render "$text" "$arr" > "$dest"
}
