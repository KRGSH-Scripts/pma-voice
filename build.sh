#!/usr/bin/env bash

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT/voice-ui"

if [[ -f package-lock.json ]]; then
	npm ci
else
	npm install
fi

npm run build

echo "Built voice-ui → $ROOT/ui (index.html, css/, js/)"
