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

has_whiptail() { command -v whiptail >/dev/null 2>&1; }

ask_menu() {
  local title="$1"; shift
  local prompt="$1"; shift
  local choices=("$@")
  if has_whiptail; then
    local args=()
    for c in "${choices[@]}"; do args+=("$c" "$c"); done
    whiptail --title "$title" --menu "$prompt" 20 70 10 "${args[@]}" 3>&1 1>&2 2>&3
  else
    printf "%s\n" "$prompt"
    select sel in "${choices[@]}"; do echo "$sel"; break; done
  fi
}

ask_input() {
  local title="$1"; shift
  local prompt="$1"; shift
  local default_val="${1:-}"; shift || true
  if has_whiptail; then
    local out
    out=$(whiptail --title "$title" --inputbox "$prompt" 10 70 "$default_val" 3>&1 1>&2 2>&3) || true
    printf "%s" "$out"
  else
    if [[ -n "$default_val" ]]; then
      read -r -p "$prompt [$default_val]: " ans; printf "%s" "${ans:-$default_val}"
    else
      read -r -p "$prompt: " ans; printf "%s" "$ans"
    fi
  fi
}

ask_secret() {
  local title="$1"; shift
  local prompt="$1"; shift
  if has_whiptail; then
    local out
    out=$(whiptail --title "$title" --passwordbox "$prompt" 10 70 3>&1 1>&2 2>&3) || true
    printf "%s" "$out"
  else
    read -r -s -p "$prompt: " ans; echo; printf "%s" "$ans"
  fi
}

confirm_yes() {
  local prompt="$1"; shift
  if has_whiptail; then
    whiptail --yesno "$prompt" 8 60; return $?
  else
    read -r -p "$prompt [y/N]: " ans; [[ "$ans" =~ ^[Yy]$ ]]
  fi
}

print_cmd() { echo "[CMD] $*"; }
