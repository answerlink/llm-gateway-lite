#!/bin/sh
set -e

GATEWAY_URL=${GATEWAY_URL:-http://localhost:8080}
MODEL=${MODEL:-gpt-3.5-turbo}

curl -sS "$GATEWAY_URL/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -d '{"model":"'"$MODEL"'","messages":[{"role":"user","content":"ping"}]}'
