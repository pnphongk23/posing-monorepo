#!/bin/bash
set -e

PORT=8089
DIR="$(pwd)/docs/prototype"
LOG="/tmp/cloudflared_tunnel.log"
rm -f "$LOG"

# Clean up any leftover processes on port
lsof -ti :$PORT | xargs kill -9 2>/dev/null || true

# Start static file server
python3 -m http.server $PORT --directory "$DIR" > /tmp/prototype_server.log 2>&1 &
SERVER_PID=$!

# Start cloudflared tunnel
cloudflared tunnel --url http://127.0.0.1:$PORT > "$LOG" 2>&1 &
TUNNEL_PID=$!

# Wait for tunnel URL
URL=""
for i in {1..25}; do
  sleep 0.5
  URL=$(grep -o 'https://[a-zA-Z0-9.-]*\.trycloudflare\.com' "$LOG" | head -n 1 || true)
  if [ -n "$URL" ]; then
    break
  fi
done

if [ -z "$URL" ]; then
  echo "Failed to obtain tunnel URL from Cloudflare."
  cat "$LOG"
  exit 1
fi

echo "SUCCESS"
echo "TUNNEL_URL=$URL"
echo "ONBOARDING_URL=$URL/screens/onboarding.html"
echo "SERVER_PID=$SERVER_PID"
echo "TUNNEL_PID=$TUNNEL_PID"
