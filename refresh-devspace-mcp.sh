#!/usr/bin/env bash
set -euo pipefail

# Ensure devspace + node are reachable. The binary often lives in a pi-node / npm
# global prefix whose bin dir is only injected into interactive shells (e.g. via a
# CodeBuddy shell snapshot) and is NOT inherited by non-interactive subshells.
# Prepend any directory that actually contains the `devspace` binary to PATH.
for _d in "$HOME/.local/share/pi-node"/*/bin /usr/local/bin; do
  if [ -e "$_d/devspace" ]; then
    export PATH="$_d:$PATH"
    # Self-heal: npm sometimes installs the bin symlink target without the
    # execute bit, which makes `devspace` fail with "Permission denied".
    _cli="$(readlink -f "$_d/devspace" 2>/dev/null || echo "$_d/devspace")"
    [ -n "$_cli" ] && chmod +x "$_cli" 2>/dev/null || true
    break
  fi
done
unset _d _cli

usage() {
  cat <<'EOF'
Usage:
  ./refresh-devspace-mcp.sh --tunnel-cmd "<command>" [options]
  ./refresh-devspace-mcp.sh --known-url "https://host/mcp" [options]

Options:
  --tunnel-cmd CMD        Shell command to start the tunnel (required unless --known-url)
  --known-url URL         Skip tunnel start/extract; use this URL directly (must end with /mcp).
                          Use this when you run your own tunnel (ngrok, cloudflared, bore, ...).
  --url-regex REGEX       Regex used to extract the tunnel URL from the tunnel output.
                          Default matches Pinggy: https://[^[:space:]]*\.free\.pinggy\.net[^[:space:]]*
  --devspace-cmd CMD      Command to start devspace serve (default: devspace serve)
  --stop-cmd CMD          Command to stop old devspace process (default: pkill -f 'devspace serve')
  --stop-tunnel-cmd CMD   Command to stop old tunnel (default: kill tmux 'pinggy' session + PID from $HOME/.devspace/tunnel.pid)
  --workspace PATH         Workspace root (default: script directory)
  --mcp-json PATH         MCP config file (default: <workspace>/.mcp.json)
  --devspace-config PATH   Devspace config (default: ~/.devspace/config.json)
  --codex-config PATH     Codex CLI config to keep in sync (default: ~/.codex/config.toml)
  --timeout SECONDS       Seconds to wait for tunnel URL (default: 90)
  --help                  Show this message

Examples:
  # Pinggy (default)
  ./refresh-devspace-mcp.sh \
    --tunnel-cmd "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 443 -R0:localhost:7676 a.pinggy.io"

  # Any other tunnel: let the script capture the URL
  ./refresh-devspace-mcp.sh \
    --tunnel-cmd "ngrok http 7676" \
    --url-regex 'https://[a-z0-9-]+\.ngrok-free\.app'

  # Any other tunnel: you already know the URL, skip tunnel management
  ./refresh-devspace-mcp.sh \
    --known-url "https://abc-def.ngrok-free.app/mcp"
EOF
  exit "${1:-0}"
}

DEVSERVE_CMD="devspace serve"
# Kill both invocation forms: the script starts it as `node .../dist/cli.js serve`
# (argv contains "cli.js serve"), while a manual `devspace serve` has "devspace serve".
STOP_CMD="pkill -f 'cli.js serve' 2>/dev/null || true; pkill -f 'devspace serve' 2>/dev/null || true"
TUNNEL_PIDFILE="$HOME/.devspace/tunnel.pid"
# Safe cleanup: kill the tmux 'pinggy' session and the previously recorded tunnel
# PID (plus its children). Deliberately avoids `pkill -f <pattern>` because the
# script's own argv contains the tunnel command and would match/kill itself.
STOP_TUNNEL_CMD="tmux kill-session -t pinggy 2>/dev/null || true; if [ -f $TUNNEL_PIDFILE ]; then p=\$(cat $TUNNEL_PIDFILE); pkill -P \"\$p\" 2>/dev/null || true; kill \"\$p\" 2>/dev/null || true; rm -f $TUNNEL_PIDFILE; fi"
WORKSPACE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MCP_JSON="$WORKSPACE/.mcp.json"
DEVS_CONFIG="$HOME/.devspace/config.json"
CODEX_CONFIG="$HOME/.codex/config.toml"
TIMEOUT=90
TUNNEL_CMD=""
# Regex used to capture the tunnel URL from the tunnel process output.
# Default matches Pinggy's free tunnel hosts; override with --url-regex.
URL_REGEX='https://[^[:space:]]*\.free\.pinggy\.net[^[:space:]]*'
# When set, tunnel start/extract is skipped and this URL is used as-is.
KNOWN_URL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tunnel-cmd)
      TUNNEL_CMD="${2-}"
      shift 2
      ;;
    --devspace-cmd)
      DEVSERVE_CMD="${2-}"
      shift 2
      ;;
    --stop-cmd)
      STOP_CMD="${2-}"
      shift 2
      ;;
    --stop-tunnel-cmd)
      STOP_TUNNEL_CMD="${2-}"
      shift 2
      ;;
    --workspace)
      WORKSPACE="${2-}"
      MCP_JSON="${WORKSPACE}/.mcp.json"
      shift 2
      ;;
    --mcp-json)
      MCP_JSON="${2-}"
      shift 2
      ;;
    --devspace-config)
      DEVS_CONFIG="${2-}"
      shift 2
      ;;
    --codex-config)
      CODEX_CONFIG="${2-}"
      shift 2
      ;;
    --timeout)
      TIMEOUT="${2-}"
      shift 2
      ;;
    --url-regex)
      URL_REGEX="${2-}"
      shift 2
      ;;
    --known-url)
      KNOWN_URL="${2-}"
      shift 2
      ;;
    --help)
      usage 0
      ;;
    *)
      usage
      ;;
  esac
done

if [[ -z "$TUNNEL_CMD" && -z "$KNOWN_URL" ]]; then
  usage
fi

command -v jq >/dev/null || { echo "jq is required but not installed."; exit 1; }

if [[ ! -f "$MCP_JSON" ]]; then
  echo "MCP config not found: $MCP_JSON"
  exit 1
fi

if [[ ! -f "$DEVS_CONFIG" ]]; then
  echo "Devspace config not found: $DEVS_CONFIG"
  exit 1
fi

LOG_FILE="$(mktemp)"
cleanup() {
  rm -f "$LOG_FILE"
}
trap cleanup EXIT

# Capture the tunnel URL from the tunnel process output using URL_REGEX.
extract_url() {
  local u
  u="$(grep -Eo "$URL_REGEX" "$LOG_FILE" | tail -n 1 || true)"
  [[ -z "$u" ]] && return 1
  if [[ "$u" != */mcp ]]; then
    u="${u%/}/mcp"
  fi
  printf '%s\n' "$u"
}

