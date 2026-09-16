#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="${1:-$SCRIPT_DIR/config/proxies.conf}"
MAIN_TEMPLATE="${2:-$PROJECT_ROOT/templates/nginx.conf}"
NGINX_CONF="${3:-/etc/nginx/nginx.conf}"
CERTBOT_VENV="/opt/auto-nginx-proxy-certbot"
CERTBOT_BIN="$CERTBOT_VENV/bin/certbot"
TENCENTCLOUD_CREDENTIALS="/etc/letsencrypt/tencentcloud.ini"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
Usage:
  ./providers/tencentcloud/install.sh [config-file] [main-nginx-template] [nginx-conf-path]

Before first use:
  cp providers/tencentcloud/config/proxies.conf.example providers/tencentcloud/config/proxies.conf
  # Edit providers/tencentcloud/config/proxies.conf with the domain, mappings, and CAM API key.
EOF
  exit 0
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "error: config file not found: $CONFIG_FILE" >&2
  echo "hint: copy $SCRIPT_DIR/config/proxies.conf.example to $SCRIPT_DIR/config/proxies.conf" >&2
  exit 1
fi

if [[ ! -f "$MAIN_TEMPLATE" ]]; then
  echo "error: main nginx template not found: $MAIN_TEMPLATE" >&2
  exit 1
fi

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

read_config_value() {
  local key="$1"
  local config_key line value

  while IFS= read -r line; do
    line="${line%%#*}"
    line="$(trim "$line")"

    if [[ "$line" == *=* ]]; then
      config_key="$(trim "${line%%=*}")"
      [[ "$config_key" == "$key" ]] || continue
      value="${line#*=}"
      trim "$value"
      return
    fi
  done < "$CONFIG_FILE"
}

DOMAIN="$(read_config_value domain)"
EMAIL="$(read_config_value email)"
TENCENTCLOUD_SECRET_ID="$(read_config_value tencentcloud_secret_id)"
TENCENTCLOUD_SECRET_KEY="$(read_config_value tencentcloud_secret_key)"

require_config_value() {
  local name="$1"
  local value="$2"
  if [[ -z "$value" || "$value" == "replace-me" ]]; then
    echo "error: missing config: $name" >&2
    exit 1
  fi
}

require_config_value "domain = example.com" "$DOMAIN"
require_config_value "email = admin@example.com" "$EMAIL"
require_config_value "tencentcloud_secret_id = your-secret-id" "$TENCENTCLOUD_SECRET_ID"
require_config_value "tencentcloud_secret_key = your-secret-key" "$TENCENTCLOUD_SECRET_KEY"

install_nginx() {
  if command -v nginx >/dev/null 2>&1; then
    echo "==> nginx already installed"
    return
  fi

  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y nginx
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y nginx
  elif command -v yum >/dev/null 2>&1; then
    sudo yum install -y nginx
  else
    echo "error: unsupported package manager. Install nginx manually first." >&2
    exit 1
  fi
}

install_certbot() {
  if [[ -x "$CERTBOT_BIN" ]]; then
    echo "==> Tencent Cloud Certbot environment already installed"
    return
  fi

  echo "==> Installing an isolated Certbot environment..."
  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y python3 python3-venv
  elif command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y python3
  elif command -v yum >/dev/null 2>&1; then
    sudo yum install -y python3
  else
    echo "error: unsupported package manager. Install Python 3 with venv support manually." >&2
    exit 1
  fi

  sudo python3 -m venv "$CERTBOT_VENV"
  sudo "$CERTBOT_VENV/bin/pip" install --upgrade pip
  sudo "$CERTBOT_VENV/bin/pip" install certbot certbot-dns-tencentcloud
  sudo "$CERTBOT_BIN" plugins | grep -q 'dns-tencentcloud' || {
    echo "error: dns-tencentcloud Certbot plugin was not installed" >&2
    exit 1
  }
}

write_tencentcloud_credentials() {
  echo "==> Writing Tencent Cloud credentials..."
  sudo install -d -m 0700 /etc/letsencrypt
  sudo tee "$TENCENTCLOUD_CREDENTIALS" >/dev/null <<EOF
dns_tencentcloud_secret_id = $TENCENTCLOUD_SECRET_ID
dns_tencentcloud_secret_key = $TENCENTCLOUD_SECRET_KEY
EOF
  sudo chmod 0600 "$TENCENTCLOUD_CREDENTIALS"
}

request_certificate() {
  echo "==> Requesting Let's Encrypt certificate..."
  sudo "$CERTBOT_BIN" certonly \
    --authenticator dns-tencentcloud \
    --dns-tencentcloud-credentials "$TENCENTCLOUD_CREDENTIALS" \
    --dns-tencentcloud-propagation-seconds 120 \
    --cert-name "$DOMAIN" \
    --non-interactive \
    --agree-tos \
    --email "$EMAIL" \
    -d "$DOMAIN" \
    -d "*.$DOMAIN"
}

install_renewal() {
  echo "==> Installing certificate renewal timer..."
  sudo install -d -m 0755 /etc/letsencrypt/renewal-hooks/deploy
  sudo tee /etc/letsencrypt/renewal-hooks/deploy/reload-nginx >/dev/null <<'EOF'
#!/bin/sh
nginx -t && systemctl reload nginx
EOF
  sudo chmod 0755 /etc/letsencrypt/renewal-hooks/deploy/reload-nginx

  sudo tee /etc/systemd/system/auto-nginx-proxy-certbot-renew.service >/dev/null <<EOF
[Unit]
Description=Renew Let's Encrypt certificates for auto-nginx-proxy

[Service]
Type=oneshot
ExecStart=$CERTBOT_BIN renew --cert-name $DOMAIN --quiet
EOF
  sudo tee /etc/systemd/system/auto-nginx-proxy-certbot-renew.timer >/dev/null <<'EOF'
[Unit]
Description=Daily renewal check for auto-nginx-proxy certificates

[Timer]
OnCalendar=daily
RandomizedDelaySec=1h
Persistent=true

[Install]
WantedBy=timers.target
EOF
  sudo systemctl daemon-reload
  sudo systemctl enable --now auto-nginx-proxy-certbot-renew.timer
}

replace_main_config() {
  echo "==> Replacing nginx main config..."
  if [[ -f "$NGINX_CONF" ]]; then
    backup_file="${NGINX_CONF}.bak.$(date +%Y%m%d%H%M%S)"
    sudo cp "$NGINX_CONF" "$backup_file"
    echo "backup: $backup_file"
  fi
  sudo install -m 0644 "$MAIN_TEMPLATE" "$NGINX_CONF"
}

install_nginx
install_certbot
write_tencentcloud_credentials
request_certificate
install_renewal
sudo systemctl enable nginx
replace_main_config
sudo nginx -t
sudo systemctl start nginx

echo "==> Done"
echo "next: $PROJECT_ROOT/generate.sh $CONFIG_FILE && $PROJECT_ROOT/sync.sh && $PROJECT_ROOT/reload.sh"
