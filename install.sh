#!/usr/bin/env bash
set -euo pipefail

MAIN_TEMPLATE="${1:-templates/nginx.conf}"
NGINX_CONF="${2:-/etc/nginx/nginx.conf}"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
Usage:
  ./install.sh [main-nginx-template] [nginx-conf-path]

Examples:
  ./install.sh
  ./install.sh templates/nginx.conf /etc/nginx/nginx.conf
EOF
  exit 0
fi

if [[ ! -f "$MAIN_TEMPLATE" ]]; then
  echo "error: main nginx template not found: $MAIN_TEMPLATE" >&2
  exit 1
fi

install_nginx() {
  if command -v nginx >/dev/null 2>&1; then
    echo "==> nginx already installed"
    return
  fi

  echo "==> Installing nginx..."

  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y nginx
    return
  fi

  if command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y nginx
    return
  fi

  if command -v yum >/dev/null 2>&1; then
    sudo yum install -y nginx
    return
  fi

  echo "error: unsupported package manager. Install nginx manually first." >&2
  exit 1
}

enable_nginx() {
  echo "==> Enabling nginx on boot..."

  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl enable nginx
    return
  fi

  echo "error: systemctl not found. Enable nginx manually." >&2
  exit 1
}

start_nginx() {
  echo "==> Checking nginx config..."
  sudo nginx -t

  echo ""
  echo "==> Starting nginx..."

  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl start nginx
    return
  fi

  echo "error: systemctl not found. Start nginx manually." >&2
  exit 1
}

replace_main_config() {
  echo "==> Replacing nginx main config..."

  sudo mkdir -p "$(dirname "$NGINX_CONF")"

  if [[ -f "$NGINX_CONF" ]]; then
    backup_file="${NGINX_CONF}.bak.$(date +%Y%m%d%H%M%S)"
    sudo cp "$NGINX_CONF" "$backup_file"
    echo "backup: $backup_file"
  fi

  sudo install -m 0644 "$MAIN_TEMPLATE" "$NGINX_CONF"
  echo "installed: $NGINX_CONF"
}

install_nginx
enable_nginx
replace_main_config
start_nginx

echo ""
echo "==> Done"
echo "next: ./generate.sh && ./sync.sh && ./reload.sh"
