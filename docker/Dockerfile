FROM node:22-slim

# Install system dependencies including Chromium
RUN apt-get update && apt-get install -y \
  chromium \
  fonts-liberation \
  libatk-bridge2.0-0 \
  libgtk-3-0 \
  libnss3 \
  libxss1 \
  xdg-utils \
  ca-certificates \
  curl \
  jq \
  && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN useradd -m -s /bin/bash openclaw

# Install OpenClaw globally
RUN npm install -g openclaw

# Switch to non-root user
USER openclaw
WORKDIR /home/openclaw

# Create config and workspace dirs
RUN mkdir -p /home/openclaw/.openclaw /home/openclaw/workspace

# Copy entrypoint
COPY --chown=openclaw:openclaw entrypoint.sh /home/openclaw/entrypoint.sh
RUN chmod +x /home/openclaw/entrypoint.sh

EXPOSE 18789

ENTRYPOINT ["/home/openclaw/entrypoint.sh"]
