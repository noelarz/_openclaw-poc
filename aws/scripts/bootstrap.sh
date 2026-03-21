#!/usr/bin/env bash
###############################################################################
# OpenClaw EC2 Bootstrap Script
# Runs as user_data on first boot (root context)
###############################################################################
set -euo pipefail

LOG="/var/log/openclaw-bootstrap.log"
exec > >(tee -a "$LOG") 2>&1
echo "========== OpenClaw Bootstrap Started: $(date -u) =========="

# -----------------------------------------------------------------------------
# 1. System updates & base dependencies
# -----------------------------------------------------------------------------

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get upgrade -y
apt-get install -y \
  build-essential \
  git \
  curl \
  wget \
  unzip \
  jq \
  htop \
  tmux \
  chromium-browser \
  fonts-liberation \
  libatk-bridge2.0-0 \
  libgtk-3-0 \
  libnss3 \
  libxss1 \
  xdg-utils \
  ca-certificates \
  gnupg

# -----------------------------------------------------------------------------
# 2. Install Node.js ${node_major}
# -----------------------------------------------------------------------------

echo ">>> Installing Node.js ${node_major}..."
curl -fsSL https://deb.nodesource.com/setup_${node_major}.x | bash -
apt-get install -y nodejs

npm install -g pnpm

echo "Node: $(node --version) | npm: $(npm --version) | pnpm: $(pnpm --version)"

# -----------------------------------------------------------------------------
# 3. Create openclaw system user
# -----------------------------------------------------------------------------

if ! id "openclaw" &>/dev/null; then
  useradd -m -s /bin/bash openclaw
  usermod -aG sudo openclaw
fi

# -----------------------------------------------------------------------------
# 4. Install OpenClaw
# -----------------------------------------------------------------------------

echo ">>> Installing OpenClaw..."
su - openclaw -c 'npm install -g openclaw'

# -----------------------------------------------------------------------------
# 5. Configure OpenClaw
# -----------------------------------------------------------------------------

echo ">>> Configuring OpenClaw..."
OPENCLAW_HOME="/home/openclaw/.openclaw"
mkdir -p "$OPENCLAW_HOME"

cat > "$OPENCLAW_HOME/openclaw.json" <<OCCONFIG
{
  "agents": {
    "defaults": {
      "model": {
        "primary": "amazon-bedrock/us.anthropic.claude-sonnet-4-20250514-v1:0"
      }
    }
  },
  "gateway": {
    "port": 18789,
    "mode": "local",
    "bind": "loopback",
    "auth": {
      "mode": "token",
      "token": "${gateway_token}"
    }
  }
}
OCCONFIG

chmod 700 "$OPENCLAW_HOME"
chmod 600 "$OPENCLAW_HOME/openclaw.json"
chown -R openclaw:openclaw "$OPENCLAW_HOME"

# -----------------------------------------------------------------------------
# 6. Create systemd service
# -----------------------------------------------------------------------------

cat > /etc/systemd/system/openclaw.service <<'SVCFILE'
[Unit]
Description=OpenClaw AI Agent Gateway
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=openclaw
Group=openclaw
WorkingDirectory=/home/openclaw
ExecStart=/home/openclaw/.nvm/versions/node/v22/bin/openclaw gateway
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=openclaw
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=/home/openclaw/.openclaw /tmp
PrivateTmp=true
Environment=NODE_ENV=production
Environment=HOME=/home/openclaw
Environment=OPENCLAW_HOME=/home/openclaw/.openclaw
Environment=AWS_REGION=${aws_region}

[Install]
WantedBy=multi-user.target
SVCFILE

systemctl daemon-reload
systemctl enable openclaw.service
systemctl start openclaw.service

# -----------------------------------------------------------------------------
# 7. Create swap (safety net for memory spikes)
# -----------------------------------------------------------------------------

if [ ! -f /swapfile ]; then
  fallocate -l 2G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# -----------------------------------------------------------------------------
# 8. Post-install verification script
# -----------------------------------------------------------------------------

cat > /home/openclaw/verify-openclaw.sh <<'VERIFY'
#!/usr/bin/env bash
echo "============================================"
echo "  OpenClaw POC -- Post-Install Verification"
echo "============================================"
echo ""
echo "System:"
echo "  OS:       $(lsb_release -ds)"
echo "  Kernel:   $(uname -r)"
echo "  Memory:   $(free -h | awk '/Mem/{print $2}')"
echo "  Disk:     $(df -h / | awk 'NR==2{print $4}') available"
echo ""
echo "Runtime:"
echo "  Node:     $(node --version 2>/dev/null || echo 'NOT FOUND')"
echo "  npm:      $(npm --version 2>/dev/null || echo 'NOT FOUND')"
echo "  pnpm:     $(pnpm --version 2>/dev/null || echo 'NOT FOUND')"
echo ""
echo "OpenClaw:"
echo "  Binary:   $(which openclaw 2>/dev/null || echo 'NOT FOUND')"
echo "  Config:   $(ls -la ~/.openclaw/openclaw.json 2>/dev/null || echo 'NOT FOUND')"
echo "  Service:  $(systemctl is-active openclaw.service 2>/dev/null || echo 'UNKNOWN')"
echo ""
echo "Network:"
echo "  Gateway:  $(curl -s -o /dev/null -w '%%{http_code}' http://127.0.0.1:18789/ 2>/dev/null || echo 'NOT RESPONDING')"
echo ""
echo "AWS:"
echo "  Region:   $(curl -s http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || echo 'UNKNOWN')"
echo "  Instance: $(curl -s http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null || echo 'UNKNOWN')"
echo ""
echo "IMDSv2 Token Test:"
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null)
if [ -n "$TOKEN" ]; then
  echo "  IMDSv2:   OK"
  echo "  Role:     $(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/ 2>/dev/null || echo 'NONE')"
else
  echo "  IMDSv2:   FAILED"
fi
echo ""
echo "============================================"
VERIFY

chmod +x /home/openclaw/verify-openclaw.sh
chown openclaw:openclaw /home/openclaw/verify-openclaw.sh

# -----------------------------------------------------------------------------
# 9. MOTD for SSH login
# -----------------------------------------------------------------------------

cat > /etc/update-motd.d/99-openclaw <<'MOTD'
#!/bin/bash
echo ""
echo "  OpenClaw POC Instance"
echo "  ----------------------------------------"
echo "  Dashboard:  http://127.0.0.1:18789"
echo "  Service:    sudo systemctl status openclaw"
echo "  Logs:       sudo journalctl -u openclaw -f"
echo "  Config:     /home/openclaw/.openclaw/openclaw.json"
echo "  Verify:     sudo -u openclaw /home/openclaw/verify-openclaw.sh"
echo "  ----------------------------------------"
echo ""
MOTD
chmod +x /etc/update-motd.d/99-openclaw

echo "========== OpenClaw Bootstrap Complete: $(date -u) =========="
