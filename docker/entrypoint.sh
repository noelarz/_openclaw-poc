#!/usr/bin/env bash
set -euo pipefail

CONFIG="$HOME/.openclaw/openclaw.json"

# Clean up stale Chromium lock files
find "$HOME/.openclaw" -name "SingletonLock" -delete 2>/dev/null || true

# Write config if not already present (volume mount takes precedence)
if [ ! -f "$CONFIG" ]; then
  cat > "$CONFIG" <<EOF
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "${OPENCLAW_MODEL:-amazon-bedrock/us.anthropic.claude-sonnet-4-20250514-v1:0}"
      }
    }
  },
  "gateway": {
    "port": 18789,
    "mode": "local",
    "bind": "loopback",
    "auth": {
      "mode": "token",
      "token": "${OPENCLAW_GATEWAY_TOKEN}"
    }
  }
}
EOF
  chmod 600 "$CONFIG"
fi

exec openclaw gateway
