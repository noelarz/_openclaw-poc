# 🦞 NemoClaw — Enterprise-Grade OpenClaw on AWS EC2

OpenClaw wrapped in NVIDIA NemoClaw's security runtime — kernel-level sandboxing, network egress policies, inference routing, and filesystem isolation. Designed as the enterprise promotion path from the base `aws/` OpenClaw deployment.

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  VPC 10.200.0.0/16  (VPC Flow Logs → CloudWatch)                │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │  Public Subnet 10.200.1.0/24                               │  │
│  │  ┌──────────────────────────────────────────────────────┐  │  │
│  │  │  EC2 t3.large (8 GB RAM / Ubuntu 24.04)              │  │  │
│  │  │                                                       │  │  │
│  │  │  ┌─────────────── NemoClaw Runtime ───────────────┐  │  │  │
│  │  │  │                                                 │  │  │  │
│  │  │  │  ┌─ OpenShell Sandbox ────────────────────────┐ │  │  │  │
│  │  │  │  │  Landlock + seccomp + network namespace    │ │  │  │  │
│  │  │  │  │                                            │ │  │  │  │
│  │  │  │  │  OpenClaw Agent                            │ │  │  │  │
│  │  │  │  │  ├─ Skills Engine                          │ │  │  │  │
│  │  │  │  │  ├─ Memory System                          │ │  │  │  │
│  │  │  │  │  └─ Browser (sandboxed)                    │ │  │  │  │
│  │  │  │  │                                            │ │  │  │  │
│  │  │  │  │  Filesystem: /sandbox + /tmp (write)       │ │  │  │  │
│  │  │  │  │             everything else (read-only)    │ │  │  │  │
│  │  │  │  └────────────────────────────────────────────┘ │  │  │  │
│  │  │  │                                                 │  │  │  │
│  │  │  │  ┌─ OpenShell Gateway ────────────────────────┐ │  │  │  │
│  │  │  │  │  Inference routing (agent never holds keys) │ │  │  │  │
│  │  │  │  │  Network egress policy (hot-reloadable)     │ │  │  │  │
│  │  │  │  │  → NVIDIA Nemotron (cloud inference)        │ │  │  │  │
│  │  │  │  └────────────────────────────────────────────┘ │  │  │  │
│  │  │  └─────────────────────────────────────────────────┘  │  │  │
│  │  │                                                       │  │  │
│  │  │  IAM Role → Bedrock + CloudWatch Logs                 │  │  │
│  │  └──────────────────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────────────────┘  │
│  Internet Gateway                                                │
└──────────────────────────────────────────────────────────────────┘
         │
    Security Group
    ├─ :22    ← your IP only
    └─ :18789 ← your IP only
```

## Security Model (4 Kernel Isolation Layers)

| Layer | Enforcement | What It Does | Mutable? |
|-------|-------------|-------------|----------|
| **Network** | Network namespace | Blocks all outbound except whitelisted hosts | Hot-reload |
| **Filesystem** | Landlock | Write only to /sandbox and /tmp; everything else read-only | Locked at creation |
| **Process** | seccomp + Landlock | Blocks privilege escalation and dangerous syscalls | Locked at creation |
| **Inference** | OpenShell gateway | All LLM API calls route through gateway; agent never holds API keys | Hot-reload |

These constraints are **out-of-process** — they exist in the environment, not in the agent. Even if the agent is compromised via prompt injection, the sandbox holds.

## Prerequisites

| Requirement | Detail |
|---|---|
| Terraform | >= 1.5.0 |
| AWS CLI | Configured with credentials |
| NVIDIA API Key | Free 90-day key from [build.nvidia.com](https://build.nvidia.com) |
| Your Public IP | For security group lockdown |

## Quick Start

```bash
# 1. Configure
cd nemoclaw
cp terraform.tfvars.example terraform.tfvars

# 2. Fill in your values
#    - Your IP: curl -s ifconfig.me
#    - NVIDIA API key from build.nvidia.com (starts with nvapi-)
nano terraform.tfvars

