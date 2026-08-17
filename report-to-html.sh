#!/usr/bin/env bash
# report-to-html.sh — Render a (filled) review report Markdown file to HTML.
#
# Prefers `pandoc` when installed (best fidelity). Otherwise falls back to a
# small built-in Markdown->HTML converter that covers the structures our
# review templates use: #/##/### headings, Markdown tables, "- " lists,
# **bold** and `code` spans, plus <>& escaping. No network / no extra deps.
set -euo pipefail

IN_FILE=""
OUT_FILE=""

usage() {
  cat <<'EOF'
Usage:
  ./report-to-html.sh --in REPORT.md [--out REPORT.html]

Options:
  --in FILE   Input Markdown report (required)
  --out FILE  Output HTML file (default: <input>.html)
  --help      Show this message
EOF
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --in)  IN_FILE="${2-}"; shift 2 ;;
    --out) OUT_FILE="${2-}"; shift 2 ;;
    --help) usage 0 ;;
    *) echo "Unknown arg: $1" >&2; usage 1 ;;
  esac
done

[[ -n "$IN_FILE" ]] || usage 1
[[ -f "$IN_FILE" ]] || { echo "Input not found: $IN_FILE" >&2; exit 1; }
[[ -n "$OUT_FILE" ]] || OUT_FILE="${IN_FILE%.md}.html"

# --- Fast path: pandoc if present -----------------------------------------
if command -v pandoc >/dev/null 2>&1; then
  pandoc -f gfm -t html \
    --metadata title="代码审查报告" \
    --standalone \
    "$IN_FILE" -o "$OUT_FILE"
  echo "Rendered (pandoc) -> $OUT_FILE"
  exit 0
fi

# --- Fallback: minimal built-in converter ---------------------------------
esc() {
  local s="$1"
  s="${s//&/&amp;}"
  s="${s//</&lt;}"
  s="${s//>/&gt;}"
  printf '%s' "$s"
}

# inline: **bold** -> <strong>, `code` -> <code>
# NOTE: the caller already HTML-escapes the text, so we must NOT re-escape here.
inline() {
  local s="$1"
  # bold: toggle ** -> <strong> / </strong> one pair at a time
  while [[ "$s" == *"**"*"**"* ]]; do
    s="${s/\*\*/<strong>}"
    s="${s/\*\*/</strong>}"
  done
  # backtick code spans (content already escaped by caller)
  while [[ "$s" == *\`*\`* ]]; do
    local pre="${s%%\`*}"
    local rest="${s#*\`}"
    local code="${rest%%\`*}"
    rest="${rest#*\`}"
    s="$pre<code>$code</code>$rest"
  done
  printf '%s' "$s"
}

{
  echo '<!DOCTYPE html>'
  echo '<html lang="zh"><head><meta charset="utf-8">'
  echo '<title>代码审查报告</title>'
  echo '<style>'
  echo 'body{font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;max-width:900px;margin:2rem auto;padding:0 1rem;line-height:1.6;color:#1a1a1a}'
  echo 'h1{border-bottom:2px solid #ddd;padding-bottom:.3em}h2{border-bottom:1px solid #eee;padding-bottom:.2em;margin-top:2em}'
  echo 'table{border-collapse:collapse;width:100%;margin:1em 0}th,td{border:1px solid #ddd;padding:.5em .7em;text-align:left;vertical-align:top}'
  echo 'th{background:#f6f8fa}code{background:#f0f0f0;padding:.1em .3em;border-radius:3px;font-family:ui-monospace,Menlo,Consolas,monospace}'
  echo 'ul{margin:.5em 0}.muted{color:#777}'
  echo '</style></head><body>'
} > "$OUT_FILE"

# State machine over the input lines.
in_table=0
in_list=0
while IFS= read -r line || [[ -n "$line" ]]; do
  # Table handling
  if [[ "$line" == \|* ]]; then
    if [[ "$in_list" -eq 1 ]]; then echo '</ul>'; in_list=0; fi
    if [[ "$line" =~ ^\|[[:space:]]*-+ ]]; then
      continue  # separator row
    fi
    if [[ "$in_table" -eq 0 ]]; then
      echo '<table>'
      in_table=1
      echo '<thead>'
    fi
    # split by |
    IFS='|' read -ra cells <<< "$line"
    row_html=''
    first=1
    for c in "${cells[@]}"; do
      [[ "$first" -eq 1 ]] && { first=0; continue; }  # leading empty field
      ct="$(echo "$c" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      [[ -z "$ct" ]] && continue
      if [[ "$in_table" -eq 1 && "$row_html" == "" && "$line" == *"编号"* ]]; then
        # header row detection (very light): treat first table block as header
        :
      fi
      row_html="$row_html<td>$(inline "$(esc "$ct")")</td>"
    done
    if [[ "$row_html" != "" ]]; then
      if [[ "$line" == *"编号"* || "$line" == *"严重度"* ]]; then
        echo '<tr>'"$row_html"'</tr>'
        echo '</thead><tbody>'
      else
        echo '<tr>'"$row_html"'</tr>'
      fi
    fi
    continue
  else
    if [[ "$in_table" -eq 1 ]]; then echo '</tbody></table>'; in_table=0; fi
  fi

  # List handling
  if [[ "$line" == "-"* && "$line" != "--"* ]]; then
    item="$(echo "$line" | sed -e 's/^[[:space:]]*-[[:space:]]*//')"
    if [[ "$in_list" -eq 0 ]]; then echo '<ul>'; in_list=1; fi
    echo '<li>'$(inline "$(esc "$item")")'</li>'
    continue
  else
    if [[ "$in_list" -eq 1 ]]; then echo '</ul>'; in_list=0; fi
  fi

  # Headings
  if [[ "$line" == '### '* ]]; then
    echo '<h3>'$(inline "$(esc "${line#"### "}")")'</h3>'; continue
  fi
  if [[ "$line" == '## '* ]]; then
    echo '<h2>'$(inline "$(esc "${line#"## "}")")'</h2>'; continue
  fi
  if [[ "$line" == '# '* ]]; then
    echo '<h1>'$(inline "$(esc "${line#"# "}")")'</h1>'; continue
  fi

  # Blank line
  if [[ -z "$line" ]]; then continue; fi

  # Paragraph (escape & inline)
  echo '<p>'$(inline "$(esc "$line")")'</p>'
done < "$IN_FILE" >> "$OUT_FILE"

# Close any open blocks
if [[ "$in_table" -eq 1 ]]; then echo '</tbody></table>' >> "$OUT_FILE"; fi
if [[ "$in_list" -eq 1 ]]; then echo '</ul>' >> "$OUT_FILE"; fi
echo '</body></html>' >> "$OUT_FILE"

echo "Rendered (built-in) -> $OUT_FILE"
