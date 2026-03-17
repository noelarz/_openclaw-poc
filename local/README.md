# 🦞 OpenClaw — Local Mac Setup

Run OpenClaw natively on macOS for active development. Native install gives you full access to browser control via CDP, file system interaction, and the macOS menu bar companion — features that are limited or broken in Docker.

## When to Use This vs EC2

| | Local Mac | EC2 (see root README) |
|---|---|---|
| Active development | ✅ | |
| Always-on / persistent | | ✅ |
| Browser + screen access | ✅ native | ✅ headless |
| Zero cloud cost | ✅ | |
| Promote to production | | ✅ |

## Prerequisites

- macOS
- Node.js 22+ — `brew install node@22`
- Anthropic API key **or** AWS credentials with Bedrock access

## Quick Start

```bash
# 1. Run the setup script
chmod +x local/quickstart.sh
./local/quickstart.sh

# 2. Edit the config — add your API key
nano ~/.openclaw/openclaw.json

# 3. Start the gateway
openclaw gateway

# 4. Open the dashboard
open http://127.0.0.1:18789
```

## Config

The quickstart copies `local/openclaw.json` to `~/.openclaw/openclaw.json`.

### Option A — Anthropic API Key (recommended for local)

```json
{
  "providers": {
    "anthropic": {
      "type": "api",
      "apiKey": "YOUR_ANTHROPIC_API_KEY"
    }
  }
}
```

### Option B — AWS Bedrock (consistent with EC2 path)

```json
{
  "providers": {
    "anthropic": {
      "type": "bedrock",
      "region": "us-east-1"
    }
  }
}
```

Bedrock uses your local `~/.aws/credentials` — no API key needed.

## Useful Commands

```bash
openclaw doctor        # verify installation
openclaw onboard       # guided setup wizard
openclaw gateway       # start the gateway
openclaw dashboard     # open browser UI
openclaw channels login  # connect WhatsApp, Telegram, etc.
```

## Promoting to EC2

Once you've validated the POC locally, deploy to EC2 for always-on operation:

```bash
cd ..
terraform init
terraform apply
```

See the [root README](../README.md) for the full EC2 deployment guide.
