#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="${1:-dist}"
TARGET_DIR="${2:-/etc/nginx/sites-enabled}"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
Usage:
  ./sync.sh [source-dir] [target-dir]

Examples:
  ./sync.sh
  ./sync.sh dist /etc/nginx/sites-enabled
EOF
  exit 0
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "error: source directory not found: $SOURCE_DIR" >&2
  echo "hint: run ./generate.sh first" >&2
  exit 1
fi

shopt -s nullglob
files=("$SOURCE_DIR"/*)
shopt -u nullglob

if [[ ${#files[@]} -eq 0 ]]; then
  echo "error: no generated files found in: $SOURCE_DIR" >&2
  echo "hint: run ./generate.sh first" >&2
  exit 1
fi

target_parent="$(dirname "$TARGET_DIR")"

if [[ -d "$TARGET_DIR" && -w "$TARGET_DIR" ]] || [[ ! -e "$TARGET_DIR" && -w "$target_parent" ]]; then
  install_cmd=(install)
  mkdir -p "$TARGET_DIR"
else
  install_cmd=(sudo install)
  sudo mkdir -p "$TARGET_DIR"
fi

synced_count=0

for file in "${files[@]}"; do
  if [[ ! -f "$file" ]]; then
    continue
  fi

  "${install_cmd[@]}" -m 0644 "$file" "$TARGET_DIR/$(basename "$file")"
  echo "synced $TARGET_DIR/$(basename "$file")"
  synced_count=$((synced_count + 1))
done

if [[ $synced_count -eq 0 ]]; then
  echo "error: no regular files found in: $SOURCE_DIR" >&2
  exit 1
fi

echo "synced $synced_count file(s)"
echo "next: sudo nginx -t && sudo systemctl reload nginx"
