#!/usr/bin/env bash
###############################################################################
# OpenClaw Local Mac Quickstart
# Installs and configures OpenClaw natively on macOS
###############################################################################
set -euo pipefail

echo "========== OpenClaw Local Setup =========="

# 1. Check Node.js >= 22
NODE_VERSION=$(node -v 2>/dev/null | tr -d 'v' | cut -d. -f1 || echo "0")
if [ "$NODE_VERSION" -lt 22 ]; then
  echo "ERROR: Node.js 22+ required. Install via: brew install node@22"
  exit 1
fi
echo "✓ Node.js $(node -v)"

# 2. Install OpenClaw
if ! command -v openclaw &>/dev/null; then
  echo ">>> Installing OpenClaw..."
  npm install -g openclaw
else
  echo "✓ OpenClaw already installed: $(openclaw --version 2>/dev/null)"
fi

# 3. Write config
OPENCLAW_HOME="$HOME/.openclaw"
mkdir -p "$OPENCLAW_HOME"

if [ ! -f "$OPENCLAW_HOME/openclaw.json" ]; then
  echo ">>> Writing config to $OPENCLAW_HOME/openclaw.json"
  cp "$(dirname "$0")/openclaw.json" "$OPENCLAW_HOME/openclaw.json"
  echo "✓ Config written — edit $OPENCLAW_HOME/openclaw.json to set your API key or Bedrock region"
else
  echo "✓ Config already exists at $OPENCLAW_HOME/openclaw.json — skipping"
fi

# 4. Verify
echo ""
echo ">>> Running diagnostics..."
openclaw doctor

echo ""
echo "========== Setup Complete =========="
echo "  Run:       openclaw gateway"
echo "  Dashboard: http://127.0.0.1:18789"
echo "  Onboard:   openclaw onboard"
