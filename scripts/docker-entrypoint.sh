#!/bin/sh
set -eu

# Optional Chrome pre-launch for container platforms (e.g. Render) where
# the browser tool needs Chrome available immediately on startup.
#
# Enable:  OPENCLAW_PRELAUNCH_CHROME=1
# Tune:    OPENCLAW_BROWSER_CDP_PORT (default 10011)
#
# When enabled, the gateway's browser config should point at the pre-launched
# instance:
#   { "browser": { "cdpUrl": "http://127.0.0.1:10011", "headless": true } }

if [ "${OPENCLAW_PRELAUNCH_CHROME:-0}" = "1" ]; then
  CDP_PORT="${OPENCLAW_BROWSER_CDP_PORT:-10011}"
  USER_DATA_DIR="${HOME:-.}/.openclaw/browser/openclaw/user-data"
  mkdir -p "$USER_DATA_DIR"

  google-chrome-stable \
    --headless=new \
    --no-sandbox \
    --disable-gpu \
    --disable-dev-shm-usage \
    --disable-background-networking \
    --disable-breakpad \
    --disable-crash-reporter \
    --disable-features=TranslateUI \
    --metrics-recording-only \
    --no-first-run \
    --no-default-browser-check \
    --remote-debugging-port="$CDP_PORT" \
    --user-data-dir="$USER_DATA_DIR" \
    about:blank &

  # Wait for CDP to become ready (up to ~6 s).
  i=0
  while [ "$i" -lt 30 ]; do
    if curl -sS --max-time 1 "http://127.0.0.1:${CDP_PORT}/json/version" >/dev/null 2>&1; then
      break
    fi
    sleep 0.2
    i=$((i + 1))
  done
fi

# Hand off to the original CMD (e.g. node dist/index.js gateway …).
exec "$@"
