FROM node:20-bookworm-slim AS build

WORKDIR /app

COPY web/services/pose-extract-server/package.json web/services/pose-extract-server/package-lock.json ./
RUN npm ci

COPY web/services/pose-extract-server/tsconfig.json web/services/pose-extract-server/vitest.config.ts ./
COPY web/services/pose-extract-server/src ./src
COPY web/services/pose-extract-server/scripts ./scripts

RUN npm run build

FROM node:20-bookworm-slim AS combined

# System CA bundle required by the Higgsfield CLI (Go) for HTTPS.
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates python3 python3-pip \
  && rm -rf /var/lib/apt/lists/*

# Higgsfield CLI (global bin: higgsfield). Pin version for reproducible builds.
RUN npm install -g @higgsfield/cli@1.1.23 \
  && higgsfield --version

# Install OS dependencies for Playwright
RUN npx playwright install-deps chromium

# Install Playwright browser
ENV PLAYWRIGHT_BROWSERS_PATH=/root/.cache/ms-playwright
RUN npx playwright install chromium

WORKDIR /app
COPY web/services/pose-extract-server/package.json web/services/pose-extract-server/package-lock.json ./
RUN npm ci --omit=dev

COPY --from=build /app/dist ./dist
COPY web/services/pose-extract-server/scripts/remove_bg_lineart.py ./scripts/remove_bg_lineart.py
COPY web/services/pose-extract-server/requirements.txt ./requirements.txt
RUN pip3 install --no-cache-dir --break-system-packages -r requirements.txt
COPY web/services/pose-extract-server/scripts/higgsfield-auth-probe.sh ./scripts/higgsfield-auth-probe.sh
RUN chmod +x ./scripts/higgsfield-auth-probe.sh \
  && mkdir -p /app/data /app/higgsfield

ENV HIGGSFIELD_CREDENTIALS_PATH=/app/higgsfield/credentials.json

EXPOSE 3000

# Start both API and Worker. wait -n ensures container exits if either process crashes.
CMD ["bash", "-c", "node dist/index.js & node dist/worker/worker-main.js & wait -n"]
