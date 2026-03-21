# 🦞 OpenClaw POC

Self-hosted OpenClaw AI Agent POC with four deployment paths — from local macOS development to enterprise-grade NemoClaw with kernel-level isolation.

## Deployment Paths

|  | [Local Mac](local/README.md) | [Docker](docker/README.md) | [AWS EC2](aws/README.md) | [NemoClaw](nemoclaw/README.md) |
| --- | --- | --- | --- | --- |
| Best for | Active development | Isolated local dev | Always-on / persistent | Enterprise / healthcare |
| Cost | Free | Free | ~$33/mo + tokens | ~$70/mo + tokens |
| Sandbox isolation | None | Container-level | Application-level | **Kernel-level** (Landlock + seccomp) |
| Network egress control | None | Docker network | Security group | **Per-agent deny-all policy** |
| Inference routing | Direct API key | Direct API key | IAM role → Bedrock | **Gateway routed** (agent never holds keys) |
| Filesystem isolation | None | Volume-scoped | Full access | **/sandbox + /tmp only** |
| Audit trail | None | Docker logs | CloudWatch | **VPC flow logs + inference logs** |
| Model provider | Anthropic API / Bedrock | Anthropic API / Bedrock | Bedrock (Claude) | NVIDIA Nemotron |
| Browser + screen access | ✅ Native | ✅ Headless | ✅ Headless | ✅ Sandboxed headless |
| macOS support | ✅ | ✅ | N/A | ❌ (Linux only) |
| Setup time | ~5 min | ~10 min | ~10 min | ~20 min |

## Structure

```
_openclaw-poc/
├── local/              # Native macOS install
│   ├── quickstart.sh
│   ├── openclaw.json
│   └── README.md
├── docker/             # Docker Compose (local containerized)
│   ├── docker-compose.yml
│   ├── Dockerfile
│   ├── Makefile
│   ├── scripts/entrypoint.sh
│   ├── config/openclaw.default.json
│   └── README.md
├── aws/                # EC2 IaaS deployment via Terraform
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── terraform.tfvars.example
│   ├── scripts/bootstrap.sh
│   └── README.md
├── nemoclaw/           # Enterprise NemoClaw on EC2 via Terraform
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── terraform.tfvars.example
│   ├── scripts/bootstrap-nemoclaw.sh
│   ├── policies/healthcare-egress.yaml  (deployed to instance)
│   └── README.md
└── README.md
```

## Recommended Workflow

```
Phase 1                Phase 2              Phase 3              Phase 4
┌─────────┐     ┌──────────────┐    ┌──────────────┐    ┌───────────────────┐
│  Local   │ ──▶ │    Docker    │ ──▶│   AWS EC2    │ ──▶│    NemoClaw       │
│  macOS   │     │  Compose     │    │  (OpenClaw)  │    │  (Enterprise)     │
│          │     │              │    │              │    │                   │
│ Explore  │     │ Isolate &    │    │ Always-on    │    │ Kernel sandbox    │
│ features │     │ reproduce    │    │ cloud agent  │    │ Egress policies   │
│          │     │              │    │              │    │ Inference routing  │
│ Claude   │     │ Claude via   │    │ Claude via   │    │ Nemotron via      │
│ via API  │     │ API key      │    │ Bedrock IAM  │    │ NVIDIA Cloud API  │
└─────────┘     └──────────────┘    └──────────────┘    └───────────────────┘
```

1. **[Local](local/README.md)** — validate the POC, explore skills, memory, channel integrations
2. **[Docker](docker/README.md)** — containerized reproducibility, good for demos and sharing
3. **[AWS EC2](aws/README.md)** — always-on operation with Bedrock and IAM role auth
4. **[NemoClaw](nemoclaw/README.md)** — enterprise security posture with kernel isolation, deny-all egress, inference routing, and VPC flow log audit trail
