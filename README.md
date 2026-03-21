# 🦞 OpenClaw POC

Self-hosted OpenClaw AI Agent POC with four deployment paths — run locally on macOS for active development, deploy via Docker, to AWS EC2 for always-on cloud operation, or enterprise-grade on AWS with NemoClaw.

## Deployment Paths

| | [Local Mac](./local/README.md) | [Docker](./docker/README.md) | [AWS EC2](./aws/README.md) | [NemoClaw](./nemoclaw/README.md) |
|---|---|---|---|---|
| Best for | Active development | Portable / containerized | Always-on / persistent | Enterprise / healthcare |
| Cost | Free | Free | ~$33/mo + Bedrock tokens | ~$70/mo + token costs |
| Browser + screen access | ✅ Native | ✅ Headless | ✅ Headless | ✅ Headless |
| Setup time | ~5 min | ~5 min | ~10 min | ~15 min |
| Model provider | Anthropic API or Bedrock | Anthropic API or Bedrock | Bedrock (IAM role) | NVIDIA Nemotron |
| Sandbox isolation | None | Container | None | Kernel-level (Landlock + seccomp) |

## Structure

```
_openclaw-poc/
├── local/        # Native macOS install
│   ├── quickstart.sh
│   ├── openclaw.json
│   └── README.md
├── docker/       # Docker / docker-compose deployment
│   ├── Dockerfile
│   ├── docker-compose.yml
│   ├── entrypoint.sh
│   ├── Makefile
│   ├── .env.example
│   └── README.md
├── aws/          # EC2 IaaS deployment via Terraform
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── terraform.tfvars
│   ├── scripts/bootstrap.sh
│   └── README.md
└── nemoclaw/     # Enterprise EC2 deployment with NemoClaw runtime
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    ├── terraform.tfvars.example
    ├── bootstrap-nemoclaw.sh
    ├── healthcare-egress.yaml
    └── README.md
```

## Recommended Workflow

1. Start with **[local setup](./local/README.md)** — validate the POC, explore features, connect channels
2. Use **[Docker](./docker/README.md)** — for a portable, containerized setup on any OS
3. Promote to **[AWS EC2](./aws/README.md)** — when you need always-on operation without tying up your laptop
4. Upgrade to **[NemoClaw](./nemoclaw/README.md)** — for enterprise or healthcare use cases requiring kernel-level sandboxing
