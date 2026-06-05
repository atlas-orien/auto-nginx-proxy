#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
Usage:
  ./reload.sh

Checks nginx config and reloads nginx.
EOF
  exit 0
fi

echo "==> Checking nginx config..."
sudo nginx -t

echo ""
echo "==> Reloading nginx..."
sudo systemctl reload nginx

echo ""
echo "==> Done"
