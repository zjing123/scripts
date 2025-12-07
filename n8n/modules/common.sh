#!/usr/bin/env bash
set -euo pipefail

print_info() { echo "[INFO] $*"; }
print_warn() { echo "[WARN] $*" >&2; }
print_error() { echo "[ERROR] $*" >&2; }

ensure_dir() { mkdir -p "$1"; }

detect_timezone() {
  local input="${1:-}"
  if [[ -n "$input" ]]; then echo "$input"; return; fi
  if [[ -f /etc/timezone ]]; then cat /etc/timezone; return; fi
  timedatectl 2>/dev/null | awk -F': ' '/Time zone/ {print $2}' | awk '{print $1}'
}

render_template() {
  local tpl="$1" out="$2"; shift 2
  local content; content="$(cat "$tpl")"
  while [[ $# -gt 0 ]]; do
    local key="$1" val="$2"; shift 2
    content="$(printf "%s" "$content" | sed "s|\${$key}|$val|g")"
  done
  printf "%s\n" "$content" > "$out"
}

service_health_check() {
  local port="$1"
  print_info "检查端口 ${port} 的服务可达性"
  sleep 2
  if command -v curl >/dev/null 2>&1; then
    curl -s "http://127.0.0.1:${port}" >/dev/null || print_warn "HTTP 检查失败，稍后重试或手动验证"
  fi
}
