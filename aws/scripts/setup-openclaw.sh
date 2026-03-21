#!/usr/bin/env bash
###############################################################################
# setup-openclaw.sh — Post-deploy OpenClaw setup for EC2/Ubuntu 24.04
#
# Run this after SSH'ing into the instance:
#   ssh -i openclaw-key.pem ubuntu@<PUBLIC_IP>
#   bash <(curl -s https://raw.githubusercontent.com/.../setup-openclaw.sh)
# Or copy and run directly:
#   scp -i openclaw-key.pem setup-openclaw.sh ubuntu@<PUBLIC_IP>:~
#   ssh -i openclaw-key.pem ubuntu@<PUBLIC_IP> "bash setup-openclaw.sh"
#
# Requirements:
#   - Ubuntu 24.04 on EC2
#   - IAM role with bedrock:InvokeModel attached
#   - GATEWAY_TOKEN env var set (or passed as arg $1)
###############################################################################
set -euo pipefail

GATEWAY_TOKEN="${1:-${GATEWAY_TOKEN:-}}"
AWS_REGION="${AWS_REGION:-us-east-1}"
OPENCLAW_MODEL="${OPENCLAW_MODEL:-amazon-bedrock/us.anthropic.claude-sonnet-4-20250514-v1:0}"
NODE_MAJOR="${NODE_MAJOR:-22}"
FNM_PATH="/home/ubuntu/.local/share/fnm"

if [ -z "$GATEWAY_TOKEN" ]; then
  echo "ERROR: GATEWAY_TOKEN is required."
  echo "Usage: GATEWAY_TOKEN=<token> bash setup-openclaw.sh"
  echo "   or: bash setup-openclaw.sh <token>"
  exit 1
fi

echo "========== OpenClaw Setup Started: $(date -u) =========="

# -----------------------------------------------------------------------------
# 1. System packages
# -----------------------------------------------------------------------------
echo ">>> Updating system packages..."
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -y || sudo apt-get update -y --allow-releaseinfo-change || true
sudo apt-get install -y curl wget git unzip jq

# -----------------------------------------------------------------------------
# 2. Install Node.js via fnm
# -----------------------------------------------------------------------------
echo ">>> Installing fnm and Node.js ${NODE_MAJOR}..."
if [ ! -f "$FNM_PATH/fnm" ] && [ ! -d "$FNM_PATH" ]; then
  curl -fsSL https://fnm.vercel.app/install | bash
fi

export PATH="$FNM_PATH:$PATH"
eval "$(fnm env --shell bash)"
fnm install "$NODE_MAJOR"
fnm use "$NODE_MAJOR"

NODE_BIN=$(fnm exec --using="$NODE_MAJOR" -- which node | head -1 || true)
NODE_DIR=$(dirname "$NODE_BIN")
echo ">>> Node: $(node --version), npm: $(npm --version)"

# -----------------------------------------------------------------------------
# 3. Install OpenClaw
# -----------------------------------------------------------------------------
echo ">>> Installing OpenClaw..."
npm install -g openclaw
echo ">>> OpenClaw: $(openclaw --version 2>&1 | head -1)"

# -----------------------------------------------------------------------------
# 4. Configure OpenClaw
# -----------------------------------------------------------------------------
echo ">>> Writing OpenClaw config..."
mkdir -p /home/ubuntu/.openclaw

cat > /home/ubuntu/.openclaw/openclaw.json <<EOF
{
  "gateway": {
    "port": 18789,
    "mode": "local",
    "bind": "lan",
    "auth": {
      "token": "${GATEWAY_TOKEN}"
    },
    "controlUi": {
      "dangerouslyAllowHostHeaderOriginFallback": true
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "${OPENCLAW_MODEL}"
      }
    }
  }
}
EOF

openclaw config set gateway.mode local

# -----------------------------------------------------------------------------
# 5. Create gateway startup script (fetches fresh IAM credentials each start)
# -----------------------------------------------------------------------------
echo ">>> Creating gateway startup script..."
cat > /home/ubuntu/start-openclaw.sh <<'STARTSCRIPT'
#!/usr/bin/env bash
# Fetches EC2 IAM role credentials and starts the OpenClaw gateway.
# Re-run this script to restart with fresh credentials (they expire ~6h).

set -euo pipefail

FNM_PATH="/home/ubuntu/.local/share/fnm"
export PATH="$FNM_PATH:$PATH"
eval "$(fnm env --shell bash)" 2>/dev/null || true
fnm use 22 2>/dev/null || true

export AWS_REGION="${AWS_REGION:-us-east-1}"
export HOME=/home/ubuntu

# Fetch credentials from EC2 instance metadata (IMDSv2)
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
ROLE=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/iam/security-credentials/)
CREDS=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  "http://169.254.169.254/latest/meta-data/iam/security-credentials/$ROLE")

export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | python3 -c 'import sys,json; print(json.load(sys.stdin)["AccessKeyId"])')
export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | python3 -c 'import sys,json; print(json.load(sys.stdin)["SecretAccessKey"])')
export AWS_SESSION_TOKEN=$(echo "$CREDS" | python3 -c 'import sys,json; print(json.load(sys.stdin)["Token"])')

echo "[$(date -u)] Starting OpenClaw gateway with IAM role: $ROLE"
exec openclaw gateway --port 18789 --force
STARTSCRIPT

chmod +x /home/ubuntu/start-openclaw.sh

# -----------------------------------------------------------------------------
# 6. Create systemd service
# -----------------------------------------------------------------------------
echo ">>> Creating systemd service..."
sudo tee /etc/systemd/system/openclaw.service > /dev/null <<UNIT
[Unit]
Description=OpenClaw Gateway
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/home/ubuntu
ExecStart=/home/ubuntu/start-openclaw.sh
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
Environment=AWS_REGION=${AWS_REGION}
Environment=HOME=/home/ubuntu
Environment=NODE_COMPILE_CACHE=/var/tmp/openclaw-compile-cache
Environment=OPENCLAW_NO_RESPAWN=1

[Install]
WantedBy=multi-user.target
UNIT

sudo mkdir -p /var/tmp/openclaw-compile-cache
sudo chown ubuntu:ubuntu /var/tmp/openclaw-compile-cache
sudo systemctl daemon-reload
sudo systemctl enable openclaw
sudo systemctl start openclaw

# -----------------------------------------------------------------------------
# 7. Verify
# -----------------------------------------------------------------------------
echo ">>> Waiting for gateway to start..."
sleep 10
if curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:18789/ | grep -q "200"; then
  echo ""
  echo "=========================================="
  echo "  OpenClaw is running!"
  echo "  Dashboard: http://127.0.0.1:18789"
  echo "  (via SSH tunnel: ssh -L 18789:127.0.0.1:18789 ubuntu@<IP>)"
  echo "=========================================="
else
  echo "WARNING: Gateway not responding yet. Check: sudo journalctl -u openclaw -f"
fi

echo ""
echo "Useful commands:"
echo "  sudo systemctl status openclaw"
echo "  sudo journalctl -u openclaw -f"
echo "  openclaw doctor"