# 3. Deploy
terraform init
terraform plan
terraform apply

# 4. SSH in
eval $(terraform output -raw ssh_command)

# 5. Verify bootstrap completed
~/verify-nemoclaw.sh

# 6. Run interactive NemoClaw onboarding
~/setup-nemoclaw.sh

# 7. Connect to the sandbox
nemoclaw healthcare-agent connect

# 8. Apply healthcare network policy
nemoclaw healthcare-agent policy apply --file ~/policies/healthcare-egress.yaml
```

## Post-Deploy Workflow

### Step 1: Verify Infrastructure
```bash
~/verify-nemoclaw.sh
# Confirms: Docker, Node.js, cgroup v2, NemoClaw binary, IAM role
```

### Step 2: Complete Onboarding
```bash
~/setup-nemoclaw.sh
# Interactive wizard: creates sandbox, configures Nemotron inference, applies policies
```

### Step 3: Connect to Sandbox
```bash
nemoclaw healthcare-agent connect
# You're now inside the sandboxed OpenClaw environment
# Run: openclaw doctor
```

### Step 4: Apply Network Policy
```bash
# Review the healthcare egress policy template
cat ~/policies/healthcare-egress.yaml

# Customize for your environment, then apply
nemoclaw healthcare-agent policy apply --file ~/policies/healthcare-egress.yaml
```

### Step 5: Monitor
```bash
# Sandbox status
nemoclaw healthcare-agent status

# Live logs
nemoclaw healthcare-agent logs --follow

# OpenShell TUI dashboard
openshell term

# VPC flow logs (from your workstation)
aws logs tail /vpc/nemoclaw-poc/flow-logs --follow --region us-east-1
```

## Healthcare Network Policy

The included `policies/healthcare-egress.yaml` is a deny-all-by-default template that whitelists only:

- NVIDIA cloud inference endpoints
- AWS Bedrock and CloudWatch (for future model swap and audit)
- npm/PyPI (for skill installation — remove in production)
- DNS resolution

To customize for your healthcare client, add entries for your EHR/EMR API gateway (e.g., Epic FHIR), internal API mesh, and approved SaaS endpoints. Remove npm/PyPI once all skills are pre-installed.

## Differences from `aws/` Deployment

| Aspect | `aws/` (OpenClaw) | `nemoclaw/` (NemoClaw) |
|---|---|---|
| Instance type | t3.medium (4 GB) | t3.large (8 GB) |
| Docker | Not required | Required (sandbox containers) |
| Sandbox isolation | Application-level | Kernel-level (Landlock + seccomp + netns) |
| Network egress | Security group only | SG + per-agent egress policy (deny-all default) |
| Inference routing | Agent holds API keys | Gateway routing (agent never sees keys) |
| Model provider | Anthropic Claude via Bedrock | NVIDIA Nemotron via NVIDIA Cloud API |
| Filesystem | Full access | /sandbox + /tmp only |
| VPC flow logs | Not included | Included (CloudWatch, 90-day retention) |
| Audit trail | Minimal | Flow logs + gateway inference logs |
| EBS volume | 30 GB | 40 GB (sandbox image ~2.4 GB) |

## Cost Estimate

| Component | Estimated Monthly Cost |
|---|---|
| EC2 t3.large | ~$60 |
| EBS 40 GB gp3 | ~$3.20 |
| CloudWatch flow logs | ~$5-10 (varies with traffic) |
| NVIDIA Cloud API tokens | Variable (free 90-day trial) |
| **Total (compute)** | **~$70 + token costs** |

## Important Notes

- NemoClaw is in **early alpha** (launched March 16, 2026). Expect rough edges.
- NemoClaw currently only supports **NVIDIA models** (Nemotron). No Anthropic Claude or OpenAI.
- The onboarding wizard is **interactive** — it cannot be fully automated in user_data. The bootstrap script installs all dependencies and the `setup-nemoclaw.sh` helper handles the interactive portion.
- **macOS is not supported** for NemoClaw. Use the `local/` or `docker/` paths for Mac development.

## Tear Down

```bash
terraform destroy
```
