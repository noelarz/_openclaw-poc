# 🦞 OpenClaw — EC2 IaaS Deployment

Self-hosted OpenClaw AI Agent on AWS EC2 with Terraform. Full IaaS approach — dedicated VPC, IAM role with Bedrock access, automated bootstrap, and systemd service management.

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│  VPC 10.100.0.0/16                                       │
│  ┌────────────────────────────────────────────────────┐  │
│  │  Public Subnet 10.100.1.0/24                       │  │
│  │  ┌──────────────────────────────────────────────┐  │  │
│  │  │  EC2 (t3.medium / Ubuntu 24.04)              │  │  │
│  │  │  ┌────────────────────────────────────────┐  │  │  │
│  │  │  │  OpenClaw Gateway :18789               │  │  │  │
│  │  │  │  ├─ Agent (Claude Sonnet via Bedrock)  │  │  │  │
│  │  │  │  ├─ Headless Chromium (browser ctrl)   │  │  │  │
│  │  │  │  ├─ Skills Engine                      │  │  │  │
│  │  │  │  └─ Memory / Cron / Webhooks           │  │  │  │
│  │  │  └────────────────────────────────────────┘  │  │  │
│  │  │  IAM Role → Bedrock InvokeModel              │  │  │
│  │  └──────────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────────┘  │
│  Internet Gateway                                        │
└──────────────────────────────────────────────────────────┘
         │
    Security Group
    ├─ :22    ← your IP only
    └─ :18789 ← your IP only
```

## Prerequisites

| Requirement    | Detail                                   |
|----------------|------------------------------------------|
| Terraform      | >= 1.5.0                                 |
| AWS CLI        | Configured with credentials              |
| Bedrock Access | Claude model enabled in your AWS account |
| Your Public IP | For security group lockdown              |

> **Bedrock Model Access**: In the AWS Console → Bedrock → Model access, make sure the Claude model you want (e.g., Claude Sonnet 4) is enabled in your target region.

## Quick Start

```bash
# 1. Navigate to this directory
cd aws

# 2. Edit terraform.tfvars — fill in your IP and generate a gateway token
#    Find your IP:
curl -s ifconfig.me

#    Generate a strong token:
openssl rand -hex 32

# 3. Deploy
terraform init
terraform plan
terraform apply

# 4. Connect via SSH tunnel (secure — recommended)
eval $(terraform output -raw ssh_tunnel_command)

# 5. Open dashboard in your browser
open http://127.0.0.1:18789
```

## Post-Deploy Checklist

```bash
# Check bootstrap completed successfully
sudo tail -50 /var/log/openclaw-bootstrap.log

# Run the built-in verification script
sudo -u openclaw /home/openclaw/verify-openclaw.sh

# Check service status
sudo systemctl status openclaw

# Watch live logs
sudo journalctl -u openclaw -f

# Run OpenClaw diagnostics
sudo -u openclaw openclaw doctor
```

## Accessing the Dashboard

**Option A — SSH Tunnel (Recommended)**

```bash
ssh -i openclaw-key.pem -L 18789:127.0.0.1:18789 ubuntu@<PUBLIC_IP>
```

**Option B — Direct Access**

```
http://<PUBLIC_IP>:18789
```

Enter the gateway token you configured in `terraform.tfvars`.

**Option C — SSM Session Manager (No SSH Key)**

```bash
aws ssm start-session --target <INSTANCE_ID> --region us-east-1
```

## Configuration

The OpenClaw config lives at `/home/openclaw/.openclaw/openclaw.json`.

```bash
sudo -u openclaw nano /home/openclaw/.openclaw/openclaw.json
sudo systemctl restart openclaw
```

### Switching Models

```json
{
  "agent": {
    "model": "anthropic/claude-opus-4-6"
  }
}
```

### Adding Channel Integrations

```bash
sudo -u openclaw openclaw channels login
```

## Cost Estimate

| Component           | Estimated Monthly Cost |
|---------------------|------------------------|
| EC2 t3.medium       | ~$30                   |
| EBS 30GB gp3        | ~$2.40                 |
| Bedrock tokens      | Variable (usage-based) |
| **Total (compute)** | **~$33 + token costs** |

> **Tip**: Stop the instance when not in use — `terraform apply` won't recreate it. Or use `aws ec2 stop-instances` to pause billing.

## Security Notes

- Security group is locked to your specified CIDR(s) — **do not open 0.0.0.0/0**
- IMDSv2 is enforced (hop limit = 1, tokens required)
- Gateway token authentication is required for dashboard access
- systemd service runs with `NoNewPrivileges`, `ProtectSystem=strict`, `PrivateTmp`
- SSH key is generated by Terraform — the private key is in your tfstate (**encrypt your state backend for production**)

## Tear Down

```bash
terraform destroy
```

## Next Steps

- [ ] Connect a messaging channel (WhatsApp/Telegram/Slack)
- [ ] Install community skills (`openclaw skills install <name>`)
- [ ] Set up cron jobs for automated tasks
- [ ] Configure memory persistence (MEMORY.md pattern)
- [ ] Add Tailscale for secure remote access without SSH tunnels
- [ ] Migrate to HCP Terraform for state management if this moves beyond POC