if [[ -n "$KNOWN_URL" ]]; then
  # User supplies the tunnel URL directly (their own tunnel already running).
  # Skip all tunnel start/stop/extract logic.
  NEW_URL="$KNOWN_URL"
  [[ "$NEW_URL" != */mcp ]] && NEW_URL="${NEW_URL%/}/mcp"
  echo "[0/4] using --known-url (no tunnel management)"
else
  echo "[0/4] stop old tunnel (if any)"
  eval "$STOP_TUNNEL_CMD" || true

  echo "[1/4] start tunnel in background"
  # setsid detaches into a new session so the tunnel survives the parent shell /
  # terminal exit (avoids SIGHUP). PATH is already patched above so the tunnel
  # command (often an `ssh ...`) resolves.
  setsid bash -lc "$TUNNEL_CMD" >"$LOG_FILE" 2>&1 &
  TUNNEL_PID=$!
  disown "$TUNNEL_PID"
  echo "$TUNNEL_PID" > "$TUNNEL_PIDFILE"

  NEW_URL=""
  for ((i = 1; i <= TIMEOUT; i++)); do
    sleep 1
    if u="$(extract_url)"; then
      NEW_URL="$u"
      break
    fi
  done

  if [[ -z "$NEW_URL" ]]; then
    echo "Failed to capture the tunnel URL in $TIMEOUT seconds."
    echo "--- tunnel log tail ---"
    tail -n 40 "$LOG_FILE"
    exit 1
  fi
fi

echo "[2/4] update MCP config -> $MCP_JSON"
jq --arg url "$NEW_URL" '.mcpServers.devspace.url = $url' "$MCP_JSON" >"${MCP_JSON}.tmp"
mv "${MCP_JSON}.tmp" "$MCP_JSON"

echo "[3/4] update devspace config -> $DEVS_CONFIG"
# IMPORTANT: devspace derives the OAuth issuer from publicBaseUrl, and MCP clients
# connect to publicBaseUrl + "/mcp". So publicBaseUrl must be the ORIGIN (no /mcp);
# only the client URLs (.mcp.json, codex) carry the trailing /mcp.
BASE_URL="${NEW_URL%/mcp}"
jq --arg url "$BASE_URL" '.publicBaseUrl = $url' "$DEVS_CONFIG" >"${DEVS_CONFIG}.tmp"
mv "${DEVS_CONFIG}.tmp" "$DEVS_CONFIG"

# Keep Codex CLI's MCP config pointing at the fresh URL, if present.
update_codex_config() {
  local f="$1" url="$2"
  [ -f "$f" ] || return 0
  if grep -q '^\[mcp_servers\.devspace\]' "$f"; then
    # Operate on the url line immediately following the devspace header. Using
    # `n` (instead of a range up to `[[skills`) keeps this robust even when the
    # devspace block is the last section in the file.
    sed -i '/^\[mcp_servers\.devspace\]/{ n; s#^url = ".*"#url = "'"$url"'"# }' "$f"
  else
    printf '\n[mcp_servers.devspace]\nurl = "%s"\n' "$url" >> "$f"
  fi
}
echo "[3.5/5] update codex config -> $CODEX_CONFIG"
update_codex_config "$CODEX_CONFIG" "$NEW_URL"

echo "[4/4] restart devspace"
eval "$STOP_CMD" || true
# setsid detaches into a new session so the server survives the parent shell /
# terminal exit (avoids SIGHUP). Use `bash -c` (not `eval`, which is a builtin
# setsid cannot exec). PATH is already patched above so `devspace` resolves.
( setsid bash -c "$DEVSERVE_CMD" >"$HOME/.devspace/devspace-serve.log" 2>&1 & )

echo "Done."
echo "New URL: $NEW_URL"
if [[ -n "${TUNNEL_PID:-}" ]]; then
  echo "Tunnel PID: $TUNNEL_PID (kept alive)"
fi
