#!/usr/bin/env bash
###############################################################################
# NemoClaw EC2 Bootstrap Script
# Installs NVIDIA NemoClaw (OpenClaw + OpenShell sandbox + kernel isolation)
# Runs as user_data on first boot (root context)
###############################################################################
set -euo pipefail

LOG="/var/log/nemoclaw-bootstrap.log"
exec > >(tee -a "$LOG") 2>&1
echo "========== NemoClaw Bootstrap Started: $(date -u) =========="

# ---------------------------------------------------------------------------
# 1. System updates & base dependencies
# ---------------------------------------------------------------------------
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
  ca-certificates \
  gnupg \
  lsb-release \
  apt-transport-https \
  software-properties-common

# ---------------------------------------------------------------------------
# 2. Install Docker (required by NemoClaw/OpenShell for sandbox containers)
# ---------------------------------------------------------------------------
echo ">>> Installing Docker..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable docker
systemctl start docker

# Add ubuntu user to docker group
usermod -aG docker ubuntu

echo "Docker: $(docker --version)"

# ---------------------------------------------------------------------------
# 3. Install Node.js ${node_major}
# ---------------------------------------------------------------------------
echo ">>> Installing Node.js ${node_major}..."
curl -fsSL https://deb.nodesource.com/setup_${node_major}.x | bash -
apt-get install -y nodejs
npm install -g pnpm

echo "Node: $(node --version) | npm: $(npm --version) | pnpm: $(pnpm --version)"

# ---------------------------------------------------------------------------
# 4. Create swap (NemoClaw sandbox image build can spike memory)
#    8 GB RAM + 4 GB swap provides buffer against OOM during image push
# ---------------------------------------------------------------------------
echo ">>> Configuring swap..."
if [ ! -f /swapfile ]; then
  fallocate -l 4G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# ---------------------------------------------------------------------------
# 5. Ensure cgroup v2 (required by OpenShell's embedded k3s)
# ---------------------------------------------------------------------------
echo ">>> Verifying cgroup v2..."
if ! mount | grep -q "cgroup2"; then
  echo "WARNING: cgroup v2 not detected. OpenShell may fail."
  echo "Ubuntu 24.04 should have cgroup v2 by default."
fi

# ---------------------------------------------------------------------------
# 6. Store NVIDIA API key securely
# ---------------------------------------------------------------------------
echo ">>> Configuring credentials..."
mkdir -p /home/ubuntu/.nemoclaw
cat > /home/ubuntu/.nemoclaw/.env <<'ENVFILE'
NVIDIA_API_KEY=${nvidia_api_key}
ENVFILE
chmod 600 /home/ubuntu/.nemoclaw/.env
chown -R ubuntu:ubuntu /home/ubuntu/.nemoclaw

# ---------------------------------------------------------------------------
# 7. Install NemoClaw
# ---------------------------------------------------------------------------
echo ">>> Installing NemoClaw..."

# Run as ubuntu user (NemoClaw expects non-root for onboarding)
# We split install from onboard for automated provisioning
su - ubuntu -c '
  export NVIDIA_API_KEY=$(cat ~/.nemoclaw/.env | grep NVIDIA_API_KEY | cut -d= -f2)

  # Download the installer but skip interactive onboard
  curl -fsSL https://nvidia.com/nemoclaw.sh -o /tmp/nemoclaw-install.sh
  chmod +x /tmp/nemoclaw-install.sh

  # Run installer
  sudo bash /tmp/nemoclaw-install.sh
'

# ---------------------------------------------------------------------------
# 8. Create automated onboarding script (run manually or via SSM)
#    NemoClaw onboard is interactive — we provide a helper script
# ---------------------------------------------------------------------------
cat > /home/ubuntu/setup-nemoclaw.sh <<'SETUP'
#!/usr/bin/env bash
###############################################################################
# NemoClaw Onboarding Helper
# Run this after SSH-ing in to complete the interactive setup
###############################################################################
set -euo pipefail

SANDBOX_NAME="${sandbox_name}"
NVIDIA_KEY=$(cat ~/.nemoclaw/.env | grep NVIDIA_API_KEY | cut -d= -f2)

