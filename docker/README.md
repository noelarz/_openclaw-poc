# 🦞 OpenClaw POC — Docker Compose (Local)

Containerized OpenClaw AI Agent for local development on macOS or Linux. Runs the full gateway, headless Chromium browser, skills engine, and memory system inside Docker with persistent volumes.

## Architecture

```
┌─ Your Mac ──────────────────────────────────────────────┐
│                                                          │
│   Browser → http://localhost:18789 (Dashboard)           │
│                  │                                       │
│   ┌──────────────▼────────────────────────────────────┐  │
│   │  Docker Container: openclaw-agent                 │  │
│   │  ┌──────────────────────────────────────────────┐ │  │
│   │  │  OpenClaw Gateway :18789                     │ │  │
│   │  │  ├─ Agent (Claude Sonnet via Anthropic API)  │ │  │
│   │  │  ├─ Headless Chromium (2GB shared memory)    │ │  │
│   │  │  ├─ Skills Engine                            │ │  │
│   │  │  └─ Memory / Cron / Webhooks                 │ │  │
│   │  └──────────────────────────────────────────────┘ │  │
│   │                                                    │  │
│   │  Volumes:                                          │  │
│   │  ├─ openclaw-data  → config, memory, credentials  │  │
│   │  ├─ browser-data   → Chromium profiles, sessions   │  │
│   │  └─ ./workspace    → shared files (bind mount)     │  │
│   └────────────────────────────────────────────────────┘  │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

## Prerequisites

| Requirement       | Detail                                   |
| ----------------- | ---------------------------------------- |
| Docker Desktop    | 4.x+ with Compose V2                    |
| Memory allocation | ≥ 6 GB allocated to Docker (Settings → Resources) |
| API Key           | Anthropic API key **or** AWS credentials |

## Quick Start

```bash
# 1. First-time setup
make setup

# 2. Add your Anthropic API key
nano .env    # set ANTHROPIC_API_KEY=sk-ant-...

# 3. Launch
make up

# 4. Open the dashboard
open http://localhost:18789

# 5. Get your gateway token (if auto-generated)
make token
```

## Makefile Commands

```
  setup           First-time setup: copy .env, create workspace, build image
  up              Start OpenClaw (detached)
  down            Stop OpenClaw (preserves data)
  restart         Restart OpenClaw
  rebuild         Rebuild image and restart (use after Dockerfile changes)
  logs            Tail live logs
  status          Show container status and health
  doctor          Run OpenClaw diagnostics inside the container
  shell           Open a shell inside the container
  token           Display the current gateway token
  config-show     Display current OpenClaw config (redacted)
  clean           Stop containers and remove images (preserves volumes/data)
  nuke            Destroy everything including persisted data volumes
```

## Configuration

### Model Provider

**Option A — Direct Anthropic API (recommended for local POC):**
```env
ANTHROPIC_API_KEY=sk-ant-your-key-here
```

**Option B — AWS Bedrock (consistent with EC2 deployment):**
```env
# Comment out ANTHROPIC_API_KEY, then uncomment:
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=...
AWS_REGION=us-east-1
```

Then update the model in the container config:
```bash
make shell
# Inside container:
jq '.providers.anthropic = {"type": "bedrock", "region": "us-east-1"}' \
  ~/.openclaw/openclaw.json > /tmp/oc.json && mv /tmp/oc.json ~/.openclaw/openclaw.json
exit
make restart
```

### Workspace Mount

The `./workspace` directory on your Mac is mounted at `/home/openclaw/workspace` inside the container. Drop files there for the agent to access, or point `HOST_WORKSPACE` in `.env` to any directory:

```env
HOST_WORKSPACE=~/Projects
```

### Switching Models

```bash
make shell
jq '.agent.model = "anthropic/claude-opus-4-6"' \
  ~/.openclaw/openclaw.json > /tmp/oc.json && mv /tmp/oc.json ~/.openclaw/openclaw.json
exit
make restart
```

## Data Persistence

All state lives in Docker volumes that survive container stops, restarts, and rebuilds:

| Volume          | Contains                               |
| --------------- | -------------------------------------- |
| `openclaw-data` | Config, memory files, skills, credentials |
| `browser-data`  | Chromium profiles, cookies, sessions   |

To start completely fresh: `make nuke`

## Resource Usage

The container is capped at 4 GB RAM / 2 CPUs by default. Monitor with:
```bash
make status
# or
docker stats openclaw-agent
```

If OpenClaw + Chromium together feel sluggish, bump the limits in `docker-compose.yml` under `deploy.resources.limits`.

## Troubleshooting

**Container won't start / health check failing:**
```bash
make logs              # check for errors
make shell             # get inside and poke around
openclaw doctor        # run diagnostics
```

**Browser not working:**
- Verify `shm_size: '2gb'` is in docker-compose.yml (it is by default)
- Stale locks are auto-cleaned on startup via entrypoint.sh
- Check: `ls -la ~/.openclaw/browser/` for lock files

**Out of memory:**
- Docker Desktop → Settings → Resources → increase to 8 GB
- Or reduce `deploy.resources.limits.memory` to match available RAM

**Gateway token unknown:**
```bash
make token
```

## Promoting to EC2

When you're ready to move from local Docker to always-on cloud:

1. Use the companion `openclaw-poc/` Terraform project
2. Your `~/.openclaw/openclaw.json` config transfers directly
3. Swap API key auth for IAM role + Bedrock (already configured in Terraform)
4. `terraform apply` and you're live

## Security Notes

- Gateway binds to `0.0.0.0` inside the container but is only port-mapped to your Mac's localhost by default
- Container runs as non-root `openclaw` user
- Non-main sessions (channels/groups) run in sandboxed mode
- API keys are injected via environment variables, not baked into the image
- `.env` is gitignored — never commit secrets
