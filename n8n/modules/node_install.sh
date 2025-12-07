#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

node_install() {
  local root="$1" port="$2" dry="$3" auto_node="$4" n8n_ver="$5" env_content="$6"
  local need_node=false
  if ! command -v node >/dev/null 2>&1; then need_node=true; else
    local v; v="$(node -v | sed 's/^v//')"
    local major="${v%%.*}" minor="${v#*.}"; minor="${minor%%.*}"
    if [[ "$major" -lt 20 ]] || [[ "$major" -gt 24 ]] || ([[ "$major" -eq 20 ]] && [[ "$minor" -lt 19 ]]); then need_node=true; fi
  fi
  if $need_node; then
    if [[ "$auto_node" == "true" ]]; then
      print_info "安装符合版本的 Node.js"
      if ! $dry; then
        curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
        sudo apt-get install -y nodejs
      fi
    else
      print_error "Node.js 版本不符合或未安装，请使用 --auto-install-node 或手动安装"
      exit 1
    fi
  fi
  if command -v corepack >/dev/null 2>&1; then
    if ! $dry; then corepack enable || true; fi
    if ! command -v pnpm >/dev/null 2>&1; then
      print_info "安装 pnpm"
      if ! $dry; then corepack prepare pnpm@latest --activate; fi
    fi
  else
    if ! command -v pnpm >/dev/null 2>&1; then
      print_info "安装 pnpm（无 corepack，使用官方安装脚本）"
      if ! $dry; then
        curl -fsSL https://get.pnpm.io/install.sh | sh -
        export PNPM_HOME="$HOME/.local/share/pnpm"
        export PATH="$PNPM_HOME:$PATH"
      fi
    fi
  fi
  print_info "使用 pnpm 全局安装 n8n@${n8n_ver}"
  if ! $dry; then pnpm add -g "n8n@${n8n_ver}"; fi
  local n8n_bin
  n8n_bin="$(command -v n8n || echo /usr/bin/n8n)"
  ensure_dir "$root/n8n"
  if ! $dry; then
    printf "%s\n" "$env_content" > "$HOME/.n8n/.env"
    chmod 600 "$HOME/.n8n/.env"
  fi
  local svc_tpl="$root/templates/n8n.service.tpl"
  local svc_out="/etc/systemd/system/n8n.service"
  if ! $dry; then
    local user_name user_home
    user_name="$(id -un)"
    user_home="$(getent passwd "$user_name" | cut -d: -f6)"
    local svc_content
    svc_content="$(sed "s|\${N8N_EXEC}|$n8n_bin|g; s|\${USER_NAME}|$user_name|g; s|\${USER_HOME}|$user_home|g" "$svc_tpl")"
    printf "%s" "$svc_content" | sudo tee /tmp/n8n.service >/dev/null
    sudo mv /tmp/n8n.service "$svc_out"
    sudo systemctl daemon-reload
    sudo systemctl enable --now n8n
  fi
  print_info "验证服务"
  if ! $dry; then sleep 3; systemctl status n8n --no-pager || true; fi
}
