#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="${1:-config/proxies.conf}"
TEMPLATE_FILE="${2:-templates/nginx.conf.tpl}"
OUTPUT_DIR="${3:-dist}"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
Usage:
  ./generate.sh [config-file] [template-file] [output-dir]

Examples:
  ./generate.sh
  ./generate.sh config/proxies.conf templates/nginx.conf.tpl dist

Config format:
  domain = example.com

  taskmate -> 192.0.2.10:29202
  abc -> 127.0.0.1:8080

Template variables:
  {{DOMAIN}}
  {{UPSTREAM}}
  {{CERT_DOMAIN}}
EOF
  exit 0
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "error: config file not found: $CONFIG_FILE" >&2
  exit 1
fi

if [[ ! -f "$TEMPLATE_FILE" ]]; then
  echo "error: template file not found: $TEMPLATE_FILE" >&2
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

awk -v template_file="$TEMPLATE_FILE" -v output_dir="$OUTPUT_DIR" '
function trim(value) {
  gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
  return value
}

function die(message) {
  print "error: " message > "/dev/stderr"
  exit 1
}

function require_domain(value, name) {
  if (value == "") {
    die(name " cannot be empty")
  }

  if (value !~ /\./) {
    die(name " should contain at least one dot: " value)
  }
}

function require_subdomain(value) {
  if (value == "") {
    die("subdomain cannot be empty")
  }

  if (value ~ /\./) {
    die("mapping should only use the subdomain prefix, for example: taskmate -> 1.2.3.4:8080")
  }

  if (value !~ /^[A-Za-z0-9_-]+$/) {
    die("subdomain can only contain letters, numbers, underscore, or hyphen: " value)
  }
}

function require_upstream(value) {
  if (value == "") {
    die("upstream cannot be empty")
  }

  if (value !~ /:[0-9]+$/) {
    die("upstream should look like ip:port: " value)
  }
}

function render(output_file, domain, upstream, base_domain, i, line) {
  for (i = 1; i <= template_count; i++) {
    line = template[i]
    gsub(/\{\{DOMAIN\}\}/, domain, line)
    gsub(/\{\{UPSTREAM\}\}/, upstream, line)
    gsub(/\{\{CERT_DOMAIN\}\}/, base_domain, line)
    print line > output_file
  }

  print "" > output_file
  close(output_file)
}

BEGIN {
  while ((getline template_line < template_file) > 0) {
    template[++template_count] = template_line
    template_text = template_text template_line "\n"
  }

  close(template_file)

  if (template_count == 0) {
    die("template file is empty")
  }

  if (template_text !~ /\{\{DOMAIN\}\}/) {
    die("template is missing required variable {{DOMAIN}}")
  }

  if (template_text !~ /\{\{UPSTREAM\}\}/) {
    die("template is missing required variable {{UPSTREAM}}")
  }

  if (template_text !~ /\{\{CERT_DOMAIN\}\}/) {
    die("template is missing required variable {{CERT_DOMAIN}}")
  }
}

{
  raw = $0
  sub(/#.*/, "", raw)
  line = trim(raw)

  if (line == "") {
    next
  }

  if (line ~ /^[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=/) {
    key = trim(line)
    sub(/[[:space:]]*=.*/, "", key)

    value = line
    sub(/^[^=]*=/, "", value)
    value = trim(value)

    if (key == "domain") {
      require_domain(value, "domain")
      base_domain = value
      next
    }

    die("unknown config key: " key)
  }

  split(line, parts, /[[:space:]]*->[[:space:]]*/)

  if (length(parts) != 2) {
    die("expected mapping format: subdomain -> ip:port")
  }

  subdomain = trim(parts[1])
  upstream = trim(parts[2])

  require_subdomain(subdomain)
  require_upstream(upstream)

  mapping_count++
  subdomains[mapping_count] = subdomain
  upstreams[mapping_count] = upstream
}

END {
  if (base_domain == "") {
    die("missing required config: domain = your-domain.com")
  }

  if (mapping_count == 0) {
    die("no proxy mappings found")
  }

  for (i = 1; i <= mapping_count; i++) {
    output_file = output_dir "/" subdomains[i]
    render(output_file, subdomains[i] "." base_domain, upstreams[i], base_domain)
    print "generated " output_file > "/dev/stderr"
  }
}
' "$CONFIG_FILE"
