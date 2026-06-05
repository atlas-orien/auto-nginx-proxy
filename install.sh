#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${1:-config/proxies.conf}"
MAIN_TEMPLATE="${2:-templates/nginx.conf}"
NGINX_CONF="${3:-/etc/nginx/nginx.conf}"
CLOUDFLARE_CREDENTIALS="/etc/letsencrypt/cloudflare.ini"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
Usage:
  ./install.sh [config-file] [main-nginx-template] [nginx-conf-path]

Examples:
  ./install.sh
  ./install.sh config/proxies.conf templates/nginx.conf /etc/nginx/nginx.conf
EOF
  exit 0
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "error: config file not found: $CONFIG_FILE" >&2
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
      if [[ "$config_key" != "$key" ]]; then
        continue
      fi

      value="${line#*=}"
      trim "$value"
      return
    fi
  done < "$CONFIG_FILE"
}

DOMAIN="$(read_config_value domain)"
EMAIL="$(read_config_value email)"
CLOUDFLARE_API_TOKEN="$(read_config_value cloudflare_api_token)"

if [[ -z "$DOMAIN" ]]; then
  echo "error: missing config: domain = example.com" >&2
  exit 1
fi

if [[ -z "$EMAIL" ]]; then
  echo "error: missing config: email = admin@example.com" >&2
  exit 1
fi

if [[ -z "$CLOUDFLARE_API_TOKEN" || "$CLOUDFLARE_API_TOKEN" == "replace-me" ]]; then
  echo "error: missing config: cloudflare_api_token = your-token" >&2
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

install_certbot() {
  if command -v certbot >/dev/null 2>&1; then
    echo "==> certbot already installed"
  else
    echo "==> Installing certbot..."
  fi

  if command -v apt-get >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y certbot python3-certbot-nginx python3-certbot-dns-cloudflare
    return
  fi

  if command -v dnf >/dev/null 2>&1; then
    sudo dnf install -y certbot python3-certbot-nginx python3-certbot-dns-cloudflare
    return
  fi

  if command -v yum >/dev/null 2>&1; then
    sudo yum install -y certbot python3-certbot-nginx python3-certbot-dns-cloudflare
    return
  fi

  echo "error: unsupported package manager. Install certbot manually first." >&2
  exit 1
}

write_cloudflare_credentials() {
  echo "==> Writing Cloudflare credentials..."

  sudo mkdir -p "$(dirname "$CLOUDFLARE_CREDENTIALS")"
  sudo tee "$CLOUDFLARE_CREDENTIALS" >/dev/null <<EOF
dns_cloudflare_api_token = $CLOUDFLARE_API_TOKEN
EOF
  sudo chmod 0600 "$CLOUDFLARE_CREDENTIALS"
  echo "installed: $CLOUDFLARE_CREDENTIALS"
}

request_certificate() {
  echo "==> Requesting Let’s Encrypt certificate..."

  sudo certbot certonly \
    --dns-cloudflare \
    --dns-cloudflare-credentials "$CLOUDFLARE_CREDENTIALS" \
    --non-interactive \
    --agree-tos \
    --email "$EMAIL" \
    -d "$DOMAIN" \
    -d "*.$DOMAIN"
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
install_certbot
write_cloudflare_credentials
request_certificate
enable_nginx
replace_main_config
start_nginx

echo ""
echo "==> Done"
echo "next: ./generate.sh && ./sync.sh && ./reload.sh"