echo ""
echo "============================================"
echo "  🦞 NemoClaw Onboarding"
echo "============================================"
echo ""
echo "  Sandbox name:  $SANDBOX_NAME"
echo "  NVIDIA API key: nvapi-****$(echo $NVIDIA_KEY | tail -c 8)"
echo ""
echo "  This will:"
echo "    1. Create the OpenShell sandbox"
echo "    2. Configure NVIDIA cloud inference"
echo "    3. Apply security policies"
echo "    4. Install OpenClaw inside the sandbox"
echo ""
read -p "  Proceed? [Y/n] " confirm
confirm=$${confirm:-Y}
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

echo ""
echo ">>> Running nemoclaw onboard..."
echo "    (Follow the interactive prompts)"
echo ""

nemoclaw onboard

echo ""
echo "============================================"
echo "  ✅ NemoClaw Setup Complete"
echo "============================================"
echo ""
echo "  Connect:  nemoclaw $SANDBOX_NAME connect"
echo "  Status:   nemoclaw $SANDBOX_NAME status"
echo "  Logs:     nemoclaw $SANDBOX_NAME logs --follow"
echo "  TUI:      openshell term"
echo ""
SETUP

chmod +x /home/ubuntu/setup-nemoclaw.sh
chown ubuntu:ubuntu /home/ubuntu/setup-nemoclaw.sh

# ---------------------------------------------------------------------------
# 9. Create healthcare network policy template
# ---------------------------------------------------------------------------
mkdir -p /home/ubuntu/policies
cat > /home/ubuntu/policies/healthcare-egress.yaml <<'POLICY'
###############################################################################
# NemoClaw Network Egress Policy — Healthcare POC
#
# Principle: deny-all by default, whitelist only approved endpoints.
# This file is a TEMPLATE — customize for your specific environment.
#
# Hot-reloadable: changes apply without restarting the sandbox.
# Apply with: nemoclaw <sandbox> policy apply --file healthcare-egress.yaml
###############################################################################

# -- Approved external endpoints -----------------------------------------
allow:
  # NVIDIA inference API (required for Nemotron model)
  - host: "api.nvcf.nvidia.com"
    ports: [443]
    reason: "NVIDIA cloud inference endpoint"

  - host: "integrate.api.nvidia.com"
    ports: [443]
    reason: "NVIDIA model integration API"

  # AWS services (Bedrock, CloudWatch — future model provider swap)
  - host: "bedrock-runtime.us-east-1.amazonaws.com"
    ports: [443]
    reason: "AWS Bedrock inference (future provider option)"

  - host: "logs.us-east-1.amazonaws.com"
    ports: [443]
    reason: "CloudWatch Logs for audit trail"

  # Package registries (for skill installation — restrict in production)
  - host: "registry.npmjs.org"
    ports: [443]
    reason: "npm package installs for skills"

  - host: "pypi.org"
    ports: [443]
    reason: "Python package installs"

  # DNS
  - host: "dns"
    ports: [53]
    reason: "DNS resolution"

# -- Explicitly blocked (documentation / auditability) -------------------
deny:
  # No direct internet browsing from sandbox
  - host: "*"
    ports: [80, 8080]
    reason: "Block unencrypted HTTP traffic"

  # No social media / messaging from agent (prevent data exfiltration)
  - host: "*.slack.com"
    reason: "Block agent-initiated Slack (use channel integration instead)"

  - host: "*.telegram.org"
    reason: "Block agent-initiated Telegram"

# -- Policy metadata -----------------------------------------------------
metadata:
  name: "healthcare-poc-egress"
  version: "1.0.0"
  author: "noel"
  compliance_notes: |
    This policy enforces network isolation for a healthcare POC environment.
    All outbound connections are denied by default except explicitly whitelisted
    endpoints above. Customize the allow list based on your specific EHR/EMR
    integrations, approved SaaS endpoints, and internal API gateways.

    For HIPAA-aligned deployments:
    - Add your EHR API gateway (e.g., Epic FHIR endpoint)
    - Add your internal API mesh / service mesh endpoints
    - Remove npm/pypi if skills are pre-installed
    - Add CloudTrail and audit log endpoints
