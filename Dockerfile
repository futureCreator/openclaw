FROM node:22-bookworm

# Install Bun (required for build scripts + global packages)
RUN curl -fsSL https://bun.sh/install | bash && \
    ln -s /root/.bun/bin/bun /usr/local/bin/bun && \
    ln -s /root/.bun/bin/bunx /usr/local/bin/bunx
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable

WORKDIR /app

# System packages: Chrome, fonts, jq, ripgrep + optional extras (single layer)
ARG OPENCLAW_DOCKER_APT_PACKAGES=""
RUN curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
      | gpg --dearmor -o /usr/share/keyrings/google-chrome.gpg && \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] http://dl.google.com/linux/chrome/deb/ stable main" \
      > /etc/apt/sources.list.d/google-chrome.list && \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      google-chrome-stable \
      fonts-ipafont-gothic fonts-wqy-zenhei fonts-thai-tlwg fonts-kacst fonts-freefont-ttf \
      libxss1 jq ripgrep $OPENCLAW_DOCKER_APT_PACKAGES && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

# External CLI tools (himalaya, gog)
RUN curl -sLo /tmp/himalaya.tgz \
      "https://github.com/pimalaya/himalaya/releases/latest/download/himalaya.x86_64-linux.tgz" && \
    tar -xzf /tmp/himalaya.tgz -C /usr/local/bin/ && \
    rm /tmp/himalaya.tgz && \
    chmod +x /usr/local/bin/himalaya && \
    wget -qO - https://github.com/steipete/gogcli/releases/download/v0.9.0/gogcli_0.9.0_linux_amd64.tar.gz \
      | tar -xzC /tmp && \
    mv /tmp/gog /usr/local/bin/gog && \
    chmod +x /usr/local/bin/gog

# Global bun packages (symlink to /usr/local/bin so node user can access)
RUN bun add -g clawhub @steipete/bird mcporter && \
    ln -s /root/.bun/bin/clawhub /usr/local/bin/clawhub && \
    ln -s /root/.bun/bin/bird /usr/local/bin/bird && \
    ln -s /root/.bun/bin/mcporter /usr/local/bin/mcporter

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY ui/package.json ./ui/package.json
COPY patches ./patches
COPY scripts ./scripts

RUN pnpm install --frozen-lockfile

COPY . .
RUN OPENCLAW_A2UI_SKIP_MISSING=1 pnpm build
# Force pnpm for UI build (Bun may fail on ARM/Synology architectures)
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:build

ENV NODE_ENV=production

# Allow non-root user to write temp files during runtime/tests.
RUN chown -R node:node /app

# Security hardening: Run as non-root user
# The node:22-bookworm image includes a 'node' user (uid 1000)
# This reduces the attack surface by preventing container escape via root privileges
USER node

# Start gateway server with default config.
# Binds to loopback (127.0.0.1) by default for security.
#
# For container platforms requiring external health checks:
#   1. Set OPENCLAW_GATEWAY_TOKEN or OPENCLAW_GATEWAY_PASSWORD env var
#   2. Override CMD: ["node","dist/index.js","gateway","--allow-unconfigured","--bind","lan"]
CMD ["node", "dist/index.js", "gateway", "--allow-unconfigured"]
