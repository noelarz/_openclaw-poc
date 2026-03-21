# OpenClaw Post-Deploy Setup Guide

After `terraform apply` completes, the EC2 instance needs manual setup.
The bootstrap script (`user_data`) handles OS-level dependencies, but OpenClaw
installation and gateway configuration must be done via `setup-openclaw.sh`.

## Why Manual Setup?

The automated `user_data` bootstrap fails on Ubuntu 24.04 due to:
- **apt mirror sync errors** — transient Ubuntu package index mismatches
- **Template variable conflicts** — `set -euo pipefail` + Terraform `templatefile` syntax collisions
- **Node.js version** — Ubuntu 24.04 ships Node 18; OpenClaw requires Node 22+

## Prerequisites

| Requirement | Detail |
|---|---|
| EC2 instance running | From `terraform apply` |
| IAM role attached | `bedrock:InvokeModel` + SSM permissions (Terraform handles this) |
| SSH key | `./openclaw-key.pem` (Terraform generates this) |
| Gateway token | From `terraform.tfvars` → `gateway_token` |

## Quick Start

```bash
# 1. Get your public IP and token from Terraform outputs
cd aws
terraform output public_ip
terraform output -raw ssh_command

# 2. Copy and run the setup script
scp -i openclaw-key.pem scripts/setup-openclaw.sh ubuntu@<PUBLIC_IP>:~
ssh -i openclaw-key.pem ubuntu@<PUBLIC_IP> \
  "GATEWAY_TOKEN=<your_token> bash setup-openclaw.sh"

# 3. Open SSH tunnel to access the dashboard
ssh -i openclaw-key.pem -L 18789:127.0.0.1:18789 ubuntu@<PUBLIC_IP>

# 4. Open in browser
open http://127.0.0.1:18789
```

## What the Setup Script Does

| Step | Action |
|---|---|
| 1 | `apt-get update` with mirror-error workaround |
| 2 | Installs `fnm` (Node version manager) |
| 3 | Installs Node.js 22 via fnm |
| 4 | Installs OpenClaw globally via npm |
| 5 | Writes `~/.openclaw/openclaw.json` with gateway config + Bedrock model |
| 6 | Creates `~/start-openclaw.sh` — fetches IAM credentials + starts gateway |
| 7 | Creates and enables `openclaw.service` systemd unit |
| 8 | Starts the gateway and verifies HTTP 200 |

## How Bedrock Auth Works

OpenClaw requires explicit AWS credentials — it does **not** auto-detect EC2
instance role credentials via the standard SDK chain.

The `start-openclaw.sh` script works around this by:
1. Fetching temporary credentials from the EC2 instance metadata service (IMDSv2)
2. Setting `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and `AWS_SESSION_TOKEN`
3. Starting the gateway with those env vars set

> **Note:** IAM role credentials expire every ~6 hours. The systemd service
> restarts automatically on failure, re-fetching fresh credentials each time.
> To manually refresh: `sudo systemctl restart openclaw`

## Accessing the Dashboard

**Option A — SSH Tunnel (Recommended)**

The Control UI requires a secure context (HTTPS or localhost). Always use a tunnel:

```bash
ssh -i openclaw-key.pem -L 18789:127.0.0.1:18789 ubuntu@<PUBLIC_IP>
```

Then open `http://127.0.0.1:18789` and enter your gateway token.

> If you have a local OpenClaw running on port 18789, stop it first or use
> a different local port: `ssh -L 18790:127.0.0.1:18789 ...` → `http://127.0.0.1:18790`

**Option B — SSM Session Manager (No SSH key required)**

```bash
aws ssm start-session --target <INSTANCE_ID> --region us-east-1
```

## Useful Commands (on the instance)

```bash
# Service status
sudo systemctl status openclaw

# Live logs
sudo journalctl -u openclaw -f

# Restart with fresh credentials
sudo systemctl restart openclaw

# OpenClaw diagnostics
openclaw doctor

# Manually start gateway (outside systemd)
GATEWAY_TOKEN=<token> bash ~/start-openclaw.sh
```

## Known Issues

| Issue | Cause | Fix |
|---|---|---|
| `apt` mirror sync error on first boot | Ubuntu 24.04 mirror inconsistency | Script uses `\|\| true` to continue past it |
| `No API key found for amazon-bedrock` | OpenClaw doesn't auto-detect EC2 IAM role | `start-openclaw.sh` fetches credentials explicitly via IMDSv2 |
| `control ui requires device identity` | Control UI requires secure context | Always access via SSH tunnel (localhost) |
| `too many failed authentication attempts` | Rate-limited from token retries | Restart gateway: `sudo systemctl restart openclaw` |
| SSH drops when killing gateway | Tunnel session killed with process | Use SSM or a separate SSH session to restart |

## Configuration File

Location: `/home/ubuntu/.openclaw/openclaw.json`

```json
{
  "gateway": {
    "port": 18789,
    "mode": "local",
    "bind": "lan",
    "auth": {
      "token": "<your_gateway_token>"
    },
    "controlUi": {
      "dangerouslyAllowHostHeaderOriginFallback": true
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "amazon-bedrock/us.anthropic.claude-sonnet-4-20250514-v1:0"
      }
    }
  }
}
```

After editing config: `sudo systemctl restart openclaw`
