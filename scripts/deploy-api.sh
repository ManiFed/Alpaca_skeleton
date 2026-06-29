#!/usr/bin/env bash
set -euo pipefail

# Deploy the cloud API service to Railway from the repo root.
# Requires: railway login (or RAILWAY_TOKEN project token in env).

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v railway >/dev/null 2>&1; then
  echo "Installing Railway CLI..."
  bash <(curl -fsSL https://railway.com/install.sh)
  export PATH="$HOME/.railway/bin:$PATH"
fi

if ! railway whoami >/dev/null 2>&1; then
  echo "Not logged in. Run: railway login"
  exit 1
fi

if ! railway status >/dev/null 2>&1; then
  echo "Link this directory to the api service:"
  echo "  railway link"
  echo "Select the TTN project → production → api"
  exit 1
fi

echo "Deploying api service from $ROOT ..."
railway up --service api --detach --ci -y
echo "Done. Watch: railway logs --service api"