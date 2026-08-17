#!/usr/bin/env bash
# Install DevSpace (the local MCP server) and run `devspace init` interactively.
#
# Usage:
#   ./setup.sh            # install with the default npm registry
#   ./setup.sh --mirror   # install via npmmirror (much faster in CN networks)
#
# After this, expose the server with a tunnel and run refresh-devspace-mcp.sh.
set -euo pipefail

USE_MIRROR=0
for a in "$@"; do
  case "$a" in
    --mirror) USE_MIRROR=1 ;;
    -h|--help)
      sed -n '2,9p' "$0"
      exit 0
      ;;
    *) echo "Unknown arg: $a" >&2; exit 1 ;;
  esac
done

echo "==> Checking prerequisites"
for c in node npm git bash ssh; do
  command -v "$c" >/dev/null || { echo "Missing required command: $c" >&2; exit 1; }
done
node -e 'const v=process.versions.node.split(".").map(Number); if(v[0]<22||(v[0]===22&&v[1]<19)||v[0]>=27){process.exit(1)}' \
  || { echo "Node >=22.19 and <27 is required (got $(node -v))." >&2; exit 1; }

if [ "$USE_MIRROR" = 1 ]; then
  echo "==> Using npmmirror registry"
  npm config set registry https://registry.npmmirror.com
fi

echo "==> Installing @waishnav/devspace globally"
npm install -g @waishnav/devspace

echo "==> Running 'devspace init' (interactive)"
echo "    - Project directory : the local dir you want ChatGPT/Codex to access"
echo "                         (e.g. /home/lijian/project/open-vela)"
echo "    - Port              : 7676"
echo "    - Public base URL   : the ORIGIN of your tunnel, WITHOUT /mcp"
echo "                         (you may type anything now; refresh-devspace-mcp.sh"
echo "                          rewrites config.json's publicBaseUrl on first run)"
devspace init

echo
echo "==> Done. Next steps:"
echo "    1. Start a tunnel, e.g.:"
echo "         ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \\"
echo "             -p 443 -R0:localhost:7676 a.pinggy.io"
echo "    2. Run the refresher (it captures the URL, updates configs, starts serve):"
echo "         ./refresh-devspace-mcp.sh --tunnel-cmd \"ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 443 -R0:localhost:7676 a.pinggy.io\""
echo "    3. Authorize your client:"
echo "         codex mcp login devspace   # then enter the Owner password"
