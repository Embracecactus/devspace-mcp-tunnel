#!/usr/bin/env bash
# review.sh — Scaffold a STATIC code-review report (read-only).
#
# It lists the source files under a path and writes a Markdown report skeleton
# containing an empty issue table and a checklist. It NEVER edits source code,
# so it is safe to run inside the workspace that DevSpace exposes to a remote AI:
# the AI (ChatGPT/Codex) can call this script over the DevSpace shell, then fill
# in findings manually — i.e. "pure static review + issue list", no CI fixes.
set -euo pipefail

REVIEW_PATH="."
NAME_GLOB="*"
OUT_FILE="review-report.md"
SUMMARIZE_FILE=""
SUMMARIZE_OUT=""
# Directories to skip when scanning (common build/dependency junk).
SKIP_DIRS=".git node_modules build dist out target .next .venv"

usage() {
  cat <<'EOF'
Usage:
  ./review.sh [--path DIR] [--glob PATTERN] [--out FILE] [--help]
  ./review.sh --summarize REPORT [--summarize-out FILE]

Options:
  --path DIR        Directory to scan (default: current directory)
  --glob PATTERN    File name pattern passed to `find -name` (default: *)
  --out FILE        Output Markdown file (default: review-report.md)
  --summarize REPORT  Parse a filled review report and print severity/type stats
  --summarize-out F    With --summarize, also write the summary block to file F
  --help            Show this message

Read-only: this script only READS files and writes the report. It never
modifies source code, so it is safe to run over the DevSpace-exposed shell.
EOF
  exit "${1:-0}"
}

# Tally a filled-in review report by severity (col 3) and type (col 4),
# and print a "## 统计汇总" block. Pure read; optionally writes to a file.
summarize_report() {
  local f="$1" out="${2:-}"
  [[ -f "$f" ]] || { echo "Report not found: $f" >&2; exit 1; }
  local stats
  stats="$(awk -F'|' '
    function trim(s){ gsub(/^[ \t]+|[ \t]+$/,"",s); return s }
    /^[ \t]*\|/ {
      if ($0 ~ /\|[ \t]*-+/) next          # skip the | --- | separator row
      sev = trim($4); typ = trim($5)
      if (sev == "严重度" || sev == "") next  # skip header / blank rows
      sevcount[sev]++; typcount[typ]++; total++
    }
    END {
      printf "## 统计汇总\n\n"
      printf "- 总计问题数：**%d**\n", total
      printf "\n### 按严重度\n\n"
      for (s in sevcount) printf "- %s：%d\n", s, sevcount[s]
      printf "\n### 按类型\n\n"
      for (t in typcount) printf "- %s：%d\n", t, typcount[t]
    }
  ' "$f")"
  printf '%s\n' "$stats"
  if [[ -n "$out" ]]; then
    printf '%s\n' "$stats" > "$out"
    echo "Summary written to: $out"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --path) REVIEW_PATH="${2-}"; shift 2 ;;
    --glob) NAME_GLOB="${2-}"; shift 2 ;;
    --out)  OUT_FILE="${2-}"; shift 2 ;;
    --summarize)     SUMMARIZE_FILE="${2-}"; shift 2 ;;
    --summarize-out) SUMMARIZE_OUT="${2-}"; shift 2 ;;
    --help) usage 0 ;;
    *) echo "Unknown arg: $1" >&2; usage 1 ;;
  esac
done

# --summarize mode: tally an existing report and exit (no scaffolding).
if [[ -n "$SUMMARIZE_FILE" ]]; then
  summarize_report "$SUMMARIZE_FILE" "$SUMMARIZE_OUT"
  exit 0
fi

[[ -d "$REVIEW_PATH" ]] || { echo "Not a directory: $REVIEW_PATH" >&2; exit 1; }

# Build the find prune list for skipped dirs, then append the real match action.
FIND_EXPR=()
for d in $SKIP_DIRS; do
  FIND_EXPR+=( -name "$d" -prune -o )
done
FIND_EXPR+=( -type f -name "$NAME_GLOB" -print )

# Collect matching files (relative paths), excluding skipped dirs.
mapfile -t FILES < <(find "$REVIEW_PATH" "${FIND_EXPR[@]}" | sort)

{
  echo "# 静态代码审查报告"
  echo
  echo "- 生成时间：$(date '+%Y-%m-%d %H:%M:%S %z')"
  echo "- 审查范围：\`$REVIEW_PATH\`（文件名模式：\`$NAME_GLOB\`）"
  echo "- 文件总数：${#FILES[@]}"
  echo
  echo "## 审查原则"
  echo
  echo "- 纯静态人工审查，**不修改任何源码**，不参与 CI 修复。"
  echo "- 借助 shell + 文件读取能力逐项核对（等价 codegraph + shell 的组合）。"
  echo "- 仅产出问题清单与报告，由人工决定是否采纳与修复。"
  echo
  echo "## 待审查文件清单"
  echo
  if [[ ${#FILES[@]} -eq 0 ]]; then
    echo "_（未匹配到文件）_"
  else
    for f in "${FILES[@]}"; do echo "- \`$f\`"; done
  fi
  echo
  echo "## 问题清单"
  echo
  echo "| 编号 | 文件:行号 | 严重度 | 类型 | 描述 | 建议 |"
  echo "| --- | --- | --- | --- | --- | --- |"
  echo
  echo "## 总结"
  echo
  echo "_（由审查者填写：整体质量、主要风险、建议优先级）_"
} > "$OUT_FILE"

echo "Report skeleton written to: $OUT_FILE (${#FILES[@]} files listed)"
