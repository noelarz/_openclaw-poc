# 🦞 OpenClaw POC

Self-hosted OpenClaw AI Agent POC with two deployment paths — run locally on macOS for active development, or deploy to AWS EC2 for always-on cloud operation.

## Deployment Paths

| | [Local Mac](./local/README.md) | [AWS EC2](./aws/README.md) |
|---|---|---|
| Best for | Active development | Always-on / persistent |
| Cost | Free | ~$33/mo + Bedrock tokens |
| Browser + screen access | ✅ Native | ✅ Headless |
| Setup time | ~5 min | ~10 min |
| Model provider | Anthropic API or Bedrock | Bedrock (IAM role) |

## Structure

```
_openclaw-poc/
├── local/        # Native macOS install
│   ├── quickstart.sh
│   ├── openclaw.json
│   └── README.md
└── aws/          # EC2 IaaS deployment via Terraform
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    ├── terraform.tfvars
    ├── scripts/bootstrap.sh
    └── README.md
```

## Recommended Workflow

1. Start with **[local setup](./local/README.md)** — validate the POC, explore features, connect channels
2. Promote to **[AWS EC2](./aws/README.md)** — when you need always-on operation without tying up your laptop