POLICY

chown -R ubuntu:ubuntu /home/ubuntu/policies

# ---------------------------------------------------------------------------
# 10. Post-install verification script
# ---------------------------------------------------------------------------
cat > /home/ubuntu/verify-nemoclaw.sh <<'VERIFY'
#!/usr/bin/env bash
echo "============================================"
echo "  NemoClaw POC — Post-Install Verification"
echo "============================================"
echo ""
echo "System:"
echo "  OS:       $(lsb_release -ds)"
echo "  Kernel:   $(uname -r)"
echo "  Memory:   $(free -h | awk '/Mem/{print $2}')"
echo "  Swap:     $(free -h | awk '/Swap/{print $2}')"
echo "  Disk:     $(df -h / | awk 'NR==2{print $4}') available"
echo ""
echo "Runtime:"
echo "  Node:     $(node --version 2>/dev/null || echo 'NOT FOUND')"
echo "  Docker:   $(docker --version 2>/dev/null || echo 'NOT FOUND')"
echo "  NemoClaw: $(which nemoclaw 2>/dev/null || echo 'NOT FOUND')"
echo ""
echo "Docker Status:"
docker ps --format "  {{.Names}}: {{.Status}}" 2>/dev/null || echo "  Docker not accessible"
echo ""
echo "cgroup:"
echo "  Version:  $(stat -fc %T /sys/fs/cgroup 2>/dev/null || echo 'UNKNOWN')"
echo ""
echo "AWS:"
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60" 2>/dev/null)
if [ -n "$TOKEN" ]; then
  echo "  IMDSv2:   OK"
  echo "  Region:   $(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null)"
  echo "  Instance: $(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id 2>/dev/null)"
  echo "  Type:     $(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-type 2>/dev/null)"
  echo "  Role:     $(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/iam/security-credentials/ 2>/dev/null)"
else
  echo "  IMDSv2:   FAILED"
fi
echo ""
echo "NemoClaw:"
if command -v nemoclaw &>/dev/null; then
  nemoclaw --version 2>/dev/null || echo "  Version check failed"
else
  echo "  Not installed yet — run: ~/setup-nemoclaw.sh"
fi
echo ""
echo "Healthcare Policy:"
if [ -f ~/policies/healthcare-egress.yaml ]; then
  echo "  Template: ~/policies/healthcare-egress.yaml ✅"
else
  echo "  Template: NOT FOUND"
fi
echo ""
echo "============================================"
echo "  Next Steps:"
echo "  1. Run: ~/setup-nemoclaw.sh"
echo "  2. Connect: nemoclaw healthcare-agent connect"
echo "  3. Apply policy: nemoclaw healthcare-agent policy apply --file ~/policies/healthcare-egress.yaml"
echo "============================================"
VERIFY

chmod +x /home/ubuntu/verify-nemoclaw.sh
chown ubuntu:ubuntu /home/ubuntu/verify-nemoclaw.sh

# ---------------------------------------------------------------------------
# 11. MOTD
# ---------------------------------------------------------------------------
cat > /etc/update-motd.d/99-nemoclaw <<'MOTD'
#!/bin/bash
echo ""
echo "  🦞 NemoClaw Enterprise POC Instance"
echo "  ────────────────────────────────────────"
echo "  Setup:    ~/setup-nemoclaw.sh"
echo "  Verify:   ~/verify-nemoclaw.sh"
echo "  Policy:   ~/policies/healthcare-egress.yaml"
echo "  Logs:     nemoclaw healthcare-agent logs --follow"
echo "  TUI:      openshell term"
echo "  ────────────────────────────────────────"
echo ""
MOTD
chmod +x /etc/update-motd.d/99-nemoclaw

echo "========== NemoClaw Bootstrap Complete: $(date -u) =========="
echo ""
echo "IMPORTANT: NemoClaw onboard is interactive."
echo "SSH in and run: ~/setup-nemoclaw.sh"
